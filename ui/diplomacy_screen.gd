extends Control
# Diplomacy full screen (TW:WH3, docs/tw-ui-parity.md §15; docs/diplomacy-design.md §15): your faction
# on the left; every faction in the centre (met first; envoys reach anyone, war-and-realm §0.2) with
# its attitude face, relation, treaty locks and envoys in transit, the proposal builder (you offer /
# you demand, items grouped as in TW:WH3) with the live acceptance bar and their reasons with numbers,
# and the proposals waiting for your answer; the selected faction on the right (attitude causes,
# perceived reputation and standing, treaties, court visibility) with its dossier. Reads only
# through UiData.

signal closed
signal war_declared(faction_id: String)

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")
const Portrait = preload("res://ui/portrait.gd")

var data
var colors: Dictionary
var selected := ""
var view := {}
var left: VBoxContainer
var centre: VBoxContainer
var right: VBoxContainer
var confirm: Control
var offer := {"give":[],"take":[]}
var tab := "deal" # deal or dossier (right column)

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

const RELATION_NAMES = {"self":"You","vassal":"Your vassal","ally":"Ally","trade":"Trade partner","neutral":"Neutral","hostile":"Hostile","war":"At war"}
const RELATION_COLORS = {"self":Color("3f9be0"),"vassal":Color("8fc8f0"),"ally":Color("4fb34a"),"trade":Color("c9b84a"),"neutral":Color("a9a39a"),"hostile":Color("d9822b"),"war":Color("ef6a5a")}

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
 for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
 add_child(margin)
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",8)
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
 cols.add_theme_constant_override("separation",14)
 v.add_child(cols)
 left = _column(cols,300,"DiplomacyMe")
 centre = _column(cols,0,"DiplomacyCentre")
 centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 right = _column(cols,360,"DiplomacyThem")
 view = data.diplomacy()
 selected = focus if view.factions.any(func(f): return f.id == focus) else (view.factions[0].id if not view.factions.is_empty() else "")
 refresh()

func _column(parent: Control,w: float,node_name: String) -> VBoxContainer:
 var frame = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.9))
 frame.custom_minimum_size.x = w
 frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
 if w == 0: frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(frame)
 var sc = ScrollContainer.new()
 sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 frame.add_child(sc)
 var c = VBoxContainer.new()
 c.name = node_name
 c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 c.add_theme_constant_override("separation",6)
 sc.add_child(c)
 return c

func _clear(box: Node):
 for c in box.get_children():
  box.remove_child(c)
  c.queue_free()

func select(id: String):
 if id != selected: offer = {"give":[],"take":[]}
 selected = id
 refresh()

func _them() -> Dictionary:
 for f in view.factions:
  if f.id == selected: return f
 return {}

func refresh():
 view = data.diplomacy()
 _fill_side(left,view.me,true)
 _fill_centre()
 var them = _them()
 _clear(right)
 if them.is_empty(): right.add_child(UiKit.label("No faction selected.",15,UiKit.TEXT_DIM))
 elif tab == "dossier": _fill_dossier(right,them)
 else: _fill_side(right,them,false)
 _wrap_long(left)
 _wrap_long(right)

# Long one-line labels wrap inside their column instead of widening it past the screen edge.
func _wrap_long(box: Node):
 for n in box.find_children("*","Label",true,false):
  if n.autowrap_mode == TextServer.AUTOWRAP_OFF and not n.clip_text and n.text.length()>26 and n.get_parent() is VBoxContainer:
   n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   n.custom_minimum_size.x = 0

# --- A faction's column ---------------------------------------------------------------------------

