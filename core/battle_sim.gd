extends RefCounted
# Battle simulation (docs/battle-design.md sections 3-5): deterministic, seeded, tick-based, no
# animation. Pure function: simulate(setup) -> result. Every number comes from data/battle.json and
# the unit battle stats in data/units/*.json; there is no scenario-specific code.
#
# setup = {seed, lanes?, field: {terrain: [lane][band 0..5 from the attacker side], weather?,
#          walls?: {defense, siege_turns, gates: [lane]}},
#          sides: [attacker, defender], each {faction, general: {name, rank, traits}, general_lane?,
#          units: [{unit, men, max_men?, rank?, lane, line: front|back|reserve, order, protect?,
#          arrive_tick?, army?, index?}]}}
# Orders: hold, aggressive, flank, protect, reserve.
# result = {winner (0 attacker, 1 defender), outcome, ticks, weather, sides: [{units: [...],
#          general: {...}}], events: [{tick, tag, side, unit, target, lane, ...}], causes, replay: [tick 0..ticks][sim unit] = [lane, y, state, men], roster: [sim unit] = {side, unit, general, row}}

const UnitTypes = preload("res://core/unit_types.gd")
const DATA = "res://data/battle.json"
# Unit states, orders and categories as integers (fast comparisons in the inner loops).
# Order matters: on the field = state <= S_ENGAGED; still in the battle = state <= S_PENDING.
enum {S_READY,S_ENGAGED,S_RESERVE,S_FLANKING,S_WAITING,S_PENDING,S_AWAY,S_ROUTED,S_FLED,S_DESTROYED}
enum {O_HOLD,O_AGGRESSIVE,O_FLANK,O_PROTECT,O_RESERVE}
enum {C_INFANTRY,C_MISSILE,C_CAVALRY,C_LORD}
const ORDER_IDS = {"hold":O_HOLD,"aggressive":O_AGGRESSIVE,"flank":O_FLANK,"protect":O_PROTECT,"reserve":O_RESERVE}
const CAT_IDS = {"infantry":C_INFANTRY,"missile":C_MISSILE,"cavalry":C_CAVALRY,"lord":C_LORD}
const HOLDING = [O_HOLD,O_PROTECT]
const STANDING = [S_READY,S_ENGAGED,S_PENDING,S_AWAY]
const ALIVE = [S_READY,S_ENGAGED,S_RESERVE,S_FLANKING,S_WAITING,S_PENDING]
const OFF_FIELD = [S_RESERVE,S_FLANKING,S_WAITING,S_PENDING,S_AWAY]
const GONE = [S_ROUTED,S_FLED]

static var _data = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("combat"),"Invalid "+DATA)
 return _data

static func reset():
 _data = null

static func roll_weather(seed: int) -> String:
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([seed,"weather"])
 var r = rng.randf()
 for w in data().weather.chances:
  r -= float(data().weather.chances[w])
  if r<0: return w
 return "clear"

# --- Battle state ------------------------------------------------------------------

# One unit on the battlefield (typed for speed; the simulation runs many battles per second).
class Unit:
 var side := 0
 var unit := ""
 var cat := C_INFANTRY
 var st: Dictionary
 var men := 0.0
 var start_men := 0.0
 var max_men := 0.0
 var rank := 0
 var lane := 0
 var y := 0.0
 var order := O_HOLD
 var protect := -1
 var state := S_READY
 var target := -1
 var morale := 0.0
 var start_morale := 0.0
 var ammo := 0
 var kills := 0.0
 var lost_tick := 0.0
 var charging := false
 var rear := false
 var contact := 0
 var eta := 0
 var wait := 0
 var fought := false
 var fired := false
 var is_general := false
 var traits: Array = []
 var src := -1
 var army := ""
 var arrive := 0
 var wall_ticks := 0
 var off_field := 0
 var charge_extra := 0.0
 var speed := 0.0
 var attack := 0.0
 var defence := 0.0
 var charge := 0.0
 var armour := 0.0
 var ap := 0.0
 var shield := 0.0
 var vs_cav := 0.0
 var brace := false
 var missile := false

