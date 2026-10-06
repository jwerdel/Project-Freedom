extends RefCounted
# Maps unit / building / road IDs to visual scene paths (data/asset_manifest.json).
# Gameplay code asks for an ID; swapping art means editing the manifest or the visual scene only.
#
# Landmarks: a specific settlement ID may map to its own unique visual scenes, one per growth
# stage ("landmarks": {"<settlement_id>": {"stage_1": path, "stage_2": path, "stage_3": path}}).
# Settlements without a landmark entry fall back to the generic "<generic>.stage_N" visuals.

const PATH = "res://data/asset_manifest.json"
const STAGES = 3

static var _data = null

static func _manifest() -> Dictionary:
 if _data == null:
  var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
  assert(data is Dictionary and data.has("visuals"),"Invalid asset manifest: "+PATH)
  use_data(data)
 return _data

# Replace the loaded manifest (tests use this); reset() reloads from PATH on next access.
static func use_data(data: Dictionary):
 _data = data.duplicate(true)
 if not _data.has("landmarks"): _data.landmarks = {}

static func reset():
 _data = null

static func visuals() -> Dictionary:
 return _manifest().visuals

static func landmarks() -> Dictionary:
 return _manifest().landmarks

# Procedural visuals: an id starting with a prefix in the manifest's "procedural" section is built
# by that builder script's build_id(id) (culture kits: visuals/kits/cultures/culture_kit.gd).
static func procedural_builder(id: String) -> String:
 var p = _manifest().get("procedural",{})
 for prefix in p:
  if not prefix.begins_with("_") and id.begins_with(prefix): return p[prefix]
 return ""

static func has(id: String) -> bool:
 return visuals().has(id) or procedural_builder(id) != ""

static func scene_path(id: String) -> String:
 var path = visuals().get(id,"")
 assert(path != "","No visual registered for '%s' in %s" % [id,PATH])
 return path

# An exact "visuals" entry wins over a procedural builder: a hand-made or generated model (for
# example an image-to-3D signature building, wrapped in its own visual scene) replaces a procedural
# kit piece by adding "kit.<culture>.<piece>": "res://visuals/...tscn" to the manifest; no code changes.
static func instantiate(id: String) -> Node3D:
 if visuals().has(id): return load(scene_path(id)).instantiate()
 var builder = procedural_builder(id)
 if builder != "": return load(builder).build_id(id)
 return load(scene_path(id)).instantiate()

static func is_landmark(settlement_id: String) -> bool:
 return landmarks().has(settlement_id)

# Scene path for a settlement at a growth stage (1..3): its landmark scene if it has one,
# otherwise the generic stage visual. A landmark must define all three stages.
static func settlement_stage_path(settlement_id: String, stage: int, generic := "settlement.city") -> String:
 if stage < 1 or stage > STAGES:
  push_error("Settlement stage %d out of range 1..%d" % [stage,STAGES])
  return ""
 if is_landmark(settlement_id):
  var path = landmarks()[settlement_id].get("stage_%d" % stage,"")
  if path == "":
   push_error("Landmark '%s' is incomplete: no stage_%d in %s" % [settlement_id,stage,PATH])
  return path
 return scene_path("%s.stage_%d" % [generic,stage])

static func instantiate_settlement(settlement_id: String, stage: int, generic := "settlement.city") -> Node3D:
 return load(settlement_stage_path(settlement_id,stage,generic)).instantiate()
