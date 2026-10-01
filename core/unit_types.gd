extends RefCounted
# Unit types (data/units/*.json) and armies (data/armies/*.json).
# A unit type names its visual by manifest ID plus an outfit, weapon loadout and visual_config;
# build_visual() turns that into a node through the asset manifest. Stats are placeholders.

const AssetManifest = preload("res://core/asset_manifest.gd")
const UNIT_DIR = "res://data/units/"
const ARMY_DIR = "res://data/armies/"
const REQUIRED = ["id","display_name","category","visual","outfit","loadout","card_portrait","placeholder_stats","size","recruitment"]

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

# --- Card art override ------------------------------------------------------------
# Optional hand-made card art: the unit's "card_art" path if set, else assets/cards/<id>.png if
# that file exists. Without either, cards use the auto-rendered portrait (core/portrait_studio.gd).
# Files are cropped and downscaled to card size by scripts/fit_card_art.gd.
const CARD_ART_DIR = "res://assets/cards/"

static func card_art_path(unit: Dictionary) -> String:
 var path = str(unit.get("card_art",""))
 if path == "": path = CARD_ART_DIR+unit.id+".png"
 return path if ResourceLoader.exists(path) or FileAccess.file_exists(path) else ""

# The card art texture, or null to fall back to the portrait. Loads imported textures normally and
# reads not-yet-imported files straight from disk.
static func card_art(unit: Dictionary) -> Texture2D:
 var path = card_art_path(unit)
 if path == "": return null
 if ResourceLoader.exists(path):
  var tex = load(path)
  if tex is Texture2D: return tex
 var img = Image.load_from_file(ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path)
 return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
