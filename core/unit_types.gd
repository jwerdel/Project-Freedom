extends RefCounted
# Unit types (data/units/*.json) and armies (data/armies/*.json).
# A unit type names its visual by manifest ID plus an outfit, weapon loadout and visual_config;
# build_visual() turns that into a node through the asset manifest. Stats are placeholders.

const AssetManifest = preload("res://core/asset_manifest.gd")
const UNIT_DIR = "res://data/units/"
const ARMY_DIR = "res://data/armies/"
const REQUIRED = ["id","display_name","category","visual","outfit","loadout","card_portrait","placeholder_stats"]

static var _types = null

static func all() -> Dictionary:
 if _types == null:
  _types = {}
  for file in DirAccess.get_files_at(UNIT_DIR):
   if not file.ends_with(".json"): continue
   var unit = _read(UNIT_DIR+file)
   for key in REQUIRED: assert(unit.has(key),"%s: missing '%s'" % [file,key])
   assert(unit.id == file.get_basename(),"%s: id '%s' must match the file name" % [file,unit.id])
   _types[unit.id] = unit
 return _types

static func ids() -> Array:
 var out = all().keys()
 out.sort()
 return out

static func get_type(id: String) -> Dictionary:
 assert(all().has(id),"Unknown unit type '%s'" % id)
 return all()[id]

static func reset():
 _types = null

static func army(id: String) -> Dictionary:
 var data = _read(ARMY_DIR+id+".json")
 assert(data.has("commander") and data.has("units"),"Army %s needs a commander and units" % id)
 for entry in [data.commander]+data.units: get_type(entry.unit)
 return data

# Instantiate a unit's visual under parent (so scenes that build in _ready can), then configure it.
static func build_visual(unit: Dictionary,parent: Node) -> Node3D:
 var node = AssetManifest.instantiate(unit.visual)
 parent.add_child(node)
 if node.has_method("configure"): node.configure(unit)
 return node

# Every manifest ID the unit's appearance depends on.
static func visual_ids(unit: Dictionary) -> Array:
 var out = [unit.visual]
 if unit.outfit != "": out.append(unit.outfit)
 out.append_array(unit.loadout)
 out.append_array(unit.get("visual_config",{}).get("hair",[]))
 return out

static func _read(path: String) -> Dictionary:
 var data = JSON.parse_string(FileAccess.get_file_as_string(path))
 assert(data is Dictionary,"Invalid JSON: "+path)
 return data
