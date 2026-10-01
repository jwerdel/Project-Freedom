extends Node3D
# A held weapon or shield. The soldier visual attaches this node to `bone`; the Model child's
# transform is the grip (scale to campaign size, orientation and offset in the hand).

@export var bone := "hand_r"
