extends RefCounted
# The chronicle: entries in the voice of the Grey Scribes (docs/archive/world-v1.md), kept in GameState so
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
 # Settlements and armies by faction in one pass (a loop per faction is slow with 150 factions).
 var owned = {}
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids: owned.get_or_add(state.settlements[id].owner,[]).append(id)
 var armed = {}
 for id in state.army_state: armed[state.army_state[id].faction] = true
 for f in state.factions():
  # A faction with no settlements and no armies is gone from the map: the scribes stop counting it.
  var mine = owned.get(f,[])
  if mine.is_empty() and not armed.has(f): continue
  if richest == "" or state.treasury[f]>state.treasury[richest]: richest = f
  var change = 0.0
  var pop = 0.0
  for id in mine:
   change += growth[id].delta
   pop += state.settlements[id].population
  lines.append(_fill(_pick(d.faction_line,rng),{
   "faction":WorldMap.faction(f).name,"treasury":_num(state.treasury[f]),"net":_signed(ledgers[f].net),
   "population":_num(int(round(pop))),"growth":_signed(int(round(change)))+" souls"}))
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

# --- War and battles (core/battles.gd) ---------------------------------------------------------
# Wording is chosen with a generator seeded by the year and the parties, like the yearly entries.

static func _rng(parts: Array) -> RandomNumberGenerator:
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(parts)
 return rng

static func war_entry(year: int,attacker: String,defender: String) -> Dictionary:
 var rng = _rng([year,attacker,defender,"war"])
 var vars = {"attacker":WorldMap.faction(attacker).name,"defender":WorldMap.faction(defender).name}
 var e = entry(year,"war",_fill(_pick(data().war_title,rng),vars),_fill(_pick(data().war_text,rng),vars),attacker)
 e.with = defender # the other side (the Event Messages sort your wars from the world's)
 return e

static func _place(pb: Dictionary) -> String:
 if pb.settlement != "": return WorldMap.region(pb.settlement).settlement.name
 var region = WorldMap.region_at(Vector2(pb.position[0],pb.position[1]))
 var r = WorldMap.region(region)
 return r.get("name","the open field")

# Battle, capture and generals' fates, for the Event Messages "war" category and the chronicle.
static func battle_entries(year: int,pb: Dictionary,result: Dictionary,after: Dictionary) -> Array:
 var d = data()
 var rng = _rng([year,pb.seed,"battle"])
 var winner = after.winner
 var loser = after.loser
 var losses = [0,0]
 for side in 2:
  for u in result.sides[side].units: losses[side] += int(u.losses)
 var wside = result.winner
 var vars = {"place":_place(pb),"winner":WorldMap.faction(winner).name,"loser":WorldMap.faction(loser).name,
  "winner_men":_num(losses[wside]),"loser_men":_num(losses[1-wside])}
 var out = [entry(year,"war",_fill(_pick(d.battle_title,rng),vars),_fill(_pick(d.battle_text,rng),vars),pb.attacker.faction)]
 out[0].with = pb.defender.faction
 if pb.settlement != "": out[0].settlement = pb.settlement
 if after.captured != "": out.append(capture_entry(year,after.captured,winner,false,loser))
 for g in after.generals:
  var key = "general_killed" if g.fate == "killed" else "general_wounded"
  out.append(entry(year,"war",g.name,_fill(_pick(d[key],rng),{"name":g.name,"faction":WorldMap.faction(g.faction).name}),g.faction))
 for p in after.promoted:
  out.append(entry(year,"war",p.name,_fill(_pick(d.captain_promoted,rng),{"name":p.name,"faction":WorldMap.faction(p.faction).name}),p.faction))
 return out

static func capture_entry(year: int,sid: String,faction: String,surrender: bool,from := "") -> Dictionary:
 var d = data()
 var rng = _rng([year,sid,faction,"capture"])
 var vars = {"place":WorldMap.region(sid).settlement.name,"faction":WorldMap.faction(faction).name}
 var text = _pick(d.surrender_text if surrender else d.capture_text,rng)
 var e = entry(year,"war",_fill(_pick(d.capture_title,rng),vars),_fill(text,vars),faction)
 e.settlement = sid
 if from != "": e.with = from
 return e

static func siege_entry(year: int,sid: String,faction: String) -> Dictionary:
 var d = data()
 var rng = _rng([year,sid,faction,"siege"])
 var vars = {"place":WorldMap.region(sid).settlement.name,"faction":WorldMap.faction(faction).name}
 var e = entry(year,"war",_fill(_pick(d.siege_title,rng),vars),_fill(_pick(d.siege_text,rng),vars),faction)
 e.settlement = sid
 return e

# A defender that drew back before battle (Battles.withdraw).
static func withdraw_entry(year: int,pb: Dictionary) -> Dictionary:
 var d = data()
 var rng = _rng([year,pb.seed,"withdraw"])
 var vars = {"place":_place(pb),"faction":WorldMap.faction(pb.defender.faction).name,"attacker":WorldMap.faction(pb.attacker.faction).name}
 return entry(year,"war",_fill(_pick(d.withdraw_title,rng),vars),_fill(_pick(d.withdraw_text,rng),vars),pb.defender.faction)

# A faction's fortunes (core/realm.gd): landless (grace starts), grace (turns left, the player's
# own), survived, destroyed, desertion (men lost, the player's own).
static func realm_entry(year: int,kind: String,faction: String,n := 0) -> Dictionary:
 var d = data().realm[kind]
 var rng = _rng([year,faction,kind])
 var vars = {"faction":WorldMap.faction(faction).name,"n":str(n),"turns":"%d turn%s" % [n,"" if n == 1 else "s"]}
 return entry(year,"war",_fill(_pick(d.title,rng),vars),_fill(_pick(d.text,rng),vars),faction)
