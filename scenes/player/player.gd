extends CharacterBody3D

const DeveloperOverlay = preload("res://scenes/player/developer_overlay.gd")
const Dummy = preload("res://scenes/dummy.gd")
var dummy_counter: int = 0

@export_group("Locomotion")
@export var move_speed: float = 7.0
@export var jump_velocity: float = 8.5
@export var mouse_sensitivity: float = 0.002
@export var sprint_speed: float = 11.5

@export var ground_acceleration: float = 25.0
@export var ground_deceleration: float = 20.0
@export var ground_momentum_drag: float = 2.0
@export var air_acceleration: float = 7.0
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.12

@export_group("Slide")
@export var slide_min_speed: float = 8.0
@export var slide_entry_boost: float = 3.0
@export var slide_boost_cooldown: float = 1.0
@export var slide_duration: float = 0.85
@export var slide_friction: float = 4.0
@export var slide_stop_speed: float = 3.5
@export var slide_steering: float = 2.0
@export var crouch_height: float = 1.0
@export var crouch_speed: float = 3.5
@export var camera_height_speed: float = 8.0

@export_group("Dash")
@export var dash_speed: float = 14.5
@export var dash_duration: float = 0.08
@export var sideways_dash_duration: float = 0.12
@export var dash_cooldown: float = 0.5
@export var dash_follows_aim: bool = true

@export_group("Double Jump")
@export var double_jump_velocity: float = 8.5

@export_group("Variable Jump")
@export var short_hop_velocity: float = 2.5
@export var early_release_window: float = 0.12
@export var jump_gravity: float = 12.0
@export var fall_gravity: float = 18.0
@export var jump_cut_multiplier: float = 0.4

enum MovementState { GROUNDED, SPRINTING, AIRBORNE, SLIDING, DASHING }

var movement_state: MovementState = MovementState.AIRBORNE
var coyote_remaining: float = 0.0
var jump_buffer_remaining: float = 0.0
var controls_active: bool = true

var slide_remaining: float = 0.0
var slide_boost_cooldown_remaining: float = 0.0
var is_crouched: bool = false

var standing_height: float
var standing_shape_position: Vector3
var standing_head_height: float
var standing_shape: CapsuleShape3D

var dash_remaining: float = 0.0
var dash_cooldown_remaining: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var dash_launch_speed: float = 0.0
var air_dash_available: bool = true

var extra_jumps_remaining: int = 1

var jump_timer: float = 0.0
var jump_cut_applied: bool = true

const MIN_LOOK_ANGLE: float = -89.0
const MAX_LOOK_ANGLE: float = 89.0

const BOB_FREQ = 2.0
const BOB_AMP = 0.08

var t_bob = 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var animation_play: AnimationPlayer = get_node_or_null("Head/Camera3D/Manurhin MR93/AnimationPlayer")
@onready var muzzle_flash: Node3D = get_node_or_null("Head/Camera3D/Manurhin MR93/Node3D")

#Guns
@onready var crosshair: Control = get_node_or_null("../Node2D/TextureRect")
@onready var crosshair_hit: Control = get_node_or_null("../Node2D/TextureRect2")

func _enter_tree():
	
	set_multiplayer_authority(str(name).to_int())
	


@export_node_path("Node") var active_weapon_path: NodePath
@onready var active_weapon: Node = get_node_or_null(active_weapon_path) if not active_weapon_path.is_empty() else null


## Keep remote players visual-only; initialize the local player's camera, collision, controls, and HUD.
func _ready() -> void:
	if not is_multiplayer_authority():
		# Remote copies must not collide with or simulate alongside the local player.
		collision_layer = 0
		collision_mask = 0
		if muzzle_flash:
			muzzle_flash.visible = false
		set_physics_process(false)
		return

	camera.current = true

	assert(body_collision.shape is CapsuleShape3D, "Movement requires a CapsuleShape3D")
	body_collision.shape = body_collision.shape.duplicate()
	standing_shape = body_collision.shape.duplicate()
	standing_height = standing_shape.height
	standing_shape_position = body_collision.position
	standing_head_height = head.position.y
	crouch_height = clampf(crouch_height, standing_shape.radius * 2.0, standing_height)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if OS.is_debug_build():
		var developer_overlay := DeveloperOverlay.new()
		developer_overlay.name = "DeveloperOverlay"
		add_child(developer_overlay)


## Release gameplay controls when the game loses focus.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_controls()


