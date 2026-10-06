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

func tiers(node: Node3D) -> int:
 for f in node.get_meta("features"):
  if f.begins_with("tiers:"): return int(f.get_slice(":",1))
 return 0

func test_stage_1_is_the_sheer_cliff_gate_mines_and_a_summit_spire():
 var f = build_stage(1).get_meta("features")
 for feature in ["cliff","gate","summit_spire","greek_city"]: assert_has(f,feature)
 for later in ["harbor","walls","towers","statue"]: assert_does_not_have(f,later)
 assert_eq(tiers(build_stage(1)),0)

func test_stage_2_carves_the_lower_tiers_and_adds_harbor_and_walls():
 var node = build_stage(2)
 var f = node.get_meta("features")
 for feature in ["harbor","walls"]: assert_has(f,feature)
 assert_eq(tiers(node),2)
 assert_does_not_have(f,"statue")

func test_stage_3_carves_every_tier_with_towers_statue_and_spires():
 var node = build_stage(3)
 var f = node.get_meta("features")
 for feature in ["harbor","walls","towers","statue","theatre","goldspire"]: assert_has(f,feature)
 assert_gt(tiers(node),tiers(build_stage(2)))

func test_the_sea_face_is_sheer_not_a_cone():
 # The cliff barely leans back on the sea side; the land side slopes.
 var node = build_stage(1)
 var sea_low = node._radius(PI*0.5,2.0)
 var sea_high = node._radius(PI*0.5,node.H*0.9)
 assert_gt(sea_high,sea_low*0.85,"the sea face stays near-vertical")
 var land_low = node._radius(-PI*0.5,2.0)
 var land_high = node._radius(-PI*0.5,node.H*0.9)
 assert_lt(land_high,land_low*0.7,"the land side slopes back")

func test_mine_entrances_grow_with_each_stage():
 var counts = []
 for stage in range(1,AssetManifest.STAGES+1): counts.append(mines(build_stage(stage)))
 assert_gt(counts[0],0)
 assert_gt(counts[1],counts[0])
 assert_gt(counts[2],counts[1])
