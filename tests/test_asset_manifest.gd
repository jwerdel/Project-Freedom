extends GutTest
# Every ID in data/asset_manifest.json must resolve to a loadable visual scene.

const AssetManifest = preload("res://core/asset_manifest.gd")

func test_manifest_is_not_empty():
 assert_gt(AssetManifest.visuals().size(),0,"Manifest lists no visuals")

func test_every_manifest_entry_loads():
 for id in AssetManifest.visuals():
  var path = AssetManifest.scene_path(id)
  assert_true(ResourceLoader.exists(path),"%s: missing scene %s" % [id,path])
  var scene = load(path)
  assert_true(scene is PackedScene,"%s: %s is not a PackedScene" % [id,path])
  if scene is PackedScene:
   var node = scene.instantiate()
   assert_true(node is Node3D,"%s: root of %s is not a Node3D" % [id,path])
   node.free()
