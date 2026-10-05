extends RefCounted
# Campaign saves: one JSON file per save in user://saves (the launcher redirects user:// into the
# ignored .local folder), plus an optional PNG thumbnail beside it.
#   {schema, meta: {name, kind, faction, faction_name, year, turn, seed, saved_at, saved_text, seq},
#    state: GameState.to_dict() through core/save_codec.gd}
# Writes go to a .tmp file that is then renamed over the old save, so a crash mid-save leaves the
# previous save intact. Loads check the schema version and run migrations; anything unreadable or
# from an incompatible version returns {ok: false, error} with a message for the player, never a
# half-loaded state.

const SaveCodec = preload("res://core/save_codec.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const SCHEMA = 5
const OLDEST = 1 # oldest schema a migration chain still reaches
const DIR = "user://saves"
const AUTOSAVES = 3
const QUICKSAVE = "quicksave"
const THUMB = Vector2i(320,200)
const BACKDROP = Vector2i(960,600)
# Migration hook: migrations()[n] turns a schema-n save dictionary into schema n+1. Add one each
# time SCHEMA rises (and keep OLDEST at the first version still convertible).
static func migrations() -> Dictionary:
 return {1:_v1_to_v2,2:_v2_to_v3,3:_v3_to_v4,4:_v4_to_v5}

# Schema 2 (campaign AI block): pending AI attacks on the player and the camera view are saved.
# A schema-1 save has neither: no pending attacks, and the default camera.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
 if d.get("state") is Dictionary and not d.state.has("pending_battles"): d.state.pending_battles = []
 return d

# Schema 3 (debt and loss condition block): grace periods and destroyed factions are saved. A
# schema-2 save has none in progress.
static func _v2_to_v3(d: Dictionary) -> Dictionary:
 if d.get("state") is Dictionary:
  if not d.state.has("grace"): d.state.grace = {}
  if not d.state.has("destroyed"): d.state.destroyed = []
 return d

# Schema 4 (map pipeline): a campaign records its map and the map's version. Every older save was
# made on the prototype map, now the test map, version 1.
static func _v3_to_v4(d: Dictionary) -> Dictionary:
 if d.get("state") is Dictionary:
  if not d.state.has("map_id"): d.state.map_id = "testmap" # the prototype map, now retired (below)
  if not d.state.has("map_version"): d.state.map_version = 1
 return d

# Schema 5 (land conversion): each region's land culture. Older saves start with every region's land
# as its owner's culture (GameState.from_dict fills it in when absent).
static func _v4_to_v5(d: Dictionary) -> Dictionary:
 return d

static var dir := DIR # tests and captures point this elsewhere
static var _pending: Array = [] # worker tasks writing thumbnails

static func path_of(file: String) -> String:
 return "%s/%s.json" % [dir,file]

static func thumb_of(file: String) -> String:
 return "%s/%s.jpg" % [dir,file]

static func backdrop_path() -> String:
 return dir+"/menu_backdrop.jpg"

# A file name from a player-chosen save name.
static func file_for(name: String) -> String:
 var s = ""
 for c in name.strip_edges().to_lower():
  s += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
 while s.contains("__"): s = s.replace("__","_")
 s = s.trim_prefix("_").trim_suffix("_")
 return "save_"+(s if s != "" else "unnamed")

# Save the state. kind: manual, auto or quick. thumbnail: an Image (scaled down here) or null.
# _interrupt (tests only): stop after writing the temp file, as a crash would.
# view: the camera ({target: [x,y,z], yaw, pitch, distance}), restored on load.
# background: encode and write on a worker thread (the game: autosave, quicksave, manual saves);
# otherwise the save is complete on return (tests, tools).
static func save(state,file: String,name: String,kind := "manual",thumbnail: Image = null,_interrupt := false,view := {},background := false) -> Dictionary:
 # One write at a time, in order (a later save of the same slot must land last).
 wait_for_saves()
 DirAccess.make_dir_recursive_absolute(dir)
 var t0 = Time.get_ticks_usec()
 var now = Time.get_datetime_dict_from_system()
 var meta = {"name":name,"kind":kind,"faction":state.player_faction,"faction_name":WorldMap.faction(state.player_faction).get("name",state.player_faction),
  "year":state.year,"turn":state.turn,"seed":state.seed,"saved_at":Time.get_unix_time_from_system(),
  "saved_text":"%04d-%02d-%02d %02d:%02d" % [now.year,now.month,now.day,now.hour,now.minute],"seq":_next_seq()}
 # The main thread only copies the state; encoding and writing run on a worker thread (the game
 # keeps running), and every reader (load, list, meta, delete) waits for the write first.
 var job = {"meta":meta,"view":view.duplicate(true),"state":state.to_dict(),"path":path_of(file),"file":file,"interrupt":_interrupt}
 var main_ms = (Time.get_ticks_usec()-t0)/1000.0
 if _interrupt or not background:
  _write_save(job)
  var r = _save_result.duplicate()
  if r.ok: r.ms = (Time.get_ticks_usec()-t0)/1000.0
  if not r.ok or _interrupt: return r
 else: _save_task = WorkerThreadPool.add_task(_write_save.bind(job))
 if thumbnail != null and not thumbnail.is_empty():
  # Scaling and encoding the pictures runs on a worker thread so End Turn does not hitch; each
  # file still lands atomically. wait_for_images() waits for them (tests, quitting).
  _pending = _pending.filter(func(t):
   if not WorkerThreadPool.is_task_completed(t): return true
   WorkerThreadPool.wait_for_task_completion(t)
   return false)
  _pending.append(WorkerThreadPool.add_task(_write_images.bind(thumb_of(file),backdrop_path(),thumbnail)))
 elif FileAccess.file_exists(thumb_of(file)): DirAccess.remove_absolute(thumb_of(file))
 if not background: return _save_result.merged({"ms":(Time.get_ticks_usec()-t0)/1000.0},true)
 return {"ok":true,"file":file,"path":path_of(file),"ms":main_ms,"meta":meta,"background":true}

static var _save_task := -1
static var _save_result = {}

# Worker: encode, write the save atomically, then its small meta sidecar (read by lists and slots
# without parsing the whole save).
static func _write_save(job: Dictionary):
 var t0 = Time.get_ticks_usec()
 var text = JSON.stringify({"schema":SCHEMA,"meta":job.meta,"view":SaveCodec.encode(job.view),"state":SaveCodec.encode(job.state)},"",false,true)
 var err = _write_atomic(job.path,text.to_utf8_buffer(),job.interrupt)
 if err != OK:
  _save_result = {"ok":false,"error":"Could not write the save (%s)." % error_string(err)}
  return
 if job.interrupt:
  _save_result = {"ok":false,"error":"interrupted"}
  return
 var side = JSON.stringify({"schema":SCHEMA,"meta":SaveCodec.encode(job.meta)})
 _write_atomic(meta_of(job.file),side.to_utf8_buffer())
 _save_result = {"ok":true,"file":job.file,"path":job.path,"bytes":text.length(),"write_ms":(Time.get_ticks_usec()-t0)/1000.0,"meta":job.meta}

# Wait for the save being written (if any); its result ({ok, bytes, write_ms, ...} or the error).
static func wait_for_saves() -> Dictionary:
 if _save_task >= 0:
  WorkerThreadPool.wait_for_task_completion(_save_task)
  _save_task = -1
 return _save_result

static func meta_of(file: String) -> String:
 return "%s/%s.meta" % [dir,file]

static func _write_atomic(path: String,bytes: PackedByteArray,interrupt := false,tmp_tag := "") -> int:
 var tmp = path+tmp_tag+".tmp"
 var f = FileAccess.open(tmp,FileAccess.WRITE)
 if f == null: return FileAccess.get_open_error()
 f.store_buffer(bytes)
 f.flush()
 f.close()
 if interrupt: return OK
 # rename replaces the old file in one step; if it ever fails the old save is still there.
 return DirAccess.rename_absolute(tmp,path)

# Load a save: {ok, state, meta} or {ok: false, error}.
static func load_save(file: String) -> Dictionary:
 wait_for_saves()
 var path = path_of(file)
 if not FileAccess.file_exists(path): return {"ok":false,"error":"The save \"%s\" no longer exists." % file}
 var t0 = Time.get_ticks_usec()
 var j = JSON.new()
 if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary): return {"ok":false,"error":"The save \"%s\" is damaged and cannot be read." % file}
 var r = migrate(j.data)
 if not r.ok: return r
 var data = r.data
 var state_dict = SaveCodec.decode(data.get("state"))
 if not (state_dict is Dictionary): return {"ok":false,"error":"The save \"%s\" is damaged: no campaign state." % file}
 for k in ["seed","year","turn","player_faction","treasury","settlements","armies","army_state","road_level","wars","battles","chronicle"]:
  if not state_dict.has(k): return {"ok":false,"error":"The save \"%s\" is damaged: missing %s." % [file,k]}
 # The save's map must exist in this version, at the same map version: during development, saves
 # across map versions are incompatible (docs/map-pipeline-design.md §7, Q11).
 var map_id = str(state_dict.get("map_id",MapRegistry.DEFAULT))
 if not map_id in MapRegistry.maps(): return {"ok":false,"error":"The save \"%s\" was made on the map \"%s\", which this version of the game does not have." % [file,map_id]}
 # Retired maps (map.json "retired"): the campaign moved to another map, so their saves no longer load.
 if MapRegistry.meta(map_id).get("retired",false):
  return {"ok":false,"error":"The save \"%s\" was made on %s, which the campaign no longer uses (it now plays on %s). Start a new campaign." % [file,MapRegistry.meta(map_id).get("name",map_id),MapRegistry.meta(MapRegistry.DEFAULT).get("name",MapRegistry.DEFAULT)]}
 if int(state_dict.get("map_version",1)) != MapRegistry.version(map_id):
  return {"ok":false,"error":"The save \"%s\" was made with an older version of the map \"%s\" (map version %d, now %d) and cannot be loaded." % [file,MapRegistry.meta(map_id).get("name",map_id),int(state_dict.get("map_version",1)),MapRegistry.version(map_id)]}
 MapRegistry.set_active(map_id)
 var state = GameState.from_dict(state_dict)
 # References the current world data must still know (a save from another map cannot load).
 for id in state.settlements:
  if not id in WorldMap.settlement_ids(): return {"ok":false,"error":"The save \"%s\" was made for a different map (unknown settlement %s)." % [file,id]}
 var view = SaveCodec.decode(data.get("view",{}))
 return {"ok":true,"state":state,"meta":SaveCodec.decode(data.get("meta",{})),"view":view if view is Dictionary else {},"ms":(Time.get_ticks_usec()-t0)/1000.0}

