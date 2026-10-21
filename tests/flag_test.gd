extends SceneTree

const Rules = preload("res://scenes/flag/flag_rules.gd")
const Flag = preload("res://scenes/flag/flag.gd")
const MatchScene = preload("res://scenes/flag/flag_match.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")

var failures := 0
var checks := 0
var world: Node3D
var flag_match: Node3D
var red: CharacterBody3D
var blue: CharacterBody3D


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	_check_throw_math()
	world = Node3D.new()
	root.add_child(world)
	_add_floor()
	flag_match = Node3D.new()
	flag_match.set_script(MatchScene)
	flag_match.name = "FlagMatch"
	world.add_child(flag_match)
	red = _spawn_player("1", Rules.Team.RED, Rules.RED_HOME + Vector3(9.0, 0.0, 0.0))
	blue = _spawn_player("2", Rules.Team.BLUE, Rules.BLUE_HOME + Vector3(-5.0, 0.0, 0.0))
	await physics_frame
	await physics_frame
	flag_match.set_physics_process(false)
	flag_match.reset_flags()
	red.health = 80
	blue.health = 80
	red.position = Rules.RED_HOME + Vector3(9.0, 0.0, 0.0)
	blue.position = Rules.BLUE_HOME + Vector3(-5.0, 0.0, 0.0)

	flag_match.simulate(1.0)
	check(red.health == 100, "red flag heals a player inside the 10m zone")
	check(blue.health == 100, "blue flag heals its own side the same way")
	var outside_health := 40
	red.health = outside_health
	red.position = Rules.RED_HOME + Vector3(10.5, 0.0, 0.0)
	blue.position = Vector3(0.0, Rules.BLUE_HOME.y, 40.0)
	flag_match.simulate(1.0)
	check(red.health == outside_health, "11m from the flag is outside the heal zone")

	red.health = 200
	red.position = Rules.RED_HOME + Vector3(3.0, 0.0, 0.0)
	flag_match.simulate(0.05)
	check(flag_match.flag_for(Rules.Team.RED).state == Flag.State.HOME, "standing 3m away does not pick the flag up")
	red.position = Rules.RED_HOME
	blue.position = Rules.RED_HOME
	flag_match.simulate(0.05)
	var red_flag: Node3D = flag_match.flag_for(Rules.Team.RED)
	check(red_flag.state == Flag.State.CARRIED and red_flag.carrier_peer_id == 1, "walking onto a flag picks it up")
	check(is_equal_approx(red.flag_speed_scale, Rules.SPEED_SCALE), "the carrier gets the speed buff")
	red.velocity = Vector3.ZERO
	red._move_horizontal(Vector3(0.0, 0.0, -1.0), false, 5.0)
	check(absf(red._horizontal_velocity().length() - red.move_speed * Rules.SPEED_SCALE) < 0.05, "walk speed uses the flag buff")
	red.velocity = Vector3.ZERO
	check(is_equal_approx(blue.flag_speed_scale, 1.0), "the other player does not get the buff")
	check(flag_match.flag_for(Rules.Team.BLUE).state == Flag.State.HOME, "a second flag stays put while one is held")

	red.head.rotation.x = deg_to_rad(70.0)
	red.rotation.y = -PI * 0.5
	var aim: Vector3 = -red.camera.global_basis.z
	var preview: PackedVector3Array = flag_match.throw_preview_points(Rules.carry_position(red), Rules.throw_velocity(aim, 1.0))
	check(preview.size() > 4 and preview[0].distance_to(Rules.carry_position(red)) < 0.05, "the throw preview traces the arc from the flag")
	check(flag_match.throw_carried_flag(red), "the carrier can throw the held flag")
	check(red_flag.state == Flag.State.FLIGHT and red_flag.carrier_peer_id == 0, "a throw leaves the hands")
	check(red_flag.velocity.normalized().dot(aim.normalized()) > 0.999, "throw follows the camera, including look pitch")
	check(absf(red_flag.velocity.length() - Rules.THROW_SPEED) < 0.05, "a full throw uses the max speed")
	check(is_equal_approx(red.flag_speed_scale, 1.0), "throwing clears the speed buff")

	var landed := false
	for _i in 120:
		flag_match.simulate(0.05)
		if red_flag.state == Flag.State.DROPPED:
			landed = true
			break
	check(landed and absf(red_flag.global_position.y + 0.45) < 0.15, "a thrown flag lands and can be picked up again")
	check(red_flag.global_position.x > Rules.RED_HOME.x, "the landing is ahead of where it was thrown")

	red.position = red_flag.global_position
	flag_match.simulate(0.05)
	check(red_flag.state == Flag.State.CARRIED, "a landed flag can be picked up again")
	var dropped_at := red.global_position
	red.mark_defeated()
	check(red.health == 0, "defeat is recorded on the carrier")
	check(red_flag.state == Flag.State.DROPPED and red_flag.carrier_peer_id == 0, "defeat drops the held flag")
	check(red_flag.global_position.distance_to(Vector3(dropped_at.x, red_flag.global_position.y, dropped_at.z)) < 1.0, "the dropped flag stays where the carrier was")
	check(is_equal_approx(red.flag_speed_scale, 1.0), "defeat clears the speed buff")
	var defeated_health: int = red.health
	flag_match.simulate(1.0)
	check(red.health == defeated_health, "the heal zone does not revive a defeated player")

	print("FLAG TESTS: %d checks, %d failures" % [checks, failures])
	world.free()
	quit(1 if failures else 0)


