extends RefCounted
# The AI's court, diplomacy, vassal and banner layer (war-and-realm §11: strategic and vassal layers;
# docs/diplomacy-design.md §6 and §15). Every AI faction thinks every think_every turns (staggered),
# using the same functions and acceptance math as the player:
#  - court: marriages for unmarried adult heirs and children (within the court or with a friendly
#    house), governors for ungoverned settlements; careers and heirs are kept by core/court.gd;
#  - diplomacy: embassies, trade, alliances with friends against a common threat, peace when weary or
#    losing, vassalage (demanded from much weaker minors; offered to a strong friend under threat);
#    at most one proposal to the player per AI faction and max_proposals in all per turn;
#  - vassals: the overlord sets each vassal's economic goal (fortify on a hostile border, else
#    economy);
#  - banners: called when at war with a stronger enemy, dismissed after a few turns of peace.
# It never targets Caeloth and never betrays (core/diplomacy.gd refuses betrayal for the AI).

const WorldMap = preload("res://core/world_map.gd")
const Court = preload("res://core/court.gd")
const Diplomacy = preload("res://core/diplomacy.gd")
const Vassals = preload("res://core/vassals.gd")
const Hosts = preload("res://core/hosts.gd")
const Reputation = preload("res://core/reputation.gd")
const Battles = preload("res://core/battles.gd")

static func take_turns(state,factions: Array) -> Dictionary:
 var rep = {"actions":[],"proposals":0}
 var every = int(Diplomacy.data().ai.think_every)
 for f in factions:
  if f == state.player_faction or state.settlements_of(f).is_empty() or Diplomacy.untouchable(f) and false: continue
  if (int(state.turn)+abs(hash(f)))%every != 0: continue
  faction_turn(state,f,rep)
 return rep

static func faction_turn(state,f: String,rep: Dictionary):
 _court(state,f,rep)
 _diplomacy(state,f,rep)
 _vassal_goals(state,f)
 _banners(state,f,rep)

# --- Court ----------------------------------------------------------------------------------------

static func _court(state,f: String,rep: Dictionary):
 var members = Court.members(state,f)
 # Governors: every settlement without one gets an idle adult (politicians first).
 for sid in state.settlements_of(f):
  if Court.governor_of(state,sid) != "": continue
  var best = ""
  for id in members:
   var c = state.characters[id]
   if not Court.is_adult(c) or str(c.role) != "courtier" or str(c.army) != "": continue
   if best == "" or (c.career == "politician" and state.characters[best].career != "politician"): best = id
  if best != "":
   Court.appoint_governor(state,f,best,sid)
   rep.actions.append({"action":"governor","faction":f,"character":best,"settlement":sid})
 # Marriages: one unmarried adult of the family per think (at most two searches, each over every court).
 var tries = 0
 for id in members:
  var c = state.characters[id]
  if str(c.spouse) != "" or not Court.is_adult(c) or str(c.house) != str(WorldMap.faction(f).get("house","")) or c.legendary: continue
  if tries>=2: break
  tries += 1
  var match = _find_match(state,f,c)
  if match.is_empty(): continue
  var other = str(state.characters[match].faction)
  if other == f:
   Court.marry(state,id,match)
   rep.actions.append({"action":"marriage","faction":f,"a":id,"b":match})
  else:
   var offer = {"give":[{"kind":"marriage","a":id,"b":match}],"take":[]}
   if other == state.player_faction:
    _propose_player(state,f,offer,rep)
   else:
    var ev = Diplomacy.evaluate(state,f,other,offer)
    if ev.accept:
     Diplomacy.apply_offer(state,f,other,offer)
     rep.actions.append({"action":"marriage","faction":f,"a":id,"b":match,"with":other})
  break

static func _find_match(state,f: String,c: Dictionary) -> String:
 var best = ""
 var best_score = -INF
 for g in state.courts:
  if g != f and not Diplomacy.has_contact(state,f,g): continue
  if g != f and Battles.at_war(state,f,g): continue
  var att = 0.0 if g == f else Diplomacy.attitude(state,g,f)
  if g != f and att<0.0: continue
  for id in Court.members(state,g):
   var o = state.characters[id]
   if o.id == c.id or o.legendary or not Court.can_marry(state,c.id,id).ok: continue
   if g == f and str(o.house) == str(c.house): continue # not one's own blood
   var score = att+(15.0 if g != f else 0.0)+(10.0 if Court.ruler(state,g) == str(o.father) else 0.0)
   if score>best_score:
    best_score = score
    best = id
 return best

# --- Diplomacy -------------------------------------------------------------------------------------

