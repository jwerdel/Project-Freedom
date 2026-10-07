extends GutTest
# The turn summary and world events (owner spec 2026-10-07, A8): the summary shows only what
# matters to you, grouped (settlements, armies and battles, diplomacy, court, threats near your
# borders), each row with a jump target; world news (others' wars, captures, marriages) lasts one
# turn and never piles up.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const UiData = preload("res://core/ui_data.gd")
const Chronicle = preload("res://core/chronicle.gd")
const Battles = preload("res://core/battles.gd")
const Movement = preload("res://core/movement.gd")
const WorldMap = preload("res://core/world_map.gd")

func before_each():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_world_events_expire_after_one_turn():
 var s = GameState.from_data()
 s.player_faction = "house_varn"
 var data = UiData.new(s)
 # A war between two other houses this turn: world news.
 s.chronicle.append(Chronicle.war_entry(int(s.year),"house_dunmoor","house_kells"))
 s.year += 1 # as End Turn closes the year
 var mine_war = func(e): return str(e.get("with","")) == "house_kells" and str(e.get("faction","")) == "house_dunmoor"
 assert_eq(data.events("world").filter(mine_war).size(),1,"others' war is world news this turn")
 assert_true(data.events("war").is_empty(),"not in your wars")
 data.end_turn()
 assert_false(data.events("world").any(func(e): return str(e.get("with","")) == "house_kells" and str(e.faction) == "house_dunmoor"),"gone the turn after")
 # Your own war stays in your wars.
 s.chronicle.append(Chronicle.war_entry(int(s.year),"house_dunmoor","house_varn"))
 assert_false(data.events("war").is_empty())

func test_summary_is_grouped_with_jump_targets():
 var s = GameState.from_data()
 s.player_faction = "house_varn"
 s.treasury.house_varn = 99999
 var data = UiData.new(s)
 var sid = s.settlements_of("house_varn")[0]
 # Something builds, and an enemy stands near the border.
 for i in s.settlements[sid].buildings.size():
  if s.settlements[sid].buildings[i].has("chain"): continue
  var o = data.building_options(sid,i).filter(func(x): return x.available and int(x.turns) == 1)
  if not o.is_empty():
   data.start_construction(sid,i,o[0].chain)
   break
 var foe = s.armies_of("house_dunmoor")[0]
 s.wars.append(Battles.war_key("house_varn","house_dunmoor"))
 var p = WorldMap.settlement_position(sid)+Vector2(150,0)
 s.army_state[foe].position = [p.x,p.y]
 s.army_state[foe].garrison = ""
 data.end_turn()
 var groups = data.turn_summary()
 var ids = groups.map(func(g): return g.id)
 assert_has(ids,"settlements","your settlements: the construction that completed")
 assert_has(ids,"threats","an enemy army near your border")
 for g in groups:
  for r in g.rows:
   assert_true(r.has("target") and r.target.has("type"),"every row jumps somewhere")
 # Only what matters: no other faction's building in your summary.
 var settle = groups.filter(func(g): return g.id == "settlements")[0]
 for r in settle.rows: assert_eq(s.settlements[r.target.id].owner,"house_varn")
 # Saved with the campaign.
 var t = GameState.from_dict(s.to_dict())
 assert_eq(t.last_summary,s.last_summary)
