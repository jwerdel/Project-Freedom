extends Node
# The look test's scripted showcase (about 80 s): walk through Frosthold among the villagers, sprint
# and wall-run up a house, Threefold Skywalk into flight, fly low over the countryside (sonic boom),
# climb seamlessly to the campaign map and the strategic map, pick Frosthold and dive back, slam
# down, then one charged punch through part of the town. It drives the same controls as the player
# (god/god_player.gd ctl), on game time, so it plays the same in real time and under Movie Maker:
#   runtime\Godot.exe --path . --write-movie captures/god_test/showcase.avi --fixed-fps 30
#     --resolution 1920x1080 god/god_test.tscn -- --showcase
# Key frames are saved as PNGs in captures/god_test/. With --perf=<file> it runs in real time and
# logs frame timings per segment (ground, flight, transition, big punch).

var host
var p # the player
var t := 0.0
var perf_file := ""
var house := -1
var house_door := Vector3.ZERO
var slam_target := Vector2.ZERO
var punch_target := Vector3.ZERO
var road: PackedVector2Array
var road_i := 0
var shots = {}
var phase := ""
var stats = {}
var punch_frame := false
var events: Array = []
var done := false
var dive_started := false
var strategic_t := -1.0
var target_yaw := 0.0
var target_pitch := -0.15
var sky_marks: Array = []
var dive_t0 := 1e9
var land_t := -1.0
var charge_t := -1.0
var punch_release := -1.0
var big_punch_ms := 0.0
var empire_t := -1.0
var _last_us := 0

const SHOTS = [[3.0,"key_01_walk"],[11.5,"key_02_wallrun"],[17.0,"key_03_skywalk"],[24.0,"key_04_flight"],[30.5,"key_05_low_pass"],
 [38.0,"key_06_rising"]]

func start(h,perf: String):
 host = h
 p = h.player
 perf_file = perf
 p.scripted = true
 h.empire.scripted = true
 h.empire.climb_scale = 0.4
 h.hud.show_help = false
 road = h.town.roads[0]
 road_i = mini(28,road.size()-1)
 # The house to run up: a two-storey home beside the south road, between the start and the market.
 var best = INF
 for b in h.town.homes:
  var blk = h.town.blocks[b]
  var c = Vector2(blk.center.x,blk.center.z)
  var on_road = road[mini(14,road.size()-1)]
  var dd = c.distance_to(on_road)
  if dd<best and blk.total>40:
   best = dd
   house = b
 house_door = h.town.blocks[house].door
 # The slam lands among the houses on the east road; the punch goes up the south road toward the market.
 var east = h.town.roads[2]
 var sp = east[mini(22,east.size()-1)]
 slam_target = h.empire.world_to_campaign(Vector3(sp.x,0,sp.y))
 target_yaw = p.yaw
 if perf_file != "":
  RenderingServer.viewport_set_measure_render_time(host.get_viewport().get_viewport_rid(),true)
  DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED) # true frame times, not the refresh rate

func _aim_yaw(to: Vector3) -> float:
 var d = to-p.global_position
 return atan2(-d.x,-d.z)

