extends SceneTree
# Headless AI-only campaign soak test (docs/ai-design.md): every faction, the player's included,
# is AI-controlled. Usage:
#   runtime\Godot.exe --headless --path . -s scripts/ai_soak.gd -- [turns] [seed,seed,...] [--verbose]
#     [--traits=faction:trait+trait;...] [--armies=N]
# Per seed: wars declared, battles, captures, factions eliminated, final treasuries and armies,
# stuck armies (never moved while their faction was at war) and idle factions (no action for 10
# turns), AI time per turn; then a determinism check (the first seed played twice).

const GameState = preload("res://core/game_state.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const Armies = preload("res://core/armies.gd")
const Battles = preload("res://core/battles.gd")
const Ai = preload("res://core/ai.gd")
const WorldMap = preload("res://core/world_map.gd")

func _initialize():
 var args = Array(OS.get_cmdline_user_args())
 var turns = int(args[0]) if args.size()>0 and args[0].is_valid_int() else 50
 var seeds = [11,22,33,44,55]
 if args.size()>1 and not args[1].begins_with("--"): seeds = Array(args[1].split(",")).map(func(x): return int(x))
 var verbose = "--verbose" in args
 # --traits=house_lannet:expansionist+cruel;house_verrin:passive overrides faction traits (variants).
 # --armies=N lets every faction keep up to N armies (scaling measurements).
 for a in args:
  if a.begins_with("--traits="):
   for part in a.get_slice("=",1).split(";"):
    WorldMap.faction(part.get_slice(":",0)).traits = Array(part.get_slice(":",1).split("+"))
  if a.begins_with("--armies="):
   Armies.data().armies.max_per_faction = int(a.get_slice("=",1))
   Ai.data().recruitment.base_armies = int(a.get_slice("=",1))
   print("ARMIES up to %d per faction" % int(a.get_slice("=",1)))
 var all_ms = []
 for sd in seeds:
  var r = run(sd,turns,verbose)
  all_ms.append_array(r.ms)
  print("SEED %d | wars %d | battles %d | sieges %d | captures %d | withdrawals %d | landless %d, survived %d, destroyed %s | deserted %d | min treasury %s | eliminated %s | treasury %s | armies %s | settlements %s | stuck %s | idle %s | ai ms avg %.1f max %.1f" % [sd,r.wars,r.battles,r.sieges,r.captures,r.withdrawals,r.graces,r.survived,str(r.destroyed),r.deserted,str(r.min_treasury),str(r.eliminated),str(r.treasury),str(r.armies),str(r.owned),str(r.stuck),str(r.idle),_avg(r.ms),r.ms.max()])
 var a = run(seeds[0],turns,false)
 var b = run(seeds[0],turns,false)
 print("DETERMINISTIC %s" % str(a.hash == b.hash))
 all_ms.sort()
 print("AI_MS all turns: avg %.2f, median %.2f, p95 %.2f, max %.2f" % [_avg(all_ms),all_ms[all_ms.size()/2],all_ms[int(all_ms.size()*0.95)],all_ms.max()])
 quit()

func _avg(a: Array) -> float:
 var s = 0.0
 for x in a: s += x
 return s/maxi(1,a.size())

func run(sd: int,turns: int,verbose: bool) -> Dictionary:
 var s = GameState.from_data(GameState.START,sd)
 var opts = {"factions":s.factions(),"resolve_player":true}
 var start_factions = s.factions().filter(func(f): return not s.settlements_of(f).is_empty())
 var out = {"wars":0,"battles":0,"sieges":0,"captures":0,"withdrawals":0,"ms":[],"eliminated":[],"stuck":[],"idle":[],"graces":0,"survived":0,"deserted":0,"min_treasury":{}}
 var last_pos = {}
 var still = {}
 var last_act = {}
 for f in s.factions(): last_act[f] = 0
 for t in turns:
  var rep = TurnLoop.end_turn(s,opts)
  out.ms.append(rep.ai.ms)
  if rep.ai.ms>30.0 and verbose: print("  SLOW y%d %.1f ms %s actions %s" % [s.year,rep.ai.ms,str(rep.ai.faction_ms),str(rep.ai.actions.map(func(a): return a.action))])
  for a in rep.ai.actions:
   match a.action:
    "war": out.wars += 1
    "battle": out.battles += 1
    "besiege": out.sieges += 1
    "withdraw": out.withdrawals += 1
   if a.action == "battle" and a.captured != "": out.captures += 1
   if a.has("faction"): last_act[a.faction] = t
   if verbose: print("  y%d %s" % [s.year,str(a)])
  for ev in rep.sieges:
   if ev.kind == "surrendered": out.captures += 1
  for ev in rep.realm:
   if ev.kind == "landless": out.graces += 1
   if ev.kind == "survived": out.survived += 1
  for ev in rep.debt:
   if ev.kind == "desertion": out.deserted += int(ev.men)
  for f in s.factions(): out.min_treasury[f] = mini(int(out.min_treasury.get(f,1<<30)),int(s.treasury[f]))
  # Stuck: an army at war that has not moved for 8 turns while outside its own settlement.
  for id in s.army_state:
   var a = s.army_state[id]
   var p = str(a.position)
   if last_pos.get(id,"") == p and a.garrison == "" and not Ai.at_war_with(s,a.faction).is_empty() and not _besieging(s,id): still[id] = still.get(id,0)+1
   else: still[id] = 0
   last_pos[id] = p
   if still[id] == 8 and not id in out.stuck: out.stuck.append(id)
  for f in s.factions():
   if t-last_act[f] == 10 and not f in out.idle and not s.settlements_of(f).is_empty(): out.idle.append(f)
 for f in start_factions:
  if s.settlements_of(f).is_empty(): out.eliminated.append(f)
 out.destroyed = s.destroyed.duplicate()
 out.treasury = {}
 out.armies = {}
 out.owned = {}
 for f in s.factions():
  out.treasury[f] = s.treasury[f]
  out.armies[f] = "%d (%d units)" % [Armies.armies_of(s,f).size(),Armies.armies_of(s,f).reduce(func(n,id): return n+s.army_state[id].units.size(),0)]
  out.owned[f] = s.settlements_of(f).size()
 out.hash = SaveCodec.to_json(s.to_dict()).hash()
 return out

func _besieging(s,id: String) -> bool:
 for sid in s.settlements:
  if s.settlements[sid].get("siege",{}).get("army","") == id: return true
 return false
