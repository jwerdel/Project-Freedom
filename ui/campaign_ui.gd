extends Control
# Campaign UI shell modeled on Total War: Warhammer III: round menu buttons (top-left), resource
# bar (top-center), minimap (top-right), event messages (right), province stats (left), province
# or army panel (bottom-center) and the End Turn button (bottom-right).
# Every value shown comes from the UiData interface (core/ui_data.gd); the UI never reads files.

signal end_turn_requested
signal settlement_selected(id: String)
signal overlay_toggled(overlay: String,on: bool)

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const Cards = preload("res://ui/cards.gd")
const Minimap = preload("res://ui/minimap.gd")

const MENU = [["faction","Faction overview"],["diplomacy","Diplomacy"],["tech","Technology"],["lords","Lords and heroes"],["finance","Finance"],["objectives","Objectives"]]
const OVERLAYS = [["borders","Territory borders"],["settlements","Settlement banners"],["armies","Armies"]]

var data
var studio
var colors: Dictionary
var resource_labels = {}
var resource_groups = {}
var chronicle_panel: Control
var chronicle_box: VBoxContainer
var event_box: VBoxContainer
var collapsed = {}
var stats_panel: Control
var stats_box: VBoxContainer
var bottom_panel: Control
var bottom_box: VBoxContainer
var end_turn_button: Button
var end_turn_year: Label
var hover_tip: PanelContainer
var hover_label: Label
var toast_label: Label
var fps_label: Label
var minimap_slot: Control
var minimap
var overlay_buttons = {}
var selected_settlement := ""
var selected_army := ""
var army_location := ""
var province_title := ""
var browser_panel: Control
var browser_box: VBoxContainer
var browser_target := {}

func setup(ui_data,portrait_studio):
 data = ui_data
 studio = portrait_studio
 theme = UiKit.theme_for(data.player_faction())
 colors = UiKit.colors(data.player_faction())
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 _build_menu()
 _build_resources()
 _build_minimap()
 _build_events()
 _build_stats()
 _build_bottom()
 _build_end_turn()
 _build_overlays()
 data.changed.connect(refresh)
 data.event_added.connect(func(_e): _rebuild_events())
 refresh()
 _rebuild_events()

# --- Layout helpers ------------------------------------------------------------

func _anchor(c: Control,left: float,top: float,right: float,bottom: float,offsets: Rect2):
 c.anchor_left = left
 c.anchor_top = top
 c.anchor_right = right
 c.anchor_bottom = bottom
 c.offset_left = offsets.position.x
 c.offset_top = offsets.position.y
 c.offset_right = offsets.size.x
 c.offset_bottom = offsets.size.y
 add_child(c)

func _framed(kind := "main") -> Widgets.Framed:
 return Widgets.Framed.new(kind,colors.trim,Color(colors.panel,0.94))

func _clear(box: Node):
 for c in box.get_children():
  box.remove_child(c)
  c.queue_free()

# --- Top-left menu, top-center resources, top-right minimap ---------------------

func _build_menu():
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",6)
 for m in MENU: row.add_child(Widgets.RoundButton.new(m[0],"%s\n(placeholder: not implemented yet)" % m[1],46,colors.trim))
 var chronicle_button = Widgets.RoundButton.new("chronicle","The Chronicle\nThe Grey Scribes' record of every year",46,colors.trim)
 chronicle_button.pressed.connect(toggle_chronicle)
 row.add_child(chronicle_button)
 _anchor(row,0,0,0,0,Rect2(14,10,0,0))

