extends GutTest
# Save system (core/save_system.gd, core/save_codec.gd): exact round trips, determinism across a
# load, autosave rotation, incompatible and damaged files, atomic writes, and campaign state that
# is in progress (construction, recruitment, multi-turn orders, sieges) surviving a save.

const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const Armies = preload("res://core/armies.gd")
const Construction = preload("res://core/construction.gd")
const Buildings = preload("res://core/buildings.gd")
const Movement = preload("res://core/movement.gd")
const WorldMap = preload("res://core/world_map.gd")
const LoadScreen = preload("res://ui/load_screen.gd")
const HOST = "aurek_host"
const GS = "goldspire_rock"
const TEST_DIR = "user://test_saves"

func before_each():
 SaveSystem.dir = TEST_DIR
 _clear()

func after_each():
 _clear()
 SaveSystem.dir = SaveSystem.DIR
 BattleSim.reset()

func _clear():
 var d = DirAccess.open(TEST_DIR)
 if d == null: return
 for f in d.get_files(): DirAccess.remove_absolute(TEST_DIR+"/"+f)

func near(sid: String) -> Vector2:
 var p = WorldMap.settlement_position(sid)
 return Vector2(p.x+8.0,p.y+4.0)

func place(s,id: String,p: Vector2):
 s.army_state[id].position = [p.x,p.y]
 s.army_state[id].garrison = ""

func empty_slot(s,id: String) -> int:
 var slots = s.settlements[id].buildings
 for i in slots.size():
  if slots[i].is_empty(): return i
 return -1

func roundtrip(s):
 var r = SaveSystem.save(s,"rt","Round trip")
 assert_true(r.ok)
 var l = SaveSystem.load_save("rt")
 assert_true(l.ok,l.get("error",""))
 return l.state

# --- Codec -----------------------------------------------------------------------------------

func test_codec_keeps_types_order_and_exact_floats():
 var v = {"z":1,"a":2.0,"m":0.1+0.2,"pop":1923.9769951954806,"neg":-0.0001,"list":[3,3.0,"3",null,true],"k":{5:"int key"},"__f":"tricky key"}
 var back = SaveCodec.from_json(SaveCodec.to_json(v))
 assert_eq(var_to_str(back),var_to_str(v),"identical values and types")
 assert_eq(back.keys(),v.keys(),"insertion order kept")
 assert_eq(typeof(back.a),TYPE_FLOAT)
 assert_eq(typeof(back.z),TYPE_INT)
 assert_eq(back.m,0.1+0.2,"bit-exact float")
 assert_null(SaveCodec.from_json("{not json"))

# --- Round trip and determinism ----------------------------------------------------------------

func test_round_trip_gives_the_identical_state():
 var s = GameState.from_data()
 Construction.start(s,GS,empty_slot(s,GS),"market")
 for i in 3: TurnLoop.end_turn(s)
 var loaded = roundtrip(s)
 assert_eq(loaded.state_hash(),s.state_hash())
 assert_eq(SaveCodec.to_json(loaded.to_dict()),SaveCodec.to_json(s.to_dict()))
 # A new campaign's random seed is part of the save.
 var n = GameState.new_campaign()
 assert_eq(roundtrip(n).seed,n.seed)

# One scripted campaign year by year: construction, recruitment, two battles, a multi-turn order
# and a siege. Returns the battle results it produced (as JSON).
func act(s) -> Array:
 var out = []
 match s.year:
  1:
   Construction.start(s,GS,empty_slot(s,GS),"market")
   Armies.raise_army(s,"house_aurek","crownwatch")
  2:
   var second = Armies.armies_of(s,"house_aurek").filter(func(a): return a != HOST)
   if not second.is_empty(): Armies.recruit(s,second[0],"peasant_levy")
   place(s,HOST,near("willowmere"))
   var t = Battles.target_at(s,HOST,WorldMap.settlement_position("willowmere"))
   Battles.declare_war(s,"house_aurek",t.faction)
   out.append(JSON.stringify(Battles.quick_resolve(s,Battles.prebattle(s,HOST,t)).result))
  3:
   var second = Armies.armies_of(s,"house_aurek").filter(func(a): return a != HOST)
   if not second.is_empty():
    s.army_state[second[0]].garrison = ""
    assert_true(Movement.order(s,second[0],near("willowmere")).ok,"the scripted march")
  4:
   if s.army_state.has(HOST):
    place(s,HOST,near("greyhaven"))
    Battles.declare_war(s,"house_aurek","house_lannet")
    Battles.besiege(s,HOST,"greyhaven")
  7:
   if s.army_state.has(HOST) and s.settlements.greyhaven.owner != "house_aurek":
    var t = Battles.target_at(s,HOST,WorldMap.settlement_position("greyhaven"))
    out.append(JSON.stringify(Battles.quick_resolve(s,Battles.prebattle(s,HOST,t)).result))
 return out

