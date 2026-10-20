extends Node3D

const PlayerScene = preload("res://scenes/player/player.tscn")
const RoomSessionScript = preload("res://multiplayer/room_session.gd")

@onready var main_menu: Control = $CanvasLayer/PanelContainer
@onready var code_entry: LineEdit = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/LineEdit

const SPAWN_SPACING: float = 2.0
const JOIN_TIMEOUT: float = 20.0

var connection_status: Label
var session: RoomSession
var joining: bool = false
var join_elapsed: float = 0.0
var join_direct_url: String = ""
var relay_url: String = ""
var room_code: String = ""
var hosting: bool = false
var in_room: bool = false
var closing_room: bool = false
var code_layer: CanvasLayer
var code_label: Label
var code_detail: Label


func _ready() -> void:
	relay_url = RoomProtocol.load_relay_url()
	connection_status = Label.new()
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_status.text = "Host creates a code. A friend on any network joins by typing it."
	code_entry.get_parent().add_child(connection_status)
	code_entry.max_length = 11
	code_entry.text_submitted.connect(func(_text: String) -> void:
		_on_button_2_pressed()
	)
	session = RoomSessionScript.new()
	session.name = "RoomSession"
	add_child(session)
	session.hosted.connect(_on_hosted)
	session.joined.connect(_on_joined)
	session.failed.connect(_on_session_failed)
	session.notice.connect(_on_notice)
	_build_code_hud()
	# Fires on every peer, so players and their dummies are cleaned up everywhere.
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)


func _on_button_pressed() -> void:
	if joining:
		return
	host_room(-1, "", true)


## Open a room. Tests can pin the port and code; players only see the code.
func host_room(port: int = -1, fixed_code: String = "", publish: bool = true) -> void:
	if joining:
		return
	var url := relay_url
	if port > 0:
		url = "ws://%s:%d" % [RoomProtocol.host_of(relay_url), port]
	joining = true
	join_elapsed = 0.0
	_set_join_buttons_disabled(true)
	main_menu.show()
	connection_status.text = "Creating room..."
	session.host(url, fixed_code, publish)


func _on_button_2_pressed() -> void:
	if joining:
		return
	var code := RoomProtocol.normalize_code(code_entry.text)
	if not RoomProtocol.valid_code(code):
		_show_connection_error("Enter the 6-character room code.")
		return
	joining = true
	join_elapsed = 0.0
	_set_join_buttons_disabled(true)
	main_menu.show()
	connection_status.text = "Connecting to room %s..." % RoomProtocol.pretty_code(code)
	session.join(code, join_direct_url, relay_url)


## Keep connection progress visible until the local player has actually spawned.
func _process(delta: float) -> void:
	if not joining:
		return
	join_elapsed += delta
	if _local_player_ready():
		joining = false
		_set_join_buttons_disabled(false)
		main_menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if join_elapsed >= JOIN_TIMEOUT:
		var connected := session.peer != null and session.peer.is_live()
		_show_connection_error(
			"Connected, but no player spawned. Both players need the same game version."
			if connected else
			"Connection timed out. Check the room code and that the host is still in the game."
		)


## Distinguish a completed network handshake from a completed player spawn.
func _on_connected_to_server() -> void:
	if joining:
		join_elapsed = 0.0
		connection_status.text = "Connected. Waiting for your player..."


func _on_hosted(peer_id: int, code: String) -> void:
	if in_room:
		return
	_attach_peer()
	in_room = true
	hosting = true
	joining = false
	room_code = code
	_set_host_spawn(true)
	_set_join_buttons_disabled(false)
	main_menu.hide()
	_show_room(code)
	add_player(peer_id)
	print("Room code: %s" % code)


func _on_joined(peer_id: int, code: String) -> void:
	if in_room:
		return
	_attach_peer()
	in_room = true
	hosting = false
	room_code = code
	_set_host_spawn(false)
	_show_room(code)
	join_elapsed = 0.0
	connection_status.text = "Connected. Waiting for your player..."
	# peer_id is assigned by the relay; the host spawns that player for us.
	if peer_id <= 0:
		_show_connection_error("Could not join that room.")


func _on_session_failed(message: String) -> void:
	if not joining or in_room:
		return
	_show_connection_error(message)


func _on_notice(text: String) -> void:
	print(text)
	if code_detail:
		code_detail.text = text
	if main_menu.visible:
		connection_status.text = text


func _attach_peer() -> void:
	if session.peer == null:
		return
	if multiplayer.multiplayer_peer != session.peer:
		multiplayer.multiplayer_peer = session.peer
	session.peer.mark_handed_off()


