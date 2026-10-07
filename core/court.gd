extends RefCounted
# Characters and courts (game-design §4; docs/v1-content.md §2; data/court.json, data/traits.json).
# Every faction has a court: family by blood and marriage, wards and courtiers. One turn is one year:
# children age 2.5 years a turn to 12, then a year a turn through the formative years (the career is
# picked by 16), adults stop aging in their prime. Nobody dies of age or sickness; characters die in
# battle, by execution, or (hooks only) by assassination and events. Level 20 makes a character
# immortal; legendary founders are immortal from the start.
# State: state.characters[id] = {id, name, house, faction, race, culture, gender, age, father, mother,
#  spouse, children, career, career_pending, xp, level, skills, traits {id: level}, deeds {counter: n},
#  epithet, epithet_changed, loyalty, loyalty_log [{turn, delta, reason}], role, immortal, legendary,
#  dead, defeated_until, history [{year, text}], since_favour, ward_of}
# state.courts[faction] = {ruler, heir, members: [ids]}; state.next_character: the id counter.
# Generals: an army's commander carries "character" (its id); the army keeps name, rank and xp for the
# battle code, and the character's level follows the rank.

const WorldMap = preload("res://core/world_map.gd")
const DATA = "res://data/court.json"
const TRAITS = "res://data/traits.json"

static var _data = null
static var _traits = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
 return _data

static func trait_data() -> Dictionary:
 if _traits == null: _traits = JSON.parse_string(FileAccess.get_file_as_string(TRAITS))
 return _traits

static func reset():
 _data = null
 _traits = null

static func rng_for(state,tag) -> RandomNumberGenerator:
 var r = RandomNumberGenerator.new()
 r.seed = hash([state.seed,state.turn,tag])
 return r

# --- Names -----------------------------------------------------------------------------------

static func _names() -> Dictionary:
 return load("res://core/armies.gd").names()

static func _given(culture: String,gender: String,rng: RandomNumberGenerator) -> String:
 var n = _names()
 var pools = n.get("cultures",{}).get(culture,{})
 var key = "female" if gender == "f" else "given"
 var pool = pools.get(key,[])
 if pool.is_empty() and gender == "f": pool = n.get("female",[])
 if pool.is_empty(): pool = pools.get("given",n.get("given",["Aldo"]))
 return str(pool[rng.randi_range(0,pool.size()-1)])

# --- Characters ------------------------------------------------------------------------------

static func get_char(state,id: String) -> Dictionary:
 return state.characters.get(id,{})

static func new_character(state,faction: String,fields: Dictionary) -> String:
 var id = "c%d" % int(state.next_character)
 state.next_character = int(state.next_character)+1
 var f = WorldMap.faction(faction)
 var c = {"id":id,"name":"","house":str(f.get("house",f.get("name",""))),"faction":faction,"race":str(f.get("culture","medieval")),
  "culture":str(f.get("culture","medieval")),"gender":"m","age":30.0,"father":"","mother":"","spouse":"","children":[],
  "career":"","career_pending":false,"xp":0.0,"level":1,"skills":[],"traits":{},"deeds":{},"epithet":"","epithet_changed":false,
  "loyalty":int(data().loyalty.start),"loyalty_log":[],"role":"courtier","immortal":false,"legendary":false,"dead":false,
  "defeated_until":-1,"history":[],"since_favour":0,"ward_of":"","army":""}
 c.merge(fields,true)
 state.characters[id] = c
 if faction != "": court(state,faction).members.append(id)
 return id

static func court(state,faction: String) -> Dictionary:
 if not state.courts.has(faction): state.courts[faction] = {"ruler":"","heir":"","members":[]}
 return state.courts[faction]

static func members(state,faction: String,alive_only := true) -> Array:
 var out = []
 for id in court(state,faction).members:
  var c = state.characters.get(id)
  if c == null or (alive_only and c.dead): continue
  out.append(id)
 return out

static func full_name(c: Dictionary) -> String:
 var n = "%s %s" % [c.name,c.house] if str(c.house) != "" else str(c.name)
 if str(c.epithet) != "": n += " "+str(c.epithet)
 return n

static func is_adult(c: Dictionary) -> bool:
 return float(c.age)>=float(data().aging.formative_until)

static func ruler(state,faction: String) -> String:
 return str(court(state,faction).ruler)

static func heir(state,faction: String) -> String:
 return str(court(state,faction).heir)

static func history(state,c: Dictionary,text: String):
 c.history.append({"year":int(state.year),"text":text})
 while c.history.size()>30: c.history.pop_front()

# --- Levels -----------------------------------------------------------------------------------

static func level_for_xp(xp: float) -> int:
 var x = data().xp
 # Inverse of xp = level_xp x (L - 1) ^ level_power.
 return 1+int(floor(pow(maxf(0.0,xp)/float(x.level_xp),1.0/float(x.level_power))+0.0001))

static func xp_for_level(l: int) -> float:
 var x = data().xp
 return float(x.level_xp)*pow(float(maxi(0,l-1)),float(x.level_power))

