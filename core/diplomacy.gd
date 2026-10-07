extends RefCounted
# Diplomacy (docs/diplomacy-design.md, approved; war-and-realm §0.2 overrides; data/diplomacy.json).
#  - Treaties between two factions: ceasefire, peace, alliance; agreements on top: trade, defensive
#    pact, non-aggression, military access (one way), embassies (one way). A treaty cannot be
#    cancelled during its first protection_turns (20); attacking a treaty partner is betrayal.
#  - Envoys reach anyone (war-and-realm §0.2): they travel by map distance and contact happens on
#    arrival; an embassy, once accepted, reveals the court.
#  - Bundled offers: items offered and demanded, valued by the receiver in gold equivalents with
#    reasons and numbers (evaluate); the AI accepts at score >= 0 and uses the same math.
#  - War declarations need a justification (grudge, claim, provocation, defending an ally) or cost
#    reputation; allies are called and join, support or refuse.
#  - Betrayal (V1 rule, kept; FLAGGED as the future Chaos trigger, war-and-realm §6.3): attacking a
#    treaty partner means war with every faction and the loss of every ally and trade partner. The AI
#    never betrays.
#  - Commandable allies and vassals: orders with willingness; accepted orders commit a real force.
#  - Trade continues during war with tariffs; movement in allied land (or with access) is fast.
# State: state.diplomacy = {treaties: {"a|b": {kind, since}}, agreements: {"a|b": {name: since}},
#  attitude: {"x>y": [{e, v, turn}]}, envoys: [{from, to, kind, arrive, offer}], contacts: {"a|b": turn},
#  betrayers: [], weariness: {f: v}, war_meta: {"a|b": {by, turn, justified, why}}, orders: [...],
#  proposals: [{from, to, offer, turn}], protects: {minor: protector}, log: [...]}

const WorldMap = preload("res://core/world_map.gd")
const Battles = preload("res://core/battles.gd")
const Economy = preload("res://core/economy.gd")
const Reputation = preload("res://core/reputation.gd")
const DATA = "res://data/diplomacy.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func key(a: String,b: String) -> String:
 return a+"|"+b if a<b else b+"|"+a

static func init(state):
 state.diplomacy = {"treaties":{},"agreements":{},"attitude":{},"envoys":[],"contacts":{},"betrayers":[],"weariness":{},"war_meta":{},"orders":[],"proposals":[],"protects":{},"log":[],"replies":[],"next_reply":0}
 # Lore friendships and rivalries (docs/v1-content.md §3.2) are remembered from the start.
 for f in state.factions():
  for g in WorldMap.faction(f).get("relations",{}):
   if not state.treasury.has(g): continue
   add_attitude(state,f,g,"lore_friend" if str(WorldMap.faction(f).relations[g]) == "friend" else "lore_rival")
 # Neighbours have met (shared borders and sight, diplomacy-design §4).
 var UiData = load("res://core/ui_data.gd")
 var radius = UiData.met_radius()
 for f in state.factions():
  for sid in state.settlements_of(f):
   for o in WorldMap.settlements_near(WorldMap.settlement_position(sid),radius):
    var g = str(state.settlements[o].owner)
    if g != "" and g != f: state.diplomacy.contacts[key(f,g)] = 0

static func d(state) -> Dictionary:
 if state.get("diplomacy") == null or state.diplomacy.is_empty(): init(state)
 if not state.diplomacy.has("replies"): # saves from before replies (2026-10-07)
  state.diplomacy.replies = []
  state.diplomacy.next_reply = 0
 return state.diplomacy

# Every answer the human player receives (owner spec 2026-10-07: every proposal and envoy gives a
# result): {id, from (the answering faction), kind (offer, embassy, contact), ok, reason, offer, turn,
# seen}. The interface shows each once (a reply pop-up with the leader's portrait) and keeps the last few.
# Why an offer was declined: its weightiest objection (the most negative reason), else the balance.
static func decline_reason(ev: Dictionary) -> String:
 if bool(ev.get("blocked",false)) and not ev.reasons.is_empty(): return str(ev.reasons[0].text)
 var worst = null
 for r in ev.get("reasons",[]):
  if float(r.value)<0.0 and (worst == null or float(r.value)<float(worst.value)): worst = r
 return str(worst.text) if worst != null else "The deal is not worth enough to them"

static func add_reply(state,from: String,kind: String,ok: bool,reason: String,offer := {}) -> Dictionary:
 var r = {"id":int(d(state).next_reply),"from":from,"kind":kind,"ok":ok,"reason":reason,"offer":offer.duplicate(true),"turn":int(state.turn),"seen":false}
 d(state).next_reply = int(d(state).next_reply)+1
 d(state).replies.append(r)
 while d(state).replies.size()>30: d(state).replies.pop_front()
 return r

# --- Peoples ------------------------------------------------------------------------------------

static func culture(f: String) -> String:
 return str(WorldMap.faction(f).get("culture",""))

static func bloc(f: String) -> String:
 var c = culture(f)
 for b in ["order","destruction","neutral"]:
  if c in data().blocs[b]: return b
 return "order"

static func prejudice(a: String,b: String) -> int:
 var ca = culture(a)
 var cb = culture(b)
 for f in data().prejudice.friendly:
  if f == a or f == b: return 0
 for p in data().prejudice.pairs:
  if (p[0] == ca and p[1] == cb) or (p[1] == ca and p[0] == cb): return int(p[2])
 return 0

static func is_minor(f: String) -> bool:
 return str(WorldMap.faction(f).get("kind","")) in ["minor","generated"]

static func untouchable(f: String) -> bool:
 return bool(WorldMap.faction(f).get("untouchable",false))

# --- Attitude (how x feels about y) ---------------------------------------------------------------

static func add_attitude(state,x: String,y: String,event: String,scale := 1.0):
 if x == y or x == "" or y == "": return
 var ev = data().attitude.events.get(event)
 if ev == null: return
 var k = x+">"+y
 var list = d(state).attitude.get_or_add(k,[])
 # Repeatable events stack up to a cap (trespass, gifts); others refresh.
 if event in ["trespass","gift"]:
  var have = 0.0
  for e in list:
   if e.e == event: have += float(e.v)
  if absf(have)>=20.0: return
  list.append({"e":event,"v":float(ev[0])*scale,"turn":int(state.turn)})
  return
 for e in list:
  if e.e == event:
   e.v = float(ev[0])*scale
   e.turn = int(state.turn)
   return
 list.append({"e":event,"v":float(ev[0])*scale,"turn":int(state.turn)})