class Battle:
 var d: Dictionary
 var rng := RandomNumberGenerator.new()
 var lanes := 5
 var nbands := 6
 var terrain: Array
 var weather := "clear"
 var walls = null
 var u: Array = []          # unit runtime records (dictionaries), fixed order
 var generals := [-1,-1]    # index of each side's general in u
 var t := 0
 var events: Array = []
 var causes := {}           # cause tag -> impact (men lost or morale), per side: "tag:side"
 var replay: Array = []
 var general_lost := [false,false]
 var broken := [false,false]
 var reserve_used := [0,0]
 var fog_hides := false
 var back_y := [0.0,0.0]
 var contact := 0.6
 # Cached constants (data/battle.json), read in the inner loops.
 var melee_kill := 0.0
 var hit_base := 0.0
 var hit_per_point := 0.0
 var hit_min := 0.0
 var hit_max := 0.0
 var missile_rate := 0.0
 var missile_acc := 0.0
 var etf := 0.0
 var per_pct := 0.0
 var waver_below := 0.0
 var waver_factor := 0.0
 var winning := 0.0
 var destroyed_at := 0.0
 var rank_att := 0.0
 var rank_def := 0.0
 var front_scale := 1.0
 var lane_units: Array = [] # [side][lane] -> indices of units on the field, in unit order
 var fast := false # skip replay frames and events (harness and odds estimates)
 var vis := PackedByteArray() # per unit, snapshot at the start of each tick: 1 = the enemy can see it
 # Per lane and band (precomputed from the terrain): frontage, speed, forest, hills.
 var t_front: Array = []
 var t_speed: Array = []
 var t_forest: Array = []
 var t_hills: Array = []
 var t_pass: Array = []

 func band(y: float) -> int:
  return clampi(int(round(y))-1,0,nbands-1)

 func forest(lane: int,y: float) -> bool:
  return t_forest[lane][band(y)]

 func hills(lane: int,y: float) -> bool:
  return t_hills[lane][band(y)]

 func bands() -> int:
  return int(d.field.bands)

 func terrain_at(lane: int,y: float) -> String:
  var b = clampi(int(round(y))-1,0,nbands-1)
  return terrain[lane][b]

 func lane_closed(lane: int) -> bool:
  for b in terrain[lane]:
   if b != "closed": return false
  return true

 func ev(tag: String,side: int,unit: int,extra := {}):
  if fast: return
  var e = {"tick":t,"tag":tag,"side":side,"unit":unit}
  e.merge(extra)
  events.append(e)

 func cause(tag: String,side: int,amount: float):
  if not causes.has(tag): causes[tag] = [0.0,0.0]
  causes[tag][side] += amount

 func noise() -> float:
  var n = float(d.combat.noise)
  return 1.0+rng.randf_range(-n,n)

 func on_field(i: int) -> bool:
  var s = u[i].state
  return s == S_READY or s == S_ENGAGED

 func alive(i: int) -> bool:
  return u[i].state in ALIVE

 func enemy(side: int) -> int:
  return 1-side

static func simulate(setup: Dictionary) -> Dictionary:
 var b = Battle.new()
 b.d = data()
 b.rng.seed = int(setup.seed)
 b.lanes = int(setup.get("lanes",b.d.field.lanes))
 b.terrain = setup.field.terrain
 b.nbands = int(b.d.field.bands)
 for l in b.lanes:
  var fr = []
  var sp = []
  var fo = []
  var hi = []
  var pa = []
  for ter in b.terrain[l]:
   pa.append(ter == "pass")
   fr.append(float(b.d.field.frontage[ter]))
   sp.append(float(b.d.terrain.speed[ter]))
   fo.append(ter == "forest")
   hi.append(ter == "hills")
  b.t_front.append(fr)
  b.t_speed.append(sp)
  b.t_forest.append(fo)
  b.t_hills.append(hi)
  b.t_pass.append(pa)
 assert(b.terrain.size() == b.lanes,"terrain must have one column per lane")
 b.weather = setup.field.get("weather",roll_weather(int(setup.seed)))
 b.walls = setup.field.get("walls",null)
 b.fast = bool(setup.get("fast",false))
 b.fog_hides = b.weather == "fog" and bool(b.d.weather.fog_hides_back_line)
 b.back_y = [float(b.d.field.back_y[0]),float(b.d.field.back_y[1])]
 b.contact = float(b.d.field.contact_distance)
 var cb = b.d.combat
 b.melee_kill = float(cb.melee_kill)
 b.hit_base = float(cb.hit_base)
 b.hit_per_point = float(cb.hit_per_point)
 b.hit_min = float(cb.hit_min)
 b.hit_max = float(cb.hit_max)
 b.missile_rate = float(cb.missile_rate)
 b.missile_acc = float(cb.missile_accuracy)
 b.etf = float(cb.engaged_target_factor)
 b.per_pct = float(b.d.morale.per_percent_lost)
 b.waver_below = float(b.d.morale.waver_below)
 b.waver_factor = float(b.d.morale.waver_attack_factor)
 b.winning = float(b.d.morale.winning)
 b.destroyed_at = float(cb.destroyed_at_loss)
 b.rank_att = float(b.d.experience.rank_attack)
 b.rank_def = float(b.d.experience.rank_defence)
 b.front_scale = float(b.d.field.frontage_lane_scale.get(str(b.lanes),1.0))
 _deploy(b,setup)
 _record(b) # replay[0] is the deployment; replay[t] is the field after tick t
 var winner = -1
 var outcome = "defender_holds"
 for tick in range(1,int(b.d.combat.max_ticks)+1):
  b.t = tick
  _arrivals(b)
  _bucket(b)
  _missiles(b)
  _movement(b)
  _flank_arrivals(b)
  _towers(b)
  _melee(b)
  _morale(b)
  _army_break(b)
  _pursuit(b)
  _record(b)
  # A side is beaten when none of its regular units can fight on (its general alone does not hold the field).
  var standing = [false,false]
  for i in b.u.size():
   if (b.u[i].state <= S_PENDING) and not b.u[i].is_general: standing[b.u[i].side] = true
  if not standing[0] or not standing[1]:
   winner = 0 if standing[0] else 1
   outcome = "victory"
   break
 if winner == -1: winner = 1
 return _result(b,winner,outcome,setup)

# --- Setup --------------------------------------------------------------------------