static func gain_xp(state,id: String,amount: float):
 var c = get_char(state,id)
 if c.is_empty() or c.dead: return
 c.xp = float(c.xp)+amount
 _sync_level(state,c)

static func _sync_level(state,c: Dictionary):
 var lv = level_for_xp(float(c.xp))
 if str(c.army) != "" and state.army_state.has(c.army): lv = maxi(lv,int(state.army_state[c.army].commander.get("rank",1)))
 if lv>int(c.level):
  c.level = lv
  if lv>=int(data().xp.immortal_level) and not c.immortal:
   c.immortal = true
   c.traits.immortal = 1
   c.deeds.immortal = 1
   history(state,c,"Reached the twentieth level and became immortal.")
   check_epithet(state,c)

static func skill_points(c: Dictionary) -> int:
 return maxi(0,int(c.level)-c.skills.size())

# --- Deeds, traits, epithets -------------------------------------------------------------------

static func deed(state,id: String,counter: String,amount := 1,xp := 0.0):
 var c = get_char(state,id)
 if c.is_empty() or c.dead: return
 c.deeds[counter] = int(c.deeds.get(counter,0))+amount
 if xp>0.0: gain_xp(state,id,xp)
 check_traits(state,c)
 check_epithet(state,c)

static func trait_level(c: Dictionary,t: String) -> int:
 return int(c.traits.get(t,0))

static func add_trait(state,c: Dictionary,t: String,lv := 1) -> bool:
 var td = trait_data().traits.get(t)
 if td == null: return false
 var opp = str(td.get("opposite",""))
 if opp != "" and c.traits.has(opp): return false
 lv = mini(lv,int(td.get("levels",1)))
 if trait_level(c,t)>=lv: return false
 c.traits[t] = lv
 history(state,c,"Became %s%s." % [td.name,"" if lv<=1 else " "+["","I","II","III"][lv]])
 return true

static func check_traits(state,c: Dictionary):
 for t in trait_data().traits:
  var td = trait_data().traits[t]
  if td.get("culture","") != "" and td.culture != c.culture: continue
  for counter in td.get("earned_by",{}):
   var th = td.earned_by[counter]
   var have = int(c.deeds.get(counter,0))
   var lv = 0
   for i in th.size():
    if have>=int(th[i]): lv = i+1
   if lv>0: add_trait(state,c,t,lv)

static func check_epithet(state,c: Dictionary):
 if c.epithet != "" and c.epithet_changed: return
 for e in trait_data().epithets:
  var ok = true
  for k in e.when:
   if int(c.deeds.get(k,0))<int(e.when[k]): ok = false
  if not ok: continue
  if c.epithet == e.name: return
  if c.epithet != "": c.epithet_changed = true
  c.epithet = e.name
  history(state,c,"Called %s from now on." % e.name)
  return

# Visible traits (at most max_visible): [{id, name, level, kind, text}].
static func visible_traits(c: Dictionary) -> Array:
 var out = []
 for t in c.traits:
  var td = trait_data().traits.get(t)
  if td == null: continue
  out.append({"id":t,"name":td.name+("" if int(c.traits[t])<=1 else " "+["","I","II","III"][int(c.traits[t])]),"level":int(c.traits[t]),"kind":td.kind,"effects":td.get("effects",{})})
 return out.slice(0,int(trait_data().max_visible))

static func trait_effect(c: Dictionary,key: String) -> float:
 var v = 0.0
 for t in c.traits:
  var e = trait_data().traits.get(t,{}).get("effects",{})
  if e.has(key) and not e[key] is String: v += float(e[key])*int(c.traits[t])
 return v

# --- Loyalty ------------------------------------------------------------------------------------

static func change_loyalty(state,id: String,delta: int,reason: String):
 var c = get_char(state,id)
 if c.is_empty() or delta == 0: return
 c.loyalty = clampi(int(c.loyalty)+delta,0,100)
 c.loyalty_log.append({"turn":int(state.turn),"delta":delta,"reason":reason})
 while c.loyalty_log.size()>int(data().loyalty.log): c.loyalty_log.pop_front()

static func favour(state,id: String,kind: String,reason := ""):
 var c = get_char(state,id)
 if c.is_empty(): return
 c.since_favour = 0
 change_loyalty(state,id,int(data().loyalty.role_gain.get(kind,5)),reason if reason != "" else kind.capitalize())

# The loyalty breakdown for tooltips: the recent changes with reasons, newest first.
static func loyalty_reasons(c: Dictionary) -> Array:
 var out = c.loyalty_log.duplicate()
 out.reverse()
 return out

static func gift(state,faction: String,id: String,gold: int) -> Dictionary:
 if int(state.treasury.get(faction,0))<gold or gold<=0: return {"ok":false,"reason":"Not enough gold"}
 state.treasury[faction] = int(state.treasury[faction])-gold
 var c = get_char(state,id)
 c.since_favour = 0
 change_loyalty(state,id,int(round(float(gold)/float(data().loyalty.gift_gold)*float(data().loyalty.gift_per))),"A gift of %d gold" % gold)
 return {"ok":true}