func _physics_process(delta):
 if done: return
 t += delta
 var c = p.ctl
 c.move = Vector2.ZERO
 c.jump = false
 c.sprint = false
 c.walk = false
 c.up = false
 c.down = false
 c.fly_pressed = false
 c.punch = false
 var e = host.empire
 if t<9.0:
  phase = "ground"
  # Walk (then run) up the south road among the villagers.
  var tgt = road[road_i]
  var to = Vector3(tgt.x,p.global_position.y,tgt.y)
  if Vector2(to.x-p.global_position.x,to.z-p.global_position.z).length()<6.0 and road_i>12: road_i -= 1
  target_yaw = _aim_yaw(to)
  c.move = Vector2(0,-1)
  c.walk = t<4.5
  target_pitch = -0.12
 elif t<14.5:
  phase = "ground"
  # Sprint at the house's front and run up its wall, onto the roof.
  if p.state != p.WALL and p.state != p.AIR: target_yaw = _aim_yaw(host.town.blocks[house].center)
  c.move = Vector2(0,-1)
  c.sprint = t<13.2
  target_pitch = 0.05 if p.state == p.WALL else -0.1
 elif t<20.5:
  phase = "ground"
  # Threefold Skywalk off the roof, the dash, then a double tap into flight.
  var k = t-14.5
  c.move = Vector2(0,-1)
  target_yaw = _aim_yaw(host.town.blocks[house].center)+0.6
  for m in [0.0,0.6,1.2,1.8,2.5]:
   if k>=m and not sky_marks.has(m):
    sky_marks.append(m)
    c.jump = true
  if k>3.3 and k<3.36: c.jump = true
  if k>3.45 and k<3.5: c.jump = true
  target_pitch = 0.1
 elif t<34.5:
  phase = "flight"
  # Fly low over the countryside, east over the fields and the forest edge; a sonic boom.
  if p.state != p.FLY: c.fly_pressed = true
  var alt = p.global_position.y-host.terrain.height_at(p.global_position.x,p.global_position.z)
  target_yaw = lerp_angle(target_yaw,-PI*0.5+sin(t*0.25)*0.5,delta*0.6)
  c.sprint = t>22.5
  c.move = Vector2(0,-1)
  target_pitch = clampf((28.0-alt)*0.012,-0.35,0.3)
  if alt<18.0: c.up = true
 elif t<48.5:
  phase = "transition"
  # Climb: up through the hand-over, the cloud deck, the campaign zoom, to the strategic map.
  if e.mode == "ground":
   if p.state != p.FLY: c.fly_pressed = true
   target_pitch = lerpf(target_pitch,-0.25,delta*1.2)
   c.sprint = true
   c.up = true
   e.script_climb = true
  else:
   e.script_climb = true
   if empire_t<0.0:
    empire_t = t
    events.append([t+0.7,"key_07_clouds"])
    events.append([t+4.0,"key_08_campaign"])
 elif not dive_started:
  phase = "strategic"
  e.script_climb = e.mode == "empire"
  if e.mode == "strategic":
   if strategic_t<0.0:
    strategic_t = t
    events.append([t+1.5,"key_09_strategic"])
   if t-strategic_t>3.2:
    e.script_climb = false
    dive_started = true
    dive_t0 = t
    e._on_chosen(slam_target,false)
 elif p.state == p.DIVE or e.mode == "dive" or t-dive_t0<2.5:
  phase = "dive"
  e.script_climb = false
  if land_t<0.0 and p.state != p.DIVE and e.mode != "dive": land_t = t
 elif punch_release<0.0:
  phase = "ground" if charge_t<0.0 else "punch"
  # Walk at the nearest standing houses (the slam flattened the ones around it), then charge.
  if punch_target == Vector3.ZERO: punch_target = _densest_direction()
  target_yaw = _aim_yaw(punch_target)
  target_pitch = -0.05
  var dist = Vector2(punch_target.x-p.global_position.x,punch_target.z-p.global_position.z).length()
  if charge_t<0.0:
   c.move = Vector2(0,-1)
   c.walk = dist<40.0
   if dist<30.0 or t-dive_t0>16.0:
    charge_t = t
    events.append([t+1.0,"key_12_charge"])
  else:
   c.punch = true
   if t-charge_t>1.6:
    c.punch = false
    punch_release = t
    var aim = -p.camera.global_transform.basis.z
    print("GODTEST showcase punch: at %s target %s dist %.1f aim %s cone chunks %d" % [p.global_position,punch_target,dist,aim,host.town.chunks_in_cone(p.global_position+Vector3(0,1.7,0),Vector3(aim.x,aim.y*0.35,aim.z).normalized(),72.0,cos(0.62)).size()])
    events.append([t+0.18,"key_13_punch"])
    events.append([t+2.5,"key_14_dust"])
    events.append([t+7.0,"key_15_ruins"])
 elif t-punch_release<9.0:
  phase = "punch"
  target_yaw = _aim_yaw(punch_target)
 else:
  _finish()
  return
 if not p.external_camera:
  p.yaw = lerp_angle(p.yaw,target_yaw,1.0-exp(-delta*3.0))
  p.pitch = lerpf(p.pitch,target_pitch,1.0-exp(-delta*2.5))

