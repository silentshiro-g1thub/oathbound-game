extends Node3D
## Isolated practice course; run this scene with F6. The main arena is unchanged.

const PlayerScene = preload("res://scenes/player/player.tscn")
var player: CharacterBody3D
var status: Label

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182330")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60), Color("3a4a56"))
	_box(Vector3(6, 2.5, -2), Vector3(0.4, 5, 32), Color("22a99e"))
	_box(Vector3(-6, 2.5, 5), Vector3(0.4, 5, 14), Color("22a99e"))
	_box(Vector3(-6, 2.5, -12), Vector3(0.4, 5, 14), Color("22a99e"))
	_box(Vector3(0, 1.3, 0), Vector3(3, 0.3, 4), Color("e9b56c"))
	_box(Vector3(0, 1.5, -12), Vector3(4, 3, 0.1), Color("c86464"))
	var ramp := _box(Vector3(12, 0.65, 0), Vector3(4, 0.4, 6), Color("7f8dc0"))
	ramp.rotation_degrees.x = 15
	_label("SLIDE UNDER\nHold Ctrl with sprint momentum", Vector3(0, 2.5, 2))
	_label("DASH COLLISION\nQ toward this thin wall", Vector3(0, 3.8, -11.8))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(16, 16)
	status.add_theme_font_size_override("font_size", 18)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)
	_respawn()

func _box(at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	body.position = at
	return body

func _label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = preload("res://assets/fonts/SourceSans3-Regular.ttf")
	label.font_size = 36
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.position = at

func _respawn() -> void:
	if is_instance_valid(player):
		player.queue_free()
	player = PlayerScene.instantiate()
	add_child(player)
	player.position = Vector3(0, 0.05, 12)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_respawn()

func _process(_delta: float) -> void:
	if player.position.y < -10:
		_respawn()
	var developer_overlay := player.get_node_or_null("DeveloperOverlay")
	status.visible = developer_overlay == null or not developer_overlay.panel.visible
	status.text = "MOVEMENT PRACTICE | R: reset | F3: developer overlay\nEsc: release mouse | Click: recapture\nWASD: move | Shift: sprint | Ctrl: crouch/slide | WASD+Q: dash | Space: jumps\nState: %s | Speed: %.1f m/s | Extra jump: %d | Dash ready in: %.2fs\nCrouched: %s" % [
		player.MovementState.keys()[player.movement_state], player._horizontal_velocity().length(),
		player.extra_jumps_remaining, player.dash_cooldown_remaining,
		player.is_crouched]
