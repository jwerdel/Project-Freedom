extends Control
# Settings (placeholder set): resolution, fullscreen, UI scale, following AI movements, AI turn
# speed, your armies' speed, End Turn warnings and the debug keys switch. Changes apply at once and are kept in user://settings.json (core/settings.gd).

signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const Settings = preload("res://core/settings.gd")

var trim := Color("c9a45a")

func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var dim = ColorRect.new()
 dim.color = Color(0,0,0,0.6)
 dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(dim)
 var frame = Widgets.Framed.new("main",trim,Color("1d1712",0.97))
 frame.anchor_left = 0.5
 frame.anchor_top = 0.5
 frame.anchor_right = 0.5
 frame.anchor_bottom = 0.5
 frame.offset_left = -260
 frame.offset_right = 260
 frame.offset_top = -320
 frame.offset_bottom = 320
 add_child(frame)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",10)
 frame.add_child(v)
 v.add_child(UiKit.header("Settings",24))
 v.add_child(UiKit.divider(trim))
 var grid = GridContainer.new()
 grid.columns = 2
 grid.add_theme_constant_override("h_separation",20)
 grid.add_theme_constant_override("v_separation",10)
 v.add_child(grid)
 grid.add_child(UiKit.label("Resolution",16))
 var res = OptionButton.new()
 res.name = "Resolution"
 res.focus_mode = Control.FOCUS_NONE
 var cur = Settings.get_value("resolution")
 for i in Settings.RESOLUTIONS.size():
  var r = Settings.RESOLUTIONS[i]
  res.add_item("%d × %d" % [r.x,r.y])
  if r.x == int(cur[0]) and r.y == int(cur[1]): res.select(i)
 res.item_selected.connect(func(i):
  var r = Settings.RESOLUTIONS[i]
  Settings.set_value("resolution",[r.x,r.y])
  Settings.apply(get_tree()))
 grid.add_child(res)
 grid.add_child(UiKit.label("Fullscreen",16))
 var fs = CheckBox.new()
 fs.name = "Fullscreen"
 fs.focus_mode = Control.FOCUS_NONE
 fs.button_pressed = bool(Settings.get_value("fullscreen"))
 fs.toggled.connect(func(on):
  Settings.set_value("fullscreen",on)
  Settings.apply(get_tree()))
 grid.add_child(fs)
 grid.add_child(UiKit.label("UI scale",16))
 var scale_opt = OptionButton.new()
 scale_opt.name = "UiScale"
 scale_opt.focus_mode = Control.FOCUS_NONE
 for i in Settings.UI_SCALES.size():
  scale_opt.add_item("%d%%" % int(round(Settings.UI_SCALES[i]*100)))
  if is_equal_approx(Settings.UI_SCALES[i],float(Settings.get_value("ui_scale"))): scale_opt.select(i)
 scale_opt.item_selected.connect(func(i):
  Settings.set_value("ui_scale",Settings.UI_SCALES[i])
  Settings.apply(get_tree()))
 grid.add_child(scale_opt)
 _option(grid,"FollowAi","Follow AI movements",Settings.FOLLOW_MODES,Settings.follow_ai_mode(),"follow_ai")
 _option(grid,"AiSpeed","AI turn speed",Settings.AI_SPEEDS.map(func(s): return [s,"%dx" % s]),Settings.ai_speed(),"ai_speed")
 _option(grid,"ArmySpeed","Your armies' speed (R)",Settings.ARMY_SPEEDS.map(func(s): return [s,"%dx" % s]),Settings.army_speed(),"army_speed")
 for wk in [["warn_funds","End Turn warning: low funds"],["warn_construction","End Turn warning: construction available"],["warn_army_moves","End Turn warning: army can still move"]]:
  grid.add_child(UiKit.label(wk[1],16))
  var cb = CheckBox.new()
  cb.name = wk[0]
  cb.focus_mode = Control.FOCUS_NONE
  cb.button_pressed = bool(Settings.get_value(wk[0]))
  cb.toggled.connect(func(on): Settings.set_value(wk[0],on))
  grid.add_child(cb)
 grid.add_child(UiKit.label("Debug keys (F5-F8, L)",16))
 var dbg = CheckBox.new()
 dbg.name = "DebugKeys"
 dbg.focus_mode = Control.FOCUS_NONE
 dbg.button_pressed = Settings.debug_keys()
 dbg.toggled.connect(func(on): Settings.set_value("debug_keys",on))
 grid.add_child(dbg)
 var note = UiKit.label("Placeholder settings. Graphics and audio options come later.",13,UiKit.TEXT_DIM)
 v.add_child(note)
 var spacer = Control.new()
 spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
 v.add_child(spacer)
 var back = Button.new()
 back.name = "Back"
 back.text = "Back"
 back.focus_mode = Control.FOCUS_NONE
 back.pressed.connect(func(): closed.emit())
 v.add_child(back)

func _unhandled_input(e):
 if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
  get_viewport().set_input_as_handled()
  closed.emit()

# A labelled option list stored under `key`: options are [value, text].
func _option(grid: GridContainer,node_name: String,label: String,options: Array,current,key: String):
 grid.add_child(UiKit.label(label,16))
 var o = OptionButton.new()
 o.name = node_name
 o.focus_mode = Control.FOCUS_NONE
 for i in options.size():
  o.add_item(options[i][1])
  if options[i][0] == current: o.select(i)
 o.item_selected.connect(func(i): Settings.set_value(key,options[i][0]))
 grid.add_child(o)
