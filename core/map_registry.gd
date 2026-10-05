extends RefCounted
# The active campaign map (docs/map-pipeline-design.md §3, §7): every map lives in its own folder
# data/maps/<map_id>/ with map.json (id, version, size), the world files (provinces.json,
# factions.json, campaign_start.json, armies/) and either a hand-baked movement grid (the test map's
# movement_grid.json) or the pipeline's committed bakes in baked/. Loaders (core/world_map.gd,
# core/movement.gd, core/unit_types.gd, core/game_state.gd) read paths from here and reload when
# the active map changes, so tests and saves can switch maps.

const ROOT = "res://data/maps/"
const DEFAULT = "testmap_pipeline" # tests, the self-test, captures and New Campaign until Varos exists (the test map built by the pipeline)

static var active := DEFAULT
static var _meta = {}

static func set_active(map_id: String):
 assert(DirAccess.dir_exists_absolute(ROOT+map_id),"Unknown map: "+map_id)
 active = map_id

static func dir(map_id := "") -> String:
 return ROOT+(map_id if map_id != "" else active)+"/"

static func path(file: String,map_id := "") -> String:
 return dir(map_id)+file

static func has_file(file: String,map_id := "") -> bool:
 return FileAccess.file_exists(path(file,map_id))

# map.json of a map: {id, version, size [x, z], origin [x, z], cell, ...}.
static func meta(map_id := "") -> Dictionary:
 var id = map_id if map_id != "" else active
 if not _meta.has(id):
  var d = JSON.parse_string(FileAccess.get_file_as_string(path("map.json",id)))
  assert(d is Dictionary and d.has("id") and d.has("version"),"Invalid map.json for "+id)
  _meta[id] = d
 return _meta[id]

static func version(map_id := "") -> int:
 return int(meta(map_id).version)

# Every map folder (sorted).
static func maps() -> Array:
 var out = []
 for d in DirAccess.get_directories_at(ROOT): if FileAccess.file_exists(ROOT+d+"/map.json"): out.append(d)
 out.sort()
 return out

static func reset():
 _meta = {}