func _build_resources():
 var bar = _framed()
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",14)
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 bar.add_child(row)
 row.add_child(Widgets.Emblem.new(data.player_faction(),26))
 var name_label = UiKit.header(data.player_faction().name,17)
 name_label.tooltip_text = "%s\n%s" % [data.player_faction().name,data.player_faction().realm]
 name_label.mouse_filter = Control.MOUSE_FILTER_PASS
 row.add_child(name_label)
 for item in [["treasury","coin","Treasury"],["income","income","Income per turn"],["population","population","Population"],["year","year","Year and turn"]]:
  var group = HBoxContainer.new()
  group.add_theme_constant_override("separation",5)
  group.tooltip_text = item[2]
  resource_groups[item[0]] = group
  group.mouse_filter = Control.MOUSE_FILTER_PASS
  group.add_child(Widgets.Icon.new(item[1],Color("e9c46a") if item[1]!="population" else Color("d9cfb6"),22))
  var value = UiKit.label("",17,UiKit.TEXT,UiKit.FONT_BOLD)
  group.add_child(value)
  resource_labels[item[0]] = value
  row.add_child(group)
 _anchor(bar,0.5,0,0.5,0,Rect2(-360,8,360,64))

func _build_minimap():
 var frame = _framed()
 minimap_slot = Control.new()
 minimap_slot.custom_minimum_size = Vector2(206,206)
 minimap_slot.clip_contents = true
 frame.add_child(minimap_slot)
 var placeholder = UiKit.label("Minimap",14,UiKit.TEXT_DIM)
 placeholder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 placeholder.name = "Placeholder"
 minimap_slot.add_child(placeholder)
 _anchor(frame,1,0,1,0,Rect2(-250,10,-14,246))

func _build_overlays():
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",4)
 for o in OVERLAYS:
  var b = Widgets.RoundButton.new(o[0],"Show "+o[1].to_lower(),32,colors.trim)
  b.toggle_mode = true
  b.button_pressed = true
  b.toggled.connect(func(on): overlay_toggled.emit(o[0],on))
  overlay_buttons[o[0]] = b
  row.add_child(b)
 _anchor(row,1,0,1,0,Rect2(-250,250,-14,282))

# --- Event messages (right) ------------------------------------------------------

func _build_events():
 var frame = _framed()
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",4)
 frame.add_child(v)
 v.add_child(UiKit.header("Event Messages",16))
 v.add_child(UiKit.divider(colors.trim))
 var scroll = ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 v.add_child(scroll)
 event_box = VBoxContainer.new()
 event_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 event_box.add_theme_constant_override("separation",3)
 scroll.add_child(event_box)
 _anchor(frame,1,0,1,0,Rect2(-326,290,-14,640))

func _rebuild_events():
 _clear(event_box)
 for cat in data.event_categories():
  var entries = data.events(cat.id)
  var open = not collapsed.get(cat.id,false)
  var head = Button.new()
  head.text = "%s  %s  (%d)" % ["–" if open else "+",cat.name,entries.size()]
  head.alignment = HORIZONTAL_ALIGNMENT_LEFT
  head.focus_mode = Control.FOCUS_NONE
  head.add_theme_font_size_override("font_size",14)
  head.pressed.connect(func():
   collapsed[cat.id] = open
   _rebuild_events())
  event_box.add_child(head)
  if not open: continue
  for e in entries.slice(0,6):
   var row = VBoxContainer.new()
   row.add_theme_constant_override("separation",0)
   var title = UiKit.label(e.title,15,Color("f1d79a"),UiKit.FONT_BOLD)
   title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   row.add_child(title)
   if e.text != "":
    var text = UiKit.label("%s  · Year %d" % [e.text,e.year],13,UiKit.TEXT_DIM)
    text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    row.add_child(text)
   var m = MarginContainer.new()
   m.add_theme_constant_override("margin_left",10)
   m.add_child(row)
   event_box.add_child(m)

# --- Province stats (left) ----------------------------------------------------------

func _build_stats():
 stats_panel = _framed()
 stats_panel.custom_minimum_size = Vector2(300,0)
 stats_box = VBoxContainer.new()
 stats_box.add_theme_constant_override("separation",6)
 stats_panel.add_child(stats_box)
 stats_panel.visible = false
 _anchor(stats_panel,0,0,0,0,Rect2(14,70,314,70))

