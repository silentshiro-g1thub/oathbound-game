extends CharacterBody3D

@export var move_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

@export var short_hop_velocity: float = 2.5
@export var early_release_window: float = 0.12
@export var jump_gravity: float = 12.0 # Standard gravity while ascending
@export var fall_gravity: float = 18.0 # Harsher gravity while falling (for smoothness)
@export var jump_cut_multiplier: float = 0.4 # Lower value = sharper cut when buttong is released

var jump_timer: float = 0.0
var jump_cut_applied: bool = false

@onready var head: Node3D = $Head

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)
		
	if event.is_action_pressed("ui_cancellation"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func calculate_gravity() -> float:
	return fall_gravity if velocity.y < 0 else jump_gravity

func _physics_process(delta: float) -> void:
	if jump_timer > 0.0:
		jump_timer -= delta
		
	if not is_on_floor():
		velocity.y -= calculate_gravity() * delta
	
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		jump_timer = early_release_window
		jump_cut_applied = false
		
	if (
		Input.is_action_just_released("jump")
		and velocity.y > 0.0
		and not jump_cut_applied
	):
		if jump_timer > 0.0:
			velocity.y = minf(velocity.y, short_hop_velocity)
		else:
			velocity.y *= jump_cut_multiplier
		
		jump_cut_applied = true
		
	var input_dir := Input.get_vector(
		"move_left", "move_right",
		"move_forward", "move_back",
	)
	
	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()
	
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else: 
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
	
	move_and_slide()
	
