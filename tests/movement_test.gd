extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")
var player: CharacterBody3D
var world: Node3D
var failures: int = 0
var checks: int = 0
var dt: float = 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	world.add_child(body)
	body.position = at
	return body

func tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
		player._physics_process(dt)
		await process_frame

func reset_player(at: Vector3 = Vector3(0, 0.01, 0)) -> void:
	for action in InputMap.get_actions():
		Input.action_release(action)
	if is_instance_valid(player):
		player.free()
	player = PlayerScene.instantiate()
	# Fixed regression fixture; Inspector/default tuning remains user-controlled.
	player.jump_velocity = 4.5
	player.double_jump_velocity = 4.95
	player.dash_speed = 23.0
	player.dash_cooldown = 0.8
	world.add_child(player)
	player.position = at
	player.set_physics_process(false)
	await tick(3)

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	await reset_player()
	check(player.is_on_floor(), "standalone player lands on real collision geometry")
	Input.action_press("move_forward")
	await tick(60)
	check(absf(player.velocity.z + 7.0) < 0.01, "forward walk reaches 7 m/s")
	Input.action_press("sprint")
	await tick(30)
	check(absf(player.velocity.z + 11.5) < 0.01, "held sprint reaches 11.5 m/s")
	Input.action_release("sprint")
	await tick(1)
	check(player.velocity.z < -7.0, "sprint release decelerates without instant speed reset")
	await reset_player()
	Input.action_press("move_forward")
	await tick(1)
	var cardinal_speed: float = player._horizontal_velocity().length()
	await reset_player()
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await tick(1)
	check(absf(player._horizontal_velocity().length() - cardinal_speed) < 0.001, "diagonal acceleration equals cardinal acceleration")
	await tick(60)
	check(absf(player._horizontal_velocity().length() - 7.0) < 0.01, "diagonal top speed is normalized")
	await reset_player()
	player.dash_follows_aim = false
	player.rotation.y = PI / 2.0
	Input.action_press("move_forward")
	await tick(30)
	check(player.velocity.x < -6.9 and absf(player.velocity.z) < 0.01, "W follows player camera yaw")
	await reset_player()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await tick(40)
	Input.action_press("jump")
	await tick(1)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await tick(5)
	check(player.velocity.y > 0.0 and absf(player.velocity.z + 11.5) < 0.01, "jump preserves sprint momentum without directional input")
	Input.action_release("jump")
	await tick(1)
	check(player.velocity.y <= player.short_hop_velocity, "early release preserves short hop")
	await reset_player()
	# Move off support just above the floor; establish an airborne collision result.
	player.position.y = 0.15
	player.velocity.y = 0.1
	await tick(1)
	Input.action_press("jump")
	await tick(1)
	check(player.velocity.y > 4.0, "coyote jump accepts input just after leaving support")
	await reset_player(Vector3(0, 0.4, 0))
	player.velocity.y = -5.0
	player.extra_jumps_remaining = 0
	Input.action_press("jump")
	await tick(6)
	check(player.velocity.y > 0.0, "buffered jump fires on landing")
	var old_yaw: float = player.rotation.y
	player._release_controls()
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	player._unhandled_input(motion)
	check(player.rotation.y == old_yaw, "released mouse does not rotate camera")
	check(not player.controls_active, "release disables gameplay input")
	await test_slide()
	await test_dash()
	await test_double_jump()
	await test_edges()
	await test_physics_rates()
	await test_launch_changes()
	await test_crouch_and_strafe()
	await test_main_scene()
	for action in InputMap.get_actions():
		Input.action_release(action)
	print("MOVEMENT TESTS: %d checks, %d failures" % [checks, failures])
	world.free()
	quit(1 if failures else 0)

func test_slide() -> void:
	await reset_player()
	Input.action_press("slide")
	await tick()
	check(player.is_crouched and player.movement_state != player.MovementState.SLIDING, "Ctrl crouches without sufficient slide momentum")
	await reset_player()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await tick(40)
	Input.action_press("slide")
	await tick()
	check(player.movement_state == player.MovementState.SLIDING, "sprint transitions to slide")
	check(player.is_crouched and absf(player.body_collision.shape.height - 1.0) < 0.01, "slide lowers collision capsule")
	check(player._horizontal_velocity().length() > 11.0, "slide preserves entry momentum")
	Input.action_press("jump")
	await tick()
	check(player.velocity.y > 4.0 and player.movement_state == player.MovementState.AIRBORNE, "slide jump exits slide and launches")
	check(player._horizontal_velocity().length() > 10.5, "slide jump preserves horizontal speed")
	await reset_player()
	player.velocity.z = -11.5
	Input.action_press("slide")
	await tick()
	var ceiling := box(player.position + Vector3(0, 1.4, 0), Vector3(8, 0.2, 8))
	Input.action_release("slide")
	await tick(20)
	check(player.is_crouched, "slide exit cannot stand through low ceiling")
	check(not player._can_stand(), "standing capsule query detects ceiling")
	ceiling.free()
	await tick(2)
	check(not player.is_crouched, "player stands when overhead space becomes clear")
	await reset_player()
	player.velocity.z = -11.5
	Input.action_press("slide")
	await tick(60)
	check(player.movement_state != player.MovementState.SLIDING, "held slide expires without auto-retrigger")