func play(s,turns: int,battles: Array):
 for i in turns:
  battles.append_array(act(s))
  TurnLoop.end_turn(s)

func test_save_at_turn_5_and_load_plays_on_identically():
 var straight = GameState.from_data()
 var b1 = []
 play(straight,10,b1)
 var split = GameState.from_data()
 var b2 = []
 play(split,5,b2)
 assert_true(split.settlements.greyhaven.has("siege"),"saved mid-siege")
 assert_eq(b2.size(),1,"one battle before the save, one after")
 BattleSim.reset()
 Movement.reset()
 var resumed = roundtrip(split)
 play(resumed,5,b2)
 assert_eq(b1.size(),2,"the script fought two battles")
 assert_eq(b2,b1,"identical battle results")
 assert_eq(resumed.state_hash(),straight.state_hash(),"identical state after 10 turns")
 assert_eq(SaveCodec.to_json(resumed.to_dict()),SaveCodec.to_json(straight.to_dict()))

func test_in_progress_campaign_state_survives_a_save():
 var s = GameState.from_data()
 # A second army recruiting at Crownwatch.
 Armies.raise_army(s,"house_aurek","crownwatch")
 var second = Armies.armies_of(s,"house_aurek").filter(func(a): return a != HOST)[0]
 assert_true(Armies.recruit(s,second,"peasant_levy").ok)
 # The host besieging Greyhaven.
 place(s,HOST,near("greyhaven"))
 Battles.declare_war(s,"house_aurek","house_lannet")
 assert_true(Battles.besiege(s,HOST,"greyhaven").ok)
 TurnLoop.end_turn(s)
 # Construction under way at Goldspire (started after End Turn, so it is mid-build).
 assert_true(Construction.start(s,GS,empty_slot(s,GS),"market").ok)
 # A multi-turn march for the second army (its recruit has arrived).
 s.army_state[second].garrison = ""
 var o = Movement.order(s,second,near("willowmere"))
 assert_true(o.ok,str(o.get("reason",o.get("reasons",""))))
 assert_gt(int(o.turns[-1]),0,"the march takes more than this turn")
 assert_false(s.army_state[second].order.is_empty())
 var loaded = roundtrip(s)
 assert_eq(loaded.state_hash(),s.state_hash())
 assert_eq(loaded.settlements[GS].construction,s.settlements[GS].construction)
 assert_false(loaded.settlements[GS].construction.is_empty(),"construction in progress")
 assert_eq(loaded.army_state[second].order,s.army_state[second].order)
 assert_eq(loaded.settlements.greyhaven.siege,s.settlements.greyhaven.siege)
 assert_eq(loaded.wars,s.wars)
 for k in s.army_state: assert_eq(loaded.army_state[k].get("queue",[]),s.army_state[k].get("queue",[]))
 # And they keep running the same way.
 for i in 3:
  TurnLoop.end_turn(s)
  TurnLoop.end_turn(loaded)
 assert_eq(loaded.state_hash(),s.state_hash())

func test_recruitment_queue_survives_a_save():
 var s = GameState.from_data()
 Armies.raise_army(s,"house_aurek","crownwatch")
 var second = Armies.armies_of(s,"house_aurek").filter(func(a): return a != HOST)[0]
 assert_true(Armies.recruit(s,second,"peasant_levy").ok)
 assert_false(s.army_state[second].queue.is_empty())
 var loaded = roundtrip(s)
 assert_eq(loaded.army_state[second].queue,s.army_state[second].queue)
 TurnLoop.end_turn(s)
 TurnLoop.end_turn(loaded)
 assert_eq(loaded.army_state[second].units,s.army_state[second].units,"the recruit arrives the same way")

# --- Files -----------------------------------------------------------------------------------

func test_autosaves_rotate_through_three_slots():
 var s = GameState.from_data()
 for i in 5:
  assert_true(SaveSystem.autosave(s).ok)
  TurnLoop.end_turn(s)
 var autos = SaveSystem.list().filter(func(m): return m.kind == "auto")
 assert_eq(autos.size(),3,"three slots")
 assert_eq(autos.map(func(m): return int(m.year)),[5,4,3],"the newest three, newest first")
 assert_eq(autos[0].file,"autosave_2","the fifth autosave reused slot 2")
 assert_eq(SaveSystem.latest().file,"autosave_2")
 assert_true(SaveSystem.quicksave(s).ok)
 assert_eq(SaveSystem.latest().file,SaveSystem.QUICKSAVE)

