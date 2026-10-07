extends RefCounted
# Procedural settlement sprawl (owner decisions 2026-10-04, game-design §12.13; design Addendum A).
# layout() turns one settlement into a placement list of kit pieces. Layouts follow the culture and
# the terrain, never a default ring (owner, 2026-10-04):
#  grid      Roman: a grid of straight streets around a forum, square walls with corner towers
#  plaza     Lizardmen: a monumental plaza on an axis, pyramids, causeways to satellite temples
#  river     Desert: blocks along the river, a processional avenue from the bank to the pyramid
#  terraces  Greek: terraces following the contours of a hill, the acropolis on top, down to a harbour
#  organic   Medieval: crooked lanes from the gates to a market square, castle on the high ground,
#            the church on the square
#  stacks    Ratmen: crooked lanes packed with leaning towers and walkways over old ruins
#  cliff     Dwarves: a hold cut into the nearest mountainside, halls stepping up it, a fortified front
#  camp      Orcs: a palisaded stronghold on the high ground, sprawling camps of huts and tents
#  spires    Elves: spires on the high ground joined by bridges, houses scattered in gardens
#  crags     Dark elves: jagged towers on the rocks and the shore, spiked walls along the cliffs
#  wild      Beastmen: a herdstone in a clearing, huts woven into the groves, totems on the trails
# Every layout is dense and asymmetric, with no empty ground inside the walls; walls follow the
# built outline and the terrain (they stop at cliffs and shores), and suburbs spill along the roads.
# Towns commit to a specialization path (military, farming, mining, lumber, market; big cities have
# none) shown by the culture's signature building and the countryside. While the land converts,
# each piece is the new culture's, a ruin of the old one's, or the old one's.
# Deterministic: all randomness is seeded from the settlement id. Presentation only.
# Angles: "rot" is the direction a piece faces in the map plane (x, z), as Vector2.from_angle(rot).
# A piece's front is its local +z; long pieces (walls, bridges) run along local x, so their rot is
# the run's direction plus PI/2.

const SPRAWL = "res://data/settlement_sprawl.json"
const CULTURES = "res://data/cultures.json"
const PATHS = ["military","farming","mining","lumber","market"]
const MILITARY_CHAINS = ["barracks","archery_range","stables"]

static var _sprawl = null
static var _cultures = null

static func sprawl_data() -> Dictionary:
 if _sprawl == null: _sprawl = JSON.parse_string(FileAccess.get_file_as_string(SPRAWL))
 return _sprawl

static func culture_data() -> Dictionary:
 if _cultures == null: _cultures = JSON.parse_string(FileAccess.get_file_as_string(CULTURES))
 return _cultures

static func culture(id: String) -> Dictionary:
 var c = culture_data().cultures
 return c.get(id,c[culture_data().default])

# The specialization path a settlement shows: its own "path", or (towns, villages, castles and
# fortresses) the strongest path-building chain it has. Cities have no path, only growth.
static func path_of(s: Dictionary) -> String:
 if s.has("path"): return str(s.path)
 if s.get("type","city") == "city": return ""
 var best = ""
 var lv = 0
 for b in s.get("buildings",[]):
  var ch = str(b.get("chain",""))
  var p = {"farm":"farming","mine":"mining","lumber":"lumber","lumber_camp":"lumber","market":"market"}.get(ch,"military" if ch in MILITARY_CHAINS else "")
  if p != "" and int(b.get("level",0))>lv:
   lv = int(b.level)
   best = p
 return best

# s: {id, type, level, position: Vector2, from, to, value (land conversion 0-1), buildings: [{chain,
# level}], landmark_radius (0 = none), path (optional)}. terrain_at(Vector2) -> class name;
# height_at(x, z) -> metres (optional: flat without it). Returns [{piece, culture, ruin, pos: Vector2,
# rot, scale: Vector3, color: Color, water?}].
static func layout(s: Dictionary,terrain_at: Callable,height_at := Callable()) -> Array:
 var L = clampi(int(s.get("level",1)),1,3)
 var types = sprawl_data().types
 var cfg = types.get(s.get("type","city"),types.city)[L-1]
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(["sprawl",s.id])
 var to = str(s.get("to","medieval"))
 var ctx = {"s":s,"rng":rng,"out":[],"terrain":terrain_at,"height":height_at,"band":float(culture_data().conversion.ruin_band),
  "center":Vector2(s.position),"L":L,"cfg":cfg,"taken":{},"inner":[],"to":to,"style":str(culture(to).get("layout","organic"))}
 var center: Vector2 = ctx.center
 var lm = float(s.get("landmark_radius",0.0))
 var chains = {}
 for b in s.get("buildings",[]):
  if b.has("chain") and int(b.get("level",0))>0: chains[b.chain] = maxi(int(chains.get(b.chain,0)),int(b.level))
 ctx.chains = chains
 ctx.site = _site(ctx,float(cfg.suburb))
 # Converging roads at uneven angles (never a symmetric star), bent toward the water and the valleys.
 var roads = int(cfg.roads)
 var a0 = rng.randf()*TAU
 if ctx.site.water != Vector2.ZERO: a0 = ctx.site.water.angle()
 var road_a = [a0]
 for i in range(1,roads): road_a.append(a0+i*TAU/roads+rng.randf_range(-0.45,0.45))
 ctx.roads = road_a
 if lm>0.0:
  # A landmark keeps its own model at the centre: the town grows around it, no walls through it.
  # A landmark with walls of its own (landmark_walls) gets no generic wall ring; one without them
  # gets the culture's ring around its town when the settlement type has walls.
  for p in _ring_lots(ctx,lm+3.0,float(cfg.suburb),4.4): _lot(ctx,p[0],p[1],"house")
  if float(cfg.get("wall",0))>0.0 and not bool(s.get("landmark_walls",false)) and not ctx.inner.is_empty() and not ctx.style in ["wild","camp"]: _outline_walls(ctx)
 else:
  match ctx.style:
   "grid": _grid(ctx,false)
   "plaza": _grid(ctx,true)
   "river": _river(ctx)
   "terraces": _terraces(ctx)
   "cliff": _cliff(ctx)
   "camp": _camp(ctx)
   "spires": _spires(ctx,false)
   "crags": _spires(ctx,true)
   "wild": _wild(ctx)
   "stacks": _organic(ctx,true)
   _: _organic(ctx,false)
  if float(cfg.get("wall",0))>0.0: _walls(ctx)
 _suburbs(ctx)
 _countryside(ctx)
 _hamlets(ctx)
 _crowds(ctx)
 return ctx.out