func _fill_side(box: VBoxContainer,f: Dictionary,mine: bool):
 _clear(box)
 if not mine:
  var tabs = HBoxContainer.new()
  for t in [["deal","Faction"],["dossier","Dossier"]]:
   var b = Button.new()
   b.name = "Tab_"+t[0]
   b.text = t[1]
   b.toggle_mode = true
   b.button_pressed = tab == t[0]
   b.focus_mode = Control.FOCUS_NONE
   var k = t[0]
   b.pressed.connect(func():
    tab = k
    refresh())
   tabs.add_child(b)
  box.add_child(tabs)
 var em = CenterContainer.new()
 em.add_child(Widgets.Emblem.new(f.faction_data,96))
 box.add_child(em)
 var nm = UiKit.header(f.name,20)
 nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 box.add_child(nm)
 var sub = UiKit.label("%s · %s" % [f.realm,f.culture] if f.realm != "" else f.culture,13,UiKit.TEXT_DIM)
 sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(sub)
 # Standing (Loved / Feared / Neutral, war-and-realm §2.2).
 var st = UiKit.label("Standing: %s" % f.standing.label,15,Color("f2cf6a"),UiKit.FONT_BOLD)
 st.name = "Standing" if mine else "TheirStanding"
 st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 st.tooltip_text = "How the world sees the ruler (love %d, fear %d). Loved or Feared rulers call larger, faster, more loyal banners; Feared but weak, large but disloyal ones; Neutral, slow and small." % [int(f.standing.love),int(f.standing.fear)]
 st.mouse_filter = Control.MOUSE_FILTER_PASS
 box.add_child(st)
 if not mine:
  var att = HBoxContainer.new()
  att.name = "Attitude"
  att.alignment = BoxContainer.ALIGNMENT_CENTER
  att.add_child(Face.new(f.face,28))
  att.add_child(UiKit.label("Attitude: %s" % f.attitude_label,15,UiKit.TEXT,UiKit.FONT_BOLD))
  var lines = ["Attitude toward you: %s (%+d)" % [f.attitude_label,int(f.attitude)]]
  for r in f.attitude_reasons: lines.append("%+d  %s" % [int(r.value),r.text])
  att.tooltip_text = "\n".join(lines)
  att.mouse_filter = Control.MOUSE_FILTER_STOP
  box.add_child(att)
  for r in f.attitude_reasons.slice(0,3):
   var l = UiKit.label("%+d  %s" % [int(r.value),r.text],12,Color("9fd27f") if r.value>0 else Color("ef8a6a"))
   l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
   box.add_child(l)
  var rel = UiKit.label(RELATION_NAMES.get(f.relation,f.relation),15,RELATION_COLORS.get(f.relation,UiKit.TEXT),UiKit.FONT_BOLD)
  rel.name = "WarStatus"
  rel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  box.add_child(rel)
  if not f.contact: box.add_child(UiKit.label("Not met: send an envoy (they travel %s)." % "by map distance",12,UiKit.TEXT_DIM))
 box.add_child(UiKit.divider(colors.trim))
 box.add_child(UiKit.header("Reputation" if mine else "How they see themselves",14))
 if f.reputation.is_empty(): box.add_child(UiKit.label("No marked reputation yet.",12,UiKit.TEXT_DIM))
 var rf = HFlowContainer.new()
 rf.add_theme_constant_override("h_separation",4)
 for l in f.reputation:
  var b = Button.new()
  b.text = l.name
  b.focus_mode = Control.FOCUS_NONE
  b.tooltip_text = "%s (%+d)\n%s" % [l.name,int(l.value),"\n".join(l.deeds) if not l.deeds.is_empty() else "From their House's tendencies."]
  rf.add_child(b)
 box.add_child(rf)
 box.add_child(UiKit.header("Strength",14))
 for l in [["Settlements","%d" % f.settlements],["Armies","%d" % f.armies],["Soldiers",UiKit.format_int(f.men)]]:
  var r = HBoxContainer.new()
  var k = UiKit.label(l[0],13,UiKit.TEXT_DIM)
  k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  r.add_child(k)
  r.add_child(UiKit.label(l[1],13))
  box.add_child(r)
 box.add_child(UiKit.header("Tendencies",14))
 var tr = UiKit.label(", ".join(f.traits) if not f.traits.is_empty() else "None known",12,UiKit.TEXT)
 tr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 box.add_child(tr)
 box.add_child(UiKit.header("Wars",14))
 var wars = UiKit.label(", ".join(f.wars) if not f.wars.is_empty() else "At war with nobody",12,UiKit.TEXT)
 wars.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 box.add_child(wars)
 if not mine:
  box.add_child(UiKit.header("Treaties with you",14))
  var tl = VBoxContainer.new()
  tl.name = "Treaties"
  for t in f.treaties: tl.add_child(UiKit.label("%s%s" % [t.name," (protected %d more turns)" % int(t.left) if int(t.left)>0 else ""],12,UiKit.TEXT))
  if f.treaties.is_empty(): tl.add_child(UiKit.label("None",12,UiKit.TEXT_DIM))
  box.add_child(tl)
  box.add_child(UiKit.label({"full":"Their court is known to you.","basic":"Only their ruler is known: an embassy reveals their court.","unknown":"At war: their court is hidden (spies come later)."}[f.court],12,UiKit.TEXT_DIM))