func test_dash() -> void:
	# Measure displacement, not just velocity: moving twice outside dash causes a hitch.
	await reset_player()
	player.dash_speed = 8.5
	player.velocity = Vector3(0, 0, -player.sprint_speed)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var previous_position := player.position
	await tick()
	var before_dash := previous_position.distance_to(player.position)
	previous_position = player.position
	Input.action_press("dash")
	await tick()
	var during_dash := previous_position.distance_to(player.position)
	await tick(5)
	previous_position = player.position
	await tick()
	var after_dash := previous_position.distance_to(player.position)
	check(absf(before_dash - player.sprint_speed * dt) < 0.002, "ordinary movement advances exactly one physics step")
	check(absf(during_dash - before_dash) < 0.002 and absf(after_dash - before_dash) < 0.002, "dash entry and exit preserve actual travel speed when incoming speed exceeds dash speed")
	await reset_player()
	player.dash_speed = 20.0
	Input.action_press("dash")
	await tick(5)
	var previous_distance := -player.position.z
	await reset_player()
	Input.action_press("dash")
	await tick(5)
	var short_distance := -player.position.z
	check(player._horizontal_velocity().length() > 19.9, "dash exit keeps speed instead of instantly stopping")
	await tick()
	check(player._horizontal_velocity().length() > 22 and player._horizontal_velocity().length() < 23, "ordinary ground friction slows the next frame without a velocity reset")
	check(absf(short_distance / previous_distance - 1.15) < 0.01, "dash burst covers 15 percent more distance")
	await tick(90)
	check(-player.position.z > short_distance and player._horizontal_velocity().length() < 0.01, "idle grounded dash eventually stops through ordinary friction")
	await reset_player()
	Input.action_press("move_left")
	Input.action_press("move_right")
	Input.action_press("dash")
	await tick(90)
	check(player._horizontal_velocity().length() < 0.01, "opposing movement inputs do not preserve dash drift")
	await reset_player()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("dash")
	await tick(90)
	check(player._horizontal_velocity().length() > player.sprint_speed, "held sprint preserves dash overspeed instead of forcing a speed reset")
	await reset_player()
	player.dash_follows_aim = false
	Input.action_press("dash")
	await tick()
	check(player.movement_state == player.MovementState.DASHING and player.velocity.z < -19.9, "empty dash input defaults to facing forward")
	Input.action_press("move_back")
	await tick(2)
	check(player.velocity.z < -19.9, "ordinary movement cannot overwrite dash")
	await tick(10)
	check(player.movement_state != player.MovementState.DASHING and player._horizontal_velocity().length() > player.move_speed and player._horizontal_velocity().length() < player.dash_speed, "dash continues carrying speed after burst")
	Input.action_release("dash")
	await tick()
	Input.action_press("dash")
	await tick()
	check(player.movement_state != player.MovementState.DASHING, "dash cooldown prevents immediate repeat")
	await tick(60)
	Input.action_release("dash")
	await tick()
	Input.action_press("dash")
	await tick()
	check(player.movement_state == player.MovementState.DASHING and player.velocity.z > 19.9, "dash refreshes after cooldown and uses backward input")
	await reset_player()
	player.dash_follows_aim = false
	player.rotation.y = PI / 2.0
	Input.action_press("move_right")
	Input.action_press("dash")
	await tick()
	check(player.velocity.z < -19.9, "directional dash follows camera yaw")
	await reset_player()
	var wall := box(Vector3(0, 2, -1), Vector3(10, 4, 0.1))
	Input.action_press("dash")
	await tick(4)
	check(player.movement_state != player.MovementState.DASHING, "head-on wall collision terminates dash")
	check(player.position.z > -0.65, "dash does not tunnel through thin wall")
	wall.free()
	await reset_player()
	player.velocity.z = -11.5
	Input.action_press("slide")
	await tick()
	Input.action_press("dash")
	await tick()
	check(player.movement_state == player.MovementState.SLIDING, "dash cannot expand a crouched capsule")

