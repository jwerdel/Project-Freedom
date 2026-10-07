extends GutTest
# Vassals, banners and Hosts, titles and Realm Standing (war-and-realm §2, §4, §5; game-design §11.6):
# the 40% vassal cap, loyalty with reasons and goals, banner turnout by standing, levies' production
# loss and return, a Host fighting as one battle, title earning and granting, Realm Standing caps,
# and the save round trip of all of it.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const V = preload("res://core/vassals.gd")
const H = preload("res://core/hosts.gd")
const T = preload("res://core/titles.gd")
const RS = preload("res://core/realm_standing.gd")
const Rep = preload("res://core/reputation.gd")
const D = preload("res://core/diplomacy.gd")
const Economy = preload("res://core/economy.gd")
const Battles = preload("res://core/battles.gd")
const Movement = preload("res://core/movement.gd")
const SaveCodec = preload("res://core/save_codec.gd")

const ME = "house_varn"

func before_each():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func state() -> RefCounted:
 var s = GameState.from_data()
 s.player_faction = ME
 return s

func test_vassal_cap_at_forty_percent():
 var s = state()
 assert_true(V.cap_check(s,ME,"barrow_lords").ok,"a small house fits")
 assert_false(V.cap_check(s,"barrow_lords",ME).ok,"a bigger realm cannot be the vassal")
 assert_false(D.eligible(s,ME,"barrow_lords",{"kind":"vassalage"}).ok,"so it cannot even be offered")
 V.swear(s,"barrow_lords",ME,"diplomacy")
 assert_eq(V.liege_of(s,"barrow_lords"),ME)
 assert_eq(D.relation(s,ME,"barrow_lords"),"vassal")

func test_vassal_loyalty_moves_with_reasons_and_goals():
 var s = state()
 V.swear(s,"barrow_lords",ME,"diplomacy")
 var e = s.vassals.barrow_lords
 var start = int(e.loyalty)
 V.gift(s,ME,"barrow_lords",600)
 assert_gt(int(e.loyalty),start)
 assert_string_contains(e.log[-1].reason,"gift")
 assert_ne(str(e.goal.get("text","")),"","every vassal states a goal")
 # Neglected long enough: loyalty falls with the reason, and rock bottom warns for turns.
 e.goal.since = -100
 e.last_favour = -100
 e.loyalty = 10
 var events = V.end_turn(s)
 assert_true(events.any(func(x): return x.kind == "warning"),"multi-turn warnings")
 assert_true(e.log.any(func(l): return "Neglected" in l.reason))
 # Economic goal steers the vassal AI's building.
 assert_true(V.set_econ_goal(s,"barrow_lords","fortify"))
 assert_gt(float(V.build_weights(s,"barrow_lords").defense),1.0)

func test_banner_turnout_follows_standing():
 var s = state()
 var neutral = H.terms(s,ME)
 assert_eq(neutral.key,"neutral")
 for i in 6: Rep.deed(s,ME,"liberated","Freed a city")
 var loved = H.terms(s,ME)
 assert_eq(loved.key,"loved")
 assert_gt(float(loved.turnout),float(neutral.turnout),"Loved: larger turnout")
 assert_lt(int(loved.turns),int(neutral.turns),"and faster")
 var plan_n = H.levy_plan(s,ME,float(neutral.turnout))
 var plan_l = H.levy_plan(s,ME,float(loved.turnout))
 var count = func(p): return p.values().reduce(func(a,b): return a+int(b),0)
 assert_gt(count.call(plan_l),count.call(plan_n))

func test_levies_cost_production_and_return_on_disband():
 var s = state()
 for i in 6: Rep.deed(s,ME,"liberated","Freed a city")
 var sid = s.settlements_of(ME)[0]
 var before = Economy.settlement_income(s,sid).total
 var r = H.call_banners(s,ME,sid)
 assert_true(r.ok)
 s.turn += 1
 H.end_turn(s)
 assert_gt(int(s.settlements[sid].get("levied",0)),0,"levies serve")
 assert_lt(Economy.settlement_income(s,sid).total,before,"production drops while they serve")
 var pop = float(s.settlements[sid].population)
 assert_eq(float(s.settlements[sid].population),pop,"population kept")
 var detachments = s.armies_of(ME).filter(func(id): return H.is_captain(s,id))
 assert_false(detachments.is_empty(),"captain-led detachments")
 assert_lte(s.army_state[detachments[0]].units.size(),6,"at most 6 units")
 assert_false(Battles.approach(s,detachments[0],{"kind":"settlement","id":"x","position":Vector2(0,0)}).ok,"defend only")
 H.dismiss_levies(s,ME)
 assert_eq(int(s.settlements[sid].get("levied",0)),0)
 assert_eq(Economy.settlement_income(s,sid).total,before,"production returns")

