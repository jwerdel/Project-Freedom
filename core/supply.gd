extends RefCounted
# Army supply (war-and-realm §2.7; owner spec 2026-10-07, Part B; data/resources.json "supply"):
# one bar per army, 0-100, kept in army_state ("supply"). Full in friendly and allied land (refilling
# costs food from the faction's stockpile), draining in neutral and enemy land (faster in winter,
# core/seasons.gd); the raiding stance (army "march_stance" == "raid") forages in enemy land instead
# and plunders gold from the land's owner, at a cost in movement. Capturing a settlement fills it.
# Empty supply: attrition every turn. AI raiders (the "raider" trait) raid when at war.

const Movement = preload("res://core/movement.gd")
const WorldMap = preload("res://core/world_map.gd")

static func cfg() -> Dictionary:
 return load("res://core/resources.gd").data().supply

static func supply(state,army_id: String) -> float:
 var a = state.army_state[army_id]
 if not a.has("supply"): a.supply = float(cfg().max)
 return float(a.supply)

static func set_supply(state,army_id: String,v: float):
 state.army_state[army_id].supply = clampf(v,0.0,float(cfg().max))

static func raiding(state,army_id: String) -> bool:
 return str(state.army_state[army_id].get("march_stance","")) == "raid"

# The raiding stance on or off (the army panel, the AI).
static func set_raid(state,army_id: String,on: bool):
 state.army_state[army_id].march_stance = "raid" if on else ""

# Where an army stands for supply: "friendly", "neutral" or "enemy" (owner at war), and the land's owner.
static func land_of(state,army_id: String) -> Dictionary:
 var a = state.army_state[army_id]
 var p = Movement.position(state,army_id)
 var rg = WorldMap.region_at(p)
 var owner = str(state.settlements.get(rg,{}).get("owner",""))
 var D = load("res://core/diplomacy.gd")
 var Battles = load("res://core/battles.gd")
 if owner == "" : return {"kind":"neutral","owner":"","region":rg}
 if owner == a.faction or (state.get("diplomacy") != null and not state.diplomacy.is_empty() and D.friendly_land(state,a.faction,owner)): return {"kind":"friendly","owner":owner,"region":rg}
 if Battles.at_war(state,a.faction,owner): return {"kind":"enemy","owner":owner,"region":rg}
 return {"kind":"neutral","owner":owner,"region":rg}

# The change this army's supply would see at End Turn, and why: {delta, reason, food (cost)}.
static func outlook(state,army_id: String) -> Dictionary:
 var c = cfg()
 var Seasons = load("res://core/seasons.gd")
 var land = land_of(state,army_id)
 var now = supply(state,army_id)
 match land.kind:
  "friendly":
   var room = minf(float(c.refill),float(c.max)-now)
   var units = state.army_state[army_id].units.size()
   return {"delta":room,"reason":"Friendly land: refilling","food":int(ceil(room*float(c.refill_food)*maxf(1.0,float(units))/4.0))}
  "enemy":
   if raiding(state,army_id): return {"delta":float(c.forage),"reason":"Raiding: living off the land","food":0}
   return {"delta":-float(c.enemy)*Seasons.supply_factor(state),"reason":"Enemy land"+(" in winter" if Seasons.is_winter(state) else ""),"food":0}
 return {"delta":-float(c.neutral),"reason":"Foreign land","food":0}

# End Turn: every army's supply moves; raiders plunder; empty supply bleeds men. Returns events
# [{army, faction, kind: plunder|starving, gold, men}].
static func end_turn(state) -> Array:
 var out = []
 var c = cfg()
 var Res = load("res://core/resources.gd")
 var ids = state.army_state.keys()
 ids.sort()
 for id in ids:
  var a = state.army_state[id]
  if a.units.is_empty(): continue
  var o = outlook(state,id)
  var delta = float(o.delta)
  if delta>0.0 and int(o.food)>0:
   # A refill eats from the stockpile; without food the army only holds what it has.
   var have = Res.amount(state,a.faction,"food")
   if have<=0: delta = 0.0
   else:
    var pay = mini(int(o.food),have)
    delta *= float(pay)/float(o.food)
    Res.add(state,a.faction,"food",-pay)
  set_supply(state,id,supply(state,id)+delta)
  # Plunder: gold from the raided land's owner (never below zero).
  if raiding(state,id):
   var land = land_of(state,id)
   if land.kind == "enemy" and land.owner != "":
    var g = mini(int(c.raid_gold)*a.units.size(),maxi(0,int(state.treasury.get(land.owner,0))))
    if g>0:
     state.treasury[land.owner] = int(state.treasury[land.owner])-g
     state.treasury[a.faction] = int(state.treasury.get(a.faction,0))+g
     out.append({"army":id,"faction":a.faction,"kind":"plunder","gold":g,"victim":land.owner,"region":land.region})
  if supply(state,id)<=0.0:
   var lost = 0
   for u in a.units:
    var before = int(u.men)
    u.men = maxi(1,int(round(before*(1.0-float(c.attrition)))))
    lost += before-int(u.men)
   if lost>0: out.append({"army":id,"faction":a.faction,"kind":"starving","men":lost})
 return out

# Movement share for a raiding army (raiders crawl).
static func move_factor(state,army_id: String) -> float:
 return float(cfg().raid_move) if raiding(state,army_id) else 1.0

# A captured settlement feeds its captors.
static func on_capture(state,army_id: String):
 if state.army_state.has(army_id): set_supply(state,army_id,float(cfg().max))