# The branch a character belongs to: the ruler's child they descend from ("" = the ruler or outside).
static func branch(state,faction: String,id: String) -> String:
 var r = ruler(state,faction)
 var cur = id
 var guard = 0
 while cur != "" and guard<12:
  guard += 1
  var c = get_char(state,cur)
  if c.is_empty(): return ""
  if c.father == r or c.mother == r: return cur
  cur = c.father if c.father != "" else c.mother
 return ""

# --- Roles --------------------------------------------------------------------------------------

static func set_role(state,id: String,role: String):
 var c = get_char(state,id)
 if c.is_empty(): return
 var old = str(c.role)
 c.role = role
 if role.begins_with("governor:") and not old.begins_with("governor:"): favour(state,id,"governor","Made governor")
 if role.begins_with("general:") and not old.begins_with("general:"): favour(state,id,"general","Given an army")

static func governor_of(state,sid: String) -> String:
 var f = str(state.settlements.get(sid,{}).get("owner",""))
 for id in members(state,f):
  if state.characters[id].role == "governor:"+sid: return id
 return ""

static func appoint_governor(state,faction: String,id: String,sid: String) -> Dictionary:
 var c = get_char(state,id)
 if c.is_empty() or c.faction != faction or c.dead: return {"ok":false,"reason":"Not in your court"}
 if not is_adult(c): return {"ok":false,"reason":"Too young"}
 if str(state.settlements.get(sid,{}).get("owner","")) != faction: return {"ok":false,"reason":"Not your region"}
 if str(c.army) != "": return {"ok":false,"reason":"Leads an army"}
 var old = governor_of(state,sid)
 if old != "" and old != id: set_role(state,old,"courtier")
 set_role(state,id,"governor:"+sid)
 history(state,c,"Appointed governor of %s." % WorldMap.region(sid).settlement.name)
 return {"ok":true}

# --- Heirs and succession (game-design §4.8: the player always picks the heir; no crisis) ---------

static func set_heir(state,faction: String,id: String) -> Dictionary:
 var c = get_char(state,id)
 if c.is_empty() or c.faction != faction or c.dead: return {"ok":false,"reason":"Not in your court"}
 if id == ruler(state,faction): return {"ok":false,"reason":"Already the ruler"}
 var old = heir(state,faction)
 if old == id: return {"ok":true}
 court(state,faction).heir = id
 if old != "": change_loyalty(state,old,int(data().loyalty.role_loss.heir),"Passed over as heir")
 favour(state,id,"heir","Named heir")
 history(state,c,"Named heir of %s." % WorldMap.faction(faction).name)
 return {"ok":true}

# A new ruler at any time (game-design §4.8): the old ruler becomes a courtier (or keeps their army as a
# hero), the reputation's first-impressions window opens.
static func make_ruler(state,faction: String,id: String,reason := "") -> Dictionary:
 var c = get_char(state,id)
 if c.is_empty() or c.faction != faction or c.dead: return {"ok":false,"reason":"Not in your court"}
 if not is_adult(c): return {"ok":false,"reason":"Too young to rule"}
 var cr = court(state,faction)
 var old = str(cr.ruler)
 if old == id: return {"ok":true}
 if old != "" and state.characters.has(old) and not state.characters[old].dead:
  var oc = state.characters[old]
  oc.role = "general:"+oc.army if str(oc.army) != "" else "courtier"
  history(state,oc,"Stepped down as ruler.")
 cr.ruler = id
 if cr.heir == id: cr.heir = ""
 c.role = "ruler" if str(c.army) == "" else "ruler"
 c.since_favour = 0
 history(state,c,"Became ruler of %s%s." % [WorldMap.faction(faction).name,(" ("+reason+")") if reason != "" else ""])
 load("res://core/reputation.gd").new_ruler(state,faction)
 if cr.heir == "": _auto_heir(state,faction)
 return {"ok":true}

# When the ruler dies: the chosen heir succeeds (or, with none, the eldest adult of the family).
static func succeed(state,faction: String):
 var h = heir(state,faction)
 if h == "" or get_char(state,h).is_empty() or get_char(state,h).dead or not is_adult(get_char(state,h)): h = _best_successor(state,faction)
 if h != "": make_ruler(state,faction,h,"succession")

static func _best_successor(state,faction: String) -> String:
 var best = ""
 for id in members(state,faction):
  var c = state.characters[id]
  if not is_adult(c) or id == ruler(state,faction): continue
  if best == "" or (str(c.house) == str(WorldMap.faction(faction).get("house","")) and str(state.characters[best].house) != str(c.house)) or float(c.age)>float(state.characters[best].age): best = id
 return best

static func _auto_heir(state,faction: String):
 var r = get_char(state,ruler(state,faction))
 var best = []
 for id in members(state,faction):
  if id == ruler(state,faction): continue
  var c = state.characters[id]
  var score = (10.0 if c.father == r.get("id","") or c.mother == r.get("id","") else 0.0)+float(c.age)*0.1
  if best.is_empty() or score>float(best[1]): best = [id,score]
 if not best.is_empty(): court(state,faction).heir = best[0]

# --- Death ------------------------------------------------------------------------------------------

