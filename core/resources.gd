extends RefCounted
# Resources (war-and-realm §7.1; owner spec 2026-10-07, Part B; data/resources.json): food, wood and
# stone are real stockpiles per faction (GameState.stock; gold stays the treasury).
#  - Production per settlement: its land (provinces.json endowments: food, wood, stone, and minerals
#    for stone) plus its buildings' "produces" (farms, fishing, pastures: food; lumber: wood; quarries
#    and mines: stone); food x the season (core/seasons.gd) and the land's climate yield (core/land.gd).
#  - Consumption: people and every army unit eat food.
#  - Deficit: food at zero stops growth; from the next turn settlements shrink and field armies bleed.
#  - Costs: buildings cost wood and stone by category, some units food or wood (data).
# Every number is a PLACEHOLDER.

const Buildings = preload("res://core/buildings.gd")
const WorldMap = preload("res://core/world_map.gd")
const DATA = "res://data/resources.json"
const KINDS = ["food","wood","stone"]
static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func reset():
 _data = null

# --- Stockpiles ----------------------------------------------------------------------------------

static func stock(state,f: String) -> Dictionary:
 if state.get("stock") == null: state.stock = {}
 if not state.stock.has(f): state.stock[f] = {"food":0,"wood":0,"stone":0,"starving":0}
 return state.stock[f]

static func amount(state,f: String,kind: String) -> int:
 return int(stock(state,f).get(kind,0))

static func add(state,f: String,kind: String,n: int):
 var s = stock(state,f)
 s[kind] = int(s.get(kind,0))+n

# The starting stockpiles: base plus per settlement; food also covers start_food_turns of eating.
static func init(state):
 state.stock = {}
 var st = data().start
 for f in state.factions():
  var n = state.settlements_of(f).size()
  var s = stock(state,f)
  for k in KINDS: s[k] = int(st.base[k])+int(st.per_settlement[k])*n
  s.food = maxi(int(s.food),int(ceil(consumption(state,f)*float(st.start_food_turns))))

# --- Production and consumption ---------------------------------------------------------------------

# What a settlement produces this turn: {food, wood, stone} (whole numbers).
static func production(state,sid: String) -> Dictionary:
 var s = state.settlements[sid]
 var land = data().land
 var e = s.get("resources",{})
 var out = {"food":float(e.get("food",0))*float(land.food)+float(s.population)/1000.0*float(land.get("subsistence",0.0)),"wood":float(e.get("wood",0))*float(land.wood),
  "stone":float(e.get("stone",0))*float(land.stone)+float(e.get("minerals",0))*float(land.minerals_stone)}
 for b in s.buildings:
  if not b.has("chain"): continue
  var p = Buildings.produces(b.chain,int(b.level))
  for k in p: out[k] = float(out.get(k,0.0))+float(p[k])
 var Seasons = load("res://core/seasons.gd")
 var Land = load("res://core/land.gd")
 out.food *= Seasons.food_factor(state,sid)*Land.climate_factor(state,sid)
 for k in out: out[k] = int(round(out[k]))
 return out

# Food a faction eats each turn: its people and every unit of its armies.
static func consumption(state,f: String) -> float:
 var c = data().consumption
 var pop = 0.0
 for sid in state.settlements_of(f): pop += float(state.settlements[sid].population)
 var units = 0
 for id in state.armies_of(f): units += state.army_state[id].units.size()
 return pop/1000.0*float(c.per_1000)+float(units)*float(c.per_unit)

# A faction's resource ledger this turn: {food, wood, stone: {income, expense, net, lines}}.
static func ledger(state,f: String) -> Dictionary:
 var out = {}
 for k in KINDS: out[k] = {"income":0,"expense":0,"net":0,"lines":[]}
 for sid in state.settlements_of(f):
  var p = production(state,sid)
  for k in KINDS:
   if int(p[k]) != 0:
    out[k].income += int(p[k])
    out[k].lines.append({"label":WorldMap.region(sid).settlement.name,"amount":int(p[k])})
 var pop = 0.0
 for sid in state.settlements_of(f): pop += float(state.settlements[sid].population)
 var eat_people = int(round(pop/1000.0*float(data().consumption.per_1000)))
 var units = 0
 for id in state.armies_of(f): units += state.army_state[id].units.size()
 var eat_armies = int(round(float(units)*float(data().consumption.per_unit)))
 out.food.expense = eat_people+eat_armies
 out.food.lines.append({"label":"Your people eat","amount":-eat_people})
 if eat_armies>0: out.food.lines.append({"label":"Your armies eat","amount":-eat_armies})
 for k in KINDS: out[k].net = int(out[k].income)-int(out[k].expense)
 return out

# Turns until food runs out at the current rate (-1: never).
static func food_turns_left(state,f: String) -> int:
 var net = int(ledger(state,f).food.net)
 if net>=0: return -1
 return int(floor(float(amount(state,f,"food"))/float(-net)))

static func starving(state,f: String) -> bool:
 return int(stock(state,f).get("starving",0))>0

# End Turn: every faction's production in, consumption out; food at zero: starving (growth stops the
# first turn; afterwards settlements shrink and field armies bleed). Returns events
# [{faction, kind: famine|famine_ends, text}].
static func end_turn(state) -> Array:
 var out = []
 var d = data().deficit
 for f in state.factions():
  if state.settlements_of(f).is_empty() and state.armies_of(f).is_empty(): continue
  var l = ledger(state,f)
  var s = stock(state,f)
  for k in KINDS: s[k] = int(s.get(k,0))+int(l[k].net)
  if int(s.food)<0:
   s.food = 0
   s.starving = int(s.get("starving",0))+1
   if int(s.starving) == 1: out.append({"faction":f,"kind":"famine","text":"The granaries are empty: your people go hungry and stop growing."})
   if int(s.starving)>=3:
    # The turn after the granaries empty, growth stops (turn loop); from the turn after that, people and armies starve.
    for sid in state.settlements_of(f): state.settlements[sid].population = maxf(0.0,float(state.settlements[sid].population)*(1.0-float(d.shrink)))
    for id in state.armies_of(f):
     var a = state.army_state[id]
     if str(a.get("garrison","")) != "": continue
     for u in a.units: u.men = maxi(1,int(round(int(u.men)*(1.0-float(d.attrition)))))
  elif int(s.get("starving",0))>0:
   s.starving = 0
   out.append({"faction":f,"kind":"famine_ends","text":"Food again in the granaries: the famine is over."})
 return out

# --- Costs -----------------------------------------------------------------------------------------

# Wood and stone for a building level (Buildings.material_cost).
static func building_cost(chain_id: String,level: int) -> Dictionary:
 return Buildings.material_cost(chain_id,level)

# Extra costs to recruit a unit, by its role (data unit_costs): {food, wood}.
static func unit_cost(unit_id: String) -> Dictionary:
 var role = str(load("res://core/unit_types.gd").get_type(unit_id).get("role",""))
 return data().unit_costs.get(role,{}).duplicate()

# What is missing to pay these costs: ["Not enough wood (120 needed)", ...].
static func shortfall(state,f: String,costs: Dictionary) -> Array:
 var out = []
 for k in costs:
  if k in KINDS and int(costs[k])>0 and amount(state,f,k)<int(costs[k]): out.append("Not enough %s (%d needed)" % [k,int(costs[k])])
 return out

static func pay(state,f: String,costs: Dictionary):
 for k in costs:
  if k in KINDS: add(state,f,k,-int(costs[k]))

static func refund(state,f: String,costs: Dictionary,share := 1.0):
 for k in costs:
  if k in KINDS: add(state,f,k,int(round(int(costs[k])*share)))