func _set_host_spawn(enabled: bool) -> void:
	var connected := multiplayer.peer_connected.is_connected(add_player)
	if enabled and not connected:
		multiplayer.peer_connected.connect(add_player)
	elif not enabled and connected:
		multiplayer.peer_connected.disconnect(add_player)


## Prevent repeated connection attempts while the current attempt is pending.
func _set_join_buttons_disabled(disabled: bool) -> void:
	$CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/Button.disabled = disabled
	$CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/Button2.disabled = disabled


func add_player(peer_id: int) -> void:
	if get_node_or_null(str(peer_id)):
		return
	var player := PlayerScene.instantiate()
	player.name = str(peer_id)
	# Players all spawn at the origin; space them so they don't stack inside each other.
	player.position = Vector3((get_child_count() % 8) * SPAWN_SPACING, 2.0, 0)
	add_child(player)


func _local_player_ready() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	var local_player := get_node_or_null(str(multiplayer.get_unique_id()))
	return local_player != null and local_player.is_node_ready() and local_player.camera.current


func _on_connection_failed() -> void:
	_show_connection_error("Could not join that room. Check the code and try again.")


func _show_connection_error(message: String) -> void:
	if closing_room:
		return
	closing_room = true
	joining = false
	in_room = false
	hosting = false
	room_code = ""
	_set_host_spawn(false)
	_set_room_hud("")
	_set_join_buttons_disabled(false)
	if session:
		session.shutdown()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	main_menu.show()
	connection_status.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$MenuCamera.make_current()
	$Floor/MeshInstance3D/Terrain3D.set_camera($MenuCamera)
	closing_room = false


func _on_peer_disconnected(peer_id: int) -> void:
	var player := get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	# Remove the departed player's debug dummies (named "<peer_id>_DummyN").
	for dummy in get_tree().get_nodes_in_group("dummy"):
		if String(dummy.name).begins_with(str(peer_id) + "_"):
			dummy.queue_free()


func _on_server_disconnected() -> void:
	# Host left, or our own relay socket closed: tear down and return to the menu.
	var own_room := hosting
	_show_connection_error("The room closed." if own_room else "Disconnected from the host.")
	for child in get_children():
		# Players are CharacterBody3D; dummies are in the "dummy" group. The Floor is neither.
		if child is CharacterBody3D or child.is_in_group("dummy"):
			child.queue_free()
	main_menu.show()


func _build_code_hud() -> void:
	code_layer = CanvasLayer.new()
	code_layer.name = "RoomCode"
	code_layer.layer = 40
	add_child(code_layer)
	var root_control := Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_layer.add_child(root_control)
	code_label = Label.new()
	code_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	code_label.offset_left = -220.0
	code_label.offset_top = 12.0
	code_label.offset_right = 220.0
	code_label.offset_bottom = 52.0
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_label.add_theme_font_size_override("font_size", 32)
	code_label.add_theme_color_override("font_color", Color.WHITE)
	code_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	code_label.add_theme_constant_override("outline_size", 8)
	root_control.add_child(code_label)
	code_detail = Label.new()
	code_detail.set_anchors_preset(Control.PRESET_CENTER_TOP)
	code_detail.offset_left = -360.0
	code_detail.offset_top = 52.0
	code_detail.offset_right = 360.0
	code_detail.offset_bottom = 96.0
	code_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	code_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_detail.add_theme_font_size_override("font_size", 16)
	code_detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	code_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	code_detail.add_theme_constant_override("outline_size", 6)
	root_control.add_child(code_detail)
	code_layer.hide()


func _show_room(code: String) -> void:
	_set_room_hud(code)
	_copy_code(code)
	if not OS.has_feature("headless"):
		DisplayServer.window_set_title("Oathbound  |  %s" % RoomProtocol.pretty_code(code))


func _set_room_hud(code: String) -> void:
	if code_layer == null:
		return
	if code.is_empty():
		code_layer.hide()
		if not OS.has_feature("headless"):
			DisplayServer.window_set_title(str(ProjectSettings.get_setting("application/config/name", "Oathbound")))
		return
	code_label.text = "ROOM  %s" % RoomProtocol.pretty_code(code)
	if code_detail.text.is_empty():
		code_detail.text = "Share this code."
	code_layer.show()


func _copy_code(code: String) -> void:
	if OS.has_feature("headless"):
		return
	DisplayServer.clipboard_set(code)
	if code_detail.text.is_empty() or code_detail.text == "Share this code.":
		code_detail.text = "Code copied. Send it to your friend."