func _stat_row(icon: String,label: String,value: String,tip: String) -> Control:
 var row = HBoxContainer.new()
 row.tooltip_text = tip
 row.mouse_filter = Control.MOUSE_FILTER_PASS
 row.add_child(Widgets.Icon.new(icon,Color("e9c46a"),20))
 var l = UiKit.label(label,15)
 l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 row.add_child(l)
 row.add_child(UiKit.label(value,16,Color("f1d79a"),UiKit.FONT_BOLD))
 return row

func _show_stats(s: Dictionary):
 _clear(stats_box)
 var p = data.province(s.province)
 var st = data.province_stats(s.province)
 province_title = p.name
 stats_box.add_child(UiKit.header(p.name,20))
 var owner_row = HBoxContainer.new()
 owner_row.add_theme_constant_override("separation",8)
 owner_row.add_child(Widgets.Emblem.new(s.faction,22))
 owner_row.add_child(UiKit.label("%s\n%s" % [s.name,s.faction.name],14,UiKit.TEXT_DIM))
 stats_box.add_child(owner_row)
 stats_box.add_child(UiKit.divider(colors.trim))
 stats_box.add_child(_stat_row("population","Growth","%+d / year" % st.growth,"Population growth per year, from settlement type, resource endowments, buildings and wealth.\nRuler popularity is not designed yet and counts as neutral."))
 stats_box.add_child(_stat_row("coin","Income",UiKit.signed(st.income),"Settlement income per turn (before upkeep): base by type and level plus taxes on population, raised by resource endowments and buildings."))
 stats_box.add_child(_stat_row("population","Population",UiKit.format_int(st.population),"People living in the province's settlements."))
 var order = HBoxContainer.new()
 order.add_child(UiKit.label("Public order",15))
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 order.add_child(spacer)
 order.add_child(UiKit.label("%+d" % st.public_order,16,Color("9fe08a") if st.public_order>=0 else Color("ef8a6a"),UiKit.FONT_BOLD))
 stats_box.add_child(order)
 var bar = Widgets.OrderBar.new(st.public_order/100.0)
 bar.tooltip_text = "Public order, -100 to +100 (placeholder: no public order system yet)"
 bar.mouse_filter = Control.MOUSE_FILTER_PASS
 stats_box.add_child(bar)
 stats_box.add_child(UiKit.label("Public order: placeholder (data/mock_ui.json)",12,Color(UiKit.TEXT_DIM,0.7)))

# --- Bottom panel: province (settlement tabs + building slots) or army ------------------

func _build_bottom():
 bottom_panel = _framed()
 bottom_box = VBoxContainer.new()
 bottom_box.add_theme_constant_override("separation",6)
 bottom_panel.add_child(bottom_box)
 bottom_panel.visible = false
 _anchor(bottom_panel,0.5,1,0.5,1,Rect2(-480,-262,480,-10))