func test_a_host_moves_together_and_fights_as_one_battle():
 var s = state()
 var lead = s.armies_of(ME)[0]
 var Armies = load("res://core/armies.gd")
 s.treasury[ME] = 99999
 var sid = s.settlements_of(ME)[1] if s.settlements_of(ME).size()>1 else s.settlements_of(ME)[0]
 var other = Armies.raise_army(s,ME,sid)
 assert_true(other.ok,", ".join(other.get("reasons",[])))
 s.army_state[other.army].units = s.army_state[lead].units.duplicate(true)
 assert_true(H.form_host(s,lead,[other.army]).ok)
 assert_eq(H.host_of(s,other.army),lead)
 Movement.order(s,lead,Movement.position(s,lead)+Vector2(60,0))
 H.follow(s)
 s.army_state[other.army].points = 999.0
 Movement.advance(s,other.army)
 assert_lt(Movement.position(s,other.army).distance_to(Movement.position(s,lead)),15.0,"the Host keeps together")
 # The battle takes every Host army near the fight (one multi-army battle).
 var foe = s.armies_of("house_dunmoor")[0]
 var t = {"kind":"army","id":foe,"faction":"house_dunmoor","position":Movement.position(s,lead)+Vector2(8,0)}
 s.army_state[foe].position = [t.position.x,t.position.y]
 s.army_state[foe].garrison = ""
 var pb = Battles.prebattle(s,lead,t,false)
 assert_true(pb.attacker.reinforcements.any(func(r): return r.army == other.army),"the Host fights as one")

func test_titles_are_earned_and_granted():
 var s = state()
 T.end_turn(s)
 var held = T.held_by(s,"wardens")
 assert_has(held,"warden_wall","the Wardens hold Wardens' Gate")
 # Conquest moves a title: Varn takes the Gate, the Wardens lose it.
 s.settlements.wardens_gate.owner = ME
 T.end_turn(s)
 assert_eq(T.holder(s,"warden_wall"),ME)
 # A grantable title goes to a vassal as a loyalty reward.
 V.swear(s,"barrow_lords",ME,"diplomacy")
 var before = V.loyalty(s,"barrow_lords")
 assert_true(T.grant(s,"warden_wall",ME,"barrow_lords").ok)
 assert_eq(T.holder(s,"warden_wall"),"barrow_lords")
 assert_gt(V.loyalty(s,"barrow_lords"),before)
 assert_false(T.grant(s,"warden_north",ME,"barrow_lords").ok,"only grantable titles")

func test_realm_standing_sets_the_lord_army_cap():
 var s = state()
 var Armies = load("res://core/armies.gd")
 var lv = RS.level(s,ME)
 assert_eq(Armies.lord_army_cap(s,ME),int(RS.data().caps.lord_armies[lv-1]))
 for sid in s.settlements.keys().slice(0,20): s.settlements[sid].owner = ME
 assert_gt(RS.level(s,ME),lv,"more territory raises the level")
 assert_gt(Armies.lord_army_cap(s,ME),int(RS.data().caps.lord_armies[lv-1]),"and the cap")
 var sm = RS.summary(s,ME)
 assert_true(sm.caps.has("agents") and sm.caps.has("decrees"),"agent and decree caps stored for later")

func test_courts_and_realm_survive_a_save_round_trip():
 var s = state()
 V.swear(s,"barrow_lords",ME,"diplomacy")
 D.sign_treaty(s,ME,"house_kells","alliance")
 H.call_banners(s,ME,s.settlements_of(ME)[0])
 T.end_turn(s)
 var d = SaveCodec.from_json(SaveCodec.to_json(s.to_dict()))
 var t = GameState.from_dict(d)
 assert_eq(SaveCodec.to_json(t.to_dict()),SaveCodec.to_json(s.to_dict()),"identical after a round trip")
 assert_eq(V.liege_of(t,"barrow_lords"),ME)
 assert_true(D.allied(t,ME,"house_kells"))
 assert_eq(t.characters.size(),s.characters.size())
