extends GutTest
# The attack flow (TW:WH3, owner 2026-10-05; docs/tw-ui-parity.md §15): right-clicking a distant
# enemy never jumps into battle. After the war declaration the lord marches over as many turns as
# needed; the pre-battle panel only opens (ready_attack) once the lord stands in attack range.

const GameState = preload("res://core/game_state.gd")
const UiData = preload("res://core/ui_data.gd")
const Battles = preload("res://core/battles.gd")
const Movement = preload("res://core/movement.gd")
const WorldMap = preload("res://core/world_map.gd")
const HOST = "aurek_host"

func after_each():
 Movement.reset()

func setup_far() -> UiData:
 var data = UiData.new(GameState.from_data())
 var s = data.state
 s.army_state[HOST].position = [60.0,-20.0]
 s.army_state[HOST].garrison = ""
 Battles.declare_war(s,"house_aurek","house_verrin")
 return data

func test_a_distant_target_is_marched_on_not_fought_at_once():
 var data = setup_far()
 var target = WorldMap.settlement_position("willowmere")
 var t = data.battle_target(HOST,target)
 assert_false(t.needs_war)
 assert_false(t.can_attack,"too far to attack this turn")
 var battles_before = data.state.battles
 var r = data.attack_order(HOST,target)
 assert_true(r.ok)
 assert_false(r.now,"no battle now")
 assert_gt(r.turns,1)
 assert_true(data.state.army_state[HOST].has("attack"),"an attack order is kept")
 assert_true(data.ready_attack().is_empty(),"not in range yet")
 var ready = {}
 for i in 8:
  data.end_turn()
  data.continue_orders() # the march waits for the player's confirm (Settings: continue automatically)
  ready = data.ready_attack()
  if not ready.is_empty(): break
 assert_false(ready.is_empty(),"the lord arrives within a few turns")
 assert_eq(ready.army,HOST)
 assert_eq(ready.target.id,"willowmere")
 assert_lt(Movement.position(data.state,HOST).distance_to(target),12.0,"next to the target")
 assert_eq(data.state.battles,battles_before,"no battle was fought on the way")

func test_a_target_in_range_this_turn_is_reached_at_once():
 var data = setup_far()
 var target = WorldMap.settlement_position("willowmere")
 data.state.army_state[HOST].position = [target.x+20.0,target.y+6.0]
 var r = data.attack_order(HOST,target)
 assert_true(r.ok and r.now)
 assert_false(data.state.army_state[HOST].has("attack"))
 assert_true(data.battle_target(HOST,target).can_attack,"now in attack range")

func test_another_order_cancels_the_attack_order_and_it_is_saved():
 var data = setup_far()
 data.attack_order(HOST,WorldMap.settlement_position("willowmere"))
 var back = GameState.from_dict(data.state.to_dict())
 assert_true(back.army_state[HOST].has("attack"),"saves keep the attack order")
 data.order_move(HOST,Vector2(40,-10))
 assert_false(data.state.army_state[HOST].has("attack"))
