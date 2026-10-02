extends Control
# Deployment screen (docs/battle-design.md section 2): the player's army on a tabletop battlefield
# built from the sampled terrain, 5 lanes x front/back + reserve + the general's slot per side.
# Drag cards from the tray onto slots (or click a card, then a slot), give orders, quick-fill from a
# template, and see the enemy's known positions. Balance of power is recomputed on "Update odds"
# or after a pause in changes, not on every drag. All rules go through UiData (core/deployment.gd).

signal fought(pb: Dictionary,out: Dictionary)
signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const Cards = preload("res://ui/cards.gd")
const Board = preload("res://ui/deployment_board.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const ODDS_DELAY = 1.0
const ORDER_NAMES = {"hold":"Hold","aggressive":"Aggressive","flank":"Flank","protect":"Protect","reserve":"Reserve"}

var data
var studio
var colors: Dictionary
var pb: Dictionary
var dep: Dictionary
var enemy: Array = []
var role := 0
var selected := -1          # unit index, or -2 for the general
var picking_protect := false
var dragging := -1
var view_3d := true
var odds := 0.5
var odds_dirty := false
var odds_timer: Timer
var tray: HBoxContainer
var message: Label
var odds_label: Label
var balance: Control
var order_box: VBoxContainer
var order_title: Label
var board_area: Control
var viewport_box: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var tabletop
var board
var view_button: Button

func setup(ui_data,portrait_studio,theme_colors: Dictionary,prebattle: Dictionary):
 data = ui_data
 studio = portrait_studio
 colors = theme_colors
 pb = prebattle
 role = data.player_role(pb)
 dep = data.deployment_create(pb)
 enemy = data.deployment_enemy(pb)
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var bg = ColorRect.new()
 bg.color = Color(0.05,0.04,0.03)
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var root = VBoxContainer.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.offset_left = 14
 root.offset_right = -14
 root.offset_top = 10
 root.offset_bottom = -10
 root.add_theme_constant_override("separation",6)
 add_child(root)
 root.add_child(_header())
 var mid = HBoxContainer.new()
 mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
 mid.add_theme_constant_override("separation",8)
 root.add_child(mid)
 board_area = Control.new()
 board_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 board_area.clip_contents = true
 mid.add_child(board_area)
 _build_3d()
 _build_2d()
 mid.add_child(_orders_panel())
 var tray_frame = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.95))
 var tv = VBoxContainer.new()
 tray_frame.add_child(tv)
 tv.add_child(UiKit.label("Your army: drag a card onto a slot, or click a card and then a slot. Click a placed unit to select it.",13,UiKit.TEXT_DIM))
 var scroll = ScrollContainer.new()
 scroll.custom_minimum_size = Vector2(0,178)
 scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 tray = HBoxContainer.new()
 tray.add_theme_constant_override("separation",6)
 scroll.add_child(tray)
 tv.add_child(scroll)
 root.add_child(tray_frame)
 odds_timer = Timer.new()
 odds_timer.one_shot = true
 odds_timer.wait_time = ODDS_DELAY
 odds_timer.timeout.connect(update_odds)
 add_child(odds_timer)
 odds = pb.odds
 refresh()
 _set_view(true)

func _framed() -> Control:
 return Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.95))

func _button(text: String,cb: Callable,name := "") -> Button:
 var b = Button.new()
 b.text = text
 if name != "": b.name = name
 b.focus_mode = Control.FOCUS_NONE
 b.pressed.connect(cb)
 return b

func _header() -> Control:
 var f = _framed()
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",4)
 f.add_child(v)
 var top = HBoxContainer.new()
 top.add_theme_constant_override("separation",8)
 var place = data.settlement(pb.settlement).name if pb.settlement != "" else "the field"
 var title = UiKit.header("Deployment · %s at %s" % ["Siege assault" if pb.field.get("walls") != null else "Battle",place],20)
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 top.add_child(title)
 view_button = _button("2D board",func(): _set_view(not view_3d),"ViewToggle")
 top.add_child(view_button)
 top.add_child(_button("Reset",reset,"Reset"))
 top.add_child(_button("Back to campaign",func(): closed.emit(),"Back"))
 var fight = _button("Fight",_fight,"Fight")
 fight.add_theme_color_override("font_color",Color("f1d79a"))
 top.add_child(fight)
 v.add_child(top)
 var lanes_txt = []
 for l in dep.lanes:
  var seen = []
  for b in 6:
   var t = pb.field.terrain[l][b]
   if not t in seen: seen.append(t)
  lanes_txt.append("%s: %s" % [data.deployment_lane_name(dep.lanes,l),"/".join(seen.map(func(t): return {"closed":"impassable"}.get(t,t)))])
 var info = UiKit.label("Weather: %s · %s" % [pb.weather," · ".join(lanes_txt)],13,UiKit.TEXT)
 info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 v.add_child(info)
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",8)
 row.add_child(UiKit.label("Templates:",13,UiKit.TEXT_DIM))
 for t in data.deployment_templates():
  row.add_child(_button(t.capitalize(),func(): apply_template(t),"Template_"+t))
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 row.add_child(spacer)
 row.add_child(UiKit.label("Balance of power",13,UiKit.TEXT_DIM))
 var holder = Control.new()
 holder.custom_minimum_size = Vector2(300,18)
 balance = holder
 row.add_child(holder)
 odds_label = UiKit.label("",14,Color("f1d79a"),UiKit.FONT_BOLD)
 row.add_child(odds_label)
 row.add_child(_button("Update odds",update_odds,"UpdateOdds"))
 v.add_child(row)
 return f