# A character dies (battle, execution; assassination and events are hooks). An immortal is defeated
# and returns after return_defeated turns instead.
static func die(state,id: String,cause: String):
 var c = get_char(state,id)
 if c.is_empty() or c.dead: return
 if c.immortal and cause in ["battle","assassination"]:
  c.defeated_until = int(state.turn)+int(data().xp.return_defeated)
  history(state,c,"Defeated (%s); will return." % cause)
  return
 c.dead = true
 c.dead_reason = cause
 history(state,c,"Died (%s)." % cause)
 if str(c.spouse) != "" and state.characters.has(c.spouse): state.characters[c.spouse].spouse = ""
 var f = str(c.faction)
 if f != "" and state.courts.has(f):
  if ruler(state,f) == id: succeed(state,f)
  if heir(state,f) == id: court(state,f).heir = ""
  if heir(state,f) == "": _auto_heir(state,f)

# --- Marriage (game-design §4.9) -------------------------------------------------------------------

static func can_marry(state,a: String,b: String) -> Dictionary:
 var ca = get_char(state,a)
 var cb = get_char(state,b)
 if ca.is_empty() or cb.is_empty(): return {"ok":false,"reason":"Unknown character"}
 if ca.dead or cb.dead: return {"ok":false,"reason":"Dead"}
 if a == b or ca.gender == cb.gender: return {"ok":false,"reason":"Not a match"}
 for c in [ca,cb]:
  if float(c.age)<float(data().marriage.min_age): return {"ok":false,"reason":"%s is too young" % c.name}
  if str(c.spouse) != "": return {"ok":false,"reason":"%s is married" % c.name}
 if ca.father != "" and (ca.father == cb.father or ca.mother == cb.mother): return {"ok":false,"reason":"Siblings"}
 if ca.father == b or ca.mother == b or cb.father == a or cb.mother == a: return {"ok":false,"reason":"Parent and child"}
 return {"ok":true,"reason":""}

# Marry two characters. The wife joins the husband's court unless she is her faction's ruler or heir
# (then the husband joins hers). Returns {ok, reason, court}.
static func marry(state,a: String,b: String) -> Dictionary:
 var chk = can_marry(state,a,b)
 if not chk.ok: return chk
 var ca = get_char(state,a)
 var cb = get_char(state,b)
 var husband = ca if ca.gender == "m" else cb
 var wife = cb if husband == ca else ca
 husband.spouse = wife.id
 wife.spouse = husband.id
 var stays = wife.faction != husband.faction and (ruler(state,wife.faction) == wife.id or heir(state,wife.faction) == wife.id)
 var mover = husband if stays else wife
 var to = wife.faction if stays else husband.faction
 if mover.faction != to:
  if state.courts.has(mover.faction):
   state.courts[mover.faction].members.erase(mover.id)
   if heir(state,mover.faction) == mover.id: state.courts[mover.faction].heir = ""
  mover.faction = to
  court(state,to).members.append(mover.id)
  mover.role = "courtier"
  mover.loyalty = int(data().loyalty.spouse_start)
 for c in [husband,wife]:
  favour(state,c.id,"marriage","Married")
  history(state,c,"Married %s." % full_name(wife if c == husband else husband))
 return {"ok":true,"reason":"","court":to}

# --- Renaming (game-design §4.12) --------------------------------------------------------------------

static func rename(state,id: String,new_name: String) -> bool:
 var c = get_char(state,id)
 new_name = new_name.strip_edges()
 if c.is_empty() or new_name == "" or new_name.length()>32: return false
 c.name = new_name
 if str(c.army) != "" and state.army_state.has(c.army): state.army_state[c.army].commander.name = full_name(c)
 return true

# --- Careers (game-design §4.3; the player picks in the formative years) -----------------------------

static func choose_career(state,id: String,career: String) -> Dictionary:
 var c = get_char(state,id)
 if c.is_empty() or not data().careers.has(career): return {"ok":false,"reason":"Unknown career"}
 if str(c.career) != "": return {"ok":false,"reason":"Already chosen"}
 if float(c.age)<float(data().aging.child_until): return {"ok":false,"reason":"Too young"}
 c.career = career
 c.career_pending = false
 history(state,c,"Chose the path of the %s." % data().careers[career].name)
 return {"ok":true}

# Characters in the formative years whose career is not chosen yet (the player's notification).
static func careers_pending(state,faction: String) -> Array:
 return members(state,faction).filter(func(id): return state.characters[id].career_pending)

# --- Absorbed families (game-design §4.10) ----------------------------------------------------------

