extends GutTest
# Movement acceptance tests (owner hotfix 2026-10-07; run every time). Everything is driven by real
# input events (Input.parse_input_event: left click to select, right click to order, keys) on the
# campaign scene, and the lord's RENDERED position is recorded every frame. For every walk:
#  - the first rendered position is where the lord stood (no jump to the destination),
#  - positions advance monotonically along the drawn path (never backwards, never off the path,
#    no teleport between frames),
#  - the last rendered position is the expected stop (this turn's reach, or the destination).
# The reversed-move bug: main.gd _on_army_moved read the figure's position after sync_army_figures()
# had already put it at the destination, so the walk began at the destination.

const SaveSystem = preload("res://core/save_system.gd")
const Session = preload("res://core/session.gd")
const Movement = preload("res://core/movement.gd")
const Battles = preload("res://core/battles.gd")
const Armies = preload("res://core/armies.gd")
const WorldMap = preload("res://core/world_map.gd")
const LORD = "aurek_host"
const ENEMY = "highbloom_levy"
const Settings = preload("res://core/settings.gd")
# The most a figure may move in one recorded frame: its walk speed x the (scaled) delta of the frame
# that moved it, plus a small margin.
var _limits: Array = []
var _input_dt := 0.0 # the (scaled) delta of the frame in which the last input event was sent

var main
var _old_scale := 1.0

func before_each():
 SaveSystem.dir = "user://test_saves"
 Movement.continue_player_orders = false
 Input.use_accumulated_input = false
 _old_scale = Engine.time_scale
 await _start_main()
 Engine.time_scale = 6.0

func after_each():
 Engine.time_scale = _old_scale
 for b in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
  if Input.is_mouse_button_pressed(b): _mouse(b,false,Vector2.ZERO)
 if main != null and is_instance_valid(main): main.free()
 main = null
 SaveSystem.dir = SaveSystem.DIR
 Movement.continue_player_orders = false

func _start_main():
 main = load("res://Main.tscn").instantiate()
 add_child(main)
 await _frames(3)

# --- Input ----------------------------------------------------------------------------------------

func _frames(n: int):
 for i in n: await get_tree().process_frame

func _push(e: InputEvent):
 _input_dt = get_process_delta_time()
 Input.parse_input_event(e)
 Input.flush_buffered_events()

# Positions are given in the campaign's viewport coordinates (what unproject_position returns); the
# event carries window coordinates, as real input does (the root viewport is stretched to the window).
func _win(at: Vector2) -> Vector2:
 return get_viewport().get_final_transform()*at

func _motion(at: Vector2):
 var m = InputEventMouseMotion.new()
 m.position = _win(at)
 m.global_position = _win(at)
 _push(m)

func _mouse(button: int,pressed: bool,at: Vector2):
 var e = InputEventMouseButton.new()
 e.button_index = button
 e.pressed = pressed
 e.position = _win(at)
 e.global_position = _win(at)
 if pressed: e.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
 _push(e)

func _key(code: int,shift := false):
 for pressed in [true,false]:
  var k = InputEventKey.new()
  k.keycode = code
  k.physical_keycode = code
  k.shift_pressed = shift
  k.pressed = pressed
  _push(k)

func _click(button: int,at: Vector2):
 _motion(at)
 _mouse(button,true,at)
 await _frames(2)
 _mouse(button,false,at)

# The camera over a point (camera placement only; it changes no campaign state).
func _view(p: Vector2,d := 150.0):
 main.target = main.ground(p)
 main.desired_distance = d
 main.distance = d
 main.camera_update(0.0)

func _xz(v: Vector3) -> Vector2:
 return Vector2(v.x,v.z)

func _select(id: String):
 var f = main.army_figures[id]
 _view(_xz(f.position),120.0)
 await _frames(1)
 await _click(MOUSE_BUTTON_LEFT,main.camera.unproject_position(f.position+Vector3(0,2.2*f.scale.x,0)))
 await _frames(2)
 assert_eq(main.selected_army_id(),id,"selected by a left click")

# Right click on a map point (hold, then release): returns the plan the preview drew for it.
func _right_click(id: String,p: Vector2) -> Dictionary:
 _view(p)
 await _frames(1)
 var at = main.camera.unproject_position(main.ground(p))
 _motion(at)
 _mouse(MOUSE_BUTTON_RIGHT,true,at)
 await _frames(2)
 var plan = main.ui_data.plan_move(id,main.move_target(at))
 _mouse(MOUSE_BUTTON_RIGHT,false,at)
 return plan

