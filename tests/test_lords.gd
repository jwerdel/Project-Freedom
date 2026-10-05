extends GutTest
# Lords on the campaign map (data/campaign_view.json): oversized figures, a minimum on-screen size
# when zoomed out, a floating faction banner per army that selects it, and click targets that scale
# with the figure.

const SaveSystem = preload("res://core/save_system.gd")
const HOST = "aurek_host"

var main

func before_each():
 SaveSystem.dir = "user://test_saves"
 main = load("res://Main.tscn").instantiate()
 add_child_autofree(main)
 await get_tree().process_frame
 await get_tree().process_frame

func after_each():
 SaveSystem.dir = SaveSystem.DIR

func test_lords_are_scaled_up_and_keep_a_minimum_size():
 var v = main.campaign_view()
 assert_gte(float(v.lord_scale),2.0)
 main.update_army_presentation()
 for id in main.army_figures: assert_gte(main.army_figures[id].scale.x,float(v.lord_scale)-0.001)
 # Far out, the figure grows to keep min_figure_px on screen.
 main.desired_distance = 210.0
 main.distance = 210.0
 main.camera_update(0.0)
 main.update_army_presentation()
 var f = main.army_figures[HOST]
 var px_per_m = main.camera.unproject_position(f.position).distance_to(main.camera.unproject_position(f.position+Vector3.UP))
 assert_gte(px_per_m*float(v.figure_height)*f.scale.x,float(v.min_figure_px)-0.5)

func test_every_army_has_a_banner_that_selects_it():
 main.update_army_presentation()
 assert_eq(main.army_banners.size(),main.army_figures.size())
 for id in main.army_banners: assert_true(main.army_banners[id].visible or main.camera.is_position_behind(main.army_figures[id].position),id)
 main.army_banners[HOST].pressed.emit()
 assert_eq(main.selected_army_id(),HOST)
 main.update_army_presentation()
 assert_true(main.army_banners[HOST].selected)

func test_click_target_scales_with_the_figure():
 main.update_army_presentation()
 var f = main.army_figures[HOST]
 var torso = main.camera.unproject_position(f.position+Vector3(0,2.2*f.scale.x,0))
 assert_eq(main.pick(torso),"army:"+HOST)

func test_banner_fades_when_very_close():
 var v = main.campaign_view()
 main.distance = float(v.banner_fade_end)-1.0
 main.update_army_presentation()
 for id in main.army_banners: assert_false(main.army_banners[id].visible,"faded out up close")
