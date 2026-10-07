extends RefCounted
# Campaign UI look, modeled on Total War: Warhammer III: dark panels with ornate metal frames,
# parchment tooltips, Cinzel headers and Fira Sans body text (2026-10-07: Alegreya Sans read poorly
# at small sizes; Fira Sans has a large x-height and open shapes built for screens). Built from the Kenney Fantasy
# UI Borders (9-slice, tinted) and UI Pack RPG Expansion, tinted per faction.

const FONT_HEAD = preload("res://assets/fonts/Cinzel-Variable.ttf")
# Body text: Fira Sans Regular, and SemiBold for emphasis and buttons (bolder weights clog at small
# sizes). Labels are never smaller than MIN_TEXT (owner 2026-10-07: text was hard to read).
const FONT_BODY = preload("res://assets/fonts/FiraSans-Regular.ttf")
const FONT_BOLD = preload("res://assets/fonts/FiraSans-SemiBold.ttf")
const MIN_TEXT = 14
const SMALL_TEXT = 14 # at or below this size, labels get one more pixel per space
const FRAMES = {
 "main": preload("res://assets/kenney/fantasy-ui-borders/panel-border-010.png"),
 "card": preload("res://assets/kenney/fantasy-ui-borders/panel-border-001.png"),
 "thin": preload("res://assets/kenney/fantasy-ui-borders/panel-border-015.png"),
}
const DIVIDER = preload("res://assets/kenney/fantasy-ui-borders/divider-fade-000.png")
const BUTTON_ROUND = preload("res://assets/kenney/rpg-expansion/buttonRound_brown.png")
const BUTTON_ROUND_LIGHT = preload("res://assets/kenney/rpg-expansion/buttonRound_beige.png")
const BUTTON_LONG = preload("res://assets/kenney/rpg-expansion/buttonLong_brown.png")
const BUTTON_LONG_PRESSED = preload("res://assets/kenney/rpg-expansion/buttonLong_brown_pressed.png")
const BUTTON_LONG_SELECTED = preload("res://assets/kenney/rpg-expansion/buttonLong_beige.png")
const PARCHMENT = preload("res://assets/kenney/rpg-expansion/panel_beige.png")
const SLOT = preload("res://assets/kenney/rpg-expansion/panelInset_brown.png")
const LOCK = preload("res://assets/kenney/rpg-expansion/iconCross_grey.png")
const BAR = {
 "back": [preload("res://assets/kenney/rpg-expansion/barBack_horizontalLeft.png"),preload("res://assets/kenney/rpg-expansion/barBack_horizontalMid.png"),preload("res://assets/kenney/rpg-expansion/barBack_horizontalRight.png")],
 "good": [preload("res://assets/kenney/rpg-expansion/barGreen_horizontalLeft.png"),preload("res://assets/kenney/rpg-expansion/barGreen_horizontalMid.png"),preload("res://assets/kenney/rpg-expansion/barGreen_horizontalRight.png")],
 "bad": [preload("res://assets/kenney/rpg-expansion/barRed_horizontalLeft.png"),preload("res://assets/kenney/rpg-expansion/barRed_horizontalMid.png"),preload("res://assets/kenney/rpg-expansion/barRed_horizontalRight.png")],
}
const INK = Color("2a1c10")
const TEXT = Color("eadfc4")
const TEXT_DIM = Color("cbbd9d") # brighter than before (2026-10-07): dim text must still read on the dark panels
const PANEL_BG = Color("16110d")

static var _head_bold: FontVariation
static var _small := {} # base font -> its small-text variation

static func head_font() -> Font:
 if _head_bold == null:
  _head_bold = FontVariation.new()
  _head_bold.base_font = FONT_HEAD
  _head_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):700}
 return _head_bold

# A body font with wider spaces for small text (see FONT_BODY).
static func small_font(base: Font) -> Font:
 if not _small.has(base):
  # Nested variations do not add up (the outer spacing replaces the inner), so start from the file.
  var v = FontVariation.new()
  v.base_font = base.base_font if base is FontVariation else base
  v.spacing_space = (base.spacing_space if base is FontVariation else 0)+1
  _small[base] = v
 return _small[base]