func _fill_dossier(box: VBoxContainer,f: Dictionary):
 var d = data.dossier(f.id)
 _fill_side(box,f,false)
 box.add_child(UiKit.divider(colors.trim))
 box.add_child(UiKit.header("Dossier",16))
 if d.visibility == "unknown":
  box.add_child(UiKit.label("Unknown: their embassy is closed while you are at war. Embed a spy (later) to see their court.",12,UiKit.TEXT_DIM))
 else:
  for c in d.court_members:
   var h = HBoxContainer.new()
   h.add_theme_constant_override("separation",6)
   h.add_child(Portrait.new(c,44.0,Color(f.faction_data.primary)))
   var l = UiKit.label("%s\n%s" % [c.full_name,c.blurb],11,UiKit.TEXT)
   l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
   h.add_child(l)
   box.add_child(h)
  if d.visibility == "basic": box.add_child(UiKit.label("Send an embassy to learn the rest of their court.",12,UiKit.TEXT_DIM))
 box.add_child(UiKit.header("Who they hate",14))
 if d.hates.is_empty(): box.add_child(UiKit.label("Nobody in particular.",12,UiKit.TEXT_DIM))
 for h in d.hates: box.add_child(UiKit.label("%s (%d): %s" % [h.faction,int(h.value),h.why],12,UiKit.TEXT))
 box.add_child(UiKit.header("The Grey Scribes record",14))
 for l in d.history:
  var t = UiKit.label(l,12,UiKit.TEXT)
  t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  box.add_child(t)
 if d.history.is_empty(): box.add_child(UiKit.label("Nothing yet worth the ink.",12,UiKit.TEXT_DIM))

# --- Centre: factions, the deal, proposals ------------------------------------------------------------

