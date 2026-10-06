extends Control
# New campaign: choose one of the three playable houses (Stage A, 2026-10-06; TW:WH3's faction
# selection: the houses on the left, the chosen house's founder, tradition and culture beside a
# preview of its start on the map). Texts from data/campaign_intro.json; the preview is the
# strategic map (ui/strategic_map.gd) zoomed onto the house's seat. `chosen` gives the faction id.

signal chosen(faction_id: String)
signal cancelled

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const WorldMap = preload("res://core/world_map.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const UiData = preload("res://core/ui_data.gd")
const StrategicMap = preload("res://ui/strategic_map.gd")

var data := {}
var state
var selected := ""
var list: VBoxContainer
var details: VBoxContainer
var preview: Control
var house_buttons := {}

func _init(campaign_state):
 state = campaign_state
 name = "FactionSelect"
 data = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_intro.json"))
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP

func _ready():
 var bg = ColorRect.new()
 bg.color = Color("120e0b")
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var m = MarginContainer.new()
 m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for s in ["left","right","top","bottom"]: m.add_theme_constant_override("margin_"+s,30)
 add_child(m)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",12)
 m.add_child(v)
 var title = UiKit.header("Choose your house",32)
 title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(title)
 var row = HBoxContainer.new()
 row.size_flags_vertical = Control.SIZE_EXPAND_FILL
 row.add_theme_constant_override("separation",18)
 v.add_child(row)
 # Left: the three houses.
 var lf = Widgets.Framed.new("main",Color("c9a45a"),Color("1d1712",0.95))
 lf.custom_minimum_size.x = 300
 row.add_child(lf)
 list = VBoxContainer.new()
 list.add_theme_constant_override("separation",10)
 lf.add_child(list)
 for h in data.houses:
  var f = WorldMap.faction(h.faction)
  var b = Button.new()
  b.name = "House_"+h.faction
  b.toggle_mode = true
  b.focus_mode = Control.FOCUS_NONE
  b.custom_minimum_size = Vector2(0,96)
  b.pressed.connect(select.bind(h.faction))
  var hb = HBoxContainer.new()
  hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
  hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  hb.offset_left = 10
  hb.add_theme_constant_override("separation",12)
  var em = Widgets.Emblem.new(f,58)
  em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
  hb.add_child(em)
  var tv = VBoxContainer.new()
  tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
  tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
  var n = UiKit.label(f.name,17,Color("f1d79a"),UiKit.FONT_BOLD)
  n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  n.custom_minimum_size.x = 190
  tv.add_child(n)
  tv.add_child(UiKit.label(h.culture,13,UiKit.TEXT_DIM))
  hb.add_child(tv)
  b.add_child(hb)
  house_buttons[h.faction] = b
  list.add_child(b)
 # Centre: the start on the map.
 var cf = Widgets.Framed.new("main",Color("c9a45a"),Color("1d1712",0.95))
 cf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 row.add_child(cf)
 preview = StrategicMap.new()
 preview.name = "StartPreview"
 preview.frame_margin = Rect2(2,2,4,4)
 cf.add_child(preview)
 var meta = MapRegistry.meta()
 preview.setup(UiData.new(state),Rect2(Vector2(meta.origin[0],meta.origin[1]),Vector2(meta.size[0],meta.size[1])))
 for n in ["LayerBar","LegendFrame"]:
  var c = preview.get_node_or_null(n)
  if c: c.visible = false
 preview.open_map(true)
 # Right: the house.
 var df = Widgets.Framed.new("main",Color("c9a45a"),Color("1d1712",0.95))
 df.custom_minimum_size.x = 420
 row.add_child(df)
 details = VBoxContainer.new()
 details.add_theme_constant_override("separation",8)
 df.add_child(details)
 var bottom = HBoxContainer.new()
 bottom.alignment = BoxContainer.ALIGNMENT_END
 bottom.add_theme_constant_override("separation",12)
 v.add_child(bottom)
 var back = Button.new()
 back.name = "SelectBack"
 back.text = "Back"
 back.focus_mode = Control.FOCUS_NONE
 back.custom_minimum_size = Vector2(150,44)
 back.pressed.connect(func(): cancelled.emit())
 bottom.add_child(back)
 var go = Button.new()
 go.name = "SelectBegin"
 go.text = "Begin the campaign"
 go.focus_mode = Control.FOCUS_NONE
 go.custom_minimum_size = Vector2(260,44)
 go.pressed.connect(func(): chosen.emit(selected))
 bottom.add_child(go)
 select(data.houses[0].faction)

func house(id: String) -> Dictionary:
 for h in data.houses:
  if h.faction == id: return h
 return {}

func select(id: String):
 selected = id
 for k in house_buttons: house_buttons[k].set_pressed_no_signal(k == id)
 var h = house(id)
 var f = WorldMap.faction(id)
 for c in details.get_children():
  details.remove_child(c)
  c.queue_free()
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",12)
 head.add_child(Widgets.Emblem.new(f,64))
 var hv = VBoxContainer.new()
 var nm = UiKit.header(f.name,22)
 nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 nm.custom_minimum_size.x = 300
 hv.add_child(nm)
 hv.add_child(UiKit.label(h.culture,14,UiKit.TEXT_DIM))
 head.add_child(hv)
 details.add_child(head)
 details.add_child(UiKit.divider(Color("c9a45a")))
 for part in [["Founder","%s, %s" % [h.founder,h.epithet]],["Traits",", ".join(h.founder_traits)],["House tradition",h.tradition],["Culture",h.culture_summary],["Start",h.start],["The road ahead",h.pressure]]:
  details.add_child(UiKit.label(part[0],15,Color("f1d79a"),UiKit.FONT_BOLD))
  var t = UiKit.label(part[1],14,UiKit.TEXT)
  t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  t.custom_minimum_size.x = 380
  details.add_child(t)
 # Zoom the preview onto the house's seat.
 var seat = str(f.get("seat_region",""))
 if seat != "" and WorldMap.region(seat).get("settlement") is Dictionary:
  preview._layout()
  preview.zoom = 1.0
  preview.center = WorldMap.settlement_position(seat)
  preview.zoom_at(preview.to_screen(WorldMap.settlement_position(seat)),StrategicMap.MAX_ZOOM)
  preview.center = WorldMap.settlement_position(seat)
  preview._layout()
