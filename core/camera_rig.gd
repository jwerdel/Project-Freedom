extends RefCounted
# Campaign camera rules (TW:WH3 plus its popular camera mods; owner, 2026-10-06): one continuous
# scroll from close (a lord and a city's streets) to a high, nearly top-down overview of most of the
# world; only scrolling out past that maximum opens the strategic map. Pure functions over
# data/campaign_view.json "camera", so the curve and the switch are testable without the scene.
#  - max_distance: the farthest 3D zoom for a map, max_fraction of its longer side (never below
#    max_floor, so the small test map keeps its old range).
#  - pitch_at: the tilt follows the zoom on one smooth curve through pitch_close (closest),
#    pitch_mid (halfway on a log scale) and pitch_far (the maximum), in degrees.
#  - high_zoom: 0 below high_from and 1 at the maximum (log scale); fog, the territory wash, labels
#    and figures read it.

static var _cfg := {}

static func cfg() -> Dictionary:
 if _cfg.is_empty(): _cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_view.json")).camera
 return _cfg

static func min_distance() -> float:
 return float(cfg().min_distance)

static func max_distance(map_size: Vector2) -> float:
 return maxf(float(cfg().max_floor),float(cfg().max_fraction)*maxf(map_size.x,map_size.y))

# 0 at the closest zoom, 1 at the farthest, on a log scale (each wheel step is the same fraction).
static func zoom_t(d: float,maxd: float) -> float:
 var lo = min_distance()
 return clampf(log(maxf(d,lo)/lo)/log(maxf(maxd,lo*1.01)/lo),0.0,1.0)

# Camera tilt in radians at zoom distance d: a quadratic through the three data points, which rises
# monotonically for any close < mid < far with mid below their midpoint plus a quarter of the span.
static func pitch_at(d: float,maxd: float) -> float:
 var t = zoom_t(d,maxd)
 var c = float(cfg().pitch_close)
 var m = float(cfg().pitch_mid)
 var f = float(cfg().pitch_far)
 # p(t) = c + b t + a t^2 with p(0.5) = m and p(1) = f.
 var a = 2.0*(f+c)-4.0*m
 var b = f-c-a
 return deg_to_rad(c+b*t+a*t*t)

static func high_zoom(d: float,maxd: float) -> float:
 return smoothstep(float(cfg().high_from),1.0,zoom_t(d,maxd))

# One wheel step. Returns {distance, strategic}: scrolling out at the farthest zoom opens the
# strategic map instead of zooming further.
static func wheel(d: float,maxd: float,zoom_in: bool) -> Dictionary:
 var step = float(cfg().wheel_step)
 if zoom_in: return {"distance":maxf(min_distance(),d/step),"strategic":false}
 if d>=maxd*0.995: return {"distance":maxd,"strategic":true}
 return {"distance":minf(maxd,d*step),"strategic":false}

# Pan speed (metres per second per unit of input) at a zoom distance: proportional to the height,
# so a pan crosses the same share of the screen at every zoom.
static func pan_speed(d: float,fast: bool) -> float:
 return d*(float(cfg().pan_fast) if fast else float(cfg().pan))

# Edge pan direction (x right, y down on screen; zero inside the band) for a mouse position.
static func edge_dir(mouse: Vector2,view: Vector2) -> Vector2:
 var band = float(cfg().edge_px)
 if mouse.x<0.0 or mouse.y<0.0 or mouse.x>view.x or mouse.y>view.y: return Vector2.ZERO
 var v = Vector2.ZERO
 if mouse.x<=band: v.x = -1.0
 elif mouse.x>=view.x-band: v.x = 1.0
 if mouse.y<=band: v.y = -1.0
 elif mouse.y>=view.y-band: v.y = 1.0
 return v

# Where the camera's target goes when zooming from d to nd toward the ground point under the cursor
# (TW:WH3 zooms toward the cursor): the cursor's ground point stays put on screen.
static func zoom_toward(target: Vector3,cursor_ground: Vector3,d: float,nd: float) -> Vector3:
 var k = 1.0-nd/maxf(d,0.001)
 return target+(cursor_ground-target)*Vector3(k,0.0,k)

# The camera distance that frames a world rectangle from nearly straight above (fov in degrees,
# aspect = width / height), with a margin.
static func frame_distance(rect_size: Vector2,fov_deg: float,aspect: float) -> float:
 var half = tan(deg_to_rad(fov_deg)*0.5)
 var need_v = rect_size.y/(2.0*half)
 var need_h = rect_size.x/(2.0*half*maxf(aspect,0.1))
 return maxf(need_v,need_h)*float(cfg().frame_margin)
