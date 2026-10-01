extends RefCounted
# Provinces, regions and factions of the map (data/provinces.json, data/factions.json).
# Regions tile the map; each settled region holds one settlement whose ID is the region ID.

const PROVINCES = "res://data/provinces.json"
const FACTIONS = "res://data/factions.json"

static var _provinces = null
static var _factions = null

static func _load():
 if _provinces != null: return
 var p = JSON.parse_string(FileAccess.get_file_as_string(PROVINCES))
 var f = JSON.parse_string(FileAccess.get_file_as_string(FACTIONS))
 assert(p is Dictionary and p.has("provinces") and p.has("regions"),"Invalid "+PROVINCES)
 assert(f is Dictionary and f.has("factions"),"Invalid "+FACTIONS)
 _provinces = p
 _factions = f.factions
 for region_id in p.regions:
  var r = p.regions[region_id]
  var poly = PackedVector2Array()
  for v in r.polygon: poly.append(Vector2(v[0],v[1]))
  r.points = poly
  assert(r.owner == "" or _factions.has(r.owner),"Region %s: unknown owner %s" % [region_id,r.owner])

static func reset():
 _provinces = null
 _factions = null

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

# Region containing a world x/z point, or "" outside the map.
static func region_at(p: Vector2) -> String:
 for id in regions():
  if Geometry2D.is_point_in_polygon(p,regions()[id].points): return id
 return ""

static func province_of(region_id: String) -> String:
 for p in provinces():
  if region_id in p.regions: return p.id
 return ""

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
