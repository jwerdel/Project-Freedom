extends RefCounted
# Tall firs for the god-game look test, built at start (no tree asset held up stretched to 15 m:
# the CC0 Poly Haven fir is a sapling, kept as undergrowth in god/foliage.gd). A tapered trunk with
# the CC0 pine bark set, and whorls of drooping branch cards textured with a needle spray drawn here
# (twigs and needles into an alpha image), normals bent outward from the trunk so the crown shades
# as one volume. About 500 triangles a tree. One mesh per variant, two surfaces (bark, needles).

const Materials = preload("res://god/materials.gd")

static var _needle_tex: ImageTexture
static var _needle_n: ImageTexture

static func needle_texture() -> ImageTexture:
 if _needle_tex != null: return _needle_tex
 var w = 512
 var h = 256
 var img = Image.create(w,h,false,Image.FORMAT_RGBA8)
 img.fill(Color(0.1,0.16,0.1,0.0))
 var rng = RandomNumberGenerator.new()
 rng.seed = 31
 var twig = Color(0.22,0.17,0.12,1.0)
 # The main twig along x, sagging a little; side twigs angled forward; needles all along.
 var twigs = [[Vector2(0,h*0.5),Vector2(w*0.97,h*0.47),4.0]]
 var x = 26.0
 var side = 1.0
 while x<w*0.85:
  var len = (w-x)*rng.randf_range(0.35,0.55)
  var a = deg_to_rad(rng.randf_range(32,48))*side
  var p0 = Vector2(x,h*0.5-x*0.06)
  twigs.append([p0,p0+Vector2(cos(a),sin(a))*len,2.2])
  side = -side
  x += rng.randf_range(22,34)
 for tw in twigs:
  var a: Vector2 = tw[0]
  var b: Vector2 = tw[1]
  var dir = (b-a).normalized()
  var steps = int(a.distance_to(b))
  for s in steps:
   var p = a.lerp(b,float(s)/steps)
   var t = float(s)/steps
   _dot(img,p,tw[2]*(1.0-t*0.5),twig)
   # Needles: short strokes both sides, angled forward.
   if s%2 == 0:
    for sgn in [-1.0,1.0]:
     var nl = rng.randf_range(10.0,18.0)*(1.0-t*0.4)
     var na = dir.rotated(deg_to_rad(rng.randf_range(50,75))*sgn)
     var g = rng.randf_range(0.0,1.0)
     var col = Color(0.1+g*0.05,0.19+g*0.09,0.1+g*0.04,1.0)
     for k in int(nl):
      _dot(img,p+na*k,1.3,col.lerp(Color(0.2,0.3,0.15,1.0),float(k)/nl*0.5))
 # Dilate colour into the transparent texels so mipmaps do not darken the edges.
 img.generate_mipmaps()
 _needle_tex = ImageTexture.create_from_image(img)
 return _needle_tex

static func _dot(img: Image,p: Vector2,r: float,c: Color):
 var ri = int(ceil(r))
 for y in range(int(p.y)-ri,int(p.y)+ri+1):
  for x in range(int(p.x)-ri,int(p.x)+ri+1):
   if x<0 or y<0 or x>=img.get_width() or y>=img.get_height(): continue
   if Vector2(x,y).distance_to(p)<=r: img.set_pixel(x,y,c)

