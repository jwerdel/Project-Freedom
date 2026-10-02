extends Control
# Load screen (main menu and pause menu): every save, newest first, with its thumbnail, name,
# faction, year and date. Load or delete (delete asks first). Emits load_requested(file).

signal load_requested(file: String)
signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const SaveSystem = preload("res://core/save_system.gd")
const KIND = {"manual":"","auto":"Autosave","quick":"Quicksave","damaged":"Damaged"}

var trim := Color("c9a45a")
var list: VBoxContainer
var empty: Label

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
 frame.offset_left = -430
 frame.offset_right = 430
 frame.offset_top = -320
 frame.offset_bottom = 320
 add_child(frame)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",8)
 frame.add_child(v)
 var head = HBoxContainer.new()
 var title = UiKit.header("Load Campaign",24)
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 var back = Button.new()
 back.name = "Back"
 back.text = "Back"
 back.focus_mode = Control.FOCUS_NONE
 back.pressed.connect(func(): closed.emit())
 head.add_child(back)
 v.add_child(head)
 v.add_child(UiKit.divider(trim))
 var scroll = ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 list = VBoxContainer.new()
 list.name = "Saves"
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 list.add_theme_constant_override("separation",6)
 scroll.add_child(list)
 v.add_child(scroll)
 empty = UiKit.label("No saves yet. Saves appear here after End Turn (autosave), Ctrl+S, or Save in the pause menu.",15,UiKit.TEXT_DIM)
 empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 v.add_child(empty)
 refresh()

func refresh():
 for c in list.get_children(): c.queue_free()
 var saves = SaveSystem.list()
 empty.visible = saves.is_empty()
 for m in saves: list.add_child(_row(m))

func _row(m: Dictionary) -> Control:
 var row = PanelContainer.new()
 row.name = "Save_"+m.file
 row.add_theme_stylebox_override("panel",UiKit.flat(Color("2a2119"),8))
 var h = HBoxContainer.new()
 h.add_theme_constant_override("separation",12)
 row.add_child(h)
 var pic = TextureRect.new()
 pic.custom_minimum_size = Vector2(160,100)
 pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
 if m.thumb != "":
  var img = Image.load_from_file(m.thumb)
  if img: pic.texture = ImageTexture.create_from_image(img)
 if pic.texture == null:
  var ph = ColorRect.new()
  ph.color = Color("3a3026")
  ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  pic.add_child(ph)
 h.add_child(pic)
 var info = VBoxContainer.new()
 info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 info.alignment = BoxContainer.ALIGNMENT_CENTER
 var kind = KIND.get(m.get("kind","manual"),"")
 info.add_child(UiKit.header(str(m.get("name",m.file)),17))
 info.add_child(UiKit.label("%s · Year %d" % [m.get("faction_name",""),int(m.get("year",0))],15))
 info.add_child(UiKit.label("%s%s" % [m.get("saved_text",""),("  ·  "+kind) if kind != "" else ""],13,UiKit.TEXT_DIM))
 h.add_child(info)
 var buttons = VBoxContainer.new()
 buttons.alignment = BoxContainer.ALIGNMENT_CENTER
 var load_b = Button.new()
 load_b.name = "Load"
 load_b.text = "Load"
 load_b.focus_mode = Control.FOCUS_NONE
 load_b.disabled = m.get("kind") == "damaged"
 load_b.pressed.connect(func(): load_requested.emit(m.file))
 buttons.add_child(load_b)
 var del = Button.new()
 del.name = "Delete"
 del.text = "Delete"
 del.focus_mode = Control.FOCUS_NONE
 buttons.add_child(del)
 # Delete asks first, in place: the buttons turn into "Delete this save? Yes / No".
 var confirm = HBoxContainer.new()
 confirm.name = "Confirm"
 confirm.visible = false
 confirm.add_child(UiKit.label("Delete this save?",14,Color("ef8a6a")))
 var yes = Button.new()
 yes.name = "Yes"
 yes.text = "Yes"
 yes.focus_mode = Control.FOCUS_NONE
 yes.pressed.connect(func():
  SaveSystem.delete(m.file)
  refresh())
 confirm.add_child(yes)
 var no = Button.new()
 no.text = "No"
 no.focus_mode = Control.FOCUS_NONE
 no.pressed.connect(func():
  confirm.visible = false
  buttons.visible = true)
 confirm.add_child(no)
 del.pressed.connect(func():
  buttons.visible = false
  confirm.visible = true)
 h.add_child(buttons)
 h.add_child(confirm)
 return row

func _unhandled_input(e):
 if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
  get_viewport().set_input_as_handled()
  closed.emit()
