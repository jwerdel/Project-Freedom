extends SceneTree
# Scale test, CPU half: runs scripts/scale_bench.gd (see there) in the editor build.
#   runtime\Godot.exe --headless --path . -s scripts/scale_test.gd -- [--map=synthetic600] [--turns=3] [--out=<file>]

func _initialize():
 # Every faction is AI-run here, the player's too: its orders walk at End Turn.
 load("res://core/movement.gd").continue_player_orders = true
 root.add_child.call_deferred(load("res://scripts/scale_bench.gd").new())
