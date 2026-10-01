extends RefCounted
# Economy rules from constitution.md (Economy and settlements). Pure functions over GameState;
# every number comes from data/economy.json.
#  - Gold is the currency; income and expenses are calculated per turn.
#  - Settlement type and level set base income. Cities are economic; fortresses have a lower
#    economic factor and a lower income ceiling even when developed.
#  - Regional resource endowments raise economic potential (income) and growth; never spent.
#  - Expenses: army upkeep (unit placeholder upkeep) and building upkeep.
#  - Population grows from type, resource abundance and wealth; ruler popularity is a neutral stub.

const UnitTypes = preload("res://core/unit_types.gd")
const DATA = "res://data/economy.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("settlement_types"),"Invalid "+DATA)
 return _data

static func reset():
 _data = null

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
 var base = float(t.base_income[i])
 var bonus = resource_income_bonus(s.resources)
 var raw = base*float(t.economic_factor)*(1.0+bonus)
 var ceiling = float(t.income_ceiling[i])
 return {"total":int(round(minf(raw,ceiling))),"base":base,"economic_factor":float(t.economic_factor),"resource_bonus":bonus,"ceiling":ceiling,"capped":raw>ceiling}

static func building_upkeep(state,id: String) -> int:
 var table = data().upkeep.building_upkeep_per_level
 var total = 0
 for b in state.settlements[id].buildings:
  if b.has("type"): total += int(table.get(b.type,0))*int(b.get("level",1))
 return total

static func army_upkeep(army_id: String) -> int:
 var a = UnitTypes.army(army_id)
 var total = 0.0
 for entry in [a.commander]+a.units: total += float(UnitTypes.get_type(entry.unit).placeholder_stats.upkeep)
 return int(round(total*float(data().upkeep.army_upkeep_multiplier)))

# Per-turn income sources and expenses of a faction (the treasury tooltip's breakdown).
static func faction_ledger(state,faction: String) -> Dictionary:
 var income = []
 var expenses = []
 for id in state.settlements_of(faction):
  income.append({"label":id,"amount":settlement_income(state,id).total,"kind":"settlement"})
  var up = building_upkeep(state,id)
  if up>0: expenses.append({"label":id,"amount":up,"kind":"buildings"})
 for army_id in state.armies_of(faction): expenses.append({"label":army_id,"amount":army_upkeep(army_id),"kind":"army"})
 var inc = 0
 var exp = 0
 for e in income: inc += e.amount
 for e in expenses: exp += e.amount
 return {"income":income,"expenses":expenses,"income_total":inc,"expense_total":exp,"net":inc-exp}

# Yearly population change of a settlement: logistic growth toward its capacity.
static func growth(state,id: String) -> Dictionary:
 var s = state.settlements[id]
 var t = type_data(s.type)
 var g = data().growth
 var i = clampi(int(s.level),1,t.capacity.size())-1
 var capacity = float(t.capacity[i])
 var resource_part = 0.0
 for r in s.resources: resource_part += float(s.resources[r])*float(data().resources[r].growth_bonus)
 var pop = maxf(float(s.population),1.0)
 var wealth = minf(float(g.wealth_cap),settlement_income(state,id).total/(pop/1000.0)*float(g.wealth_per_gold_per_1000_people))
 var popularity = float(g.ruler_popularity_default)*float(g.popularity_factor) # STUB: popularity is open
 var rate = float(t.growth_base)+resource_part+wealth+popularity
 var delta = float(s.population)*rate*(1.0-float(s.population)/capacity)
 return {"delta":delta,"rate":rate,"capacity":capacity,"type_part":float(t.growth_base),"resource_part":resource_part,"wealth_part":wealth,"popularity_part":popularity}
