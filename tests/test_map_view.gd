extends GutTest
# The pipeline map's 3D view (map/map_view.gd): terrain chunks, streamed settlement sprawl and trees,
# and the land palette (headless: no pixels, but the scene graph and data are checked).

const MapRegistry = preload("res://core/map_registry.gd")
const Synthetic = preload("res://map/synthetic.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const MapView = preload("res://map/map_view.gd")
const MAP = "synthetic_tiny"

func before_all():
 Synthetic.build(MAP)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func make_view():
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 var v = MapView.new()
 add_child_autofree(v)
 v.setup(s)
 return [v,s]

func test_terrain_chunks_cover_the_map():
 var vs = make_view()
 var v = vs[0]
 assert_eq(v.chunks.size(),int(ceil(512.0/256.0))*int(ceil(320.0/256.0)))
 for k in v.chunks: assert_eq(v.chunks[k].node.get_child_count(),4,"four LODs")

func test_streaming_builds_settlements_and_trees_near_the_focus():
 var vs = make_view()
 var v = vs[0]
 var p = WorldMap.settlement_position(WorldMap.settlement_ids()[0])
 v.update(Vector3(p.x,0,p.y))
 var st = v.stats()
 assert_gt(st.settlements_built,0)
 assert_gt(st.settlement_pieces,0)
 for sid in v.settlements: assert_gt(v.settlements[sid].draw_calls(),0)

func test_land_change_rebuilds_the_sprawl():
 var vs = make_view()
 var v = vs[0]
 var s = vs[1]
 var sid = WorldMap.settlement_ids()[0]
 var p = WorldMap.settlement_position(sid)
 v.update(Vector3(p.x,0,p.y))
 var key = v.settlements[sid].key
 s.land[sid] = {"from":"greek","to":"orc","value":0.34,"built":0}
 v.refresh_land()
 v.update(Vector3(p.x,0,p.y))
 assert_ne(v.settlements[sid].key,key,"rebuilt for the new land")
 # The palette texel holds from / to / value.
 var i = v.region_names.find(sid)+1
 var px = v.palette_img.get_pixel(i,0)
 assert_eq(int(round(px.b*255.0)),int(round(0.34*255.0)))
