extends RefCounted
# Construction (TW:WH3-style), over GameState and data/buildings.json:
#  - Each settlement has a main building in slot 0; its level is the settlement level and caps the
#    level of every other building. Upgrading it raises the settlement level, its population cap
#    and slot count, and moves the settlement visual to the next growth stage.
#  - Other slots hold one building chain each (no duplicates per settlement), built from level 1
#    and upgraded one level at a time. In V1 availability is gated by settlement level, plus
#    geography where a chain requires it (data "requires": coastal, water (sea, lake or river), hills).
#  - Every slot can be under construction at the same time (owner spec 2026-10-07: parallel builds),
#    each paid when it starts; each completes after its level's turns (1 turn = 1 year) during End
#    Turn. Cancelling refunds in full in the turn it started, partially afterwards (PLACEHOLDER rule).
#    State: settlement "constructions" = [{slot, chain, level, turns_left, turns_total, cost, started_turn}].
#  - AI factions build through start() like the player (core/ai.gd decides what).
# OPEN (constitution): converting a city to a fortress or back is confirmed but deferred, not built.

const Buildings = preload("res://core/buildings.gd")
const Resources = preload("res://core/resources.gd")
const CATEGORY_ORDER = ["economic","civic","military","defense"]

static func rules() -> Dictionary:
 return Buildings.data().construction

# Every construction under way in a settlement (one per slot).
static func jobs(state,id: String) -> Array:
 var s = state.settlements[id]
 if not s.has("constructions") or not s.constructions is Array: s.constructions = []
 return s.constructions

# The construction in a slot, or {}.
static func in_slot(state,id: String,slot: int) -> Dictionary:
 for j in jobs(state,id):
  if int(j.slot) == slot: return j
 return {}

# The first construction under way ({} when nothing builds); "is anything building here" for callers
# that need no more.
static func in_progress(state,id: String) -> Dictionary:
 var j = jobs(state,id)
 return j[0] if not j.is_empty() else {}

# Every construction of a faction across its realm (the realm construction queue): [{settlement, job}].
static func realm_jobs(state,faction: String) -> Array:
 var out = []
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids:
  if state.settlements[id].owner != faction: continue
  for j in jobs(state,id): out.append({"settlement":id,"job":j})
 return out

# What building a slot offers: [{chain, level, name, cost, turns, upkeep, effects, available, reasons}].
# Empty slot: level 1 of every chain this settlement type can build and whose site fits (a chain that
# needs water, hills or woodland is not offered without them). Built slot: its next level.
static func options(state,id: String,slot: int) -> Array:
 var s = state.settlements[id]
 var b = s.buildings[slot]
 var out = []
 if b.has("chain"):
  if int(b.level)<Buildings.max_level(b.chain): out.append(_option(state,id,slot,b.chain,int(b.level)+1))
 else:
  # Chains already standing or building elsewhere here are not listed again.
  var present = []
  for other in s.buildings: present.append(other.get("chain",""))
  for j in jobs(state,id): present.append(str(j.chain))
  for c in Buildings.chains_for(s.type):
   if c in present or Buildings.site_reason(state,id,c) != "": continue
   out.append(_option(state,id,slot,c,1))
  out.sort_custom(func(a,b): return [CATEGORY_ORDER.find(a.category),a.cost,a.chain]<[CATEGORY_ORDER.find(b.category),b.cost,b.chain])
 return out

static func _option(state,id: String,slot: int,chain_id: String,level: int) -> Dictionary:
 var l = Buildings.level_data(chain_id,level)
 var check = can_build(state,id,slot,chain_id)
 return {"chain":chain_id,"level":level,"name":Buildings.building_name(id,chain_id,level),"chain_name":Buildings.chain(chain_id).name,
  "category":Buildings.chain(chain_id).category,"cost":int(l.cost),"turns":int(l.turns),"upkeep":int(l.upkeep),
  "effects":Buildings.effect_lines(chain_id,level),"available":check.ok,"reasons":check.reasons,"materials":Resources.building_cost(chain_id,level)}

