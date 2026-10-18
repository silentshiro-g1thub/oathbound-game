extends CanvasLayer
## Read-only movement diagnostics. Attached by the player in debug builds.
## F3: overlay. Shift+F3: live console log. F4: full console snapshot.

const SCREEN_INTERVAL: float = 0.1
const CONSOLE_INTERVAL: float = 1.0

var player: CharacterBody3D
var panel: PanelContainer
var readout: Label
var console_logging: bool = false
var screen_elapsed: float = 0.0
var console_elapsed: float = 0.0

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	layer = 100
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.045, 0.065, 0.94)
	background.border_color = Color(0.25, 0.85, 0.65, 0.8)
	background.set_border_width_all(1)
	background.set_corner_radius_all(6)
	background.content_margin_left = 14
	background.content_margin_right = 14
	background.content_margin_top = 12
	background.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	readout = Label.new()
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "monospace"])
	readout.add_theme_font_override("font", font)
	readout.add_theme_font_size_override("font_size", 14)
	readout.add_theme_color_override("font_color", Color(0.85, 0.95, 0.92))
	panel.add_child(readout)
	panel.hide()
	panel.resized.connect(_place_panel)
	get_viewport().size_changed.connect(_place_panel)
	set_process(false)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_F3:
		if event.shift_pressed:
			console_logging = not console_logging
			console_elapsed = 0.0
			print("[OATHBOUND DEV] Live console logging %s (Shift+F3 to toggle)." % ("ON" if console_logging else "OFF"))
		else:
			panel.visible = not panel.visible
		if panel.visible:
			_refresh_screen()
		set_process(panel.visible or console_logging)
		get_viewport().set_input_as_handled()
	elif key == KEY_F4:
		print("\n[OATHBOUND DEV SNAPSHOT | physics frame %d]\n%s\n" % [Engine.get_physics_frames(), snapshot_text()])
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if panel.visible:
		screen_elapsed += delta
		if screen_elapsed >= SCREEN_INTERVAL:
			screen_elapsed = 0.0
			_refresh_screen()
	if console_logging:
		console_elapsed += delta
		if console_elapsed >= CONSOLE_INTERVAL:
			console_elapsed = 0.0
			print("[OATHBOUND DEV] %s | speed %.2f m/s | velocity %s | floor %s | extra jump %d | dash cooldown %.2fs" % [
				_state_name(), _horizontal_speed(player.velocity), _vector(player.velocity),
				_yes_no(player.is_on_floor()), player.extra_jumps_remaining, player.dash_cooldown_remaining])

func _refresh_screen() -> void:
	readout.text = snapshot_text()
	_place_panel()

func _place_panel() -> void:
	# Keep the whole readout inside a small or resized game viewport.
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := panel.get_combined_minimum_size()
	var fit := minf(1.0, minf(maxf(1.0, viewport_size.x - 24.0) / maxf(1.0, panel_size.x), maxf(1.0, viewport_size.y - 24.0) / maxf(1.0, panel_size.y)))
	panel.scale = Vector2.ONE * fit
	panel.position = Vector2(maxf(12.0, viewport_size.x - panel_size.x * fit - 12.0), 12.0)

func snapshot_text() -> String:
	var real_velocity := player.get_real_velocity()
	var inputs: Array[String] = []
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "slide", "dash"]:
		if Input.is_action_pressed(action):
			inputs.append(action.trim_prefix("move_"))
	var floor_angle := rad_to_deg(player.get_floor_angle()) if player.is_on_floor() else 0.0
	var active_slide: float = maxf(0.0, player.slide_remaining) if player.movement_state == player.MovementState.SLIDING else 0.0
	var active_dash: float = maxf(0.0, player.dash_remaining) if player.movement_state == player.MovementState.DASHING else 0.0
	var contact_normal := player.get_wall_normal() if player.is_on_wall() else Vector3.ZERO
	return "\n".join(PackedStringArray([
		"OATHBOUND / DEVELOPER CHECK",
		"F3: hide/show  |  F4: console snapshot",
		"Shift+F3: live console [%s]" % ("ON" if console_logging else "OFF"),
		"",
		"FPS: %d  |  Physics: %d Hz" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second],
		"State: %s  |  Crouched: %s" % [_state_name(), _yes_no(player.is_crouched)],
		"Speed: %.2f m/s  |  Vertical: %+.2f m/s" % [_horizontal_speed(player.velocity), player.velocity.y],
		"Total speed: %.2f m/s | Air dash: %s" % [player.velocity.length(), _yes_no(player.air_dash_available)],
		"Velocity XYZ: %s" % _vector(player.velocity),
		"Real velocity: %s" % _vector(real_velocity),
		"Position XYZ: %s" % _vector(player.global_position),
		"",
		"Floor: %s  Wall: %s  Ceiling: %s" % [_yes_no(player.is_on_floor()), _yes_no(player.is_on_wall()), _yes_no(player.is_on_ceiling())],
		"Floor angle: %.1f deg  |  Collisions: %d" % [floor_angle, player.get_slide_collision_count()],
		"Wall contact normal: %s" % _vector(contact_normal),
		"",
		"Extra jump: %d  |  Jump cut: %s" % [player.extra_jumps_remaining, _yes_no(player.jump_cut_applied)],
		"Coyote: %.2fs  |  Jump buffer: %.2fs" % [player.coyote_remaining, player.jump_buffer_remaining],
		"Slide time: %.2fs  |  Dash time: %.2fs" % [active_slide, active_dash],
		"Dash cooldown: %.2fs" % player.dash_cooldown_remaining,
		"Wall budget: %.2fs  |  Re-entry: %.2fs" % [player.wall_budget_remaining, player.wall_reentry_remaining],
		"Wall jump steering lock: %.2fs" % player.wall_jump_lock_remaining,
		"",
		"Controls: %s  |  Mouse captured: %s" % [_yes_no(player.controls_active), _yes_no(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)],
		"Held: %s" % (", ".join(inputs) if not inputs.is_empty() else "none"),
	]))

func _state_name() -> String:
	return player.MovementState.keys()[player.movement_state]

func _horizontal_speed(value: Vector3) -> float:
	return Vector2(value.x, value.z).length()

func _vector(value: Vector3) -> String:
	return "(%+.2f, %+.2f, %+.2f)" % [value.x, value.y, value.z]

func _yes_no(value: bool) -> String:
	return "YES" if value else "NO"
