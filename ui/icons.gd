extends RefCounted
# Simple vector icons drawn in a unit square, for placeholder UI glyphs and faction emblems.
# draw(canvas, kind, rect, color) must be called from the canvas item's _draw().

static func draw(c: CanvasItem,kind: String,r: Rect2,color: Color):
 var p = func(x: float,y: float) -> Vector2: return r.position+Vector2(x,y)*r.size
 var s = minf(r.size.x,r.size.y)
 var dark = color.darkened(0.45)
 var w = maxf(1.5,s*0.08)
 match kind:
  "coin":
   c.draw_circle(p.call(0.5,0.5),s*0.42,color)
   c.draw_arc(p.call(0.5,0.5),s*0.30,0,TAU,24,dark,w*0.6)
  "income":
   c.draw_circle(p.call(0.42,0.6),s*0.32,color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.62,0.42),p.call(0.82,0.12),p.call(1.0,0.42)]),Color("7fd16a"))
   c.draw_line(p.call(0.82,0.4),p.call(0.82,0.7),Color("7fd16a"),w)
  "population":
   for x in [0.32,0.68]:
    c.draw_circle(p.call(x,0.3),s*0.14,color)
    c.draw_colored_polygon(_ellipse(p.call(x,0.82),s*0.2,s*0.28,true),color)
  "year":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.2,0.1),p.call(0.8,0.1),p.call(0.5,0.5)]),color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.5,0.5),p.call(0.8,0.9),p.call(0.2,0.9)]),color)
   c.draw_line(p.call(0.15,0.08),p.call(0.85,0.08),dark,w)
   c.draw_line(p.call(0.15,0.92),p.call(0.85,0.92),dark,w)
  "faction":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.12,0.78),p.call(0.12,0.3),p.call(0.32,0.52),p.call(0.5,0.2),p.call(0.68,0.52),p.call(0.88,0.3),p.call(0.88,0.78)]),color)
  "diplomacy":
   c.draw_rect(Rect2(p.call(0.2,0.22),Vector2(0.6,0.56)*r.size),color)
   for y in [0.2,0.8]: c.draw_colored_polygon(_ellipse(p.call(0.5,y),s*0.34,s*0.08,false),dark)
   for y in [0.4,0.52,0.64]: c.draw_line(p.call(0.3,y),p.call(0.7,y),dark,w*0.6)
  "chronicle":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.08,0.25),p.call(0.48,0.32),p.call(0.48,0.86),p.call(0.08,0.78)]),color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.52,0.32),p.call(0.92,0.25),p.call(0.92,0.78),p.call(0.52,0.86)]),color)
   for y in [0.45,0.58,0.7]:
    c.draw_line(p.call(0.15,y-0.02),p.call(0.42,y+0.02),dark,w*0.5)
    c.draw_line(p.call(0.58,y+0.02),p.call(0.85,y-0.02),dark,w*0.5)
  "tech":
   c.draw_rect(Rect2(p.call(0.18,0.18),Vector2(0.64,0.64)*r.size),color)
   c.draw_line(p.call(0.5,0.18),p.call(0.5,0.82),dark,w)
  "lords":
   c.draw_colored_polygon(_ellipse(p.call(0.5,0.55),s*0.32,s*0.36,false),color)
   c.draw_rect(Rect2(p.call(0.2,0.55),Vector2(0.6,0.3)*r.size),color)
   c.draw_line(p.call(0.28,0.55),p.call(0.72,0.55),dark,w)
   c.draw_line(p.call(0.5,0.55),p.call(0.5,0.85),dark,w)
  "finance":
   for i in 4: c.draw_colored_polygon(_ellipse(p.call(0.5,0.8-i*0.17),s*0.32,s*0.11,false),color if i%2==0 else color.darkened(0.15))
  "objectives":
   c.draw_line(p.call(0.25,0.1),p.call(0.25,0.92),color,w)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.28,0.12),p.call(0.85,0.3),p.call(0.28,0.5)]),color)
  "borders":
   for i in 8:
    var a = i*TAU/8
    c.draw_arc(p.call(0.5,0.5),s*0.36,a,a+TAU/16,4,color,w)
  "settlements":
   c.draw_rect(Rect2(p.call(0.18,0.42),Vector2(0.64,0.46)*r.size),color)
   for x in [0.18,0.42,0.66]: c.draw_rect(Rect2(p.call(x,0.26),Vector2(0.16,0.17)*r.size),color)
   c.draw_rect(Rect2(p.call(0.42,0.62),Vector2(0.16,0.26)*r.size),dark)
  "armies":
   for d in [1,-1]:
    var a = p.call(0.5-0.32*d,0.85)
    var b = p.call(0.5+0.32*d,0.15)
    c.draw_line(a,b,color,w*1.2)
    c.draw_line(p.call(0.5-0.32*d-0.1,0.66),p.call(0.5-0.32*d+0.14,0.8),color,w)
  "plus":
   c.draw_line(p.call(0.5,0.2),p.call(0.5,0.8),color,w*1.4)
   c.draw_line(p.call(0.2,0.5),p.call(0.8,0.5),color,w*1.4)
  "spire":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.5,0.06),p.call(0.68,0.62),p.call(0.32,0.62)]),color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.14,0.92),p.call(0.32,0.6),p.call(0.68,0.6),p.call(0.86,0.92)]),color.darkened(0.12))
  "wave":
   for row in 3:
    var pts = PackedVector2Array()
    for i in 13: pts.append(p.call(0.1+i*0.8/12,0.32+row*0.2+sin(i*1.05)*0.07))
    c.draw_polyline(pts,color,w)
  "wheat":
   c.draw_line(p.call(0.5,0.95),p.call(0.5,0.15),color,w)
   for i in 4:
    var y = 0.22+i*0.15
    for d in [-1,1]: c.draw_colored_polygon(_ellipse(p.call(0.5+d*0.1,y),s*0.07,s*0.12,false),color)
  "tower":
   c.draw_rect(Rect2(p.call(0.3,0.3),Vector2(0.4,0.62)*r.size),color)
   for x in [0.26,0.44,0.62]: c.draw_rect(Rect2(p.call(x,0.16),Vector2(0.12,0.16)*r.size),color)
   c.draw_rect(Rect2(p.call(0.44,0.66),Vector2(0.12,0.26)*r.size),dark)
  "mountain":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.05,0.9),p.call(0.38,0.22),p.call(0.6,0.55),p.call(0.72,0.38),p.call(0.95,0.9)]),color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.3,0.38),p.call(0.38,0.22),p.call(0.46,0.38)]),dark)
  "star":
   var sp = PackedVector2Array()
   for i in 10: sp.append(p.call(0.5,0.52)+Vector2.from_angle(-PI*0.5+i*PI/5.0)*s*(0.44 if i%2 == 0 else 0.18))
   c.draw_colored_polygon(sp,color)
  "sun":
   c.draw_circle(p.call(0.5,0.5),s*0.22,color)
   for i in 12: c.draw_line(p.call(0.5,0.5)+Vector2.from_angle(i*PI/6.0)*s*0.28,p.call(0.5,0.5)+Vector2.from_angle(i*PI/6.0)*s*0.44,color,w)
  "moon":
   c.draw_circle(p.call(0.5,0.5),s*0.36,color)
   c.draw_circle(p.call(0.64,0.4),s*0.3,dark if dark.a>0 else Color(0,0,0,0))
  "tree":
   c.draw_rect(Rect2(p.call(0.45,0.6),Vector2(0.1,0.32)*r.size),color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.5,0.06),p.call(0.82,0.66),p.call(0.18,0.66)]),color)
  "hammer":
   c.draw_rect(Rect2(p.call(0.45,0.3),Vector2(0.1,0.62)*r.size),color)
   c.draw_rect(Rect2(p.call(0.2,0.14),Vector2(0.6,0.2)*r.size),color)
  "ship":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.08,0.62),p.call(0.92,0.62),p.call(0.75,0.85),p.call(0.25,0.85)]),color)
   c.draw_line(p.call(0.5,0.62),p.call(0.5,0.1),color,w)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.54,0.14),p.call(0.84,0.54),p.call(0.54,0.54)]),color)
  "flame":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.5,0.05),p.call(0.72,0.45),p.call(0.68,0.8),p.call(0.5,0.92),p.call(0.32,0.8),p.call(0.28,0.45),p.call(0.42,0.5)]),color)
  "key":
   c.draw_arc(p.call(0.5,0.25),s*0.15,0,TAU,16,color,w*1.2)
   c.draw_line(p.call(0.5,0.4),p.call(0.5,0.9),color,w*1.4)
   c.draw_line(p.call(0.5,0.75),p.call(0.66,0.75),color,w*1.2)
   c.draw_line(p.call(0.5,0.86),p.call(0.62,0.86),color,w*1.2)
  "horn":
   var hp = PackedVector2Array()
   for i in 9: hp.append(p.call(0.2+i*0.075,0.75-sin(i*0.35)*0.5))
   c.draw_polyline(hp,color,w*2.2)
   c.draw_circle(hp[-1],s*0.08,color)
  "eye":
   c.draw_colored_polygon(_ellipse(p.call(0.5,0.5),s*0.42,s*0.2,false),color)
   c.draw_circle(p.call(0.5,0.5),s*0.12,dark)
  "sword":
   c.draw_line(p.call(0.5,0.06),p.call(0.5,0.78),color,w*1.6)
   c.draw_line(p.call(0.3,0.7),p.call(0.7,0.7),color,w*1.6)
   c.draw_line(p.call(0.5,0.78),p.call(0.5,0.94),color,w*1.2)
  "axe":
   c.draw_line(p.call(0.46,0.1),p.call(0.46,0.94),color,w*1.2)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.48,0.14),p.call(0.86,0.22),p.call(0.86,0.5),p.call(0.48,0.42)]),color)
  "anvil":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.1,0.3),p.call(0.9,0.3),p.call(0.7,0.5),p.call(0.62,0.5),p.call(0.7,0.82),p.call(0.3,0.82),p.call(0.38,0.5),p.call(0.25,0.45)]),color)
  "boar":
   c.draw_colored_polygon(_ellipse(p.call(0.48,0.55),s*0.34,s*0.22,false),color)
   c.draw_colored_polygon(PackedVector2Array([p.call(0.78,0.45),p.call(0.95,0.55),p.call(0.78,0.65)]),color)
   for x in [0.3,0.62]: c.draw_line(p.call(x,0.7),p.call(x,0.88),color,w*1.2)
   c.draw_line(p.call(0.86,0.6),p.call(0.94,0.48),dark,w)
  "wolf":
   c.draw_colored_polygon(PackedVector2Array([p.call(0.2,0.2),p.call(0.38,0.38),p.call(0.62,0.38),p.call(0.8,0.2),p.call(0.76,0.55),p.call(0.5,0.9),p.call(0.24,0.55)]),color)
   for x in [0.4,0.6]: c.draw_circle(p.call(x,0.52),s*0.04,dark)
  "magnify":
   c.draw_arc(p.call(0.42,0.42),s*0.26,0,TAU,24,color,w*1.2)
   c.draw_line(p.call(0.61,0.61),p.call(0.88,0.88),color,w*2.0)
  "skull":
   c.draw_circle(p.call(0.5,0.42),s*0.32,color)
   c.draw_rect(Rect2(p.call(0.34,0.6),Vector2(0.32,0.24)*r.size),color)
   for x in [0.38,0.62]: c.draw_circle(p.call(x,0.42),s*0.08,dark)
  _:
   c.draw_circle(p.call(0.5,0.5),s*0.3,color)

