extends Node3D
# Prototype farmland: an irregular patchwork of fields draped exactly on the terrain mesh, with
# crop colors, furrows, grassy headlands, hedgerows and a few fences. Builds in world space;
# the node stays at the origin.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const SHADER = preload("res://visuals/terrain/farmland.gdshader")
const INSET = 0.4
# Crop color, furrow strength, weight.
const CROPS = [
 [Color("a8924f"),0.75,4], # ripe wheat
 [Color("9f9962"),0.65,3], # barley
 [Color("6f8a3f"),0.85,3], # young green crop
 [Color("566e35"),0.9,2],  # beans / roots
 [Color("6c5540"),1.0,3],  # ploughed earth
 [Color("7d8449"),0.0,2],  # hay meadow
 [Color("ad9a46"),0.6,1],  # flowering flax / mustard
]

var _height: Callable
var _ground: Callable
var _open: Callable

# ctx.center: Vector2 patchwork center; ctx.half_size: Vector2 local half extents;
# ctx.angle: float grid rotation; ctx.seed: int; ctx.height: Callable(x, z) -> terrain height;
# ctx.ground: Callable(Vector2, offset) -> Vector3; ctx.open: Callable(Vector2) -> float,
# 1 where fields may grow, 0 on roads and settlements.
func build(ctx: Dictionary):
 _height = ctx.height
 _ground = ctx.ground
 _open = ctx.open
 var rng = RandomNumberGenerator.new()
 rng.seed = ctx.seed
 var center: Vector2 = ctx.center
 var half: Vector2 = ctx.half_size
 var to_world = func(l: Vector2) -> Vector2: return center+l.rotated(ctx.angle)
 var cols = _splits(-half.x,half.x,4.2,8.0,rng)
 var rows = _splits(-half.y,half.y,3.6,6.8,rng)
 # Jittered grid corners in world space.
 var corners = []
 for j in rows.size():
  var line = []
  for i in cols.size():
   line.append(to_world.call(Vector2(cols[i],rows[j])+Vector2(rng.randf_range(-1.35,1.35),rng.randf_range(-1.35,1.35))))
  corners.append(line)
 var fields = []
 var edges = {}
 for j in rows.size()-1:
  for i in cols.size()-1:
   var quad = [corners[j][i],corners[j][i+1],corners[j+1][i+1],corners[j+1][i]]
   var mid = (quad[0]+quad[1]+quad[2]+quad[3])*0.25
   var local = (mid-center).rotated(-ctx.angle)
   var shape = pow(local.x/half.x,2)+pow(local.y/half.y,2)
   var keep = shape<0.9+rng.randf_range(-0.15,0.2) and _open.call(mid)>0.5 and rng.randf()>0.07
   if not keep: continue
   for e in [[Vector2i(i,j),Vector2i(i+1,j)],[Vector2i(i+1,j),Vector2i(i+1,j+1)],[Vector2i(i,j+1),Vector2i(i+1,j+1)],[Vector2i(i,j),Vector2i(i,j+1)]]:
    edges[str(e)] = [corners[e[0].y][e[0].x],corners[e[1].y][e[1].x]]
   # Some wide plots are worked as two long strips.
   var w = quad[0].distance_to(quad[1])
   var h = quad[0].distance_to(quad[3])
   if maxf(w,h)>5.5 and rng.randf()<0.4:
    if w>h:
     var a = quad[0].lerp(quad[1],0.5)
     var b = quad[3].lerp(quad[2],0.5)
     fields.append([quad[0],a,b,quad[3]])
     fields.append([a,quad[1],quad[2],b])
    else:
     var a = quad[0].lerp(quad[3],0.5)
     var b = quad[1].lerp(quad[2],0.5)
     fields.append([quad[0],quad[1],b,a])
     fields.append([a,b,quad[2],quad[3]])
   else:
    fields.append(quad)
 _build_fields(fields,rng)
 _build_borders(edges.values(),rng)

