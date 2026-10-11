extends RefCounted
# Turns the procedural culture kits (visuals/kits/cultures/culture_kit.gd, landmark_kit.gd) into
# destructible chunks for the god-game look test: every kit shape (box, gable prism, cylinder or
# cone, hemisphere) becomes one or more convex chunks at character scale, large shapes pre-fractured
# along seams (walls into blocks, towers into drums), each with a PBR material class picked from its
# kit colour and shape, planar UVs per face in world metres (so textures line up across pieces and
# stay put on flying debris), tangents, and a vertex tint (rgb: kit colour, a: height for grime).
# The kits stay the single source of the architecture; only the look test reads this.

const MAX_PIECE = 3.6 # metres: larger shapes split into pieces about this size
# --flat (god/materials.gd flat): plain kit colours in the vertex tint.
static func set_flat(on: bool):
 Builder.flat_mode = on

# Material classes: [texture set folder, metres per texture tile, roughness scale].
const MATS = {
 "stone": ["castle_wall_slates",3.2],
 "house_stone": ["rustic_stone_wall",2.4],
 "plaster": ["white_plaster_rough_01",2.2],
 "timber": ["rough_wood",1.4],
 "planks": ["medieval_wood",2.0],
 "slate": ["roof_slates_02",2.4],
 "thatch": ["thatch_roof_angled",2.6],
 "window": ["wood_shutter",0.9],
 "door": ["rough_pine_door",2.2],
 "bark": ["pine_bark",1.6],
 "leaves": ["thatch_roof_angled",1.8],
 "cloth": ["white_plaster_rough_01",1.2],
 "void": ["",1.0],
 "glow": ["",1.0],
 "glass": ["",1.0],
 "water": ["",1.0],
}
const MAT_IDS = ["stone","house_stone","plaster","timber","planks","slate","thatch","window","door","bark","leaves","cloth","void","glow","glass","water"]

static func mat_id(name: String) -> int:
 return MAT_IDS.find(name)

# Every chunk of a kit node tree, at `xf` (character-scale placement: includes the kit scale).
# base_y: the ground height under the piece (the grime gradient starts there).
static func collect(root: Node3D,xf: Transform3D,base_y := 0.0,stone_class := "house_stone") -> Array:
 var out = []
 for mi in root.find_children("*","MeshInstance3D",true,false):
  if mi.mesh == null: continue
  var t = Transform3D.IDENTITY
  var p: Node = mi
  while p != null and p != root:
   t = (p as Node3D).transform*t
   p = p.get_parent()
  var mat = mi.get_surface_override_material(0)
  if mat == null: mat = mi.mesh.surface_get_material(0)
  var col = Color(0.7,0.7,0.7)
  var glow = false
  if mat is BaseMaterial3D:
   col = mat.albedo_color
   glow = mat.emission_enabled
  _shape(out,mi.mesh,xf*t,col,glow,base_y,stone_class)
 return out

static func _classify(mesh: Mesh,c: Color,glow: bool,stone_class: String) -> String:
 if glow: return "glow"
 var h = c.h*360.0
 var s = c.s
 var v = c.v
 if c.to_html(false) in ["8fd0d8","3f7fa6"]: return "water"
 if c.to_html(false) == "9ec8b8": return "glass"
 if c.to_html(false) == "eae6dc": return "bark"
 if mesh is SphereMesh and s>0.5 and (h<20.0 or h>340.0): return "leaves"
 var roof = mesh is PrismMesh or (mesh is CylinderMesh and (mesh as CylinderMesh).top_radius == 0.0)
 var thin = false
 if mesh is BoxMesh:
  var sz = (mesh as BoxMesh).size
  thin = minf(sz.x,minf(sz.y,sz.z))<0.2
  if v<0.2 and sz.y>2.6: return "void" # gate openings
  if v<0.3 and absf(sz.y-1.1)<0.25 and sz.x<0.9: return "door"
  if v<0.22 and maxf(sz.x,sz.z)<0.6 and sz.y<0.7: return "window"
 if roof:
  if h>25.0 and h<60.0 and s>0.3: return "thatch"
  return "slate"
 if v<0.2: return "void"
 if h>10.0 and h<50.0 and s>0.3 and v<0.62: return "timber" if thin or mesh is CylinderMesh else "planks"
 if s>0.45: return "cloth"
 if v>0.72 and s<0.25: return "plaster"
 return stone_class

