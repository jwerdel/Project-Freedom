extends RefCounted
# Construction (TW:WH3-style), over GameState and data/buildings.json:
#  - Each settlement has a main building in slot 0; its level is the settlement level and caps the
#    level of every other building. Upgrading it raises the settlement level, its population cap
#    and slot count, and moves the settlement visual to the next growth stage.
#  - Other slots hold one building chain each (no duplicates per settlement), built from level 1
#    and upgraded one level at a time. In V1 availability is gated by settlement level, plus
#    geography where a chain requires it (ports need a coastal settlement).
#  - Gold is paid when construction starts; it completes after the level's turns (1 turn = 1 year)
#    during End Turn. One construction at a time per settlement (data). Cancelling refunds in full
#    in the turn it started, partially afterwards (PLACEHOLDER rule in data).
#  - AI factions build through start() like the player (core/ai.gd decides what).
# OPEN (constitution): converting a city to a fortress or back is confirmed but deferred, not built.

const Buildings = preload("res://core/buildings.gd")
const CATEGORY_ORDER = ["economic","civic","military","defense"]

static func rules() -> Dictionary:
 return Buildings.data().construction

static func in_progress(state,id: String) -> Dictionary:
 return state.settlements[id].get("construction",{})

# What building a slot offers: [{chain, level, name, cost, turns, upkeep, effects, available, reasons}].
# Empty slot: level 1 of every chain this settlement type can build. Built slot: its next level.
static func options(state,id: String,slot: int) -> Array:
 var s = state.settlements[id]
 var b = s.buildings[slot]
 var out = []
 if b.has("chain"):
  if int(b.level)<Buildings.max_level(b.chain): out.append(_option(state,id,slot,b.chain,int(b.level)+1))
 else:
  # Chains already standing elsewhere here are upgraded from their own slot, so not listed.
  var present = []
  for other in s.buildings: present.append(other.get("chain",""))
  for c in Buildings.chains_for(s.type):
   if not c in present: out.append(_option(state,id,slot,c,1))
  out.sort_custom(func(a,b): return [CATEGORY_ORDER.find(a.category),a.cost,a.chain]<[CATEGORY_ORDER.find(b.category),b.cost,b.chain])
 return out

static func _option(state,id: String,slot: int,chain_id: String,level: int) -> Dictionary:
 var l = Buildings.level_data(chain_id,level)
 var check = can_build(state,id,slot,chain_id)
 return {"chain":chain_id,"level":level,"name":Buildings.building_name(id,chain_id,level),"chain_name":Buildings.chain(chain_id).name,
  "category":Buildings.chain(chain_id).category,"cost":int(l.cost),"turns":int(l.turns),"upkeep":int(l.upkeep),
  "effects":Buildings.effect_lines(chain_id,level),"available":check.ok,"reasons":check.reasons}

# Whether chain_id can be built (or upgraded) in this slot now, and why not.
static func can_build(state,id: String,slot: int,chain_id: String) -> Dictionary:
 var s = state.settlements[id]
 var reasons = []
 if slot<0 or slot>=s.buildings.size(): return {"ok":false,"reasons":["No such slot"],"level":0}
 var b = s.buildings[slot]
 var main = Buildings.main_chain_id(s.type)
 var level = 1
 if b.has("chain"):
  if b.chain != chain_id: return {"ok":false,"reasons":["Slot holds %s" % Buildings.chain(b.chain).name],"level":0}
  level = int(b.level)+1
  if level>Buildings.max_level(chain_id): return {"ok":false,"reasons":["Already at the highest level"],"level":level}
 else:
  if Buildings.is_main(chain_id) or not chain_id in Buildings.chains_for(s.type):
   return {"ok":false,"reasons":["%s cannot be built in a %s" % [Buildings.chain(chain_id).name,s.type]],"level":level}
  for other in s.buildings:
   if other.get("chain","") == chain_id: reasons.append("Already built in this settlement")
  var pending = in_progress(state,id)
  if pending.get("chain","") == chain_id: reasons.append("Already under construction here")
 if Buildings.chain(chain_id).get("requires",{}).get("coastal",false) and not s.get("coastal",false): reasons.append("Requires coast")
 if not Buildings.is_main(chain_id) and level>int(s.level):
  reasons.append("Requires %s (settlement level %d)" % [Buildings.building_name(id,main,level),level])
 if not in_progress(state,id).is_empty() and not "Already under construction here" in reasons:
  reasons.append("Another construction is in progress here")
 var cost = int(Buildings.level_data(chain_id,level).cost)
 if int(state.treasury.get(s.owner,0))<cost: reasons.append("Not enough gold (%d needed)" % cost)
 return {"ok":reasons.is_empty(),"reasons":reasons,"level":level}

