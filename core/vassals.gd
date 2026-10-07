extends RefCounted
# Vassals (war-and-realm §4; docs/diplomacy-design.md §9; data/vassals.json). Fealty, not
# absorption: a vassal keeps its own faction, family, lands, armies and banners and serves its
# overlord: tribute, troops on request, war calls, orders carried out with real force, its economy
# run toward the goal the overlord sets. Routes: war and surrender, diplomacy, debt, marriage,
# protection from a bigger threat (all through swear()). Loyalty rises and falls with visible
# reasons; a well-treated vassal never rebels; a neglected one at rock bottom shows multi-turn
# warnings (the breakaway itself is deferred to the realm-mechanics part: hook only). No vassal may
# exceed cap_share of its overlord's strength; the vassal AI stops expanding at the cap.
# State: state.vassals[vassal] = {liege, since, route, loyalty, log [{turn, delta, reason}], econ_goal,
#  goal {kind, target, text, since}, warning (turns left, -1 none), last_favour, calls_unanswered}
# state.tributes: [{from, to, amount, until}]

const WorldMap = preload("res://core/world_map.gd")
const Economy = preload("res://core/economy.gd")
const Reputation = preload("res://core/reputation.gd")
const DATA = "res://data/vassals.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func _v(state) -> Dictionary:
 if state.get("vassals") == null: state.vassals = {}
 return state.vassals

static func liege_of(state,f: String) -> String:
 if state.get("vassals") == null: return ""
 return str(state.vassals.get(f,{}).get("liege",""))

static func vassals_of(state,liege: String) -> Array:
 var out = []
 for f in _v(state):
  if str(state.vassals[f].liege) == liege and not state.settlements_of(f).is_empty(): out.append(f)
 out.sort()
 return out

static func loyalty(state,f: String) -> int:
 return int(_v(state).get(f,{}).get("loyalty",0))

# How reliably obligations are met: 1 at reliable_at loyalty or more, loyalty / reliable_at below.
static func reliability(state,f: String) -> float:
 return clampf(float(loyalty(state,f))/float(data().reliable_at),0.0,1.0)

# The cap: `vassal` may not exceed cap_share of `liege`'s strength. {ok, reason, share}.
static func cap_check(state,liege: String,vassal: String) -> Dictionary:
 var s = Reputation.strength(state,vassal)
 var o = maxf(1.0,Reputation.strength(state,liege))
 var share = s/o
 if share>float(data().cap_share): return {"ok":false,"reason":"Too strong to be a vassal (%d%% of your strength, cap %d%%)" % [int(share*100),int(float(data().cap_share)*100)],"share":share}
 return {"ok":true,"reason":"","share":share}

static func at_cap(state,vassal: String) -> bool:
 var l = liege_of(state,vassal)
 return l != "" and Reputation.strength(state,vassal)>=float(data().cap_share)*Reputation.strength(state,l)

# The vassal swears fealty to the liege (any route).
static func swear(state,vassal: String,liege: String,route := "diplomacy"):
 var D = load("res://core/diplomacy.gd")
 var B = load("res://core/battles.gd")
 B_end(state,vassal,liege)
 # A vassal follows its liege's diplomatic lead: it leaves its own wars against the liege's friends.
 for k in state.wars.duplicate():
  var parts = k.split("|")
  if not vassal in parts: continue
  var other = parts[0] if parts[1] == vassal else parts[1]
  if D.allied(state,liege,other): state.wars.erase(k)
 _v(state)[vassal] = {"liege":liege,"since":int(state.turn),"route":route,"loyalty":int(data().start_loyalty.get(route,50)),"log":[{"turn":int(state.turn),"delta":0,"reason":"Swore fealty (%s)" % route}],
  "econ_goal":"balanced","goal":_new_goal(state,vassal,liege),"warning":-1,"last_favour":int(state.turn),"calls_unanswered":0}
 D.add_attitude(state,vassal,liege,"vassal_of")
 D.make_contact(state,vassal,liege)
 var C = load("res://core/court.gd")
 for id in C.members(state,vassal): C.history(state,state.characters[id],"Their house swore fealty to %s." % WorldMap.faction(liege).name)
 D._log(state,"%s swears fealty to %s." % [WorldMap.faction(vassal).name,WorldMap.faction(liege).name])

static func B_end(state,a: String,b: String):
 state.wars.erase(load("res://core/battles.gd").war_key(a,b))

# The overlord releases a vassal (free, an act of honour).
static func release(state,vassal: String):
 _v(state).erase(vassal)

