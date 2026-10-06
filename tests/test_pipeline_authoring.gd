extends GutTest
# The authoring pipeline (docs/map-pipeline-design.md §2-5): the SVG sketch parser, the build of an
# authored map (the test map rebuilt as testmap_pipeline), determinism, the committed-bake check,
# and the validator (one broken copy per check).

const Sketch = preload("res://map/sketch.gd")
const Pipeline = preload("res://map/pipeline.gd")
const Validator = preload("res://map/validator.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const MAP = "testmap_pipeline"

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_sketch_parser_reads_the_supported_subset():
 var svg = """<svg xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape">
 <g inkscape:groupmode="layer" id="land"><polygon id="isle" points="0,0 10,0 10,10 0,10"/></g>
 <g inkscape:groupmode="layer" id="rivers"><path id="r1" data-width="3" d="M 1,1 l 2,0 C 4,1 5,2 6,3 Q 7,4 8,4 H 9 V 8"/></g>
 <g inkscape:groupmode="layer" id="sites"><circle id="town" cx="5" cy="5" r="2"/></g>
</svg>"""
 var s = Sketch.parse(svg)
 assert_eq(s.errors,[])
 assert_eq(s.layers.land[0].points.size(),4)
 var r = s.layers.rivers[0]
 assert_eq(r.data.width,"3")
 assert_eq(r.points[1],Vector2(3,1),"relative line-to")
 assert_eq(r.points[-1],Vector2(9,8),"H then V")
 assert_gt(r.points.size(),10,"curves flattened")
 assert_eq(s.layers.sites[0].center,Vector2(5,5))

func test_sketch_parser_rejects_what_it_does_not_support():
 var bad = """<svg><g id="land"><rect id="box" x="0" y="0" width="5" height="5"/><path id="arc" d="M 0,0 A 5 5 0 0 1 10 10"/><polygon id="moved" transform="translate(5,0)" points="0,0 1,0 1,1"/></g></svg>"""
 var s = Sketch.parse(bad)
 assert_eq(s.errors.size(),3,str(s.errors))
 for id in ["box","arc","moved"]: assert_true(s.errors.any(func(e): return e.contains(id)),id+" named in its error")

func test_testmap_pipeline_builds_validates_and_matches_the_legacy_map():
 var r = Pipeline.build(MAP)
 assert_eq(r.errors,[])
 var v = Validator.validate(MAP)
 assert_eq(v.errors,0,str(v.problems))
 MapRegistry.set_active(MAP)
 var WorldMap = load("res://core/world_map.gd")
 WorldMap.reset()
 for id in ["greyhaven","willowmere","crownwatch","goldspire_rock"]:
  var p = WorldMap.settlement_position(id)
  assert_eq(WorldMap.region_at(p),id,id+" lies in its own region")
 assert_eq(WorldMap.region_at(Vector2(0,-275)),"greyspine","the range's region")
 var Movement = load("res://core/movement.gd")
 Movement.reset()
 assert_eq(Movement.terrain_at(Vector2(0,250)),"water","the sea south of the coast")
 assert_eq(Movement.terrain_at(Vector2(75,-220)),"mountain","the Greyspine ridge")
 assert_eq(Movement.terrain_at(Vector2(108,-200)),"pass","the Greyspine Pass")

func test_build_is_deterministic_and_the_bake_check_catches_stale_bakes():
 Pipeline.build(MAP)
 var a = FileAccess.get_file_as_bytes(MapRegistry.path("baked/movement.bin",MAP))
 Pipeline.build(MAP)
 assert_eq(FileAccess.get_file_as_bytes(MapRegistry.path("baked/movement.bin",MAP)),a,"same sources, same bakes")
 var stamp_path = MapRegistry.path("baked/sources.json",MAP)
 var keep = FileAccess.get_file_as_string(stamp_path)
 var f = FileAccess.open(stamp_path,FileAccess.WRITE)
 f.store_string('{"hash":"0"}')
 f.close()
 var v = Validator.validate(MAP)
 assert_true(v.problems.any(func(p): return p.check == "bakes"),"stale bakes are an error")
 f = FileAccess.open(stamp_path,FileAccess.WRITE)
 f.store_string(keep)
 f.close()

func broken(change: Callable) -> Array:
 var prov = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("provinces.json",MAP)))
 var fac = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("factions.json",MAP)))
 var meta = MapRegistry.meta(MAP).duplicate(true)
 change.call(prov,fac,meta)
 return Validator.validate(MAP,{"provinces":prov,"factions":fac,"meta":meta}).problems.map(func(p): return p.check)

func test_validator_catches_each_broken_copy():
 assert_has(broken(func(p,_f,_m): p.provinces[0].regions.append("nowhere")),"ids")
 assert_has(broken(func(p,_f,_m): p.regions.greyhaven.owner = "house_nobody"),"ids")
 assert_has(broken(func(p,_f,_m): p.provinces[1].regions.append("greyhaven")),"ids","a region in two provinces")
 assert_has(broken(func(_p,_f,m): m.allow_legacy_majors = false),"majors","village and town majors only on the test map")
 assert_has(broken(func(p,_f,_m): p.regions.willowmere.settlement.position = [-55,35]),"footprints")
 assert_has(broken(func(p,_f,_m): p.regions.willowmere.settlement.position = [0,100]),"settlements","a settlement in the sea")
 assert_has(broken(func(p,_f,_m): p.regions.willowmere.culture = {"roman":0.5,"greek":0.2}),"shares")
 assert_has(broken(func(p,_f,_m): p.regions.greyhaven.settlement.landmark = "atlantis"),"landmarks")
 assert_has(broken(func(p,_f,_m): p.provinces[0].regions = ["willowmere","crownwatch"]; p.provinces[0].capital = "willowmere"; p.provinces[1].regions = ["greyhaven"]; p.provinces[1].capital = "greyhaven"),"provinces","two regions that do not touch")
