extends Control
# Campaign UI shell modeled on Total War: Warhammer III: round menu buttons (top-left), resource
# bar (top-center), minimap (top-right), event messages (right), province stats (left), province
# or army panel (bottom-center) and the End Turn button (bottom-right).
# Every value shown comes from the UiData interface (core/ui_data.gd); the UI never reads files.

signal end_turn_requested
signal settlement_selected(id: String)
signal overlay_toggled(overlay: String,on: bool)
signal follow_toggled(on: bool)
signal cancel_order_requested(army_id: String)
signal army_raised(army_id: String)
signal warning_step(dir: int)
signal warning_skip

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const Cards = preload("res://ui/cards.gd")
const Minimap = preload("res://ui/minimap.gd")
const DeploymentScreen = preload("res://ui/deployment_screen.gd")
const BattleReplay = preload("res://ui/battle_replay.gd")
const RichTooltip = preload("res://ui/rich_tooltip.gd")
const Settings = preload("res://core/settings.gd")


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
var hover_title: Label
var toast_label: Label
var fps_label: Label
var minimap_slot: Control
var minimap
var selected_settlement := ""
var selected_army := ""
var army_location := ""
var province_title := ""
var selected_unit := -1 # index of the selected unit card in the army panel
var recruit_box: VBoxContainer # the recruitment drawer while open (inside the army panel)
var recruit_army := ""
var follow_on := false
var follow_button: Button
var movement_bar: Control
var browser_panel: Control
var grace_tag: Label # landless countdown in the resource bar
var debt_tag: Label # "IN DEBT" next to the treasury
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
 add_child(RichTooltip.new()) # TW-style tooltips for every control
 data.changed.connect(refresh)
 data.event_added.connect(func(_e): _rebuild_events())
 data.alert.connect(show_alert)
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

# --- Top bar (TW:WH3, docs/tw-ui-parity.md L1-L4) ---------------------------------------------
# Left: Menu, Advisor, Help, Unit browser, Camera settings. Centre: treasury, income, population,
# faction-resource slots, faction effects. Right: tactical map (minimap) toggle, Events, Lords and
# heroes, Provinces, Missions, Known factions, Faction summary. Buttons for systems that do not
# exist yet stand in their TW place, greyed, with "Coming later".

const COMING = "\nComing later."
signal menu_requested
signal camera_setting_changed(key: String,value)
signal army_chosen(army_id: String)       # from the Lords and heroes list
signal settlement_chosen(settlement_id: String)

var top_buttons := {}
var dropdown: Control
var dropdown_kind := ""
var events_frame: Control
var minimap_frame: Control
var popup_panel: Control
var effects_icon: Control

func _round(icon: String,tip: String,size: float,enabled := true) -> Button:
 var b = Widgets.RoundButton.new(icon,tip+("" if enabled else COMING),size,colors.trim)
 b.disabled = not enabled
 if not enabled: b.modulate = Color(0.55,0.55,0.55)
 return b

func _build_menu():
 var row = HBoxContainer.new()
 row.name = "TopLeft"
 row.add_theme_constant_override("separation",6)
 var items = [["menu","faction","Menu (Esc)\nSave, load, settings, quit",true],["advisor","objectives","Advisor",false],
  ["help","finance","Help pages\nThe encyclopedia",false],["units","lords","Unit and spell browser",false],
  ["camera","year","Camera settings\nFollowing AI armies, AI turn speed, your armies' speed, map labels",true]]
 for it in items:
  var b = _round(it[1],it[2],44,it[3])
  b.name = "Top_"+it[0]
  top_buttons[it[0]] = b
  row.add_child(b)
 top_buttons.menu.pressed.connect(func(): menu_requested.emit())
 top_buttons.camera.pressed.connect(func(): open_camera_settings())
 _anchor(row,0,0,0,0,Rect2(14,10,0,0))

func _build_resources():
 var bar = _framed()
 bar.name = "TopCentre"
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",14)
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 bar.add_child(row)
 row.add_child(Widgets.Emblem.new(data.player_faction(),26))
 var name_label = UiKit.header(data.player_faction().name,17)
 name_label.tooltip_text = "%s\n%s" % [data.player_faction().name,data.player_faction().realm]
 name_label.mouse_filter = Control.MOUSE_FILTER_PASS
 row.add_child(name_label)
 for item in [["treasury","coin","Treasury"],["income","income","Income per turn"],["population","population","Population"]]:
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
 # In debt: a red tag (the treasury tooltip explains desertion and the limit).
 debt_tag = UiKit.label(" IN DEBT ",14,Color("ffe3c8"),UiKit.FONT_BOLD)
 debt_tag.name = "DebtTag"
 debt_tag.add_theme_stylebox_override("normal",UiKit.flat(Color("7a1c1c",0.95),6))
 debt_tag.mouse_filter = Control.MOUSE_FILTER_PASS
 debt_tag.visible = false
 resource_groups.treasury.add_child(debt_tag)
 # Faction-specific resources (TW: they differ by race): slots stand ready, greyed.
 for i in 2:
  var slot = Widgets.Icon.new("objectives",Color(0.45,0.42,0.38),20)
  slot.name = "FactionResource%d" % i
  slot.tooltip_text = "Faction resource"+COMING
  slot.mouse_filter = Control.MOUSE_FILTER_STOP
  row.add_child(slot)
 # Landless (grace period): a red countdown tag, hidden otherwise.
 grace_tag = UiKit.label("",15,Color("ffe3c8"),UiKit.FONT_BOLD)
 grace_tag.name = "GraceTag"
 grace_tag.add_theme_stylebox_override("normal",UiKit.flat(Color("7a1c1c",0.95),6))
 grace_tag.mouse_filter = Control.MOUSE_FILTER_PASS
 grace_tag.visible = false
 row.add_child(grace_tag)
 # Faction effects (TW: at the right end of the centre bar).
 effects_icon = Widgets.Icon.new("chronicle",Color("e9c46a"),22)
 effects_icon.name = "FactionEffects"
 effects_icon.mouse_filter = Control.MOUSE_FILTER_STOP
 row.add_child(effects_icon)
 _anchor(bar,0.5,0,0.5,0,Rect2(-400,8,400,64))

# Everything affecting your faction now, for the effects icon's tooltip.
func _effects_text() -> String:
 var r = data.resources()
 var lines = ["Faction effects"]
 if r.in_debt: lines.append("In debt: no construction, recruitment or new armies; units lose %d%% of their men each turn." % r.desertion_pct)
 if int(r.grace)>=0: lines.append("Landless: %d turn%s to retake a settlement." % [r.grace,"" if r.grace == 1 else "s"])
 var wars = data.state.factions().filter(func(f): return f != data.player_faction_id() and data.at_war(f))
 if not wars.is_empty(): lines.append("At war with %s." % ", ".join(wars.map(func(f): return data.faction(f).name)))
 if lines.size() == 1: lines.append("Nothing affects your faction right now.")
 return "\n".join(lines)

func _build_minimap():
 # Right side of the top bar: map toggle, lists and the faction summary (left to right).
 var row = HBoxContainer.new()
 row.name = "TopRight"
 row.add_theme_constant_override("separation",5)
 var items = [["tactical","borders","Tactical map\nShow or hide the small map (Tab opens the strategic map)",true],
  ["events","chronicle","Events\nShow or hide the event messages",true],
  ["lords","lords","Lords and heroes\nYour armies and their generals",true],
  ["provinces","settlements","Provinces\nYour provinces: income, growth and public order",true],
  ["missions","objectives","Missions",false],
  ["factions","diplomacy","Known factions\nWar and peace with you",true]]
 for it in items:
  var b = _round(it[1],it[2],36,it[3])
  b.name = "Top_"+it[0]
  top_buttons[it[0]] = b
  row.add_child(b)
 var summary = _round("faction","Faction summary\nSummary, records (the Grey Scribes' chronicle) and statistics",44)
 summary.name = "Top_summary"
 top_buttons.summary = summary
 row.add_child(summary)
 top_buttons.tactical.pressed.connect(func(): minimap_frame.visible = not minimap_frame.visible)
 top_buttons.events.pressed.connect(func(): events_frame.visible = not events_frame.visible)
 for k in ["lords","provinces","factions"]: top_buttons[k].pressed.connect(toggle_dropdown.bind(k))
 summary.pressed.connect(open_faction_summary)
 _anchor(row,1,0,1,0,Rect2(-300,10,-14,56))
 row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
 # The small map under the bar (TW's tactical map toggle).
 minimap_frame = _framed()
 minimap_frame.name = "Minimap"
 minimap_slot = Control.new()
 minimap_slot.custom_minimum_size = Vector2(206,206)
 minimap_slot.clip_contents = true
 minimap_frame.add_child(minimap_slot)
 var placeholder = UiKit.label("Minimap",14,UiKit.TEXT_DIM)
 placeholder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 placeholder.name = "Placeholder"
 minimap_slot.add_child(placeholder)
 _anchor(minimap_frame,1,0,1,0,Rect2(-250,62,-14,298))

func _build_overlays():
 pass # display toggles live in the camera settings (TW: Ctrl+T toggles labels)

# --- Event messages (right, under the small map; toggled by Events) ---------------------------

func _build_events():
 events_frame = _framed()
 events_frame.name = "EventFeed"
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",4)
 events_frame.add_child(v)
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
 # Ends above the round End Turn menu and its warning; the bottom panel ends left of it.
 _anchor(events_frame,1,0,1,1,Rect2(-326,304,-14,EVENTS_BOTTOM))

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

# --- Bottom panel (TW:WH3, docs/tw-ui-parity.md L6-L7): three parts ---------------------------
# Province: left = growth, income, public order; middle = settlement tabs with building slots or the
# garrison; right = resources, climate (terrain) and effects. Army: left = lord card, equipment and
# traits (greyed), movement; middle = recruit buttons, the recruitment drawer, unit cards; right =
# upkeep, replenishment, stance (greyed). The panel ends left of the round End Turn menu and the
# event feed, so the drawer never covers them.

