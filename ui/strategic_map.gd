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

signal location_chosen(world: Vector2,from_scroll: bool) # click (zoomed in) or scroll in (at the highest 3D zoom): return to the 3D map there
signal closed
signal palette_changed # the territory colours changed (the minimap shares them)

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const Settings = preload("res://core/settings.gd")
const MapShader = preload("res://ui/strategic_map.gdshader")
const Paint = preload("res://ui/strategic_paint.gd")
const Icons = preload("res://ui/icons.gd")
const FADE = 0.35
# Map modes (TW:WH3 overlays; owner 2026-10-06: Political and Diplomacy first, Religion, Culture and
# Resources ready for later). available: false = greyed until its system exists.
const LAYERS = [
 {"id":"political","name":"Political","available":true,"tip":"Who owns each region: your realm bright and outlined, other realms muted, occupied and besieged land hatched in the occupier's colour, vassals striped with their liege's colour"},
 {"id":"diplomacy","name":"Diplomacy","available":true,"tip":"Every realm coloured by its relation to you: yours, vassals, allies, trade partners, neutral, hostile, at war"},
 {"id":"religion","name":"Religion","available":false,"tip":"The faiths of each region"},
 {"id":"culture","name":"Culture","available":true,"tip":"The culture each region's land belongs to; a region being converted shows both, blended by how far it has turned (game-design §12.13)"},
 {"id":"resources","name":"Resources","available":false,"tip":"Food, wood, stone and gold in each region"},
 {"id":"order","name":"Public order","available":true,"tip":"Public order of each province (placeholder values until the public order system exists)"},
 {"id":"development","name":"Development","available":true,"tip":"Settlement level of each region"},
 {"id":"climate","name":"Terrain","available":true,"tip":"Terrain: plains, forest, hills, mountains, passes and water"},
]
const LAYER_ALIASES = {"affiliation":"political","diplomatic":"diplomacy"} # older capture flags
# Diplomacy mode: relation to the player (UiData.relation_to_player) -> colour and legend name.
const RELATIONS = [["self",Color("3f9be0"),"You"],["vassal",Color("8fc8f0"),"Your vassals"],["ally",Color("4fb34a"),"Allies"],["trade",Color("c9b84a"),"Trade partners"],["neutral",Color("a9a39a"),"Neutral"],["hostile",Color("d9822b"),"Hostile"],["war",Color("c8382c"),"At war"]]
const CAELOTH_FILL = Color("f1e8c8")
const TERRAIN_PARCHMENT = {"open":Color("e6d4ab"),"settlement":Color("e6d4ab"),"forest":Color("c5c48f"),"hills":Color("d8c08a"),"mountain":Color("a58f6c"),"pass":Color("c6ad83"),"water":Color("9fb3ad")}
const TERRAIN_VIVID = {"open":Color("b8cf7e"),"settlement":Color("b8cf7e"),"forest":Color("5f8f4a"),"hills":Color("c9b16a"),"mountain":Color("8c7a64"),"pass":Color("b59a6c"),"water":Color("4f7f9c")}

var data
var world_rect: Rect2
var layer := "political"
var base_parchment: ImageTexture
var base_vivid: ImageTexture
var layer_buttons := {}
var legend: VBoxContainer
var legend_collapsed := false
var fade := 0.0
var showing := false
var selected_army := ""
var _fills := {}    # region id -> fill colour on the current layer
var _seals := []    # [world position, colour, level, name, region id]
var _armies := []   # [id, world position, colour]
var _owners := {}   # region id -> owner faction id
var _polys := {}    # region id -> screen polygon (closed), for _poly_size
var _poly_size = null # the size, zoom and centre the polygons were placed for
var _surface: TextureRect # the territory (shader)
var _icons: Node2D        # seal, pip and army MultiMeshes
var _overlay: Control     # names and the selected army's ring
var _index := {}          # region id -> palette index
var _palette: Image
var _palette_tex: ImageTexture
var _labels := []         # placed names: [screen position, text, font size]
var _layout_key = null
var _clip: Control         # the map's frame: clips a zoomed map
var _glyph_layer: Node2D  # mountains, hills and trees (MultiMeshes)
var _glyph_key = null
var _paint := {}          # ui/strategic_paint.gd textures and glyphs
var _region_labels := []  # province names: [screen position, text, font size, alpha]
var _realms := []         # [faction id, world centre, settlement count], largest first
var _realm_labels := []   # placed realm labels: [screen position, text, font size, faction]
# Zoom (1 = the whole world in the frame, up to MAX_ZOOM) and the world point at the frame centre.
const MAX_ZOOM = 3.0
var zoom := 1.0
var center := Vector2.INF
var _drag := false

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
 close.tooltip_text = "Back to the campaign map (Tab or Esc).