func _build_3d():
 viewport_box = SubViewportContainer.new()
 viewport_box.stretch = true
 viewport_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 board_area.add_child(viewport_box)
 viewport = SubViewport.new()
 viewport.own_world_3d = true
 viewport.msaa_3d = Viewport.MSAA_2X
 viewport_box.add_child(viewport)
 var env = WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("1d1914")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("a8b0b8")
 env.environment.ambient_light_energy = 0.6
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 viewport.add_child(env)
 var sun = DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-55,-30,0)
 sun.light_energy = 1.2
 sun.shadow_enabled = true
 viewport.add_child(sun)
 camera = Camera3D.new()
 camera.fov = 40
 viewport.add_child(camera)
 var s = 1.0 if role == 0 else -1.0
 camera.position = Vector3(0,29,s*29)
 camera.look_at(Vector3(0,0,s*2.0))
 tabletop = AssetManifest.instantiate("battle.tabletop")
 viewport.add_child(tabletop)
 var cols = [UiKit.colors(data.faction(pb.attacker.faction)).primary,UiKit.colors(data.faction(pb.defender.faction)).primary]
 tabletop.build({"terrain":pb.field.terrain,"walls":pb.field.get("walls") != null,"colors":cols})
 viewport_box.gui_input.connect(_on_3d_input)

func _build_2d():
 board = Board.new()
 board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 board.setup(pb.field.terrain,role,pb.field.get("walls") != null)
 board.slot_clicked.connect(_on_slot)
 board_area.add_child(board)

func _set_view(three_d: bool):
 view_3d = three_d
 viewport_box.visible = three_d
 board.visible = not three_d
 view_button.text = "2D board" if three_d else "3D tabletop"

func _orders_panel() -> Control:
 var f = _framed()
 f.custom_minimum_size = Vector2(230,0)
 order_box = VBoxContainer.new()
 order_box.add_theme_constant_override("separation",4)
 f.add_child(order_box)
 order_title = UiKit.header("Orders",16)
 order_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 order_title.custom_minimum_size = Vector2(210,0)
 order_box.add_child(order_title)
 for o in [["hold","Hold"],["aggressive","Aggressive"],["flank:left","Flank left"],["flank:right","Flank right"],["protect","Protect..."],["reserve","Reserve"]]:
  order_box.add_child(_button(o[1],_order.bind(o[0]),"Order_"+o[0].replace(":","_")))
 order_box.add_child(UiKit.divider(colors.trim))
 message = UiKit.label("Select a unit.",13,UiKit.TEXT_DIM)
 message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 message.custom_minimum_size = Vector2(210,0)
 order_box.add_child(message)
 var help = UiKit.label("Hold: stand and fight what comes.\nAggressive: advance and charge.\nFlank: ride around an outer lane to the enemy rear.\nProtect: shield another unit.\nReserve: wait behind the line; intercept flankers, fill broken lanes.",12,Color(UiKit.TEXT_DIM,0.8))
 help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 help.custom_minimum_size = Vector2(210,0)
 order_box.add_child(help)
 return f

# --- State changes ------------------------------------------------------------------------------

func _changed():
 refresh()
 odds_dirty = true
 odds_label.text = "(changed: updating...)"
 odds_timer.start()

func update_odds():
 odds_timer.stop()
 odds = data.deployment_odds(pb,dep)
 odds_dirty = false
 _draw_balance()

func apply_template(t: String):
 data.deployment_apply_template(pb,dep,t)
 selected = -1
 picking_protect = false
 say("Template: %s. Adjust it as you like." % t.capitalize())
 _changed()