## Release held actions and show the mouse so input cannot remain stuck.
func _release_controls() -> void:
	controls_active = false
	jump_buffer_remaining = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for action in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "slide", "dash", "Shoot"]:
		Input.action_release(action)


## Read a held action only while gameplay controls are active.
func _action_pressed(action: StringName) -> bool:
	return controls_active and Input.is_action_pressed(action)


## Read a new button press only while gameplay controls are active.
func _action_just_pressed(action: StringName) -> bool:
	return controls_active and Input.is_action_just_pressed(action)


## Handle mouse capture, aiming, and firing; the recapture click never shoots.
func _unhandled_input(event: InputEvent) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if not is_multiplayer_authority(): return
	if event.is_action_pressed("ui_cancellation"):
		_release_controls()
		return
	# Debug: F3 + 1 spawns a one-hit dummy where you stand (replicated to peers).
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_1 and Input.is_physical_key_pressed(KEY_F3):
			spawn_dummy.rpc(_dummy_spawn_position())
			return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		controls_active = true
		return

	if not controls_active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(MIN_LOOK_ANGLE),
			deg_to_rad(MAX_LOOK_ANGLE)
		)
	if event.is_action_pressed("Shoot") and not _shot_anim_active():
		play_shoot_effects.rpc()
		_fire_hitscan()

	if event.is_action_pressed("Shoot"):
		_fire_active_weapon()


## Forward a shot only when the equipped node has a valid weapon script.
func _fire_active_weapon() -> void:
	if is_instance_valid(active_weapon) and active_weapon.has_method("try_fire"):
		active_weapon.try_fire()


## Use stronger gravity while falling than while rising.
func calculate_gravity() -> float:
	return fall_gravity if velocity.y < 0 else jump_gravity


## Read input and choose one movement mode, with exactly one collision move per tick.
func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer(): return
	if not is_multiplayer_authority(): return

	_update_movement_timers(delta)

	## Handles headbobbing
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)

	var input_dir := Vector2.ZERO

	if controls_active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var direction := global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.limit_length()

	var sprinting := _action_pressed("sprint") and not input_dir.is_zero_approx()
	_update_crouch_and_slide()

	if (
		_action_just_pressed("dash")
		and dash_cooldown_remaining <= 0.0
		and not is_crouched
		and (is_on_floor() or air_dash_available)
	):
		_start_dash(direction)

	if movement_state == MovementState.DASHING:
		_move_dash(delta)
		return

	_update_jump(delta)

	if movement_state == MovementState.SLIDING:
		_move_slide(direction, delta)
	else:
		_move_horizontal(direction, sprinting, delta)

	move_and_slide()

	if movement_state == MovementState.SLIDING and not is_on_floor():
		movement_state = MovementState.AIRBORNE

	if movement_state != MovementState.SLIDING:
		movement_state = MovementState.AIRBORNE
		if is_on_floor():
			movement_state = MovementState.SPRINTING if sprinting and not is_crouched else MovementState.GROUNDED


## Advance cooldowns, refresh airborne abilities on landing, and buffer jump presses.
func _update_movement_timers(delta: float) -> void:
	jump_timer = maxf(0.0, jump_timer - delta)
	jump_buffer_remaining = maxf(0.0, jump_buffer_remaining - delta)
	coyote_remaining = maxf(0.0, coyote_remaining - delta)
	dash_cooldown_remaining = maxf(0.0, dash_cooldown_remaining - delta)
	slide_boost_cooldown_remaining = maxf(0.0, slide_boost_cooldown_remaining - delta)

	if is_on_floor():
		coyote_remaining = coyote_time
		extra_jumps_remaining = 1
		air_dash_available = true

	if _action_just_pressed("jump"):
		jump_buffer_remaining = jump_buffer_time


## Handle held crouch and slide entry, limiting repeat boosts and checking standing clearance.
func _update_crouch_and_slide() -> void:
	if (
		is_crouched
		and not _action_pressed("slide")
		and movement_state != MovementState.SLIDING
		and _can_stand()
	):
		_set_crouched(false)

	if (
		_action_just_pressed("slide")
		and movement_state != MovementState.DASHING
		and is_on_floor()
		and _horizontal_velocity().length() >= slide_min_speed
	):
		movement_state = MovementState.SLIDING
		slide_remaining = slide_duration
		if slide_boost_cooldown_remaining <= 0.0:
			var speed := _horizontal_velocity().length()
			var boosted := maxf(speed, minf(speed + slide_entry_boost, sprint_speed + slide_entry_boost))
			_set_horizontal(_horizontal_velocity().normalized() * boosted)
			slide_boost_cooldown_remaining = slide_boost_cooldown
		_set_crouched(true)

	if (
		_action_pressed("slide")
		and is_on_floor()
		and movement_state != MovementState.DASHING
		and not is_crouched
	):
		_set_crouched(true)


