extends GutTest
# Player deployment (core/deployment.gd) and the full battle report: placement rules (lane capacity,
# passes, impassable lanes), templates give legal deployments, orders reach the battle setup, an
# unchanged template fights exactly like the default, and the replay matches the simulation.

const GameState = preload("res://core/game_state.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const BattleDeploy = preload("res://core/battle_deploy.gd")
const BattleReport = preload("res://core/battle_report.gd")
const Deployment = preload("res://core/deployment.gd")
const WorldMap = preload("res://core/world_map.gd")
const HOST = "aurek_host"

func after_each():
 BattleSim.reset()

# Far left impassable, left a pass, center open, right forest, far right open.
func mixed_terrain() -> Array:
 var t = []
 for kind in ["closed","pass","open","forest","open"]:
  var lane = []
  for b in 6: lane.append(kind)
  t.append(lane)
 return t

func flat_terrain(kind := "open") -> Array:
 var t = []
 for l in 5:
  var lane = []
  for b in 6: lane.append(kind)
  t.append(lane)
 return t

func units(n := 6) -> Array:
 var kinds = ["spearmen","swordsmen","archers","peasant_levy","heavy_infantry","cavalry","spearmen","archers","cavalry","peasant_levy"]
 var out = []
 for i in n: out.append({"unit":kinds[i%kinds.size()],"men":100,"max_men":100,"index":i,"army":"test"})
 return out

func battle_at(s,sid: String) -> Dictionary:
 var p = WorldMap.settlement_position(sid)
 s.army_state[HOST].position = [p.x+8.0,p.y+4.0]
 s.army_state[HOST].garrison = ""
 var t = Battles.target_at(s,HOST,p)
 Battles.declare_war(s,"house_aurek",t.faction)
 return Battles.prebattle(s,HOST,t)

func test_impassable_lanes_and_passes_limit_placement():
 var dep = Deployment.create(units(6),mixed_terrain(),0,"line")
 assert_eq(Deployment.validate(dep),[],"the template itself is legal")
 var r = Deployment.can_place(dep,0,0,"front")
 assert_false(r.ok)
 assert_string_contains(r.reason,"impassable")
 # The pass holds one unit per line.
 for i in dep.units.size(): Deployment.place(dep,i,0,"reserve")
 assert_true(Deployment.place(dep,0,1,"front").ok)
 var before = dep.units[1].duplicate()
 r = Deployment.place(dep,1,1,"front")
 assert_false(r.ok)
 assert_string_contains(r.reason,"pass holds only 1")
 assert_eq(dep.units[1],before,"a refused move changes nothing")
 assert_true(Deployment.place(dep,1,1,"back").ok,"the back line of the pass has its own slot")

func test_lane_capacity_per_terrain():
 var dep = Deployment.create(units(6),mixed_terrain(),0,"line")
 for i in dep.units.size(): Deployment.place(dep,i,0,"reserve")
 var cap_open = Deployment.capacity(dep,2,"front")
 var cap_forest = Deployment.capacity(dep,3,"front")
 assert_gt(cap_open,cap_forest,"forest holds fewer units than open ground")
 for i in cap_open: assert_true(Deployment.place(dep,i,2,"front").ok)
 var r = Deployment.place(dep,cap_open,2,"front")
 assert_false(r.ok)
 assert_string_contains(r.reason,"full")
 for i in cap_forest: assert_true(Deployment.place(dep,cap_open+1+i,3,"front").ok)
 r = Deployment.place(dep,5,3,"front")
 assert_false(r.ok)
 assert_string_contains(r.reason,"forest")
 assert_true(Deployment.place(dep,5,0,"reserve").ok,"the reserve has no limit")
 assert_eq(dep.units[5].order,"reserve")
 assert_eq(Deployment.validate(dep),[])

func test_every_template_gives_a_legal_deployment():
 for terrain in [flat_terrain(),mixed_terrain(),flat_terrain("forest"),flat_terrain("pass")]:
  for role in 2:
   for n in [3,8,10]:
    for t in BattleDeploy.TEMPLATES:
     var dep = Deployment.create(units(n),terrain,role,t)
     assert_eq(dep.units.size(),n,"%s keeps every unit" % t)
     assert_eq(Deployment.validate(dep),[],"%s, role %d, %d units" % [t,role,n])

func test_orders_are_checked_and_saved_into_the_battle_setup():
 var s = GameState.from_data()
 var pb = battle_at(s,"greyhaven")
 var dep = Deployment.create(Battles.side_units(s,pb,0),pb.field.terrain,0,"line")
 var n = dep.units.size()
 assert_gt(n,3)
 assert_true(Deployment.set_order(dep,0,"reserve").ok)
 assert_eq(dep.units[0].line,"reserve")
 assert_false(Deployment.set_order(dep,1,"protect",1).ok,"a unit cannot protect itself")
 # Protect a unit on the field.
 var target = -1
 for i in n:
  if i>1 and dep.units[i].line != "reserve": target = i
 assert_true(Deployment.set_order(dep,1,"protect",target).ok)
 var fr = Deployment.set_order(dep,2,"flank","right")
 if fr.ok:
  assert_eq(int(dep.units[2].lane),dep.lanes-1)
  assert_eq(dep.units[2].order,"flank")
 else: assert_ne(fr.reason,"")
 assert_true(Deployment.set_general_lane(dep,1).ok)
 assert_eq(Deployment.validate(dep),[])
 pb.deployment = dep
 var setup = Battles.setup(s,pb,pb.seed)
 var side = setup.sides[0]
 assert_eq(int(side.general_lane),1)
 for i in n:
  assert_eq(side.units[i].order,dep.units[i].order)
  assert_eq(side.units[i].line,dep.units[i].line)
  assert_eq(int(side.units[i].lane),int(dep.units[i].lane))
 assert_eq(int(side.units[1].protect),target)
 assert_eq(side.units[1].order,"protect")
 # The enemy side keeps its own default deployment.
 assert_eq(JSON.stringify(setup.sides[1].units),JSON.stringify(Battles.default_placement(s,pb,1)))

func test_deployment_matching_a_template_fights_like_that_template():
 # The faction's default template, through the whole campaign flow.
 var a = GameState.from_data()
 var b = GameState.from_data()
 var pa = battle_at(a,"greyhaven")
 var pbb = battle_at(b,"greyhaven")
 pa.deployment = Deployment.create(Battles.side_units(a,pa,0),pa.field.terrain,0,Battles.default_template(a,pa,0))
 var ra = Battles.quick_resolve(a,pa)
 var rb = Battles.quick_resolve(b,pbb)
 assert_eq(JSON.stringify(ra.result),JSON.stringify(rb.result))
 # Every other template, at the simulation: a player deployment from template T equals T itself.
 var s = GameState.from_data()
 var pb = battle_at(s,"willowmere")
 for t in BattleDeploy.TEMPLATES:
  var p = pb.duplicate()
  p.deployment = Deployment.create(Battles.side_units(s,pb,0),pb.field.terrain,0,t)
  var with_dep = Battles.setup(s,p,77)
  var plain = Battles.setup(s,pb,77)
  plain.sides[0].units = BattleDeploy.deploy(Battles.side_units(s,pb,0),t,pb.field.terrain,0)
  var x = BattleSim.simulate(with_dep)
  var y = BattleSim.simulate(plain)
  assert_eq(JSON.stringify(x),JSON.stringify(y),"template %s" % t)

func test_replay_ticks_match_the_simulation():
 var s = GameState.from_data()
 var pb = battle_at(s,"greyhaven")
 var result = BattleSim.simulate(Battles.setup(s,pb,pb.seed))
 assert_eq(result.replay.size(),int(result.ticks)+1,"the deployment frame plus one frame per tick")
 assert_eq(result.roster.size(),result.replay[0].size())
 var last = result.replay[-1]
 for i in result.roster.size():
  var r = result.roster[i]
  if r.general: continue
  var row = result.sides[r.side].units[r.row]
  assert_eq(int(result.replay[0][i][3]),int(row.men_start),"frame 0 holds the starting men")
  assert_eq(int(last[i][3]),int(row.men_end),"the last frame holds the final men")
 for e in result.events:
  assert_between(int(e.tick),1,int(result.ticks))
  var st = int(result.replay[e.tick][e.unit][2]) if int(e.unit)>=0 else -1
  if e.tag == "destroyed": assert_eq(st,BattleSim.S_DESTROYED,"destroyed at its tick")
  if e.tag == "routed": assert_true(st>=BattleSim.S_ROUTED,"routed at its tick")
 # The report carries the same frames, a roster and a timeline whose units index the frames.
 var rep = BattleReport.build(pb,result,{"captured":"","generals":[],"promoted":[]},"house_aurek")
 assert_eq(rep.replay,result.replay)
 assert_eq(rep.roster.size(),result.roster.size())
 assert_eq(rep.enemy_units.size(),result.sides[1].units.size())
 assert_gt(rep.timeline.size(),0)
 for e in rep.timeline:
  assert_ne(e.text,"")
  for u in e.units: assert_between(int(u),0,result.roster.size()-1)
 assert_false(rep.walls.is_empty(),"a siege replay draws the walls")

func test_quick_resolve_report_has_the_full_report():
 var s = GameState.from_data()
 var pb = battle_at(s,"willowmere")
 var out = Battles.quick_resolve(s,pb)
 var rep = BattleReport.build(pb,out.result,out.aftermath,"house_aurek")
 for k in ["timeline","replay","roster","enemy_units","units","why","headline"]: assert_true(rep.has(k),k)
 assert_eq(rep.replay.size(),int(out.result.ticks)+1)
