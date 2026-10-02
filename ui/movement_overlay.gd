extends Node3D
# Map overlays for army movement, TW:WH3-style: the planned path (this turn's reachable part in
# green, later turns in yellow, orange and red) with plain discs where each turn ends (no numbers), the standing order of an
# army, a blocked-destination marker, and the subtle reachable-area overlay of the selected army.
# Draws only; all movement rules live in core/movement.gd and reach here through UiData.

const UiKit = preload("res://ui/ui_kit.gd")
const TURN_COLORS = [Color("4fe03a"),Color("ffd21f"),Color("ff8a1f"),Color("ff3b2f")]
const LIFT = 0.28
const WIDTH = 0.8
const OUTLINE = 0.35 # dark edge on each side, for contrast on grass

var height: Callable # (x, z) -> ground height
var _layers = {}     # kind -> Node3D ("preview", "order", "reach")
var _path_mat: StandardMaterial3D
var _reach_mat: StandardMaterial3D

func setup(height_fn: Callable):
 height = height_fn
 _path_mat = StandardMaterial3D.new()
 _path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 _path_mat.vertex_color_use_as_albedo = true
 _path_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 _path_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 _reach_mat = _path_mat.duplicate()

func _layer(kind: String) -> Node3D:
 if _layers.has(kind):
  clear(kind)
  return _layers[kind]
 var n = Node3D.new()
 n.name = kind
 add_child(n)
 _layers[kind] = n
 return n

func clear(kind: String):
 if _layers.has(kind):
  # Detach at once (not at the end of the frame), so has_content() is right immediately.
  for c in _layers[kind].get_children():
   _layers[kind].remove_child(c)
   c.free()

func has_content(kind: String) -> bool:
 return _layers.has(kind) and _layers[kind].get_child_count()>0

func _ground(p: Vector2,lift := LIFT) -> Vector3:
 return Vector3(p.x,maxf(height.call(p.x,p.y),0.0)+lift,p.y)

# points: world x/z; turns: turn index per point (0 = this turn). dim: for standing orders.
func show_path(kind: String,points: Array,turns: Array,dim := false):
 var layer = _layer(kind)
 if points.size()<2: return
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var alpha = 0.6 if dim else 0.95
 for i in range(1,points.size()):
  var a: Vector2 = points[i-1]
  var b: Vector2 = points[i]
  var col = TURN_COLORS[mini(turns[i],TURN_COLORS.size()-1)]
  col.a = alpha
  var dir = (b-a).orthogonal().normalized()
  var steps = maxi(1,int(a.distance_to(b)))
  for s in steps:
   var p0 = a.lerp(b,float(s)/steps)
   var p1 = a.lerp(b,float(s+1)/steps)
   # Dark outline first (slightly lower), then the colored band on top.
   for band in [[WIDTH*0.5+OUTLINE,Color(0.05,0.04,0.03,alpha*0.8),LIFT-0.04],[WIDTH*0.5,col,LIFT]]:
    var side = dir*band[0]
    var v = [_ground(p0+side,band[2]),_ground(p0-side,band[2]),_ground(p1+side,band[2]),_ground(p1-side,band[2])]
    for idx in [0,1,2,2,1,3]:
     st.set_color(band[1])
     st.add_vertex(v[idx])
 var mesh = MeshInstance3D.new()
 mesh.mesh = st.commit()
 mesh.material_override = _path_mat
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 layer.add_child(mesh)
 # A plain disc where each turn's walk ends and at the destination: no numbers on the map (TW:WH3
 # parity; the colour already says which turn).
 for i in range(1,points.size()):
  var last = i == points.size()-1
  if last or turns[i+1] != turns[i]:
   _disc(layer,points[i],TURN_COLORS[mini(turns[i],TURN_COLORS.size()-1)],dim)

func _disc(layer: Node3D,p: Vector2,col: Color,dim: bool):
 var m = MeshInstance3D.new()
 var c = CylinderMesh.new()
 c.top_radius = 0.9
 c.bottom_radius = 0.9
 c.height = 0.12
 c.radial_segments = 20
 m.mesh = c
 var mat = StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.albedo_color = col if not dim else col.darkened(0.15)
 m.material_override = mat
 m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 m.position = _ground(p,LIFT+0.05)
 layer.add_child(m)

# A blocked destination: a red cross only; the reason is shown in the cursor tooltip, not on the map.
func show_blocked(p: Vector2,_reason: String):
 var layer = _layer("preview")
 var l = Label3D.new()
 l.text = "X"
 l.font = UiKit.FONT_BOLD
 l.font_size = 34
 l.outline_size = 12
 l.modulate = Color("ef7a5a")
 l.outline_modulate = Color(0.08,0.04,0.03)
 l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 l.fixed_size = true
 l.pixel_size = 0.0011
 l.no_depth_test = true
 l.position = _ground(p,1.8)
 layer.add_child(l)

# Reachable area this turn, TW-style: a highlighted boundary (gold-yellow, the WH2 Academy colour)
# with barely any fill.
const REACH_FILL = Color(1.0,0.85,0.35,0.03)
const REACH_EDGE = Color(1.0,0.83,0.29,0.85)
func show_reachable(centers: Array,cell: float):
 var layer = _layer("reach")
 if centers.is_empty(): return
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var h = cell*0.5
 var inside = {}
 for c in centers: inside[Vector2i(floori(c.x/cell),floori(c.y/cell))] = true
 for c in centers:
  var v = [_ground(c+Vector2(-h,-h),0.15),_ground(c+Vector2(h,-h),0.15),_ground(c+Vector2(-h,h),0.15),_ground(c+Vector2(h,h),0.15)]
  for idx in [0,1,2,2,1,3]:
   st.set_color(REACH_FILL)
   st.add_vertex(v[idx])
  var k = Vector2i(floori(c.x/cell),floori(c.y/cell))
  for side in [[Vector2i(1,0),Vector2(h,-h),Vector2(h,h)],[Vector2i(-1,0),Vector2(-h,-h),Vector2(-h,h)],[Vector2i(0,1),Vector2(-h,h),Vector2(h,h)],[Vector2i(0,-1),Vector2(-h,-h),Vector2(h,-h)]]:
   if inside.has(k+side[0]): continue
   var a = c+side[1]
   var b = c+side[2]
   var inward = -Vector2(side[0])*0.5
   var e = [_ground(a,0.2),_ground(b,0.2),_ground(a+inward,0.2),_ground(b+inward,0.2)]
   for idx in [0,1,2,2,1,3]:
    st.set_color(REACH_EDGE)
    st.add_vertex(e[idx])
 var mesh = MeshInstance3D.new()
 mesh.mesh = st.commit()
 mesh.material_override = _reach_mat
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 layer.add_child(mesh)
