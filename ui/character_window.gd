extends HBoxContainer
# Lords & Heroes character window (TW:WH3 character details, docs/tw-ui-parity.md §15): the
# full-body model on a dark backdrop with name, epithet, level and experience on the left; tabs
# Details (stats, traits, army), Skills (rows by function, points, auto-allocate) and Equipment
# (placeholder slots) on the right. Reads only through UiData (character, take_skill,
# set_auto_skills). Skills have no gameplay effect yet (core/characters.gd).

signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")

const COMING = "\nComing later."
const TABS = [["details","Details"],["skills","Skills"],["equipment","Equipment"]]
const EQUIPMENT = [["Weapon","weapon"],["Armour","armour"],["Talisman","talisman"],["Enchanted item","enchanted"],["Banner","banner"],["Follower","follower"],["Follower","follower2"]]
const MODEL_SIZE = Vector2(330,540)

var data
var colors: Dictionary
var army_id := ""
var tab := "details"
var view := {}
var body: VBoxContainer
var tab_buttons := {}
var figure: Node3D
var spin := 0.0
var dragging := false

func _init(ui_data,trim_colors: Dictionary,id: String,start_tab := "details"):
 data = ui_data
 colors = trim_colors
 army_id = id
 tab = start_tab
 name = "CharacterWindow"
 add_theme_constant_override("separation",14)
 _build()

func _build():
 view = data.character(army_id)
 add_child(_model_column())
 var right = VBoxContainer.new()
 right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 right.add_theme_constant_override("separation",8)
 add_child(right)
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",6)
 for t in TABS:
  var b = Button.new()
  b.name = "Tab_"+t[0]
  b.text = t[1]
  b.toggle_mode = true
  b.focus_mode = Control.FOCUS_NONE
  b.custom_minimum_size = Vector2(130,34)
  b.pressed.connect(set_tab.bind(t[0]))
  tab_buttons[t[0]] = b
  head.add_child(b)
 var gap = Control.new()
 gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(gap)
 var close = Button.new()
 close.name = "CharacterClose"
 close.text = "Close"
 close.focus_mode = Control.FOCUS_NONE
 close.pressed.connect(func(): closed.emit())
 head.add_child(close)
 right.add_child(head)
 right.add_child(UiKit.divider(colors.trim))
 body = VBoxContainer.new()
 body.size_flags_vertical = Control.SIZE_EXPAND_FILL
 body.add_theme_constant_override("separation",8)
 right.add_child(body)
 set_tab(tab)

# --- Left: the model, name, epithet, level --------------------------------------------------

func _model_column() -> Control:
 var col = VBoxContainer.new()
 col.name = "ModelColumn"
 col.add_theme_constant_override("separation",4)
 var nm = UiKit.header(view.name,22)
 nm.name = "CharacterName"
 nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 col.add_child(nm)
 var ep = UiKit.label(view.epithet if view.epithet != "" else "No epithet yet",14,Color("e2c27a") if view.epithet != "" else Color(UiKit.TEXT_DIM,0.7))
 ep.name = "Epithet"
 ep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 ep.tooltip_text = "Epithets are earned from deeds (the Great, the Wise, the Butcher), not chosen.\nThey come with the character system."
 ep.mouse_filter = Control.MOUSE_FILTER_PASS
 col.add_child(ep)
 var sub = UiKit.label("General of %s" % view.faction_data.name,14,UiKit.TEXT_DIM)
 sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 col.add_child(sub)
 var box = SubViewportContainer.new()
 box.name = "CharacterModel"
 box.stretch = true
 box.custom_minimum_size = MODEL_SIZE
 box.tooltip_text = "Drag to turn the model."
 box.gui_input.connect(_model_input)
 var vp = SubViewport.new()
 vp.own_world_3d = true
 vp.msaa_3d = Viewport.MSAA_4X
 vp.size = Vector2i(MODEL_SIZE)
 box.add_child(vp)
 var env = Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("1a1310")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("8a7a68")
 env.ambient_light_energy = 0.6
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 var we = WorldEnvironment.new()
 we.environment = env
 vp.add_child(we)
 var key = DirectionalLight3D.new()
 key.rotation_degrees = Vector3(-35,-30,0)
 key.light_energy = 1.6
 vp.add_child(key)
 var rim = DirectionalLight3D.new()
 rim.rotation_degrees = Vector3(-20,150,0)
 rim.light_color = Color("ffd59a")
 rim.light_energy = 1.2
 vp.add_child(rim)
 figure = AssetManifest.instantiate("unit.commander")
 vp.add_child(figure)
 if figure.has_method("set_faction_colors"): figure.set_faction_colors(Color(view.faction_data.primary),Color(view.faction_data.get("secondary",view.faction_data.primary)))
 figure.rotation.y = -0.35
 if figure.has_method("set_standard_visible"): figure.set_standard_visible(false)
 var cam = Camera3D.new()
 cam.fov = 30
 cam.position = Vector3(0,2.6,12.4)
 vp.add_child(cam)
 cam.look_at_from_position(cam.position,Vector3(0,2.3,0))
 col.add_child(box)
 # Level badge and the experience bar under the model.
 var lv = HBoxContainer.new()
 lv.add_theme_constant_override("separation",8)
 var badge = UiKit.header("Level %d" % view.level,17)
 badge.name = "CharacterLevel"
 lv.add_child(badge)
 var bar = ProgressBar.new()
 bar.name = "XpBar"
 bar.show_percentage = false
 bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 bar.custom_minimum_size.y = 12
 bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 var x = view.xp
 if x.to>x.from:
  bar.max_value = x.to-x.from
  bar.value = clampf(x.xp-x.from,0,x.to-x.from)
  bar.tooltip_text = "Experience %d / %d to level %d\nGenerals gain experience from every battle, more from victories (data/battle.json)." % [int(x.xp),int(x.to),view.level+1]
 else:
  bar.value = bar.max_value
  bar.tooltip_text = "Highest placeholder level reached."
 lv.add_child(bar)
 col.add_child(lv)
 return col

