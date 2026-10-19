extends Node3D

@onready var main_menu = $CanvasLayer/PanelContainer
@onready var address_entry = $CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/LineEdit

const Player = preload("res://scenes/player/player.tscn")
const PORT = 9999
const SPAWN_SPACING: float = 2.0
var enet_peer = ENetMultiplayerPeer.new()
var upnp := UPNP.new()


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
	upnp_setup()

func _on_button_2_pressed() -> void:
	main_menu.hide()
	# Blank means localhost for testing on one machine.
	var address: String = address_entry.text.strip_edges()
	if address.is_empty():
		address = "localhost"
	enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_client(address, PORT)
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

func upnp_setup() -> void:
	# Open UDP 9999 on the router and print the address for a friend to join.
	# Every step can fail (many routers have UPnP off), so never assert/crash.
	var discover_result = upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPnP: discover failed (%s). Forward UDP %d to this PC manually." % [discover_result, PORT])
		return
	var gateway = upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		print("UPnP: no valid gateway. Forward UDP %d to this PC manually." % PORT)
		return
	var map_result = upnp.add_port_mapping(PORT, PORT, "oathbound", "UDP")
	if map_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPnP: port mapping failed (%s). Forward UDP %d to this PC manually." % [map_result, PORT])
		return
	print("UPnP ready. Join Address: %s" % upnp.query_external_address())