## Apply gravity, consume a buffered ground or extra jump, and handle early release.
func _update_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= calculate_gravity() * delta

	if jump_buffer_remaining > 0.0:
		if is_on_floor() or coyote_remaining > 0.0:
			_begin_jump(jump_velocity)
		elif extra_jumps_remaining > 0:
			extra_jumps_remaining -= 1
			_begin_jump(double_jump_velocity)
	_apply_jump_cut()


## Return the camera bob offset for the current movement phase.
func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ) * BOB_AMP
	return pos


## Start a jump without reducing stronger inherited lift, then consume the jump buffer.
func _begin_jump(upward_speed: float) -> void:
	movement_state = MovementState.AIRBORNE

	if is_crouched and _can_stand():
		_set_crouched(false)

	var inherited_lift := velocity.y > upward_speed
	velocity.y = maxf(velocity.y, upward_speed)
	jump_timer = early_release_window
	jump_cut_applied = inherited_lift
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0


## Shorten released jumps, including buffered ones, without cutting inherited launch momentum.
func _apply_jump_cut() -> void:
	if not _action_pressed("jump") and velocity.y > 0.0 and not jump_cut_applied:
		if jump_timer > 0.0:
			velocity.y = minf(velocity.y, short_hop_velocity)
		else:
			velocity.y *= jump_cut_multiplier
		jump_cut_applied = true


## Return horizontal motion without the vertical component.
func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


