extends Node
# The frame probe's late half (god/frame_probe.gd): stamps the end of the physics callbacks.

var probe

func _ready():
 process_physics_priority = 100000

func _physics_process(_d):
 probe.f.phys_end = Time.get_ticks_usec()
