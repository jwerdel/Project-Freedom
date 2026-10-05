extends Control
# TW:WH3-style strategic map (docs/tw-ui-parity.md, "Strategic map"): a flat, stylised parchment map
# of the whole world with territory colours, borders, settlement and army icons, and map layers.
# Entered by zooming all the way out or with Tab; clicking a place or scrolling in returns to the 3D
# map there. Built from data only (terrain grid, region polygons, campaign state through UiData), so
# it scales to the full world: the parchment base is rasterised once from the movement grid, and
# region colours, icons and screen polygons are cached and rebuilt only when the campaign state, the
# layer or the screen size changes (no per-frame work while it stands open).
# Drawing scales to V1 Varos (600 regions): the territory is one shader pass over a region-ID texture
# (ui/strategic_map.gdshader: fills and borders from a small palette), settlement and army icons are
# a few MultiMeshes, and names are placed greedily by importance so they never overlap (fewer show
# when the map is small on screen, more when it is large).

signal location_chosen(world: Vector2) # click or scroll in: return to the 3D map there
signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const MapShader = preload("res://ui/strategic_map.gdshader")
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
 {"id":"culture","name":"Culture","available":true,"tip":"The culture each region's land belongs to; a region being converted shows both, blended by how far it has turned (game-design §12.13)"},
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
var _seals := []    # [world position, colour, level, name, region id]
var _armies := []   # [id, world position, colour]
var _owners := {}   # region id -> owner faction id
var _polys := {}    # region id -> screen polygon (closed), for _poly_size
var _poly_size := Vector2.ZERO
var _surface: TextureRect # the territory (shader)
var _icons: Node2D        # seal, pip and army MultiMeshes
var _overlay: Control     # names and the selected army's ring
var _index := {}          # region id -> palette index
var _palette: Image
var _palette_tex: ImageTexture
var _labels := []         # placed names: [screen position, text, font size]
var _layout_key = null

func setup(ui_data,rect: Rect2):
 data = ui_data
 world_rect = rect
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # smooth terrain (one texel per grid cell)
 visible = false
 modulate.a = 0.0
 base_parchment = _bake(TERRAIN_PARCHMENT)
 base_vivid = _bake(TERRAIN_VIVID)
 _build_surface()
 _build_bar()
 resized.connect(_layout)
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
 frame.offset_left = -580
 frame.offset_right = 500 # clear of the minimap on the right
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
 if _overlay != null: _overlay.queue_redraw()

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
  _seals.append([WorldMap.settlement_position(sid),Color(data.faction(s.owner).primary) if s.owner != "" else Color("777777"),int(s.level),s.name,sid])
 _armies.clear()
 for id in data.army_ids():
  var m = data.army_movement(id)
  if m.garrison != "": continue
  _armies.append([id,m.position,Color(data.army(id).faction_data.primary)])
 _rebuild_fills()
 _layout_key = null
 _layout()
 if visible: queue_redraw()

func _rebuild_fills():
 _fills.clear()
 if data == null: return
 if layer != "climate":
  for id in WorldMap.regions():
   var c = region_color(id)
   if c.a>0.0: _fills[id] = c
 _update_palette()

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
  "culture":
   var l = data.land(id)
   return Color(Color(l.from_color).lerp(Color(l.to_color),float(l.value)),0.62)
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
  "culture":
   var seen = {}
   for sid in data.settlement_ids():
    var l = data.land(sid)
    for k in [[l.from,l.from_color],[l.to,l.to_color]]:
     if not seen.has(k[0]):
      seen[k[0]] = true
      rows.append([Color(k[1]),data.culture_name(k[0])])
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
 draw_rect(map_rect().grow(1.5),Color("5a4630"),false,3.0)

# The territory surface (one shader pass), the icon layer and the name layer, under the bars.
func _build_surface():
 var rr = _region_raster()
 for i in rr.names.size(): _index[rr.names[i]] = i+1
 _palette = Image.create(rr.names.size()+1,2,false,Image.FORMAT_RGBA8)
 _palette_tex = ImageTexture.create_from_image(_palette)
 _surface = TextureRect.new()
 _surface.name = "Territory"
 _surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 _surface.stretch_mode = TextureRect.STRETCH_SCALE
 _surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _surface.texture = base_parchment
 var mat = ShaderMaterial.new()
 mat.shader = MapShader
 mat.set_shader_parameter("ids",rr.tex)
 mat.set_shader_parameter("palette",_palette_tex)
 mat.set_shader_parameter("id_xform",rr.xform)
 _surface.material = mat
 add_child(_surface)
 _icons = Node2D.new()
 _icons.name = "Icons"
 add_child(_icons)
 _overlay = Control.new()
 _overlay.name = "Names"
 _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _overlay.draw.connect(_draw_overlay)
 add_child(_overlay)

