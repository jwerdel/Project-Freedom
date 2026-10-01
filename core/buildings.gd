extends RefCounted
# Building chains and their effects (data/buildings.json). Pure functions over GameState.
# A settlement's buildings are slots: slot 0 is always the main building (its level IS the
# settlement level); other slots are {} (empty) or {chain, level[, name]}. Each level's effects are
# that level's totals (an upgrade replaces the lower level's numbers), except recruitment unlocks,
# which accumulate over levels 1..n. Constitution: buildings have real effects (income, growth,
# recruitment unlocks, defense); in V1 availability is gated only by settlement level.

const UnitTypes = preload("res://core/unit_types.gd")
const DATA = "res://data/buildings.json"
const EFFECT_KEYS = ["income","income_pct","tax_pct","growth","capacity","defense","public_order"]

static var _data = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("chains") and _data.has("slots"),"Invalid "+DATA)
  for id in _data.chains:
   var c = _data.chains[id]
   assert(c.levels.size()>=1 and c.levels.size()<=3,"Chain %s needs 1-3 levels" % id)
 return _data

static func reset():
 _data = null

static func chain(id: String) -> Dictionary:
 assert(data().chains.has(id),"Unknown building chain '%s'" % id)
 return data().chains[id]

static func chain_ids() -> Array:
 var out = data().chains.keys()
 out.sort()
 return out

static func level_data(chain_id: String,level: int) -> Dictionary:
 var levels = chain(chain_id).levels
 assert(level>=1 and level<=levels.size(),"Chain %s has no level %d" % [chain_id,level])
 return levels[level-1]

static func max_level(chain_id: String) -> int:
 return chain(chain_id).levels.size()

static func main_chain_id(settlement_type: String) -> String:
 assert(data().main_chains.has(settlement_type),"No main chain for settlement type '%s'" % settlement_type)
 return data().main_chains[settlement_type]

static func is_main(chain_id: String) -> bool:
 return chain(chain_id).get("main",false)

# Chains a settlement of this type can ever build in a non-main slot.
static func chains_for(settlement_type: String) -> Array:
 var out = []
 for id in chain_ids():
  var c = chain(id)
  if not c.get("main",false) and settlement_type in c.get("settlement_types",[]): out.append(id)
 return out

static func slot_count(settlement_type: String,level: int) -> int:
 var table = data().slots[settlement_type]
 return int(table[clampi(level,1,table.size())-1])

# Display name of a built level; landmark settlements name their main building per level.
static func building_name(settlement_id: String,chain_id: String,level: int) -> String:
 if is_main(chain_id) and data().landmark_names.has(settlement_id):
  return data().landmark_names[settlement_id][level-1]
 return level_data(chain_id,level).name

# Built buildings of a settlement as [{slot, chain, level}], main building first.
static func built(state,id: String) -> Array:
 var out = []
 var slots = state.settlements[id].buildings
 for i in slots.size():
  if slots[i].has("chain") and int(slots[i].get("level",0))>0: out.append({"slot":i,"chain":slots[i].chain,"level":int(slots[i].level)})
 return out

# Summed effects of every building in a settlement. income is flat gold including endowment terms.
static func effects(state,id: String) -> Dictionary:
 var s = state.settlements[id]
 var out = {"unlocks":[]}
 for k in EFFECT_KEYS: out[k] = 0.0
 for b in built(state,id):
  var e = level_data(b.chain,b.level).effects
  for k in EFFECT_KEYS: out[k] += float(e.get(k,0))
  for r in e.get("income_per_endowment",{}): out.income += float(e.income_per_endowment[r])*float(s.resources.get(r,0))
  for l in range(1,b.level+1):
   for u in level_data(b.chain,l).effects.get("unlocks",[]):
    if not u in out.unlocks: out.unlocks.append(u)
 out.unlocks.sort()
 return out

static func upkeep(state,id: String) -> int:
 var total = 0
 for b in built(state,id): total += int(level_data(b.chain,b.level).upkeep)
 return total

static func defense(state,id: String) -> int:
 return int(effects(state,id).defense)

static func unlocked_units(state,id: String) -> Array:
 return effects(state,id).unlocks

# Store derived values on the settlement for later systems (battles read defense, recruitment
# reads unlocks). Call after any building change.
static func refresh(state,id: String):
 var e = effects(state,id)
 state.settlements[id].defense = int(e.defense)
 state.settlements[id].unlocks = e.unlocks.duplicate()

# Readable effect lines for one chain level (building browser and tooltips).
static func effect_lines(chain_id: String,level: int) -> Array:
 var e = level_data(chain_id,level).effects
 var out = []
 if e.get("income",0): out.append("+%d gold per turn" % int(e.income))
 for r in e.get("income_per_endowment",{}): out.append("+%d gold per %s endowment point" % [int(e.income_per_endowment[r]),r])
 if e.get("income_pct",0): out.append("+%d%% settlement income" % int(round(e.income_pct*100)))
 if e.get("tax_pct",0): out.append("+%d%% tax from population" % int(round(e.tax_pct*100)))
 if e.get("growth",0): out.append("+%.1f%% yearly growth" % (e.growth*100))
 if e.get("capacity",0): out.append("+%d population cap" % int(e.capacity))
 if e.get("defense",0): out.append("+%d defense" % int(e.defense))
 for u in e.get("unlocks",[]): out.append("Unlocks recruitment: %s" % UnitTypes.get_type(u).display_name)
 if e.get("public_order",0): out.append("+%d public order (not simulated yet)" % int(e.public_order))
 return out
