extends GutTest
# The campaign UI shows only what the UiData interface provides, and End Turn advances the year.

const UiData = preload("res://core/ui_data.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const FIXTURE = "res://tests/fixtures/mock_ui_fixture.json"

var studio

func before_each():
 studio = PortraitStudio.new()
 add_child_autofree(studio)

func build_ui(data) -> Control:
 var ui = CampaignUI.new()
 add_child_autofree(ui)
 ui.setup(data,studio)
 return ui

func test_mock_file_is_clearly_marked():
 var data = UiData.new()
 assert_true(data.is_mock())
 assert_string_contains(data.mock._MOCK,"MOCK")

func test_resource_bar_shows_the_data_interface_values():
 # A fixture with distinctive numbers: if the UI read anything else, these would not appear.
 var ui = build_ui(UiData.new(FIXTURE))
 assert_eq(ui.resource_labels.treasury.text,"123,456")
 assert_eq(ui.resource_labels.income.text,"-77")
 assert_eq(ui.resource_labels.population.text,"9,090")
 assert_eq(ui.resource_labels.year.text,"Year 40 · Turn 1")

func test_panels_follow_the_data_interface():
 var data = UiData.new(FIXTURE)
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

func test_end_turn_advances_the_year_and_posts_an_event():
 var data = UiData.new(FIXTURE)
 var ui = build_ui(data)
 var before = data.events("turn").size()
 ui.end_turn_requested.connect(data.end_turn)
 ui.end_turn_button.pressed.emit()
 assert_eq(data.resources().year,41)
 assert_eq(data.resources().turn,2)
 assert_eq(data.events("turn").size(),before+1)
 assert_eq(data.events("turn")[0].title,"Year 41 begins")
 assert_eq(ui.resource_labels.year.text,"Year 41 · Turn 2")
 assert_eq(ui.end_turn_year.text,"Year 41")

func test_end_turn_changes_nothing_but_the_calendar():
 var data = UiData.new(FIXTURE)
 var r = data.resources()
 data.end_turn()
 var after = data.resources()
 for key in ["treasury","income","population"]: assert_eq(after[key],r[key],key+" must not change")