# Region IDs as a texture: the map's baked raster (pipeline maps), or the region polygons scanned
# into one (the test map). xform maps the surface's uv (world_rect) to the raster's uv.
func _region_raster() -> Dictionary:
 WorldMap.regions()
 var rs = WorldMap._raster
 var names: Array
 var ids: PackedInt32Array
 var cols: int
 var rows: int
 var origin: Vector2
 var span: Vector2
 if rs != null:
  names = rs.names
  ids = rs.ids
  cols = rs.cols
  rows = rs.rows
  origin = rs.origin
  span = Vector2(cols,rows)*float(rs.cell)
 else:
  names = WorldMap.regions().keys()
  cols = 1024
  rows = maxi(1,int(round(cols*world_rect.size.y/world_rect.size.x)))
  origin = world_rect.position
  span = world_rect.size
  ids = rasterize(names,origin,span,cols,rows)
 var img = Image.create_from_data(cols,rows,false,Image.FORMAT_RGBA8,ids.to_byte_array())
 # About one texel per screen pixel (nearest: IDs must not blend): fewer texture cache misses.
 if cols>ID_MAX_WIDTH: img.resize(ID_MAX_WIDTH,maxi(1,int(round(rows*float(ID_MAX_WIDTH)/cols))),Image.INTERPOLATE_NEAREST)
 var sc = world_rect.size/span
 var off = (world_rect.position-origin)/span
 return {"names":names,"tex":ImageTexture.create_from_image(img),"xform":Vector4(sc.x,sc.y,off.x,off.y)}

# Region polygons scanned into an ID raster (index+1 per cell, 0 = none): per row, the polygon's
# edge crossings at the cell centres, filled in pairs.
static func rasterize(names: Array,origin: Vector2,span: Vector2,cols: int,rows: int) -> PackedInt32Array:
 var ids = PackedInt32Array()
 ids.resize(cols*rows)
 var cw = span.x/cols
 var ch = span.y/rows
 var regions = WorldMap.regions()
 for i in names.size():
  var pts = regions[names[i]].points
  var n = pts.size()
  if n<3: continue
  var lo = pts[0].y
  var hi = pts[0].y
  for p in pts:
   lo = minf(lo,p.y)
   hi = maxf(hi,p.y)
  for z in range(maxi(0,int((lo-origin.y)/ch)),mini(rows,int((hi-origin.y)/ch)+1)):
   var y = origin.y+(z+0.5)*ch
   var xs = []
   for k in n:
    var a = pts[k]
    var b = pts[(k+1)%n]
    if (a.y<=y and b.y>y) or (b.y<=y and a.y>y): xs.append(a.x+(y-a.y)/(b.y-a.y)*(b.x-a.x))
   xs.sort()
   for k in range(0,xs.size()-1,2):
    var x0 = maxi(0,int(ceil((xs[k]-origin.x)/cw-0.5)))
    var x1 = mini(cols-1,int(floor((xs[k+1]-origin.x)/cw-0.5)))
    for x in range(x0,x1+1): ids[z*cols+x] = i+1
 return ids

# Palette: row 0 the current layer's fills, row 1 owner colours (borders).
func _update_palette():
 if _palette == null: return
 _palette.fill(Color(0,0,0,0))
 for id in _fills:
  if _index.has(id): _palette.set_pixel(_index[id],0,_fills[id])
 for id in _owners:
  var o = _owners[id]
  if o != "" and _index.has(id): _palette.set_pixel(_index[id],1,Color(Color(data.faction(o).primary).darkened(0.2),1.0))
 _palette_tex.update(_palette)
 _surface.texture = base_vivid if layer == "climate" else base_parchment

# Positions follow the screen: the surface, the icons and the names are laid out again when the
# size or the campaign state changes.
func _layout():
 if _surface == null or data == null: return
 var r = map_rect()
 if r.size.x<=0.0 or r.size.y<=0.0: return
 _surface.position = r.position
 _surface.size = r.size
 var key = [size,_seals.size(),_armies.size()]
 if key == _layout_key: return
 _layout_key = key
 for c in _icons.get_children():
  _icons.remove_child(c)
  c.free()
 var circle = _disc(16)
 var seal_back = []
 var seal = []
 var pips = []
 for s in _seals:
  var p = to_screen(s[0])
  seal_back.append([Transform2D(0.0,Vector2(9,9),0.0,p),Color(0.1,0.08,0.06)])
  seal.append([Transform2D(0.0,Vector2(7,7),0.0,p),s[1]])
  for i in s[2]: pips.append([Transform2D(0.0,Vector2(2.2,2.2),0.0,p+Vector2(-6+i*6,13)),Color("f2cf6a")])
 var shield = _shield()
 var army_back = []
 var army = []
 for a in _armies:
  var p = to_screen(a[1])
  army_back.append([Transform2D(0.0,Vector2(1.3,1.3),0.0,p),Color(0.1,0.08,0.06)])
  army.append([Transform2D(0.0,Vector2.ONE,0.0,p),a[2]])
 for group in [[circle,seal_back],[circle,seal],[circle,pips],[shield,army_back],[shield,army]]:
  _icons.add_child(_multimesh(group[0],group[1]))
 _place_labels()
 _overlay.queue_redraw()

