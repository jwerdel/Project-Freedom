extends Node3D
# Placeholder cavalry: the shared soldier model, seated, on the Quaternius horse.
# The rider uses the unit's outfit, loadout and visual_config; the pose is forced to "seated".

const AssetManifest = preload("res://core/asset_manifest.gd")
const SoldierVisual = preload("res://visuals/units/soldier_visual.gd")
const HORSE = preload("res://assets/quaternius/animals/Horse.gltf")
const HORSE_SCALE = 0.42 # about 1.5 m at the withers, 2.4 m nose to tail
const SADDLE_BONE = "Back"
const SEAT_OFFSET = Vector3(0,0.04,0.5)

var built = false

func configure(unit: Dictionary):
 assert(not built,"cavalry already configured")
 built = true
 var horse = HORSE.instantiate()
 add_child(horse)
 horse.scale = Vector3.ONE*HORSE_SCALE
 var horse_skel: Skeleton3D = horse.find_child("Skeleton3D")
 var player: AnimationPlayer = horse.find_child("AnimationPlayer")
 SoldierVisual.apply_pose(horse_skel,player.get_animation("Idle"),0.4)
 player.free()
 var rider_unit = unit.duplicate(true)
 rider_unit.visual_config = rider_unit.get("visual_config",{})
 rider_unit.visual_config.pose = "seated"
 var rider = AssetManifest.instantiate("unit.soldier")
 add_child(rider)
 rider.configure(rider_unit)
 var saddle = horse.transform*horse_skel.transform*_posed(horse_skel,horse_skel.find_bone(SADDLE_BONE)).origin
 var seat = _posed(rider.skeleton,rider.skeleton.find_bone("pelvis")).origin
 rider.position = saddle-seat+SEAT_OFFSET

static func _posed(skel: Skeleton3D,bone: int) -> Transform3D:
 var t = skel.get_bone_pose(bone)
 var parent = skel.get_bone_parent(bone)
 while parent>=0:
  t = skel.get_bone_pose(parent)*t
  parent = skel.get_bone_parent(parent)
 return t
