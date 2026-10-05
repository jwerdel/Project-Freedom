extends RefCounted
# Procedural settlement sprawl (owner decisions 2026-10-04, game-design §12.13 A-C; design doc
# Addendum A). layout() turns one settlement into a placement list of kit pieces: the wall ring
# with towers and gates, district rings, a central plaza, suburbs along the converging roads,
# outlying villages, the farm belt, and the countryside features of its building chains (fields,
# mines in the hills, docks on the coast, yards, shrines, stalls). Every level grows every ring.
# Pieces respect the terrain (callable terrain_at(Vector2) -> class name) and, while the region's
# land is converting, come from the old or the new culture (old ones turning to ruins first).
# Deterministic: all randomness is seeded from the settlement id. Presentation only.

const SPRAWL = "res://data/settlement_sprawl.json"
const CULTURES = "res://data/cultures.json"

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

# s: {id, type, level, position: Vector2, from, to, value (land conversion 0-1), buildings: [{chain,
# level}], landmark_radius (0 = none)}. Returns [{piece, culture, ruin, pos: Vector2, rot, scale:
# Vector3, color: Color}].
static func layout(s: Dictionary,terrain_at: Callable) -> Array:
 var L = clampi(int(s.get("level",1)),1,3)
 var types = sprawl_data().types
 var cfg = types.get(s.get("type","city"),types.city)[L-1]
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(["sprawl",s.id])
 var out = []
 var ctx = {"s":s,"rng":rng,"out":out,"terrain":terrain_at,"band":float(culture_data().conversion.ruin_band)}
 var center: Vector2 = s.position
 var lm = float(s.get("landmark_radius",0.0))
 var chains = {}
 for b in s.get("buildings",[]):
  if b.has("chain") and int(b.get("level",0))>0: chains[b.chain] = maxi(int(chains.get(b.chain,0)),int(b.level))
 var R = float(cfg.get("wall",0))
 if lm>0.0: R = 0.0 # a landmark keeps its own model at the centre: no wall ring through it
 var roads = int(cfg.roads)
 var base_a = rng.randf()*TAU
 var road_a = []
 for i in roads: road_a.append(base_a+i*TAU/roads+rng.randf_range(-0.2,0.2))
 var plaza = maxf(float(cfg.plaza),lm)
 # Centre: keeps for fortresses and castles, a temple or a tall house otherwise, and market stalls.
 if lm<=0.0:
  var keeps = int(cfg.get("keeps",0))
  if keeps>0:
   _put(ctx,"keep",center,rng.randf()*TAU,1.0)
   for k in range(1,keeps):
    _put(ctx,"tower",center+Vector2.from_angle(k*TAU/(keeps-1)+0.3)*plaza*0.7,rng.randf()*TAU,1.0)
  elif chains.has("temple") or L>=2: _put(ctx,"temple",center,rng.randf()*TAU,1.0)
  else: _put(ctx,"tall",center,rng.randf()*TAU,1.0)
 var stalls = int(sprawl_data().chains.market.stalls)*int(chains.get("market",0))
 for i in stalls: _put(ctx,"kit.stall",center+Vector2.from_angle(i*TAU/maxi(1,stalls)+0.4)*(plaza+0.8),rng.randf()*TAU,1.0)
 # Districts: house rings from the plaza to the walls (or most of the suburb radius without walls).
 var inner_end = (R-3.2) if R>0.0 else float(cfg.suburb)*0.6
 var gap = float(cfg.house_gap)*(1.0-float(sprawl_data().chains.houses.houses)*int(chains.get("houses",0)))
 var r = plaza+2.6
 while r<=inner_end:
  var n = int(floor(TAU*r/gap))
  for i in n:
   var a = i*TAU/n+rng.randf_range(-0.04,0.04)
   if _on_street(a,r,road_a,2.0): continue
   if rng.randf()<0.12: continue
   _put(ctx,"tall" if rng.randf()<0.14 else "house",center+Vector2.from_angle(a)*(r+rng.randf_range(-0.5,0.5)),a+PI*0.5+rng.randf_range(-0.2,0.2),1.0)
  r += 3.7
 # Walls: rings of segments with towers and a gate where each road leaves.
 if R>0.0:
  var every = maxi(1,int(cfg.get("towers_every",4))-int(chains.get("walls",0))/2)
  var pal = bool(cfg.get("palisade",false))
  for ring in int(cfg.get("wall_rings",1)):
   var rr = R+ring*5.5
   var n = int(round(TAU*rr/float(sprawl_data().piece_size.wall)))
   for i in n:
    var a = i*TAU/n
    var p = center+Vector2.from_angle(a)*rr
    var role = "wall"
    if _on_street(a,rr,road_a,1.7): role = "gate"
    elif i%every == 0: role = "tower"
    if pal and role != "tower": role = "kit.palisade"
    _put(ctx,role,p,a+PI*0.5,1.0)
 # Roads from the plaza out through the farm belt.
 var farm_r = float(cfg.farm)
 for a in road_a:
  var d = plaza
  while d<farm_r:
   var p = center+Vector2.from_angle(a)*(d+3.0)
   if _land(ctx,p): out.append({"piece":"kit.road","culture":s.get("to","medieval"),"ruin":false,"pos":p,"rot":a+PI*0.5,"scale":Vector3(2.4,1,6.2),"color":Color(sprawl_data().colors.road)})
   d += 6.0
 # Suburbs: houses along both sides of each road, past the walls.
 var sub_start = (R+4.0) if R>0.0 else inner_end+2.0
 for a in road_a:
  var d = sub_start
  while d<float(cfg.suburb):
   for side in [-1.0,1.0]:
    if rng.randf()<0.3: continue
    var p = center+Vector2.from_angle(a)*d+Vector2.from_angle(a+PI*0.5)*side*rng.randf_range(3.2,5.5)
    _put(ctx,"house",p,a+rng.randf_range(-0.3,0.3),1.0)
   d += 4.0
 # Outlying villages, between the roads.
 for v in int(cfg.villages):
  var a = base_a+(v+0.5)*TAU/maxi(1,roads)+rng.randf_range(-0.25,0.25)
  var vc = center+Vector2.from_angle(a)*float(cfg.village_radius)
  if not _land(ctx,vc): continue
  for h in rng.randi_range(5,7): _put(ctx,"hut" if rng.randf()<0.5 else "house",vc+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(1.5,6.0),rng.randf()*TAU,1.0)
  _put(ctx,"kit.farmstead",vc+Vector2.from_angle(a)*7.0,a,1.0)
 # The farm belt: a patchwork of fields on open ground between the roads.
 var fields = 8*L+int(sprawl_data().chains.farm.fields)*int(chains.get("farm",0))
 var fr0 = maxf(float(cfg.suburb)+2.0,R+6.0)
 var tries = fields*4
 var colors = sprawl_data().colors.fields
 while fields>0 and tries>0:
  tries -= 1
  var a = rng.randf()*TAU
  var d = rng.randf_range(fr0,farm_r+6.0)
  if _on_street(a,d,road_a,4.5): continue
  var p = center+Vector2.from_angle(a)*d
  if str(terrain_at.call(p)) != "open": continue
  var sz = rng.randf_range(5.0,7.5)
  out.append({"piece":"kit.field","culture":s.get("to","medieval"),"ruin":false,"pos":p,"rot":a+rng.randf_range(-0.3,0.3),"scale":Vector3(sz,1,sz*rng.randf_range(0.7,1.3)),"color":Color(colors[rng.randi_range(0,colors.size()-1)])})
  fields -= 1
 for i in int(sprawl_data().chains.farm.farmsteads)*int(chains.get("farm",0)): _put(ctx,"kit.farmstead",center+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(fr0,farm_r),rng.randf()*TAU,1.0)
 # Mines in the hills.
 if chains.has("mine"):
  var m = sprawl_data().chains.mine
  var spot = _find(ctx,center,["hills","pass","mountain"],float(m.search))
  if spot != null:
   var lv = int(chains.mine)
   var toward = (center-spot).normalized()
   var site = spot+toward*3.0 if str(terrain_at.call(spot)) == "mountain" else spot
   for i in int(m.mines)*lv: _put(ctx,"kit.mine",site+Vector2.from_angle(i*2.1)*i*6.0,toward.angle()+PI*0.5,1.0)
   for i in int(m.spoil)*lv: _put(ctx,"kit.spoil",site+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(5.0,11.0),rng.randf()*TAU,rng.randf_range(0.8,1.3))
   for i in int(m.pits)*lv: _put(ctx,"kit.pit",site+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(4.0,9.0),0.0,1.0)
   for i in int(m.carts)*lv: _put(ctx,"kit.cart",site.lerp(center,rng.randf_range(0.25,0.6)),toward.angle()+PI*0.5,1.0)
 # Docks, ships and warehouses on the nearest coast.
 if chains.has("port"):
  var pc = sprawl_data().chains.port
  var shore = _find(ctx,center,["water"],float(pc.search))
  if shore != null:
   var out_dir = (shore-center).normalized()
   var lv = int(chains.port)
   for i in int(pc.docks)*lv:
    var side = out_dir.orthogonal()*(i-(int(pc.docks)*lv-1)*0.5)*5.5
    _put(ctx,"kit.dock",shore+side,out_dir.angle()+PI*0.5,1.0,true)
   if lv>=2: _put(ctx,"kit.port",shore-out_dir*4.0,out_dir.angle()+PI*0.5,1.0,true)
   for i in int(pc.ships)*lv: out.append({"piece":"commerce.ship","culture":s.get("to","medieval"),"ruin":false,"pos":shore+out_dir*(9.0+i*6.0)+out_dir.orthogonal()*(i*4.0-2.0),"rot":out_dir.angle(),"scale":Vector3.ONE,"color":Color.WHITE,"water":true})
   for i in int(pc.warehouses)*lv: _put(ctx,"kit.warehouse",shore-out_dir*(9.0+i*5.5),out_dir.angle(),1.0)
 # Military yards near the first gate, outside the walls.
 for ch in ["barracks","archery_range","stables"]:
  if not chains.has(ch): continue
  var y = sprawl_data().chains[ch]
  var ga = road_a[0]+0.55*(1 if ch == "barracks" else (-1 if ch == "stables" else 2))
  var yc = center+Vector2.from_angle(ga)*(maxf(R,plaza)+7.0)
  for i in int(y.tents)*int(chains[ch]): _put(ctx,"kit.tent",yc+Vector2(i%3*3.4,i/3*4.0).rotated(ga),ga,1.0)
  for i in int(y.fences)*int(chains[ch]): _put(ctx,"kit.fence",yc+Vector2.from_angle(ga+PI*0.5)*6.0+Vector2(0,i*3.0).rotated(ga),ga,1.0)
 # Shrines around the centre; watchtowers out on the roads.
 if chains.has("temple"):
  for i in int(sprawl_data().chains.temple.shrines)*int(chains.temple): _put(ctx,"kit.shrine",center+Vector2.from_angle(i*TAU/(3.0*int(chains.temple))+0.2)*(plaza+1.5),0.0,1.0)
 if chains.has("watchtower"):
  for i in int(sprawl_data().chains.watchtower.watch)*int(chains.watchtower):
   var a = road_a[i%road_a.size()]
   _put(ctx,"kit.watchtower",center+Vector2.from_angle(a)*(maxf(R,float(cfg.suburb))+6.0)+Vector2.from_angle(a+PI*0.5)*5.0,a,1.0)
 # Carts on the roads (market).
 for i in int(sprawl_data().chains.market.carts)*int(chains.get("market",0)):
  var a = road_a[i%road_a.size()]
  _put(ctx,"kit.cart",center+Vector2.from_angle(a)*rng.randf_range(sub_start,float(cfg.suburb))+Vector2.from_angle(a+PI*0.5)*1.6,a,1.0)
 return out

