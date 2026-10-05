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
 # TW:WH3-like relief (owner, 2026-10-04): broad massifs with wide bases, several peaks, ridges and
 # valleys, foothills rolling into the plains, natural pass valleys through the ranges, and rivers
 # winding to the sea in carved valleys. Shaped on the 8 m land grid (native noise, ridged fractal
 # with domain warp, a thermal-erosion pass, a priority-flood drainage network), then upsampled to
 # cells with fine detail added.
 t = Time.get_ticks_msec()
 var lo_cell = cell*4.0
 var relief = _relief(int(spec.seed),land_lo,lc,lr,lo_cell)
 var hi_img = Image.create_from_data(lc,lr,false,Image.FORMAT_RF,relief.heights.to_byte_array())
 hi_img.resize(cols,rows,Image.INTERPOLATE_BILINEAR)
 var hi_h = hi_img.get_data().to_float32_array()
 var mass_img = Image.create_from_data(lc,lr,false,Image.FORMAT_RF,relief.mass.to_byte_array())
 mass_img.resize(cols,rows,Image.INTERPOLATE_BILINEAR)
 var mass = mass_img.get_data().to_float32_array()
 var pass_img = Image.create_from_data(lc,lr,false,Image.FORMAT_RF,relief.valley.to_byte_array())
 pass_img.resize(cols,rows,Image.INTERPOLATE_BILINEAR)
 var valley = pass_img.get_data().to_float32_array()
 var riv_img = Image.create_from_data(lc,lr,false,Image.FORMAT_RF,relief.rivers.to_byte_array())
 riv_img.resize(cols,rows,Image.INTERPOLATE_BILINEAR)
 var riv = riv_img.get_data().to_float32_array()
 var detail = _noise(int(spec.seed)+5,0.08,cols,rows,3)
 var forest = _noise(int(spec.seed)+3,0.014,cols,rows,4)
 var heights = PackedFloat32Array()
 heights.resize(n)
 var cls = PackedByteArray()
 cls.resize(n)
 var colors = PackedByteArray()
 colors.resize(n*3)
 var rivers = PackedByteArray()
 rivers.resize(n)
 var palette = {PASS:Color("b59a6c"),OPEN:Color("8fae5a"),FOREST:Color("4f7a38"),HILLS:Color("a69a5e"),MOUNTAIN:Color("8a7f72"),WATER:Color("3f6f8e")}
 var pal = []
 for k in 7: pal.append(palette.get(k,Color.MAGENTA))
 # Heights with fine detail (rougher in the mountains).
 for i in n:
  var h = hi_h[i]
  if land[i]>=0.0: h += (float(detail[i])/255.0-0.5)*(0.5+mass[i]*5.0)
  heights[i] = h
 for z in rows:
  for x in cols:
   var i = z*cols+x
   var h = heights[i]
   rivers[i] = clampi(int(riv[i]*255.0),0,255)
   if land[i]<0.0:
    cls[i] = WATER
   else:
    var dx = heights[mini(i+1,n-1)]-heights[maxi(i-1,0)]
    var dz = heights[mini(i+cols,n-1)]-heights[maxi(i-cols,0)]
    var slope = sqrt(dx*dx+dz*dz)/(2.0*cell) # rise per metre
    if h>MOUNTAIN_ABOVE or (h>MOUNTAIN_ABOVE*0.6 and slope>1.1): cls[i] = MOUNTAIN
    elif valley[i]>0.5 and mass[i]>0.25: cls[i] = PASS
    elif h>HILLS_ABOVE or slope>0.45: cls[i] = HILLS
    elif riv[i]<0.3 and float(forest[i])+mass[i]*60.0+(25.0 if slope>0.2 else 0.0)>FOREST_ABOVE: cls[i] = FOREST
    else: cls[i] = OPEN
    # Forested slopes and valleys in the hills too (TW: canopy carpets climbing the ranges).
    if cls[i] == HILLS and riv[i]<0.3 and float(forest[i])+mass[i]*50.0>FOREST_ABOVE+20.0: cls[i] = FOREST
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
 MapBake.write_render_cache(map_id,cell,origin,cols,rows,heights,colors,rivers)
 times.write = Time.get_ticks_msec()-t
 t = Time.get_ticks_msec()
 var hpa = PathHierarchy.build(map_id)
 times.hpa = Time.get_ticks_msec()-t
 times.total = Time.get_ticks_msec()-t_all
 return {"regions":sites.size(),"provinces":provinces.size(),"factions":nf,"armies":armies.size(),"hpa_paths":hpa.paths,"roads":network.size(),"cols":cols,"rows":rows,"times":times}

# --- Relief (8 m land grid) ----------------------------------------------------------------------
const MOUNTAIN_ABOVE = 32.0 # metres: impassable massif
const HILLS_ABOVE = 9.0
const FOREST_ABOVE = 150.0  # forest noise (0-255) plus massif and slope bonuses
const RIVER_CELLS = 150     # drainage area (16 m cells, about 0.04 km2) where a river starts
const TALUS = 0.95          # thermal erosion: steepest stable rise per metre

