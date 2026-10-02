extends GutTest
# Goldspire Rock (docs/archive/world-v1.md landmark #2) is registered in the manifest's landmark slot, and
# each of its three stage scenes loads, builds, and shows the features its stage calls for.

const AssetManifest = preload("res://core/asset_manifest.gd")
const ID = "goldspire_rock"

func after_each():
 AssetManifest.reset()

func build_stage(stage: int) -> Node3D:
 var node = AssetManifest.instantiate_settlement(ID,stage)
 add_child_autofree(node)
 node.build({})
 return node

func mines(node: Node3D) -> int:
 for f in node.get_meta("features"):
  if f.begins_with("mines:"): return int(f.get_slice(":",1))
 return 0

func test_registered_as_landmark_with_distinct_stages():
 assert_true(AssetManifest.is_landmark(ID))
 var paths = {}
 for stage in range(1,AssetManifest.STAGES+1):
  var path = AssetManifest.settlement_stage_path(ID,stage)
  assert_true(ResourceLoader.exists(path),"stage %d scene missing: %s" % [stage,path])
  paths[path] = true
 assert_eq(paths.size(),AssetManifest.STAGES,"each stage has its own scene")

func test_each_stage_loads_and_builds():
 for stage in range(1,AssetManifest.STAGES+1):
  var node = build_stage(stage)
  assert_eq(node.stage,stage)
  assert_eq(node.get_meta("stage"),stage)
  assert_gt(node.find_children("*","MeshInstance3D",true,false).size(),0,"stage %d built no meshes" % stage)

func test_stage_1_is_mines_and_a_summit_tower():
 var f = build_stage(1).get_meta("features")
 assert_has(f,"rock")
 assert_has(f,"summit_tower")
 for later in ["halls","harbor","walls","terraces"]: assert_does_not_have(f,later)

func test_stage_2_adds_carved_halls_harbor_and_walls():
 var f = build_stage(2).get_meta("features")
 for feature in ["halls","harbor","walls"]: assert_has(f,feature)
 assert_does_not_have(f,"terraces")

func test_stage_3_terraces_the_rock_face():
 var f = build_stage(3).get_meta("features")
 for feature in ["halls","harbor","walls","terraces","goldspire"]: assert_has(f,feature)

func test_mine_entrances_grow_with_each_stage():
 var counts = []
 for stage in range(1,AssetManifest.STAGES+1): counts.append(mines(build_stage(stage)))
 assert_gt(counts[0],0)
 assert_gt(counts[1],counts[0])
 assert_gt(counts[2],counts[1])