static func attitude(state,x: String,y: String) -> float:
 var t = 0.0
 for e in d(state).attitude.get(x+">"+y,[]): t += float(e.v)
 t += prejudice(x,y)
 if y in d(state).betrayers: t -= 100.0
 return clampf(t,-100.0,100.0)

# The biggest causes of x's attitude toward y, as short phrases: [{text, value}].
static func attitude_reasons(state,x: String,y: String) -> Array:
 var names = {"attacked_us":"You attacked us","attacked_ally":"You attacked our ally","unprovoked_ally":"Unprovoked war on our ally","alliance":"Our alliance","marriage":"Marriage between our houses","trade":"Our trade","embassy":"Our embassies","common_enemy":"A common enemy","gift":"Your gifts","released_captive":"You released our kin","trespass":"Your armies trespass","broke_trade":"You broke trade","refused_call":"You refused our call","answered_call":"You answered our call","abandoned":"You abandoned us","betrayer":"Betrayer","liked_victim":"You attacked a friend of ours","vassal_of":"Sworn to you","lore_friend":"Old friendship","lore_rival":"Old rivalry","peace":"Peace between us","tribute_paused":"Unpaid tribute"}
 var out = []
 for e in d(state).attitude.get(x+">"+y,[]):
  var fading = data().attitude.events.get(e.e,[0,0])[1] != 0 and int(state.turn)-int(e.turn)>3
  out.append({"text":names.get(e.e,e.e)+(", fading" if fading else ""),"value":float(e.v)})
 var p = prejudice(x,y)
 if p != 0: out.append({"text":"Hatred between our peoples","value":float(p)})
 if y in d(state).betrayers: out.append({"text":"You betrayed your allies","value":-100.0})
 out.sort_custom(func(a,b): return absf(a.value)>absf(b.value))
 return out.slice(0,5)

static func face(v: float) -> int:
 var f = data().attitude.faces
 var i = 0
 for t in f:
  if v>float(t): i += 1
 return i # 0 hostile .. 4 very friendly

static func decay(state):
 for k in d(state).attitude:
  var list = d(state).attitude[k]
  for e in list:
   var rate = float(data().attitude.events.get(e.e,[0,0])[1])
   if rate>0.0: e.v = move_toward(float(e.v),0.0,rate)
  d(state).attitude[k] = list.filter(func(e): return absf(float(e.v))>0.01 or float(data().attitude.events.get(e.e,[0,0])[1]) == 0.0)

# --- Treaties and agreements ---------------------------------------------------------------------

static func treaty(state,a: String,b: String) -> Dictionary:
 return d(state).treaties.get(key(a,b),{})

static func has_agreement(state,a: String,b: String,name: String) -> bool:
 return d(state).agreements.get(key(a,b),{}).has(name)

static func allied(state,a: String,b: String) -> bool:
 return str(treaty(state,a,b).get("kind","")) == "alliance"

static func at_peace_treaty(state,a: String,b: String) -> bool:
 return str(treaty(state,a,b).get("kind","")) in ["peace","ceasefire","alliance"]

static func protected_turns_left(state,a: String,b: String) -> int:
 var t = treaty(state,a,b)
 var since = int(t.get("since",-1000))
 for n in d(state).agreements.get(key(a,b),{}):
  since = maxi(since,int(d(state).agreements[key(a,b)][n]))
 return maxi(0,int(data().protection_turns)-(int(state.turn)-since))

static func sign_treaty(state,a: String,b: String,kind: String):
 var k = key(a,b)
 match kind:
  "ceasefire","peace":
   end_war(state,a,b)
   d(state).treaties[k] = {"kind":kind,"since":int(state.turn)}
   add_attitude(state,a,b,"peace")
   add_attitude(state,b,a,"peace")
   Reputation.deed(state,a,"peace","Made peace with %s" % WorldMap.faction(b).name,0.5)
   Reputation.deed(state,b,"peace","Made peace with %s" % WorldMap.faction(a).name,0.5)
  "alliance":
   d(state).treaties[k] = {"kind":"alliance","since":int(state.turn)}
   add_attitude(state,a,b,"alliance")
   add_attitude(state,b,a,"alliance")
   Reputation.deed(state,a,"alliance","Allied with %s" % WorldMap.faction(b).name)
   Reputation.deed(state,b,"alliance","Allied with %s" % WorldMap.faction(a).name)
  "trade","defensive","nap":
   d(state).agreements.get_or_add(k,{})[kind] = int(state.turn)
   if kind == "trade":
    add_attitude(state,a,b,"trade")
    add_attitude(state,b,a,"trade")
 _log(state,"%s and %s sign %s." % [WorldMap.faction(a).name,WorldMap.faction(b).name,{"ceasefire":"a ceasefire","peace":"peace","alliance":"an alliance","trade":"a trade agreement","defensive":"a defensive pact","nap":"a non-aggression pact"}.get(kind,kind)])

# a grants b military access to a's land (one way).
static func grant_access(state,a: String,b: String):
 d(state).agreements.get_or_add(key(a,b),{})["access:"+b] = int(state.turn)

static func has_access(state,mover: String,land_owner: String) -> bool:
 return d(state).agreements.get(key(mover,land_owner),{}).has("access:"+mover)

# a opens an embassy in b (reveals b's court to a).
static func open_embassy(state,a: String,b: String):
 d(state).agreements.get_or_add(key(a,b),{})["embassy:"+a] = int(state.turn)
 add_attitude(state,b,a,"embassy")
 make_contact(state,a,b)

static func has_embassy(state,a: String,b: String) -> bool:
 return d(state).agreements.get(key(a,b),{}).has("embassy:"+a)

# Cancel a treaty or an agreement. Treaties (and the pacts) cannot be cancelled while protected;
# trade, access and embassies can be at any time (trade costs -10 with the partner).
static func cancel(state,a: String,b: String,name: String) -> Dictionary:
 var k = key(a,b)
 if name in ["peace","ceasefire","alliance"]:
  if str(treaty(state,a,b).get("kind","")) != name: return {"ok":false,"reason":"No such treaty"}
  if protected_turns_left(state,a,b)>0: return {"ok":false,"reason":"Protected for %d more turns" % protected_turns_left(state,a,b)}
  d(state).treaties.erase(k)
  if name == "alliance": add_attitude(state,b,a,"abandoned",0.5)
  return {"ok":true}
 var ag = d(state).agreements.get(k,{})
 if not ag.has(name): return {"ok":false,"reason":"No such agreement"}
 if name in ["defensive","nap"] and protected_turns_left(state,a,b)>0: return {"ok":false,"reason":"Protected for %d more turns" % protected_turns_left(state,a,b)}
 ag.erase(name)
 if name == "trade": add_attitude(state,b,a,"broke_trade")
 return {"ok":true}

