extends Control
## Lower-left health and resolve plates. They trail the camera look instead of sitting still.

const CameraLag = preload("res://scenes/player/camera_lag.gd")
const SLANT := 18.0
const HEALTH_HEIGHT := 34.0
const RESOLVE_HEIGHT := 26.0
const GAP := 8.0

var health := 200
var max_health := 200
var resolve := 50
var max_resolve := 50
var _base_left := 28.0
var _base_top := -96.0
var _base_right := 348.0
var _base_bottom := -28.0
var _lag := Vector2.ZERO
var _previous := Vector2.ZERO
var _camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = _base_left
	offset_top = _base_top
	offset_right = _base_right
	offset_bottom = _base_bottom
	var player := get_parent().get_parent() if get_parent() else null
	_camera = player.get_node_or_null("Head/Camera3D") if player else null
	if _camera:
		_previous = Vector2(_camera.global_rotation.y, _camera.global_rotation.x)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var step: Dictionary = CameraLag.advance(_camera, _previous, _lag, delta, 240.0, Vector2(16, 12), 8.0)
	_previous = step.previous
	_lag = step.lag
	offset_left = _base_left + _lag.x
	offset_right = _base_right + _lag.x
	offset_top = _base_top + _lag.y
	offset_bottom = _base_bottom + _lag.y


func set_health(current: int, maximum: int) -> void:
	health = maxi(0, current)
	max_health = maxi(1, maximum)
	queue_redraw()


func set_resolve(current: int, maximum: int) -> void:
	resolve = maxi(0, current)
	max_resolve = maxi(1, maximum)
	queue_redraw()


func _draw() -> void:
	_draw_meter(Rect2(0, 0, size.x, HEALTH_HEIGHT), health, max_health, "%d HP" % health, Color(0.16, 0.05, 0.05, 0.94), Color(0.86, 0.16, 0.18), Color(0.95, 0.45, 0.12), 18)
	_draw_meter(Rect2(0, HEALTH_HEIGHT + GAP, size.x, RESOLVE_HEIGHT), resolve, max_resolve, "%d RESOLVE" % resolve, Color(0.04, 0.08, 0.12, 0.94), Color(0.2, 0.72, 0.82), Color(0.85, 0.62, 0.16), 14)


func _draw_meter(bounds: Rect2, current: int, maximum: int, label: String, plate_color: Color, fill_color: Color, low_color: Color, font_size: int) -> void:
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0)
	var plate := _plate(bounds, 1.0, 0.0)
	var shadow := PackedVector2Array()
	for point in plate:
		shadow.append(point + Vector2(4, 4))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
	draw_colored_polygon(plate, plate_color)
	if ratio > 0.04:
		var fill := fill_color if ratio > 0.3 else low_color
		draw_colored_polygon(_plate(bounds, ratio, 3.0), fill)
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_position := Vector2(bounds.position.x + (bounds.size.x - text_size.x) * 0.5, bounds.position.y + (bounds.size.y + font.get_ascent(font_size)) * 0.5 - 1.0)
	draw_string_outline(font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.05, 0.01, 0.01, 0.9))
	draw_string(font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.96, 0.94))


func _plate(bounds: Rect2, ratio: float, inset: float) -> PackedVector2Array:
	var top_left := bounds.position.x + SLANT
	var top_right := bounds.position.x + lerpf(SLANT, bounds.size.x, ratio)
	var bottom_right := bounds.position.x + lerpf(0.0, bounds.size.x - SLANT, ratio)
	var top := bounds.position.y
	var bottom := bounds.position.y + bounds.size.y
	return PackedVector2Array([
		Vector2(top_left + inset, top + inset),
		Vector2(top_right - inset, top + inset),
		Vector2(bottom_right - inset, bottom - inset),
		Vector2(bounds.position.x + inset, bottom - inset),
	])