func show_settlement(id: String):
 var s = data.settlement(id)
 if s.is_empty(): return
 selected_settlement = id
 selected_army = ""
 _show_stats(s)
 stats_panel.visible = true
 _clear(bottom_box)
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",10)
 head.add_child(Widgets.Emblem.new(s.faction,24))
 var title = VBoxContainer.new()
 title.add_theme_constant_override("separation",-2)
 title.add_child(UiKit.header(s.province_name,18))
 title.add_child(UiKit.label("%s · %s · level %d · defense %d · %s" % [s.name,s.type.capitalize(),s.level,s.defense,s.faction.name],14,UiKit.TEXT_DIM))
 head.add_child(title)
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(spacer)
 for sid in data.settlements_in_province(s.province):
  var tab = Button.new()
  tab.text = data.settlement(sid).name
  tab.focus_mode = Control.FOCUS_NONE
  tab.custom_minimum_size = Vector2(130,36)
  if sid == id:
   tab.add_theme_stylebox_override("normal",UiKit.textured(UiKit.BUTTON_LONG_SELECTED,10,8))
   tab.add_theme_stylebox_override("hover",UiKit.textured(UiKit.BUTTON_LONG_SELECTED,10,8))
   tab.add_theme_color_override("font_color",UiKit.INK)
   tab.add_theme_color_override("font_hover_color",UiKit.INK)
  tab.pressed.connect(func():
   show_settlement(sid)
   settlement_selected.emit(sid))
  head.add_child(tab)
 bottom_box.add_child(head)
 bottom_box.add_child(UiKit.divider(colors.trim))
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 for slot in data.building_slots(id): row.add_child(Cards.building_card(slot,colors.trim,studio,open_building_browser.bind(id,int(slot.get("slot",-1)))))
 bottom_box.add_child(_scroller(row))
 bottom_panel.visible = true
 _fit_bottom.call_deferred()

# location: province name where the army stands (for tooltips).
func show_army(army_id: String,location: String):
 close_building_browser()
 var a = data.army(army_id)
 selected_army = army_id
 selected_settlement = ""
 army_location = location
 stats_panel.visible = false
 _clear(bottom_box)
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",10)
 head.add_child(Widgets.Emblem.new(a.faction_data,24))
 var title = VBoxContainer.new()
 title.add_theme_constant_override("separation",-2)
 title.add_child(UiKit.header(a.display_name,18))
 title.add_child(UiKit.label("Led by %s · %s · %s" % [a.commander.name,a.faction_data.name,location],14,UiKit.TEXT_DIM))
 head.add_child(title)
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(spacer)
 head.add_child(UiKit.label("Units %d / 20" % (a.units.size()+1),15,UiKit.TEXT_DIM))
 bottom_box.add_child(head)
 bottom_box.add_child(UiKit.divider(colors.trim))
 var row = HBoxContainer.new()
 row.alignment = BoxContainer.ALIGNMENT_BEGIN
 row.add_theme_constant_override("separation",6)
 for entry in [a.commander]+a.units:
  var u = data.unit_type(entry.unit)
  var name = entry.get("name",u.display_name)
  var men = int(round(u.placeholder_stats.entities*float(entry.get("strength",1.0))))
  var tip = "%s\n%s · %s\n%s\nStrength %d%% · %d of %d (placeholder)" % [name,a.faction_data.name,location,u.description,int(float(entry.get("strength",1.0))*100),men,u.placeholder_stats.entities]
  if u.get("single_entity",false): tip = "%s\n%s · %s\n%s" % [name,a.faction_data.name,location,u.display_name]
  row.add_child(Cards.unit_card(u,entry,a.faction_data,studio,tip))
 bottom_box.add_child(_scroller(row))
 bottom_panel.visible = true
 _fit_bottom.call_deferred()

func _scroller(content: Control) -> ScrollContainer:
 var scroll = ScrollContainer.new()
 var h = 0.0
 for c in content.get_children(): h = maxf(h,c.custom_minimum_size.y)
 scroll.custom_minimum_size = Vector2(0,h+12)
 scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.add_child(content)
 return scroll

func clear_selection():
 close_building_browser()
 selected_settlement = ""
 selected_army = ""
 stats_panel.visible = false
 bottom_panel.visible = false

# --- Building browser (TW-style): opens above the province panel from a slot card -------------
# Empty slot: every chain this settlement can build (level 1) with cost, turns, upkeep, effects
# and locked reasons. Built slot: the next level as an upgrade. Under construction: progress and
# a cancel button with the refund it would give now.

func open_building_browser(settlement_id: String,slot: int):
 if slot<0: return
 browser_target = {"settlement":settlement_id,"slot":slot}
 if browser_panel == null:
  browser_panel = _framed()
  browser_box = VBoxContainer.new()
  browser_box.add_theme_constant_override("separation",6)
  browser_panel.add_child(browser_box)
  _anchor(browser_panel,0.5,1,0.5,1,Rect2(-480,-640,480,-272))
 browser_panel.visible = true
 _fill_browser()

