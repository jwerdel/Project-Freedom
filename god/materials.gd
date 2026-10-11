extends RefCounted
# Materials of the god-game look test: one god/surface.gdshader material per chunk material class
# (god/mesh_kit.gd MATS) from the CC0 Poly Haven sets in assets/god/materials/, and the ground
# material (god/terrain.gdshader).

const MeshKit = preload("res://god/mesh_kit.gd")
const DIR = "res://assets/god/materials/"

static var _mats = {}
static var flat := false # --flat: the kits' plain colours, no textures (the material pass's "before")
static var _macro: Texture2D

static func tex(set_name: String,kind: String) -> Texture2D:
 return load(DIR+set_name+"/"+set_name+"_"+kind+".jpg")

static func surface(id: int) -> ShaderMaterial:
 if _mats.has(id): return _mats[id]
 var cls = MeshKit.MAT_IDS[id]
 var m = ShaderMaterial.new()
 m.shader = load("res://god/surface.gdshader")
 var set_name = str(MeshKit.MATS[cls][0])
 if flat:
  m.set_shader_parameter("textured",false)
  m.set_shader_parameter("base_color",Color(1,1,1))
  m.set_shader_parameter("snow",0.0)
  m.set_shader_parameter("grime",0.0)
  if cls == "glow":
   m.set_shader_parameter("emission_color",Color("ffb050"))
   m.set_shader_parameter("emission_energy",2.2)
  _mats[id] = m
  return m
 m.set_shader_parameter("snow_tex",tex("snow_02","diff"))
 m.set_shader_parameter("snow_n",tex("snow_02","nor_gl"))
 if set_name != "":
  m.set_shader_parameter("albedo_tex",tex(set_name,"diff"))
  m.set_shader_parameter("normal_tex",tex(set_name,"nor_gl"))
  m.set_shader_parameter("arm_tex",tex(set_name,"arm"))
 else:
  m.set_shader_parameter("textured",false)
 var grade = {"stone":Color(0.74,0.77,0.84),"house_stone":Color(0.8,0.79,0.8),"plaster":Color(0.93,0.92,0.9),"timber":Color(0.62,0.52,0.45),
  "planks":Color(0.7,0.62,0.56),"slate":Color(0.6,0.66,0.76),"thatch":Color(0.86,0.8,0.7),"window":Color(0.7,0.62,0.56),"door":Color(0.72,0.64,0.58)}
 if grade.has(cls): m.set_shader_parameter("tint",grade[cls])
 var sat = {"stone":0.55,"house_stone":0.7,"plaster":0.55,"timber":0.8,"planks":0.8,"slate":0.7,"thatch":0.85,"window":0.75,"door":0.75}
 if sat.has(cls): m.set_shader_parameter("saturation",sat[cls])
 match cls:
  "slate", "thatch": m.set_shader_parameter("snow",1.0)
  "window":
   m.set_shader_parameter("snow",0.0)
   m.set_shader_parameter("grime",0.2)
  "door": m.set_shader_parameter("snow",0.0)
  "timber": m.set_shader_parameter("snow",0.6)
  "void":
   m.set_shader_parameter("base_color",Color("16120f"))
   m.set_shader_parameter("snow",0.0)
   m.set_shader_parameter("grime",0.0)
  "glow":
   m.set_shader_parameter("base_color",Color("3a2a12"))
   m.set_shader_parameter("emission_color",Color("ffb050"))
   m.set_shader_parameter("emission_energy",2.2)
   m.set_shader_parameter("snow",0.0)
   m.set_shader_parameter("grime",0.0)
  "glass":
   m.set_shader_parameter("base_color",Color("5d7c76"))
   m.set_shader_parameter("roughness_scale",0.15)
   m.set_shader_parameter("snow",0.4)
   m.set_shader_parameter("grime",0.1)
  "water":
   m.set_shader_parameter("base_color",Color("2c4b52"))
   m.set_shader_parameter("roughness_scale",0.08)
   m.set_shader_parameter("emission_color",Color("9fd4d8"))
   m.set_shader_parameter("emission_energy",0.15)
   m.set_shader_parameter("snow",0.0)
   m.set_shader_parameter("grime",0.0)
  "leaves":
   m.set_shader_parameter("leaves",1.0)
   m.set_shader_parameter("snow",0.55)
   m.set_shader_parameter("grime",0.0)
  "bark": m.set_shader_parameter("snow",0.4)
  "cloth":
   m.set_shader_parameter("snow",0.45)
   m.set_shader_parameter("grime",0.25)
 _mats[id] = m
 return m

static func macro() -> Texture2D:
 if _macro == null:
  var nt = NoiseTexture2D.new()
  nt.width = 512
  nt.height = 512
  nt.seamless = true
  nt.generate_mipmaps = true
  var nz = FastNoiseLite.new()
  nz.frequency = 0.012
  nz.fractal_octaves = 4
  nt.noise = nz
  _macro = nt
 return _macro

static func terrain() -> ShaderMaterial:
 var m = ShaderMaterial.new()
 m.shader = load("res://god/terrain.gdshader")
 for pair in [["snow","snow_02"],["ground","forest_ground_04"],["mud","brown_mud_02"],["rock","rocky_terrain_02"],["pave","cobblestone_floor_08"]]:
  m.set_shader_parameter(pair[0]+"_a",tex(pair[1],"diff"))
  m.set_shader_parameter(pair[0]+"_n",tex(pair[1],"nor_gl"))
 m.set_shader_parameter("macro",macro())
 m.set_shader_parameter("flat_look",flat)
 return m

# Tiling value noise for the sky and the cloud deck (32 cells across, see their noise()).
static var _cloud_noise: Texture2D
static func cloud_noise() -> Texture2D:
 if _cloud_noise == null:
  var nt = NoiseTexture2D.new()
  nt.width = 256
  nt.height = 256
  nt.seamless = true
  nt.generate_mipmaps = true
  var nz = FastNoiseLite.new()
  nz.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
  nz.frequency = 0.125
  nz.fractal_type = FastNoiseLite.FRACTAL_NONE
  nt.noise = nz
  nt.normalize = true
  _cloud_noise = nt
 return _cloud_noise