func reset():
 dep = data.deployment_create(pb)
 selected = -1
 picking_protect = false
 say("Reset to your faction's default deployment.")
 _changed()

func say(text: String,bad := false):
 message.text = text
 message.add_theme_color_override("font_color",Color("ef8a6a") if bad else UiKit.TEXT_DIM)

func select(i: int):
 if picking_protect and i >= 0 and selected >= 0:
  var r = data.deployment_order(dep,selected,"protect",i)
  picking_protect = false
  if r.ok: say("%s protects %s." % [_name(selected),_name(i)])
  else: say(r.reason,true)
  _changed()
  return
 selected = i
 picking_protect = false
 if i == -2: say("General: click a lane in your general's row.")
 elif i >= 0: say("%s: %s. Click a slot to move it, or give an order." % [_name(i),ORDER_NAMES.get(dep.units[i].order,"")])
 refresh()

func _name(i: int) -> String:
 return data.unit_type(dep.units[i].unit).display_name

func _order(o: String):
 if selected < 0:
  say("Select one of your units first.",true)
  return
 var parts = o.split(":")
 if parts[0] == "protect":
  picking_protect = true
  say("Protect: click the unit %s should shield." % _name(selected))
  return
 var r = data.deployment_order(dep,selected,parts[0],parts[1] if parts.size()>1 else null)
 if r.ok: say("%s: %s." % [_name(selected),ORDER_NAMES[parts[0]]+(" "+parts[1] if parts.size()>1 else "")])
 else: say(r.reason,true)
 _changed()

# A slot was clicked (3D or 2D): place the selected unit, set the general's lane, or select a unit there.
func _on_slot(slot: Dictionary):
 if slot.is_empty(): return
 if slot.role != role:
  say("That is the enemy's side.",true)
  return
 if selected == -2:
  if slot.line != "general":
   say("The general stands in your general's row.",true)
   return
  var g = data.deployment_general(dep,slot.lane)
  if g.ok: say("General moved to the %s lane." % data.deployment_lane_name(dep.lanes,slot.lane).to_lower())
  else: say(g.reason,true)
  _changed()
  return
 if slot.line == "general":
  select(-2)
  return
 if selected >= 0 and not picking_protect:
  var r = data.deployment_place(dep,selected,slot.lane,slot.line)
  if r.ok: say("%s placed: %s %s." % [_name(selected),data.deployment_lane_name(dep.lanes,slot.lane),slot.line] if slot.line != "reserve" else "%s held in reserve." % _name(selected))
  else: say(r.reason,true)
  _changed()
  return
 # Nothing selected (or picking a Protect target): pick the first own unit in that slot.
 for i in dep.units.size():
  var u = dep.units[i]
  if u.line == slot.line and (slot.line == "reserve" or int(u.lane) == slot.lane):
   select(i)
   return

func _on_3d_input(e):
 if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
  _on_slot(slot_at_3d(e.position))

func slot_at_3d(p: Vector2) -> Dictionary:
 var vp = p*Vector2(viewport.size.x/maxf(1.0,viewport_box.size.x),viewport.size.y/maxf(1.0,viewport_box.size.y))
 var o = camera.project_ray_origin(vp)
 var d = camera.project_ray_normal(vp)
 if absf(d.y)<0.0001: return {}
 var t = -o.y/d.y
 return tabletop.slot_at(o+d*t)

# Drag from the tray: release over the board places the unit.
func _input(e):
 if dragging >= 0 and e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
  var i = dragging
  dragging = -1
  var local = board_area.get_global_transform().affine_inverse()*e.position
  if Rect2(Vector2.ZERO,board_area.size).has_point(local):
   selected = i
   _on_slot(slot_at_3d(local) if view_3d else board.slot_at(local))

func _fight():
 if odds_dirty: update_odds()
 var out = data.fight(pb,dep)
 fought.emit(pb,out)

# --- Drawing ------------------------------------------------------------------------------------

func _view_units() -> Array:
 var out = []
 var my_color = UiKit.colors(data.faction(pb.attacker.faction if role == 0 else pb.defender.faction)).primary
 var their_color = UiKit.colors(data.faction(pb.defender.faction if role == 0 else pb.attacker.faction)).primary
 for i in dep.units.size():
  var u = dep.units[i]
  out.append({"key":"p%d" % i,"unit":u.unit,"name":data.unit_type(u.unit).display_name,"lane":int(u.lane),"line":u.line,"order":u.order,"hidden":false,"role":role,"color":my_color})
 out.append({"key":"pg","unit":"commander","name":"General","lane":int(dep.general_lane),"line":"general","order":"hold","hidden":false,"role":role,"color":my_color})
 for i in enemy.size():
  var u = enemy[i]
  out.append({"key":"e%d" % i,"unit":u.unit,"name":data.unit_type(u.unit).display_name,"lane":int(u.lane),"line":u.line,"order":u.order,"hidden":u.hidden,"role":1-role,"color":their_color})
 out.append({"key":"eg","unit":"commander","name":"General","lane":dep.lanes/2,"line":"general","order":"hold","hidden":false,"role":1-role,"color":their_color})
 return out

