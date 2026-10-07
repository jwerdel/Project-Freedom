extends RefCounted
# Titles (war-and-realm §5; docs/v1-content.md §3.1; data/titles.json): per race and region,
# collectible and dynamic. Earned by a powerful faction that is Loved or Feared plus each title's
# conditions; lost by conquest (a key region taken) to whoever meets them; grantable titles can be
# given by their holder to a vassal (who then holds it) or a family member (who carries it; the
# powers stay with the realm) as a loyalty reward. Senate votes and Holy Wars are pending systems.
# State: state.titles[id] = {faction, character, since}.

const WorldMap = preload("res://core/world_map.gd")
const Reputation = preload("res://core/reputation.gd")
const DATA = "res://data/titles.json"

static var _data = null
# Faction strengths cached while end_turn checks every title (one strength per faction, not per title).
static var _strength = null

static func _str(state,f: String) -> float:
 if _strength == null: return Reputation.strength(state,f)
 if not _strength.has(f): _strength[f] = Reputation.strength(state,f)
 return _strength[f]

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func _t(state) -> Dictionary:
 if state.get("titles") == null: state.titles = {}
 return state.titles

static func holder(state,id: String) -> String:
 return str(_t(state).get(id,{}).get("faction",""))

static func held_by(state,f: String) -> Array:
 var out = []
 for id in _t(state):
  if str(state.titles[id].faction) == f: out.append(id)
 out.sort()
 return out

# The realm of a region (its original owner's realm, factions.json "realm").
static func region_realm(sid: String) -> String:
 return str(WorldMap.faction(str(WorldMap.region(sid).get("owner",""))).get("realm",""))

# Each condition of a title for faction f: [{text, met}].
static func conditions(state,id: String,f: String) -> Array:
 var t = data().titles[id]
 var out = []
 var cul = str(WorldMap.faction(f).get("culture",""))
 if t.has("cultures"): out.append({"text":"A %s realm" % " or ".join(t.cultures.map(func(c): return str(c).capitalize())),"met":cul in t.cultures})
 if bool(t.get("standing",false)):
  var st = Reputation.standing(state,f)
  out.append({"text":"Loved or Feared (now %s)" % st.label,"met":st.kind != "neutral"})
 if bool(t.get("most_powerful",false)):
  var mine = _str(state,f)
  var top = true
  for g in state.factions():
   if g != f and str(WorldMap.faction(g).get("culture","")) in t.get("cultures",[]) and _str(state,g)>mine: top = false
  out.append({"text":"The most powerful of its people","met":top})
 var own = state.settlements_of(f)
 for sid in t.get("regions",[]):
  if state.settlements.has(sid): out.append({"text":"Hold %s" % WorldMap.region(sid).settlement.name,"met":sid in own})
 for realm in t.get("realm_regions",{}):
  var n = own.filter(func(s): return region_realm(s) == realm).size()
  out.append({"text":"Hold %d regions of %s (%d)" % [int(t.realm_regions[realm]),realm,n],"met":n>=int(t.realm_regions[realm])})
 if t.has("regions_total"): out.append({"text":"Hold %d regions (%d)" % [int(t.regions_total),own.size()],"met":own.size()>=int(t.regions_total)})
 var V = load("res://core/vassals.gd")
 if t.has("vassals"): out.append({"text":"%d vassals (%d)" % [int(t.vassals),V.vassals_of(state,f).size()],"met":V.vassals_of(state,f).size()>=int(t.vassals)})
 if t.has("league"):
  var n = own.filter(func(s): return str(WorldMap.faction(str(WorldMap.region(s).get("owner",""))).get("culture","")) == "greek").size()
  for v in V.vassals_of(state,f): n += state.settlements_of(v).size()
  out.append({"text":"Lead a league of %d cities (%d)" % [int(t.league),n],"met":n>=int(t.league)})
 if t.has("pending"): out.append({"text":str(t.pending),"met":false})
 return out

