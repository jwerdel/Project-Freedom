extends Control
# Minimap (TW:WH3's top-right map; owner 2026-10-06): the strategic map's political painting at
# minimap size (the same parchment, region raster, borders and colours: your realm bright and
# outlined, other realms muted, occupied land hatched, vassals striped), with settlement dots, army
# pips and the camera's view drawn on top. Clicking or dragging moves the camera there
# (minimap_clicked carries a world x/z position). It shares the strategic map's textures, so it costs
# one shader pass and updates whenever the territory does.

signal minimap_clicked(world: Vector2)

const UiKit = preload("res://ui/ui_kit.gd")
const WorldMap = preload("res://core/world_map.gd")

var data
var rect: Rect2 # world x/z shown
var view_getter: Callable # -> PackedVector2Array, the camera footprint on the ground (world x/z)
var image: TextureRect
var show_settlements := true
var overlay: Control
var strategic

func setup(ui_data,strategic_map,world_rect: Rect2,camera_footprint: Callable):
 data = ui_data
 strategic = strategic_map
 rect = world_rect
 view_getter = camera_footprint
 clip_contents = true
 mouse_filter = Control.MOUSE_FILTER_STOP
 mouse_default_cursor_shape = Control.CURSOR_CROSS
 image = TextureRect.new()
 image.name = "Political"
 image.texture = strategic.base_parchment
 image.material = strategic.minimap_material()
 image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 image.stretch_mode = TextureRect.STRETCH_SCALE
 image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 image.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(image)
 overlay = Control.new()
 overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
 overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 overlay.draw.connect(_draw_overlay)
 add_child(overlay)
 resized.connect(_fit)
 _fit()

# The whole world letterboxed in the minimap (it keeps the world's proportions).
func _fit():
 if image == null or size.x<=0.0: return
 var s = minf(size.x/rect.size.x,size.y/rect.size.y)
 var sz = rect.size*s
 image.position = (size-sz)*0.5
 image.size = sz
 var paint = strategic._paint
 if paint.has("coast_cells_per_world"): image.material.set_shader_parameter("coast_px",float(paint.coast_cells_per_world)*rect.size.x/maxf(sz.x,1.0))
 image.material.set_shader_parameter("owner_width",1.2)

# Kept for callers that re-rendered the old 3D minimap: the painting updates by itself.
func refresh():
 if overlay: overlay.queue_redraw()

func world_to_map(p: Vector2) -> Vector2:
 return image.position+(p-rect.position)/rect.size*image.size

func map_to_world(p: Vector2) -> Vector2:
 return rect.position+(p-image.position)/image.size*rect.size

func _process(_d):
 if overlay and is_visible_in_tree(): overlay.queue_redraw()

# Settlement dots (the player's larger), army pips and the view outline.
func _draw_overlay():
 var o = overlay
 var me = data.player_faction_id()
 if show_settlements:
  for id in data.settlement_ids():
   var st = data.state.settlements[id]
   var fd = data.faction(st.owner)
   var p = world_to_map(WorldMap.settlement_position(id))
   var r = 2.6 if st.owner == me else 1.8
   o.draw_circle(p,r+1.0,Color(0,0,0,0.75))
   o.draw_circle(p,r,Color(fd.primary).lightened(0.25))
 for id in data.army_ids():
  var m = data.army_movement(id)
  if m.garrison != "": continue
  var a = data.state.army_state[id]
  var p = world_to_map(m.position)
  var c = Color(data.faction(a.faction).primary)
  o.draw_rect(Rect2(p-Vector2(2.2,2.2),Vector2(4.4,4.4)),Color(0,0,0,0.8))
  o.draw_rect(Rect2(p-Vector2(1.5,1.5),Vector2(3,3)),c.lightened(0.3) if a.faction == me else c)
 var view = view_getter.call()
 if view.size() == 4:
  var pts = PackedVector2Array()
  for v in view: pts.append(world_to_map(v))
  pts.append(pts[0])
  o.draw_polyline(pts,Color(0,0,0,0.55),3.0)
  o.draw_polyline(pts,Color(1,0.95,0.8,0.95),1.5)

func _gui_input(event):
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  minimap_clicked.emit(map_to_world(event.position))
  accept_event()
 elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
  minimap_clicked.emit(map_to_world(event.position))
  accept_event()
