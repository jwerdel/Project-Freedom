extends RefCounted
# The player's deployment (docs/battle-design.md section 2): units on a lanes x front/back grid, a
# reserve, the general's lane, and one order per unit. Pure functions on a deployment dictionary:
#   {lanes, terrain [lane][band], role (0 attacker, 1 defender), general_lane,
#    units: [{unit, men, max_men, rank, index, army, lane, line: front|back|reserve, order, protect}]}
# Lane capacity per line comes from data/battle.json (a pass holds one unit per line; impassable
# lanes hold none). The deployment becomes the side's units in the battle setup unchanged.

const BattleDeploy = preload("res://core/battle_deploy.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const ORDERS = ["hold","aggressive","flank","protect","reserve"]

static func create(units: Array,terrain: Array,role: int,template := "line") -> Dictionary:
 var dep = {"lanes":terrain.size(),"terrain":terrain,"role":role,"general_lane":terrain.size()/2,"units":[]}
 apply_template(dep,units,template)
 return dep

# Replace the layout with a template's (the player can then adjust it). Unit order is kept.
static func apply_template(dep: Dictionary,units: Array,template: String):
 var placed = BattleDeploy.deploy(units,template,dep.terrain,dep.role)
 var by_key = {}
 for p in placed: by_key[_key(p)] = p
 dep.units = []
 for u in units:
  var p = by_key[_key(u)].duplicate()
  if not p.has("protect"): p.protect = -1
  dep.units.append(p)
 dep.template = template

static func _key(u: Dictionary) -> String:
 return "%s:%d:%s" % [u.get("army",""),int(u.get("index",-1)),u.unit]

# Band of a line for this side (0-based, from the attacker's edge).
static func band(dep: Dictionary,line: String) -> int:
 if dep.role == 0: return 1 if line == "front" else 0
 return 4 if line == "front" else 5

static func capacity(dep: Dictionary,lane: int,line: String) -> int:
 return BattleDeploy.capacity(dep.terrain,dep.lanes,lane,band(dep,line))

static func occupants(dep: Dictionary,lane: int,line: String,except := -1) -> Array:
 var out = []
 for i in dep.units.size():
  var u = dep.units[i]
  if i != except and u.line == line and int(u.lane) == lane: out.append(i)
 return out

# Can unit i stand in this slot? {ok, reason} with a message the player can act on.
static func can_place(dep: Dictionary,i: int,lane: int,line: String) -> Dictionary:
 if line == "reserve": return {"ok":true,"reason":""}
 if lane<0 or lane>=dep.lanes: return {"ok":false,"reason":"No such lane"}
 var cap = capacity(dep,lane,line)
 var ter = dep.terrain[lane][band(dep,line)]
 if cap<=0: return {"ok":false,"reason":"%s lane is impassable here" % lane_name(dep.lanes,lane)}
 if occupants(dep,lane,line,i).size()>=cap:
  if ter == "pass": return {"ok":false,"reason":"The pass holds only %d unit per line" % cap}
  return {"ok":false,"reason":"%s %s line is full (%d units%s)" % [lane_name(dep.lanes,lane),line,cap," in %s" % ter if ter in ["forest","hills"] else ""]}
 return {"ok":true,"reason":""}

# Move unit i into a slot. Reserve line means order Reserve; leaving the reserve means Hold.
static func place(dep: Dictionary,i: int,lane: int,line: String) -> Dictionary:
 var check = can_place(dep,i,lane,line)
 if not check.ok: return check
 var u = dep.units[i]
 u.line = line
 u.lane = lane if line != "reserve" else dep.lanes/2
 if line == "reserve": u.order = "reserve"
 elif u.order == "reserve": u.order = "hold"
 if u.order == "flank" and not (u.lane == 0 or u.lane == dep.lanes-1): u.order = "hold"
 return check

# Give unit i an order. Flank takes a side ("left"/"right") and moves the unit to that outer lane's
# front line; Protect takes the index of the unit to protect; Reserve moves it to the reserve.
static func set_order(dep: Dictionary,i: int,order: String,arg = null) -> Dictionary:
 if not order in ORDERS: return {"ok":false,"reason":"Unknown order"}
 var u = dep.units[i]
 match order:
  "reserve": return place(dep,i,0,"reserve")
  "flank":
   var lane = 0 if arg == "left" else dep.lanes-1
   if not (int(u.lane) == lane and u.line != "reserve"):
    var r = place(dep,i,lane,"front")
    if not r.ok: return {"ok":false,"reason":"Cannot flank %s: %s" % [arg,r.reason]}
   u.order = "flank"
   u.protect = -1
  "protect":
   var t = int(arg) if arg != null else -1
   if t<0 or t>=dep.units.size() or t == i: return {"ok":false,"reason":"Pick another of your units to protect"}
   if dep.units[t].line == "reserve": return {"ok":false,"reason":"Units in reserve need no protection"}
   if u.line == "reserve": place(dep,i,int(dep.units[t].lane),"back" if dep.units[t].line == "front" else "front")
   u.order = "protect"
   u.protect = t
  _:
   if u.line == "reserve":
    var placed = false
    for lane in BattleDeploy.lane_order(dep.lanes):
     for line in ["front","back"]:
      if not placed and can_place(dep,i,lane,line).ok:
       place(dep,i,lane,line)
       placed = true
    if not placed: return {"ok":false,"reason":"No free slot on the field"}
   u.order = order
   u.protect = -1
 # Units protecting this one keep working only while it is on the field.
 for o in dep.units:
  if o.order == "protect" and int(o.protect) == i and u.line == "reserve":
   o.order = "hold"
   o.protect = -1
 return {"ok":true,"reason":""}

static func set_general_lane(dep: Dictionary,lane: int) -> Dictionary:
 if lane<0 or lane>=dep.lanes: return {"ok":false,"reason":"No such lane"}
 if dep.terrain[lane][band(dep,"back")] == "closed": return {"ok":false,"reason":"%s lane is impassable" % lane_name(dep.lanes,lane)}
 dep.general_lane = lane
 return {"ok":true,"reason":""}

# Every placement legal? (Templates and loads are checked against the same rules.)
static func validate(dep: Dictionary) -> Array:
 var problems = []
 for lane in dep.lanes:
  for line in ["front","back"]:
   var n = occupants(dep,lane,line).size()
   if n>capacity(dep,lane,line): problems.append("%s %s line: %d units, room for %d" % [lane_name(dep.lanes,lane),line,n,capacity(dep,lane,line)])
 for u in dep.units:
  if u.order == "flank" and not (int(u.lane) == 0 or int(u.lane) == dep.lanes-1): problems.append("%s flanks from an inner lane" % u.unit)
  if u.order == "reserve" and u.line != "reserve": problems.append("%s has order Reserve outside the reserve" % u.unit)
 return problems

# The side's units as the battle setup takes them (protect targets are indices into this list).
static func setup_units(dep: Dictionary) -> Array:
 var out = []
 for u in dep.units: out.append(u.duplicate())
 return out

static func lane_name(lanes: int,lane: int) -> String:
 if lanes == 5: return ["Far left","Left","Center","Right","Far right"][lane]
 if lanes == 3: return ["Left","Center","Right"][lane]
 return "Lane %d" % (lane+1)

# Can the other side see this unit before battle? Reserve, forest and (in fog) the back line hide it.
static func hidden(u: Dictionary,terrain: Array,role: int,weather: String) -> bool:
 if u.line == "reserve": return true
 var b = (1 if u.line == "front" else 0) if role == 0 else (4 if u.line == "front" else 5)
 if terrain[int(u.lane)][b] == "forest": return true
 if weather == "fog" and u.line == "back" and bool(BattleSim.data().weather.fog_hides_back_line): return true
 return false
