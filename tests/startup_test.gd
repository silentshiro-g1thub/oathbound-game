extends SceneTree


## Check the menu scene and its locally owned player without opening network ports.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	assert(main.main_menu.visible)
	assert(root.get_camera_3d() != null)
	main.add_player(1)
	var player: CharacterBody3D = main.get_node("1")
	await process_frame
	assert(player.is_multiplayer_authority())
	assert(player.standing_shape != null)
	assert(player.camera.current)
	assert(player.active_weapon.has_method("try_fire"))
	player._fire_active_weapon()
	assert(player.active_weapon.revolver_sfx.playing)
	print("STARTUP CHECK PASSED: menu, local player, camera, and weapon.")
	main.queue_free()
	await process_frame
	quit()