# --- Site --------------------------------------------------------------------------------------------

static func _h(ctx: Dictionary,p: Vector2) -> float:
 return float(ctx.height.call(p.x,p.y)) if ctx.height.is_valid() else 0.0

static func _cls(ctx: Dictionary,p: Vector2) -> String:
 return str(ctx.terrain.call(p))

static func _land(ctx: Dictionary,p: Vector2) -> bool:
 var t = _cls(ctx,p)
 return t != "water" and t != "mountain" and t != ""

# High ground, the uphill direction, the nearest water and the nearest mountain around the centre.
static func _site(ctx: Dictionary,radius: float) -> Dictionary:
 var c: Vector2 = ctx.center
 var best = c
 var best_h = _h(ctx,c)
 var water = Vector2.ZERO
 var water_d = INF
 var mountain = Vector2.ZERO
 var mountain_d = INF
 var forest = []
 for ring in range(1,9):
  var r = radius*1.3*ring/8.0
  var n = 10+ring*4
  for i in n:
   var p = c+Vector2.from_angle(i*TAU/n)*r
   var t = _cls(ctx,p)
   if t == "water" and r<water_d:
    water_d = r
    water = (p-c).normalized()
   elif t == "mountain" and r<mountain_d:
    mountain_d = r
    mountain = (p-c).normalized()
   elif t == "forest": forest.append(p)
   elif t != "" and r<radius*0.75:
    var h = _h(ctx,p)
    if h>best_h+0.5:
     best_h = h
     best = p
 return {"high":best,"high_h":best_h,"low_h":_h(ctx,c),"water":water,"water_d":water_d,"water_p":c+water*water_d if water != Vector2.ZERO else c,
  "mountain":mountain,"mountain_d":mountain_d,"forest":forest}

# --- Placement ---------------------------------------------------------------------------------------

const CELL = 1.0 # occupancy grid (m)
const FOOT = {"house":1.2,"hut":1.0,"tall":1.3,"keep":4.2,"temple":4.0,"wall":1.2,"tower":1.4,"gate":1.8,"path":3.2,"bridge":0.0,"prop":0.9} # half widths (m)

static func _free(ctx: Dictionary,p: Vector2,r: float) -> bool:
 var lo = ((p-Vector2.ONE*r)/CELL).floor()
 var hi = ((p+Vector2.ONE*r)/CELL).floor()
 for y in range(int(lo.y),int(hi.y)+1):
  for x in range(int(lo.x),int(hi.x)+1):
   if ctx.taken.has(Vector2i(x,y)): return false
 return true

static func _take(ctx: Dictionary,p: Vector2,r: float):
 var lo = ((p-Vector2.ONE*r)/CELL).floor()
 var hi = ((p+Vector2.ONE*r)/CELL).floor()
 for y in range(int(lo.y),int(hi.y)+1):
  for x in range(int(lo.x),int(hi.x)+1): ctx.taken[Vector2i(x,y)] = true

# A building lot: placed if the ground is free, dry and not too steep. role: house, hut, tall, keep,
# temple, wall, tower, gate, path_<path>, or a shared kit id (kit.*). Returns true when placed.
static func _lot(ctx: Dictionary,p: Vector2,rot: float,role: String,force := false,inner := true,sc := 1.0) -> bool:
 var foot = FOOT.get("path" if role.begins_with("path_") else role,FOOT.prop)*sc
 if not force:
  if not _land(ctx,p) or not _free(ctx,p,foot): return false
  if ctx.height.is_valid():
   var d = absf(_h(ctx,p+Vector2(foot,0))-_h(ctx,p-Vector2(foot,0)))+absf(_h(ctx,p+Vector2(0,foot))-_h(ctx,p-Vector2(0,foot)))
   if d>foot*2.6: return false # too steep to build on
 _take(ctx,p,foot)
 if inner and not role in ["wall","tower","gate"]: ctx.inner.append(p)
 _put(ctx,role,p,rot,sc)
 return true

# One piece; while the land converts, the new culture's, a ruin of the old one's, or the old one's.
static func _put(ctx: Dictionary,role: String,p: Vector2,rot: float,sc := 1.0,extra := {}):
 var s = ctx.s
 var rng: RandomNumberGenerator = ctx.rng
 var h = rng.randf()
 var to = str(s.get("to","medieval"))
 var from = str(s.get("from",to))
 var v = float(s.get("value",1.0))
 var cul = to
 var ruin = false
 if from != to and v<1.0 and h>=v:
  cul = from
  ruin = h<v+float(ctx.band)
 var piece = role
 if not role.begins_with("kit.") and not role.begins_with("commerce."):
  var r = role
  if role == "house": r = ["house_1","house_2","house_3"][rng.randi_range(0,2)]
  piece = "kit.%s.%s" % [cul,r]
 var col = Color(culture(cul).tint.ruin) if ruin else Color.WHITE
 if role.begins_with("kit.") and extra.has("color"): col = extra.color
 var e = {"piece":piece,"culture":cul,"ruin":ruin,"pos":p,"rot":rot,"scale":extra.get("scale",Vector3.ONE*sc),"color":col}
 var lift = float(extra.get("lift",ctx.get("lift",0.0)))
 if lift>0.0: e.lift = lift
 if extra.get("water",false): e.water = true
 ctx.out.append(e)