func close_building_browser():
 browser_target = {}
 if browser_panel: browser_panel.visible = false

func browser_visible() -> bool:
 return browser_panel != null and browser_panel.visible

func _fill_browser():
 _clear(browser_box)
 var sid = browser_target.settlement
 var slot_view = data.building_slots(sid)[browser_target.slot]
 var s = data.settlement(sid)
 var head = HBoxContainer.new()
 var heading = "Construct in %s" % s.name
 if slot_view.has("construction"): heading = "%s: under construction" % s.name
 elif slot_view.has("chain"): heading = "%s · %s (level %d of %d)" % [s.name,slot_view.name,slot_view.level,slot_view.max_level]
 var title = UiKit.header(heading,18)
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 head.add_child(UiKit.label("Treasury %s gold" % UiKit.format_int(data.resources().treasury),14,UiKit.TEXT_DIM))
 var close = Button.new()
 close.text = "Close"
 close.focus_mode = Control.FOCUS_NONE
 close.pressed.connect(close_building_browser)
 head.add_child(close)
 browser_box.add_child(head)
 browser_box.add_child(UiKit.divider(colors.trim))
 if slot_view.has("construction"):
  var c = slot_view.construction
  browser_box.add_child(UiKit.label("%s (level %d): %d of %d turns left. Paid %s gold." % [c.name,c.level,c.turns_left,c.turns_total,UiKit.format_int(c.cost)],15))
  var cancel = Button.new()
  cancel.name = "Cancel"
  cancel.text = "Cancel construction (refund %s gold)" % UiKit.format_int(c.refund)
  cancel.focus_mode = Control.FOCUS_NONE
  cancel.disabled = not s.player_owned
  cancel.pressed.connect(func():
   var refund = data.cancel_construction(sid)
   close_building_browser()
   toast("Construction cancelled. %s gold refunded." % UiKit.format_int(refund)))
  browser_box.add_child(cancel)
  browser_box.add_child(UiKit.label("Refund rule (placeholder): full refund in the turn construction started, partial afterwards.",12,Color(UiKit.TEXT_DIM,0.7)))
  return
 if slot_view.has("chain"):
  var current = "Current effects: "+(", ".join(slot_view.effects) if not slot_view.effects.is_empty() else "none")
  var l = UiKit.label(current,14,UiKit.TEXT_DIM)
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  browser_box.add_child(l)
 var options = data.building_options(sid,browser_target.slot)
 if options.is_empty():
  browser_box.add_child(UiKit.label("Fully upgraded.",15))
  return
 var grid = GridContainer.new()
 grid.columns = 4
 grid.add_theme_constant_override("h_separation",8)
 grid.add_theme_constant_override("v_separation",8)
 for o in options: grid.add_child(_option_tile(sid,o))
 var scroll = ScrollContainer.new()
 scroll.custom_minimum_size = Vector2(0,270)
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.add_child(grid)
 browser_box.add_child(scroll)