# A fir `height` metres tall (trunk at the origin, +y up). seed varies the whorls.
static func build(height: float,seed: int) -> ArrayMesh:
 var rng = RandomNumberGenerator.new()
 rng.seed = seed
 var bark = SurfaceTool.new()
 bark.begin(Mesh.PRIMITIVE_TRIANGLES)
 var r0 = height*0.018+0.12
 var segs = 7
 var rings = 4
 var trunk_h = height*0.9
 for j in rings:
  var y0 = trunk_h*j/rings
  var y1 = trunk_h*(j+1)/rings
  var ra = r0*(1.0-0.95*float(j)/rings)
  var rb = r0*(1.0-0.95*float(j+1)/rings)
  for i in segs:
   var a0 = TAU*i/segs
   var a1 = TAU*(i+1)/segs
   var q = [Vector3(cos(a0)*ra,y0,sin(a0)*ra),Vector3(cos(a1)*ra,y0,sin(a1)*ra),Vector3(cos(a1)*rb,y1,sin(a1)*rb),Vector3(cos(a0)*rb,y1,sin(a0)*rb)]
   var uv = [Vector2(float(i)/segs,y0/1.6),Vector2(float(i+1)/segs,y0/1.6),Vector2(float(i+1)/segs,y1/1.6),Vector2(float(i)/segs,y1/1.6)]
   for k in [0,2,1,0,3,2]:
    var n = Vector3(q[k].x,0,q[k].z).normalized()
    bark.set_normal(n)
    bark.set_uv(uv[k])
    bark.add_vertex(q[k])
 bark.generate_tangents()
 var nd = SurfaceTool.new()
 nd.begin(Mesh.PRIMITIVE_TRIANGLES)
 # Whorls from a bare lower trunk to the tip; branch length follows a cone with a slight belly.
 var y = height*rng.randf_range(0.12,0.2)
 var whorl = 0
 while y<height*0.97:
  var t = (y-height*0.12)/(height*0.88)
  var reach = height*0.21*pow(1.0-t,0.9)+0.35
  var n = int(lerpf(8.0,4.0,t))
  var spin = rng.randf()*TAU
  for i in n:
   var a = spin+TAU*i/n+rng.randf_range(-0.2,0.2)
   var dir = Vector3(cos(a),0,sin(a))
   var l = reach*rng.randf_range(0.8,1.15)
   var droop = rng.randf_range(0.25,0.5)*(1.0-t*0.6)
   _branch(nd,Vector3(0,y,0)+dir*r0*0.5,dir,l,l*0.5,droop,rng)
  whorl += 1
  y += lerpf(0.75,0.35,t)*height/16.0+rng.randf_range(0.0,0.2)
 # A leader at the tip.
 _branch(nd,Vector3(0,height*0.9,0),Vector3(0.05,1,0).normalized(),height*0.12,height*0.05,-0.6,rng)
 var mesh = bark.commit()
 nd.generate_tangents()
 nd.commit(mesh)
 return mesh

# One branch: two cards crossed along its length (flat and tilted), bending down by `droop`.
static func _branch(st: SurfaceTool,root: Vector3,dir: Vector3,length: float,width: float,droop: float,rng: RandomNumberGenerator):
 var side = dir.cross(Vector3.UP).normalized() if absf(dir.y)<0.9 else Vector3.RIGHT
 var mid = root+dir*length*0.5+Vector3(0,-droop*length*0.25,0)
 var tip = root+dir*length+Vector3(0,-droop*length,0)
 for k in 2:
  var roll = rng.randf_range(-0.25,0.25)+(0.0 if k == 0 else 1.1)
  var s = (side*cos(roll)+Vector3.UP*sin(roll)).normalized()*width*0.5
  var pts = [root,mid,tip]
  var us = [0.0,0.5,1.0]
  for seg in 2:
   var a = pts[seg]
   var b = pts[seg+1]
   var wa = 1.0 if seg == 0 else 0.85
   var wb = 0.85 if seg == 0 else 0.4
   var q = [a-s*wa,b-s*wb,b+s*wb,a+s*wa]
   var uv = [Vector2(us[seg],1.0),Vector2(us[seg+1],1.0),Vector2(us[seg+1],0.0),Vector2(us[seg],0.0)]
   for idx in [0,1,2,0,2,3]:
    var p = q[idx]
    # Crown normals: out from the trunk and up, so the needles shade as one mass.
    var n = (Vector3(p.x,0,p.z).normalized()*0.8+Vector3(0,0.6,0)).normalized()
    st.set_normal(n)
    st.set_uv(uv[idx])
    st.set_color(Color(1,1,1,clampf(p.y,0.0,1.0)))
    st.add_vertex(p)

static func materials(snow: float) -> Array:
 var bark = ShaderMaterial.new()
 bark.shader = load("res://god/surface.gdshader")
 bark.set_shader_parameter("albedo_tex",Materials.tex("pine_bark","diff"))
 bark.set_shader_parameter("normal_tex",Materials.tex("pine_bark","nor_gl"))
 bark.set_shader_parameter("arm_tex",Materials.tex("pine_bark","arm"))
 bark.set_shader_parameter("snow_tex",Materials.tex("snow_02","diff"))
 bark.set_shader_parameter("snow_n",Materials.tex("snow_02","nor_gl"))
 bark.set_shader_parameter("snow",0.2)
 bark.set_shader_parameter("grime",0.0)
 var needles = ShaderMaterial.new()
 needles.shader = load("res://god/tree.gdshader")
 needles.set_shader_parameter("albedo_tex",needle_texture())
 needles.set_shader_parameter("snow",snow)
 needles.set_shader_parameter("use_normal_map",false)
 return [bark,needles]
