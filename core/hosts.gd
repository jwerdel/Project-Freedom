extends RefCounted
# Hosts and calling the banners (war-and-realm §2.1-2.5; game-design §12.3-12.4; data/hosts.json).
#  - Three forces: the standing army (recruited lords' armies), levies (from the regions' young men:
#    production drops while they serve, returns on disband), and vassal armies under their own lords.
#  - Call the Banners: pick a muster point. Levies form captain-led detachments (at most 6 units,
#    defend only, slow abroad, merging into a lord's army on contact) that set out after the muster
#    time; vassal contingents march to the muster point. Turnout and speed come from the ruler's
#    standing (Loved / Feared / Neutral) times each vassal's loyalty; Feared-but-weak gives large but
#    disloyal turnout (desertion). Mustering is visible to the world.
#  - A Host groups armies under one commanding lord: they move together and fight as one battle (the
#    battle code's reinforcements take every Host army near the fight). No cohesion decay, ever.
# State: state.musters[faction] = {point, called, ready, pending: [{settlement, units}], contingents};
#  state.hosts[leader army id] = {faction, members: [army ids]}; a detachment's army has captain: true
#  and its levy units carry levy_from; settlements carry levied (units serving).

const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const Reputation = preload("res://core/reputation.gd")
const DATA = "res://data/hosts.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func _m(state) -> Dictionary:
 if state.get("musters") == null: state.musters = {}
 return state.musters

static func _h(state) -> Dictionary:
 if state.get("hosts") == null: state.hosts = {}
 return state.hosts

# The standing's muster terms: {turns, turnout, loyalty, key, label}.
static func terms(state,f: String) -> Dictionary:
 var st = Reputation.standing(state,f)
 var k = st.kind
 if k == "feared" and not st.powerful: k = "feared_weak"
 var t = data().standing[k].duplicate()
 var T = load("res://core/titles.gd")
 t.turnout = float(t.turnout)*T.power(state,f,"banner_turnout",1.0)
 t.key = k
 t.label = st.label
 return t

static func levy_unit(f: String) -> String:
 var R = load("res://core/rosters.gd")
 return R.levy_of(str(WorldMap.faction(f).get("culture","")))

# How many levy units each settlement gives at this turnout: {sid: n}.
static func levy_plan(state,f: String,turnout: float) -> Dictionary:
 var l = data().levy
 var out = {}
 for sid in state.settlements_of(f):
  var s = state.settlements[sid]
  if float(s.population)<float(l.min_population): continue
  var free = int(l.max_per_settlement)-int(s.get("levied",0))
  var n = mini(free,int(floor(float(s.population)/1000.0*float(l.per_thousand)*turnout)))
  if n>0: out[sid] = n
 return out

static func mustering(state,f: String) -> bool:
 return _m(state).has(f)

# Call the banners to a muster point (one of the faction's settlements). Returns {ok, reason, ...}.
static func call_banners(state,f: String,point: String) -> Dictionary:
 if mustering(state,f): return {"ok":false,"reason":"The banners are already called"}
 if str(state.settlements.get(point,{}).get("owner","")) != f: return {"ok":false,"reason":"Muster in your own lands"}
 var t = terms(state,f)
 var plan = levy_plan(state,f,float(t.turnout))
 var pending = []
 var units = 0
 for sid in plan:
  pending.append({"settlement":sid,"units":int(plan[sid])})
  units += int(plan[sid])
 var V = load("res://core/vassals.gd")
 var Ai = load("res://core/ai.gd")
 var contingents = []
 for v in V.vassals_of(state,f):
  var chance = V.reliability(state,v)*clampf(float(t.turnout),0.0,1.0)
  if V.randf_for(state,v,["banners",point])>=chance: continue
  var best = ""
  for id in Ai.field_armies(state,v):
   if best == "" or Ai.army_power(state,id)>Ai.army_power(state,best): best = id
  if best == "": continue
  Movement.order(state,best,WorldMap.settlement_position(point))
  contingents.append(best)
 _m(state)[f] = {"point":point,"called":int(state.turn),"ready":int(state.turn)+int(t.turns),"pending":pending,"contingents":contingents,"loyalty":str(t.loyalty)}
 # Visible to the world (war-and-realm §2.2): neighbours learn of it.
 var seen = _noticed_by(state,f,point)
 var D = load("res://core/diplomacy.gd")
 D._log(state,"%s calls its banners to %s." % [WorldMap.faction(f).name,WorldMap.region(point).settlement.name])
 if t.turns<=0: _raise_levies(state,f)
 return {"ok":true,"levies":units,"contingents":contingents.size(),"turns":int(t.turns),"standing":t.label,"turnout":float(t.turnout),"noticed":seen}