# Bring a parsed save up to SCHEMA, or explain why it cannot be.
static func migrate(data: Dictionary,table = null,current := SCHEMA,oldest := OLDEST) -> Dictionary:
 var steps: Dictionary = table if table != null else migrations()
 if not data.has("schema"): return {"ok":false,"error":"This file is not a Project Freedom save."}
 var v = int(data.schema)
 if v>current: return {"ok":false,"error":"This save was made by a newer version of the game (save format %d, this version reads up to %d)." % [v,current]}
 if v<oldest: return {"ok":false,"error":"This save is from an old version of the game that can no longer be loaded (save format %d, oldest supported %d)." % [v,oldest]}
 while v<current:
  if not steps.has(v): return {"ok":false,"error":"No upgrade path for save format %d." % v}
  data = steps[v].call(data)
  v += 1
  data.schema = v
 return {"ok":true,"data":data}

# All saves, newest first: [{file, name, kind, faction, faction_name, year, turn, saved_text, thumb}].
static func list() -> Array:
 wait_for_saves()
 var out = []
 var d = DirAccess.open(dir)
 if d == null: return out
 for f in d.get_files():
  if not f.ends_with(".json"): continue
  var file = f.get_basename()
  var meta = read_meta(file)
  if meta.is_empty(): continue
  meta.file = file
  meta.thumb = thumb_of(file) if FileAccess.file_exists(thumb_of(file)) else ""
  out.append(meta)
 out.sort_custom(func(a,b): return int(a.get("seq",0))>int(b.get("seq",0)))
 return out

