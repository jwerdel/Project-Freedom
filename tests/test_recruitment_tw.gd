extends GutTest
# TW:WH3 recruitment (docs/tw-ui-parity.md section 14): the panel stays open across clicks (the
# playtest bug), local and global recruitment, recruitment capacity with overflow turns, the
# green / blue / orange banners, and full refunds on cancel.

const UiData = preload("res://core/ui_data.gd")
const GameState = preload("res://core/game_state.gd")
const Armies = preload("res://core/armies.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const Cards = preload("res://ui/cards.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const SaveSystem = preload("res://core/save_system.gd")
const HOST = "aurek_host"

# Stands in for main.gd's _unhandled_input: records mouse buttons the interface did not consume.
class Catcher extends Node:
 var seen = []
 func _unhandled_input(e):
  if e is InputEventMouseButton: seen.append(e.pressed)

func at(s,sid: String,garrison := true):
 var p = WorldMap.settlement_position(sid)
 s.army_state[HOST].position = [p.x,p.y]
 s.army_state[HOST].garrison = sid if garrison else ""

func rich_state():
 var s = GameState.from_data()
 s.treasury.house_aurek = 100000
 at(s,"goldspire_rock")
 return s

func build_ui(data) -> Control:
 var studio = PortraitStudio.new()
 add_child_autofree(studio)
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(data,studio)
 return ui

# --- The playtest bug -----------------------------------------------------------------------------

func click(sv: SubViewport,pos: Vector2):
 for pressed in [true,false]:
  var e = InputEventMouseButton.new()
  e.button_index = MOUSE_BUTTON_LEFT
  e.pressed = pressed
  e.position = pos
  e.global_position = pos
  sv.push_input(e)
  await get_tree().process_frame

func test_panel_stays_open_across_several_clicks_and_no_click_reaches_the_map():
 # Real mouse input through a SubViewport (headless Godot routes GUI input only there).
 var sv = SubViewport.new()
 sv.size = Vector2i(1600,1000)
 add_child_autofree(sv)
 var studio = PortraitStudio.new()
 add_child_autofree(studio)
 var catcher = Catcher.new()
 sv.add_child(catcher)
 var data = UiData.new(rich_state())
 var ui = CampaignUI.new()
 sv.add_child(ui)
 ui.setup(data,studio)
 ui.show_army(HOST,"Goldspire")
 ui.open_recruitment(HOST)
 for i in 4: await get_tree().process_frame
 for n in 3:
  var card = ui.bottom_box.find_child("Recruit_peasant_levy",true,false)
  await click(sv,card.get_global_rect().get_center())
  for i in 2: await get_tree().process_frame
 assert_eq(data.state.army_state[HOST].queue.size(),3,"three clicks queue three units")
 assert_true(ui.recruitment_visible(),"the panel stays open")
 # The bug: the press reached the map too, so press + release made a "click on empty ground" that
 # deselected the army. Presses are now consumed; the orphan releases (the card was rebuilt
 # under the mouse) still arrive, and main.gd ignores a release whose press it never saw (next test).
 assert_false(catcher.seen.has(true),"no press falls through to the map")
 ui.bottom_box.find_child("CloseRecruitment",true,false).pressed.emit()
 assert_false(ui.recruitment_visible(),"its Close button closes it")

func test_a_release_without_a_map_press_is_not_a_map_click():
 SaveSystem.dir = "user://test_saves"
 var main = load("res://Main.tscn").instantiate()
 add_child_autofree(main)
 await get_tree().process_frame
 main.select_army(HOST)
 main.ui.open_recruitment(HOST)
 # An orphan release (its press was taken by the interface) used to count as a click on the map.
 main.press_pos = Vector2(400,300)
 var release = InputEventMouseButton.new()
 release.button_index = MOUSE_BUTTON_LEFT
 release.pressed = false
 release.position = Vector2(400,300)
 main._unhandled_input(release)
 assert_eq(main.selected_army_id(),HOST)
 assert_true(main.ui.recruitment_visible())
 SaveSystem.dir = SaveSystem.DIR

func test_esc_and_deselect_close_the_panel():
 var ui = build_ui(UiData.new(rich_state()))
 ui.show_army(HOST,"Goldspire")
 ui.open_recruitment(HOST)
 assert_true(ui.close_top_panel())
 assert_false(ui.recruitment_visible(),"Esc closes it")
 ui.open_recruitment(HOST)
 ui.clear_selection()
 assert_false(ui.recruitment_visible(),"deselecting closes it")

# --- Capacity and overflow ------------------------------------------------------------------------

func test_capacity_and_overflow_turns():
 var s = rich_state()
 var cap = Armies.capacity(s,HOST)
 assert_eq(cap,int(Armies.data().recruitment.capacity.per_turn))
 assert_eq(cap,3)
 var base = int(UnitTypes.get_type("peasant_levy").recruitment.turns)
 var turns = []
 var kinds = []
 for i in 7:
  var r = Armies.recruit(s,HOST,"peasant_levy")
  assert_true(r.ok,str(r.reasons))
  turns.append(r.turns)
  kinds.append(r.kind)
 assert_eq(turns,[base,base,base,base+1,base+1,base+1,base+2],"each started batch over capacity adds a turn")
 assert_eq(kinds,["local","local","local","overflow","overflow","overflow","overflow"])
 assert_true(Armies.options(s,HOST)[0].overflow,"the panel shows the next recruit's extra turns")

func test_capacity_hooks_raise_it():
 var s = rich_state()
 s.army_state[HOST].commander.recruit_capacity = 2 # a trait or skill (character system hook)
 assert_eq(Armies.capacity(s,HOST),5)

func test_cancel_refunds_in_full_and_overflow_moves_up():
 var s = rich_state()
 var gold = s.treasury.house_aurek
 var pop = s.settlements.goldspire_rock.population
 for i in 4: Armies.recruit(s,HOST,"peasant_levy")
 assert_eq(Armies.queue_kind(s.army_state[HOST].queue[3]),"overflow")
 var r = Armies.cancel_recruit(s,HOST,0)
 assert_eq(r.gold,250)
 var q = s.army_state[HOST].queue
 assert_eq(Armies.queue_kind(q[2]),"local","the overflow unit takes the freed slot")
 assert_eq(int(q[2].turns_left),1)
 while not q.is_empty(): Armies.cancel_recruit(s,HOST,0)
 assert_eq(s.treasury.house_aurek,gold,"every gold piece back")
 assert_eq(s.settlements.goldspire_rock.population,pop,"every man back")

# --- Global recruitment ---------------------------------------------------------------------------

func test_global_recruitment_works_abroad_at_double_cost_and_turns():
 var s = rich_state()
 at(s,"greyhaven",false) # House Lannet's region: no local recruitment here
 assert_false(Armies.recruit_context(s,HOST).ok)
 assert_false(Armies.recruit(s,HOST,"peasant_levy","local").ok)
 var gold = s.treasury.house_aurek
 var r = Armies.recruit(s,HOST,"peasant_levy","global")
 assert_true(r.ok,str(r.reasons))
 var q = s.army_state[HOST].queue[0]
 assert_eq(int(q.cost),int(ceil(250*float(Armies.data().recruitment.global.cost_multiplier))))
 assert_eq(int(q.turns_left),int(UnitTypes.get_type("peasant_levy").recruitment.turns)*int(Armies.data().recruitment.global.turns_multiplier))
 assert_eq(s.treasury.house_aurek,gold-int(q.cost))
 assert_eq(Armies.queue_kind(q),"global")
 assert_eq(s.settlements[q.settlement].owner,"house_aurek","men come from your own settlement")

func test_global_offers_every_unit_unlocked_in_the_realm():
 var s = rich_state()
 var unlocked = {}
 for sid in s.settlements_of("house_aurek"):
  for u in s.settlements[sid].get("unlocks",[]): unlocked[u] = true
 assert_gt(unlocked.size(),0)
 for o in Armies.options(s,HOST,"global"):
  assert_eq(o.available,unlocked.has(o.unit),o.unit)

# --- Banners and panel layout -------------------------------------------------------------------------

func test_queued_cards_carry_their_banner_colour():
 var data = UiData.new(rich_state())
 var ui = build_ui(data)
 data.recruit(HOST,"peasant_levy","local")
 data.recruit(HOST,"peasant_levy","global")
 data.recruit(HOST,"peasant_levy","local")
 data.recruit(HOST,"peasant_levy","local")
 ui.show_army(HOST,"Goldspire")
 var kinds = []
 for i in 4: kinds.append(ui.bottom_box.find_child("Queued_%d" % i,true,false).queued_kind)
 assert_eq(kinds,["local","global","local","overflow"])
 assert_eq(Cards.QUEUE_COLORS.keys(),["local","global","overflow"])
 var box = ui.bottom_box
 var cards_row = box.find_child("ArmyCards",true,false).get_parent() # its scroller
 assert_gt(box.find_child("ArmyActions",true,false).get_index(),cards_row.get_index(),"recruit buttons sit below the cards")
 ui.toggle_recruitment(HOST,"global")
 var slots = ui.bottom_box.find_child("CapacitySlots",true,false)
 assert_eq([slots.capacity,slots.queued],[3,4])
 assert_eq(ui.recruit_mode,"global")
 ui.toggle_recruitment(HOST,"global")
 assert_false(ui.recruitment_visible(),"the same button closes it")

func test_locked_units_show_why():
 var data = UiData.new(rich_state())
 var ui = build_ui(data)
 ui.show_army(HOST,"Goldspire")
 ui.open_recruitment(HOST)
 var locked = data.recruitment(HOST).options.filter(func(o): return not o.available)
 assert_gt(locked.size(),0)
 var col = ui.bottom_box.find_child("Recruit_"+locked[0].unit,true,false).get_parent()
 assert_not_null(col.find_child("Locked",true,false))
 assert_eq(col.find_child("Locked",true,false).text,locked[0].reasons[0])