# --- Geometry -------------------------------------------------------------------------------------

static func _shape(out: Array,mesh: Mesh,xf: Transform3D,col: Color,glow: bool,base_y: float,stone_class: String):
 var cls = _classify(mesh,col,glow,stone_class)
 if not Builder.flat_mode: _trim(out,mesh,xf,cls,base_y,stone_class)
 if mesh is BoxMesh:
  var sz = (mesh as BoxMesh).size
  var w = xf.basis.get_scale()*sz
  var nx = maxi(1,int(ceil(w.x/MAX_PIECE)))
  var ny = maxi(1,int(ceil(w.y/MAX_PIECE)))
  var nz = maxi(1,int(ceil(w.z/MAX_PIECE)))
  for i in nx:
   for j in ny:
    for k in nz:
     var lo = Vector3(-0.5+float(i)/nx,-0.5+float(j)/ny,-0.5+float(k)/nz)*sz
     var hi = Vector3(-0.5+float(i+1)/nx,-0.5+float(j+1)/ny,-0.5+float(k+1)/nz)*sz
     var b = Builder.new(cls,col,base_y)
     b.box(xf,lo,hi)
     out.append(b.done())
 elif mesh is PrismMesh:
  var sz = (mesh as PrismMesh).size
  var length = (xf.basis*Vector3(0,0,sz.z)).length()
  var nz = maxi(1,int(ceil(length/(MAX_PIECE*1.2))))
  for k in nz:
   var b = Builder.new(cls,col,base_y)
   b.prism(xf,sz,-0.5+float(k)/nz,-0.5+float(k+1)/nz)
   out.append(b.done())
 elif mesh is CylinderMesh:
  var cm = mesh as CylinderMesh
  var hgt = (xf.basis*Vector3(0,cm.height,0)).length()
  var ny = 1 if cm.top_radius == 0.0 else maxi(1,int(ceil(hgt/MAX_PIECE)))
  var rmax = maxf(cm.top_radius,cm.bottom_radius)*xf.basis.get_scale().x
  var sectors = 1 if rmax<2.2 or cm.radial_segments<6 else (2 if rmax<4.0 else 4)
  for j in ny:
   for s in sectors:
    var b = Builder.new(cls,col,base_y)
    b.cylinder(xf,cm,float(j)/ny,float(j+1)/ny,s,sectors)
    out.append(b.done())
 elif mesh is SphereMesh:
  var b = Builder.new(cls,col,base_y)
  b.dome(xf,mesh as SphereMesh)
  out.append(b.done())
 else:
  # Any other mesh: take its triangles whole.
  var b = Builder.new(cls,col,base_y)
  b.arrays(xf,mesh.surface_get_arrays(0))
  out.append(b.done())

