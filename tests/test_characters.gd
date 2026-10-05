extends GutTest
# Lords as characters (core/characters.gd, placeholder skills in data/skills.json): one skill
# point per level, rows read left to right with level gates, auto-allocation (always for AI
# generals), the unspent-points End Turn warning, saves, and the character window.

const GameState = preload("res://core/game_state.gd")
const UiData = preload("res://core/ui_data.gd")
const Characters = preload("res://core/characters.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const CharacterWindow = preload("res://ui/character_window.gd")
const UiKit = preload("res://ui/ui_kit.gd")
const HOST = "aurek_host"

func test_points_per_level_and_row_order():
 var data = UiData.new(GameState.from_data())
 var c = data.state.army_state[HOST].commander
 c.rank = 3
 assert_eq(Characters.skill_points(c),3)
 assert_false(Characters.can_take(c,"drilled_ranks").ok,"the row's first skill comes first")
 assert_true(data.take_skill(HOST,"rally_the_line"))
 assert_true(data.take_skill(HOST,"drilled_ranks"))
 var gated = Characters.can_take(c,"stern_presence")
 assert_false(gated.ok)
 assert_eq(gated.reason,"Needs level 4")
 assert_false(data.take_skill(HOST,"rally_the_line"),"no skill twice")
 assert_eq(Characters.skill_points(c),1)
 assert_true(data.take_skill(HOST,"forced_march"))
 assert_eq(Characters.skill_points(c),0)
 assert_false(Characters.can_take(c,"siege_engineers").ok,"no points left")

func test_auto_allocate_spends_every_point_round_robin():
 var data = UiData.new(GameState.from_data())
 var c = data.state.army_state[HOST].commander
 c.rank = 4
 data.set_auto_skills(HOST,true)
 assert_eq(Characters.skill_points(c),0)
 assert_eq(c.skills,["rally_the_line","forced_march","siege_engineers","drilled_ranks"])

func test_unspent_points_warn_until_auto_allocate():
 var data = UiData.new(GameState.from_data())
 var kinds = data.end_turn_warnings().map(func(w): return w.kind)
 assert_has(kinds,"skill_points","a level-1 general has a point to spend")
 var w = data.end_turn_warnings().filter(func(x): return x.kind == "skill_points")[0]
 assert_eq(w.items[0].type,"character")
 for id in data.state.army_state:
  if data.state.army_state[id].faction == data.state.player_faction: data.set_auto_skills(id,true)
 kinds = data.end_turn_warnings().map(func(w2): return w2.kind)
 assert_does_not_have(kinds,"skill_points")

func test_ai_generals_spend_points_at_end_turn_and_skills_survive_saves():
 var data = UiData.new(GameState.from_data())
 var s = data.state
 var ai_id = ""
 for id in s.army_state:
  if s.army_state[id].faction != s.player_faction: ai_id = id
 assert_ne(ai_id,"")
 data.end_turn()
 if s.army_state.has(ai_id): assert_eq(Characters.skill_points(s.army_state[ai_id].commander),0,"AI generals auto-allocate")
 data.take_skill(HOST,"rally_the_line")
 var back = GameState.from_dict(SaveCodec.from_json(SaveCodec.to_json(s.to_dict())))
 assert_has(back.army_state[HOST].commander.skills,"rally_the_line")

func test_character_window_tabs():
 var data = UiData.new(GameState.from_data())
 var w = CharacterWindow.new(data,UiKit.colors(data.player_faction()),HOST)
 add_child_autofree(w)
 assert_not_null(w.find_child("CharacterStats",true,false),"Details tab first")
 assert_not_null(w.find_child("CharacterModel",true,false),"the model")
 assert_eq(w.find_child("CharacterLevel",true,false).text,"Level %d" % int(data.state.army_state[HOST].commander.rank))
 w.set_tab("skills")
 assert_not_null(w.find_child("SkillRow_command",true,false))
 var tile = w.find_child("Skill_rally_the_line",true,false)
 assert_false(tile.disabled)
 tile.pressed.emit()
 assert_has(data.state.army_state[HOST].commander.skills,"rally_the_line")
 assert_eq(w.find_child("SkillPoints",true,false).text,"Skill points: %d" % Characters.skill_points(data.state.army_state[HOST].commander))
 assert_eq(Characters.skill_points(data.state.army_state[HOST].commander),int(data.state.army_state[HOST].commander.rank)-1)
 w.set_tab("equipment")
 assert_not_null(w.find_child("EquipmentSlots",true,false))