# Rendered positions of these armies every frame until their walks end.
func _record(ids: Array,max_frames := 6000) -> Dictionary:
 var out = {}
 for id in ids: out[id] = []
 _limits = []
 var speed = Settings.walk_speed(float(main.WALK_SPEED),true)
 # Godot moves the figure in each frame by speed x that frame's delta; the delta read at a sample is
 # the one the next frame uses (the first step uses the delta of the frame the input came in).
 var dt = _input_dt
 for n in max_frames:
  await get_tree().process_frame
  _limits.append(speed*dt*1.1+0.1)
  dt = get_process_delta_time()
  for id in ids:
   if main.army_figures.has(id): out[id].append(_xz(main.army_figures[id].position))
  if n>=2 and not ids.any(func(i): return main.walks.has(i)): break
 return out

# Where a point lies along a polyline: {along (metres from its start), off (metres from it)}.
func _project(line: Array,p: Vector2) -> Dictionary:
 var best = {"along":0.0,"off":INF}
 var acc = 0.0
 for i in range(1,line.size()):
  var a: Vector2 = line[i-1]
  var b: Vector2 = line[i]
  var seg = a.distance_to(b)
  var t = 0.0 if seg<0.0001 else clampf((p-a).dot(b-a)/(seg*seg),0.0,1.0)
  var d = p.distance_to(a.lerp(b,t))
  if d<best.off-0.0001: best = {"along":acc+seg*t,"off":d}
  acc += seg
 return best

# The acceptance checks on one recorded walk along `line` (start .. expected stop).
func _check_walk(samples: Array,line: Array,label: String):
 assert_gt(samples.size(),2,label+": it walked over several frames")
 if samples.size()<2: return
 assert_lt(samples[0].distance_to(line[0]),_limits[0],label+": the first rendered position is where the lord stood")
 var prev = -INF
 var back = 0
 var off = 0.0
 var jump = 0.0
 for i in samples.size():
  var pr = _project(line,samples[i])
  if pr.along<prev-0.05: back += 1
  prev = maxf(prev,pr.along)
  off = maxf(off,pr.off)
  if i>0: jump = maxf(jump,samples[i].distance_to(samples[i-1])-_limits[mini(i,_limits.size()-1)])
 assert_eq(back,0,label+": never moves backwards along the path")
 assert_lt(off,1.0,label+": stays on the drawn path")
 assert_lte(jump,0.0,label+": no snap or teleport between frames (each step within walk speed x frame time)")
 assert_lt(samples[-1].distance_to(line[-1]),0.3,label+": stops where expected")

# The polyline a walk must follow: from where the figure stood, along the plan's points up to this
# turn's reach, to where the figure ends (outside the walls when it ends in a garrison).
func _walk_line(start: Vector2,plan: Dictionary,id: String) -> Array:
 var line = [start]
 for i in range(1,int(plan.reach)+1): line.append(plan.points[i])
 line[-1] = main.figure_spot(id)
 return line

# A target around the army for which pred(plan) holds, in open ground away from settlements and armies.
func _find(id: String,pred: Callable,radii := [70.0,100.0,140.0,200.0,260.0]) -> Vector2:
 var s = main.ui_data.state
 var p = Movement.position(s,id)
 for r in radii:
  for k in 32:
   var t = p+Vector2(r,0).rotated(k*TAU/32.0)
   if Movement.settlement_at(t) != "": continue
   if s.army_state.keys().any(func(o): return o != id and Movement.position(s,o).distance_to(t)<40.0): continue
   var plan = main.ui_data.plan_move(id,t)
   if plan.ok and str(plan.get("settlement","")) == "" and pred.call(plan): return t
 return Vector2.INF

func _share(plan: Dictionary,f: Callable) -> float:
 var n = 0
 for q in plan.points: if f.call(q): n += 1
 return float(n)/maxf(1.0,float(plan.points.size()))

func _length(points: Array) -> float:
 var l = 0.0
 for i in range(1,points.size()): l += points[i-1].distance_to(points[i])
 return l

# One order by right click, recorded and checked. Returns {plan, samples, line}.
func _move(id: String,target: Vector2,label: String) -> Dictionary:
 var start = _xz(main.army_figures[id].position)
 var plan = await _right_click(id,target)
 assert_true(plan.ok,label+": the plan is possible")
 if not plan.ok: return {}
 var rec = await _record([id])
 var line = _walk_line(start,plan,id)
 _check_walk(rec[id],line,label)
 assert_almost_eq(Movement.position(main.ui_data.state,id).distance_to(plan.points[int(plan.reach)]),0.0,0.5,label+": the army stands at this turn's reach")
 return {"plan":plan,"samples":rec[id],"line":line}

# --- The suite --------------------------------------------------------------------------------------

