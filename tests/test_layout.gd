extends GutTest
# TW:WH3 campaign layout (docs/tw-ui-parity.md section 13): top bar sections with greyed "Coming
# later" buttons, the drop-down lists, the faction summary, the round End Turn menu, the three-part
# bottom panel, important-event pop-ups, and that the recruitment drawer never covers the event feed.

const UiData = preload("res://core/ui_data.gd")
const GameState = preload("res://core/game_state.gd")
const Battles = preload("res://core/battles.gd")
const WorldMap = preload("res://core/world_map.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const HOST = "aurek_host"

var studio

func before_each():
 studio = PortraitStudio.new()
 add_child_autofree(studio)

func build_ui(data) -> Control:
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(data,studio)
 return ui

func test_top_bar_has_tw_buttons_in_order_with_missing_systems_greyed():
 var ui = build_ui(UiData.new(GameState.from_data()))
 var left = ui.find_child("TopLeft",true,false).get_children().map(func(b): return String(b.name))
 assert_eq(left,["Top_menu","Top_advisor","Top_help","Top_units","Top_camera","Top_court","Top_realm"])
 var right = ui.find_child("TopRight",true,false).get_children().map(func(b): return String(b.name))
 assert_eq(right,["Top_tactical","Top_events","Top_lords","Top_provinces","Top_construction","Top_missions","Top_factions","Top_summary"])
 for k in ["advisor","help","units","missions"]:
  assert_true(ui.top_buttons[k].disabled,k+" is greyed")
  assert_string_contains(ui.top_buttons[k].tooltip_text,"Coming later")
 for k in ["menu","camera","tactical","events","lords","provinces","factions","summary"]: assert_false(ui.top_buttons[k].disabled,k+" works")
 # Part B: the food, wood and stone stockpiles, the season and the market replace the mock resource slots.
 for n in ["Res_food","Res_wood","Res_stone","Season","MarketButton"]: assert_not_null(ui.find_child(n,true,false),n)
 assert_string_contains(ui.effects_icon.tooltip_text,"Faction effects")

func test_toggles_and_menu_signal():
 var ui = build_ui(UiData.new(GameState.from_data()))
 watch_signals(ui)
 ui.top_buttons.menu.pressed.emit()
 assert_signal_emitted(ui,"menu_requested")
 ui.top_buttons.events.pressed.emit()
 assert_false(ui.events_frame.visible)
 ui.top_buttons.tactical.pressed.emit()
 assert_false(ui.minimap_frame.visible)

func test_lists_come_from_the_data_and_jump_on_click():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 watch_signals(ui)
 ui.top_buttons.lords.pressed.emit()
 assert_eq(ui.dropdown_kind,"lords")
 var row = ui.dropdown.find_child("Lord_"+HOST,true,false)
 assert_not_null(row)
 row.pressed.emit()
 assert_signal_emitted_with_parameters(ui,"army_chosen",[HOST])
 assert_false(ui.dropdown_visible(),"a choice closes the list")
 ui.top_buttons.provinces.pressed.emit()
 assert_eq(ui.dropdown.find_children("Province_*","",true,false).size(),data.provinces_list().size())
 assert_gt(data.provinces_list().size(),0)
 ui.top_buttons.factions.pressed.emit()
 for f in data.factions_list(): assert_not_null(ui.dropdown.find_child("Faction_"+f.id,true,false))
 ui.top_buttons.factions.pressed.emit()
 assert_false(ui.dropdown_visible(),"the same button closes it")

func test_list_rows_match_the_state():
 var data = UiData.new(GameState.from_data())
 var me = data.player_faction_id()
 for r in data.provinces_list():
  var st = data.province_stats(r.id)
  assert_eq(r.income,int(st.income))
  assert_eq(data.state.settlements[r.settlement].owner,me)
 var foe = data.factions_list()[0].id
 data.state.wars.append(Battles.war_key(me,foe))
 assert_true(data.factions_list().filter(func(x): return x.id == foe)[0].at_war)
 assert_false(data.factions_list().any(func(x): return x.id == me),"you are not in your own list")

func test_camera_settings_toggle_map_overlays():
 var ui = build_ui(UiData.new(GameState.from_data()))
 watch_signals(ui)
 ui.top_buttons.camera.pressed.emit()
 assert_eq(ui.dropdown_kind,"camera")
 var c: CheckBox = ui.dropdown.find_child("Overlay_borders",true,false)
 c.button_pressed = false
 assert_signal_emitted_with_parameters(ui,"overlay_toggled",["borders",false])

func test_faction_summary_tabs_and_records_are_the_chronicle():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 data.end_turn()
 ui.top_buttons.summary.pressed.emit()
 assert_true(ui.summary_visible())
 assert_false(ui.chronicle_visible())
 assert_true(ui.chronicle_panel.find_child("Summary_statistics",true,false).disabled)
 ui.chronicle_panel.find_child("Summary_records",true,false).pressed.emit()
 assert_true(ui.chronicle_visible())
 assert_eq(ui.chronicle_box.get_child_count(),data.state.chronicle.size())
 assert_true(ui.close_top_panel())
 assert_false(ui.summary_visible())

func test_round_menu_end_turn_counter_and_greyed_buttons():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 var ring = ui.find_child("RoundMenu",true,false)
 assert_true(ring.is_ancestor_of(ui.end_turn_button))
 for k in ["objectives","technology","culture"]:
  assert_true(ui.round_buttons[k].disabled,k+" greyed")
  assert_string_contains(ui.round_buttons[k].tooltip_text,"Coming later")
 assert_false(ui.round_buttons.notifications.disabled)
 assert_false(ui.round_buttons.diplomacy.disabled,"diplomacy opens the diplomacy screen")
 assert_eq(ui.resource_labels.year.text,"Year %d · Turn %d" % [data.resources().year,data.resources().turn])
 ui.round_buttons.notifications.pressed.emit()
 assert_eq(ui.dropdown_kind,"notifications")
 assert_not_null(ui.dropdown.find_child("Warn_funds",true,false))

func test_province_panel_has_three_parts_and_a_garrison_tab():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 ui.show_settlement("goldspire_rock")
 assert_true(ui.stats_panel.visible)
 assert_false(ui.lord_box.visible)
 assert_not_null(ui.bottom_box.find_child("BuildingCards",true,false))
 assert_true(ui.info_box.get_children().any(func(c): return c is Label and c.text == "Climate"))
 ui.set_settlement_tab("garrison")
 var g = ui.bottom_box.find_child("GarrisonCards",true,false)
 assert_not_null(g)
 assert_eq(g.get_children().filter(func(c): return not c is Label).size(),data.garrison("goldspire_rock").units.size())
 ui.set_settlement_tab("buildings")

func test_army_panel_has_lord_left_and_info_right():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 ui.show_army(HOST,"Goldspire")
 assert_false(ui.stats_panel.visible)
 assert_true(ui.lord_box.visible)
 assert_not_null(ui.lord_box.find_child("LordCard",true,false))
 assert_not_null(ui.lord_box.find_child("MovementBar",true,false))
 assert_not_null(ui.info_box.find_child("SupplyBar",true,false),"supply replaces the greyed stance slot")
 var info = data.army_info(HOST)
 assert_eq(info.upkeep,data.army(HOST).upkeep)
 assert_between(info.replenish_pct,0,100)

func test_drawer_never_covers_the_event_feed_or_round_menu():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 var vp = Vector2(1600,1000)
 # Horizontal extents at the design viewport: the bottom panel ends left of the feed and the menu.
 var panel_right = ui.bottom_panel.offset_right
 var feed_left = vp.x+ui.events_frame.offset_left
 var ring_left = vp.x+ui.find_child("RoundMenu",true,false).offset_left
 assert_lt(panel_right,feed_left)
 assert_lt(panel_right,ring_left)
 # Its content never makes it wider than that (it did: the columns' minimum widths added up to
 # more, and the panel grew into the feed). Checked with the drawer open and a full queue.
 var s = data.state
 s.treasury.house_aurek = 100000
 var gp = load("res://core/world_map.gd").settlement_position("goldspire_rock")
 s.army_state.aurek_host.position = [gp.x,gp.y]
 s.army_state.aurek_host.garrison = "goldspire_rock"
 for i in 6: data.recruit("aurek_host","peasant_levy")
 ui.show_army("aurek_host","Goldspire")
 ui.open_recruitment("aurek_host")
 assert_lte(ui.bottom_panel.get_combined_minimum_size().x,ui.BOTTOM_WIDTH,"the army panel with the drawer fits its width")
 ui.show_settlement("goldspire_rock")
 assert_lte(ui.bottom_panel.get_combined_minimum_size().x,ui.BOTTOM_WIDTH,"the province panel fits its width")
 # The feed ends above the round menu (its notification is on the End Turn button itself).
 assert_lt(ui.events_frame.offset_bottom,ui.find_child("RoundMenu",true,false).offset_top)

func test_important_events_pop_up():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 var me = data.player_faction_id()
 var before = data._alert_snapshot()
 var foe = data.factions_list()[0].id
 Battles.declare_war(data.state,foe,me)
 var lost = data.state.settlements_of(me)[0]
 data.state.settlements[lost].owner = foe
 var alerts = data.alerts_since(before)
 assert_eq(alerts.map(func(a): return a.kind),["war","settlement_lost"])
 for a in alerts: ui.show_alert(a)
 assert_true(ui.alert_visible())
 assert_eq(ui.popup_panel.find_child("PopupOk",true,false).text,"Next (1 more)")
 assert_true(ui.close_top_panel())
 assert_true(ui.alert_visible())
 ui.popup_panel.find_child("PopupOk",true,false).pressed.emit()
 assert_false(ui.alert_visible())

func test_small_text_keeps_visible_word_spaces():
 # Small text kept readable (2026-10-07): labels are at least MIN_TEXT and spaces stay visible (the
 # old body font's spaces vanished at 12-13 px: the general's name read "SerAlaricAurek").
 var UiKit = load("res://ui/ui_kit.gd")
 for size in [11,12,13,14]:
  var l: Label = UiKit.label("Ser Alaric Aurek",size)
  var f: Font = l.get_theme_font("font")
  var gap = (f.get_string_size("Ser Alaric Aurek",HORIZONTAL_ALIGNMENT_LEFT,-1,size).x-f.get_string_size("SerAlaricAurek",HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)/2.0
  assert_gte(gap,0.25*size,"a space is at least a quarter em at %d px" % size)
  l.free()

# --- Diplomacy screen and character window (docs/tw-ui-parity.md §15) --------------------------

func test_diplomacy_screen_three_columns_and_declare_war():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 ui.round_buttons.diplomacy.pressed.emit()
 assert_true(ui.diplomacy_visible())
 var d = ui.diplomacy_screen
 for n in ["DiplomacyMe","DiplomacyCentre","DiplomacyThem","Acceptance","Standing","WarStatus","Propose"]: assert_not_null(d.find_child(n,true,false),n)
 assert_true(d.find_child("Propose",true,false).disabled,"an empty offer cannot be proposed")
 var target = d.selected
 assert_ne(target,"")
 assert_false(data.at_war(target))
 d.find_child("DeclareWarDip",true,false).pressed.emit()
 assert_not_null(d.find_child("WarConfirm",true,false),"war asks first")
 d.find_child("WarYes",true,false).pressed.emit()
 assert_true(data.at_war(target))
 assert_true(d.find_child("DeclareWarDip",true,false).disabled,"already at war")
 assert_true(ui.close_top_panel())
 assert_false(ui.diplomacy_visible())

func test_diplomacy_focus_selects_the_faction():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 var ids = data.diplomacy().factions.map(func(f): return f.id)
 assert_gt(ids.size(),0)
 ui.open_diplomacy(ids[-1])
 assert_eq(ui.diplomacy_screen.selected,ids[-1])

func test_character_window_from_the_lord_panel_and_lords_list():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 ui.show_army(HOST,"here")
 ui.lord_box.find_child("LordDetails",true,false).pressed.emit()
 assert_true(ui.character_visible())
 assert_true(ui.close_top_panel())
 assert_false(ui.character_visible())
 ui.toggle_dropdown("lords")
 ui.dropdown.find_child("LordInfo_"+HOST,true,false).pressed.emit()
 assert_true(ui.character_visible())
 assert_false(ui.dropdown_visible())

# The End Turn button IS the notification (owner spec 2026-10-07): the top item's icon, a plate
# with its short text and a count while anything is pending; the hourglass when nothing is.
func test_end_turn_button_states():
 var data = UiData.new(GameState.from_data())
 var ui = build_ui(data)
 var w = data.end_turn_warnings()
 assert_false(w.is_empty(),"a fresh campaign has something pending (lords that have not moved)")
 var total = 0
 for k in w: total += k.items.size()
 ui.show_end_turn_warning({"label":w[0].label,"short":w[0].short,"icon":w[0].icon,"name":w[0].items[0].name,"index":0,"count":w[0].items.size(),"total":total})
 assert_true(ui.end_turn_plate.visible,"the plate names the item")
 assert_eq(str(ui.end_turn_plate.get_meta("text")),w[0].short)
 assert_eq(ui.end_turn_button.icon_kind,w[0].icon,"the button shows the item's icon")
 assert_eq(int(ui.end_turn_badge.get_meta("count")),total)
 assert_true(ui.end_turn_anyway.visible,"End turn anyway beside it")
 assert_null(ui.find_child("EndTurnWarning",true,false),"no separate notification stack")
 ui.show_end_turn_warning({})
 assert_false(ui.end_turn_plate.visible)
 assert_eq(ui.end_turn_button.icon_kind,"year","nothing pending: End Turn")

func test_labels_have_a_minimum_size():
 var UiKit = load("res://ui/ui_kit.gd")
 var l: Label = UiKit.label("Small print",11)
 assert_eq(l.get_theme_font_size("font_size"),UiKit.MIN_TEXT,"no label below the minimum body size")
 l.free()
