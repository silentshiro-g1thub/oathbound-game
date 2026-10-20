extends Control
## Lower-left health plate. The fill tracks current health against a fixed maximum.

const SLANT := 18.0

var health := 200
var max_health := 200


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 28.0
	offset_top = -68.0
	offset_right = 348.0
	offset_bottom = -28.0


func set_health(current: int, maximum: int) -> void:
	health = maxi(0, current)
	max_health = maxi(1, maximum)
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var height := size.y
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	var plate := _plate(width, height, 1.0, 0.0)
	var shadow := PackedVector2Array()
	for point in plate:
		shadow.append(point + Vector2(5, 5))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
	draw_colored_polygon(plate, Color(0.16, 0.05, 0.05, 0.94))
	if ratio > 0.04:
		var fill := Color(0.86, 0.16, 0.18) if ratio > 0.3 else Color(0.95, 0.45, 0.12)
		draw_colored_polygon(_plate(width, height, ratio, 3.0), fill)
	var label := "%d HP" % health
	var font := ThemeDB.fallback_font
	var font_size := 20
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_position := Vector2((width - text_size.x) * 0.5, (height + font.get_ascent(font_size)) * 0.5 - 1.0)
	draw_string_outline(font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.05, 0.01, 0.01, 0.9))
	draw_string(font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.96, 0.94))


func _plate(width: float, height: float, ratio: float, inset: float) -> PackedVector2Array:
	var top_left := SLANT
	var top_right := lerpf(SLANT, width, ratio)
	var bottom_right := lerpf(0.0, width - SLANT, ratio)
	return PackedVector2Array([
		Vector2(top_left + inset, inset),
		Vector2(top_right - inset, inset),
		Vector2(bottom_right - inset, height - inset),
		Vector2(inset, height - inset),
	])
