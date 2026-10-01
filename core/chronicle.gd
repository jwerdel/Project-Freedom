extends RefCounted
# The chronicle: entries in the voice of the Grey Scribes (docs/world.md), kept in GameState so
# any later system can add to it. Wording comes from data/chronicle.json.

const WorldMap = preload("res://core/world_map.gd")
const DATA = "res://data/chronicle.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("faction_line"),"Invalid "+DATA)
 return _data

static func opening_entries() -> Array:
 return data().opening.duplicate(true)

static func entry(year: int,category: String,title: String,text := "",faction := "") -> Dictionary:
 var e = {"year":year,"category":category,"title":title,"text":text}
 if faction != "": e.faction = faction
 return e

# One "buildings" entry per construction completed this year (Construction.advance results).
static func building_entries(ended: int,completed: Array,rng: RandomNumberGenerator) -> Array:
 var d = data()
 var out = []
 for c in completed:
  var vars = {"building":c.name,"settlement":WorldMap.region(c.settlement).settlement.name,"faction":WorldMap.faction(c.faction).name}
  var text = _pick(d.upgrade_text if c.main else d.building_text,rng)
  out.append(entry(ended,"buildings",_fill(_pick(d.building_title,rng),vars),_fill(text,vars),c.faction))
 return out

# Entries for the year that just ended: the new year begins, and the Scribes' yearly account.
static func year_entries(state,ended: int,ledgers: Dictionary,growth: Dictionary,rng: RandomNumberGenerator) -> Array:
 var d = data()
 var lines = [_pick(d.summary_open,rng)]
 var richest = ""
 for f in state.factions():
  if richest == "" or state.treasury[f]>state.treasury[richest]: richest = f
  var change = 0.0
  for id in state.settlements_of(f): change += growth[id].delta
  lines.append(_fill(_pick(d.faction_line,rng),{
   "faction":WorldMap.faction(f).name,"treasury":_num(state.treasury[f]),"net":_signed(ledgers[f].net),
   "population":_num(state.population_of(f)),"growth":_signed(int(round(change)))+" souls"}))
 lines.append(_fill(_pick(d.richest_line,rng),{"faction":WorldMap.faction(richest).name}))
 var vars = {"year":str(ended),"ordinal":_ordinal(ended+1)}
 return [
  entry(ended,"turn",_fill(_pick(d.summary_title,rng),vars),"\n".join(lines)),
  entry(ended+1,"turn",_fill(_pick(d.year_begins,rng),{"year":str(ended+1),"ordinal":_ordinal(ended+1)})),
 ]

static func _pick(options: Array,rng: RandomNumberGenerator) -> String:
 return options[rng.randi_range(0,options.size()-1)]

static func _fill(text: String,vars: Dictionary) -> String:
 for k in vars: text = text.replace("{%s}" % k,str(vars[k]))
 return text

static func _num(n) -> String:
 var s = str(absi(int(n)))
 var out = ""
 while s.length()>3:
  out = ","+s.substr(s.length()-3)+out
  s = s.substr(0,s.length()-3)
 return ("-" if int(n)<0 else "")+s+out

static func _signed(n: int) -> String:
 return ("+" if n>=0 else "")+_num(n)

static func _ordinal(n: int) -> String:
 var suffix = "th"
 if n%100<11 or n%100>13: suffix = {1:"st",2:"nd",3:"rd"}.get(n%10,"th")
 return "%d%s" % [n,suffix]
