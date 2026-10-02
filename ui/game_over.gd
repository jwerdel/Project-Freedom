extends Control
# Game over (constitution: the player's faction destroyed after its grace period): a defeat screen
# over the map with the chronicle's last word, and two ways on: load a save or the main menu.

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const LoadScreen = preload("res://ui/load_screen.gd")
const Session = preload("res://core/session.gd")
const SaveSystem = preload("res://core/save_system.gd")

var host # the campaign (main.gd): load_file(file)
var overlay: Control

func setup(campaign,faction: Dictionary,year: int):
 host = campaign
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var dim = ColorRect.new()
 dim.color = Color(0.03,0.02,0.02,0.82)
 dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(dim)
 var c = UiKit.colors(faction)
 var frame = Widgets.Framed.new("main",Color("8a2a20"),Color("1a1210",0.96))
 frame.anchor_left = 0.5
 frame.anchor_top = 0.5
 frame.anchor_right = 0.5
 frame.anchor_bottom = 0.5
 frame.offset_left = -330
 frame.offset_right = 330
 frame.offset_top = -210
 frame.offset_bottom = 210
 add_child(frame)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",12)
 v.alignment = BoxContainer.ALIGNMENT_CENTER
 frame.add_child(v)
 var em = Widgets.Emblem.new(faction,64)
 em.modulate = Color(0.6,0.55,0.55)
 em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
 v.add_child(em)
 var title = UiKit.header("Defeat",46,Color("ef8a6a"))
 title.name = "Title"
 title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(title)
 var sub = UiKit.header("%s is no more" % faction.name,22,Color("e9d3b0"))
 sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(sub)
 var text = UiKit.label("In the year %d the last banners of %s were furled. Without a settlement to hold, its armies went home, and the Grey Scribes closed its page in the chronicle." % [year,faction.name],15,UiKit.TEXT)
 text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 text.custom_minimum_size = Vector2(600,0)
 v.add_child(text)
 v.add_child(UiKit.divider(Color("8a2a20")))
 var row = HBoxContainer.new()
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 row.add_theme_constant_override("separation",16)
 for b in [["Load a save","LoadSave",_show_load],["Main menu","MainMenu",func(): Session.to_menu(get_tree())]]:
  var btn = Button.new()
  btn.name = b[1]
  btn.text = b[0]
  btn.custom_minimum_size = Vector2(220,48)
  btn.focus_mode = Control.FOCUS_NONE
  btn.add_theme_font_override("font",UiKit.head_font())
  btn.add_theme_font_size_override("font_size",18)
  btn.pressed.connect(b[2])
  row.add_child(btn)
 v.add_child(row)
 var note = UiKit.label("Autosaves from the last three turns are on the load screen.",13,UiKit.TEXT_DIM)
 note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(note)

func _show_load():
 overlay = LoadScreen.new()
 overlay.name = "Overlay"
 add_child(overlay)
 overlay.load_requested.connect(func(file): host.load_file(file))
 overlay.closed.connect(func():
  overlay.queue_free()
  overlay = null)

# The game is over: Esc does nothing here (pick Load or Main menu).
func _unhandled_input(e):
 if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and overlay == null: get_viewport().set_input_as_handled()
