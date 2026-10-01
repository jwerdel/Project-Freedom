extends GutTest
# Optional card art: a unit type's card_art image replaces the rendered portrait; without one the
# card falls back to the portrait. The game's overlays (faction border, strength bar, rank chevrons,
# unit count) are drawn above either. scripts/fit_card_art.gd crops and scales art to card size.

const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const Cards = preload("res://ui/cards.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const FitCardArt = preload("res://scripts/fit_card_art.gd")
const ART = "user://test_card_art.png"

var studio

func before_each():
 studio = PortraitStudio.new()
 add_child_autofree(studio)

func after_each():
 if FileAccess.file_exists(ART): DirAccess.remove_absolute(ProjectSettings.globalize_path(ART))

func card_for(unit: Dictionary,entry := {"men":60,"max_men":120}) -> Control:
 var card = Cards.unit_card(unit,entry,WorldMap.faction("house_aurek"),studio,"tip")
 add_child_autofree(card)
 return card

func test_cards_fall_back_to_the_rendered_portrait():
 for id in UnitTypes.ids():
  var unit = UnitTypes.get_type(id)
  if UnitTypes.card_art_path(unit) != "": continue # real art present for this unit
  assert_null(UnitTypes.card_art(unit),id)
  var card = card_for(unit)
  assert_false(card.uses_card_art(),id)
 var spear = card_for(UnitTypes.get_type("spearmen"))
 var tex = await studio.render("spearmen")
 await wait_process_frames(2)
 if not spear.uses_card_art(): assert_eq(spear.portrait.texture,tex)

func test_card_art_replaces_the_portrait_with_overlays_on_top():
 var img = Image.create(40,60,false,Image.FORMAT_RGBA8)
 img.fill(Color.RED)
 img.save_png(ProjectSettings.globalize_path(ART))
 var unit = UnitTypes.get_type("spearmen").duplicate(true)
 unit.card_art = ART
 assert_eq(UnitTypes.card_art_path(unit),ART)
 var art = UnitTypes.card_art(unit)
 assert_not_null(art)
 assert_eq(art.get_size(),Vector2(40,60))
 var card = card_for(unit,{"men":90,"max_men":120,"rank":2})
 assert_true(card.uses_card_art())
 assert_eq(card.portrait.texture,card.art)
 assert_eq(card.art.get_size(),Vector2(40,60))
 assert_gt(card.overlay.get_index(),card.portrait.get_index(),"overlays draw above the art")
 assert_eq(card.rank,2)
 assert_eq(card.men,90)
 assert_almost_eq(card.strength,0.75,0.0001)
 # A missing card_art file falls back instead of failing.
 unit.card_art = "user://does_not_exist.png"
 assert_eq(UnitTypes.card_art_path(unit),"")
 assert_null(UnitTypes.card_art(unit))

func test_fit_script_crops_and_scales_to_card_size():
 for size in [Vector2i(1440,2912),Vector2i(1000,400),Vector2i(50,50)]:
  var img = Image.create(size.x,size.y,false,Image.FORMAT_RGB8)
  img.fill(Color.BLUE)
  var out = FitCardArt.fit(img)
  assert_eq(out.get_size(),FitCardArt.SIZE,str(size))
 assert_almost_eq(float(FitCardArt.SIZE.x)/FitCardArt.SIZE.y,Cards.UNIT_CARD.x/Cards.UNIT_CARD.y,0.001)
