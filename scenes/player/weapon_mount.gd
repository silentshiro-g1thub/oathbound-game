extends Node3D
## Keeps the held weapon in view, but lets it trail the camera instead of locking to it.

const CameraLag = preload("res://scenes/player/camera_lag.gd")

@export var look_strength := 0.55
@export var max_offset := Vector2(0.07, 0.05)
@export var settle_rate := 7.0
@export var tilt := 1.6

var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO
var _lag := Vector2.ZERO
var _previous := Vector2.ZERO
var _camera: Camera3D
var _player: Node


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	_camera = get_parent() as Camera3D
	_player = _camera.get_parent().get_parent() if _camera else null
	if _camera:
		_previous = Vector2(_camera.global_rotation.y, _camera.global_rotation.x)


func _process(delta: float) -> void:
	if _camera == null:
		return
	if _player != null and _player.has_method("is_multiplayer_authority") and not _player.is_multiplayer_authority():
		position = _rest_position
		rotation = _rest_rotation
		return
	var step: Dictionary = CameraLag.advance(_camera, _previous, _lag, delta, look_strength, max_offset, settle_rate)
	_previous = step.previous
	_lag = step.lag
	var follow := 1.0
	if _player != null and _player.get("viewmodel_follow") != null:
		follow = float(_player.viewmodel_follow)
	position = _rest_position + Vector3(_lag.x * follow, _lag.y * follow, 0.0)
	rotation = _rest_rotation + Vector3(_lag.y * tilt * follow, -_lag.x * tilt * follow, _lag.x * 0.7 * follow)
