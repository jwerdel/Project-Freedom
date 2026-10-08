extends RefCounted
# Regional markets (war-and-realm §7.2; owner spec 2026-10-07, Part B; data/resources.json
# "markets"): buy or sell food, wood and stone for gold. Prices: base x scarcity (your stock against
# your need) x biome (your capital's land: wood dear in the desert, food dear in the snowy north) x
# season (food dear in winter, in a dry season). Readable, not a full dynamic economy. The AI buys to
# cover shortages and stockpiles food before winter (ai_turn).

const Resources = preload("res://core/resources.gd")
const WorldMap = preload("res://core/world_map.gd")

static func cfg() -> Dictionary:
 return Resources.data().markets

# A faction's need of a resource per turn (what scarcity is measured against).
static func need(state,f: String,kind: String) -> float:
 if kind == "food": return maxf(20.0,Resources.consumption(state,f))
 return maxf(40.0,float(state.settlements_of(f).size())*30.0)

# The climate of a faction's capital region (for the biome factor).
static func biome(state,f: String) -> String:
 var cap = load("res://core/armies.gd").capital(state,f)
 if cap == "": return ""
 return str(WorldMap.region(cap).get("climate",""))

# The buy price of one unit and its parts: {price, base, scarcity, biome, season}.
static func price(state,f: String,kind: String) -> Dictionary:
 var c = cfg()
 var base = float(c.base[kind])
 var turns = float(Resources.amount(state,f,kind))/need(state,f,kind)
 var t = clampf((turns-float(c.scarce_turns))/maxf(0.01,float(c.plenty_turns)-float(c.scarce_turns)),0.0,1.0)
 var scarcity = lerpf(float(c.scarcity[0]),float(c.scarcity[1]),t)
 var bio = float(c.biome.get(biome(state,f),{}).get(kind,1.0))
 var Seasons = load("res://core/seasons.gd")
 var s = Seasons.at(state)
 var season_key = s.kind
 var cap = load("res://core/armies.gd").capital(state,f)
 if s.kind == "winter" and cap != "" and Seasons.dry_land(cap): season_key = "dry"
 var sea = float(c.season.get(season_key,{}).get(kind,1.0))
 return {"price":base*scarcity*bio*sea,"base":base,"scarcity":scarcity,"biome":bio,"season":sea}

static func buy_cost(state,f: String,kind: String,qty: int) -> int:
 return int(ceil(float(price(state,f,kind).price)*qty))

static func sell_value(state,f: String,kind: String,qty: int) -> int:
 return int(floor(float(price(state,f,kind).price)*float(cfg().sell_share)*qty))

static func buy(state,f: String,kind: String,qty: int) -> Dictionary:
 if not kind in Resources.KINDS or qty<=0: return {"ok":false,"reason":"Nothing to buy"}
 var cost = buy_cost(state,f,kind,qty)
 if int(state.treasury.get(f,0))<cost: return {"ok":false,"reason":"Not enough gold (%d needed)" % cost}
 state.treasury[f] = int(state.treasury[f])-cost
 Resources.add(state,f,kind,qty)
 return {"ok":true,"gold":cost}

static func sell(state,f: String,kind: String,qty: int) -> Dictionary:
 if not kind in Resources.KINDS or qty<=0: return {"ok":false,"reason":"Nothing to sell"}
 if Resources.amount(state,f,kind)<qty: return {"ok":false,"reason":"Not enough %s" % kind}
 var gold = sell_value(state,f,kind,qty)
 Resources.add(state,f,kind,-qty)
 state.treasury[f] = int(state.treasury.get(f,0))+gold
 return {"ok":true,"gold":gold}

# The AI's market turn: cover a food shortage within three turns, stockpile food for a forecast winter,
# and buy wood or stone it lacks for building. Spends at most spend_share of its treasury.
# Returns the trades [{faction, kind, qty, gold, why}].
const SPEND_SHARE = 0.35
static func ai_turn(state,f: String) -> Array:
 var out = []
 var budget = int(float(maxi(0,int(state.treasury.get(f,0))))*SPEND_SHARE)
 if budget<=0: return out
 var l = Resources.ledger(state,f)
 var Seasons = load("res://core/seasons.gd")
 var want_food = 0
 var food = Resources.amount(state,f,"food")
 if int(l.food.net)<0 and food+int(l.food.net)*3<0: want_food = -int(l.food.net)*3-food
 var nw = Seasons.next_winter(state)
 if not nw.is_empty() and int(nw.start)-int(state.turn)<=int(nw.get("forecast",3)):
  # Before winter: enough to eat through it at a winter's (lower) production.
  var winter_need = int(ceil(need(state,f,"food")*float(nw.length)*0.6))
  want_food = maxi(want_food,winter_need-food)
 if want_food>0:
  var qty = mini(want_food,int(floor(budget/maxf(0.01,float(price(state,f,"food").price)))))
  if qty>=10:
   var r = buy(state,f,"food",qty)
   if r.ok:
    out.append({"faction":f,"kind":"food","qty":qty,"gold":r.gold,"why":"winter" if not nw.is_empty() and int(nw.start)-int(state.turn)<=3 else "shortage"})
    budget -= int(r.gold)
 for k in ["wood","stone"]:
  if Resources.amount(state,f,k)<60 and budget>200:
   var qty = mini(120,int(floor(float(budget)*0.4/maxf(0.01,float(price(state,f,k).price)))))
   if qty>=20:
    var r = buy(state,f,k,qty)
    if r.ok:
     out.append({"faction":f,"kind":k,"qty":qty,"gold":r.gold,"why":"building"})
     budget -= int(r.gold)
 return out
