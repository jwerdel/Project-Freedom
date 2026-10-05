extends RefCounted
# Lords as characters (placeholder until the character system, game-design §4 and build order 6):
# the general of each army in state.army_state[id].commander. Level is the general's rank (battle
# experience, data/battle.json "experience"); each level grants a skill point (data/skills.json).
# Spent skills live in commander.skills (ids, in the order taken) and the auto-allocate switch in
# commander.auto_skills, so saves carry them. Skills have NO gameplay effect yet; epithets, life
# traits, items and followers are stubs (game-design §4.4: epithets are earned from life, not
# chosen). AI generals always auto-allocate.

const BattleSim = preload("res://core/battle_sim.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const DATA = "res://data/skills.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func rows(career := "general") -> Array:
 return data().careers[career].rows

static func level(c: Dictionary) -> int:
 return maxi(1,int(c.get("rank",1)))

static func skill_points(c: Dictionary) -> int:
 return maxi(0,level(c)*int(data().points_per_level)-c.get("skills",[]).size())

# {ok, reason} for taking a skill now: one point free, the level reached, the skill before it in
# its row taken, not taken already.
static func can_take(c: Dictionary,skill_id: String) -> Dictionary:
 var taken = c.get("skills",[])
 if skill_id in taken: return {"ok":false,"reason":"Already learned"}
 for r in rows():
  for i in r.skills.size():
   var s = r.skills[i]
   if s.id != skill_id: continue
   if level(c)<int(s.level): return {"ok":false,"reason":"Needs level %d" % int(s.level)}
   if i>0 and not r.skills[i-1].id in taken: return {"ok":false,"reason":"Learn %s first" % r.skills[i-1].name}
   if skill_points(c)<=0: return {"ok":false,"reason":"No skill points"}
   return {"ok":true,"reason":""}
 return {"ok":false,"reason":"Unknown skill"}

static func take(state,army_id: String,skill_id: String) -> bool:
 var c = state.army_state[army_id].commander
 if not can_take(c,skill_id).ok: return false
 if not c.has("skills"): c.skills = []
 c.skills.append(skill_id)
 return true

# Spend every free point, filling the rows round robin in auto_order. Returns the skills taken.
static func auto_allocate(state,army_id: String) -> Array:
 var c = state.army_state[army_id].commander
 var out = []
 var progress = true
 while skill_points(c)>0 and progress:
  progress = false
  for row_id in data().auto_order:
   if skill_points(c)<=0: break
   for r in rows():
    if r.id != row_id: continue
    for s in r.skills:
     if can_take(c,s.id).ok:
      take(state,army_id,s.id)
      out.append(s.id)
      progress = true
      break
 return out

static func set_auto(state,army_id: String,on: bool):
 state.army_state[army_id].commander.auto_skills = on
 if on: auto_allocate(state,army_id)

static func auto_on(state,army_id: String) -> bool:
 var a = state.army_state[army_id]
 return a.faction != state.player_faction or bool(a.commander.get("auto_skills",false))

# Every general with auto-allocation on (all AI generals) spends its points (End Turn).
static func auto_allocate_all(state):
 for id in state.army_state:
  if auto_on(state,id): auto_allocate(state,id)

# Experience toward the next level: {xp, from, to} (to = -1 at the last placeholder threshold).
static func xp_progress(c: Dictionary) -> Dictionary:
 var t = BattleSim.data().experience.general_rank_thresholds
 var lv = level(c)
 var from = float(t[mini(lv,t.size()-1)])
 var to = float(t[lv+1]) if lv+1<t.size() else -1.0
 return {"xp":float(c.get("xp",0.0)),"from":from,"to":to}

# The general's battle stats (data/units/commander.json "battle"), raised by rank as units are
# (data/battle.json experience rank bonuses).
static func stats(c: Dictionary) -> Array:
 var b = UnitTypes.get_type("commander").battle
 var xp = BattleSim.data().experience
 var r = level(c)-1
 return [["Leadership",int(b.morale)+r*int(xp.rank_morale),"Morale of the general and the aura he lends his army."],
  ["Melee attack",int(b.melee_attack)+r*int(xp.rank_attack),"How often the general lands blows in melee."],
  ["Melee defence",int(b.melee_defence)+r*int(xp.rank_defence),"How well the general parries in melee."],
  ["Charge bonus",int(b.charge),"Extra attack on the charge."],
  ["Armour",int(b.armour),"Blocks part of every blow that is not armour-piercing."],
  ["Hit points",int(b.hp),"How much punishment the general takes before falling."],
  ["Speed",snappedf(float(b.speed),0.1),"Battle speed in bands per tick."]]

# Traits: the faction's default general traits (until life traits exist) and the general's state.
static func traits(state,army_id: String) -> Array:
 var a = state.army_state[army_id]
 var out = []
 for t in WorldMap.faction(a.faction).get("general_traits",[]):
  out.append({"id":t,"name":str(t).capitalize(),"text":"A house trait of %s's generals (placeholder until life traits)." % WorldMap.faction(a.faction).name})
 match str(a.commander.get("status","ok")):
  "wounded": out.append({"id":"wounded","name":"Wounded","text":"Recovering from battle wounds; a captain leads the army."})
  "captain": out.append({"id":"captain","name":"Acting captain","text":"Leads after the general fell; cannot move the army until a new general is appointed."})
 return out
