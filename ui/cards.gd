extends RefCounted
# Unit cards and building slot cards for the campaign UI. Card art comes from the portrait
# studio (rendered from the unit's or building's visual scene), never from hand-made images.

const UiKit = preload("res://ui/ui_kit.gd")
const Icons = preload("res://ui/icons.gd")

const UNIT_CARD = Vector2(80,150)
const BUILDING_CARD = Vector2(112,132)

class UnitCard extends Control:
 var unit_id := ""
 var faction := {}
 var strength := 1.0
 var is_lord := false
 var portrait: TextureRect
 var studio
 func _init(unit_type: Dictionary,entry: Dictionary,faction_data: Dictionary,portraits,tip: String):
  unit_id = unit_type.id
  faction = faction_data
  strength = float(entry.get("strength",1.0))
  is_lord = unit_type.get("single_entity",false)
  studio = portraits
  custom_minimum_size = UNIT_CARD*(Vector2(1.12,1.12) if is_lord else Vector2.ONE)
  tooltip_text = tip
  mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
  texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  portrait = TextureRect.new()
  portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
  portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
  portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
  portrait.clip_contents = true
  add_child(portrait)
  mouse_entered.connect(queue_redraw)
  mouse_exited.connect(queue_redraw)
  resized.connect(_layout)
 func _ready():
  var tex = studio.portrait(unit_id)
  if tex: portrait.texture = tex
  else: studio.portrait_ready.connect(_on_portrait)
  _layout()
 func _on_portrait(key: String,tex: Texture2D):
  if key == "unit:"+unit_id:
   portrait.texture = tex
   studio.portrait_ready.disconnect(_on_portrait)
 func _layout():
  portrait.position = Vector2(3,3)
  portrait.size = size-Vector2(6,16)
 func _draw():
  var c = UiKit.colors(faction)
  var top = c.primary.lightened(0.22 if is_hovered() else 0.1)
  var bottom = c.primary.darkened(0.6)
  var r = Rect2(Vector2.ZERO,size)
  draw_polygon(PackedVector2Array([r.position,Vector2(r.end.x,0),r.end,Vector2(0,r.end.y)]),PackedColorArray([top,top,bottom,bottom]))
  # Strength bar along the bottom.
  draw_rect(Rect2(4,size.y-11,size.x-8,6),Color(0,0,0,0.7))
  draw_rect(Rect2(4,size.y-11,(size.x-8)*clampf(strength,0,1),6),Color("e9dcb4") if strength>0.5 else Color("d77a4a"))
 func is_hovered() -> bool:
  return get_global_rect().has_point(get_global_mouse_position())

# Frame overlay for a card (drawn above the portrait child).
class CardFrame extends Control:
 var trim := Color.WHITE
 func _init(t: Color):
  trim = t
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 func _draw():
  draw_style_box(UiKit.frame_box("card",trim),Rect2(Vector2.ZERO,size))

static func unit_card(unit_type: Dictionary,entry: Dictionary,faction: Dictionary,studio,tip: String) -> Control:
 var card = UnitCard.new(unit_type,entry,faction,studio,tip)
 var trim = Color("f2cf6a") if card.is_lord else UiKit.colors(faction).trim.darkened(0.15)
 card.add_child(CardFrame.new(trim))
 return card

class BuildingCard extends Control:
 var slot := {}
 var trim := Color.WHITE
 var thumb: TextureRect
 var studio
 func _init(slot_data: Dictionary,trim_color: Color,thumbnails):
  slot = slot_data
  trim = trim_color
  studio = thumbnails
  custom_minimum_size = BUILDING_CARD
  texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  if slot.get("locked",false): tooltip_text = "Locked slot\nRequires: %s" % slot.get("requires","?")
  elif slot.get("empty",false): tooltip_text = "Empty building slot\n(Construction is not implemented yet.)"
  else: tooltip_text = "%s\nLevel %d" % [slot.name,int(slot.level)]
  if slot.has("visual"):
   thumb = TextureRect.new()
   thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
   thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
   thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
   thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
   thumb.position = Vector2(5,5)
   thumb.size = Vector2(BUILDING_CARD.x-10,82)
   add_child(thumb)
   var name_label = UiKit.label(slot.name,12,UiKit.TEXT,UiKit.FONT_BOLD)
   name_label.position = Vector2(6,86)
   name_label.custom_minimum_size = Vector2(BUILDING_CARD.x-12,30)
   name_label.size = name_label.custom_minimum_size
   name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
   name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
   name_label.add_theme_constant_override("line_spacing",-4)
   add_child(name_label)
 func _ready():
  if thumb:
   var tex = studio.thumbnail(slot.visual)
   if tex: thumb.texture = tex
   else: studio.portrait_ready.connect(_on_thumb)
 func _on_thumb(key: String,tex: Texture2D):
  if key == "visual:"+slot.visual:
   thumb.texture = tex
   studio.portrait_ready.disconnect(_on_thumb)
 func _draw():
  var r = Rect2(Vector2.ZERO,size)
  draw_style_box(UiKit.textured(UiKit.SLOT,10,0,Color(0.55,0.5,0.45) if slot.has("visual") else Color(0.35,0.32,0.3)),r)
  if slot.get("locked",false):
   draw_texture_rect(UiKit.LOCK,Rect2(size*0.5-Vector2(18,24),Vector2(36,34)),false,Color(1,1,1,0.8))
   _caption("Locked")
  elif slot.get("empty",false):
   Icons.draw(self,"plus",Rect2(size*0.5-Vector2(18,26),Vector2(36,36)),Color("d8c28c"))
   _caption("Empty slot")
  else:
   for i in 4:
    var col = Color("f2cf6a") if i<int(slot.level) else Color(0,0,0,0.45)
    draw_circle(Vector2(size.x*0.5+(i-1.5)*12,size.y-9),3.6,col)
 func _caption(text: String):
  var f = UiKit.FONT_BOLD
  var w = f.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
  draw_string(f,Vector2((size.x-w)*0.5,size.y-18),text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,UiKit.TEXT_DIM)

static func building_card(slot: Dictionary,trim: Color,studio) -> Control:
 var card = BuildingCard.new(slot,trim,studio)
 card.add_child(CardFrame.new(trim))
 return card
