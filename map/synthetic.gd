extends RefCounted
# Synthetic scale-test map (docs/map-pipeline-design.md §6.2): a procedurally generated world of
# the full V1 size with the design ceiling's counts (600 regions, 150 factions, 500 armies), written
# in exactly the formats an authored map uses (provinces.json, factions.json, campaign_start.json,
# armies/, movement.json overlay, committed-style bakes in baked/, render cache in user://), so the
# budgets measured on it are the budgets the real pipeline will meet. It is a test fixture: only its
# map.json is committed; scripts/build_map.gd regenerates the rest.
#
# Steps (one tight loop per pass over the 2048 x 1280 cells):
#  1. land: three continents (noise-warped ellipses, computed at 8 m and upsampled natively)
#  2. heights and terrain classes from native noise images (open, forest, hills, mountain, water)
#  3. region sites on open land (jittered grid, exactly `regions`)
#  4. regions: multi-source flood fill over land; adjacency and hull points from one border pass
#  5. provinces (2-4 adjacent regions), factions (contiguous territories), settlements, armies
#  6. roads: straight segments between adjacent regions' majors that stay on passable land

const MapBake = preload("res://map/map_bake.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const PathHierarchy = preload("res://core/path_hierarchy.gd")
const UNITS = ["spearmen","swordsmen","archers","peasant_levy","cavalry","heavy_infantry"]
const EMBLEMS = ["spire","wave","wheat"]
const CULTURES = ["medieval","roman","greek","orc","dwarf","elf","dark_elf","beastmen","ratmen","lizardmen","desert"]
const TRAITS = ["passive","income_focused","generous","kind","expansionist","cruel","treacherous"]
# Terrain class indices: the order of data/movement.json terrain (checked by MapBake.write_movement).
const OPEN = 0
const FOREST = 1
const HILLS = 2
const PASS = 3
const SETTLEMENT = 4
const MOUNTAIN = 5
const WATER = 6

static func build(map_id: String) -> Dictionary:
 var t_all = Time.get_ticks_msec()
 var meta = MapRegistry.meta(map_id)
 var spec = meta.synthetic
 var cell = float(meta.cell)
 var cols = int(float(meta.size[0])/cell)
 var rows = int(float(meta.size[1])/cell)
 var origin = Vector2(meta.origin[0],meta.origin[1])
 var n = cols*rows
 var rng = RandomNumberGenerator.new()
 rng.seed = int(spec.seed)
 var times = {}
 var t = Time.get_ticks_msec()
 # --- 1. Land (8 m), upsampled to cells -------------------------------------------------------
 var lc = cols/4
 var lr = rows/4
 var warp = _noise(int(spec.seed),0.012,lc,lr,4)
 var land_lo = PackedFloat32Array()
 land_lo.resize(lc*lr)
 var conts = [[Vector2(0.20,0.42),Vector2(0.17,0.38)],[Vector2(0.62,0.38),Vector2(0.17,0.34)],[Vector2(0.38,0.90),Vector2(0.17,0.07)]]
 for z in lr:
  for x in lc:
   var w = float(warp[z*lc+x])/255.0-0.5
   var u = Vector2(float(x)/lc,float(z)/lr)
   var best = 9.0
   for c in conts:
    var d = (u-c[0])/c[1]
    best = minf(best,d.length_squared())
   land_lo[z*lc+x] = 1.0-best+w*0.9
 var land_img = Image.create_from_data(lc,lr,false,Image.FORMAT_RF,land_lo.to_byte_array())
 land_img.resize(cols,rows,Image.INTERPOLATE_BILINEAR)
 var land = land_img.get_data().to_float32_array()
 times.land = Time.get_ticks_msec()-t
 # --- 2. Heights and classes ---------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var base = _noise(int(spec.seed)+1,0.006,cols,rows,5)
 var ridge = _noise(int(spec.seed)+2,0.004,cols,rows,3)
 var forest = _noise(int(spec.seed)+3,0.02,cols,rows,3)
 # Passes (design: ranges are impassable except at passes): where this noise is high, a ridge drops
 # to a pass corridor; at this frequency a ridge opens every few hundred metres.
 var gaps = _noise(int(spec.seed)+4,0.012,cols,rows,2)
 var pass_above = int(spec.get("pass_above",168)) # 256: no passes (the earlier maze-like ridges)
 var heights = PackedFloat32Array()
 heights.resize(n)
 var cls = PackedByteArray()
 cls.resize(n)
 var colors = PackedByteArray()
 colors.resize(n*3)
 var palette = {PASS:Color("b59a6c"),OPEN:Color("8fae5a"),FOREST:Color("4f7a38"),HILLS:Color("a69a5e"),MOUNTAIN:Color("8a7f72"),WATER:Color("3f6f8e")}
 var pal = []
 for k in 7: pal.append(palette.get(k,Color.MAGENTA))
 for i in n:
  var l = land[i]
  if l<0.0:
   heights[i] = -2.0+l*4.0
   cls[i] = WATER
  else:
   var b = float(base[i])/255.0
   var r = 1.0-absf(float(ridge[i])/127.5-1.0) # ridged: 1 on the ridge line
   var mtn = maxf(0.0,r-0.86)*7.0*minf(1.0,l*4.0)
   var h = 0.6+b*7.0+mtn*40.0+minf(l,0.3)*6.0
   var is_pass = h>20.0 and gaps[i]>pass_above
   if is_pass: h = 12.0+b*4.0
   heights[i] = h
   if is_pass: cls[i] = PASS
   elif h>20.0: cls[i] = MOUNTAIN
   elif h>8.5: cls[i] = HILLS
   elif forest[i]>150: cls[i] = FOREST
   else: cls[i] = OPEN
  var c = pal[cls[i]]
  colors[i*3] = c.r8
  colors[i*3+1] = c.g8
  colors[i*3+2] = c.b8
 times.terrain = Time.get_ticks_msec()-t
 # --- 3. Region sites -----------------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var target = int(spec.regions)
 var open_cells = 0
 for i in n: if cls[i] == OPEN or cls[i] == FOREST: open_cells += 1
 var spacing = sqrt(float(open_cells)/target)*1.0
 var sites = []
 for attempt in 12:
  sites = []
  var s = int(spacing)
  for z in range(s/2,rows,s):
   for x in range(s/2,cols,s):
    var jx = clampi(x+rng.randi_range(-s/3,s/3),2,cols-3)
    var jz = clampi(z+rng.randi_range(-s/3,s/3),2,rows-3)
    if cls[jz*cols+jx] == OPEN: sites.append(Vector2i(jx,jz))
  if sites.size()>=target: break
  spacing *= 0.93
 # Exactly `target` sites, dropped evenly.
 while sites.size()>target: sites.remove_at(rng.randi_range(0,sites.size()-1))
 times.sites = Time.get_ticks_msec()-t
 # --- 4. Regions: flood fill from the sites over land ---------------------------------------------
 t = Time.get_ticks_msec()
 var rid = PackedInt32Array()
 rid.resize(n)
 var queue = PackedInt32Array()
 queue.resize(n)
 var head = 0
 var tail = 0
 for k in sites.size():
  var i0 = sites[k].y*cols+sites[k].x
  rid[i0] = k+1
  queue[tail] = i0
  tail += 1
 while head<tail:
  var i = queue[head]
  head += 1
  var id = rid[i]
  var x = i%cols
  if x>0 and rid[i-1] == 0 and cls[i-1] != WATER:
   rid[i-1] = id
   queue[tail] = i-1
   tail += 1
  if x<cols-1 and rid[i+1] == 0 and cls[i+1] != WATER:
   rid[i+1] = id
   queue[tail] = i+1
   tail += 1
  if i>=cols and rid[i-cols] == 0 and cls[i-cols] != WATER:
   rid[i-cols] = id
   queue[tail] = i-cols
   tail += 1
  if i<n-cols and rid[i+cols] == 0 and cls[i+cols] != WATER:
   rid[i+cols] = id
   queue[tail] = i+cols
   tail += 1
 # Adjacency (by shared border), with one crossing per pair for hierarchical paths: the passable
 # border cell nearest the midpoint between the two sites; and sampled points per region (hulls).
 var adj = {}
 var pts = []
 for k in sites.size(): pts.append(PackedVector2Array())
 for z in rows:
  var row = z*cols
  for x in cols:
   var i = row+x
   var a = rid[i]
   if a == 0: continue
   if x<cols-1:
    var b = rid[i+1]
    if b != 0 and b != a: _border(adj,a,b,i,i+1,cls,sites,cols)
   if z<rows-1:
    var b2 = rid[i+cols]
    if b2 != 0 and b2 != a: _border(adj,a,b2,i,i+cols,cls,sites,cols)
   if (x & 3) == 0 and (z & 3) == 0: pts[a-1].append(origin+Vector2(x+0.5,z+0.5)*cell)
 var neighbours = []
 for k in sites.size(): neighbours.append([])
 for key in adj:
  var a = key/65536-1
  var b = key%65536-1
  neighbours[a].append(b)
  neighbours[b].append(a)
 times.regions = Time.get_ticks_msec()-t
 # --- 5. Provinces, factions, settlements, armies --------------------------------------------------
 t = Time.get_ticks_msec()
 var region_ids = []
 for k in sites.size(): region_ids.append("r%03d" % k)
 var province_of = []
 province_of.resize(sites.size())
 province_of.fill(-1)
 var provinces = []
 for k in sites.size():
  if province_of[k] != -1: continue
  var members = [k]
  province_of[k] = provinces.size()
  var want = rng.randi_range(2,4)
  for nb in neighbours[k]:
   if members.size()>=want: break
   if province_of[nb] == -1:
    province_of[nb] = provinces.size()
    members.append(nb)
  provinces.append(members)
 # Factions: seeds spread over the regions, territories grown by turns over the region graph.
 var nf = int(spec.factions)
 var owner = []
 owner.resize(sites.size())
 owner.fill(-1)
 var order = range(sites.size())
 _shuffle(order,rng)
 var fronts = []
 for f in nf:
  owner[order[f]] = f
  fronts.append([order[f]])
 var grown = true
 while grown:
  grown = false
  for f in nf:
   var next = []
   for r in fronts[f]:
    for nb in neighbours[r]:
     if owner[nb] == -1:
      owner[nb] = f
      next.append(nb)
      grown = true
      break
   fronts[f] += next
 for k in sites.size(): if owner[k] == -1: owner[k] = rng.randi_range(0,nf-1) # islands without a neighbour
 var faction_ids = []
 for f in nf: faction_ids.append("synth_%03d" % f)
 var factions = {}
 for f in nf:
  var col = Color.from_hsv(fmod(f*0.61803,1.0),0.55+0.3*((f*7)%3)/2.0,0.45+0.2*((f*5)%3)/2.0)
  factions[faction_ids[f]] = {"culture":CULTURES[f%CULTURES.size()],"name":"House Synth %03d" % f,"realm":"Synthetic realm %03d" % f,"seat":region_ids[order[f]],"primary":"#"+col.to_html(false),
   "secondary":"#"+col.lightened(0.5).to_html(false),"emblem":EMBLEMS[f%EMBLEMS.size()],"placeholder_assignment":true,
   "battle_style":{"default":"line"},"general_traits":[],"traits":[TRAITS[f%TRAITS.size()]]}
 var regions = {}
 var settlements = {}
 var treasury = {}
 for f in faction_ids: treasury[f] = rng.randi_range(2000,9000)
 var minor_types = ["village","castle","town"]
 for k in sites.size():
  var p = origin+(Vector2(sites[k])+Vector2(0.5,0.5))*cell
  var coastal = _near_class(cls,cols,rows,sites[k],WATER,6)
  var typ = "fortress" if rng.randf()<0.25 else "city"
  var level = rng.randi_range(1,3)
  var hull = Geometry2D.convex_hull(pts[k]) if pts[k].size()>=3 else PackedVector2Array([p+Vector2(-8,-8),p+Vector2(8,-8),p+Vector2(8,8),p+Vector2(-8,8),p+Vector2(-8,-8)])
  var poly = []
  for v in hull.slice(0,hull.size()-1): poly.append([snappedf(v.x,0.1),snappedf(v.y,0.1)])
  var minor = []
  var mp = p+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(18,30)
  var mc = Vector2i(((mp-origin)/cell).floor())
  if mc.x>=0 and mc.y>=0 and mc.x<cols and mc.y<rows and rid[mc.y*cols+mc.x] == k+1 and cls[mc.y*cols+mc.x] != WATER and cls[mc.y*cols+mc.x] != MOUNTAIN:
   minor.append({"name":"Minor %03d" % k,"type":minor_types[k%3],"level":1,"position":[snappedf(mp.x,0.1),snappedf(mp.y,0.1)]})
  regions[region_ids[k]] = {"name":"Region %03d" % k,"owner":faction_ids[owner[k]],
   "resources":{"wood":rng.randi_range(0,3),"stone":rng.randi_range(0,3),"food":rng.randi_range(0,4),"minerals":rng.randi_range(0,2)},
   "settlement":{"name":"Settlement %03d" % k,"type":typ,"level":level,"coastal":coastal,"position":[snappedf(p.x,0.1),snappedf(p.y,0.1)]},
   "minor":minor,"polygon":poly}
  var builds = [{"chain":"barracks","level":1}] if rng.randf()<0.6 else []
  if typ == "fortress": builds = [{"chain":"walls","level":1}]
  settlements[region_ids[k]] = {"population":rng.randi_range(2500,14000),"buildings":builds}
 var prov_list = []
 for pi in provinces.size():
  var ids = provinces[pi].map(func(k): return region_ids[k])
  prov_list.append({"id":"p%03d" % pi,"name":"Province %03d" % pi,"capital":ids[0],"regions":ids})
 # Armies: spread over the factions, each beside one of its own settlements.
 var armies = []
 var positions = {}
 var army_files = {}
 var by_faction = {}
 for k in sites.size(): by_faction.get_or_add(owner[k],[]).append(k)
 for a in int(spec.armies):
  var f = a%nf
  var home = by_faction.get(f,[order[f]])
  var k = home[(a/nf)%home.size()]
  var id = "army_%03d" % a
  var p = origin+(Vector2(sites[k])+Vector2(0.5,0.5))*cell+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(8,14)
  var c = Vector2i(((p-origin)/cell).floor())
  if cls[clampi(c.y,0,rows-1)*cols+clampi(c.x,0,cols-1)] in [WATER,MOUNTAIN]: p = origin+(Vector2(sites[k])+Vector2(0.5,0.5))*cell
  armies.append(id)
  positions[id] = [snappedf(p.x,0.1),snappedf(p.y,0.1)]
  var units = []
  for u in rng.randi_range(10,19): units.append({"unit":UNITS[rng.randi_range(0,UNITS.size()-1)],"strength":snappedf(rng.randf_range(0.6,1.0),0.05)})
  army_files[id] = {"id":id,"display_name":"Army %03d" % a,"faction":faction_ids[f],"commander":{"unit":"commander","name":"General %03d" % a,"rank":rng.randi_range(1,5)},"units":units}
 times.world = Time.get_ticks_msec()-t
 # --- 6. Roads between neighbouring majors -----------------------------------------------------------
 t = Time.get_ticks_msec()
 var road = PackedByteArray()
 road.resize(n)
 var network = []
 for key in adj:
  var a = key/65536-1
  var b = key%65536-1
  var pa = Vector2(sites[a])
  var pb = Vector2(sites[b])
  var steps = int(pa.distance_to(pb))
  if steps>110: continue
  var ok = true
  var cells = PackedInt32Array()
  for s in steps+1:
   var q = pa.lerp(pb,float(s)/maxi(1,steps))
   var ci = int(q.y)*cols+int(q.x)
   if cls[ci] == WATER or cls[ci] == MOUNTAIN:
    ok = false
    break
   cells.append(ci)
  if not ok: continue
  for ci in cells:
   road[ci] = 1
   if ci+1<n: road[ci+1] = 1
  network.append({"id":"%s_%s" % [region_ids[a],region_ids[b]],"points":[[snappedf(origin.x+(pa.x+0.5)*cell,0.1),snappedf(origin.y+(pa.y+0.5)*cell,0.1)],[snappedf(origin.x+(pb.x+0.5)*cell,0.1),snappedf(origin.y+(pb.y+0.5)*cell,0.1)]]})
 # Settlement cells.
 for k in sites.size(): cls[sites[k].y*cols+sites[k].x] = SETTLEMENT
 times.roads = Time.get_ticks_msec()-t
 # --- Write ------------------------------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var dir = MapRegistry.dir(map_id)
 DirAccess.make_dir_recursive_absolute(dir+"armies")
 DirAccess.make_dir_recursive_absolute(dir+"baked")
 MapBake.write_json(dir+"provinces.json",{"_note":"GENERATED by scripts/build_map.gd (map/synthetic.gd). Synthetic scale-test map; do not edit.","provinces":prov_list,"regions":regions})
 MapBake.write_json(dir+"factions.json",{"_note":"GENERATED synthetic factions.","factions":factions})
 MapBake.write_json(dir+"campaign_start.json",{"_note":"GENERATED synthetic start.","seed":int(spec.seed),"year":1,"player_faction":faction_ids[0],"treasury":treasury,"armies":armies,"army_positions":positions,"road_level":1,"settlements":settlements})
 MapBake.write_json(dir+"movement.json",{"_note":"GENERATED synthetic road network.","roads":{"network":network},"passes":{"list":[]}})
 for id in army_files: MapBake.write_json(dir+"armies/"+id+".json",army_files[id])
 MapBake.write_regions(dir,cell,origin,cols,rows,rid,region_ids)
 MapBake.write_movement(dir,cell,origin,cols,rows,cls,road)
 MapBake.write_components(dir,MapBake.components_of(cls,cols,rows))
 MapBake.write_parts(dir,MapBake.parts_of(cls,rid,cols,rows))
 var edges = []
 for key in adj:
  if adj[key][1]>=0: edges.append([key/65536-1,key%65536-1,adj[key][1],adj[key][2]])
 MapBake.write_graph(dir,edges)
 MapBake.write_render_cache(map_id,cell,origin,cols,rows,heights,colors)
 times.write = Time.get_ticks_msec()-t
 t = Time.get_ticks_msec()
 var hpa = PathHierarchy.build(map_id)
 times.hpa = Time.get_ticks_msec()-t
 times.total = Time.get_ticks_msec()-t_all
 return {"regions":sites.size(),"provinces":provinces.size(),"factions":nf,"armies":armies.size(),"hpa_paths":hpa.paths,"roads":network.size(),"cols":cols,"rows":rows,"times":times}

# Record a border between regions a and b (1-based) at cells i and j; keep the passable crossing
# nearest the sites' midpoint.
static func _border(adj: Dictionary,a: int,b: int,i: int,j: int,cls: PackedByteArray,sites: Array,cols: int):
 var key = mini(a,b)*65536+maxi(a,b)
 var e = adj.get(key)
 if e == null:
  e = [INF,-1,-1]
  adj[key] = e
 if cls[i] == WATER or cls[i] == MOUNTAIN or cls[j] == WATER or cls[j] == MOUNTAIN: return
 var mid = Vector2(sites[a-1]+sites[b-1])*0.5
 var d2 = Vector2(i%cols,i/cols).distance_squared_to(mid)
 if d2<e[0]:
  e[0] = d2
  e[1] = i
  e[2] = j

# A normalized noise image as bytes (0-255), frequency in cycles per cell.
static func _noise(seed: int,freq: float,w: int,h: int,octaves: int) -> PackedByteArray:
 var fn = FastNoiseLite.new()
 fn.seed = seed
 fn.frequency = freq
 fn.fractal_octaves = octaves
 fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
 var img = fn.get_image(w,h,false,false,true)
 img.convert(Image.FORMAT_L8)
 return img.get_data()

static func _near_class(cls: PackedByteArray,cols: int,rows: int,c: Vector2i,want: int,r: int) -> bool:
 for z in range(maxi(0,c.y-r),mini(rows,c.y+r+1),2):
  for x in range(maxi(0,c.x-r),mini(cols,c.x+r+1),2):
   if cls[z*cols+x] == want: return true
 return false

static func _shuffle(a: Array,rng: RandomNumberGenerator):
 for i in range(a.size()-1,0,-1):
  var j = rng.randi_range(0,i)
  var tmp = a[i]
  a[i] = a[j]
  a[j] = tmp