On the map: the wheel zooms, right drag pans, click or scroll in past the closest zoom to go there."
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
 id = LAYER_ALIASES.get(id,id)
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
 # Realms: crest and name at each realm's centre, sized by its size (political map).
 _realms.clear()
 var by = {}
 for sid in _owners:
  var o = _owners[sid]
  if o == "": continue
  if not by.has(o): by[o] = []
  by[o].append(WorldMap.settlement_position(sid))
 for o in by:
  var c = Vector2.ZERO
  for p in by[o]: c += p
  _realms.append([o,c/by[o].size(),by[o].size()])
 _realms.sort_custom(func(a,b): return a[2]>b[2] if a[2] != b[2] else a[0]<b[0])
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
 if debug == "regions":
  for id in WorldMap.regions(): _fills[id] = _debug_fill(id)
 elif layer != "climate" and debug != "movement":
  for id in WorldMap.regions():
   var c = region_color(id)
   if c.a>0.0: _fills[id] = c
 _update_palette()

func _screen_polys() -> Dictionary:
 if _poly_size != [size,zoom,center]:
  _poly_size = [size,zoom,center]
  _polys.clear()
  var regions = WorldMap.regions()
  for id in regions:
   var pts = PackedVector2Array()
   for p in regions[id].points: pts.append(to_screen(p))
   _polys[id] = pts
 return _polys

# --- Geometry ---------------------------------------------------------------------------------

# The frame on screen (below the layer bar) and the map inside it: the whole world letterboxed at
# zoom 1; zoomed in, a larger map around `center`, clamped so it always fills the frame.
var frame_margin := Rect2(16,128,32,144) # left, top, total width and height taken (previews use less)
func frame_rect() -> Rect2:
 return Rect2(frame_margin.position,size-frame_margin.size)

func map_rect() -> Rect2:
 var area = frame_rect()
 var s = minf(area.size.x/world_rect.size.x,area.size.y/world_rect.size.y)
 var sz = world_rect.size*s*zoom
 if zoom<=1.0 or not center.is_finite(): return Rect2(area.position+(area.size-sz)*0.5,sz)
 var pos = area.get_center()-(center-world_rect.position)/world_rect.size*sz
 for k in 2:
  if sz[k]>area.size[k]: pos[k] = clampf(pos[k],area.end[k]-sz[k],area.position[k])
  else: pos[k] = area.position[k]+(area.size[k]-sz[k])*0.5
 return Rect2(pos,sz)

# Zoom by `factor` keeping the world point under `at` (screen) in place.
func zoom_at(at: Vector2,factor: float):
 var w = to_world(at)
 var z = clampf(zoom*factor,1.0,MAX_ZOOM)
 if z == zoom: return
 var area = frame_rect()
 var s = minf(area.size.x/world_rect.size.x,area.size.y/world_rect.size.y)*z
 zoom = z
 center = w+(area.get_center()-at)/s
 _layout()

func pan_by(delta: Vector2):
 if zoom<=1.0: return
 center = to_world(frame_rect().get_center()-delta)
 center = to_world(frame_rect().get_center()) # back inside the clamped map
 _layout()

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
  "political":
   if owner == "": return Color(0,0,0,0)
   if _is_caeloth(owner): return Color(CAELOTH_FILL,0.8)
   var col = Color(data.faction(owner).primary)
   # An occupied region keeps its rightful owner's colour under the occupier's hatching.
   var home = _home_owner(id)
   if home != owner and _occupied(id): col = Color(data.faction(home).primary)
   # Your realm saturated and strong; other realms muted (TW:WH3 political map).
   if owner == data.player_faction_id(): return Color(col.lightened(0.05),0.78)
   var g = col.get_luminance()
   return Color(col.lerp(Color(g,g,g),0.35),0.48)
  "diplomacy":
   if owner == "": return Color(0,0,0,0)
   if _is_caeloth(owner) and owner != data.player_faction_id(): return Color(CAELOTH_FILL,0.8)
   var rel = data.relation_to_player(owner)
   for r in RELATIONS:
    if r[0] == rel: return Color(r[1],0.72 if rel == "self" else 0.6)
   return Color(0,0,0,0)
  "order":
   var po = float(data.province_stats(s.province).public_order)
   return Color("c8382c").lerp(Color("4fb34a"),clampf((po+100.0)/200.0,0,1))*Color(1,1,1,0.6)
  "development":
   return Color("f4e2a6").lerp(Color("8a5a12"),clampf((int(s.level)-1)/2.0,0,1))*Color(1,1,1,0.65)
  "culture":
   var l = data.land(id)
   return Color(Color(l.from_color).lerp(Color(l.to_color),float(l.value)),0.62)
 return Color(0,0,0,0)