# favour: the overlord did something for them (gifts, goals, titles); time and shared wars do not count
# against neglect.
static func change(state,f: String,delta: int,reason: String,favour := true):
 var e = _v(state).get(f)
 if e == null or delta == 0: return
 e.loyalty = clampi(int(e.loyalty)+delta,0,100)
 e.log.append({"turn":int(state.turn),"delta":delta,"reason":reason})
 while e.log.size()>24: e.log.pop_front()
 if delta>0 and favour: e.last_favour = int(state.turn)

static func set_econ_goal(state,f: String,goal: String) -> bool:
 if not data().econ_goals.has(goal) or not _v(state).has(f): return false
 _v(state)[f].econ_goal = goal
 return true

# The vassal AI's construction weights (core/ai.gd _build).
static func build_weights(state,f: String):
 var e = _v(state).get(f)
 if e == null: return null
 return data().econ_goals[str(e.econ_goal)].weights

static func gift(state,liege: String,vassal: String,gold: int) -> Dictionary:
 if int(state.treasury.get(liege,0))<gold or gold<=0: return {"ok":false,"reason":"Not enough gold"}
 state.treasury[liege] = int(state.treasury[liege])-gold
 state.treasury[vassal] = int(state.treasury[vassal])+gold
 change(state,vassal,int(round(float(gold)/float(data().gains.gift_gold)*float(data().gains.gift))),"A gift of %d gold" % gold)
 return {"ok":true}

# --- Personal goals (war-and-realm §4.3) ------------------------------------------------------------

static func _new_goal(state,vassal: String,liege: String) -> Dictionary:
 var r = RandomNumberGenerator.new()
 r.seed = hash([state.seed,"goal",vassal,int(state.turn)])
 var kinds = ["land","marriage","revenge","title"]
 var kind = kinds[r.randi_range(0,kinds.size()-1)]
 match kind:
  "land":
   # The nearest region of a faction outside the liege's realm.
   var best = ""
   var bd = INF
   for sid in state.settlements_of(vassal):
    for o in WorldMap.settlements_near(WorldMap.settlement_position(sid),2500.0):
     var ow = str(state.settlements[o].owner)
     if ow in [vassal,liege,""] or liege_of(state,ow) == liege or bool(WorldMap.faction(ow).get("untouchable",false)): continue
     var dd = WorldMap.settlement_position(sid).distance_to(WorldMap.settlement_position(o))
     if dd<bd:
      bd = dd
      best = o
   if best != "": return {"kind":"land","target":best,"text":"wants %s" % WorldMap.region(best).settlement.name,"since":int(state.turn)}
  "revenge":
   for g in WorldMap.faction(vassal).get("relations",{}):
    if str(WorldMap.faction(vassal).relations[g]) == "rival" and state.treasury.has(g) and not state.settlements_of(g).is_empty() and g != liege:
     return {"kind":"revenge","target":g,"text":"wants revenge on %s" % WorldMap.faction(g).name,"since":int(state.turn)}
  "title":
   return {"kind":"title","target":"","text":"wants a title of your realm","since":int(state.turn)}
 return {"kind":"marriage","target":"","text":"wants a marriage into your family","since":int(state.turn)}

# Is the goal met? (land taken by the vassal, a marriage between the houses, a title granted, the
# rival at war with the liege or fallen).
static func goal_met(state,vassal: String) -> bool:
 var e = _v(state).get(vassal,{})
 var g = e.get("goal",{})
 var liege = str(e.get("liege",""))
 match str(g.get("kind","")):
  "land": return str(state.settlements.get(g.target,{}).get("owner","")) == vassal
  "revenge": return load("res://core/battles.gd").at_war(state,liege,g.target) or state.settlements_of(g.target).is_empty()
  "title":
   var T = load("res://core/titles.gd")
   return not T.held_by(state,vassal).is_empty()
  "marriage":
   var C = load("res://core/court.gd")
   for id in C.members(state,vassal):
    var sp = C.get_char(state,state.characters[id].spouse)
    if not sp.is_empty() and sp.get("faction","") == liege: return true
   for id in C.members(state,liege):
    var sp = C.get_char(state,state.characters[id].spouse)
    if not sp.is_empty() and str(sp.get("house","")) == str(WorldMap.faction(vassal).get("house","?")): return true
 return false

# --- Tribute --------------------------------------------------------------------------------------

static func add_tribute(state,from: String,to: String,amount: int,turns: int):
 if state.get("tributes") == null: state.tributes = []
 state.tributes.append({"from":from,"to":to,"amount":amount,"until":int(state.turn)+turns})

static func tribute_due(state,vassal: String) -> int:
 return int(round(float(Economy.faction_ledger(state,vassal).income_total)*float(data().tribute_share)))

