extends MultiplayerPeerExtension
class_name RelayMultiplayerPeer
## Godot multiplayer over a room-code relay. The host is peer 1.

signal attempt_ready(peer_id: int, room_code: String)
signal attempt_failed(message: String)

var link_status: int = CONNECTION_DISCONNECTED
var unique_id := 0
var server := false
var room_code := ""
var framer: RoomFramer
var greeting := PackedByteArray()
var greeting_sent := false
var inbox: Array[Dictionary] = []
var target_peer := 0
var outbound_channel := 0
var outbound_mode: int = TRANSFER_MODE_RELIABLE
var refusing := false
var closing := false
var handed_off := false
var pending_peers: Array[int] = []
var fail_message := "Could not reach the room relay."


func connect_and_host(url: String, requested_code: String = "") -> void:
	server = true
	greeting = RoomProtocol.host_packet(requested_code)
	_open(url)


func connect_and_join(url: String, code: String) -> void:
	server = false
	room_code = code
	greeting = RoomProtocol.join_packet(code)
	_open(url)


func service() -> void:
	_poll()


func mark_handed_off() -> void:
	handed_off = true
	for peer_id in pending_peers:
		peer_connected.emit(peer_id)
	pending_peers.clear()


func shutdown() -> void:
	closing = true
	link_status = CONNECTION_DISCONNECTED
	inbox.clear()
	pending_peers.clear()
	greeting_sent = false
	if framer and framer.stream:
		framer.stream.disconnect_from_host()
	framer = null


func is_live() -> bool:
	return link_status == CONNECTION_CONNECTED


func _open(url: String) -> void:
	shutdown()
	closing = false
	handed_off = false
	unique_id = 0
	greeting_sent = false
	link_status = CONNECTION_CONNECTING
	var stream := StreamPeerTCP.new()
	var error := stream.connect_to_host(RoomProtocol.host_of(url), RoomProtocol.port_of(url))
	if error != OK:
		link_status = CONNECTION_DISCONNECTED
		fail_message = "Could not reach the room relay."
		attempt_failed.emit(fail_message)
		return
	framer = RoomFramer.new()
	framer.stream = stream


func _poll() -> void:
	if framer == null or framer.stream == null:
		return
	framer.poll_stream()
	if framer.is_connecting():
		return
	if not framer.stream_ready():
		_on_socket_closed()
		return
	if not greeting_sent:
		greeting_sent = true
		framer.stream.set_no_delay(true)
		framer.queue_packet(greeting)
	for packet in framer.take_packets():
		_handle_packet(packet)
		if framer == null:
			return
	framer.flush()


func _handle_packet(packet: PackedByteArray) -> void:
	var info := RoomProtocol.parse(packet)
	match int(info.type):
		RoomProtocol.HOST_OK:
			_become_ready(int(info.peer_id), str(info.code), true)
		RoomProtocol.JOIN_OK:
			_become_ready(int(info.peer_id), str(info.code), false)
			_notify_peer(1)
		RoomProtocol.ERROR:
			fail_message = str(info.message) if str(info.message) != "" else "Could not join that room."
			_fail_attempt()
		RoomProtocol.PEER_JOINED:
			_notify_peer(int(info.peer_id))
		RoomProtocol.PEER_LEFT:
			_notify_left(int(info.peer_id))
		RoomProtocol.DATA:
			if int(info.from) <= 0:
				return
			inbox.append({
				"from": int(info.from),
				"channel": int(info.channel),
				"mode": int(info.mode),
				"data": info.payload,
			})


func _become_ready(peer_id: int, code: String, as_server: bool) -> void:
	if link_status == CONNECTION_CONNECTED:
		return
	if peer_id <= 0 or code.is_empty():
		fail_message = "The room relay sent a bad reply."
		_fail_attempt()
		return
	unique_id = peer_id
	room_code = code
	server = as_server
	link_status = CONNECTION_CONNECTED
	attempt_ready.emit(peer_id, code)


func _fail_attempt() -> void:
	if closing or link_status != CONNECTION_CONNECTING:
		return
	closing = true
	link_status = CONNECTION_DISCONNECTED
	if framer and framer.stream:
		framer.stream.disconnect_from_host()
	framer = null
	attempt_failed.emit(fail_message)


func _on_socket_closed() -> void:
	if closing:
		link_status = CONNECTION_DISCONNECTED
		return
	if link_status == CONNECTION_CONNECTING:
		_fail_attempt()
		return
	link_status = CONNECTION_DISCONNECTED


func _notify_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if handed_off:
		peer_connected.emit(peer_id)
	elif not pending_peers.has(peer_id):
		pending_peers.append(peer_id)


func _notify_left(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if handed_off:
		peer_disconnected.emit(peer_id)
	else:
		pending_peers.erase(peer_id)


func _close() -> void:
	shutdown()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if server and framer and framer.stream_ready():
		framer.queue_packet(RoomProtocol.kick_packet(peer))


func _get_available_packet_count() -> int:
	return inbox.size()


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return link_status as MultiplayerPeer.ConnectionStatus


func _get_max_packet_size() -> int:
	return 8 * 1024 * 1024


func _get_packet_channel() -> int:
	if inbox.is_empty():
		return 0
	return int(inbox[0].channel)


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if inbox.is_empty():
		return TRANSFER_MODE_RELIABLE
	return int(inbox[0].mode) as MultiplayerPeer.TransferMode


func _get_packet_peer() -> int:
	if inbox.is_empty():
		return 0
	return int(inbox[0].from)


func _get_packet_script() -> PackedByteArray:
	if inbox.is_empty():
		return PackedByteArray()
	var item: Dictionary = inbox.pop_front()
	return item.data


func _get_transfer_channel() -> int:
	return outbound_channel


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return outbound_mode as MultiplayerPeer.TransferMode


func _get_unique_id() -> int:
	return unique_id


func _is_refusing_new_connections() -> bool:
	return refusing


func _is_server() -> bool:
	return server


func _is_server_relay_supported() -> bool:
	return true


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if link_status != CONNECTION_CONNECTED or framer == null or not framer.stream_ready():
		return ERR_UNCONFIGURED
	return framer.queue_packet(RoomProtocol.data_packet(target_peer, 0, outbound_channel, outbound_mode, buffer))


func _set_refuse_new_connections(enable: bool) -> void:
	refusing = enable
	if server and link_status == CONNECTION_CONNECTED and framer and framer.stream_ready():
		framer.queue_packet(RoomProtocol.refuse_packet(enable))


func _set_target_peer(peer: int) -> void:
	target_peer = peer


func _set_transfer_channel(channel: int) -> void:
	outbound_channel = channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	outbound_mode = mode
