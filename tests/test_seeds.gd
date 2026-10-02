extends GutTest
# Campaign and battle seeds: each new campaign gets a random seed kept in the campaign state; the
# start file's fixed seed stays available for tests; a battle's seed combines the campaign seed,
# year, battle counter and both sides' armies, so battles differ within a year yet replay exactly.

const GameState = preload("res://core/game_state.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const WorldMap = preload("res://core/world_map.gd")
const HOST = "aurek_host"

func after_each():
 BattleSim.reset()

func battle_at(s,sid: String) -> Dictionary:
 var p = WorldMap.settlement_position(sid)
 s.army_state[HOST].position = [p.x+8.0,p.y+4.0]
 s.army_state[HOST].garrison = ""
 var t = Battles.target_at(s,HOST,p)
 Battles.declare_war(s,"house_aurek",t.faction)
 return Battles.prebattle(s,HOST,t)

func test_new_campaigns_get_different_random_seeds():
 var seeds = {}
 for i in 5: seeds[GameState.new_campaign().seed] = true
 assert_gt(seeds.size(),3,"new campaigns draw different seeds")
 var s = GameState.new_campaign()
 assert_eq(s.to_dict().seed,s.seed,"the seed is part of the campaign state")

func test_the_fixed_seed_stays_available():
 var start = JSON.parse_string(FileAccess.get_file_as_string(GameState.START))
 assert_eq(GameState.from_data().seed,int(start.seed))
 assert_eq(GameState.from_data(GameState.START,777).seed,777)

func test_same_campaign_seed_and_battle_reproduce_exactly():
 var a = GameState.from_data(GameState.START,4242)
 var b = GameState.from_data(GameState.START,4242)
 var pa = battle_at(a,"greyhaven")
 var pb = battle_at(b,"greyhaven")
 assert_eq(pa.seed,pb.seed)
 var ra = Battles.quick_resolve(a,pa)
 var rb = Battles.quick_resolve(b,pb)
 assert_eq(JSON.stringify(ra.result),JSON.stringify(rb.result))
 assert_eq(JSON.stringify(a.to_dict()),JSON.stringify(b.to_dict()))

func test_different_campaign_seeds_give_different_battles():
 var pa = battle_at(GameState.from_data(GameState.START,1),"greyhaven")
 var pb = battle_at(GameState.from_data(GameState.START,2),"greyhaven")
 assert_ne(pa.seed,pb.seed)

func test_two_battles_in_one_year_differ():
 var s = GameState.from_data()
 var first = battle_at(s,"greyhaven")
 var other_target = battle_at(s,"willowmere")
 assert_ne(first.seed,other_target.seed,"different armies, different seed")
 assert_eq(s.year,1)
 Battles.quick_resolve(s,other_target)
 # The same matchup later in the same year: the battle counter moved on.
 if s.army_state.has(HOST):
  var again = battle_at(s,"greyhaven")
  assert_eq(s.year,1)
  assert_ne(again.seed,first.seed)
 # Same inputs give the same seed; any changed input changes it.
 var k = Battles.battle_seed(s,HOST,["silverfall_guard"],"greyhaven")
 assert_eq(Battles.battle_seed(s,HOST,["silverfall_guard"],"greyhaven"),k)
 assert_ne(Battles.battle_seed(s,HOST,["highbloom_levy"],"greyhaven"),k)