const BOTTOM_WIDTH = 1256.0 # left edge to the round menu (1600-wide viewport)
const BOTTOM_LEFT_W = 210.0
const BOTTOM_RIGHT_W = 190.0
const CARD_GAP = 4
const ARMY_PANEL_WIDTH = BOTTOM_WIDTH-BOTTOM_LEFT_W-BOTTOM_RIGHT_W-60.0 # the middle column
const SETTLEMENT_TABS = [["buildings","Buildings","Building slots (1 overview, 3 building browser)"],["garrison","Garrison","Who defends the settlement (2)"]]

var lord_box: VBoxContainer   # army: left column
var info_box: VBoxContainer   # right column (province or army)
var settlement_tab := "buildings"

func _column(w: float) -> VBoxContainer:
 var v = VBoxContainer.new()
 v.custom_minimum_size = Vector2(w,0)
 v.add_theme_constant_override("separation",5)
 return v

func _rule() -> Control:
 var r = ColorRect.new()
 r.color = Color(colors.trim,0.45)
 r.custom_minimum_size = Vector2(1,0)
 r.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return r

func _build_stats():
 pass # the province stats are the bottom panel's left column (see _build_bottom)

func _build_bottom():
 bottom_panel = _framed()
 bottom_panel.name = "BottomPanel"
 var h = HBoxContainer.new()
 h.add_theme_constant_override("separation",12)
 bottom_panel.add_child(h)
 stats_panel = _column(BOTTOM_LEFT_W)
 stats_panel.name = "ProvinceLeft"
 stats_box = stats_panel
 h.add_child(stats_panel)
 lord_box = _column(BOTTOM_LEFT_W)
 lord_box.name = "ArmyLeft"
 h.add_child(lord_box)
 h.add_child(_rule())
 bottom_box = VBoxContainer.new()
 bottom_box.name = "Middle"
 bottom_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 bottom_box.custom_minimum_size = Vector2(ARMY_PANEL_WIDTH,0)
 bottom_box.add_theme_constant_override("separation",6)
 h.add_child(bottom_box)
 h.add_child(_rule())
 info_box = _column(BOTTOM_RIGHT_W)
 info_box.name = "Right"
 h.add_child(info_box)
 bottom_panel.visible = false
 _anchor(bottom_panel,0,1,0,1,Rect2(14,-262,14+BOTTOM_WIDTH,-10))

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

func _small(text: String,color := UiKit.TEXT_DIM,size := 13) -> Label:
 var l = UiKit.label(text,size,color)
 l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 return l

func _show_stats(s: Dictionary):
 _clear(stats_box)
 var p = data.province(s.province)
 var st = data.province_stats(s.province)
 province_title = p.name
 stats_box.add_child(UiKit.header(p.name,18))
 var owner_row = HBoxContainer.new()
 owner_row.add_theme_constant_override("separation",8)
 owner_row.add_child(Widgets.Emblem.new(s.faction,22))
 owner_row.add_child(UiKit.label(s.faction.name,14,UiKit.TEXT_DIM))
 stats_box.add_child(owner_row)
 stats_box.add_child(_stat_row("coin","Income",UiKit.signed(st.income),"Province income per turn (before upkeep): base by type and level plus taxes on population, raised by resource endowments and buildings."))
 stats_box.add_child(_stat_row("population","Growth","%+d / year" % st.growth,"Population growth per year, from settlement type, resource endowments, buildings and wealth.\nRuler popularity is not designed yet and counts as neutral."))
 stats_box.add_child(_stat_row("population","Population",UiKit.format_int(st.population),"People living in the province's settlements."))
 var order = HBoxContainer.new()
 order.add_child(UiKit.label("Public order",15))
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 order.add_child(spacer)
 order.add_child(UiKit.label("%+d" % st.public_order,16,Color("9fe08a") if st.public_order>=0 else Color("ef8a6a"),UiKit.FONT_BOLD))
 stats_box.add_child(order)
 var bar = Widgets.OrderBar.new(st.public_order/100.0)
 bar.tooltip_text = "Public order, -100 to +100 (placeholder: no public order system yet, data/mock_ui.json)"
 bar.mouse_filter = Control.MOUSE_FILTER_PASS
 stats_box.add_child(bar)

# Right column of the province panel.
func _show_region_info(id: String):
 _clear(info_box)
 var d = data.region_details(id)
 info_box.add_child(UiKit.header("Resources",15))
 var res = HBoxContainer.new()
 res.add_theme_constant_override("separation",8)
 for k in ["food","wood","stone","minerals"]:
  var n = int(d.resources.get(k,0))
  var l = UiKit.label("%s %d" % [k.capitalize().left(4),n],13,UiKit.TEXT if n>0 else Color(UiKit.TEXT_DIM,0.6))
  l.tooltip_text = "%s endowment %d (raises income and growth; data/provinces.json)" % [k.capitalize(),n]
  l.mouse_filter = Control.MOUSE_FILTER_PASS
  res.add_child(l)
 info_box.add_child(res)
 info_box.add_child(UiKit.header("Climate",15))
 var terr = d.terrain.slice(0,3).map(func(t): return "%s %d%%" % [String(t[0]).capitalize(),int(round(t[1]*100))])
 var tl = _small(", ".join(terr) if not terr.is_empty() else "Unknown")
 tl.tooltip_text = "The region's terrain (from the movement grid). Climates are not designed yet; terrain stands in."
 tl.mouse_filter = Control.MOUSE_FILTER_PASS
 info_box.add_child(tl)
 info_box.add_child(UiKit.header("Effects",15))
 if d.effects.is_empty(): info_box.add_child(_small("No building effects."))
 for i in mini(d.effects.size(),4): info_box.add_child(_small(d.effects[i],UiKit.TEXT,12))
 if d.effects.size()>4:
  var more = _small("+%d more" % (d.effects.size()-4))
  more.tooltip_text = "\n".join(d.effects)
  more.mouse_filter = Control.MOUSE_FILTER_PASS
  info_box.add_child(more)

func _tab_button(text: String,on: bool) -> Button:
 var tab = Button.new()
 tab.text = text
 tab.focus_mode = Control.FOCUS_NONE
 tab.custom_minimum_size = Vector2(110,32)
 if on:
  tab.add_theme_stylebox_override("normal",UiKit.textured(UiKit.BUTTON_LONG_SELECTED,10,8))
  tab.add_theme_stylebox_override("hover",UiKit.textured(UiKit.BUTTON_LONG_SELECTED,10,8))
  tab.add_theme_color_override("font_color",UiKit.INK)
  tab.add_theme_color_override("font_hover_color",UiKit.INK)
 return tab

# Keys 1 and 2 (TW:WH3): the settlement's overview (building slots) or its garrison.
func set_settlement_tab(tab: String):
 settlement_tab = tab
 if selected_settlement != "": show_settlement(selected_settlement)

func show_settlement(id: String):
 close_recruitment()
 var s = data.settlement(id)
 if s.is_empty(): return
 selected_settlement = id
 selected_army = ""
 _show_stats(s)
 stats_panel.visible = true
 lord_box.visible = false
 _show_region_info(id)
 _clear(bottom_box)
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",8)
 # Settlement tabs of the province (TW: one header per settlement).
 for sid in data.settlements_in_province(s.province):
  var tab = _tab_button(data.settlement(sid).name,sid == id)
  tab.pressed.connect(func():
   show_settlement(sid)
   settlement_selected.emit(sid))
  head.add_child(tab)
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(spacer)
 for t in SETTLEMENT_TABS:
  var b = _tab_button(t[1],settlement_tab == t[0])
  b.name = "Tab_"+t[0]
  b.tooltip_text = t[2]
  b.pressed.connect(set_settlement_tab.bind(t[0]))
  head.add_child(b)
 bottom_box.add_child(head)
 var sub = HBoxContainer.new()
 sub.add_theme_constant_override("separation",10)
 var info = UiKit.label("%s · %s · level %d · defense %d" % [s.name,s.type.capitalize(),s.level,s.defense],14,UiKit.TEXT_DIM)
 info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 sub.add_child(info)
 if s.player_owned:
  var check = data.raise_army_check(id)
  var hire = Button.new()
  hire.name = "HireGeneral"
  hire.text = "Hire general (%s gold)" % UiKit.format_int(check.cost)
  hire.focus_mode = Control.FOCUS_NONE
  hire.disabled = not check.ok
  hire.tooltip_text = "Raise a new army here, led by a newly hired general (placeholder: name generated, no family system yet; at most %d armies)." % check.max_armies if check.ok else ", ".join(check.reasons)
  hire.pressed.connect(func():
   var r = data.raise_army(id)
   if r.ok:
    toast("%s takes command of a new army at %s." % [r.name,s.name])
    army_raised.emit(r.army)
   else: toast(", ".join(r.reasons)))
  sub.add_child(hire)
 bottom_box.add_child(sub)
 bottom_box.add_child(UiKit.divider(colors.trim))
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 if settlement_tab == "garrison":
  row.name = "GarrisonCards"
  var g = data.garrison(id)
  for u in g.units:
   var t = data.unit_type(u.unit)
   row.add_child(Cards.unit_card(t,u,s.faction,studio,"%s\nGarrison of %s\nRaised from the settlement's level and walls when it is attacked (placeholder: data/battle.json)." % [t.display_name,s.name]))
  if g.units.is_empty(): row.add_child(_small("No garrison."))
  if not g.armies.is_empty():
   var armies = _small("Armies inside: %s" % ", ".join(g.armies),Color("f1d79a"),14)
   armies.custom_minimum_size = Vector2(160,0)
   row.add_child(armies)
 else:
  row.name = "BuildingCards"
  for slot in data.building_slots(id): row.add_child(Cards.building_card(slot,colors.trim,studio,open_building_browser.bind(id,int(slot.get("slot",-1)))))
 bottom_box.add_child(_scroller(row))
 bottom_panel.visible = true
 _fit_bottom.call_deferred()

