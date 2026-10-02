extends GutTest
# Settings (core/settings.gd): persistence, AI turn speed, following AI movements, your armies'
# animation speed, and the controls that set them (AI turn bar, camera settings, Settings panel).

const Settings = preload("res://core/settings.gd")
const UiData = preload("res://core/ui_data.gd")
const GameState = preload("res://core/game_state.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const SettingsPanel = preload("res://ui/settings_panel.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")

var saved = null # the developer's settings file, restored after the tests

func before_all():
 if FileAccess.file_exists(Settings.PATH): saved = FileAccess.get_file_as_string(Settings.PATH)

func before_each():
 if FileAccess.file_exists(Settings.PATH): DirAccess.remove_absolute(Settings.PATH)
 Settings.reload()

func after_all():
 if saved != null:
  var f = FileAccess.open(Settings.PATH,FileAccess.WRITE)
  f.store_string(saved)
  f.close()
 elif FileAccess.file_exists(Settings.PATH): DirAccess.remove_absolute(Settings.PATH)
 Settings.reload()

func build_ui() -> Control:
 var studio = PortraitStudio.new()
 add_child_autofree(studio)
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(UiData.new(GameState.from_data()),studio)
 return ui

func test_defaults():
 assert_eq(Settings.follow_ai_mode(),"off","following AI movements is off by default (owner)")
 assert_eq(Settings.ai_speed(),1)
 assert_eq(Settings.army_speed(),1)

func test_values_persist_across_a_reload():
 Settings.set_value("follow_ai","near")
 Settings.set_value("ai_speed",4)
 Settings.set_value("army_speed",2)
 Settings.reload()
 assert_eq(Settings.follow_ai_mode(),"near")
 assert_eq(Settings.ai_speed(),4)
 assert_eq(Settings.army_speed(),2)
 var file = JSON.parse_string(FileAccess.get_file_as_string(Settings.PATH))
 assert_eq(file.follow_ai,"near")
 assert_eq(int(file.ai_speed),4)

func test_invalid_values_fall_back():
 Settings.set_value("follow_ai","sometimes")
 Settings.set_value("ai_speed",3)
 Settings.set_value("army_speed",8)
 assert_eq(Settings.follow_ai_mode(),"off")
 assert_eq(Settings.ai_speed(),1)
 assert_eq(Settings.army_speed(),1)

func test_follow_modes():
 assert_false(Settings.should_follow("off",true))
 assert_false(Settings.should_follow("off",false))
 assert_true(Settings.should_follow("near",true))
 assert_false(Settings.should_follow("near",false))
 assert_true(Settings.should_follow("all",true))
 assert_true(Settings.should_follow("all",false))

func test_speed_multipliers():
 for s in Settings.AI_SPEEDS:
  Settings.set_value("ai_speed",s)
  assert_eq(Settings.walk_speed(12.0,false),12.0*s,"AI armies at %dx" % s)
  assert_eq(Settings.walk_speed(12.0,true),12.0,"your armies keep their own speed")
 for s in Settings.ARMY_SPEEDS:
  Settings.set_value("army_speed",s)
  assert_eq(Settings.walk_speed(12.0,true),12.0*s,"your armies at %dx" % s)
 assert_eq(Settings.AI_SPEEDS,[1,2,4])
 assert_eq(Settings.ARMY_SPEEDS,[1,2])

func test_ai_turn_bar_sets_and_saves_the_speed():
 var ui = build_ui()
 watch_signals(ui)
 ui.show_ai_turn_bar(true)
 assert_true(ui.ai_speed_buttons[1].button_pressed)
 ui.ai_speed_buttons[4].pressed.emit()
 assert_eq(Settings.ai_speed(),4)
 Settings.reload()
 assert_eq(Settings.ai_speed(),4,"saved in Settings")
 assert_true(ui.ai_speed_buttons[4].button_pressed)
 assert_false(ui.ai_speed_buttons[1].button_pressed)
 ui.ai_pause.button_pressed = true
 assert_signal_emitted_with_parameters(ui,"ai_pause_toggled",[true])
 ui.find_child("AiSkip",true,false).pressed.emit()
 assert_signal_emitted(ui,"ai_skip")
 ui.show_ai_turn_bar(true)
 assert_false(ui.ai_pause.button_pressed,"each AI turn starts unpaused")

func test_camera_settings_hold_follow_and_speeds():
 var ui = build_ui()
 ui.open_camera_settings()
 var follow: OptionButton = ui.dropdown.find_child("FollowAi",true,false)
 var ai: OptionButton = ui.dropdown.find_child("AiSpeed",true,false)
 var own: OptionButton = ui.dropdown.find_child("ArmySpeed",true,false)
 assert_eq(follow.item_count,3)
 assert_eq(follow.get_item_text(follow.selected),"Off")
 follow.item_selected.emit(2)
 assert_eq(Settings.follow_ai_mode(),"all")
 ai.item_selected.emit(1)
 assert_eq(Settings.ai_speed(),2)
 own.item_selected.emit(1)
 assert_eq(Settings.army_speed(),2)

func test_settings_panel_has_the_same_options():
 var p = SettingsPanel.new()
 add_child_autofree(p)
 var follow: OptionButton = p.find_child("FollowAi",true,false)
 assert_eq(follow.item_count,3)
 follow.item_selected.emit(1)
 assert_eq(Settings.follow_ai_mode(),"near")
 var ai: OptionButton = p.find_child("AiSpeed",true,false)
 ai.item_selected.emit(2)
 assert_eq(Settings.ai_speed(),4)
 assert_not_null(p.find_child("ArmySpeed",true,false))