func _splits(from: float,to: float,min_w: float,max_w: float,rng: RandomNumberGenerator) -> Array:
 var out = [from]
 while out[-1]<to-min_w*0.6:
  out.append(minf(out[-1]+rng.randf_range(min_w,max_w),to))
 return out

func _pick_crop(rng: RandomNumberGenerator) -> Array:
 var total = 0
 for c in CROPS: total += c[2]
 var r = rng.randi_range(1,total)
 for c in CROPS:
  r -= c[2]
  if r<=0: return c
 return CROPS[0]

func _build_fields(fields: Array,rng: RandomNumberGenerator):
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for k in range(3): st.set_custom_format(k,SurfaceTool.CUSTOM_RGBA_FLOAT)
 for quad in fields:
  var centroid = (quad[0]+quad[1]+quad[2]+quad[3])*0.25
  var poly = []
  for c in quad: poly.append(c+(centroid-c).normalized()*INSET)
  var crop = _pick_crop(rng)
  var color = (crop[0]*rng.randf_range(0.92,1.08)).srgb_to_linear()
  # Furrows run along the field's longer side.
  var along = poly[1]-poly[0] if poly[0].distance_to(poly[1])>poly[0].distance_to(poly[3]) else poly[3]-poly[0]
  along = along.normalized()
  var c0 = Color(poly[0].x,poly[0].y,poly[1].x,poly[1].y)
  var c1 = Color(poly[2].x,poly[2].y,poly[3].x,poly[3].y)
  var c2 = Color(along.x,along.y,rng.randf_range(0.38,0.5),crop[1])
  var lo = Vector2(INF,INF)
  var hi = -lo
  for p in poly:
   lo = lo.min(p)
   hi = hi.max(p)
  for z in range(floori(lo.y),ceili(hi.y)):
   for x in range(floori(lo.x),ceili(hi.x)):
    # The terrain mesh's two triangles for this 1 m cell (see main.gd make_terrain).
    for tri in [[Vector2(x,z),Vector2(x+1,z),Vector2(x,z+1)],[Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)]]:
     var piece = _clip(tri,poly)
     if piece.size()<3: continue
     var plane = []
     for t in tri: plane.append(Vector3(t.x,_height.call(t.x,t.y),t.y))
     for i in range(1,piece.size()-1):
      var a = piece[0]
      var b = piece[i]
      var c = piece[i+1]
      if (b-a).cross(c-a)<0:
       var swap = b
       b = c
       c = swap
      for p in [a,b,c]:
       st.set_color(Color(color.r,color.g,color.b,clampf(_open.call(p),0,1)))
       st.set_custom(0,c0)
       st.set_custom(1,c1)
       st.set_custom(2,c2)
       st.set_normal(_normal(p))
       st.add_vertex(Vector3(p.x,_plane_y(plane,p)+0.045,p.y))
 var material = ShaderMaterial.new()
 material.shader = SHADER
 var n = MeshInstance3D.new()
 n.mesh = st.commit()
 n.material_override = material
 n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(n)

func _normal(p: Vector2) -> Vector3:
 return Vector3(_height.call(p.x-0.3,p.y)-_height.call(p.x+0.3,p.y),0.6,_height.call(p.x,p.y-0.3)-_height.call(p.x,p.y+0.3)).normalized()

func _plane_y(tri: Array,p: Vector2) -> float:
 var a = Vector2(tri[0].x,tri[0].z)
 var v0 = Vector2(tri[1].x,tri[1].z)-a
 var v1 = Vector2(tri[2].x,tri[2].z)-a
 var v2 = p-a
 var den = v0.cross(v1)
 var u = v2.cross(v1)/den
 var v = v0.cross(v2)/den
 return tri[0].y+(tri[1].y-tri[0].y)*u+(tri[2].y-tri[0].y)*v

