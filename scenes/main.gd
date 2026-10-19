extends Node3D

@onready var main_menu = $CanvasLayer/PanelContainer
@onready var address_entry = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/LineEdit

const Player = preload("res://scenes/player/player.tscn")
const PORT = 9999
const SPAWN_SPACING: float = 2.0
var enet_peer = ENetMultiplayerPeer.new()


func _ready() -> void:
	# Fires on every peer, so players and their dummies are cleaned up everywhere.
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)


func _on_button_pressed() -> void:
	main_menu.hide()
	enet_peer = ENetMultiplayerPeer.new() # fresh peer so re-hosting after a disconnect works
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	if not multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.connect(add_player)
	add_player(multiplayer.get_unique_id())
	_print_join_info()

func _on_button_2_pressed() -> void:
	main_menu.hide()
	# Blank means localhost for testing on one machine.
	var address: String = address_entry.text.strip_edges()
	if address.is_empty():
		address = "localhost"
	var port := PORT
	if address.contains(":"):
		# Accept "ip:port" so a manually forwarded port can be used.
		var parts := address.split(":")
		address = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_client(address, port)
	multiplayer.multiplayer_peer = enet_peer

func add_player(peer_id):
	var player =Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	# Players all spawn at the origin; space them so they don't stack inside each other.
	player.position.x = (get_child_count() % 8) * SPAWN_SPACING

func _on_connection_failed() -> void:
	# Clear the failed peer so retrying with another address works.
	multiplayer.multiplayer_peer = null

func _on_peer_disconnected(peer_id: int) -> void:
	var player := get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	# Remove the departed player's debug dummies (named "<peer_id>_DummyN").
	for dummy in get_tree().get_nodes_in_group("dummy"):
		if String(dummy.name).begins_with(str(peer_id) + "_"):
			dummy.queue_free()


func _on_server_disconnected() -> void:
	# Host left: tear down the session and return to the menu.
	multiplayer.multiplayer_peer = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child in get_children():
		# Players are CharacterBody3D; dummies are in the "dummy" group. The Floor is neither.
		if child is CharacterBody3D or child.is_in_group("dummy"):
			child.queue_free()
	main_menu.show()

func _print_join_info() -> void:
	# UPnP is off the table; print the addresses so one can be typed into Join.
	print("Hosting on UDP %d. Friend types one of these addresses:" % PORT)
	var lan := _lan_addresses()
	print("LAN / VPN addresses: %s" % (", ".join(lan) if not lan.is_empty() else "none"))
	_fetch_public_ip()

func _fetch_public_ip() -> void:
	# Manual port forwarding still needs the public address it forwards to.
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var ip := body.get_string_from_utf8().strip_edges()
		if not ip.is_empty():
			print("Public IP: %s (works if UDP %d is forwarded on the router)" % [ip, PORT])
	)
	http.request("https://api.ipify.org")

func _lan_addresses() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)
	return found
