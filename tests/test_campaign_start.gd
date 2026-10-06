extends GutTest
# The new campaign on Varos (Stage A, 2026-10-06): its factions and starting armies, the faction
# selection screen, the illustrated intro with the court introduction, and the untouchable Throne
# Church (constitution: no faction's goal is to take Caeloth).

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const Characters = preload("res://core/characters.gd")
const Ai = preload("res://core/ai.gd")
const FactionSelect = preload("res://ui/faction_select.gd")
const CampaignIntro = preload("res://ui/campaign_intro.gd")
const PLAYABLE = ["house_varn","house_varrenus","the_aurekids"]

func before_each():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_every_stage_a_faction_has_a_seat_crest_faith_and_an_army():
 var s = GameState.from_data()
 var factions = WorldMap.factions()
 assert_eq(factions.size(),42)
 for f in factions:
  var d = factions[f]
  assert_true(d.has("crest") and d.crest.has("charge"),f+" crest")
  assert_ne(str(d.get("faith","")),"",f+" faith")
  if str(d.get("seat_region","")) == "": continue
  assert_false(s.armies_of(f).is_empty(),f+" has a starting army")
 for p in PLAYABLE:
  assert_eq(str(factions[p].kind),"playable")
  for id in s.armies_of(p): assert_eq(Characters.skill_points(s.army_state[id].commander),0,"pre-allocated")

func test_lore_relations_are_mutual():
 var factions = WorldMap.factions()
 assert_eq(str(factions.house_varn.relations.house_dunmoor),"rival")
 assert_eq(str(factions.house_dunmoor.relations.house_varn),"rival")
 assert_eq(str(factions.the_aurekids.relations.theros),"friend")
 assert_eq(str(factions.theros.relations.the_aurekids),"friend")

func test_faction_selection_picks_a_house():
 var s = GameState.from_data()
 var sel = FactionSelect.new(s)
 add_child_autofree(sel)
 watch_signals(sel)
 for p in PLAYABLE: assert_not_null(sel.find_child("House_"+p,true,false))
 sel.find_child("House_house_varn",true,false).pressed.emit()
 assert_eq(sel.selected,"house_varn")
 sel.find_child("SelectBegin",true,false).pressed.emit()
 assert_signal_emitted_with_parameters(sel,"chosen",["house_varn"])

func test_intro_pages_then_the_court():
 var intro = CampaignIntro.new("the_aurekids")
 add_child_autofree(intro)
 watch_signals(intro)
 assert_eq(intro.pages(),4)
 assert_not_null(intro.find_child("IntroArt",true,false),"an art slot (placeholder until drawn)")
 for i in 3: intro.find_child("IntroNext",true,false).pressed.emit()
 assert_not_null(intro.find_child("CourtIntro",true,false))
 intro.find_child("IntroNext",true,false).pressed.emit()
 assert_signal_emitted(intro,"finished")

func test_the_ai_never_targets_caeloth():
 var s = GameState.from_data()
 assert_true(bool(WorldMap.faction("throne_church").untouchable))
 for id in s.army_state:
  if s.army_state[id].faction == "throne_church": continue
  for t in Ai.targets_for(s,id,5000.0): assert_ne(str(t.faction),"throne_church",id)