# Political-mode marks per region (the shader's palette rows 2 and 3): flags 1 = the player's land,
# 2 = a vassal (striped in its liege's colour), 4 = occupied or besieged (hatched in the occupier's
# colour), 8 = Caeloth (its own neutral style); and the pattern colour.
func region_marks(id: String) -> Dictionary:
 var out = {"flags":0,"pattern":Color(0,0,0,0)}
 var s = data.state.settlements.get(id,{})
 if s.is_empty(): return out
 var owner = str(s.owner)
 if owner == "": return out
 if owner == data.player_faction_id(): out.flags |= 1
 if _is_caeloth(owner): out.flags |= 8
 if layer != "political": return out
 var liege = data.liege_of(owner)
 if liege != "":
  out.flags |= 2
  out.pattern = Color(data.faction(liege).primary)
 var sg = s.get("siege",{})
 if not sg.is_empty() and data.state.army_state.has(sg.get("army","")):
  out.flags |= 4
  out.pattern = Color(data.faction(data.state.army_state[sg.army].faction).primary)
 elif _occupied(id):
  out.flags |= 4
  out.pattern = Color(data.faction(owner).primary)
 return out

func _is_caeloth(f: String) -> bool:
 return bool(WorldMap.faction(f).get("untouchable",false))

# The region's owner at the start of the campaign (its rightful owner for the political map).
func _home_owner(id: String) -> String:
 return str(WorldMap.region(id).get("owner",""))

# Taken from a faction that still stands and is at war with the holder.
func _occupied(id: String) -> bool:
 var owner = str(data.state.settlements[id].owner)
 var home = _home_owner(id)
 if home == "" or home == owner or home in data.state.destroyed: return false
 if data.state.settlements_of(home).is_empty(): return false
 return load("res://core/battles.gd").at_war(data.state,home,owner)

func _fill_legend():
 if legend == null: return
 for c in legend.get_children(): c.queue_free()
 var title = ""
 for l in LAYERS:
  if l.id == layer: title = l.name
 # Collapsible (TW:WH3 legends fold away): the title toggles the rows.
 var head = Button.new()
 head.name = "LegendToggle"
 head.flat = true
 head.focus_mode = Control.FOCUS_NONE
 head.alignment = HORIZONTAL_ALIGNMENT_LEFT
 head.text = ("▸ " if legend_collapsed else "▾ ")+title
 head.add_theme_font_override("font",UiKit.head_font())
 head.pressed.connect(func():
  legend_collapsed = not legend_collapsed
  _fill_legend())
 legend.add_child(head)
 if legend_collapsed: return
 var rows = []
 match layer:
  "political":
   rows.append([Color(data.faction(data.player_faction_id()).primary),"Your realm (outlined)"])
   rows.append([Color(0,0,0,0),"Hatched: occupied or besieged"])
   rows.append([Color(0,0,0,0),"Striped: a vassal, in its liege's colour"])
   # Only the factions you have met (yours, at war with you, or near your lands and armies).
   for f in data.known_factions():
    if not data.state.settlements_of(f).is_empty(): rows.append([Color(data.faction(f).primary),data.faction(f).name])
   var hidden = data.state.factions().size()-data.known_factions().size()
   if hidden>0: rows.append([Color(0,0,0,0),"(%d factions not met)" % hidden])
  "diplomacy":
   for r in RELATIONS: rows.append([r[1],r[2]])
   rows.append([CAELOTH_FILL,"Caeloth (untouchable)"])
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
 # A parchment map's frame: a dark outer band, a gilt rule and an inked inner line.
 var f = frame_rect().intersection(map_rect())
 draw_rect(f.grow(9),Color("1a130d"))
 draw_rect(f.grow(6),Color("b8955a"),false,1.5)
 draw_rect(f.grow(3),Color("3a2a1a"),false,2.0)

