extends SceneTree
# Validate a map's committed data and bakes (docs/map-pipeline-design.md §5.1; map/validator.gd).
#   runtime\Godot.exe --headless --path . -s scripts/validate_map.gd -- --map=<map_id>
# Prints every problem and a summary; exits 1 when there are errors.

const MapRegistry = preload("res://core/map_registry.gd")
const Validator = preload("res://map/validator.gd")

func _initialize():
 var map_id = ""
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--map="): map_id = a.get_slice("=",1)
 if map_id == "" or not map_id in MapRegistry.maps():
  printerr("Usage: -s scripts/validate_map.gd -- --map=<map_id>  (maps: %s)" % ", ".join(MapRegistry.maps()))
  quit(2)
  return
 MapRegistry.set_active(map_id)
 var v = Validator.validate(map_id)
 for p in v.problems: print("VALIDATE %s %s: %s%s" % [p.level,p.check,p.message,"" if p.pos == null else " at %s" % str(p.pos)])
 print("VALIDATE_SUMMARY %s errors=%d warnings=%d skipped=%s" % [map_id,v.errors,v.warnings,", ".join(v.skipped)])
 quit(1 if v.errors>0 else 0)
