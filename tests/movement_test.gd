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
	await test_wall_run()
	await test_wall_jump()
	await test_double_jump()
	await test_edges()
	await test_physics_rates()
	await test_launch_changes()
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
	check(not player.is_crouched, "slide rejects insufficient momentum")
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
	await reset_player()
	player.dash_follows_aim = false
	Input.action_press("dash")
	await tick()
	check(player.movement_state == player.MovementState.DASHING and player.velocity.z < -19.9, "empty dash input defaults to facing forward")
	Input.action_press("move_back")
	await tick(2)
	check(player.velocity.z < -19.9, "ordinary movement cannot overwrite dash")
	await tick(10)
	check(player.movement_state != player.MovementState.DASHING and player._horizontal_velocity().length() > 18.0, "dash expires and preserves exit momentum")
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

func test_wall_run() -> void:
	var wall := box(Vector3(0.85, 7, 0), Vector3(0.5, 14, 100))
	await reset_player(Vector3(0, 6, 0))
	player.velocity = Vector3(0, -3, -10)
	Input.action_press("move_forward")
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "unmarked props cannot trigger wall run")
	wall.add_to_group("wall_runnable")
	await tick()
	check(player.movement_state == player.MovementState.WALL_RUNNING, "eligible airborne movement starts on marked side wall")
	check(player.velocity.y >= -2.01, "wall run limits falling speed")
	await tick(80)
	check(player.movement_state != player.MovementState.WALL_RUNNING and player.wall_budget_remaining <= 0.0, "airtime budget prevents indefinite wall run or reattachment")
	await reset_player(Vector3(0, 6, 0))
	player.velocity.z = -10
	Input.action_press("move_forward")
	await tick()
	wall.position.x = 4
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "wall gap ends run")
	wall.position.x = 0.85
	await reset_player(Vector3(0, 6, 0))
	player.velocity.z = -10
	Input.action_press("move_forward")
	Input.action_press("dash")
	await tick(12)
	check(player.movement_state == player.MovementState.WALL_RUNNING, "dash can transition to eligible wall run")
	Input.action_release("move_forward")
	Input.action_press("move_left")
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "steering away detaches from wall")
	wall.free()

func test_wall_jump() -> void:
	var wall := box(Vector3(0.85, 7, 0), Vector3(0.5, 14, 100))
	wall.add_to_group("wall_runnable")
	await reset_player(Vector3(0, 6, 0))
	player.velocity.z = -10
	Input.action_press("move_forward")
	await tick()
	Input.action_press("jump")
	await tick()
	check(player.velocity.y > 5.0 and player.velocity.x < -6.5, "wall jump launches up and away")
	check(player.velocity.z < -9.0, "wall jump retains capped tangential momentum")
	check(player.movement_state == player.MovementState.AIRBORNE, "wall jump exits wall run")
	check(player.extra_jumps_remaining == 1, "wall jump preserves available extra jump")
	Input.action_release("jump")
	await tick()
	Input.action_press("jump")
	await tick()
	check(player.extra_jumps_remaining == 0 and player.velocity.y > 4.0, "wall jump can transition to double jump")
	await tick(16)
	player.position.x = 0.0
	player.velocity = Vector3(0, 0, -10)
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "same-facing wall cannot be reused after wall jump")
	wall.free()

func test_double_jump() -> void:
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
	var wall := box(Vector3(0.85, 7, 0), Vector3(0.5, 14, 100))
	wall.add_to_group("wall_runnable")
	await reset_player(Vector3(0, 6, 0))
	player.extra_jumps_remaining = 0
	player.velocity.z = -10
	Input.action_press("move_forward")
	await tick()
	Input.action_press("jump")
	await tick()
	check(player.velocity.y > 5 and player.extra_jumps_remaining == 0, "wall jump works after extra jump is spent and does not refill it")
	wall.free()

func test_edges() -> void:
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
	var wall := box(Vector3(0.85, 7, 0), Vector3(0.5, 14, 100))
	wall.add_to_group("wall_runnable")
	await reset_player(Vector3(0, 6, 0))
	player.velocity.z = -3
	Input.action_press("move_forward")
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "wall run rejects insufficient speed")
	player.velocity = Vector3(10, 0, 0)
	Input.action_release("move_forward")
	Input.action_press("move_right")
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "head-on approach does not attach to wall")
	wall.free()
	var steep_surface := box(Vector3(0.8, 7, 0), Vector3(0.5, 14, 100))
	steep_surface.rotation.z = deg_to_rad(35)
	steep_surface.add_to_group("wall_runnable")
	await reset_player(Vector3(0, 6, 0))
	player.velocity.z = -10
	Input.action_press("move_forward")
	await tick()
	check(player.movement_state != player.MovementState.WALL_RUNNING, "tilted surface does not count as vertical wall")
	steep_surface.free()
	var side := box(Vector3(0.85, 7, 0), Vector3(0.5, 14, 100))
	side.add_to_group("wall_runnable")
	var corner := box(Vector3(0, 7, -2), Vector3(10, 14, 0.2))
	corner.add_to_group("wall_runnable")
	await reset_player(Vector3(0, 6, 0))
	player.velocity.z = -10
	Input.action_press("move_forward")
	await tick(15)
	check(player.movement_state != player.MovementState.WALL_RUNNING and player.position.z > -1.6, "sharp blocking corner ends wall run without snapping around it")
	side.free()
	corner.free()
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
	var actor := main.get_node("Player") as CharacterBody3D
	actor.set_physics_process(false)
	check(actor.animation_play != null and actor.muzzle_flash != null and actor.aim_ray != null, "main scene retains weapon and aim node references")
	check(actor.crosshair.mouse_filter == Control.MOUSE_FILTER_IGNORE and actor.crosshair_hit.mouse_filter == Control.MOUSE_FILTER_IGNORE, "crosshair UI cannot swallow shooting or recapture clicks")
	check(actor.get_node("Head/Camera3D").rotation.is_zero_approx(), "camera mount is aligned with movement yaw and head pitch")
	actor._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not actor.controls_active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss releases mouse and controls")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	actor._unhandled_input(click)
	print("Headless mouse mode after recapture: ", Input.mouse_mode, "; click matches Shoot: ", click.is_action_pressed("Shoot"))
	check(actor.controls_active and actor.animation_play.current_animation != "Shot", "recapture click does not shoot")
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		actor._unhandled_input(click)
	else:
		print("MANUAL CHECK REQUIRED: headless display does not capture mouse; invoking weapon effects directly")
		actor.play_shoot_effects()
	check(actor.animation_play.current_animation == "Shot" and actor.muzzle_flash.visible, "original shot animation and muzzle flash still work")
	await create_timer(0.15).timeout
	check(not actor.muzzle_flash.visible, "muzzle flash expires")
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
		Input.action_press("move_back")
		Input.action_press("dash")
		await tick()
		check(player.velocity.normalized().dot(aim) > 0.999 and absf(player.velocity.length()-20) < 0.01, "dash follows normalized camera aim at %.0f degrees" % pitch)
	await reset_player()
	player.head.rotation.x = deg_to_rad(89)
	Input.action_press("dash")
	await tick(12)
	check(player.velocity.y > 19 and player.position.y > 3, "upward dash launches and retains lift after exit")
	Input.action_press("jump")
	await tick()
	Input.action_release("jump")
	await tick()
	check(player.velocity.y > 18, "jump and release do not cut inherited dash lift")
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
	await tick(12)
	check(player.velocity.z < -27.9, "dash retains speed above its base speed")
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
