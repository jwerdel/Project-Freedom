extends SceneTree
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

func line(key: String,value,budget := ""):
 print("SCALE %s = %s%s" % [key,str(value),"  (budget %s)" % budget if budget != "" else ""])

func _initialize():
 var map_id = "synthetic600"
 var turns = 3
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--map="): map_id = a.get_slice("=",1)
  if a.begins_with("--turns="): turns = int(a.get_slice("=",1))
 MapRegistry.set_active(map_id)
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
 t = Time.get_ticks_usec()
 var first = Movement.plan(s,a0,start+Vector2(40,25))
 line("path_first_ms_including_grid_build",(Time.get_ticks_usec()-t)/1000.0)
 var times = []
 var long_times = []
 for i in 20:
  var aid = ids[(i*37)%ids.size()]
  var p0 = Movement.position(s,aid)
  t = Time.get_ticks_usec()
  Movement.plan(s,aid,p0+Vector2.from_angle(i)*60.0)
  times.append((Time.get_ticks_usec()-t)/1000.0)
  t = Time.get_ticks_usec()
  Movement.plan(s,aid,p0+Vector2.from_angle(i)*400.0)
  long_times.append((Time.get_ticks_usec()-t)/1000.0)
 times.sort()
 long_times.sort()
 line("path_60m_median_ms",times[times.size()/2],"5 per preview update")
 line("path_60m_max_ms",times[-1])
 line("path_400m_median_ms",long_times[long_times.size()/2],"5 per preview update")
 line("path_400m_max_ms",long_times[-1])
 # --- End Turn: every faction AI-run (the player's too) ---------------------------------------------
 s.player_faction = "" # no human: all factions run by the AI
 var turn_ms = []
 for k in turns:
  t = Time.get_ticks_usec()
  var r = TurnLoop.end_turn(s)
  turn_ms.append((Time.get_ticks_usec()-t)/1000.0)
  line("end_turn_%d_ms" % (k+1),turn_ms[-1],"4000 release build, V1 Varos")
 line("memory_static_mb_after_turns",snappedf((OS.get_static_memory_usage()-mem0)/1048576.0,0.1),"2500 total RAM")
 # --- Save and load ----------------------------------------------------------------------------------
 SaveSystem.dir = "user://scale_test_saves"
 t = Time.get_ticks_usec()
 var sv = SaveSystem.save(s,"scale","Scale test")
 line("save_ms",(Time.get_ticks_usec()-t)/1000.0,"100")
 line("save_kb",FileAccess.get_file_as_bytes(SaveSystem.path_of("scale")).size()/1024,"5120")
 t = Time.get_ticks_usec()
 var ld = SaveSystem.load_save("scale")
 line("load_save_ms",(Time.get_ticks_usec()-t)/1000.0,"3000")
 line("load_save_ok",ld.ok)
 SaveSystem.delete("scale")
 quit(0)