func _option_tile(sid: String,o: Dictionary) -> Control:
 var tile = PanelContainer.new()
 tile.custom_minimum_size = Vector2(222,0)
 tile.add_theme_stylebox_override("panel",UiKit.textured(UiKit.SLOT,10,8,Color(0.55,0.5,0.45) if o.available else Color(0.35,0.32,0.3)))
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",1)
 tile.add_child(v)
 var name_label = UiKit.label(o.name,15,Color("f1d79a") if o.available else UiKit.TEXT_DIM,UiKit.FONT_BOLD)
 name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 v.add_child(name_label)
 v.add_child(UiKit.label("%s · level %d · %s" % [o.chain_name,o.level,o.category],12,UiKit.TEXT_DIM))
 v.add_child(UiKit.label("%s gold · %d turn%s · upkeep %d" % [UiKit.format_int(o.cost),o.turns,"" if o.turns == 1 else "s",o.upkeep],13,UiKit.TEXT))
 for e in o.effects:
  var l = UiKit.label(e,12,Color("9fe08a"))
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  v.add_child(l)
 for r in o.reasons:
  var l = UiKit.label(r,12,Color("ef8a6a"))
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  v.add_child(l)
 var build = Button.new()
 build.name = "Build_"+o.chain
 build.text = "Upgrade" if o.level>1 else "Build"
 build.focus_mode = Control.FOCUS_NONE
 build.disabled = not o.available
 build.pressed.connect(func():
  var r = data.start_construction(sid,browser_target.slot,o.chain)
  if r.ok:
   close_building_browser()
   toast("Construction started: %s (%d turn%s)." % [o.name,o.turns,"" if o.turns == 1 else "s"])
  else: toast(", ".join(r.reasons)))
 v.add_child(build)
 return tile

# --- End turn (bottom-right), hover tooltip, toast, FPS --------------------------------

func _build_end_turn():
 var v = VBoxContainer.new()
 v.alignment = BoxContainer.ALIGNMENT_END
 v.add_theme_constant_override("separation",2)
 end_turn_button = Widgets.RoundButton.new("year","End turn\nAdvances the year: income, upkeep, construction and growth.",112,Color("e2b955"))
 end_turn_button.pressed.connect(func(): end_turn_requested.emit())
 v.add_child(end_turn_button)
 var l = UiKit.header("End Turn",15)
 l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(l)
 end_turn_year = UiKit.label("",14,UiKit.TEXT_DIM)
 end_turn_year.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(end_turn_year)
 _anchor(v,1,1,1,1,Rect2(-140,-178,-14,-10))
 hover_tip = PanelContainer.new()
 hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
 hover_tip.add_theme_stylebox_override("panel",UiKit.textured(UiKit.PARCHMENT,12,10))
 hover_label = UiKit.label("",16,UiKit.INK)
 hover_tip.add_child(hover_label)
 hover_tip.visible = false
 hover_tip.top_level = true
 add_child(hover_tip)
 toast_label = UiKit.header("",16,UiKit.TEXT)
 toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _anchor(toast_label,0.5,0,0.5,0,Rect2(-400,74,400,100))
 fps_label = UiKit.label("",12,Color(UiKit.TEXT_DIM,0.8))
 _anchor(fps_label,0,1,0,1,Rect2(14,-26,400,-8))

func show_hover(text: String,screen_pos: Vector2):
 hover_label.text = text
 hover_tip.reset_size()
 var vp = get_viewport_rect().size
 hover_tip.position = (screen_pos+Vector2(18,18)).clamp(Vector2.ZERO,vp-hover_tip.size)
 hover_tip.visible = true

func hide_hover():
 hover_tip.visible = false

func toast(text: String):
 toast_label.text = text
 toast_label.modulate.a = 1.0
 var t = create_tween()
 t.tween_interval(3.5)
 t.tween_property(toast_label,"modulate:a",0.0,0.8)

func set_fps(text: String):
 fps_label.text = text

func refresh():
 var r = data.resources()
 resource_labels.treasury.text = UiKit.format_int(r.treasury)
 resource_labels.income.text = UiKit.signed(r.income)
 resource_labels.population.text = UiKit.format_int(r.population)
 resource_labels.year.text = "Year %d · Turn %d" % [r.year,r.turn]
 resource_groups.treasury.tooltip_text = _ledger_text()
 resource_groups.income.tooltip_text = _ledger_text()
 resource_groups.population.tooltip_text = "Population of your settlements: %s\nGrows each year with settlement type, resources and wealth." % UiKit.format_int(r.population)
 resource_groups.year.tooltip_text = "Year %d, turn %d. One turn is one year." % [r.year,r.turn]
 if chronicle_panel and chronicle_panel.visible: _fill_chronicle()
 end_turn_year.text = "Year %d" % r.year
 if selected_settlement != "": show_settlement(selected_settlement)
 if browser_visible() and not browser_target.is_empty(): _fill_browser()

