extends Button
# Map banner for a settlement: a pennant in the owner's colors with its emblem, a name plate and
# level pips. Fixed screen size so it reads at every zoom level; the owner positions it each frame.

const UiKit = preload("res://ui/ui_kit.gd")
const Icons = preload("res://ui/icons.gd")

const PENNANT = Vector2(34,44)
const PLATE_H = 26.0
const MAX_LEVEL = 3
const SIEGE_H = 20.0

var settlement_id := ""
var settlement := {}
var selected := false
var compact := false # high zoom: the pennant only (the name is in the tooltip)

func _init(s: Dictionary):
 settlement_id = s.id
 flat = true
 focus_mode = Control.FOCUS_NONE
 mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
 texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 mouse_entered.connect(queue_redraw)
 mouse_exited.connect(queue_redraw)
 update_settlement(s)

func update_settlement(s: Dictionary):
 settlement = s
 tooltip_text = "%s\n%s\n%s\n%s · level %d" % [s.name,s.faction.name,s.province_name,s.type.capitalize(),s.level]
 _resize()

func _resize():
 var s = settlement
 var w = PENNANT.x+12 if compact else maxf(PENNANT.x+12,UiKit.head_font().get_string_size(s.name.to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+28)
 var h = PENNANT.y+4 if compact else PENNANT.y+PLATE_H+12
 custom_minimum_size = Vector2(w,h+(SIEGE_H if not s.get("siege",{}).is_empty() else 0.0))
 size = custom_minimum_size
 queue_redraw()

# High zoom (main.gd): small settlements show only their pennant so the map stays readable.
func set_compact(on: bool):
 if on == compact: return
 compact = on
 _resize()

func set_selected(on: bool):
 if on == selected: return
 selected = on
 queue_redraw()

# Screen point the banner's foot should sit on (the bottom of the pole tip).
func anchor_offset() -> Vector2:
 return Vector2(size.x*0.5,size.y)

func _draw():
 var c = UiKit.colors(settlement.faction)
 var hover = get_global_rect().has_point(get_global_mouse_position())
 var cx = size.x*0.5
 var trim = Color("f6d77c") if (selected or hover) else c.secondary
 # Pennant with a swallowtail, hanging above the plate.
 var top = 0.0
 var pts = PackedVector2Array([Vector2(cx-PENNANT.x*0.5,top),Vector2(cx+PENNANT.x*0.5,top),Vector2(cx+PENNANT.x*0.5,top+PENNANT.y),Vector2(cx,top+PENNANT.y-9),Vector2(cx-PENNANT.x*0.5,top+PENNANT.y)])
 Icons.crest(self,settlement.faction,pts,Rect2(cx-11,top+7,22,24))
 var outline = pts.duplicate()
 outline.append(pts[0])
 draw_polyline(outline,trim,2.0 if not selected else 3.0)
 draw_line(Vector2(cx-PENNANT.x*0.5-4,top),Vector2(cx+PENNANT.x*0.5+4,top),Color("3a2a1a"),4)
 if compact:
  var sg0 = settlement.get("siege",{})
  if not sg0.is_empty(): draw_rect(Rect2(Vector2(cx-PENNANT.x*0.5,PENNANT.y+2),Vector2(PENNANT.x,SIEGE_H-6)),Color("7a1c1c",0.92))
  return
 # Name plate.
 var plate = Rect2(Vector2(2,PENNANT.y+2),Vector2(size.x-4,PLATE_H))
 draw_rect(plate,Color(0.07,0.05,0.04,0.9))
 draw_style_box(UiKit.frame_box("thin",trim),plate.grow(2))
 var name = settlement.name.to_upper()
 var f = UiKit.head_font()
 var tw = f.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
 # A dark outline under the letters (2026-10-07): the name reads on any terrain behind the plate.
 draw_string_outline(f,Vector2(cx-tw*0.5,plate.position.y+18),name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,4,Color(0.02,0.01,0.0,0.95))
 draw_string(f,Vector2(cx-tw*0.5,plate.position.y+18),name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff0cc"))
 # Level pips under the plate.
 for i in MAX_LEVEL:
  var p = Vector2(cx+(i-1)*12,plate.end.y+6)
  draw_circle(p,4.2,Color(0,0,0,0.75))
  draw_circle(p,3.0,Color("f2cf6a") if i<int(settlement.level) else Color(0.35,0.3,0.25))
 # Something can be built or upgraded here (the player's own settlements): the TW:WH3 green hammer.
 if settlement.get("upgrade_available",false): Icons.upgrade_hammer(self,Vector2(plate.end.x-2,plate.position.y-2),9.0)
 # A muster point: the banners gather here (visible to the world).
 if str(settlement.get("muster","")) != "":
  var mt = Rect2(Vector2(cx-40,plate.position.y-18),Vector2(80,15))
  draw_rect(mt,Color(UiKit.colors(settlement.faction).primary.darkened(0.3),0.95))
  draw_rect(mt,Color("f2cf6a"),false,1.2)
  var mw = UiKit.FONT_BOLD.get_string_size("MUSTER",HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
  draw_string(UiKit.FONT_BOLD,Vector2(cx-mw*0.5,mt.position.y+12),"MUSTER",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("f2cf6a"))
 # Under siege: a red tag under the pips with the besieger and the turns held.
 var sg = settlement.get("siege",{})
 if not sg.is_empty():
  var txt = "BESIEGED %d/%d" % [sg.turns,sg.endurance]
  var tag = Rect2(Vector2(cx-46,plate.end.y+12),Vector2(92,SIEGE_H-4))
  draw_rect(tag,Color("7a1c1c",0.92))
  draw_rect(tag,UiKit.colors(sg.faction).primary.lightened(0.3),false,1.5)
  var sw = UiKit.FONT_BOLD.get_string_size(txt,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
  draw_string(UiKit.FONT_BOLD,Vector2(cx-sw*0.5,tag.position.y+12),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffe3c8"))