func test_double_jump() -> void:
	var heights: Array[float] = []
	for launch_speed in [4.5, 4.95]:
		await reset_player(Vector3(0, 8, 0))
		player.velocity = Vector3.ZERO
		player.double_jump_velocity = launch_speed
		var start_y := player.position.y
		var peak_y := start_y
		Input.action_press("jump")
		for frame in 40:
			await tick()
			peak_y = maxf(peak_y, player.position.y)
		heights.append(peak_y - start_y)
	check(heights[1] / heights[0] > 1.15 and heights[1] / heights[0] < 1.25, "extra jump gains between 15 and 25 percent actual height")
	await reset_player()
	Input.action_press("jump")
	await tick(4)
	check(player.extra_jumps_remaining == 1, "ground jump does not spend extra jump")
	Input.action_release("jump")
	await tick()
	Input.action_press("jump")
	await tick()
	check(player.extra_jumps_remaining == 0 and player.velocity.y > 4.0, "second press spends one extra jump")
	await tick(4)
	check(player.velocity.y < 4.5, "holding jump does not retrigger")
	Input.action_release("jump")
	await tick()
	var before: float = player.velocity.y
	Input.action_press("jump")
	await tick()
	check(player.velocity.y < before and player.extra_jumps_remaining == 0, "third airborne press cannot jump")
	Input.action_release("jump")
	await tick(100)
	check(player.is_on_floor() and player.extra_jumps_remaining == 1, "landing restores exactly one extra jump")
func test_edges() -> void:
	var side_wall := box(Vector3(0.85, 7, 0), Vector3(0.5, 14, 100))
	await reset_player(Vector3(0, 6, 0))
	player.velocity = Vector3(0, -3, -11.5)
	player.extra_jumps_remaining = 0
	Input.action_press("move_forward")
	Input.action_press("jump")
	await tick(10)
	check(player.movement_state == player.MovementState.AIRBORNE and player.velocity.y < -5.0, "side wall does not alter gravity or grant a jump")
	check(player.extra_jumps_remaining == 0, "side wall does not restore extra jump")
	side_wall.free()
	await reset_player()
	player.velocity.z = -11.5
	Input.action_press("slide")
	Input.action_press("jump")
	await tick()
	check(player.velocity.y > 4.0 and not player.is_crouched, "simultaneous slide and jump produces one airborne state")
	await reset_player()
	Input.action_press("jump")
	Input.action_press("dash")
	await tick()
	check(player.movement_state == player.MovementState.DASHING and player.velocity.y <= 0.0, "simultaneous dash and jump prioritizes dash")
	await tick(15)
	check(player.extra_jumps_remaining == 1 and player.velocity.y <= 0.0, "expired dash jump buffer cannot launch a delayed jump")
	await reset_player()
	var roof := box(Vector3(0, 2.0, 0), Vector3(8, 0.1, 8))
	Input.action_press("jump")
	await tick(10)
	check(player.position.y < 0.2 and player.velocity.y <= 0.0, "jump stops against low ceiling")
	roof.free()
	var ramp := box(Vector3(0, 0, 0), Vector3(8, 0.4, 10))
	ramp.rotation.x = deg_to_rad(15)
	await reset_player(Vector3(0, 2, 2))
	await tick(60)
	check(player.is_on_floor(), "walkable slope registers as floor")
	Input.action_press("move_forward")
	await tick(25)
	check(player.is_on_floor() and player.position.z < 1.0, "ground movement follows walkable slope")
	ramp.free()

func test_physics_rates() -> void:
	var distances: Array[float] = []
	var heights: Array[float] = []
	for rate in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		dt = 1.0 / rate
		await reset_player()
		Input.action_press("move_forward")
		await tick(rate)
		distances.append(-player.position.z)
		check(absf(player._horizontal_velocity().length() - 7.0) < 0.01, "walk reaches same target at %d physics ticks" % rate)
		await reset_player()
		# At 120 Hz, three reset frames do not reach the floor from spawn height.
		await tick(10)
		check(player.is_on_floor(), "jump-rate comparison starts grounded at %d Hz" % rate)
		Input.action_press("jump")
		var peak: float = 0.0
		for i in rate:
			await tick()
			peak = maxf(peak, player.position.y)
		heights.append(peak)
	# Swept character movement uses discrete physics steps. Allow one 30 Hz step.
	check(distances.max() - distances.min() < 7.0 / 30.0, "one-second walk distance differs by less than one 30 Hz step across physics rates")
	print("Physics-rate walking distances: ", distances, "; jump peaks: ", heights)
	check(heights.max() - heights.min() < 0.08, "jump peak agrees within 8 cm across 30/60/120 Hz")
	Engine.physics_ticks_per_second = 60
	dt = 1.0 / 60.0

