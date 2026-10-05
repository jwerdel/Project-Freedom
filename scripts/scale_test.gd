extends SceneTree
# Scale test, CPU half: runs scripts/scale_bench.gd (see there) in the editor build.
#   runtime\Godot.exe --headless --path . -s scripts/scale_test.gd -- [--map=synthetic600] [--turns=3] [--out=<file>]

func _initialize():
 root.add_child.call_deferred(load("res://scripts/scale_bench.gd").new())
