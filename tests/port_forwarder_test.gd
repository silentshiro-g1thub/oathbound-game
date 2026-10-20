extends SceneTree
## PortForwarder checks against a fake NAT-PMP router on loopback.
## No real router is contacted and nothing outside the game is configured.

const FAKE_PORT := 35351
const GAME_PORT := 27950
const FAKE_PUBLIC_IP := "203.0.113.7"
const FAKE_ASSIGNED_PORT := 40000

var ok := true


class FakeRouter:
	extends Node
	var udp := PacketPeerUDP.new()
	var refuse_suggested := false
	var silent := false
	var seen_addresses := 0
	var seen_maps: Array = []

	func _ready() -> void:
		assert(udp.bind(FAKE_PORT, "127.0.0.1") == OK)

	func _process(_delta: float) -> void:
		while udp.get_available_packet_count() > 0:
			var packet := udp.get_packet()
			var from_ip := udp.get_packet_ip()
			var from_port := udp.get_packet_port()
			if silent or packet.size() < 4 or packet[0] != 0:
				continue
			var opcode := int(packet[1])
			if opcode == 0:
				seen_addresses += 1
				_reply_address(from_ip, from_port)
			elif opcode == 1 or opcode == 2:
				if packet.size() < 12:
					continue
				var internal := (int(packet[4]) << 8) | int(packet[5])
				var suggested := (int(packet[6]) << 8) | int(packet[7])
				var lifetime := (int(packet[8]) << 24) | (int(packet[9]) << 16) | (int(packet[10]) << 8) | int(packet[11])
				var external := suggested if suggested != 0 else FAKE_ASSIGNED_PORT
				var result := 0
				if refuse_suggested and suggested != 0 and lifetime > 0:
					result = 2
					external = 0
				seen_maps.append({"opcode": opcode, "internal": internal, "suggested": suggested, "lifetime": lifetime, "result": result})
				_reply_map(from_ip, from_port, opcode, internal, external, lifetime if result == 0 else 0, result)

	func _reply_address(to_ip: String, to_port: int) -> void:
		var buf := _buffer()
		buf.put_u8(0)
		buf.put_u8(128)
		buf.put_u16(0)
		for part in FAKE_PUBLIC_IP.split("."):
			buf.put_u8(int(part))
		udp.set_dest_address(to_ip, to_port)
		udp.put_packet(buf.data_array)

	func _reply_map(to_ip: String, to_port: int, opcode: int, internal: int, external: int, lifetime: int, result: int) -> void:
		var buf := _buffer()
		buf.put_u8(0)
		buf.put_u8(opcode + 128)
		buf.put_u16(result)
		buf.put_u16(internal)
		buf.put_u16(external)
		buf.put_u32(lifetime)
		udp.set_dest_address(to_ip, to_port)
		udp.put_packet(buf.data_array)

	func _buffer() -> StreamPeerBuffer:
		var buf := StreamPeerBuffer.new()
		buf.big_endian = true
		return buf


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	ok = false
	push_error("FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_test_packets()
	_test_route_parsing()
	if ok:
		await _test_open_renew_close()
	if ok:
		await _test_exit_releases()
	if ok:
		await _test_refused_port()
	if ok:
		await _test_silent_router()
	if ok:
		print("PASS: the router port opens, renews, and closes without touching a router page")
	quit(0 if ok else 1)


func _test_packets() -> void:
	var request := PortForwarder.natpmp_map_request(27950, 27950, 7200, 2)
	_expect(request.size() == 12 and request[0] == 0 and request[1] == 2, "TCP mapping request has the NAT-PMP header")
	_expect(((int(request[4]) << 8) | int(request[5])) == 27950, "ports travel in network byte order")
	_expect(((int(request[8]) << 24) | (int(request[9]) << 16) | (int(request[10]) << 8) | int(request[11])) == 7200, "the lease travels in network byte order")
	var address_reply := StreamPeerBuffer.new()
	address_reply.big_endian = true
	address_reply.put_u8(0)
	address_reply.put_u8(128)
	address_reply.put_u16(0)
	address_reply.put_u8(198)
	address_reply.put_u8(51)
	address_reply.put_u8(100)
	address_reply.put_u8(9)
	var parsed := PortForwarder.natpmp_parse(address_reply.data_array)
	_expect(parsed.ok and parsed.address == "198.51.100.9", "public address replies are read")
	var map_reply := StreamPeerBuffer.new()
	map_reply.big_endian = true
	map_reply.put_u8(0)
	map_reply.put_u8(130)
	map_reply.put_u16(0)
	map_reply.put_u16(27950)
	map_reply.put_u16(41000)
	map_reply.put_u32(3600)
	var mapped := PortForwarder.natpmp_parse(map_reply.data_array)
	_expect(mapped.ok and mapped.external_port == 41000 and mapped.lifetime == 3600, "mapping replies are read")
	map_reply.seek(2)
	map_reply.put_u16(2)
	var refused := PortForwarder.natpmp_parse(map_reply.data_array)
	_expect(not refused.ok and refused.result == 2, "refusals keep their result code")
	_expect(not PortForwarder.natpmp_parse(PackedByteArray([0, 128, 0])).ok, "short replies are rejected")
	_expect(not PortForwarder.natpmp_parse(PackedByteArray([9, 128, 0, 0, 1, 1, 1, 1])).ok, "replies from another protocol version are rejected")
	_expect(PortForwarder.natpmp_result_text(2).contains("refused"), "refusals have readable text")


func _test_route_parsing() -> void:
	var windows := "IPv4 Route Table\nActive Routes:\nNetwork Destination        Netmask          Gateway       Interface  Metric\n          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.50     25\n        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331\nPersistent Routes:\n  None\n"
	_expect(PortForwarder.gateway_from_route_output(windows) == "192.168.1.1", "Windows route tables name the gateway")
	var linux := "default via 10.0.0.1 dev eth0 proto dhcp src 10.0.0.2 metric 100\n"
	_expect(PortForwarder.gateway_from_route_output(linux) == "10.0.0.1", "Linux route tables name the gateway")
	var macos := "   route to: default\ndestination: default\n       mask: default\n    gateway: 172.16.0.1\n  interface: en0\n"
	_expect(PortForwarder.gateway_from_route_output(macos) == "172.16.0.1", "macOS route tables name the gateway")
	_expect(PortForwarder.gateway_from_route_output("nothing useful here") == "", "unreadable route output yields no gateway")
	_expect(PortForwarder.gateway_from_route_output("0.0.0.0 0.0.0.0 On-link 127.0.0.1") == "", "on-link defaults are not gateways")
	_expect(PortForwarder.is_ipv4_address("192.168.0.1"), "plain addresses pass the check")
	_expect(not PortForwarder.is_ipv4_address("192.168.0.256") and not PortForwarder.is_ipv4_address("192.168.0"), "broken addresses fail the check")


func _forwarder() -> PortForwarder:
	var forwarder := PortForwarder.new()
	forwarder.skip_upnp = true
	forwarder.gateway_override = "127.0.0.1"
	forwarder.natpmp_port_override = FAKE_PORT
	root.add_child(forwarder)
	return forwarder


func _record(forwarder: PortForwarder, events: Array) -> void:
	forwarder.opened.connect(func(port: int, ip: String, used: String) -> void:
		events.append("opened:%d:%s:%s" % [port, ip, used])
	)
	forwarder.renewed.connect(func(port: int, ip: String) -> void:
		events.append("renewed:%d:%s" % [port, ip])
	)
	forwarder.failed.connect(func(reason: String) -> void:
		events.append("failed:" + reason)
	)
	forwarder.closed.connect(func() -> void:
		events.append("closed")
	)


func _wait_until(condition: Callable, milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await create_timer(0.01).timeout


func _test_open_renew_close() -> void:
	var router := FakeRouter.new()
	root.add_child(router)
	var forwarder := _forwarder()
	var events: Array = []
	_record(forwarder, events)

	forwarder.open_port(GAME_PORT)
	await _wait_until(func() -> bool: return not events.is_empty(), 5000)
	_expect(events == ["opened:%d:%s:%s" % [GAME_PORT, FAKE_PUBLIC_IP, PortForwarder.METHOD_NATPMP]], "opening reports the mapped port and public address: %s" % str(events))
	_expect(forwarder.is_open(), "the forwarder counts itself open")
	_expect(forwarder.renew_interval == 1800.0, "renewal waits half the lease, capped at thirty minutes")
	_expect(router.seen_addresses == 1, "the router was asked for the public address once")
	_expect(router.seen_maps.size() == 1 and int(router.seen_maps[0].opcode) == 2, "the TCP relay port is mapped")
	_expect(int(router.seen_maps[0].lifetime) == 7200, "the mapping asks for a two hour lease")

	events.clear()
	forwarder.renew_now()
	await _wait_until(func() -> bool: return not events.is_empty(), 5000)
	_expect(events == ["renewed:%d:%s" % [GAME_PORT, FAKE_PUBLIC_IP]], "renewal keeps the same port and address: %s" % str(events))
	_expect(router.seen_maps.size() == 2, "renewal re-requests the mapping")
	_expect(int(router.seen_maps[1].lifetime) == 7200, "renewal asks for the same lease again")

	events.clear()
	forwarder.close_port()
	await _wait_until(func() -> bool: return not events.is_empty(), 5000)
	_expect(events == ["closed"], "closing reports back: %s" % str(events))
	_expect(int(router.seen_maps.back().lifetime) == 0, "closing releases the router lease")
	_expect(not forwarder.is_open(), "the forwarder forgets the mapping")
	forwarder.free()
	router.free()
	await process_frame


func _test_exit_releases() -> void:
	var router := FakeRouter.new()
	root.add_child(router)
	var forwarder := _forwarder()
	var events: Array = []
	_record(forwarder, events)

	forwarder.open_port(GAME_PORT + 3)
	await _wait_until(func() -> bool: return forwarder.is_open(), 5000)
	_expect(forwarder.is_open(), "the forwarder is open before shutdown: %s" % str(events))
	forwarder.free()
	# The release packet sits in the fake router's socket until its next frame.
	await process_frame
	await process_frame
	_expect(router.seen_maps.size() >= 2, "shutdown asks the router to release the port")
	_expect(int(router.seen_maps.back().lifetime) == 0, "shutdown releases the router lease")
	router.free()
	await process_frame


func _test_refused_port() -> void:
	var router := FakeRouter.new()
	router.refuse_suggested = true
	root.add_child(router)
	var forwarder := _forwarder()
	var events: Array = []
	_record(forwarder, events)

	forwarder.open_port(GAME_PORT + 1)
	await _wait_until(func() -> bool: return not events.is_empty(), 5000)
	_expect(events == ["opened:%d:%s:%s" % [FAKE_ASSIGNED_PORT, FAKE_PUBLIC_IP, PortForwarder.METHOD_NATPMP]], "a refused public port is retried without a preference: %s" % str(events))
	_expect(int(router.seen_maps.back().suggested) == 0, "the retry drops the preferred public port")
	forwarder.free()
	router.free()
	await process_frame


func _test_silent_router() -> void:
	var router := FakeRouter.new()
	router.silent = true
	root.add_child(router)
	var forwarder := _forwarder()
	var events: Array = []
	_record(forwarder, events)

	forwarder.open_port(GAME_PORT + 2)
	await _wait_until(func() -> bool: return not events.is_empty(), 6000)
	_expect(events.size() == 1 and str(events[0]).begins_with("failed:"), "a router that never answers fails cleanly: %s" % str(events))
	_expect(not forwarder.is_open(), "a silent router leaves nothing open")
	forwarder.free()
	router.free()
	await process_frame
