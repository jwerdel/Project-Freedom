extends GutTest
# Debt and the loss condition (core/realm.gd; constitution, confirmed 2026-10-01): in debt no
# construction, recruitment or new armies, desertion each turn; below the limit the highest-upkeep
# units disband; losing the last settlement starts a grace period; retaking a settlement saves the
# faction, otherwise it is destroyed and its armies disband; the AI fights to retake land.

const GameState = preload("res://core/game_state.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Realm = preload("res://core/realm.gd")
const Ai = preload("res://core/ai.gd")
const Economy = preload("res://core/economy.gd")
const Construction = preload("res://core/construction.gd")
const Armies = preload("res://core/armies.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const SaveSystem = preload("res://core/save_system.gd")
const UiData = preload("res://core/ui_data.gd")
const HOST = "aurek_host"
const GUARD = "silverfall_guard"
const QUIET = {"ai":false}

func after_each():
 BattleSim.reset()
 Ai.reset()

func lose_all(s,f: String,to: String):
 for sid in s.settlements_of(f): Battles.occupy(s,sid,to,"")
 for id in Armies.armies_of(s,f): s.army_state[id].garrison = ""

func upkeep(u: Dictionary) -> float:
 return float(UnitTypes.get_type(u.unit).placeholder_stats.upkeep)

# --- Debt -----------------------------------------------------------------------------------------

func test_in_debt_no_construction_recruitment_or_new_armies():
 var s = GameState.from_data()
 s.treasury.house_aurek = -10
 var slot = -1
 for i in s.settlements.goldspire_rock.buildings.size():
  if s.settlements.goldspire_rock.buildings[i].is_empty(): slot = i
 var b = Construction.can_build(s,"goldspire_rock",slot,"market")
 assert_false(b.ok)
 assert_string_contains(", ".join(b.reasons),"In debt")
 s.army_state[HOST].garrison = "goldspire_rock"
 var r = Armies.can_recruit(s,HOST,"peasant_levy")
 assert_false(r.ok)
 assert_string_contains(", ".join(r.reasons),"In debt")
 var g = Armies.can_raise(s,"house_aurek","crownwatch")
 assert_false(g.ok)
 assert_string_contains(", ".join(g.reasons),"In debt")
 # Buying can never push a faction into debt: everything costs at most what is in the treasury.
 s.treasury.house_aurek = 100
 assert_false(Construction.can_build(s,"goldspire_rock",slot,"market").ok)

func test_debt_causes_desertion_every_turn():
 var s = GameState.from_data()
 # Deep in debt but above the limit: desertion only.
 s.treasury.house_aurek = int(Realm.debt().limit)/2
 var before = []
 for u in s.army_state[HOST].units: before.append(int(u.men))
 var events = Realm.apply_debt(s)
 var share = float(Realm.debt().desertion_share)
 var lost = 0
 for i in before.size():
  var men = int(s.army_state[HOST].units[i].men)
  assert_eq(men,before[i]-mini(maxi(1,int(round(before[i]*share))),before[i]-1),"unit %d loses its share" % i)
  assert_gte(men,1,"never below one man")
  lost += before[i]-men
 assert_eq(s.army_state[HOST].units.size(),before.size(),"no unit disbands above the limit")
 assert_true(events.any(func(e): return e.kind == "desertion" and e.faction == "house_aurek" and int(e.men) == lost))
 # Out of debt: nobody deserts.
 var t = GameState.from_data()
 assert_true(Realm.apply_debt(t).filter(func(e): return e.faction == "house_aurek").is_empty())

func test_below_the_limit_the_most_expensive_units_disband_until_income_covers_upkeep():
 var s = GameState.from_data()
 # A large expensive army on a small income.
 for i in 10: s.army_state[HOST].units.append({"unit":"cavalry" if i%2 == 0 else "heavy_infantry","men":100,"max_men":100})
 for i in 6: s.army_state[HOST].units.append({"unit":"peasant_levy","men":100,"max_men":100})
 assert_lt(int(Economy.faction_ledger(s,"house_aurek").net),0,"precondition: upkeep exceeds income")
 s.treasury.house_aurek = int(Realm.debt().limit)-1
 var events = Realm.apply_debt(s)
 var gone = events.filter(func(e): return e.kind == "disband").map(func(e): return e.unit)
 assert_false(gone.is_empty())
 assert_gte(int(Economy.faction_ledger(s,"house_aurek").net),0,"income covers upkeep afterwards")
 # The disbanded units cost at least as much upkeep as any unit left.
 var cheapest_gone = INF
 for u in gone: cheapest_gone = minf(cheapest_gone,upkeep({"unit":u}))
 for u in s.army_state[HOST].units: assert_lte(upkeep(u),cheapest_gone,"%s stayed while dearer units went" % u.unit)

func test_debt_is_applied_in_the_turn_and_recorded():
 var s = GameState.from_data()
 s.treasury.house_aurek = int(Realm.debt().limit)/2 # still in debt after this year's income
 var rep = TurnLoop.end_turn(s,QUIET)
 assert_true(rep.debt.any(func(e): return e.kind == "desertion" and e.faction == "house_aurek"))
 assert_true(s.chronicle.any(func(e): return e.get("faction","") == "house_aurek" and e.title.contains("Desert")))
 var ui = UiData.new(s)
 if s.treasury.house_aurek<0: assert_true(ui.resources().in_debt)

# --- Loss condition -------------------------------------------------------------------------------

func test_losing_the_last_settlement_starts_a_grace_period_then_destruction():
 var s = GameState.from_data()
 var n = int(Realm.rules().loss.grace_turns)
 lose_all(s,"house_verrin","house_lannet")
 TurnLoop.end_turn(s,QUIET)
 assert_eq(Realm.grace_left(s,"house_verrin"),n,"grace starts at %d" % n)
 assert_true(s.chronicle.any(func(e): return e.get("faction","") == "house_verrin" and e.title.contains("No Land")))
 for i in n-1:
  TurnLoop.end_turn(s,QUIET)
  assert_eq(Realm.grace_left(s,"house_verrin"),n-1-i)
 assert_false(Realm.destroyed(s,"house_verrin"))
 TurnLoop.end_turn(s,QUIET)
 assert_true(Realm.destroyed(s,"house_verrin"),"destroyed when the grace runs out")
 assert_true(Armies.armies_of(s,"house_verrin").is_empty(),"its armies disband")
 assert_eq(Realm.grace_left(s,"house_verrin"),-1)
 assert_false(Ai.alive(s,"house_verrin"))

func test_retaking_a_settlement_in_time_saves_the_faction():
 var s = GameState.from_data()
 lose_all(s,"house_verrin","house_lannet")
 TurnLoop.end_turn(s,QUIET)
 TurnLoop.end_turn(s,QUIET)
 assert_gt(Realm.grace_left(s,"house_verrin"),0)
 Battles.occupy(s,"willowmere","house_verrin","highbloom_levy")
 var rep = TurnLoop.end_turn(s,QUIET)
 assert_true(rep.realm.any(func(e): return e.kind == "survived" and e.faction == "house_verrin"))
 assert_eq(Realm.grace_left(s,"house_verrin"),-1)
 assert_false(Realm.destroyed(s,"house_verrin"))

func test_a_faction_with_no_army_left_is_destroyed_at_once():
 var s = GameState.from_data()
 lose_all(s,"house_verrin","house_lannet")
 s.army_state.erase("highbloom_levy")
 s.armies.erase("highbloom_levy")
 TurnLoop.end_turn(s,QUIET)
 assert_true(Realm.destroyed(s,"house_verrin"))

func test_the_players_destruction_is_game_over_and_survives_a_save():
 var s = GameState.from_data()
 lose_all(s,"house_aurek","house_lannet")
 TurnLoop.end_turn(s,QUIET)
 var ui = UiData.new(s)
 assert_eq(ui.resources().grace,int(Realm.rules().loss.grace_turns),"the player sees the countdown")
 var back = GameState.from_dict(SaveCodec.from_json(SaveCodec.to_json(s.to_dict())))
 assert_eq(back.grace,s.grace,"grace periods are saved")
 for i in int(Realm.rules().loss.grace_turns): TurnLoop.end_turn(s,QUIET)
 assert_true(UiData.new(s).resources().destroyed,"game over")
 # Each grace turn told the player how long is left.
 assert_gte(s.chronicle.filter(func(e): return e.get("faction","") == "house_aurek" and e.title.contains("Left to")).size(),int(Realm.rules().loss.grace_turns)-1)

func test_a_schema_2_save_migrates():
 var r = SaveSystem.migrate({"schema":2,"state":{"x":1}})
 assert_true(r.ok)
 assert_eq(r.data.state.grace,{})
 assert_eq(r.data.state.destroyed,[])

# --- AI ------------------------------------------------------------------------------------------

func test_a_landless_ai_fights_to_retake_a_settlement():
 var s = GameState.from_data()
 # House Lannet loses Greyhaven to the player; its guard (reinforced) stands near Verrin's
 # unwalled Willowmere, with no war yet against Verrin.
 lose_all(s,"house_lannet","house_aurek")
 var kinds = ["spearmen","swordsmen","archers","heavy_infantry","spearmen","archers"]
 for i in 6: s.army_state[GUARD].units.append({"unit":kinds[i],"men":100,"max_men":100})
 var w = WorldMap.settlement_position("willowmere")
 s.army_state[GUARD].position = [w.x+14.0,w.y+4.0]
 TurnLoop.end_turn(s,QUIET)
 assert_gte(Realm.grace_left(s,"house_lannet"),0,"precondition: landless")
 var rep = Ai.take_turns(s,{"factions":["house_lannet","house_verrin"],"resolve_player":true})
 var mine = rep.actions.filter(func(a): return a.get("faction","") == "house_lannet" or a.get("attacker","") == "house_lannet")
 assert_true(mine.any(func(a): return a.action == "war"),"it declares war to get land back (no roll)")
 assert_true(mine.any(func(a): return a.action in ["attack","besiege","march"]),"and goes for a settlement: %s" % str(mine.map(func(a): return a.action)))

func test_ai_in_debt_cannot_build_or_recruit():
 var s = GameState.from_data()
 s.treasury.house_lannet = -50
 var rep = Ai.take_turns(s,{"factions":["house_lannet"]})
 assert_true(rep.actions.filter(func(a): return a.action in ["build","recruit","raise"]).is_empty())
