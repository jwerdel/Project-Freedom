extends RefCounted
# Maps unit / building / road IDs to visual scene paths (data/asset_manifest.json).
# Gameplay code asks for an ID; swapping art means editing the manifest or the visual scene only.

const PATH = "res://data/asset_manifest.json"

static var _visuals = null

static func visuals() -> Dictionary:
 if _visuals == null:
  var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
  assert(data is Dictionary and data.has("visuals"),"Invalid asset manifest: "+PATH)
  _visuals = data.visuals
 return _visuals

static func scene_path(id: String) -> String:
 var path = visuals().get(id,"")
 assert(path != "","No visual registered for '%s' in %s" % [id,PATH])
 return path

static func instantiate(id: String) -> Node3D:
 return load(scene_path(id)).instantiate()
