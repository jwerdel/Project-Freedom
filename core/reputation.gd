extends RefCounted
# Reputation (game-design §7.1-7.4; docs/diplomacy-design.md §3.1; war-and-realm §2.2). Every faction
# has a ruler reputation (fast, weighs more) and a House reputation (slow memory) on the axes of
# data/reputation.json, each -100..100. Deeds move them (x3 in a new ruler's first-impressions
# window); neighbours weigh the ruler, distant factions the House. From them come the labels shown
# with their deeds and the Loved / Feared / Neutral standing that drives banner turnout (hosts).
# State: state.reputation[faction] = {ruler: {axis: v}, house: {axis: v}, deeds: [{turn, deed, text,
# changes}], ruler_since: turn}. Decrees and suspicion attach later (hooks: deed()).

const WorldMap = preload("res://core/world_map.gd")
const DATA = "res://data/reputation.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func axes() -> Array:
 return data().axes.map(func(a): return a.id)

static func _zero() -> Dictionary:
 var z = {}
 for a in axes(): z[a] = 0.0
 return z

# Campaign start: every House seeded from its faction's tendencies; the ruler starts where the House is.
static func init(state):
 state.reputation = {}
 for f in state.factions():
  var house = _zero()
  for t in WorldMap.faction(f).get("traits",[]):
   var s = data().seed.get(t,{})
   for a in s: house[a] = clampf(float(house[a])+float(s[a]),-100.0,100.0)
  state.reputation[f] = {"ruler":house.duplicate(),"house":house,"deeds":[],"ruler_since":-1000}

static func entry(state,f: String) -> Dictionary:
 if not state.reputation.has(f): state.reputation[f] = {"ruler":_zero(),"house":_zero(),"deeds":[],"ruler_since":-1000}
 return state.reputation[f]

static func in_first_impressions(state,f: String) -> bool:
 return int(state.turn)-int(entry(state,f).ruler_since)<int(data().first_impressions)

# A deed (data/reputation.json "deeds", or a dictionary of axis changes) moves both reputations.
static func deed(state,f: String,kind,text := "",scale := 1.0):
 if f == "" or not state.treasury.has(f): return
 var changes: Dictionary = data().deeds.get(kind,{}) if kind is String else kind
 if changes.is_empty(): return
 var e = entry(state,f)
 var fast = float(data().first_impressions_factor) if in_first_impressions(state,f) else 1.0
 var applied = {}
 for a in changes:
  var v = float(changes[a])*scale
  e.ruler[a] = clampf(float(e.ruler[a])+v*fast,-100.0,100.0)
  e.house[a] = clampf(float(e.house[a])+v*float(data().house_rate)*fast,-100.0,100.0)
  applied[a] = v*fast
 e.deeds.append({"turn":int(state.turn),"deed":str(kind) if kind is String else "custom","text":text,"changes":applied})
 while e.deeds.size()>int(data().deed_log): e.deeds.pop_front()

# A new ruler takes power: the ruler's reputation starts from the House's, and the world watches.
static func new_ruler(state,f: String):
 var e = entry(state,f)
 e.ruler = e.house.duplicate()
 e.ruler_since = int(state.turn)

# Ruler weight by distance between capitals: near_weight for neighbours down to far_weight.
static func ruler_weight(state,observer: String,f: String) -> float:
 var d = data()
 var a = _seat(state,observer)
 var b = _seat(state,f)
 if a == Vector2.INF or b == Vector2.INF: return float(d.far_weight)
 var t = clampf((a.distance_to(b)-float(d.near_metres))/maxf(1.0,float(d.far_metres)-float(d.near_metres)),0.0,1.0)
 return lerpf(float(d.near_weight),float(d.far_weight),t)

static func _seat(state,f: String) -> Vector2:
 var own = state.settlements_of(f)
 if own.is_empty(): return Vector2.INF
 var seat = str(WorldMap.faction(f).get("seat_region",""))
 return WorldMap.settlement_position(seat if seat in own else own[0])

# How `observer` sees `f` (observer "" = the world at large: an even blend).
static func perceived(state,observer: String,f: String) -> Dictionary:
 var e = entry(state,f)
 var w = 0.6 if observer == "" else ruler_weight(state,observer,f)
 var out = {}
 for a in axes(): out[a] = w*float(e.ruler[a])+(1.0-w)*float(e.house[a])
 return out

# Labels past +-label_at: [{axis, name, value, deeds: [text]}], strongest first.
static func labels(state,observer: String,f: String) -> Array:
 var p = perceived(state,observer,f)
 var out = []
 for a in data().axes:
  var v = float(p[a.id])
  if absf(v)<float(data().label_at): continue
  var deeds = []
  for d in entry(state,f).deeds:
   if d.changes.has(a.id) and signf(float(d.changes[a.id])) == signf(v) and str(d.text) != "": deeds.append(d.text)
  out.append({"axis":a.id,"name":a.plus if v>0.0 else a.minus,"value":v,"deeds":deeds.slice(maxi(0,deeds.size()-4))})
 out.sort_custom(func(x,y): return absf(x.value)>absf(y.value))
 return out

# Love and fear (0..100) as the world sees the ruler.
static func love_fear(state,f: String) -> Dictionary:
 var p = perceived(state,"",f)
 var love = 0.0
 for a in data().kind_axes: love += maxf(0.0,float(p[a]))
 love /= maxf(1.0,data().kind_axes.size())
 var fear = 0.0
 var harsh = data().harsh_axes
 for a in harsh: fear += maxf(0.0,float(p[a])*float(harsh[a]))
 fear /= maxf(1.0,harsh.size())
 return {"love":love,"fear":fear}

# A faction's strength for standing and vassal caps: its regions and its armies' power.
static func strength(state,f: String) -> float:
 var Ai = load("res://core/ai.gd")
 var s = state.settlements_of(f).size()*10.0
 for id in state.armies_of(f): s += Ai.army_power(state,id)
 return s

static func powerful(state,f: String) -> bool:
 var mine = strength(state,f)
 var all = []
 for g in state.factions():
  if not state.settlements_of(g).is_empty(): all.append(strength(state,g))
 all.sort()
 all.reverse()
 if all.is_empty(): return false
 var rank = all.find(mine)
 return mine>=float(all[0])*float(data().powerful_share) or (rank>=0 and rank<int(data().powerful_rank))

# War-and-realm §2.2: "loved", "feared" (with powerful true or false) or "neutral".
static func standing(state,f: String) -> Dictionary:
 var lf = love_fear(state,f)
 var at = float(data().standing_at)
 var kind = "neutral"
 if lf.love>=at and lf.love>=lf.fear: kind = "loved"
 elif lf.fear>=at: kind = "feared"
 var pw = powerful(state,f)
 var label = {"loved":"Loved","feared":"Feared" if pw else "Feared but weak","neutral":"Neutral"}[kind]
 return {"kind":kind,"powerful":pw,"label":label,"love":lf.love,"fear":lf.fear}
