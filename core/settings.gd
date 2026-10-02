extends RefCounted
# Player settings (placeholder set): window resolution, fullscreen, UI scale, following AI moves
# at End Turn, AI turn speed, your armies' animation speed, End Turn warnings and the debug keys
# switch. Stored in user://settings.json; applied at startup by the main menu and the campaign.

const PATH = "user://settings.json"
const RESOLUTIONS = [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1600,1000),Vector2i(1920,1080)]
const UI_SCALES = [0.8,1.0,1.25,1.5]
const DEFAULTS = {"resolution":[1440,900],"fullscreen":false,"ui_scale":1.0,"debug_keys":true,
 "follow_ai":"off","ai_speed":1,"army_speed":1,
 "warn_funds":true,"warn_construction":true,"warn_army_moves":true}

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

# Following AI movements at End Turn (owner, docs/tw-ui-parity.md L10): off (default), only the
# armies whose path comes near your territory or armies, or all of them. Space or Esc skips.
const FOLLOW_MODES = [["off","Off"],["near","Only near my territory"],["all","All"]]
static func follow_ai_mode() -> String:
 var m = str(get_value("follow_ai"))
 return m if FOLLOW_MODES.any(func(f): return f[0] == m) else "off"

static func should_follow(mode: String,near: bool) -> bool:
 return mode == "all" or (mode == "near" and near)

# AI turn speed (owner: 1x, 2x, 4x; TW:WH3 has only play and fast-forward) and your armies'
# animation speed (TW:WH3's R: 1x or 2x). Presentation only: they never change what happens.
const AI_SPEEDS = [1,2,4]
const ARMY_SPEEDS = [1,2]
static func ai_speed() -> int:
 var s = int(get_value("ai_speed"))
 return s if s in AI_SPEEDS else 1

static func army_speed() -> int:
 var s = int(get_value("army_speed"))
 return s if s in ARMY_SPEEDS else 1

# Map walking speed of an army figure: your armies at the animation speed, others at the AI speed.
static func walk_speed(base: float,player_owned: bool) -> float:
 return base*float(army_speed() if player_owned else ai_speed())

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

# Which End Turn warnings show (TW:WH3's notification settings), keyed like UiData.WARNINGS.
static func end_turn_warnings() -> Dictionary:
 return {"funds":bool(get_value("warn_funds")),"construction":bool(get_value("warn_construction")),"army_moves":bool(get_value("warn_army_moves"))}

# Forget the loaded values so the next read comes from the file again (tests, external edits).
static func reload():
 _current = null
