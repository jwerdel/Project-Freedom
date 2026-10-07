extends Control
# Placeholder character portrait (game-design §4; docs/v1-content.md §7.1 art comes later): a simple
# procedural bust in the character's culture colours on a faction-tinted backdrop, sized by age stage
# (child, youth, adult), with hair or beard by gender and a small career mark. No generated art.

const CULTURE_CLOTH = {"medieval":Color("4a5d78"),"roman":Color("8a2f2a"),"greek":Color("e8e2d0"),"dwarf":Color("7a5a3a"),"orc":Color("5a4a2a"),"dark_elf":Color("3a2a4a"),"ratmen":Color("5a4a3a"),"elf":Color("d8e4ec"),"desert":Color("d8b878"),"beastmen":Color("5a3a2a"),"lizardmen":Color("3a6a4a")}
const SKIN = {"orc":Color("6f8a4a"),"dark_elf":Color("c8c0d8"),"ratmen":Color("8a7a6a"),"dwarf":Color("d8a882"),"lizardmen":Color("6aa07a"),"beastmen":Color("8a6a4a"),"elf":Color("f0dcc8")}
const CAREER_MARK = {"general":"sword","warlord":"axe","assassin":"eye","spy":"key","politician":"horn","merchant":"anvil","wizard":"star","priest":"sun"}

var c: Dictionary
var backdrop := Color("2a2018")

func _init(character: Dictionary,size_px := 72.0,faction_color := Color("2a2018")):
 c = character
 backdrop = faction_color
 custom_minimum_size = Vector2(size_px,size_px)
 mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw():
 var s = size
 draw_rect(Rect2(Vector2.ZERO,s),backdrop.darkened(0.55))
 draw_rect(Rect2(Vector2(0,s.y*0.55),Vector2(s.x,s.y*0.45)),backdrop.darkened(0.35))
 var age = float(c.get("age",30))
 var k = 0.62 if age<12.0 else (0.82 if age<16.0 else 1.0)
 var cx = s.x*0.5
 var cloth: Color = CULTURE_CLOTH.get(str(c.get("culture","medieval")),Color("5a5a5a"))
 var skin: Color = SKIN.get(str(c.get("race","medieval")),Color("e8c4a0"))
 # Shoulders.
 var sw = s.x*0.42*k
 var top = s.y*(0.68-0.06*k)
 draw_colored_polygon(PackedVector2Array([Vector2(cx-sw,s.y),Vector2(cx-sw*0.86,top+s.y*0.08),Vector2(cx-sw*0.3,top),Vector2(cx+sw*0.3,top),Vector2(cx+sw*0.86,top+s.y*0.08),Vector2(cx+sw,s.y)]),cloth)
 if bool(c.get("immortal",false)): draw_arc(Vector2(cx,top+s.y*0.05),sw*0.55,PI*0.15,PI*0.85,12,Color("f2cf6a"),2.0)
 # Neck and head.
 var hr = s.x*0.17*k
 var hc = Vector2(cx,top-hr*0.9)
 draw_rect(Rect2(Vector2(cx-hr*0.35,hc.y+hr*0.6),Vector2(hr*0.7,hr*0.7)),skin.darkened(0.12))
 draw_circle(hc,hr,skin)
 # Hair (and a beard for adult men), by gender.
 var hair = Color("3a2a1a") if hash(str(c.get("id",""))) % 3 != 0 else Color("8a6a3a")
 if str(c.get("race","")) in ["orc","lizardmen"]: hair = Color(0,0,0,0)
 if hair.a>0.0:
  draw_arc(hc,hr*0.98,PI*1.05,TAU-0.05,16,hair,hr*0.45)
  if str(c.get("gender","m")) == "f": draw_rect(Rect2(Vector2(hc.x-hr*1.05,hc.y-hr*0.2),Vector2(hr*0.35,hr*1.6)),hair)
  if str(c.get("gender","m")) == "f": draw_rect(Rect2(Vector2(hc.x+hr*0.7,hc.y-hr*0.2),Vector2(hr*0.35,hr*1.6)),hair)
  elif age>=18.0: draw_arc(hc+Vector2(0,hr*0.15),hr*0.8,0.3,PI-0.3,12,hair,hr*0.35)
 for x in [-0.35,0.35]: draw_circle(hc+Vector2(x*hr,-0.05*hr),hr*0.09,Color(0.1,0.07,0.05))
 # Career mark in the corner.
 var Icons = load("res://ui/icons.gd")
 var mark = CAREER_MARK.get(str(c.get("career","")),"")
 if mark != "": Icons.draw(self,mark,Rect2(Vector2(s.x*0.72,s.y*0.72),Vector2(s.x*0.24,s.y*0.24)),Color("f2cf6a"))
 draw_rect(Rect2(Vector2.ZERO,s),Color("8a6a3a"),false,1.5)
 if bool(c.get("dead",false)):
  draw_rect(Rect2(Vector2.ZERO,s),Color(0,0,0,0.55))
  draw_line(Vector2(4,4),s-Vector2(4,4),Color("c0392b"),2.0)
