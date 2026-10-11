extends CanvasLayer
# HUD of the god-game look test: the post-process pass (god/post.gdshader), Frosthold's approval
# (Manor Lords-style), suspicion bars over the townsfolk's heads (Where Winds Meet), the charge
# meter, flight speed and altitude, messages, a controls card (H) and a performance readout (F3).

const FONT = preload("res://assets/fonts/FiraSans-Regular.ttf")
const FONT_B = preload("res://assets/fonts/FiraSans-SemiBold.ttf")

var host
var post: ColorRect
var post_mat: ShaderMaterial
var draw: Control
var msg := ""
var msg_t := 0.0
var flash := 0.0
var show_help := true
var show_perf := false
var perf_text := ""

func setup(h):
 host = h
 layer = 2
 post = ColorRect.new()
 post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 post.mouse_filter = Control.MOUSE_FILTER_IGNORE
 post_mat = ShaderMaterial.new()
 post_mat.shader = load("res://god/post.gdshader")
 post.material = post_mat
 add_child(post)
 draw = Control.new()
 draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
 draw.draw.connect(_draw)
 add_child(draw)

func say(text: String,secs := 4.0):
 msg = text
 msg_t = secs

func _process(delta):
 var real = delta/maxf(Engine.time_scale,0.05)
 msg_t -= real
 flash = maxf(0.0,flash-real*3.0)
 var p = host.player
 var fly = p.state == p.FLY or p.state == p.DIVE
 var sl = clampf((p.velocity.length()-50.0)/70.0,0.0,1.0) if fly else 0.0
 post_mat.set_shader_parameter("speed_lines",sl)
 post_mat.set_shader_parameter("charge",p.charge_amount())
 post_mat.set_shader_parameter("flash",flash)
 post.visible = host.empire == null or host.empire.mode != "strategic"
 draw.queue_redraw()

func _text(pos: Vector2,t: String,size: int,col := Color(0.92,0.9,0.85),font = FONT,align := HORIZONTAL_ALIGNMENT_LEFT,width := -1.0):
 draw.draw_string(font,pos+Vector2(1,1),t,align,width,size,Color(0,0,0,0.6))
 draw.draw_string(font,pos,t,align,width,size,col)

func _draw():
 if host == null or host.player == null: return
 var vs = draw.size
 var p = host.player
 var town = host.town
 if host.empire != null and host.empire.mode == "strategic":
  if msg_t>0.0 and msg != "": _banner(vs,msg)
  return
 # Approval panel (top left).
 var panel = Rect2(18,16,330,74)
 draw.draw_rect(panel,Color(0.08,0.07,0.06,0.72))
 draw.draw_rect(panel,Color(0.79,0.64,0.35,0.8),false,1.5)
 _text(Vector2(30,40),"FROSTHOLD",16,Color(0.85,0.72,0.45),FONT_B)
 var ap = town.approval
 _text(Vector2(220,40),"Approval %d%%" % roundi(ap),15)
 var bar = Rect2(30,52,306,10)
 draw.draw_rect(bar,Color(0.2,0.18,0.16))
 var col = Color(0.45,0.7,0.35).lerp(Color(0.8,0.25,0.18),clampf((75.0-ap)/50.0,0.0,1.0))
 draw.draw_rect(Rect2(bar.position,Vector2(bar.size.x*ap/100.0,bar.size.y)),col)
 for t in [50.0,75.0]: draw.draw_line(Vector2(bar.position.x+bar.size.x*t/100.0,bar.position.y-2),Vector2(bar.position.x+bar.size.x*t/100.0,bar.end.y+2),Color(1,1,1,0.5),1.0)
 var st = town.stats()
 _text(Vector2(30,80),"%d buildings ruined  ·  %d hurt  ·  %d alarmed" % [st.ruined,host.villagers.hurt if host.villagers else 0,host.villagers.alarmed_count() if host.villagers else 0],14,Color(0.75,0.72,0.66))
 # Suspicion bars over heads.
 var cam = get_viewport().get_camera_3d()
 if host.villagers != null and cam != null:
  for v in host.villagers.people:
   if v.sus<0.02: continue
   var head = v.pos+Vector3(0,2.15,0)
   if cam.is_position_behind(head) or head.distance_to(cam.global_position)>70.0: continue
   var sp = cam.unproject_position(head)
   var w = 34.0
   var r = Rect2(sp-Vector2(w*0.5,3),Vector2(w,6))
   draw.draw_rect(r.grow(1.0),Color(0,0,0,0.55))
   var c = Color(0.95,0.8,0.25).lerp(Color(0.95,0.25,0.15),v.sus)
   draw.draw_rect(Rect2(r.position,Vector2(w*v.sus,6)),c)
   if v.sus>=0.99: _text(sp+Vector2(-4,-8),"!",18,Color(1,0.3,0.2),FONT_B)
 # Crosshair and charge ring.
 var center = vs*0.5
 var ch = p.charge_amount()
 if p.mouse_captured or p.scripted:
  draw.draw_circle(center,2.0,Color(1,1,1,0.7))
  if ch>0.0:
   draw.draw_arc(center,26.0,-PI*0.5,-PI*0.5+TAU*ch,48,Color(1.0,0.78,0.4,0.9),3.0)
   if ch>=1.0: draw.draw_arc(center,31.0,0,TAU,48,Color(1.0,0.9,0.6,0.6),1.5)
 # Flight readout.
 if p.state == p.FLY or host.empire.mode != "ground":
  var alt = host.empire._alt_above_ground(cam.global_position if host.empire.mode != "ground" else p.global_position)
  _text(Vector2(vs.x*0.5-90,vs.y-40),"%s   %d m/s   %d m up" % [host.empire.mode.to_upper() if host.empire.mode != "ground" else "FLIGHT",roundi(p.velocity.length()),roundi(alt)],15,Color(0.9,0.88,0.82),FONT,HORIZONTAL_ALIGNMENT_CENTER,180)
 if msg_t>0.0 and msg != "": _banner(vs,msg)
 if show_help: _help(vs)
 if show_perf: _text(Vector2(vs.x-460,vs.y-20),perf_text,14,Color(0.7,0.9,0.7))

func _banner(vs: Vector2,t: String):
 var r = Rect2(vs.x*0.5-330,vs.y*0.2,660,44)
 draw.draw_rect(r,Color(0.08,0.07,0.06,0.8))
 draw.draw_rect(r,Color(0.79,0.64,0.35,0.9),false,1.5)
 _text(Vector2(r.position.x,r.position.y+29),t,16,Color(0.95,0.9,0.8),FONT,HORIZONTAL_ALIGNMENT_CENTER,r.size.x)

func _help(vs: Vector2):
 var lines = ["WASD move · Shift sprint · Alt walk · Space jump (x3 in air, then dash)","Sprint into a wall: wall-run · Hold Space falling: glide",
  "Double-tap Space in air or F: fly (Space up, Ctrl down, Shift boost)","LMB punch · hold LMB: serious punch · R reset town",
  "Fly high to rise to the empire view · Tab/scroll: strategic map · click: dive","H hide help · F3 perf · Esc free mouse"]
 var r = Rect2(vs.x-500,16,482,lines.size()*19+14)
 draw.draw_rect(r,Color(0.08,0.07,0.06,0.6))
 for i in lines.size(): _text(Vector2(r.position.x+10,r.position.y+20+i*19),lines[i],14,Color(0.82,0.8,0.74))
