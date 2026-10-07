extends Control
# The Court (game-design §4; TW:WH3 full-screen panels): the family tree on the left (the ruler and
# spouse, their children and grandchildren; siblings beside them) with placeholder portraits, the rest
# of the court below (courtiers, wards, absorbed families); the selected character on the right:
# portrait, name and epithet, age, career, level, traits, loyalty with its reasons, role, and the
# actions: name heir, make ruler, arrange a marriage, appoint a governor, choose a career (formative
# years), rename, a gift, and the character details (skills, traits, history). Reads only through
# UiData.

signal closed
signal details_requested(character_id: String)

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const Portrait = preload("res://ui/portrait.gd")

var data
var colors: Dictionary
var view := {}
var selected := ""
var tree_box: Control
var others: VBoxContainer
var side: VBoxContainer
var popup: Control

func _init(ui_data,trim_colors: Dictionary,focus := ""):
 data = ui_data
 colors = trim_colors
 name = "CourtScreen"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var bg = ColorRect.new()
 bg.color = Color(0.05,0.035,0.025,0.96)
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(bg)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for s in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+s,28)
 add_child(margin)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",10)
 margin.add_child(v)
 var head = HBoxContainer.new()
 var title = UiKit.header("Court of %s" % data.faction(data.player_faction_id()).name,30)
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(title)
 var close = Button.new()
 close.name = "CourtClose"
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
 var lf = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.9))
 lf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 lf.size_flags_vertical = Control.SIZE_EXPAND_FILL
 cols.add_child(lf)
 var lv = VBoxContainer.new()
 lv.add_theme_constant_override("separation",8)
 lf.add_child(lv)
 lv.add_child(UiKit.header("The family",18))
 tree_box = Control.new()
 tree_box.name = "FamilyTree"
 tree_box.custom_minimum_size = Vector2(760,430)
 tree_box.draw.connect(_draw_lines)
 lv.add_child(tree_box)
 lv.add_child(UiKit.divider(colors.trim))
 var ch = HBoxContainer.new()
 var ct = UiKit.header("The court",18)
 ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 ch.add_child(ct)
 # The soft cap (owner spec 2026-10-07): it grows with Realm Standing; births slow as the court fills.
 var cv = data.court_view()
 var capl = UiKit.label("%d / %d members%s" % [cv.size,cv.cap,"  ·  births slowing" if float(cv.birth_factor)<0.5 and int(cv.size)<int(cv.cap) else ("  ·  full: no births" if int(cv.size)>=int(cv.cap) else "")],14,UiKit.TEXT_DIM)
 capl.name = "CourtCap"
 capl.tooltip_text = "A court grows to a size set by your Realm Standing (%d now). Births slow as it fills and stop at the cap." % int(cv.cap)
 capl.mouse_filter = Control.MOUSE_FILTER_PASS
 ch.add_child(capl)
 lv.add_child(ch)
 var sc = ScrollContainer.new()
 sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
 sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 lv.add_child(sc)
 others = VBoxContainer.new()
 others.name = "Courtiers"
 others.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 sc.add_child(others)
 var rf = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.9))
 rf.custom_minimum_size.x = 420
 rf.size_flags_vertical = Control.SIZE_EXPAND_FILL
 cols.add_child(rf)
 var rsc = ScrollContainer.new()
 rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 rf.add_child(rsc)
 side = VBoxContainer.new()
 side.name = "CharacterCard"
 side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 side.add_theme_constant_override("separation",6)
 rsc.add_child(side)
 selected = focus
 refresh()

func _clear(n: Node):
 for c in n.get_children():
  n.remove_child(c)
  c.queue_free()

func refresh():
 view = data.court_view()
 if selected == "" or not view.members.any(func(m): return m.id == selected): selected = view.ruler
 _build_tree()
 _build_others()
 _build_card()

func _member(id: String) -> Dictionary:
 for m in view.members:
  if m.id == id: return m
 return {}

# --- The family tree ----------------------------------------------------------------------------------

