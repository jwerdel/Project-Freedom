extends RefCounted
# Battlefield generation (docs/battle-design.md section 1): samples the campaign movement grid
# (data/movement_grid.json) around the defender into lanes x 6 bands, oriented along the
# attacker's approach. Each lane-band takes the majority terrain of its cells. Settlement battles
# add walls when the settlement's stored defense is high enough.

const Movement = preload("res://core/movement.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const MAP_TO_BATTLE = {"open":"open","settlement":"open","forest":"forest","hills":"hills","pass":"pass","mountain":"closed","water":"closed"}

# defender_pos / attacker_pos: world x/z. Returns {terrain: [lane][band], lanes, summary}.
static func sample(defender_pos: Vector2,attacker_pos: Vector2,lanes := -1) -> Dictionary:
 var d = BattleSim.data().field
 if lanes<0: lanes = int(d.lanes)
 var bands = int(d.bands)
 var cell = float(Movement.grid().cell)
 var forward = (defender_pos-attacker_pos).normalized()
 if forward.length()<0.5: forward = Vector2(0,1)
 var side = forward.orthogonal()
 var lane_w = cell*(2.0 if lanes == 5 else 3.0)
 var band_d = cell*2.0
 var terrain = []
 var counts = {}
 for l in lanes:
  var col = []
  for b in bands:
   # Band 0 is the attacker's back line; the defender stands between bands 4 and 5.
   var center = defender_pos+forward*((b-4.5)*band_d)+side*((l-(lanes-1)/2.0)*lane_w)
   var votes = {}
   for sx in [-0.25,0.25]:
    for sy in [-0.25,0.25]:
     var p = center+side*(sx*lane_w)+forward*(sy*band_d)
     var c = Movement.cell_of(p)
     var t = "road" if Movement.is_road(c) and Movement.terrain_of(c) != "water" else MAP_TO_BATTLE.get(Movement.terrain_of(c),"open")
     votes[t] = votes.get(t,0)+1
   var best = "open"
   for t in ["closed","pass","forest","hills","road","open"]:
    if votes.get(t,0)>votes.get(best,0): best = t
   col.append(best)
   counts[best] = counts.get(best,0)+1
  terrain.append(col)
 # A lane that is closed in the deployment bands of either side is closed throughout.
 for l in lanes:
  if terrain[l][1] == "closed" or terrain[l][4] == "closed":
   for b in bands: terrain[l][b] = "closed"
 return {"terrain":terrain,"lanes":lanes,"summary":summary(terrain)}

# Readable terrain summary for the pre-battle panel.
static func summary(terrain: Array) -> String:
 var counts = {}
 for col in terrain:
  for t in col: counts[t] = counts.get(t,0)+1
 var total = 0
 for t in counts: total += counts[t]
 var parts = []
 for t in ["open","road","forest","hills","pass","closed"]:
  if counts.has(t): parts.append("%s %d%%" % [{"closed":"impassable"}.get(t,t),int(round(100.0*counts[t]/total))])
 var closed = 0
 for col in terrain:
  if col[0] == "closed": closed += 1
 var s = ", ".join(parts)
 if closed>0: s += " (%d of %d lanes blocked)" % [closed,terrain.size()]
 return s

# Walls for a settlement battle, or null (stored defense below the threshold means a field battle).
static func walls(defense: int,siege_turns: int,lanes: int):
 var s = BattleSim.data().sieges
 if defense<int(s.wall_threshold): return null
 return {"defense":defense,"siege_turns":siege_turns,"gates":[lanes/2]}
