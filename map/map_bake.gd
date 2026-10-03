extends RefCounted
# Reading and writing a map's build outputs (docs/map-pipeline-design.md §4.2).
#  - Gameplay bakes, committed with the map (baked/): the region-ID raster (regions.json + zstd
#    int32 regions.bin, read by core/world_map.gd) and the movement grid (movement.json + zstd
#    movement.bin: terrain bytes then road bytes, read by core/movement.gd).
#  - Render bakes, cached locally (user://map_cache/<map_id>/): the heightfield (float32) and the
#    terrain colour map (RGB8), keyed by the map's version and build stamp.
# Everything is a native buffer operation; nothing loops per cell here.

const MapRegistry = preload("res://core/map_registry.gd")
const CACHE = "user://map_cache/"

static func write_json(path: String,d: Dictionary):
 var f = FileAccess.open(path,FileAccess.WRITE)
 assert(f != null,"Cannot write "+path)
 f.store_string(JSON.stringify(d,"  ",false))

static func _write_zstd(path: String,bytes: PackedByteArray):
 var f = FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 assert(f != null,"Cannot write "+path)
 f.store_buffer(bytes)

static func _read_zstd(path: String,size: int) -> PackedByteArray:
 var f = FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 if f == null: return PackedByteArray()
 return f.get_buffer(size)

static func write_regions(dir: String,cell: float,origin: Vector2,cols: int,rows: int,ids: PackedInt32Array,names: Array):
 write_json(dir+"baked/regions.json",{"_note":"GENERATED region-ID raster meta (map/map_bake.gd); ids in regions.bin, 0 = no region, i = names[i-1].","cell":cell,"origin":[origin.x,origin.y],"cols":cols,"rows":rows,"names":names})
 _write_zstd(dir+"baked/regions.bin",ids.to_byte_array())

# classes: one byte per cell, an index into data/movement.json terrain (in its order).
static func write_movement(dir: String,cell: float,origin: Vector2,cols: int,rows: int,classes: PackedByteArray,road: PackedByteArray):
 var names = []
 var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/movement.json"))
 for t in d.terrain:
  if not t.begins_with("_"): names.append(t)
 assert(names == ["open","forest","hills","pass","settlement","mountain","water"],"data/movement.json terrain order changed: update the map generators' class indices")
 write_json(dir+"baked/movement.json",{"_note":"GENERATED movement grid meta (map/map_bake.gd); movement.bin holds the terrain bytes then the road bytes.","cell":cell,"origin":[origin.x,origin.y],"cols":cols,"rows":rows,"names":names})
 var both = classes.duplicate()
 both.append_array(road)
 _write_zstd(dir+"baked/movement.bin",both)

static func cache_dir(map_id: String) -> String:
 return CACHE+map_id+"/"

# The render cache is valid for one build of one map version (stamp written by the build).
static func write_render_cache(map_id: String,cell: float,origin: Vector2,cols: int,rows: int,heights: PackedFloat32Array,colors: PackedByteArray):
 var dir = cache_dir(map_id)
 DirAccess.make_dir_recursive_absolute(dir)
 _write_zstd(dir+"heights.bin",heights.to_byte_array())
 _write_zstd(dir+"colors.bin",colors)
 write_json(dir+"meta.json",{"map_version":MapRegistry.version(map_id),"cell":cell,"origin":[origin.x,origin.y],"cols":cols,"rows":rows,"stamp":stamp(map_id)})

# Changes whenever the committed bakes change (their meta files' modification times and sizes).
static func stamp(map_id: String) -> String:
 var p = MapRegistry.path("baked/movement.bin",map_id)
 return "%d:%d" % [FileAccess.get_modified_time(p),FileAccess.get_file_as_bytes(p).size()]

# {cell, origin, cols, rows, heights: Image (FORMAT_RF), colors: Image (FORMAT_RGB8)} or {} when the
# cache is missing or stale (the map then has to be rebuilt: scripts/build_map.gd).
static func load_render_cache(map_id: String) -> Dictionary:
 var dir = cache_dir(map_id)
 if not FileAccess.file_exists(dir+"meta.json"): return {}
 var meta = JSON.parse_string(FileAccess.get_file_as_string(dir+"meta.json"))
 if int(meta.map_version) != MapRegistry.version(map_id) or str(meta.stamp) != stamp(map_id): return {}
 var cols = int(meta.cols)
 var rows = int(meta.rows)
 var h = _read_zstd(dir+"heights.bin",cols*rows*4)
 var c = _read_zstd(dir+"colors.bin",cols*rows*3)
 if h.size() != cols*rows*4 or c.size() != cols*rows*3: return {}
 return {"cell":float(meta.cell),"origin":Vector2(meta.origin[0],meta.origin[1]),"cols":cols,"rows":rows,
  "heights":Image.create_from_data(cols,rows,false,Image.FORMAT_RF,h),"colors":Image.create_from_data(cols,rows,false,Image.FORMAT_RGB8,c)}
