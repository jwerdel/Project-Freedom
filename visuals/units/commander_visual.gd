extends Node3D
# Armored commander at campaign-map scale (deliberately oversized; see constitution.md): the rigged
# general from art_source/general_aurek (Blender, humanoid rig, exported to
# assets/models/general_aurek.glb) on a stone base with the faction banner. Plate armour, pauldrons,
# great helm, cape, mace and shield; the faction_primary/faction_secondary materials take the
# owner's colors.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const MODEL = preload("res://assets/models/general_aurek.glb")

const HEIGHT = 4.45 # campaign figure height in map units (the earlier procedural figure's size)
const SOURCE_HEIGHT = 1.958 # the model's height in meters

var _primary := Color("8a2b2b")
var _secondary := Color("d6a443")
var _tinted := [] # [MeshInstance3D, surface, "primary"|"secondary"]
var _standard_on := true

func _ready():
 var kit = ProtoKit.shared()
 kit.cylinder(self,Vector3(0,0.08,0),1.1,1.1,0.16,kit.stone,48)
 var model = MODEL.instantiate()
 model.name = "General"
 model.scale = Vector3.ONE*(HEIGHT/SOURCE_HEIGHT)
 model.position.y = 0.16
 add_child(model)
 for m in model.find_children("*","MeshInstance3D",true,false):
  for i in m.mesh.get_surface_count():
   var mat = m.mesh.surface_get_material(i)
   if mat == null: continue
   if mat.resource_name == "faction_primary": _tinted.append([m,i,"primary"])
   elif mat.resource_name == "faction_secondary": _tinted.append([m,i,"secondary"])
 var standard = Node3D.new()
 standard.name = "Standard"
 standard.visible = _standard_on
 add_child(standard)
 kit.banner(standard,Vector3(1.3,0,-0.4),3.4)
 _apply_colors()

# Faction colors on the cape, tabard, shield and banner (banner.gdshader tint). Called after
# _ready by the map; the secondary color follows the primary unless set_faction_colors gives it.
func set_banner_color(c: Color):
 set_faction_colors(c,_secondary)

func set_faction_colors(primary: Color,secondary: Color):
 _primary = primary
 _secondary = secondary
 if is_inside_tree(): _apply_colors()

func _apply_colors():
 for t in _tinted:
  var src = t[0].mesh.surface_get_material(t[1])
  var mat = src.duplicate() if src is BaseMaterial3D else StandardMaterial3D.new()
  mat.albedo_color = _primary if t[2] == "primary" else _secondary
  mat.albedo_texture = null
  t[0].set_surface_override_material(t[1],mat)
 for m in find_children("*","MeshInstance3D",true,false):
  var mat = m.material_override
  if mat is ShaderMaterial and mat.shader != null and mat.shader.resource_path == "res://banner.gdshader": mat.set_shader_parameter("tint",_primary)

# The faction standard on its pole (hidden in the character window, which shows the lord alone).
func set_standard_visible(on: bool):
 _standard_on = on
 var s = get_node_or_null("Standard")
 if s: s.visible = on