func _fill_centre():
 _clear(centre)
 # Proposals waiting for your answer (AI offers and calls to arms).
 if not view.proposals.is_empty():
  centre.add_child(UiKit.header("Proposals for you",16))
  for p in view.proposals:
   var h = HBoxContainer.new()
   h.name = "Proposal_%d" % p.index
   var l = UiKit.label(p.text,13,UiKit.TEXT)
   l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
   h.add_child(l)
   var opts = [["Join","join"],["Support","support"],["Refuse","refuse"]] if p.call != "" else [["Accept","accept"],["Decline","decline"]]
   for o in opts:
    var b = Button.new()
    b.text = o[0]
    b.focus_mode = Control.FOCUS_NONE
    var idx = p.index
    var ans = o[1]
    b.pressed.connect(func():
     data.answer_proposal(idx,ans in ["accept","join"],ans if p.call != "" else "")
     refresh())
    h.add_child(b)
   centre.add_child(h)
  centre.add_child(UiKit.divider(colors.trim))
 centre.add_child(UiKit.header("Factions",16))
 var head = HBoxContainer.new()
 head.add_theme_constant_override("separation",8)
 for hcol in [["",30],["Faction",230],["Relation",110],["Attitude",110],["Treaties",150]]:
  var l = UiKit.label(hcol[0],12,UiKit.TEXT_DIM)
  l.custom_minimum_size.x = hcol[1]
  head.add_child(l)
 centre.add_child(head)
 var list = VBoxContainer.new()
 list.name = "DiplomacyFactions"
 list.add_theme_constant_override("separation",2)
 for f in view.factions:
  var b = Button.new()
  b.name = "Dip_"+f.id
  b.toggle_mode = true
  b.focus_mode = Control.FOCUS_NONE
  b.button_pressed = f.id == selected
  b.custom_minimum_size.y = 34
  b.tooltip_text = "%s\n%s · %d settlements, %d armies%s" % [f.name,RELATION_NAMES.get(f.relation,""),f.settlements,f.armies,"" if f.contact else "\nNot met: an envoy reaches them"]
  b.pressed.connect(select.bind(f.id))
  var h = HBoxContainer.new()
  h.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  h.offset_left = 4
  h.add_theme_constant_override("separation",8)
  var em = Widgets.Emblem.new(f.faction_data,26)
  em.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.add_child(em)
  var treaties = ", ".join(f.treaties.map(func(t): return t.name+(" 🔒%d" % int(t.left) if int(t.left)>0 else "")))
  if not f.envoy.is_empty(): treaties = ("Envoy: %d turns" % int(f.envoy[0].arrive))+(", "+treaties if treaties != "" else "")
  for c in [[f.name,230,UiKit.TEXT if f.contact else UiKit.TEXT_DIM],[RELATION_NAMES.get(f.relation,""),110,RELATION_COLORS.get(f.relation,UiKit.TEXT)]]:
   var l = UiKit.label(c[0],13,c[2])
   l.custom_minimum_size.x = c[1]
   l.clip_text = true
   l.mouse_filter = Control.MOUSE_FILTER_IGNORE
   h.add_child(l)
  var face = HBoxContainer.new()
  face.custom_minimum_size.x = 110
  face.mouse_filter = Control.MOUSE_FILTER_IGNORE
  var fc = Face.new(f.face,20)
  fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
  face.add_child(fc)
  var al = UiKit.label(f.attitude_label,12,UiKit.TEXT_DIM)
  al.mouse_filter = Control.MOUSE_FILTER_IGNORE
  face.add_child(al)
  h.add_child(face)
  var tl = UiKit.label(treaties,12,UiKit.TEXT_DIM)
  tl.custom_minimum_size.x = 150
  tl.clip_text = true
  tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
  h.add_child(tl)
  b.add_child(h)
  list.add_child(b)
 var scroll = ScrollContainer.new()
 scroll.custom_minimum_size.y = 230
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.add_child(list)
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 centre.add_child(scroll)
 if not view.envoys.is_empty():
  centre.add_child(UiKit.label("Envoys on the road: "+", ".join(view.envoys.map(func(e): return "%s (%s, %d turns)" % [e.name,e.kind,int(e.turns)])),12,UiKit.TEXT_DIM))
 centre.add_child(UiKit.divider(colors.trim))
 _fill_deal()