static func can_earn(state,id: String,f: String) -> bool:
 var t = data().titles[id]
 if bool(t.get("grant_only",false)): return false
 # Cheap checks first (culture, key regions) before the standing and power comparisons.
 if t.has("cultures") and not str(WorldMap.faction(f).get("culture","")) in t.cultures: return false
 var own = state.settlements_of(f)
 for sid in t.get("regions",[]):
  if state.settlements.has(sid) and not sid in own: return false
 var c = conditions(state,id,f)
 return not c.is_empty() and c.all(func(x): return x.met)

# The key regions a holder must keep (conquest moves a title).
static func _keeps(state,id: String,f: String) -> bool:
 var own = state.settlements_of(f)
 for sid in data().titles[id].get("regions",[]):
  if state.settlements.has(sid) and not sid in own: return false
 return not own.is_empty()

static func grant(state,id: String,by: String,to_faction := "",character := "") -> Dictionary:
 var t = data().titles.get(id)
 if t == null or not bool(t.get("grantable",false)): return {"ok":false,"reason":"Cannot be granted"}
 if holder(state,id) != by: return {"ok":false,"reason":"Not yours to grant"}
 var V = load("res://core/vassals.gd")
 var C = load("res://core/court.gd")
 if to_faction != "":
  if V.liege_of(state,to_faction) != by: return {"ok":false,"reason":"Only to your vassals"}
  state.titles[id] = {"faction":to_faction,"character":C.ruler(state,to_faction),"since":int(state.turn),"granted_by":by}
  V.change(state,to_faction,int(V.data().gains.title),"Granted the title %s" % t.name)
  return {"ok":true}
 var c = C.get_char(state,character)
 if c.is_empty() or c.faction != by: return {"ok":false,"reason":"Not in your court"}
 state.titles[id].character = character
 C.favour(state,character,"title","Granted the title %s" % t.name)
 C.history(state,c,"Granted the title %s." % t.name)
 return {"ok":true}

# Yearly: titles change hands by conquest; vacant titles go to a faction that meets them. Returns
# events [{title, faction, kind}].
static func end_turn(state) -> Array:
 var out = []
 _strength = {}
 for id in data().titles:
  var h = holder(state,id)
  if h != "" and not _keeps(state,id,h):
   _t(state).erase(id)
   out.append({"title":id,"faction":h,"kind":"lost"})
   h = ""
  if h != "": continue
  var best = ""
  for f in state.factions():
   if state.settlements_of(f).is_empty() or bool(WorldMap.faction(f).get("untouchable",false)): continue
   if can_earn(state,id,f) and (best == "" or _str(state,f)>_str(state,best)): best = f
  if best != "":
   var C = load("res://core/court.gd")
   _t(state)[id] = {"faction":best,"character":C.ruler(state,best),"since":int(state.turn)}
   out.append({"title":id,"faction":best,"kind":"earned"})
 _strength = null
 return out

# A faction's total power value from its titles.
static func power(state,f: String,key: String,neutral := 0.0) -> float:
 var v = neutral
 for id in held_by(state,f):
  var p = data().titles[id].powers
  if p.has(key):
   if neutral == 1.0: v *= float(p[key])
   else: v += float(p[key])
 return v

static func toll_income(state,f: String) -> int:
 return int(power(state,f,"toll_income"))

# The Titles panel: every title with its holder, conditions for f and powers.
static func panel(state,f: String) -> Array:
 var out = []
 for id in data().titles:
  var t = data().titles[id]
  var e = _t(state).get(id,{})
  out.append({"id":id,"name":t.name,"people":t.get("people",""),"holder":str(e.get("faction","")),"character":str(e.get("character","")),
   "conditions":conditions(state,id,f),"powers":t.get("power_text",[]),"grantable":bool(t.get("grantable",false)),"pending":str(t.get("pending",""))})
 return out
