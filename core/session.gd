extends RefCounted
# Hand-over between scenes: the main menu (ui/main_menu.gd) and the campaign (Main.tscn). Loading
# a save or starting a campaign sets pending_state and reloads Main.tscn, which builds the whole map
# from that state. message carries a notice back to the menu (for example a failed load).

const MENU_SCENE = "res://ui/main_menu.tscn"
const CAMPAIGN_SCENE = "res://Main.tscn"

static var pending_state = null
static var pending_name := ""   # the save it came from ("" for a new campaign)
static var message := ""
static var started_at := 0  # Time.get_ticks_msec() when the hand-over began (load timing)
static var pending_view := {}  # the loaded save's camera (main.gd applies it once)

static func start(tree: SceneTree,state,from_save := "",view := {}):
 started_at = Time.get_ticks_msec()
 pending_view = view
 load("res://core/save_system.gd").wait_for_images()
 pending_state = state
 pending_name = from_save
 tree.change_scene_to_file(CAMPAIGN_SCENE)

static func to_menu(tree: SceneTree,notice := ""):
 message = notice
 load("res://core/save_system.gd").wait_for_images()
 tree.change_scene_to_file(MENU_SCENE)

static func take_view() -> Dictionary:
 var v = pending_view
 pending_view = {}
 return v
