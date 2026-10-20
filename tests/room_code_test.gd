extends SceneTree

var ok := true


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	ok = false
	push_error("FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var framer_script: GDScript = load("res://multiplayer/room_framer.gd")
	if framer_script == null or not framer_script.can_instantiate():
		push_error("FAIL: room framer did not compile")
		quit(1)
		return
	_test_protocol()
	if ok:
		await _test_gameplay_packets()
	if ok:
		await _test_unknown_room()
	if ok:
		print("PASS: room codes relay a host, a join, and gameplay packets")
	quit(0 if ok else 1)


func _test_protocol() -> void:
	assert(RoomProtocol.normalize_code("abc def") == "ABCDEF")
	assert(RoomProtocol.normalize_code("test-ab") == "TESTAB")
	assert(RoomProtocol.valid_code("TESTAB"))
	assert(not RoomProtocol.valid_code("TEST01"))
	assert(RoomProtocol.port_of("ws://127.0.0.1:19999") == 19999)
	assert(RoomProtocol.is_local_url("ws://127.0.0.1:9050"))
	assert(RoomProtocol.is_public_ip("8.8.8.8"))
	assert(not RoomProtocol.is_public_ip("192.168.0.20"))
	assert(not RoomProtocol.is_public_ip("100.64.1.1"))
	var opened := RoomProtocol.parse(RoomProtocol.host_ok("TESTAB"))
	assert(opened.type == RoomProtocol.HOST_OK and opened.code == "TESTAB" and opened.peer_id == 1)
	var payload := PackedByteArray([9, 8, 7])
	var forwarded := RoomProtocol.parse(RoomProtocol.data_packet(1, 4, 2, MultiplayerPeer.TRANSFER_MODE_RELIABLE, payload))
	assert(forwarded.type == RoomProtocol.DATA)
	assert(forwarded.target == 1 and forwarded.from == 4 and forwarded.channel == 2)
	assert(forwarded.payload == payload)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _index in 20:
		assert(RoomProtocol.valid_code(RoomProtocol.random_code(rng)))


func _test_gameplay_packets() -> void:
	var relay := RoomRelay.new()
	assert(relay.start(27905) == OK)
	root.add_child(relay)

	var host_peer := RelayMultiplayerPeer.new()
	var host_box := {"code": "", "id": 0}
	host_peer.attempt_ready.connect(func(peer_id: int, code: String) -> void:
		host_box.id = peer_id
		host_box.code = code
	)
	host_peer.connect_and_host("ws://127.0.0.1:27905", "TESTAB")
	for _frame in 90:
		relay.poll_network()
		host_peer.service()
		if str(host_box.code) != "":
			break
		await process_frame
	_expect(str(host_box.code) == "TESTAB" and int(host_box.id) == 1 and host_peer.is_live() and host_peer._is_server(), "host did not open TESTAB")
	if not ok:
		return

	var host_world := Node.new()
	host_world.name = "HostWorld"
	root.add_child(host_world)
	var host_api := SceneMultiplayer.new()
	set_multiplayer(host_api, host_world.get_path())
	host_api.multiplayer_peer = host_peer
	host_peer.mark_handed_off()
	var host_ping: Node = load("res://tests/room_ping.gd").new()
	host_ping.name = "Ping"
	host_world.add_child(host_ping)

	var client_peer := RelayMultiplayerPeer.new()
	var client_box := {"id": 0, "code": ""}
	client_peer.attempt_ready.connect(func(peer_id: int, code: String) -> void:
		client_box.id = peer_id
		client_box.code = code
	)
	client_peer.connect_and_join("ws://127.0.0.1:27905", "TESTAB")
	for _frame in 90:
		relay.poll_network()
		host_peer.service()
		client_peer.service()
		if int(client_box.id) > 1 and host_api.get_peers().has(int(client_box.id)):
			break
		await process_frame
	var client_id := int(client_box.id)
	_expect(client_id > 1 and str(client_box.code) == "TESTAB", "client did not join TESTAB")
	_expect(host_api.get_peers().has(client_id), "host did not see the client")
	if not ok:
		return

	var client_world := Node.new()
	client_world.name = "ClientWorld"
	root.add_child(client_world)
	var client_api := SceneMultiplayer.new()
	set_multiplayer(client_api, client_world.get_path())
	client_api.multiplayer_peer = client_peer
	client_peer.mark_handed_off()
	var client_ping: Node = load("res://tests/room_ping.gd").new()
	client_ping.name = "Ping"
	client_world.add_child(client_ping)
	for _frame in 30:
		if client_api.get_peers().has(1):
			break
		await process_frame
	_expect(client_api.get_peers().has(1), "client did not see the host")
	if not ok:
		return

	host_ping.rpc("ping", "hello")
	for _frame in 40:
		if client_ping.got.has("1:hello"):
			break
		await process_frame
	_expect(client_ping.got.has("1:hello"), "client did not receive the host packet: %s" % str(client_ping.got))

	client_ping.rpc_id(1, "ping", "back")
	for _frame in 40:
		if host_ping.got.has("%d:back" % client_id):
			break
		await process_frame
	_expect(host_ping.got.has("%d:back" % client_id), "host did not receive the client packet: %s" % str(host_ping.got))

	host_peer.shutdown()
	client_peer.shutdown()
	relay.queue_free()
	await process_frame


func _test_unknown_room() -> void:
	var relay := RoomRelay.new()
	assert(relay.start(27906) == OK)
	root.add_child(relay)
	var stranger := RelayMultiplayerPeer.new()
	var failure := {"message": ""}
	stranger.attempt_failed.connect(func(reason: String) -> void:
		failure.message = reason
	)
	stranger.connect_and_join("ws://127.0.0.1:27906", "ZZZZZZ")
	for _frame in 40:
		relay.poll_network()
		stranger.service()
		if str(failure.message) != "":
			break
		await process_frame
	_expect(str(failure.message).contains("Unknown room"), "unknown code returned '%s'" % failure.message)
	stranger.shutdown()
	relay.queue_free()
	await process_frame