# Left column of the army panel: the lord's card, greyed equipment, trait and stance slots,
# movement.
func _show_lord(army_id: String,a: Dictionary,location: String):
 _clear(lord_box)
 var top = HBoxContainer.new()
 top.add_theme_constant_override("separation",8)
 var lord_card = Cards.unit_card(data.unit_type("commander"),a.commander,a.faction_data,studio,"%s\n%s · %s\nGeneral of %s" % [a.commander.name,a.faction_data.name,location,a.display_name])
 lord_card.name = "LordCard"
 top.add_child(lord_card)
 var side = VBoxContainer.new()
 side.add_theme_constant_override("separation",4)
 var lord_name = _small(a.commander.name,Color("f1d79a"),15)
 lord_name.custom_minimum_size = Vector2(110,0)
 side.add_child(lord_name)
 side.add_child(_small("Rank %d" % a.commander.rank))
 for slot in [["finance","Equipment"],["objectives","Traits"],["armies","Stances"]]:
  var r = HBoxContainer.new()
  r.add_theme_constant_override("separation",4)
  r.tooltip_text = slot[1]+COMING
  r.mouse_filter = Control.MOUSE_FILTER_STOP
  for i in (2 if slot[0] == "armies" else 3): r.add_child(Widgets.Icon.new(slot[0],Color(0.45,0.42,0.38),18))
  r.name = "Lord"+slot[1]
  side.add_child(r)
 top.add_child(side)
 lord_box.add_child(top)
 lord_box.add_child(_movement_box(army_id))

# Right column of the army panel.
func _show_army_info(army_id: String,a: Dictionary):
 _clear(info_box)
 var d = data.army_info(army_id)
 info_box.add_child(UiKit.header("Army",15))
 info_box.add_child(_stat_row("coin","Upkeep","%d" % d.upkeep,"Gold paid each turn for this army: the general and every unit (placeholder: data/units, data/economy.json)."))
 var men = 0
 for u in a.units: men += int(u.men)
 info_box.add_child(_stat_row("population","Men",UiKit.format_int(men),"Soldiers in the army's units."))
 var rep = _stat_row("income","Replenish","%d%%" % d.replenish_pct,"Share of each unit's missing men regained per turn.\nFull rate in your own territory, low (and paid in gold) elsewhere (data/recruitment.json).")
 info_box.add_child(rep)
 info_box.add_child(_small({"own":"In your territory","foreign":"In %s territory" % d.region_owner,"unclaimed":"In unclaimed land"}[d.territory]))
 var stance = HBoxContainer.new()
 stance.name = "Stance"
 stance.add_theme_constant_override("separation",6)
 stance.tooltip_text = "Stances (march, ambush, raid, encamp)"+COMING
 stance.mouse_filter = Control.MOUSE_FILTER_STOP
 stance.add_child(UiKit.label("Stance",14,Color(UiKit.TEXT_DIM,0.6)))
 for i in 3: stance.add_child(Widgets.Icon.new("armies",Color(0.45,0.42,0.38),18))
 info_box.add_child(stance)

# location: province name where the army stands (for tooltips).
func show_army(army_id: String,location: String):
 close_building_browser()
 var a = data.army(army_id)
 selected_army = army_id
 selected_settlement = ""
 army_location = location
 stats_panel.visible = false
 lord_box.visible = true
 _show_lord(army_id,a,location)
 _show_army_info(army_id,a)
 _clear(bottom_box)
 if selected_unit>=a.units.size(): selected_unit = -1
 # TW:WH3 recruitment drawer: opens above the army's cards (inside the middle column).
 if a.player_owned and recruit_army == army_id: bottom_box.add_child(_recruitment_drawer(army_id))
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",10)
 head.add_child(Widgets.Emblem.new(a.faction_data,24))
 var title = VBoxContainer.new()
 title.add_theme_constant_override("separation",-2)
 title.add_child(UiKit.header(a.display_name,17))
 title.add_child(UiKit.label("%s · %s" % [a.faction_data.name,location],13,UiKit.TEXT_DIM))
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 # Recruit buttons above the cards (TW:WH3), with the reason when recruiting is impossible.
 if a.player_owned:
  var actions = HBoxContainer.new()
  actions.name = "ArmyActions"
  actions.add_theme_constant_override("separation",8)
  var where = data.recruitment(army_id)
  if not where.ok:
   var why = UiKit.label("Cannot recruit: %s" % where.reason,13,Color("ef8a6a"))
   why.name = "RecruitReason"
   why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
   why.custom_minimum_size = Vector2(160,0)
   why.tooltip_text = why.text
   why.mouse_filter = Control.MOUSE_FILTER_PASS
   actions.add_child(why)
  var recruit = Button.new()
  recruit.name = "Recruit"
  recruit.text = "Hide recruitment" if recruit_army == army_id else "Recruit units"
  recruit.focus_mode = Control.FOCUS_NONE
  recruit.disabled = not where.ok
  recruit.tooltip_text = ("Recruit units from your buildings in %s (4)" % where.province_name) if where.ok else "Cannot recruit: %s." % where.reason
  recruit.pressed.connect(func():
   if recruit_army == army_id: close_recruitment()
   else: open_recruitment(army_id))
  actions.add_child(recruit)
  var disband = Button.new()
  disband.name = "Disband"
  disband.text = "Disband"
  disband.focus_mode = Control.FOCUS_NONE
  disband.disabled = selected_unit<0
  disband.tooltip_text = "Disband the selected unit (Ctrl+P); its men return to the population of this region." if selected_unit>=0 else "Click a unit card to select it."
  disband.pressed.connect(disband_selected)
  actions.add_child(disband)
  head.add_child(actions)
 var count = UiKit.label("Units %d / %d" % [1+a.units.size()+a.queue.size(),a.max_units],14,UiKit.TEXT_DIM)
 count.name = "UnitCount"
 count.tooltip_text = "General, units and queued recruits. The %d-unit cap is a placeholder (data/recruitment.json)." % a.max_units
 count.mouse_filter = Control.MOUSE_FILTER_PASS
 head.add_child(count)
 bottom_box.add_child(head)
 bottom_box.add_child(UiKit.divider(colors.trim))
 var row = HBoxContainer.new()
 row.name = "ArmyCards"
 row.alignment = BoxContainer.ALIGNMENT_BEGIN
 row.add_theme_constant_override("separation",CARD_GAP)
 # Cards narrow so a full army (general, units and queued recruits) always fits the column. The
 # general's card is in the left column; it still counts against the cap.
 var card_scale = _card_scale(a.units.size()+a.queue.size())
 for i in a.units.size():
  var entry = a.units[i]
  var u = data.unit_type(entry.unit)
  var tip = "%s\n%s · %s\n%s\nStrength %d of %d men (%d%%)\nUpkeep %d per turn%s" % [u.display_name,a.faction_data.name,location,u.description,entry.men,entry.max_men,int(round(100.0*entry.men/maxf(1,entry.max_men))),
   data.unit_upkeep(entry.unit),"\nClick to select (Disband)" if a.player_owned else ""]
  var card = Cards.unit_card(u,entry,a.faction_data,studio,tip,(func():
   selected_unit = -1 if selected_unit == i else i
   show_army(army_id,army_location)) if a.player_owned else Callable())
  card.selected = i == selected_unit
  card.set_card_scale(card_scale)
  row.add_child(card)
 # Queued recruits: greyed cards with the turns left, right after the units; click to cancel.
 for i in a.queue.size():
  var q = a.queue[i]
  var u = data.unit_type(q.unit)
  var entry = {"unit":q.unit,"men":q.men,"max_men":q.men,"queued_turns":q.turns_left}
  var tip = "%s (recruiting)\n%d turn%s left · from %s\nClick to cancel (full refund: %d gold, %d men)" % [u.display_name,q.turns_left,"" if q.turns_left == 1 else "s",data.settlement(q.settlement).name,q.cost,q.men]
  var qc = Cards.unit_card(u,entry,a.faction_data,studio,tip,(func():
   var r = data.cancel_recruit(army_id,i)
   toast("Recruitment cancelled: %d gold and %d men returned." % [r.gold,r.men])) if a.player_owned else Callable())
  qc.name = "Queued_%d" % i
  qc.set_card_scale(card_scale)
  row.add_child(qc)
 bottom_box.add_child(_scroller(row))
 bottom_panel.visible = true
 _fit_bottom.call_deferred()

# Card scale so `count` unit cards fit the middle column; at most 1.
func _card_scale(count: int) -> float:
 # Only the cards shrink; the gaps between them stay.
 count = maxi(count,1)
 var avail = ARMY_PANEL_WIDTH-40.0-(count-1)*CARD_GAP
 return clampf(avail/(count*Cards.UNIT_CARD.x),0.4,1.0)

# Disband the selected unit of the selected army (button or Ctrl+P).
func disband_selected():
 if selected_army == "" or selected_unit<0: return
 var army_id = selected_army
 var r = data.disband_unit(army_id,selected_unit)
 selected_unit = -1
 show_army(army_id,army_location)
 toast("Unit disbanded: %d men return to %s." % [r.men,data.settlement(r.settlement).name] if r.settlement != "" else "Unit disbanded: %d men scatter (no settlement in this region)." % r.men)

