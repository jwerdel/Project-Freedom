extends GutTest
# The strategic map (ui/strategic_map.gd) and the map scene's TW:WH3 hotkeys: layers, colours from
# the campaign state, the fade in and out, clicking or scrolling in to return, caching for the big
# map, and Tab, zooming out, K, Alt+K, Ctrl+T, 1, 2, R and Esc on the map scene.

const UiData = preload("res://core/ui_data.gd")
const GameState = preload("res://core/game_state.gd")
const Battles = preload("res://core/battles.gd")
const WorldMap = preload("res://core/world_map.gd")
const StrategicMap = preload("res://ui/strategic_map.gd")
const TerritoryOverlay = preload("res://visuals/terrain/territory_overlay.gd")
const Settings = preload("res://core/settings.gd")
const SaveSystem = preload("res://core/save_system.gd")
const HOST = "aurek_host"

var saved = null

func before_all():
 if FileAccess.file_exists(Settings.PATH): saved = FileAccess.get_file_as_string(Settings.PATH)

func after_all():
 if saved != null:
  var f = FileAccess.open(Settings.PATH,FileAccess.WRITE)
  f.store_string(saved)
  f.close()
 elif FileAccess.file_exists(Settings.PATH): DirAccess.remove_absolute(Settings.PATH)
 Settings.reload()

func build_map(data) -> Control:
 var m = StrategicMap.new()
 add_child_autofree(m)
 m.setup(data,TerritoryOverlay.RECT)
 m.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT) # a fixed size for the tests
 m.size = Vector2(1600,1000)
 return m

func test_layers_available_and_greyed():
 var m = build_map(UiData.new(GameState.from_data()))
 var ids = StrategicMap.LAYERS.map(func(l): return l.id)
 assert_eq(ids,["affiliation","diplomatic","attitude","order","development","climate","faith","culture"])
 for id in ["attitude","faith"]:
  assert_true(m.layer_buttons[id].disabled,id+" greyed")
  assert_string_contains(m.layer_buttons[id].tooltip_text,"Coming later")
 assert_false(m.layer_buttons.culture.disabled,"the Culture layer works (land conversion, 2026-10-04)")
 m.set_layer("attitude")
 assert_eq(m.layer,"affiliation","a greyed layer cannot be chosen")
 m.set_layer("development")
 assert_eq(m.layer,"development")
 assert_true(m.layer_buttons.development.button_pressed)
 assert_false(m.layer_buttons.affiliation.button_pressed)

func test_layer_colours_follow_the_campaign_state():
 var data = UiData.new(GameState.from_data())
 var m = build_map(data)
 var me = data.player_faction_id()
 var mine = data.state.settlements_of(me)[0]
 var other = data.settlement_ids().filter(func(s): return data.state.settlements[s].owner != me and data.state.settlements[s].owner != "")[0]
 var foe = data.state.settlements[other].owner
 m.set_layer("affiliation")
 assert_eq(Color(m.region_color(mine),1.0),Color(data.faction(me).primary))
 m.set_layer("diplomatic")
 var peace = m.region_color(other)
 data.state.wars.append(Battles.war_key(me,foe))
 assert_ne(m.region_color(other),peace,"war changes the diplomatic colour")
 assert_ne(m.region_color(mine),m.region_color(other))
 m.set_layer("development")
 data.state.settlements[mine].level = 1
 var low = m.region_color(mine)
 data.state.settlements[mine].level = 3
 assert_ne(m.region_color(mine),low)
 m.set_layer("climate")
 assert_true(m._fills.is_empty(),"climate shows the terrain itself, no region fills")
 m.set_layer("order")
 assert_false(m._fills.is_empty())

func test_fills_and_icons_refresh_on_state_change():
 var data = UiData.new(GameState.from_data())
 var m = build_map(data)
 m.set_layer("affiliation")
 var sid = data.state.settlements_of(data.player_faction_id())[0]
 var before = m._fills[sid]
 var foe = data.factions_list()[0].id
 data.state.settlements[sid].owner = foe
 data.changed.emit()
 assert_ne(m._fills[sid],before,"a capture recolours the region")
 assert_eq(m._owners[sid],foe)
 assert_eq(m._seals.size(),data.settlement_ids().size())

func test_screen_mapping_round_trips_and_polys_are_cached():
 var m = build_map(UiData.new(GameState.from_data()))
 for p in [Vector2(0,0),Vector2(-60,30),Vector2(80,-40)]:
  assert_almost_eq(m.to_world(m.to_screen(p)),p,Vector2(0.01,0.01))
 assert_gte(m.map_rect().position.y,127.9,"below the layer bar")
 var a = m._screen_polys()
 assert_eq(a.size(),WorldMap.regions().size())
 assert_same(m._screen_polys(),a,"cached while the size stays")
 var first = a.values()[0].duplicate()
 m.size = Vector2(1200,800)
 assert_ne(m._screen_polys().values()[0],first,"rebuilt when the size changes")