func _model_input(e: InputEvent):
 if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT: dragging = e.pressed
 elif e is InputEventMouseMotion and dragging and figure: figure.rotation.y += e.relative.x*0.01

func _process(delta: float):
 if figure and not dragging: figure.rotation.y += delta*0.15

# --- Tabs ------------------------------------------------------------------------------------

func set_tab(t: String):
 tab = t
 for k in tab_buttons: tab_buttons[k].set_pressed_no_signal(k == tab)
 refresh()

func refresh():
 view = data.character(army_id)
 for c in body.get_children():
  body.remove_child(c)
  c.queue_free()
 match tab:
  "details": _details()
  "skills": _skills()
  "equipment": _equipment()

func _section(title: String) -> Label:
 var l = UiKit.header(title,16)
 return l

func _details():
 body.add_child(_section("Statistics"))
 var grid = GridContainer.new()
 grid.name = "CharacterStats"
 grid.columns = 4
 grid.add_theme_constant_override("h_separation",14)
 grid.add_theme_constant_override("v_separation",4)
 for s in view.stats:
  var l = UiKit.label(s[0],15,UiKit.TEXT_DIM)
  l.custom_minimum_size.x = 120
  l.tooltip_text = s[2]
  l.mouse_filter = Control.MOUSE_FILTER_PASS
  grid.add_child(l)
  var v = UiKit.label(str(s[1]),15,UiKit.TEXT,UiKit.FONT_BOLD)
  v.custom_minimum_size.x = 70
  grid.add_child(v)
 body.add_child(grid)
 body.add_child(UiKit.divider(colors.trim))
 body.add_child(_section("Traits"))
 var tr = HFlowContainer.new()
 tr.name = "CharacterTraits"
 tr.add_theme_constant_override("h_separation",8)
 for t in view.traits:
  var chip = Button.new()
  chip.text = t.name
  chip.focus_mode = Control.FOCUS_NONE
  chip.tooltip_text = "%s\n%s" % [t.name,t.text]
  tr.add_child(chip)
 if view.traits.is_empty(): tr.add_child(UiKit.label("No traits yet. Life traits are earned from deeds and events (character system).",14,Color(UiKit.TEXT_DIM,0.75)))
 body.add_child(tr)
 body.add_child(UiKit.divider(colors.trim))
 body.add_child(_section("Army"))
 var a = view.army
 var lines = [["Army",a.display_name],["Location",view.location],["Units","%d / %d" % [1+a.units.size(),a.max_units]],["Men",UiKit.format_int(view.men)],["Upkeep","%d gold per turn" % a.upkeep]]
 var ag = GridContainer.new()
 ag.name = "CharacterArmy"
 ag.columns = 2
 ag.add_theme_constant_override("h_separation",14)
 for l in lines:
  ag.add_child(UiKit.label(l[0],15,UiKit.TEXT_DIM))
  ag.add_child(UiKit.label(l[1],15))
 body.add_child(ag)
 var counts = {}
 for u in a.units: counts[u.unit] = int(counts.get(u.unit,0))+1
 var names = []
 for k in counts: names.append("%d× %s" % [counts[k],data.unit_type(k).display_name])
 var comp = UiKit.label(", ".join(names) if not names.is_empty() else "No units.",14,UiKit.TEXT_DIM)
 comp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 body.add_child(comp)

