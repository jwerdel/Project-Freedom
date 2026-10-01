extends Node
# Unit card portraits, rendered from each unit type's real visual scene in an isolated SubViewport
# (fixed camera angle, lighting and transparent background; the card adds the faction backdrop).
# Results are cached in memory and in user://portrait_cache/, keyed by a hash of the unit data and
# every scene, script and model file its visual uses, so editing the visual re-renders the card.

signal portrait_ready(key: String,texture: Texture2D) # key: "unit:<id>" or "visual:<manifest id>"

const UnitTypes = preload("res://core/unit_types.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const SIZE = Vector2i(200,360)
const THUMB_SIZE = Vector2i(240,200)
const STYLE_VERSION = "portrait-v2"
const CACHE_DIR = "user://portrait_cache/"
const VIEW_DIR = Vector3(-0.42,0.16,1.0)
const BUILDING_DIR = Vector3(-0.8,0.75,1.0)
const FOV = 24.0

var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var _cache = {}
var _queue: Array = []
var _busy = false

func _ready():
 viewport = SubViewport.new()
 viewport.size = SIZE
 viewport.own_world_3d = true
 viewport.transparent_bg = true
 viewport.msaa_3d = Viewport.MSAA_4X
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 add_child(viewport)
 var env = WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_CLEAR_COLOR
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("b4bcc4")
 env.environment.ambient_light_energy = 0.75
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 viewport.add_child(env)
 for l in [[Vector3(-32,-38,0),1.35,Color("fff1dc")],[Vector3(-12,140,0),0.45,Color("c9d6ff")]]:
  var light = DirectionalLight3D.new()
  light.rotation_degrees = l[0]
  light.light_energy = l[1]
  light.light_color = l[2]
  viewport.add_child(light)
 camera = Camera3D.new()
 camera.fov = FOV
 viewport.add_child(camera)
 stage = Node3D.new()
 viewport.add_child(stage)

func has_portrait(unit_id: String) -> bool:
 return _cache.has("unit:"+unit_id)

# Cached unit card portrait, or null after queueing a render (portrait_ready fires when done).
func portrait(unit_id: String) -> Texture2D:
 return _request("unit:"+unit_id)

# Cached building/visual thumbnail for a manifest ID, or null after queueing a render.
func thumbnail(visual_id: String) -> Texture2D:
 return _request("visual:"+visual_id)

# Await these to get a texture directly (used by tests and captures).
func render(unit_id: String) -> Texture2D:
 return await render_key("unit:"+unit_id)

func render_key(key: String) -> Texture2D:
 _request(key)
 # Poll rather than await the signal: a disk-cache hit can finish before we would start waiting.
 while not _cache.has(key): await get_tree().process_frame
 return _cache[key]

func _request(key: String) -> Texture2D:
 if _cache.has(key): return _cache[key]
 if not key in _queue: _queue.append(key)
 if not _busy: _drain()
 # A disk-cache hit finishes synchronously inside _drain, before the caller can connect.
 return _cache.get(key)

func _drain():
 _busy = true
 while not _queue.is_empty():
  var key = _queue.pop_front()
  var tex = await _render(key)
  _cache[key] = tex
  portrait_ready.emit(key,tex)
 _busy = false

func _render(key: String) -> Texture2D:
 var is_unit = key.begins_with("unit:")
 var id = key.get_slice(":",1)
 var unit = UnitTypes.get_type(id) if is_unit else {}
 var size = SIZE if is_unit else THUMB_SIZE
 var hash = cache_key(unit) if is_unit else visual_cache_key(id)
 var path = CACHE_DIR+"%s_%s_%s.png" % [key.get_slice(":",0),id.replace(".","_"),hash]
 if FileAccess.file_exists(path):
  var cached = Image.load_from_file(ProjectSettings.globalize_path(path))
  if cached and not cached.is_empty(): return ImageTexture.create_from_image(cached)
 viewport.size = size
 var node: Node3D
 if is_unit: node = UnitTypes.build_visual(unit,stage)
 else:
  node = AssetManifest.instantiate(id)
  stage.add_child(node)
 await get_tree().process_frame
 _frame(node,unit.card_portrait.get("framing","full_body") if is_unit else "building",size)
 viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 var img = viewport.get_texture().get_image()
 node.queue_free()
 if img == null or img.is_empty():
  # Headless/dummy renderer: no pixels to read; hand back a labeled placeholder.
  img = Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
  img.fill(Color(0.3,0.3,0.3,1))
  var tex = ImageTexture.create_from_image(img)
  tex.set_meta("placeholder",true)
  return tex
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
 img.save_png(ProjectSettings.globalize_path(path))
 return ImageTexture.create_from_image(img)

# Fit the whole visual into the frame with the same camera angle for every unit (or building).
func _frame(node: Node3D,framing: String,size: Vector2i):
 var box = AABB()
 var first = true
 for m in node.find_children("*","MeshInstance3D",true,false):
  if not m.visible or m.mesh == null: continue
  var b = m.global_transform*m.get_aabb()
  box = b if first else box.merge(b)
  first = false
 var center = box.get_center()
 if framing == "building":
  var radius = box.size.length()*0.5
  camera.position = center+BUILDING_DIR.normalized()*radius/sin(deg_to_rad(FOV*0.5))*0.9
 else:
  var aspect = float(size.x)/size.y
  var half_h = maxf(box.size.y*0.5,maxf(box.size.x,box.size.z)*0.5/aspect)*(0.98 if framing=="mounted" else 0.8)
  # Full-body cards sit slightly high so the figure fills the card; feet may crop.
  if framing != "mounted": center.y += box.size.y*0.08
  camera.position = center+VIEW_DIR.normalized()*(half_h/tan(deg_to_rad(FOV*0.5))+maxf(box.size.x,box.size.z)*0.5)
 camera.look_at(center)

func visual_cache_key(visual_id: String) -> String:
 return _files_key([STYLE_VERSION,str(THUMB_SIZE),visual_id],[AssetManifest.scene_path(visual_id)])

# Hash of the unit data plus every file its visual depends on (scenes, their scripts and models).
func cache_key(unit: Dictionary) -> String:
 var scenes = []
 for id in UnitTypes.visual_ids(unit): scenes.append(AssetManifest.scene_path(id))
 return _files_key([STYLE_VERSION,str(SIZE),JSON.stringify(unit,"",true)],scenes)

func _files_key(parts: Array,pending: Array) -> String:
 var seen = {}
 var re = RegEx.create_from_string("path=\"(res://[^\"]+)\"")
 while not pending.is_empty():
  var p = pending.pop_back()
  if seen.has(p): continue
  seen[p] = true
  parts.append(p+":"+FileAccess.get_md5(p))
  if p.ends_with(".tscn") or p.ends_with(".gd"):
   var text = FileAccess.get_file_as_string(p)
   for m in re.search_all(text): pending.append(m.get_string(1))
   for m in RegEx.create_from_string("preload\\(\"(res://[^\"]+)\"\\)").search_all(text): pending.append(m.get_string(1))
 return "|".join(parts).md5_text().substr(0,12)