# Pay and start construction. Returns {ok, reasons}.
static func start(state,id: String,slot: int,chain_id: String) -> Dictionary:
 var check = can_build(state,id,slot,chain_id)
 if not check.ok: return check
 var s = state.settlements[id]
 var l = Buildings.level_data(chain_id,check.level)
 state.treasury[s.owner] -= int(l.cost)
 s.construction = {"slot":slot,"chain":chain_id,"level":check.level,"turns_left":int(l.turns),"turns_total":int(l.turns),"cost":int(l.cost),"started_turn":state.turn}
 return check

static func refund_amount(state,id: String) -> int:
 var c = in_progress(state,id)
 if c.is_empty(): return 0
 var ratio = rules().cancel_refund_same_turn if int(c.started_turn) == state.turn else rules().cancel_refund_later
 return int(round(float(c.cost)*float(ratio)))

# Cancel this settlement's construction; returns the gold refunded.
static func cancel(state,id: String) -> int:
 var refund = refund_amount(state,id)
 if in_progress(state,id).is_empty(): return 0
 var s = state.settlements[id]
 state.treasury[s.owner] += refund
 s.construction = {}
 return refund

# End Turn: advance every construction by one turn; returns the completions of this turn.
static func advance(state) -> Array:
 var done = []
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids:
  var c = in_progress(state,id)
  if c.is_empty(): continue
  c.turns_left = int(c.turns_left)-1
  if c.turns_left>0: continue
  var s = state.settlements[id]
  s.construction = {}
  var slot = s.buildings[int(c.slot)]
  if not slot.has("chain"): s.buildings[int(c.slot)] = {"chain":c.chain,"level":c.level}
  else: slot.level = c.level
  var main = Buildings.is_main(c.chain)
  if main: _set_settlement_level(state,id,int(c.level))
  Buildings.refresh(state,id)
  done.append({"settlement":id,"faction":s.owner,"chain":c.chain,"level":int(c.level),"main":main,"name":Buildings.building_name(id,c.chain,int(c.level))})
 return done

# Settlement level follows the main building; new slots open as empty slots. Shrinking (debug
# only) keeps occupied slots and drops trailing empty ones.
static func _set_settlement_level(state,id: String,level: int):
 var s = state.settlements[id]
 s.level = level
 s.buildings[0].level = level
 var count = Buildings.slot_count(s.type,level)
 while s.buildings.size()<count: s.buildings.append({})
 while s.buildings.size()>count and s.buildings.back().is_empty() and not (int(in_progress(state,id).get("slot",-1)) == s.buildings.size()-1): s.buildings.pop_back()

# Debug/developer override (prototype keys and capture flags): set the main building level directly.
static func set_level(state,id: String,level: int):
 _set_settlement_level(state,id,level)
 Buildings.refresh(state,id)

# Growth-stage visual of a settlement: its stage is its level; generic is the main chain's
# asset-manifest prefix (landmarks use their own stages via AssetManifest).
static func visual_stage(state,id: String) -> Dictionary:
 var s = state.settlements[id]
 return {"stage":int(s.level),"generic":Buildings.chain(Buildings.main_chain_id(s.type)).visual_generic}
