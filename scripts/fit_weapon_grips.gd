extends SceneTree
# Writes visuals/weapons/*.tscn: each weapon's grip transform is solved so that, in the pose it is
# used with, the weapon points in the intended world direction from the given bone.
# Run (needs a renderer-free tree only): runtime\Godot.exe --headless --path . -s scripts/fit_weapon_grips.gd
# Character space: feet at origin, facing +Z, character's left is +X.

const WEAPONS = {
 # id: [model, pose, bone, scale, model axis to aim (up), its world direction, model axis for facing, its world direction, grip point (model units), world offset]
 "spear": ["Spear","idle","hand_r",0.22,Vector3.UP,Vector3(0,1,0.06),Vector3.BACK,Vector3(1,0,0),Vector3(0,1.3,0),Vector3.ZERO],
 "spear_raised": ["Spear","spear","hand_l",0.22,Vector3.UP,Vector3(0,1,0.15),Vector3.BACK,Vector3(1,0,0),Vector3(0,1.9,0),Vector3.ZERO],
 "lance": ["Spear","seated","hand_r",0.27,Vector3.UP,Vector3(0,1,0.3),Vector3.BACK,Vector3(1,0,0),Vector3(0,-0.2,0),Vector3.ZERO],
 "shield_round": ["Shield_Round","idle","lowerarm_l",0.32,Vector3.UP,Vector3(0,1,0),Vector3.BACK,Vector3(0.45,0,1),Vector3.ZERO,Vector3(0.08,0,0.05)],
 "shield_heater": ["Shield_Heater","sword","lowerarm_l",0.28,Vector3.UP,Vector3(0,1,0),Vector3.BACK,Vector3(0.5,0,1),Vector3.ZERO,Vector3(0.07,0,0.06)],
 "shield_large": ["Shield_Heater","sword","lowerarm_l",0.46,Vector3.UP,Vector3(0,1,0),Vector3.BACK,Vector3(0.45,0,1),Vector3(0,0.3,0),Vector3(0.1,0,0.1)],
 "sword": ["Sword","sword","hand_r",0.2,Vector3.UP,Vector3(-0.1,0.75,1),Vector3.BACK,Vector3(1,0,0),Vector3(0,-0.4,0),Vector3.ZERO],
 "hammer": ["Hammer_Double","sword","hand_r",0.26,Vector3.UP,Vector3(-0.25,1,0.35),Vector3.BACK,Vector3(0,0,1),Vector3(0,-0.9,0),Vector3.ZERO],
 "bow": ["Bow_Wooden","bow","hand_l",0.22,Vector3.UP,Vector3(0,1,0.1),Vector3.RIGHT,Vector3(0,0,-1),Vector3.ZERO,Vector3.ZERO],
}

func _initialize():
 _run.call_deferred()

func _run():
 for id in WEAPONS:
  var w = WEAPONS[id]
  var soldier = load("res://visuals/units/soldier.tscn").instantiate()
  root.add_child(soldier)
  soldier.configure({"outfit":"outfit.ranger_hoodless","loadout":[],"visual_config":{"pose":w[1]}})
  for i in 3: await process_frame
  var skel: Skeleton3D = soldier.skeleton
  var bone_t: Transform3D = skel.global_transform*_posed(skel,skel.find_bone(w[2]))
  # World basis: model `up` axis -> aim direction, model `face` axis -> facing (orthogonalized).
  var aim = (w[5] as Vector3).normalized()
  var face = ((w[7] as Vector3)-aim*aim.dot(w[7])).normalized()
  var target = _basis_mapping(w[4],w[6],aim,face).scaled(Vector3.ONE*w[3])
  var world = Transform3D(target,bone_t.origin+w[9]-target*(w[8] as Vector3))
  var local = bone_t.affine_inverse()*world
  _write(id,w[0],w[2],local)
  soldier.free()
 print("GRIPS_WRITTEN")
 quit()

# Skeleton-space transform of a bone in the current pose, chained from the poses directly
# (get_bone_global_pose can still return the rest pose right after poses are set).
func _posed(skel: Skeleton3D,bone: int) -> Transform3D:
 var t = skel.get_bone_pose(bone)
 var parent = skel.get_bone_parent(bone)
 while parent>=0:
  t = skel.get_bone_pose(parent)*t
  parent = skel.get_bone_parent(parent)
 return t

# Rotation taking model axes (a1, a2) to world directions (b1, b2).
func _basis_mapping(a1: Vector3,a2: Vector3,b1: Vector3,b2: Vector3) -> Basis:
 var from = Basis(a1,a2,a1.cross(a2))
 var to = Basis(b1,b2,b1.cross(b2))
 return to*from.inverse()

func _write(id: String,model: String,bone: String,t: Transform3D):
 var text = "[gd_scene load_steps=3 format=3]\n\n"
 text += "[ext_resource type=\"Script\" path=\"res://visuals/weapons/weapon_visual.gd\" id=\"1\"]\n"
 text += "[ext_resource type=\"PackedScene\" path=\"res://assets/quaternius/weapons/%s.fbx\" id=\"2\"]\n\n" % model
 text += "[node name=\"%s\" type=\"Node3D\"]\nscript = ExtResource(\"1\")\nbone = \"%s\"\n\n" % [id.to_pascal_case(),bone]
 text += "[node name=\"Model\" parent=\".\" instance=ExtResource(\"2\")]\n"
 text += "transform = %s\n" % var_to_str(t)
 var f = FileAccess.open("res://visuals/weapons/%s.tscn" % id,FileAccess.WRITE)
 f.store_string(text)
 f.close()
 print("GRIP ",id," ",t)