static func end_war(state,a: String,b: String):
 state.wars.erase(Battles.war_key(a,b))
 d(state).war_meta.erase(key(a,b))

# --- Contact and envoys (war-and-realm §0.2: envoys reach anyone) ---------------------------------

static func has_contact(state,a: String,b: String) -> bool:
 return d(state).contacts.has(key(a,b)) or Battles.at_war(state,a,b)

static func make_contact(state,a: String,b: String):
 if not d(state).contacts.has(key(a,b)): d(state).contacts[key(a,b)] = int(state.turn)

static func envoy_turns(state,a: String,b: String) -> int:
 var pa = Reputation._seat(state,a)
 var pb = Reputation._seat(state,b)
 if pa == Vector2.INF or pb == Vector2.INF: return 1
 return maxi(1,int(ceil(pa.distance_to(pb)/float(data().envoys.metres_per_turn))))

# Send an envoy: kind "contact", "embassy" or "offer" (with an offer). It arrives in envoy_turns.
static func send_envoy(state,from: String,to: String,kind: String,offer := {}) -> Dictionary:
 if from == to: return {"ok":false,"reason":"Yourself"}
 for e in d(state).envoys:
  if e.from == from and e.to == to and e.kind == kind: return {"ok":false,"reason":"An envoy is already on the way"}
 var t = envoy_turns(state,from,to)
 d(state).envoys.append({"from":from,"to":to,"kind":kind,"arrive":int(state.turn)+t,"offer":offer,"sent":int(state.turn)})
 return {"ok":true,"turns":t}

static func envoys_from(state,f: String) -> Array:
 return d(state).envoys.filter(func(e): return e.from == f)

# Envoys arriving this turn: contact, then the embassy request or the offer is answered.
static func process_envoys(state) -> Array:
 var out = []
 var keep = []
 for e in d(state).envoys:
  if int(e.arrive)>int(state.turn):
   keep.append(e)
   continue
  make_contact(state,e.from,e.to)
  var res = {"from":e.from,"to":e.to,"kind":e.kind,"ok":true,"reason":""}
  match e.kind:
   "embassy":
    var why = embassy_refusal(state,e.from,e.to)
    if why == "": open_embassy(state,e.from,e.to)
    else: res = {"from":e.from,"to":e.to,"kind":"embassy","ok":false,"reason":why}
   "offer":
    var ev = evaluate(state,e.from,e.to,e.offer)
    res.ok = ev.accept
    res.reason = "" if ev.accept else decline_reason(ev)
    if ev.accept and e.to != state.player_faction: apply_offer(state,e.from,e.to,e.offer)
    elif e.to == state.player_faction: d(state).proposals.append({"from":e.from,"to":e.to,"offer":e.offer,"turn":int(state.turn)})
  # The human player's envoy always comes back with an answer.
  if e.from == state.player_faction and e.from != "": add_reply(state,e.to,str(e.kind),bool(res.ok),str(res.reason),e.get("offer",{}))
  out.append(res)
 d(state).envoys = keep
 return out

static func embassy_refusal(state,a: String,b: String) -> String:
 if Battles.at_war(state,a,b): return "At war with you"
 if prejudice(a,b)<=-60: return "They will not receive your people"
 if a in d(state).betrayers: return "You betrayed your allies"
 return ""

# What a can see of b's court: "full" (an embassy, an ally or vassal, or one's own), "unknown" at war
# (spies come later), else "basic" (the ruler only).
static func court_visibility(state,a: String,b: String) -> String:
 if a == b or allied(state,a,b) or has_embassy(state,a,b): return "full"
 var V = load("res://core/vassals.gd")
 if V.liege_of(state,b) == a or V.liege_of(state,a) == b: return "full"
 if Battles.at_war(state,a,b): return "unknown"
 return "basic"

# --- Relations for the map and the screens ----------------------------------------------------------

static func relation(state,me: String,f: String) -> String:
 if f == me: return "self"
 if Battles.at_war(state,me,f): return "war"
 var V = load("res://core/vassals.gd")
 if V.liege_of(state,f) == me: return "vassal"
 if allied(state,me,f) or V.liege_of(state,me) == f: return "ally"
 if has_agreement(state,me,f,"trade"): return "trade"
 if attitude(state,f,me)<=-30.0 or str(WorldMap.faction(me).get("relations",{}).get(f,"")) == "rival": return "hostile"
 return "neutral"

static func liege_of(state,f: String) -> String:
 return load("res://core/vassals.gd").liege_of(state,f)

# Land a faction's armies move fast in: its own, its vassals' and liege's, its allies', and land it has
# military access to (war-and-realm §2.6).
static func friendly_land(state,mover: String,owner: String) -> bool:
 if owner == "" or owner == mover: return true
 if d(state).is_empty(): return false
 if allied(state,mover,owner) or has_access(state,mover,owner): return true
 var V = load("res://core/vassals.gd")
 return V.liege_of(state,owner) == mover or V.liege_of(state,mover) == owner

# --- War ---------------------------------------------------------------------------------------------

# Why a may go to war with b: [{kind, text}] (diplomacy-design §7).
static func justifications(state,a: String,b: String) -> Array:
 var out = []
 for e in d(state).attitude.get(a+">"+b,[]):
  if e.e in ["attacked_us","refused_call","abandoned","broke_trade"]: out.append({"kind":"grudge","text":"A grudge: they wronged us"})
 if str(WorldMap.faction(a).get("relations",{}).get(b,"")) == "rival": out.append({"kind":"grudge","text":"An old rivalry"})
 # A claim: a region b holds that was a's at the start, or a marriage into b's ruling family.
 for sid in state.settlements_of(b):
  if str(WorldMap.region(sid).get("owner","")) == a: out.append({"kind":"claim","text":"A claim on %s" % WorldMap.region(sid).settlement.name})
 var C = load("res://core/court.gd")
 for id in C.members(state,a):
  var sp = C.get_char(state,state.characters[id].spouse)
  if not sp.is_empty() and str(state.characters[id].house) != "" and C.ruler(state,b) != "" and (sp.father == C.ruler(state,b) or sp.id == C.heir(state,b)): out.append({"kind":"claim","text":"A claim through marriage"})
 # Provocation: their armies trespass in our land beyond the limit.
 var tres = 0.0
 for e in d(state).attitude.get(a+">"+b,[]):
  if e.e == "trespass": tres += absf(float(e.v))
 if tres>=float(data().war.trespass_limit)*2.0: out.append({"kind":"provocation","text":"Their armies trespass in our lands"})
 # Defending an ally or vassal at war with them.
 for f in state.factions():
  if (allied(state,a,f) or liege_of(state,f) == a) and Battles.at_war(state,f,b): out.append({"kind":"ally","text":"Defending %s" % WorldMap.faction(f).name})
 if a in d(state).betrayers or b in d(state).betrayers: out.append({"kind":"betrayer","text":"They are betrayers"})
 # Unprotected minors need none (diplomacy-design §13).
 if is_minor(b) and not d(state).protects.has(b): out.append({"kind":"minor","text":"A minor house without a protector"})
 var seen = {}
 return out.filter(func(j):
  if seen.has(j.text): return false
  seen[j.text] = true
  return true)