func _check_throw_math() -> void:
	var aim := Vector3(0.0, 8.0, -2.0)
	var velocity := Rules.throw_velocity(aim)
	check(velocity.is_equal_approx(aim.normalized() * Rules.THROW_MAX_SPEED), "throw follows the camera direction")
	check(absf(velocity.length() - Rules.THROW_MAX_SPEED) < 0.01, "a full charge uses the max throw speed")
	var soft := Rules.throw_velocity(aim, 0.0)
	check(absf(soft.length() - Rules.THROW_MIN_SPEED) < 0.01, "a tap uses the minimum throw speed")
	check(soft.normalized().is_equal_approx(velocity.normalized()), "charge changes speed and leaves the aim direction")
	check(velocity.y > 0.0 and velocity.z < 0.0, "an upward camera aim throws upward")
	var step: Dictionary = Rules.step_flight(Vector3.ZERO, velocity, 1.0 / 60.0)
	check(step.position.y > 0.0 and step.velocity.y < velocity.y, "flight rises on the first step and gravity pulls it down")
	var tossed := Vector3(Rules.THROW_MAX_SPEED, Rules.THROW_MAX_SPEED * 0.55, 0.0)
	var spot := Vector3.ZERO
	var peak := 0.0
	for _i in 90:
		var flight: Dictionary = Rules.step_flight(spot, tossed, 1.0 / 60.0)
		spot = flight.position
		tossed = flight.velocity
		peak = maxf(peak, spot.y)
	check(peak > 2.0 and spot.y < peak - 1.0 and spot.x > 8.0, "a throw climbs, hangs, then falls in an arc")
	check(Vector3(tossed.x, 0.0, tossed.z).length() > Rules.THROW_MAX_SPEED * 0.85, "air barely slows the throw, like a baseball")
	var bounce: Dictionary = Rules.land(Vector3(2.0, -8.0, 0.0), Vector3.UP)
	check(not bounce.rolling and bounce.velocity.y > 2.0, "a hard hit bounces back up")
	var roll: Dictionary = Rules.land(Vector3(3.0, -0.3, 0.0), Vector3.UP)
	check(roll.rolling and absf(roll.velocity.y) < 0.01, "a soft hit rolls instead of bouncing")


func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(0.0, -0.5, 0.0)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 1.0, 80.0)
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape_node)
	world.add_child(body)


func _spawn_player(peer_name: String, team: int, at: Vector3) -> CharacterBody3D:
	var player := PlayerScene.instantiate()
	player.name = peer_name
	player.team = team
	player.position = at
	world.add_child(player)
	player.set_physics_process(false)
	return player
