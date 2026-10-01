extends SceneTree
# One-off asset preparation for the placeholder unit models (Quaternius, CC0).
# Copies the base character, outfits and horse into assets/quaternius/, downscales their
# textures to 1024 px, and extracts the few poses we use from the Universal Animation Library.
# Run: runtime\Godot.exe --headless --path . -s scripts/prepare_character_assets.gd -- <quaternius download folder>

const MAX_TEXTURE = 1024
const POSES = ["Idle_Loop","Sword_Idle","Idle_Torch_Loop","Sitting_Idle_Loop","Spell_Simple_Idle_Loop","Pistol_Idle_Loop"]

func _initialize():
 var src = OS.get_cmdline_user_args()[0].replace("\\","/")
 var base = src+"/base-characters/Universal Base Characters[Standard]/Base Characters/Godot - UE/"
 var outfits = src+"/outfits-fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/"
 var dst = ProjectSettings.globalize_path("res://assets/quaternius/")
 for d in ["characters","outfits","animals","animations"]: DirAccess.make_dir_recursive_absolute(dst+d)
 # Base character (only the head, eyes and eyebrows are shown; see visuals/units/soldier_visual.gd).
 for f in ["Superhero_Male_FullBody.gltf","Superhero_Male_FullBody.bin"]: copy(base+f,dst+"characters/"+f)
 for pair in [["T_Hair_1_BaseColor.png","T_Hair_1_BaseColor.png"],["T_Hair_1_Normal.png","T_Hair_1_Normal_png.png"],
   ["T_Eye_Brown.png","T_Eye_Brown.png"],["T_Eye_Normal.png","T_Eye_Normal_png.png"],
   ["T_Superhero_Male_Dark.png","T_Superhero_Male_Dark.png"],["T_Superhero_Male_Normal.png","T_Superhero_Male_Normal.png"],
   ["T_Superhero_Male_Roughness.png","T_Superhero_Male_Roughness.png"]]:
  shrink(base+pair[0],dst+"characters/"+pair[1])
 # Hair and beard rigged to the head bone, for the bare-headed outfits.
 var hair = src+"/base-characters/Universal Base Characters[Standard]/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/"
 for f in ["Hair_Buzzed","Hair_Beard","Hair_SimpleParted"]:
  for ext in [".gltf",".bin"]: copy(hair+f+ext,dst+"characters/"+f+ext)
 shrink(hair+"T_Hair_1_Normal.png",dst+"characters/T_Hair_1_Normal.png")
 for f in ["Male_Peasant.gltf","Male_Peasant.bin","Male_Ranger.gltf","Male_Ranger.bin"]: copy(outfits+f,dst+"outfits/"+f)
 for f in ["T_Peasant_BaseColor.png","T_Peasant_Normal.png","T_Peasant_ORM.png","T_Ranger_BaseColor.png","T_Ranger_Normal.png","T_Ranger_ORM.png",
   "T_Regular_Male_Dark_BaseColor.png","T_Regular_Male_Normal.png","T_Regular_Male_Roughness.png"]:
  shrink(outfits+f,dst+"outfits/"+f)
 copy(src+"/animals/glTF/Horse.gltf",dst+"animals/Horse.gltf")
 # Poses: extracted from UAL1_Standard.glb (no root motion) as standalone Animation resources.
 var doc = GLTFDocument.new()
 var state = GLTFState.new()
 var err = doc.append_from_file(src+"/animation-library/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb",state)
 assert(err == OK,"Could not read UAL1_Standard.glb")
 var scene = doc.generate_scene(state)
 var player: AnimationPlayer = scene.find_children("*","AnimationPlayer",true,false)[0]
 for pose in POSES:
  var anim = player.get_animation(pose)
  assert(anim != null,"Missing animation "+pose)
  ResourceSaver.save(anim.duplicate(true),"res://assets/quaternius/animations/"+pose+".res")
  print("POSE ",pose," tracks ",anim.get_track_count()," length ",anim.length)
 scene.free()
 print("PREPARED")
 quit()

func copy(from: String,to: String):
 var e = DirAccess.copy_absolute(from,to)
 assert(e == OK,"copy failed: "+from)

func shrink(from: String,to: String):
 var img = Image.load_from_file(from)
 assert(img != null,"cannot load "+from)
 var s = float(MAX_TEXTURE)/maxi(img.get_width(),img.get_height())
 if s<1.0: img.resize(int(img.get_width()*s),int(img.get_height()*s),Image.INTERPOLATE_LANCZOS)
 img.save_png(to)
 print("TEX ",to.get_file()," ",img.get_size())