# Heights, massif mask, pass valleys and river strength (0-1) on the land grid (lc x lr, cell lo_cell).
static func _relief(seed: int,land_lo: PackedFloat32Array,lc: int,lr: int,lo_cell: float) -> Dictionary:
 var m = lc*lr
 var massif = _fnl(seed+11,0.00042*lo_cell,FastNoiseLite.FRACTAL_FBM,4)
 var ridged = _fnl(seed+12,0.0026*lo_cell,FastNoiseLite.FRACTAL_RIDGED,5)
 ridged.fractal_weighted_strength = 0.55
 ridged.domain_warp_enabled = true
 ridged.domain_warp_amplitude = 26.0
 ridged.domain_warp_frequency = 0.02
 var rolling = _fnl(seed+13,0.0011*lo_cell,FastNoiseLite.FRACTAL_FBM,4)
 var gaps = _fnl(seed+14,0.0009*lo_cell,FastNoiseLite.FRACTAL_RIDGED,2)
 var h = PackedFloat32Array()
 h.resize(m)
 var mass = PackedFloat32Array()
 mass.resize(m)
 var valley = PackedFloat32Array()
 valley.resize(m)
 for z in lr:
  for x in lc:
   var i = z*lc+x
   var l = land_lo[i]
   if l<0.0:
    h[i] = -2.0+l*4.0
    continue
   var coast = minf(1.0,l*3.0)
   var mv = massif.get_noise_2d(x,z)*0.5+0.5
   var ms = _smooth(0.53,0.73,mv)*coast
   var foot = _smooth(0.36,0.6,mv)*coast
   var r = ridged.get_noise_2d(x,z)*0.5+0.5 # ridged: peaks and ridgelines, valleys between
   var b = rolling.get_noise_2d(x,z)*0.5+0.5
   var hh = 0.8+b*4.5+minf(l,0.3)*5.0+foot*(3.0+r*9.0)+ms*(r*r*105.0+10.0)
   # Pass valleys: where the gap noise ridges, the range drops to a valley floor.
   var g = _smooth(0.78,0.93,gaps.get_noise_2d(x,z)*0.5+0.5)*ms
   if g>0.0: hh = lerpf(hh,minf(hh,11.0+b*5.0),g)
   h[i] = hh
   mass[i] = ms
   valley[i] = g
 _erode(h,land_lo,lc,lr,lo_cell)
 var riv = _rivers(h,land_lo,lc,lr)
 # Carve the river valleys: the bed sinks with the river's size, the banks slope up gently.
 for i in m:
  if riv[i]<=0.0 or land_lo[i]<0.0: continue
  h[i] = maxf(lerpf(h[i],0.3,riv[i]*0.85)-riv[i]*1.6,-0.6)
 return {"heights":h,"mass":mass,"valley":valley,"rivers":riv}

static func _fnl(seed: int,freq: float,fractal: int,octaves: int) -> FastNoiseLite:
 var f = FastNoiseLite.new()
 f.seed = seed
 f.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
 f.frequency = freq
 f.fractal_type = fractal
 f.fractal_octaves = octaves
 return f

static func _smooth(a: float,b: float,v: float) -> float:
 var t = clampf((v-a)/(b-a),0.0,1.0)
 return t*t*(3.0-2.0*t)

# Thermal erosion: material slides from slopes steeper than TALUS to the cell below, which widens
# the bases, rounds the ridges and piles scree at the feet of the cliffs.
static func _erode(h: PackedFloat32Array,land_lo: PackedFloat32Array,lc: int,lr: int,lo_cell: float):
 var limit = TALUS*lo_cell
 for it in 4:
  for z in range(1,lr-1):
   for x in range(1,lc-1):
    var i = z*lc+x
    if land_lo[i]<0.0: continue
    var low = i
    var drop = 0.0
    for j in [i-1,i+1,i-lc,i+lc]:
     var d = h[i]-h[j]
     if d>drop:
      drop = d
      low = j
    if drop>limit:
     var move = (drop-limit)*0.35
     h[i] -= move
     h[low] += move

