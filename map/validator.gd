extends RefCounted
# Map validator (docs/map-pipeline-design.md §5.1): runs on a map's committed data and bakes and
# reports problems; errors fail the build, warnings are listed. Each problem: {"check", "level"
# ("error" or "warning"), "message", "pos" (world Vector2, or null)} so the debug overlay can mark it.
# Checks that need systems not built yet (sea graph and port anchors, the Greywall, start positions
# against the world bible, minor factions, names by culture) report as skipped in the summary.

const MapRegistry = preload("res://core/map_registry.gd")
const MapBake = preload("res://map/map_bake.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const Sketch = preload("res://map/sketch.gd")
const MAJOR_TYPES = ["city","fortress"]

const MAX_SLOPE = 0.6     # rise per metre under a settlement
const SKIPPED = ["sea graph and port anchors","Greywall continuity","start positions against the world bible","minor factions near majors","names by culture"]

# overrides (tests): "provinces", "factions" or "meta" dictionaries used instead of the map's files.
static func validate(map_id: String,overrides := {}) -> Dictionary:
 var out = {"map":map_id,"problems":[],"skipped":SKIPPED}
 var meta = overrides.get("meta",MapRegistry.meta(map_id))
 var dir = MapRegistry.dir(map_id)
 var add = func(check: String,level: String,msg: String,pos = null): out.problems.append({"check":check,"level":level,"message":msg,"pos":pos})
 var prov = overrides.get("provinces",JSON.parse_string(FileAccess.get_file_as_string(dir+"provinces.json")) if FileAccess.file_exists(dir+"provinces.json") else null)
 if prov == null:
  add.call("files","error","provinces.json missing or invalid")
  return _summary(out)
 var factions = overrides.get("factions",JSON.parse_string(FileAccess.get_file_as_string(dir+"factions.json")) if FileAccess.file_exists(dir+"factions.json") else {"factions":{}})
 var regions: Dictionary = prov.regions
 var legacy = bool(meta.get("allow_legacy_majors",false)) or str(meta.get("kind","")) == "legacy"
 # --- IDs and references ----------------------------------------------------------------------
 var seen = {}
 for p in prov.provinces:
  if seen.has(p.id): add.call("ids","error","duplicate id '%s'" % p.id)
  seen[p.id] = true
  for r in p.regions:
   if not regions.has(r): add.call("ids","error","province %s lists unknown region '%s'" % [p.id,r])
  if str(p.get("capital","")) != "" and not p.capital in p.regions: add.call("ids","error","province %s capital '%s' is not one of its regions" % [p.id,p.capital])
 var in_province = {}
 for p in prov.provinces:
  for r in p.regions:
   if in_province.has(r): add.call("ids","error","region '%s' is in two provinces" % r)
   in_province[r] = p.id
 for r in regions:
  if not in_province.has(r): add.call("ids","error","region '%s' is in no province" % r)
  var owner = str(regions[r].get("owner",""))
  if owner != "" and not factions.factions.has(owner): add.call("ids","error","region %s owner '%s' is not a faction" % [r,owner])
 if MapRegistry.has_file("sketch.svg",map_id):
  var sk = Sketch.parse_file(dir+"sketch.svg")
  for e in sk.errors: add.call("sketch","error",e)
  var sites = {}
  for e in sk.layers.get("sites",[]): sites[e.id] = true
  for r in regions:
   if regions[r].get("settlement") != null and not sites.has(r): add.call("ids","error","region %s has a settlement but no site in sketch.svg" % r)
  for s in sites:
   if not regions.has(s): add.call("ids","error","site '%s' in sketch.svg is not a region" % s)
 # --- Settlements --------------------------------------------------------------------------------
 var majors = []
 for r in regions:
  var s = regions[r].get("settlement")
  if s == null:
   if str(regions[r].get("owner","")) != "": add.call("majors","error","settled region %s (owned) has no major settlement" % r)
   continue
  var pos = Vector2(s.position[0],s.position[1])
  majors.append([r,pos,str(s.type)])
  if not legacy and not str(s.type) in MAJOR_TYPES: add.call("majors","error","%s: major settlement type '%s' (must be city or fortress)" % [r,s.type],pos)
  var lmv = s.get("landmark","")
  var lm = r if lmv is bool and lmv else str(lmv) # legacy maps flag it with true
  if lm != "" or AssetManifest.is_landmark(r):
   var lid = lm if lm != "" else r
   for st in range(1,4):
    if not AssetManifest.landmarks().has(lid) or AssetManifest.landmarks()[lid].get("stage_%d" % st,"") == "": add.call("landmarks","error","landmark %s has no stage_%d in the asset manifest" % [lid,st],pos)
 # No-overlap rule: settlement footprints (data/settlement_sprawl.json "footprint": the sprawl at max
 # level plus a countryside ring) must not touch.
 var fp = JSON.parse_string(FileAccess.get_file_as_string("res://data/settlement_sprawl.json")).footprint
 var reach = func(t: String) -> float: return float(fp.radius.get(t,fp.radius.city))+float(fp.countryside)
 for i in majors.size():
  for j in range(i+1,majors.size()):
   var need = reach.call(majors[i][2])+reach.call(majors[j][2])
   var d = majors[i][1].distance_to(majors[j][1])
   if d<need: add.call("footprints","error","%s and %s: footprints touch (%d m apart, need %d m)" % [majors[i][0],majors[j][0],int(d),int(ceil(need))],majors[i][1])
 # --- Grid checks (pipeline and synthetic maps: baked/) ---------------------------------------------
 if MapRegistry.has_file("baked/movement.json",map_id) and MapRegistry.has_file("baked/regions.json",map_id):
  _grid_checks(map_id,out,add,regions,majors,prov)
 # --- Factions ----------------------------------------------------------------------------------------
 var start_of = {}
 for r in regions:
  var o = str(regions[r].get("owner",""))
  if o != "": start_of.get_or_add(o,[]).append(r)
 for f in factions.factions:
  var n = start_of.get(f,[]).size()
  if n<1 or n>2: add.call("factions","warning","faction %s starts with %d regions (game-design §3.2: 1-2)" % [f,n])
  var seat = str(factions.factions[f].get("seat",""))
  if regions.has(seat) and not seat in start_of.get(f,[]): add.call("factions","error","faction %s seat '%s' is not one of its regions" % [f,seat])
 # --- Shares --------------------------------------------------------------------------------------------
 for r in regions:
  for k in ["culture","faith","race"]:
   if regions[r].has(k) and regions[r][k] is Dictionary:
    var sum = 0.0
    for v in regions[r][k].values(): sum += float(v)
    if absf(sum-1.0)>0.001: add.call("shares","error","%s %s shares sum to %.3f" % [r,k,sum])
 # --- Budgets -----------------------------------------------------------------------------------------
 for p in prov.provinces:
  if p.regions.size()<1 or p.regions.size()>5: add.call("budgets","warning","province %s has %d regions (1-5)" % [p.id,p.regions.size()])
 # --- Committed bakes match their sources ------------------------------------------------------------
 if str(meta.get("kind","")) == "pipeline":
  var Pipeline = load("res://map/pipeline.gd")
  var stamp = JSON.parse_string(FileAccess.get_file_as_string(dir+"baked/sources.json")) if FileAccess.file_exists(dir+"baked/sources.json") else {}
  if str(stamp.get("hash","")) != Pipeline.sources_hash(map_id): add.call("bakes","error","baked/ is stale: rebuild with scripts/build_map.gd -- --map=%s" % map_id)
 return _summary(out)

static func _grid_checks(map_id: String,out: Dictionary,add: Callable,regions: Dictionary,majors: Array,prov: Dictionary):
 var dir = MapRegistry.dir(map_id)
 var g = JSON.parse_string(FileAccess.get_file_as_string(dir+"baked/movement.json"))
 var rmeta = JSON.parse_string(FileAccess.get_file_as_string(dir+"baked/regions.json"))
 var cols = int(rmeta.cols)
 var rows = int(rmeta.rows)
 var cell = float(rmeta.cell)
 var origin = Vector2(rmeta.origin[0],rmeta.origin[1])
 var f = FileAccess.open_compressed(dir+"baked/regions.bin",FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 var rid = f.get_buffer(cols*rows*4).to_int32_array()
 f.close()
 var names: Array = rmeta.names
 var mv = MapBake.read_movement(dir)
 var cls: PackedByteArray = mv.get("classes",PackedByteArray())
 var water = 6
 var mountain = 5
 var center = func(i: int) -> Vector2: return origin+(Vector2(i%cols,i/cols)+Vector2(0.5,0.5))*cell
 # Every land cell in a region; every region one connected area.
 if cls.size() == cols*rows:
  var holes = 0
  var first = -1
  for i in cols*rows:
   if cls[i] != water and rid[i] == 0:
    holes += 1
    if first<0: first = i
  if holes>0: add.call("regions","error","%d land cells belong to no region" % holes,center.call(first))
 var seen = PackedByteArray()
 seen.resize(cols*rows)
 var pieces = {}
 for i in cols*rows:
  if rid[i] == 0 or seen[i] == 1: continue
  pieces[rid[i]] = pieces.get(rid[i],0)+1
  var q = [i]
  seen[i] = 1
  var h = 0
  while h<q.size():
   var c = q[h]
   h += 1
   for j in [c-1,c+1,c-cols,c+cols]:
    if j<0 or j>=cols*rows or seen[j] == 1 or rid[j] != rid[i]: continue
    if absi(j%cols-c%cols)>1: continue
    seen[j] = 1
    q.append(j)
  if pieces[rid[i]] == 2: add.call("regions","error","region %s is split into more than one area" % names[rid[i]-1],center.call(i))
 # Settlements on dry, gentle ground; majors reachable by land (or by sea through a port).
 if cls.size() == cols*rows:
  var comp = MapBake.read_components(dir,cols*rows) if FileAccess.file_exists(dir+"baked/components.bin") else PackedInt32Array()
  var comps = {}
  for m in majors:
   var c = Vector2i(((m[1]-origin)/cell).floor())
   if c.x<0 or c.y<0 or c.x>=cols or c.y>=rows:
    add.call("settlements","error","%s lies outside the map" % m[0],m[1])
    continue
   var i = c.y*cols+c.x
   if cls[i] == water or cls[i] == mountain: add.call("settlements","error","%s sits on %s" % [m[0],"water" if cls[i] == water else "a mountain"],m[1])
   if not comp.is_empty(): comps.get_or_add(comp[i],[]).append(m[0])
  if comps.size()>1:
   for k in comps:
    var port = comps[k].any(func(r): return regions[r].settlement.get("coastal",false))
    if not port: add.call("reach","error","%s cannot reach the other majors by land and has no port" % ", ".join(comps[k]))
 # Provinces contiguous (regions adjacent through the graph).
 var graph = JSON.parse_string(FileAccess.get_file_as_string(dir+"baked/graph.json")) if FileAccess.file_exists(dir+"baked/graph.json") else {}
 var adj = {}
 for e in graph.get("edges",[]):
  adj[Vector2i(int(e[0]),int(e[1]))] = true
  adj[Vector2i(int(e[1]),int(e[0]))] = true
 if not adj.is_empty():
  var index = {}
  for i in names.size(): index[names[i]] = i
  for p in prov.provinces:
   if p.regions.size()<2 or p.get("island",false): continue
   var reach = {p.regions[0]:true}
   var grew = true
   while grew:
    grew = false
    for r in p.regions:
     if reach.has(r): continue
     for s in reach.keys():
      if adj.has(Vector2i(index.get(r,-1),index.get(s,-1))):
       reach[r] = true
       grew = true
       break
   if reach.size()<p.regions.size(): add.call("provinces","error","province %s is not contiguous" % p.id)

static func _summary(out: Dictionary) -> Dictionary:
 out.errors = out.problems.filter(func(p): return p.level == "error").size()
 out.warnings = out.problems.filter(func(p): return p.level == "warning").size()
 return out