static func _deploy(b: Battle,setup: Dictionary):
 var f = b.d.field
 for side in 2:
  var s = setup.sides[side]
  var g = s.get("general",{"name":"","rank":1,"traits":[]})
  var traits = g.get("traits",[])
  var aura_lane = int(s.get("general_lane",b.lanes/2))
  var list = s.units.duplicate(true)
  # The general fights as a single elite entity (decision 14).
  list.append({"unit":"commander","men":0,"lane":aura_lane,"line":"back","order":"hold","is_general":true})
  for e in list:
   var ut = UnitTypes.get_type(e.unit)
   var st = ut.battle
   var is_general = e.get("is_general",false)
   var men = float(st.get("hp",1))*float(b.d.combat.general_hp_scale) if is_general else float(e.men)
   var rank = int(g.get("rank",1)) if is_general else int(e.get("rank",0))
   var line = e.get("line","front")
   var order = ORDER_IDS[e.get("order","hold")]
   if line == "reserve": order = O_RESERVE
   var y = float(f.reserve_y[side]) if order == O_RESERVE else float(f.front_y[side] if line == "front" else f.back_y[side])
   var rec = Unit.new()
   rec.side = side
   rec.unit = e.unit
   rec.cat = CAT_IDS[ut.category]
   rec.st = st
   rec.men = men
   rec.start_men = men
   rec.max_men = float(e.get("max_men",men))
   rec.rank = rank
   rec.lane = int(e.get("lane",b.lanes/2))
   rec.y = y
   rec.order = order
   rec.protect = int(e.get("protect",-1))
   rec.ammo = int(st.missile.volleys) if st.missile != null else 0
   rec.is_general = is_general
   rec.traits = traits
   rec.src = int(e.get("index",-1))
   rec.army = str(e.get("army",""))
   rec.arrive = int(e.get("arrive_tick",0))
   rec.speed = float(st.speed)
   rec.attack = float(st.melee_attack)
   rec.defence = float(st.melee_defence)
   rec.charge = float(st.charge)
   rec.armour = float(st.armour)
   rec.ap = float(st.ap)
   rec.shield = float(st.shield)
   rec.vs_cav = float(st.bonus_vs_cavalry)
   rec.brace = bool(st.brace)
   rec.missile = st.missile != null
   if order == O_RESERVE: rec.state = S_RESERVE
   if rec.arrive>0: rec.state = S_WAITING
   if is_general: b.generals[side] = b.u.size()
   b.u.append(rec)
  for i in b.u.size():
   var r: Unit = b.u[i]
   if r.side != side: continue
   var m = float(r.st.morale)+r.rank*float(b.d.experience.rank_morale)
   if absi(r.lane-aura_lane)<=int(b.d.morale.general_aura_lanes): m += int(g.get("rank",1))*float(b.d.morale.general_aura_per_rank)
   if "cautious" in traits and r.order == O_HOLD: m += float(b.d.traits.cautious.hold_morale)
   # Fortunes of the day: each unit's starting morale varies a little (seeded).
   m *= 1.0+b.rng.randf_range(-float(b.d.morale.start_morale_noise),float(b.d.morale.start_morale_noise))
   r.morale = m
   r.start_morale = m
   # Flankers need an open outer lane.
   if r.order == O_FLANK and (not (r.lane == 0 or r.lane == b.lanes-1) or b.lane_closed(r.lane)): r.order = O_HOLD
   if r.order == O_FLANK:
    r.state = S_FLANKING
    r.eta = _flank_eta(b,r,traits,int(g.get("rank",1)))
   # Protect indexes refer to the side's unit list; map them to runtime indices.
  var base = -1
  for i in b.u.size():
   if b.u[i].side == side:
    base = i
    break
  for i in b.u.size():
   var r: Unit = b.u[i]
   if r.side == side and r.protect>=0: r.protect = base+r.protect

static func _delay(b: Battle,traits: Array) -> int:
 var dl = 0
 if "mediocre" in traits: dl += int(b.d.traits.mediocre.all_delays)
 return dl

static func _flank_eta(b: Battle,r,traits: Array,rank: int) -> int:
 var o = b.d.orders
 var spd = 0.0
 var n = 0
 for ter in b.terrain[r.lane]:
  if ter == "closed": continue
  spd += float(b.d.terrain.speed[ter])
  n += 1
 spd = maxf(0.2,spd/maxf(1,n))
 var forest = "forest" in b.terrain[r.lane]
 var eta = float(o.flank_path_bands)/(r.speed*spd)*(float(o.flank_forest_factor) if forest else 1.0)
 eta -= int(rank/3)*int(o.flank_ticks_per_3_ranks)
 return maxi(1,int(ceil(eta))+_delay(b,traits))

# --- Phases ---------------------------------------------------------------------------

static func _arrivals(b: Battle):
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.state == S_WAITING and b.t>=r.arrive:
   r.state = S_RESERVE
   b.ev("reinforcements",r.side,i)
  if r.state == S_PENDING:
   r.eta -= 1
   if r.eta<=0:
    r.state = S_READY
    b.ev("reserve_plugs",r.side,i,{"lane":r.lane})
  if r.off_field>0:
   r.off_field -= 1
   if r.off_field == 0 and r.state == S_AWAY: r.state = S_READY

static func _visible(b: Battle,i: int) -> bool:
 var r: Unit = b.u[i]
 if r.state != S_READY and r.state != S_ENGAGED: return false
 if r.fought or r.state == S_ENGAGED: return true
 if b.forest(r.lane,r.y): return false
 if b.fog_hides and absf(r.y-b.back_y[r.side])<0.01: return false
 return true

static func _missile_range(b: Battle,r) -> float:
 var rng_b = float(r.st.missile.range)
 if b.hills(r.lane,r.y): rng_b += float(b.d.terrain.hills_missile_range)
 if b.weather == "fog": rng_b += float(b.d.weather.fog_missile_range)
 return rng_b