class Builder:
 static var flat_mode := false
 var cls: String
 var col: Color
 var base_y: float
 var tile: float
 var long_axis := Vector3.ZERO # wood grain follows a beam's length
 var v := PackedVector3Array()
 var n := PackedVector3Array()
 var uv := PackedVector2Array()
 var tg := PackedFloat32Array()
 var c := PackedColorArray()
 var hull := PackedVector3Array()
 var inside := Vector3.ZERO

 func _init(k: String,colour: Color,by: float):
  cls = k
  col = colour
  base_y = by
  tile = float(MATS[k][1])

 # Planar UVs in the face's own frame: u along the face horizontally (or along the beam for wood),
 # v up the face (down the slope on roofs).
 func tri(a: Vector3,b: Vector3,d: Vector3,na := Vector3.ZERO,nb := Vector3.ZERO,nd := Vector3.ZERO):
  var fn = (b-a).cross(d-a)
  if fn.length_squared()<1e-12: return
  fn = -fn.normalized() # Godot's front faces wind clockwise
  # Convex pieces: every face points away from the piece's inside point.
  if fn.dot((a+b+d)/3.0-inside)<0.0:
   var tmp = b
   b = d
   d = tmp
   var tn = nb
   nb = nd
   nd = tn
   fn = -fn
  if na == Vector3.ZERO:
   na = fn
   nb = fn
   nd = fn
  var u_ax: Vector3
  if absf(fn.y)>0.92: u_ax = Vector3(1,0,0)
  else: u_ax = Vector3.UP.cross(fn).normalized()
  if long_axis != Vector3.ZERO:
   var la = (long_axis-fn*long_axis.dot(fn))
   if la.length()>0.3: u_ax = la.normalized()
  var v_ax = fn.cross(u_ax).normalized()
  if absf(fn.y)<=0.92 and long_axis == Vector3.ZERO and v_ax.y<0.0: v_ax = -v_ax
  var sign = 1.0 if fn.cross(u_ax).dot(v_ax)>0.0 else -1.0
  var tint = _tint()
  for p in [[a,na],[b,nb],[d,nd]]:
   v.append(p[0])
   n.append(p[1])
   uv.append(Vector2(p[0].dot(u_ax),-p[0].dot(v_ax))/tile)
   tg.append_array([u_ax.x,u_ax.y,u_ax.z,sign])
   c.append(Color(tint.r,tint.g,tint.b,clampf((p[0].y-base_y)/7.0,0.0,1.0)))

 func _tint() -> Color:
  # The kit colour as a gentle multiplier around the texture's own colour (keeps per-house variety).
  var l = maxf(0.05,col.r*0.3+col.g*0.59+col.b*0.11)
  var hue = Color(col.r/l,col.g/l,col.b/l)*clampf(l*1.6,0.55,1.25)
  if cls in ["glow","glass","water","void","leaves","bark","cloth"] or flat_mode: return col
  return Color(1,1,1).lerp(hue,0.32)

 func quad(a: Vector3,b: Vector3,cc: Vector3,d: Vector3):
  tri(a,b,cc)
  tri(a,cc,d)

 func box(xf: Transform3D,lo: Vector3,hi: Vector3):
  inside = xf*((lo+hi)*0.5)
  var p = []
  for k in 8: p.append(xf*Vector3(hi.x if k&1 else lo.x,hi.y if k&2 else lo.y,hi.z if k&4 else lo.z))
  if cls in ["timber","planks"]:
   var ext = [(p[1]-p[0]).length(),(p[2]-p[0]).length(),(p[4]-p[0]).length()]
   var axes = [p[1]-p[0],p[2]-p[0],p[4]-p[0]]
   long_axis = axes[ext.find(ext.max())].normalized()
  quad(p[0],p[2],p[3],p[1]) # -z
  quad(p[4],p[5],p[7],p[6]) # +z
  quad(p[0],p[4],p[6],p[2]) # -x
  quad(p[1],p[3],p[7],p[5]) # +x
  quad(p[2],p[6],p[7],p[3]) # +y
  quad(p[0],p[1],p[5],p[4]) # -y
  for q in p: hull.append(q)

 # PrismMesh: size (x width, y height, z depth), apex along x = 0 at the top; z0..z1 a slice of depth.
 func prism(xf: Transform3D,sz: Vector3,z0: float,z1: float):
  var h = sz.y*0.5
  var w = sz.x*0.5
  var za = z0*sz.z
  var zb = z1*sz.z
  var l0 = xf*Vector3(-w,-h,za)
  var r0 = xf*Vector3(w,-h,za)
  var t0 = xf*Vector3(0,h,za)
  var l1 = xf*Vector3(-w,-h,zb)
  var r1 = xf*Vector3(w,-h,zb)
  inside = xf*Vector3(0,-h*0.33,(za+zb)*0.5)
  var t1 = xf*Vector3(0,h,zb)
  tri(l0,t0,r0)
  tri(l1,r1,t1)
  quad(l0,l1,t1,t0)
  quad(r0,t0,t1,r1)
  quad(l0,r0,r1,l1)
  for q in [l0,r0,t0,l1,r1,t1]: hull.append(q)

 # A slice (rows f0..f1 of the height, sector s of `sectors`) of a CylinderMesh (smooth sides).
 func cylinder(xf: Transform3D,cm: CylinderMesh,f0: float,f1: float,s: int,sectors: int):
  var segs = cm.radial_segments
  var hh = cm.height*0.5
  var y0 = -hh+f0*cm.height
  var y1 = -hh+f1*cm.height
  var r0 = lerpf(cm.bottom_radius,cm.top_radius,f0)
  var r1 = lerpf(cm.bottom_radius,cm.top_radius,f1)
  var a0 = int(float(s)*segs/sectors)
  var a1 = int(float(s+1)*segs/sectors)
  var nb = xf.basis.inverse().transposed()
  var slope = (cm.bottom_radius-cm.top_radius)/cm.height
  var mid_r = (r0+r1)*0.5
  var mid_a = TAU*(a0+a1)*0.5/segs
  inside = xf*(Vector3(0,lerpf(y0,y1,0.4 if r1<0.0001 else 0.5),0)+(Vector3(cos(mid_a),0,sin(mid_a))*mid_r*0.45 if sectors>1 else Vector3.ZERO))
  for i in range(a0,a1):
   var t0 = TAU*i/segs
   var t1 = TAU*(i+1)/segs
   var d0 = Vector3(cos(t0),0,sin(t0))
   var d1 = Vector3(cos(t1),0,sin(t1))
   var n0 = (nb*(d0+Vector3(0,slope,0))).normalized()
   var n1 = (nb*(d1+Vector3(0,slope,0))).normalized()
   var p00 = xf*(d0*r0+Vector3(0,y0,0))
   var p01 = xf*(d1*r0+Vector3(0,y0,0))
   var p10 = xf*(d0*r1+Vector3(0,y1,0))
   var p11 = xf*(d1*r1+Vector3(0,y1,0))
   if r1>0.0001:
    tri(p00,p10,p11,n0,n0,n1)
    tri(p00,p11,p01,n0,n1,n1)
   else:
    tri(p00,p10,p01,n0,(n0+n1).normalized(),n1)
   var cb = xf*Vector3(0,y0,0)
   tri(cb,p00,p01)
   if r1>0.0001: tri(xf*Vector3(0,y1,0),p11,p10)
   hull.append_array(PackedVector3Array([p00,p01,p10,p11]))
  if sectors>1:
   # Close the wedge's cut faces.
   for a in [a0,a1]:
    var t = TAU*a/segs
    var d = Vector3(cos(t),0,sin(t))
    var q0 = xf*Vector3(0,y0,0)
    var q1 = xf*Vector3(0,y1,0)
    var q2 = xf*(d*r1+Vector3(0,y1,0))
    var q3 = xf*(d*r0+Vector3(0,y0,0))
    if a == a0: quad(q0,q1,q2,q3)
    else: quad(q0,q3,q2,q1)
   hull.append(xf*Vector3(0,y0,0))
   hull.append(xf*Vector3(0,y1,0))

 func dome(xf: Transform3D,sm: SphereMesh):
  var r = sm.radius
  var segs = 12
  var rings = 5
  inside = xf*Vector3(0,r*0.3,0)
  var nb = xf.basis.inverse().transposed()
  for j in rings:
   var p0 = PI*0.5*j/rings
   var p1 = PI*0.5*(j+1)/rings
   for i in segs:
    var t0 = TAU*i/segs
    var t1 = TAU*(i+1)/segs
    var q = []
    for pp in [[p0,t0],[p0,t1],[p1,t1],[p1,t0]]:
     q.append(Vector3(cos(pp[1])*cos(pp[0]),sin(pp[0]),sin(pp[1])*cos(pp[0])))
    var w = []
    for d in q: w.append(xf*(d*r))
    var nn = []
    for d in q: nn.append((nb*d).normalized())
    tri(w[0],w[3],w[2],nn[0],nn[3],nn[2])
    tri(w[0],w[2],w[1],nn[0],nn[2],nn[1])
    for p in w: hull.append(p)

 func arrays(xf: Transform3D,a: Array):
  var vv = a[Mesh.ARRAY_VERTEX]
  var idx = a[Mesh.ARRAY_INDEX]
  if idx == null or idx.is_empty():
   idx = PackedInt32Array()
   for i in vv.size(): idx.append(i)
  inside = Vector3.ZERO
  for p in vv: inside += xf*p
  inside /= maxf(1.0,vv.size())
  for i in range(0,idx.size(),3): tri(xf*vv[idx[i]],xf*vv[idx[i+1]],xf*vv[idx[i+2]])
  for p in vv: hull.append(xf*p)

 func done() -> Dictionary:
  var center = Vector3.ZERO
  for p in hull: center += p
  center /= maxf(1.0,hull.size())
  var lo = Vector3(INF,INF,INF)
  var hi = -lo
  var local = PackedVector3Array()
  for p in hull:
   lo = lo.min(p)
   hi = hi.max(p)
   local.append(p-center)
  return {"m":MAT_IDS.find(cls),"v":v,"n":n,"uv":uv,"t":tg,"c":c,"center":center,"hull":local,"size":hi-lo,"alive":true}

