extends Control
# Pause menu (Esc on the campaign map when no panel is open): Resume, Save, Load, Settings, Exit to
# main menu, Quit. Exiting or quitting with unsaved progress asks first. host is the campaign
# (main.gd): save_named(name), load_file(file), unsaved, ui_data.

signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const LoadScreen = preload("res://ui/load_screen.gd")
const SettingsPanel = preload("res://ui/settings_panel.gd")
const Session = preload("res://core/session.gd")

var host
var trim := Color("c9a45a")
var buttons: VBoxContainer
var save_box: VBoxContainer
var save_name: LineEdit
var confirm_box: VBoxContainer
var confirm_text: Label
var confirm_action := Callable()
var overlay: Control

func setup(campaign):
 host = campaign
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var dim = ColorRect.new()
 dim.color = Color(0,0,0,0.55)
 dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(dim)
 var frame = Widgets.Framed.new("main",trim,Color("1d1712",0.97))
 frame.anchor_left = 0.5
 frame.anchor_top = 0.5
 frame.anchor_right = 0.5
 frame.anchor_bottom = 0.5
 frame.offset_left = -190
 frame.offset_right = 190
 frame.offset_top = -215
 frame.offset_bottom = 215
 add_child(frame)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",8)
 frame.add_child(v)
 var title = UiKit.header("Paused",26)
 title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(title)
 var r = host.ui_data.resources()
 var sub = UiKit.label("%s · Year %d" % [host.ui_data.player_faction().name,r.year],14,UiKit.TEXT_DIM)
 sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(sub)
 v.add_child(UiKit.divider(trim))
 buttons = VBoxContainer.new()
 buttons.add_theme_constant_override("separation",8)
 v.add_child(buttons)
 for b in [["Resume",func(): closed.emit()],["Save",_show_save],["Load",_show_load],["Settings",_show_settings],
  ["Exit to main menu",func(): _guard("Exit to the main menu?",func(): Session.to_menu(get_tree()))],
  ["Quit",func(): _guard("Quit the game?",func(): get_tree().quit())]]:
  var btn = Button.new()
  btn.name = b[0].replace(" ","")
  btn.text = b[0]
  btn.custom_minimum_size = Vector2(320,44)
  btn.focus_mode = Control.FOCUS_NONE
  btn.pressed.connect(b[1])
  buttons.add_child(btn)
 # Save: a name field (defaults to the faction and year) and Save / Cancel.
 save_box = VBoxContainer.new()
 save_box.name = "SaveBox"
 save_box.visible = false
 save_box.add_child(UiKit.label("Save name",15))
 save_name = LineEdit.new()
 save_name.name = "SaveName"
 save_name.custom_minimum_size = Vector2(320,36)
 save_name.text_submitted.connect(func(_t): _do_save())
 save_box.add_child(save_name)
 var srow = HBoxContainer.new()
 var sb = Button.new()
 sb.name = "ConfirmSave"
 sb.text = "Save"
 sb.focus_mode = Control.FOCUS_NONE
 sb.pressed.connect(_do_save)
 srow.add_child(sb)
 var sc = Button.new()
 sc.text = "Cancel"
 sc.focus_mode = Control.FOCUS_NONE
 sc.pressed.connect(_show_buttons)
 srow.add_child(sc)
 save_box.add_child(srow)
 v.add_child(save_box)
 # Unsaved progress warning.
 confirm_box = VBoxContainer.new()
 confirm_box.name = "ConfirmBox"
 confirm_box.visible = false
 confirm_text = UiKit.label("",15,Color("f1d79a"))
 confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 confirm_text.custom_minimum_size = Vector2(320,0)
 confirm_box.add_child(confirm_text)
 for b in [["Save and continue","SaveFirst",func():
   _show_save()
   save_box.set_meta("then",confirm_action)],
  ["Continue without saving","Discard",func(): confirm_action.call()],["Cancel","CancelExit",_show_buttons]]:
  var btn = Button.new()
  btn.name = b[1]
  btn.text = b[0]
  btn.custom_minimum_size = Vector2(320,40)
  btn.focus_mode = Control.FOCUS_NONE
  btn.pressed.connect(b[2])
  confirm_box.add_child(btn)
 v.add_child(confirm_box)

func _show_buttons():
 buttons.visible = true
 save_box.visible = false
 confirm_box.visible = false
 save_box.remove_meta("then")

func _show_save():
 buttons.visible = false
 confirm_box.visible = false
 save_box.visible = true
 var r = host.ui_data.resources()
 save_name.text = "%s, year %d" % [host.ui_data.player_faction().name,r.year]
 if DisplayServer.get_name() != "headless": save_name.grab_focus()

func _do_save():
 var name = save_name.text.strip_edges()
 if name == "": return
 var r = host.save_named(name) # the thumbnail is drawn without the interface
 if r.ok and save_box.has_meta("then"):
  var then: Callable = save_box.get_meta("then")
  then.call()
  return
 _show_buttons()

# Run action, asking first when the campaign has unsaved progress.
func _guard(question: String,action: Callable):
 if not host.unsaved:
  action.call()
  return
 confirm_action = action
 confirm_text.text = "%s Progress since your last save will be lost." % question
 buttons.visible = false
 save_box.visible = false
 confirm_box.visible = true

func _show_load():
 _open(LoadScreen.new())
 overlay.load_requested.connect(func(file): host.load_file(file))

func _show_settings():
 _open(SettingsPanel.new())

func _open(c: Control):
 overlay = c
 overlay.name = "Overlay"
 add_child(overlay)
 overlay.closed.connect(func():
  overlay.queue_free()
  overlay = null)

func _unhandled_input(e):
 if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and overlay == null:
  get_viewport().set_input_as_handled()
  if buttons.visible: closed.emit()
  else: _show_buttons()
