extends RefCounted
# The map sketch (docs/map-pipeline-design.md §2.3): an SVG drawn in Inkscape (or written as text),
# one layer per kind of feature, 1 SVG unit = 1 m, origin at the map's north-west corner. A small
# subset is supported: <g> layers (inkscape:groupmode="layer", named by id or inkscape:label), and
# path (M L H V C Q Z, absolute or relative; curves flattened), circle, ellipse and polygon.
# Transforms and any other element are errors naming the element's id.
# parse(text) -> {"layers": {layer: [element]}, "errors": [string]}; an element is
# {"id", "kind" (path, circle, ellipse, polygon), "points": PackedVector2Array (flattened outline or
# polyline; for circles the centre), "closed", "center", "r", "data": {data-* attributes}}.

const CURVE_STEPS = 8
const KNOWN = ["svg","g","path","circle","ellipse","polygon","title","desc","defs","metadata","namedview","sodipodi:namedview","rdf:RDF","rdf:Description","cc:Work","dc:format","dc:type","dc:title"]

static func parse_file(path: String) -> Dictionary:
 if not FileAccess.file_exists(path): return {"layers":{},"errors":["missing sketch "+path]}
 return parse(FileAccess.get_file_as_string(path))

static func parse(text: String) -> Dictionary:
 var out = {"layers":{},"errors":[]}
 var xp = XMLParser.new()
 if xp.open_buffer(text.to_utf8_buffer()) != OK:
  out.errors.append("not an SVG document")
  return out
 var stack = [] # layer names of open <g> elements ("" = not a layer)
 var meta_depth = 0
 while xp.read() == OK:
  var t = xp.get_node_type()
  if t == XMLParser.NODE_ELEMENT_END:
   var name = xp.get_node_name()
   if name == "g" and not stack.is_empty(): stack.pop_back()
   if name in ["metadata","defs","sodipodi:namedview"]: meta_depth = maxi(0,meta_depth-1)
   continue
  if t != XMLParser.NODE_ELEMENT: continue
  var name = xp.get_node_name()
  var attrs = {}
  for i in xp.get_attribute_count(): attrs[xp.get_attribute_name(i)] = xp.get_attribute_value(i)
  var empty = xp.is_empty()
  if name in ["metadata","defs","sodipodi:namedview"]:
   if not empty: meta_depth += 1
   continue
  if meta_depth>0: continue
  var id = str(attrs.get("id",""))
  if attrs.has("transform"):
   out.errors.append("transform on '%s' (%s): not supported; apply it in Inkscape" % [id,name])
  if name == "g":
   var layer = ""
   if attrs.get("inkscape:groupmode","") == "layer" or stack.is_empty(): layer = str(attrs.get("inkscape:label",id))
   if layer == "" and not stack.is_empty(): layer = stack[-1]
   if not empty: stack.append(layer)
   continue
  if not name in KNOWN:
   out.errors.append("unsupported element <%s> '%s'" % [name,id])
   continue
  if name in ["svg","title","desc"]: continue
  var layer_name = stack[-1] if not stack.is_empty() else ""
  if layer_name == "":
   out.errors.append("'%s' (%s) is outside any layer" % [id,name])
   continue
  var e = {"id":id,"kind":name,"closed":false,"data":{}}
  for k in attrs:
   if str(k).begins_with("data-"): e.data[str(k).substr(5)] = attrs[k]
  match name:
   "path":
    var r = path_points(str(attrs.get("d","")))
    if r.error != "": out.errors.append("path '%s': %s" % [id,r.error])
    e.points = r.points
    e.closed = r.closed
   "polygon":
    var nums = _numbers(str(attrs.get("points","")))
    var pts = PackedVector2Array()
    for i in range(0,nums.size()-1,2): pts.append(Vector2(nums[i],nums[i+1]))
    e.points = pts
    e.closed = true
   "circle", "ellipse":
    var c = Vector2(float(attrs.get("cx",0)),float(attrs.get("cy",0)))
    e.center = c
    e.r = float(attrs.get("r",attrs.get("rx",0)))
    e.ry = float(attrs.get("ry",e.r))
    var pts = PackedVector2Array()
    for i in 24: pts.append(c+Vector2(cos(i*TAU/24.0)*e.r,sin(i*TAU/24.0)*e.ry))
    e.points = pts
    e.closed = true
  if id == "": out.errors.append("an element in layer '%s' has no id" % layer_name)
  out.layers.get_or_add(layer_name,[]).append(e)
 return out