var _nodes := {} # id -> Rect2 of its card in the tree
func _build_tree():
 _clear(tree_box)
 _nodes.clear()
 var r = _member(view.ruler)
 if r.is_empty(): return
 var w = tree_box.custom_minimum_size.x
 var rows = [[r.id]]
 if r.spouse != "" and not _member(r.spouse).is_empty(): rows[0].append(r.spouse)
 # Siblings of the ruler (the same house without parents in the court).
 var sibs = view.members.filter(func(m): return m.id != r.id and m.house == r.house and m.father == "" and m.mother == "" and m.id != r.spouse and not m.id in r.children)
 var kids = r.children.filter(func(k): return not _member(k).is_empty())
 var grand = []
 for k in kids:
  for g in _member(k).children:
   if not _member(g).is_empty(): grand.append(g)
 var gen = [rows[0],kids,grand]
 var cw = 132.0
 var ch = 118.0
 for gi in gen.size():
  var ids = gen[gi]
  if ids.is_empty(): continue
  var y = 8.0+gi*(ch+26.0)
  var total = ids.size()*cw+(ids.size()-1)*10.0
  var x0 = (w-total)*0.5 if gi>0 or sibs.is_empty() else (w-total)*0.5+60.0
  for i in ids.size(): _card(ids[i],Rect2(x0+i*(cw+10.0),y,cw,ch))
  # Spouses of the children sit beside them in the same row (when in the court).
 for i in sibs.size():
  if i>=3: break
  _card(sibs[i].id,Rect2(8.0,8.0+i*(ch*0.72+6.0),cw*0.9,ch*0.72))
 tree_box.queue_redraw()

func _card(id: String,r: Rect2):
 var m = _member(id)
 if m.is_empty(): return
 _nodes[id] = r
 var b = Button.new()
 b.name = "Char_"+id
 b.toggle_mode = true
 b.button_pressed = id == selected
 b.focus_mode = Control.FOCUS_NONE
 b.position = r.position
 b.size = r.size
 b.tooltip_text = "%s\n%s · age %d\nLoyalty %d" % [m.full_name,m.role_text,m.age,m.loyalty]
 b.pressed.connect(func():
  selected = id
  refresh())
 var v = VBoxContainer.new()
 v.mouse_filter = Control.MOUSE_FILTER_IGNORE
 v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 v.alignment = BoxContainer.ALIGNMENT_CENTER
 var pc = CenterContainer.new()
 pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
 var p = Portrait.new(m,minf(64.0,r.size.y-44.0),Color(data.faction(data.player_faction_id()).primary))
 pc.add_child(p)
 v.add_child(pc)
 var n = UiKit.label(m.name+(" ★" if m.ruler else (" ♦" if m.heir else "")),13,Color("f2cf6a") if m.ruler or m.heir else UiKit.TEXT)
 n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 n.clip_text = true
 n.mouse_filter = Control.MOUSE_FILTER_IGNORE
 v.add_child(n)
 var a = UiKit.label("%d · %s" % [m.age,m.career_name if m.career_name != "" else ("child" if m.age<12 else "choosing a path")],11,UiKit.TEXT_DIM)
 a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 a.clip_text = true
 a.mouse_filter = Control.MOUSE_FILTER_IGNORE
 v.add_child(a)
 b.add_child(v)
 tree_box.add_child(b)

# Lines from parents to children.
func _draw_lines():
 for id in _nodes:
  var m = _member(id)
  for k in m.get("children",[]):
   if not _nodes.has(k): continue
   var a: Rect2 = _nodes[id]
   var b: Rect2 = _nodes[k]
   var p0 = Vector2(a.get_center().x,a.end.y)
   var p1 = Vector2(b.get_center().x,b.position.y)
   var mid = (p0.y+p1.y)*0.5
   tree_box.draw_polyline(PackedVector2Array([p0,Vector2(p0.x,mid),Vector2(p1.x,mid),p1]),Color(colors.trim,0.7),2.0)
  if m.get("spouse","") != "" and _nodes.has(m.spouse) and id<m.spouse:
   var a: Rect2 = _nodes[id]
   var b: Rect2 = _nodes[m.spouse]
   tree_box.draw_line(Vector2(a.end.x,a.get_center().y),Vector2(b.position.x,b.get_center().y),Color("c0392b",0.8),2.0)

func _build_others():
 _clear(others)
 var in_tree = _nodes.keys()
 var rest = view.members.filter(func(m): return not m.id in in_tree)
 if rest.is_empty():
  others.add_child(UiKit.label("Everyone in your court is family.",14,UiKit.TEXT_DIM))
  return
 var flow = HFlowContainer.new()
 flow.add_theme_constant_override("h_separation",6)
 flow.add_theme_constant_override("v_separation",6)
 flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 others.add_child(flow)
 for m in rest:
  var b = Button.new()
  b.name = "Char_"+m.id
  b.toggle_mode = true
  b.button_pressed = m.id == selected
  b.focus_mode = Control.FOCUS_NONE
  b.custom_minimum_size = Vector2(230,52)
  b.tooltip_text = "%s\n%s" % [m.full_name,m.role_text]
  var id = m.id
  b.pressed.connect(func():
   selected = id
   refresh())
  var h = HBoxContainer.new()
  h.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  h.add_theme_constant_override("separation",6)
  h.add_child(Portrait.new(m,46.0,Color(data.faction(data.player_faction_id()).primary)))
  var l = UiKit.label("%s\n%s" % [m.full_name,m.role_text],12)
  l.clip_text = true
  l.mouse_filter = Control.MOUSE_FILTER_IGNORE
  l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  h.add_child(l)
  b.add_child(h)
  flow.add_child(b)