# Nearest visible enemy in range (own lane or the next one), never one in melee with this unit.
static func _missile_target(b: Battle,i: int) -> int:
 var r: Unit = b.u[i]
 var rng_b = _missile_range(b,r)
 var best = -1
 var best_d = 999.0
 var foes: Array = []
 for l in range(maxi(0,r.lane-1),mini(b.lanes,r.lane+2)): foes.append_array(b.lane_units[1-r.side][l])
 foes.sort()
 for j in foes:
  var e: Unit = b.u[j]
  var ld = absi(e.lane-r.lane)
  if b.vis[j] == 0: continue
  if e.state == S_ENGAGED and (e.target == i or r.target == j): continue
  var dist = absf(e.y-r.y)+ld
  if dist<=rng_b and dist<best_d:
   best = j
   best_d = dist
 return best

# Rebuild the per-side, per-lane lists of units on the field (cheap; keeps searches local).
static func _bucket(b: Battle):
 b.lane_units = [[],[]]
 for s in 2:
  for l in b.lanes: b.lane_units[s].append([])
 b.vis.resize(b.u.size())
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.state == S_READY or r.state == S_ENGAGED: b.lane_units[r.side][r.lane].append(i)
  # Visible to the enemy: fighting, or standing in the open (not in forest, not a fog-hidden back line).
  var hidden = not r.fought and r.state != S_ENGAGED and (b.t_forest[r.lane][clampi(int(round(r.y))-1,0,b.nbands-1)] or (b.fog_hides and absf(r.y-b.back_y[r.side])<0.01))
  b.vis[i] = 0 if hidden else 1

static func _missiles(b: Battle):
 var losses = {}
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.ammo<=0 or r.state != S_READY or r.st.missile == null: continue
  var best = _missile_target(b,i)
  if best<0: continue
  var e: Unit = b.u[best]
  var est = e.st
  var armour = 1.0-e.armour*(1.0-r.ap)/100.0
  var shield = 1.0-e.shield
  var cover = float(b.d.terrain.forest_missile_cover) if b.forest(e.lane,e.y) else 1.0
  var wx = float(b.d.weather.rain_missile_factor) if b.weather == "rain" else 1.0
  var into_melee = b.etf if e.state == S_ENGAGED else 1.0
  var kills = into_melee*r.men*b.missile_rate*float(r.st.missile.damage)*b.missile_acc*armour*shield*cover*wx*b.noise()
  if e.is_general: kills *= 0.1
  losses[best] = losses.get(best,0.0)+kills
  r.ammo -= 1
  b.cause("volleys",r.side,1.0)
  r.fired = true
  r.kills += kills
  b.cause("missiles",r.side,kills)
  if r.cat == C_MISSILE and absf(r.y-float(b.d.field.back_y[r.side]))<0.01: b.cause("protected_missiles",r.side,kills)
 _apply(b,losses)

# Nearest live, visible enemy in a lane, measured along y from this unit.
static func _nearest_in_lane(b: Battle,i: int,lane: int) -> int:
 var r: Unit = b.u[i]
 var best = -1
 var best_d = 999.0
 for j in b.lane_units[1-r.side][lane]:
  var e: Unit = b.u[j]
  if e.lane != lane or not (b.u[j].state <= S_ENGAGED): continue
  if b.vis[j] == 0 and absf(e.y-r.y)>1.0: continue
  var dist = absf(e.y-r.y)
  if dist<best_d:
   best = j
   best_d = dist
 return best

static func _protector_of(b: Battle,j: int) -> int:
 for k in b.u.size():
  var p: Unit = b.u[k]
  if p.order == O_PROTECT and p.protect == j and p.state == S_READY: return k
 return -1

static func _engage(b: Battle,i: int,j: int,charging: bool,rear := false):
 var p = _protector_of(b,j)
 if p>=0 and p != i and not rear:
  b.ev("protected",b.u[p].side,p,{"target":j,"by":i})
  b.cause("protect",b.u[p].side,10.0)
  j = p
 elif p>=0 and rear:
  b.ev("protected",b.u[p].side,p,{"target":j,"by":i})
  b.cause("protect",b.u[p].side,20.0)
  j = p
  rear = false
 var r: Unit = b.u[i]
 var e: Unit = b.u[j]
 r.target = j
 r.state = S_ENGAGED
 r.charging = charging
 r.rear = rear
 r.contact = 0
 r.fought = true
 if e.state != S_ENGAGED or e.target<0 or not (b.u[e.target].state <= S_ENGAGED):
  e.target = i
  e.state = S_ENGAGED
  e.charging = false
  e.rear = false
  e.contact = 0
 e.fought = true

