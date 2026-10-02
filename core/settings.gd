extends RefCounted
# Player settings (placeholder set): window resolution, fullscreen, UI scale, following AI moves
# at End Turn, and the debug keys switch. Stored in user://settings.json; applied at startup by
# the main menu and the campaign.

const PATH = "user://settings.json"
const RESOLUTIONS = [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1600,1000),Vector2i(1920,1080)]
const UI_SCALES = [0.8,1.0,1.25,1.5]
const DEFAULTS = {"resolution":[1440,900],"fullscreen":false,"ui_scale":1.0,"debug_keys":true,"follow_ai_moves":true}

static var _current = null

static func current() -> Dictionary:
 if _current == null:
  _current = DEFAULTS.duplicate(true)
  if FileAccess.file_exists(PATH):
   var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
   if d is Dictionary:
    for k in DEFAULTS:
     if d.has(k): _current[k] = d[k]
 return _current

static func get_value(key: String):
 return current().get(key,DEFAULTS.get(key))

static func set_value(key: String,value):
 current()[key] = value
 var f = FileAccess.open(PATH,FileAccess.WRITE)
 if f: f.store_string(JSON.stringify(current(),"  "))

static func debug_keys() -> bool:
 return bool(get_value("debug_keys"))

# End Turn: the camera follows AI armies moving near your lands (Space or Esc skips).
static func follow_ai_moves() -> bool:
 return bool(get_value("follow_ai_moves"))

# Apply window mode, size and UI scale. Headless runs and captures keep the project defaults so
# screenshots stay comparable.
static func apply(tree: SceneTree):
 if DisplayServer.get_name() == "headless" or "--capture" in OS.get_cmdline_user_args(): return
 var win = tree.root
 win.content_scale_factor = float(get_value("ui_scale"))
 if bool(get_value("fullscreen")):
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
 else:
  if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
  var r = get_value("resolution")
  var size = Vector2i(int(r[0]),int(r[1]))
  if DisplayServer.window_get_size() != size:
   DisplayServer.window_set_size(size)
   var screen = DisplayServer.screen_get_usable_rect()
   DisplayServer.window_set_position(screen.position+(screen.size-size)/2)
