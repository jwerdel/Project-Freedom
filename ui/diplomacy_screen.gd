extends Control
# Diplomacy full screen (TW:WH3, docs/tw-ui-parity.md §15): your faction on the left, the known
# factions in the centre with Quick Deal, Negotiate and War Coordination, the selected faction
# mirrored on the right with its traits and an acceptance indicator. Wired now: declaring war
# (with a confirmation), war and peace status, strength; attitude, reliability and deal chances are
# placeholders; every treaty is greyed "Coming later" until the diplomacy system
# (docs/diplomacy-design.md). Reads only through UiData.

signal closed
signal war_declared(faction_id: String)

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")

const COMING = "\nComing later (diplomacy system)."
const DEALS = [["non_aggression","Non-aggression pact"],["trade","Trade agreement"],["access","Military access"],["defensive","Defensive alliance"],["military","Military alliance"],["peace","Peace"]]

var data
var colors: Dictionary
var selected := ""
var view := {}
var left: VBoxContainer
var centre: VBoxContainer
var right: VBoxContainer
var confirm: Control

# Attitude face in five steps (TW:WH3): 0 hostile ... 4 very friendly.
class Face extends Control:
 var step := 2
 func _init(s := 2,size := 26.0):
  step = s
  custom_minimum_size = Vector2(size,size)
  mouse_filter = Control.MOUSE_FILTER_PASS
 func _draw():
  var c = size*0.5
  var r = minf(size.x,size.y)*0.45
  var col = [Color("c0392b"),Color("d9822b"),Color("c9b27a"),Color("7fb65a"),Color("3fa34d")][step]
  draw_circle(c,r,col)
  draw_arc(c,r,0,TAU,24,Color(0,0,0,0.6),1.5)
  for x in [-0.35,0.35]: draw_circle(c+Vector2(x*r,-0.2*r),r*0.11,Color(0.1,0.07,0.05))
  var curve = (step-2)*0.18
  var pts = PackedVector2Array()
  for i in 9:
   var t = -1.0+i*0.25
   pts.append(c+Vector2(t*0.45*r,0.35*r+curve*r*(1.0-t*t)))
  draw_polyline(pts,Color(0.1,0.07,0.05),2.0)

func _init(ui_data,trim_colors: Dictionary,focus := ""):
 data = ui_data
 colors = trim_colors
 name = "DiplomacyScreen"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var bg = ColorRect.new()
 bg.color = Color(0.05,0.035,0.025,0.96)
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,28)
 add_child(margin)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",10)
 margin.add_child(v)
 var head = HBoxContainer.new()
 var title = UiKit.header("Diplomacy",30)
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 var close = Button.new()
 close.name = "DiplomacyClose"
 close.text = "Close (Esc)"
 close.focus_mode = Control.FOCUS_NONE
 close.custom_minimum_size = Vector2(130,34)
 close.pressed.connect(func(): closed.emit())
 head.add_child(close)
 v.add_child(head)
 v.add_child(UiKit.divider(colors.trim))
 var cols = HBoxContainer.new()
 cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
 cols.add_theme_constant_override("separation",18)
 v.add_child(cols)
 left = _column(cols,330,"DiplomacyMe")
 centre = _column(cols,0,"DiplomacyCentre")
 centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 right = _column(cols,330,"DiplomacyThem")
 view = data.diplomacy()
 selected = focus if view.factions.any(func(f): return f.id == focus) else (view.factions[0].id if not view.factions.is_empty() else "")
 refresh()

func _column(parent: Control,w: float,node_name: String) -> VBoxContainer:
 var frame = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.9))
 frame.custom_minimum_size.x = w
 frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
 if w == 0: frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(frame)
 var c = VBoxContainer.new()
 c.name = node_name
 c.add_theme_constant_override("separation",8)
 frame.add_child(c)
 return c

func _clear(box: Node):
 for c in box.get_children():
  box.remove_child(c)
  c.queue_free()

func select(id: String):
 selected = id
 refresh()

func refresh():
 view = data.diplomacy()
 _fill_side(left,view.me,true)
 _fill_centre()
 var them = view.factions.filter(func(f): return f.id == selected)
 if them.is_empty():
  _clear(right)
  right.add_child(UiKit.label("No faction selected.",15,UiKit.TEXT_DIM))
 else: _fill_side(right,them[0],false)