# Lots along a polyline (a street), both sides, facing the street.
static func _street(ctx: Dictionary,pts: Array,gap: float,setback: float,role_of: Callable):
 for k in pts.size()-1:
  var a: Vector2 = pts[k]
  var b: Vector2 = pts[k+1]
  var d = b-a
  var n = maxi(1,int(d.length()/gap))
  var dir = d.normalized()
  for i in n:
   var p = a+dir*(i+0.5)*d.length()/n
   for side in [-1.0,1.0]:
    if ctx.rng.randf()<0.08: continue
    var q = p+dir.orthogonal()*side*setback+dir*ctx.rng.randf_range(-0.4,0.4)
    _lot(ctx,q,(-dir.orthogonal()*side).angle(),role_of.call(q))
   if ctx.rng.randf()<0.18: _put(ctx,"people",p+dir.orthogonal()*ctx.rng.randf_range(-0.6,0.6),ctx.rng.randf()*TAU)

# A crooked lane from a to b (random walk with a pull toward b).
static func _lane(ctx: Dictionary,a: Vector2,b: Vector2,wiggle: float) -> Array:
 var pts = [a]
 var p = a
 var steps = maxi(2,int(a.distance_to(b)/5.0))
 for i in steps:
  var t = float(i+1)/steps
  var q = a.lerp(b,t)+Vector2(ctx.rng.randf_range(-1,1),ctx.rng.randf_range(-1,1))*wiggle*sin(t*PI)
  pts.append(q)
  p = q
 pts[-1] = b
 return pts

# Fill the remaining ground inside a radius function with lots (no empty ground inside the walls).
static func _infill(ctx: Dictionary,center: Vector2,reach: Callable,gap: float,role_of: Callable,tries := 600):
 for i in tries:
  var a = ctx.rng.randf()*TAU
  var r = sqrt(ctx.rng.randf())*float(reach.call(a))
  var p = center+Vector2.from_angle(a)*r
  _lot(ctx,p,a+ctx.rng.randf_range(-0.3,0.3)+PI,role_of.call(p))

static func _ring_lots(ctx: Dictionary,r0: float,r1: float,gap: float) -> Array:
 var out = []
 var r = r0
 while r<r1:
  var n = int(TAU*r/gap)
  for i in n:
   var a = i*TAU/n+ctx.rng.randf_range(-0.1,0.1)
   out.append([ctx.center+Vector2.from_angle(a)*(r+ctx.rng.randf_range(-1.0,1.0)),a+PI])
  r += gap
 return out

# The city's reach in each direction: an irregular blob (stretched along one axis, dented), so no two
# settlements share an outline and none is a circle.
static func _blob(ctx: Dictionary,r: float) -> Callable:
 var rng: RandomNumberGenerator = ctx.rng
 var k = [rng.randf_range(0.15,0.32),rng.randf_range(0.05,0.15),rng.randf_range(0.04,0.1)]
 var ph = [rng.randf()*TAU,rng.randf()*TAU,rng.randf()*TAU]
 return func(a: float) -> float: return r*(1.0+k[0]*cos(2.0*a+ph[0])+k[1]*cos(3.0*a+ph[1])+k[2]*cos(5.0*a+ph[2]))

static func _role_mix(ctx: Dictionary,tall_share: float,hut_share := 0.0) -> Callable:
 return func(p: Vector2) -> String:
  var u = ctx.rng.randf()
  if u<tall_share: return "tall"
  if u<tall_share+hut_share: return "hut"
  return "house"

# --- Layout styles ----------------------------------------------------------------------------------

# Roman grid (plaza = false) or the lizardmen's monumental plaza (true).
static func _grid(ctx: Dictionary,plaza: bool):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var ax = Vector2.from_angle(ctx.roads[0])
 var ay = ax.orthogonal()
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.85)
 var rx = R*ctx.rng.randf_range(0.95,1.2)
 var ry = R*ctx.rng.randf_range(0.7,0.95)
 var lot = 4.2
 ctx.grid = {"ax":ax,"ay":ay,"rx":rx,"ry":ry}
 if plaza:
  # The plaza on the axis: the great pyramid at its head, temple pyramids flanking it.
  _lot(ctx,c+ax*rx*0.35,ax.angle()+PI,"keep",true)
  for s in [-1.0,1.0]: _lot(ctx,c+ay*s*9.0-ax*2.0,(-ay*s).angle(),"temple",true)
  _take(ctx,c-ax*4.0,7.0) # the open plaza
  for i in range(2,6): _put(ctx,"kit.road",c-ax*(i*6.0),ax.angle(),1.0,{"scale":Vector3(3.6,1,6.2),"color":Color(sprawl_data().colors.causeway)})
 else:
  # The forum: temple at its head, a colonnaded hall (market) on its side.
  _lot(ctx,c+ax*6.5,ax.angle()+PI,"temple",true)
  _lot(ctx,c-ay*6.5,ay.angle(),"path_market" if ctx.chains.has("market") else "tall",true)
  _take(ctx,c,5.5)
 # Insulae: lots on the grid, a street every third row and column.
 var nx = int(rx/lot)
 var ny = int(ry/lot)
 for i in range(-nx,nx+1):
  for j in range(-ny,ny+1):
   var every = 3 if str(ctx.s.get("type","city")) in ["city","fortress"] else 4
   if i%every == 0 or j%every == 0: continue # streets (fewer in small towns)
   var p = c+ax*i*lot+ay*j*lot
   if plaza and ctx.rng.randf()<0.35: continue # looser jungle quarters
   var role = "house"
   var u = ctx.rng.randf()
   if u<0.12: role = "tall"
   elif plaza and u<0.5: role = "hut"
   _lot(ctx,p,ax.angle() if j>0 else ax.angle()+PI,role)
 if ctx.chains.has("barracks") or path_of(ctx.s) == "military":
  # A legion camp outside: tents in rows inside a square palisade.
  var lc = c-ax*(rx+14.0)
  for i in range(-2,3):
   for j in range(-2,3): _put(ctx,"kit.tent",lc+ax*i*3.0+ay*j*3.4,ax.angle())
  for k in range(-3,4):
   for s in [-1.0,1.0]:
    _put(ctx,"kit.fence",lc+ax*k*2.6+ay*s*9.0,ax.angle())
    _put(ctx,"kit.fence",lc+ay*k*2.6+ax*s*9.0,ay.angle())

