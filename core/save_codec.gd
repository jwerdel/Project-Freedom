extends RefCounted
# Type-exact JSON for campaign state. Plain JSON cannot tell 2 from 2.0 (Godot parses every number
# as a float), and the simulation's arithmetic depends on the difference, so:
#   int -> JSON integer; float with a fraction -> JSON number (17 significant digits);
#   whole float -> {"__f": n}; a float the parser would not read back exactly -> {"__x": hex bits};
#   dictionary with a non-String key -> {"__d": [[key, value], ...]}.
# Dictionary insertion order is kept (it decides iteration order, which systems rely on).
# StringName keys (from dict.key = v) are written as strings; Godot treats both as the same key.
# Only the types campaign state uses are supported: null, bool, int, float, String, Array, Dictionary.

static func encode(v):
 match typeof(v):
  TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING: return v
  TYPE_STRING_NAME: return String(v)
  TYPE_FLOAT:
   if is_finite(v) and v == floorf(v) and absf(v)<9.0e15: return {"__f":int(v)}
   # Godot's JSON parser is not correctly rounded: keep a readable number only when it reads
   # back bit-exact, otherwise store the 64-bit pattern.
   if is_finite(v) and JSON.parse_string(JSON.stringify(v,"",false,true)) == v: return v
   var b = PackedByteArray()
   b.resize(8)
   b.encode_double(0,v)
   return {"__x":b.hex_encode()}
  TYPE_ARRAY:
   var out = []
   for x in v: out.append(encode(x))
   return out
  TYPE_DICTIONARY:
   var plain = true
   for k in v:
    if not (typeof(k) == TYPE_STRING or typeof(k) == TYPE_STRING_NAME) or k == "__f" or k == "__d" or k == "__x":
     plain = false
     break
   if plain:
    var out = {}
    for k in v: out[String(k)] = encode(v[k])
    return out
   var pairs = []
   for k in v: pairs.append([encode(k),encode(v[k])])
   return {"__d":pairs}
 push_error("SaveCodec: unsupported type %s" % type_string(typeof(v)))
 return null

static func decode(v):
 match typeof(v):
  TYPE_FLOAT: return int(v) if v == floorf(v) and absf(v)<9.0e15 else v
  TYPE_ARRAY:
   var out = []
   for x in v: out.append(decode(x))
   return out
  TYPE_DICTIONARY:
   if v.size() == 1 and v.has("__f"): return float(v.__f)
   if v.size() == 1 and v.has("__x"): return String(v.__x).hex_decode().decode_double(0)
   if v.size() == 1 and v.has("__d"):
    var d = {}
    for p in v.__d: d[decode(p[0])] = decode(p[1])
    return d
   var out = {}
   for k in v: out[k] = decode(v[k])
   return out
 return v

static func to_json(v,indent := "") -> String:
 return JSON.stringify(encode(v),indent,false,true)

# Returns the decoded value, or null when the text is not valid JSON.
static func from_json(text: String):
 var j = JSON.new()
 if j.parse(text) != OK: return null
 return decode(j.data)