# One piece. role: a culture role (house, tall, wall, tower, gate, keep, temple, hut) or a kit id.
# While the land converts, each piece is the new culture's, a ruin of the old one's, or the old one's.
static func _put(ctx: Dictionary,role: String,p: Vector2,rot: float,sc: float,on_coast := false):
 if not on_coast and not _land(ctx,p): return
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
 if not role.begins_with("kit."):
  var kit = culture(cul).kit
  var choice = kit.get(role,kit.house)
  piece = choice[rng.randi_range(0,choice.size()-1)] if choice is Array else str(choice)
 var tint_key = "stone" if role in ["wall","tower","gate","keep","temple"] else "house"
 var col = Color(culture(cul).tint.get(tint_key,"#ffffff"))
 if ruin: col = Color(culture(cul).tint.ruin)
 ctx.out.append({"piece":piece,"culture":cul,"ruin":ruin,"pos":p,"rot":rot,"scale":Vector3.ONE*sc,"color":col})

static func _land(ctx: Dictionary,p: Vector2) -> bool:
 var t = str(ctx.terrain.call(p))
 return t != "water" and t != "mountain" and t != ""

# A street gap: is the angle within `half_width` metres of a road at this radius?
static func _on_street(a: float,r: float,road_a: Array,half_width: float) -> bool:
 for ra in road_a:
  if absf(angle_difference(a,ra))*r<half_width: return true
 return false

# The nearest point (searching outward in rings) whose terrain class is one of `classes`, or null.
static func _find(ctx: Dictionary,center: Vector2,classes: Array,search: float):
 var d = 10.0
 while d<=search:
  var n = int(maxf(12.0,TAU*d/5.0))
  for i in n:
   var p = center+Vector2.from_angle(i*TAU/n)*d
   if str(ctx.terrain.call(p)) in classes: return p
  d += 4.0
 return null