func _multimesh(mesh: Mesh,items: Array) -> MultiMeshInstance2D:
 var mm = MultiMesh.new()
 mm.transform_format = MultiMesh.TRANSFORM_2D
 mm.use_colors = true
 mm.mesh = mesh
 mm.instance_count = items.size()
 for i in items.size():
  mm.set_instance_transform_2d(i,items[i][0])
  mm.set_instance_color(i,items[i][1])
 var mi = MultiMeshInstance2D.new()
 mi.multimesh = mm
 return mi

static func _disc(n: int) -> ArrayMesh:
 var pts = PackedVector2Array()
 for i in n: pts.append(Vector2.from_angle(i*TAU/n))
 return _fan(pts)

# A banner shield (the army icon), about 12 x 17 px; drawn again 1.3x larger in dark as its rim.
static func _shield() -> ArrayMesh:
 return _fan(PackedVector2Array([Vector2(-6,-8),Vector2(6,-8),Vector2(6,2),Vector2(0,9),Vector2(-6,2)]))

static func _fan(pts: PackedVector2Array) -> ArrayMesh:
 var v = PackedVector2Array()
 for i in range(1,pts.size()-1):
  v.append(pts[0])
  v.append(pts[i])
  v.append(pts[i+1])
 var arr = []
 arr.resize(Mesh.ARRAY_MAX)
 arr[Mesh.ARRAY_VERTEX] = v
 var m = ArrayMesh.new()
 m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
 return m

# Names by importance (level, then yours, then the rest by name), each kept only if it overlaps no
# name or seal already placed: a crowded map shows its larger settlements, never a pile of text,
# and the larger the map is on screen, the more names fit.
const NAME_PAD = 3.0
const ID_MAX_WIDTH = 2048
func _place_labels():
 _labels.clear()
 var font = UiKit.FONT_BOLD
 var me = data.player_faction_id()
 var order = range(_seals.size())
 order.sort_custom(func(a,b):
  var sa = _seals[a]
  var sb = _seals[b]
  if sa[2] != sb[2]: return sa[2]>sb[2]
  var ma = _owners.get(sa[4],"") == me
  var mb = _owners.get(sb[4],"") == me
  if ma != mb: return ma
  return sa[3]<sb[3])
 var taken = {} # 48 px buckets -> [Rect2]
 for s in _seals:
  var p = to_screen(s[0])
  _take(taken,Rect2(p-Vector2(9,8),Vector2(18,23)))
 var r = map_rect()
 for k in order:
  var s = _seals[k]
  var fs = 15 if s[2]>=3 else 13
  var w = font.get_string_size(s[3],HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
  var p = to_screen(s[0])
  var top = -12.0-fs*0.85-NAME_PAD # the glyphs above the baseline at -12, clear of the seal below
  var box = Rect2(p+Vector2(-w*0.5-NAME_PAD,top),Vector2(w+NAME_PAD*2,-10.0-top))
  if not r.encloses(box) or _hits(taken,box): continue
  _take(taken,box)
  _labels.append([p+Vector2(-w*0.5,-12),s[3],fs])

func _buckets_of(box: Rect2) -> Array:
 var out = []
 for by in range(int(floor(box.position.y/48.0)),int(floor(box.end.y/48.0))+1):
  for bx in range(int(floor(box.position.x/48.0)),int(floor(box.end.x/48.0))+1): out.append(Vector2i(bx,by))
 return out

func _hits(taken: Dictionary,box: Rect2) -> bool:
 for b in _buckets_of(box):
  for other in taken.get(b,[]):
   if other.intersects(box): return true
 return false

func _take(taken: Dictionary,box: Rect2):
 for b in _buckets_of(box): taken.get_or_add(b,[]).append(box)

func _draw_overlay():
 var font = UiKit.FONT_BOLD
 for l in _labels: _overlay.draw_string(font,l[0]+Vector2(1,1),l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,l[2],Color(0,0,0,0.7))
 for l in _labels: _overlay.draw_string(font,l[0],l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,l[2],Color("2a1c10"))
 for a in _armies:
  if a[0] != selected_army: continue
  var p = to_screen(a[1])
  var shield = PackedVector2Array([p+Vector2(-6,-8),p+Vector2(6,-8),p+Vector2(6,2),p+Vector2(0,9),p+Vector2(-6,2),p+Vector2(-6,-8)])
  _overlay.draw_polyline(shield,Color("f2cf6a"),2.0)

func _gui_input(e):
 if not showing: return
 if e is InputEventMouseButton and e.pressed:
  var r = map_rect()
  if not r.has_point(e.position): return
  if e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_WHEEL_UP:
   location_chosen.emit(to_world(e.position))
   accept_event()