# The territory surface (one shader pass), the relief glyphs, the icon layer and the name layer,
# under the bars, inside a clip so a zoomed map stays in its frame.
func _build_surface():
 var rr = _region_raster()
 for i in rr.names.size(): _index[rr.names[i]] = i+1
 _palette = Image.create(rr.names.size()+1,4,false,Image.FORMAT_RGBA8)
 _palette_tex = ImageTexture.create_from_image(_palette)
 _clip = Control.new()
 _clip.name = "MapClip"
 _clip.clip_contents = true
 _clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(_clip)
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
 _paint = Paint.build(world_rect)
 for k in ["heights","biome","rivers","coast","paint_xform","coast_xform","texel","relief","coast_texel"]: mat.set_shader_parameter(k,_paint[k])
 _surface.material = mat
 _clip.add_child(_surface)
 _glyph_layer = Node2D.new()
 _glyph_layer.name = "Glyphs"
 _clip.add_child(_glyph_layer)
 _icons = Node2D.new()
 _icons.name = "Icons"
 _clip.add_child(_icons)
 _overlay = Control.new()
 _overlay.name = "Names"
 _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _overlay.draw.connect(_draw_overlay)
 _clip.add_child(_overlay)

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
  origin = rs.origin
  span = Vector2(rs.cols,rs.rows)*float(rs.cell)
  # Smooth borders: the region polygons (vector, from the sketch) rasterised finer than the baked
  # raster, up to POLY_RASTER_MAX wide; cached per map.
  var regions = WorldMap.regions()
  if names.all(func(n): return regions.has(n) and regions[n].points.size()>=3):
   cols = mini(POLY_RASTER_MAX,rs.cols*8)
   rows = maxi(1,int(round(cols*float(rs.rows)/rs.cols)))
   var key = "%s|%d|%d" % [MapRegistry.active,cols,rows]
   if not _poly_raster.has(key):
    # Keep the polygon's id where it agrees with the baked raster within one baked cell (smooth
    # borders); elsewhere the baked id (flood-filled regions only have convex hulls, and polygons
    # may reach into the sea).
    var fine = rasterize(names,origin,span,cols,rows)
    var sx = float(rs.cols)/cols
    var sz = float(rs.rows)/rows
    for z in rows:
     var bz = mini(rs.rows-1,int(z*sz))
     for x in cols:
      var bx = mini(rs.cols-1,int(x*sx))
      var f = fine[z*cols+x]
      var b = rs.ids[bz*rs.cols+bx]
      if f == b: continue
      var near = false
      for dz in [-1,0,1]:
       for dx in [-1,0,1]:
        var nz = bz+dz
        var nx = bx+dx
        if nz>=0 and nx>=0 and nz<rs.rows and nx<rs.cols and rs.ids[nz*rs.cols+nx] == f: near = true
      if not near: fine[z*cols+x] = b
    _poly_raster[key] = fine
   ids = _poly_raster[key]
  else:
   ids = rs.ids
   cols = rs.cols
   rows = rs.rows
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

# Palette: row 0 the current layer's fills, row 1 owner colours (borders), row 2 the owner's index
# (R + 256 G, so borders compare owners, not colours) and the region's marks in B, row 3 the marks'
# pattern colour (stripes and hatching).
func _update_palette():
 if _palette == null: return
 _write_palette(_palette,_fills)
 _palette_tex.update(_palette)
 # The minimap always shows the political map (A3): its own palette, filled the same way.
 if mini_palette_tex != null:
  var keep = layer
  layer = "political"
  var fills = {}
  for id in WorldMap.regions():
   var c = region_color(id)
   if c.a>0.0: fills[id] = c
  _write_palette(mini_palette,fills)
  layer = keep
  mini_palette_tex.update(mini_palette)
 _surface.texture = base_vivid if layer == "climate" or debug == "movement" else base_parchment
 # Painted parchment except for the movement classes; the climate layer washes the ground colours
 # in strongly.
 _surface.material.set_shader_parameter("painted",debug != "movement")
 _surface.material.set_shader_parameter("wash",0.85 if layer == "climate" else 0.5)
 _surface.material.set_shader_parameter("player_color",Color(data.faction(data.player_faction_id()).primary))
 _surface.material.set_shader_parameter("political",layer == "political")
 palette_changed.emit()

func _write_palette(img: Image,fills: Dictionary):
 img.fill(Color(0,0,0,0))
 for id in fills:
  if _index.has(id): img.set_pixel(_index[id],0,fills[id])
 var index = {}
 for id in _owners:
  var o = _owners[id]
  if o == "" or not _index.has(id): continue
  if not index.has(o): index[o] = index.size()+1
  var own = Color(data.faction(o).primary).darkened(0.2)
  if _is_caeloth(o): own = Color("b89a4a")
  img.set_pixel(_index[id],1,Color(own,1.0))
  var m = region_marks(id)
  img.set_pixel(_index[id],2,Color8(index[o]%256,index[o]/256,m.flags,255))
  img.set_pixel(_index[id],3,m.pattern)

