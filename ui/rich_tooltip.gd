extends Control
# TW:WH3-style tooltips for every control (docs/tw-ui-parity.md H1): after a short hover, a framed
# panel pinned beside the hovered element, its first line as a bold title and the rest as body
# text. It reads each control's ordinary tooltip_text, so no control needs special code. Godot's
# own tooltips are turned off (project setting gui/timers/tooltip_delay_sec is set very high).
# Sticky, inspectable tooltips (TW:WH3 Update 3.0) are not built yet.

const UiKit = preload("res://ui/ui_kit.gd")
const DELAY = 0.45

var panel: PanelContainer
var title: Label
var body: Label
var hovered: Control
var text := ""
var timer := 0.0

func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 top_level = true
 z_index = 100
 panel = PanelContainer.new()
 panel.name = "RichTooltip"
 panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
 panel.add_theme_stylebox_override("panel",UiKit.textured(UiKit.PARCHMENT,12,10))
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",2)
 panel.add_child(v)
 title = UiKit.label("",17,UiKit.INK,UiKit.FONT_BOLD)
 v.add_child(title)
 body = UiKit.label("",15,UiKit.INK)
 v.add_child(body)
 panel.visible = false
 add_child(panel)

# Title and body of a tooltip text: the first line is the title.
static func split(t: String) -> Array:
 var lines = t.strip_edges().split("\n")
 return [lines[0],"\n".join(lines.slice(1))]

func _process(delta):
 var c = get_viewport().gui_get_hovered_control()
 var t = ""
 if c != null and c.is_visible_in_tree():
  t = c.get_tooltip(c.get_local_mouse_position())
 if c != hovered or t != text:
  hovered = c
  text = t
  timer = 0.0
  panel.visible = false
 if text == "": return
 timer += delta
 if timer<DELAY or panel.visible: return
 var parts = split(text)
 title.text = parts[0]
 body.text = parts[1]
 body.visible = parts[1] != ""
 panel.reset_size()
 panel.visible = true
 # Pinned to the element: below it when there is room, else above; kept on screen.
 var r = hovered.get_global_rect()
 var screen = get_viewport_rect().size
 var s = panel.get_combined_minimum_size()
 var p = Vector2(r.position.x,r.end.y+6)
 if p.y+s.y>screen.y-4: p.y = r.position.y-s.y-6
 p.x = clampf(p.x,4,screen.x-s.x-4)
 p.y = clampf(p.y,4,screen.y-s.y-4)
 panel.position = p
