extends Node
## Global warp transition helper. Autoloaded.
## Call WarpTransition.warp_to(scene_path) to play the warp tunnel then load the target.
## For non-level transitions (menu, shop), call change_scene_to_file directly as normal.

const WARP_SCENE := "res://game/warp/WarpTunnel.tscn"

func warp_to(target_scene: String) -> void:
	## Play the hyperspace warp tunnel, then load the target scene.
	var warp = load(WARP_SCENE).instantiate()
	# Replace the current scene with the warp tunnel
	get_tree().current_scene.queue_free()
	get_tree().root.add_child(warp)
	get_tree().current_scene = warp
	warp.warp_to(target_scene)
