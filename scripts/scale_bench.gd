extends Node
# Scale test, CPU half (docs/map-pipeline-design.md §6.2), headless:
#   runtime\Godot.exe --headless --path . -s scripts/scale_test.gd -- [--map=synthetic600] [--turns=3]
# Build the map first (scripts/build_map.gd). Measures campaign load, memory, region lookups, path
# planning, End Turn with every faction run by the AI, and save/load. The GPU half (frame time,
# draw calls, VRAM, strategic map) runs windowed: Main.tscn -- --map-view=<map> --scale-capture.
# Prints one SCALE line per measurement; the debug (editor) build is slower than a release build.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const SaveSystem = preload("res://core/save_system.gd")

var out_file: FileAccess = null # --out=<path>: the lines also go to this file (release builds have no console)

func line(key: String,value,budget := ""):
 var text = "SCALE %s = %s%s" % [key,str(value),"  (budget %s)" % budget if budget != "" else ""]
 print(text)
 if out_file: out_file.store_line(text)

func _ready():
 var map_id = "synthetic600"
 var turns = 3
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--map="): map_id = a.get_slice("=",1)
  if a.begins_with("--turns="): turns = int(a.get_slice("=",1))
  if a.begins_with("--out="): out_file = FileAccess.open(a.get_slice("=",1),FileAccess.WRITE)
 MapRegistry.set_active(map_id)
 # --render-cache: time the first-run render cache build (heights, colours, rivers; map/pipeline.gd).
 if "--render-cache" in OS.get_cmdline_user_args():
  var tr = Time.get_ticks_usec()
  var rr = load("res://map/pipeline.gd").build(map_id,false)
  line("render_cache_build_ms",(Time.get_ticks_usec()-tr)/1000.0,"30000 first run")
  line("render_cache_errors",str(rr.errors))
 var mem0 = OS.get_static_memory_usage()
 # --- Load -------------------------------------------------------------------------------------
 var t = Time.get_ticks_usec()
 WorldMap.regions()
 var t_world = Time.get_ticks_usec()-t
 t = Time.get_ticks_usec()
 Movement.grid()
 var t_grid = Time.get_ticks_usec()-t
 t = Time.get_ticks_usec()
 var s = GameState.from_data()
 var t_state = Time.get_ticks_usec()-t
 # A map without starting armies yet (Varos before its Stage A content): one army of 8 units per
 # faction at its first settlement, so paths and End Turn have work (benchmark only).
 if s.army_state.is_empty():
  var Armies = load("res://core/armies.gd")
  var kinds = ["spearmen","swordsmen","archers","heavy_infantry","peasant_levy","cavalry"]
  for f in s.factions():
   var own = s.settlements_of(f)
   if own.is_empty(): continue
   s.treasury[f] = 100000
   var r = Armies.raise_army(s,f,own[0])
   if not r.ok: continue
   for i in 8: s.army_state[r.army].units.append({"unit":kinds[i%kinds.size()],"men":100,"max_men":100})
  line("bench_armies_added",s.army_state.size())
 line("map",map_id)
 line("regions",WorldMap.settlement_ids().size())
 line("factions",s.factions().size())
 line("armies",s.army_state.size())
 line("load_world_ms",t_world/1000.0)
 line("load_grid_ms",t_grid/1000.0)
 line("load_state_ms",t_state/1000.0)
 line("load_total_ms",(t_world+t_grid+t_state)/1000.0,"10000 warm, gameplay data part")
 line("memory_static_mb_after_load",snappedf((OS.get_static_memory_usage()-mem0)/1048576.0,0.1),"2500 total RAM")
 # --- region_at ----------------------------------------------------------------------------------
 var rng = RandomNumberGenerator.new()
 rng.seed = 1
 var size = Vector2(MapRegistry.meta().size[0],MapRegistry.meta().size[1])
 var pts = []
 for i in 100000: pts.append(Vector2(rng.randf()*size.x,rng.randf()*size.y))
 t = Time.get_ticks_usec()
 for p in pts: WorldMap.region_at(p)
 line("region_at_us",snappedf((Time.get_ticks_usec()-t)/100000.0,0.001),"10 (0.01 ms)")
 # --- Paths ----------------------------------------------------------------------------------------
 var ids = s.army_state.keys()
 ids.sort()
 var a0 = ids[0]
 var start = Movement.position(s,a0)
 # One-time per session: the pathfinding grid from the baked runs, plus the path hierarchy.
 t = Time.get_ticks_usec()
 Movement._astar_for(s.road_level)
 line("path_grid_and_hierarchy_build_ms_once",(Time.get_ticks_usec()-t)/1000.0)
 # Each plan as a fresh preview update: the blocking sync is forced (a new frame would do it).
 for dist in [60.0,150.0,400.0,1000.0]:
  var ts = []
  var none = 0
  for i in 100:
   var aid = ids[(i*37)%ids.size()]
   var p0 = Movement.position(s,aid)
   Movement._blk_key = []
   t = Time.get_ticks_usec()
   var r = Movement.plan(s,aid,p0+Vector2.from_angle(i*0.7)*dist)
   ts.append((Time.get_ticks_usec()-t)/1000.0)
   if not r.ok: none += 1
  ts.sort()
  var tag = "path_%dm" % int(dist)
  line(tag+"_median_ms",snappedf(ts[50],0.01),"5")
  line(tag+"_p95_ms",snappedf(ts[95],0.01),"5")
  line(tag+"_max_ms",snappedf(ts[-1],0.01))
  line(tag+"_not_possible",none)
 # The held-right-click preview's first frame on long moves: the coarse route (the full plan
 # follows on the next frame, measured above).
 var tc = []
 for i in 100:
  var aid = ids[(i*37)%ids.size()]
  var p0 = Movement.position(s,aid)
  t = Time.get_ticks_usec()
  Movement.coarse_plan(s,aid,p0+Vector2.from_angle(i*0.7)*1000.0)
  tc.append((Time.get_ticks_usec()-t)/1000.0)
 tc.sort()
 line("preview_coarse_1000m_p95_ms",snappedf(tc[95],0.01),"5")
 # --- End Turn: every faction AI-run (the player's too) ---------------------------------------------
 s.player_faction = "" # no human: all factions run by the AI
 var turn_ms = []
 for k in turns:
  t = Time.get_ticks_usec()
  var r = TurnLoop.end_turn(s)
  turn_ms.append((Time.get_ticks_usec()-t)/1000.0)
  line("end_turn_%d_ms" % (k+1),turn_ms[-1],"4000 release build, V1 Varos")
 # The game spreads End Turn over frames: the longest stretch without a frame is what the player
 # could notice (budget 12 ms of work per frame).
 if turns>0:
  t = Time.get_ticks_usec()
  var rs = await TurnLoop.end_turn_sliced(s,get_tree(),12.0)
  line("end_turn_sliced_ms",(Time.get_ticks_usec()-t)/1000.0,"10000 release build")
  line("end_turn_sliced_frames",rs.frames)
  line("end_turn_sliced_longest_chunk_ms",snappedf(rs.max_chunk_ms,0.1),"UI responsive")
  line("end_turn_sliced_longest_chunk_at",rs.max_chunk_at)
  var fm = rs.ai.faction_ms.values()
  fm.sort()
  line("ai_faction_ms_max",snappedf(fm[-1],0.1))
  line("ai_faction_ms_p95",snappedf(fm[int(fm.size()*0.95)],0.1))
 line("memory_static_mb_after_turns",snappedf((OS.get_static_memory_usage()-mem0)/1048576.0,0.1),"2500 total RAM")
 # --- Save and load ----------------------------------------------------------------------------------
 SaveSystem.dir = "user://scale_test_saves"
 SaveSystem.save(s,"scale_warm","Warm-up")
 t = Time.get_ticks_usec()
 var sv = SaveSystem.save(s,"scale","Scale test","auto",null,false,{},true)
 line("save_main_thread_ms",(Time.get_ticks_usec()-t)/1000.0,"100 on the main thread")
 var written = SaveSystem.wait_for_saves()
 line("save_background_write_ms",snappedf(float(written.get("write_ms",0.0)),0.1))
 t = Time.get_ticks_usec()
 SaveSystem.save(s,"scale_sync","Synchronous")
 line("save_synchronous_ms",(Time.get_ticks_usec()-t)/1000.0)
 SaveSystem.delete("scale_warm")
 SaveSystem.delete("scale_sync")
 line("save_kb",FileAccess.get_file_as_bytes(SaveSystem.path_of("scale")).size()/1024,"5120")
 t = Time.get_ticks_usec()
 var ld = SaveSystem.load_save("scale")
 line("load_save_ms",(Time.get_ticks_usec()-t)/1000.0,"3000")
 line("load_save_ok",ld.ok)
 SaveSystem.delete("scale")
 line("build","debug" if OS.is_debug_build() else "release")
 if out_file: out_file.close()
 get_tree().quit(0)
