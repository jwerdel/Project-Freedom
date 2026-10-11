extends Node
# Diagnostics for the look test's perf runs: per frame, when physics starts, when process starts,
# and the draw (pre to post); a frame over `limit` ms prints where its time went.

var limit := 60.0
var f = {"phys":0,"phys_end":0,"proc":0,"pre":0,"post":0}
var prev = {}

func _ready():
 process_priority = -100000
 process_physics_priority = -100000
 RenderingServer.frame_pre_draw.connect(func(): f.pre = Time.get_ticks_usec())
 RenderingServer.frame_post_draw.connect(_on_post)
 var late = load("res://god/frame_probe_late.gd").new()
 late.probe = self
 add_child(late)

func _physics_process(_d):
 if f.phys == 0: f.phys = Time.get_ticks_usec()

func _process(_d):
 f.proc = Time.get_ticks_usec()
 if f.phys == 0: f.phys = f.proc

func _on_post():
 f.post = Time.get_ticks_usec()
 if not prev.is_empty():
  var total = (f.post-prev.post)/1000.0
  if total>limit:
   print("GODTEST frame %.1f ms: idle before physics %.1f, physics callbacks %.1f, physics step and rest %.1f, process %.1f, draw %.1f" % [total,(f.phys-prev.post)/1000.0,(f.phys_end-f.phys)/1000.0,(f.proc-f.phys_end)/1000.0,(f.pre-f.proc)/1000.0,(f.post-f.pre)/1000.0])
 prev = f.duplicate()
 f.phys = 0
