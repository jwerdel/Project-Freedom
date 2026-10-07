extends Control
# The Realm (TW:WH3 full-screen panels; war-and-realm §2, §4, §5; game-design §11.6): tabs
#  - Vassals: each vassal's loyalty (every change with its reason), personal goal, economic goal
#    setting (Fortify / Military / Economy / Balanced), tribute, the 40% cap, gifts and orders;
#  - Titles: every title with its holder, conditions for you and powers; grant your grantable titles
#    to a vassal or a family member;
#  - Realm Standing: level, progress and the caps it sets;
#  - Banners and Hosts: your standing's muster terms, call the banners to a muster point, dismiss the
#    levies; your Hosts.
# Reads only through UiData.

signal closed

const UiKit = preload("res://ui/ui_kit.gd")
const Widgets = preload("res://ui/widgets.gd")

const TABS = [["vassals","Vassals"],["titles","Titles"],["standing","Realm Standing"],["banners","Banners and Hosts"]]

var data
var colors: Dictionary
var tab := "vassals"
var body: VBoxContainer
var tab_buttons := {}

func _init(ui_data,trim_colors: Dictionary,start_tab := "vassals"):
 data = ui_data
 colors = trim_colors
 tab = start_tab
 name = "RealmScreen"
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
 head.add_theme_constant_override("separation",8)
 var title = UiKit.header("The Realm",30)
 head.add_child(title)
 for t in TABS:
  var b = Button.new()
  b.name = "Tab_"+t[0]
  b.text = t[1]
  b.toggle_mode = true
  b.focus_mode = Control.FOCUS_NONE
  b.custom_minimum_size = Vector2(150,34)
  b.pressed.connect(set_tab.bind(t[0]))
  tab_buttons[t[0]] = b
  head.add_child(b)
 var gap = Control.new()
 gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 head.add_child(gap)
 var close = Button.new()
 close.name = "RealmClose"
 close.text = "Close (Esc)"
 close.focus_mode = Control.FOCUS_NONE
 close.custom_minimum_size = Vector2(130,34)
 close.pressed.connect(func(): closed.emit())
 head.add_child(close)
 v.add_child(head)
 v.add_child(UiKit.divider(colors.trim))
 var frame = Widgets.Framed.new("main",colors.trim,Color(colors.panel,0.9))
 frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
 v.add_child(frame)
 var sc = ScrollContainer.new()
 sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 frame.add_child(sc)
 body = VBoxContainer.new()
 body.name = "RealmBody"
 body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 body.add_theme_constant_override("separation",8)
 sc.add_child(body)
 set_tab(tab)

func set_tab(t: String):
 tab = t
 for k in tab_buttons: tab_buttons[k].set_pressed_no_signal(k == t)
 refresh()

func refresh():
 for c in body.get_children():
  body.remove_child(c)
  c.queue_free()
 match tab:
  "vassals": _vassals()
  "titles": _titles()
  "standing": _standing()
  "banners": _banners()

func _row(cells: Array,sizes: Array,color := UiKit.TEXT) -> HBoxContainer:
 var h = HBoxContainer.new()
 h.add_theme_constant_override("separation",10)
 for i in cells.size():
  var l = UiKit.label(str(cells[i]),14,color)
  l.custom_minimum_size.x = sizes[i]
  l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  h.add_child(l)
 return h

# --- Vassals -----------------------------------------------------------------------------------------

