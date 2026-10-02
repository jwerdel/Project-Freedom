extends GutTest
# Maps (core/map_registry.gd, docs/map-pipeline-design.md §7): every map lives in data/maps/<id>/,
# the loaders read the active map, a campaign records its map and map version, and a save from
# another map version is refused (schema 4).

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const SaveSystem = preload("res://core/save_system.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const WorldMap = preload("res://core/world_map.gd")
const TEST_DIR = "user://test_saves_maps"

func before_each():
 SaveSystem.dir = TEST_DIR
 MapRegistry.set_active(MapRegistry.DEFAULT)

func after_each():
 var d = DirAccess.open(TEST_DIR)
 if d:
  for f in d.get_files(): DirAccess.remove_absolute(TEST_DIR+"/"+f)
 SaveSystem.dir = SaveSystem.DIR
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_the_test_map_is_the_default_and_complete():
 assert_eq(MapRegistry.active,"testmap")
 assert_true("testmap" in MapRegistry.maps())
 for f in ["map.json","provinces.json","factions.json","campaign_start.json","movement_grid.json","movement.json"]:
  assert_true(MapRegistry.has_file(f),f)
 assert_eq(MapRegistry.meta().id,"testmap")
 assert_eq(MapRegistry.version(),1)

func test_a_campaign_records_its_map():
 var s = GameState.from_data()
 assert_eq(s.map_id,"testmap")
 assert_eq(s.map_version,MapRegistry.version())
 var back = GameState.from_dict(s.to_dict())
 assert_eq([back.map_id,back.map_version],[s.map_id,s.map_version])

func test_lookups_are_dictionary_lookups():
 for p in WorldMap.provinces():
  for r in p.regions: assert_eq(WorldMap.province_of(r),p.id)
 assert_eq(WorldMap.province_of("nowhere"),"")
 assert_eq(WorldMap.region_at(WorldMap.settlement_position("greyhaven")),"greyhaven")

func test_schema_3_saves_migrate_to_the_test_map():
 var s = GameState.from_data()
 var d = s.to_dict()
 d.erase("map_id")
 d.erase("map_version")
 var r = SaveSystem.migrate({"schema":3,"meta":{},"state":SaveCodec.encode(d)})
 assert_true(r.ok)
 assert_eq(r.data.state.map_id,"testmap")
 assert_eq(int(r.data.state.map_version),1)

func test_a_save_from_another_map_version_is_refused():
 var s = GameState.from_data()
 assert_true(SaveSystem.save(s,"same","Same").ok)
 assert_true(SaveSystem.load_save("same").ok,"the same map version loads")
 s.map_version = 99
 assert_true(SaveSystem.save(s,"old_map","Old map").ok)
 var r = SaveSystem.load_save("old_map")
 assert_false(r.ok)
 assert_string_contains(r.error,"older version of the map")
 s.map_version = 1
 s.map_id = "atlantis"
 assert_true(SaveSystem.save(s,"lost_map","Lost map").ok)
 r = SaveSystem.load_save("lost_map")
 assert_false(r.ok)
 assert_string_contains(r.error,"does not have")
