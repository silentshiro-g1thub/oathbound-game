extends RefCounted
class_name RoomProtocol
## Binary room-code protocol shared by the relay and the game.
## Players only see the code. The relay carries Godot multiplayer packets.

const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const DEFAULT_PORT := 9050
const MAX_PLAYERS := 8

const HOST := 1
const HOST_OK := 2
const JOIN := 3
const JOIN_OK := 4
const ERROR := 5
const PEER_JOINED := 6
const PEER_LEFT := 7
const DATA := 8
const KICK := 9
const REFUSE := 10

const DISCOVER_ASK := "OB1"
const DISCOVER_ANSWER := "OB2"


static func _buf() -> StreamPeerBuffer:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	return buf


static func normalize_code(raw: String) -> String:
	var cleaned := ""
	for character in raw.to_upper():
		if character == " " or character == "-":
			continue
		cleaned += character
	return cleaned


static func valid_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for index in code.length():
		if not ALPHABET.contains(code[index]):
			return false
	return true


static func random_code(rng: RandomNumberGenerator) -> String:
	var characters := PackedStringArray()
	for _index in CODE_LENGTH:
		characters.append(ALPHABET[rng.randi() % ALPHABET.length()])
	return "".join(characters)


static func pretty_code(code: String) -> String:
	if code.length() == CODE_LENGTH:
		return "%s %s" % [code.substr(0, 3), code.substr(3, 3)]
	return code


static func topic_for(code: String) -> String:
	return "obind-" + code


static func host_of(url: String) -> String:
	var remainder := url
	var scheme := remainder.find("://")
	if scheme != -1:
		remainder = remainder.substr(scheme + 3)
	var slash := remainder.find("/")
	if slash != -1:
		remainder = remainder.substr(0, slash)
	if remainder.begins_with("["):
		var end := remainder.find("]")
		return remainder.substr(1, end - 1) if end > 1 else remainder
	var colon := remainder.rfind(":")
	if colon > 0:
		return remainder.substr(0, colon)
	return remainder


static func port_of(url: String) -> int:
	var remainder := url
	var scheme := remainder.find("://")
	if scheme != -1:
		remainder = remainder.substr(scheme + 3)
	var slash := remainder.find("/")
	if slash != -1:
		remainder = remainder.substr(0, slash)
	if remainder.begins_with("["):
		var end := remainder.find("]")
		if end != -1 and end + 1 < remainder.length() and remainder[end + 1] == ":":
			var port_text := remainder.substr(end + 2)
			if port_text.is_valid_int():
				return int(port_text)
		return DEFAULT_PORT
	var colon := remainder.rfind(":")
	if colon > 0 and remainder.substr(colon + 1).is_valid_int():
		return int(remainder.substr(colon + 1))
	return DEFAULT_PORT


static func is_local_url(url: String) -> bool:
	var host := host_of(url)
	return host == "localhost" or host == "127.0.0.1" or host == "::1"


static func local_url(port: int) -> String:
	return "ws://127.0.0.1:%d" % port


static func is_public_ip(ip: String) -> bool:
	if ip.is_empty() or ip.contains(":"):
		return false
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
		var value := int(part)
		if value < 0 or value > 255:
			return false
	var first := int(parts[0])
	var second := int(parts[1])
	if first == 10 or first == 127 or ip.begins_with("192.168.") or ip.begins_with("169.254."):
		return false
	if first == 172 and second >= 16 and second <= 31:
		return false
	# Carrier-grade NAT. These addresses are not reachable from other networks.
	if first == 100 and second >= 64 and second <= 127:
		return false
	if first == 0:
		return false
	return true


static func lan_addresses() -> PackedStringArray:
	var found := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)
	return found


static func load_relay_url() -> String:
	var config := ConfigFile.new()
	if config.load("user://relay.cfg") == OK:
		var chosen := str(config.get_value("relay", "url", "")).strip_edges()
		if not chosen.is_empty():
			return chosen
	if config.load("res://multiplayer/relay.cfg") == OK:
		var bundled := str(config.get_value("relay", "url", "")).strip_edges()
		if not bundled.is_empty():
			return bundled
	return local_url(DEFAULT_PORT)


static func host_packet(code: String) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(HOST)
	if valid_code(code):
		buf.put_data(code.to_utf8_buffer())
	return buf.data_array


