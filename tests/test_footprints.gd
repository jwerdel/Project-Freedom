extends GutTest
# The no-overlap rule (owner, 2026-10-06): every settlement's sprawl at max level (walls, suburbs,
# villages, farms and industry props, any culture and specialization) stays inside its footprint
# radius (data/settlement_sprawl.json "footprint"), and the validator fails when two footprints
# (radius + countryside ring) touch.

const Sprawl = preload("res://map/sprawl.gd")
const Validator = preload("res://map/validator.gd")
const MapRegistry = preload("res://core/map_registry.gd")

func test_max_level_sprawl_stays_inside_its_footprint():
 var fp = Sprawl.sprawl_data().footprint
 var flat = func(_p): return "open"
 for t in fp.radius:
  var worst = 0.0
  for c in Sprawl.culture_data().cultures:
   for b in [[],[{"chain":"farm","level":3}],[{"chain":"mine","level":3}],[{"chain":"barracks","level":3}]]:
    var s = {"id":"fp_%s_%s_%d" % [t,c,b.size()],"type":t,"level":3,"position":Vector2.ZERO,"from":c,"to":c,"value":1.0,"buildings":b}
    for e in Sprawl.layout(s,flat): worst = maxf(worst,Vector2(e.pos).length()+maxf(e.scale.x,e.scale.z)*1.5)
  assert_lte(worst,float(fp.radius[t]),"%s sprawl reaches %.1f m" % [t,worst])

func test_footprints_hold_on_the_test_map():
 var v = Validator.validate(MapRegistry.DEFAULT)
 assert_eq(v.problems.filter(func(p): return p.check == "footprints"),[])