# The territory surface's material for another view of the same map (the minimap): the same region
# raster and paint, the political palette.
var mini_palette: Image
var mini_palette_tex: ImageTexture
func minimap_material() -> ShaderMaterial:
 if mini_palette_tex == null:
  mini_palette = _palette.duplicate()
  mini_palette_tex = ImageTexture.create_from_image(mini_palette)
  _update_palette()
 var m: ShaderMaterial = _surface.material.duplicate()
 m.set_shader_parameter("palette",mini_palette_tex)
 m.set_shader_parameter("political",true)
 m.set_shader_parameter("wash",0.5)
 return m

# Positions follow the screen: the surface, the glyphs, the icons and the names are laid out again
# when the size, the zoom or the campaign state changes.
func _layout():
 if _surface == null or data == null: return
 var r = map_rect()
 if r.size.x<=0.0 or r.size.y<=0.0: return
 var area = frame_rect()
 queue_redraw() # the frame follows the zoom
 _clip.position = area.position
 _clip.size = area.size
 # Children of the clip draw in this control's coordinates.
 _surface.position = r.position-area.position
 _surface.size = r.size
 if _paint.has("coast_cells_per_world"): _surface.material.set_shader_parameter("coast_px",float(_paint.coast_cells_per_world)*world_rect.size.x/r.size.x)
 for n in [_glyph_layer,_icons]: n.position = -area.position
 _overlay.position = -area.position
 _overlay.size = size
 _layout_glyphs()
 var key = [size,_seals.size(),_armies.size(),zoom,center]
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

# Mountains, hills and trees as ink-outlined glyphs (MultiMeshes), sized by the glyph grid's
# spacing on screen; skipped when the map is too small for them to read.
func _layout_glyphs():
 var r = map_rect()
 var key = [r]
 if key == _glyph_key: return
 _glyph_key = key
 for c in _glyph_layer.get_children():
  _glyph_layer.remove_child(c)
  c.free()
 var spacing = r.size.x/Paint.GLYPHS_ACROSS
 var base = spacing/zoom # glyphs grow slower than the map: zoomed in, they spread out
 if spacing<2.5 or _paint.is_empty(): return
 var px = clampf(base*1.25*sqrt(zoom),5.0,40.0)
 var meshes = _glyph_meshes()
 var sets = {"m_back":[],"m":[],"snow":[],"h_back":[],"h":[],"t_back":[],"t":[]}
 var ink = Color(0.2,0.15,0.11,0.9)
 var area = frame_rect().grow(px*2)
 for gl in _paint.glyphs:
  var p = to_screen(gl[0])
  if not area.has_point(p): continue
  var s = px*float(gl[2])
  match int(gl[1]):
   0:
    var xf = Transform2D(0.0,Vector2(s*(1.3+gl[3]*0.3),s*1.35),0.0,p)
    sets.m_back.append([xf,ink])
    sets.m.append([xf,_glyph_tint(gl,0.55).darkened(gl[3]*0.12)])
    var ground = _glyph_tint(gl,1.0)
    if gl[2]>1.05 and ground.get_luminance()>0.62 and ground.s<0.25: sets.snow.append([xf,Color.WHITE])
   1:
    var xf = Transform2D(0.0,Vector2(s,s*0.8),0.0,p)
    sets.h_back.append([xf,ink])
    sets.h.append([xf,_glyph_tint(gl,0.45).darkened(gl[3]*0.1)])
   2:
    var xf = Transform2D(0.0,Vector2(s,s)*0.55,0.0,p)
    sets.t_back.append([xf,ink])
    sets.t.append([xf,_glyph_tint(gl,0.35).darkened(gl[3]*0.18)])
 for k in [["h_back","hill_back"],["h","hill"],["t_back","tree_back"],["t","tree"],["m_back","mountain_back"],["m","mountain"],["snow","snow"]]:
  if not sets[k[0]].is_empty(): _glyph_layer.add_child(_multimesh(meshes[k[1]],sets[k[0]]))


# A glyph's colour: white (its own painted colours) pulled toward the ground under it by `amount`,
# kept light so the glyph still reads (red peaks, dark ash walls, pale snowfields).
func _glyph_tint(gl: Array,amount: float) -> Color:
 if gl.size()<5: return Color.WHITE
 var g: Color = gl[4]
 var t = Color.WHITE.lerp(g.lightened(0.35),amount)
 return t