# Grow the bottom panel upward to fit its content (building cards are shorter than unit cards).
func _fit_bottom():
 bottom_panel.offset_top = bottom_panel.offset_bottom-bottom_panel.get_combined_minimum_size().y

# Replace the minimap placeholder with the live minimap (see ui/minimap.gd).
func setup_minimap(world: World3D,world_rect: Rect2,camera_footprint: Callable) -> Control:
 var placeholder = minimap_slot.get_node_or_null("Placeholder")
 if placeholder: placeholder.queue_free()
 minimap = Minimap.new()
 minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 minimap_slot.add_child(minimap)
 minimap.setup(data,world,world_rect,camera_footprint)
 minimap.tooltip_text = "Minimap: click or drag to move the camera"
 return minimap

# TW-style income breakdown for the treasury tooltip: sources, expenses, net per turn.
func _ledger_text() -> String:
 var b = data.income_breakdown()
 var lines = ["Treasury: %s gold" % UiKit.format_int(b.treasury),"","Income per turn: %s" % UiKit.signed(b.income_total)]
 for e in b.income: lines.append("    %s  %s" % [e.label,UiKit.signed(e.amount)])
 lines.append("Expenses per turn: %s" % UiKit.signed(-b.expense_total))
 for e in b.expenses: lines.append("    %s  %s" % [e.label,UiKit.signed(-e.amount)])
 lines.append("")
 lines.append("Net per turn: %s" % UiKit.signed(b.net))
 lines.append("(placeholder numbers: data/economy.json)")
 return "\n".join(lines)

# --- Chronicle window -------------------------------------------------------------

func toggle_chronicle():
 if chronicle_panel == null:
  chronicle_panel = _framed()
  var v = VBoxContainer.new()
  v.add_theme_constant_override("separation",6)
  chronicle_panel.add_child(v)
  var head = HBoxContainer.new()
  var title = UiKit.header("The Chronicle of the Grey Scribes",20)
  title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  head.add_child(title)
  var close = Button.new()
  close.text = "Close"
  close.focus_mode = Control.FOCUS_NONE
  close.pressed.connect(func(): chronicle_panel.visible = false)
  head.add_child(close)
  v.add_child(head)
  v.add_child(UiKit.label("Kept in the archive at Crownhaven, without favour to any realm.",14,UiKit.TEXT_DIM))
  v.add_child(UiKit.divider(colors.trim))
  var scroll = ScrollContainer.new()
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  v.add_child(scroll)
  chronicle_box = VBoxContainer.new()
  chronicle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  chronicle_box.add_theme_constant_override("separation",10)
  scroll.add_child(chronicle_box)
  chronicle_panel.visible = false
  _anchor(chronicle_panel,0.5,0.5,0.5,0.5,Rect2(-320,-300,320,300))
 chronicle_panel.visible = not chronicle_panel.visible
 if chronicle_panel.visible: _fill_chronicle()

func _fill_chronicle():
 _clear(chronicle_box)
 for e in data.chronicle():
  var row = VBoxContainer.new()
  row.add_theme_constant_override("separation",1)
  row.add_child(UiKit.label("Year %d" % e.year,13,UiKit.TEXT_DIM))
  var title = UiKit.label(e.title,17,Color("f1d79a"),UiKit.FONT_BOLD)
  title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  row.add_child(title)
  if e.text != "":
   var text = UiKit.label(e.text,15,UiKit.TEXT)
   text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   row.add_child(text)
  chronicle_box.add_child(row)

func chronicle_visible() -> bool:
 return chronicle_panel != null and chronicle_panel.visible