static func _movement(b: Battle):
 var f = b.d.field
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.state != S_READY: continue
  var dir = 1.0 if r.side == 0 else -1.0
  var traits = r.traits
  # Line depth: an idle holding unit joins the fight of an enemy already in contact in its lane.
  # (Missile troops keep shooting instead; they only fight when attacked.)
  if r.order in HOLDING and not r.missile:
   var foe = _adjacent_fighting_enemy(b,i)
   if foe>=0:
    _engage(b,i,foe,false)
    continue
  var moves = r.order == O_AGGRESSIVE
  if r.order == O_HOLD and "impetuous" in traits and b.rng.randf()<float(b.d.traits.impetuous.advance_chance) and _neighbour_winning(b,i): moves = true
  if not moves: continue
  # Missile troops advance only until an enemy is in range, then stand and shoot.
  if r.st.missile != null and r.ammo>0 and _missile_target(b,i)>=0: continue
  var start_delay = _delay(b,traits)+(int(b.d.traits.cautious.aggressive_delay) if "cautious" in traits else 0)
  if b.t<=start_delay: continue
  var target = _nearest_in_lane(b,i,r.lane)
  if target<0:
   r.wait += 1
   if r.wait>=int(b.d.combat.lane_change_wait):
    var best_lane = -1
    for dl in [1,-1,2,-2,3,-3,4,-4]:
     var l = r.lane+dl
     if l<0 or l>=b.lanes or b.lane_closed(l): continue
     if _nearest_in_lane(b,i,l)>=0:
      best_lane = l
      break
    if best_lane>=0:
     r.lane = best_lane if absi(best_lane-r.lane) == 1 else r.lane+signi(best_lane-r.lane)
     r.wait = 0
   continue
  var e: Unit = b.u[target]
  var dist = absf(e.y-r.y)
  var contact = float(f.contact_distance)
  # Walls: attackers stop at the wall and need time to cross (or to break a gate).
  if b.walls != null and r.side == 0:
   var wy = float(b.d.sieges.wall_band_y)
   if r.y+0.001>=wy-contact:
    r.wall_ticks += 1
    var need = int(b.d.sieges.gate_break_ticks) if r.lane in b.walls.get("gates",[]) else int(b.d.sieges.wall_cross_ticks)
    if r.wall_ticks<=need:
     b.cause("walls",1,5.0)
     continue
  var step = r.speed*b.t_speed[r.lane][b.band(r.y)]
  if dist-step<=contact:
   r.y = e.y-dir*contact
   _engage(b,i,target,true)
  else:
   r.y += dir*step
   if b.walls != null and r.side == 0: r.y = minf(r.y,float(b.d.sieges.wall_band_y)-contact+0.001) if r.wall_ticks == 0 else r.y

static func _adjacent_fighting_enemy(b: Battle,i: int) -> int:
 var r: Unit = b.u[i]
 var reach = float(b.d.field.contact_distance)*1.5
 for j in b.lane_units[1-r.side][r.lane]:
  var e: Unit = b.u[j]
  if e.side != r.side and e.state == S_ENGAGED and e.lane == r.lane and absf(e.y-r.y)<=reach: return j
 return -1

static func _neighbour_winning(b: Battle,i: int) -> bool:
 var r: Unit = b.u[i]
 for j in b.u.size():
  var n: Unit = b.u[j]
  if n.side == r.side and n.state == S_ENGAGED and absi(n.lane-r.lane) == 1 and n.target>=0 and b.u[n.target].lost_tick>n.lost_tick: return true
 return false

static func _flank_arrivals(b: Battle):
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.state != S_FLANKING: continue
  r.eta -= 1
  var foe = b.enemy(r.side)
  if "cautious" in r.traits and b.reserve_used[foe] == 0 and _reserve_left(b,foe) and r.eta<=0 and r.eta>-6: continue
  if r.eta>0: continue
  r.state = S_READY
  # Once arrived, a flanker keeps attacking whatever is nearest in its lane.
  r.order = O_AGGRESSIVE
  r.y = float(b.d.field.back_y[foe])
  # 1. An uncommitted reserve rides out and meets the flanker where it arrives (its outer lane).
  var res = _take_reserve(b,foe,"cavalry")
  if res>=0:
   var rr: Unit = b.u[res]
   rr.state = S_READY
   rr.order = O_AGGRESSIVE
   rr.lane = r.lane
   rr.y = r.y
   b.ev("flank_intercepted",foe,res,{"by":i,"lane":rr.lane})
   b.cause("reserve_intercept",foe,40.0)
   _engage(b,res,i,true)
   # Cavalry meeting cavalry: both sides charge.
   r.charging = true
   r.contact = 0
   continue
  # 2. An idle unit in the same outer lane, in its own half of the field, screens it head-on.
  #    Units already locked in melee cannot screen.
  var screen = -1
  for j in b.u.size():
   var e: Unit = b.u[j]
   if e.side == foe and e.lane == r.lane and e.state == S_READY and not e.is_general and absf(e.y-r.y)<=float(b.d.field.bands)/2.0:
    screen = j
    break
  if screen>=0:
   b.ev("flank_screened",foe,screen,{"by":i,"lane":r.lane})
   b.cause("screen",foe,30.0)
   r.y = b.u[screen].y
   _engage(b,i,screen,true)
   continue
  # 3. Otherwise it hits the nearest enemy lane from the outside in, back line first, from behind.
  var target = -1
  var order = range(b.lanes) if r.lane == 0 else range(b.lanes-1,-1,-1)
  for l in order:
   var back = -1
   var front = -1
   for j in b.u.size():
    var e: Unit = b.u[j]
    if e.side != foe or e.lane != l or not (b.u[j].state <= S_ENGAGED): continue
    if absf(e.y-float(b.d.field.back_y[foe]))<0.6: back = j if back<0 else back
    elif front<0: front = j
   target = back if back>=0 else front
   if target>=0: break
  if target<0: continue
  r.lane = b.u[target].lane
  r.y = b.u[target].y
  # The target may turn and face in time (more likely with high morale and a skilled general):
  # then it is a frontal fight, with no rear bonus and no morale shock.
  var tf = b.d.orders.turn_face
  var tu: Unit = b.u[target]
  var g_rank = b.u[b.generals[foe]].rank
  var face = clampf(float(tf.base)+tu.morale*float(tf.per_morale)+g_rank*float(tf.per_general_rank),0.0,float(tf.max))
  if b.rng.randf()<face:
   b.ev("turned_to_face",foe,target,{"by":i,"lane":r.lane})
   b.cause("turned_to_face",foe,20.0)
   _engage(b,i,target,true)
   continue
  b.ev("flank_hit_rear",r.side,i,{"target":target,"lane":r.lane,"no_reserve":true})
  var shock = float(b.d.morale.rear_hit)
  b.u[target].morale -= shock
  b.cause("flank_rear",r.side,shock)
  for j in b.u.size():
   var n: Unit = b.u[j]
   if n.side == foe and j != target and (b.u[j].state <= S_ENGAGED) and absi(n.lane-r.lane)<=1:
    n.morale -= float(b.d.morale.rear_hit_neighbour)
    b.cause("flank_rear",r.side,float(b.d.morale.rear_hit_neighbour))
  var extra = float(b.d.traits.reckless.first_charge) if "reckless" in r.traits else 0.0
  _engage(b,i,target,true,true)
  r.charge_extra = extra