# Attacking b would break a treaty (betrayal): the treaty's name, or "".
static func would_betray(state,a: String,b: String) -> String:
 if Battles.at_war(state,a,b): return ""
 var t = str(treaty(state,a,b).get("kind",""))
 if t != "": return t
 for n in ["defensive","nap"]:
  if has_agreement(state,a,b,n): return n
 var V = load("res://core/vassals.gd")
 if V.liege_of(state,b) == a or V.liege_of(state,a) == b: return "vassalage"
 return ""

# Everything the declaration dialog shows (diplomacy-design §7).
static func declaration_preview(state,a: String,b: String) -> Dictionary:
 var j = justifications(state,a,b)
 var allies = []
 for f in state.factions():
  if f != a and (allied(state,b,f) or has_agreement(state,b,f,"defensive") or liege_of(state,f) == b or liege_of(state,b) == f) and not Battles.at_war(state,a,f): allies.append(f)
 var angered = []
 for f in state.factions():
  if f in [a,b]: continue
  if attitude(state,f,b)>40.0: angered.append(f)
 return {"justified":not j.is_empty(),"justifications":j,"betrayal":would_betray(state,a,b),"allies":allies,"angered":angered,
  "cost":{} if not j.is_empty() else data().get("unjustified_cost",Reputation.data().deeds.unjustified_war)}

# Declare war (the diplomacy screen or the attack confirmation; the temporary "attacking declares
# war" rule is retired). Betrayal applies when a treaty stands: the AI never does it.
static func declare_war(state,a: String,b: String,ai := false) -> Dictionary:
 if a == b or Battles.at_war(state,a,b): return {"ok":false,"reason":"Already at war"}
 if untouchable(b): return {"ok":false,"reason":"Caeloth cannot be attacked"}
 var pv = declaration_preview(state,a,b)
 if pv.betrayal != "" and ai: return {"ok":false,"reason":"The AI never betrays"}
 if pv.betrayal != "": return betray(state,a,b,pv.betrayal)
 var e = Battles.declare_war(state,a,b)
 d(state).war_meta[key(a,b)] = {"by":a,"turn":int(state.turn),"justified":pv.justified,"why":pv.justifications.map(func(x): return x.text),"start":_war_snapshot(state,a,b)}
 add_attitude(state,b,a,"attacked_us")
 var minor = is_minor(b) and not d(state).protects.has(b)
 if not minor:
  if not pv.justified: Reputation.deed(state,a,"unjustified_war","Declared war on %s without cause" % WorldMap.faction(b).name)
  else: Reputation.deed(state,a,"justified_war","Went to war with %s" % WorldMap.faction(b).name)
  for f in pv.allies: add_attitude(state,f,a,"attacked_ally" if pv.justified else "unprovoked_ally")
  for f in pv.angered: add_attitude(state,f,a,"liked_victim")
 var calls = []
 for f in pv.allies: calls.append(call_to_arms(state,b,f,a))
 _log(state,"%s declares war on %s%s." % [WorldMap.faction(a).name,WorldMap.faction(b).name,"" if pv.justified else " without cause"])
 return {"ok":true,"entry":e,"calls":calls,"justified":pv.justified}

# Betrayal (V1 rule; future Chaos trigger, war-and-realm §6.3): permanent war with every faction, every
# treaty and trade agreement lost, a permanent mark on both reputations. Only loading a save undoes it.
static func betray(state,a: String,b: String,what: String) -> Dictionary:
 # FUTURE CHAOS TRIGGER: post-V1, betraying an ally during an invasion turns the betrayer to Chaos.
 if not a in d(state).betrayers: d(state).betrayers.append(a)
 for k in d(state).treaties.keys():
  if a in k.split("|"): d(state).treaties.erase(k)
 for k in d(state).agreements.keys():
  if a in k.split("|"): d(state).agreements.erase(k)
 for f in state.factions():
  if f == a or untouchable(f) or state.settlements_of(f).is_empty(): continue
  if not Battles.at_war(state,a,f): Battles.declare_war(state,f,a)
  add_attitude(state,f,a,"betrayer")
 Reputation.deed(state,a,"betrayal","Betrayed %s (%s)" % [WorldMap.faction(b).name,what])
 var C = load("res://core/court.gd")
 var r = C.ruler(state,a)
 if r != "": C.deed(state,r,"betrayals")
 _log(state,"%s betrays %s. Every hand is now raised against them." % [WorldMap.faction(a).name,WorldMap.faction(b).name])
 return {"ok":true,"betrayal":true}

# An ally (or vassal, or pact partner) is called to war against `enemy` by `caller`.
static func call_to_arms(state,caller: String,ally: String,enemy: String) -> Dictionary:
 var V = load("res://core/vassals.gd")
 if ally == state.player_faction:
  d(state).proposals.append({"from":caller,"to":ally,"offer":{"call":enemy},"turn":int(state.turn)})
  return {"ally":ally,"answer":"asked"}
 var w = clampf(0.5+attitude(state,ally,caller)/100.0-attitude(state,ally,enemy)/200.0,0.0,1.0)
 if V.liege_of(state,ally) == caller: w = maxf(w,V.reliability(state,ally))
 if "treacherous" in WorldMap.faction(ally).get("traits",[]): w *= float(data().calls.treacherous_factor)
 if would_betray(state,ally,enemy) != "": w = minf(w,float(data().calls.join_at)-0.01) # never a betrayal
 var answer = "refuse"
 if w>=float(data().calls.join_at):
  answer = "join"
  Battles.declare_war(state,ally,enemy)
  add_attitude(state,caller,ally,"answered_call")
  Reputation.deed(state,ally,"answered_call","Answered the call of %s" % WorldMap.faction(caller).name)
 elif w>=float(data().calls.support_at):
  answer = "support"
  var g = mini(int(data().calls.support_gold),maxi(0,int(state.treasury[ally])))
  state.treasury[ally] = int(state.treasury[ally])-g
  state.treasury[caller] = int(state.treasury[caller])+g
  add_attitude(state,enemy,ally,"liked_victim")
 else:
  add_attitude(state,caller,ally,"refused_call")
  Reputation.deed(state,ally,"refused_call","Refused the call of %s" % WorldMap.faction(caller).name)
 return {"ally":ally,"answer":answer}

