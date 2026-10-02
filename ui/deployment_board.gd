extends Control
# 2D top-down deployment board: the same lanes, lines, general's row and reserve as the 3D
# tabletop, drawn flat. Unit chips show faction color, a short name and the order letter; Protect
# and Flank draw arrows. The player's side is at the bottom. Click reports a slot.

signal slot_clicked(slot: Dictionary)

const UiKit = preload("res://ui/ui_kit.gd")
const TERRAIN_COLORS = {"open":Color("6f8a4a"),"road":Color("8a7556"),"forest":Color("3f6332"),"hills":Color("7d7a4c"),"pass":Color("7b7262"),"closed":Color("3b3632")}
const ORDER_LETTERS = {"hold":"H","aggressive":"A","flank":"F","protect":"P","reserve":"R"}
const ORDER_COLORS = {"hold":Color("e9e2c8"),"aggressive":Color("ef8a6a"),"flank":Color("e9cf5a"),"protect":Color("7fc8ef"),"reserve":Color("b7a8e0")}

var terrain: Array = []
var lanes := 5
var player_role := 0
var walls := false
var units: Array = []       # {key, unit, name, lane, line, order, hidden, role, color}
var arrows: Array = []      # {from_key, to_key | to_slot, color}
var selected := ""
var general_lanes := [2,2]

func setup(t: Array,role: int,has_walls: bool):
 terrain = t
 lanes = t.size()
 player_role = role
 walls = has_walls
 queue_redraw()

# Rows from top to bottom: enemy reserve, enemy general, the six bands, our general, our reserve.
func rows() -> Array:
 var enemy = 1-player_role
 var out = [[enemy,"reserve"],[enemy,"general"]]
 var bands = range(6) if player_role == 1 else range(5,-1,-1)
 for b in bands: out.append(["band",b])
 out.append([player_role,"general"])
 out.append([player_role,"reserve"])
 return out

func cell_rect(row: int,lane: int) -> Rect2:
 var h = size.y/rows().size()
 var w = size.x/lanes
 return Rect2(lane*w,row*h,w,h)

func row_of(role: int,line: String) -> int:
 var r = rows()
 for i in r.size():
  if r[i][0] is int and r[i][0] == role and r[i][1] == line: return i
 var b = (1 if line == "front" else 0) if role == 0 else (4 if line == "front" else 5)
 for i in r.size():
  if r[i][0] is String and r[i][1] == b: return i
 return -1

func chip_rect(u: Dictionary,k: int,n: int) -> Rect2:
 var row = row_of(u.role,u.line)
 if u.line == "reserve":
  var w = size.x/maxi(6,n)
  var r = cell_rect(row,0)
  return Rect2(k*w+3,r.position.y+4,w-6,r.size.y-8)
 var c = cell_rect(row,int(u.lane))
 var cw = c.size.x/maxi(1,n)
 return Rect2(c.position.x+k*cw+3,c.position.y+4,cw-6,c.size.y-8)

func _layout() -> Dictionary:
 var groups = {}
 for u in units:
  var gk = "%d:%s:%d" % [u.role,u.line,int(u.lane) if u.line != "reserve" else 0]
  if not groups.has(gk): groups[gk] = []
  groups[gk].append(u)
 var out = {}
 for gk in groups:
  var list = groups[gk]
  for k in list.size(): out[list[k].key] = chip_rect(list[k],k,list.size())
 return out

func _draw():
 if terrain.is_empty(): return
 var r = rows()
 var f = UiKit.FONT_BOLD
 for i in r.size():
  for l in lanes:
   var rect = cell_rect(i,l)
   var col = Color("2c241c")
   if r[i][0] is String: col = TERRAIN_COLORS.get(terrain[l][r[i][1]],TERRAIN_COLORS.open)
   elif r[i][1] == "general": col = Color("3a3226")
   draw_rect(rect.grow(-1),col)
  if r[i][0] is int:
   var lbl = ("Your " if r[i][0] == player_role else "Enemy ")+("general" if r[i][1] == "general" else "reserve")
   draw_string(f,Vector2(6,cell_rect(i,0).position.y+14),lbl,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(1,1,1,0.45))
 if walls:
  var b = row_of(1,"front")
  var y = cell_rect(b,0).end.y if player_role == 0 else cell_rect(b,0).position.y
  draw_line(Vector2(0,y),Vector2(size.x,y),Color("cfc6b0"),5.0)
 for g in 2:
  var gr = cell_rect(row_of(g,"general"),int(general_lanes[g])).grow(-6)
  draw_rect(gr,Color("f2cf6a",0.35))
  draw_string(f,gr.position+Vector2(4,gr.size.y*0.6),"General",HORIZONTAL_ALIGNMENT_LEFT,gr.size.x-8,12,Color("f1d79a"))
 var lay = _layout()
 for u in units:
  var cr: Rect2 = lay[u.key]
  draw_rect(cr,Color(u.color).darkened(0.25) if not u.hidden else Color("555555"))
  draw_rect(cr,Color("ffe08a") if u.key == selected else Color(0,0,0,0.6),false,3.0 if u.key == selected else 1.0)
  var name = "?" if u.hidden else u.name
  draw_string(f,cr.position+Vector2(4,cr.size.y*0.45),name,HORIZONTAL_ALIGNMENT_LEFT,cr.size.x-8,12,Color("f1e6c8"))
  if not u.hidden:
   draw_string(f,cr.position+Vector2(4,cr.size.y*0.85),ORDER_LETTERS.get(u.order,""),HORIZONTAL_ALIGNMENT_LEFT,-1,13,ORDER_COLORS.get(u.order,Color.WHITE))
 for a in arrows:
  if not lay.has(a.from_key): continue
  var p0 = lay[a.from_key].get_center()
  var p1: Vector2
  if a.has("to_key") and lay.has(a.to_key): p1 = lay[a.to_key].get_center()
  elif a.has("to_slot"): p1 = cell_rect(row_of(a.to_slot.role,a.to_slot.line),int(a.to_slot.lane)).get_center()
  else: continue
  var pts = PackedVector2Array([p0])
  if a.get("flank",false):
   var edge = 6.0 if int(a.to_slot.lane) == 0 else size.x-6.0
   pts.append(Vector2(edge,p0.y))
   pts.append(Vector2(edge,p1.y))
  pts.append(p1)
  draw_polyline(pts,a.color,3.0)
  var dir = (pts[-1]-pts[-2]).normalized()
  var perp = Vector2(-dir.y,dir.x)
  draw_colored_polygon(PackedVector2Array([p1,p1-dir*12+perp*6,p1-dir*12-perp*6]),a.color)

func _gui_input(e):
 if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
  var slot = slot_at(e.position)
  if not slot.is_empty(): slot_clicked.emit(slot)

func slot_at(p: Vector2) -> Dictionary:
 var r = rows()
 var i = int(p.y/(size.y/r.size()))
 var lane = clampi(int(p.x/(size.x/lanes)),0,lanes-1)
 if i<0 or i>=r.size(): return {}
 if r[i][0] is int: return {"role":r[i][0],"lane":lane,"line":r[i][1]}
 var b = r[i][1]
 for role in 2:
  for line in ["front","back"]:
   if ((1 if line == "front" else 0) if role == 0 else (4 if line == "front" else 5)) == b: return {"role":role,"lane":lane,"line":line}
 return {}

# Unit under a point (for picking a Protect target on the board).
func unit_at(p: Vector2) -> String:
 var lay = _layout()
 for k in lay:
  if lay[k].has_point(p): return k
 return ""
