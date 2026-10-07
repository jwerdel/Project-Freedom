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
 assert(names == ["open","forest","hills","pass","settlement","mountain","water","marsh"],"data/movement.json terrain order changed: update the map generators' class indices")
 write_json(dir+"baked/movement.json",{"_note":"GENERATED movement grid meta (map/map_bake.gd); movement.bin holds the terrain bytes then the road bytes.","cell":cell,"origin":[origin.x,origin.y],"cols":cols,"rows":rows,"names":names})
 var both = classes.duplicate()
 both.append_array(road)
 _write_zstd(dir+"baked/movement.bin",both)
 var runs = runs_of(classes,road,cols,rows)
 write_runs(dir,runs)
 var meta = JSON.parse_string(FileAccess.get_file_as_string(dir+"baked/movement.json"))
 meta.runs = runs.size()/4
 write_json(dir+"baked/movement.json",meta)

# The committed movement grid: {cols, rows, classes, road} (bytes per cell), or {} when missing.
static func read_movement(dir: String) -> Dictionary:
 if not FileAccess.file_exists(dir+"baked/movement.json"): return {}
 var meta = JSON.parse_string(FileAccess.get_file_as_string(dir+"baked/movement.json"))
 var n = int(meta.cols)*int(meta.rows)
 var raw = _read_zstd(dir+"baked/movement.bin",2*n)
 if raw.size() != 2*n: return {}
 return {"cols":int(meta.cols),"rows":int(meta.rows),"classes":raw.slice(0,n),"road":raw.slice(n)}

static func cache_dir(map_id: String) -> String:
 return CACHE+map_id+"/"

# The render cache is valid for one build of one map version (stamp written by the build).
# Bump CACHE_FORMAT when the render cache gains or changes a file: older caches then count as stale
# and are rebuilt on the next start (the first-run preparation screen).
const CACHE_FORMAT = 4 # 2: climate looks (2026-10-06); 3: their values retuned; 4: marsh ground (2026-10-07)

static func write_render_cache(map_id: String,cell: float,origin: Vector2,cols: int,rows: int,heights: PackedFloat32Array,colors: PackedByteArray,rivers := PackedByteArray(),climate := PackedByteArray(),ccols := 0,crows := 0):
 var dir = cache_dir(map_id)
 DirAccess.make_dir_recursive_absolute(dir)
 _write_zstd(dir+"heights.bin",heights.to_byte_array())
 _write_zstd(dir+"colors.bin",colors)
 if rivers.size() == cols*rows: _write_zstd(dir+"rivers.bin",rivers) # river strength per cell (0-255), drawn as water
 elif FileAccess.file_exists(dir+"rivers.bin"): DirAccess.remove_absolute(dir+"rivers.bin")
 if climate.size() == ccols*crows*4 and ccols>0: _write_zstd(dir+"climate.bin",climate) # climate looks per coarse texel (RGBA: snow, frost, dry, wet)
 elif FileAccess.file_exists(dir+"climate.bin"): DirAccess.remove_absolute(dir+"climate.bin")
 write_json(dir+"meta.json",{"map_version":MapRegistry.version(map_id),"cell":cell,"origin":[origin.x,origin.y],"cols":cols,"rows":rows,"stamp":stamp(map_id),"format":CACHE_FORMAT,"climate_size":[ccols,crows]})

# Changes whenever the committed bakes change (their meta files' modification times and sizes).
static func stamp(map_id: String) -> String:
 var p = MapRegistry.path("baked/movement.bin",map_id)
 return "%d:%d" % [FileAccess.get_modified_time(p),FileAccess.get_file_as_bytes(p).size()]