static var _gmeshes := {}
static func _glyph_meshes() -> Dictionary:
 if not _gmeshes.is_empty(): return _gmeshes
 var lit = Color("dccaa2")
 var shade = Color("8a7458")
 # Mountain: a peak with a lit west face and a shaded east face, its base on the point.
 _gmeshes.mountain = _tris([[[Vector2(-0.62,0),Vector2(-0.08,-1),Vector2(0.06,0)],lit],[[Vector2(0.06,0),Vector2(-0.08,-1),Vector2(0.62,0)],shade]])
 _gmeshes.mountain_back = _tris([[[Vector2(-0.74,0.06),Vector2(-0.08,-1.12),Vector2(0.74,0.06)],Color.WHITE]])
 _gmeshes.snow = _tris([[[Vector2(-0.3,-0.56),Vector2(-0.08,-1),Vector2(-0.02,-0.6)],Color("f4f1e8")],[[Vector2(-0.02,-0.6),Vector2(-0.08,-1),Vector2(0.16,-0.62)],Color("cfd3d4")]])
 # Hill: a low dome, lit west and shaded east.
 var west = []
 var east = []
 for i in 8:
  var a0 = PI+i*PI/16.0
  var a1 = PI+(i+1)*PI/16.0
  west.append([[Vector2.ZERO,Vector2(cos(a0)*0.6,sin(a0)*0.42),Vector2(cos(a1)*0.6,sin(a1)*0.42)],Color("d4bf8e")])
  var b0 = 1.5*PI+i*PI/16.0
  var b1 = 1.5*PI+(i+1)*PI/16.0
  east.append([[Vector2.ZERO,Vector2(cos(b0)*0.6,sin(b0)*0.42),Vector2(cos(b1)*0.6,sin(b1)*0.42)],Color("a48c63")])
 _gmeshes.hill = _tris(west+east)
 var back = []
 for i in 16:
  var a0 = PI+i*PI/16.0
  var a1 = PI+(i+1)*PI/16.0
  back.append([[Vector2(0,0.05),Vector2(cos(a0)*0.7,sin(a0)*0.52),Vector2(cos(a1)*0.7,sin(a1)*0.52)],Color.WHITE])
 _gmeshes.hill_back = _tris(back)
 # Tree: a three-lobed canopy, dark with a lit crown, on a short trunk.
 var tree = [[[Vector2(-0.07,0),Vector2(0.07,0),Vector2(0,-0.5)],Color("5a4632")]]
 var tb = []
 for lobe in [[Vector2(-0.3,-0.5),0.34,Color("4f6b3b")],[Vector2(0.3,-0.52),0.32,Color("49633a")],[Vector2(0,-0.85),0.36,Color("5d7a44")],[Vector2(-0.1,-0.95),0.16,Color("86a35e")]]:
  tree.append_array(_disc_tris(lobe[0],lobe[1],lobe[2]))
 for lobe in [[Vector2(-0.3,-0.5),0.42],[Vector2(0.3,-0.52),0.4],[Vector2(0,-0.85),0.44]]:
  tb.append_array(_disc_tris(lobe[0],lobe[1],Color.WHITE))
 _gmeshes.tree = _tris(tree)
 _gmeshes.tree_back = _tris(tb)
 return _gmeshes

static func _disc_tris(c: Vector2,r: float,col: Color) -> Array:
 var out = []
 for i in 10:
  out.append([[c,c+Vector2.from_angle(i*TAU/10)*r,c+Vector2.from_angle((i+1)*TAU/10)*r],col])
 return out