static func _reserve_left(b: Battle,side: int) -> bool:
 for j in b.u.size():
  if b.u[j].side == side and b.u[j].state == S_RESERVE: return true
 return false

# Take an uncommitted reserve unit, preferring the given category.
static func _take_reserve(b: Battle,side: int,prefer_cat: String) -> int:
 var prefer = CAT_IDS[prefer_cat]
 var pick = -1
 for j in b.u.size():
  var r: Unit = b.u[j]
  if r.side != side or r.state != S_RESERVE: continue
  if pick<0 or (r.cat == prefer and b.u[pick].cat != prefer): pick = j
 if pick>=0: b.reserve_used[side] += 1
 return pick

static func _towers(b: Battle):
 if b.walls == null: return
 var s = b.d.sieges
 var dmg = float(b.walls.get("defense",0))*float(s.tower_damage_per_defense)*maxf(0.0,1.0-float(s.wall_decay_per_turn)*int(b.walls.get("siege_turns",0)))
 if dmg<=0: return
 var targets = []
 for j in b.u.size():
  if b.u[j].side == 0 and (b.u[j].state <= S_ENGAGED) and b.u[j].y>=float(s.tower_range_y): targets.append(j)
 if targets.is_empty(): return
 var losses = {}
 for j in targets:
  var armour = 1.0-float(b.u[j].st.armour)/100.0*0.5
  losses[j] = dmg/targets.size()*armour*b.noise()
  b.cause("towers",1,losses[j])
 _apply(b,losses)

static func _frontage(b: Battle,r) -> float:
 return b.t_front[r.lane][b.band(r.y)]*b.front_scale

static func _melee(b: Battle):
 var c = b.d.combat
 var losses = {}
 # Attackers on one target share its frontage (front and rear separately).
 var n = b.u.size()
 var press_front = PackedFloat64Array()
 var press_rear = PackedFloat64Array()
 press_front.resize(n)
 press_rear.resize(n)
 for i in n:
  var r: Unit = b.u[i]
  if r.state != S_ENGAGED or r.target<0 or not (b.u[r.target].state <= S_ENGAGED): continue
  var m = r.men if r.is_general else minf(r.men,_frontage(b,r))
  if r.rear: press_rear[r.target] += m
  else: press_front[r.target] += m
 var wall_factor = 0.0
 if b.walls != null: wall_factor = maxf(0.0,1.0-float(b.d.sieges.wall_decay_per_turn)*int(b.walls.get("siege_turns",0)))
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.state != S_ENGAGED or r.target<0: continue
  var j = r.target
  var e: Unit = b.u[j]
  if not (b.u[j].state <= S_ENGAGED):
   r.state = S_READY
   r.target = -1
   continue
  r.contact += 1
  var st = r.st
  var est = e.st
  var att = r.attack+r.rank*b.rank_att
  var def = e.defence+e.rank*b.rank_def
  if b.hills(r.lane,r.y) and not b.hills(e.lane,e.y): att += float(b.d.terrain.hills_attack)
  if e.cat == C_CAVALRY: att += r.vs_cav
  var first = r.contact == 1 and r.charging
  if first:
   var ch = r.charge+r.charge_extra
   if b.forest(e.lane,e.y): ch *= float(b.d.terrain.forest_charge_factor)
   var braced = e.order in HOLDING and e.state == S_ENGAGED
   if braced and e.brace:
    # Braced spears blunt most of the charge (a data share), not all of it.
    b.ev("charge_braced",e.side,j,{"by":i})
    var cut = ch*float(c.brace_charge_reduction)
    b.cause("brace",e.side,cut)
    ch -= cut
   elif braced: def += float(c.brace_defence)
   if ch>0:
    att += ch
    b.ev("charge",r.side,i,{"target":j})
  if r.rear:
   att *= float(c.rear_attack_factor)
   def *= float(c.rear_defence_factor)
  if b.walls != null and e.side == 1 and r.side == 0:
   var gate_open = r.lane in b.walls.get("gates",[]) and r.contact>int(b.d.sieges.gate_break_ticks)
   if not gate_open:
    att -= float(b.d.sieges.wall_attack_malus)*wall_factor
    def += float(b.d.sieges.wall_defence_bonus)*wall_factor
  var hit = clampf(b.hit_base+(att-def)*b.hit_per_point,b.hit_min,b.hit_max)
  var armour = 1.0-e.armour*(1.0-r.ap)/100.0
  var fighting = minf(r.men,_frontage(b,r))
  if r.is_general: fighting = r.men
  var cap = _frontage(b,e)*(0.5 if r.rear else 1.0)
  fighting *= minf(1.0,cap/maxf(1.0,press_rear[j] if r.rear else press_front[j]))
  # In a pass, units waiting behind the fighting unit add a share of their strength.
  if b.t_pass[r.lane][b.band(r.y)] and not r.rear: fighting += _pass_support(b,i)*float(c.pass_support_fraction)
  var kills = fighting*hit*b.melee_kill*armour*b.noise()
  if r.morale<b.waver_below: kills *= b.waver_factor
  if e.is_general: kills *= 0.25
  losses[j] = losses.get(j,0.0)+kills
  r.kills += kills
  if r.rear: b.cause("flank_rear",r.side,kills)
  if first and r.cat == C_CAVALRY: b.cause("charge",r.side,kills)
  if e.cat == C_MISSILE and r.cat == C_CAVALRY: b.cause("cavalry_on_missiles",r.side,kills)
 _apply(b,losses)

