extends GutTest
# The synthetic map's relief (map/synthetic.gd, owner 2026-10-04: TW:WH3-like terrain): broad massifs
# rising well above the plains, pass valleys through them, and rivers draining all the way to the sea.

const Synthetic = preload("res://map/synthetic.gd")

var relief = null
const W = 352
const H = 224

func before_all():
 var land = PackedFloat32Array()
 land.resize(W*H)
 for z in H:
  for x in W:
   var u = Vector2(float(x)/W-0.5,float(z)/H-0.5)
   land[z*W+x] = 0.42-u.length() # one island
 relief = Synthetic._relief(600,land,W,H,8.0)
 relief.land = land

func test_massifs_rise_above_the_plains_with_wide_bases():
 var hi = 0.0
 var mountain = 0
 var foothill = 0
 for i in W*H:
  if relief.land[i]<0.0: continue
  hi = maxf(hi,relief.heights[i])
  if relief.heights[i]>Synthetic.MOUNTAIN_ABOVE: mountain += 1
  elif relief.heights[i]>Synthetic.HILLS_ABOVE: foothill += 1
 assert_gt(hi,Synthetic.MOUNTAIN_ABOVE+5.0,"peaks well above the plains (even on a small island)")
 assert_gt(mountain,0)
 assert_gt(foothill,mountain/2,"wide bases: the hills around a range are not a thin wall")

func test_thermal_erosion_limits_slopes():
 var steep = 0
 var land = 0
 for z in range(1,H-1):
  for x in range(1,W-1):
   var i = z*W+x
   if relief.land[i]<0.0: continue
   land += 1
   if absf(relief.heights[i]-relief.heights[i+1])>Synthetic.TALUS*8.0*2.0: steep += 1
 assert_lt(float(steep)/land,0.01,"almost no cliffs steeper than twice the talus")

func test_rivers_reach_the_sea():
 var cells = 0
 var mouths = 0
 for z in range(1,H-1):
  for x in range(1,W-1):
   var i = z*W+x
   if relief.rivers[i]<0.5 or relief.land[i]<0.0: continue
   cells += 1
   for j in [i-1,i+1,i-W,i+W]:
    if relief.land[j]<0.0: mouths += 1
 assert_gt(cells,50,"a river network")
 assert_gt(mouths,0,"rivers end at the coast")
