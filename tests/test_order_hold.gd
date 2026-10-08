extends GutTest
# No player army moves at End Turn unless the player ordered it that turn (playtest 2026-10-07:
# "my character auto-moved when I started a new turn"). Multi-turn orders, attack orders and Host
# followers wait for the player's confirm while Settings "Continue multi-turn orders automatically"
# is off (core/movement.gd holds_orders); AI armies keep walking, and levies marching to their muster
# point march on their own (owner hotfix 2026-10-07).

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const UiData = preload("res://core/ui_data.gd")
const Movement = preload("res://core/movement.gd")
const Hosts = preload("res://core/hosts.gd")

func after_each():
 Movement.continue_player_orders = false
 MapRegistry.set_active(MapRegistry.DEFAULT)

# A target two or more turns away for the army (searched around it).
func far_target(s,id: String) -> Vector2:
 var p = Movement.position(s,id)
 for r in [400.0,300.0,250.0,200.0]:
  for k in 16:
   var t = p+Vector2(r,0).rotated(k*TAU/16.0)
   var plan = Movement.plan(s,id,t)
   if plan.ok and int(plan.total_turns)>=2: return t
 return Vector2.INF

func test_no_player_army_moves_without_an_order():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 var s = GameState.from_data()
 s.player_faction = "house_varn"
 var data = UiData.new(s)
 # Banners called: the Host machinery runs, yet no lord of ours moves at End Turn. Levies marching
 # to the muster point are the exception: they march on their own (owner hotfix 2026-10-07).
 data.call_banners(load("res://core/armies.gd").capital(s,"house_varn"))
 for t in 4:
  var before = {}
  for id in s.armies_of("house_varn"):
   if not bool(s.army_state[id].get("muster",false)): before[id] = Movement.position(s,id)
  data.end_turn()
  for id in before:
   if s.army_state.has(id): assert_eq(Movement.position(s,id),before[id],"%s moved at End Turn %d without an order" % [id,t+1])

func test_levies_march_to_the_muster_point_on_their_own():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 var s = GameState.from_data()
 s.player_faction = "house_varn"
 var data = UiData.new(s)
 # Muster away from the capital, so the levies raised there have somewhere to march.
 var cap = load("res://core/armies.gd").capital(s,"house_varn")
 var point = s.settlements_of("house_varn").filter(func(x): return x != cap)[0]
 assert_true(data.call_banners(point).ok)
 var muster = load("res://core/world_map.gd").settlement_position(point)
 var marched = false
 var last = {}
 for t in 8:
  var report = data.end_turn()
  for id in s.armies_of("house_varn"):
   var a = s.army_state[id]
   if not bool(a.get("captain",false)): continue
   var d = Movement.position(s,id).distance_to(muster)
   if last.has(id) and d<last[id]-0.01:
    marched = true
    assert_true(report.moves.has(id),"its march is in the turn's moves (the map shows it)")
   if last.has(id): assert_lte(d,last[id]+0.01,"%s never walks away from the muster point" % id)
   last[id] = d
   assert_false(id in data.waiting_orders(),"levies are not a waiting order")
 assert_true(marched,"levies marched without a confirm")

func test_multi_turn_order_waits_for_the_player():
 var s = GameState.from_data()
 var data = UiData.new(s)
 var id = s.armies_of(s.player_faction)[0]
 var t = far_target(s,id)
 assert_true(t.is_finite(),"a target two turns away")
 var r = data.order_move(id,t)
 assert_true(r.ok)
 var after_order = Movement.position(s,id)
 data.end_turn()
 assert_eq(Movement.position(s,id),after_order,"held at End Turn")
 assert_false(s.army_state[id].order.is_empty(),"the order and its path stay")
 assert_has(data.waiting_orders(),id)
 assert_eq(data.continue_orders([id]),1)
 assert_ne(Movement.position(s,id),after_order,"walks when confirmed")

func test_continue_setting_walks_orders_at_end_turn():
 Movement.continue_player_orders = true
 var s = GameState.from_data()
 var data = UiData.new(s)
 var id = s.armies_of(s.player_faction)[0]
 var t = far_target(s,id)
 data.order_move(id,t)
 var p = Movement.position(s,id)
 data.end_turn()
 assert_ne(Movement.position(s,id),p,"with the setting on, orders continue")