# --- The selected character --------------------------------------------------------------------------

func _build_card():
 _clear(side)
 var m = _member(selected)
 if m.is_empty(): return
 var top = HBoxContainer.new()
 top.add_theme_constant_override("separation",10)
 top.add_child(Portrait.new(m,120.0,Color(data.faction(data.player_faction_id()).primary)))
 var tv = VBoxContainer.new()
 tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var nm = UiKit.header(m.full_name,20)
 nm.name = "SelectedName"
 nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 tv.add_child(nm)
 tv.add_child(UiKit.label(m.role_text,14,Color("f2cf6a")))
 tv.add_child(UiKit.label("%s · age %d%s" % [m.gender.replace("m","Man").replace("f","Woman"),m.age," · immortal" if m.immortal else ""],13,UiKit.TEXT_DIM))
 tv.add_child(UiKit.label("%s · level %d%s" % [m.career_name if m.career_name != "" else "No career yet",m.level," · %d skill points" % m.points if m.points>0 else ""],13,UiKit.TEXT))
 for t in m.titles: tv.add_child(UiKit.label(t,13,Color("e2c27a")))
 top.add_child(tv)
 side.add_child(top)
 # Loyalty: one bar, every change with its reason in the tooltip.
 var lr = HBoxContainer.new()
 lr.name = "Loyalty"
 lr.add_child(UiKit.label("Loyalty",14,UiKit.TEXT_DIM))
 var bar = ProgressBar.new()
 bar.show_percentage = false
 bar.max_value = 100
 bar.value = m.loyalty
 bar.custom_minimum_size = Vector2(200,14)
 bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 bar.modulate = Color("4fb34a") if m.loyalty>=60 else (Color("c9a43a") if m.loyalty>=30 else Color("c8382c"))
 lr.add_child(bar)
 lr.add_child(UiKit.label("%d" % m.loyalty,14,UiKit.TEXT))
 var reasons = ["Loyalty %d" % m.loyalty]
 for r in m.loyalty_reasons.slice(0,8): reasons.append("%+d  %s" % [int(r.delta),r.reason])
 if m.loyalty_reasons.is_empty(): reasons.append("No changes yet.")
 lr.tooltip_text = "\n".join(reasons)
 lr.mouse_filter = Control.MOUSE_FILTER_STOP
 side.add_child(lr)
 var why = UiKit.label("\n".join(reasons.slice(1,4)),12,UiKit.TEXT_DIM)
 why.name = "LoyaltyReasons"
 why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 side.add_child(why)
 side.add_child(UiKit.header("Traits",15))
 var tf = HFlowContainer.new()
 tf.add_theme_constant_override("h_separation",4)
 for t in m.traits:
  var tl = Button.new()
  tl.text = t.name
  tl.flat = false
  tl.focus_mode = Control.FOCUS_NONE
  tl.tooltip_text = "%s (%s)\nEarned from deeds, never chosen." % [t.name,t.kind]
  tf.add_child(tl)
 if m.traits.is_empty(): tf.add_child(UiKit.label("None yet: traits are earned from deeds.",12,UiKit.TEXT_DIM))
 side.add_child(tf)
 if m.epithet == "": side.add_child(UiKit.label("No epithet yet (earned from a pattern of deeds).",12,UiKit.TEXT_DIM))
 side.add_child(UiKit.divider(colors.trim))
 side.add_child(UiKit.header("Actions",15))
 var acts = HFlowContainer.new()
 acts.name = "CourtActions"
 acts.add_theme_constant_override("h_separation",6)
 acts.add_theme_constant_override("v_separation",6)
 side.add_child(acts)
 var add = func(id: String,text: String,tip: String,enabled: bool,fn: Callable):
  var b = Button.new()
  b.name = id
  b.text = text
  b.tooltip_text = tip
  b.disabled = not enabled
  b.focus_mode = Control.FOCUS_NONE
  b.pressed.connect(fn)
  acts.add_child(b)
 var adult = m.age>=16
 add.call("NameHeir","Name heir","The heir succeeds without crisis (you always choose).",not m.heir and not m.ruler and not m.dead,func():
  data.set_heir(m.id)
  refresh())
 add.call("MakeRuler","Make ruler","Replace the ruler at any time: the old ruler becomes a courtier or keeps their army.\nThe world watches a new ruler's first years closely.",not m.ruler and adult and not m.dead,func():
  data.make_ruler(m.id)
  refresh())
 add.call("Marry","Arrange marriage","Within your court at once, or across courts as an offer (cross-race allowed: children take the father's race).",adult and str(m.spouse) == "" and not m.dead,func(): _marriage_popup(m.id))
 add.call("Governor","Appoint governor","Any adult can govern a region.",adult and m.army == "" and not m.dead,func(): _governor_popup(m.id))
 if m.career_pending: add.call("Career","Choose a path","The formative years (12-16): choose the career.",true,func(): _career_popup(m.id))
 add.call("Gift","Gift 300 gold","A gift raises loyalty.",not m.dead,func():
  data.gift_character(m.id,300)
  refresh())
 add.call("Rename","Rename","Rename this character.",not m.dead,func(): _rename_popup(m.id))
 add.call("Details","Details","Skills, traits and history.",true,func(): details_requested.emit(m.id))
 side.add_child(UiKit.divider(colors.trim))
 side.add_child(UiKit.header("History",15))
 for h in m.history.slice(maxi(0,m.history.size()-6)):
  var l = UiKit.label("Year %d. %s" % [int(h.year),h.text],12,UiKit.TEXT)
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  side.add_child(l)

