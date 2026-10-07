extends RefCounted
# Realm Standing (game-design §11.6; war-and-realm §2.5): a faction's level from its territory,
# population and wealth. Each level raises the cap on lord armies (enforced by core/armies.gd) and
# stores the agent and decree caps for the systems that come later. No growth penalties.
# Numbers: data/realm_standing.json (placeholders).

const Economy = preload("res://core/economy.gd")
const DATA = "res://data/realm_standing.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func score(state,f: String) -> float:
 var d = data()
 var regions = state.settlements_of(f).size()
 var gross = float(Economy.faction_ledger(state,f).income_total)
 return regions*float(d.per_region)+state.population_of(f)/1000.0*float(d.per_thousand_people)+gross*float(d.per_gold)

# Level 1.. (the highest threshold reached).
static func level(state,f: String) -> int:
 var s = score(state,f)
 var t = data().thresholds
 var lv = 1
 for i in t.size():
  if s>=float(t[i]): lv = i+1
 return lv

static func cap(state,f: String,kind: String) -> int:
 var c = data().caps[kind]
 return int(c[clampi(level(state,f)-1,0,c.size()-1)])

# Everything the Realm Standing panel shows: level, name, score, the next threshold and the caps.
static func summary(state,f: String) -> Dictionary:
 var d = data()
 var lv = level(state,f)
 var t = d.thresholds
 var caps = {}
 for k in d.caps: caps[k] = cap(state,f,k)
 var nxt = float(t[lv]) if lv<t.size() else -1.0
 var cur = float(t[lv-1])
 var s = score(state,f)
 return {"level":lv,"name":str(d.names[clampi(lv-1,0,d.names.size()-1)]),"score":s,"next":nxt,
  "progress":(clampf((s-cur)/(nxt-cur),0.0,1.0) if nxt>0.0 else 1.0),"caps":caps,
  "regions":state.settlements_of(f).size(),"population":state.population_of(f),"income":int(Economy.faction_ledger(state,f).income_total)}