func test_main_scene() -> void:
	var main := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(main)
	# The arena spawns players through the room system, so give it one local
	# player and a multiplayer peer, the same way hosting does in the game.
	main.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	main.add_player(1)
	var actor := main.get_node_or_null("1") as CharacterBody3D
	check(actor != null, "main scene spawns its local player through the room script")
	if actor == null:
		main.multiplayer.multiplayer_peer = null
		main.free()
		return
	actor.set_physics_process(false)
	var weapon: Node = actor.active_weapon
	check(weapon != null and weapon.has_method("try_fire"), "equipped revolver loads its firing script from its current path")
	var plain_node := Node.new()
	actor.active_weapon = plain_node
	actor._fire_active_weapon()
	plain_node.free()
	actor._fire_active_weapon()
	actor.active_weapon = weapon
	check(not weapon.revolver_sfx.playing, "missing or freed weapon scripts cannot fire or crash dispatch")
	check(actor.active_weapon.revolver_sfx is AudioStreamPlayer3D and actor.active_weapon.revolver_sfx.stream != null, "revolver owns a configured 3D gunshot player")
	check(not actor.active_weapon.revolver_sfx.playing, "gunshot does not autoplay")
	check(actor.active_weapon.animation_play != null and actor.active_weapon.muzzle_flash != null and actor.active_weapon.aim_ray != null, "main scene retains weapon and aim node references")
	check(actor.active_weapon.crosshair.mouse_filter == Control.MOUSE_FILTER_IGNORE and actor.active_weapon.crosshair_hit.mouse_filter == Control.MOUSE_FILTER_IGNORE, "crosshair UI cannot swallow shooting or recapture clicks")
	check(actor.get_node("Head/Camera3D").rotation.is_zero_approx(), "camera mount is aligned with movement yaw and head pitch")
	actor._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not actor.controls_active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss releases mouse and controls")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	actor._unhandled_input(click)
	print("Headless mouse mode after recapture: ", Input.mouse_mode, "; click matches Shoot: ", click.is_action_pressed("Shoot"))
	check(actor.controls_active and actor.active_weapon.animation_play.current_animation != "Shot", "recapture click does not shoot")
	check(not actor.active_weapon.revolver_sfx.playing, "mouse recapture click does not play gunshot audio")
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		actor._unhandled_input(click)
	else:
		print("MANUAL CHECK REQUIRED: headless display does not capture mouse; invoking weapon effects directly")
		actor._fire_active_weapon()
	check(actor.active_weapon.animation_play.current_animation == "Shot" and actor.active_weapon.muzzle_flash.visible, "original shot animation and muzzle flash still work")
	check(actor.active_weapon.revolver_sfx.playing, "accepted revolver shot plays its audio")
	actor.active_weapon.revolver_sfx.stop()
	actor.active_weapon.try_fire()
	check(not actor.active_weapon.revolver_sfx.playing, "shot rejected during recoil cannot trigger audio")
	await create_timer(0.15).timeout
	check(not actor.active_weapon.muzzle_flash.visible, "muzzle flash expires")
	main.multiplayer.multiplayer_peer = null
	main.free()