# Desert: blocks along the river; a processional avenue from the bank to the pyramid.
static func _river(ctx: Dictionary):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var w: Vector2 = ctx.site.water if ctx.site.water != Vector2.ZERO else Vector2.from_angle(ctx.roads[0])
 var along = w.orthogonal()
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.85)
 # The pyramid inland, the avenue to the water lined with guardian statues (towers here).
 var pyr = c-w*R*0.55
 _lot(ctx,pyr,w.angle(),"keep",true)
 var d = 8.0
 while d<R*1.2:
  var p = pyr+w*d
  if not _land(ctx,p): break
  _put(ctx,"kit.road",p,w.angle(),1.0,{"scale":Vector3(3.0,1,6.2),"color":Color(sprawl_data().colors.causeway)})
  _take(ctx,p,1.8)
  if int(d)%12 == 8:
   for s in [-1.0,1.0]: _lot(ctx,p+along*s*3.2,(-along*s).angle(),"tower",true,true,0.55)
  d += 6.0
 _lot(ctx,pyr+w*R*0.45+along*7.0,w.angle()+PI,"temple",true)
 # Flat-roofed blocks in rows parallel to the river.
 var lot = 4.0
 for i in range(-int(R*1.3/lot),int(R*1.3/lot)+1):
  for j in range(-int(R/lot),int(R/lot)+1):
   if i%4 == 0: continue
   var p = c+along*i*lot+w*j*lot+Vector2(ctx.rng.randf_range(-0.5,0.5),ctx.rng.randf_range(-0.5,0.5))
   _lot(ctx,p,w.angle(),"tall" if ctx.rng.randf()<0.1 else "house")

# Greek: the acropolis on the high ground; terraces stepping down its contours toward the sea.
static func _terraces(ctx: Dictionary):
 var cfg = ctx.cfg
 var top: Vector2 = ctx.site.high
 # Always terraced (owner, 2026-10-05): the core stands on a raised acropolis of stepped stone
 # terraces, built up even on flat ground (higher where the hill is low) and stepping down a
 # terrace per band; on a hill the contours add to it.
 var relief = maxf(0.0,float(ctx.site.high_h)-float(ctx.site.low_h))
 var acro = maxf(2.0,6.0+ctx.L*1.5-relief*0.5)
 ctx.acro = {"top":top,"lift":acro}
 _terrace(ctx,top,acro,13.0)
 ctx.lift = acro
 _lot(ctx,top,(ctx.center-top).angle(),"temple",true)
 _lot(ctx,top+(ctx.center-top).normalized().orthogonal()*8.0,(ctx.center-top).angle(),"keep",true)
 ctx.lift = 0.0
 var reach = _blob(ctx,maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.85))
 var downhill: Vector2 = ctx.site.water if ctx.site.water != Vector2.ZERO else (ctx.center-top).normalized()
 var h_top = _h(ctx,top)
 for band in range(1,9):
  # Lots on this terrace: march out from the acropolis until the ground drops a band lower (a
  # contour), farther on the sea side.
  var n = 18+band*5
  for i in n:
   var a = i*TAU/n+ctx.rng.randf_range(-0.05,0.05)
   var dir = Vector2.from_angle(a)
   var lean = 1.0+0.6*maxf(0.0,dir.dot(downhill))
   # The city spills down toward the sea: on the land side only the upper terraces are built.
   if dir.dot(downhill)<-0.2 and band>2+ctx.L/2: continue
   if dir.dot(downhill)<0.3 and band>4+ctx.L: continue
   var r = 5.0+band*4.2*lean
   if ctx.height.is_valid():
    var target = h_top-band*1.6
    var rr = 4.0
    while rr<reach.call(a)*1.4 and _h(ctx,top+dir*rr)>target: rr += 1.5
    r = lerpf(r,rr,0.7)
   if r>reach.call(a)*1.3: continue
   var lift = maxf(0.0,acro-band*1.5)
   var q = top+dir*r
   if lift>0.2 and _land(ctx,q) and _free(ctx,q,1.2): _terrace(ctx,q,lift,3.4)
   ctx.lift = lift
   _lot(ctx,q,a+PI,"tall" if band<3 and ctx.rng.randf()<0.3 else "house")
   ctx.lift = 0.0
 _infill(ctx,top.lerp(ctx.center,0.5),reach,4.0,_role_mix(ctx,0.08))

# A stone terrace (retaining walls and fill) of the given height and width under a lot.
static func _terrace(ctx: Dictionary,p: Vector2,height: float,width: float):
 _put(ctx,"plinth",p,ctx.rng.randf()*0.2,1.0,{"scale":Vector3(width,height+0.6,width),"lift":-0.5})

