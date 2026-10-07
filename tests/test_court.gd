extends GutTest
# Characters and courts (game-design §4; core/court.gd): aging and the career window, level-20
# immortality, heirs and succession, the marriage race rule, loyalty with reasons, renaming, and
# absorbed families.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const Court = preload("res://core/court.gd")
const TurnLoop = preload("res://core/turn_loop.gd")

func before_each():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_every_faction_has_a_court_with_its_founder():
 var s = GameState.from_data()
 for f in s.factions():
  if s.settlements_of(f).is_empty(): continue
  var r = Court.ruler(s,f)
  assert_ne(r,"",f+" has a ruler")
  assert_gt(Court.members(s,f).size(),1,f+" has family")
 var edric = s.characters[Court.ruler(s,"house_varn")]
 assert_eq(Court.full_name(edric),"Edric Varn the Winter Shield")
 assert_true(edric.legendary and edric.immortal,"legendary founders are immortal from the start")
 # The ruler leads the first army (generals come from the court).
 var host = s.armies_of("house_varn")[0]
 assert_eq(str(s.army_state[host].commander.character),edric.id)

func test_aging_and_the_career_window():
 var s = GameState.from_data()
 var f = "house_varn"
 var kid = Court.new_character(s,f,{"name":"Wyn","gender":"m","age":0.0,"role":"child"})
 var ages = []
 for i in 8:
  Court.end_turn(s)
  s.turn += 1
  ages.append(float(s.characters[kid].age))
 assert_eq(ages[0],2.5,"children age 2.5 years a turn")
 assert_eq(ages[4],12.0,"to twelve")
 assert_eq(ages[5],13.0,"then one year a turn")
 # At twelve the player must choose a career (the formative years).
 assert_true(s.characters[kid].career_pending or s.characters[kid].career != "")
 s.characters[kid].career = ""
 s.characters[kid].career_pending = true
 assert_true(Court.choose_career(s,kid,"spy").ok)
 assert_eq(s.characters[kid].career,"spy")
 assert_false(Court.choose_career(s,kid,"general").ok,"chosen once")
 # Adults stop aging in their prime.
 var old = Court.new_character(s,f,{"name":"Gram","age":32.0})
 for i in 5: Court.end_turn(s)
 assert_eq(float(s.characters[old].age),32.0,"no aging past the prime")
 # No death of old age: still alive.
 assert_false(s.characters[old].dead)

func test_level_twenty_makes_a_character_immortal():
 var s = GameState.from_data()
 var id = Court.new_character(s,"house_varn",{"name":"Brand","age":30.0})
 assert_false(s.characters[id].immortal)
 Court.gain_xp(s,id,Court.xp_for_level(20))
 assert_gte(int(s.characters[id].level),20)
 assert_true(s.characters[id].immortal)
 # A defeated immortal returns after return_defeated turns instead of dying.
 Court.die(s,id,"battle")
 assert_false(s.characters[id].dead)
 assert_gt(int(s.characters[id].defeated_until),int(s.turn))
 s.turn = int(s.characters[id].defeated_until)
 Court.end_turn(s)
 assert_eq(int(s.characters[id].defeated_until),-1,"back")
 # A mortal dies.
 var m = Court.new_character(s,"house_varn",{"name":"Hale","age":30.0})
 Court.die(s,m,"battle")
 assert_true(s.characters[m].dead)

func test_heir_and_succession_without_crisis():
 var s = GameState.from_data()
 var f = "house_varrenus"
 var ruler = Court.ruler(s,f)
 var pick = ""
 for id in Court.members(s,f):
  if id != ruler and Court.is_adult(s.characters[id]): pick = id
 assert_ne(pick,"")
 assert_true(Court.set_heir(s,f,pick).ok)
 assert_eq(Court.heir(s,f),pick)
 # The ruler can be replaced at any time; the old ruler stays in the court.
 assert_true(Court.make_ruler(s,f,pick).ok)
 assert_eq(Court.ruler(s,f),pick)
 assert_false(s.characters[ruler].dead)
 assert_true(load("res://core/reputation.gd").in_first_impressions(s,f),"a new ruler is watched")
 # A mortal ruler's death: the chosen heir succeeds.
 s.characters[pick].immortal = false
 var next = Court.heir(s,f)
 assert_ne(next,"")
 Court.die(s,pick,"execution")
 assert_eq(Court.ruler(s,f),next,"the heir succeeds")

