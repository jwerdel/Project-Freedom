extends RefCounted
# Data for the painted parchment strategic map (ui/strategic_map.gd, look after
# docs/reference/world/varos_map.jpg): textures the territory shader paints from, and the mountain,
# hill and forest glyphs, all derived from map data, never from meshes.
#  - relief: heights (render cache, normalised), else a blurred guess from the movement classes
#  - biome: the render cache's ground colours, else a parchment palette per movement class
#  - rivers: the render cache's river raster (empty when missing)
#  - coast: signed distance to the coast in cells (+ land, - water) from the movement grid's water,
#    at most COAST_MAX cells on the long side, for inked coastlines and sea ripple contours
#  - glyphs: [world position, kind (0 mountain, 1 hill, 2 tree), scale, seed, ground colour] on a
#    jittered grid
# Built once per map and cached (static), so opening the map or rebuilding it costs nothing.

const Movement = preload("res://core/movement.gd")
const MapBake = preload("res://map/map_bake.gd")
const MapRegistry = preload("res://core/map_registry.gd")

const COAST_MAX = 512
const GLYPHS_ACROSS = 68.0 # glyph grid columns over the world's width
const CLASS_COLORS = {"open":Color("cdbb84"),"settlement":Color("cdbb84"),"forest":Color("7d8f55"),"hills":Color("b9a06a"),"mountain":Color("9a8a74"),"pass":Color("b49c74"),"water":Color("5f8c8f")}
const CLASS_HEIGHT = {"open":0.12,"settlement":0.12,"forest":0.16,"hills":0.42,"pass":0.5,"mountain":0.95,"water":0.0}

static var _cache := {}

static func build(world_rect: Rect2) -> Dictionary:
 var key = "%s|%s|%s" % [MapRegistry.active,MapBake.stamp(MapRegistry.active) if MapRegistry.has_file("baked/movement.bin") else "",world_rect]
 if _cache.has(key): return _cache[key]
 var g = Movement.grid()
 var out = {}
 var rc = MapBake.load_render_cache(MapRegistry.active) if MapRegistry.has_file("baked/movement.bin") else {}
 if not rc.is_empty():
  var h: Image = rc.heights
  var lo = INF
  var hi = -INF
  var data = h.get_data().to_float32_array()
  for v in data:
   lo = minf(lo,v)
   hi = maxf(hi,v)
  var n = PackedFloat32Array()
  n.resize(data.size())
  var sea = maxf(lo,0.0)
  for i in data.size(): n[i] = clampf((data[i]-sea)/maxf(0.001,hi-sea),0.0,1.0)
  out.heights = ImageTexture.create_from_image(Image.create_from_data(rc.cols,rc.rows,false,Image.FORMAT_RF,n.to_byte_array()))
  out.biome = ImageTexture.create_from_image(rc.colors)
  out.rivers = ImageTexture.create_from_image(rc.rivers)
  out.paint_xform = _xform(world_rect,rc.origin,Vector2(rc.cols,rc.rows)*float(rc.cell))
  out.texel = Vector2(1.0/rc.cols,1.0/rc.rows)
  out.relief = 1.0
 else:
  # No render cache (the legacy map, tests): a parchment palette and a softened class relief.
  var img = Image.create(g.cols,g.rows,false,Image.FORMAT_RGB8)
  var hv = PackedFloat32Array()
  hv.resize(g.cols*g.rows)
  for i in g.cols*g.rows:
   var nm = g.names[g.terrain[i]]
   img.set_pixel(i%g.cols,i/g.cols,CLASS_COLORS.get(nm,Color("cdbb84")))
   hv[i] = CLASS_HEIGHT.get(nm,0.1)
  var himg = Image.create_from_data(g.cols,g.rows,false,Image.FORMAT_RF,hv.to_byte_array())
  out.heights = ImageTexture.create_from_image(himg)
  out.biome = ImageTexture.create_from_image(img)
  var rv = Image.create(4,4,false,Image.FORMAT_R8)
  out.rivers = ImageTexture.create_from_image(rv)
  out.paint_xform = _xform(world_rect,g.origin,Vector2(g.cols,g.rows)*float(g.cell))
  out.texel = Vector2(1.0/g.cols,1.0/g.rows)
  out.relief = 0.5
 var coast = _coast(g)
 out.coast = coast.tex
 out.coast_xform = _xform(world_rect,g.origin,Vector2(g.cols,g.rows)*float(g.cell))
 out.coast_texel = Vector2(1.0/coast.cols,1.0/coast.rows)
 out.coast_cells_per_world = coast.cols/(g.cols*float(g.cell))
 out.glyphs = _glyphs(g,world_rect,rc)
 _cache[key] = out
 return out

static func _xform(world_rect: Rect2,origin: Vector2,span: Vector2) -> Vector4:
 var sc = world_rect.size/span
 var off = (world_rect.position-origin)/span
 return Vector4(sc.x,sc.y,off.x,off.y)

