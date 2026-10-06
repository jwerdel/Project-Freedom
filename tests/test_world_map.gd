extends GutTest
# Provinces, regions and factions: lookups, ownership and that the regions tile the map.

const WorldMap = preload("res://core/world_map.gd")
const TerritoryOverlay = preload("res://visuals/terrain/territory_overlay.gd")
const SETTLEMENTS = {"greyhaven":"house_lannet","willowmere":"house_verrin","crownwatch":"house_aurek","goldspire_rock":"house_aurek"}

func after_each():
 WorldMap.reset()

func test_each_settlement_lies_in_its_own_region_with_the_expected_owner():
 for id in SETTLEMENTS:
  assert_eq(WorldMap.region_at(WorldMap.settlement_position(id)),id)
  assert_eq(WorldMap.owner_of(id),SETTLEMENTS[id])
  assert_false(WorldMap.faction(SETTLEMENTS[id]).is_empty(),"faction data for "+SETTLEMENTS[id])

func test_goldspire_rock_belongs_to_house_aurek_as_in_the_world_bible():
 assert_eq(WorldMap.owner_of("goldspire_rock"),"house_aurek")
 assert_eq(WorldMap.faction("house_aurek").seat,"Goldspire Rock")

func test_province_lookup():
 assert_eq(WorldMap.province_of("greyhaven"),"greywater_march")
 assert_eq(WorldMap.province_of("willowmere"),"greywater_march")
 assert_eq(WorldMap.province_of("crownwatch"),"crownwatch_pass")
 assert_eq(WorldMap.province_of("goldspire_rock"),"goldspire")
 assert_eq(WorldMap.settlements_in("greywater_march"),["greyhaven","willowmere"])
 assert_between(WorldMap.provinces().size(),3,4)

func test_mountains_are_unclaimed():
 assert_eq(WorldMap.region_at(Vector2(0,-225)),"greyspine")
 assert_eq(WorldMap.owner_of("greyspine"),"")
 assert_eq(WorldMap.settlements_in("greyspine_peaks"),[])

func test_regions_tile_the_map_without_gaps_or_overlaps():
 for x in range(-340,343,20):
  for z in range(-340,145,20):
   var p = Vector2(x+0.37,z+0.61)
   var hits = 0
   for id in WorldMap.regions():
    if Geometry2D.is_point_in_polygon(p,WorldMap.regions()[id].points): hits += 1
   assert_eq(hits,1,"point %s is in %d regions" % [p,hits])

func test_border_kinds():
 var kinds = {}
 for e in TerritoryOverlay.shared_edges(): kinds[e.kind] = true
 assert_true(kinds.has(0),"faction borders exist")
 assert_true(kinds.has(1),"province borders between same-faction provinces exist (Crownwatch Pass / Goldspire)")
 assert_eq(TerritoryOverlay._kind("crownwatch","goldspire_rock"),1)
 assert_eq(TerritoryOverlay._kind("greyhaven","willowmere"),0)