func test_short_move_within_reach():
 await _select(LORD)
 var t = _find(LORD,func(p): return int(p.total_turns) == 1 and int(p.reach) == p.points.size()-1)
 assert_true(t.is_finite(),"a target within reach")
 if not t.is_finite(): return
 var r = await _move(LORD,t,"short move")
 assert_eq(int(r.plan.reach),r.plan.points.size()-1,"reaches the destination this turn")
 assert_true(main.ui_data.state.army_state[LORD].order.is_empty(),"no order left")

func test_move_past_reach_stops_at_the_edge_and_waits():
 await _select(LORD)
 var t = _find(LORD,func(p): return int(p.total_turns)>=2 and int(p.reach)>=2,[400.0,320.0,260.0])
 assert_true(t.is_finite(),"a target two or more turns away")
 if not t.is_finite(): return
 var r = await _move(LORD,t,"multi-turn move")
 var a = main.ui_data.state.army_state[LORD]
 assert_false(a.order.is_empty(),"the remainder is kept as an order")
 main.refresh_army_overlays()
 assert_true(main.movement_overlay.has_content("order:"+LORD),"the remaining path is drawn")
 var turns = main.ui_data.order_path(LORD).turns
 assert_true(turns.any(func(x): return int(x)>=1),"the remainder is a later turn (amber)")
 # End Turn (Shift+Enter skips the notifications): the lord does not move.
 var stood = _xz(main.army_figures[LORD].position)
 var logical = Movement.position(main.ui_data.state,LORD)
 _key(KEY_ENTER,true)
 await _frames(30)
 assert_eq(int(main.ui_data.state.turn),2,"the turn ended")
 assert_eq(Movement.position(main.ui_data.state,LORD),logical,"no move at End Turn")
 assert_lt(_xz(main.army_figures[LORD].position).distance_to(stood),0.01,"the figure stayed")
 assert_false(main.ui_data.state.army_state[LORD].order.is_empty(),"the order waits")

func test_continue_order_goes_on_from_where_he_stopped():
 await _select(LORD)
 var t = _find(LORD,func(p): return int(p.total_turns)>=3 and int(p.reach)>=2,[520.0,440.0,380.0])
 if not t.is_finite(): t = _find(LORD,func(p): return int(p.total_turns)>=2 and int(p.reach)>=2,[400.0,320.0])
 assert_true(t.is_finite())
 if not t.is_finite(): return
 await _move(LORD,t,"first leg")
 _key(KEY_ENTER,true)
 await _frames(10)
 # The next turn: Continue order on the army panel (a real click on the button).
 await _select(LORD)
 var path = main.ui_data.order_path(LORD)
 var stop = 0
 for i in path.turns.size():
  if int(path.turns[i]) == 0: stop = i
 assert_gt(stop,0,"part of the remaining path is walkable this turn")
 var start = _xz(main.army_figures[LORD].position)
 var button = main.ui.find_child("ContinueOrder",true,false)
 assert_not_null(button,"the Continue order button")
 if button == null: return
 await _click(MOUSE_BUTTON_LEFT,button.get_global_rect().get_center())
 var rec = await _record([LORD])
 var line = [start]
 for i in range(1,stop+1): line.append(path.points[i])
 line[-1] = main.figure_spot(LORD)
 _check_walk(rec[LORD],line,"continue order")
 assert_almost_eq(Movement.position(main.ui_data.state,LORD).distance_to(path.points[stop]),0.0,0.5)

func test_off_road_move_across_forest_and_hills():
 await _select(LORD)
 # The test map's forest and hills lie along its roads: the target whose path crosses the most rough
 # ground off the roads.
 var s = main.ui_data.state
 var p = Movement.position(s,LORD)
 var rough_off = func(q): return Movement.terrain_at(q) in ["forest","hills"] and not Movement.is_road(Movement.cell_of(q))
 var best = Vector2.INF
 var best_n = 0
 for x in range(-24,25):
  for y in range(-24,25):
   var t = p+Vector2(x,y)*10.0
   if not rough_off.call(t) or Movement.settlement_at(t) != "": continue
   var plan = main.ui_data.plan_move(LORD,t)
   if not plan.ok or int(plan.total_turns) != 1: continue
   var n = 0
   for q in plan.points: if rough_off.call(q): n += 1
   if n>best_n:
    best_n = n
    best = t
 assert_gte(best_n,8,"a path across forest or hills off the roads")
 if not best.is_finite(): return
 var r = await _move(LORD,best,"off-road move")
 if r.is_empty(): return
 var rough_cost = 0.0
 var rough_len = 0.0
 for i in range(1,r.plan.points.size()):
  var q = r.plan.points[i]
  if rough_off.call(q):
   rough_len += r.plan.points[i-1].distance_to(q)
   rough_cost += Movement.segment_cost(r.plan.points[i-1],q,int(s.road_level))
 assert_gt(rough_cost/maxf(0.01,rough_len),1.0,"forest and hills cost more than open ground")

