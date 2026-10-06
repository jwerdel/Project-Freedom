extends Control
# Main menu on launch: Continue (the latest save), New Campaign, Load, Settings, Quit. The
# campaign starts on Varos after the faction selection and intro (Stage A). Command-line runs that
# need the campaign directly (captures, the self-test, the movement-grid bake, --seed) skip the
# menu unless --menu is given.

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const WorldMap = preload("res://core/world_map.gd")
const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const Session = preload("res://core/session.gd")
const Settings = preload("res://core/settings.gd")
const LoadScreen = preload("res://ui/load_screen.gd")
const SettingsPanel = preload("res://ui/settings_panel.gd")
const CAMPAIGN_FLAGS = ["--capture","--self-test","--bake-movement-grid","--campaign"]
const CREDITS = "Icons by Lorc, Delapouite and contributors, game-icons.net (CC BY 3.0) · 3D models by Quaternius and Kenney (CC0) · Textures: Poly Haven (CC0) · Fonts: SIL OFL · Full list: ASSETS.md"

var trim := Color("c9a45a")
var overlay: Control
var notice: Label
var continue_button: Button
var frames := 0

func _ready():
 var args = Array(OS.get_cmdline_user_args())
 # The release benchmark export (preset "Windows Benchmark", feature tag "benchmark") runs the scale
 # benchmark instead of the menu (scripts/scale_bench.gd).
 if OS.has_feature("benchmark"):
  get_tree().root.add_child.call_deferred(load("res://scripts/scale_bench.gd").new())
  return
 var direct = args.any(func(a): return a in CAMPAIGN_FLAGS or a.begins_with("--seed="))
 if direct and not "--menu" in args:
  get_tree().change_scene_to_file.call_deferred(Session.CAMPAIGN_SCENE)
  return
 if args.has("--capture"): SaveSystem.dir = "user://capture_saves"
 Settings.apply(get_tree())
 var faction = WorldMap.faction("house_aurek")
 theme = UiKit.theme_for(faction)
 trim = UiKit.colors(faction).trim
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _build()
 add_child(load("res://ui/rich_tooltip.gd").new())
 if args.has("--load-screen"): _show_load()
 if args.has("--settings"): _show_settings()
 for a in args:
  if a.begins_with("--menu-load="): _load.call_deferred(a.get_slice("=",1)) # captures: the full load path
  # Captures: --faction-select opens the selection (=<faction> picks a house); --intro=<faction> the intro.
  if a.begins_with("--faction-select"):
   _new_campaign.call_deferred()
   if "=" in a: (func(): (find_child("FactionSelect",true,false) as Control).call("select",a.get_slice("=",1))).call_deferred()
  if a.begins_with("--intro="):
   MapRegistry.set_active(MapRegistry.CAMPAIGN)
   var st = GameState.from_data()
   st.player_faction = a.get_slice("=",1)
   _intro.call_deferred(st)

func _build():
 # Backdrop: the latest saved view of the campaign (core/save_system.gd), darkened.
 var bg = ColorRect.new()
 bg.color = Color("120e0b")
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var latest = SaveSystem.latest()
 var art = TextureRect.new()
 art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
 art.modulate = Color(0.55,0.5,0.45)
 if FileAccess.file_exists(SaveSystem.backdrop_path()):
  var img = Image.load_from_file(SaveSystem.backdrop_path())
  if img: art.texture = ImageTexture.create_from_image(img)
 add_child(art)
 # No saved view yet: the house emblem, large and faint, on the right.
 if art.texture == null:
  var em = Widgets.Emblem.new(WorldMap.faction("house_aurek"),420)
  em.modulate = Color(1,1,1,0.18)
  em.anchor_left = 1.0
  em.anchor_right = 1.0
  em.anchor_top = 0.5
  em.anchor_bottom = 0.5
  em.offset_left = -620
  em.offset_right = -200
  em.offset_top = -240
  em.offset_bottom = 240
  add_child(em)
 var shade = Shade.new()
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 # Title, top left.
 var title_box = VBoxContainer.new()
 title_box.position = Vector2(90,90)
 var title = UiKit.header("Project Freedom",64)
 title_box.add_child(title)
 title_box.add_child(UiKit.header("The Greywater March",26,Color("d9c398")))
 add_child(title_box)
 # Button column, left, in a framed panel (Total War style).
 var frame = Widgets.Framed.new("main",trim,Color("1d1712",0.88))
 frame.anchor_top = 0.5
 frame.anchor_bottom = 0.5
 frame.offset_left = 90
 frame.offset_right = 460
 frame.offset_top = -170
 frame.offset_bottom = 250
 add_child(frame)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",10)
 frame.add_child(v)
 continue_button = _button(v,"Continue",_continue)
 continue_button.disabled = latest.is_empty()
 var cont_info = UiKit.label("%s · Year %d · %s" % [latest.get("faction_name",""),int(latest.get("year",0)),latest.get("saved_text","")] if not latest.is_empty() else "No saved campaign yet",13,UiKit.TEXT_DIM)
 cont_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(cont_info)
 var nc = _button(v,"New Campaign",_new_campaign)
 nc.tooltip_text = "Choose one of the three great houses of Aldryn and begin on Varos."
 var nci = UiKit.label("House Varn, House Varrenus or the Aurekids, on Varos",13,UiKit.TEXT_DIM)
 nci.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(nci)
 _button(v,"Load",_show_load)
 _button(v,"Settings",_show_settings)
 _button(v,"Quit",func():
  SaveSystem.wait_for_images()
  get_tree().quit())
 notice = UiKit.label(Session.message,15,Color("ef8a6a"))
 notice.anchor_top = 1.0
 notice.anchor_bottom = 1.0
 notice.offset_left = 90
 notice.offset_top = -80
 notice.offset_right = 1200
 notice.offset_bottom = -50
 add_child(notice)
 Session.message = ""
 var ver = UiKit.label("Godot 4.7.2 · personal prototype",12,Color(UiKit.TEXT_DIM,0.6))
 ver.anchor_left = 1.0
 ver.anchor_right = 1.0
 ver.anchor_top = 1.0
 ver.anchor_bottom = 1.0
 ver.offset_left = -300
 ver.offset_top = -36
 ver.offset_right = -20
 ver.offset_bottom = -14
 ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 add_child(ver)
 # Credits (ASSETS.md): CC BY assets need attribution in the game itself.
 var credits = UiKit.label(CREDITS,11,Color(UiKit.TEXT_DIM,0.55))
 credits.name = "Credits"
 credits.anchor_top = 1.0
 credits.anchor_bottom = 1.0
 credits.offset_left = 20
 credits.offset_top = -36
 credits.offset_right = 1100
 credits.offset_bottom = -14
 add_child(credits)