static func _numbers(s: String) -> PackedFloat64Array:
 var out = PackedFloat64Array()
 var rx = RegEx.new()
 rx.compile("-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
 for m in rx.search_all(s): out.append(float(m.get_string()))
 return out

# Flatten SVG path data into one polyline (a second subpath is an error: one element, one shape).
static func path_points(d: String) -> Dictionary:
 var rx = RegEx.new()
 rx.compile("[MmLlHhVvCcQqZzAaSsTt]|-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
 var tokens = []
 for m in rx.search_all(d): tokens.append(m.get_string())
 var pts = PackedVector2Array()
 var cur = Vector2.ZERO
 var cmd = ""
 var at = [0] # read position (an array: lambdas capture it by reference)
 var closed = false
 var moves = 0
 var num = func() -> float:
  var v = float(tokens[at[0]]) if at[0]<tokens.size() else 0.0
  at[0] += 1
  return v
 while at[0]<tokens.size():
  var tk = tokens[at[0]]
  if tk.length() == 1 and tk.to_upper() in ["M","L","H","V","C","Q","Z","A","S","T"]:
   cmd = tk
   at[0] += 1
   if cmd.to_upper() in ["A","S","T"]: return {"points":pts,"closed":false,"error":"command %s not supported (use M, L, H, V, C, Q, Z)" % cmd}
   if cmd.to_upper() == "Z":
    closed = true
    continue
  var rel = cmd == cmd.to_lower()
  var base = cur if rel else Vector2.ZERO
  match cmd.to_upper():
   "M":
    moves += 1
    if moves>1: return {"points":pts,"closed":closed,"error":"more than one subpath"}
    cur = base+Vector2(num.call(),num.call())
    pts.append(cur)
    cmd = "l" if rel else "L" # further pairs are line-tos
   "L":
    cur = base+Vector2(num.call(),num.call())
    pts.append(cur)
   "H":
    cur = Vector2((cur.x if rel else 0.0)+num.call(),cur.y)
    pts.append(cur)
   "V":
    cur = Vector2(cur.x,(cur.y if rel else 0.0)+num.call())
    pts.append(cur)
   "C":
    var p1 = base+Vector2(num.call(),num.call())
    var p2 = base+Vector2(num.call(),num.call())
    var p3 = base+Vector2(num.call(),num.call())
    var p0 = cur
    for s in range(1,CURVE_STEPS+1):
     var t = float(s)/CURVE_STEPS
     var u = 1.0-t
     pts.append(p0*u*u*u+p1*3.0*u*u*t+p2*3.0*u*t*t+p3*t*t*t)
    cur = p3
   "Q":
    var q1 = base+Vector2(num.call(),num.call())
    var q2 = base+Vector2(num.call(),num.call())
    var q0 = cur
    for s in range(1,CURVE_STEPS+1):
     var t = float(s)/CURVE_STEPS
     pts.append(q0.lerp(q1,t).lerp(q1.lerp(q2,t),t))
    cur = q2
   _:
    return {"points":pts,"closed":closed,"error":"unexpected '%s'" % tk}
 return {"points":pts,"closed":closed,"error":""}

# Every element id in the sketch (for reference checks).
static func ids(sketch: Dictionary) -> Dictionary:
 var out = {}
 for layer in sketch.layers:
  for e in sketch.layers[layer]: out[e.id] = layer
 return out
