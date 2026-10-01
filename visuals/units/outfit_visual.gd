extends Node3D
# A placeholder outfit: a skinned Quaternius outfit model, optionally with some parts hidden.
# The soldier visual moves the visible parts onto its own skeleton.

@export var hidden_parts: PackedStringArray = []

func parts() -> Array:
 var out = []
 for m in find_children("*","MeshInstance3D",true,false):
  if not (m.name in hidden_parts): out.append(m)
 return out