# Whether chain_id can be built (or upgraded) in this slot now, and why not.
static func can_build(state,id: String,slot: int,chain_id: String) -> Dictionary:
 var s = state.settlements[id]
 var reasons = []
 if slot<0 or slot>=s.buildings.size(): return {"ok":false,"reasons":["No such slot"],"level":0}
 var b = s.buildings[slot]
 var main = Buildings.main_chain_id(s.type)
 var level = 1
 if not in_slot(state,id,slot).is_empty(): return {"ok":false,"reasons":["Already under construction in this slot"],"level":0}
 if b.has("chain"):
  if b.chain != chain_id: return {"ok":false,"reasons":["Slot holds %s" % Buildings.chain(b.chain).name],"level":0}
  level = int(b.level)+1
  if level>Buildings.max_level(chain_id): return {"ok":false,"reasons":["Already at the highest level"],"level":level}
 else:
  if Buildings.is_main(chain_id) or not chain_id in Buildings.chains_for(s.type):
   return {"ok":false,"reasons":["%s cannot be built in a %s" % [Buildings.chain(chain_id).name,s.type]],"level":level}
  for other in s.buildings:
   if other.get("chain","") == chain_id: reasons.append("Already built in this settlement")
  for j in jobs(state,id):
   if str(j.chain) == chain_id: reasons.append("Already under construction here")
 # The land decides new buildings only; one already standing keeps upgrading.
 var site = Buildings.site_reason(state,id,chain_id) if not b.has("chain") else ""
 if site != "": reasons.append(site)
 if not Buildings.is_main(chain_id) and level>int(s.level):
  reasons.append("Requires %s (settlement level %d)" % [Buildings.building_name(id,main,level),level])
 var cap = int(rules().get("max_per_settlement",0))
 if cap>0 and jobs(state,id).size()>=cap: reasons.append("Another construction is in progress here")
 var cost = int(Buildings.level_data(chain_id,level).cost)
 if int(state.treasury.get(s.owner,0))<0: reasons.append("In debt: no construction until the treasury is out of debt")
 elif int(state.treasury.get(s.owner,0))<cost: reasons.append("Not enough gold (%d needed)" % cost)
 # Wood and stone (Part B, data/resources.json building_costs).
 reasons.append_array(Resources.shortfall(state,s.owner,Resources.building_cost(chain_id,level)))
 return {"ok":reasons.is_empty(),"reasons":reasons,"level":level}

# Pay and start construction. Returns {ok, reasons}.
static func start(state,id: String,slot: int,chain_id: String) -> Dictionary:
 var check = can_build(state,id,slot,chain_id)
 if not check.ok: return check
 var s = state.settlements[id]
 var l = Buildings.level_data(chain_id,check.level)
 state.treasury[s.owner] -= int(l.cost)
 var mats = Resources.building_cost(chain_id,check.level)
 Resources.pay(state,s.owner,mats)
 jobs(state,id).append({"slot":slot,"chain":chain_id,"level":check.level,"turns_left":int(l.turns),"turns_total":int(l.turns),"cost":int(l.cost),"materials":mats,"started_turn":state.turn})
 return check

# The refund for cancelling the construction in a slot (-1: the first one).
static func refund_amount(state,id: String,slot := -1) -> int:
 var c = in_progress(state,id) if slot<0 else in_slot(state,id,slot)
 if c.is_empty(): return 0
 var ratio = rules().cancel_refund_same_turn if int(c.started_turn) == state.turn else rules().cancel_refund_later
 return int(round(float(c.cost)*float(ratio)))

# Cancel the construction in a slot (-1: the first one); returns the gold refunded.
static func cancel(state,id: String,slot := -1) -> int:
 var c = in_progress(state,id) if slot<0 else in_slot(state,id,slot)
 if c.is_empty(): return 0
 var refund = refund_amount(state,id,int(c.slot))
 state.treasury[state.settlements[id].owner] += refund
 var ratio = float(rules().cancel_refund_same_turn) if int(c.started_turn) == state.turn else float(rules().cancel_refund_later)
 Resources.refund(state,state.settlements[id].owner,c.get("materials",{}),ratio)
 jobs(state,id).erase(c)
 return refund

# Drop every construction of a settlement (it changed hands): nothing is refunded.
static func clear(state,id: String):
 state.settlements[id].constructions = []

# End Turn: advance every construction by one turn; returns the completions of this turn.
static func advance(state) -> Array:
 var done = []
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids:
  var list = jobs(state,id)
  if list.is_empty(): continue
  var s = state.settlements[id]
  for c in list.duplicate():
   c.turns_left = int(c.turns_left)-1
   if c.turns_left>0: continue
   list.erase(c)
   var slot = s.buildings[int(c.slot)]
   if not slot.has("chain"): s.buildings[int(c.slot)] = {"chain":c.chain,"level":c.level}
   else: slot.level = c.level
   var main = Buildings.is_main(c.chain)
   if main: _set_settlement_level(state,id,int(c.level))
   Buildings.refresh(state,id)
   done.append({"settlement":id,"faction":s.owner,"chain":c.chain,"level":int(c.level),"main":main,"name":Buildings.building_name(id,c.chain,int(c.level))})
 return done

# Settlement level follows the main building; new slots open as empty slots. Shrinking (debug
# only) keeps occupied slots and slots under construction, and drops trailing empty ones.
static func _set_settlement_level(state,id: String,level: int):
 var s = state.settlements[id]
 s.level = level
 s.buildings[0].level = level
 var count = Buildings.slot_count(s.type,level)
 while s.buildings.size()<count: s.buildings.append({})
 while s.buildings.size()>count and s.buildings.back().is_empty() and in_slot(state,id,s.buildings.size()-1).is_empty(): s.buildings.pop_back()

# Debug/developer override (prototype keys and capture flags): set the main building level directly.
static func set_level(state,id: String,level: int):
 _set_settlement_level(state,id,level)
 Buildings.refresh(state,id)

# Growth-stage visual of a settlement: its stage is its level; generic is the main chain's
# asset-manifest prefix (landmarks use their own stages via AssetManifest).
static func visual_stage(state,id: String) -> Dictionary:
 var s = state.settlements[id]
 return {"stage":int(s.level),"generic":Buildings.chain(Buildings.main_chain_id(s.type)).visual_generic}