# When a faction falls to `by` (conquest or surrender): "court" (the family enters by's court, low
# loyalty), "vassal" (handled by core/vassals.gd: the family keeps its lands) or "remove" with a
# method ("exile", "imprison", "execute": reputation and loyalty effects).
static func absorb_family(state,by: String,fallen: String,choice: String,method := "exile") -> Dictionary:
 var Rep = load("res://core/reputation.gd")
 var ids = members(state,fallen)
 match choice:
  "court":
   for id in ids:
    var c = state.characters[id]
    court(state,fallen).members.erase(id)
    c.faction = by
    c.role = "courtier"
    c.loyalty = int(data().loyalty.absorbed_start)
    c.loyalty_log = [{"turn":int(state.turn),"delta":0,"reason":"Joined after the fall of their house"}]
    court(state,by).members.append(id)
    history(state,c,"Entered the court of %s after the fall of their house." % WorldMap.faction(by).name)
   state.courts[fallen] = {"ruler":"","heir":"","members":[]}
   return {"ok":true,"moved":ids.size()}
  "remove":
   var r = ruler(state,by)
   for id in ids:
    var c = state.characters[id]
    match method:
     "execute":
      die(state,id,"execution")
      if r != "": deed(state,r,"executions")
     "imprison": c.role = "prisoner:"+by
     _: c.role = "exile"
   Rep.deed(state,by,{"execute":"executed","imprison":"imprisoned"}.get(method,"exiled"),"%s the family of %s" % [{"execute":"Executed","imprison":"Imprisoned"}.get(method,"Exiled"),WorldMap.faction(fallen).name],float(maxi(1,ids.size()))*0.5)
   return {"ok":true,"removed":ids.size()}
 return {"ok":false,"reason":"Unknown choice"}

# --- Yearly processing ----------------------------------------------------------------------------

# Aging, careers, births, courtiers joining, xp, loyalty drift, defeated immortals returning, rulers'
# years. Returns notable events [{faction, kind, character, text}].
static func end_turn(state) -> Array:
 var events = []
 var ag = data().aging
 var ids = state.characters.keys()
 ids.sort_custom(func(a,b): return int(a.substr(1))<int(b.substr(1)))
 for id in ids:
  var c = state.characters[id]
  if c.dead: continue
  if int(c.defeated_until)>=0 and int(state.turn)>=int(c.defeated_until):
   c.defeated_until = -1
   history(state,c,"Returned.")
   events.append({"faction":c.faction,"kind":"returned","character":id,"text":"%s has returned." % full_name(c)})
  var a = float(c.age)
  if a<float(ag.child_until): c.age = minf(a+float(ag.child_years_per_turn),float(ag.child_until))
  elif a<float(ag.prime): c.age = a+1.0
  if float(c.age)>=float(ag.child_until) and str(c.career) == "" and not c.career_pending:
   c.career_pending = true
   events.append({"faction":c.faction,"kind":"career","character":id,"text":"%s is old enough to choose a path." % c.name})
  # The career must be chosen by the end of the formative years: the AI (and a player who waited) picks then.
  if c.career_pending and (float(c.age)>=float(ag.formative_until) or c.faction != state.player_faction): _auto_career(state,c)
  if float(c.age)>=float(ag.formative_until) and a<float(ag.formative_until): _upbringing(state,c)
  if is_adult(c):
   gain_xp(state,id,float(data().xp.per_turn))
   c.since_favour = int(c.since_favour)+1
   if ruler(state,c.faction) == id:
    c.deeds.years_ruled = int(c.deeds.get("years_ruled",0))+1
    if int(state.treasury.get(c.faction,0))>10000: c.deeds.wealth = int(c.deeds.get("wealth",0))+1
    check_epithet(state,c)
   if str(c.role).begins_with("governor:"):
    c.deeds.turns_governing = int(c.deeds.get("turns_governing",0))+1
    check_traits(state,c)
 for f in state.courts.keys():
  if not state.treasury.has(f) or state.settlements_of(f).is_empty(): continue
  events.append_array(_births(state,f))
  events.append_array(_courtiers(state,f))
  _loyalty_drift(state,f)
 return events

static func _auto_career(state,c: Dictionary):
 var r = rng_for(state,["career",c.id])
 var keys = data().careers.keys()
 # Most children of a house become generals or politicians; the rest spread over the careers.
 var pick = "general" if r.randf()<0.4 else ("politician" if r.randf()<0.3 else keys[r.randi_range(0,keys.size()-1)])
 c.career = pick
 c.career_pending = false
 history(state,c,"Took the path of the %s." % data().careers[pick].name)

static func _upbringing(state,c: Dictionary):
 var r = rng_for(state,["upbringing",c.id])
 for t in trait_data().traits:
  var td = trait_data().traits[t]
  if td.kind != "personality" or not td.get("earned_by",{}).is_empty() and t in ["craven","cruel","merciful","deceitful"]: continue
  if c.traits.size()>=3: break
  if r.randf()<float(trait_data().upbringing_chance)*0.25: add_trait(state,c,t)