# Sutherland-Hodgman clip of a polygon against a convex polygon (either winding).
func _clip(subject: Array,poly: Array) -> Array:
 var orient = 0.0
 for i in poly.size(): orient += poly[i].cross(poly[(i+1)%poly.size()])
 orient = signf(orient)
 var out = subject
 for i in poly.size():
  if out.is_empty(): break
  var a = poly[i]
  var e = poly[(i+1)%poly.size()]-a
  var input = out
  out = []
  for j in input.size():
   var p = input[j]
   var q = input[(j+1)%input.size()]
   var dp = orient*e.cross(p-a)
   var dq = orient*e.cross(q-a)
   if dp>=0: out.append(p)
   if (dp>=0) != (dq>=0): out.append(p.lerp(q,dp/(dp-dq)))
 return out

# Hedgerows along most field boundaries, a few post-and-rail fences, gaps for the roads.
func _build_borders(edges: Array,rng: RandomNumberGenerator):
 var kit = ProtoKit.shared()
 var bushes = []
 var posts = []
 var rails = []
 for e in edges:
  var roll = rng.randf()
  var length = e[0].distance_to(e[1])
  if roll<0.72:
   var count = int(length/0.42)
   for k in range(count+1):
    var p = e[0].lerp(e[1],float(k)/maxi(count,1))+Vector2(rng.randf_range(-0.12,0.12),rng.randf_range(-0.12,0.12))
    if _open.call(p)<0.6 or rng.randf()<0.06: continue
    var tall = rng.randf()<0.06
    var w = rng.randf_range(0.38,0.58)*(1.6 if tall else 1.0)
    var h = rng.randf_range(0.3,0.48)*(2.6 if tall else 1.0)
    var basis = Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(w,h,w))
    var tint = rng.randf_range(0.85,1.12)
    bushes.append([Transform3D(basis,_ground.call(p,h*0.36)),Color(0.24*tint,0.37*tint,0.16*tint)])
  elif roll<0.86:
   var count = int(length/0.9)
   var prev = null
   for k in range(count+1):
    var p = e[0].lerp(e[1],float(k)/maxi(count,1))
    if _open.call(p)<0.6:
     prev = null
     continue
    var top = _ground.call(p,0.0)
    posts.append(Transform3D(Basis(),top+Vector3(0,0.2,0)))
    if prev != null:
     var d = top-prev
     var basis = Basis.looking_at(d.normalized(),Vector3.UP)*Basis.from_scale(Vector3(1,1,d.length()))
     for y in [0.17,0.32]: rails.append(Transform3D(basis,(top+prev)*0.5+Vector3(0,y,0)))
    prev = top
 var bush_mesh = SphereMesh.new()
 bush_mesh.radius = 0.5
 bush_mesh.height = 1.0
 bush_mesh.radial_segments = 7
 bush_mesh.rings = 4
 var leaf = kit.mat(Color.WHITE,0.9)
 leaf.vertex_color_use_as_albedo = true
 leaf.vertex_color_is_srgb = true
 _multimesh(bush_mesh,leaf,bushes.map(func(b): return b[0]),bushes.map(func(b): return b[1]))
 var post_mesh = BoxMesh.new()
 post_mesh.size = Vector3(0.07,0.4,0.07)
 var rail_mesh = BoxMesh.new()
 rail_mesh.size = Vector3(0.035,0.035,1.0)
 var timber = kit.mat(Color("6e5538"))
 _multimesh(post_mesh,timber,posts,[])
 _multimesh(rail_mesh,timber,rails,[])

func _multimesh(mesh: Mesh,material: Material,transforms: Array,colors: Array):
 if transforms.is_empty(): return
 var mm = MultiMesh.new()
 mm.transform_format = MultiMesh.TRANSFORM_3D
 mm.use_colors = not colors.is_empty()
 mm.mesh = mesh
 mm.instance_count = transforms.size()
 for i in transforms.size():
  mm.set_instance_transform(i,transforms[i])
  if mm.use_colors: mm.set_instance_color(i,colors[i])
 var n = MultiMeshInstance3D.new()
 n.multimesh = mm
 n.material_override = material
 add_child(n)