static func _noticed_by(state,f: String,point: String) -> Array:
 var at = WorldMap.settlement_position(point)
 var out = []
 for sid in WorldMap.settlements_near(at,float(data().notice_metres)):
  var o = str(state.settlements[sid].owner)
  if o != f and o != "" and not o in out: out.append(o)
 return out

# The factions that have noticed f mustering (AI wariness, core/ai.gd).
static func musters_near(state,observer: String) -> Array:
 var out = []
 for f in _m(state):
  if f != observer and observer in _noticed_by(state,f,str(state.musters[f].point)): out.append(f)
 return out

# Levies set out: one captain-led detachment per settlement, marching to the muster point.
static func _raise_levies(state,f: String):
 var m = _m(state)[f]
 var unit = levy_unit(f)
 var UnitTypes = load("res://core/unit_types.gd")
 var size = int(UnitTypes.get_type(unit).size)
 for p in m.pending:
  var sid = str(p.settlement)
  if str(state.settlements[sid].owner) != f: continue
  var n = mini(int(p.units),int(data().detachment.max_units))
  var id = new_detachment(state,f,sid,[])
  for i in n: state.army_state[id].units.append({"unit":unit,"men":size,"max_men":size,"rank":0,"levy_from":sid})
  state.settlements[sid].levied = int(state.settlements[sid].get("levied",0))+n
  if sid != m.point: Movement.order(state,id,WorldMap.settlement_position(m.point),not Movement.holds_orders(state,f))
 m.pending = []

# A captain-led detachment at a settlement (no general; game-design §12.3).
static func new_detachment(state,f: String,sid: String,units: Array) -> String:
 var n = 1
 while state.army_state.has("%s_levy_%d" % [f,n]): n += 1
 var id = "%s_levy_%d" % [f,n]
 var pos = WorldMap.settlement_position(sid)
 var a = {"id":id,"display_name":"Levies of %s" % WorldMap.region(sid).settlement.name,"faction":f,
  "commander":{"unit":"commander","name":"Captain of %s" % WorldMap.region(sid).settlement.name,"rank":1,"captain":true},
  "units":units,"queue":[],"captain":true}
 a.merge(Movement.new_army_state(f,pos))
 a.garrison = sid
 state.army_state[id] = a
 state.armies.append(id)
 return id

static func is_captain(state,id: String) -> bool:
 return bool(state.army_state.get(id,{}).get("captain",false))

# Disband levies: every levy unit of the faction (or of one army) goes home; production returns.
static func dismiss_levies(state,f: String,army_id := "") -> int:
 var n = 0
 for id in state.army_state.keys():
  var a = state.army_state[id]
  if a.faction != f or (army_id != "" and id != army_id): continue
  var keep = []
  for u in a.units:
   if u.has("levy_from"):
    var sid = str(u.levy_from)
    if state.settlements.has(sid): state.settlements[sid].levied = maxi(0,int(state.settlements[sid].get("levied",0))-1)
    n += 1
   else: keep.append(u)
  a.units = keep
  if bool(a.get("captain",false)) and a.units.is_empty(): _remove_army(state,id)
 _m(state).erase(f)
 return n

static func _remove_army(state,id: String):
 state.army_state.erase(id)
 state.armies.erase(id)
 for k in _h(state).keys():
  if k == id: state.hosts.erase(k)
  else: state.hosts[k].members.erase(id)

# Income lost to levies serving from a settlement (Economy reads it).
static func production_factor(s: Dictionary) -> float:
 var l = data().levy
 return 1.0-minf(float(l.max_drop),float(s.get("levied",0))*float(l.production_drop))

# --- Hosts ---------------------------------------------------------------------------------------

static func host_of(state,army_id: String) -> String:
 for k in _h(state):
  if k == army_id or army_id in state.hosts[k].members: return k
 return ""

# Form (or extend) a Host under a commanding lord's army.
static func form_host(state,leader: String,members: Array) -> Dictionary:
 var a = state.army_state.get(leader)
 if a == null or bool(a.get("captain",false)): return {"ok":false,"reason":"A Host needs a lord to command it"}
 var h = _h(state).get_or_add(leader,{"faction":a.faction,"members":[]})
 for id in members:
  if id == leader or not state.army_state.has(id) or state.army_state[id].faction != a.faction: continue
  var old = host_of(state,id)
  if old != "" and old != leader: state.hosts[old].members.erase(id)
  if not id in h.members: h.members.append(id)
 return {"ok":true,"members":h.members.size()}

