extends GutTest
# The campaign UI shows only what the UiData interface provides (real campaign state, economy and
# chronicle; mock only for public order), and End Turn runs the turn loop.

const UiData = preload("res://core/ui_data.gd")
const GameState = preload("res://core/game_state.gd")
const Economy = preload("res://core/economy.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const UiKit = preload("res://ui/ui_kit.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const FIXTURE = "res://tests/fixtures/campaign_start_fixture.json"

var studio

func before_each():
 studio = PortraitStudio.new()
 add_child_autofree(studio)

func build_ui(data) -> Control:
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(data,studio)
 return ui

func fixture_data():
 return UiData.new(GameState.from_data(FIXTURE))

func test_remaining_mock_file_is_clearly_marked_and_only_public_order():
 var data = UiData.new()
 assert_true(data.is_mock())
 assert_string_contains(data.mock._MOCK,"MOCK")
 for key in data.mock.keys(): assert_true(key in ["_MOCK","public_order"],"unexpected mock key "+key)

func test_resource_bar_shows_real_campaign_values():
 # A fixture start with distinctive values: if the UI read anything else, these would not appear.
 var data = fixture_data()
 var ui = build_ui(data)
 var ledger = Economy.faction_ledger(data.state,"house_aurek")
 assert_eq(ui.resource_labels.treasury.text,"123,456")
 assert_eq(ui.resource_labels.income.text,UiKit.signed(ledger.net))
 assert_eq(ui.resource_labels.population.text,UiKit.format_int(data.state.population_of("house_aurek")))
 assert_eq(ui.resource_labels.year.text,"Year 40 · Turn 1")

func test_treasury_tooltip_breaks_down_income_and_expenses():
 var data = fixture_data()
 var ui = build_ui(data)
 var tip = ui.resource_groups.treasury.tooltip_text
 assert_string_contains(tip,"Goldspire Rock (city)")
 assert_string_contains(tip,"Army upkeep: The Host of Goldspire")
 assert_string_contains(tip,"Building upkeep: Crownwatch")
 assert_string_contains(tip,"Net per turn: "+UiKit.signed(Economy.faction_ledger(data.state,"house_aurek").net))

func test_province_stats_are_real_economy_values():
 var data = fixture_data()
 var st = data.province_stats("goldspire")
 assert_eq(st.income,Economy.settlement_income(data.state,"goldspire_rock").total)
 assert_eq(st.growth,int(round(Economy.growth(data.state,"goldspire_rock").delta)))
 assert_eq(st.population,15800)
 assert_true(st.public_order_is_mock)

func test_panels_follow_the_data_interface():
 var data = fixture_data()
 var ui = build_ui(data)
 ui.show_settlement("greyhaven")
 assert_eq(ui.province_title,"The Greywater March")
 assert_true(ui.stats_panel.visible and ui.bottom_panel.visible)
 data.set_settlement_level("greyhaven",3)
 assert_eq(data.settlement("greyhaven").level,3)
 ui.show_army("aurek_host","The Greywater March")
 assert_eq(ui.selected_army,"aurek_host")
 assert_false(ui.stats_panel.visible)
 ui.clear_selection()
 assert_false(ui.bottom_panel.visible)

func test_end_turn_runs_the_turn_loop_and_updates_the_ui():
 var data = fixture_data()
 var ui = build_ui(data)
 # Full-strength units, so no paid replenishment changes the treasury this turn.
 for u in data.state.army_state.aurek_host.units: u.men = u.max_men
 var net = Economy.faction_ledger(data.state,"house_aurek").net
 ui.end_turn_requested.connect(data.end_turn)
 ui.end_turn_button.pressed.emit()
 assert_eq(data.resources().year,41)
 assert_eq(data.resources().turn,2)
 assert_eq(data.resources().treasury,123456+net)
 assert_eq(data.events("turn")[0].year,41)
 assert_eq(ui.resource_labels.year.text,"Year 41 · Turn 2")
 assert_eq(ui.resource_labels.treasury.text,UiKit.format_int(123456+net))
 assert_eq(ui.end_turn_year.text,"Year 41")

func test_chronicle_window_lists_the_log():
 var data = fixture_data()
 var ui = build_ui(data)
 data.end_turn()
 ui.toggle_chronicle()
 assert_true(ui.chronicle_visible())
 assert_eq(ui.chronicle_box.get_child_count(),data.state.chronicle.size())