# Medieval (and the ratmen's stacks): lanes from the gates to a market square below the castle.
static func _organic(ctx: Dictionary,stacks: bool):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var high: Vector2 = ctx.site.high
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.85)
 var reach = _blob(ctx,R)
 # The castle (or the ratmen's bell tower) on the high ground; the square between it and the centre.
 var keep_at = high if high.distance_to(c)>4.0 else c+Vector2.from_angle(ctx.roads[0]+PI*0.8)*R*0.35
 _lot(ctx,keep_at,(c-keep_at).angle(),"keep",true)
 var square = keep_at.lerp(c,0.6)+Vector2(ctx.rng.randf_range(-3,3),ctx.rng.randf_range(-3,3))
 _lot(ctx,square+Vector2.from_angle(ctx.rng.randf()*TAU)*6.0,ctx.rng.randf()*TAU,"temple",true)
 if ctx.chains.has("market") or path_of(ctx.s) == "market": _lot(ctx,square-Vector2.from_angle(ctx.roads[0])*6.0,ctx.roads[0],"path_market",true)
 _take(ctx,square,4.0)
 var role = _role_mix(ctx,0.45 if stacks else 0.14)
 for a in ctx.roads:
  var gate = c+Vector2.from_angle(a)*reach.call(a)
  _street(ctx,_lane(ctx,gate,square,4.0 if not stacks else 6.0),3.6 if not stacks else 3.0,2.6,role)
 # Back lanes between the main ones.
 for i in 2+ctx.L:
  var a = ctx.rng.randf()*TAU
  _street(ctx,_lane(ctx,c+Vector2.from_angle(a)*reach.call(a)*0.9,square.lerp(c,0.5),5.0),3.8,2.4,role)
 _infill(ctx,c,reach,3.6,role,500+ctx.L*250)
 if stacks:
  # Walkways between the leaning towers, and ruins of the old city underneath.
  var talls = ctx.out.filter(func(e): return str(e.piece).ends_with(".tall"))
  for i in mini(talls.size(),40):
   var a = talls[i]
   for j in range(i+1,mini(talls.size(),40)):
    var b = talls[j]
    var d = a.pos.distance_to(b.pos)
    if d>3.0 and d<9.0 and ctx.rng.randf()<0.5:
     _put(ctx,"bridge",(a.pos+b.pos)*0.5,(b.pos-a.pos).angle()+PI*0.5,1.0,{"scale":Vector3(d,1,1)})
     break
  for i in 6+ctx.L*4:
   var p = c+Vector2.from_angle(ctx.rng.randf()*TAU)*reach.call(0.0)*ctx.rng.randf_range(0.2,1.1)
   ctx.out.append({"piece":"kit.medieval.house_2","culture":"medieval","ruin":true,"pos":p,"rot":ctx.rng.randf()*TAU,"scale":Vector3.ONE,"color":Color(culture("medieval").tint.ruin)})

# Dwarves: the hold cut into the nearest mountainside; halls stepping up the slope.
static func _cliff(ctx: Dictionary):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var up: Vector2 = ctx.site.mountain if ctx.site.mountain != Vector2.ZERO else (ctx.site.high-c).normalized()
 if up == Vector2.ZERO: up = Vector2.from_angle(ctx.roads[0]+PI)
 var side = up.orthogonal()
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.85)
 # The great gate where the land meets the rock, facing out.
 var foot = c+up*minf(float(ctx.site.mountain_d)*0.85,R*0.8) if ctx.site.mountain != Vector2.ZERO else c+up*R*0.5
 _lot(ctx,foot,(-up).angle(),"keep",true)
 _lot(ctx,foot-up*7.0+side*9.0,(-up).angle(),"temple",true)
 # Halls in rows along the contour, stepping uphill (and down into the valley in front).
 for row in range(-4,4):
  var n = 7-absi(row)/2
  for i in range(-n,n+1):
   var p = foot-up*(9.0+row*4.4)+side*i*4.0+side*ctx.rng.randf_range(-0.6,0.6)
   _lot(ctx,p,(-up).angle(),"tall" if row>1 and ctx.rng.randf()<0.4 else "house")
 # Towers on the spurs above the hold.
 for s in [-1.0,1.0]: _lot(ctx,foot+up*4.0+side*s*12.0,(-up).angle(),"tower",false)
 ctx.front = {"at":foot-up*(9.0+4*4.4+3.0),"side":side,"half":8*4.0,"up":up}

# Orcs: the stronghold on the high ground; camps sprawling around it in clusters.
static func _camp(ctx: Dictionary):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var hold: Vector2 = ctx.site.high
 _lot(ctx,hold,ctx.rng.randf()*TAU,"keep",true)
 # A tight spiked palisade round the stronghold only.
 var pr = 9.0
 var n = int(TAU*pr/3.2)
 for i in n:
  var a = i*TAU/n
  if absf(angle_difference(a,(c-hold).angle()))<0.35: continue # its gate faces the camps
  _lot(ctx,hold+Vector2.from_angle(a)*(pr+ctx.rng.randf_range(-0.6,0.6)),a+PI,"wall",true,false)
 _lot(ctx,hold+(c-hold).normalized()*pr,(c-hold).angle(),"gate",true,false)
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.9)
 for k in 4+ctx.L*2:
  var cc = hold+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(pr+6.0,R)
  var size = ctx.rng.randf_range(5.0,9.0+ctx.L*2.0)
  for i in int(size*1.4):
   var p = cc+Vector2.from_angle(ctx.rng.randf()*TAU)*sqrt(ctx.rng.randf())*size
   _lot(ctx,p,ctx.rng.randf()*TAU,"hut" if ctx.rng.randf()<0.55 else ("kit.tent" if ctx.rng.randf()<0.5 else "house"))
  _lot(ctx,cc,0.0,"temple" if k%3 == 0 else "kit.pit")
 for i in ctx.L+1: _lot(ctx,hold+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(R*0.5,R),0.0,"tall")

# Elves (spires on the high ground, bridges, gardens) and dark elves (towers on rock and shore).
static func _spires(ctx: Dictionary,crags: bool):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.85)
 var reach = _blob(ctx,R)
 var top: Vector2 = ctx.site.high
 if crags and ctx.site.water != Vector2.ZERO: top = c.lerp(ctx.site.water_p,0.6)
 _lot(ctx,top,(c-top).angle(),"keep",true)
 # Spires on the highest ground around (or the rocks along the shore).
 var spots = []
 for i in 60:
  var p = c+Vector2.from_angle(ctx.rng.randf()*TAU)*sqrt(ctx.rng.randf())*reach.call(ctx.rng.randf()*TAU)
  var score = _h(ctx,p)+(6.0 if _cls(ctx,p) == "hills" else 0.0)
  if crags and ctx.site.water != Vector2.ZERO: score += 12.0-p.distance_to(ctx.site.water_p)*0.3
  spots.append([score,p])
 spots.sort_custom(func(a,b): return a[0]>b[0])
 var placed = []
 for sp in spots.slice(0,6+ctx.L*4):
  if _lot(ctx,sp[1],ctx.rng.randf()*TAU,"tall"): placed.append(sp[1])
 # Bridges between neighbouring spires.
 for i in placed.size():
  for j in range(i+1,placed.size()):
   var d = placed[i].distance_to(placed[j])
   if d>4.0 and d<14.0 and not crags:
    _put(ctx,"bridge",(placed[i]+placed[j])*0.5,(placed[j]-placed[i]).angle()+PI*0.5,1.0,{"scale":Vector3(d,1,1)})
 _lot(ctx,top+(c-top).normalized().orthogonal()*10.0,(c-top).angle(),"temple",true)
 # Houses scattered in gardens (elves) or packed under the towers (dark elves).
 _infill(ctx,c,reach,4.0,_role_mix(ctx,0.1),(260 if not crags else 420)+ctx.L*120)

