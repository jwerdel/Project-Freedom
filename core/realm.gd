extends RefCounted
# A faction's standing as a whole (constitution, confirmed 2026-10-01):
#  - Debt: a treasury may fall below zero down to a limit (data/economy.json debt). In debt: no
#    construction, recruitment or new armies (enforced where those are bought), and desertion each
#    End Turn. Below the limit: the units with the highest upkeep disband until income covers
#    upkeep.
#  - Loss condition: losing the last settlement starts a grace period (data/campaign_rules.json);
#    retaking a settlement in time saves the faction, otherwise it is destroyed and its armies
#    disband. The player's destruction is game over.
# State: state.grace (faction -> End Turns left), state.destroyed (factions).

const Economy = preload("res://core/economy.gd")
const Armies = preload("res://core/armies.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const Chronicle = preload("res://core/chronicle.gd")
const RULES = "res://data/campaign_rules.json"

static var _rules = null

static func rules() -> Dictionary:
 if _rules == null:
  _rules = JSON.parse_string(FileAccess.get_file_as_string(RULES))
  assert(_rules is Dictionary and _rules.has("loss"),"Invalid "+RULES)
 return _rules

static func reset():
 _rules = null

static func debt() -> Dictionary:
 return Economy.data().debt

static func in_debt(state,f: String) -> bool:
 return int(state.treasury.get(f,0))<0

static func below_limit(state,f: String) -> bool:
 return int(state.treasury.get(f,0))<int(debt().limit)

static func destroyed(state,f: String) -> bool:
 return f in state.destroyed

# Turns left to retake a settlement, or -1 when the faction is not in its grace period.
static func grace_left(state,f: String) -> int:
 return int(state.grace.get(f,-1))

static func _upkeep(u: Dictionary) -> float:
 return float(UnitTypes.get_type(u.unit).placeholder_stats.upkeep)*float(Economy.data().upkeep.army_upkeep_multiplier)

# End Turn, after income and expenses: desertion in debt, disbanding below the limit.
# Returns events [{kind: desertion|disband, faction, ...}].
static func apply_debt(state) -> Array:
 var events = []
 var share = float(debt().desertion_share)
 for f in state.factions():
  if not in_debt(state,f): continue
  var lost = 0
  for id in Armies.armies_of(state,f):
   for u in state.army_state[id].units:
    var n = mini(maxi(1,int(round(int(u.men)*share))),int(u.men)-1)
    if n<=0: continue
    u.men = int(u.men)-n
    lost += n
  if lost>0: events.append({"kind":"desertion","faction":f,"men":lost})
  if not below_limit(state,f): continue
  # Below the limit: the most expensive units go first, until income covers upkeep.
  var guard = 0
  while int(Economy.faction_ledger(state,f).net)<0 and guard<200:
   guard += 1
   var worst = {}
   for id in Armies.armies_of(state,f):
    var a = state.army_state[id]
    for i in a.units.size():
     var key = [-_upkeep(a.units[i]),id,i]
     if worst.is_empty() or key<worst.key: worst = {"key":key,"army":id,"index":i,"unit":a.units[i].unit}
   if worst.is_empty(): break
   Armies.disband(state,worst.army,worst.index)
   events.append({"kind":"disband","faction":f,"army":worst.army,"unit":worst.unit})
 return events

# End Turn, last: start, count down or end grace periods; destroy factions whose grace ran out.
# Returns events [{kind: landless|grace|survived|destroyed, faction, turns}].
static func check_survival(state) -> Array:
 var events = []
 for f in state.factions():
  if destroyed(state,f): continue
  var landless = state.settlements_of(f).is_empty()
  if not landless:
   if state.grace.has(f):
    state.grace.erase(f)
    events.append({"kind":"survived","faction":f})
   continue
  if not state.grace.has(f):
   # It just lost its last settlement: the countdown starts. Without an army it cannot retake
   # anything, so it is destroyed at once.
   if Armies.armies_of(state,f).is_empty():
    destroy(state,f)
    events.append({"kind":"destroyed","faction":f})
    continue
   state.grace[f] = int(rules().loss.grace_turns)
   events.append({"kind":"landless","faction":f,"turns":state.grace[f]})
   continue
  state.grace[f] = int(state.grace[f])-1
  if int(state.grace[f])<=0 or Armies.armies_of(state,f).is_empty():
   destroy(state,f)
   events.append({"kind":"destroyed","faction":f})
  else: events.append({"kind":"grace","faction":f,"turns":state.grace[f]})
 return events

# Destroyed: its armies disband (their men go home to the region they stand in) and it leaves the game.
static func destroy(state,f: String):
 for id in Armies.armies_of(state,f):
  var a = state.army_state[id]
  while not a.units.is_empty(): Armies.disband(state,id,a.units.size()-1)
  state.army_state.erase(id)
  state.armies.erase(id)
 state.grace.erase(f)
 if not f in state.destroyed: state.destroyed.append(f)
 state.pending_battles = state.pending_battles.filter(func(p): return p.attacker.faction != f)

# Chronicle entries for the events above (the player's own countdown is told every turn).
static func entries(state,year: int,events: Array) -> Array:
 var out = []
 for e in events:
  match e.kind:
   "landless","survived","destroyed": out.append(Chronicle.realm_entry(year,e.kind,e.faction,int(e.get("turns",0))))
   "grace":
    if e.faction == state.player_faction: out.append(Chronicle.realm_entry(year,"grace",e.faction,int(e.turns)))
   "desertion":
    if e.faction == state.player_faction: out.append(Chronicle.realm_entry(year,"desertion",e.faction,int(e.men)))
 return out
