extends Node3D
# Edric Varn, the god of the look test: the rigged model and Mixamo animations from
# art_source/lords/edric_varn/ (copied to assets/characters/edric_varn/), scaled to god_height
# (1.5x a human). Clips: walk (walking.fbx), fly (flying.fbx), punch (punching.fbx), fall
# (falling_idle.fbx), land (falling_to_landing.fbx), jump (wh.fbx: a crouch and leap). Root motion is removed
# (the controller moves the body). States without a clip get a procedural pose on top
# (god/pose_mod.gd) or a stand-in: idle (the landing clip's last frame, breathing), run and sprint (the
# walk sped up, leaning), wall-run, glide, charge, dash, and the superhero landing (the landing clip).

const PoseMod = preload("res://god/pose_mod.gd")
const DIR = "res://assets/characters/edric_varn/"
const CLIPS = {"walk":"walking","fly":"flying","punch":"punching","fall":"falling_idle","land":"falling_to_landing","jump":"wh"}
const LOOP = ["walk","fly","fall"]

var height := 2.7
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var pose: PoseMod
var current := ""
var missing: Array = ["idle","run","sprint","wall_run","glide","charge","dash","superhero_landing"] # procedural or stand-ins
var unit_scale := 1.0

func setup(h: float):
 height = h
 model = load(DIR+"wh.fbx").instantiate()
 add_child(model)
 skeleton = model.find_children("*","Skeleton3D",true,false)[0]
 player = model.find_children("*","AnimationPlayer",true,false)[0]
 # Height from the rest pose: head top to the toes.
 var top = skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_HeadTop_End")).origin.y
 var low = minf(skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_LeftToe_End")).origin.y,skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_LeftFoot")).origin.y)
 unit_scale = height/maxf(0.0001,top-low)
 model.scale = Vector3.ONE*unit_scale
 model.position.y = -low*unit_scale
 model.rotation.y = PI # Mixamo faces +z; the controller's forward is -z
 _measure_lift()
 var lib = AnimationLibrary.new()
 for name in CLIPS:
  var src = load(DIR+CLIPS[name]+".fbx").instantiate()
  var sp: AnimationPlayer = src.find_children("*","AnimationPlayer",true,false)[0]
  var anim: Animation = sp.get_animation(sp.get_animation_list()[0]).duplicate(true)
  _in_place(anim)
  anim.loop_mode = Animation.LOOP_LINEAR if name in LOOP else Animation.LOOP_NONE
  lib.add_animation(name,anim)
  src.free()
 lib.add_animation("idle",_still(lib.get_animation("land"),1.05))
 if player.has_animation_library(""): player.remove_animation_library("")
 player.add_animation_library("",lib)
 pose = PoseMod.new()
 skeleton.add_child(pose)
 pose.setup(skeleton)
 for mi in model.find_children("*","MeshInstance3D",true,false): mi.material_override = _material()
 play("walk")

# Mixamo clips move the hips forward: keep the height, pin x and z to the first key. Their hip
# heights are measured from the feet while the rig's rest pose is centred on the hips, so every clip
# drops by `lift` (the walk's standing hip height above the rest hips), keeping the feet on the ground.
var lift := 0.0

func _in_place(anim: Animation):
 for t in anim.get_track_count():
  if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(t)).ends_with("Hips"):
   var first: Vector3 = anim.track_get_key_value(t,0)
   for k in anim.track_get_key_count(t):
    var v: Vector3 = anim.track_get_key_value(t,k)
    anim.track_set_key_value(t,k,Vector3(first.x,v.y-lift,first.z))

func _measure_lift():
 var src = load(DIR+"walking.fbx").instantiate()
 var sp: AnimationPlayer = src.find_children("*","AnimationPlayer",true,false)[0]
 var anim: Animation = sp.get_animation(sp.get_animation_list()[0])
 for t in anim.get_track_count():
  if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(t)).ends_with("Hips"):
   lift = (anim.track_get_key_value(t,0) as Vector3).y-skeleton.get_bone_rest(skeleton.find_bone("mixamorig_Hips")).origin.y
 src.free()

func play(name: String,blend := 0.2,speed := 1.0):
 player.speed_scale = speed
 if current == name: return
 current = name
 player.play(name,blend)

func play_once(name: String,blend := 0.08,speed := 1.0):
 current = name
 player.speed_scale = speed
 player.play(name,blend)
 player.seek(0.0,true)

# The model arrived untextured (the clips carry only the mesh and the rig), so it gets a material
# of its own: dark blued steel with worn bright edges and a faint inner glow, a god in armour.
func _material() -> ShaderMaterial:
 var m = ShaderMaterial.new()
 m.shader = load("res://god/god_body.gdshader")
 m.set_shader_parameter("height",height/unit_scale)
 m.set_shader_parameter("foot",model.position.y/unit_scale*-1.0)
 return m

# A one-pose looping clip: `src` held at time t (the idle stand-in; a zero speed scale would also
# freeze the cross-fade into it).
func _still(src: Animation,t: float) -> Animation:
 var a = Animation.new()
 a.length = 1.0
 a.loop_mode = Animation.LOOP_LINEAR
 for i in src.get_track_count():
  var tr = a.add_track(src.track_get_type(i))
  a.track_set_path(tr,src.track_get_path(i))
  match src.track_get_type(i):
   Animation.TYPE_ROTATION_3D: a.rotation_track_insert_key(tr,0.0,src.rotation_track_interpolate(i,t))
   Animation.TYPE_POSITION_3D: a.position_track_insert_key(tr,0.0,src.position_track_interpolate(i,t))
   Animation.TYPE_SCALE_3D: a.scale_track_insert_key(tr,0.0,src.scale_track_interpolate(i,t))
 return a