# Beastmen: the herdstone in a clearing, huts nestled in the groves, totems on the trails.
static func _wild(ctx: Dictionary):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 _lot(ctx,c,0.0,"keep",true)
 _take(ctx,c,8.0)
 var groves = ctx.site.forest.duplicate()
 var R = maxf(float(cfg.get("wall",0)),float(cfg.suburb)*0.9)
 for k in 4+ctx.L*2:
  var g = groves[ctx.rng.randi_range(0,groves.size()-1)] if not groves.is_empty() and ctx.rng.randf()<0.7 else c+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(12.0,R)
  g = c+(g-c).limit_length(R)
  for i in 6+ctx.L*2:
   var p = g+Vector2.from_angle(ctx.rng.randf()*TAU)*sqrt(ctx.rng.randf())*7.0
   _lot(ctx,p,ctx.rng.randf()*TAU,"hut" if ctx.rng.randf()<0.4 else "house",false)
 for a in ctx.roads:
  for d in [10.0,18.0]: _lot(ctx,c+Vector2.from_angle(a)*d+Vector2.from_angle(a+PI*0.5)*2.5,a,"temple" if d>15.0 else "gate",false,false,0.8)

# --- Walls --------------------------------------------------------------------------------------------

# Walls around the built-up area: the Roman square, the dwarves' fortified front, or (everyone else)
# the city's own irregular outline, broken where it meets cliffs and shores. Towers at the corners and
# along the curtain, gatehouses where the roads leave.
static func _walls(ctx: Dictionary):
 match ctx.style:
  "wild", "camp": return # beastmen have no walls; the orcs' palisade guards the stronghold only
  "cliff":
   var f = ctx.front
   var n = int(f.half*2.0/3.2)
   for i in n+1:
    var p = f.at+f.side*(-f.half+i*3.2)
    var role = "tower" if i%4 == 0 else ("gate" if i == n/2 else "wall")
    _lot(ctx,p,f.side.angle()+PI*0.5,role,false,false)
   return
  "grid", "plaza":
   if ctx.style == "plaza": return # the plaza is open to its causeways
   var g = ctx.grid
   var corners = []
   for s in [[-1,-1],[1,-1],[1,1],[-1,1]]: corners.append(ctx.center+g.ax*s[0]*(g.rx+3.0)+g.ay*s[1]*(g.ry+3.0))
   _wall_ring(ctx,corners,4)
   return
 _outline_walls(ctx)

# Walls along the town's outline: per direction, the farthest building plus a margin, smoothed.
static func _outline_walls(ctx: Dictionary):
 var c: Vector2 = ctx.center
 var bins = 40
 var r = []
 r.resize(bins)
 r.fill(0.0)
 for p in ctx.inner:
  var d: Vector2 = p-c
  var i = int(fposmod(d.angle(),TAU)/TAU*bins)%bins
  r[i] = maxf(r[i],d.length())
 for i in bins:
  if r[i] == 0.0: r[i] = maxf(r[(i+bins-1)%bins],r[(i+1)%bins])
 var sm = []
 for i in bins: sm.append((r[(i+bins-1)%bins]+r[i]*2.0+r[(i+1)%bins])*0.25+3.4)
 var poly = []
 for i in bins: poly.append(c+Vector2.from_angle((i+0.5)*TAU/bins)*sm[i])
 _wall_ring(ctx,poly,3 if ctx.style in ["organic","terraces"] else 4)

# Curtain walls along a closed polygon: towers at corners and every `every` segments, gatehouses
# where a road crosses; nothing on water or cliffs (the walls stop at shores and cliffs).
static func _wall_ring(ctx: Dictionary,poly: Array,every: int):
 var seg = float(sprawl_data().piece_size.wall)
 var k = 0
 for i in poly.size():
  var a: Vector2 = poly[i]
  var b: Vector2 = poly[(i+1)%poly.size()]
  var prev: Vector2 = poly[(i+poly.size()-1)%poly.size()]
  var turn = absf(angle_difference((a-prev).angle(),(b-a).angle()))
  if turn>0.3: _lot(ctx,a,(b-a).angle()+PI*0.5,"tower",false,false)
  var n = maxi(1,int(round(a.distance_to(b)/seg)))
  for j in n:
   var p = a.lerp(b,(j+0.5)/n)
   if not _land(ctx,p): continue
   var role = "wall"
   var ang = (p-ctx.center).angle()
   for ra in ctx.roads:
    if absf(angle_difference(ang,ra))*p.distance_to(ctx.center)<seg*0.8: role = "gate"
   if role == "wall" and k%every == every-1: role = "tower"
   k += 1
   _lot(ctx,p,(b-a).angle()+PI*0.5,role,role != "tower",false) # wall length along the edge

# Alive at scale (game-design §12.13 F): specks of people gathered in the open ground of the centre
# (squares, forums, plazas) and travellers on the roads out of town.
static func _crowds(ctx: Dictionary):
 var c: Vector2 = ctx.center
 var placed = 0
 for i in 40:
  if placed>=4+ctx.L*4: break
  var p = c+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(2.0,10.0+ctx.L*2.0)
  if _land(ctx,p) and _free(ctx,p,0.6):
   _put(ctx,"people",p,ctx.rng.randf()*TAU)
   placed += 1
 for a in ctx.roads:
  for k in 1+ctx.L:
   var p = c+Vector2.from_angle(a)*ctx.rng.randf_range(float(ctx.cfg.suburb),float(ctx.cfg.farm))+Vector2.from_angle(a+PI*0.5)*1.2
   if _land(ctx,p): _put(ctx,"people",p,a)

