extends RefCounted
# Territory overlay textures for the terrain shader, rasterized from the region polygons in
# data/maps/<map>/provinces.json (via core/world_map.gd):
#  - tint: RGB = owning faction's color, A = tint strength (0 for unclaimed land)
#  - border: R = faction border, G = province border (same owner), B = region border (same province)
# Each side of a border carries its own faction color in the tint, so each side glows in its color.

const WorldMap = preload("res://core/world_map.gd")
const RECT = Rect2(-140,-140,280,280) # world x/z covered (the terrain is 280 x 270)
const TINT_PER_M = 0.5 # soft tint; the border lines carry the crisp edge
const BORDER_PER_M = 3
const CORE = 0.45 # m, bright line half-width
const GLOW = 2.2 # m, soft glow reach

# Current owners (region id -> faction) when they differ from data/maps/<map>/provinces.json, e.g. after a
# settlement is captured. main.gd sets this from the campaign state and rebuilds the textures.
static var live_owners := {}

static func owner_of(id: String) -> String:
 return live_owners.get(id,WorldMap.owner_of(id))

static func rect_uniform() -> Vector4:
 return Vector4(RECT.position.x,RECT.position.y,RECT.size.x,RECT.size.y)

static func tint_texture() -> ImageTexture:
 var w = int(RECT.size.x*TINT_PER_M)
 var h = int(RECT.size.y*TINT_PER_M)
 var img = Image.create(w,h,false,Image.FORMAT_RGBA8)
 var regions = WorldMap.regions()
 for y in h:
  for x in w:
   var p = RECT.position+Vector2(x+0.5,y+0.5)/TINT_PER_M
   var id = WorldMap.region_at(p)
   if id == "": continue
   var owner = owner_of(id)
   if owner == "":
    img.set_pixel(x,y,Color(0.55,0.55,0.55,0.0))
   else:
    var c = Color(WorldMap.faction(owner).primary).lightened(0.25)
    img.set_pixel(x,y,Color(c.r,c.g,c.b,0.12))
 return ImageTexture.create_from_image(img)

# Edges shared by two regions, with the kind of border they are.
static func shared_edges() -> Array:
 var regions = WorldMap.regions()
 var ids = regions.keys()
 var out = []
 for i in ids.size():
  for j in range(i+1,ids.size()):
   var a = regions[ids[i]].points
   var b = regions[ids[j]].points
   var kind = _kind(ids[i],ids[j])
   for k in a.size():
    var p = a[k]
    var q = a[(k+1)%a.size()]
    for m in b.size():
     var r = b[m]
     var s = b[(m+1)%b.size()]
     if (p.is_equal_approx(s) and q.is_equal_approx(r)) or (p.is_equal_approx(r) and q.is_equal_approx(s)):
      out.append({"a":p,"b":q,"kind":kind})
 return out

static func _kind(r1: String,r2: String) -> int:
 if owner_of(r1) != owner_of(r2): return 0 # faction border
 if WorldMap.province_of(r1) != WorldMap.province_of(r2): return 1 # province border
 return 2 # region border

static func border_texture() -> ImageTexture:
 var w = int(RECT.size.x*BORDER_PER_M)
 var h = int(RECT.size.y*BORDER_PER_M)
 var img = Image.create(w,h,false,Image.FORMAT_RGBA8)
 img.fill(Color(0,0,0,1))
 var reach = int(ceil(GLOW*BORDER_PER_M))
 for e in shared_edges():
  var a: Vector2 = (e.a-RECT.position)*BORDER_PER_M
  var b: Vector2 = (e.b-RECT.position)*BORDER_PER_M
  var lo = a.min(b)-Vector2(reach,reach)
  var hi = a.max(b)+Vector2(reach,reach)
  for y in range(maxi(0,int(lo.y)),mini(h,int(hi.y)+1)):
   for x in range(maxi(0,int(lo.x)),mini(w,int(hi.x)+1)):
    var px = Vector2(x+0.5,y+0.5)
    var d = px.distance_to(Geometry2D.get_closest_point_to_segment(px,a,b))/BORDER_PER_M
    if d>GLOW: continue
    var v = maxf(1.0-smoothstep(CORE*0.6,CORE,d),0.4*(1.0-d/GLOW))
    var c = img.get_pixel(x,y)
    match e.kind:
     0: c.r = maxf(c.r,v)
     1: c.g = maxf(c.g,v)
     _: c.b = maxf(c.b,v)
    img.set_pixel(x,y,c)
 return ImageTexture.create_from_image(img)