# --- Yearly processing --------------------------------------------------------------------------

# Tribute, loyalty (time, neglect, shared enemies, goals), warnings and the cap. Returns events
# [{vassal, liege, kind, text}].
static func end_turn(state) -> Array:
 var out = []
 var B = load("res://core/battles.gd")
 var g = data().gains
 var l = data().losses
 for f in _v(state).keys():
  var e = state.vassals[f]
  var liege = str(e.liege)
  if state.settlements_of(f).is_empty() or state.settlements_of(liege).is_empty():
   state.vassals.erase(f)
   continue
  # Tribute (paused while the vassal is in debt: diplomacy-design §18.9).
  var due = tribute_due(state,f)
  if int(state.treasury[f])>=due and due>0:
   if randf_for(state,f,"tribute")<reliability(state,f):
    state.treasury[f] = int(state.treasury[f])-due
    state.treasury[liege] = int(state.treasury[liege])+due
  # Time and shared enemies.
  if int(e.loyalty)<int(g.time_to): change(state,f,int(g.time),"Years of loyal service",false)
  var Ai = load("res://core/ai.gd")
  for enemy in Ai.at_war_with(state,f):
   if B.at_war(state,liege,enemy):
    change(state,f,int(g.shared_enemy),"Fighting %s together" % WorldMap.faction(enemy).name,false)
    break
  # Goals: met earns loyalty and the overlord's cut; long ignored is neglect.
  if goal_met(state,f):
   change(state,f,int(g.goal_helped),"You helped them: %s" % str(e.goal.text))
   var cut = mini(int(data().goals.cut_gold),maxi(0,int(state.treasury[f])))
   state.treasury[f] = int(state.treasury[f])-cut
   state.treasury[liege] = int(state.treasury[liege])+cut
   out.append({"vassal":f,"liege":liege,"kind":"goal_met","text":"%s's goal is met; they send you %d gold." % [WorldMap.faction(f).name,cut]})
   e.goal = _new_goal(state,f,liege)
  elif int(state.turn)-int(e.goal.get("since",state.turn))>int(l.neglect_after) and int(state.turn)-int(e.last_favour)>int(l.neglect_after):
   change(state,f,-int(l.neglect),"Neglected: you ignore that %s %s" % [WorldMap.faction(f).name,str(e.goal.text)])
  # Rock bottom: multi-turn warnings (the breakaway is deferred to the realm-mechanics part: hook).
  if int(e.loyalty)<int(data().warn_below):
   if int(e.warning)<0: e.warning = int(data().warning_turns)
   else: e.warning = maxi(0,int(e.warning)-1)
   out.append({"vassal":f,"liege":liege,"kind":"warning","text":"%s wavers (loyalty %d): %d turns of warning" % [WorldMap.faction(f).name,int(e.loyalty),int(e.warning)]})
   # HOOK: breakaway (realm-mechanics part) when warning reaches 0.
  else: e.warning = -1
  # A vassal follows its liege into war (reliability by loyalty).
  for enemy in Ai.at_war_with(state,liege):
   if B.at_war(state,f,enemy) or enemy == f or liege_of(state,enemy) == liege: continue
   if load("res://core/diplomacy.gd").would_betray(state,f,enemy) != "": continue
   if randf_for(state,f,["call",enemy])<reliability(state,f): B.declare_war(state,f,enemy)
 # Ended tributes; tributes paid.
 if state.get("tributes") != null:
  for t in state.tributes:
   if state.treasury.has(t.from) and int(state.treasury[t.from])>=int(t.amount):
    state.treasury[t.from] = int(state.treasury[t.from])-int(t.amount)
    state.treasury[t.to] = int(state.treasury[t.to])+int(t.amount)
  state.tributes = state.tributes.filter(func(t): return int(t.until)>int(state.turn))
 return out

static func randf_for(state,f: String,tag) -> float:
 var r = RandomNumberGenerator.new()
 r.seed = hash([state.seed,state.turn,f,tag])
 return r.randf()

# Everything the Vassals screen shows for one vassal.
static func summary(state,f: String) -> Dictionary:
 var e = _v(state).get(f,{})
 if e.is_empty(): return {}
 var log = e.log.duplicate()
 log.reverse()
 return {"faction":f,"liege":e.liege,"loyalty":int(e.loyalty),"reasons":log,"econ_goal":str(e.econ_goal),"goal":e.goal,"warning":int(e.warning),
  "tribute":tribute_due(state,f),"reliability":reliability(state,f),"cap":cap_check(state,str(e.liege),f),"since":int(e.since),"route":str(e.route)}
