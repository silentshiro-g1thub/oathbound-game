extends SceneTree
var main: Node
var mode: String

## Start the two-process integration check after the scene tree is available.
func _initialize():
	call_deferred("run")

## Check peer spawning, crosshair alignment, and floor/terrain landings on each client.
func run():
	mode = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	if mode == "host":
		main.enet_peer = ENetMultiplayerPeer.new()
		assert(main.enet_peer.create_server(19999) == OK)
		main.multiplayer.multiplayer_peer = main.enet_peer
		main.multiplayer.peer_connected.connect(main.add_player)
		main.add_player(1)
	else:
		main.enet_peer = ENetMultiplayerPeer.new()
		assert(main.enet_peer.create_client("127.0.0.1", 19999) == OK)
		main.multiplayer.multiplayer_peer = main.enet_peer
	await create_timer(1.5).timeout
	var local = main.get_node_or_null(str(main.multiplayer.get_unique_id()))
	assert(local != null)
	assert(main.multiplayer.get_peers().size() == 1)
	assert(main.get_node_or_null(str(main.multiplayer.get_peers()[0])) != null)
	assert(local.collision_mask != 0 and local.camera.current)
	assert(main.get_node("Floor/MeshInstance3D/Terrain3D").get_camera() == local.camera)
	var marker = local.active_weapon.crosshair
	assert((marker.position + marker.size * marker.scale * 0.5).distance_to(root.get_visible_rect().size * 0.5) < 0.01)
	local._begin_jump(local.jump_velocity)
	await create_timer(0.15).timeout
	local._begin_jump(local.double_jump_velocity)
	await create_timer(0.15).timeout
	local.head.rotation.x = deg_to_rad(-89)
	local.velocity.y = -90
	local._start_dash(Vector3.ZERO)
	await create_timer(1.5).timeout
	assert(local.is_on_floor() and local.position.y >= -0.6)
	var terrain = main.get_node("Floor/MeshInstance3D/Terrain3D")
	var point := Vector3(64, 0, 0)
	var ground: float = terrain.get_data().get_height(point)
	assert(is_finite(ground))
	local.position = Vector3(point.x, ground + 12, point.z)
	local.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	local.velocity.y = -90
	local._start_dash(Vector3.ZERO)
	await create_timer(1.5).timeout
	assert(local.is_on_floor() and local.position.y >= ground - 0.2)
	print("PASS ",mode,": fast downward dash lands on terrain outside the central floor")
	print("PASS ",mode,": connected, both players spawned, local terrain camera, centered crosshair, double jump/downward dash lands safely")
	if mode == "host":
		await create_timer(3).timeout
	main.multiplayer.multiplayer_peer = null
	quit()
