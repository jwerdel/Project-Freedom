extends GutTest
# Construction (TW:WH3-style): gold is paid up front and buildings finish on time during End Turn;
# the main building's level caps other buildings; upgrading it raises the settlement level, slots
# and growth stage visual; cancelling refunds per the data rule; completions reach Event Messages
# and the chronicle; the placeholder AI builds; the UI building browser drives all of it.

const GameState = preload("res://core/game_state.gd")
const Economy = preload("res://core/economy.gd")
const Buildings = preload("res://core/buildings.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const Construction = preload("res://core/construction.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const UiData = preload("res://core/ui_data.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")

const GS = "goldspire_rock"

func after_each():
 Economy.reset()

func empty_slot(s,id: String) -> int:
 for i in s.settlements[id].buildings.size():
  if s.settlements[id].buildings[i].is_empty(): return i
 return -1

func test_construction_costs_gold_and_completes_on_time():
 var s = GameState.from_data()
 var slot = empty_slot(s,GS)
 var cost = int(Buildings.level_data("market",1).cost)
 var turns = int(Buildings.level_data("market",1).turns)
 var before = s.treasury.house_aurek
 assert_true(Construction.start(s,GS,slot,"market").ok)
 assert_eq(s.treasury.house_aurek,before-cost)
 for i in turns-1:
  TurnLoop.end_turn(s)
  assert_true(s.settlements[GS].buildings[slot].is_empty(),"not finished early")
 var report = TurnLoop.end_turn(s)
 assert_eq(s.settlements[GS].buildings[slot],{"chain":"market","level":1})
 assert_true(Construction.in_progress(s,GS).is_empty())
 assert_eq(report.completed.size(),1)

func test_two_turn_construction_takes_two_end_turns():
 var s = GameState.from_data()
 s.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 var main = s.settlements[GS].buildings[0].chain
 assert_eq(int(Buildings.level_data(main,3).turns),2)
 assert_true(Construction.start(s,GS,0,main).ok)
 TurnLoop.end_turn(s)
 assert_eq(int(s.settlements[GS].level),2)
 TurnLoop.end_turn(s)
 assert_eq(int(s.settlements[GS].level),3)

func test_level_caps_are_enforced():
 var s = GameState.from_data()
 s.treasury.house_aurek = 1000000
 s.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 # Goldspire is level 2: its level-2 mine cannot go to level 3 until the main building does.
 var mine_slot = 1
 assert_eq(s.settlements[GS].buildings[mine_slot].chain,"mine")
 var check = Construction.can_build(s,GS,mine_slot,"mine")
 assert_false(check.ok)
 assert_string_contains(", ".join(check.reasons),"settlement level 3")
 assert_false(Construction.start(s,GS,mine_slot,"mine").ok)
 # Duplicates and wrong settlement types are refused; every slot builds at once (owner spec 2026-10-07).
 var slot = empty_slot(s,GS)
 assert_false(Construction.can_build(s,GS,slot,"port").ok,"port already built")
 assert_false(Construction.can_build(s,GS,slot,"farm").ok,"no farms in a city")
 assert_true(Construction.start(s,GS,slot,"market").ok)
 assert_false(Construction.can_build(s,GS,slot,"market").ok,"that slot is already building")
 assert_true(Construction.can_build(s,GS,0,s.settlements[GS].buildings[0].chain).ok,"the main building can upgrade at the same time")
 # Not enough gold.
 var poor = GameState.from_data()
 poor.treasury.house_aurek = 10
 var r = Construction.can_build(poor,GS,empty_slot(poor,GS),"market")
 assert_false(r.ok)
 assert_string_contains(", ".join(r.reasons),"Not enough gold")

func test_main_upgrade_raises_level_slots_capacity_and_visual_stage():
 var s = GameState.from_data()
 s.treasury.house_aurek = 1000000
 s.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 var main = s.settlements[GS].buildings[0].chain
 var slots_before = s.settlements[GS].buildings.size()
 var cap_before = Economy.capacity(s,GS)
 var stage_before = Construction.visual_stage(s,GS)
 var path_before = AssetManifest.settlement_stage_path(GS,stage_before.stage,stage_before.generic)
 assert_true(Construction.start(s,GS,0,main).ok)
 for i in int(Buildings.level_data(main,3).turns): TurnLoop.end_turn(s)
 assert_eq(int(s.settlements[GS].level),3)
 assert_eq(int(s.settlements[GS].buildings[0].level),3)
 assert_eq(s.settlements[GS].buildings.size(),Buildings.slot_count("city",3))
 assert_gt(s.settlements[GS].buildings.size(),slots_before)
 assert_gt(Economy.capacity(s,GS),cap_before)
 var stage = Construction.visual_stage(s,GS)
 assert_eq(stage.stage,3)
 assert_eq(AssetManifest.settlement_stage_path(GS,stage.stage,stage.generic),AssetManifest.landmarks()[GS].stage_3)
 assert_ne(AssetManifest.settlement_stage_path(GS,stage.stage,stage.generic),path_before)
 # The cap is lifted: the mine can now reach level 3.
 assert_true(Construction.can_build(s,GS,1,"mine").ok)
 # A generic (non-landmark) city switches to the generic stage scenes.
 var g = Construction.visual_stage(s,"greyhaven")
 assert_eq(AssetManifest.settlement_stage_path("greyhaven",g.stage,g.generic),AssetManifest.scene_path("settlement.city.stage_%d" % g.stage))

func test_cancel_refunds_in_full_this_turn_and_partially_later():
 var rules = Buildings.data().construction
 var s = GameState.from_data()
 var slot = empty_slot(s,GS)
 var before = s.treasury.house_aurek
 Construction.start(s,GS,slot,"market")
 assert_eq(Construction.cancel(s,GS),int(round(Buildings.level_data("market",1).cost*rules.cancel_refund_same_turn)))
 assert_eq(s.treasury.house_aurek,before)
 assert_true(Construction.in_progress(s,GS).is_empty())
 # A two-turn build cancelled after one End Turn refunds the later ratio.
 s.treasury.house_aurek = 1000000
 s.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 var main = s.settlements[GS].buildings[0].chain
 var cost = int(Buildings.level_data(main,3).cost)
 Construction.start(s,GS,0,main)
 TurnLoop.end_turn(s)
 var t = s.treasury.house_aurek
 var refund = Construction.cancel(s,GS)
 assert_eq(refund,int(round(cost*rules.cancel_refund_later)))
 assert_lt(refund,cost)
 assert_eq(s.treasury.house_aurek,t+refund)
 assert_eq(int(s.settlements[GS].level),2)

func test_completions_are_logged_to_events_and_chronicle():
 var data = UiData.new()
 data.state.treasury.house_aurek = 1000000
 data.state.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 assert_true(data.start_construction(GS,empty_slot(data.state,GS),"market").ok)
 data.end_turn()
 var events = data.events("buildings")
 assert_eq(events.size(),1)
 assert_string_contains(events[0].title,"Market Square")
 assert_eq(events[0].faction,"house_aurek")
 var found = false
 for e in data.chronicle(): found = found or (e.category == "buildings" and e.title == events[0].title)
 assert_true(found,"completion is in the Grey Scribes' chronicle")

func test_event_messages_show_only_the_players_buildings():
 var data = UiData.new()
 data.state.treasury.house_lannet = 100000
 data.state.stock["house_lannet"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 for i in 3: data.end_turn()
 var ai_built = 0
 for e in data.state.chronicle:
  if e.category == "buildings" and e.faction != "house_aurek": ai_built += 1
 assert_gt(ai_built,0,"the AI built something")
 for e in data.events("buildings"): assert_eq(e.faction,"house_aurek")

func test_ui_browser_builds_upgrades_and_cancels():
 var studio = PortraitStudio.new()
 add_child_autofree(studio)
 var data = UiData.new()
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(data,studio)
 ui.show_settlement(GS)
 var slot = empty_slot(data.state,GS)
 ui.open_building_browser(GS,slot)
 assert_true(ui.browser_visible())
 var build = ui.browser_box.find_child("Build_market",true,false)
 assert_not_null(build)
 assert_false(build.disabled)
 build.pressed.emit()
 assert_false(ui.browser_visible())
 assert_eq(data.construction(GS).chain,"market")
 var card_slot = data.building_slots(GS)[slot]
 assert_true(card_slot.has("construction"))
 # The level-capped mine shows its locked reason and a disabled Upgrade button.
 ui.open_building_browser(GS,1)
 var upgrade = ui.browser_box.find_child("Build_mine",true,false)
 assert_true(upgrade.disabled)
 # The construction slot offers a cancel with a full refund this turn.
 var before = data.resources().treasury
 ui.open_building_browser(GS,slot)
 var cancel = ui.browser_box.find_child("Cancel",true,false)
 assert_not_null(cancel)
 cancel.pressed.emit()
 assert_eq(data.resources().treasury,before+int(Buildings.level_data("market",1).cost))
 # Other factions' settlements cannot be built in from the player's UI.
 for o in data.building_options("greyhaven",5): assert_false(o.available)

func test_ports_require_a_coastal_settlement():
 var s = GameState.from_data()
 s.treasury.house_verrin = 100000
 s.stock["house_verrin"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 s.treasury.house_aurek = 100000
 s.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 assert_false(s.settlements.willowmere.coastal)
 assert_true(s.settlements.greyhaven.coastal and s.settlements[GS].coastal)
 # Willowmere (level 1) may have no empty slot; give it one at level 2 to test the coast rule alone.
 Construction.set_level(s,"willowmere",2)
 var check = Construction.can_build(s,"willowmere",empty_slot(s,"willowmere"),"port")
 assert_false(check.ok)
 assert_has(check.reasons,"Requires a coast")
 # Not offered at all (owner spec 2026-10-07: port and fishing only where there is water).
 assert_false(Construction.options(s,"willowmere",empty_slot(s,"willowmere")).any(func(o): return o.chain == "port"),"no port offered inland")
 # Coastal settlements are not affected; every starting port stands on the coast.
 assert_false("Requires a coast" in Construction.can_build(s,GS,2,"port").reasons)
 for id in s.settlements:
  for b in s.settlements[id].buildings:
   if b.get("chain","") == "port": assert_true(s.settlements[id].coastal,id+" has a port inland")
 # The AI never starts an inland port.
 for i in 15:
  TurnLoop.end_turn(s)
  for id in s.settlements:
   if not s.settlements[id].coastal: assert_false(Construction.jobs(s,id).any(func(j): return j.chain == "port"),id)

# Parallel builds (owner spec 2026-10-07): every empty slot under construction at once, each paid
# when started; the realm queue lists them all with cancel and refund.
func test_every_slot_builds_at_the_same_time():
 var s = GameState.from_data()
 s.treasury.house_aurek = 100000
 s.stock["house_aurek"] = {"food":100000,"wood":100000,"stone":100000,"starving":0}
 Construction.set_level(s,GS,3) # every slot open
 var data = UiData.new(s)
 var started = 0
 for i in s.settlements[GS].buildings.size():
  if s.settlements[GS].buildings[i].has("chain"): continue
  for o in Construction.options(s,GS,i):
   if o.available and Construction.start(s,GS,i,o.chain).ok:
    started += 1
    break
 assert_gt(started,1,"several slots building at once")
 assert_eq(Construction.jobs(s,GS).size(),started)
 var q = data.realm_constructions()
 assert_eq(q.size(),started,"the realm queue lists every construction")
 var gold = s.treasury.house_aurek
 var refund = data.cancel_construction(GS,int(q[0].slot))
 assert_gt(refund,0)
 assert_eq(s.treasury.house_aurek,gold+refund)
 assert_eq(Construction.jobs(s,GS).size(),started-1)
 for t in 4: TurnLoop.end_turn(s)
 assert_true(Construction.jobs(s,GS).is_empty(),"all complete")

# Placement rules (validator): no settlement without water offers a port or fishing, none without
# hills offers mines; on the test map and on Varos.
func test_terrain_buildings_only_where_the_land_allows():
 for map in [MapRegistry.DEFAULT,MapRegistry.CAMPAIGN]:
  MapRegistry.set_active(map)
  var s = GameState.from_data()
  var water = 0
  for id in s.settlements:
   var geo = Buildings.geography(s,id)
   if geo.water: water += 1
   var offered = []
   var st = s.settlements[id]
   while st.buildings.size()<Buildings.slot_count(st.type,Buildings.max_level(Buildings.main_chain_id(st.type))): st.buildings.append({})
   for i in st.buildings.size():
    if st.buildings[i].has("chain"): continue
    for o in Construction.options(s,id,i): offered.append(o.chain)
   if not geo.coastal: assert_false("port" in offered,"%s %s: a port without a coast" % [map,id])
   if not geo.water: assert_false("fishing" in offered,"%s %s: fishing without water" % [map,id])
   if not geo.hills: assert_false("mine" in offered,"%s %s: mines without hills" % [map,id])
  assert_gt(water,0,map+": some settlements have water")
 MapRegistry.set_active(MapRegistry.DEFAULT)