# One faction's column (left: yours; right: the selected faction, mirrored).
func _fill_side(box: VBoxContainer,f: Dictionary,mine: bool):
 _clear(box)
 var em = CenterContainer.new()
 em.add_child(Widgets.Emblem.new(f.faction_data,110))
 box.add_child(em)
 var nm = UiKit.header(f.name,22)
 nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 box.add_child(nm)
 var sub = UiKit.label("%s · %s" % [f.realm,f.culture] if f.realm != "" else f.culture,14,UiKit.TEXT_DIM)
 sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 box.add_child(sub)
 if mine:
  var rel = UiKit.label("Reliability: %s" % f.reliability,16,Color("f2cf6a"),UiKit.FONT_BOLD)
  rel.name = "Reliability"
  rel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  rel.tooltip_text = "How far other factions trust your word. Placeholder: you have broken no treaty.\nReputation and reliability come with diplomacy (docs/diplomacy-design.md §3.1)."
  rel.mouse_filter = Control.MOUSE_FILTER_PASS
  box.add_child(rel)
 else:
  var att = HBoxContainer.new()
  att.name = "Attitude"
  att.alignment = BoxContainer.ALIGNMENT_CENTER
  att.add_theme_constant_override("separation",6)
  att.add_child(Face.new(2,28))
  var al = UiKit.label("Attitude: %s" % f.attitude_label,16,UiKit.TEXT,UiKit.FONT_BOLD)
  att.add_child(al)
  att.tooltip_text = "Attitude toward you: %s (placeholder)\nEvery faction starts neutral; shared history (attacks, trade, alliances, gifts) moves it once diplomacy exists." % f.attitude_label
  att.mouse_filter = Control.MOUSE_FILTER_STOP
  box.add_child(att)
  var st = UiKit.label("At war with you" if f.at_war else "At peace with you (no treaty)",16,Color("ef6a5a") if f.at_war else Color("9fd27f"),UiKit.FONT_BOLD)
  st.name = "WarStatus"
  st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  box.add_child(st)
 box.add_child(UiKit.divider(colors.trim))
 box.add_child(UiKit.header("Strength",16))
 for l in [["Settlements","%d" % f.settlements],["Armies","%d" % f.armies],["Soldiers",UiKit.format_int(f.men)]]:
  var r = HBoxContainer.new()
  var k = UiKit.label(l[0],15,UiKit.TEXT_DIM)
  k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  r.add_child(k)
  r.add_child(UiKit.label(l[1],15))
  box.add_child(r)
 box.add_child(UiKit.header("Diplomatic traits" if not mine else "Your tendencies",16))
 var traits = UiKit.label(", ".join(f.traits) if not f.traits.is_empty() else "None known",14,UiKit.TEXT)
 traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 traits.tooltip_text = "The house's tendencies (data: factions). Other factions weigh them; perceived reputation comes with diplomacy."
 traits.mouse_filter = Control.MOUSE_FILTER_PASS
 box.add_child(traits)
 box.add_child(UiKit.header("Wars",16))
 var wars = UiKit.label(", ".join(f.wars) if not f.wars.is_empty() else "At war with nobody",14,UiKit.TEXT)
 wars.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 box.add_child(wars)
 box.add_child(UiKit.header("Treaties",16))
 box.add_child(UiKit.label("None",14,UiKit.TEXT_DIM))

