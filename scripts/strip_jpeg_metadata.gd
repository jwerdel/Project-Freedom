extends SceneTree
# Strips metadata from JPEG files in place, losslessly (CLAUDE.md: strip metadata from images before
# committing them): drops the APP1 (Exif, XMP), APP13 (Photoshop IPTC) and COM segments and keeps
# everything needed to decode (JFIF, ICC, Adobe colour transform, tables, scan data).
#   runtime\Godot.exe --headless --path . -s scripts/strip_jpeg_metadata.gd -- <folder> [<folder> ...]

const DROP = [0xE1,0xED,0xFE]

func _initialize():
 var stripped = 0
 var files = 0
 for dir in OS.get_cmdline_user_args():
  for path in _jpegs(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir):
   files += 1
   if _strip(path): stripped += 1
 print("STRIP %d of %d JPEG files had metadata removed" % [stripped,files])
 quit(0)

func _jpegs(dir: String) -> Array:
 var out = []
 var d = DirAccess.open(dir)
 if d == null: return out
 for f in d.get_files():
  if f.to_lower().ends_with(".jpg") or f.to_lower().ends_with(".jpeg"): out.append(dir.path_join(f))
 for sub in d.get_directories(): out.append_array(_jpegs(dir.path_join(sub)))
 return out

func _strip(path: String) -> bool:
 var b = FileAccess.get_file_as_bytes(path)
 if b.size()<4 or b[0] != 0xFF or b[1] != 0xD8: return false
 var out = PackedByteArray([0xFF,0xD8])
 var i = 2
 var dropped = false
 while i+4<=b.size():
  if b[i] != 0xFF: return false # not a marker where one should be: leave the file alone
  var m = b[i+1]
  if m == 0xDA: # start of scan: the rest is image data
   out.append_array(b.slice(i))
   break
  var length = (b[i+2]<<8)|b[i+3]
  if m in DROP: dropped = true
  else: out.append_array(b.slice(i,i+2+length))
  i += 2+length
 if not dropped: return false
 var f = FileAccess.open(path,FileAccess.WRITE)
 f.store_buffer(out)
 f.close()
 return true
