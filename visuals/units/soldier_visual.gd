extends Node3D
# Placeholder soldier: the base character's head on a skinned outfit, weapons attached to bones,
# and a static pose from the Universal Animation Library. All soldiers share this model; the
# unit type's outfit, loadout and pose (data/units/*.json) make each one recognizable.

const AssetManifest = preload("res://core/asset_manifest.gd")
const BASE = preload("res://assets/quaternius/characters/Superhero_Male_FullBody.gltf")
const POSES = {
 "idle": preload("res://assets/quaternius/animations/Idle_Loop.res"),
 "sword": preload("res://assets/quaternius/animations/Sword_Idle.res"),
 "spear": preload("res://assets/quaternius/animations/Idle_Torch_Loop.res"),
 "seated": preload("res://assets/quaternius/animations/Sitting_Idle_Loop.res"),
 "bow": preload("res://assets/quaternius/animations/Pistol_Idle_Loop.res"),
 "command": preload("res://assets/quaternius/animations/Spell_Simple_Idle_Loop.res"),
}
# The base mesh is a full body; outfits bring their own arms, legs and feet, so only the
# triangles skinned mainly to these bones are kept, which avoids clipping through clothes.
const HEAD_BONES = ["Head","neck_01"]

static var _head_meshes = {}

var skeleton: Skeleton3D
var built = false

# unit: a unit type dictionary (see core/unit_types.gd). Uses unit.outfit (manifest ID),
# unit.loadout (weapon manifest IDs) and unit.visual_config {pose, pose_time, tint, scale, hair (manifest IDs)}.
func configure(unit: Dictionary):
 assert(not built,"soldier already configured")
 built = true
 var look: Dictionary = unit.get("visual_config",{})
 var body = BASE.instantiate()
 add_child(body)
 skeleton = body.find_child("Skeleton3D")
 var full: MeshInstance3D = skeleton.get_node("SuperHero_Male")
 full.mesh = head_only(full)
 var tint = Color(look.get("tint","#ffffff"))
 # The outfit and any hair pieces are skinned to the same rig; move their meshes onto ours.
 for id in [unit.outfit]+look.get("hair",[]):
  var outfit = AssetManifest.instantiate(id)
  for part in outfit.parts():
   part.owner = null
   part.get_parent().remove_child(part)
   skeleton.add_child(part)
   part.skeleton = NodePath("..")
   if id == unit.outfit:
    if tint != Color.WHITE: _tint(part,tint)
   else: _tint(part,Color(look.get("hair_color","#6b4a30")))
  outfit.free()
 apply_pose(skeleton,POSES[look.get("pose","idle")],look.get("pose_time",0.0))
 for id in unit.get("loadout",[]):
  var weapon = AssetManifest.instantiate(id)
  var socket = BoneAttachment3D.new()
  socket.bone_name = weapon.bone
  skeleton.add_child(socket)
  socket.add_child(weapon)
 scale = Vector3.ONE*float(look.get("scale",1.0))

# Tint cloth and leather, not skin.
func _tint(part: MeshInstance3D,tint: Color):
 for s in part.mesh.get_surface_count():
  var m = part.mesh.surface_get_material(s)
  if m is StandardMaterial3D and not m.resource_name.contains("Regular"):
   var t = m.duplicate()
   t.albedo_color = t.albedo_color*tint
   part.set_surface_override_material(s,t)

# Static pose: bone rotations (and the pelvis position) sampled from an animation at time t.
static func apply_pose(skel: Skeleton3D,anim: Animation,t: float):
 var pelvis = skel.find_bone("pelvis")
 for i in anim.get_track_count():
  var bone = skel.find_bone(anim.track_get_path(i).get_concatenated_subnames())
  if bone<0: continue
  match anim.track_get_type(i):
   Animation.TYPE_ROTATION_3D: skel.set_bone_pose_rotation(bone,anim.rotation_track_interpolate(i,t))
   Animation.TYPE_POSITION_3D:
    if bone==pelvis: skel.set_bone_pose_position(bone,anim.position_track_interpolate(i,t))

static func head_only(mi: MeshInstance3D) -> ArrayMesh:
 var src: Mesh = mi.mesh
 if _head_meshes.has(src): return _head_meshes[src]
 var keep = {}
 for i in mi.skin.get_bind_count():
  if mi.skin.get_bind_name(i) in HEAD_BONES: keep[i] = true
 var out = ArrayMesh.new()
 for s in src.get_surface_count():
  var arrays = src.surface_get_arrays(s)
  var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
  var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
  var per = bones.size()/arrays[Mesh.ARRAY_VERTEX].size()
  var dominant = PackedInt32Array()
  dominant.resize(arrays[Mesh.ARRAY_VERTEX].size())
  for v in dominant.size():
   var best = 0
   for k in range(1,per):
    if weights[v*per+k]>weights[v*per+best]: best = k
   dominant[v] = bones[v*per+best]
  var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
  var kept = PackedInt32Array()
  for t in range(0,index.size(),3):
   if keep.has(dominant[index[t]]) and keep.has(dominant[index[t+1]]) and keep.has(dominant[index[t+2]]):
    kept.append(index[t])
    kept.append(index[t+1])
    kept.append(index[t+2])
  arrays[Mesh.ARRAY_INDEX] = kept
  out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
  out.surface_set_material(s,src.surface_get_material(s))
 _head_meshes[src] = out
 return out
