extends RefCounted
class_name RoomFramer
## Length-prefixed packets over one TCP stream.

const MAX_FRAME := 8 * 1024 * 1024

var stream: StreamPeerTCP
var needed := -1
var pending := PackedByteArray()
var outbound := PackedByteArray()


func poll_stream() -> void:
	if stream:
		stream.poll()


func stream_ready() -> bool:
	return stream != null and stream.get_status() == StreamPeerTCP.STATUS_CONNECTED


func is_connecting() -> bool:
	return stream != null and stream.get_status() == StreamPeerTCP.STATUS_CONNECTING


func broken() -> bool:
	if needed < -1 or stream == null:
		return true
	var status := stream.get_status()
	return status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE


func queue_packet(packet: PackedByteArray) -> Error:
	if packet.is_empty() or packet.size() > MAX_FRAME:
		return ERR_INVALID_DATA
	var header := StreamPeerBuffer.new()
	header.big_endian = false
	header.put_u32(packet.size())
	outbound.append_array(header.data_array)
	outbound.append_array(packet)
	return flush()


func flush() -> Error:
	if stream == null:
		return ERR_UNCONFIGURED
	while outbound.size() > 0:
		var result: Array = stream.put_partial_data(outbound)
		var error := int(result[0])
		var sent := int(result[1])
		if sent > 0:
			outbound = outbound.slice(sent)
		if error != OK:
			return ERR_CONNECTION_ERROR
		if sent == 0:
			return OK
	return OK


func take_packets() -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	if stream == null:
		return packets
	while true:
		if needed < 0:
			if stream.get_available_bytes() < 4:
				break
			var header_read: Array = stream.get_data(4)
			if int(header_read[0]) != OK:
				needed = -2
				break
			var header := StreamPeerBuffer.new()
			header.big_endian = false
			header.data_array = header_read[1]
			needed = int(header.get_u32())
			pending = PackedByteArray()
			if needed <= 0 or needed > MAX_FRAME:
				needed = -2
				break
		var available := stream.get_available_bytes()
		if available <= 0:
			break
		var take := mini(needed - pending.size(), available)
		var body_read: Array = stream.get_data(take)
		if int(body_read[0]) != OK:
			needed = -2
			break
		pending.append_array(body_read[1])
		if pending.size() == needed:
			packets.append(pending)
			pending = PackedByteArray()
			needed = -1
	return packets