# TW-style movement readout for the army panel: remaining movement as a bar, the standing order
# (with cancel) or the garrison, and the camera-follow toggle.
class MovementBar extends Control:
 var fraction := 1.0
 var spend := 0.0      # share of the full allowance a previewed move would spend this turn
 var overflow := false # the previewed move needs more than this turn
 func _init(f: float):
  fraction = clampf(f,0,1)
  custom_minimum_size = Vector2(150,12)
  mouse_filter = Control.MOUSE_FILTER_PASS
 func _draw():
  var r = Rect2(Vector2(0,1),size-Vector2(0,2))
  draw_rect(r,Color(0,0,0,0.7))
  draw_rect(Rect2(r.position+Vector2(2,2),Vector2((r.size.x-4)*fraction,r.size.y-4)),Color("e9c46a") if fraction>0.15 else Color("d77a4a"))
  # TW:WH3: the part a held right-click preview would spend shows green (red when it reaches past
  # this turn).
  if spend>0.0:
   var w = (r.size.x-4)*minf(spend,fraction)
   draw_rect(Rect2(r.position+Vector2(2+(r.size.x-4)*fraction-w,2),Vector2(w,r.size.y-4)),Color("d74a3a") if overflow else Color("5fd34a"))
  draw_rect(r,Color("c9a45a"),false,1.0)

func _movement_box(army_id: String) -> Control:
 var m = data.army_movement(army_id)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",2)
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",6)
 row.add_child(UiKit.label("Movement",13,UiKit.TEXT_DIM))
 movement_bar = MovementBar.new(m.points/maxf(1.0,m.max_points))
 movement_bar.custom_minimum_size.x = 130
 movement_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 movement_bar.name = "MovementBar"
 movement_bar.tooltip_text = "Movement left this turn\nRefilled on End Turn. Forest, hills and passes cost more, roads less.\nHold right click on the map to preview a move: the part it would spend shows green, red if it takes more than this turn."
 row.add_child(movement_bar)
 v.add_child(row)
 var row2 = HBoxContainer.new()
 row2.add_theme_constant_override("separation",6)
 var gs = data.general_status(army_id)
 if gs.status != "ok":
  # A captain leads: the army cannot move until a general is appointed (or the wounded one returns).
  var why = "General wounded (%d turns)" % int(gs.wounded_turns) if gs.status == "wounded" else "General fallen"
  v.add_child(_small("%s: a captain cannot move the army" % why,Color("ef8a6a"),12))
  var appoint = Button.new()
  appoint.name = "AppointGeneral"
  appoint.text = "Appoint general"
  appoint.focus_mode = Control.FOCUS_NONE
  appoint.disabled = not m.player_owned
  appoint.pressed.connect(func():
   var r = data.appoint_general(army_id)
   toast("%s takes command." % r.name if r.ok else ", ".join(r.reasons)))
  row2.add_child(appoint)
 elif not m.order.is_empty():
  v.add_child(_small("Marching (order continues on End Turn)",Color("f1d79a"),12))
  var cancel = Button.new()
  cancel.name = "CancelOrder"
  cancel.text = "Cancel order"
  cancel.focus_mode = Control.FOCUS_NONE
  cancel.disabled = not m.player_owned
  cancel.pressed.connect(func(): cancel_order_requested.emit(army_id))
  row2.add_child(cancel)
 elif m.garrison != "": v.add_child(_small("Garrisoned in %s" % m.garrison_name,Color("f1d79a"),12))
 else: v.add_child(_small("Right click the map to move",UiKit.TEXT_DIM,12))
 follow_button = Button.new()
 follow_button.name = "Follow"
 follow_button.text = "Follow"
 follow_button.toggle_mode = true
 follow_button.button_pressed = follow_on
 follow_button.focus_mode = Control.FOCUS_NONE
 follow_button.tooltip_text = "Camera follows the army (F)"
 follow_button.toggled.connect(func(on):
  follow_on = on
  follow_toggled.emit(on))
 row2.add_child(follow_button)
 v.add_child(row2)
 return v

func set_follow(on: bool):
 follow_on = on
 if follow_button and is_instance_valid(follow_button): follow_button.set_pressed_no_signal(on)

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
 recruit_army = ""
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

# --- Recruitment panel (TW-style): opens above the army panel --------------------------------
# Recruitable unit cards with cost, turns, upkeep and the men drawn from the settlement; locked
# units show why. Recruiting queues the unit on the army (see the army panel).

func open_recruitment(army_id: String):
 close_building_browser()
 recruit_army = army_id
 if selected_army == army_id: show_army(army_id,army_location)

func close_recruitment():
 var was = recruit_army
 recruit_army = ""
 if was != "" and selected_army == was: show_army(was,army_location)

func recruitment_visible() -> bool:
 return recruit_army != "" and selected_army == recruit_army and bottom_panel.visible

func _fill_recruitment():
 if recruitment_visible(): show_army(recruit_army,army_location)

# The drawer (TW:WH3 local recruitment): one card per unit your buildings in this province offer,
# turns above the card, cost and upkeep below; click a card to queue it. Unavailable units are
# greyed with the reason in their tooltip.
func _recruitment_drawer(army_id: String) -> Control:
 var r = data.recruitment(army_id)
 var a = data.army(army_id)
 var box = VBoxContainer.new()
 box.name = "RecruitDrawer"
 box.add_theme_constant_override("separation",4)
 recruit_box = box
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",10)
 var title = UiKit.header("Recruit in %s" % r.province_name if r.ok else "Recruitment unavailable",16)
 head.add_child(title)
 if r.ok:
  var towns = ", ".join(r.settlements.map(func(t): return "%s %s" % [t.name,UiKit.format_int(t.population)]))
  head.add_child(UiKit.label("Population: %s (each keeps at least %s)" % [towns,UiKit.format_int(r.min_population)],13,UiKit.TEXT_DIM))
 box.add_child(head)
 if not r.ok:
  box.add_child(UiKit.label("Cannot recruit here: %s." % r.reason,14,Color("ef8a6a")))
  box.add_child(UiKit.divider(colors.trim))
  return box
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 for o in r.options:
  var u = data.unit_type(o.unit)
  var col = VBoxContainer.new()
  col.add_theme_constant_override("separation",1)
  var turns = UiKit.label("%d turn%s" % [o.turns,"" if o.turns == 1 else "s"],12,Color("f1d79a") if o.available else UiKit.TEXT_DIM,UiKit.FONT_BOLD)
  turns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  col.add_child(turns)
  var tip = "%s\n%s\nCost %s gold · Upkeep %d per turn · %d men from the population\n%s" % [u.display_name,u.description,UiKit.format_int(o.cost),o.upkeep,o.men,
   "Click to recruit (%d turn%s)." % [o.turns,"" if o.turns == 1 else "s"] if o.available else "Unavailable: %s." % ", ".join(o.reasons)]
  var card = Cards.unit_card(u,{"unit":o.unit,"men":o.men,"max_men":o.men},a.faction_data,studio,tip,(func():
   var res = data.recruit(army_id,o.unit)
   if not res.ok: toast(", ".join(res.reasons))) if o.available else Callable())
  card.name = "Recruit_"+o.unit
  card.set_card_scale(0.8)
  if not o.available: card.modulate = Color(0.45,0.45,0.45)
  col.add_child(card)
  var cost = UiKit.label(UiKit.format_int(o.cost),12,UiKit.TEXT if o.available else UiKit.TEXT_DIM)
  cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  col.add_child(cost)
  row.add_child(col)
 box.add_child(row)
 box.add_child(UiKit.divider(colors.trim))
 return box

# --- Battles: war confirmation, pre-battle panel, report window -------------------------------
# Opened by the map when an order targets an enemy army or settlement (core/battles.gd via UiData).

# Balance of power (decision 13): attacker share on the left in its colors, defender on the right.
class BalanceBar extends Control:
 var share := 0.5
 var left := Color.RED
 var right := Color.BLUE
 func _init(s: float,l: Color,r: Color):
  share = clampf(s,0,1)
  left = l
  right = r
  custom_minimum_size = Vector2(420,18)
 func _draw():
  var w = size.x*share
  draw_rect(Rect2(0,0,w,size.y),left)
  draw_rect(Rect2(w,0,size.x-w,size.y),right)
  draw_rect(Rect2(Vector2.ZERO,size),Color("c9a45a"),false,1.5)
  draw_line(Vector2(size.x*0.5,-3),Vector2(size.x*0.5,size.y+3),Color(1,1,1,0.6),1.0)

var battle_panel: Control
var battle_box: VBoxContainer
var battle_pb := {}
var report_panel: Control
var report_box: VBoxContainer
signal battle_resolved(outcome: Dictionary)

func battle_visible() -> bool:
 return battle_panel != null and battle_panel.visible

func report_visible() -> bool:
 return report_panel != null and report_panel.visible

func _center_panel(w: float,h: float) -> Array:
 var p = _framed()
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",6)
 p.add_child(v)
 p.visible = false
 _anchor(p,0.5,0.5,0.5,0.5,Rect2(-w/2,-h/2,w/2,h/2))
 return [p,v]

func close_battle():
 battle_pb = {}
 if battle_panel: battle_panel.visible = false

# Entry point: war confirmation if needed (temporary rule), then the pre-battle panel.
func open_battle_flow(army_id: String,point: Vector2,target: Dictionary):
 if battle_panel == null:
  var pv = _center_panel(980,380)
  battle_panel = pv[0]
  battle_box = pv[1]
 _clear(battle_box)
 battle_panel.visible = true
 if target.needs_war:
  battle_box.add_child(UiKit.header("This means war with %s" % target.faction_name,22))
  battle_box.add_child(UiKit.divider(colors.trim))
  var t = UiKit.label("Diplomacy does not exist yet. Under the temporary rule, attacking another faction's army or settlement declares war on it, and there is no peace until diplomacy exists.",15)
  t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  t.custom_minimum_size = Vector2(900,0)
  battle_box.add_child(t)
  var row = HBoxContainer.new()
  var yes = Button.new()
  yes.name = "DeclareWar"
  yes.text = "Declare war"
  yes.focus_mode = Control.FOCUS_NONE
  yes.pressed.connect(func():
   data.declare_war(target.faction)
   target.needs_war = false
   open_battle_flow(army_id,point,target))
  row.add_child(yes)
  var no = Button.new()
  no.text = "Cancel"
  no.focus_mode = Control.FOCUS_NONE
  no.pressed.connect(close_battle)
  row.add_child(no)
  battle_box.add_child(row)
  return
 battle_pb = data.prebattle(army_id,point)
 _fill_prebattle()