func _arrows() -> Array:
 var out = []
 for i in dep.units.size():
  var u = dep.units[i]
  if u.order == "protect" and int(u.protect) >= 0: out.append({"from_key":"p%d" % i,"to_key":"p%d" % int(u.protect),"color":Color("7fc8ef")})
  if u.order == "flank": out.append({"from_key":"p%d" % i,"to_slot":{"role":1-role,"lane":int(u.lane),"line":"back"},"color":Color("e9cf5a"),"flank":true})
 return out

func refresh():
 var units = _view_units()
 tabletop.set_units(units)
 var arr3 = []
 for a in _arrows():
  var p0 = tabletop.block_position(a.from_key)
  var pts = [p0]
  if a.has("to_key"): pts.append(tabletop.block_position(a.to_key))
  else:
   var edge = (0 if int(a.to_slot.lane) == 0 else dep.lanes-1)
   var x = tabletop.lane_x(edge)+(-1 if edge == 0 else 1)*tabletop.LANE_W*0.55
   var target = tabletop.slot_point(a.to_slot.role,int(a.to_slot.lane),"back",0,1)
   pts.append(Vector3(x,0,p0.z))
   pts.append(Vector3(x,0,target.z))
   pts.append(target)
  arr3.append({"points":pts,"color":a.color})
 tabletop.set_arrows(arr3)
 tabletop.select("p%d" % selected if selected >= 0 else ("pg" if selected == -2 else ""))
 board.units = units
 board.arrows = _arrows()
 board.selected = "p%d" % selected if selected >= 0 else ("pg" if selected == -2 else "")
 board.general_lanes = [int(dep.general_lane),dep.lanes/2] if role == 0 else [dep.lanes/2,int(dep.general_lane)]
 board.queue_redraw()
 _fill_tray()
 if not odds_dirty: _draw_balance()

func _draw_balance():
 for c in balance.get_children(): c.queue_free()
 var a = UiKit.colors(data.faction(pb.attacker.faction)).primary.lightened(0.15)
 var d = UiKit.colors(data.faction(pb.defender.faction)).primary.lightened(0.15)
 var bar = load("res://ui/campaign_ui.gd").BalanceBar.new(odds,a,d)
 bar.custom_minimum_size = Vector2(300,18)
 bar.name = "BalanceBar"
 balance.add_child(bar)
 var mine = odds if role == 0 else 1.0-odds
 odds_label.text = "%d%%" % int(round(mine*100))

func _fill_tray():
 for c in tray.get_children():
  tray.remove_child(c)
  c.queue_free()
 var fac = data.faction(pb.attacker.faction if role == 0 else pb.defender.faction)
 var g = Cards.unit_card(data.unit_type("commander"),{"unit":"commander","name":"General"},fac,studio,"Your general: click, then a lane in the general's row.",func(): select(-2))
 g.selected = selected == -2
 tray.add_child(g)
 for i in dep.units.size():
  var u = dep.units[i]
  var t = data.unit_type(u.unit)
  var tip = "%s · %s\n%s\nPlaced: %s" % [t.display_name,ORDER_NAMES.get(u.order,""),t.description,"reserve" if u.line == "reserve" else "%s %s" % [data.deployment_lane_name(dep.lanes,int(u.lane)),u.line]]
  var card = Cards.unit_card(t,u,fac,studio,tip,select.bind(i))
  card.selected = i == selected
  card.gui_input.connect(func(e):
   if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not picking_protect: dragging = i)
  var badge = UiKit.label({"hold":"H","aggressive":"A","flank":"F","protect":"P","reserve":"R"}.get(u.order,""),15,{"hold":Color("e9e2c8"),"aggressive":Color("ef8a6a"),"flank":Color("e9cf5a"),"protect":Color("7fc8ef"),"reserve":Color("b7a8e0")}.get(u.order,Color.WHITE),UiKit.FONT_BOLD)
  badge.name = "OrderBadge"
  badge.position = Vector2(60,4)
  badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
  card.add_child(badge)
  tray.add_child(card)