static func leave_host(state,id: String):
 for k in _h(state).keys():
  if k == id:
   state.hosts.erase(k)
   return
  state.hosts[k].members.erase(id)

# Host armies follow their leader (after the leader moves, and at End Turn).
static func follow(state,end_turn := false):
 for k in _h(state).keys():
  if not state.army_state.has(k):
   state.hosts.erase(k)
   continue
  # At End Turn the player's Host waits for the player like any order (Movement.holds_orders).
  if end_turn and Movement.holds_orders(state,str(state.army_state[k].faction)): continue
  var lead = Movement.position(state,k)
  for id in state.hosts[k].members.duplicate():
   if not state.army_state.has(id):
    state.hosts[k].members.erase(id)
    continue
   var me = Movement.position(state,id)
   if me.distance_to(lead)<=8.0: continue
   var off = (me-lead).normalized()*6.0 if me.distance_to(lead)>0.01 else Vector2(6,0)
   Movement.order(state,id,lead+off)

# Detachments merge into a lord's army of their faction on contact.
static func merge_detachments(state) -> Array:
 var out = []
 var r = float(data().detachment.merge_radius)
 var Armies = load("res://core/armies.gd")
 for id in state.army_state.keys():
  if not state.army_state.has(id): continue
  var a = state.army_state[id]
  if not bool(a.get("captain",false)): continue
  var at = Movement.position(state,id)
  for o in state.army_state.keys():
   var b = state.army_state[o]
   if o == id or b.faction != a.faction or bool(b.get("captain",false)): continue
   if Movement.position(state,o).distance_to(at)>r: continue
   var room = Armies.max_units()-b.units.size()
   if room<=0: continue
   var moving = a.units.slice(0,room)
   b.units.append_array(moving)
   a.units = a.units.slice(room)
   out.append({"from":id,"into":o,"units":moving.size()})
   if a.units.is_empty():
    _remove_army(state,id)
    break
 return out

# Yearly: levies set out when their muster time is up, desertion under a feared-but-weak ruler,
# detachments merge, Hosts follow their leaders; a muster ends once its levies have set out and its
# contingents reached the point.
static func end_turn(state) -> Array:
 var out = []
 for f in _m(state).keys():
  var m = state.musters[f]
  if not m.pending.is_empty() and int(state.turn)>=int(m.ready):
   _raise_levies(state,f)
   out.append({"faction":f,"kind":"levies","text":"The levies of %s set out for %s." % [WorldMap.faction(f).name,WorldMap.region(m.point).settlement.name]})
  if str(m.loyalty) == "low":
   for id in state.army_state.keys():
    var a = state.army_state[id]
    if a.faction != f: continue
    var keep = []
    for i in a.units.size():
     var u = a.units[i]
     var r = RandomNumberGenerator.new()
     r.seed = hash([state.seed,state.turn,id,i,"desert"])
     if u.has("levy_from") and r.randf()<float(data().desertion):
      var sid = str(u.levy_from)
      if state.settlements.has(sid): state.settlements[sid].levied = maxi(0,int(state.settlements[sid].get("levied",0))-1)
      continue
     keep.append(u)
    a.units = keep
 out.append_array(merge_detachments(state).map(func(x): return {"faction":state.army_state[x.into].faction if state.army_state.has(x.into) else "","kind":"merged","text":"Levies joined the army."}))
 follow(state,true)
 return out

# Movement allowance factor for an army at a position (war-and-realm §2.6).
static func move_factor(state,army_id: String) -> float:
 var a = state.army_state[army_id]
 var rg = WorldMap.region_at(Vector2(a.position[0],a.position[1]))
 var owner = str(state.settlements.get(rg,{}).get("owner",""))
 var D = load("res://core/diplomacy.gd")
 if owner == "" or D.friendly_land(state,a.faction,owner): return 1.0
 return float(data().detachment.foreign_factor) if bool(a.get("captain",false)) else float(data().foreign_factor.lord)

# Zone of control radius of an army (large armies block passage).
static func zoc_radius(state,army_id: String,base: float) -> float:
 var a = state.army_state[army_id]
 if str(a.get("garrison","")) != "": return base
 var z = data().zoc
 return minf(float(z.max_radius),base+float(z.per_unit)*maxf(0.0,float(a.get("units",[]).size()-int(z.from_units))))
