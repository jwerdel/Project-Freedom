extends Control
# TW:WH3-style strategic map (docs/tw-ui-parity.md, "Strategic map"): a flat, stylised parchment map
# of the whole world with territory colours, borders, settlement and army icons, and map layers.
# Entered by zooming all the way out or with Tab; clicking a place or scrolling in returns to the 3D
# map there. Built from data only (terrain grid, region polygons, campaign state through UiData), so
# it scales to the full world: the parchment base is rasterised once from the movement grid, and
# region colours, icons and screen polygons are cached and rebuilt only when the campaign state, the
# layer or the screen size changes (no per-frame work while it stands open).

signal location_chosen(world: Vector2) # click or scroll in: return to the 3D map there
signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const FADE = 0.35
# Map layers (TW:WH3 overlays). available: false = greyed until its system exists.
const LAYERS = [
 {"id":"affiliation","name":"Affiliation","available":true,"tip":"Who owns each region"},
 {"id":"diplomatic","name":"Diplomatic status","available":true,"tip":"At war with you, at peace, or yours"},
 {"id":"attitude","name":"Attitude","available":false,"tip":"How each faction feels about you"},
 {"id":"order","name":"Public order","available":true,"tip":"Public order of each province (placeholder values until the public order system exists)"},
 {"id":"development","name":"Development","available":true,"tip":"Settlement level of each region"},
 {"id":"climate","name":"Climate and terrain","available":true,"tip":"Terrain: plains, forest, hills, mountains, passes and water"},
 {"id":"faith","name":"Faith","available":false,"tip":"The faiths of each region"},
 {"id":"culture","name":"Culture","available":false,"tip":"The cultures of each region"},
]
const TERRAIN_PARCHMENT = {"open":Color("e6d4ab"),"settlement":Color("e6d4ab"),"forest":Color("c5c48f"),"hills":Color("d8c08a"),"mountain":Color("a58f6c"),"pass":Color("c6ad83"),"water":Color("9fb3ad")}
const TERRAIN_VIVID = {"open":Color("b8cf7e"),"settlement":Color("b8cf7e"),"forest":Color("5f8f4a"),"hills":Color("c9b16a"),"mountain":Color("8c7a64"),"pass":Color("b59a6c"),"water":Color("4f7f9c")}

var data
var world_rect: Rect2
var layer := "affiliation"
var base_parchment: ImageTexture
var base_vivid: ImageTexture
var layer_buttons := {}
var legend: VBoxContainer
var fade := 0.0
var showing := false
var selected_army := ""
var _fills := {}    # region id -> fill colour on the current layer
var _seals := []    # [screen-independent world position, colour, level, name]
var _armies := []   # [id, world position, colour]
var _owners := {}   # region id -> owner faction id
var _polys := {}    # region id -> screen polygon (closed), for _poly_size
var _poly_size := Vector2.ZERO

func setup(ui_data,rect: Rect2):
 data = ui_data
 world_rect = rect
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 visible = false
 modulate.a = 0.0
 base_parchment = _bake(TERRAIN_PARCHMENT)
 base_vivid = _bake(TERRAIN_VIVID)
 _build_bar()
 data.changed.connect(refresh)
 refresh()

# The terrain grid rasterised once into a texture (one pixel per cell; roads darker).
func _bake(palette: Dictionary) -> ImageTexture:
 var g = Movement.grid()
 var img = Image.create(g.cols,g.rows,false,Image.FORMAT_RGB8)
 for z in g.rows:
  for x in g.cols:
   var i = z*g.cols+x
   var c: Color = palette.get(g.names[g.terrain[i]],Color("e6d4ab"))
   if g.road[i] == 1 and g.names[g.terrain[i]] != "water": c = c.darkened(0.25)
   img.set_pixel(x,z,c)
 return ImageTexture.create_from_image(img)