static func _tris(tris: Array) -> ArrayMesh:
 var v = PackedVector2Array()
 var col = PackedColorArray()
 for t in tris:
  for p in t[0]:
   v.append(p)
   col.append(t[1])
 var arr = []
 arr.resize(Mesh.ARRAY_MAX)
 arr[Mesh.ARRAY_VERTEX] = v
 arr[Mesh.ARRAY_COLOR] = col
 var m = ArrayMesh.new()
 m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
 return m
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
# and the larger the map is on screen, the more names fit. Labels thin with the zoom (TW:WH3,
# docs/tw-ui-parity.md §15): zoomed out, province names in spaced capitals and only the larger
# settlements (level 2+ and yours); zoomed in, every settlement name and no province names.
const NAME_PAD = 3.0
const ID_MAX_WIDTH = 2048
const POLY_RASTER_MAX = 2048
static var _poly_raster := {} # map|cols|rows -> ids from the region polygons
const PROVINCE_NAMES_UNTIL = 2.0 # zoom at which province names have faded out
const ALL_SETTLEMENTS_FROM = 1.4 # zoom from which small settlements are named too
func _place_labels():
 _labels.clear()
 _region_labels.clear()
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
 var r = frame_rect().intersection(map_rect())
 # Realm names first on the political and diplomacy maps: crest and name at each realm's centre,
 # larger for larger realms (TW:WH3 faction labels); a one-settlement realm only when zoomed in.
 _realm_labels.clear()
 if layer in ["political","diplomacy"]:
  var hf0 = UiKit.head_font()
  for rl in _realms:
   if int(rl[2])<2 and zoom<ALL_SETTLEMENTS_FROM and rl[0] != me: continue
   var fs0 = int(clampf(13.0+4.0*sqrt(float(rl[2])),14.0,34.0))
   var text0 = str(data.faction(rl[0]).name).to_upper()
   var w0 = hf0.get_string_size(text0,HORIZONTAL_ALIGNMENT_LEFT,-1,fs0).x+fs0*1.2
   var p0 = to_screen(rl[1])+Vector2(0,-30)
   var box0 = Rect2(p0+Vector2(-w0*0.5-NAME_PAD,-fs0),Vector2(w0+NAME_PAD*2,fs0*1.25))
   if not r.encloses(box0) or _hits(taken,box0): continue
   _take(taken,box0)
   _realm_labels.append([p0+Vector2(-w0*0.5,0),text0,fs0,rl[0]])
 # Province names first while zoomed out (they matter most at that scale).
 var pa = clampf((PROVINCE_NAMES_UNTIL-zoom)/(PROVINCE_NAMES_UNTIL-1.0),0.0,1.0)
 if pa>0.0:
  var hf = UiKit.head_font()
  var fs = int(round(16.0+4.0*zoom))
  for prov in WorldMap.provinces():
   var regs = WorldMap.settlements_in(prov.id)
   if regs.is_empty(): continue
   var c = Vector2.ZERO
   for sid in regs: c += WorldMap.settlement_position(sid)
   var text = _spaced(str(prov.name).to_upper())
   var w = hf.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
   var p = to_screen(c/regs.size())+Vector2(0,26)
   var box = Rect2(p+Vector2(-w*0.5-NAME_PAD,-fs),Vector2(w+NAME_PAD*2,fs+NAME_PAD))
   if not r.encloses(box) or _hits(taken,box): continue
   _take(taken,box)
   _region_labels.append([p+Vector2(-w*0.5,0),text,fs,pa])
 for k in order:
  var s = _seals[k]
  if zoom<ALL_SETTLEMENTS_FROM and int(s[2])<2 and _owners.get(s[4],"") != me: continue
  var fs = 15 if s[2]>=3 else 13
  var w = font.get_string_size(s[3],HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
  var p = to_screen(s[0])
  var top = -12.0-fs*0.85-NAME_PAD # the glyphs above the baseline at -12, clear of the seal below
  var box = Rect2(p+Vector2(-w*0.5-NAME_PAD,top),Vector2(w+NAME_PAD*2,-10.0-top))
  if not r.encloses(box) or _hits(taken,box): continue
  _take(taken,box)
  _labels.append([p+Vector2(-w*0.5,-12),s[3],fs])

# Spaced capitals for province names ("G R E Y W A T E R").
static func _spaced(t: String) -> String:
 var out = ""
 for i in t.length():
  out += t[i]
  if i<t.length()-1: out += " " if t[i] != " " else "  "
 return out
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
 _draw_debug()
 # Aged edges: a soft brown vignette inside the frame.
 var f = frame_rect().intersection(map_rect())
 for i in 10:
  _overlay.draw_rect(f.grow(-i*2.5),Color(0.24,0.16,0.08,0.05),false,2.5)
 var hf = UiKit.head_font()
 for l in _region_labels: _overlay.draw_string(hf,l[0],l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,l[2],Color(0.22,0.14,0.08,0.62*l[3]))
 # Realm labels: the crest (a small shield) before the name, in the faction's colours.
 for l in _realm_labels:
  var fs = float(l[2])
  var fd = data.faction(l[3])
  var sh = Rect2(l[0]+Vector2(0,-fs*0.95),Vector2(fs*0.8,fs*1.0))
  var pts = PackedVector2Array([sh.position,sh.position+Vector2(sh.size.x,0),sh.position+Vector2(sh.size.x,sh.size.y*0.62),sh.position+Vector2(sh.size.x*0.5,sh.size.y),sh.position+Vector2(0,sh.size.y*0.62)])
  Icons.crest(_overlay,fd,pts,sh.grow(-sh.size.x*0.18))
  var outline = pts.duplicate()
  outline.append(pts[0])
  _overlay.draw_polyline(outline,Color(0.16,0.1,0.05),1.5)
  var at = l[0]+Vector2(fs*1.2,0)
  _overlay.draw_string_outline(hf,at,l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs),5,Color(0.95,0.9,0.76,0.9))
  _overlay.draw_string(hf,at,l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs),Color(fd.primary).darkened(0.45))
 var font = UiKit.FONT_BOLD
 for l in _labels: _overlay.draw_string_outline(font,l[0],l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,l[2],4,Color(0.93,0.87,0.72,0.85))
 for l in _labels: _overlay.draw_string(font,l[0],l[1],HORIZONTAL_ALIGNMENT_LEFT,-1,l[2],Color("2a1c10"))
 for a in _armies:
  if a[0] != selected_army: continue
  var p = to_screen(a[1])
  var shield = PackedVector2Array([p+Vector2(-6,-8),p+Vector2(6,-8),p+Vector2(6,2),p+Vector2(0,9),p+Vector2(-6,2),p+Vector2(-6,-8)])
  _overlay.draw_polyline(shield,Color("f2cf6a"),2.0)

