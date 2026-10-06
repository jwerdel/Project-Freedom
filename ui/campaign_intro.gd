extends Control
# The illustrated intro of a new campaign (three panels per house, data/campaign_intro.json; the
# art slots show a placeholder frame until their images exist), then the court introduction (a
# placeholder until the character system). Next moves on, Skip jumps to the court; `finished`
# fires when the player continues to the campaign.

signal finished

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const WorldMap = preload("res://core/world_map.gd")

var house := {}
var court_text := ""
var page := 0
var box: VBoxContainer

func _init(faction_id: String):
 name = "CampaignIntro"
 var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_intro.json"))
 court_text = d.court
 for h in d.houses:
  if h.faction == faction_id: house = h
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP

func _ready():
 var bg = ColorRect.new()
 bg.color = Color("0e0b09")
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 box = VBoxContainer.new()
 box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 box.grow_horizontal = Control.GROW_DIRECTION_BOTH
 box.grow_vertical = Control.GROW_DIRECTION_BOTH
 box.custom_minimum_size = Vector2(900,0)
 box.add_theme_constant_override("separation",16)
 add_child(box)
 show_page(0)

func pages() -> int:
 return house.get("intro",[]).size()+1 # the panels, then the court

func show_page(i: int):
 page = i
 for c in box.get_children():
  box.remove_child(c)
  c.queue_free()
 var f = WorldMap.faction(house.get("faction",""))
 if i<house.intro.size():
  var p = house.intro[i]
  box.add_child(_art(p.art))
  var t = UiKit.label(p.text,20,UiKit.TEXT)
  t.name = "IntroText"
  t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  box.add_child(t)
 else:
  # The court introduction (placeholder until the character system, Part 4).
  var head = HBoxContainer.new()
  head.alignment = BoxContainer.ALIGNMENT_CENTER
  head.add_theme_constant_override("separation",14)
  head.add_child(Widgets.Emblem.new(f,70))
  var hv = VBoxContainer.new()
  hv.add_child(UiKit.header("The Court of %s" % f.get("name",""),26))
  hv.add_child(UiKit.label("%s, %s · %s" % [house.founder,house.epithet,", ".join(house.founder_traits)],16,Color("f1d79a")))
  head.add_child(hv)
  head.name = "CourtIntro"
  box.add_child(head)
  var t = UiKit.label(court_text,17,UiKit.TEXT)
  t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  box.add_child(t)
 var row = HBoxContainer.new()
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 row.add_theme_constant_override("separation",14)
 var last = i>=pages()-1
 if not last:
  var skip = Button.new()
  skip.name = "IntroSkip"
  skip.text = "Skip"
  skip.focus_mode = Control.FOCUS_NONE
  skip.custom_minimum_size = Vector2(140,42)
  skip.pressed.connect(show_page.bind(pages()-1))
  row.add_child(skip)
 var next = Button.new()
 next.name = "IntroNext"
 next.text = "To the campaign" if last else "Next"
 next.focus_mode = Control.FOCUS_NONE
 next.custom_minimum_size = Vector2(220,42)
 next.pressed.connect(func():
  if last: finished.emit()
  else: show_page(i+1))
 row.add_child(next)
 box.add_child(row)

# An illustration slot: the image when it exists, otherwise a framed placeholder.
func _art(path: String) -> Control:
 var frame = Widgets.Framed.new("main",Color("c9a45a"),Color("1d1712",0.95))
 frame.name = "IntroArt"
 frame.custom_minimum_size = Vector2(900,420)
 if ResourceLoader.exists(path):
  var tr = TextureRect.new()
  tr.texture = load(path)
  tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
  frame.add_child(tr)
 else:
  var l = UiKit.label("Illustration (placeholder)\n%s" % path.get_file(),15,Color(UiKit.TEXT_DIM,0.6))
  l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  frame.add_child(l)
 return frame