# --- Trim (the material pass; not in --flat) ------------------------------------------------------
# Kit pieces are bare shapes; at 5 m they need the joinery that sells them: barge boards, a ridge
# beam and fascias on every gable roof, a frame and a sill round every window, quoins up the corners of
# stone ground floors. Sizes in kit metres (before kit_scale), added as chunks of their own.
const TRIM_TIMBER = Color("4a3524")
const TRIM_STONE = Color("9a958c")

static func _trim(out: Array,mesh: Mesh,xf: Transform3D,cls: String,base_y: float,stone_class: String):
 if mesh is PrismMesh and cls in ["slate","thatch"]:
  var sz = (mesh as PrismMesh).size
  var hx = sz.x*0.5
  var hy = sz.y*0.5
  var hz = sz.z*0.5
  var slope = atan2(sz.y,hx)
  var edge = Vector2(hx,sz.y).length()
  for zs in [-1.0,1.0]:
   for xs in [-1.0,1.0]:
    # A barge board up each sloped gable edge.
    var mid = Vector3(xs*hx*0.5,0.0,zs*(hz+0.025))
    var bx = Transform3D(Basis(Vector3.BACK,-xs*slope),mid)
    _box(out,xf*bx,Vector3(edge+0.12,0.13,0.05),"timber",TRIM_TIMBER,base_y)
  # Ridge beam and the fascia boards along both eaves.
  _box(out,xf*Transform3D(Basis(),Vector3(0,hy+0.03,0)),Vector3(0.14,0.1,sz.z+0.16),"timber",TRIM_TIMBER,base_y)
  for xs in [-1.0,1.0]: _box(out,xf*Transform3D(Basis(),Vector3(xs*(hx-0.02),-hy+0.04,0)),Vector3(0.05,0.12,sz.z+0.04),"timber",TRIM_TIMBER,base_y)
 elif mesh is BoxMesh and cls == "window":
  var sz = (mesh as BoxMesh).size
  var along_x = sz.x>sz.z
  var w = sz.x if along_x else sz.z
  var d = 0.14
  var frame = func(size: Vector3,pos: Vector3,c: String,col: Color):
   var s = size if along_x else Vector3(size.z,size.y,size.x)
   _box(out,xf*Transform3D(Basis(),pos),s,c,col,base_y)
  frame.call(Vector3(w+0.14,0.06,d),Vector3(0,sz.y*0.5+0.03,0),"timber",TRIM_TIMBER)
  frame.call(Vector3(w+0.2,0.05,d+0.06),Vector3(0,-sz.y*0.5-0.025,0),"stone",TRIM_STONE)
  for s in [-1.0,1.0]:
   var p = Vector3(s*(w*0.5+0.035),0,0) if along_x else Vector3(0,0,s*(w*0.5+0.035))
   frame.call(Vector3(0.06,sz.y+0.06,d),p,"timber",TRIM_TIMBER)
 elif mesh is BoxMesh and cls == "stone" and stone_class == "stone":
  # Castle walls and the keep: arrow slits (and taller windows on the big blocks) in rows.
  var sz = (mesh as BoxMesh).size
  if sz.y<3.0 or maxf(sz.x,sz.z)<2.8: return
  var big = minf(sz.x,sz.z)>4.0
  var slit = Vector3(0.16,0.75,0.08) if not big else Vector3(0.45,1.3,0.08)
  var rows = int((sz.y-2.5)/(2.4 if not big else 2.8))
  for face in 4:
   var along_x = face<2
   var width = sz.x if along_x else sz.z
   var depth = sz.z if along_x else sz.x
   var sgn = -1.0 if face%2 == 0 else 1.0
   var n = int(width/(2.6 if not big else 2.2))
   if n<1 or (not big and depth>width): continue
   for r in rows:
    for i in n:
     var u = -width*0.5+(i+0.5)*width/n
     var y = -sz.y*0.5+2.2+r*(2.4 if not big else 2.8)
     var p = Vector3(u,y,sgn*(depth*0.5+0.02)) if along_x else Vector3(sgn*(depth*0.5+0.02),y,u)
     var s = slit if along_x else Vector3(slit.z,slit.y,slit.x)
     _box(out,xf*Transform3D(Basis(),p),s,"void",Color("16120f"),base_y)
 elif mesh is CylinderMesh and cls == "stone" and (mesh as CylinderMesh).top_radius>0.5 and (mesh as CylinderMesh).height>6.0:
  # Round towers: slits round the drum, staggered.
  var cm = mesh as CylinderMesh
  var rows = int((cm.height-3.0)/3.0)
  for r in rows:
   var f = (1.5+r*3.0)/cm.height
   var y = -cm.height*0.5+1.5+r*3.0
   var rad = lerpf(cm.bottom_radius,cm.top_radius,f)+0.02
   for i in 4:
    var a = TAU*i/4.0+(0.785 if r%2 == 1 else 0.0)
    var p = Vector3(cos(a)*rad,y,sin(a)*rad)
    _box(out,xf*Transform3D(Basis(Vector3.UP,-a),p),Vector3(0.08,0.75,0.16),"void",Color("16120f"),base_y)
 elif mesh is BoxMesh and cls == "house_stone" and stone_class == "house_stone":
  var sz = (mesh as BoxMesh).size
  if sz.y<0.9 or sz.y>2.0 or minf(sz.x,sz.z)<1.6: return
  # Quoins: dressed blocks alternating long and short up each corner.
  var n = int(sz.y/0.3)
  for xs in [-1.0,1.0]:
   for zs in [-1.0,1.0]:
    for k in n:
     var long = k%2 == 0
     var bs = Vector3(0.36 if long else 0.22,0.27,0.22 if long else 0.36)
     var p = Vector3(xs*(sz.x*0.5-bs.x*0.5+0.025),-sz.y*0.5+0.15+k*0.3,zs*(sz.z*0.5-bs.z*0.5+0.025))
     _box(out,xf*Transform3D(Basis(),p),bs,"stone",TRIM_STONE.darkened(0.04*(k%3)),base_y)

static func _box(out: Array,xf: Transform3D,size: Vector3,cls: String,col: Color,base_y: float):
 var b = Builder.new(cls,col,base_y)
 b.box(xf,-size*0.5,size*0.5)
 var ch = b.done()
 ch.trim = true # drawn and breakable, but no collision shape of its own
 out.append(ch)
