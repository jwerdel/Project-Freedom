extends Node3D
# Map overlays for army movement, TW:WH3-style (owner spec 2026-10-07, docs/tw-ui-parity.md §18):
#  - the path: a thick ribbon projected onto the terrain and drawn over everything (no depth test
#    against trees, buildings, hills or walls), with chevrons running toward the destination; the part
#    reachable this turn bright green, later turns amber, a numbered marker at each turn break, and an
#    end marker showing the action (move, attack, enter, merge, besiege); red when blocked;
#  - other armies' committed orders as thin faint lines (Settings "Show my armies' orders");
#  - the reachable area this turn: a soft fill with a crisp edge.
# Draws only; all movement rules live in core/movement.gd and reach here through UiData. The ribbon
# is widened in its shader (ui/move_path.gdshader), so set_view() can follow the camera height every
# frame without rebuilding meshes.

const UiKit = preload("res://ui/ui_kit.gd")
const MoveIcons = preload("res://ui/move_icons.gd")
const PATH_SHADER = preload("res://ui/move_path.gdshader")
const THIS_TURN = Color("4fe03a")
const LATER = Color("ffb020")
const BLOCKED = Color("e8402c")
const LIFT = 0.3

var height: Callable # (x, z) -> ground height
var _layers = {}     # kind -> Node3D
var _markers = {}    # kind -> [{"at": Vector3, "node": Control}]
var _full_mat: ShaderMaterial
var _faint_mat: ShaderMaterial
var _reach_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _canvas: CanvasLayer
var _camera: Camera3D

func setup(height_fn: Callable):
 height = height_fn
 _full_mat = ShaderMaterial.new()
 _full_mat.shader = PATH_SHADER
 _full_mat.render_priority = 10
 _faint_mat = _full_mat.duplicate()
 _faint_mat.set_shader_parameter("chevrons",0.0)
 _faint_mat.set_shader_parameter("opacity",0.45)
 _faint_mat.render_priority = 9
 _reach_mat = StandardMaterial3D.new()
 _reach_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 _reach_mat.vertex_color_use_as_albedo = true
 _reach_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 _reach_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 _edge_mat = _reach_mat.duplicate()
 _edge_mat.no_depth_test = true # the edge stays crisp over trees and roofs
 _edge_mat.render_priority = 5
 # Turn numbers and end markers are screen-space plates above the map and below the interface.
 _canvas = CanvasLayer.new()
 _canvas.layer = -1
 add_child(_canvas)

# Every frame: ribbon width from the camera height (readable from 10 m to the top zoom) and the
# screen positions of the markers.
func set_view(camera: Camera3D,distance: float):
 _camera = camera
 var hw = clampf(distance*0.012,0.6,80.0)
 _full_mat.set_shader_parameter("half_width",hw)
 _full_mat.set_shader_parameter("spacing",maxf(2.5,hw*5.0))
 _faint_mat.set_shader_parameter("half_width",hw*0.45)
 for kind in _markers:
  for m in _markers[kind]:
   var n: Control = m.node
   var hidden = camera == null or camera.is_position_behind(m.at)
   n.visible = not hidden and _layers.has(kind) and _layers[kind].visible
   if n.visible: n.position = camera.unproject_position(m.at)-n.size*0.5

func _layer(kind: String) -> Node3D:
 if _layers.has(kind):
  clear(kind)
  return _layers[kind]
 var n = Node3D.new()
 n.name = kind.replace(":","_")
 add_child(n)
 _layers[kind] = n
 _markers[kind] = []
 return n

func clear(kind: String):
 if _layers.has(kind):
  # Detach at once (not at the end of the frame), so has_content() is right immediately.
  for c in _layers[kind].get_children():
   _layers[kind].remove_child(c)
   c.free()
 for m in _markers.get(kind,[]): m.node.free()
 if _markers.has(kind): _markers[kind] = []

func has_content(kind: String) -> bool:
 return _layers.has(kind) and _layers[kind].get_child_count()>0

func kinds() -> Array:
 return _layers.keys()

func _ground(p: Vector2,lift := LIFT) -> Vector3:
 return Vector3(p.x,maxf(height.call(p.x,p.y),0.0)+lift,p.y)