# An AI army attacks the player (UiData.pending_battle): the pre-battle panel with the player
# defending.
func open_defense(pb: Dictionary):
 if battle_panel == null:
  var pv = _center_panel(980,380)
  battle_panel = pv[0]
  battle_box = pv[1]
 battle_panel.visible = true
 battle_pb = pb
 _fill_prebattle()

func _army_column(view: Dictionary,title: String) -> Control:
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",2)
 v.custom_minimum_size = Vector2(460,0)
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",8)
 head.add_child(Widgets.Emblem.new(view.faction,24))
 head.add_child(UiKit.header("%s · %s" % [title,view.faction.name],16))
 v.add_child(head)
 v.add_child(UiKit.label("%s men" % UiKit.format_int(view.men),14,UiKit.TEXT_DIM))
 for line in view.lines:
  v.add_child(UiKit.label("%s%s (%s)" % [line.army,(", led by "+line.general) if line.general != "" else "",line.arrives],14,Color("f1d79a"),UiKit.FONT_BOLD))
  var counts = {}
  var order = []
  for u in line.units:
   var n = data.unit_type(u.unit).display_name
   if not counts.has(n): order.append(n)
   counts[n] = counts.get(n,0)+1
  var parts = []
  for n in order: parts.append("%d× %s" % [counts[n],n])
  var l = UiKit.label(", ".join(parts) if not parts.is_empty() else "(no units)",13,UiKit.TEXT)
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  l.custom_minimum_size = Vector2(450,0)
  v.add_child(l)
 return v

func _fill_prebattle():
 _clear(battle_box)
 var pb = battle_pb
 var place = data.settlement(pb.settlement).name if pb.settlement != "" else "the field"
 var head = HBoxContainer.new()
 var heading = ("Siege assault on %s" % place) if pb.field.get("walls") != null else ("Battle at %s" % place if pb.settlement != "" else "Battle in the field")
 if pb.get("forced",false): heading = "%s attacks! %s" % [data.faction(pb.attacker.faction).name,heading]
 var title = UiKit.header(heading,22,Color("ef8a6a") if pb.get("forced",false) else Color("f1d79a"))
 title.name = "BattleTitle"
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 # An AI attack must be answered (Deploy, Quick resolve or Withdraw): no Close.
 if not pb.get("forced",false):
  var close = Button.new()
  close.text = "Close"
  close.focus_mode = Control.FOCUS_NONE
  close.pressed.connect(close_battle)
  head.add_child(close)
 battle_box.add_child(head)
 battle_box.add_child(UiKit.divider(colors.trim))
 var cols = HBoxContainer.new()
 cols.add_theme_constant_override("separation",20)
 cols.add_child(_army_column(pb.view.attacker,"Attacker"))
 cols.add_child(_army_column(pb.view.defender,"Defender"))
 battle_box.add_child(cols)
 battle_box.add_child(UiKit.divider(colors.trim))
 var walls = pb.field.get("walls")
 var wtxt = ""
 if walls != null: wtxt = " · walls and towers (defense %d)%s" % [int(walls.defense)," after %d turns of siege" % int(walls.siege_turns) if int(walls.siege_turns)>0 else ""]
 battle_box.add_child(UiKit.label("Terrain: %s · Weather: %s%s" % [pb.field.summary,pb.weather,wtxt],14,UiKit.TEXT))
 var bal = HBoxContainer.new()
 bal.add_theme_constant_override("separation",10)
 bal.add_child(UiKit.label("Balance of power",14,UiKit.TEXT_DIM))
 var ac = UiKit.colors(pb.view.attacker.faction).primary.lightened(0.15)
 var dc = UiKit.colors(pb.view.defender.faction).primary.lightened(0.15)
 var bar = BalanceBar.new(pb.odds,ac,dc)
 bar.name = "BalanceBar"
 bar.tooltip_text = "Attacker wins %d of %d quick simulations with default deployments (placeholder balance)." % [int(round(pb.odds*data.battle_odds_runs())),data.battle_odds_runs()]
 bar.mouse_filter = Control.MOUSE_FILTER_PASS
 bal.add_child(bar)
 var mine = pb.odds if not pb.player_is_defender else 1.0-pb.odds
 var verdict = "Decisive victory likely" if mine>=0.85 else ("Victory likely" if mine>=0.6 else ("Close fight" if mine>=0.4 else ("Defeat likely" if mine>=0.15 else "Crushing defeat likely")))
 bal.add_child(UiKit.label("%s (%d%%)" % [verdict,int(round(mine*100))],15,Color("f1d79a"),UiKit.FONT_BOLD))
 battle_box.add_child(bal)
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 var deploy = Button.new()
 deploy.name = "Deploy"
 deploy.text = "Deploy"
 deploy.focus_mode = Control.FOCUS_NONE
 deploy.disabled = not pb.approach.ok
 deploy.tooltip_text = pb.approach.get("reason","") if not pb.approach.ok else "Place your units and give orders on the battlefield."
 deploy.pressed.connect(open_deployment)
 row.add_child(deploy)
 var quick = Button.new()
 quick.name = "QuickResolve"
 quick.text = "Quick resolve"
 quick.focus_mode = Control.FOCUS_NONE
 quick.disabled = not pb.approach.ok
 quick.tooltip_text = pb.approach.get("reason","") if not pb.approach.ok else "Fight now with default deployments for both sides."
 quick.pressed.connect(func():
  var out = data.quick_resolve(battle_pb)
  var pbc = battle_pb
  close_battle()
  battle_resolved.emit(out)
  open_battle_report(pbc,out))
 row.add_child(quick)
 if pb.player_is_defender:
  var wd = Button.new()
  wd.name = "Withdraw"
  wd.text = "Withdraw"
  wd.focus_mode = Control.FOCUS_NONE
  wd.disabled = pb.kind == "settlement"
  wd.tooltip_text = "Retreat before the battle, losing %d%% of your men (placeholder)." % int(round(data.battle_withdraw_share()*100))
  wd.pressed.connect(func():
   data.withdraw(battle_pb)
   close_battle()
   toast("Your army withdrew before the battle."))
  row.add_child(wd)
 if walls != null and not pb.player_is_defender and data.siege_of(pb.settlement).get("army","") != pb.attacker.army:
  var bs = Button.new()
  bs.name = "Besiege"
  bs.text = "Besiege"
  bs.focus_mode = Control.FOCUS_NONE
  bs.disabled = not pb.approach.ok
  bs.tooltip_text = "Surround the settlement. Each turn weakens its walls; after its supplies run out the garrison starves (placeholder)."
  bs.pressed.connect(func():
   var r = data.besiege(pb.attacker.army,pb.settlement,pb)
   close_battle()
   toast("Siege laid: %s can hold out about %d turns." % [place,r.endurance] if r.ok else ", ".join(r.reasons)))
  row.add_child(bs)
 if not pb.approach.ok: row.add_child(UiKit.label(pb.approach.reason,14,Color("ef8a6a")))
 battle_box.add_child(row)

# Deployment screen (ui/deployment_screen.gd): full screen over the map. Back returns to the
# pre-battle panel with nothing spent; Fight resolves with the player's deployment.
var deployment_screen: Control

func deployment_visible() -> bool:
 return deployment_screen != null and is_instance_valid(deployment_screen)

func open_deployment():
 var pbc = battle_pb
 battle_panel.visible = false
 deployment_screen = DeploymentScreen.new()
 deployment_screen.name = "DeploymentScreen"
 add_child(deployment_screen)
 deployment_screen.setup(data,studio,colors,pbc)
 get_viewport().disable_3d = true # the opaque screen covers the map; skip rendering it
 deployment_screen.closed.connect(func():
  close_deployment()
  battle_panel.visible = true)
 deployment_screen.fought.connect(func(p,out):
  close_deployment()
  close_battle()
  battle_resolved.emit(out)
  open_battle_report(p,out))

func close_deployment():
 if deployment_visible(): deployment_screen.queue_free()
 deployment_screen = null
 get_viewport().disable_3d = false

# Battle report window (open_battle_report below).
func close_report():
 if report_panel: report_panel.visible = false

var report_replay: Control
var report_timeline: VBoxContainer