static func _births(state,f: String) -> Array:
 var out = []
 var b = data().births
 var ids = members(state,f)
 if ids.size()>=int(b.get("max_court",9999)): return out
 for id in ids:
  if out.size()+ids.size()>=int(b.get("max_court",9999)): break
  var c = state.characters[id]
  if c.gender != "m" or str(c.spouse) == "" or not is_adult(c): continue
  var w = get_char(state,c.spouse)
  if w.is_empty() or w.dead or not is_adult(w) or float(w.age)>float(b.mother_until): continue
  var together = c.children.filter(func(k): return k in w.children).size()
  if together>=int(b.max_children): continue
  var r = rng_for(state,["birth",id])
  if r.randf()>=float(b.chance): continue
  var g = "m" if r.randf()<0.5 else "f"
  var kid = new_character(state,c.faction,{"name":_given(c.culture,g,r),"house":c.house,"race":c.race,"culture":c.culture,"gender":g,"age":0.0,"father":c.id,"mother":w.id,"loyalty":int(data().loyalty.start)+10,"role":"child"})
  c.children.append(kid)
  w.children.append(kid)
  history(state,state.characters[kid],"Born to %s and %s." % [full_name(c),full_name(w)])
  out.append({"faction":c.faction,"kind":"birth","character":kid,"text":"A child, %s, is born to %s." % [state.characters[kid].name,full_name(c)]})
 return out

static func _courtiers(state,f: String) -> Array:
 var cd = data().courtiers
 if members(state,f).size()>=int(cd.max_members): return []
 var lv = load("res://core/realm_standing.gd").level(state,f)
 var r = rng_for(state,["courtier",f])
 if r.randf()>=float(cd.chance_per_level)*lv: return []
 var cul = str(WorldMap.faction(f).get("culture","medieval"))
 var g = "m" if r.randf()<0.6 else "f"
 var houses = _names().get("cultures",{}).get(cul,{}).get("houses",["Ashby","Morrow","Vell"])
 var id = new_character(state,f,{"name":_given(cul,g,r),"house":str(houses[r.randi_range(0,houses.size()-1)]),"gender":g,"age":float(r.randi_range(18,34)),"loyalty":int(cd.get("start",data().loyalty.courtier_start)) if cd.has("start") else int(data().loyalty.courtier_start),"career":data().careers.keys()[r.randi_range(0,data().careers.size()-1)],"xp":xp_for_level(r.randi_range(1,3))})
 _sync_level(state,state.characters[id])
 history(state,state.characters[id],"Asked to join the court of %s." % WorldMap.faction(f).name)
 return [{"faction":f,"kind":"courtier","character":id,"text":"%s asks to join your court." % full_name(state.characters[id])}]

# Neglect and favouritism (game-design §4.6), and a slow drift toward drift_to otherwise.
static func _loyalty_drift(state,f: String):
 var ld = data().loyalty
 var ids = members(state,f)
 var roles = {}
 var held = 0
 for id in ids:
  var c = state.characters[id]
  if str(c.role) in ["courtier","child",""] or id == ruler(state,f): continue
  held += 1
  var b = branch(state,f,id)
  if b != "": roles[b] = int(roles.get(b,0))+1
 var favoured = ""
 for b in roles:
  if held>=3 and float(roles[b])/held>=float(ld.favouritism_share): favoured = b
 for id in ids:
  var c = state.characters[id]
  if id == ruler(state,f) or not is_adult(c): continue
  if int(c.since_favour)>=int(ld.neglect_after) and str(c.role) == "courtier": change_loyalty(state,id,-int(ld.neglect_loss),"Neglected: no role, title or gift for years")
  elif favoured != "" and branch(state,f,id) != favoured and branch(state,f,id) != "": change_loyalty(state,id,-int(ld.favouritism_loss),"Resents the favour shown to %s's branch" % state.characters[favoured].name)
  elif int(c.loyalty)<int(ld.drift_to) and int(c.since_favour)<int(ld.neglect_after): change_loyalty(state,id,1,"Settling into the court")

# --- Seeding at campaign start -----------------------------------------------------------------------