# points: world x/z; turns: turn index per point (0 = this turn).
# opts: style "full" (default) or "faint" (other armies' orders), action (end marker kind: move,
# attack, enter, merge, besiege), blocked (all red, a blocked end marker).
func show_path(kind: String,points: Array,turns: Array,opts := {}):
 var layer = _layer(kind)
 if points.size()<2: return
 var faint = opts.get("style","full") == "faint"
 var blocked = bool(opts.get("blocked",false))
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var along = 0.0
 for i in range(1,points.size()):
  var a: Vector2 = points[i-1]
  var b: Vector2 = points[i]
  var col = BLOCKED if blocked else (THIS_TURN if int(turns[i]) == 0 else LATER)
  var seg = a.distance_to(b)
  if seg<0.0001: continue
  var side = (b-a).orthogonal().normalized()
  var steps = maxi(1,int(seg/1.5))
  for s in steps:
   var p0 = a.lerp(b,float(s)/steps)
   var p1 = a.lerp(b,float(s+1)/steps)
   var u0 = along+seg*float(s)/steps
   var u1 = along+seg*float(s+1)/steps
   var c0 = _ground(p0)
   var c1 = _ground(p1)
   var n = Vector3(side.x,0,side.y)
   # Quad: two vertices at each end, pushed to the sides in the shader (NORMAL = side * sign).
   var v = [[c0,n,u0,0.0],[c0,-n,u0,1.0],[c1,n,u1,0.0],[c1,-n,u1,1.0]]
   for idx in [0,1,2,2,1,3]:
    st.set_color(col)
    st.set_normal(v[idx][1])
    st.set_uv(Vector2(v[idx][2],v[idx][3]))
    st.add_vertex(v[idx][0])
  along += seg
 var mesh = MeshInstance3D.new()
 mesh.mesh = st.commit()
 mesh.material_override = _faint_mat if faint else _full_mat
 mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 mesh.extra_cull_margin = 64.0
 layer.add_child(mesh)
 if faint: return
 # A numbered marker where each turn's walk ends (TW:WH3), and the action at the destination.
 var last_turn = int(turns[-1])
 for i in range(1,points.size()-1):
  if int(turns[i+1]) != int(turns[i]): _marker(kind,points[i],TurnMarker.new(int(turns[i])+1,THIS_TURN if int(turns[i]) == 0 else LATER))
 var action = "blocked" if blocked else str(opts.get("action","move"))
 _marker(kind,points[-1],EndMarker.new(action,last_turn+1 if last_turn>0 else 0))

# A blocked or unreachable destination: a red line to it from the army and the blocked marker. The
# reason is shown in the cursor tooltip.
func show_blocked(p: Vector2,_reason: String,from = null):
 if from is Vector2: show_path("preview",[from,p],[0,0],{"blocked":true})
 else:
  _layer("preview")
  _marker("preview",p,EndMarker.new("blocked",0))
 # A marker-only layer still counts as content (has_content checks children).
 if not has_content("preview"): _layers["preview"].add_child(Node3D.new())

func _marker(kind: String,p: Vector2,node: Control):
 node.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _canvas.add_child(node)
 _markers[kind].append({"at":_ground(p,1.0),"node":node})
 if _camera != null:
  node.position = _camera.unproject_position(_markers[kind][-1].at)-node.size*0.5

# Reachable area this turn (TW): a soft fill with a crisp edge.
const REACH_FILL = Color(0.98,0.86,0.42,0.16)
const REACH_EDGE = Color(1.0,0.86,0.36,0.95)
func show_reachable(centers: Array,cell: float):
 var layer = _layer("reach")
 if centers.is_empty(): return
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var et = SurfaceTool.new()
 et.begin(Mesh.PRIMITIVE_TRIANGLES)
 var h = cell*0.5
 var inside = {}
 for c in centers: inside[Vector2i(floori(c.x/cell),floori(c.y/cell))] = true
 var ew = maxf(cell*0.35,0.6)
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
   var inward = -Vector2(side[0])*ew
   var e = [_ground(a,0.2),_ground(b,0.2),_ground(a+inward,0.2),_ground(b+inward,0.2)]
   for idx in [0,1,2,2,1,3]:
    et.set_color(REACH_EDGE)
    et.add_vertex(e[idx])
 for pair in [[st,_reach_mat],[et,_edge_mat]]:
  var mesh = MeshInstance3D.new()
  mesh.mesh = pair[0].commit()
  mesh.material_override = pair[1]
  mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  layer.add_child(mesh)

# A numbered turn marker (screen space): the turn on which the army reaches this point.
class TurnMarker extends Control:
 var n := 1
 var col := Color.WHITE
 func _init(turn: int,c: Color):
  n = turn
  col = c
  size = Vector2(26,26)
 func _draw():
  var c = size*0.5
  draw_circle(c,12.5,Color(0.04,0.03,0.02,0.92))
  draw_circle(c,10.5,col.darkened(0.35))
  draw_arc(c,10.5,0,TAU,24,col.lightened(0.3),1.6,true)
  var f = UiKit.FONT_BOLD
  var t = str(n)
  var fs = 15
  var w = f.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
  draw_string(f,c+Vector2(-w*0.5,fs*0.36),t,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("fff8e0"))

# The destination: the action icon on a plate, with the number of turns for a multi-turn march.
class EndMarker extends Control:
 var action := "move"
 var turns := 0
 func _init(a: String,t: int):
  action = a
  turns = t
  size = Vector2(40,40)
 func _draw():
  MoveIcons.draw(self,action,size*0.5,18.0)
  if turns>1:
   var c = size*0.5+Vector2(13,-13)
   draw_circle(c,8.5,Color(0.04,0.03,0.02,0.95))
   draw_circle(c,7.0,Color("ffb020").darkened(0.3))
   var f = UiKit.FONT_BOLD
   var t = str(turns)
   var w = f.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
   draw_string(f,c+Vector2(-w*0.5,4),t,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("fff8e0"))