func test_incompatible_or_damaged_saves_fail_with_a_message():
 var s = GameState.from_data()
 assert_true(SaveSystem.save(s,"good","Good").ok)
 var text = FileAccess.get_file_as_string(SaveSystem.path_of("good"))
 var cases = {"newer":text.replace("\"schema\":1","\"schema\":999"),"old":text.replace("\"schema\":1","\"schema\":0"),
  "damaged":text.substr(0,text.length()/2),"Project Freedom save":"{\"hello\":1}"}
 for want in cases:
  var f = FileAccess.open(SaveSystem.path_of("bad"),FileAccess.WRITE)
  f.store_string(cases[want])
  f.close()
  var r = SaveSystem.load_save("bad")
  assert_false(r.ok,want)
  assert_false(r.has("state"),"no half-loaded state")
  assert_string_contains(r.error,want)
 assert_string_contains(SaveSystem.load_save("missing").error,"no longer exists")
 # A damaged file still lists, marked damaged, so it can be deleted.
 assert_eq(SaveSystem.list().filter(func(m): return m.file == "bad")[0].kind,"damaged")
 assert_true(SaveSystem.load_save("good").ok,"other saves are unaffected")

func test_migration_hook_upgrades_old_saves():
 var ran = []
 var migrations = {1:func(d):
  ran.append(1)
  d.state.added_in_v2 = true
  return d}
 var r = SaveSystem.migrate({"schema":1,"state":{}},migrations,2,1)
 assert_true(r.ok)
 assert_eq(ran,[1])
 assert_eq(int(r.data.schema),2)
 assert_true(r.data.state.added_in_v2)
 assert_false(SaveSystem.migrate({"schema":1},{},2,1).ok,"a missing migration is reported")

func test_an_interrupted_save_leaves_the_old_file_intact():
 var s = GameState.from_data()
 assert_true(SaveSystem.save(s,"slot","Before").ok)
 var before = FileAccess.get_file_as_string(SaveSystem.path_of("slot"))
 var later = GameState.from_data()
 for i in 2: TurnLoop.end_turn(later)
 var r = SaveSystem.save(later,"slot","After","manual",null,true)
 assert_false(r.ok)
 assert_true(FileAccess.file_exists(SaveSystem.path_of("slot")+".tmp"),"the crash left only the temp file")
 assert_eq(FileAccess.get_file_as_string(SaveSystem.path_of("slot")),before,"old save byte-identical")
 var l = SaveSystem.load_save("slot")
 assert_true(l.ok)
 assert_eq(l.state.state_hash(),s.state_hash())
 assert_eq(SaveSystem.list().size(),1,"temp files are not listed")
 # The next save completes normally over the leftover temp file.
 assert_true(SaveSystem.save(later,"slot","After").ok)
 assert_false(FileAccess.file_exists(SaveSystem.path_of("slot")+".tmp"))
 assert_eq(SaveSystem.load_save("slot").state.state_hash(),later.state_hash())

func test_save_names_list_and_delete():
 var s = GameState.from_data()
 assert_eq(SaveSystem.file_for("  My Campaign: Year 3! "),"save_my_campaign_year_3")
 SaveSystem.save(s,SaveSystem.file_for("First"),"First")
 TurnLoop.end_turn(s)
 SaveSystem.save(s,SaveSystem.file_for("Second"),"Second")
 var l = SaveSystem.list()
 assert_eq(l.map(func(m): return m.name),["Second","First"],"newest first")
 assert_eq(int(l[0].year),2)
 assert_eq(l[0].faction_name,"House Aurek")
 assert_true(SaveSystem.delete(l[1].file))
 assert_eq(SaveSystem.list().size(),1)

func test_load_screen_lists_saves_and_confirms_delete():
 var s = GameState.from_data()
 SaveSystem.save(s,"a","Alpha")
 SaveSystem.save(s,"b","Beta")
 var screen = LoadScreen.new()
 add_child_autofree(screen)
 assert_eq(screen.list.get_child_count(),2)
 var row = screen.list.get_child(0)
 assert_eq(row.name,"Save_b","newest first")
 var del: Button = row.find_child("Delete",true,false)
 del.pressed.emit()
 var confirm = row.find_child("Confirm",true,false)
 assert_true(confirm.visible,"delete asks first")
 assert_true(FileAccess.file_exists(SaveSystem.path_of("b")))
 (confirm.find_child("Yes",true,false) as Button).pressed.emit()
 assert_false(FileAccess.file_exists(SaveSystem.path_of("b")))
 var loaded = []
 screen.load_requested.connect(func(f): loaded.append(f))
 await get_tree().process_frame
 (screen.list.get_child(screen.list.get_child_count()-1).find_child("Load",true,false) as Button).pressed.emit()
 assert_eq(loaded,["a"])