func test_launch_changes() -> void:
	await reset_player()
	player.velocity.z = -11.5
	Input.action_press("move_forward")
	Input.action_press("slide")
	await tick()
	check(player.velocity.z < -14.0, "slide boosts beyond sprint speed")
	Input.action_release("slide")
	await tick(20)
	check(player.velocity.z < -13.0, "ground movement carries slide excess speed")
	Input.action_press("slide")
	var before: float = player.velocity.z
	await tick()
	check(player.velocity.z >= before, "rapid slide cannot stack boosts")
	Input.action_press("jump")
	await tick()
	check(player.velocity.z < -13.0, "slide jump retains excess momentum")
	for pitch in [45.0, 89.0, -45.0]:
		await reset_player(Vector3(0, 8, 0))
		player.head.rotation.x = deg_to_rad(pitch)
		player.rotation.y = 0.7
		var aim: Vector3 = -player.camera.global_basis.z
		Input.action_press("move_forward")
		Input.action_press("dash")
		await tick()
		check(player.velocity.normalized().dot(aim) > 0.999 and absf(player.velocity.length()-23) < 0.01, "dash follows normalized camera aim at %.0f degrees" % pitch)
	await reset_player()
	player.head.rotation.x = deg_to_rad(89)
	Input.action_press("dash")
	await tick(12)
	check(player.velocity.y > 20 and player.position.y > 3, "upward dash preserves lift after burst")
	Input.action_press("jump")
	await tick()
	Input.action_release("jump")
	await tick()
	check(player.velocity.y > 20, "jump release does not cut inherited dash lift")
	await reset_player(Vector3(0, 20, 0))
	Input.action_press("dash")
	await tick(50)
	Input.action_release("dash")
	await tick()
	Input.action_press("dash")
	await tick()
	check(player.movement_state != player.MovementState.DASHING, "cooldown cannot grant unlimited airborne dashes")
	await tick(220)
	check(player.is_on_floor() and player.air_dash_available, "landing restores air dash")
	await reset_player(Vector3(0, 8, 0))
	player.velocity.z = -28
	Input.action_press("dash")
	await tick()
	check(player.velocity.length() >= 28.0, "dash activation does not cut faster incoming momentum")
	await tick(11)
	check(player._horizontal_velocity().length() > 27.9, "air dash preserves horizontal momentum without input")
	await reset_player()
	var roof := box(Vector3(0, 3, 0), Vector3(8, 0.1, 8))
	player.head.rotation.x = deg_to_rad(89)
	Input.action_press("dash")
	await tick(5)
	check(player.position.y < 1.16 and player.velocity.y <= 0 and player.movement_state != player.MovementState.DASHING, "ceiling collision terminates upward dash")
	roof.free()
	await reset_player(Vector3(0, 1, 0))
	player.head.rotation.x = deg_to_rad(-89)
	Input.action_press("dash")
	await tick(5)
	check(player.is_on_floor() and player.position.y >= -0.01, "downward dash collides safely with floor")

func test_crouch_and_strafe() -> void:
	await reset_player()
	Input.action_press("slide")
	await tick(10)
	check(player.is_crouched and absf(player.body_collision.shape.height - player.crouch_height) < 0.01, "held Ctrl lowers capsule while stationary")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await tick(30)
	check(absf(player._horizontal_velocity().length() - player.crouch_speed) < 0.01, "crouch walking stays slow even with sprint")
	Input.action_release("slide")
	await tick(2)
	check(not player.is_crouched, "release Ctrl stands in clear space")
	await reset_player()
	Input.action_press("slide")
	await tick()
	var roof := box(Vector3(0, 1.4, 0), Vector3(8, 0.2, 8))
	Input.action_release("slide")
	await tick(3)
	check(player.is_crouched, "crouch release cannot stand through ceiling")
	roof.free()
	await tick(2)
	check(not player.is_crouched, "blocked crouch stands once space clears")
	await reset_player()
	player.velocity.z = -11.5
	Input.action_press("slide")
	await tick(60)
	check(player.is_crouched and player.movement_state != player.MovementState.SLIDING, "holding Ctrl after slide expires stays crouched")
	for action in ["move_left", "move_right", "move_back"]:
		await reset_player(Vector3(0, 8, 0))
		player.rotation.y = 0.7
		player.head.rotation.x = deg_to_rad(65)
		var aim_before: Vector3 = -player.camera.global_basis.z
		var expected: Vector3 = player.global_basis.z if action == "move_back" else player.global_basis.x * (-1 if action == "move_left" else 1)
		Input.action_press(action)
		Input.action_press("dash")
		await tick()
		check(player.velocity.normalized().dot(expected) > 0.999 and absf(player.velocity.y) < 0.01, "pitched aim permits horizontal %s dash" % action)
		check((-player.camera.global_basis.z).is_equal_approx(aim_before), "directional dash does not rotate camera")
		await tick(4)
		check((player.movement_state == player.MovementState.DASHING) == (action != "move_back"), "sideways burst lasts longer than forward and backward burst")
	await reset_player(Vector3(0, 8, 0))
	player.head.rotation.x = deg_to_rad(45)
	Input.action_press("move_forward")
	Input.action_press("move_right")
	Input.action_press("dash")
	await tick()
	check(player.velocity.x > 0 and player.velocity.y > 0 and player.velocity.z < 0 and absf(player.velocity.length()-23) < 0.01, "forward diagonal dash combines strafe and upward aim without speed multiplication")
