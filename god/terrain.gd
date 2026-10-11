extends Node3D
# The character-scale ground of the god-game look test (docs/pivot/god-game.md): a heightfield of
# half_size metres each way around the settlement at `cell` metres, taken from the campaign map's
# heights at campaign_scale plus relief (rolling hills, the castle rise) that fades out toward the
# edge so it meets the campaign terrain drawn around it. Chunks with three LOD grids on visibility
# ranges, one HeightMapShape3D for collision and a splat image (R road mud, G bare ground, B field
# soil, A paving) that the town paints and god/terrain.gdshader reads.

const CHUNK_LODS = [[1,0.0,380.0],[3,380.0,950.0],[8,950.0,0.0]] # grid step in cells, range begin, end

var half := 1200.0
var cell := 2.0
var n := 0 # vertices per side
var heights := PackedFloat32Array()
var splat: Image
var splat_tex: ImageTexture
var material: ShaderMaterial
var body: StaticBody3D
var castle := Vector2(0,-40)
var cfg: Dictionary

# base: Callable(x, z) -> the campaign height at this local point, already at character scale.
func build(c: Dictionary,base: Callable):
 cfg = c
 half = float(c.half_size)
 cell = float(c.cell)
 n = int(half*2.0/cell)+1
 heights.resize(n*n)
 var noise = FastNoiseLite.new()
 noise.seed = int(c.seed)
 noise.frequency = 0.0016
 noise.fractal_octaves = 5
 noise.fractal_gain = 0.48
 var ridge = FastNoiseLite.new()
 ridge.seed = int(c.seed)+3
 ridge.noise_type = FastNoiseLite.TYPE_PERLIN
 ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
 ridge.frequency = 0.0021
 ridge.fractal_octaves = 4
 var fine = FastNoiseLite.new()
 fine.seed = int(c.seed)+7
 fine.frequency = 0.03
 fine.fractal_octaves = 3
 var relief = float(c.relief)
 var rise = float(c.castle_rise)
 var fade = float(c.edge_fade)
 # The campaign heights come in 8 m steps at this scale: sample them on a coarse grid and smooth.
 var coarse_step = 16.0
 var cn = int(half*2.0/coarse_step)+1
 var coarse = PackedFloat32Array()
 coarse.resize(cn*cn)
 for j in cn:
  for i in cn:
   var x = -half+i*coarse_step
   var z = -half+j*coarse_step
   var s = 0.0
   for o in [Vector2.ZERO,Vector2(12,0),Vector2(-12,0),Vector2(0,12),Vector2(0,-12)]: s += float(base.call(x+o.x,z+o.y))
   coarse[j*cn+i] = s/5.0
 for j in n:
  var z = -half+j*cell
  for i in n:
   var x = -half+i*cell
   var cx = clampf((x+half)/coarse_step,0.0,cn-1.001)
   var cz = clampf((z+half)/coarse_step,0.0,cn-1.001)
   var x0 = int(cx)
   var z0 = int(cz)
   var bh = lerpf(lerpf(coarse[z0*cn+x0],coarse[z0*cn+x0+1],cx-x0),lerpf(coarse[(z0+1)*cn+x0],coarse[(z0+1)*cn+x0+1],cx-x0),cz-z0)
   var r = Vector2(x,z).length()
   # The valley floor stays gentle where the town stands; hills rise beyond it.
   var open = smoothstep(260.0,700.0,r)
   var edge = clampf(minf(half-absf(x),half-absf(z))/fade,0.0,1.0)
   edge = edge*edge*(3.0-2.0*edge)
   var hill = noise.get_noise_2d(x,z)*relief*(0.25+0.75*open)+maxf(0.0,ridge.get_noise_2d(x,z))*relief*0.9*open
   var cd = Vector2(x,z).distance_to(castle)
   var mound = rise*exp(-cd*cd/(2.0*95.0*95.0))
   var detail = fine.get_noise_2d(x,z)*0.35
   heights[j*n+i] = bh+(hill+mound+detail)*edge
 splat = Image.create(n,n,false,Image.FORMAT_RGBA8)
 splat.fill(Color(0,0,0,0))