func _build_bar():
 var frame = Widgets.Framed.new("main",Color("c9a45a"),Color("1d1712",0.92))
 frame.name = "LayerBar"
 var h = HBoxContainer.new()
 h.add_theme_constant_override("separation",6)
 frame.add_child(h)
 h.add_child(UiKit.header("Map layers",15))
 for l in LAYERS:
  var b = Button.new()
  b.name = "Layer_"+l.id
  b.text = l.name
  b.toggle_mode = true
  b.focus_mode = Control.FOCUS_NONE
  b.disabled = not l.available
  b.tooltip_text = "%s\n%s" % [l.name,l.tip] if l.available else "%s\nComing later: %s." % [l.name,l.tip.to_lower()]
  b.pressed.connect(set_layer.bind(l.id))
  layer_buttons[l.id] = b
  h.add_child(b)
 var close = Button.new()
 close.name = "CloseMap"
 close.text = "Close (Tab)"
 close.focus_mode = Control.FOCUS_NONE
 close.pressed.connect(func(): closed.emit())
 h.add_child(close)
 frame.anchor_left = 0.5
 frame.anchor_right = 0.5
 frame.offset_left = -560
 frame.offset_right = 560
 frame.offset_top = 74
 frame.offset_bottom = 120
 add_child(frame)
 legend = VBoxContainer.new()
 legend.name = "Legend"
 var lf = Widgets.Framed.new("main",Color("c9a45a"),Color("1d1712",0.9))
 lf.add_child(legend)
 lf.name = "LegendFrame"
 lf.offset_left = 16
 lf.offset_top = 132
 lf.offset_right = 236
 lf.offset_bottom = 132
 add_child(lf)
 set_layer(layer)

func set_layer(id: String):
 for l in LAYERS:
  if l.id == id and not l.available: return
 layer = id
 for k in layer_buttons: layer_buttons[k].set_pressed_no_signal(k == id)
 _fill_legend()
 _rebuild_fills()
 queue_redraw()

# instant: no fade (captures).
func open_map(instant := false):
 showing = true
 visible = true
 if instant:
  fade = 1.0
  modulate.a = 1.0
 queue_redraw()

func set_selected_army(id: String):
 if selected_army == id: return
 selected_army = id
 if visible: queue_redraw()

func close_map():
 showing = false

func is_open() -> bool:
 return showing

func _process(delta):
 var target = 1.0 if showing else 0.0
 if fade != target:
  fade = move_toward(fade,target,delta/FADE)
  modulate.a = fade
  if fade == 0.0: visible = false

# The campaign state changed (End Turn, a move, a capture): rebuild the cached icons and colours.
func refresh():
 _owners.clear()
 _seals.clear()
 for sid in data.settlement_ids():
  var s = data.settlement(sid)
  _owners[sid] = s.owner
  _seals.append([WorldMap.settlement_position(sid),Color(data.faction(s.owner).primary) if s.owner != "" else Color("777777"),int(s.level),s.name])
 _armies.clear()
 for id in data.army_ids():
  var m = data.army_movement(id)
  if m.garrison != "": continue
  _armies.append([id,m.position,Color(data.army(id).faction_data.primary)])
 _rebuild_fills()
 if visible: queue_redraw()

func _rebuild_fills():
 _fills.clear()
 if data == null or layer == "climate": return
 for id in WorldMap.regions():
  var c = region_color(id)
  if c.a>0.0: _fills[id] = c

func _screen_polys() -> Dictionary:
 if _poly_size != size:
  _poly_size = size
  _polys.clear()
  var regions = WorldMap.regions()
  for id in regions:
   var pts = PackedVector2Array()
   for p in regions[id].points: pts.append(to_screen(p))
   _polys[id] = pts
 return _polys

# --- Geometry ---------------------------------------------------------------------------------

# The map's square area on screen (letterboxed, leaving room for the bars).
func map_rect() -> Rect2:
 var area = Rect2(Vector2(16,128),size-Vector2(32,144))
 var s = minf(area.size.x/world_rect.size.x,area.size.y/world_rect.size.y)
 var sz = world_rect.size*s
 return Rect2(area.position+(area.size-sz)*0.5,sz)

func to_screen(w: Vector2) -> Vector2:
 var r = map_rect()
 return r.position+(w-world_rect.position)/world_rect.size*r.size

func to_world(p: Vector2) -> Vector2:
 var r = map_rect()
 return world_rect.position+(p-r.position)/r.size*world_rect.size

# --- Layers ------------------------------------------------------------------------------------