func _fill_deal():
 var them = _them()
 if them.is_empty(): return
 centre.add_child(UiKit.header("Negotiate with %s" % them.name,16))
 var cols = HBoxContainer.new()
 cols.add_theme_constant_override("separation",10)
 centre.add_child(cols)
 var palette = data.offer_palette(them.id)
 for side in [["give","You offer"],["take","You demand"]]:
  var col = VBoxContainer.new()
  col.name = "Deal_"+side[0]
  col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  col.add_child(UiKit.header(side[1],14))
  for it in offer[side[0]]:
   var row = HBoxContainer.new()
   var l = UiKit.label(_item_label(palette,it),13,UiKit.TEXT)
   l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
   l.clip_text = true
   row.add_child(l)
   var x = Button.new()
   x.text = "×"
   x.focus_mode = Control.FOCUS_NONE
   var s = side[0]
   var item = it
   x.pressed.connect(func():
    offer[s].erase(item)
    refresh())
   row.add_child(x)
   col.add_child(row)
  # The item palette (TW:WH3 groups): an option button per group.
  var add = OptionButton.new()
  add.name = "Add_"+side[0]
  add.focus_mode = Control.FOCUS_NONE
  # Sized by the column, not by the longest item (long reasons would push the right column off-screen).
  add.fit_to_longest_item = false
  add.clip_text = true
  add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  add.add_item("Add an item…")
  var entries = []
  var group = ""
  for p in palette:
   if p.group != group:
    group = p.group
    add.add_separator(group)
    entries.append(null)
   var e = p[side[0]]
   add.add_item(p.name+("" if e.ok else " — "+str(e.reason)))
   add.set_item_disabled(add.item_count-1,not e.ok)
   entries.append(p)
  var s2 = side[0]
  add.item_selected.connect(func(i):
   var p = entries[i-1] if i>0 and i-1<entries.size() else null
   if p != null and not offer[s2].has(p.item): offer[s2].append(p.item)
   refresh())
  col.add_child(add)
  cols.add_child(col)
 # The live acceptance bar and their reasons with numbers.
 var empty = offer.give.is_empty() and offer.take.is_empty()
 var ev = data.evaluate_offer(them.id,offer) if not empty else {"score":0.0,"chance":"No proposal","reasons":[],"accept":false,"blocked":true}
 var acc = HBoxContainer.new()
 acc.name = "Acceptance"
 acc.add_theme_constant_override("separation",8)
 acc.add_child(UiKit.label("Acceptance",14,UiKit.TEXT_DIM))
 var bar = ProgressBar.new()
 bar.show_percentage = false
 bar.custom_minimum_size = Vector2(240,14)
 bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 bar.min_value = -1000
 bar.max_value = 1000
 bar.value = clampf(float(ev.score),-1000.0,1000.0)
 bar.modulate = Color("4fb34a") if ev.accept else Color("c8382c")
 acc.add_child(bar)
 var ch = UiKit.label(str(ev.chance),14,Color("9fd27f") if ev.accept else Color("ef8a6a"),UiKit.FONT_BOLD)
 ch.name = "AcceptanceLabel"
 acc.add_child(ch)
 centre.add_child(acc)
 var reasons = VBoxContainer.new()
 reasons.name = "Reasons"
 for r in ev.reasons.slice(0,6): reasons.add_child(UiKit.label("%+d  %s" % [int(round(float(r.value))),r.text],12,Color("9fd27f") if float(r.value)>=0.0 else Color("ef8a6a")))
 centre.add_child(reasons)
 var actions = HFlowContainer.new()
 actions.name = "DealActions"
 actions.add_theme_constant_override("h_separation",8)
 actions.add_theme_constant_override("v_separation",6)
 centre.add_child(actions)
 var button = func(id: String,text: String,tip: String,enabled: bool,fn: Callable):
  var b = Button.new()
  b.name = id
  b.text = text
  b.tooltip_text = tip
  b.disabled = not enabled
  b.focus_mode = Control.FOCUS_NONE
  b.custom_minimum_size = Vector2(150,34)
  b.pressed.connect(fn)
  actions.add_child(b)
 button.call("Propose","Propose","Send the proposal (an envoy carries it if you have not met).",not empty and not bool(ev.get("blocked",false)),func():
  var r = data.propose_offer(them.id,offer)
  if r.get("accept",false): offer = {"give":[],"take":[]}
  _toast("They accept." if r.get("accept",false) else str(r.get("reason","They decline.")) if r.get("sent",false) else "They decline.")
  refresh())
 button.call("SendEnvoy","Send envoy","Envoys reach anyone; contact happens on arrival.",not them.contact and them.envoy.is_empty(),func():
  var r = data.send_envoy(them.id,"contact")
  _toast("The envoy sets out (%d turns)." % int(r.get("turns",0)) if r.ok else str(r.reason))
  refresh())
 button.call("Embassy","Send embassy","An embassy reveals their court. Any faction with no reason to refuse accepts.",them.court != "full" and them.relation != "war" and them.envoy.is_empty(),func():
  var r = data.send_envoy(them.id,"embassy")
  _toast("The embassy sets out (%d turns)." % int(r.get("turns",0)) if r.ok else str(r.reason))
  refresh())
 button.call("DeclareWarDip","Declare war","Declare war on %s." % them.name,them.relation != "war" and not them.untouchable,_ask_war)
 if them.relation in ["ally","vassal"]:
  button.call("OrderAlly","Order…","Give them an order: attack, besiege or defend (from the map: right-click a target with their army selected comes later).",true,func(): _order_popup(them))