func test_marriage_children_take_the_fathers_race():
 var s = GameState.from_data()
 var orc = Court.new_character(s,"grimhollow",{"name":"Gor","gender":"m","age":24.0,"race":"orc","culture":"orc"})
 var woman = Court.new_character(s,"house_varn",{"name":"Ilsa","gender":"f","age":22.0,"race":"medieval","culture":"medieval"})
 var r = Court.marry(s,orc,woman)
 assert_true(r.ok)
 assert_eq(s.characters[woman].faction,"grimhollow","the wife joins the husband's court")
 s.seed = 1
 var born = false
 for i in 40:
  s.turn += 1
  for e in Court.end_turn(s):
   if e.kind == "birth" and s.characters[e.character].father == orc:
    assert_eq(s.characters[e.character].race,"orc","children take the father's race")
    born = true
  if born: break
 assert_true(born,"a child is born")
 assert_false(Court.can_marry(s,orc,woman).ok,"already married")

func test_loyalty_changes_carry_their_reasons():
 var s = GameState.from_data()
 var f = "house_varn"
 var id = Court.new_character(s,f,{"name":"Osk","age":25.0,"loyalty":50})
 Court.gift(s,f,id,600)
 Court.appoint_governor(s,f,id,s.settlements_of(f)[0])
 var reasons = Court.loyalty_reasons(s.characters[id])
 assert_gte(reasons.size(),2)
 assert_string_contains(reasons[1].reason,"gift")
 assert_string_contains(reasons[0].reason,"governor")
 assert_gt(int(s.characters[id].loyalty),50)
 # Neglect: no role, title or gift for years.
 var idle = Court.new_character(s,f,{"name":"Nell","age":25.0,"loyalty":60})
 s.characters[idle].since_favour = 20
 Court._loyalty_drift(s,f)
 assert_lt(int(s.characters[idle].loyalty),60)
 assert_string_contains(s.characters[idle].loyalty_log[-1].reason,"Neglected")

func test_traits_and_epithets_come_from_deeds():
 var s = GameState.from_data()
 var id = Court.new_character(s,"house_varn",{"name":"Rurik","age":30.0})
 for i in 5: Court.deed(s,id,"settlements_taken")
 assert_eq(s.characters[id].epithet,"the Conqueror")
 for i in 3: Court.deed(s,id,"battles_won")
 assert_eq(Court.trait_level(s.characters[id],"brave"),1,"Brave from victories")

func test_renaming_and_absorbed_families():
 var s = GameState.from_data()
 var r = Court.ruler(s,"house_dunmoor")
 assert_true(Court.rename(s,r,"Aldo"))
 assert_eq(s.characters[r].name,"Aldo")
 var n = Court.members(s,"house_dunmoor").size()
 assert_true(Court.absorb_family(s,"house_varn","house_dunmoor","court").ok)
 assert_eq(Court.members(s,"house_dunmoor").size(),0)
 assert_eq(s.characters[r].faction,"house_varn")
 assert_lt(int(s.characters[r].loyalty),50,"absorbed families start low")
 var before = load("res://core/reputation.gd").entry(s,"house_varn").ruler.mercy
 Court.absorb_family(s,"house_varn","house_kells","remove","execute")
 assert_lt(float(load("res://core/reputation.gd").entry(s,"house_varn").ruler.mercy),float(before),"executions cost mercy")

func test_births_pause_at_the_court_cap():
 var s = GameState.from_data()
 var f = "house_varn"
 var cap = Court.court_cap(s,f)
 assert_between(cap,16,40,"the soft cap follows Realm Standing")
 var hus = Court.new_character(s,f,{"name":"Aric","gender":"m","age":25.0})
 var wife = Court.new_character(s,f,{"name":"Bera","gender":"f","age":22.0,"house":"Ashby"})
 assert_true(Court.marry(s,hus,wife).ok)
 var i = 0
 while Court.members(s,f).size()<cap:
  Court.new_character(s,f,{"name":"Filler%d" % i,"age":30.0})
  i += 1
 # Every married couple would have a child at chance 1, but the court is full.
 Court.data().births.chance = 1.0
 var before = Court.members(s,f).size()
 Court._births(s,f)
 Court.reset()
 assert_eq(Court.members(s,f).size(),before,"no births in a full court")

# Soft cap (owner spec 2026-10-07): the cap rises with Realm Standing; births slow as a court fills.
func test_births_slow_as_the_court_fills_and_the_cap_grows_with_standing():
 var s = GameState.from_data()
 var f = "house_varn"
 var cap = Court.court_cap(s,f)
 assert_gt(Court.birth_factor(s,f,0),Court.birth_factor(s,f,cap/2),"slower half full")
 assert_gt(Court.birth_factor(s,f,cap/2),Court.birth_factor(s,f,cap-1),"slower still near the cap")
 assert_eq(Court.birth_factor(s,f,cap),0.0,"none at the cap")
 for sid in s.settlements.keys().slice(0,30): s.settlements[sid].owner = f
 assert_gt(Court.court_cap(s,f),cap,"a greater realm keeps a larger court")
 assert_lte(Court.court_cap(s,f),40)
