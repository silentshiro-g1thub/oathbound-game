extends Node3D

@onready var main_menu = $CanvasLayer/PanelContainer
@onready var lobby_panel = $CanvasLayer/LobbyPanel
@onready var address_entry = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/LineEdit
@onready var name_entry = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/NameEdit
@onready var lobby_code_label = $CanvasLayer/LobbyPanel/MarginContainer/VBoxContainer/CodeLabel
@onready var lobby_players_label = $CanvasLayer/LobbyPanel/MarginContainer/VBoxContainer/PlayersLabel
@onready var start_button = $CanvasLayer/LobbyPanel/MarginContainer/VBoxContainer/StartButton

const Player = preload("res://scenes/player/player.tscn")
const SPAWN_SPACING: float = 2.0
var enet_peer = ENetMultiplayerPeer.new()
var connection_status: Label
var joining: bool = false
var join_elapsed: float = 0.0
const JOIN_TIMEOUT: float = 20.0
var _match_connecting: bool = false


func _ready() -> void:
	connection_status = Label.new()
	connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	address_entry.get_parent().add_child(connection_status)
	lobby_panel.hide()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	Online.lobby_changed.connect(_refresh_lobby_panel)
	Online.kicked.connect(_on_kicked_from_lobby)


func _on_button_pressed() -> void:
	if joining:
		return
	_set_join_buttons_disabled(true)
	connection_status.text = "Creating lobby..."
	var ok: bool = await Online.login_and_host(_display_name())
	_set_join_buttons_disabled(false)
	if not ok:
		_show_connection_error(Online.last_error)
		return
	_show_lobby()


func _on_button_2_pressed() -> void:
	if joining:
		return
	var code: String = address_entry.text.strip_edges()
	if code.is_empty():
		_show_connection_error("Enter a 6-character join code.")
		return
	_set_join_buttons_disabled(true)
	connection_status.text = "Joining %s..." % code.to_upper()
	var ok: bool = await Online.login_and_join(_display_name(), code)
	_set_join_buttons_disabled(false)
	if not ok:
		_show_connection_error(Online.last_error)
		return
	_show_lobby()
	if Online.is_match_started():
		_connect_to_host()


func _on_start_button_pressed() -> void:
	if not Online.is_host():
		return
	start_button.disabled = true
	var peer := Online.create_host_peer()
	if peer == null:
		_show_connection_error(Online.last_error)
		start_button.disabled = false
		return
	main_menu.hide()
	lobby_panel.hide()
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.connect(add_player)
	add_player(multiplayer.get_unique_id())
	if not await Online.mark_match_started():
		_show_connection_error("Hosted locally, but could not flag the lobby as started.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_leave_button_pressed() -> void:
	await Online.leave_lobby()
	multiplayer.multiplayer_peer = null
	lobby_panel.hide()
	main_menu.show()
	connection_status.text = ""
	_set_join_buttons_disabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_lobby() -> void:
	main_menu.hide()
	lobby_panel.show()
	_refresh_lobby_panel()
	if Online.is_host() and not Online.join_code.is_empty():
		DisplayServer.clipboard_set(Online.join_code)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_lobby_panel() -> void:
	if not Online.is_in_lobby():
		return
	lobby_code_label.text = "Code: %s" % Online.join_code
	lobby_players_label.text = "Crew:\n" + "\n".join(Online.member_names())
	start_button.visible = Online.is_host()
	start_button.disabled = Online.is_match_started()
	if not Online.is_host() and Online.is_match_started() and not _match_connecting:
		_connect_to_host()


func _connect_to_host() -> void:
	_match_connecting = true
	var peer := Online.create_client_peer()
	if peer == null:
		_match_connecting = false
		_show_connection_error(Online.last_error)
		return
	_begin_join_wait("Connecting to host...")
	multiplayer.multiplayer_peer = peer


func _begin_join_wait(message: String) -> void:
	joining = true
	join_elapsed = 0.0
	main_menu.show()
	lobby_panel.hide()
	connection_status.text = message
	_set_join_buttons_disabled(true)


func _process(delta: float) -> void:
	if not joining:
		return

	join_elapsed += delta
	var peer := multiplayer.multiplayer_peer
	if peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var local_player := get_node_or_null(str(multiplayer.get_unique_id()))
		if local_player and local_player.is_node_ready() and local_player.camera.current:
			joining = false
			_match_connecting = false
			_set_join_buttons_disabled(false)
			main_menu.hide()
			lobby_panel.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

	if join_elapsed >= JOIN_TIMEOUT:
		var connected := peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		_on_server_disconnected()
		_show_connection_error(
			"Connected, but no player spawned. Both players need the same game version."
			if connected else
			"Connection timed out. Check the join code and that the host clicked Start."
		)


func _on_connected_to_server() -> void:
	if joining:
		join_elapsed = 0.0
		connection_status.text = "Connected. Waiting for your player..."


func _set_join_buttons_disabled(disabled: bool) -> void:
	$CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/Button.disabled = disabled
	$CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/Button2.disabled = disabled


func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	player.position = Vector3((get_child_count() % 8) * SPAWN_SPACING, 2.0, 0)
	add_child(player)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_match_connecting = false
	_show_connection_error("Connection failed.")


func _show_connection_error(message: String) -> void:
	joining = false
	_match_connecting = false
	_set_join_buttons_disabled(false)
	lobby_panel.hide()
	main_menu.show()
	connection_status.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$MenuCamera.make_current()
	$Floor/MeshInstance3D/Terrain3D.set_camera($MenuCamera)


func _on_peer_disconnected(peer_id: int) -> void:
	var player := get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	for dummy in get_tree().get_nodes_in_group("dummy"):
		if String(dummy.name).begins_with(str(peer_id) + "_"):
			dummy.queue_free()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_match_connecting = false
	_show_connection_error("Disconnected from the host.")
	for child in get_children():
		if child is CharacterBody3D or child.is_in_group("dummy"):
			child.queue_free()
	main_menu.show()


func _on_kicked_from_lobby() -> void:
	multiplayer.multiplayer_peer = null
	_show_connection_error("The host closed the lobby.")


func _display_name() -> String:
	var shown: String = name_entry.text.strip_edges()
	return shown if not shown.is_empty() else "Player"
