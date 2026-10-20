extends Node
class_name RoomRelay
## Outbound TCP rooms. The host stays Godot's server (peer 1).
## Friends never type an address; they connect out with a room code.

const PACKET_BUDGET := 8 * 1024 * 1024

var listen_port := 0
var tcp := TCPServer.new()
var udp: PacketPeerUDP
var links: Array = []
var rooms := {}
var rng := RandomNumberGenerator.new()


class Link:
	var framer: RoomFramer
	var id := 0
	var room_code := ""
	var gone := false


class Room:
	var code := ""
	var members := {}
	var next_id := 2
	var refusing := false


func start(port: int) -> Error:
	if tcp.is_listening() and listen_port == port:
		return OK
	stop()
	tcp = TCPServer.new()
	var error := tcp.listen(port, "0.0.0.0")
	if error != OK:
		return error
	listen_port = port
	udp = PacketPeerUDP.new()
	if udp.bind(port + 1, "0.0.0.0") != OK:
		udp = null
	rng.randomize()
	return OK


func stop() -> void:
	for link in links:
		if link.framer and link.framer.stream:
			link.framer.stream.disconnect_from_host()
	links.clear()
	rooms.clear()
	if tcp.is_listening():
		tcp.stop()
	if udp:
		udp.close()
		udp = null
	listen_port = 0


func is_listening() -> bool:
	return tcp.is_listening()


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	poll_network()


func poll_network() -> void:
	if not tcp.is_listening():
		return
	while tcp.is_connection_available():
		var connection := tcp.take_connection()
		connection.set_no_delay(true)
		var link := Link.new()
		link.framer = RoomFramer.new()
		link.framer.stream = connection
		links.append(link)
	var alive: Array = []
	for link in links:
		if link.gone or link.framer == null:
			continue
		var framer: RoomFramer = link.framer
		framer.poll_stream()
		if framer.broken():
			_drop(link)
			continue
		for packet in framer.take_packets():
			if link.gone:
				break
			_on_packet(link, packet)
		framer.flush()
		if not link.gone and not framer.broken():
			alive.append(link)
	links = alive
	_poll_discovery()


func _on_packet(link: Link, packet: PackedByteArray) -> void:
	if packet.size() > PACKET_BUDGET:
		_send(link, RoomProtocol.error_packet("Packet too large."))
		return
	var info := RoomProtocol.parse(packet)
	match int(info.type):
		RoomProtocol.HOST:
			_host(link, str(info.code))
		RoomProtocol.JOIN:
			_join(link, str(info.code))
		RoomProtocol.DATA:
			_forward(link, info)
		RoomProtocol.KICK:
			_kick(link, int(info.peer_id))
		RoomProtocol.REFUSE:
			_refuse(link, bool(info.refusing))
		_:
			_send(link, RoomProtocol.error_packet("Bad room packet."))


func _host(link: Link, requested: String) -> void:
	if link.id != 0:
		return
	var code := requested
	if code.is_empty():
		code = _fresh_code()
	elif not RoomProtocol.valid_code(code):
		_send(link, RoomProtocol.error_packet("Bad room code."))
		return
	elif rooms.has(code):
		_send(link, RoomProtocol.error_packet("Code in use."))
		return
	if code.is_empty():
		_send(link, RoomProtocol.error_packet("Could not create a room."))
		return
	var room := Room.new()
	room.code = code
	link.id = 1
	link.room_code = code
	room.members[1] = link
	rooms[code] = room
	_send(link, RoomProtocol.host_ok(code))
	print("Room %s is open." % code)


func _fresh_code() -> String:
	for _attempt in 16:
		var code := RoomProtocol.random_code(rng)
		if not rooms.has(code):
			return code
	return ""


func _join(link: Link, code: String) -> void:
	if link.id != 0:
		return
	if not RoomProtocol.valid_code(code) or not rooms.has(code):
		_send(link, RoomProtocol.error_packet("Unknown room."))
		return
	var room: Room = rooms[code]
	if room.refusing or room.members.size() >= RoomProtocol.MAX_PLAYERS or not room.members.has(1):
		_send(link, RoomProtocol.error_packet("Room is full."))
		return
	link.id = room.next_id
	room.next_id += 1
	link.room_code = code
	room.members[link.id] = link
	_send(link, RoomProtocol.join_ok(link.id, code))
	_send(room.members[1], RoomProtocol.peer_joined(link.id))
	print("Peer %d joined room %s." % [link.id, code])


func _forward(link: Link, info: Dictionary) -> void:
	if link.id == 0 or not rooms.has(link.room_code):
		_send(link, RoomProtocol.error_packet("Join a room first."))
		return
	var room: Room = rooms[link.room_code]
	var outgoing := RoomProtocol.data_packet(int(info.target), link.id, int(info.channel), int(info.mode), info.payload)
	var target := int(info.target)
	if target <= 0:
		for member_id in room.members.keys():
			if int(member_id) != link.id:
				_send(room.members[member_id], outgoing)
		return
	if room.members.has(target):
		_send(room.members[target], outgoing)


func _kick(link: Link, peer_id: int) -> void:
	if link.id != 1 or not rooms.has(link.room_code):
		return
	var room: Room = rooms[link.room_code]
	if room.members.has(peer_id):
		_drop(room.members[peer_id])


func _refuse(link: Link, enabled: bool) -> void:
	if link.id != 1 or not rooms.has(link.room_code):
		return
	rooms[link.room_code].refusing = enabled


func _drop(link: Link) -> void:
	if link.gone:
		return
	link.gone = true
	if link.room_code == "" or not rooms.has(link.room_code):
		_close_link(link)
		return
	var room: Room = rooms[link.room_code]
	room.members.erase(link.id)
	if link.id == 1:
		var leftovers: Array = room.members.values()
		rooms.erase(link.room_code)
		for other in leftovers:
			other.room_code = ""
			other.gone = true
			_close_link(other)
		print("Room %s closed." % room.code)
	elif room.members.has(1):
		_send(room.members[1], RoomProtocol.peer_left(link.id))
	_close_link(link)


func _close_link(link: Link) -> void:
	if link.framer and link.framer.stream:
		link.framer.stream.disconnect_from_host()


func _send(link: Link, packet: PackedByteArray) -> void:
	if link.gone or link.framer == null:
		return
	link.framer.queue_packet(packet)


func _poll_discovery() -> void:
	if udp == null:
		return
	while udp.get_available_packet_count() > 0:
		var packet := udp.get_packet()
		var ip := udp.get_packet_ip()
		var from_port := udp.get_packet_port()
		if packet.size() < 3 + RoomProtocol.CODE_LENGTH:
			continue
		if packet.slice(0, 3).get_string_from_utf8() != RoomProtocol.DISCOVER_ASK:
			continue
		var code := packet.slice(3, 3 + RoomProtocol.CODE_LENGTH).get_string_from_utf8()
		if not rooms.has(code):
			continue
		udp.set_dest_address(ip, from_port)
		udp.put_packet(RoomProtocol.discover_response(listen_port))
