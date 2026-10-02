extends GutTest
# TW:WH3 parity (docs/tw-ui-parity.md): province-wide recruitment with the drawer and greyed queued
# cards, cards that fit a full army, the movement preview (hold right click, no numbers), selection
# that never moves the camera, cycling at the current zoom, and End Turn warnings.

const UiData = preload("res://core/ui_data.gd")
const GameState = preload("res://core/game_state.gd")
const Armies = preload("res://core/armies.gd")
const Battles = preload("res://core/battles.gd")
const Buildings = preload("res://core/buildings.gd")
const WorldMap = preload("res://core/world_map.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const Cards = preload("res://ui/cards.gd")
const MovementOverlay = preload("res://ui/movement_overlay.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const SaveSystem = preload("res://core/save_system.gd")
const HOST = "aurek_host"

var studio

func before_each():
 studio = PortraitStudio.new()
 add_child_autofree(studio)

func build_ui(data) -> Control:
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(data,studio)
 return ui

func at(s,sid: String,offset := Vector2.ZERO,garrison := true):
 var p = WorldMap.settlement_position(sid)+offset
 s.army_state[HOST].position = [p.x,p.y]
 s.army_state[HOST].garrison = sid if garrison else ""

# --- Recruitment (Phase B) ----------------------------------------------------------------------

func test_recruitment_drawer_queues_greyed_cards_that_cancel_on_click():
 var data = UiData.new(GameState.from_data())
 at(data.state,"goldspire_rock")
 var ui = build_ui(data)
 ui.show_army(HOST,"Goldspire")
 var gold = data.resources().treasury
 ui.open_recruitment(HOST)
 var drawer = ui.bottom_box.find_child("RecruitDrawer",true,false)
 assert_not_null(drawer,"the drawer opens inside the army panel")
 var card = drawer.find_child("Recruit_peasant_levy",true,false)
 assert_not_null(card)
 card.pressed.emit()
 assert_eq(data.army(HOST).queue.size(),1,"clicking a card queues the unit")
 var queued = ui.bottom_box.find_child("Queued_0",true,false)
 assert_not_null(queued,"the queued unit appears in the army at once")
 assert_gt(queued.queued_turns,0,"greyed, with its turns left")
 queued.pressed.emit()
 assert_eq(data.army(HOST).queue.size(),0,"clicking the queued card cancels it")
 assert_eq(data.resources().treasury,gold,"full refund")
 await get_tree().process_frame # let the rebuilt panels free their old nodes

func test_recruit_button_says_why_outside_own_territory():
 var data = UiData.new(GameState.from_data())
 at(data.state,"greyhaven",Vector2(10,6),false) # Lannet's land
 var ui = build_ui(data)
 ui.show_army(HOST,"field")
 var b: Button = ui.bottom_box.find_child("Recruit",true,false)
 assert_true(b.disabled)
 var why: Label = ui.bottom_box.find_child("RecruitReason",true,false)
 assert_not_null(why)
 assert_string_contains(why.text,"own territory")

func test_recruiting_anywhere_in_the_province_uses_its_buildings():
 var s = GameState.from_data()
 # House Aurek holds the whole Greywater March; only Greyhaven trains archers.
 Battles.occupy(s,"greyhaven","house_aurek","")
 Battles.occupy(s,"willowmere","house_aurek","")
 if not "archers" in s.settlements.greyhaven.unlocks: s.settlements.greyhaven.unlocks.append("archers")
 s.settlements.willowmere.unlocks.erase("archers")
 s.treasury.house_aurek = 50000
 # Out in Willowmere's region, away from both settlements.
 var w = WorldMap.settlement_position("willowmere")
 var p = w+Vector2(10,8)
 assert_eq(WorldMap.region_at(p),"willowmere","precondition: Willowmere's region")
 s.army_state[HOST].position = [p.x,p.y]
 s.army_state[HOST].garrison = ""
 var r = Armies.can_recruit(s,HOST,"archers")
 assert_true(r.ok,str(r.reasons))
 assert_eq(r.settlement,"greyhaven","men come from the settlement whose building unlocks it")
 var pop = s.settlements.greyhaven.population
 assert_true(Armies.recruit(s,HOST,"archers").ok)
 assert_lt(s.settlements.greyhaven.population,pop)

func test_a_full_army_fits_the_panel():
 var data = UiData.new(GameState.from_data())
 at(data.state,"goldspire_rock")
 var a = data.state.army_state[HOST]
 while Armies.card_count(a)<Armies.max_units(): a.units.append({"unit":"spearmen","men":120,"max_men":120})
 var ui = build_ui(data)
 ui.show_army(HOST,"Goldspire")
 var row = ui.bottom_box.find_child("ArmyCards",true,false)
 var width = 0.0
 for c in row.get_children(): width += c.custom_minimum_size.x
 width += (row.get_child_count()-1)*CampaignUI.CARD_GAP
 assert_eq(row.get_child_count(),Armies.max_units()-1,"the general's card is in the left column")
 assert_lte(width,CampaignUI.ARMY_PANEL_WIDTH-40.0+0.5,"every card is visible without scrolling")

# --- Movement preview and map overlays (Phase C) -------------------------------------------------

func test_paths_and_blocked_markers_carry_no_numbers():
 var o = MovementOverlay.new()
 add_child_autofree(o)
 o.setup(func(_x,_z): return 0.0)
 o.show_path("preview",[Vector2(0,0),Vector2(30,0),Vector2(60,0),Vector2(90,0)],[0,0,1,2])
 for n in o.get_node("preview").get_children(): assert_false(n is Label3D,"no text on the path")
 o.show_blocked(Vector2(5,5),"Impassable terrain")
 var texts = o.get_node("preview").get_children().filter(func(n): return n is Label3D).map(func(n): return n.text)
 assert_eq(texts,["X"],"a blocked destination is a red cross only")

func test_attack_preview_names_the_target_and_plans_the_approach():
 var data = UiData.new(GameState.from_data())
 at(data.state,"greyhaven",Vector2(14,6),false)
 var r = data.attack_preview(HOST,WorldMap.settlement_position("greyhaven"))
 assert_eq(r.name,"Greyhaven")
 assert_true(r.plan.get("ok",false))

func test_end_turn_warnings_follow_state_and_settings():
 var data = UiData.new(GameState.from_data())
 var kinds = data.end_turn_warnings().map(func(w): return w.kind)
 assert_true("construction" in kinds,"something can be built at the start")
 assert_false("funds" in kinds)
 data.state.treasury.house_aurek = -10
 assert_true(data.end_turn_warnings().map(func(w): return w.kind).has("funds"))
 assert_eq(data.end_turn_warnings({"funds":false,"construction":false,"army_moves":false}),[],"each kind can be switched off")

# --- The map scene: camera and input (Phase C) ---------------------------------------------------

func test_map_selection_preview_and_end_turn_follow_tw():
 SaveSystem.dir = "user://test_saves" # End Turn autosaves; keep the player's saves untouched
 var main = load("res://Main.tscn").instantiate()
 add_child_autofree(main)
 await get_tree().process_frame
 # Selecting never moves or zooms the camera.
 var cam = [main.target,main.desired_distance,main.yaw]
 main.select_army(HOST)
 assert_eq([main.target,main.desired_distance,main.yaw],cam)
 # Cycling armies pans at the current zoom.
 main.desired_distance = 77.0
 main.cycle_selection(1)
 assert_eq(main.desired_distance,77.0)
 main.select_army(HOST)
 # A held right click previews; releasing gives the order; Esc during the hold cancels it.
 var screen = main.camera.unproject_position(main.ground(Vector2(-20,-10)))
 var press = InputEventMouseButton.new()
 press.button_index = MOUSE_BUTTON_RIGHT
 press.pressed = true
 press.position = screen
 main._unhandled_input(press)
 assert_true(main.rmb_held)
 var esc = InputEventKey.new()
 esc.keycode = KEY_ESCAPE
 esc.pressed = true
 main._unhandled_input(esc)
 assert_false(main.rmb_held,"Esc cancels the held preview")
 assert_eq(main.selected_army_id(),HOST,"and keeps the selection")
 main._unhandled_input(press)
 var release = InputEventMouseButton.new()
 release.button_index = MOUSE_BUTTON_RIGHT
 release.pressed = false
 release.position = screen
 var before = main.ui_data.army_movement(HOST).points
 main._unhandled_input(release)
 var m = main.ui_data.army_movement(HOST)
 assert_true(m.points<before or not m.order.is_empty(),"releasing gives the order")
 # The preview itself: no numbers; the movement bar shows the spend.
 main.preview_key = Vector2i(1<<20,0)
 var t = main.preview_move(Vector2(-118,-30))
 assert_eq(t,"","a valid move shows no tooltip text")
 assert_gt(main.ui.movement_bar.spend,0.0)
 main.cancel_move_preview()
 # End Turn: the button jumps to a pending warning before it ends the turn.
 var year = main.ui_data.state.year
 main.refresh_warnings()
 if not main.current_warnings().is_empty():
  main.end_turn_pressed()
  assert_eq(main.ui_data.state.year,year,"the first press jumps to the warning")
 main.end_turn(true)
 await get_tree().process_frame
 assert_eq(main.ui_data.state.year,year+1,"Shift+Enter ends the turn anyway")
 var d = DirAccess.open("user://test_saves")
 if d:
  for f in d.get_files(): DirAccess.remove_absolute("user://test_saves/"+f)
 SaveSystem.dir = SaveSystem.DIR
