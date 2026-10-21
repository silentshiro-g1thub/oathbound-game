extends Node3D
## Bagyo rifle. Handling follows an M14 carbine: low-ready hip fire,
## a short sight picture, and a muzzle-down sprint. The mesh itself has no clips.

const GUNSHOT = preload("res://assets/audio/gunshot.mp3")

const HIP_POSITION := Vector3(0.18, -0.19, -0.34)
const HIP_ROTATION := Vector3(deg_to_rad(-1.0), deg_to_rad(-85.0), deg_to_rad(-1.0))
const SPRINT_POSITION := Vector3(0.08, -0.25, -0.28)
const SPRINT_ROTATION := Vector3(deg_to_rad(-14.0), deg_to_rad(-42.0), deg_to_rad(-18.0))
const ADS_POSITION := Vector3(0.0, -0.212, -0.33)
const ADS_ROTATION := Vector3(0.0, deg_to_rad(-90.0), deg_to_rad(-4.5))

var player: CharacterBody3D
var _model: Node3D
var _muzzle: OmniLight3D
var _shot: AudioStreamPlayer3D
var _pose_position := HIP_POSITION
var _pose_rotation := HIP_ROTATION
var _recoil_remaining := 0.0
var _aiming := false


func _ready() -> void:
	var cursor: Node = self
	while cursor and not (cursor is CharacterBody3D):
		cursor = cursor.get_parent()
	player = cursor as CharacterBody3D
	_model = get_node_or_null("Model") as Node3D
	_muzzle = get_node_or_null("Model/Muzzle") as OmniLight3D
	_shot = get_node_or_null("Gunshot") as AudioStreamPlayer3D
	if _model:
		_model.scale = Vector3.ONE * 1.9
		_model.position = HIP_POSITION
		_model.rotation = HIP_ROTATION
	if _muzzle:
		_muzzle.visible = false
	if _shot:
		_shot.stream = GUNSHOT
		# No separate M14 recording is in the project. A lower, slower pitch
		# matches the heavier carbine report better than the revolver crack.
		_shot.pitch_scale = 0.58
		_shot.volume_db = 3.0


func is_rifle() -> bool:
	return true


func set_equipped(equipped: bool) -> void:
	visible = equipped
	if not equipped:
		_aiming = false
		_recoil_remaining = 0.0
		if _muzzle:
			_muzzle.visible = false


func is_recoiling() -> bool:
	return _recoil_remaining > 0.0


func play_fire_effects() -> bool:
	if not visible or is_recoiling() or _sprinting():
		return false
	_recoil_remaining = 0.09 if _aiming else 0.14
	if _shot and _shot.stream:
		_shot.play()
	_flash_muzzle()
	return true


func try_fire() -> bool:
	return play_fire_effects()


func _process(delta: float) -> void:
	if _model == null or player == null or not visible:
		return
	var sprinting := _sprinting()
	_aiming = (
		not sprinting
		and player.controls_active
		and not player.weapon_menu_open
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	)
	player.viewmodel_follow = 0.22 if _aiming else 1.0
	var target_position := HIP_POSITION
	var target_rotation := HIP_ROTATION
	if sprinting:
		target_position = SPRINT_POSITION
		target_rotation = SPRINT_ROTATION
	elif _aiming:
		target_position = ADS_POSITION
		target_rotation = ADS_ROTATION
	var blend := 1.0 - exp(-12.0 * delta)
	_pose_position = _pose_position.lerp(target_position, blend)
	_pose_rotation = _pose_rotation.lerp(target_rotation, blend)
	var kick := 0.0
	if _recoil_remaining > 0.0:
		var duration := 0.09 if _aiming else 0.14
		_recoil_remaining = maxf(0.0, _recoil_remaining - delta)
		kick = sin(clampf(1.0 - _recoil_remaining / duration, 0.0, 1.0) * PI)
		if _aiming:
			kick *= 0.35
	_model.position = _pose_position + Vector3(0.0, 0.012 * kick, 0.045 * kick)
	_model.rotation = _pose_rotation + Vector3(0.0, 0.0, -0.11 * kick)


func _sprinting() -> bool:
	if player == null:
		return false
	return player.movement_state == player.MovementState.SPRINTING


func _flash_muzzle() -> void:
	if _muzzle == null:
		return
	_muzzle.visible = true
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(_muzzle):
		_muzzle.visible = false
