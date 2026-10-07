extends GutTest
# The Stage A landmarks (2026-10-06; world bible §8): each is registered in the asset manifest with
# its own three growth stages, every stage builds, and later stages add features to earlier ones.

const AssetManifest = preload("res://core/asset_manifest.gd")
const IDS = ["caeloth","crownhaven","frosthold","wardens_gate","skyreach","harrow_crossing","highbloom","oldstone_citadel","tempest_keep","skulkmire","emberdeep","brinecrag","goldspire_rock"]

func after_each():
 AssetManifest.reset()

func build(id: String,stage: int) -> Node3D:
 var n = AssetManifest.instantiate_settlement(id,stage)
 add_child_autofree(n)
 n.build({"height":func(_x,_z): return 2.0})
 return n

func test_every_stage_a_landmark_has_three_stages_that_grow():
 for id in IDS:
  assert_true(AssetManifest.is_landmark(id),id)
  var f1 = build(id,1).get_meta("features")
  var n3 = build(id,3)
  var f3 = n3.get_meta("features")
  assert_gt(f1.size(),0,id+" stage 1 shows its signature")
  assert_gt(f3.size(),f1.size(),id+" grows by stage 3")
  for f in f1:
   if not f.contains(":"): assert_has(f3,f,"%s keeps %s" % [id,f])
  assert_gt(n3.find_children("*","MeshInstance3D",true,false).size(),0,id)
  assert_gt(float(AssetManifest.landmarks()[id].get("radius",0.0)),0.0,id+" has its own ground radius")

# Owner 2026-10-06: a landmark with walls of its own gets no generic wall ring from the settlement
# layout; one without them (or before its walls stand) gets the culture's ring around its town.
func test_a_landmark_with_its_own_walls_suppresses_the_town_wall_ring():
 var Sprawl = load("res://map/sprawl.gd")
 var flat = func(_p): return "open"
 var spec = {"id":"frosthold","type":"city","level":3,"position":Vector2.ZERO,"from":"medieval","to":"medieval","value":1.0,"buildings":[],"landmark_radius":26.0}
 var walls = func(lay: Array) -> int: return lay.filter(func(o): return str(o.piece).ends_with(".wall") or str(o.piece).ends_with(".tower") or str(o.piece).ends_with(".gate")).size()
 spec.landmark_walls = true
 assert_eq(walls.call(Sprawl.layout(spec,flat)),0,"own walls: no generic ring")
 spec.landmark_walls = false
 assert_gt(walls.call(Sprawl.layout(spec,flat)),0,"no walls of its own: the town gets its ring")
 # The manifest says from which stage each landmark has walls.
 assert_true(AssetManifest.landmark_has_walls("frosthold",1))
 assert_false(AssetManifest.landmark_has_walls("crownhaven",1))
 assert_true(AssetManifest.landmark_has_walls("crownhaven",2))
 assert_false(AssetManifest.landmark_has_walls("skulkmire",3),"the drowned ruin has no walls")
 assert_false(AssetManifest.landmark_has_walls("greyhaven",3),"not a landmark")

# Brinecrag follows its own reference since 2026-10-06 (dark spiked towers on sea stacks, chain
# bridges, sea gates, the fleet); Emberdeep keeps the dwarf hold.
func test_brinecrag_has_sea_stacks_chain_bridges_and_sea_gates():
 var f2 = build("brinecrag",2).get_meta("features")
 for f in ["main_stack","spiked_towers","chain_bridges","sea_gates"]: assert_has(f2,f)
 var f3 = build("brinecrag",3).get_meta("features")
 assert_has(f3,"black_fleet")
 assert_has(f3,"docks")
 for p in ["res://visuals/landmarks/brinecrag_visual.gd","res://visuals/landmarks/emberdeep_visual.gd"]:
  var src = FileAccess.get_file_as_string(p)
  var own = p.get_file().get_slice("_visual",0)
  assert_string_contains(src,"docs/reference/landmarks/%s.jpg" % own,p+" points at its own reference")

# The Greywall (owner 2026-10-06: not a flat slab): blocks with buttresses and crenellations, towers
# at intervals and a fortified gatehouse at every pass; far terrain tiles replace chunks at high zoom.
func test_greywall_has_towers_and_gatehouses_and_varos_has_far_tiles():
 var MapRegistry = load("res://core/map_registry.gd")
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 var s = load("res://core/game_state.gd").from_data()
 var v = load("res://map/map_view.gd").new()
 add_child_autofree(v)
 v.setup(s)
 var w = v.wall_stats
 assert_gt(int(w.get("blocks",0)),100,"a long wall")
 assert_gt(int(w.get("towers",0)),5,"towers at intervals")
 assert_gt(int(w.get("gates",0)),0,"a gatehouse at the pass")
 assert_eq(int(w.get("gate_towers",0)),int(w.gates)*2,"two flanking towers per gate")
 assert_gt(v.far_tiles,0,"far terrain tiles on the large map")
 var tile = v.get_node("FarTile_0_0")
 var chunk = v.chunks[Vector2i(0,0)].node.get_child(0)
 assert_eq(chunk.get_node(chunk.visibility_parent),tile,"chunks hand over to their far tile")
 MapRegistry.set_active(MapRegistry.DEFAULT)
