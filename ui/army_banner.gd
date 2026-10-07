extends Button
# TW:WH3-style floating faction banner above an army on the campaign map: a hanging banner on a
# crossbar in the faction's colors with its emblem. Screen-space, so it stays readable at every
# zoom; the map sets its scale (smaller far out, within a minimum) and fades it when the camera is
# very close (data/campaign_view.json). Clicking it selects the army.

const UiKit = preload("res://ui/ui_kit.gd")
const Icons = preload("res://ui/icons.gd")
const BASE = Vector2(30,46) # cloth size at scale 1

var army_id := ""
var faction := {}
var selected := false
var banner_scale := 1.0
var host_role := "" # "leader" or "member" of a Host (war-and-realm §2.5), "" otherwise
var movement := -1.0 # movement left 0..1 (your armies; -1 hides the bar)

func _init(id: String,faction_data: Dictionary,tip: String):
 army_id = id
 faction = faction_data
 tooltip_text = tip
 flat = true
 focus_mode = Control.FOCUS_NONE
 mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
 texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 mouse_entered.connect(queue_redraw)
 mouse_exited.connect(queue_redraw)
 set_banner_scale(1.0)

func set_banner_scale(s: float):
 if is_equal_approx(s,banner_scale) and size != Vector2.ZERO: return
 banner_scale = s
 custom_minimum_size = (BASE+Vector2(10,16))*s
 size = custom_minimum_size
 queue_redraw()

# Movement points left as a bar under the cloth (owner spec 2026-10-07; your armies only).
func set_movement(frac: float):
 if absf(frac-movement)<0.005: return
 movement = frac
 queue_redraw()

func set_host(role: String):
 if role == host_role: return
 host_role = role
 queue_redraw()

func set_selected(on: bool):
 if on == selected: return
 selected = on
 queue_redraw()

# Screen point the banner's foot (the bottom of its tail) sits on.
func anchor_offset() -> Vector2:
 return Vector2(size.x*0.5,size.y)

func _draw():
 var c = UiKit.colors(faction)
 var s = banner_scale
 var hover = get_global_rect().has_point(get_global_mouse_position())
 var trim = Color("f6d77c") if (selected or hover) else c.secondary
 var cx = size.x*0.5
 var w = BASE.x*s
 var h = BASE.y*s
 var top = 4.0*s
 # Crossbar with finials.
 draw_line(Vector2(cx-w*0.5-4*s,top),Vector2(cx+w*0.5+4*s,top),Color("3a2a1a"),maxf(2.0,3.0*s))
 draw_circle(Vector2(cx-w*0.5-4*s,top),2.2*s,trim)
 draw_circle(Vector2(cx+w*0.5+4*s,top),2.2*s,trim)
 # Cloth with a pointed tail.
 var pts = PackedVector2Array([Vector2(cx-w*0.5,top),Vector2(cx+w*0.5,top),Vector2(cx+w*0.5,top+h*0.78),Vector2(cx,top+h),Vector2(cx-w*0.5,top+h*0.78)])
 Icons.crest(self,faction,pts,Rect2(cx-w*0.32,top+h*0.2,w*0.64,h*0.5))
 # A band in the secondary color across the top.
 draw_rect(Rect2(cx-w*0.5,top,w,h*0.12),c.secondary.darkened(0.15))
 var outline = pts.duplicate()
 outline.append(pts[0])
 draw_polyline(outline,trim,maxf(1.5,(2.6 if selected else 1.8)*s))
 # A Host: the commanding lord's banner carries a gold star, its armies a gold pip.
 if host_role == "leader":
  var sc = Vector2(cx+w*0.5+2*s,top+2*s)
  var star = PackedVector2Array()
  for i in 10:
   var rr = (6.0 if i%2 == 0 else 2.6)*s
   star.append(sc+Vector2.from_angle(-PI*0.5+i*PI/5.0)*rr)
  draw_colored_polygon(star,Color("f2cf6a"))
 elif host_role == "member":
  draw_circle(Vector2(cx+w*0.5+1*s,top+3*s),3.0*s,Color("f2cf6a"))
 if movement>=0.0:
  var bw = w+6*s
  var r = Rect2(cx-bw*0.5,top+h+4*s,bw,maxf(4.0,5.0*s))
  draw_rect(r.grow(1.0),Color(0.03,0.02,0.02,0.9))
  draw_rect(Rect2(r.position,Vector2(r.size.x*clampf(movement,0,1),r.size.y)),Color("f2c94c") if movement>0.02 else Color("6b5a3a"))
 # The lord's name on a dark plate when hovered or selected (TW:WH3 names lords on hover).
 if hover or selected:
  var nm = tooltip_text.get_slice("\n",0)
  var f = UiKit.FONT_BOLD
  var fs = 15
  var tw = f.get_string_size(nm,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
  var y = top+h+(14.0 if movement>=0.0 else 6.0)*s
  var pr = Rect2(cx-tw*0.5-8,y,tw+16,22)
  draw_rect(pr,Color(0.05,0.04,0.03,0.92))
  draw_rect(pr,trim,false,1.2)
  draw_string_outline(f,Vector2(cx-tw*0.5,y+16),nm,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,3,Color(0,0,0,0.9))
  draw_string(f,Vector2(cx-tw*0.5,y+16),nm,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("fff0cc"))