# Rivers by drainage (on a 16 m grid): a priority flood from the coast gives every land cell a
# downstream neighbour (filling pits, so every river reaches the sea); the drainage area summed
# upstream marks rivers where it passes RIVER_CELLS. Returns river strength 0-1 on the land grid.
static func _rivers(h: PackedFloat32Array,land_lo: PackedFloat32Array,lc: int,lr: int) -> PackedFloat32Array:
 var c2 = lc/2
 var r2 = lr/2
 var m2 = c2*r2
 var hh = PackedFloat32Array()
 hh.resize(m2)
 var landm = PackedByteArray()
 landm.resize(m2)
 var wander = _fnl(7919,0.045,FastNoiseLite.FRACTAL_FBM,4)
 for z in r2:
  for x in c2:
   var i = (z*2)*lc+x*2
   # Meanders: a little noise on the heights the water follows, so rivers wind across the plains.
   hh[z*c2+x] = h[i]+wander.get_noise_2d(x,z)*6.0
   landm[z*c2+x] = 1 if land_lo[i]>=0.0 else 0
 # Bucket queue on filled height (0.1 m buckets).
 var STEP = 0.1
 var buckets = []
 var down = PackedInt32Array()
 down.resize(m2)
 down.fill(-1)
 var seen = PackedByteArray()
 seen.resize(m2)
 var order = PackedInt32Array()
 var filled = hh.duplicate()
 var push = func(i: int,v: float):
  var k = maxi(0,int(v/STEP)+20)
  while buckets.size()<=k: buckets.append([])
  buckets[k].append(i)
 for i in m2:
  if landm[i] == 1: continue
  # Sea cells next to land seed the flood.
  var x = i%c2
  var z = i/c2
  for nb in [[x-1,z],[x+1,z],[x,z-1],[x,z+1]]:
   if nb[0]>=0 and nb[1]>=0 and nb[0]<c2 and nb[1]<r2:
    var j = nb[1]*c2+nb[0]
    if landm[j] == 1 and seen[j] == 0:
     seen[j] = 1
     down[j] = -1
     filled[j] = maxf(hh[j],0.0)
     push.call(j,filled[j])
 var k = 0
 while k<buckets.size():
  if buckets[k].is_empty():
   k += 1
   continue
  var i = buckets[k].pop_back()
  order.append(i)
  var x = i%c2
  var z = i/c2
  for d in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
   var nx = x+d.x
   var nz = z+d.y
   if nx<0 or nz<0 or nx>=c2 or nz>=r2: continue
   var j = nz*c2+nx
   if seen[j] == 1 or landm[j] == 0: continue
   seen[j] = 1
   down[j] = i
   filled[j] = maxf(hh[j],filled[i]+0.01)
   push.call(j,filled[j])
 var acc = PackedFloat32Array()
 acc.resize(m2)
 acc.fill(1.0)
 for t in range(order.size()-1,-1,-1):
  var i = order[t]
  if down[i]>=0: acc[down[i]] += acc[i]
 return _draw_rivers(acc,down,landm,c2,r2,lc,lr)

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

# The river network as smooth lines: chains of river cells (16 m grid) followed downstream from
# each source to the sea or the river they join, rounded (Chaikin) and drawn onto the land grid
# with a width that grows with the drainage area. Returns strength 0-1 per land-grid cell.
static func _draw_rivers(acc: PackedFloat32Array,down: PackedInt32Array,landm: PackedByteArray,c2: int,r2: int,lc: int,lr: int) -> PackedFloat32Array:
 var m2 = c2*r2
 var is_river = PackedByteArray()
 is_river.resize(m2)
 var has_up = PackedByteArray()
 has_up.resize(m2)
 for i in m2:
  if landm[i] == 1 and acc[i]>=RIVER_CELLS:
   is_river[i] = 1
   if down[i]>=0: has_up[down[i]] = 1
 var out = PackedFloat32Array()
 out.resize(lc*lr)
 var done = PackedByteArray()
 done.resize(m2)
 for i in m2:
  if is_river[i] == 0 or has_up[i] == 1: continue
  # A source: walk down to the sea or to a cell already drawn (the junction).
  var pts = PackedVector2Array()
  var sw = PackedFloat32Array()
  var c = i
  while c>=0:
   pts.append(Vector2(c%c2,c/c2)*2.0+Vector2(1,1))
   sw.append(clampf(0.35+0.65*log(acc[c]/RIVER_CELLS)/log(60.0),0.0,1.0))
   if done[c] == 1: break
   done[c] = 1
   c = down[c]
  if pts.size()<3: continue
  for it in 2:
   var p2 = PackedVector2Array([pts[0]])
   var s2 = PackedFloat32Array([sw[0]])
   for k in pts.size()-1:
    p2.append(pts[k].lerp(pts[k+1],0.25))
    p2.append(pts[k].lerp(pts[k+1],0.75))
    s2.append(lerpf(sw[k],sw[k+1],0.25))
    s2.append(lerpf(sw[k],sw[k+1],0.75))
   p2.append(pts[pts.size()-1])
   s2.append(sw[sw.size()-1])
   pts = p2
   sw = s2
  for k in pts.size()-1:
   var a = pts[k]
   var b = pts[k+1]
   var w = 0.45+sw[k]*1.25 # half width in land cells (8 m)
   var lo = Vector2i((a.min(b)-Vector2.ONE*(w+1.5)).floor())
   var hi = Vector2i((a.max(b)+Vector2.ONE*(w+1.5)).ceil())
   for z in range(maxi(lo.y,0),mini(hi.y,lr-1)+1):
    for x in range(maxi(lo.x,0),mini(hi.x,lc-1)+1):
     var p = Vector2(x+0.5,z+0.5)
     var d = p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))
     var v = clampf((w+1.0-d)/1.5,0.0,1.0)*(0.55+0.45*sw[k])
     if v>out[z*lc+x]: out[z*lc+x] = v
 return out
