extends RefCounted
# Movement action icons (TW:WH3 cursors and path end markers): move, attack, enter, merge, besiege
# and blocked, drawn as simple vector shapes on a round plate so one drawing serves the map marker
# (ui/movement_overlay.gd) and the mouse cursor (main.gd, rendered once into a texture).

const KINDS = ["move","attack","enter","merge","besiege","blocked"]
const PLATE = {"move":Color("2f6a22"),"attack":Color("8a1f17"),"enter":Color("2c4f7a"),"merge":Color("2c4f7a"),"besiege":Color("7a3b12"),"blocked":Color("5a1410")}
const INK = Color("fff3d0")

static func draw(ci: CanvasItem,kind: String,c: Vector2,r: float,plate := true):
 if plate:
  ci.draw_circle(c,r,Color(0.05,0.04,0.03,0.9))
  ci.draw_circle(c,r*0.86,PLATE.get(kind,Color("2f6a22")))
  ci.draw_arc(c,r*0.86,0,TAU,32,Color("e8c46a"),maxf(1.0,r*0.09),true)
 var s = r*0.55
 var w = maxf(1.5,r*0.13)
 match kind:
  "move":
   # A flag on a pole.
   ci.draw_line(c+Vector2(-s*0.45,s),c+Vector2(-s*0.45,-s),INK,w,true)
   ci.draw_colored_polygon(PackedVector2Array([c+Vector2(-s*0.45,-s),c+Vector2(s*0.85,-s*0.55),c+Vector2(-s*0.45,-s*0.1)]),INK)
  "attack":
   # Crossed swords.
   for d in [1.0,-1.0]:
    var a = c+Vector2(-s*d,s)
    var b = c+Vector2(s*d,-s)
    ci.draw_line(a,b,INK,w,true)
    var g = a.lerp(b,0.25)
    var n = (b-a).orthogonal().normalized()*s*0.32
    ci.draw_line(g-n,g+n,INK,w,true)
  "enter":
   # A gate: an arch with a doorway.
   ci.draw_rect(Rect2(c+Vector2(-s*0.8,-s*0.4),Vector2(s*1.6,s*1.3)),INK)
   for k in 3: ci.draw_rect(Rect2(c+Vector2(-s*0.8+k*s*0.6,-s*0.75),Vector2(s*0.4,s*0.4)),INK)
   ci.draw_circle(c+Vector2(0,s*0.25),s*0.38,PLATE.enter)
   ci.draw_rect(Rect2(c+Vector2(-s*0.38,s*0.25),Vector2(s*0.76,s*0.66)),PLATE.enter)
  "merge":
   # Two arrows meeting.
   ci.draw_line(c+Vector2(-s,0),c+Vector2(-s*0.1,0),INK,w,true)
   ci.draw_line(c+Vector2(s,0),c+Vector2(s*0.1,0),INK,w,true)
   ci.draw_colored_polygon(PackedVector2Array([c+Vector2(-s*0.05,0),c+Vector2(-s*0.45,-s*0.35),c+Vector2(-s*0.45,s*0.35)]),INK)
   ci.draw_colored_polygon(PackedVector2Array([c+Vector2(s*0.05,0),c+Vector2(s*0.45,-s*0.35),c+Vector2(s*0.45,s*0.35)]),INK)
   ci.draw_line(c+Vector2(0,-s*0.9),c+Vector2(0,s*0.9),INK,w*0.6,true)
  "besiege":
   # A tower with a ladder against it.
   ci.draw_rect(Rect2(c+Vector2(-s*0.2,-s*0.7),Vector2(s*0.8,s*1.6)),INK)
   for k in 2: ci.draw_rect(Rect2(c+Vector2(-s*0.2+k*s*0.5,-s),Vector2(s*0.3,s*0.35)),INK)
   ci.draw_line(c+Vector2(-s*0.95,s*0.9),c+Vector2(-s*0.35,-s*0.55),INK,w*0.8,true)
   ci.draw_line(c+Vector2(-s*0.6,s*0.9),c+Vector2(-s*0.05,-s*0.45),INK,w*0.8,true)
   for k in 4:
    var t = 0.15+k*0.22
    ci.draw_line(c+Vector2(-s*0.95,s*0.9).lerp(c+Vector2(-s*0.35,-s*0.55),t),c+Vector2(-s*0.6,s*0.9).lerp(c+Vector2(-s*0.05,-s*0.45),t),INK,w*0.5,true)
  "blocked":
   ci.draw_arc(c,s*0.95,0,TAU,24,INK,w,true)
   ci.draw_line(c+Vector2(-s*0.65,-s*0.65),c+Vector2(s*0.65,s*0.65),INK,w,true)
