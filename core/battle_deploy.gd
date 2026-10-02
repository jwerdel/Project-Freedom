extends RefCounted
# Default deployments (docs/battle-design.md sections 7-8): AI templates and the player's quick
# resolve. deploy() places an army's units on the lane grid with orders; templates are chosen from
# the faction's battle_style in data/maps/<map>/factions.json and the army's makeup.

const UnitTypes = preload("res://core/unit_types.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const TEMPLATES = ["line","shield_wall","hammer_anvil","levy_swarm","hold_walls"]

# Lanes from the center outward (5 lanes: 2,1,3,0,4).
static func lane_order(lanes: int) -> Array:
 var c = lanes/2
 var out = [c]
 for k in range(1,c+1):
  out.append(c-k)
  out.append(c+k)
 return out

static func capacity(terrain: Array,lanes: int,lane: int,band: int) -> int:
 var cap = BattleSim.data().field.capacity_per_line[str(lanes)]
 return int(cap[terrain[lane][band]])

static func is_levy(u: Dictionary) -> bool:
 var t = UnitTypes.get_type(u.unit)
 return t.category == "infantry" and float(t.battle.morale)<=35.0

static func strength(u: Dictionary) -> float:
 var b = UnitTypes.get_type(u.unit).battle
 return float(b.melee_attack)+float(b.melee_defence)+float(b.armour)*0.5

# Template for a faction: its style from data/maps/<map>/factions.json, adapted to the army.
static func choose_template(style: Dictionary,units: Array,siege_defender: bool) -> String:
 if siege_defender: return "hold_walls"
 var levies = 0
 var cav = 0
 for u in units:
  if is_levy(u): levies += 1
  elif UnitTypes.get_type(u.unit).category == "cavalry": cav += 1
 if style.has("if_levy_majority") and levies*2>units.size(): return style.if_levy_majority
 if style.has("if_cavalry") and cav>=int(style.get("cavalry_min",2)): return style.if_cavalry
 return style.get("default","line")

# Units: [{unit, men, max_men?, rank?, index?, army?}]. role: 0 attacker, 1 defender.
# Returns copies with lane, line (front/back/reserve), order and protect set.
static func deploy(units: Array,template: String,terrain: Array,role: int) -> Array:
 var lanes = terrain.size()
 var fb = 1 if role == 0 else 4   # front band index (0-based) for this side
 var bb = 0 if role == 0 else 5
 var free = {}
 for l in lanes:
  free["front:%d" % l] = capacity(terrain,lanes,l,fb)
  free["back:%d" % l] = capacity(terrain,lanes,l,bb)
 var spears = []
 var infantry = []
 var levies = []
 var missile = []
 var cavalry = []
 for u in units:
  var t = UnitTypes.get_type(u.unit)
  var c = u.duplicate()
  if t.category == "cavalry": cavalry.append(c)
  elif t.category == "missile": missile.append(c)
  elif is_levy(c): levies.append(c)
  elif t.battle.brace: spears.append(c)
  else: infantry.append(c)
 infantry.sort_custom(func(a,b): return strength(a)>strength(b))
 var out = []
 var order = lane_order(lanes)
 var outer = [0,lanes-1]
 var inner = order.filter(func(l): return not l in outer) if lanes>3 else order
 # put: try each [line, order, lanes] in turn; a unit that fits nowhere goes to the reserve.
 var put = func(u: Dictionary,tries: Array):
  for t in tries:
   for l in t[2]:
    var k = "%s:%d" % [t[0],l]
    if free.get(k,0)>0:
     free[k] -= 1
     u.lane = l
     u.line = t[0]
     u.order = t[1]
     out.append(u)
     return
  u.lane = lanes/2
  u.line = "reserve"
  u.order = "reserve"
  out.append(u)
 var fo = "aggressive" if role == 0 else "hold"
 # Attacking missile troops advance until the enemy is in range (they never charge).
 var mo = "aggressive" if role == 0 else "hold"
 match template:
  "shield_wall":
   for u in spears+infantry+levies: put.call(u,[["front",fo,order],["back","hold",order]])
   for u in missile: put.call(u,[["back",mo,order]])
   for u in cavalry: put.call(u,[])
  "hammer_anvil":
   for u in spears+infantry+levies: put.call(u,[["front",fo,inner],["back","hold",inner]])
   for u in missile: put.call(u,[["back",mo,inner]])
   for i in cavalry.size(): put.call(cavalry[i],[["front","flank",[outer[i%2]]]])
  "levy_swarm":
   for u in levies: put.call(u,[["front","aggressive",order]])
   for u in spears+infantry: put.call(u,[["front",fo,order],["back","hold",order]])
   for u in missile: put.call(u,[["back",mo,order]])
   for u in cavalry: put.call(u,[])
  "hold_walls":
   for u in missile: put.call(u,[["front","hold",order],["back","hold",order]])
   for u in spears+infantry+levies: put.call(u,[["front","hold",order],["back","hold",order]])
   for u in cavalry: put.call(u,[])
  _: # line: infantry across the inner lanes, missiles behind, one cavalry flank, the rest in reserve
   var line_units = spears+infantry+levies
   var keep = null
   if cavalry.is_empty() and line_units.size()>=4: keep = line_units.pop_back()
   for u in line_units: put.call(u,[["front",fo,inner],["front",fo,order],["back","hold",order]])
   for u in missile: put.call(u,[["back",mo,inner],["back",mo,order]])
   for i in cavalry.size(): put.call(cavalry[i],[["front","flank",[outer[0]]]] if i == 0 else [])
   if keep != null: put.call(keep,[])
 return out
