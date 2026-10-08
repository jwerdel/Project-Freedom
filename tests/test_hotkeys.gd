extends GutTest
# Hotkeys (owner hotfix 2026-10-07; docs/tw-ui-parity.md §20): Tab is the strategic map, M the market,
# driven by real key events on the campaign scene.

const SaveSystem = preload("res://core/save_system.gd")
const Movement = preload("res://core/movement.gd")

var main

func before_each():
 SaveSystem.dir = "user://test_saves"
 main = load("res://Main.tscn").instantiate()
 add_child_autofree(main)
 for i in 3: await get_tree().process_frame

func after_each():
 SaveSystem.dir = SaveSystem.DIR

func _key(code: int):
 for pressed in [true,false]:
  var k = InputEventKey.new()
  k.keycode = code
  k.physical_keycode = code
  k.pressed = pressed
  Input.parse_input_event(k)
  Input.flush_buffered_events()

func test_tab_toggles_the_strategic_map():
 assert_false(main.map_open())
 _key(KEY_TAB)
 await get_tree().process_frame
 assert_true(main.map_open(),"Tab opens the strategic map")
 assert_false(main.ui.market_visible(),"and nothing else")
 _key(KEY_TAB)
 await get_tree().process_frame
 assert_false(main.map_open(),"Tab closes it")

func test_m_toggles_the_market_only():
 _key(KEY_M)
 await get_tree().process_frame
 assert_true(main.ui.market_visible(),"M opens the market")
 assert_false(main.map_open(),"M is not the strategic map")
 _key(KEY_M)
 await get_tree().process_frame
 assert_false(main.ui.market_visible(),"M closes it")

func test_backspace_cancels_the_selected_army_order():
 main.select_army(main.COMMANDER_ARMY)
 var s = main.ui_data.state
 var p = Movement.position(s,main.COMMANDER_ARMY)
 for k in 16:
  var t = p+Vector2(420,0).rotated(k*TAU/16.0)
  var plan = main.ui_data.plan_move(main.COMMANDER_ARMY,t)
  if plan.ok and int(plan.total_turns)>=2:
   main.ui_data.order_move(main.COMMANDER_ARMY,t)
   break
 assert_false(s.army_state[main.COMMANDER_ARMY].order.is_empty(),"a standing order")
 _key(KEY_BACKSPACE)
 await get_tree().process_frame
 assert_true(s.army_state[main.COMMANDER_ARMY].order.is_empty(),"Backspace cancels it")
