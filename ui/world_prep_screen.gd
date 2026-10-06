extends CanvasLayer
# First start of a map version (owner, 2026-10-06): the map's local render cache (terrain heights,
# ground colours, rivers) is built once from its sources. The release build takes about 40 s on
# the enlarged Varos, so it runs on a worker thread behind this screen, with a clear message and
# the build's steps; `finished` fires when the cache is written (the campaign scene then reloads).

signal finished

const UiKit = preload("res://ui/ui_kit.gd")

var map_id := ""
var thread: Thread
var mutex := Mutex.new()
var fraction := 0.0
var step := "Starting"
var done := false
var started := 0
var bar: ProgressBar
var step_label: Label
var time_label: Label

func _init(id: String):
 map_id = id
 layer = 100
 name = "WorldPrepScreen"

func _ready():
 var bg = ColorRect.new()
 bg.color = Color("16110d")
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var box = VBoxContainer.new()
 box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 box.grow_horizontal = Control.GROW_DIRECTION_BOTH
 box.grow_vertical = Control.GROW_DIRECTION_BOTH
 box.custom_minimum_size = Vector2(620,0)
 box.add_theme_constant_override("separation",14)
 add_child(box)
 var t = UiKit.header("Preparing the world map",30)
 t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(t)
 var msg = UiKit.label("This is the first start with this version of the map. Its terrain is built once and kept for every later start; this takes about a minute.",17,UiKit.TEXT)
 msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(msg)
 bar = ProgressBar.new()
 bar.name = "PrepProgress"
 bar.custom_minimum_size = Vector2(0,20)
 bar.max_value = 1.0
 bar.show_percentage = false
 box.add_child(bar)
 step_label = UiKit.label("",16,Color("f1d79a"))
 step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(step_label)
 time_label = UiKit.label("",14,UiKit.TEXT_DIM)
 time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(time_label)
 started = Time.get_ticks_msec()
 thread = Thread.new()
 thread.start(_build)

func _build():
 load("res://map/pipeline.gd").build(map_id,false,func(f: float,s: String):
  mutex.lock()
  fraction = f
  step = s
  mutex.unlock())
 mutex.lock()
 fraction = 1.0
 step = "Done"
 done = true
 mutex.unlock()

func _process(_delta):
 mutex.lock()
 var f = fraction
 var s = step
 var d = done
 mutex.unlock()
 bar.value = f
 step_label.text = s
 time_label.text = "%d s" % int((Time.get_ticks_msec()-started)/1000)
 if d:
  thread.wait_to_finish()
  set_process(false)
  finished.emit()