func _fill_centre():
 _clear(centre)
 centre.add_child(UiKit.header("Known factions",18))
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",8)
 for h in [["",34],["Faction",250],["Status",90],["Attitude",110],["Deal chance",100]]:
  var l = UiKit.label(h[0],13,UiKit.TEXT_DIM)
  l.custom_minimum_size.x = h[1]
  head.add_child(l)
 centre.add_child(head)
 var list = VBoxContainer.new()
 list.name = "DiplomacyFactions"
 list.add_theme_constant_override("separation",3)
 for f in view.factions:
  var b = Button.new()
  b.name = "Dip_"+f.id
  b.toggle_mode = true
  b.focus_mode = Control.FOCUS_NONE
  b.button_pressed = f.id == selected
  b.custom_minimum_size.y = 38
  b.tooltip_text = "%s\n%s · %d settlements, %d armies\nClick to select" % [f.name,"At war with you" if f.at_war else "At peace with you",f.settlements,f.armies]
  b.pressed.connect(select.bind(f.id))
  var h = HBoxContainer.new()
  h.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  h.offset_left = 4
  h.add_theme_constant_override("separation",8)
  var em = Widgets.Emblem.new(f.faction_data,30)
  em.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.add_child(em)
  for c in [[f.name,250,UiKit.TEXT],["War" if f.at_war else "Peace",90,Color("ef6a5a") if f.at_war else Color("9fd27f")]]:
   var l = UiKit.label(c[0],15,c[2])
   l.custom_minimum_size.x = c[1]
   l.clip_text = true
   l.mouse_filter = Control.MOUSE_FILTER_IGNORE
   h.add_child(l)
  var face = HBoxContainer.new()
  face.custom_minimum_size.x = 110
  face.mouse_filter = Control.MOUSE_FILTER_IGNORE
  var fc = Face.new(2,22)
  fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
  face.add_child(fc)
  var al = UiKit.label(f.attitude_label,13,UiKit.TEXT_DIM)
  al.mouse_filter = Control.MOUSE_FILTER_IGNORE
  face.add_child(al)
  h.add_child(face)
  var dc = UiKit.label("—",15,UiKit.TEXT_DIM)
  dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.add_child(dc)
  b.add_child(h)
  list.add_child(b)
 if view.factions.is_empty(): list.add_child(UiKit.label("You have not met any faction yet.",15,UiKit.TEXT_DIM))
 var scroll = ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.add_child(list)
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 centre.add_child(scroll)
 centre.add_child(UiKit.divider(colors.trim))
 # Quick Deal (TW:WH3): one-click proposals with their chance; all greyed until diplomacy.
 centre.add_child(UiKit.header("Quick Deal",16))
 var deals = HFlowContainer.new()
 deals.name = "QuickDeal"
 deals.add_theme_constant_override("h_separation",6)
 deals.add_theme_constant_override("v_separation",6)
 for d in DEALS:
  var b = Button.new()
  b.name = "Deal_"+d[0]
  b.text = d[1]
  b.disabled = true
  b.focus_mode = Control.FOCUS_NONE
  b.tooltip_text = d[1]+COMING
  b.mouse_filter = Control.MOUSE_FILTER_STOP
  deals.add_child(b)
 centre.add_child(deals)
 # Acceptance indicator (TW-style bar, "Will not accept" ... "Very likely"): placeholder.
 var acc = HBoxContainer.new()
 acc.name = "Acceptance"
 acc.add_theme_constant_override("separation",8)
 acc.add_child(UiKit.label("Acceptance",15,UiKit.TEXT_DIM))
 var bar = ProgressBar.new()
 bar.show_percentage = false
 bar.custom_minimum_size = Vector2(260,14)
 bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 bar.value = 0
 bar.modulate = Color(0.6,0.6,0.6)
 acc.add_child(bar)
 acc.add_child(UiKit.label("No proposal",14,Color(UiKit.TEXT_DIM,0.7)))
 acc.tooltip_text = "How likely they are to accept the proposal on the table."+COMING
 acc.mouse_filter = Control.MOUSE_FILTER_STOP
 centre.add_child(acc)
 var actions = HBoxContainer.new()
 actions.add_theme_constant_override("separation",10)
 for a in [["Negotiate","Negotiate","Open the proposal builder: offers and demands in bundles."],["WarCoordination","War coordination","Set targets for your allies."]]:
  var b = Button.new()
  b.name = a[0]
  b.text = a[1]
  b.disabled = true
  b.focus_mode = Control.FOCUS_NONE
  b.custom_minimum_size = Vector2(170,36)
  b.tooltip_text = a[1]+"\n"+a[2]+COMING
  b.mouse_filter = Control.MOUSE_FILTER_STOP
  actions.add_child(b)
 var them = view.factions.filter(func(f): return f.id == selected)
 var war = Button.new()
 war.name = "DeclareWarDip"
 war.focus_mode = Control.FOCUS_NONE
 war.custom_minimum_size = Vector2(170,36)
 war.text = "Declare war"
 war.disabled = them.is_empty() or them[0].at_war
 war.tooltip_text = ("Already at war with %s." % them[0].name if not them.is_empty() and them[0].at_war else "Declare war on %s." % them[0].name) if not them.is_empty() else "Select a faction."
 war.add_theme_color_override("font_color",Color("ef8a6a"))
 war.pressed.connect(_ask_war)
 actions.add_child(war)
 centre.add_child(actions)

# Declaring war asks first (TW: a confirmation that lists the treaties it breaks; none exist yet).
func _ask_war():
 var them = view.factions.filter(func(f): return f.id == selected)
 if them.is_empty() or them[0].at_war: return
 var box = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.98))
 box.name = "WarConfirm"
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",10)
 box.add_child(v)
 var t = UiKit.header("Declare war on %s?" % them[0].name,20)
 t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(t)
 var txt = UiKit.label("You have no treaties with them to break. Until diplomacy exists there is no way back to peace.",15,UiKit.TEXT)
 txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 txt.custom_minimum_size.x = 420
 v.add_child(txt)
 var row = HBoxContainer.new()
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 row.add_theme_constant_override("separation",16)
 var yes = Button.new()
 yes.name = "WarYes"
 yes.text = "Declare war"
 yes.focus_mode = Control.FOCUS_NONE
 yes.pressed.connect(func():
  data.declare_war(them[0].id)
  war_declared.emit(them[0].id)
  box.queue_free()
  confirm = null
  refresh())
 row.add_child(yes)
 var no = Button.new()
 no.name = "WarNo"
 no.text = "Cancel"
 no.focus_mode = Control.FOCUS_NONE
 no.pressed.connect(func():
  box.queue_free()
  confirm = null)
 row.add_child(no)
 v.add_child(row)
 add_child(box)
 box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 box.grow_horizontal = Control.GROW_DIRECTION_BOTH
 box.grow_vertical = Control.GROW_DIRECTION_BOTH
 confirm = box
