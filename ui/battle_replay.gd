extends VBoxContainer
# Top-down battle replay (docs/battle-design.md section 6): unit blocks per tick on the lanes, the
# reader's side at the bottom, a scrubber with play/pause, and timeline events as markers on the
# scrubber. jump(tick, units) moves to a tick and highlights the units involved.

const UiKit = preload("res://ui/ui_kit.gd")
const STEP = 0.45 # seconds per tick while playing
# Simulation states (core/battle_sim.gd): ready, engaged, reserve, flanking, waiting, pending (not
# arrived), away (pursuing off the field), routed, fled, destroyed.
const S_PENDING = 5
const S_AWAY = 6
const S_ROUTED = 7
const S_FLED = 8
const S_DESTROYED = 9

var frames: Array = []
var walls := {}
var roster: Array = []
var events: Array = []
var lanes := 5
var my_side := 0
var ours := Color.RED
var theirs := Color.BLUE
var tick := 0
var highlight: Array = []
var playing := false
var acc := 0.0
var field: Control
var markers: Control
var slider: HSlider
var play_button: Button
var tick_label: Label

func setup(rep: Dictionary,our_color: Color,their_color: Color):
 frames = rep.replay
 roster = rep.roster
 events = rep.timeline
 lanes = rep.lanes
 walls = rep.get("walls",{})
 my_side = rep.my_side
 ours = our_color
 theirs = their_color
 add_theme_constant_override("separation",4)
 field = Field.new(self)
 field.name = "ReplayField"
 field.custom_minimum_size = Vector2(0,340)
 add_child(field)
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 play_button = Button.new()
 play_button.name = "Play"
 play_button.text = "Play"
 play_button.focus_mode = Control.FOCUS_NONE
 play_button.pressed.connect(toggle_play)
 row.add_child(play_button)
 slider = HSlider.new()
 slider.name = "Scrubber"
 slider.min_value = 0
 slider.max_value = maxi(0,frames.size()-1)
 slider.step = 1
 slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 slider.focus_mode = Control.FOCUS_NONE
 slider.value_changed.connect(func(v):
  if int(v) != tick:
   tick = int(v)
   highlight = []
   _redraw())
 # Event markers sit directly above the scrubber, sharing its width.
 var track = VBoxContainer.new()
 track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 track.add_theme_constant_override("separation",0)
 markers = Markers.new(self)
 markers.custom_minimum_size = Vector2(0,14)
 track.add_child(markers)
 track.add_child(slider)
 row.add_child(track)
 tick_label = UiKit.label("",13,UiKit.TEXT_DIM)
 tick_label.custom_minimum_size = Vector2(110,0)
 row.add_child(tick_label)
 add_child(row)
 _redraw()

func toggle_play():
 playing = not playing
 if playing and tick>=frames.size()-1: set_tick(0)
 play_button.text = "Pause" if playing else "Play"

func set_tick(t: int):
 tick = clampi(t,0,maxi(0,frames.size()-1))
 slider.set_value_no_signal(tick)
 _redraw()

# Jump to an event's tick and highlight the units it involves.
func jump(t: int,units: Array):
 playing = false
 play_button.text = "Play"
 set_tick(t)
 highlight = units
 _redraw()

func _process(delta):
 if not playing: return
 acc += delta
 if acc<STEP: return
 acc = 0.0
 if tick>=frames.size()-1:
  toggle_play()
  return
 highlight = []
 set_tick(tick+1)

func _redraw():
 tick_label.text = "Deployment" if tick == 0 else "Tick %d of %d" % [tick,frames.size()-1]
 field.queue_redraw()
 markers.queue_redraw()

# Field y (0 = attacker's rear edge, 7 = defender's) to a pixel row; the reader's side at the bottom.
func y_px(y: float,h: float) -> float:
 var f = clampf((y+0.5)/8.0,0.0,1.0)
 return h*f if my_side == 1 else h*(1.0-f)