# {cell, origin, cols, rows, heights: Image (FORMAT_RF), colors: Image (FORMAT_RGB8)} or {} when the
# cache is missing or stale (the map then has to be rebuilt: scripts/build_map.gd).
# True when the local render cache matches the map's current build (cheap: only its meta).
static func render_cache_valid(map_id: String) -> bool:
 var dir = cache_dir(map_id)
 if not FileAccess.file_exists(dir+"meta.json"): return false
 var meta = JSON.parse_string(FileAccess.get_file_as_string(dir+"meta.json"))
 return meta is Dictionary and int(meta.map_version) == MapRegistry.version(map_id) and str(meta.stamp) == stamp(map_id) and int(meta.get("format",1)) == CACHE_FORMAT

static func load_render_cache(map_id: String) -> Dictionary:
 var dir = cache_dir(map_id)
 if not FileAccess.file_exists(dir+"meta.json"): return {}
 var meta = JSON.parse_string(FileAccess.get_file_as_string(dir+"meta.json"))
 if int(meta.map_version) != MapRegistry.version(map_id) or str(meta.stamp) != stamp(map_id) or int(meta.get("format",1)) != CACHE_FORMAT: return {}
 var cols = int(meta.cols)
 var rows = int(meta.rows)
 var h = _read_zstd(dir+"heights.bin",cols*rows*4)
 var c = _read_zstd(dir+"colors.bin",cols*rows*3)
 if h.size() != cols*rows*4 or c.size() != cols*rows*3: return {}
 var rv = _read_zstd(dir+"rivers.bin",cols*rows) if FileAccess.file_exists(dir+"rivers.bin") else PackedByteArray()
 if rv.size() != cols*rows:
  rv = PackedByteArray()
  rv.resize(cols*rows)
 var cs = meta.get("climate_size",[0,0])
 var climate: Image = null
 if int(cs[0])>0 and FileAccess.file_exists(dir+"climate.bin"):
  var cb = _read_zstd(dir+"climate.bin",int(cs[0])*int(cs[1])*4)
  if cb.size() == int(cs[0])*int(cs[1])*4: climate = Image.create_from_data(int(cs[0]),int(cs[1]),false,Image.FORMAT_RGBA8,cb)
 return {"cell":float(meta.cell),"origin":Vector2(meta.origin[0],meta.origin[1]),"cols":cols,"rows":rows,"climate":climate,
  "heights":Image.create_from_data(cols,rows,false,Image.FORMAT_RF,h),"colors":Image.create_from_data(cols,rows,false,Image.FORMAT_RGB8,c),
  "rivers":Image.create_from_data(cols,rows,false,Image.FORMAT_R8,rv)}

# Row runs of identical cells, for building the pathfinding grid in bulk (core/movement.gd): quads
# (x0, z, length, code) with code = terrain index + 16 * road. Computed once per map (at build time
# for pipeline maps, baked/movement_runs.bin; at load for the small test map).
static func runs_of(classes: PackedByteArray,road: PackedByteArray,cols: int,rows: int) -> PackedInt32Array:
 var out = PackedInt32Array()
 for z in rows:
  var row = z*cols
  var x0 = 0
  var code = classes[row]+16*road[row]
  for x in range(1,cols):
   var c = classes[row+x]+16*road[row+x]
   if c != code:
    out.append_array([x0,z,x-x0,code])
    x0 = x
    code = c
  out.append_array([x0,z,cols-x0,code])
 return out

static func write_runs(dir: String,runs: PackedInt32Array):
 _write_zstd(dir+"baked/movement_runs.bin",runs.to_byte_array())

static func read_runs(dir: String,count: int) -> PackedInt32Array:
 return _read_zstd(dir+"baked/movement_runs.bin",count*16).to_int32_array()

# Region graph for hierarchical paths (core/movement.gd): edges [a, b, crossing cell index] between
# regions (indices into baked/regions.json names) that share a passable border.
static func write_graph(dir: String,edges: Array):
 write_json(dir+"baked/graph.json",{"_note":"GENERATED region graph (map/map_bake.gd): edges [region a, region b, crossing cell] with region indices into baked/regions.json names.","edges":edges})