# Every faction's court: its founder or ruling lord (the general of its first army), a spouse,
# children, siblings and courtiers. Legendary founders (playable) and the rulers of major factions are
# immortal from the start (game-design §4.5).
static func init(state):
 state.characters = {}
 state.courts = {}
 state.next_character = 1
 var fd = data().family
 for f in state.factions():
  if state.settlements_of(f).is_empty(): continue
  var fac = WorldMap.faction(f)
  var cul = str(fac.get("culture","medieval"))
  var house = str(fac.get("house",fac.get("name","")))
  var r = RandomNumberGenerator.new()
  r.seed = hash([state.seed,"court",f])
  var armies = state.armies_of(f)
  var gen_name = ""
  if not armies.is_empty(): gen_name = str(state.army_state[armies[0]].commander.name)
  var founder = data().founders.get(f,{})
  var ruler_fields = {"gender":"m","age":float(founder.get("age",r.randi_range(32,52))),"career":str(founder.get("career","general")),"role":"ruler"}
  if not founder.is_empty():
   ruler_fields.name = founder.name
   ruler_fields.house = founder.house
   ruler_fields.epithet = founder.epithet
   ruler_fields.legendary = true
   ruler_fields.immortal = true
   ruler_fields.xp = xp_for_level(int(founder.level))
  else:
   ruler_fields.name = gen_name.split(" ")[0] if gen_name != "" else _given(cul,"m",r)
   ruler_fields.legendary = str(fac.get("kind","")) == "major"
   ruler_fields.immortal = ruler_fields.legendary
   ruler_fields.xp = xp_for_level(r.randi_range(2,5))
  var rid = new_character(state,f,ruler_fields)
  var rc = state.characters[rid]
  _sync_level(state,rc)
  for t in founder.get("traits",[]): add_trait(state,rc,t)
  if founder.is_empty(): _upbringing(state,rc)
  if rc.immortal: rc.traits.immortal = 1
  court(state,f).ruler = rid
  # The ruler leads the first army (generals are court members; game-design §4.3).
  if not armies.is_empty():
   var cmd = state.army_state[armies[0]].commander
   cmd.character = rid
   cmd.name = full_name(rc)
   rc.army = armies[0]
   _sync_level(state,rc)
  var minor = str(fac.get("kind","")) == "minor" or str(fac.get("kind","")) == "generated"
  # Spouse and children.
  var sp = new_character(state,f,{"name":_given(cul,"f",r),"house":house,"gender":"f","age":float(maxi(18,int(rc.age)-r.randi_range(2,10))),"spouse":rid,"loyalty":int(data().loyalty.spouse_start)+15,"career":"politician"})
  rc.spouse = sp
  var nk = r.randi_range(int(fd.children_min),int(fd.children_max))
  for i in nk:
   var g = "m" if r.randf()<0.55 else "f"
   var age = float(r.randi_range(1,17))
   var kid = new_character(state,f,{"name":_given(cul,g,r),"house":rc.house,"gender":g,"age":age,"father":rid,"mother":sp,"loyalty":int(data().loyalty.start)+10,"role":"child" if age<16.0 else "courtier"})
   rc.children.append(kid)
   state.characters[sp].children.append(kid)
   var kc = state.characters[kid]
   if age>=float(data().aging.child_until):
    _auto_career(state,kc)
    if age>=16.0: _upbringing(state,kc)
  # Siblings and courtiers (fewer for minor houses).
  for i in r.randi_range(int(fd.siblings_min),int(fd.siblings_max)-(1 if minor else 0)):
   var g = "m" if r.randf()<0.6 else "f"
   var sid = new_character(state,f,{"name":_given(cul,g,r),"house":rc.house,"gender":g,"age":float(r.randi_range(24,40)),"career":data().careers.keys()[r.randi_range(0,7)],"xp":xp_for_level(r.randi_range(1,4))})
   _sync_level(state,state.characters[sid])
   _upbringing(state,state.characters[sid])
  if not minor:
   for i in r.randi_range(int(fd.courtiers_min),int(fd.courtiers_max)):
    var g = "m" if r.randf()<0.65 else "f"
    var houses = _names().get("cultures",{}).get(cul,{}).get("houses",["Ashby","Morrow","Vell"])
    var cid = new_character(state,f,{"name":_given(cul,g,r),"house":str(houses[r.randi_range(0,houses.size()-1)]),"gender":g,"age":float(r.randi_range(22,40)),"loyalty":int(data().loyalty.courtier_start)+10,"career":data().careers.keys()[r.randi_range(0,7)],"xp":xp_for_level(r.randi_range(1,4))})
    _sync_level(state,state.characters[cid])
  _auto_heir(state,f)
  # Other armies' generals join the court too.
  for k in range(1,armies.size()):
   var cmd = state.army_state[armies[k]].commander
   var gid = new_character(state,f,{"name":str(cmd.name).split(" ")[0],"house":house,"gender":"m","age":float(r.randi_range(24,44)),"career":"general","army":armies[k],"role":"general:"+armies[k]})
   cmd.character = gid
   cmd.name = full_name(state.characters[gid])
  for id in members(state,f): state.characters[id].loyalty_log = []

# --- Battles, captures and fallen houses -----------------------------------------------------------

# A leaderless army gets a general from the court (the best idle adult, or a lesser noble who joins).
static func promote_captain(state,army_id: String):
 var a = state.army_state[army_id]
 var Armies = load("res://core/armies.gd")
 var cands = Armies.general_candidates(state,a.faction)
 var cid = cands[0] if not cands.is_empty() else ""
 if cid == "":
  var parts = str(a.commander.name).split(" ")
  cid = new_character(state,a.faction,{"name":parts[parts.size()-2] if parts.size()>1 else parts[0],"gender":"m","age":28.0,"career":"general","loyalty":int(data().loyalty.courtier_start)})
 var c = state.characters[cid]
 c.army = army_id
 set_role(state,cid,"general:"+army_id)
 a.commander.character = cid
 a.commander.name = full_name(c)
 a.commander.rank = maxi(int(a.commander.get("rank",1)),int(c.level))

