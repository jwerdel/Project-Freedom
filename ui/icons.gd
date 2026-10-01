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
  _:
   c.draw_circle(p.call(0.5,0.5),s*0.3,color)

static func _ellipse(center: Vector2,rx: float,ry: float,upper_half: bool) -> PackedVector2Array:
 var out = PackedVector2Array()
 var n = 16
 for i in n+1:
  var a = (PI+i*PI/n) if upper_half else i*TAU/n
  out.append(center+Vector2(cos(a)*rx,sin(a)*ry))
 return out