## Replace horizontal motion while leaving vertical velocity unchanged.
func _set_horizontal(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z


## Apply walking, sprinting, or crouching movement while preserving earned ground and air momentum.
func _move_horizontal(direction: Vector3, sprinting: bool, delta: float) -> void:
	var horizontal := _horizontal_velocity()

	var target_speed := sprint_speed if sprinting else move_speed

	if is_crouched:
		target_speed = crouch_speed

	if is_on_floor() and velocity.y <= 0.0:
		var acceleration := ground_deceleration if direction.is_zero_approx() else ground_acceleration
		if not is_crouched and not direction.is_zero_approx() and direction.dot(horizontal) > 0.0:
			target_speed = maxf(target_speed, horizontal.length() - ground_momentum_drag * delta)
		horizontal = horizontal.move_toward(direction * target_speed, acceleration * delta)
	elif not direction.is_zero_approx():
		var speed_limit := maxf(target_speed, horizontal.length())
		horizontal = horizontal.move_toward(direction * speed_limit, air_acceleration * delta)
	_set_horizontal(horizontal)


## Resize the capsule and lower the camera immediately when crouching.
func _set_crouched(value: bool) -> void:
	is_crouched = value

	var capsule := body_collision.shape as CapsuleShape3D
	capsule.height = crouch_height if value else standing_height
	body_collision.position = standing_shape_position - Vector3.UP * (standing_height - capsule.height) * 0.5

	if value:
		head.position.y = standing_head_height - (standing_height - crouch_height)


## Check whether the standing capsule fits without hitting overhead geometry.
func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = global_transform
	query.transform.origin = to_global(standing_shape_position) + Vector3.UP * 0.02
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Apply slide friction and limited steering, then end the slide when needed.
func _move_slide(direction: Vector3, delta: float) -> void:
	var local_input := global_basis.inverse() * direction
	slide_remaining -= delta

	var horizontal := _horizontal_velocity()

	var speed := maxf(0.0, horizontal.length() - slide_friction * delta)

	if not direction.is_zero_approx():
		horizontal = horizontal.move_toward(direction * speed, slide_steering * delta)
	_set_horizontal(horizontal.normalized() * speed)

	if slide_remaining <= 0.0 or not _action_pressed("slide") or speed < slide_stop_speed:
		movement_state = MovementState.GROUNDED if is_on_floor() else MovementState.AIRBORNE


## Lock a camera-relative or flat dash direction, preserve faster speed, and consume the dash charge.
func _start_dash(direction: Vector3) -> void:
	var local_input := global_basis.inverse() * direction

	if dash_follows_aim:
		var local_direction := local_input
		if direction.is_zero_approx():
			dash_direction = -camera.global_basis.z.normalized()
		else:
			var forward := -camera.global_basis.z if local_direction.z < 0.0 else -global_basis.z
			dash_direction = (global_basis.x * local_direction.x - forward * local_direction.z).normalized()
		dash_launch_speed = maxf(dash_speed, velocity.length())
		jump_cut_applied = true
		jump_timer = 0.0
	else:
		dash_direction = direction.normalized() if not direction.is_zero_approx() else -global_basis.z.normalized()
		dash_direction.y = 0.0
		dash_direction = dash_direction.normalized()
		dash_launch_speed = maxf(dash_speed, velocity.length())
	air_dash_available = false
	jump_buffer_remaining = 0.0
	dash_remaining = dash_duration
	dash_remaining = lerpf(dash_duration, sideways_dash_duration, absf(local_input.x))
	dash_cooldown_remaining = dash_cooldown
	coyote_remaining = 0.0
	movement_state = MovementState.DASHING


## Move the dash once, stop on blocking collisions or timeout, and preserve exit momentum.
func _move_dash(delta: float) -> void:
	if dash_follows_aim:
		velocity = dash_direction * dash_launch_speed
	else:
		_set_horizontal(dash_direction * dash_launch_speed)
		velocity.y -= calculate_gravity() * delta if not is_on_floor() else 0.0

	move_and_slide()
	dash_remaining -= delta

	var blocked := false

	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		var support := normal.y >= cos(floor_max_angle)
		if dash_direction.dot(normal) < -0.1 and (not support or dash_direction.y < -0.05):
			blocked = true

	if blocked or dash_remaining <= 0.0:
		movement_state = MovementState.GROUNDED if is_on_floor() else MovementState.AIRBORNE


## Smooth the eye height for standing and crouching without changing movement velocity.
func _process(delta: float) -> void:
	# Post-disconnect frames: the peer is gone but freed nodes still tick once.
	if not multiplayer.has_multiplayer_peer(): return
	if is_multiplayer_authority():
		var eye_height := standing_head_height - (standing_height - crouch_height) if is_crouched else standing_head_height
		head.position.y = move_toward(head.position.y, eye_height, camera_height_speed * delta)
	# Weapon presentation never writes movement velocity. Remote copies stay
	# processable so replicated Shot/idle animations still update.
	if _shot_anim_active():
		return
	var animation := "move" if is_on_floor() and _horizontal_velocity().length() > 0.1 else "Idle"
	if animation_play.current_animation != animation:
		animation_play.play(animation)

func _shot_anim_active() -> bool:
	# A finished non-looping animation keeps its name in current_animation;
	# is_playing() is the only reliable "still shooting" check.
	return animation_play != null and animation_play.is_playing() and animation_play.current_animation == "Shot"

const GUN_RANGE: float = 10000.0

func _fire_hitscan() -> void:
	# One-hit kill on debug dummies; ignored against everything else.
	var origin := camera.global_position
	var target := origin - camera.global_basis.z * GUN_RANGE
	var query := PhysicsRayQueryParameters3D.create(origin, target, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.has_method("die"):
		hit.collider.die.rpc()

func _dummy_spawn_position() -> Vector3:
	# Slightly in front: a dummy spawned inside your own capsule shoves you around.
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	return global_position + forward.normalized() * 1.5

@rpc("authority", "call_local")
func spawn_dummy(spawn_position: Vector3) -> void:
	var dummy := Dummy.new()
	# Peer-prefixed names never collide between players, and stay deterministic so
	# every peer's copy sits at the same node path for die.rpc().
	dummy.name = "%s_Dummy%d" % [name, dummy_counter]
	dummy_counter += 1
	get_parent().add_child(dummy)
	dummy.global_position = spawn_position

@rpc("authority", "call_local")
func play_shoot_effects() -> void:
	if not animation_play:
		return
	animation_play.stop()
	animation_play.play("Shot")
	# Direct call: this already runs on every peer, and a nested .rpc() from a
	# remote copy would be rejected (only the authority may call RPCs here).
	show_muzzle_flash()

func show_muzzle_flash() -> void:
	if not muzzle_flash:
		return
	muzzle_flash.visible = true
	muzzle_flash.rotation.z = randf_range(0.0, TAU) # random spin so it looks different each shot
	await get_tree().create_timer(0.08).timeout
	muzzle_flash.visible = false
