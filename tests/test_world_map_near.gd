extends GutTest
# WorldMap.settlements_near: a wide radius scans the settlements instead of thousands of 32 m buckets
# (AI war range, muster notice) and must give the bucket walk's exact result and order.

const MapRegistry = preload("res://core/map_registry.gd")
const WorldMap = preload("res://core/world_map.gd")

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_wide_radius_matches_the_bucket_walk():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 WorldMap.settlement_ids()
 var rng = RandomNumberGenerator.new()
 rng.seed = 7
 var size = Vector2(MapRegistry.meta().size[0],MapRegistry.meta().size[1])
 for i in 60:
  var p = Vector2(rng.randf()*size.x,rng.randf()*size.y)
  var r = [300.0,1400.0,3000.0][i%3]
  var walk = []
  var lo = Vector2i(((p-Vector2.ONE*r)/WorldMap.BUCKET).floor())
  var hi = Vector2i(((p+Vector2.ONE*r)/WorldMap.BUCKET).floor())
  for bz in range(lo.y,hi.y+1):
   for bx in range(lo.x,hi.x+1):
    for id in WorldMap._buckets.get(Vector2i(bx,bz),[]):
     if WorldMap._positions[id].distance_to(p)<=r: walk.append(id)
  assert_eq(WorldMap.settlements_near(p,r),walk)