func _vassals():
 var list = data.vassals_view()
 body.add_child(UiKit.header("Your vassals",20))
 body.add_child(UiKit.label("Fealty, not absorption: a vassal keeps its family, lands, armies and banners. A well-treated vassal never rebels; no vassal may grow past 40% of your strength.",13,UiKit.TEXT_DIM))
 if list.is_empty():
  body.add_child(UiKit.label("No house is sworn to you yet. Offer vassalage in diplomacy, leave a conquered family in power, or protect a threatened neighbour.",14,UiKit.TEXT))
  return
 for vs in list:
  var f = Widgets.Framed.new("thin",colors.trim,Color(colors.panel,0.6))
  f.name = "Vassal_"+vs.faction
  body.add_child(f)
  var v = VBoxContainer.new()
  f.add_child(v)
  var h = HBoxContainer.new()
  h.add_theme_constant_override("separation",10)
  h.add_child(Widgets.Emblem.new(vs.faction_data,48))
  var info = VBoxContainer.new()
  info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  info.add_child(UiKit.header(vs.name,17))
  info.add_child(UiKit.label("%d settlements · %d armies · sworn since turn %d (%s)" % [vs.settlements,vs.armies,vs.since,vs.route],12,UiKit.TEXT_DIM))
  info.add_child(UiKit.label("Goal: %s %s" % [vs.name,vs.goal.get("text","")],13,Color("f2cf6a")))
  h.add_child(info)
  var lv = VBoxContainer.new()
  var lr = HBoxContainer.new()
  lr.name = "VassalLoyalty"
  lr.add_child(UiKit.label("Loyalty %d" % vs.loyalty,14,UiKit.TEXT,UiKit.FONT_BOLD))
  var bar = ProgressBar.new()
  bar.show_percentage = false
  bar.max_value = 100
  bar.value = vs.loyalty
  bar.custom_minimum_size = Vector2(180,14)
  bar.modulate = Color("4fb34a") if vs.loyalty>=60 else (Color("c9a43a") if vs.loyalty>=30 else Color("c8382c"))
  lr.add_child(bar)
  var why = ["Loyalty %d" % vs.loyalty]
  for r in vs.reasons.slice(0,8): why.append("%+d  %s" % [int(r.delta),r.reason])
  lr.tooltip_text = "\n".join(why)
  lr.mouse_filter = Control.MOUSE_FILTER_STOP
  lv.add_child(lr)
  if int(vs.warning)>=0: lv.add_child(UiKit.label("Wavering: %d turns of warning" % int(vs.warning),13,Color("ef6a5a"),UiKit.FONT_BOLD))
  lv.add_child(UiKit.label("Tribute %d a turn · reliability %d%% · %d%% of your strength (cap 40%%)" % [vs.tribute,int(vs.reliability*100),int(vs.cap.share*100)],12,UiKit.TEXT_DIM))
  for r in vs.reasons.slice(0,3): lv.add_child(UiKit.label("%+d  %s" % [int(r.delta),r.reason],12,Color("9fd27f") if int(r.delta)>=0 else Color("ef8a6a")))
  h.add_child(lv)
  v.add_child(h)
  var acts = HBoxContainer.new()
  acts.add_theme_constant_override("separation",6)
  acts.add_child(UiKit.label("Economic goal:",13,UiKit.TEXT_DIM))
  for g in [["fortify","Fortify"],["military","Military"],["economy","Economy"],["balanced","Balanced"]]:
   var b = Button.new()
   b.name = "Goal_%s_%s" % [vs.faction,g[0]]
   b.text = g[1]
   b.toggle_mode = true
   b.button_pressed = vs.econ_goal == g[0]
   b.focus_mode = Control.FOCUS_NONE
   var fid = vs.faction
   var gid = g[0]
   b.pressed.connect(func():
    data.set_vassal_goal(fid,gid)
    refresh())
   acts.add_child(b)
  var gift = Button.new()
  gift.text = "Gift 300 gold"
  gift.focus_mode = Control.FOCUS_NONE
  var fv = vs.faction
  gift.pressed.connect(func():
   data.gift_vassal(fv,300)
   refresh())
  acts.add_child(gift)
  var hint = UiKit.label("Orders: Diplomacy → select the vassal → Order…",12,UiKit.TEXT_DIM)
  acts.add_child(hint)
  v.add_child(acts)