func _skills():
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",16)
 var auto = CheckBox.new()
 auto.name = "AutoAllocate"
 auto.text = "Auto-allocate skill points"
 auto.focus_mode = Control.FOCUS_NONE
 auto.button_pressed = view.auto
 auto.disabled = not view.player_owned
 auto.tooltip_text = "Spend this general's skill points automatically at End Turn (and now).\nAlso removes him from the unspent-points warning."
 auto.toggled.connect(func(on):
  data.set_auto_skills(army_id,on)
  refresh())
 head.add_child(auto)
 var pts = UiKit.label("Skill points: %d" % view.points,16,Color("8fd36b") if view.points>0 else UiKit.TEXT_DIM,UiKit.FONT_BOLD)
 pts.name = "SkillPoints"
 pts.tooltip_text = "One point per level (data/skills.json). Placeholder skills: no gameplay effect yet."
 pts.mouse_filter = Control.MOUSE_FILTER_PASS
 head.add_child(pts)
 body.add_child(head)
 for r in view.rows:
  var row = HBoxContainer.new()
  row.name = "SkillRow_"+r.id
  row.add_theme_constant_override("separation",6)
  var lab = VBoxContainer.new()
  lab.custom_minimum_size.x = 150
  lab.add_child(UiKit.header(r.name,16))
  var fn = UiKit.label(r.function,12,UiKit.TEXT_DIM)
  fn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  fn.custom_minimum_size.x = 150
  lab.add_child(fn)
  row.add_child(lab)
  for s in r.skills: row.add_child(_skill_tile(s))
  body.add_child(row)
  body.add_child(UiKit.divider(Color(colors.trim,0.5)))
 var note = UiKit.label("Placeholder skill tree: the skills take effect with the character system.",13,Color(UiKit.TEXT_DIM,0.7))
 body.add_child(note)

func _skill_tile(s: Dictionary) -> Control:
 var b = Button.new()
 b.name = "Skill_"+s.id
 b.custom_minimum_size = Vector2(118,62)
 b.focus_mode = Control.FOCUS_NONE
 b.clip_text = true
 b.text = "%s\nLevel %d" % [s.name,s.level]
 var state_text = "Learned" if s.taken else ("Click to learn (1 point)" if s.available else s.reason)
 b.tooltip_text = "%s\n%s\n%s" % [s.name,s.text,state_text]
 var bg = Color("4a3a1c") if s.taken else (Color("244a1f") if s.available else Color("1d1814"))
 var edge = Color("f2cf6a") if s.taken else (Color("8fd36b") if s.available else Color("4a4036"))
 var sb = UiKit.flat(bg,6)
 sb.border_color = edge
 sb.set_border_width_all(2)
 for st in ["normal","hover","pressed","disabled"]: b.add_theme_stylebox_override(st,sb)
 b.add_theme_color_override("font_color",UiKit.TEXT if (s.taken or s.available) else Color(UiKit.TEXT_DIM,0.6))
 b.add_theme_color_override("font_disabled_color",Color(UiKit.TEXT_DIM,0.55) if not s.taken else UiKit.TEXT)
 b.add_theme_font_size_override("font_size",13)
 b.disabled = not (s.available and view.player_owned)
 b.pressed.connect(func():
  data.take_skill(army_id,s.id)
  refresh())
 return b

func _equipment():
 body.add_child(UiKit.label("Items and followers come with the character system.",14,UiKit.TEXT_DIM))
 var grid = GridContainer.new()
 grid.name = "EquipmentSlots"
 grid.columns = 4
 grid.add_theme_constant_override("h_separation",10)
 grid.add_theme_constant_override("v_separation",10)
 for e in EQUIPMENT:
  var slot = PanelContainer.new()
  slot.name = "Slot_"+e[1]
  slot.custom_minimum_size = Vector2(150,90)
  slot.add_theme_stylebox_override("panel",UiKit.textured(UiKit.SLOT,8,8,Color(0.6,0.6,0.6)))
  slot.tooltip_text = e[0]+COMING
  slot.mouse_filter = Control.MOUSE_FILTER_STOP
  var l = UiKit.label("%s\nEmpty" % e[0],14,Color(UiKit.TEXT_DIM,0.6))
  l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  slot.add_child(l)
  grid.add_child(slot)
 body.add_child(grid)