# Signed chamfer distance to the coast (cells of the downsampled grid, + land, - water).
static func _coast(g: Dictionary) -> Dictionary:
 var water = g.names.find("water")
 var step = maxi(1,int(ceil(maxf(g.cols,g.rows)/float(COAST_MAX))))
 var cols = int(ceil(g.cols/float(step)))
 var rows = int(ceil(g.rows/float(step)))
 var wet = PackedByteArray()
 wet.resize(cols*rows)
 for z in rows:
  for x in cols:
   var gx = mini(g.cols-1,x*step+step/2)
   var gz = mini(g.rows-1,z*step+step/2)
   wet[z*cols+x] = 1 if g.terrain[gz*g.cols+gx] == water else 0
 var d_land = _chamfer(wet,cols,rows,0) # on land: distance to water
 var d_sea = _chamfer(wet,cols,rows,1)  # at sea: distance to land
 var sd = PackedFloat32Array()
 sd.resize(cols*rows)
 for i in cols*rows: sd[i] = (d_land[i]-0.5) if wet[i] == 0 else -(d_sea[i]-0.5)
 return {"tex":ImageTexture.create_from_image(Image.create_from_data(cols,rows,false,Image.FORMAT_RF,sd.to_byte_array())),"cols":cols,"rows":rows}

# Distance (cells, 1 / 1.414 chamfer) from every cell whose wet value == side to the nearest cell of
# the other kind; 0 on the other kind itself.
static func _chamfer(wet: PackedByteArray,cols: int,rows: int,side: int) -> PackedFloat32Array:
 var d = PackedFloat32Array()
 d.resize(cols*rows)
 var far = float(cols+rows)
 for i in cols*rows: d[i] = far if wet[i] == side else 0.0
 for z in rows:
  for x in cols:
   var i = z*cols+x
   var v = d[i]
   if v == 0.0: continue
   if x>0: v = minf(v,d[i-1]+1.0)
   if z>0:
    v = minf(v,d[i-cols]+1.0)
    if x>0: v = minf(v,d[i-cols-1]+1.414)
    if x<cols-1: v = minf(v,d[i-cols+1]+1.414)
   d[i] = v
 for z in range(rows-1,-1,-1):
  for x in range(cols-1,-1,-1):
   var i = z*cols+x
   var v = d[i]
   if v == 0.0: continue
   if x<cols-1: v = minf(v,d[i+1]+1.0)
   if z<rows-1:
    v = minf(v,d[i+cols]+1.0)
    if x<cols-1: v = minf(v,d[i+cols+1]+1.414)
    if x>0: v = minf(v,d[i+cols-1]+1.414)
   d[i] = v
 return d

# Glyphs on a jittered grid: mountains (snow-capped when high), hills and forest trees. Sorted
# north to south so nearer (lower) glyphs overlap the ones behind them.
static func _glyphs(g: Dictionary,world_rect: Rect2,rc: Dictionary) -> Array:
 var out = []
 var step = world_rect.size.x/GLYPHS_ACROSS
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(MapRegistry.active)
 var idx = {}
 for k in ["mountain","hills","forest","pass"]: idx[k] = g.names.find(k)
 var ny = int(world_rect.size.y/step)
 var nx = int(GLYPHS_ACROSS)
 for j in ny:
  for i in nx:
   var p = world_rect.position+Vector2((i+0.5+rng.randf_range(-0.38,0.38))*step,(j+0.5+rng.randf_range(-0.38,0.38))*step)
   var gx = int((p.x-g.origin.x)/g.cell)
   var gz = int((p.y-g.origin.y)/g.cell)
   if gx<0 or gz<0 or gx>=g.cols or gz>=g.rows: continue
   var t = g.terrain[gz*g.cols+gx]
   var s = rng.randf()
   if (t == idx.mountain and rng.randf()<0.8) or t == idx.pass: out.append([p,0,rng.randf_range(0.9,1.25) if t == idx.mountain else 0.75,s,_ground(rc,p)])
   elif t == idx.hills:
    if rng.randf()<0.3: out.append([p,1,rng.randf_range(0.8,1.05),s,_ground(rc,p)])
   elif t == idx.forest: out.append([p,2,rng.randf_range(0.8,1.1),s,_ground(rc,p)])
 out.sort_custom(func(a,b): return a[0].y<b[0].y)
 return out

# The render cache's ground colour under a glyph (white when there is no cache), so mountains and
# trees take their land's tint: red peaks, ash walls, snowy ranges.
static func _ground(rc: Dictionary,p: Vector2) -> Color:
 if rc.is_empty(): return Color.WHITE
 var x = clampi(int((p.x-rc.origin.x)/rc.cell),0,rc.cols-1)
 var z = clampi(int((p.y-rc.origin.y)/rc.cell),0,rc.rows-1)
 return rc.colors.get_pixel(x,z)