static func host_ok(code: String) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(HOST_OK)
	buf.put_data(code.to_utf8_buffer())
	buf.put_u32(1)
	return buf.data_array


static func join_packet(code: String) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(JOIN)
	buf.put_data(code.to_utf8_buffer())
	return buf.data_array


static func join_ok(peer_id: int, code: String) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(JOIN_OK)
	buf.put_u32(peer_id)
	buf.put_data(code.to_utf8_buffer())
	return buf.data_array


static func error_packet(message: String) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(ERROR)
	buf.put_data(message.to_utf8_buffer())
	return buf.data_array


static func peer_joined(peer_id: int) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(PEER_JOINED)
	buf.put_u32(peer_id)
	return buf.data_array


static func peer_left(peer_id: int) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(PEER_LEFT)
	buf.put_u32(peer_id)
	return buf.data_array


static func kick_packet(peer_id: int) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(KICK)
	buf.put_u32(peer_id)
	return buf.data_array


static func refuse_packet(enabled: bool) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(REFUSE)
	buf.put_u8(1 if enabled else 0)
	return buf.data_array


static func data_packet(target: int, from_id: int, channel: int, mode: int, payload: PackedByteArray) -> PackedByteArray:
	var buf := _buf()
	buf.put_u8(DATA)
	buf.put_u32(target)
	buf.put_u32(from_id)
	buf.put_u8(clampi(channel, 0, 255))
	buf.put_u8(clampi(mode, 0, 255))
	if not payload.is_empty():
		buf.put_data(payload)
	return buf.data_array


static func discover_request(code: String) -> PackedByteArray:
	return (DISCOVER_ASK + code).to_utf8_buffer()


static func discover_response(port: int) -> PackedByteArray:
	var buf := _buf()
	buf.put_data(DISCOVER_ANSWER.to_utf8_buffer())
	buf.put_u16(port)
	return buf.data_array


static func parse_discover_response(packet: PackedByteArray) -> int:
	if packet.size() < 5:
		return 0
	if packet.slice(0, 3).get_string_from_utf8() != DISCOVER_ANSWER:
		return 0
	var buf := _buf()
	buf.data_array = packet
	buf.seek(3)
	return buf.get_u16()


static func parse(packet: PackedByteArray) -> Dictionary:
	var info := {
		"type": 0,
		"code": "",
		"peer_id": 0,
		"target": 0,
		"from": 0,
		"channel": 0,
		"mode": 0,
		"payload": PackedByteArray(),
		"message": "",
		"refusing": false,
	}
	if packet.is_empty():
		return info
	var buf := _buf()
	buf.data_array = packet
	buf.seek(0)
	info.type = buf.get_u8()
	match int(info.type):
		HOST:
			info.code = _read_code(buf) if buf.get_available_bytes() >= CODE_LENGTH else ""
		HOST_OK:
			info.code = _read_code(buf)
			info.peer_id = buf.get_u32() if buf.get_available_bytes() >= 4 else 0
		JOIN:
			info.code = _read_code(buf)
		JOIN_OK:
			info.peer_id = buf.get_u32() if buf.get_available_bytes() >= 4 else 0
			info.code = _read_code(buf)
		ERROR:
			info.message = _read_rest(buf).get_string_from_utf8()
		PEER_JOINED, PEER_LEFT, KICK:
			info.peer_id = buf.get_u32() if buf.get_available_bytes() >= 4 else 0
		DATA:
			if buf.get_available_bytes() < 10:
				info.type = 0
				return info
			info.target = buf.get_u32()
			info.from = buf.get_u32()
			info.channel = buf.get_u8()
			info.mode = buf.get_u8()
			info.payload = _read_rest(buf)
		REFUSE:
			info.refusing = buf.get_u8() != 0 if buf.get_available_bytes() >= 1 else false
		_:
			info.type = 0
	return info


static func _read_code(buf: StreamPeerBuffer) -> String:
	if buf.get_available_bytes() < CODE_LENGTH:
		return ""
	var result: Array = buf.get_data(CODE_LENGTH)
	if int(result[0]) != OK:
		return ""
	return (result[1] as PackedByteArray).get_string_from_utf8()


static func _read_rest(buf: StreamPeerBuffer) -> PackedByteArray:
	var remaining := buf.get_available_bytes()
	if remaining <= 0:
		return PackedByteArray()
	var result: Array = buf.get_data(remaining)
	if int(result[0]) != OK:
		return PackedByteArray()
	return result[1]