# A save's meta block without decoding its state ({} if unreadable). Unreadable saves still list,
# marked damaged, so the player can delete them.
static func read_meta(file: String) -> Dictionary:
 wait_for_saves()
 var path = path_of(file)
 if not FileAccess.file_exists(path): return {}
 # The sidecar holds the meta of saves made since the background-write change; older saves are
 # parsed in full.
 if FileAccess.file_exists(meta_of(file)) and FileAccess.get_modified_time(meta_of(file)) >= FileAccess.get_modified_time(path):
  var sj = JSON.parse_string(FileAccess.get_file_as_string(meta_of(file)))
  if sj is Dictionary and sj.has("meta"):
   var sm = SaveCodec.decode(sj.meta)
   if sm is Dictionary and sm.has("name"):
    sm.schema = int(sj.get("schema",0))
    return sm
 var j = JSON.new()
 if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
  return {"name":file,"kind":"damaged","faction":"","faction_name":"Damaged save","year":0,"turn":0,"saved_text":"","seq":0}
 var meta = SaveCodec.decode(j.data.get("meta",{}))
 if not (meta is Dictionary) or not meta.has("name") or not j.data.has("state"):
  return {"name":file,"kind":"damaged","faction":"","faction_name":"Damaged save","year":0,"turn":0,"saved_text":"","seq":0}
 meta.schema = int(j.data.get("schema",0))
 return meta