# After a battle (core/battles.gd aftermath): deeds and traits for the generals, deaths in battle,
# reputation, and a fallen house's family (game-design §4.10).
static func on_battle(state,pb: Dictionary,out: Dictionary):
 var Rep = load("res://core/reputation.gd")
 for dd in out.deeds:
  var id = str(dd.character)
  if dd.won:
   deed(state,id,"battles_won",1,150.0)
   if dd.stronger: deed(state,id,"battles_won_stronger")
   if dd.desperate: deed(state,id,"desperate_defenses")
   if pb.kind == "settlement" and str(pb.get("settlement","")) == "wardens_gate" and out.winner == dd.faction: deed(state,id,"wall_defenses")
  else: deed(state,id,"battles_lost",1,40.0)
 for g in out.generals:
  if g.fate == "killed" and str(g.get("character","")) != "":
   var c = get_char(state,g.character)
   if not c.is_empty():
    c.army = ""
    if not c.immortal: c.role = "courtier"
    die(state,g.character,"battle")
 # Armies destroyed with their general: the general falls with them (an immortal returns).
 for d in out.destroyed_armies:
  for id in state.characters:
   var c = state.characters[id]
   if str(c.army) == str(d.army):
    c.army = ""
    c.role = "courtier"
    die(state,id,"battle")
 Rep.deed(state,out.winner,"won_battle","Won a battle against %s" % WorldMap.faction(out.loser).name,0.5)
 var sid = str(out.captured)
 if sid == "": return
 var att = str(pb.attacker.faction)
 var home = str(WorldMap.region(sid).get("owner",""))
 var name = WorldMap.region(sid).settlement.name
 var gid = str(state.army_state.get(pb.attacker.army,{}).get("commander",{}).get("character",""))
 for id in [gid,ruler(state,att)]:
  if id == "": continue
  deed(state,id,"settlements_taken",1,60.0)
  if load("res://core/ai.gd").walled(state,sid): deed(state,id,"walled_taken")
 if home == att:
  Rep.deed(state,att,"liberated","Took back %s" % name)
  for id in [gid,ruler(state,att)]:
   if id != "": deed(state,id,"liberations")
 else: Rep.deed(state,att,"took_settlement","Took %s" % name)
 # The defender's last settlement: its house falls. The player chooses (court, vassal or removal);
 # the AI keeps the family as a vassal when the cap allows, else takes it into its court.
 var fallen = str(pb.defender.faction)
 if fallen == "" or not state.settlements_of(fallen).is_empty() or fallen == state.player_faction: return
 if members(state,fallen).is_empty(): return
 if att == state.player_faction:
  state.absorptions.append({"fallen":fallen,"settlement":sid,"turn":int(state.turn)})
  return
 resolve_absorption(state,att,fallen,sid,"vassal" if _vassal_fits(state,att,fallen,sid) else "court")

static func _vassal_fits(state,by: String,fallen: String,sid: String) -> bool:
 var V = load("res://core/vassals.gd")
 return V.liege_of(state,by) == "" and not bool(WorldMap.faction(fallen).get("untouchable",false))

# The choice for a fallen house: "vassal" (the family keeps the settlement and swears fealty), "court"
# (it enters the conqueror's court), or "exile" / "imprison" / "execute" (removed, with reputation).
static func resolve_absorption(state,by: String,fallen: String,sid: String,choice: String) -> Dictionary:
 state.absorptions = state.absorptions.filter(func(a): return a.fallen != fallen)
 match choice:
  "vassal":
   if str(state.settlements.get(sid,{}).get("owner","")) == by:
    state.settlements[sid].owner = fallen
    load("res://core/buildings.gd").refresh(state,sid)
    for id in load("res://core/movement.gd").garrison_of(state,sid):
     if state.army_state[id].faction == by: state.army_state[id].garrison = ""
    if fallen in state.destroyed: state.destroyed.erase(fallen)
    state.grace.erase(fallen)
   load("res://core/vassals.gd").swear(state,fallen,by,"conquest")
   load("res://core/reputation.gd").deed(state,by,"spared","Left the family of %s in power as vassals" % WorldMap.faction(fallen).name)
   return {"ok":true}
  "court": return absorb_family(state,by,fallen,"court")
  "exile","imprison","execute": return absorb_family(state,by,fallen,"remove",choice)
 return {"ok":false,"reason":"Unknown choice"}

# --- Skills (the career's tree; docs/v1-content.md §2.4) ---------------------------------------------

static func career_rows(c: Dictionary) -> Array:
 var Characters = load("res://core/characters.gd")
 var career = str(c.career) if Characters.data().careers.has(str(c.career)) else "general"
 return Characters.rows(career)

# A court character's skills as the skill tree helper reads them ({rank, skills}).
static func _skill_view(c: Dictionary) -> Dictionary:
 return {"rank":int(c.level),"skills":c.skills}

static func can_take_skill(c: Dictionary,skill_id: String) -> Dictionary:
 var Characters = load("res://core/characters.gd")
 return Characters.can_take(_skill_view(c),skill_id,str(c.career) if Characters.data().careers.has(str(c.career)) else "general")

static func take_skill(state,id: String,skill_id: String) -> bool:
 var c = get_char(state,id)
 if c.is_empty() or not can_take_skill(c,skill_id).ok: return false
 c.skills.append(skill_id)
 return true

# The AI (and auto-allocation) spend a character's points row by row.
static func auto_skills(state,id: String):
 var c = get_char(state,id)
 var guard = 0
 while skill_points(c)>0 and guard<40:
  guard += 1
  var took = false
  for r in career_rows(c):
   for s in r.skills:
    if can_take_skill(c,s.id).ok:
     c.skills.append(s.id)
     took = true
     break
   if took: break
  if not took: return