func test_move_along_a_road_gets_the_road_bonus():
 await _select(LORD)
 var road = func(q): return Movement.is_road(Movement.cell_of(q))
 var t = _find(LORD,func(p): return _share(p,road)>=0.8 and _length(p.points)>=50.0,[60.0,90.0,120.0,160.0,220.0,300.0])
 assert_true(t.is_finite(),"a target along a road")
 if not t.is_finite(): return
 var r = await _move(LORD,t,"road move")
 var per_m = float(r.plan.cost)/maxf(0.01,_length(r.plan.points))
 var mult = Movement.road_multiplier(int(main.ui_data.state.road_level))
 assert_lt(mult,1.0)
 assert_lt(per_m,1.0,"cheaper than open ground")
 assert_almost_eq(per_m,mult,0.12,"about the road's multiplier per metre")

func test_backspace_cancels_a_held_preview():
 await _select(LORD)
 var t = _find(LORD,func(p): return int(p.total_turns) == 1)
 _view(t)
 await _frames(1)
 var at = main.camera.unproject_position(main.ground(t))
 var before = Movement.position(main.ui_data.state,LORD)
 var fig = _xz(main.army_figures[LORD].position)
 _motion(at)
 _mouse(MOUSE_BUTTON_RIGHT,true,at)
 await _frames(3)
 assert_true(main.rmb_held,"previewing")
 assert_true(main.movement_overlay.has_content("preview"),"the path is drawn")
 _key(KEY_BACKSPACE)
 await _frames(1)
 assert_false(main.rmb_held,"Backspace dropped the held preview")
 _mouse(MOUSE_BUTTON_RIGHT,false,at)
 await _frames(20)
 assert_eq(Movement.position(main.ui_data.state,LORD),before,"no order on release")
 assert_true(main.ui_data.state.army_state[LORD].order.is_empty())
 assert_lt(_xz(main.army_figures[LORD].position).distance_to(fig),0.01,"the figure did not move")

func test_host_members_follow_the_leader_at_once():
 var s = main.ui_data.state
 s.treasury[s.player_faction] = 100000
 var raised = Armies.raise_army(s,s.player_faction,"goldspire_rock")
 assert_true(raised.ok,"a second lord: %s" % str(raised.get("reasons","")))
 if not raised.ok: return
 var member = raised.army
 assert_true(main.ui_data.form_host(LORD,[member]).ok)
 main.sync_army_figures()
 await _frames(2)
 await _select(LORD)
 var t = _find(LORD,func(p): return int(p.total_turns) == 1 and _length(p.points)>=80.0,[110.0,150.0,200.0])
 assert_true(t.is_finite())
 if not t.is_finite(): return
 var lead_start = _xz(main.army_figures[LORD].position)
 var mem_start = _xz(main.army_figures[member].position)
 var plan = await _right_click(LORD,t)
 # Right after the release, before any frame: both walks exist and begin where the figures stand.
 assert_true(main.walks.has(member),"the member walks now, with the leader (not at End Turn)")
 if not main.walks.has(member): return
 var mline = main.walks[member].points.duplicate()
 assert_lt(mline[0].distance_to(mem_start),0.01,"the member's walk begins where it stands")
 var rec = await _record([LORD,member])
 _check_walk(rec[LORD],_walk_line(lead_start,plan,LORD),"host leader")
 _check_walk(rec[member],mline,"host member")
 assert_lt(Movement.position(s,member).distance_to(Movement.position(s,LORD)),40.0,"next to its leader")
 # End Turn: nothing more moves.
 var lp = Movement.position(s,LORD)
 var mp = Movement.position(s,member)
 _key(KEY_ENTER,true)
 await _frames(20)
 assert_eq(Movement.position(s,LORD),lp)
 assert_eq(Movement.position(s,member),mp)