# Battle report: headline, why you won/lost, key numbers, the top-down replay with event markers,
# both sides' unit tables, and the full timeline (collapsed; clicking an event jumps the replay).
func open_battle_report(pb: Dictionary,out: Dictionary):
 # The enemy drew back before battle: no report, just the news.
 if out.get("withdrew",false):
  toast("%s: %s" % [out.entry.title,out.entry.text])
  return
 if report_panel == null:
  var pv = _center_panel(1240,860)
  report_panel = pv[0]
  report_box = pv[1]
 _clear(report_box)
 report_panel.visible = true
 var rep = data.battle_report(pb,out)
 var head = HBoxContainer.new()
 var title = UiKit.header(rep.headline,19,Color("9fe08a") if rep.won else Color("ef8a6a"))
 title.name = "Headline"
 title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 var close = Button.new()
 close.text = "Close"
 close.focus_mode = Control.FOCUS_NONE
 close.pressed.connect(close_report)
 head.add_child(close)
 report_box.add_child(head)
 report_box.add_child(UiKit.divider(colors.trim))
 var scroll = ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.custom_minimum_size = Vector2(1200,760)
 var body = VBoxContainer.new()
 body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 body.add_theme_constant_override("separation",6)
 scroll.add_child(body)
 report_box.add_child(scroll)
 var top = HBoxContainer.new()
 top.add_theme_constant_override("separation",16)
 body.add_child(top)
 var left = VBoxContainer.new()
 left.custom_minimum_size = Vector2(520,0)
 top.add_child(left)
 left.add_child(UiKit.header("Why you %s" % ("won" if rep.won else "lost"),16))
 var why = VBoxContainer.new()
 why.name = "Why"
 for line in rep.why:
  var l = UiKit.label("•  "+line,15,UiKit.TEXT if not line.begins_with("Lesson") else Color("f1d79a"))
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  l.custom_minimum_size = Vector2(510,0)
  why.add_child(l)
 left.add_child(why)
 left.add_child(UiKit.divider(colors.trim))
 var n = rep.numbers
 var nl = UiKit.label("Your men: %s, lost %s · Theirs: %s, lost %s · Units destroyed: %d yours, %d theirs · %d ticks · %s" % [
  UiKit.format_int(n.your_men),UiKit.format_int(n.your_losses),UiKit.format_int(n.their_men),UiKit.format_int(n.their_losses),n.your_destroyed,n.their_destroyed,n.ticks,n.weather],14,UiKit.TEXT_DIM)
 nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 nl.custom_minimum_size = Vector2(510,0)
 left.add_child(nl)
 for g in rep.generals: left.add_child(UiKit.label(g,14,Color("f1d79a")))
 var right = VBoxContainer.new()
 right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 top.add_child(right)
 right.add_child(UiKit.header("Replay",16))
 var my_fac = data.faction(pb.attacker.faction if rep.my_side == 0 else pb.defender.faction)
 var their_fac = data.faction(pb.defender.faction if rep.my_side == 0 else pb.attacker.faction)
 report_replay = BattleReplay.new()
 report_replay.name = "Replay"
 report_replay.setup(rep,UiKit.colors(my_fac).primary.lightened(0.1),UiKit.colors(their_fac).primary.lightened(0.1))
 right.add_child(report_replay)
 right.add_child(UiKit.label("Markers: green helped you, red helped them. Click one to jump there.",12,Color(UiKit.TEXT_DIM,0.8)))
 body.add_child(UiKit.divider(colors.trim))
 var tables = HBoxContainer.new()
 tables.add_theme_constant_override("separation",40)
 tables.add_child(_unit_table("Your units",rep.units,"Units"))
 tables.add_child(_unit_table("Enemy units",rep.enemy_units,"EnemyUnits"))
 body.add_child(tables)
 body.add_child(UiKit.divider(colors.trim))
 var toggle = Button.new()
 toggle.name = "TimelineToggle"
 toggle.text = "Show full timeline (%d events)" % rep.timeline.size()
 toggle.focus_mode = Control.FOCUS_NONE
 toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
 body.add_child(toggle)
 report_timeline = VBoxContainer.new()
 report_timeline.name = "Timeline"
 report_timeline.visible = false
 report_timeline.add_theme_constant_override("separation",0)
 for e in rep.timeline:
  var b = Button.new()
  b.flat = true
  b.focus_mode = Control.FOCUS_NONE
  b.alignment = HORIZONTAL_ALIGNMENT_LEFT
  b.text = "Tick %d  ·  %s" % [e.tick,e.text]
  b.add_theme_color_override("font_color",Color("bfe3a8") if e.ours else Color("efb39f"))
  b.pressed.connect(report_replay.jump.bind(e.tick,e.units))
  report_timeline.add_child(b)
 body.add_child(report_timeline)
 toggle.pressed.connect(func():
  report_timeline.visible = not report_timeline.visible
  toggle.text = ("Hide full timeline" if report_timeline.visible else "Show full timeline (%d events)" % rep.timeline.size()))

func _unit_table(title: String,units: Array,name: String) -> Control:
 var v = VBoxContainer.new()
 v.add_child(UiKit.header(title,15))
 var grid = GridContainer.new()
 grid.name = name
 grid.columns = 5
 grid.add_theme_constant_override("h_separation",16)
 for h in ["Unit","Men","Lost","Kills","Outcome"]: grid.add_child(UiKit.label(h,13,UiKit.TEXT_DIM,UiKit.FONT_BOLD))
 for u in units:
  grid.add_child(UiKit.label(u.name,14))
  grid.add_child(UiKit.label(str(u.men_start),14))
  grid.add_child(UiKit.label(str(u.losses),14))
  grid.add_child(UiKit.label(str(u.kills),14))
  grid.add_child(UiKit.label(u.outcome,14,Color("ef8a6a") if u.outcome in ["routed","destroyed"] else UiKit.TEXT))
 v.add_child(grid)
 return v

# --- End turn (bottom-right), hover tooltip, toast, FPS --------------------------------

# --- Round End Turn menu (TW:WH3, docs/tw-ui-parity.md L5) ------------------------------------
# End Turn in the centre; the hourglass turn counter below it with the notification gear beside;
# Objectives, Diplomacy, Technology and a culture slot (Senate / League / Vassals) around it, greyed
# until those systems exist. Positions on the ring are ours (TW's are unverified). The End Turn
# warning sits above the menu with its arrows and skip.

const ROUND_MENU = Vector2(300,214)
const ROUND_CENTRE = Vector2(176,110)
const EVENTS_BOTTOM = -336.0 # the event feed ends above the round menu and its warning
var round_buttons := {}

func _build_end_turn():
 var ring = Control.new()
 ring.name = "RoundMenu"
 ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ring.draw.connect(func():
  ring.draw_circle(ROUND_CENTRE,100,Color(colors.panel,0.92))
  ring.draw_arc(ROUND_CENTRE,100,0,TAU,64,colors.trim,2.0,true)
  ring.draw_arc(ROUND_CENTRE,64,0,TAU,48,Color(colors.trim,0.5),1.0,true))
 _anchor(ring,1,1,1,1,Rect2(-14-ROUND_MENU.x,-10-ROUND_MENU.y,-14,-10))
 end_turn_button = Widgets.RoundButton.new("year","End turn (Enter)\nAdvances the year: income, upkeep, construction and growth.",112,Color("e2b955"))
 end_turn_button.name = "EndTurn"
 end_turn_button.pressed.connect(func(): end_turn_requested.emit())
 end_turn_button.position = ROUND_CENTRE-Vector2(56,56)
 ring.add_child(end_turn_button)
 # Around the ring: [key, icon, tooltip, angle in degrees (0 = right, 90 = down), enabled].
 var items = [["notifications","finance","Notification settings\nWhich End Turn warnings show",135,true],
  ["objectives","objectives","Objectives",180,false],["diplomacy","diplomacy","Diplomacy",218,false],
  ["technology","tech","Technology",256,false],["culture","faction","Senate, League or Vassals (by culture)",294,false]]
 for it in items:
  var b = _round(it[1],it[2],38,it[4])
  b.name = "Round_"+it[0]
  b.position = ROUND_CENTRE+Vector2.from_angle(deg_to_rad(it[3]))*82.0-Vector2(19,19)
  round_buttons[it[0]] = b
  ring.add_child(b)
 round_buttons.notifications.pressed.connect(open_notification_settings)
 # Hourglass turn counter under the button.
 var counter = HBoxContainer.new()
 counter.name = "TurnCounter"
 counter.add_theme_constant_override("separation",4)
 counter.mouse_filter = Control.MOUSE_FILTER_PASS
 counter.add_child(Widgets.Icon.new("year",Color("e9c46a"),18))
 var year = UiKit.label("",14,UiKit.TEXT,UiKit.FONT_BOLD)
 counter.add_child(year)
 resource_labels.year = year
 resource_groups.year = counter
 end_turn_year = year
 counter.position = ROUND_CENTRE+Vector2(-60,66)
 counter.size = Vector2(120,22)
 counter.alignment = BoxContainer.ALIGNMENT_CENTER
 ring.add_child(counter)
 # End Turn warnings (TW:WH3): the pending kind and item; arrows cycle its items, Skip moves on to
 # the next kind. While one is shown, the End Turn button jumps to it instead of ending the turn.
 warning_box = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.95))
 warning_box.name = "EndTurnWarning"
 warning_box.visible = false
 var wv = VBoxContainer.new()
 wv.add_theme_constant_override("separation",2)
 warning_box.add_child(wv)
 warning_kind = UiKit.label("",14,Color("f1d79a"),UiKit.FONT_BOLD)
 warning_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 wv.add_child(warning_kind)
 warning_item = UiKit.label("",13,UiKit.TEXT)
 warning_item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 warning_item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 warning_item.custom_minimum_size = Vector2(190,0)
 wv.add_child(warning_item)
 var wr = HBoxContainer.new()
 wr.alignment = BoxContainer.ALIGNMENT_CENTER
 for b in [["<","WarnPrev",func(): warning_step.emit(-1),"Previous"],[">","WarnNext",func(): warning_step.emit(1),"Next"],["Skip >>","WarnSkip",func(): warning_skip.emit(),"Skip these warnings"]]:
  var btn = Button.new()
  btn.name = b[1]
  btn.text = b[0]
  btn.tooltip_text = b[3]
  btn.focus_mode = Control.FOCUS_NONE
  btn.pressed.connect(b[2])
  wr.add_child(btn)
 wv.add_child(wr)
 _anchor(warning_box,1,1,1,1,Rect2(-14-ROUND_MENU.x+40,-10-ROUND_MENU.y-110,-54,-10-ROUND_MENU.y-4))
 warning_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
 hover_tip = PanelContainer.new()
 hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
 hover_tip.add_theme_stylebox_override("panel",UiKit.textured(UiKit.PARCHMENT,12,10))
 var hv = VBoxContainer.new()
 hv.add_theme_constant_override("separation",2)
 hover_tip.add_child(hv)
 hover_title = UiKit.label("",17,UiKit.INK,UiKit.FONT_BOLD)
 hv.add_child(hover_title)
 hover_label = UiKit.label("",15,UiKit.INK)
 hv.add_child(hover_label)
 hover_tip.visible = false
 hover_tip.top_level = true
 add_child(hover_tip)
 toast_label = UiKit.header("",16,UiKit.TEXT)
 toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _anchor(toast_label,0.5,0,0.5,0,Rect2(-400,74,400,100))
 fps_label = UiKit.label("",12,Color(UiKit.TEXT_DIM,0.8))
 _anchor(fps_label,0,1,0,1,Rect2(14,-26,400,-8))

