extends RefCounted
# Monte Carlo harness for the battle simulation (docs/battle-design.md section 12). Builds battles
# from tests/fixtures/battle_scenarios.json, runs many seeded battles per case and checks the
# targets. Used by scripts/battle_harness.gd (full report) and tests/test_battle_sim.gd (subset).

const BattleSim = preload("res://core/battle_sim.gd")
const BattleDeploy = preload("res://core/battle_deploy.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const SCENARIOS = "res://tests/fixtures/battle_scenarios.json"
const LANE3 = [0,0,1,2,2]

static var _sc = null

static func data() -> Dictionary:
 if _sc == null: _sc = JSON.parse_string(FileAccess.get_file_as_string(SCENARIOS))
 return _sc

static func scenario(id: String) -> Dictionary:
 for s in data().scenarios:
  if s.id == id: return s
 return {}

static func terrain(field: String,lanes: int) -> Array:
 var bands = int(BattleSim.data().field.bands)
 var out = []
 for l in lanes:
  var col = []
  for b in bands:
   if field == "pass": col.append("pass" if l == lanes/2 else "closed")
   else: col.append("open")
  out.append(col)
 return out

# A case with "same_as" inherits that case, then applies its own keys and per-unit overrides.
static func resolve(sc: Dictionary,ci: int) -> Dictionary:
 var c = sc.cases[ci]
 if c.has("same_as_scenario"):
  var other = scenario(c.same_as_scenario)
  return resolve(other,0)
 var out = {}
 if c.has("same_as"): out = resolve(sc,int(c.same_as)).duplicate(true)
 # A case that states its own target replaces the inherited one.
 if c.has("min") or c.has("max") or c.get("reference",false):
  out.erase("min")
  out.erase("max")
 for k in c:
  if k in ["same_as","b_override","a_override"]: continue
  out[k] = c[k].duplicate(true) if c[k] is Dictionary or c[k] is Array else c[k]
 for side in ["a","b"]:
  var key = side+"_override"
  if c.has(key):
   for idx in c[key]:
    out[side].units[int(idx)].merge(c[key][idx],true)
 return out

static func _units(spec: Dictionary,role: int,ter: Array,lanes: int,men_scale: float) -> Array:
 var out = []
 if spec.has("units"):
  for u in spec.units:
   var e = u.duplicate(true)
   var size = int(UnitTypes.get_type(e.unit).size)
   e.men = size*men_scale
   e.max_men = size
   if e.has("lane") and lanes == 3: e.lane = LANE3[int(e.lane)]
   if not e.has("lane"): e.lane = lanes/2
   out.append(e)
  return out
 var army = spec.army if spec.army is Array else data().armies[spec.army]
 var list = []
 for id in army:
  var size = int(UnitTypes.get_type(id).size)
  list.append({"unit":id,"men":size*men_scale,"max_men":size})
 out = BattleDeploy.deploy(list,spec.get("template","line"),ter,role)
 if spec.has("front"):
  for e in out:
   if e.line == "front" and e.order == "hold": e.order = spec.front
 return out

static func build(c: Dictionary,seed: int,a_attacks: bool,lanes: int) -> Dictionary:
 var field = c.get("field","open")
 var ter = terrain(field,lanes)
 var f = {"terrain":ter}
 if field == "walls": f.walls = {"defense":int(c.walls.defense),"siege_turns":int(c.walls.get("siege_turns",0)),"gates":[lanes/2]}
 var sides = []
 for k in (["a","b"] if a_attacks else ["b","a"]):
  var role = sides.size()
  var spec = c[k]
  var scale = float(c.get("men_scale",1.0)) if k == "a" else 1.0
  sides.append({"faction":k,"general":{"name":k,"rank":int(spec.get("general_rank",1)),"traits":spec.get("traits",[])},"units":_units(spec,role,ter,lanes,scale)})
 return {"seed":seed,"lanes":lanes,"field":f,"sides":sides}

# Runs n battles. Returns {rate (side A wins), ms (per battle), missiles, volleys, results?}.
static func run(sc: Dictionary,c: Dictionary,n: int,lanes: int) -> Dictionary:
 var wins = 0.0
 var missiles = 0.0
 var volleys = 0.0
 var t0 = Time.get_ticks_usec()
 for i in n:
  var a_attacks = true
  match sc.role:
   "defender": a_attacks = false
   "attacker": a_attacks = true
   _: a_attacks = i%2 == 0
  var seed = hash([sc.id,c.get("label",""),i])
  var setup = build(c,seed,a_attacks,lanes)
  setup.fast = true
  var r = BattleSim.simulate(setup)
  var a_side = 0 if a_attacks else 1
  if r.winner == a_side: wins += 1.0
  missiles += float(r.causes.get("missiles:%d" % a_side,0.0))
  volleys += float(r.causes.get("volleys:%d" % a_side,0.0))
 var ms = (Time.get_ticks_usec()-t0)/1000.0/n
 return {"rate":wins/n,"ms":ms,"kpv":missiles/maxf(1.0,volleys)}

static func _row(id: String,label: String,target: String,actual: String,ok: bool) -> Dictionary:
 return {"scenario":id,"label":label,"target":target,"actual":actual,"pass":ok}

static func _target_text(c: Dictionary) -> String:
 if c.has("min") and c.has("max"): return "%d-%d%%" % [int(c.min*100),int(c.max*100)]
 if c.has("min"): return ">= %d%%" % int(c.min*100)
 if c.has("max"): return "<= %d%%" % int(c.max*100)
 return "(reference)"

static func _check(c: Dictionary,rate: float) -> bool:
 return rate>=float(c.get("min",0.0))-0.0001 and rate<=float(c.get("max",1.0))+0.0001

# Evaluate one scenario; returns rows of {scenario, label, target, actual, pass}.
static func evaluate(sc: Dictionary,n: int,lanes := 5) -> Array:
 var rows = []
 match sc.metric:
  "win_rate":
   for ci in sc.cases.size():
    var c = resolve(sc,ci)
    var r = run(sc,c,n,lanes)
    var has_target = c.has("min") or c.has("max")
    rows.append(_row(sc.id,c.label,_target_text(c),"%.1f%%" % (r.rate*100),_check(c,r.rate) if has_target else true))
  "kills_per_volley":
   var k = []
   for ci in sc.cases.size(): k.append(run(sc,resolve(sc,ci),n,lanes).kpv)
   var ratio = k[0]/maxf(0.0001,k[1])
   rows.append(_row(sc.id,"heavy infantry / levies kills per volley","<= %.2f" % float(sc.ratio_max),"%.2f (%.2f vs %.2f)" % [ratio,k[0],k[1]],ratio<=float(sc.ratio_max)))
  "monotonic":
   var rates = []
   for ci in sc.cases.size(): rates.append(run(sc,resolve(sc,ci),n,lanes).rate)
   var ok = true
   for i in range(1,rates.size()): ok = ok and rates[i]>=rates[i-1]
   ok = ok and rates[-1]>rates[0]
   var txt = []
   for r in rates: txt.append("%d%%" % int(round(r*100)))
   rows.append(_row(sc.id,"70/85/100/115/130% men","rising"," ".join(txt),ok))
  "determinism":
   var c = resolve(sc,0)
   var setup = build(c,12345,true,lanes)
   var a = JSON.stringify(BattleSim.simulate(setup))
   var b = JSON.stringify(BattleSim.simulate(build(c,12345,true,lanes)))
   rows.append(_row(sc.id,"same seed, same result and report","identical","identical" if a == b else "DIFFERENT",a == b))
  "speed":
   var r = run(sc,resolve(sc,0),n,lanes)
   rows.append(_row(sc.id,"ms per battle (10 v 10 units, debug build)","< %.1f ms" % float(sc.max_ms),"%.2f ms" % r.ms,r.ms<float(sc.max_ms)))
  "lanes":
   var gaps = {}
   for l in [3,5]:
    var all_ok = true
    for other in data().scenarios:
     if not other.get("lanes_check",false): continue
     for row in evaluate(other,n,l): all_ok = all_ok and row.pass
    var s5 = scenario("5")
    var open_rate = run(s5,resolve(s5,0),n,l).rate
    var screened = run(s5,resolve(s5,2),n,l).rate
    gaps[l] = open_rate-screened
    # Targets apply to the configured lane count (5); other counts are informational.
    var binding = l == int(BattleSim.data().field.lanes)
    rows.append(_row(sc.id,"%d lanes: scenarios 2-6 meet targets%s" % [l,"" if binding else " (informational)"],"all pass" if binding else "(info)","all pass" if all_ok else "some miss",all_ok or not binding))
   rows.append(_row(sc.id,"flank gap (unscreened - screened)","5 lanes > 3 lanes","%.0f%% vs %.0f%%" % [gaps[5]*100,gaps[3]*100],gaps[5]>gaps[3]))
 return rows

static func evaluate_all(n: int) -> Array:
 var rows = []
 for sc in data().scenarios: rows.append_array(evaluate(sc,n))
 return rows
