extends GutTest
# The campaign camera (core/camera_rig.gd, owner 2026-10-06): one continuous scroll from close to a
# high, nearly top-down view; the tilt follows the zoom on a smooth curve (about 40 degrees close,
# 60 mid, 85-89 at the top); only scrolling out at the maximum opens the strategic map; the maximum
# comes from the map's size.

const CameraRig = preload("res://core/camera_rig.gd")

func test_pitch_curve_is_smooth_and_hits_its_marks():
 var maxd = 7040.0
 var lo = CameraRig.min_distance()
 assert_almost_eq(rad_to_deg(CameraRig.pitch_at(lo,maxd)),40.0,0.5,"about 40 degrees close in")
 var mid = lo*sqrt(maxd/lo) # halfway on the log scale
 assert_almost_eq(rad_to_deg(CameraRig.pitch_at(mid,maxd)),60.0,0.5,"about 60 degrees mid zoom")
 var top = rad_to_deg(CameraRig.pitch_at(maxd,maxd))
 assert_between(top,85.0,89.0,"nearly top-down at the maximum")
 # Monotonic and without steps: small zoom changes give small tilt changes.
 var prev = CameraRig.pitch_at(lo,maxd)
 var d = lo
 while d<maxd:
  d = minf(maxd,d*1.02)
  var p = CameraRig.pitch_at(d,maxd)
  assert_true(p>=prev-0.0001,"never flattens while zooming out")
  assert_lt(p-prev,deg_to_rad(1.0),"no steps")
  prev = p

func test_maximum_zoom_follows_the_map_size():
 assert_almost_eq(CameraRig.max_distance(Vector2(14080,11520)),7040.0,1.0,"Varos: about 7 km up")
 assert_eq(CameraRig.max_distance(Vector2(300,300)),210.0,"never below the old maximum")
 assert_gt(CameraRig.max_distance(Vector2(700,700)),210.0)

func test_only_scrolling_out_at_the_maximum_opens_the_strategic_map():
 var maxd = 7040.0
 var d = 50.0
 var steps = 0
 while true:
  var w = CameraRig.wheel(d,maxd,false)
  if w.strategic: break
  assert_lte(w.distance,maxd)
  d = w.distance
  steps += 1
  assert_lt(steps,200)
 assert_almost_eq(d,maxd,0.01,"the strategic map opens only from the maximum")
 assert_gt(steps,20,"a long continuous scroll from close to the top")
 var w = CameraRig.wheel(maxd,maxd,true)
 assert_false(w.strategic)
 assert_lt(w.distance,maxd,"scrolling in zooms in")
 assert_eq(CameraRig.wheel(CameraRig.min_distance(),maxd,true).distance,CameraRig.min_distance())

func test_high_zoom_look_rises_only_far_out():
 var maxd = 7040.0
 assert_eq(CameraRig.high_zoom(40.0,maxd),0.0,"none up close")
 assert_eq(CameraRig.high_zoom(maxd,maxd),1.0,"full at the top")
 assert_lt(CameraRig.high_zoom(600.0,maxd),CameraRig.high_zoom(3000.0,maxd))

func test_zoom_toward_the_cursor_keeps_its_ground_point():
 var t = Vector3(0,0,0)
 var g = Vector3(100,0,-40)
 var nt = CameraRig.zoom_toward(t,g,200.0,100.0)
 assert_almost_eq(nt,Vector3(50,0,-20),Vector3(0.01,0.01,0.01),"halving the distance halves the gap to the cursor")
 assert_eq(CameraRig.zoom_toward(t,g,200.0,200.0),t)

func test_edge_pan_and_pan_speed():
 var v = Vector2(1440,900)
 assert_eq(CameraRig.edge_dir(Vector2(700,450),v),Vector2.ZERO)
 assert_eq(CameraRig.edge_dir(Vector2(1,450),v),Vector2(-1,0))
 assert_eq(CameraRig.edge_dir(Vector2(1439,899),v),Vector2(1,1))
 assert_eq(CameraRig.edge_dir(Vector2(-5,450),v),Vector2.ZERO,"outside the window: no pan")
 assert_almost_eq(CameraRig.pan_speed(2000.0,false)/CameraRig.pan_speed(100.0,false),20.0,0.001,"pan speed scales with height")

func test_frame_distance_fits_a_rectangle():
 var d = CameraRig.frame_distance(Vector2(4000,2000),43.0,1.6)
 var half = tan(deg_to_rad(43.0)*0.5)
 assert_gte(2.0*d*half,2000.0,"fits the height")
 assert_gte(2.0*d*half*1.6,4000.0,"fits the width")
