extends RefCounted
# Economy rules from constitution.md (Economy and settlements). Pure functions over GameState;
# every number comes from data/economy.json and data/buildings.json.
#  - Gold is the currency; income and expenses are calculated per turn.
#  - Settlement income = base by type and level + a per-capita tax on population (confirmed
#    2026-10-01), both raised by resource endowments and buildings, plus flat building income,
#    all times the type's economic factor and capped by its income ceiling. Cities are economic;
#    fortresses have a lower economic factor and a lower ceiling even when developed.
#  - Regional resource endowments raise economic potential (income) and growth; never spent.
#  - Expenses: army upkeep (unit placeholder upkeep) and building upkeep (per building level).
#  - Population grows from type, resource abundance, buildings and wealth toward a capacity set by
#    the main building's level plus housing; ruler popularity is a neutral stub.

const UnitTypes = preload("res://core/unit_types.gd")
const Buildings = preload("res://core/buildings.gd")
const Land = preload("res://core/land.gd")
const DATA = "res://data/economy.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("settlement_types") and _data.has("taxes"),"Invalid "+DATA)
 return _data

static func reset():
 _data = null
 Buildings.reset()

static func type_data(type: String) -> Dictionary:
 assert(data().settlement_types.has(type),"Unknown settlement type '%s'" % type)
 return data().settlement_types[type]

static func resource_income_bonus(resources: Dictionary) -> float:
 var bonus = 0.0
 for r in resources: bonus += float(resources[r])*float(data().resources[r].income_bonus)
 return bonus

# Income of one settlement this turn, with the parts that make it up.
static func settlement_income(state,id: String) -> Dictionary:
 var s = state.settlements[id]
 var t = type_data(s.type)
 var i = clampi(int(s.level),1,t.base_income.size())-1
 var e = Buildings.effects(state,id)
 var base = float(t.base_income[i])
 var tax = float(s.population)*float(data().taxes.tax_per_capita)*(1.0+e.tax_pct)
 var bonus = resource_income_bonus(s.resources)
 var factor = float(t.economic_factor)
 # Climate (game-design §10.9): land of another culture yields less until it converts (core/land.gd).
 var climate = Land.climate_factor(state,id) if state.get("land") != null else 1.0
 # Levies serving away from home (core/hosts.gd): the young men are gone, production drops.
 var levy = load("res://core/hosts.gd").production_factor(s) if int(s.get("levied",0))>0 else 1.0
 var raw = ((base+tax)*(1.0+bonus+e.income_pct)+e.income)*factor*climate*levy
 var ceiling = float(t.income_ceiling[i])
 return {"total":int(round(minf(raw,ceiling))),"base":base,"tax":tax,"buildings":e.income,"building_pct":e.income_pct,"economic_factor":factor,"climate":climate,"levy":levy,"resource_bonus":bonus,"ceiling":ceiling,"capped":raw>ceiling}

static func building_upkeep(state,id: String) -> int:
 return Buildings.upkeep(state,id)

# Upkeep of an army's general and units (queued units cost nothing until they arrive).
static func army_upkeep(state,army_id: String) -> int:
 var a = state.army_state[army_id]
 var total = float(UnitTypes.get_type("commander").placeholder_stats.upkeep)
 for u in a.units: total += float(UnitTypes.get_type(u.unit).placeholder_stats.upkeep)
 return int(round(total*float(data().upkeep.army_upkeep_multiplier)))

# Per-turn income sources and expenses of a faction (the treasury tooltip's breakdown).
static func faction_ledger(state,faction: String) -> Dictionary:
 var income = []
 var expenses = []
 for id in state.settlements_of(faction):
  income.append({"label":id,"amount":settlement_income(state,id).total,"kind":"settlement"})
  var up = building_upkeep(state,id)
  if up>0: expenses.append({"label":id,"amount":up,"kind":"buildings"})
 for army_id in state.armies_of(faction): expenses.append({"label":army_id,"amount":army_upkeep(state,army_id),"kind":"army"})
 # Trade agreements (core/diplomacy.gd; tariffs at war) and title tolls (core/titles.gd).
 if state.get("diplomacy") != null and not state.diplomacy.is_empty():
  for t in load("res://core/diplomacy.gd").trade_income(state,faction): income.append({"label":t.partner,"amount":int(t.amount),"kind":"trade"})
  var toll = load("res://core/titles.gd").toll_income(state,faction)
  if toll>0: income.append({"label":"tolls","amount":toll,"kind":"title"})
 var inc = 0
 var exp = 0
 for e in income: inc += e.amount
 for e in expenses: exp += e.amount
 return {"income":income,"expenses":expenses,"income_total":inc,"expense_total":exp,"net":inc-exp}

# Population cap: the main building's level sets the type capacity; housing adds to it.
static func capacity(state,id: String) -> float:
 var s = state.settlements[id]
 var t = type_data(s.type)
 return float(t.capacity[clampi(int(s.level),1,t.capacity.size())-1])+Buildings.effects(state,id).capacity

# Yearly population change of a settlement: logistic growth toward its capacity.
static func growth(state,id: String) -> Dictionary:
 var s = state.settlements[id]
 var t = type_data(s.type)
 var g = data().growth
 var cap = capacity(state,id)
 var resource_part = 0.0
 for r in s.resources: resource_part += float(s.resources[r])*float(data().resources[r].growth_bonus)
 var building_part = Buildings.effects(state,id).growth
 var pop = maxf(float(s.population),1.0)
 var wealth = minf(float(g.wealth_cap),settlement_income(state,id).total/(pop/1000.0)*float(g.wealth_per_gold_per_1000_people))
 var popularity = float(g.ruler_popularity_default)*float(g.popularity_factor) # STUB: popularity is open
 var rate = float(t.growth_base)+resource_part+building_part+wealth+popularity
 var delta = float(s.population)*rate*(1.0-float(s.population)/cap)
 return {"delta":delta,"rate":rate,"capacity":cap,"type_part":float(t.growth_base),"resource_part":resource_part,"building_part":building_part,"wealth_part":wealth,"popularity_part":popularity}