# --- Pop-ups --------------------------------------------------------------------------------------

func _popup(title: String) -> VBoxContainer:
 if popup and is_instance_valid(popup): popup.queue_free()
 var box = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.98))
 box.name = "CourtPopup"
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",6)
 box.add_child(v)
 var h = HBoxContainer.new()
 var t = UiKit.header(title,18)
 t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 h.add_child(t)
 var x = Button.new()
 x.text = "Cancel"
 x.focus_mode = Control.FOCUS_NONE
 x.pressed.connect(func(): box.queue_free())
 h.add_child(x)
 v.add_child(h)
 add_child(box)
 box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 box.grow_horizontal = Control.GROW_DIRECTION_BOTH
 box.grow_vertical = Control.GROW_DIRECTION_BOTH
 box.custom_minimum_size = Vector2(520,0)
 popup = box
 return v

func close_popup() -> bool:
 if popup and is_instance_valid(popup):
  popup.queue_free()
  popup = null
  return true
 return false

func _marriage_popup(id: String):
 var v = _popup("A match for %s" % _member(id).name)
 var cands = data.marriage_candidates(id)
 if cands.is_empty():
  v.add_child(UiKit.label("Nobody suitable in your court or the courts you know. Send envoys and embassies to meet more houses.",13,UiKit.TEXT_DIM))
  return
 var sc = ScrollContainer.new()
 sc.custom_minimum_size = Vector2(500,320)
 v.add_child(sc)
 var list = VBoxContainer.new()
 list.name = "MarriageCandidates"
 sc.add_child(list)
 for c in cands.slice(0,30):
  var b = Button.new()
  b.name = "Match_"+c.id
  b.text = "%s (%d) · %s%s" % [c.full_name,c.age,c.faction_name,"" if c.race == _member(id).race else " · %s" % c.race.capitalize()]
  b.alignment = HORIZONTAL_ALIGNMENT_LEFT
  b.focus_mode = Control.FOCUS_NONE
  var other = c.id
  b.pressed.connect(func():
   var r = data.arrange_marriage(id,other)
   popup.queue_free()
   if r.has("evaluation") and not r.get("accept",false): _notice("They decline: %s." % (r.evaluation.reasons[0].text if not r.evaluation.reasons.is_empty() else "no reason given"))
   elif r.get("sent",false): _notice(str(r.reason))
   refresh())
  list.add_child(b)

func _governor_popup(id: String):
 var v = _popup("Govern which region?")
 for sid in data.state.settlements_of(data.player_faction_id()):
  var b = Button.new()
  b.name = "Govern_"+sid
  b.text = data.settlement(sid).name
  b.focus_mode = Control.FOCUS_NONE
  b.pressed.connect(func():
   data.appoint_governor(id,sid)
   popup.queue_free()
   refresh())
  v.add_child(b)

func _career_popup(id: String):
 var v = _popup("The path of %s" % _member(id).name)
 for c in view.careers:
  var b = Button.new()
  b.name = "Career_"+c.id
  b.text = c.name
  b.tooltip_text = c.text
  b.focus_mode = Control.FOCUS_NONE
  var k = c.id
  b.pressed.connect(func():
   data.choose_career(id,k)
   popup.queue_free()
   refresh())
  v.add_child(b)

func _rename_popup(id: String):
 var v = _popup("Rename %s" % _member(id).name)
 var e = LineEdit.new()
 e.name = "RenameField"
 e.text = _member(id).name
 e.max_length = 32
 v.add_child(e)
 var ok = Button.new()
 ok.text = "Rename"
 ok.focus_mode = Control.FOCUS_NONE
 ok.pressed.connect(func():
  data.rename_character(id,e.text)
  popup.queue_free()
  refresh())
 v.add_child(ok)

func _notice(text: String):
 var v = _popup("Court")
 var l = UiKit.label(text,14,UiKit.TEXT)
 l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 v.add_child(l)