# Connected components of passable land (terrain classes other than mountain and water), for an
# instant "no route" when start and goal lie in different components: int32 per cell, 0 =
# impassable. Movement through blocked cells (armies, settlements) is not considered here.
static func components_of(classes: PackedByteArray,cols: int,rows: int) -> PackedInt32Array:
 var n = cols*rows
 var comp = PackedInt32Array()
 comp.resize(n)
 var queue = PackedInt32Array()
 queue.resize(n)
 var label = 0
 for s in n:
  if comp[s] != 0 or (classes[s] == 5 or classes[s] == 6): continue # 5 mountain, 6 water (data/movement.json order; 7 marsh is passable)
  label += 1
  comp[s] = label
  var head = 0
  var tail = 1
  queue[0] = s
  while head<tail:
   var i = queue[head]
   head += 1
   var x = i%cols
   if x>0 and comp[i-1] == 0 and (classes[i-1]<5 or classes[i-1]>6):
    comp[i-1] = label
    queue[tail] = i-1
    tail += 1
   if x<cols-1 and comp[i+1] == 0 and (classes[i+1]<5 or classes[i+1]>6):
    comp[i+1] = label
    queue[tail] = i+1
    tail += 1
   if i>=cols and comp[i-cols] == 0 and (classes[i-cols]<5 or classes[i-cols]>6):
    comp[i-cols] = label
    queue[tail] = i-cols
    tail += 1
   if i<n-cols and comp[i+cols] == 0 and (classes[i+cols]<5 or classes[i+cols]>6):
    comp[i+cols] = label
    queue[tail] = i+cols
    tail += 1
 return comp

static func write_components(dir: String,comp: PackedInt32Array):
 _write_zstd(dir+"baked/components.bin",comp.to_byte_array())

static func read_components(dir: String,count: int) -> PackedInt32Array:
 return _read_zstd(dir+"baked/components.bin",count*4).to_int32_array()

# Region parts (core/path_hierarchy.gd): connected passable areas within one region (a ridge can
# cut a region in two). int32 per cell, 0 = impassable or outside every region.
static func parts_of(classes: PackedByteArray,rid: PackedInt32Array,cols: int,rows: int) -> PackedInt32Array:
 var n = cols*rows
 var part = PackedInt32Array()
 part.resize(n)
 var queue = PackedInt32Array()
 queue.resize(n)
 var label = 0
 for s in n:
  if part[s] != 0 or (classes[s] == 5 or classes[s] == 6) or rid[s] == 0: continue
  label += 1
  part[s] = label
  var r = rid[s]
  var head = 0
  var tail = 1
  queue[0] = s
  while head<tail:
   var i = queue[head]
   head += 1
   var x = i%cols
   if x>0 and part[i-1] == 0 and (classes[i-1]<5 or classes[i-1]>6) and rid[i-1] == r:
    part[i-1] = label
    queue[tail] = i-1
    tail += 1
   if x<cols-1 and part[i+1] == 0 and (classes[i+1]<5 or classes[i+1]>6) and rid[i+1] == r:
    part[i+1] = label
    queue[tail] = i+1
    tail += 1
   if i>=cols and part[i-cols] == 0 and (classes[i-cols]<5 or classes[i-cols]>6) and rid[i-cols] == r:
    part[i-cols] = label
    queue[tail] = i-cols
    tail += 1
   if i<n-cols and part[i+cols] == 0 and (classes[i+cols]<5 or classes[i+cols]>6) and rid[i+cols] == r:
    part[i+cols] = label
    queue[tail] = i+cols
    tail += 1
 return part

static func write_parts(dir: String,parts: PackedInt32Array):
 _write_zstd(dir+"baked/parts.bin",parts.to_byte_array())

static func read_parts(dir: String,count: int) -> PackedInt32Array:
 return _read_zstd(dir+"baked/parts.bin",count*4).to_int32_array()
