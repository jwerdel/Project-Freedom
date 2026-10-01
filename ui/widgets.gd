extends RefCounted
# Small reusable campaign UI controls: a framed panel, round icon buttons, icons, faction emblems
# and a public-order style bar. Each is a Control subclass defined here as an inner class.

const UiKit = preload("res://ui/ui_kit.gd")
const Icons = preload("res://ui/icons.gd")

# PanelContainer with a 9-slice Kenney frame drawn over its background.
class Framed extends PanelContainer:
 var frame_kind := "main"
 var trim := Color("c9a45a")
 func _init(kind := "main",tint := Color("c9a45a"),bg := Color(0,0,0,0)):
  frame_kind = kind
  trim = tint
  texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  if bg.a>0: add_theme_stylebox_override("panel",UiKit.flat(bg,14))
 func _draw():
  draw_style_box(UiKit.frame_box(frame_kind,trim),Rect2(Vector2.ZERO,size))

class Icon extends Control:
 var kind := ""
 var color := Color.WHITE
 func _init(k := "",c := Color.WHITE,s := 22.0):
  kind = k
  color = c
  custom_minimum_size = Vector2(s,s)
  mouse_filter = Control.MOUSE_FILTER_IGNORE
 func _draw():
  Icons.draw(self,kind,Rect2(Vector2.ZERO,size),color)

# Heraldic shield in the faction's colors with its emblem.
class Emblem extends Control:
 var faction := {}
 func _init(f := {},s := 34.0):
  faction = f
  custom_minimum_size = Vector2(s,s*1.15)
  mouse_filter = Control.MOUSE_FILTER_IGNORE
 func _draw():
  var c = UiKit.colors(faction)
  var w = size.x
  var h = size.y
  var pts = PackedVector2Array([Vector2(0,0),Vector2(w,0),Vector2(w,h*0.55),Vector2(w*0.5,h),Vector2(0,h*0.55)])
  draw_colored_polygon(pts,c.primary)
  pts.append(pts[0])
  draw_polyline(pts,c.secondary,maxf(1.5,w*0.06))
  Icons.draw(self,faction.get("emblem",""),Rect2(w*0.2,h*0.1,w*0.6,h*0.62),c.secondary)

# Round button: Kenney round button art, a metal ring, and an icon.
class RoundButton extends Button:
 var icon_kind := ""
 var ring := Color("c9a45a")
 var toggled_look := false
 func _init(kind := "",tip := "",diameter := 46.0,trim := Color("c9a45a")):
  icon_kind = kind
  ring = trim
  tooltip_text = tip
  custom_minimum_size = Vector2(diameter,diameter)
  flat = true
  focus_mode = Control.FOCUS_NONE
  mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
  mouse_entered.connect(queue_redraw)
  mouse_exited.connect(queue_redraw)
  toggled.connect(func(_on): queue_redraw())
 func _draw():
  var r = minf(size.x,size.y)*0.5
  var center = size*0.5
  var hover = is_hovered()
  draw_texture_rect(UiKit.BUTTON_ROUND_LIGHT if (hover or (toggle_mode and button_pressed)) else UiKit.BUTTON_ROUND,Rect2(center-Vector2(r,r)*0.92,Vector2(r,r)*1.84),false)
  draw_circle(center,r*0.74,Color(0.08,0.06,0.05,0.82))
  draw_arc(center,r*0.93,0,TAU,40,ring.darkened(0.3),r*0.12)
  draw_arc(center,r*0.84,0,TAU,40,ring.lightened(0.15) if hover else ring,r*0.07)
  var dim = 1.0 if (not toggle_mode or button_pressed) else 0.55
  Icons.draw(self,icon_kind,Rect2(center-Vector2(r,r)*0.48,Vector2(r,r)*0.96),Color("ead9b0")*Color(dim,dim,dim))

# Horizontal bar from -1..1 (e.g. public order), Kenney bar pieces, green when positive.
class OrderBar extends Control:
 var value := 0.0
 func _init(v := 0.0):
  value = v
  custom_minimum_size = Vector2(200,18)
  mouse_filter = Control.MOUSE_FILTER_IGNORE
 func _draw():
  _bar(UiKit.BAR.back,Rect2(Vector2.ZERO,size))
  var mid = size.x*0.5
  var len = absf(clampf(value,-1,1))*(mid-4)
  if len>4:
   var r = Rect2(Vector2(mid,2),Vector2(len,size.y-4)) if value>0 else Rect2(Vector2(mid-len,2),Vector2(len,size.y-4))
   _bar(UiKit.BAR.good if value>0 else UiKit.BAR.bad,r)
  draw_line(Vector2(mid,0),Vector2(mid,size.y),Color(0,0,0,0.6),2)
 func _bar(parts: Array,r: Rect2):
  var cap = minf(r.size.y*0.5,r.size.x*0.5)
  draw_texture_rect(parts[0],Rect2(r.position,Vector2(cap,r.size.y)),false)
  draw_texture_rect(parts[1],Rect2(r.position+Vector2(cap,0),Vector2(r.size.x-cap*2,r.size.y)),false)
  draw_texture_rect(parts[2],Rect2(r.position+Vector2(r.size.x-cap,0),Vector2(cap,r.size.y)),false)
