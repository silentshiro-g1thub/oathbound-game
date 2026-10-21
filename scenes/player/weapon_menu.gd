extends CanvasLayer
## Temporary loadout. E opens it. The rifle is shown as an orthographic side silhouette.

const UI_FONT = preload("res://assets/fonts/SourceSans3-Regular.ttf")
const GUN_SCENE = preload("res://assets/weapon_models/bagyo_gun.glb")

var player: Node
var _slots: Array[Button] = []


func _ready() -> void:
	layer = 40
	visible = false
	player = get_parent()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.06, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -280
	column.offset_top = -220
	column.offset_right = 280
	column.offset_bottom = 220
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var title := _label("LOADOUT", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var stage := PanelContainer.new()
	stage.custom_minimum_size = Vector2(520, 250)
	column.add_child(stage)
	var viewport_box := SubViewportContainer.new()
	viewport_box.custom_minimum_size = Vector2(520, 250)
	viewport_box.stretch = true
	viewport_box.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_box.gui_input.connect(_on_gun_pressed)
	stage.add_child(viewport_box)
	viewport_box.add_child(_build_preview())

	var name_label := _label("BAGYO", 32)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var hint := _label("Click the rifle to put it on 1.   2 melee   3 hands   E closes", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	for slot in [1, 2, 3]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 48)
		button.add_theme_font_override("font", UI_FONT)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		row.add_child(button)
		_slots.append(button)
	refresh_slots()


func refresh_slots() -> void:
	var owned: bool = player.rifle_owned if player else false
	var selected: int = player.weapon_slot if player else 0
	var names := [
		"1  RIFLE\n%s" % ("BAGYO" if owned else "EMPTY"),
		"2  MELEE\nEMPTY",
		"3  HANDS\nEMPTY",
	]
	for index in _slots.size():
		_slots[index].text = names[index]
		_slots[index].modulate = Color(1, 0.86, 0.45) if selected == index + 1 else Color.WHITE


func _on_gun_pressed(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		player.give_rifle()
		refresh_slots()
		get_viewport().set_input_as_handled()


func _on_slot_pressed(slot: int) -> void:
	player.select_weapon_slot(slot)
	refresh_slots()


func _build_preview() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(520, 250)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var world := Node3D.new()
	viewport.add_child(world)
	var gun := GUN_SCENE.instantiate()
	_paint_silhouette(gun)
	world.add_child(gun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.5
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 0.06, 0.8), Vector3(0, 0.06, 0))
	camera.current = true
	return viewport


func _paint_silhouette(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.08, 0.09, 0.11)
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_paint_silhouette(child)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9))
	return label