func _button(parent: Control,text: String,cb: Callable) -> Button:
 var b = Button.new()
 b.name = text.replace(" ","")
 b.text = text
 b.custom_minimum_size = Vector2(330,50)
 b.add_theme_font_override("font",UiKit.head_font())
 b.add_theme_font_size_override("font_size",19)
 b.focus_mode = Control.FOCUS_NONE
 b.pressed.connect(cb)
 parent.add_child(b)
 return b

func _continue():
 var latest = SaveSystem.latest()
 if not latest.is_empty(): _load(latest.file)

const FactionSelect = preload("res://ui/faction_select.gd")
const CampaignIntro = preload("res://ui/campaign_intro.gd")
const MapRegistry = preload("res://core/map_registry.gd")

# New Campaign: Varos, the faction selection, the illustrated intro and the court, then the campaign.
func _new_campaign():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 var state = GameState.new_campaign()
 var sel = FactionSelect.new(state)
 add_child(sel)
 sel.cancelled.connect(func():
  sel.queue_free()
  MapRegistry.set_active(MapRegistry.DEFAULT))
 sel.chosen.connect(func(f: String):
  state.player_faction = f
  sel.queue_free()
  _intro(state))

func _intro(state):
 var intro = CampaignIntro.new(state.player_faction)
 add_child(intro)
 if "--intro-court" in OS.get_cmdline_user_args(): intro.show_page(intro.pages()-1)
 intro.finished.connect(func(): Session.start(get_tree(),state))

func _load(file: String):
 var r = SaveSystem.load_save(file)
 if "--capture" in OS.get_cmdline_user_args(): print("LOAD_FILE_MS %.2f" % r.get("ms",0.0))
 if not r.ok:
  notice.text = r.error
  if overlay: overlay.queue_free()
  overlay = null
  return
 Session.start(get_tree(),r.state,r.meta.get("name",file),r.get("view",{}))

func _show_load():
 _open(LoadScreen.new())
 overlay.load_requested.connect(_load)

func _show_settings():
 _open(SettingsPanel.new())

func _open(c: Control):
 if overlay: overlay.queue_free()
 overlay = c
 add_child(overlay)
 overlay.closed.connect(func():
  overlay.queue_free()
  overlay = null
  # Continue may have lost its save (deleted on the load screen).
  continue_button.disabled = SaveSystem.latest().is_empty())

# Captures (--capture --menu): save the frame as captures/<--name= or main_menu>.png and quit.
func _process(_delta):
 if not "--capture" in OS.get_cmdline_user_args(): return
 frames += 1
 if frames == 60:
  await RenderingServer.frame_post_draw
  var name_v = "main_menu"
  for a in OS.get_cmdline_user_args():
   if a.begins_with("--name="): name_v = a.get_slice("=",1)
  var folder = ProjectSettings.globalize_path("res://captures")
  DirAccess.make_dir_recursive_absolute(folder)
  var path = folder+"/"+name_v+".png"
  var result = get_viewport().get_texture().get_image().save_png(path)
  print("CAPTURE ",path," result=",result)
  get_tree().quit(0 if result == OK else 1)

# Dark vignette toward the left, so the title and buttons read over any backdrop.
class Shade extends TextureRect:
 func _ready():
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  var g = Gradient.new()
  g.set_color(0,Color(0.05,0.035,0.025,0.9))
  g.set_color(1,Color(0.05,0.035,0.025,0.2))
  var t = GradientTexture2D.new()
  t.gradient = g
  t.width = 256
  t.height = 4
  texture = t