# Fill colour of a region on the current layer (alpha 0 = none).
func region_color(id: String) -> Color:
 var s = data.settlement(id)
 if s.is_empty(): return Color(0,0,0,0)
 var owner = s.owner
 match layer:
  "affiliation":
   return Color(Color(data.faction(owner).primary),0.55) if owner != "" else Color(0,0,0,0)
  "diplomatic":
   if owner == data.player_faction_id(): return Color("4fb34a",0.55)
   if owner != "" and data.at_war(owner): return Color("c8382c",0.6)
   return Color("8a97a8",0.45)
  "order":
   var po = float(data.province_stats(s.province).public_order)
   return Color("c8382c").lerp(Color("4fb34a"),clampf((po+100.0)/200.0,0,1))*Color(1,1,1,0.6)
  "development":
   return Color("f4e2a6").lerp(Color("8a5a12"),clampf((int(s.level)-1)/2.0,0,1))*Color(1,1,1,0.65)
 return Color(0,0,0,0)

func _fill_legend():
 if legend == null: return
 for c in legend.get_children(): c.queue_free()
 var title = ""
 for l in LAYERS:
  if l.id == layer: title = l.name
 legend.add_child(UiKit.header(title,15))
 var rows = []
 match layer:
  "affiliation":
   for f in data.state.factions():
    if not data.state.settlements_of(f).is_empty(): rows.append([Color(data.faction(f).primary),data.faction(f).name])
  "diplomatic": rows = [[Color("4fb34a"),"Yours"],[Color("c8382c"),"At war with you"],[Color("8a97a8"),"Not at war"]]
  "order": rows = [[Color("4fb34a"),"High"],[Color("c9a43a"),"Neutral"],[Color("c8382c"),"Low (unrest)"]]
  "development": rows = [[Color("f4e2a6"),"Level 1"],[Color("bf9a5a"),"Level 2"],[Color("8a5a12"),"Level 3"]]
  "climate":
   for t in ["open","forest","hills","mountain","pass","water"]: rows.append([TERRAIN_VIVID[t],{"open":"Plains"}.get(t,t.capitalize())])
 for r in rows:
  var h = HBoxContainer.new()
  var sw = ColorRect.new()
  sw.color = r[0]
  sw.custom_minimum_size = Vector2(18,12)
  h.add_child(sw)
  h.add_child(UiKit.label(r[1],13))
  legend.add_child(h)

# --- Drawing -----------------------------------------------------------------------------------

func _draw():
 draw_rect(Rect2(Vector2.ZERO,size),Color("2a2218"))
 var r = map_rect()
 draw_texture_rect(base_vivid if layer == "climate" else base_parchment,r,false)
 var polys = _screen_polys()
 # Region fills on the current layer.
 for id in _fills:
  if polys.has(id) and polys[id].size()>=3: draw_colored_polygon(polys[id],_fills[id])
 # Borders: every region outline thin; owned regions strong in the owner's colour.
 for id in polys:
  var pts = polys[id]
  if pts.size()<3: continue
  var closed = pts.duplicate()
  closed.append(pts[0])
  draw_polyline(closed,Color(0.2,0.15,0.1,0.55),1.0)
  var owner = _owners.get(id,"")
  if owner != "": draw_polyline(closed,Color(data.faction(owner).primary).darkened(0.2),2.5)
 draw_rect(r,Color("5a4630"),false,3.0)
 var font = UiKit.FONT_BOLD
 # Settlement icons: a round seal in the owner's colour, level pips, the name.
 for s in _seals:
  var p = to_screen(s[0])
  draw_circle(p,9.0,Color(0.1,0.08,0.06))
  draw_circle(p,7.0,s[1])
  for i in s[2]: draw_circle(p+Vector2(-6+i*6,13),2.2,Color("f2cf6a"))
  var w = font.get_string_size(s[3],HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
  draw_string(font,p+Vector2(-w*0.5+1,-12+1),s[3],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0,0,0,0.7))
  draw_string(font,p+Vector2(-w*0.5,-12),s[3],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("2a1c10"))
 # Army icons: a small banner shield in the faction's colour; the selected one ringed.
 for a in _armies:
  var p = to_screen(a[1])
  var shield = PackedVector2Array([p+Vector2(-6,-8),p+Vector2(6,-8),p+Vector2(6,2),p+Vector2(0,9),p+Vector2(-6,2)])
  draw_colored_polygon(shield,a[2])
  shield.append(shield[0])
  draw_polyline(shield,Color("f2cf6a") if a[0] == selected_army else Color(0.1,0.08,0.06),2.0)

func _gui_input(e):
 if not showing: return
 if e is InputEventMouseButton and e.pressed:
  var r = map_rect()
  if not r.has_point(e.position): return
  if e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_WHEEL_UP:
   location_chosen.emit(to_world(e.position))
   accept_event()
