extends GutTest
# Every ID in data/asset_manifest.json must resolve to a loadable visual scene,
# and settlement lookups must prefer a landmark's own stages over the generic ones.

const AssetManifest = preload("res://core/asset_manifest.gd")

func after_each():
 AssetManifest.reset()

func assert_loads_node3d(label: String, path: String):
 assert_true(ResourceLoader.exists(path),"%s: missing scene %s" % [label,path])
 var scene = load(path)
 assert_true(scene is PackedScene,"%s: %s is not a PackedScene" % [label,path])
 if scene is PackedScene:
  var node = scene.instantiate()
  assert_true(node is Node3D,"%s: root of %s is not a Node3D" % [label,path])
  node.free()

func test_manifest_is_not_empty():
 assert_gt(AssetManifest.visuals().size(),0,"Manifest lists no visuals")

func test_every_manifest_entry_loads():
 for id in AssetManifest.visuals():
  assert_loads_node3d(id,AssetManifest.scene_path(id))

func test_every_landmark_stage_loads():
 if AssetManifest.landmarks().is_empty():
  pass_test("No landmarks registered yet")
  return
 for settlement_id in AssetManifest.landmarks():
  for stage in range(1,AssetManifest.STAGES+1):
   assert_loads_node3d("%s stage %d" % [settlement_id,stage],AssetManifest.settlement_stage_path(settlement_id,stage))

# Test manifest: stand-in scenes play the part of a landmark's unique stages.
func landmark_manifest() -> Dictionary:
 var data = {"visuals":AssetManifest.visuals().duplicate(),"landmarks":{
  "crownhaven":{
   "stage_1":"res://visuals/settlements/fortress.tscn",
   "stage_2":"res://visuals/settlements/harbor.tscn",
   "stage_3":"res://visuals/settlements/village.tscn"},
  "half_built":{"stage_1":"res://visuals/settlements/fortress.tscn"}}}
 return data

func test_landmark_lookup_uses_its_own_stages():
 AssetManifest.use_data(landmark_manifest())
 assert_true(AssetManifest.is_landmark("crownhaven"))
 assert_eq(AssetManifest.settlement_stage_path("crownhaven",1),"res://visuals/settlements/fortress.tscn")
 assert_eq(AssetManifest.settlement_stage_path("crownhaven",2),"res://visuals/settlements/harbor.tscn")
 assert_eq(AssetManifest.settlement_stage_path("crownhaven",3),"res://visuals/settlements/village.tscn")
 var node = AssetManifest.instantiate_settlement("crownhaven",1)
 assert_eq(node.scene_file_path,"res://visuals/settlements/fortress.tscn")
 node.free()

func test_non_landmark_falls_back_to_generic_stages():
 AssetManifest.use_data(landmark_manifest())
 assert_false(AssetManifest.is_landmark("greyhaven"))
 for stage in range(1,AssetManifest.STAGES+1):
  assert_eq(AssetManifest.settlement_stage_path("greyhaven",stage),AssetManifest.scene_path("settlement.city.stage_%d" % stage))

func test_incomplete_landmark_reports_error_instead_of_falling_back():
 AssetManifest.use_data(landmark_manifest())
 assert_eq(AssetManifest.settlement_stage_path("half_built",2),"")
 assert_push_error("incomplete")

func test_a_registered_model_overrides_a_procedural_kit_piece():
 # Image-to-3D or hand-made models replace procedural pieces through the manifest alone.
 var data = JSON.parse_string(FileAccess.get_file_as_string(AssetManifest.PATH))
 data.visuals["kit.greek.temple"] = AssetManifest.scene_path("unit.commander")
 AssetManifest.use_data(data)
 var n = AssetManifest.instantiate("kit.greek.temple")
 add_child_autofree(n)
 assert_eq(n.scene_file_path,AssetManifest.scene_path("unit.commander"),"the registered scene wins")
 AssetManifest.reset()
 var p = AssetManifest.instantiate("kit.greek.temple")
 add_child_autofree(p)
 assert_eq(p.scene_file_path,"","without an entry the procedural builder builds it")