class Field extends Control:
 var r
 func _init(owner_replay):
  r = owner_replay
 func _draw():
  var w = size.x/r.lanes
  draw_rect(Rect2(Vector2.ZERO,size),Color("2a3a22"))
  for l in r.lanes:
   draw_rect(Rect2(l*w+1,0,w-2,size.y),Color("4f6a3a") if l%2 == 0 else Color("4a6436"))
  # No man's land between the two deployment zones.
  var a = r.y_px(2.5,size.y)
  var b = r.y_px(4.5,size.y)
  draw_rect(Rect2(0,minf(a,b),size.x,absf(b-a)),Color(0,0,0,0.12))
  if not r.walls.is_empty():
   var wy = r.y_px(float(r.walls.y),size.y)
   for l in r.lanes:
    if not l in r.walls.gates: draw_rect(Rect2(l*w,wy-3,w,6),Color("cfc6b0"))
    else: draw_rect(Rect2(l*w,wy-2,w,4),Color("8a6a44"))
  if r.frames.is_empty(): return
  var frame = r.frames[r.tick]
  # Units in the same lane at about the same depth sit side by side.
  var groups = {}
  for i in frame.size():
   var s = int(frame[i][2])
   if s == r.S_PENDING or s == r.S_AWAY or s == r.S_FLED: continue
   var k = "%d:%d" % [int(frame[i][0]),int(round(float(frame[i][1])*2.0))]
   if not groups.has(k): groups[k] = []
   groups[k].append(i)
  var font = UiKit.FONT_BOLD
  for k in groups:
   var list = groups[k]
   for n in list.size():
    var i = list[n]
    var f = frame[i]
    var info = r.roster[i]
    var start = maxf(1.0,float(r.frames[0][i][3]))
    var share = clampf(float(f[3])/start,0.0,1.0)
    var cw = (w-8)/list.size()
    var bw = cw-4
    var bh = 9.0+8.0*sqrt(share) if not info.general else 12.0
    var x = int(f[0])*w+4+n*cw+2
    var y = r.y_px(float(f[1]),size.y)-bh/2
    var col: Color = r.ours if info.ours else r.theirs
    var st = int(f[2])
    if st == r.S_ROUTED: col = col.lerp(Color("cccccc"),0.55)
    if st == r.S_DESTROYED: col = Color(0.2,0.2,0.2,0.6)
    var rect = Rect2(x,y,bw,bh)
    draw_rect(rect,col)
    draw_rect(rect,Color(0,0,0,0.7),false,1.0)
    if info.general: draw_circle(rect.get_center(),4.0,Color("f2cf6a"))
    if st == r.S_DESTROYED:
     draw_line(rect.position,rect.end,Color("ef8a6a"),2.0)
     draw_line(Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y),Color("ef8a6a"),2.0)
    if bw>44 and not info.general: draw_string(font,rect.position+Vector2(3,minf(bh-2,13)),info.name,HORIZONTAL_ALIGNMENT_LEFT,bw-6,11,Color("f1e6c8"))
    if i in r.highlight: draw_rect(rect.grow(3),Color("ffe08a"),false,3.0)

class Markers extends Control:
 var r
 func _init(owner_replay):
  r = owner_replay
  mouse_filter = Control.MOUSE_FILTER_STOP
 func _x(t: int) -> float:
  # Matches the slider's grabber travel closely enough for a marker strip.
  return 8.0+(size.x-16.0)*float(t)/maxf(1.0,r.frames.size()-1)
 func _draw():
  draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,0.25))
  for e in r.events:
   draw_rect(Rect2(_x(e.tick)-1.5,2,3,size.y-4),Color("9fe08a") if e.ours else Color("ef8a6a"))
  draw_rect(Rect2(_x(r.tick)-1,0,2,size.y),Color.WHITE)
 func _gui_input(e):
  if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
   # Nearest event to the click.
   var best = -1
   var bd = 9.0
   for k in r.events.size():
    var d = absf(_x(r.events[k].tick)-e.position.x)
    if d<bd:
     bd = d
     best = k
   if best>=0: r.jump(r.events[best].tick,r.events[best].units)