# --- Titles ------------------------------------------------------------------------------------------

func _titles():
 body.add_child(UiKit.header("Titles",20))
 body.add_child(UiKit.label("Per people and region, collectible and dynamic: earned by a powerful realm that is Loved or Feared plus each title's conditions; they change hands by conquest.",13,UiKit.TEXT_DIM))
 var me = data.player_faction_id()
 for t in data.titles_panel():
  var f = Widgets.Framed.new("thin",colors.trim,Color(colors.panel,0.6))
  f.name = "Title_"+t.id
  body.add_child(f)
  var v = VBoxContainer.new()
  f.add_child(v)
  var h = HBoxContainer.new()
  var nm = UiKit.header(t.name,17)
  nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  h.add_child(nm)
  h.add_child(UiKit.label(("Held by %s" % t.holder_name) if t.holder != "" else "Unclaimed",14,Color("f2cf6a") if t.holder == me else UiKit.TEXT_DIM,UiKit.FONT_BOLD))
  v.add_child(h)
  v.add_child(UiKit.label(t.people,12,UiKit.TEXT_DIM))
  var conds = HFlowContainer.new()
  conds.add_theme_constant_override("h_separation",10)
  for c in t.conditions: conds.add_child(UiKit.label(("✔ " if c.met else "✘ ")+c.text,12,Color("9fd27f") if c.met else Color("ef8a6a")))
  v.add_child(conds)
  conds.call_deferred("update_minimum_size") # a flow container's height settles after the first layout
  for p in t.powers: v.add_child(UiKit.label("• "+p,12,UiKit.TEXT))
  var pad = Control.new()
  pad.custom_minimum_size.y = 6
  v.add_child(pad)
  if t.holder == me and t.grantable:
   var gr = HBoxContainer.new()
   gr.add_child(UiKit.label("Grant to:",13,UiKit.TEXT_DIM))
   for vs in data.vassals_view():
    var b = Button.new()
    b.text = vs.name
    b.focus_mode = Control.FOCUS_NONE
    var fid = vs.faction
    var tid = t.id
    b.pressed.connect(func():
     data.grant_title(tid,fid)
     refresh())
    gr.add_child(b)
   for m in data.court_view().members:
    if m.ruler or m.age<16 or m.dead: continue
    var b = Button.new()
    b.text = m.name
    b.tooltip_text = "Grant %s to %s (loyalty +15)" % [t.name,m.full_name]
    b.focus_mode = Control.FOCUS_NONE
    var cid = m.id
    var tid2 = t.id
    b.pressed.connect(func():
     data.grant_title(tid2,"",cid)
     refresh())
    gr.add_child(b)
    if gr.get_child_count()>8: break
   v.add_child(gr)

# --- Realm Standing ------------------------------------------------------------------------------------