# --- Outside the walls -------------------------------------------------------------------------------

# Suburbs spilling along the roads (more on one side), roads out to the farm belt.
static func _suburbs(ctx: Dictionary):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var far = float(cfg.farm)
 var role = _role_mix(ctx,0.05,0.25)
 var favour = ctx.rng.randf()*TAU
 for a in ctx.roads:
  var pts = []
  var d = 6.0
  var dir = Vector2.from_angle(a)
  var bend = ctx.rng.randf_range(-0.012,0.012)
  var p = c+dir*d
  while d<far:
   if _land(ctx,p): pts.append(p)
   if _land(ctx,p): _put(ctx,"kit.road",p,dir.angle(),1.0,{"scale":Vector3(2.2,1,6.2),"color":Color(sprawl_data().colors.road)})
   dir = dir.rotated(bend+ctx.rng.randf_range(-0.05,0.05))
   p += dir*6.0
   d += 6.0
  # Houses along the road from the edge of town out to the suburb limit; denser on the favoured side.
  var lots = 0
  var weight = 0.6+0.4*cos(angle_difference(a,favour))
  for k in range(1,pts.size()):
   var q: Vector2 = pts[k]
   if q.distance_to(c)>float(cfg.suburb)*(0.8+weight*0.6): break
   for side in [-1.0,1.0]:
    if ctx.rng.randf()>weight: continue
    var off = (pts[k]-pts[k-1]).normalized().orthogonal()*side*ctx.rng.randf_range(3.2,5.5)
    if _lot(ctx,q+off,(-off).angle(),role.call(q),false,false): lots += 1
 # Outlying villages.
 for v in int(cfg.villages):
  var a = ctx.roads[v%ctx.roads.size()]+ctx.rng.randf_range(0.5,1.2)
  var vc = c+Vector2.from_angle(a)*float(cfg.village_radius)*ctx.rng.randf_range(0.85,1.15)
  if not _land(ctx,vc): continue
  for h in ctx.rng.randi_range(5,8): _lot(ctx,vc+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(1.5,6.5),ctx.rng.randf()*TAU,"hut" if ctx.rng.randf()<0.5 else "house",false,false)

# The countryside: the farm belt, the specialization path's look, and the building chains' features
# (mines, docks, yards, shrines, stalls).
static func _countryside(ctx: Dictionary):
 var cfg = ctx.cfg
 var c: Vector2 = ctx.center
 var chains = ctx.chains
 var path = path_of(ctx.s)
 var sd = sprawl_data()
 var farm_r = float(cfg.farm)
 var fr0 = maxf(float(cfg.suburb)*0.7,float(cfg.get("wall",0))+6.0)
 # The path's signature building, at the place that suits it.
 var sig_at = c+Vector2.from_angle(ctx.roads[0]+0.6)*(fr0+4.0)
 match path:
  "mining":
   var spot = _find(ctx,c,["hills","pass","mountain"],float(sd.chains.mine.search))
   if spot == null:
    # Any town can take any path: a mine pit opens beside the town.
    spot = c+Vector2.from_angle(ctx.roads[0]+1.9)*(fr0+8.0)
    for i in 3: _put(ctx,"kit.pit",spot+Vector2.from_angle(i*2.1)*5.0,0.0,1.6)
   sig_at = spot
   _sig(ctx,sig_at,path)
   for i in 3+ctx.L*2: _lot(ctx,spot+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(6.0,12.0),ctx.rng.randf()*TAU,"kit.spoil",false,false,ctx.rng.randf_range(0.9,1.5))
   for i in ctx.L+1: _put(ctx,"kit.cart",spot.lerp(c,ctx.rng.randf_range(0.3,0.6)),(c-spot).angle())
  "lumber":
   var f = ctx.site.forest
   if not f.is_empty(): sig_at = f[0]+(c-f[0]).normalized()*4.0
   _sig(ctx,sig_at,path)
   for i in 4+ctx.L*2: _put(ctx,"kit.fence",sig_at+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(5.0,9.0),ctx.rng.randf()*TAU)
  "military":
   sig_at = c+Vector2.from_angle(ctx.roads[0]+0.5)*(fr0+3.0)
   _sig(ctx,sig_at,path)
   for i in 6+ctx.L*3: _put(ctx,"kit.tent",sig_at+Vector2(i%4*3.2,i/4*3.6).rotated(ctx.roads[0])+Vector2.from_angle(ctx.roads[0])*7.0,ctx.roads[0])
  "market":
   _sig(ctx,sig_at,path)
   for i in 4+ctx.L*4: _put(ctx,"kit.stall",sig_at+Vector2.from_angle(i*TAU/(4+ctx.L*4))*ctx.rng.randf_range(5.0,7.0),ctx.rng.randf()*TAU)
   for i in 2+ctx.L*2:
    var a = ctx.roads[i%ctx.roads.size()]
    _put(ctx,"kit.cart",c+Vector2.from_angle(a)*ctx.rng.randf_range(fr0,farm_r)+Vector2.from_angle(a+PI*0.5)*1.6,a)
 if path == "farming": _sig(ctx,sig_at,path)
 # Fields on open ground: many for farming towns, none in the forests (lumber towns keep them).
 var fields = 6*ctx.L+int(sd.chains.farm.fields)*int(chains.get("farm",0))+(14 if path == "farming" else 0)-(6 if path in ["mining","lumber"] else 0)
 var tries = maxi(0,fields)*4
 var colors = sd.colors.fields
 while fields>0 and tries>0:
  tries -= 1
  var a = ctx.rng.randf()*TAU
  var d = ctx.rng.randf_range(fr0,farm_r+6.0)
  var p = c+Vector2.from_angle(a)*d
  if _cls(ctx,p) != "open" or not _free(ctx,p,3.0): continue
  var sz = ctx.rng.randf_range(5.0,7.5)
  ctx.out.append({"piece":"kit.field","culture":ctx.to,"ruin":false,"pos":p,"rot":a+PI*0.5,"scale":Vector3(sz,1,sz*ctx.rng.randf_range(0.7,1.3)),"color":Color(colors[ctx.rng.randi_range(0,colors.size()-1)])})
  _take(ctx,p,2.5)
  fields -= 1
 if path == "farming":
  for i in 2+ctx.L: _lot(ctx,c+Vector2.from_angle(ctx.rng.randf()*TAU)*ctx.rng.randf_range(fr0,farm_r),ctx.rng.randf()*TAU,"path_farming",false,false)
 # Docks, ships and warehouses on the nearest coast.
 if chains.has("port"):
  var pc = sd.chains.port
  var shore = _find(ctx,c,["water"],float(pc.search))
  if shore != null:
   var out_dir = (shore-c).normalized()
   var lv = int(chains.port)
   for i in int(pc.docks)*lv:
    var side = out_dir.orthogonal()*(i-(int(pc.docks)*lv-1)*0.5)*5.5
    _put(ctx,"kit.dock",shore+side,out_dir.angle(),1.0,{"water":false})
   if lv>=2: _put(ctx,"kit.port",shore-out_dir*4.0,out_dir.angle())
   for i in int(pc.ships)*lv: _put(ctx,"commerce.ship",shore+out_dir*(9.0+i*6.0)+out_dir.orthogonal()*(i*4.0-2.0),out_dir.angle(),1.0,{"water":true})
 # Shrines and watchtowers.
 if chains.has("temple") and ctx.style in ["organic","grid","terraces","river"]:
  for i in int(sd.chains.temple.shrines)*int(chains.temple): _put(ctx,"kit.shrine",c+Vector2.from_angle(i*2.4+0.2)*(fr0+2.0),0.0)
 if chains.has("watchtower"):
  for i in int(sd.chains.watchtower.watch)*int(chains.watchtower):
   var a = ctx.roads[i%ctx.roads.size()]
   _lot(ctx,c+Vector2.from_angle(a)*(farm_r*0.8)+Vector2.from_angle(a+PI*0.5)*5.0,a,"tower",false,false,0.8)