static func _ellipse(center: Vector2,rx: float,ry: float,upper_half: bool) -> PackedVector2Array:
 var out = PackedVector2Array()
 var n = 16
 for i in n+1:
  var a = (PI+i*PI/n) if upper_half else i*TAU/n
  out.append(center+Vector2(cos(a)*rx,sin(a)*ry))
 return out

# Upgrade available (TW:WH3): a green up-arrow in a dark disc, centred at c with radius r.
static func upgrade_arrow(ci: CanvasItem,c: Vector2,r: float):
 ci.draw_circle(c,r+1.5,Color(0.05,0.08,0.04,0.9))
 ci.draw_circle(c,r,Color("3d8f2e"))
 var pts = PackedVector2Array([c+Vector2(0,-r*0.72),c+Vector2(r*0.62,-r*0.02),c+Vector2(r*0.24,-r*0.02),c+Vector2(r*0.24,r*0.66),c+Vector2(-r*0.24,r*0.66),c+Vector2(-r*0.24,-r*0.02),c+Vector2(-r*0.62,-r*0.02)])
 ci.draw_colored_polygon(pts,Color("e9ffd8"))

# Settlement can build or upgrade (TW:WH3 green hammer), centred at c.
static func upgrade_hammer(ci: CanvasItem,c: Vector2,r: float):
 ci.draw_circle(c,r+1.5,Color(0.05,0.08,0.04,0.9))
 ci.draw_circle(c,r,Color("3d8f2e"))
 var head = Rect2(c+Vector2(-r*0.55,-r*0.6),Vector2(r*1.1,r*0.42))
 ci.draw_rect(head,Color("e9ffd8"))
 ci.draw_line(c+Vector2(0,-r*0.2),c+Vector2(0,r*0.65),Color("e9ffd8"),maxf(2.0,r*0.24))

