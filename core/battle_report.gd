extends RefCounted
# Battle report text (docs/battle-design.md section 6): scannable in under a minute. A headline, a
# 3-5 line "why you won / why you lost" ranked by impact (built from the simulation's cause tags),
# key numbers and a per-unit table. The timeline and 2D replay come in a later block.

const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const Chronicle = preload("res://core/chronicle.gd")

# Cause tag -> [line when it helped the reader's side, line when it helped the enemy, lesson for a loss].
const CAUSES = {
 "flank_rear":["Your flankers hit the enemy from behind; they had nothing in reserve to stop them.","Enemy flankers hit your rear: you had no reserve to meet them.","Keep at least one unit, ideally cavalry, in reserve to meet flank attacks."],
 "reserve_intercept":["Your reserve rode out and stopped the enemy's flank attack.","Their reserve met your flankers before they reached the rear.","Flank where the enemy has no reserve left, or draw it out first."],
 "screen":["A unit on your outer lane screened the enemy flank attack.","Your flankers were stopped by a unit screening their outer lane.","Flank on the side the enemy has left open."],
 "turned_to_face":["Your back line turned to face the flankers in time.","Their back line turned to face your flankers in time.","Disciplined troops and a good general turn to face; flank shaken units."],
 "brace":["Your braced spears blunted the enemy's cavalry charge.","Their braced spears blunted your cavalry charge.","Do not charge cavalry into braced spears; send it at archers or flanks."],
 "cavalry_on_missiles":["Your cavalry caught the enemy archers.","Enemy cavalry caught your archers.","Keep archers behind infantry, where cavalry cannot reach them."],
 "protected_missiles":["Your archers, safe behind your infantry, kept shooting.","Their archers, safe behind their infantry, kept shooting.","Protect your own archers behind infantry, and screen against theirs."],
 "missiles":["Your missile fire thinned the enemy before contact.","Enemy missile fire thinned your ranks before contact.","Close quickly or stay out of range of massed archers."],
 "chain_rout":["Once their line began to break, the rout spread down the line.","When one of your units broke, its neighbours lost heart.","Shore up a failing lane with a reserve before it breaks."],
 "pursuit":["Your pursuit cut down the fleeing enemy.","Their pursuit cut down your fleeing men.","Cavalry kept in reserve can ride down routers."],
 "walls":["Your walls held the attackers at the foot of the defences.","Their walls held your army at the foot of the defences.","Besiege first: every turn of siege weakens the walls."],
 "towers":["Your towers struck the attackers as they came.","Their towers struck your men as they came.","Siege the walls down before assaulting, to silence the towers."],
 "general_lost":["Their general fell or fled, and their army's courage went with him.","Your general fell or fled, and your army's courage went with him.","Keep the general behind the line, out of harm's way."],
 "reserve_plug":["Your reserve filled a broken lane.","Their reserve filled a lane you had broken.","Break more than one lane at once, or strip their reserve first."],
 "charge":["Your cavalry charge struck hard.","Their cavalry charge struck hard.","Brace spears against cavalry."],
}

# perspective: the faction reading the report (the player).
static func build(pb: Dictionary,result: Dictionary,after: Dictionary,perspective: String) -> Dictionary:
 var my_side = 0 if pb.attacker.faction == perspective else 1
 var won = result.winner == my_side
 var place = Chronicle._place(pb)
 var losses = [0,0]
 var start = [0,0]
 var destroyed = [0,0]
 for side in 2:
  for u in result.sides[side].units:
   losses[side] += int(u.losses)
   start[side] += int(u.men_start)
   if u.outcome == "destroyed": destroyed[side] += 1
 var headline = "%s at %s: %s men of yours lost, %s of theirs" % ["Victory" if won else "Defeat",place,Chronicle._num(losses[my_side]),Chronicle._num(losses[1-my_side])]
 if after.captured != "": headline += " · %s taken" % WorldMap.region(after.captured).settlement.name
 # Why: rank causes by impact; positive for the reader's side first when won, negative first when lost.
 var scored = []
 for k in result.causes:
  var tag = k.get_slice(":",0)
  var side = int(k.get_slice(":",1))
  if not CAUSES.has(tag): continue
  scored.append({"tag":tag,"ours":side == my_side,"impact":float(result.causes[k])})
 # Missile credit is counted once: the protected share replaces the general missile line.
 scored = scored.filter(func(c): return not (c.tag == "missiles" and _has(scored,"protected_missiles",c.ours)))
 scored.sort_custom(func(a,b): return _weight(a,won)>_weight(b,won))
 var why = []
 var lesson = ""
 for c in scored:
  if why.size()>=4: break
  if c.impact<5.0: continue
  why.append(CAUSES[c.tag][0 if c.ours else 1])
  if not won and not c.ours and lesson == "": lesson = CAUSES[c.tag][2]
 if why.is_empty(): why.append("Neither side gained a clear edge; the larger and steadier army prevailed." if result.outcome == "victory" else "The defenders held their ground until the day ended.")
 if not won and lesson != "": why.append("Lesson: "+lesson)
 var units = []
 for u in result.sides[my_side].units:
  units.append({"name":UnitTypes.get_type(u.unit).display_name,"men_start":int(u.men_start),"losses":int(u.losses),"kills":int(u.kills),"outcome":u.outcome})
 var numbers = {"your_losses":losses[my_side],"their_losses":losses[1-my_side],"your_men":start[my_side],"their_men":start[1-my_side],
  "your_destroyed":destroyed[my_side],"their_destroyed":destroyed[1-my_side],"ticks":int(result.ticks),"weather":result.weather}
 var generals = []
 for g in after.generals: generals.append("%s was %s." % [g.name,"killed" if g.fate == "killed" else "wounded"])
 for p in after.promoted: generals.append("%s was promoted to general." % p.name)
 return {"won":won,"headline":headline,"why":why.slice(0,5),"numbers":numbers,"units":units,"generals":generals,"place":place}

static func _has(list: Array,tag: String,ours: bool) -> bool:
 for c in list:
  if c.tag == tag and c.ours == ours: return true
 return false

# Victories list what went right first; defeats what went wrong first.
static func _weight(c: Dictionary,won: bool) -> float:
 var favoured = c.ours == won
 return c.impact*(2.0 if favoured else 1.0)
