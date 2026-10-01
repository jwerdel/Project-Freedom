extends Control
# Minimap: a top-down orthographic render of the live 3D world (territory borders included,
# re-rendered only on request), with settlement markers and the camera's view drawn on top.
# Clicking moves the camera there (minimap_clicked carries a world x/z position).

signal minimap_clicked(world: Vector2)

const UiKit = preload("res://ui/ui_kit.gd")

var data
var rect: Rect2 # world x/z shown
var view_getter: Callable # -> PackedVector2Array, the camera footprint on the ground (world x/z)
var viewport: SubViewport
var image: TextureRect
var show_settlements := true
var overlay: Control

func setup(ui_data,world: World3D,world_rect: Rect2,camera_footprint: Callable):
 data = ui_data
 rect = world_rect
 view_getter = camera_footprint
 clip_contents = true
 mouse_filter = Control.MOUSE_FILTER_STOP
 mouse_default_cursor_shape = Control.CURSOR_CROSS
 viewport = SubViewport.new()
 viewport.size = Vector2i(400,400)
 viewport.world_3d = world
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 viewport.msaa_3d = Viewport.MSAA_2X
 add_child(viewport)
 var cam = Camera3D.new()
 cam.projection = Camera3D.PROJECTION_ORTHOGONAL
 cam.size = world_rect.size.y
 cam.near = 1
 cam.far = 400
 cam.position = Vector3(world_rect.get_center().x,250,world_rect.get_center().y)
 cam.rotation_degrees = Vector3(-90,0,0)
 viewport.add_child(cam)
 cam.current = true
 image = TextureRect.new()
 image.texture = viewport.get_texture()
 image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 image.stretch_mode = TextureRect.STRETCH_SCALE
 image.mouse_filter = Control.MOUSE_FILTER_IGNORE
 image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(image)
 overlay = Control.new()
 overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
 overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 overlay.draw.connect(_draw_overlay)
 add_child(overlay)
 refresh()

# Re-render the map image (after the world visibly changes).
func refresh():
 if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func world_to_map(p: Vector2) -> Vector2:
 return (p-rect.position)/rect.size*size

func map_to_world(p: Vector2) -> Vector2:
 return rect.position+p/size*rect.size

func _process(_d):
 if overlay: overlay.queue_redraw()

# Markers and the view outline, drawn on a child so they sit above the map image.
func _draw_overlay():
 var o = overlay
 if show_settlements:
  for id in data.settlement_ids():
   var s = data.settlement(id)
   var c = UiKit.colors(s.faction)
   var p = world_to_map(Vector2(s.position[0],s.position[1]))
   o.draw_circle(p,6.0,Color(0,0,0,0.8))
   o.draw_circle(p,4.6,c.primary.lightened(0.15))
   o.draw_arc(p,4.6,0,TAU,16,c.secondary,1.5)
 var view = view_getter.call()
 if view.size() == 4:
  var pts = PackedVector2Array()
  for v in view: pts.append(world_to_map(v))
  pts.append(pts[0])
  o.draw_polyline(pts,Color(1,0.95,0.8,0.95),1.5)

func _gui_input(event):
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  minimap_clicked.emit(map_to_world(event.position))
  accept_event()
 elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
  minimap_clicked.emit(map_to_world(event.position))
  accept_event()