# A faction's crest (original heraldry): its field in the primary tincture, an optional division in
# a second tincture, and the charge, all clipped to `shape` (a shield, pennant or banner outline).
# faction.crest: {division: plain|pale|fess|bend|chevron|quarterly|saltire|chief|bordure, field2,
# charge (an icon kind), charge_color}; without one, the emblem on the primary colour.
const DIVISIONS = ["plain","pale","fess","bend","chevron","quarterly","saltire","chief","bordure"]
static func crest(ci: CanvasItem,faction: Dictionary,shape: PackedVector2Array,charge_rect: Rect2):
 var cr = faction.get("crest",{})
 var primary = Color(faction.get("primary","#777777"))
 var secondary = Color(faction.get("secondary","#dddddd"))
 ci.draw_colored_polygon(shape,primary)
 var field2 = Color(cr.get("field2",secondary.to_html()))
 var b = Rect2(shape[0],Vector2.ZERO)
 for v in shape: b = b.expand(v)
 var cx = b.get_center().x
 var cy = b.position.y+b.size.y*0.45
 var parts = []
 match str(cr.get("division","plain")):
  "pale": parts.append(PackedVector2Array([Vector2(cx,b.position.y),b.end*Vector2(1,0)+Vector2(0,b.position.y),b.end,Vector2(cx,b.end.y)]))
  "fess": parts.append(PackedVector2Array([Vector2(b.position.x,cy),Vector2(b.end.x,cy),b.end,Vector2(b.position.x,b.end.y)]))
  "bend": parts.append(PackedVector2Array([b.position,Vector2(b.end.x,b.end.y),Vector2(b.position.x,b.end.y)]))
  "chevron":
   var t = b.size.y*0.18
   parts.append(PackedVector2Array([Vector2(b.position.x,b.end.y-t*1.4),Vector2(cx,cy-t),Vector2(b.end.x,b.end.y-t*1.4),Vector2(b.end.x,b.end.y-t*0.2),Vector2(cx,cy+t*0.6),Vector2(b.position.x,b.end.y-t*0.2)]))
  "quarterly":
   parts.append(PackedVector2Array([Vector2(cx,b.position.y),Vector2(b.end.x,b.position.y),Vector2(b.end.x,cy),Vector2(cx,cy)]))
   parts.append(PackedVector2Array([Vector2(b.position.x,cy),Vector2(cx,cy),Vector2(cx,b.end.y),Vector2(b.position.x,b.end.y)]))
  "saltire":
   var k = b.size.x*0.12
   parts.append(PackedVector2Array([b.position+Vector2(k,0),b.position,b.end-Vector2(k,0),b.end]))
   parts.append(PackedVector2Array([Vector2(b.end.x-k,b.position.y),Vector2(b.end.x,b.position.y),Vector2(b.position.x+k,b.end.y),Vector2(b.position.x,b.end.y)]))
  "chief": parts.append(PackedVector2Array([b.position,Vector2(b.end.x,b.position.y),Vector2(b.end.x,b.position.y+b.size.y*0.3),Vector2(b.position.x,b.position.y+b.size.y*0.3)]))
 for poly in parts:
  for clipped in Geometry2D.intersect_polygons(shape,poly): ci.draw_colored_polygon(clipped,field2)
 if str(cr.get("division","")) == "bordure":
  var outline = shape.duplicate()
  outline.append(shape[0])
  ci.draw_polyline(outline,field2,maxf(2.0,b.size.x*0.1))
 var charge = str(cr.get("charge",faction.get("emblem","")))
 if charge != "": draw(ci,charge,charge_rect,Color(cr.get("charge_color",secondary.to_html())))