# Map hover info, styled like every tooltip (first line bold as the title).
func show_hover(text: String,screen_pos: Vector2):
 var parts = RichTooltip.split(text)
 hover_title.text = parts[0]
 hover_label.text = parts[1]
 hover_label.visible = parts[1] != ""
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
 # Debt: the treasury turns red, with what it means in the tooltip.
 resource_labels.treasury.add_theme_color_override("font_color",Color("ff7a6a") if r.in_debt else UiKit.TEXT)
 resource_labels.income.text = UiKit.signed(r.income)
 resource_labels.population.text = UiKit.format_int(r.population)
 resource_labels.year.text = "Year %d · Turn %d" % [r.year,r.turn]
 resource_groups.treasury.tooltip_text = _ledger_text()
 if r.in_debt:
  resource_groups.treasury.tooltip_text = ("IN DEBT
No construction, recruitment or new armies until the treasury is out of debt.
Unpaid soldiers desert: every unit loses %d%% of its men each turn.
%s

" % [r.desertion_pct,
   "BELOW THE DEBT LIMIT (%s): your most expensive units disband each turn until income covers upkeep." % UiKit.format_int(r.debt_limit) if r.below_limit else "Below %s gold, your most expensive units start to disband." % UiKit.format_int(r.debt_limit)])+_ledger_text()
 debt_tag.visible = r.in_debt
 debt_tag.tooltip_text = resource_groups.treasury.tooltip_text
 grace_tag.visible = int(r.grace)>=0
 if grace_tag.visible:
  grace_tag.text = " LANDLESS · %d turn%s " % [r.grace,"" if r.grace == 1 else "s"]
  grace_tag.tooltip_text = "Your house holds no settlement. Retake one within %d turn%s or it is destroyed (game over)." % [r.grace,"" if r.grace == 1 else "s"]
 resource_groups.income.tooltip_text = _ledger_text()
 resource_groups.population.tooltip_text = "Population of your settlements: %s\nGrows each year with settlement type, resources and wealth." % UiKit.format_int(r.population)
 resource_groups.year.tooltip_text = "Year %d, turn %d. One turn is one year." % [r.year,r.turn]
 if chronicle_panel and chronicle_panel.visible: _fill_summary()
 effects_icon.tooltip_text = _effects_text()
 if dropdown and dropdown.visible and dropdown_kind in LISTS: _fill_dropdown()
 if selected_settlement != "": show_settlement(selected_settlement)
 if selected_army != "": show_army(selected_army,army_location)
 if recruitment_visible(): _fill_recruitment()
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

# --- Small pop-ups under the top bar: camera and notification settings, and the lists ---------
# One at a time; pressing the same button again closes it (TW:WH3 drop-downs).

const LISTS = ["lords","provinces","factions"]
var overlay_state := {"borders":true,"settlements":true,"armies":true}

func _toggle_dropdown(kind: String,rect: Rect2,anchor_right: bool):
 if dropdown and dropdown.visible and dropdown_kind == kind:
  close_dropdown()
  return
 if dropdown == null:
  dropdown = _framed()
  dropdown.name = "Dropdown"
  add_child(dropdown)
 dropdown_kind = kind
 var a = 1.0 if anchor_right else 0.0
 dropdown.grow_vertical = Control.GROW_DIRECTION_END
 dropdown.grow_horizontal = Control.GROW_DIRECTION_BEGIN if anchor_right else Control.GROW_DIRECTION_END
 dropdown.anchor_left = a
 dropdown.anchor_right = a
 dropdown.anchor_top = 0
 dropdown.anchor_bottom = 0
 dropdown.offset_left = rect.position.x
 dropdown.offset_top = rect.position.y
 dropdown.offset_right = rect.size.x
 dropdown.offset_bottom = rect.position.y
 _fill_dropdown()
 dropdown.visible = true

func close_dropdown():
 if dropdown: dropdown.visible = false
 dropdown_kind = ""

func dropdown_visible() -> bool:
 return dropdown != null and dropdown.visible

func _fill_dropdown():
 _clear(dropdown)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",4)
 dropdown.add_child(v)
 match dropdown_kind:
  "camera": _fill_camera_settings(v)
  "notifications": _fill_notification_settings(v)
  "lords": _fill_lords(v)
  "provinces": _fill_provinces(v)
  "factions": _fill_factions(v)
 dropdown.reset_size()

func toggle_dropdown(kind: String):
 _toggle_dropdown(kind,Rect2(-470,62,-14,0),true)

func open_camera_settings():
 _toggle_dropdown("camera",Rect2(14,62,334,0),false)

func open_notification_settings():
 if dropdown and dropdown.visible and dropdown_kind == "notifications":
  close_dropdown()
  return
 _toggle_dropdown("notifications",Rect2(-14-ROUND_MENU.x-250,0,-14-ROUND_MENU.x-10,0),true)
 # Above the round menu, from the bottom.
 dropdown.anchor_top = 1
 dropdown.anchor_bottom = 1
 dropdown.offset_bottom = -20
 dropdown.offset_top = -20-dropdown.get_combined_minimum_size().y
 dropdown.grow_vertical = Control.GROW_DIRECTION_BEGIN

func _check(text: String,on: bool,tip: String,changed: Callable) -> CheckBox:
 var c = CheckBox.new()
 c.text = text
 c.button_pressed = on
 c.tooltip_text = tip
 c.focus_mode = Control.FOCUS_NONE
 c.toggled.connect(changed)
 return c

# Camera settings (TW:WH3 top-left): what the map shows and how the camera behaves. AI speed,
# following AI movements and your armies' speed are the camera settings of docs/tw-ui-parity.md L10.
func _fill_camera_settings(v: VBoxContainer):
 v.add_child(UiKit.header("Camera settings",16))
 v.add_child(UiKit.divider(colors.trim))
 v.add_child(UiKit.label("Show on the map (Ctrl+T: labels)",13,UiKit.TEXT_DIM))
 for o in [["borders","Territory borders"],["settlements","Settlement banners"],["armies","Armies"]]:
  var c = _check(o[1],overlay_state[o[0]],"Show or hide %s on the map" % o[1].to_lower(),func(on):
   overlay_state[o[0]] = on
   overlay_toggled.emit(o[0],on))
  c.name = "Overlay_"+o[0]
  v.add_child(c)
 _fill_camera_extra(v)

# Filled in by the AI turn and animation speed settings (Part 3 of this block).
func _fill_camera_extra(_v: VBoxContainer):
 pass

func set_overlay_state(overlay: String,on: bool):
 overlay_state[overlay] = on
 if dropdown_visible() and dropdown_kind == "camera": _fill_dropdown()

func _fill_notification_settings(v: VBoxContainer):
 v.add_child(UiKit.header("Notification settings",16))
 v.add_child(UiKit.label("Warnings on the End Turn button",13,UiKit.TEXT_DIM))
 for w in data.WARNINGS:
  var key = "warn_"+w[0]
  var c = _check(w[1],bool(Settings.get_value(key)),"Warn before ending the turn: %s" % w[1].to_lower(),func(on): Settings.set_value(key,on))
  c.name = "Warn_"+w[0]
  v.add_child(c)

func _list_row(cells: Array,widths: Array,on_press: Callable,tip := "") -> Control:
 var b = Button.new()
 b.focus_mode = Control.FOCUS_NONE
 b.flat = not on_press.is_valid()
 b.tooltip_text = tip
 b.custom_minimum_size = Vector2(0,26)
 var h = HBoxContainer.new()
 h.mouse_filter = Control.MOUSE_FILTER_IGNORE
 h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 h.offset_left = 6
 h.add_theme_constant_override("separation",6)
 for i in cells.size():
  var l = UiKit.label(str(cells[i]),13,UiKit.TEXT)
  l.custom_minimum_size = Vector2(widths[i],0)
  l.clip_text = true
  l.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.add_child(l)
 b.add_child(h)
 if on_press.is_valid(): b.pressed.connect(on_press)
 return b

func _list_head(cells: Array,widths: Array) -> Control:
 var h = HBoxContainer.new()
 h.add_theme_constant_override("separation",6)
 for i in cells.size():
  var l = UiKit.label(cells[i],12,UiKit.TEXT_DIM)
  l.custom_minimum_size = Vector2(widths[i],0)
  h.add_child(l)
 var m = MarginContainer.new()
 m.add_theme_constant_override("margin_left",6)
 m.add_child(h)
 return m

func _fill_lords(v: VBoxContainer):
 v.add_child(UiKit.header("Lords and heroes",16))
 var w = [130,120,46,100]
 v.add_child(_list_head(["General","Location","Units","Movement"],w))
 var rows = data.lords_list()
 for r in rows:
  var row = _list_row([r.general,r.where,r.units,"%d%%" % int(round(r.movement*100))],w,func():
   close_dropdown()
   army_chosen.emit(r.id),"%s\n%s · %s men" % [r.army,r.general,UiKit.format_int(r.men)])
  row.name = "Lord_"+r.id
  v.add_child(row)
 if rows.is_empty(): v.add_child(UiKit.label("No armies.",13,UiKit.TEXT_DIM))
 v.add_child(UiKit.label("Heroes"+COMING.replace("\n"," "),12,Color(UiKit.TEXT_DIM,0.6)))