func _item_label(palette: Array,it: Dictionary) -> String:
 for p in palette:
  if p.item == it: return p.name
 if str(it.kind) == "gold": return "%s gold" % UiKit.format_int(int(it.get("amount",0)))
 if str(it.kind) == "tribute": return "%s gold a turn for %d turns" % [UiKit.format_int(int(it.get("amount",0))),int(it.get("turns",0))]
 return str(it.kind)

func _toast(text: String):
 var l = UiKit.label(text,14,Color("f2cf6a"),UiKit.FONT_BOLD)
 l.name = "DiplomacyToast"
 centre.add_child(l)

# Orders to an ally or vassal: pick a target among the enemy settlements nearest you.
func _order_popup(them: Dictionary):
 var box = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.98))
 box.name = "OrderPopup"
 var v = VBoxContainer.new()
 box.add_child(v)
 v.add_child(UiKit.header("Order %s" % them.name,18))
 var me = data.player_faction_id()
 var n = 0
 for sid in data.settlement_ids():
  var s = data.state.settlements[sid]
  if not data.at_war(s.owner) or n>=8: continue
  n += 1
  var b = Button.new()
  b.text = "Attack %s (%s)" % [data.settlement(sid).name,data.faction(s.owner).name]
  b.focus_mode = Control.FOCUS_NONE
  var t = sid
  b.pressed.connect(func():
   var r = data.order_ally(them.id,"attack",t)
   box.queue_free()
   _toast("They march with a real force." if r.get("accept",false) else str(r.get("reason","They refuse.")))
   refresh())
  v.add_child(b)
 for sid in data.state.settlements_of(me).slice(0,4):
  var b = Button.new()
  b.text = "Defend %s" % data.settlement(sid).name
  b.focus_mode = Control.FOCUS_NONE
  var t = sid
  b.pressed.connect(func():
   var r = data.order_ally(them.id,"defend",t)
   box.queue_free()
   _toast("They send an army." if r.get("accept",false) else str(r.get("reason","They refuse.")))
   refresh())
  v.add_child(b)
 var x = Button.new()
 x.text = "Cancel"
 x.focus_mode = Control.FOCUS_NONE
 x.pressed.connect(func(): box.queue_free())
 v.add_child(x)
 add_child(box)
 box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 box.grow_horizontal = Control.GROW_DIRECTION_BOTH
 box.grow_vertical = Control.GROW_DIRECTION_BOTH
 confirm = box

# Declaring war asks first: the justification (or its reputation cost), the treaties it would break
# (betrayal), who would be angered and which allies would join (diplomacy-design §7).
func _ask_war():
 var them = _them()
 if them.is_empty() or them.relation == "war": return
 var pv = data.declaration_preview(them.id)
 var box = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.98))
 box.name = "WarConfirm"
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",8)
 box.add_child(v)
 var t = UiKit.header("Declare war on %s?" % them.name,20)
 t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 v.add_child(t)
 var lines = []
 if pv.betrayal != "": lines.append("BETRAYAL: you have %s with them. Breaking it means war with every faction, the loss of every ally and trade partner, and a permanent mark on your name. Only loading a save undoes it." % pv.betrayal)
 elif pv.justified: lines.append("Justified: "+", ".join(pv.justifications.map(func(j): return j.text))+".")
 else: lines.append("No justification: your reputation suffers (Expansionist, Dishonorable), and their allies see an unprovoked war.")
 if not pv.ally_names.is_empty(): lines.append("Their allies may join: "+", ".join(pv.ally_names)+".")
 if not pv.angered_names.is_empty(): lines.append("It angers: "+", ".join(pv.angered_names)+".")
 var txt = UiKit.label("\n".join(lines),14,Color("ef8a6a") if pv.betrayal != "" else UiKit.TEXT)
 txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 txt.custom_minimum_size.x = 460
 v.add_child(txt)
 var row = HBoxContainer.new()
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 row.add_theme_constant_override("separation",16)
 var yes = Button.new()
 yes.name = "WarYes"
 yes.text = "Betray them" if pv.betrayal != "" else "Declare war"
 yes.focus_mode = Control.FOCUS_NONE
 yes.pressed.connect(func():
  data.declare_war(them.id,pv.betrayal != "")
  war_declared.emit(them.id)
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