# Men waiting behind a unit fighting in a pass: idle melee units of its side in the same lane, plus
# the side's reserve when this pass is the only open lane.
static func _pass_support(b: Battle,i: int) -> float:
 var r: Unit = b.u[i]
 var open_lanes = 0
 for l in b.lanes:
  if not b.lane_closed(l): open_lanes += 1
 var men = 0.0
 for j in b.u.size():
  if j == i: continue
  var w: Unit = b.u[j]
  if w.side != r.side or w.is_general or w.missile: continue
  if (w.state == S_READY and w.lane == r.lane) or (w.state == S_RESERVE and open_lanes == 1): men += minf(w.men,_frontage(b,r))
 return men

static func _apply(b: Battle,losses: Dictionary):
 for j in losses:
  var e: Unit = b.u[j]
  var l = minf(e.men,losses[j])
  e.men -= l
  e.lost_tick += l

static func _morale(b: Battle):
 var m = b.d.morale
 var routed_now = []
 for i in b.u.size():
  var r: Unit = b.u[i]
  if not (b.u[i].state <= S_ENGAGED):
   r.lost_tick = 0.0
   continue
  var pct = r.lost_tick/maxf(1.0,r.start_men)*100.0
  r.morale -= pct*b.per_pct
  if r.state == S_ENGAGED and r.target>=0 and b.u[r.target].lost_tick>r.lost_tick: r.morale += b.winning
  if r.is_general and r.men<=0.001:
   r.state = S_DESTROYED
   b.general_lost[r.side] = true
   b.ev("general_killed",r.side,i)
   routed_now.append(i)
  elif r.men<=r.start_men*(1.0-b.destroyed_at):
   r.state = S_DESTROYED
   b.ev("destroyed",r.side,i)
   routed_now.append(i)
  elif r.morale<=0:
   r.state = S_ROUTED
   r.target = -1
   b.ev("routed" if not r.is_general else "general_fled",r.side,i,{"lane":r.lane})
   if r.is_general: b.general_lost[r.side] = true
   routed_now.append(i)
 for i in b.u.size(): b.u[i].lost_tick = 0.0
 for k in routed_now:
  var r: Unit = b.u[k]
  for j in b.u.size():
   var n: Unit = b.u[j]
   if n.side != r.side or not (b.u[j].state <= S_ENGAGED): continue
   if r.is_general:
    n.morale -= float(m.general_lost)
    b.cause("general_lost",1-r.side,float(m.general_lost))
   elif absi(n.lane-r.lane)<=1:
    var hit = float(m.neighbour_rout)+(float(b.d.traits.steady.neighbour_rout) if "steady" in n.traits else 0.0)
    n.morale -= hit
    b.cause("chain_rout",1-r.side,hit)
  # A broken lane pulls in a reserve; cavalry reserves ride down the routers.
  if not r.is_general: _plug_lane(b,r.side,r.lane)
  # Cavalry reserves ride down routers, but not while enemy flankers are still on their way.
  var flankers_inbound = false
  for j in b.u.size():
   if b.u[j].side == r.side and b.u[j].state == S_FLANKING: flankers_inbound = true
  var cav = -1
  for j in b.u.size():
   if flankers_inbound: break
   if b.u[j].side == 1-r.side and b.u[j].state == S_RESERVE and b.u[j].cat == C_CAVALRY:
    cav = j
    break
  if cav>=0 and r.state == S_ROUTED:
   b.u[cav].state = S_READY
   b.u[cav].lane = r.lane
   b.u[cav].y = r.y
   b.u[cav].order = O_AGGRESSIVE
   b.reserve_used[1-r.side] += 1
   b.ev("reserve_pursues",1-r.side,cav,{"target":k})

