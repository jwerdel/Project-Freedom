extends GutTest
# Unit types load from data/units/, build their visual through the manifest, render a card
# portrait, and the map commander's army references only known unit types.

const UnitTypes = preload("res://core/unit_types.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const EXPECTED = ["archers","cavalry","commander","heavy_infantry","peasant_levy","spearmen","swordsmen"]

func after_each():
 UnitTypes.reset()

func generic_ids() -> Array:
 return UnitTypes.ids().filter(func(id): return str(UnitTypes.get_type(id).get("culture","")) == "")

func test_all_expected_unit_types_exist():
 assert_eq(generic_ids(),EXPECTED)

# The culture rosters (docs/v1-content.md §1, generated from data/rosters.json): every culture has at
# least a levy, a line, an anti-large, a missile, a cavalry or fast unit, an elite and 1-3 monsters;
# the three playable human rosters are complete (§1.2-1.4).
func test_culture_rosters_cover_every_role():
 var rosters = JSON.parse_string(FileAccess.get_file_as_string("res://data/rosters.json"))
 var counts = {"medieval":17,"roman":16,"greek":15}
 for cul in rosters.cultures:
  var units = UnitTypes.ids().filter(func(id): return str(UnitTypes.get_type(id).get("culture","")) == cul)
  assert_eq(units.size(),rosters.cultures[cul].units.size(),cul+" units generated")
  if counts.has(cul): assert_eq(units.size(),counts[cul],cul+" roster complete")
  var roles = units.map(func(id): return str(UnitTypes.get_type(id).role))
  assert_has(roles,"levy",cul)
  assert_true(roles.has("line") or roles.has("shock"),cul+" line")
  assert_has(roles,"anti_large",cul)
  assert_true(roles.has("missile") or roles.has("skirmish"),cul+" missile")
  assert_true(roles.has("cav_shock") or roles.has("cav_skirmish") or roles.has("skirmish") or roles.has("flying"),cul+" fast")
  assert_true(units.any(func(id): return int(UnitTypes.get_type(id).tier)>=3),cul+" elite")
  var monsters = roles.filter(func(r): return r in ["monster","monster_cav","flying"]).size()
  assert_between(monsters,1,4,cul+" monsters")
  for id in units:
   var u = UnitTypes.get_type(id)
   assert_true(u.battle.melee_attack>0 and u.recruitment.cost>0 and u.placeholder_stats.upkeep>0,id)

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
 for id in generic_ids():
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
 var army = UnitTypes.army("aurek_host") # the starting composition file
 assert_eq(army.commander.unit,"commander")
 assert_between(army.units.size(),7,10)
 for entry in army.units: assert_true(UnitTypes.all().has(entry.unit))