func test_open_fades_in_and_close_fades_out():
 var m = build_map(UiData.new(GameState.from_data()))
 assert_false(m.visible)
 m.open_map()
 assert_true(m.is_open() and m.visible)
 m._process(StrategicMap.FADE*0.5)
 assert_almost_eq(m.modulate.a,0.5,0.01)
 m._process(StrategicMap.FADE)
 assert_eq(m.modulate.a,1.0)
 m.close_map()
 assert_false(m.is_open())
 m._process(StrategicMap.FADE*2)
 assert_false(m.visible,"hidden once faded out")
 m.open_map(true)
 assert_eq(m.fade,1.0,"captures open at once")

func test_click_or_scroll_in_chooses_a_location():
 var m = build_map(UiData.new(GameState.from_data()))
 m.open_map(true)
 watch_signals(m)
 var target = Vector2(-30,10)
 for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_WHEEL_UP]:
  var e = InputEventMouseButton.new()
  e.button_index = button
  e.pressed = true
  e.position = m.to_screen(target)
  m._gui_input(e)
 assert_signal_emit_count(m,"location_chosen",2)
 var p = get_signal_parameters(m,"location_chosen")[0]
 assert_almost_eq(p,target,Vector2(0.01,0.01))
 var down = InputEventMouseButton.new()
 down.button_index = MOUSE_BUTTON_WHEEL_DOWN
 down.pressed = true
 down.position = m.to_screen(target)
 m._gui_input(down)
 assert_signal_emit_count(m,"location_chosen",2,"scrolling out does nothing")

func test_rebuild_is_cheap():
 # Scaling guard: rebuilding every cached colour and icon must stay far below a frame.
 var data = UiData.new(GameState.from_data())
 var m = build_map(data)
 var t0 = Time.get_ticks_usec()
 for i in 10: m.refresh()
 var ms = (Time.get_ticks_usec()-t0)/10000.0
 gut.p("strategic map refresh: %.2f ms for %d regions" % [ms,WorldMap.regions().size()])
 assert_lt(ms,8.0)

# --- The map scene -----------------------------------------------------------------------------

func key(main,code: Key,alt := false,ctrl := false):
 var e = InputEventKey.new()
 e.keycode = code
 e.pressed = true
 e.alt_pressed = alt
 e.ctrl_pressed = ctrl
 main._unhandled_input(e)

func test_map_scene_hotkeys_and_strategic_transition():
 SaveSystem.dir = "user://test_saves"
 Settings.set_value("army_speed",1)
 var main = load("res://Main.tscn").instantiate()
 add_child_autofree(main)
 await get_tree().process_frame
 # Tab opens and closes the strategic map; Esc also closes it.
 key(main,KEY_TAB)
 assert_true(main.map_open())
 assert_false(main.pins_root.visible,"banners hide under the strategic map")
 key(main,KEY_TAB)
 assert_false(main.map_open())
 key(main,KEY_TAB)
 key(main,KEY_ESCAPE)
 assert_false(main.map_open())
 # Zooming out past the farthest zoom opens it; choosing a place returns there, zoomed in.
 main.desired_distance = 210.0
 var wheel = InputEventMouseButton.new()
 wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
 wheel.pressed = true
 main._unhandled_input(wheel)
 assert_true(main.map_open())
 main.strategic.location_chosen.emit(Vector2(-40,12))
 assert_false(main.map_open())
 assert_almost_eq(Vector2(main.target.x,main.target.z),Vector2(-40,12),Vector2(0.01,0.01))
 assert_lte(main.desired_distance,main.STRATEGIC_RETURN_DISTANCE)
 # K hides the interface; Alt+K adds letterbox bars; Esc brings it back.
 key(main,KEY_K)
 assert_false(main.ui.visible)
 key(main,KEY_K)
 assert_true(main.ui.visible)
 key(main,KEY_K,true)
 assert_false(main.ui.visible)
 assert_true(main.letterbox.visible)
 key(main,KEY_ESCAPE)
 assert_true(main.ui.visible)
 assert_false(main.letterbox.visible)
 # Ctrl+T: settlement labels.
 key(main,KEY_T,false,true)
 assert_false(main.overlays.settlements)
 assert_false(main.pins_root.visible)
 key(main,KEY_T,false,true)
 assert_true(main.pins_root.visible)
 # 1 / 2: the settlement's building slots or garrison.
 main.select_settlement("goldspire_rock")
 key(main,KEY_2)
 assert_eq(main.ui.settlement_tab,"garrison")
 key(main,KEY_1)
 assert_eq(main.ui.settlement_tab,"buildings")
 # R: your armies' speed.
 key(main,KEY_R)
 assert_eq(Settings.army_speed(),2)
 key(main,KEY_R)
 assert_eq(Settings.army_speed(),1)
 SaveSystem.dir = SaveSystem.DIR

func test_culture_layer_blends_a_converting_region():
 var data = UiData.new(GameState.from_data())
 var m = build_map(data)
 m.set_layer("culture")
 var before = m.region_color("goldspire_rock")
 data.state.land.goldspire_rock = {"from":"greek","to":"roman","value":0.5,"built":0}
 var mid = m.region_color("goldspire_rock")
 assert_ne(mid,before)
 var l = data.land("goldspire_rock")
 assert_true(Color(mid,1.0).is_equal_approx(Color(l.from_color).lerp(Color(l.to_color),0.5)),"halfway between the two cultures")