# Hamlets and fields in the countryside ring (data/settlement_sprawl.json "hamlets"; owner
# 2026-10-06): a few clusters of houses with fences and fields near the roads out of town, and more
# fields on open ground, all inside the settlement's own footprint circle (countryside: true marks
# them; tests/test_footprints.gd lets them reach the countryside ring, never beyond).
static func _hamlets(ctx: Dictionary):
 var hd = sprawl_data().get("hamlets",{})
 if hd.is_empty(): return
 var fp = sprawl_data().footprint
 var t = str(ctx.s.get("type","city"))
 var R = float(fp.radius.get(t,60))
 var r0 = R*float(hd.ring[0])
 var r1 = R+float(fp.countryside)*float(hd.ring[1])
 var c: Vector2 = ctx.center
 var rng: RandomNumberGenerator = ctx.rng
 var count = int(hd.count.get(t,[1,1,1])[ctx.L-1])
 var colors = sprawl_data().colors.fields
 var farming = path_of(ctx.s) == "farming"
 var field = func(p: Vector2,a: float) -> bool:
  if _cls(ctx,p) != "open" or not _free(ctx,p,3.0) or p.distance_to(c)>r1-6.0: return false
  var sz = rng.randf_range(5.0,7.5)
  ctx.out.append({"piece":"kit.field","culture":ctx.to,"ruin":false,"pos":p,"rot":a,"scale":Vector3(sz,1,sz*rng.randf_range(0.7,1.3)),"color":Color(colors[rng.randi_range(0,colors.size()-1)]),"countryside":true})
  _take(ctx,p,2.5)
  return true
 for k in count:
  # Near a road out of town, part way across the ring.
  var a = ctx.roads[k%ctx.roads.size()]+rng.randf_range(0.35,0.8)*(1.0 if k%2 == 0 else -1.0)
  var hc = c+Vector2.from_angle(a)*rng.randf_range(r0+4.0,r1-10.0)
  if not _land(ctx,hc): continue
  var before = ctx.out.size()
  for i in rng.randi_range(int(hd.houses[0]),int(hd.houses[1])):
   var p = hc+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(1.5,6.5)
   _lot(ctx,p,(hc-p).angle()+rng.randf_range(-0.4,0.4),"hut" if rng.randf()<0.4 else "house",false,false)
  for i in 2: _put(ctx,"kit.fence",hc+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(6.0,8.5),rng.randf()*TAU)
  for i in rng.randi_range(int(hd.fields[0]),int(hd.fields[1])):
   for tries in 6:
    if field.call(hc+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(9.0,16.0),rng.randf()*TAU): break
  for i in range(before,ctx.out.size()): ctx.out[i].countryside = true
 var extra = int(hd.extra_fields[ctx.L-1])*(2 if farming else 1)
 var tries = extra*5
 while extra>0 and tries>0:
  tries -= 1
  var a = rng.randf()*TAU
  if field.call(c+Vector2.from_angle(a)*rng.randf_range(r0,r1-6.0),a+PI*0.5): extra -= 1

# The path's signature building: placed first and always (on the nearest dry ground).
static func _sig(ctx: Dictionary,at: Vector2,path: String):
 var p = at
 var tries = 0
 while not _land(ctx,p) and tries<12:
  p = p.lerp(ctx.center,0.15)
  tries += 1
 _lot(ctx,p,(ctx.center-p).angle(),"path_"+path,true,false)

# The nearest point (searching outward in rings) whose terrain class is one of `classes`, or null.
static func _find(ctx: Dictionary,center: Vector2,classes: Array,search: float):
 var d = 10.0
 while d<=search:
  var n = int(maxf(12.0,TAU*d/5.0))
  for i in n:
   var p = center+Vector2.from_angle(i*TAU/n)*d
   if _cls(ctx,p) in classes: return p
  d += 4.0
 return null