# Left click returns to the 3D map there, zoomed in. Scrolling in returns to the 3D map at its highest
# zoom, centred on the cursor (TW:WH3). Ctrl+wheel zooms the parchment itself (around the cursor);
# scrolling out zooms it back out. Right or middle drag pans a zoomed parchment.
func _gui_input(e):
 if not showing: return
 if e is InputEventMouseMotion:
  if debug == "problems": tooltip_text = _debug_tooltip(e.position)
  if _drag:
   pan_by(e.relative)
   accept_event()
  return
 if e is InputEventMouseButton:
  if e.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
   _drag = e.pressed and zoom>1.0
   return
  if not e.pressed: return
  var r = map_rect()
  if not r.has_point(e.position) or not frame_rect().has_point(e.position): return
  if e.button_index == MOUSE_BUTTON_LEFT:
   location_chosen.emit(to_world(e.position),false)
   accept_event()
  elif e.button_index == MOUSE_BUTTON_WHEEL_UP and not e.ctrl_pressed:
   # TW:WH3: scrolling in returns to the 3D map, at its highest zoom, centred on the cursor.
   location_chosen.emit(to_world(e.position),true)
   accept_event()
  elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
   zoom_at(e.position,1.25) # Ctrl+wheel zooms the parchment itself
   accept_event()
  elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
   zoom_at(e.position,1.0/1.25)
   accept_event()

# --- Debug overlay (docs/map-pipeline-design.md §5.2; debug keys on: F9 cycles) ------------------
# regions: every region in its own colour with its ID; movement: the movement classes; problems:
# the validator's problems as red markers (hover for the message).
const DEBUG_LAYERS = ["","regions","movement","problems"]
const Validator = preload("res://map/validator.gd")
const MapRegistry = preload("res://core/map_registry.gd")
var debug := ""
var _problems := []

func set_debug(kind: String):
 debug = kind
 if kind == "problems": _problems = Validator.validate(MapRegistry.active).problems.filter(func(p): return p.pos != null)
 _rebuild_fills()
 if _overlay != null: _overlay.queue_redraw()

func cycle_debug():
 set_debug(DEBUG_LAYERS[(DEBUG_LAYERS.find(debug)+1)%DEBUG_LAYERS.size()])

func _unhandled_key_input(e):
 if showing and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F9 and Settings.debug_keys():
  cycle_debug()
  get_viewport().set_input_as_handled()

func _debug_fill(id: String) -> Color:
 var h = float(hash(id)%997)/997.0
 return Color.from_hsv(h,0.65,0.95,0.7)

func _draw_debug():
 var font = UiKit.FONT_BOLD
 match debug:
  "regions":
   for id in WorldMap.regions():
    var pts = WorldMap.regions()[id].points
    if pts.is_empty(): continue
    var c = Vector2.ZERO
    for p in pts: c += p
    var at = to_screen(c/pts.size())
    var w = font.get_string_size(id,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
    _overlay.draw_rect(Rect2(at-Vector2(w*0.5+3,12),Vector2(w+6,16)),Color(0,0,0,0.6))
    _overlay.draw_string(font,at-Vector2(w*0.5,0),id,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
  "problems":
   for p in _problems:
    var at = to_screen(p.pos)
    _overlay.draw_circle(at,7.0,Color(0.9,0.1,0.1,0.9))
    _overlay.draw_circle(at,3.0,Color.WHITE)
 if debug != "":
  var label = "Debug: %s (F9)" % debug
  if debug == "problems": label += " — %d with a position" % _problems.size()
  _overlay.draw_string(font,map_rect().position+Vector2(8,20),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(1,0.3,0.3))

# Hover over a problem marker: its message as the tooltip.
func _debug_tooltip(at: Vector2) -> String:
 for p in _problems:
  if to_screen(p.pos).distance_to(at)<9.0: return "%s (%s): %s" % [p.level.capitalize(),p.check,p.message]
 return ""