func height_at(x: float,z: float) -> float:
 var gx = clampf((x+half)/cell,0.0,n-1.001)
 var gz = clampf((z+half)/cell,0.0,n-1.001)
 var x0 = int(gx)
 var z0 = int(gz)
 var fx = gx-x0
 var fz = gz-z0
 var a = lerpf(heights[z0*n+x0],heights[z0*n+x0+1],fx)
 var b = lerpf(heights[(z0+1)*n+x0],heights[(z0+1)*n+x0+1],fx)
 return lerpf(a,b,fz)

func normal_at(x: float,z: float) -> Vector3:
 var e = cell
 return Vector3(height_at(x-e,z)-height_at(x+e,z),2.0*e,height_at(x,z-e)-height_at(x,z+e)).normalized()

func inside(x: float,z: float,margin := 0.0) -> bool:
 return absf(x)<half-margin and absf(z)<half-margin

# Flatten the ground toward height h inside radius r (soft edge): building sites, the market square.
func flatten(p: Vector2,r: float,h: float,soft := 6.0):
 var i0 = maxi(0,int((p.x-r-soft+half)/cell))
 var i1 = mini(n-1,int((p.x+r+soft+half)/cell)+1)
 var j0 = maxi(0,int((p.y-r-soft+half)/cell))
 var j1 = mini(n-1,int((p.y+r+soft+half)/cell)+1)
 for j in range(j0,j1+1):
  for i in range(i0,i1+1):
   var d = Vector2(-half+i*cell,-half+j*cell).distance_to(p)
   var w = 1.0-smoothstep(r,r+soft,d)
   if w>0.0: heights[j*n+i] = lerpf(heights[j*n+i],h,w)

# Flatten a rectangle (local frame: centre, half extents, yaw) toward h.
func flatten_rect(c: Vector2,he: Vector2,yaw: float,h: float,soft := 3.0):
 var rr = he.length()+soft
 var i0 = maxi(0,int((c.x-rr+half)/cell))
 var i1 = mini(n-1,int((c.x+rr+half)/cell)+1)
 var j0 = maxi(0,int((c.y-rr+half)/cell))
 var j1 = mini(n-1,int((c.y+rr+half)/cell)+1)
 var cs = cos(yaw)
 var sn = sin(yaw)
 for j in range(j0,j1+1):
  for i in range(i0,i1+1):
   var d = Vector2(-half+i*cell,-half+j*cell)-c
   var l = Vector2(d.x*cs-d.y*sn,d.x*sn+d.y*cs)
   var ex = maxf(absf(l.x)-he.x,0.0)
   var ez = maxf(absf(l.y)-he.y,0.0)
   var w = 1.0-smoothstep(0.0,soft,Vector2(ex,ez).length())
   if w>0.0: heights[j*n+i] = lerpf(heights[j*n+i],h,w)

# Paint a splat channel (0 R road, 1 G bare ground, 2 B field, 3 A paving) along a polyline.
func paint_line(points: PackedVector2Array,width: float,channel: int,strength := 1.0):
 for k in points.size()-1:
  var a = points[k]
  var b = points[k+1]
  var steps = maxi(1,int(a.distance_to(b)/(cell*0.5)))
  for s in steps+1:
   paint_disc(a.lerp(b,float(s)/steps),width*0.5,channel,strength)

func paint_disc(p: Vector2,r: float,channel: int,strength := 1.0,soft := 1.5):
 var i0 = maxi(0,int((p.x-r-soft+half)/cell))
 var i1 = mini(n-1,int((p.x+r+soft+half)/cell)+1)
 var j0 = maxi(0,int((p.y-r-soft+half)/cell))
 var j1 = mini(n-1,int((p.y+r+soft+half)/cell)+1)
 for j in range(j0,j1+1):
  for i in range(i0,i1+1):
   var d = Vector2(-half+i*cell,-half+j*cell).distance_to(p)
   var w = (1.0-smoothstep(r,r+soft,d))*strength
   if w<=0.0: continue
   var c = splat.get_pixel(i,j)
   c[channel] = maxf(c[channel],w)
   splat.set_pixel(i,j,c)

