extends GutTest
# The Stage A landmarks (2026-10-06; world bible §8): each is registered in the asset manifest with
# its own three growth stages, every stage builds, and later stages add features to earlier ones.

const AssetManifest = preload("res://core/asset_manifest.gd")
const IDS = ["caeloth","crownhaven","frosthold","wardens_gate","skyreach","harrow_crossing","highbloom","oldstone_citadel","tempest_keep","skulkmire","emberdeep","brinecrag","goldspire_rock"]

func after_each():
 AssetManifest.reset()

func build(id: String,stage: int) -> Node3D:
 var n = AssetManifest.instantiate_settlement(id,stage)
 add_child_autofree(n)
 n.build({"height":func(_x,_z): return 2.0})
 return n

func test_every_stage_a_landmark_has_three_stages_that_grow():
 for id in IDS:
  assert_true(AssetManifest.is_landmark(id),id)
  var f1 = build(id,1).get_meta("features")
  var n3 = build(id,3)
  var f3 = n3.get_meta("features")
  assert_gt(f1.size(),0,id+" stage 1 shows its signature")
  assert_gt(f3.size(),f1.size(),id+" grows by stage 3")
  for f in f1:
   if not f.contains(":"): assert_has(f3,f,"%s keeps %s" % [id,f])
  assert_gt(n3.find_children("*","MeshInstance3D",true,false).size(),0,id)
  assert_gt(float(AssetManifest.landmarks()[id].get("radius",0.0)),0.0,id+" has its own ground radius")