func test_levies_march_to_the_muster_point_on_their_own():
 var s = main.ui_data.state
 var point = "crownwatch" # Goldspire Rock raises the levies; they march here
 assert_true(main.ui_data.call_banners(point).ok)
 var muster = WorldMap.settlement_position(point)
 var marched = false
 for turn in 6:
  var before = {}
  for id in s.armies_of(s.player_faction): before[id] = _xz(main.army_figures[id].position)
  _key(KEY_ENTER,true)
  # End Turn runs at once in headless runs; the walks begin as it ends.
  var levies = s.armies_of(s.player_faction).filter(func(id): return bool(s.army_state[id].get("captain",false)) and main.walks.has(id))
  if levies.is_empty():
   await _frames(2)
   continue
  var lines = {}
  for id in levies:
   lines[id] = main.walks[id].points.duplicate()
   if before.has(id): assert_lt(lines[id][0].distance_to(before[id]),0.01,"%s's walk begins where it stands" % id)
   assert_lt(lines[id][-1].distance_to(muster),lines[id][0].distance_to(muster),"%s marches toward the muster point" % id)
  var rec = await _record(levies)
  for id in levies: _check_walk(rec[id],lines[id],"levy "+id)
  marched = true
 assert_true(marched,"levies marched to the muster point without a confirm")

func test_attack_order_on_an_adjacent_enemy():
 var s = main.ui_data.state
 var me = s.player_faction
 var foe = s.army_state[ENEMY].faction
 # The enemy stands close by in open ground, at war with us.
 var spot = _find(LORD,func(p): return int(p.total_turns) == 1 and _length(p.points)>=50.0,[60.0,80.0,100.0])
 assert_true(spot.is_finite())
 s.army_state[ENEMY].position = [spot.x,spot.y]
 s.army_state[ENEMY].garrison = ""
 Battles.declare_war(s,me,foe)
 main.sync_army_figures()
 main.place_commander()
 await _frames(2)
 await _select(LORD)
 var start = _xz(main.army_figures[LORD].position)
 _view(spot)
 await _frames(1)
 var ef = main.army_figures[ENEMY]
 await _click(MOUSE_BUTTON_RIGHT,main.camera.unproject_position(ef.position+Vector3(0,2.2*ef.scale.x,0)))
 assert_true(main.walks.has(LORD),"the lord marches on the enemy")
 if not main.walks.has(LORD): return
 var line = main.walks[LORD].points.duplicate()
 assert_lt(line[0].distance_to(start),0.01,"the walk begins where he stands")
 assert_lt(line[-1].distance_to(spot),line[0].distance_to(spot),"toward the enemy")
 var rec = await _record([LORD])
 _check_walk(rec[LORD],line,"attack")
 assert_lt(Movement.position(s,LORD).distance_to(spot),80.0,"in attack range")
 await _frames(5)
 assert_true(main.ui.battle_visible(),"the pre-battle panel opens when he arrives")

func test_move_save_load_and_continue():
 await _select(LORD)
 var t = _find(LORD,func(p): return int(p.total_turns)>=2 and int(p.reach)>=2,[400.0,320.0,260.0])
 assert_true(t.is_finite())
 if not t.is_finite(): return
 await _move(LORD,t,"move before saving")
 var stood = Movement.position(main.ui_data.state,LORD)
 # Ctrl+S quicksaves; loading rebuilds the campaign scene from the save (the real load path).
 var k = InputEventKey.new()
 k.keycode = KEY_S
 k.physical_keycode = KEY_S
 k.ctrl_pressed = true
 k.pressed = true
 _push(k)
 k = k.duplicate()
 k.pressed = false
 _push(k)
 await _frames(2)
 SaveSystem.wait_for_images()
 var r = SaveSystem.load_save(SaveSystem.QUICKSAVE)
 assert_true(r.ok,"the quicksave loads")
 if not r.ok: return
 main.free()
 Session.pending_state = r.state
 Session.pending_name = SaveSystem.QUICKSAVE
 await _start_main()
 var s = main.ui_data.state
 assert_eq(Movement.position(s,LORD),stood,"the army is where it stopped")
 assert_false(s.army_state[LORD].order.is_empty(),"its order was saved")
 assert_lt(_xz(main.army_figures[LORD].position).distance_to(main.figure_spot(LORD)),0.5,"the figure stands there after loading")
 # End Turn, then Continue order: on from where he stopped.
 _key(KEY_ENTER,true)
 await _frames(10)
 await _select(LORD)
 var path = main.ui_data.order_path(LORD)
 var stop = 0
 for i in path.turns.size():
  if int(path.turns[i]) == 0: stop = i
 var start = _xz(main.army_figures[LORD].position)
 var button = main.ui.find_child("ContinueOrder",true,false)
 assert_not_null(button)
 if button == null: return
 await _click(MOUSE_BUTTON_LEFT,button.get_global_rect().get_center())
 var rec = await _record([LORD])
 var line = [start]
 for i in range(1,stop+1): line.append(path.points[i])
 line[-1] = main.figure_spot(LORD)
 _check_walk(rec[LORD],line,"continue after loading")
