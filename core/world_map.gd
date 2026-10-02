extends RefCounted
# Provinces, regions and factions of the active map (data/maps/<id>/provinces.json and
# factions.json, core/map_registry.gd). Regions tile the map; each settled region holds one
# settlement whose ID is the region ID. Maps built by the pipeline also have a region-ID raster
# (baked/regions.png), which makes region_at a lookup instead of a polygon search.

const MapRegistry = preload("res://core/map_registry.gd")

static var _provinces = null
static var _factions = null
static var _map := ""
static var _province_of = {} # region id -> province id
static var _raster = null     # {cell, origin, cols, rows, ids: PackedInt32Array, names: [region ids]} or null

static func _load():
 if _provinces != null and _map == MapRegistry.active: return
 _map = MapRegistry.active
 var pf = MapRegistry.path("provinces.json")
 var ff = MapRegistry.path("factions.json")
 var p = JSON.parse_string(FileAccess.get_file_as_string(pf))
 var f = JSON.parse_string(FileAccess.get_file_as_string(ff))
 assert(p is Dictionary and p.has("provinces") and p.has("regions"),"Invalid "+pf)
 assert(f is Dictionary and f.has("factions"),"Invalid "+ff)
 _provinces = p
 _factions = f.factions
 for region_id in p.regions:
  var r = p.regions[region_id]
  var poly = PackedVector2Array()
  for v in r.polygon: poly.append(Vector2(v[0],v[1]))
  r.points = poly
  assert(r.owner == "" or _factions.has(r.owner),"Region %s: unknown owner %s" % [region_id,r.owner])
 _province_of = {}
 for prov in p.provinces:
  for rid in prov.regions: _province_of[rid] = prov.id
 _raster = _load_raster()

static func reset():
 _provinces = null
 _factions = null
 _map = ""
 _raster = null

static func provinces() -> Array:
 _load()
 return _provinces.provinces

static func province(id: String) -> Dictionary:
 for p in provinces():
  if p.id == id: return p
 return {}

static func regions() -> Dictionary:
 _load()
 return _provinces.regions

static func region(id: String) -> Dictionary:
 return regions().get(id,{})

static func factions() -> Dictionary:
 _load()
 return _factions

static func faction(id: String) -> Dictionary:
 return factions().get(id,{})

# Region containing a world x/z point, or "" outside the map. With a baked raster this is one
# lookup; otherwise a search over the region polygons (the test map, four regions).
static func region_at(p: Vector2) -> String:
 _load()
 if _raster != null:
  var x = floori((p.x-_raster.origin.x)/_raster.cell)
  var z = floori((p.y-_raster.origin.y)/_raster.cell)
  if x<0 or z<0 or x>=_raster.cols or z>=_raster.rows: return ""
  var i = _raster.ids[z*_raster.cols+x]
  return _raster.names[i-1] if i>0 else ""
 for id in regions():
  if Geometry2D.is_point_in_polygon(p,regions()[id].points): return id
 return ""

static func province_of(region_id: String) -> String:
 _load()
 return _province_of.get(region_id,"")

static func owner_of(region_id: String) -> String:
 return region(region_id).get("owner","")

static func settlement_ids() -> Array:
 var out = []
 for id in regions():
  if regions()[id].settlement != null: out.append(id)
 return out

static func settlements_in(province_id: String) -> Array:
 var out = []
 for id in province(province_id).get("regions",[]):
  if region(id).settlement != null: out.append(id)
 return out

static func settlement_position(region_id: String) -> Vector2:
 var pos = region(region_id).settlement.position
 return Vector2(pos[0],pos[1])

# The region-ID raster of a pipeline map, or null. baked/regions.bin: zstd-compressed little-endian
# int32 ids, row by row (0 = no region, i = names[i-1]); baked/regions.json: {cell, origin, cols,
# rows, names}. Decoded natively (no per-cell script loop), so even a 2048 x 1280 raster loads fast.
static func _load_raster():
 if not MapRegistry.has_file("baked/regions.json"): return null
 var meta = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("baked/regions.json")))
 var f = FileAccess.open_compressed(MapRegistry.path("baked/regions.bin"),FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 assert(f != null,"Missing "+MapRegistry.path("baked/regions.bin"))
 var ids = f.get_buffer(int(meta.cols)*int(meta.rows)*4).to_int32_array()
 return {"cell":float(meta.cell),"origin":Vector2(meta.origin[0],meta.origin[1]),"cols":int(meta.cols),"rows":int(meta.rows),"ids":ids,"names":meta.names}