func paint_rect(c: Vector2,he: Vector2,yaw: float,channel: int,strength := 1.0):
 var rr = he.length()+1.0
 var cs = cos(yaw)
 var sn = sin(yaw)
 for j in range(maxi(0,int((c.y-rr+half)/cell)),mini(n-1,int((c.y+rr+half)/cell)+1)+1):
  for i in range(maxi(0,int((c.x-rr+half)/cell)),mini(n-1,int((c.x+rr+half)/cell)+1)+1):
   var d = Vector2(-half+i*cell,-half+j*cell)-c
   var l = Vector2(d.x*cs-d.y*sn,d.x*sn+d.y*cs)
   if absf(l.x)<=he.x and absf(l.y)<=he.y:
    var col = splat.get_pixel(i,j)
    col[channel] = maxf(col[channel],strength)
    splat.set_pixel(i,j,col)

func splat_at(x: float,z: float) -> Color:
 var i = clampi(int((x+half)/cell+0.5),0,n-1)
 var j = clampi(int((z+half)/cell+0.5),0,n-1)
 return splat.get_pixel(i,j)

# --- Meshes and collision ----------------------------------------------------------------------

func finish(mat: ShaderMaterial):
 material = mat
 splat_tex = ImageTexture.create_from_image(splat)
 material.set_shader_parameter("splat",splat_tex)
 material.set_shader_parameter("area_half",half)
 var per = int(float(cfg.chunk)/cell)
 var chunks = int(ceil(float(n-1)/per))
 for cj in chunks:
  for ci in chunks:
   var holder = Node3D.new()
   holder.name = "chunk_%d_%d" % [ci,cj]
   add_child(holder)
   for lod in CHUNK_LODS:
    var mi = MeshInstance3D.new()
    mi.mesh = _chunk_mesh(ci*per,cj*per,per,int(lod[0]))
    mi.material_override = material
    mi.visibility_range_begin = float(lod[1])
    mi.visibility_range_end = float(lod[2])
    mi.visibility_range_begin_margin = 20.0 if lod[1]>0.0 else 0.0
    mi.visibility_range_end_margin = 20.0 if lod[2]>0.0 else 0.0
    if lod[0]>1: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    holder.add_child(mi)
 _collision()

func refresh_splat():
 splat_tex.update(splat)

func _chunk_mesh(i0: int,j0: int,per: int,step: int) -> ArrayMesh:
 var i1 = mini(i0+per,n-1)
 var j1 = mini(j0+per,n-1)
 var verts = PackedVector3Array()
 var norms = PackedVector3Array()
 var idx = PackedInt32Array()
 var xs = []
 var i = i0
 while i<i1:
  xs.append(i)
  i += step
 xs.append(i1)
 var zs = []
 var j = j0
 while j<j1:
  zs.append(j)
  j += step
 zs.append(j1)
 var w = xs.size()
 for jj in zs:
  for ii in xs:
   var x = -half+ii*cell
   var z = -half+jj*cell
   verts.append(Vector3(x,heights[jj*n+ii],z))
   norms.append(normal_at(x,z))
 for b in zs.size()-1:
  for a in w-1:
   var v = b*w+a
   idx.append_array([v,v+1,v+w,v+1,v+w+1,v+w])
 # Skirts hide the cracks between LODs: a strip hanging 4 m below each edge.
 var ring = []
 for a in w: ring.append(a)
 for b in range(1,zs.size()): ring.append(b*w+w-1)
 for a in range(w-2,-1,-1): ring.append((zs.size()-1)*w+a)
 for b in range(zs.size()-2,0,-1): ring.append(b*w)
 ring.append(0)
 var base = verts.size()
 for k in ring:
  verts.append(verts[k]-Vector3(0,4.0,0))
  norms.append(norms[k])
 for k in ring.size()-1:
  var a0 = ring[k]
  var a1 = ring[k+1]
  idx.append_array([a0,base+k,a1,a1,base+k,base+k+1])
  idx.append_array([a0,a1,base+k,a1,base+k+1,base+k])
 var arr = []
 arr.resize(Mesh.ARRAY_MAX)
 arr[Mesh.ARRAY_VERTEX] = verts
 arr[Mesh.ARRAY_NORMAL] = norms
 arr[Mesh.ARRAY_INDEX] = idx
 var m = ArrayMesh.new()
 m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
 return m

func _collision():
 body = StaticBody3D.new()
 body.name = "Ground"
 body.collision_layer = 1
 add_child(body)
 var shape = HeightMapShape3D.new()
 shape.map_width = n
 shape.map_depth = n
 shape.map_data = heights
 var cs = CollisionShape3D.new()
 cs.shape = shape
 cs.scale = Vector3(cell,1.0,cell)
 body.add_child(cs)