static func latest() -> Dictionary:
 var l = list().filter(func(m): return m.kind != "damaged")
 return l[0] if not l.is_empty() else {}

static func delete(file: String) -> bool:
 wait_for_saves()
 if FileAccess.file_exists(meta_of(file)): DirAccess.remove_absolute(meta_of(file))
 var ok = DirAccess.remove_absolute(path_of(file)) == OK
 if FileAccess.file_exists(thumb_of(file)): DirAccess.remove_absolute(thumb_of(file))
 return ok

# Save order: one more than the highest seq in the save folder, scanned once per folder and then
# counted up (the scan reads the meta sidecars, so it stays cheap).
static var _seq = {} # save folder -> last seq used
static func _next_seq() -> int:
 if not _seq.has(dir):
  var n = 0
  var d = DirAccess.open(dir)
  if d != null:
   for f in d.get_files():
    if f.ends_with(".json"): n = maxi(n,int(read_meta(f.get_basename()).get("seq",0)))
  _seq[dir] = n
 _seq[dir] += 1
 return _seq[dir]

# Autosave at the start of End Turn into the oldest of AUTOSAVES rotating slots.
static func autosave(state,thumbnail: Image = null,view := {}) -> Dictionary:
 var slot = 1
 var oldest = 1<<62
 for i in range(1,AUTOSAVES+1):
  var m = read_meta("autosave_%d" % i)
  if m.is_empty():
   slot = i
   break
  if int(m.get("seq",0))<oldest:
   oldest = int(m.get("seq",0))
   slot = i
 return save(state,"autosave_%d" % slot,"Autosave, year %d" % state.year,"auto",thumbnail,false,view,true)

static func quicksave(state,thumbnail: Image = null,view := {}) -> Dictionary:
 return save(state,QUICKSAVE,"Quicksave","quick",thumbnail,false,view,true)

# Thumbnail (load screen) and the main menu's backdrop (the latest saved view, larger).
static func _write_images(thumb_path: String,backdrop: String,source: Image):
 var img = source.duplicate()
 img.resize(THUMB.x,THUMB.y,Image.INTERPOLATE_BILINEAR)
 var tag = ".%d" % OS.get_thread_caller_id() # overlapping saves never share a temp file
 _write_atomic(thumb_path,img.save_jpg_to_buffer(0.85),false,tag)
 var big = source.duplicate()
 big.resize(BACKDROP.x,BACKDROP.y,Image.INTERPOLATE_BILINEAR)
 _write_atomic(backdrop,big.save_jpg_to_buffer(0.85),false,tag)

static func wait_for_images():
 wait_for_saves()
 for task in _pending: WorkerThreadPool.wait_for_task_completion(task)
 _pending.clear()

# Non-blocking: the result of the background write once it has finished ({} while still writing or
# when nothing is pending). The map polls this to report a failed save.
static func poll_saves() -> Dictionary:
 if _save_task >= 0 and WorkerThreadPool.is_task_completed(_save_task): return wait_for_saves()
 return {}
