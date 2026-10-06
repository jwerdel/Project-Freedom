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
 custom_minimum_size = (BASE+Vector2(10,8))*s
 size = custom_minimum_size
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