# A side that has lost the configured share of its men breaks: everyone left routs or leaves.
static func _army_break(b: Battle):
 var share = float(b.d.morale.army_break_fraction)
 for side in 2:
  if b.broken[side]: continue
  var start = 0.0
  var lost = 0.0
  for r: Unit in b.u:
   if r.side != side or r.is_general: continue
   start += r.start_men
   lost += r.start_men-r.men
   if r.state in GONE: lost += r.men
  # Missile troops alone cannot hold the field: the army also breaks when no melee unit is left.
  var melee_left = false
  for i in b.u.size():
   var r: Unit = b.u[i]
   if r.side == side and not r.is_general and r.cat != C_MISSILE and (b.u[i].state <= S_PENDING): melee_left = true
  if start<=0 or (lost/start<share and melee_left): continue
  b.broken[side] = true
  b.ev("army_broke",side,-1,{"share":lost/start})
  for i in b.u.size():
   var r: Unit = b.u[i]
   if r.side != side: continue
   if (b.u[i].state <= S_ENGAGED):
    r.state = S_ROUTED
    r.target = -1
   elif r.state in OFF_FIELD: r.state = S_FLED

static func _plug_lane(b: Battle,side: int,lane: int):
 for j in b.u.size():
  var n: Unit = b.u[j]
  if n.side == side and n.lane == lane and (b.u[j].state <= S_ENGAGED) and not n.is_general: return
 var foe_here = false
 for j in b.u.size():
  if b.u[j].side != side and b.u[j].lane == lane and (b.u[j].state <= S_ENGAGED): foe_here = true
 if not foe_here: return
 var res = _take_reserve(b,side,"infantry")
 if res<0: return
 var r: Unit = b.u[res]
 var g: Unit = b.u[b.generals[side]]
 var delay = int(b.d.orders.reserve_delay)
 if g.rank>=int(b.d.orders.reserve_fast_rank): delay -= 1
 if "steady" in r.traits: delay += int(b.d.traits.steady.reserve_delay)
 delay += _delay(b,r.traits)
 r.state = S_PENDING
 r.eta = maxi(0,delay)
 r.lane = lane
 r.y = float(b.d.field.front_y[side])
 r.order = O_HOLD
 b.cause("reserve_plug",side,25.0)

static func _pursuit(b: Battle):
 var p = b.d.pursuit
 var losses = {}
 for i in b.u.size():
  var r: Unit = b.u[i]
  if r.state != S_ROUTED: continue
  var dir = -1.0 if r.side == 0 else 1.0
  r.y += dir*float(p.rout_speed)
  var hunter = -1
  for j in b.u.size():
   var e: Unit = b.u[j]
   if e.side == r.side or e.state != S_READY or absi(e.lane-r.lane)>1: continue
   if e.cat == C_CAVALRY or e.order == O_AGGRESSIVE:
    hunter = j
    if e.cat == C_CAVALRY: break
  if hunter>=0:
   var h: Unit = b.u[hunter]
   var k = r.men*float(p.cavalry if h.cat == C_CAVALRY else p.infantry)
   losses[i] = losses.get(i,0.0)+k
   h.kills += k
   b.cause("pursuit",h.side,k)
   if "reckless" in h.traits and h.cat == C_CAVALRY:
    h.state = S_AWAY
    h.off_field = int(b.d.traits.reckless.pursue_off_field_ticks)
  if r.y<0.0 or r.y>float(b.d.field.bands)+1.0:
   r.state = S_FLED
 _apply(b,losses)
 for i in losses:
  b.u[i].lost_tick = 0.0

static func _record(b: Battle):
 if b.fast: return
 var frame = []
 for r: Unit in b.u: frame.append([r.lane,snappedf(r.y,0.01),r.state,int(round(r.men))])
 b.replay.append(frame)

# --- Result ------------------------------------------------------------------------------

static func _result(b: Battle,winner: int,outcome: String,setup: Dictionary) -> Dictionary:
 var sides = [{"units":[],"general":{}},{"units":[],"general":{}}]
 var xp = b.d.experience
 # Roster: who each replay column / event unit index is (row = index in sides[side].units, -1 for a general).
 var roster = []
 var rows = [0,0]
 for r: Unit in b.u:
  roster.append({"side":r.side,"unit":r.unit,"general":r.is_general,"row":-1 if r.is_general else rows[r.side]})
  if not r.is_general: rows[r.side] += 1
 for i in b.u.size():
  var r: Unit = b.u[i]
  var men = int(round(r.men))
  var fate = "held"
  match r.state:
   S_ROUTED,S_FLED: fate = "routed"
   S_DESTROYED: fate = "destroyed"
   S_RESERVE,S_WAITING: fate = "unused"
  if r.state in STANDING and r.side == winner: fate = "won"
  if r.is_general:
   sides[r.side].general = {"engaged":r.fought,"hp_left":r.men,"killed":r.state == S_DESTROYED,"fled":r.state in GONE,"kills":r.kills}
   continue
  var surv = fate in ["held","won","unused"]
  sides[r.side].units.append({"unit":r.unit,"index":r.src,"army":r.army,"men_start":int(round(r.start_men)),"men_end":men,
   "losses":int(round(r.start_men))-men,"kills":int(round(r.kills)),"outcome":fate,"xp":r.kills*float(xp.per_kill)+(float(xp.survive) if surv else 0.0)})
 var report_causes = {}
 for k in b.causes:
  for s in 2:
   if b.causes[k][s] != 0.0: report_causes["%s:%d" % [k,s]] = snappedf(b.causes[k][s],0.01)
 return {"winner":winner,"outcome":outcome if outcome != "mutual" else "victory","ticks":b.t,"weather":b.weather,"sides":sides,
  "events":b.events,"causes":report_causes,"replay":b.replay,"roster":roster,"lanes":b.lanes}

# Total men lost per side.
static func losses(result: Dictionary,side: int) -> int:
 var n = 0
 for x in result.sides[side].units: n += int(x.losses)
 return n
