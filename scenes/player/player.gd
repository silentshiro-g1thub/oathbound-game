extends CharacterBody3D

# MOVEMENT SETTINGS
@export var move_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var sprint_speed: float = 11.5

@export var ground_acceleration: float = 25.0
@export var ground_deceleration: float = 20.0

# VARIABLE JUMP HEIGHT SETITNGS
@export var short_hop_velocity: float = 2.5
@export var early_release_window: float = 0.12
@export var jump_gravity: float = 12.0 # Standard gravity while ascending
@export var fall_gravity: float = 18.0 # Harsher gravity while falling (for smoothness)
@export var jump_cut_multiplier: float = 0.4 # Lower value = sharper cut when buttong is released

# JUMP STATE VARIABLES
var jump_timer: float = 0.0
var jump_cut_applied: bool = false

# CAMERA CONSTANTS
const MIN_LOOK_ANGLE: float = -89.0
const MAX_LOOK_ANGLE: float = 89.0

@onready var head: Node3D = $Head

# INITIALIZATION
func _ready() -> void:
	# Capture mouse when the game launches
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
# MOUSE TRACKING AND INPUT EVENTS & EDGE CASES
func _unhandled_input(event: InputEvent) -> void:
	# Rotate player horizontally when mouse moves
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Rotate the head vertically when mouse moves
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		# Limits the camera from moving too far vertically
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(MIN_LOOK_ANGLE),
			deg_to_rad(MAX_LOOK_ANGLE)
		)
		
	# Release the mouse when cancel key is triggered
	if event.is_action_pressed("ui_cancellation"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Clicking the game window captures the mouse again
	if event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# GRAVITY CALCULATION
func calculate_gravity() -> float:
	return fall_gravity if velocity.y < 0 else jump_gravity

# MAIN PHYSICS CALCULATION
func _physics_process(delta: float) -> void:
	# Count the early release window using elapsed time
	if jump_timer > 0.0:
		jump_timer -= delta
	
	# Apply gravity whenever the player is on the air
	if not is_on_floor():
		velocity.y -= calculate_gravity() * delta
	
	# Begin a jump only when the player is on the ground
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		# Start the early release window for this jump
		jump_timer = early_release_window
		# Allow the jump-cut effect to be applied again
		jump_cut_applied = false
	
	# Reduce upward velocity naturally when the player releases jump
	if (
		Input.is_action_just_released("jump")
		and velocity.y > 0.0
		and not jump_cut_applied
	):
		# Early release limits upward velocity for a short hop
		if jump_timer > 0.0:
			velocity.y = minf(velocity.y, short_hop_velocity)
		# Later release scales the remaining upward velocity
		else:
			velocity.y *= jump_cut_multiplier
		
		# Mark the jump cut as complete
		jump_cut_applied = true
		
	# Read directional input and create a movement vector
	# Normalization prevents diagonal movement from being faster
	var input_dir := Input.get_vector(
		"move_left", "move_right",
		"move_forward", "move_back",
	)
	
	# Convert input relative to the player's facing direction
	# Makes forward movement follow the direction the player faces
	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()
	
	# Sprint only while the sprint action is held and the player is moving
	var current_speed : float = move_speed
	
	if Input.is_action_pressed("sprint") and not input_dir.is_zero_approx():
		current_speed = sprint_speed
	
	# Apply horizontal movement
	if not direction.is_zero_approx():
		# Accelerate in the given direction
		velocity.x = move_toward(
			velocity.x,
			direction.x * current_speed,
			ground_acceleration * delta
		)
		
		velocity.z = move_toward(
			velocity.z,
			direction.z * current_speed,
			ground_acceleration * delta
		)
	else: 
		# Gradually reduce horizontal velocity when no direction is pressed
		velocity.x = move_toward(
			velocity.x,
			0.0,
			ground_deceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			ground_deceleration * delta
		)
		
	print(
		"Sprint held: ", Input.is_action_pressed("sprint"),
		" | Target speed: ", current_speed,
		" | Actual horizontal speed: ",
		Vector2(velocity.x, velocity.z).length()
	)
	
	# Apply velocity and resolve collisions with the environment
	move_and_slide()
	
