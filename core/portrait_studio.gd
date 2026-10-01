extends Node
# Unit card portraits, rendered from each unit type's real visual scene in an isolated SubViewport
# (fixed camera angle, lighting and transparent background; the card adds the faction backdrop).
# Results are cached in memory and in user://portrait_cache/, keyed by a hash of the unit data and
# every scene, script and model file its visual uses, so editing the visual re-renders the card.

signal portrait_ready(unit_id: String,texture: Texture2D)

const UnitTypes = preload("res://core/unit_types.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const SIZE = Vector2i(200,360)
const STYLE_VERSION = "portrait-v1"
const CACHE_DIR = "user://portrait_cache/"
const VIEW_DIR = Vector3(-0.42,0.16,1.0)
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
 return _cache.has(unit_id)

# Cached texture, or null after queueing a render (portrait_ready fires when it is done).
func portrait(unit_id: String) -> Texture2D:
 if _cache.has(unit_id): return _cache[unit_id]
 if not unit_id in _queue: _queue.append(unit_id)
 if not _busy: _drain()
 return null

# Await this to get a portrait directly (used by tests and captures).
func render(unit_id: String) -> Texture2D:
 portrait(unit_id)
 # Poll rather than await the signal: a disk-cache hit can finish before we would start waiting.
 while not _cache.has(unit_id): await get_tree().process_frame
 return _cache[unit_id]

func _drain():
 _busy = true
 while not _queue.is_empty():
  var id = _queue.pop_front()
  var tex = await _render(id)
  _cache[id] = tex
  portrait_ready.emit(id,tex)
 _busy = false

func _render(unit_id: String) -> Texture2D:
 var unit = UnitTypes.get_type(unit_id)
 var path = CACHE_DIR+"%s_%s.png" % [unit_id,cache_key(unit)]
 if FileAccess.file_exists(path):
  var cached = Image.load_from_file(ProjectSettings.globalize_path(path))
  if cached and not cached.is_empty(): return ImageTexture.create_from_image(cached)
 var node = UnitTypes.build_visual(unit,stage)
 await get_tree().process_frame
 _frame(node,unit.card_portrait.get("framing","full_body"))
 viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
 await RenderingServer.frame_post_draw
 await RenderingServer.frame_post_draw
 var img = viewport.get_texture().get_image()
 node.queue_free()
 if img == null or img.is_empty():
  # Headless/dummy renderer: no pixels to read; hand back a labeled placeholder.
  img = Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
  img.fill(Color(0.3,0.3,0.3,1))
  var tex = ImageTexture.create_from_image(img)
  tex.set_meta("placeholder",true)
  return tex
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
 img.save_png(ProjectSettings.globalize_path(path))
 return ImageTexture.create_from_image(img)

# Fit the whole visual into the tall card with the same camera angle for every unit.
func _frame(node: Node3D,framing: String):
 var box = AABB()
 var first = true
 for m in node.find_children("*","MeshInstance3D",true,false):
  if not m.visible or m.mesh == null: continue
  var b = m.global_transform*m.get_aabb()
  box = b if first else box.merge(b)
  first = false
 var aspect = float(SIZE.x)/SIZE.y
 var half_h = maxf(box.size.y*0.5,maxf(box.size.x,box.size.z)*0.5/aspect)*(1.0 if framing=="mounted" else 0.94)
 var center = box.get_center()
 var dist = half_h/tan(deg_to_rad(FOV*0.5))+maxf(box.size.x,box.size.z)*0.5
 camera.position = center+VIEW_DIR.normalized()*dist
 camera.look_at(center)

# Hash of the unit data plus every file its visual depends on (scenes, their scripts and models).
func cache_key(unit: Dictionary) -> String:
 var parts = [STYLE_VERSION,str(SIZE),JSON.stringify(unit,"",true)]
 var seen = {}
 var pending = []
 for id in UnitTypes.visual_ids(unit): pending.append(AssetManifest.scene_path(id))
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
