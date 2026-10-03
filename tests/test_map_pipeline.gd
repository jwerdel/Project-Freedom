extends GutTest
# The map pipeline's generator and bakes (map/synthetic.gd, map/map_bake.gd): a tiny synthetic map
# is built, then loaded through the same loaders as any map: region raster, baked movement grid,
# render cache, campaign start, End Turn.

const MapRegistry = preload("res://core/map_registry.gd")
const MapBake = preload("res://map/map_bake.gd")
const Synthetic = preload("res://map/synthetic.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const MAP = "synthetic_tiny"

var built = {}

func before_all():
 built = Synthetic.build(MAP)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_build_reports_the_requested_counts():
 assert_eq(built.regions,24)
 assert_eq(built.factions,8)
 assert_eq(built.armies,10)
 assert_gt(built.provinces,0)

func test_the_region_raster_agrees_with_the_regions():
 MapRegistry.set_active(MAP)
 var ids = WorldMap.settlement_ids()
 assert_eq(ids.size(),24)
 for id in ids: assert_eq(WorldMap.region_at(WorldMap.settlement_position(id)),id,"a settlement lies in its own region")
 assert_eq(WorldMap.region_at(Vector2(-50,-50)),"","outside the map")
 for p in WorldMap.provinces():
  for r in p.regions: assert_eq(WorldMap.province_of(r),p.id)

func test_the_baked_movement_grid_loads():
 MapRegistry.set_active(MAP)
 var g = Movement.grid()
 assert_eq([g.cols,g.rows],[256,160])
 assert_eq(g.terrain.size(),256*160)
 assert_eq(g.road.size(),256*160)
 for id in WorldMap.settlement_ids(): assert_eq(Movement.terrain_at(WorldMap.settlement_position(id)),"settlement")

func test_render_cache_round_trips():
 var rc = MapBake.load_render_cache(MAP)
 assert_false(rc.is_empty())
 assert_eq([rc.cols,rc.rows],[256,160])
 assert_eq(rc.heights.get_format(),Image.FORMAT_RF)

func test_a_campaign_starts_and_a_turn_runs_on_it():
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 assert_eq(s.map_id,MAP)
 assert_eq(s.army_state.size(),10)
 s.player_faction = ""
 var year = s.year
 TurnLoop.end_turn(s)
 assert_eq(s.year,year+1)

func test_the_build_is_deterministic():
 var a = FileAccess.get_file_as_bytes(MapRegistry.path("baked/regions.bin",MAP))
 var b2 = Synthetic.build(MAP)
 assert_eq(b2.regions,24)
 assert_eq(FileAccess.get_file_as_bytes(MapRegistry.path("baked/regions.bin",MAP)),a,"same sources, same bakes")