# The player answers a call to arms ("join", "support" or "refuse").
static func answer_call(state,caller: String,enemy: String,answer: String):
 var me = state.player_faction
 match answer:
  "join":
   if would_betray(state,me,enemy) == "": declare_war(state,me,enemy)
   add_attitude(state,caller,me,"answered_call")
  "support":
   var g = mini(int(data().calls.support_gold),maxi(0,int(state.treasury[me])))
   state.treasury[me] = int(state.treasury[me])-g
   state.treasury[caller] = int(state.treasury[caller])+g
  _:
   add_attitude(state,caller,me,"refused_call")
   Reputation.deed(state,me,"refused_call","Refused the call of %s" % WorldMap.faction(caller).name)
 d(state).proposals = d(state).proposals.filter(func(p): return not (p.from == caller and p.offer.get("call","") == enemy))

static func weariness(state,f: String) -> float:
 return float(d(state).weariness.get(f,0.0))

# --- Offers: items, eligibility, valuation (diplomacy-design §6) -----------------------------------
# An offer from proposer P to receiver R: {"give": [items P gives], "take": [items P asks for]}.
# Items: {kind: gold, amount}, {kind: tribute, amount, turns} (per turn), {kind: region, settlement},
# {kind: marriage, a, b} (character ids), {kind: alliance|defensive|nap|ceasefire|peace|trade|embassy},
# {kind: access} (the giver grants the other military access), {kind: vassalage} (the giver becomes
# the other's vassal), {kind: captive, character}.

const TREATY_ITEMS = ["alliance","defensive","nap","ceasefire","peace","trade","embassy"]

# {ok, reason} for one item given by `giver` to `other`.
static func eligible(state,giver: String,other: String,item: Dictionary) -> Dictionary:
 var at_war = Battles.at_war(state,giver,other)
 match str(item.kind):
  "gold":
   if int(item.get("amount",0))<=0: return {"ok":false,"reason":"No gold"}
   if int(state.treasury.get(giver,0))<int(item.amount): return {"ok":false,"reason":"Not enough gold"}
  "tribute":
   if int(Economy.faction_ledger(state,giver).net)<int(item.get("amount",0)): return {"ok":false,"reason":"Income too low"}
  "region":
   var sid = str(item.get("settlement",""))
   var own = state.settlements_of(giver)
   if not sid in own: return {"ok":false,"reason":"Not theirs"}
   if own.size()<=1: return {"ok":false,"reason":"Their last settlement"}
   if sid == load("res://core/armies.gd").capital(state,giver): return {"ok":false,"reason":"Their capital"}
   if load("res://core/asset_manifest.gd").is_landmark(sid) and str(WorldMap.faction(giver).get("seat_region","")) == sid: return {"ok":false,"reason":"A landmark seat"}
   if not state.settlements[sid].get("siege",{}).is_empty(): return {"ok":false,"reason":"Under siege"}
  "marriage":
   var C = load("res://core/court.gd")
   var chk = C.can_marry(state,str(item.get("a","")),str(item.get("b","")))
   if not chk.ok: return chk
  "alliance":
   if at_war: return {"ok":false,"reason":"At war"}
   if is_minor(giver) or is_minor(other): return {"ok":false,"reason":"Minor houses do not ally"}
   if prejudice(giver,other)<=-60: return {"ok":false,"reason":"Their peoples hate each other"}
   if giver in d(state).betrayers or other in d(state).betrayers: return {"ok":false,"reason":"A betrayer"}
   if allied(state,giver,other): return {"ok":false,"reason":"Already allied"}
  "defensive","nap":
   if at_war: return {"ok":false,"reason":"At war"}
   if has_agreement(state,giver,other,str(item.kind)): return {"ok":false,"reason":"Already agreed"}
  "ceasefire":
   if not at_war: return {"ok":false,"reason":"Not at war"}
  "peace":
   if not at_war and str(treaty(state,giver,other).get("kind","")) != "ceasefire": return {"ok":false,"reason":"Not at war"}
  "trade":
   if has_agreement(state,giver,other,"trade"): return {"ok":false,"reason":"Already trading"}
   if prejudice(giver,other)<=-60: return {"ok":false,"reason":"They will not trade with your people"}
  "embassy":
   if has_embassy(state,other,giver): return {"ok":false,"reason":"Already have an embassy"}
   var why = embassy_refusal(state,other,giver)
   if why != "": return {"ok":false,"reason":why}
  "access":
   if at_war: return {"ok":false,"reason":"At war"}
   if has_access(state,other,giver): return {"ok":false,"reason":"Already granted"}
  "vassalage":
   var V = load("res://core/vassals.gd")
   if V.liege_of(state,giver) != "": return {"ok":false,"reason":"Already sworn to %s" % WorldMap.faction(V.liege_of(state,giver)).name}
   if V.liege_of(state,other) == giver: return {"ok":false,"reason":"Their vassal"}
   if untouchable(giver) or untouchable(other): return {"ok":false,"reason":"Caeloth swears to no one"}
   var cap = V.cap_check(state,other,giver)
   if not cap.ok: return cap
  "captive":
   var c = load("res://core/court.gd").get_char(state,str(item.get("character","")))
   if c.is_empty() or str(c.role) != "prisoner:"+giver: return {"ok":false,"reason":"Not their captive"}
 return {"ok":true,"reason":""}

static func _trust(state,receiver: String,proposer: String) -> float:
 var t = float(Reputation.perceived(state,receiver,proposer).trust)
 return lerpf(float(data().trust.low),float(data().trust.high),(t+100.0)/200.0)

static func _power(state,f: String) -> float:
 return maxf(1.0,Reputation.strength(state,f))