func _standing():
 var s = data.realm_standing()
 body.add_child(UiKit.header("Realm Standing: %s (level %d)" % [s.name,s.level],20))
 body.add_child(UiKit.label("It rises with territory, population and wealth. Each level raises your caps; there are no growth penalties.",13,UiKit.TEXT_DIM))
 var bar = ProgressBar.new()
 bar.name = "StandingProgress"
 bar.show_percentage = false
 bar.max_value = 1.0
 bar.value = s.progress
 bar.custom_minimum_size = Vector2(500,18)
 bar.modulate = Color("d9b04a") # the theme's grey fill is invisible on its grey track
 body.add_child(bar)
 body.add_child(UiKit.label("Score %d%s · %d regions · %s people · %d gold a turn" % [int(s.score),(" of %d for the next level" % int(s.next)) if s.next>0 else " (the highest level)",s.regions,UiKit.format_int(s.population),s.income],14,UiKit.TEXT))
 body.add_child(UiKit.divider(colors.trim))
 body.add_child(_row(["Lord armies","%d" % s.caps.lord_armies,"The number of lord-led armies you may field (enforced)."],[200,80,600]))
 body.add_child(_row(["Agents per career","%d" % s.caps.agents,"Stored for the agents system (comes later)."],[200,80,600],UiKit.TEXT_DIM))
 body.add_child(_row(["Active decrees","%d" % s.caps.decrees,"Stored for decrees (come later)."],[200,80,600],UiKit.TEXT_DIM))
 var rep = data.reputation_view()
 body.add_child(UiKit.divider(colors.trim))
 body.add_child(UiKit.header("Your standing in the world: %s" % rep.standing.label,17))
 if rep.first_impressions: body.add_child(UiKit.label("A new ruler: the world is watching closely (reputation moves three times faster).",13,Color("f2cf6a")))
 for l in rep.labels: body.add_child(UiKit.label("%s (%+d): %s" % [l.name,int(l.value),"; ".join(l.deeds) if not l.deeds.is_empty() else "from the House's tendencies"],13,UiKit.TEXT))
 if rep.labels.is_empty(): body.add_child(UiKit.label("No marked reputation yet: your deeds will make one.",13,UiKit.TEXT_DIM))

# --- Banners and Hosts -------------------------------------------------------------------------------

func _banners():
 var t = data.banner_terms()
 body.add_child(UiKit.header("Call the Banners",20))
 body.add_child(UiKit.label("Levies are your regions' young men: production drops while they serve and returns when you send them home. Vassals march under their own lords. Mustering is seen by your neighbours.",13,UiKit.TEXT_DIM))
 body.add_child(UiKit.label("Your standing: %s · turnout %d%% · the levies set out in %d turn%s · field loyalty %s" % [t.label,int(float(t.turnout)*100),int(t.turns),"" if int(t.turns) == 1 else "s",t.loyalty],14,Color("f2cf6a")))
 body.add_child(UiKit.label("Ready to answer: %d levy units and %d vassal houses." % [int(t.levies),int(t.vassals)],14,UiKit.TEXT))
 if t.mustering:
  body.add_child(UiKit.label("The banners are called to %s." % data.settlement(t.muster.point).name,14,Color("9fd27f"),UiKit.FONT_BOLD))
  var d = Button.new()
  d.name = "DismissLevies"
  d.text = "Send the levies home"
  d.focus_mode = Control.FOCUS_NONE
  d.pressed.connect(func():
   data.dismiss_levies()
   refresh())
  body.add_child(d)
 else:
  body.add_child(UiKit.label("Muster at:",14,UiKit.TEXT_DIM))
  var flow = HFlowContainer.new()
  flow.name = "MusterPoints"
  flow.add_theme_constant_override("h_separation",6)
  for sid in data.state.settlements_of(data.player_faction_id()):
   var b = Button.new()
   b.name = "Muster_"+sid
   b.text = data.settlement(sid).name
   b.focus_mode = Control.FOCUS_NONE
   var s = sid
   b.pressed.connect(func():
    data.call_banners(s)
    refresh())
   flow.add_child(b)
  body.add_child(flow)
 body.add_child(UiKit.divider(colors.trim))
 body.add_child(UiKit.header("Your Hosts",17))
 body.add_child(UiKit.label("A Host groups armies under one commanding lord: they move together and fight as one battle. Form one from the army panel (select a lord, then Form Host).",13,UiKit.TEXT_DIM))
 var any = false
 for id in data.state.hosts:
  var h = data.state.hosts[id]
  if h.faction != data.player_faction_id() or not data.state.army_state.has(id): continue
  any = true
  body.add_child(UiKit.label("%s with %s" % [data.state.army_state[id].display_name,", ".join(h.members.filter(func(m): return data.state.army_state.has(m)).map(func(m): return data.state.army_state[m].display_name))],14,UiKit.TEXT))
 if not any: body.add_child(UiKit.label("None yet.",13,UiKit.TEXT_DIM))
