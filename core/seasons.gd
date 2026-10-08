extends RefCounted
# Seasons (war-and-realm §9; owner spec 2026-10-07, Part B; data/seasons.json): long irregular
# summers (3-9 turns) and short winters (1-2, a rare long winter of 3), generated once per campaign
# from its seed and saved (GameState.seasons). Each winter is forecast 2-4 turns ahead by the culture's
# seers. Effects: summer food bonus; winter food loss by latitude (the north worst, the south barely),
# a dry season instead of snow in desert and jungle lands, faster supply drain in enemy land, slower
# movement in the north and on high ground, and the map turning white (map shader, snow_amount).
# State: GameState.seasons = {schedule: [{kind, start, length, forecast}], announced: [start turns]}.

const MapRegistry = preload("res://core/map_registry.gd")
const WorldMap = preload("res://core/world_map.gd")
const DATA = "res://data/seasons.json"
static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func reset():
 _data = null

# The campaign's seasons from its seed: summer first, then alternating.
static func generate(seed: int) -> Dictionary:
 var d = data()
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([seed,"seasons"])
 var out = []
 var t = 0
 var summer = true
 while t<int(d.schedule_turns):
  var length = 0
  if summer: length = rng.randi_range(int(d.summer[0]),int(d.summer[1]))
  else: length = int(d.long_winter) if rng.randf()<float(d.long_winter_chance) else rng.randi_range(int(d.winter[0]),int(d.winter[1]))
  var e = {"kind":"summer" if summer else "winter","start":t,"length":length}
  if not summer: e.forecast = rng.randi_range(int(d.forecast[0]),int(d.forecast[1]))
  out.append(e)
  t += length
  summer = not summer
 return {"schedule":out,"announced":[]}

static func init(state):
 state.seasons = generate(int(state.seed))

static func _s(state) -> Dictionary:
 if state.get("seasons") == null or state.seasons.is_empty(): init(state)
 return state.seasons

# The season at a turn: {kind, start, length, turns_left (after this one), index, long}.
static func at(state,turn := -1) -> Dictionary:
 var t = int(state.turn) if turn<0 else turn
 var list = _s(state).schedule
 for i in list.size():
  var e = list[i]
  if t>=int(e.start) and t<int(e.start)+int(e.length):
   return {"kind":e.kind,"start":int(e.start),"length":int(e.length),"turns_left":int(e.start)+int(e.length)-t-1,"index":i,"long":e.kind == "winter" and int(e.length)>=int(data().long_winter)}
 return {"kind":"summer","start":t,"length":1,"turns_left":0,"index":-1,"long":false}

static func is_winter(state) -> bool:
 return at(state).kind == "winter"

# The next winter after the current turn: the schedule entry, or {}.
static func next_winter(state) -> Dictionary:
 var t = int(state.turn)
 for e in _s(state).schedule:
  if e.kind == "winter" and int(e.start)>t: return e
 return {}

# How deep into the winter the map is: 0 in summer, rising to 1 over snow_ramp turns.
static func snow_amount(state) -> float:
 var s = at(state)
 if s.kind != "winter": return 0.0
 return clampf(float(int(state.turn)-int(s.start)+1)/float(data().effects.snow_ramp),0.0,1.0)

# 0 at the map's north edge, 1 at its south edge.
static func latitude(z: float) -> float:
 var size = MapRegistry.meta().get("size",[1000,1000])
 var origin = MapRegistry.meta().get("origin",[0,0])
 return clampf((z-float(origin[1]))/maxf(1.0,float(size[1])),0.0,1.0)

# A region's climate name for the dry-season rule (map data "climate" when the region carries one).
static func dry_land(sid: String) -> bool:
 var c = str(WorldMap.region(sid).get("climate",""))
 return c in data().effects.dry_climates

# Food production multiplier for a settlement this turn.
static func food_factor(state,sid: String) -> float:
 var s = at(state)
 var e = data().effects
 if s.kind == "summer": return float(e.summer_food)
 if dry_land(sid): return float(e.dry_food)
 var lat = latitude(WorldMap.settlement_position(sid).y)
 var t = clampf(lat/maxf(0.01,float(e.north_band)),0.0,1.0)
 return lerpf(float(e.north_food),float(e.south_food),t)

# Supply drain multiplier in enemy land.
static func supply_factor(state) -> float:
 return float(data().effects.winter_supply) if is_winter(state) else 1.0

# Movement points an army refills this turn, as a share: snow in the north band and on high ground.
static func move_factor(state,at_pos: Vector2) -> float:
 if not is_winter(state): return 1.0
 var e = data().effects
 if latitude(at_pos.y)<float(e.north_band): return float(e.winter_move)
 var Movement = load("res://core/movement.gd")
 var c = Movement.cell_of(at_pos)
 var g = Movement.grid()
 if c.x>=0 and c.y>=0 and c.x<g.cols and c.y<g.rows:
  var n = g.names[g.terrain[c.y*g.cols+c.x]] if g.terrain[c.y*g.cols+c.x]<g.names.size() else ""
  if n in ["hills","pass","mountain"]: return float(e.winter_move)
 return 1.0

# Who forecasts the winter for a culture.
static func seers(culture: String) -> String:
 return str(data().seers.get(culture,"the seers"))

# End Turn (after the year advances): forecasts and season changes. Returns events
# [{kind: forecast|winter|summer, long, turns, text}] for the player and the chronicle.
static func end_turn(state) -> Array:
 var out = []
 var t = int(state.turn)
 var s = at(state)
 if s.start == t and s.index>0:
  if s.kind == "winter": out.append({"kind":"winter","long":s.long,"turns":s.length,"text":"Winter has come. %s" % ("A long winter: three years of snow and hunger lie ahead." if s.long else "The snows will last %d year%s." % [s.length,"" if s.length == 1 else "s"])})
  else: out.append({"kind":"summer","long":false,"turns":s.length,"text":"The thaw: summer returns to the land."})
 var nw = next_winter(state)
 if not nw.is_empty() and int(nw.start)-t == int(nw.forecast) and not int(nw.start) in _s(state).announced:
  _s(state).announced.append(int(nw.start))
  var long = int(nw.length)>=int(data().long_winter)
  out.append({"kind":"forecast","long":long,"turns":int(nw.forecast),"length":int(nw.length),"text":"Winter is coming in %d years%s." % [int(nw.forecast)," and it will be long" if long else ""]})
 return out
