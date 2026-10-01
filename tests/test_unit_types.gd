extends GutTest
# Unit types load from data/units/, build their visual through the manifest, render a card
# portrait, and the map commander's army references only known unit types.

const UnitTypes = preload("res://core/unit_types.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const EXPECTED = ["archers","cavalry","commander","heavy_infantry","peasant_levy","spearmen","swordsmen"]

func after_each():
 UnitTypes.reset()

func test_all_expected_unit_types_exist():
 assert_eq(UnitTypes.ids(),EXPECTED)

func test_unit_types_have_required_fields_and_placeholder_stats():
 for id in UnitTypes.ids():
  var u = UnitTypes.get_type(id)
  for key in UnitTypes.REQUIRED: assert_true(u.has(key),"%s missing %s" % [id,key])
  assert_string_contains(u.placeholder_stats._note,"PLACEHOLDER")

func test_every_unit_visual_builds():
 for id in UnitTypes.ids():
  var holder = Node3D.new()
  add_child_autofree(holder)
  var node = UnitTypes.build_visual(UnitTypes.get_type(id),holder)
  await wait_process_frames(1)
  assert_gt(node.find_children("*","MeshInstance3D",true,false).size(),0,"%s built no meshes" % id)

func test_infantry_types_differ_in_loadout_or_outfit():
 var seen = {}
 for id in UnitTypes.ids():
  var u = UnitTypes.get_type(id)
  var look = [u.visual,u.outfit,u.loadout]
  assert_false(seen.has(str(look)),"%s looks like %s" % [id,seen.get(str(look),"")])
  seen[str(look)] = id

func test_every_unit_renders_a_portrait():
 var studio = PortraitStudio.new()
 add_child_autofree(studio)
 await wait_process_frames(1)
 var headless = DisplayServer.get_name() == "headless"
 for id in UnitTypes.ids():
  var tex = await studio.render(id)
  assert_not_null(tex,"%s: no portrait" % id)
  assert_eq(tex.get_size(),Vector2(PortraitStudio.SIZE),"%s: portrait size" % id)
  if headless:
   pass_test("%s: headless renderer, pixels not checked" % id)
  else:
   # A real render has transparent background and an opaque figure.
   var img = tex.get_image()
   assert_lt(img.get_pixel(2,2).a,0.05,"%s: background should be transparent" % id)
   var opaque = 0
   for y in range(0,img.get_height(),6):
    for x in range(0,img.get_width(),6):
     if img.get_pixel(x,y).a>0.9: opaque += 1
   assert_gt(opaque,40,"%s: portrait looks empty" % id)

func test_portrait_cache_key_changes_with_the_visual():
 var studio = PortraitStudio.new()
 add_child_autofree(studio)
 var unit = UnitTypes.get_type("spearmen").duplicate(true)
 var before = studio.cache_key(unit)
 unit.loadout = ["weapon.sword","weapon.shield_round"]
 assert_ne(studio.cache_key(unit),before,"changing the loadout must invalidate the cached portrait")

func test_commander_army_has_about_eight_known_units():
 var army = UnitTypes.army("aurek_host")
 assert_eq(army.commander.unit,"commander")
 assert_between(army.units.size(),7,10)
 for entry in army.units: assert_true(UnitTypes.all().has(entry.unit))
