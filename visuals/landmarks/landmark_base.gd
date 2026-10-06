extends Node3D
# Base of the Stage A landmark visuals (2026-10-06): each landmark scene sets `stage` (1-3) and its
# script overrides make(h), adding pieces and naming its features (tests read them). build() is
# called by map/map_view.gd after the node is placed (origin at sea level under the site, local +z
# toward the nearest water) with the height lookup in that local space.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const K = preload("res://visuals/landmarks/landmark_kit.gd")
const S = preload("res://visuals/kits/cultures/kit_shapes.gd")

@export_range(1,3) var stage := 1
var features: Array = []
var h: Callable = Callable()

func build(ctx: Dictionary):
 h = ctx.get("height",Callable())
 make()
 set_meta("stage",stage)
 set_meta("features",features)
 ProtoKit.shared().batch(self)

func make():
 pass

func y(x: float,z: float) -> float:
 return K.ground(h,x,z)

func at(x: float,z: float,lift := 0.0) -> Vector3:
 return Vector3(x,y(x,z)+lift,z)