func _fill_provinces(v: VBoxContainer):
 v.add_child(UiKit.header("Provinces",16))
 var w = [170,70,70,70]
 v.add_child(_list_head(["Province","Income","Growth","Order"],w))
 for r in data.provinces_list():
  var row = _list_row([r.name,UiKit.signed(r.income),"%+d" % r.growth,"%+d" % r.public_order],w,func():
   close_dropdown()
   settlement_chosen.emit(r.settlement),"%s\nClick to go there" % r.name)
  row.name = "Province_"+r.id
  v.add_child(row)

func _fill_factions(v: VBoxContainer):
 v.add_child(UiKit.header("Known factions",16))
 var w = [170,60,70,80]
 v.add_child(_list_head(["Faction","With you","Holdings","Attitude"],w))
 for r in data.factions_list():
  var row = _list_row([r.name,"War" if r.at_war else "Peace","%d / %d" % [r.settlements,r.armies],"—"],w,Callable(),
   "%s\n%s with you · %d settlements, %d armies\nAttitude comes with diplomacy." % [r.name,"At war" if r.at_war else "At peace",r.settlements,r.armies])
  row.name = "Faction_"+r.id
  v.add_child(row)

# --- Faction summary (TW:WH3 top-right round button): Summary, Records, Statistics ------------

var summary_tab := "summary"
var summary_box: VBoxContainer

func open_faction_summary(tab := "summary"):
 if chronicle_panel == null:
  chronicle_panel = _framed()
  chronicle_panel.name = "FactionSummary"
  var v = VBoxContainer.new()
  v.add_theme_constant_override("separation",6)
  chronicle_panel.add_child(v)
  summary_box = VBoxContainer.new()
  summary_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
  v.add_child(summary_box)
  chronicle_panel.visible = false
  _anchor(chronicle_panel,0.5,0.5,0.5,0.5,Rect2(-340,-300,340,300))
 if chronicle_panel.visible and summary_tab == tab:
  chronicle_panel.visible = false
  return
 summary_tab = tab
 chronicle_panel.visible = true
 _fill_summary()

func close_faction_summary():
 if chronicle_panel: chronicle_panel.visible = false

func summary_visible() -> bool:
 return chronicle_panel != null and chronicle_panel.visible

# The Records tab is the Grey Scribes' chronicle.
func toggle_chronicle():
 open_faction_summary("records")

func chronicle_visible() -> bool:
 return summary_visible() and summary_tab == "records"

func _fill_summary():
 _clear(summary_box)
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",6)
 head.add_child(Widgets.Emblem.new(data.player_faction(),26))
 var title = UiKit.header(data.player_faction().name,20)
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 for t in [["summary","Summary",true],["records","Records",true],["statistics","Statistics",false]]:
  var b = _tab_button(t[1],summary_tab == t[0])
  b.name = "Summary_"+t[0]
  b.custom_minimum_size.x = 96
  b.disabled = not t[2]
  if not t[2]: b.tooltip_text = t[1]+COMING
  b.pressed.connect(func():
   summary_tab = t[0]
   _fill_summary())
  head.add_child(b)
 var close = Button.new()
 close.text = "Close"
 close.focus_mode = Control.FOCUS_NONE
 close.pressed.connect(close_faction_summary)
 head.add_child(close)
 summary_box.add_child(head)
 summary_box.add_child(UiKit.divider(colors.trim))
 if summary_tab == "records":
  summary_box.add_child(UiKit.label("The Chronicle of the Grey Scribes. Kept in the archive at Crownhaven, without favour to any realm.",14,UiKit.TEXT_DIM))
  var scroll = ScrollContainer.new()
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  summary_box.add_child(scroll)
  chronicle_box = VBoxContainer.new()
  chronicle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  chronicle_box.add_theme_constant_override("separation",10)
  scroll.add_child(chronicle_box)
  _fill_chronicle()
  return
 var r = data.resources()
 var f = data.player_faction()
 summary_box.add_child(UiKit.label(f.get("realm",""),15,UiKit.TEXT_DIM))
 var lines = [["coin","Treasury",UiKit.format_int(r.treasury)],["income","Income per turn",UiKit.signed(r.income)],["population","Population",UiKit.format_int(r.population)],
  ["settlements","Settlements","%d" % data.state.settlements_of(data.player_faction_id()).size()],["settlements","Provinces","%d" % data.provinces_list().size()],
  ["lords","Armies","%d" % data.lords_list().size()],["year","Year","%d (turn %d)" % [r.year,r.turn]]]
 for l in lines: summary_box.add_child(_stat_row(l[0],l[1],l[2],""))
 var wars = data.factions_list().filter(func(x): return x.at_war).map(func(x): return x.name)
 summary_box.add_child(UiKit.divider(colors.trim))
 summary_box.add_child(_small("At war with: %s" % (", ".join(wars) if not wars.is_empty() else "nobody"),UiKit.TEXT,15))
 summary_box.add_child(_small(_effects_text(),UiKit.TEXT_DIM,14))

# --- Event pop-ups (TW:WH3 notifications for important events) --------------------------------

var popup_queue := []

func show_alert(a: Dictionary):
 popup_queue.append(a)
 if popup_panel == null or not popup_panel.visible: _next_alert()
 else: popup_panel.find_child("PopupOk",true,false).text = "Next (%d more)" % popup_queue.size()

func _next_alert():
 if popup_queue.is_empty():
  if popup_panel: popup_panel.visible = false
  return
 var a = popup_queue.pop_front()
 if popup_panel == null:
  popup_panel = _framed()
  popup_panel.name = "EventPopup"
  _anchor(popup_panel,0.5,0.5,0.5,0.5,Rect2(-220,-140,220,40))
 _clear(popup_panel)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",8)
 popup_panel.add_child(v)
 var t = UiKit.header(a.title,20)
 t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(t)
 v.add_child(UiKit.divider(colors.trim))
 var text = _small(a.text,UiKit.TEXT,15)
 text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(text)
 var ok = Button.new()
 ok.name = "PopupOk"
 ok.text = "Close" if popup_queue.is_empty() else "Next (%d more)" % popup_queue.size()
 ok.focus_mode = Control.FOCUS_NONE
 ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
 ok.pressed.connect(_next_alert)
 v.add_child(ok)
 popup_panel.visible = true

func alert_visible() -> bool:
 return popup_panel != null and popup_panel.visible

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

# Esc: close the topmost open panel. Returns false when nothing was open (the map then opens
# the pause menu).
func close_top_panel() -> bool:
 if alert_visible():
  _next_alert()
  return true
 if dropdown_visible():
  close_dropdown()
  return true
 if deployment_visible():
  deployment_screen.closed.emit()
  return true
 if report_visible():
  close_report()
  return true
 if battle_visible():
  if not battle_pb.get("forced",false): close_battle() # an attack on you must be answered
  return true
 if recruitment_visible():
  close_recruitment()
  return true
 if browser_visible():
  close_building_browser()
  return true
 if summary_visible():
  close_faction_summary()
  return true
 if selected_settlement != "" or selected_army != "":
  clear_selection()
  return true
 return false

# Show on the selected army's movement bar what a previewed move would spend this turn (main.gd
# during a held right click); spend 0 clears it.
func preview_movement(spend: float,overflow: bool):
 if movement_bar == null or not is_instance_valid(movement_bar): return
 if is_equal_approx(movement_bar.spend,spend) and movement_bar.overflow == overflow: return
 movement_bar.spend = spend
 movement_bar.overflow = overflow
 movement_bar.queue_redraw()

var warning_box: Control
var warning_kind: Label
var warning_item: Label

# Show the pending End Turn warning ({} hides it): {label, name, index, count}.
func show_end_turn_warning(w: Dictionary):
 warning_box.visible = not w.is_empty()
 if w.is_empty():
  end_turn_button.tooltip_text = "End turn (Enter)\nAdvances the year: income, upkeep, construction and growth."
  return
 warning_kind.text = w.label if int(w.count) == 1 else "%s (%d of %d)" % [w.label,int(w.index)+1,int(w.count)]
 warning_item.text = w.name
 end_turn_button.tooltip_text = "%s: %s\nClick (or Enter) to go there. Shift+Enter ends the turn anyway.\nWhich warnings show: Settings." % [w.label,w.name]

# Key 3 (TW:WH3 building browser): open the browser on the first empty slot of a settlement, or
# on the main building when every slot is built.
func open_first_empty_slot(settlement_id: String):
 var slots = data.building_slots(settlement_id)
 var slot = 0
 for i in slots.size():
  if slots[i].get("empty",false):
   slot = i
   break
 open_building_browser(settlement_id,slot)

# During the AI's turn (camera following its armies): a top-centre bar with a skip button (TW:WH3's
# ">>"). Space or Esc also skips.
signal ai_skip
var ai_bar: Control
func show_ai_turn_bar(on: bool):
 if ai_bar == null:
  ai_bar = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.95))
  ai_bar.name = "AiTurnBar"
  var h = HBoxContainer.new()
  h.add_theme_constant_override("separation",10)
  ai_bar.add_child(h)
  h.add_child(UiKit.header("Enemy movements",15))
  var skip = Button.new()
  skip.name = "AiSkip"
  skip.text = ">>  Skip"
  skip.tooltip_text = "Skip the rest of the AI movements (Space or Esc)"
  skip.focus_mode = Control.FOCUS_NONE
  skip.pressed.connect(func(): ai_skip.emit())
  h.add_child(skip)
  _anchor(ai_bar,0.5,0,0.5,0,Rect2(-140,104,140,150))
 ai_bar.visible = on
