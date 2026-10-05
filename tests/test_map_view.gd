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

func tris_drawn(node) -> int:
 var t = 0
 for mi in node.get_children():
  var m: Mesh = mi.multimesh.mesh
  for si in m.get_surface_count():
   var arr = m.surface_get_arrays(si)
   var n = arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()
   t += n/3*mi.multimesh.instance_count
 return t

func test_city_draws_one_baked_mesh_per_piece_with_every_triangle():
 # Part 1 budget fix: each kit piece is one MultiMesh of one baked surface per look (parts and
 # material colours combined): far fewer draw calls, the same triangles, the same colours; fields
 # and roads cast no shadow.
 var vs = make_view()
 var v = vs[0]
 var s = vs[1]
 var sid = WorldMap.settlement_ids()[0]
 s.settlements[sid].level = 3
 s.settlements[sid].buildings = [{"chain":"farm","level":3},{"chain":"market","level":3},{"chain":"walls","level":3},{"chain":"temple","level":2}]
 var spec = v.settlement_spec(sid)
 var SprawlNode = load("res://map/sprawl_node.gd")
 var baked = SprawlNode.new()
 add_child_autofree(baked)
 baked.build(spec,v.terrain_at,v.height_at,v.sea_level)
 SprawlNode.merge = false
 var old = SprawlNode.new()
 add_child_autofree(old)
 old.build(spec,v.terrain_at,v.height_at,v.sea_level)
 SprawlNode.merge = true
 assert_lt(baked.draw_calls()*2,old.draw_calls(),"less than half the draw calls (%d vs %d)" % [baked.draw_calls(),old.draw_calls()])
 assert_eq(tris_drawn(baked),tris_drawn(old),"every triangle kept")
 var quiet = 0
 for mi in baked.get_children():
  if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: quiet += 1
 assert_gt(quiet,0,"fields and roads without shadows")

func test_baked_piece_keeps_material_colours_in_linear_vertex_colours():
 var KitCache = load("res://map/kit_cache.gd")
 for id in ["kit.house_a","kit.wall","kit.field"]:
  var m = KitCache.baked(id)
  assert_gt(m.get_surface_count(),0,id)
  for si in m.get_surface_count():
   var mat = m.surface_get_material(si)
   if mat is BaseMaterial3D:
    assert_true(mat.vertex_color_use_as_albedo)
    assert_eq(mat.albedo_color,Color.WHITE,"the colour lives in the vertices")
 # A flat-coloured part: its vertex colour is its material colour, linear.
 var src = KitCache.meshes("kit.wall")[0].mesh
 var mat0 = src.surface_get_material(0)
 if mat0 is BaseMaterial3D:
  var c = KitCache.baked("kit.wall").surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
  assert_true(c.is_equal_approx(mat0.albedo_color.srgb_to_linear()) or absf(c.r-mat0.albedo_color.srgb_to_linear().r)<0.01)
