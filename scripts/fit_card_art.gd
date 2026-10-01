extends SceneTree
# Crops and downscales every image in assets/cards/ to unit-card size, so hand-made card art
# (optional; see UnitTypes.card_art) matches the cards the UI draws. Center crop to the card's
# aspect, Lanczos downscale, saved as assets/cards/<unit_id>.png (other formats are converted and
# the original removed). Files whose name is not a unit type ID are reported and left alone.
# Run: runtime\Godot.exe --headless --path . -s scripts/fit_card_art.gd
# then a headless import so Godot picks up the new files.

const UnitTypes = preload("res://core/unit_types.gd")
const DIR = "res://assets/cards/"
const SIZE = Vector2i(192,360) # 2.4x the 80x150 unit card, same aspect; enough for the larger lord card
const EXTS = ["png","jpg","jpeg","webp"]

func _initialize():
 var ids = UnitTypes.ids()
 var done = 0
 for file in DirAccess.get_files_at(DIR):
  var ext = file.get_extension().to_lower()
  if not ext in EXTS: continue
  var id = file.get_basename()
  if not id in ids:
   push_warning("assets/cards/%s: '%s' is not a unit type ID (%s); skipped" % [file,id,", ".join(ids)])
   continue
  var src = ProjectSettings.globalize_path(DIR+file)
  var img = Image.load_from_file(src)
  if img == null or img.is_empty():
   push_error("assets/cards/%s: could not read" % file)
   continue
  if ext == "png" and img.get_size() == SIZE: continue
  img = fit(img)
  img.save_png(ProjectSettings.globalize_path(DIR+id+".png"))
  if ext != "png": DirAccess.remove_absolute(src)
  print("card art: %s -> %s.png %s" % [file,id,SIZE])
  done += 1
 print("card art: %d file(s) fitted" % done)
 quit()

static func fit(img: Image) -> Image:
 img.convert(Image.FORMAT_RGBA8)
 var aspect = float(SIZE.x)/SIZE.y
 var w = img.get_width()
 var h = img.get_height()
 var crop = Rect2i(0,0,w,h)
 if float(w)/h>aspect: crop = Rect2i(int((w-h*aspect)*0.5),0,int(h*aspect),h)
 else: crop = Rect2i(0,int((h-w/aspect)*0.5),w,int(w/aspect))
 var out = img.get_region(crop)
 out.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_LANCZOS)
 return out