func _process(_delta):
 if done: return
 # Key frames (not in perf runs: saving a PNG costs a frame of 100+ ms).
 if perf_file == "":
  var all = SHOTS+events+[[dive_t0+0.7,"key_10_dive"]]+([[land_t+0.5,"key_11_slam"]] if land_t>0.0 else [])
  for s in all:
   if t>=s[0] and not shots.has(s[1]):
    shots[s[1]] = true
    host.save_frame(s[1])
 if perf_file != "": _measure()

func _measure():
 if t<2.0:
  _last_us = Time.get_ticks_usec()
  return # warm-up: the first frames build grass and compile what is first seen
 var rid = host.get_viewport().get_viewport_rid()
 # Wall-clock frame time (scaled deltas mislead under hit-stop and the punch's time slow).
 var now = Time.get_ticks_usec()
 var real = (now-_last_us)/1000.0 if _last_us>0 else 16.7
 _last_us = now
 var seg = phase
 # The serious punch's own frame (and the next, which carries its cost) is reported on its own.
 var since = Engine.get_process_frames()-host.big_punch_frame
 if since>=0 and since<=2:
  big_punch_ms = maxf(big_punch_ms,real)
  return
 if not stats.has(seg): stats[seg] = {"frames":0,"sum":0.0,"worst":0.0,"worst2":0.0,"gpu":0.0,"cpu":0.0,"draws":0,"prims":0,"vram":0.0,"over33":0,"worst_t":0.0}
 var s = stats[seg]
 s.frames += 1
 s.sum += real
 if real>s.worst:
  s.worst2 = s.worst
  s.worst = real
  s.worst_t = t
 elif real>s.worst2: s.worst2 = real
 if real>33.3:
  s.over33 += 1
  print("GODTEST spike t=%.2f phase=%s frame_ms=%.1f process_ms=%.1f physics_ms=%.1f render_cpu_ms=%.1f gpu_ms=%.1f state=%s mode=%s" % [t,seg,real,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,RenderingServer.viewport_get_measured_render_time_cpu(rid),RenderingServer.viewport_get_measured_render_time_gpu(rid),p.state_name(),host.empire.mode])
 s.gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
 s.cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
 s.draws = maxi(s.draws,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
 s.prims = maxi(s.prims,int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
 s.vram = maxf(s.vram,Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0)

func _finish():
 done = true
 if perf_file != "":
  var f = FileAccess.open(perf_file,FileAccess.WRITE)
  f.store_line("GODTEST perf window=%s" % str(DisplayServer.window_get_size()))
  for seg in stats:
   var s = stats[seg]
   var n = maxf(1.0,s.frames)
   var line = "GODTEST perf %-10s frames=%d avg_ms=%.2f worst_ms=%.1f second_worst_ms=%.1f worst_at_s=%.1f frames_over_33ms=%d gpu_ms=%.2f render_cpu_ms=%.2f draw_calls_max=%d primitives_max=%d vram_mb=%.0f" % [seg,s.frames,s.sum/n,s.worst,s.worst2,s.worst_t,s.over33,s.gpu/n,s.cpu/n,s.draws,s.prims,s.vram]
   f.store_line(line)
   print(line)
  var bp = "GODTEST perf big_punch_frame_ms=%.1f" % big_punch_ms
  f.store_line(bp)
  print(bp)
  f.close()
 host.get_tree().quit(0)

# The nearest standing building in the direction (of 24) whose 140 m cone holds the most standing
# chunks: the punch goes there.
func _densest_direction() -> Vector3:
 # Counted per building (standing chunks in each), not per chunk: cheap enough for one frame.
 var best = 0
 var best_d = Vector3.FORWARD
 for i in 24:
  var a = TAU*i/24.0
  var d = Vector3(cos(a),0,sin(a))
  var n = 0
  for b in host.town.blocks:
   if b.ruined: continue
   var v = b.center-p.global_position
   v.y = 0.0
   if v.length()<140.0 and v.length()>4.0 and v.normalized().dot(d)>cos(0.5): n += b.alive
  if n>best:
   best = n
   best_d = d
 var near = INF
 var tgt = p.global_position+best_d*40.0
 for b in host.town.blocks:
  if b.ruined: continue
  var d = b.center-p.global_position
  d.y = 0.0
  if d.length()<near and d.length()>4.0 and d.normalized().dot(best_d)>cos(0.5):
   near = d.length()
   tgt = b.center
 return tgt