static func colors(faction: Dictionary) -> Dictionary:
 var primary = Color(faction.get("primary","#5a4a3a"))
 var secondary = Color(faction.get("secondary","#c8a050"))
 return {"primary":primary,"secondary":secondary,"panel":PANEL_BG.lerp(primary,0.16),"trim":secondary.lerp(Color("c9a45a"),0.35)}

static func frame_box(kind: String,tint: Color) -> StyleBoxTexture:
 var s = StyleBoxTexture.new()
 s.texture = FRAMES[kind]
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: s.set_texture_margin(side,16)
 s.draw_center = false
 s.modulate_color = tint
 return s

static func flat(color: Color,margin := 12) -> StyleBoxFlat:
 var s = StyleBoxFlat.new()
 s.bg_color = color
 s.set_content_margin_all(margin)
 return s

static func textured(tex: Texture2D,margin: int,content := 10,tint := Color.WHITE) -> StyleBoxTexture:
 var s = StyleBoxTexture.new()
 s.texture = tex
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: s.set_texture_margin(side,margin)
 s.set_content_margin_all(content)
 s.modulate_color = tint
 return s

# The campaign UI theme for a faction (panels tinted toward its primary color, trim in its metal).
static func theme_for(faction: Dictionary) -> Theme:
 var c = colors(faction)
 var t = Theme.new()
 t.default_font = FONT_BODY
 t.default_font_size = 16
 t.set_color("font_color","Label",TEXT)
 var panel = flat(Color(c.panel,0.94),14)
 t.set_stylebox("panel","PanelContainer",panel)
 t.set_stylebox("panel","Panel",panel)
 for state in ["normal","hover","pressed","disabled","focus"]:
  var tex = BUTTON_LONG_PRESSED if state=="pressed" else BUTTON_LONG
  var tint = Color(1.15,1.08,0.95) if state=="hover" else (Color(0.6,0.6,0.6) if state=="disabled" else Color.WHITE)
  t.set_stylebox(state,"Button",textured(tex,10,8,tint) if state!="focus" else StyleBoxEmpty.new())
 t.set_color("font_color","Button",TEXT)
 t.set_color("font_hover_color","Button",Color("fff3d6"))
 t.set_color("font_pressed_color","Button",Color("f3d58c"))
 t.set_font("font","Button",FONT_BOLD)
 t.set_font_size("font_size","Button",16)
 t.set_stylebox("panel","TooltipPanel",textured(PARCHMENT,12,12))
 t.set_color("font_color","TooltipLabel",INK)
 t.set_font("font","TooltipLabel",FONT_BODY)
 t.set_font_size("font_size","TooltipLabel",16)
 return t

static func label(text: String,size := 16,color := TEXT,font: Font = null) -> Label:
 var l = Label.new()
 l.text = text
 size = maxi(size,MIN_TEXT)
 l.add_theme_font_size_override("font_size",size)
 l.add_theme_color_override("font_color",color)
 if size<=SMALL_TEXT and (font == null or font == FONT_BODY or font == FONT_BOLD): font = small_font(font if font else FONT_BODY)
 if font: l.add_theme_font_override("font",font)
 l.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return l

static func header(text: String,size := 18,color := Color("f1d79a")) -> Label:
 var l = label(text,size,color,head_font())
 l.add_theme_color_override("font_shadow_color",Color(0,0,0,0.7))
 l.add_theme_constant_override("shadow_offset_y",2)
 return l

static func divider(tint: Color) -> TextureRect:
 var d = TextureRect.new()
 d.texture = DIVIDER
 d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 d.stretch_mode = TextureRect.STRETCH_SCALE
 d.custom_minimum_size = Vector2(0,10)
 d.modulate = tint
 d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 d.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return d

static func format_int(n: int) -> String:
 var s = str(absi(n))
 var out = ""
 while s.length()>3:
  out = ","+s.substr(s.length()-3)+out
  s = s.substr(0,s.length()-3)
 return ("-" if n<0 else "")+s+out

static func signed(n: int) -> String:
 return ("+" if n>=0 else "")+format_int(n)