static func _income(state,sid: String) -> float:
 return float(Economy.settlement_income(state,sid).total)

# What R values item `it` at when it goes the way `to_r` says (true: R receives it). Gold
# equivalents with the reason text.
static func _value(state,r: String,p: String,it: Dictionary,to_r: bool) -> Array:
 var v = data().values
 var gpa = float(data().attitude.gold_per_point)
 var trust = _trust(state,r,p)
 var traits = WorldMap.faction(r).get("traits",[])
 var reluct = float(v.reluctance) if ("proud" in traits or "expansionist" in traits) else 1.0
 var name_p = WorldMap.faction(p).name
 match str(it.kind):
  "gold":
   var a = float(it.amount)
   if to_r: return [a,"%d gold" % int(a)]
   return [-a*(float(v.generous) if "generous" in traits else 1.0),"They pay %d gold" % int(a)]
  "tribute":
   var a = float(it.amount)*float(it.get("turns",v.tribute_turns))*float(v.tribute_factor)
   if to_r: return [a*trust,"%d gold a turn for %d turns" % [int(it.amount),int(it.get("turns",v.tribute_turns))]]
   return [-a*reluct,"They pay tribute of %d a turn" % int(it.amount)]
  "region":
   var sid = str(it.settlement)
   var a = _income(state,sid)*float(v.region_turns)+400.0
   var n = WorldMap.region(sid).settlement.name
   if to_r: return [a,"They gain %s" % n]
   return [-a*reluct,"They give up %s" % n]
  "marriage":
   return [float(v.marriage)*gpa,"A marriage between your houses"]
  "embassy":
   return [float(v.embassy)*gpa*(1.0 if attitude(state,r,p)>-30.0 else -1.0),"An embassy"]
  "nap":
   return [float(v.nap)*gpa*trust,"A pact of non-aggression"]
  "access":
   var fear = attitude(state,r,p)<-10.0 or float(Reputation.perceived(state,r,p).peace)<-30.0
   if to_r: return [float(v.access_friend)*gpa,"Military access to %s's lands" % name_p]
   return [float(v.access_fear if fear else v.access_friend)*gpa*(1.0 if fear else -0.3),"Your armies cross their lands"]
  "trade":
   var mine = 0.0
   for sid in state.settlements_of(p): mine += _income(state,sid)
   return [mine*float(data().trade.share)*float(v.trade_turns)*trust,"Trade"]
  "alliance","defensive":
   var base = float(v.alliance_base if it.kind == "alliance" else v.defensive_base)
   var protect = base*clampf(_power(state,p)/_power(state,r),0.2,3.0)
   var threats = 0
   for e in load("res://core/ai.gd").at_war_with(state,p): threats += 1
   var risk = float(v.alliance_per_war)*threats if it.kind == "alliance" else 0.0
   return [(protect+risk)*trust,"%s with %s" % ["An alliance" if it.kind == "alliance" else "A defensive pact",name_p]]
  "ceasefire","peace":
   var w = weariness(state,r)*float(v.peace_per_weariness)
   var ratio = _power(state,p)/_power(state,r)
   var bal = float(v.peace_losing)*clampf(ratio-1.0,0.0,2.0) if ratio>1.0 else float(v.peace_winning)*clampf(1.0/ratio-1.0,0.0,2.0)
   var mult = 1.0 if it.kind == "peace" else 0.6
   # How the war goes for the receiver (owner spec 2026-10-07): a winner wants more than peace; a loser
   # is glad of it; an even war grows stale.
   var oc = war_outcome(state,r,p) if Battles.at_war(state,p,r) else "even"
   var wo = data().war
   var out_v = float(wo.get("winning_refuses",-700)) if oc == "winning" else (float(wo.get("losing_accepts",400)) if oc == "losing" else (float(wo.get("stalemate_value",250)) if Battles.at_war(state,p,r) and war_age(state,p,r)>=int(wo.get("stalemate_turns",10)) else 0.0))
   return [(w+bal)*mult+120.0+out_v,"%s (they are %s)" % ["Peace" if it.kind == "peace" else "A ceasefire",{"winning":"winning this war","losing":"losing this war"}.get(oc,"losing" if ratio>1.15 else ("winning" if ratio<0.87 else "evenly matched"))]]
  "vassalage":
   # R becomes P's vassal (when R gives it) or P becomes R's (when R receives it).
   if not to_r:
    var gap = _power(state,p)/_power(state,r)
    var threatened = 0.0
    for e in load("res://core/ai.gd").at_war_with(state,r): threatened += _power(state,e)/_power(state,r)
    var a = float(v.vassal_base)+float(v.vassal_threat)*clampf(threatened,0.0,3.0)+400.0*clampf(gap-float(v.vassal_gap),0.0,4.0)
    if in_debt(state,r): a += 600.0
    return [a,"They swear fealty to %s" % name_p]
   return [600.0,"%s swears fealty to them" % name_p]
  "captive":
   var c = load("res://core/court.gd").get_char(state,str(it.character))
   var a = 150.0*float(c.get("level",1))+(800.0 if load("res://core/court.gd").heir(state,r) == c.get("id","") else 0.0)
   if to_r: return [a,"The return of %s" % c.get("name","a captive")]
   return [-a,"They release %s" % c.get("name","a captive")]
 return [0.0,str(it.kind)]

static func in_debt(state,f: String) -> bool:
 return int(state.treasury.get(f,0))<0

