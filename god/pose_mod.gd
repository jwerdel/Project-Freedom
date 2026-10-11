extends SkeletonModifier3D
# Procedural pose layer over the Mixamo clips (god/god_model.gd) for the states that have no clip:
# a forward lean (run, sprint, dash), a spine twist (the charged punch), arms spread toward the rest
# T-pose (glide), the right fist thrust overhead (fast flight), arms swept back (dash), breathing
# (idle). Works in skeleton space (Mixamo: +z forward, +y up, +x the character's left), after the
# animation player has posed the bones.

var sk: Skeleton3D
var lean := 0.0
var twist := 0.0
var glide := 0.0
var reach := 0.0
var sweep := 0.0
var breath := 0.0
var crouch := 0.0
var _t := 0.0
var b = {}

func setup(skeleton: Skeleton3D):
 sk = skeleton
 for n in ["Hips","Spine","Spine1","Spine2","Neck","Head","LeftArm","LeftForeArm","LeftHand","RightArm","RightForeArm","RightHand","LeftUpLeg","RightUpLeg","LeftLeg","RightLeg"]:
  b[n] = sk.find_bone("mixamorig_"+n)

func _process_modification():
 _t += 1.0/60.0
 var spine_x = lean*0.36+sin(_t*1.7)*0.015*breath
 for n in ["Spine","Spine1","Spine2"]:
  _rot(n,Basis(Vector3.RIGHT,spine_x))
  if twist != 0.0: _rot(n,Basis(Vector3.UP,twist*0.33))
 if crouch>0.0:
  _rot("LeftUpLeg",Basis(Vector3.RIGHT,-crouch*0.9))
  _rot("RightUpLeg",Basis(Vector3.RIGHT,-crouch*0.9))
  _rot("LeftLeg",Basis(Vector3.RIGHT,crouch*1.4))
  _rot("RightLeg",Basis(Vector3.RIGHT,crouch*1.4))
 if glide>0.0:
  for n in ["LeftArm","LeftForeArm","RightArm","RightForeArm"]: _toward_rest(n,glide,Basis.IDENTITY)
 if sweep>0.0:
  for n in ["LeftArm","RightArm"]: _rot(n,Basis(Vector3.RIGHT,-sweep*0.9))
 if reach>0.0:
  var up = Basis(Vector3.BACK,-PI*0.5)
  for n in ["RightArm","RightForeArm","RightHand"]: _toward_rest(n,reach,up)

# Rotate a bone about its joint by r (skeleton space); its children follow.
func _rot(n: String,r: Basis):
 var i = b[n]
 if i<0: return
 var g = sk.get_bone_global_pose(i)
 sk.set_bone_global_pose(i,Transform3D(r*g.basis,g.origin))

# Blend a bone's skeleton-space rotation toward its rest rotation turned by `extra` (keeps position).
func _toward_rest(n: String,w: float,extra: Basis):
 var i = b[n]
 if i<0: return
 var g = sk.get_bone_global_pose(i)
 var r = sk.get_bone_global_rest(i)
 var s = g.basis.get_scale()
 var qa = g.basis.orthonormalized().get_rotation_quaternion()
 var qb = (extra*r.basis.orthonormalized()).get_rotation_quaternion()
 sk.set_bone_global_pose(i,Transform3D(Basis(qa.slerp(qb,clampf(w,0.0,1.0))).scaled(s),g.origin))