static func _diplomacy(state,f: String,rep: Dictionary):
 var Ai = load("res://core/ai.gd")
 var enemies = Ai.at_war_with(state,f)
 var contacts = []
 for k in Diplomacy.d(state).contacts:
  var p = k.split("|")
  if f in p:
   var g = p[0] if p[1] == f else p[1]
   if state.treasury.has(g) and not state.settlements_of(g).is_empty(): contacts.append(g)
 contacts.sort()
 # Embassies: one envoy per think to a contact without one.
 for g in contacts:
  if not Diplomacy.has_embassy(state,f,g) and Diplomacy.embassy_refusal(state,f,g) == "":
   Diplomacy.send_envoy(state,f,g,"embassy")
   break
 # Peace with an enemy when weary or losing.
 for e in enemies:
  if Diplomacy.untouchable(e): continue
  var ai = Diplomacy.data().ai
  var meta = Diplomacy.d(state).war_meta.get(Diplomacy.key(f,e),{})
  if not meta.is_empty() and int(state.turn)-int(meta.turn)<int(ai.peace_min_turns): continue
  var ratio = Diplomacy._power(state,e)/Diplomacy._power(state,f)
  if Diplomacy.weariness(state,f)<float(ai.peace_weariness) and ratio<float(ai.peace_losing_ratio): continue
  var offer = {"give":[{"kind":"peace"}],"take":[]}
  if e == state.player_faction: _propose_player(state,f,offer,rep)
  elif Diplomacy.evaluate(state,f,e,offer).accept:
   Diplomacy.apply_offer(state,f,e,offer)
   rep.actions.append({"action":"peace","faction":f,"with":e})
  break
 for g in contacts:
  if Battles.at_war(state,f,g) or Diplomacy.untouchable(g): continue
  var att = Diplomacy.attitude(state,f,g)
  # Trade with anyone not hostile.
  if att>=0.0 and not Diplomacy.has_agreement(state,f,g,"trade") and Diplomacy.eligible(state,f,g,{"kind":"trade"}).ok:
   if _offer(state,f,g,{"give":[{"kind":"trade"}],"take":[]},rep,"trade"): break
  # Alliances with friends, especially against a common enemy.
  var common = enemies.any(func(e): return Battles.at_war(state,g,e))
  if (att>=25.0 or (common and att>=5.0)) and Diplomacy.eligible(state,f,g,{"kind":"alliance"}).ok:
   if _offer(state,f,g,{"give":[{"kind":"alliance"}],"take":[]},rep,"alliance"): break
 # Vassalage: a much stronger faction asks a weak minor neighbour to swear fealty.
 if Vassals.liege_of(state,f) == "":
  for g in contacts:
   if not Diplomacy.is_minor(g) or Vassals.liege_of(state,g) != "" or Battles.at_war(state,f,g): continue
   if Diplomacy._power(state,f)<Diplomacy._power(state,g)*float(Diplomacy.data().values.vassal_gap): continue
   if _offer(state,f,g,{"give":[],"take":[{"kind":"vassalage"}]},rep,"vassalize"): break
 # Under a stronger enemy: seek a protector among friends.
 if not enemies.is_empty() and Vassals.liege_of(state,f) == "" and Diplomacy.is_minor(f):
  var threat = 0.0
  for e in enemies: threat += Diplomacy._power(state,e)
  if threat>Diplomacy._power(state,f)*1.5:
   for g in contacts:
    if Diplomacy.attitude(state,f,g)<10.0 or Battles.at_war(state,f,g) or Diplomacy.is_minor(g): continue
    if _offer(state,f,g,{"give":[{"kind":"vassalage"}],"take":[]},rep,"seek_protection"): break

# Offer to an AI faction (applied when it accepts) or to the player (a proposal). Returns true if made.
static func _offer(state,f: String,g: String,offer: Dictionary,rep: Dictionary,kind: String) -> bool:
 for it in offer.get("give",[]):
  if not Diplomacy.eligible(state,f,g,it).ok: return false
 for it in offer.get("take",[]):
  if not Diplomacy.eligible(state,g,f,it).ok: return false
 # Only deals it values itself: the proposer's own view, seen from its side.
 var mirror = {"give":offer.get("take",[]),"take":offer.get("give",[])}
 if Diplomacy.evaluate(state,g,f,mirror).score<float(Diplomacy.data().ai.accept_margin)-300.0: return false
 if g == state.player_faction: return _propose_player(state,f,offer,rep)
 var ev = Diplomacy.evaluate(state,f,g,offer)
 if not ev.accept: return false
 Diplomacy.apply_offer(state,f,g,offer)
 rep.actions.append({"action":kind,"faction":f,"with":g})
 return true

static func _propose_player(state,f: String,offer: Dictionary,rep: Dictionary) -> bool:
 if int(rep.proposals)>=int(Diplomacy.data().ai.max_proposals): return false
 for p in Diplomacy.d(state).proposals:
  if p.from == f and int(p.turn) == int(state.turn): return false
 Diplomacy.d(state).proposals.append({"from":f,"to":state.player_faction,"offer":offer,"turn":int(state.turn)})
 rep.proposals = int(rep.proposals)+1
 return true

# --- Vassals and banners --------------------------------------------------------------------------

static func _vassal_goals(state,f: String):
 var Ai = load("res://core/ai.gd")
 for v in Vassals.vassals_of(state,f):
  var hostile = false
  for sid in state.settlements_of(v):
   for o in WorldMap.settlements_near(WorldMap.settlement_position(sid),900.0):
    var ow = str(state.settlements[o].owner)
    if ow != v and ow != f and Battles.at_war(state,f,ow): hostile = true
  Vassals.set_econ_goal(state,v,"fortify" if hostile else "economy")

static func _banners(state,f: String,rep: Dictionary):
 var Ai = load("res://core/ai.gd")
 var enemies = Ai.at_war_with(state,f)
 if Hosts.mustering(state,f):
  if enemies.is_empty(): Hosts.dismiss_levies(state,f)
  return
 if enemies.is_empty(): return
 var threat = 0.0
 for e in enemies: threat += Reputation.strength(state,e)
 if threat<Reputation.strength(state,f): return
 var cap = load("res://core/armies.gd").capital(state,f)
 if cap == "": return
 var r = Hosts.call_banners(state,f,cap)
 if r.ok: rep.actions.append({"action":"banners","faction":f,"levies":r.levies,"contingents":r.contingents})