# The receiver's view of an offer: {score, accept, chance (label), reasons: [{text, value}], blocked}.
# Treaty items are valued from both sides (both receive them); a deal the receiver cannot take
# (an ineligible item) is blocked with the reason.
static func evaluate(state,p: String,r: String,offer: Dictionary) -> Dictionary:
 var reasons = []
 var score = 0.0
 for it in offer.get("give",[]):
  var e = eligible(state,p,r,it)
  if not e.ok: return {"score":-9999.0,"accept":false,"chance":"Impossible","reasons":[{"text":e.reason,"value":0.0}],"blocked":true}
  var v = _value(state,r,p,it,true)
  score += v[0]
  reasons.append({"text":v[1],"value":v[0]})
 for it in offer.get("take",[]):
  var e = eligible(state,r,p,it)
  if not e.ok: return {"score":-9999.0,"accept":false,"chance":"Impossible","reasons":[{"text":e.reason,"value":0.0}],"blocked":true}
  var v = _value(state,r,p,it,false)
  if str(it.kind) in TREATY_ITEMS+["marriage"]: v = _value(state,r,p,it,true) # shared: both gain it
  score += v[0]
  reasons.append({"text":v[1],"value":v[0]})
 if reasons.is_empty(): return {"score":0.0,"accept":false,"chance":"Nothing offered","reasons":[],"blocked":true}
 var gpa = float(data().attitude.gold_per_point)
 var att = attitude(state,r,p)
 if absf(att)>=1.0:
  score += att*gpa*0.5
  reasons.append({"text":"They %s you (attitude %+d)" % ["like" if att>0.0 else "dislike",int(att)],"value":att*gpa*0.5})
 var bp = bloc(p)
 var br = bloc(r)
 if bp != "neutral" and br != "neutral":
  var b = float(data().blocs.same if bp == br else data().blocs.cross)*gpa
  score += b
  reasons.append({"text":"Same people (%s)" % bp.capitalize() if bp == br else "Across the divide of Order and Destruction","value":b})
 for l in Reputation.labels(state,r,p).slice(0,2):
  var lv = 0.0
  match str(l.axis):
   "trust": lv = float(l.value)*3.0
   "honor": lv = float(l.value)*1.5
   "mercy": lv = float(l.value)*1.0
  if lv != 0.0:
   score += lv
   reasons.append({"text":"They think you are %s" % l.name,"value":lv})
 if p in d(state).betrayers:
  score -= 2000.0
  reasons.append({"text":"You betrayed your allies","value":-2000.0})
 reasons.sort_custom(func(a,b): return absf(a.value)>absf(b.value))
 return {"score":score,"accept":score>=0.0,"chance":chance_label(score),"reasons":reasons,"blocked":false}

static func chance_label(score: float) -> String:
 if score>=600.0: return "Very likely"
 if score>=150.0: return "Likely"
 if score>=0.0: return "Will accept"
 if score>=-300.0: return "Unlikely"
 return "Will not accept"

# Carry out an accepted offer.
static func apply_offer(state,p: String,r: String,offer: Dictionary):
 for pair in [[p,r,offer.get("give",[])],[r,p,offer.get("take",[])]]:
  var giver = pair[0]
  var other = pair[1]
  for it in pair[2]:
   match str(it.kind):
    "gold":
     state.treasury[giver] = int(state.treasury[giver])-int(it.amount)
     state.treasury[other] = int(state.treasury[other])+int(it.amount)
     add_attitude(state,other,giver,"gift",float(it.amount)/1000.0)
    "tribute":
     load("res://core/vassals.gd").add_tribute(state,giver,other,int(it.amount),int(it.get("turns",data().values.tribute_turns)))
    "region":
     var sid = str(it.settlement)
     state.settlements[sid].owner = other
     state.settlements[sid].constructions = []
     load("res://core/buildings.gd").refresh(state,sid)
     for id in load("res://core/movement.gd").garrison_of(state,sid):
      if state.army_state[id].faction == giver: state.army_state[id].garrison = ""
    "marriage":
     load("res://core/court.gd").marry(state,str(it.a),str(it.b))
     add_attitude(state,p,r,"marriage")
     add_attitude(state,r,p,"marriage")
     Reputation.deed(state,p,"marriage","A marriage with %s" % WorldMap.faction(r).name,0.5)
    "embassy":
     open_embassy(state,other,giver)
    "access":
     grant_access(state,giver,other)
    "vassalage":
     load("res://core/vassals.gd").swear(state,giver,other,"diplomacy")
    "captive":
     var c = load("res://core/court.gd").get_char(state,str(it.character))
     c.role = "courtier"
     add_attitude(state,other,giver,"released_captive")
    _:
     if str(it.kind) in ["alliance","defensive","nap","ceasefire","peace","trade"]: sign_treaty(state,p,r,str(it.kind))
 var C = load("res://core/court.gd")
 for f in [p,r]:
  var ru = C.ruler(state,f)
  if ru != "": C.deed(state,ru,"deals",1,30.0)
  if offer.get("give",[]).any(func(i): return i.kind == "trade") or offer.get("take",[]).any(func(i): return i.kind == "trade"):
   if ru != "": C.deed(state,ru,"trade_deals")

# The player proposes: R answers at once if in contact (an envoy is sent otherwise).
static func propose(state,p: String,r: String,offer: Dictionary) -> Dictionary:
 if not has_contact(state,p,r):
  var s = send_envoy(state,p,r,"offer",offer)
  return {"ok":s.ok,"sent":true,"turns":s.get("turns",0),"accept":false,"reason":"An envoy is on the way (%d turns)" % s.get("turns",0) if s.ok else s.reason}
 var ev = evaluate(state,p,r,offer)
 if ev.accept: apply_offer(state,p,r,offer)
 var rep = {}
 if p == state.player_faction and p != "": rep = add_reply(state,r,"offer",ev.accept,"" if ev.accept else decline_reason(ev),offer)
 return {"ok":true,"accept":ev.accept,"evaluation":ev,"reply":rep}

# --- Trade income (war-and-realm §7.3: trade continues during war with tariffs) -------------------

static func trade_income(state,f: String) -> Array:
 var out = []
 if state.get("diplomacy") == null or state.diplomacy.is_empty(): return out
 var own = 0.0
 for sid in state.settlements_of(f): own += _income(state,sid)
 var total = 0.0
 for k in d(state).agreements:
  if not d(state).agreements[k].has("trade"): continue
  var parts = k.split("|")
  if not f in parts: continue
  var other = parts[0] if parts[1] == f else parts[1]
  var theirs = 0.0
  for sid in state.settlements_of(other): theirs += float(state.settlements[sid].population)*0.02+100.0
  var amt = theirs*float(data().trade.share)
  if Battles.at_war(state,f,other): amt *= float(data().trade.war_tariff)
  amt = minf(amt,maxf(0.0,own*float(data().trade.cap_share)-total))
  if amt<1.0: continue
  total += amt
  out.append({"partner":other,"amount":int(round(amt)),"war":Battles.at_war(state,f,other)})
 return out

# --- Commandable allies and vassals (diplomacy-design §8) -------------------------------------------

# Willingness of `to` to obey `by` (0..1) for an order with `gold` reward.
static func willingness(state,by: String,to: String,gold := 0) -> float:
 var o = data().orders
 var dom = clampf(_power(state,by)/_power(state,to),0.0,4.0)/4.0
 var w = 0.25+dom*0.35+attitude(state,to,by)/250.0+float(gold)/500.0*float(o.reward_per_500)
 var V = load("res://core/vassals.gd")
 if V.liege_of(state,to) == by: w += float(o.vassal_bonus)*V.reliability(state,to)
 var lf = Reputation.love_fear(state,by)
 w += (lf.love+lf.fear*0.5)/400.0
 return clampf(w,0.0,1.0)

# Order an ally or vassal: kind "attack" (an army or settlement), "besiege", "defend" (a region),
# target id. Accepted orders are carried out by the AI with a real force (core/ai.gd); refusals give
# the reason. Returns {ok, accept, reason, army}.
static func give_order(state,by: String,to: String,kind: String,target: String,gold := 0) -> Dictionary:
 var V = load("res://core/vassals.gd")
 if not (allied(state,by,to) or V.liege_of(state,to) == by): return {"ok":false,"accept":false,"reason":"Not your ally or vassal"}
 var w = willingness(state,by,to,gold)
 if w<float(data().orders.accept_at): return {"ok":true,"accept":false,"reason":"They will not (willingness %d%%)" % int(w*100)}
 var force = _commit_army(state,to,kind,target)
 if force.is_empty(): return {"ok":true,"accept":false,"reason":"Our armies are needed at home"}
 if gold>0 and int(state.treasury[by])>=gold:
  state.treasury[by] = int(state.treasury[by])-gold
  state.treasury[to] = int(state.treasury[to])+gold
 d(state).orders.append({"by":by,"to":to,"kind":kind,"target":target,"army":force.army,"turn":int(state.turn)})
 if kind in ["attack","besiege"]:
  var tf = _target_faction(state,kind,target)
  if tf != "" and not Battles.at_war(state,to,tf) and would_betray(state,to,tf) == "": declare_war(state,to,tf,true)
 return {"ok":true,"accept":true,"reason":"","army":force.army}

static func _target_faction(state,kind: String,target: String) -> String:
 if state.settlements.has(target): return str(state.settlements[target].owner)
 if state.army_state.has(target): return str(state.army_state[target].faction)
 return ""

static func _target_pos(state,target: String) -> Vector2:
 if state.settlements.has(target): return WorldMap.settlement_position(target)
 if state.army_state.has(target): return load("res://core/movement.gd").position(state,target)
 return Vector2.INF

# The army that gives the best odds with at least min_commit of the target's defence, or the strongest.
static func _commit_army(state,f: String,kind: String,target: String) -> Dictionary:
 var Ai = load("res://core/ai.gd")
 var need = 0.0
 if kind in ["attack","besiege"]:
  if state.settlements.has(target): need = Ai.settlement_defense(state,target)
  elif state.army_state.has(target): need = Ai.army_power(state,target)
 var best = {}
 for id in Ai.field_armies(state,f):
  var pw = Ai.army_power(state,id)
  if best.is_empty() or pw>float(best.power): best = {"army":id,"power":pw}
 if best.is_empty(): return {}
 if kind == "defend": return best
 if float(best.power)<need*float(data().orders.min_commit) and float(best.power)<need: return {}
 return best

static func orders_for(state,f: String) -> Array:
 return d(state).orders.filter(func(o): return o.to == f)

# --- Yearly processing --------------------------------------------------------------------------

static func end_turn(state) -> Dictionary:
 var out = {"envoys":process_envoys(state),"expired":[]}
 # Ceasefires end with their protection (then neutral, unless peace is signed).
 for k in d(state).treaties.keys():
  var t = d(state).treaties[k]
  if t.kind == "ceasefire" and int(state.turn)-int(t.since)>=int(data().protection_turns):
   d(state).treaties.erase(k)
   out.expired.append(k)
 # War weariness.
 for f in state.factions():
  var w = float(d(state).weariness.get(f,0.0))
  if load("res://core/ai.gd").at_war_with(state,f).is_empty(): w = maxf(0.0,w-float(data().war.weariness_decay))
  else: w += float(data().war.weariness_per_turn)
  d(state).weariness[f] = w
 # Trespass: armies at peace in another's land without access.
 for id in state.army_state:
  var a = state.army_state[id]
  var at = Vector2(a.position[0],a.position[1])
  var rg = WorldMap.region_at(at)
  if rg == "" or not state.settlements.has(rg): continue
  var owner = str(state.settlements[rg].owner)
  if owner == "" or owner == a.faction or Battles.at_war(state,owner,a.faction) or friendly_land(state,a.faction,owner): continue
  add_attitude(state,owner,a.faction,"trespass")
 # Orders expire.
 d(state).orders = d(state).orders.filter(func(o): return int(state.turn)-int(o.turn)<int(data().orders.expire) and state.army_state.has(o.army))
 decay(state)
 return out

static func _log(state,text: String):
 d(state).log.append({"turn":int(state.turn),"year":int(state.year),"text":text})
 while d(state).log.size()>60: d(state).log.pop_front()

# --- War outcome (owner spec 2026-10-07: peace by how the war goes, not a timer) ----------------------
# At the declaration each side's settlements and power are recorded; a side is "winning" when it has
# taken ground (a settlement more than the other, net) or its power has risen against the other's by
# outcome_swing, "losing" in the mirror case, "even" otherwise. The loser sues for peace and pays for
# it (gold, land or fealty); the winner refuses plain peace; even wars settle after stalemate_turns.
static func _war_snapshot(state,a: String,b: String) -> Dictionary:
 return {a:{"settlements":state.settlements_of(a).size(),"power":_power(state,a)},b:{"settlements":state.settlements_of(b).size(),"power":_power(state,b)}}

static func war_meta(state,a: String,b: String) -> Dictionary:
 var m = d(state).war_meta.get_or_add(key(a,b),{"by":a,"turn":int(state.turn),"justified":false,"why":[]})
 if not m.has("start") or not m.start.has(a) or not m.start.has(b): m.start = _war_snapshot(state,a,b)
 return m

static func war_age(state,a: String,b: String) -> int:
 return int(state.turn)-int(war_meta(state,a,b).turn)

static func war_outcome(state,f: String,e: String) -> String:
 var st = war_meta(state,f,e).start
 var gained = (state.settlements_of(f).size()-int(st[f].settlements))-(state.settlements_of(e).size()-int(st[e].settlements))
 if gained>=1: return "winning"
 if gained<=-1: return "losing"
 var then = float(st[f].power)/maxf(1.0,float(st[e].power))
 var now = _power(state,f)/maxf(1.0,_power(state,e))
 var swing = float(data().war.get("outcome_swing",0.25))
 if now>then*(1.0+swing): return "winning"
 if now<then*(1.0-swing): return "losing"
 return "even"
