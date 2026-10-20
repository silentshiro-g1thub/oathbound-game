extends Node
class_name RoomSession
## Hosts or joins a room code. Local, same-network, and internet lookups stay behind the code.

signal hosted(peer_id: int, room_code: String)
signal joined(peer_id: int, room_code: String)
signal failed(message: String)
signal notice(text: String)

const STEP_LOCAL := 1
const STEP_DISCOVER := 2
const STEP_LOOKUP := 3
const STEP_REMOTE := 4
const STEP_WAIT := 5
const STEP_DONE := 6

var peer: RelayMultiplayerPeer
var relay: RoomRelay
var hosting := false
var active := false
var sealed := false
var handed := false
var cancelled := false
var code := ""
var configured_url := ""
var listen_port := RoomProtocol.DEFAULT_PORT
var phase := 0
var step_elapsed := 0.0
var last_error := ""
var fail_queued := false
var remote_urls: PackedStringArray = PackedStringArray()
var remote_index := 0
var discover: PacketPeerUDP
var lookup_http: HTTPRequest
var publish_http: HTTPRequest
var lookup_done := false
var lookup_message := ""
var want_publish := false
var listed_public := false
var publish_started := false
var upnp_thread: Thread
var thread_joined := false
var upnp_mutex := Mutex.new()
var upnp_done := false
var upnp_ip := ""
var upnp_posted := false


func host(url: String, fixed_code: String, publish: bool) -> void:
	_begin()
	hosting = true
	configured_url = url
	listen_port = RoomProtocol.port_of(url)
	want_publish = publish and RoomProtocol.is_local_url(url) and not OS.has_feature("headless")
	if RoomProtocol.is_local_url(url):
		_ensure_relay(listen_port)
	phase = STEP_WAIT
	_attempt_host(url, fixed_code)


func join(room_code: String, direct_url: String, fallback_url: String) -> void:
	_begin()
	hosting = false
	code = room_code
	configured_url = fallback_url
	var target := direct_url if direct_url != "" else fallback_url
	listen_port = RoomProtocol.port_of(target)
	if direct_url != "":
		phase = STEP_WAIT
		_attempt_join(direct_url)
		return
	phase = STEP_LOCAL
	_attempt_join(RoomProtocol.local_url(listen_port))


func cancel() -> void:
	sealed = true
	active = false
	phase = STEP_DONE
	_close_discover()
	_abort_http()
	_drop_current_peer()
	if not handed:
		_stop_relay()


func shutdown() -> void:
	handed = false
	cancel()
	_stop_relay()
	_finish_thread()


func _begin() -> void:
	sealed = false
	cancelled = false
	handed = false
	active = true
	fail_queued = false
	publish_started = false
	upnp_posted = false
	listed_public = false
	last_error = ""
	step_elapsed = 0.0
	remote_urls = PackedStringArray()
	remote_index = 0
	lookup_done = false
	lookup_message = ""
	_close_discover()
	_abort_http()
	_drop_current_peer()


func _process(delta: float) -> void:
	if peer and not handed and not sealed:
		peer.service()
	if active and not sealed and not handed and not hosting:
		_advance_join(delta)
	_advance_publish()


func _advance_join(delta: float) -> void:
	step_elapsed += delta
	if phase == STEP_LOCAL and step_elapsed >= 0.6:
		_enter(STEP_DISCOVER)
	elif phase == STEP_DISCOVER:
		var found := _read_discovery()
		if found != "":
			_use_remote(PackedStringArray([found]))
		elif step_elapsed >= 0.8:
			_enter(STEP_LOOKUP)
	elif phase == STEP_LOOKUP and (lookup_done or step_elapsed >= 5.5):
		_use_remote(_urls_from_message(lookup_message))
	elif phase == STEP_REMOTE and step_elapsed >= _remote_budget():
		_next_remote()


func _enter(next: int) -> void:
	if sealed or handed or next <= phase:
		return
	phase = next
	step_elapsed = 0.0
	if next == STEP_DISCOVER:
		_close_peer_quiet()
		_open_discovery()
	elif next == STEP_LOOKUP:
		_close_discover()
		_close_peer_quiet()
		if OS.has_feature("headless"):
			_fail_final()
			return
		_start_lookup()


func _use_remote(urls: PackedStringArray) -> void:
	if sealed or handed or phase >= STEP_REMOTE:
		return
	remote_urls = urls
	remote_index = 0
	if remote_urls.is_empty():
		_fail_final()
		return
	phase = STEP_REMOTE
	step_elapsed = 0.0
	_attempt_join(remote_urls[0])


func _next_remote() -> void:
	if sealed or handed:
		return
	remote_index += 1
	if remote_index >= remote_urls.size():
		_fail_final()
		return
	step_elapsed = 0.0
	_attempt_join(remote_urls[remote_index])


func _remote_budget() -> float:
	if remote_index < 0 or remote_index >= remote_urls.size():
		return 1.0
	if RoomProtocol.is_public_ip(RoomProtocol.host_of(remote_urls[remote_index])):
		return 3.0
	return 0.9


func _attempt_host(url: String, fixed_code: String) -> void:
	_new_peer()
	peer.connect_and_host(url, fixed_code)


func _attempt_join(url: String) -> void:
	_new_peer()
	peer.connect_and_join(url, code)


func _new_peer() -> void:
	_drop_current_peer()
	peer = RelayMultiplayerPeer.new()
	peer.attempt_ready.connect(_on_attempt_ready)
	peer.attempt_failed.connect(_on_attempt_failed)


func _on_attempt_ready(peer_id: int, room_code: String) -> void:
	if sealed:
		return
	handed = true
	active = false
	code = room_code
	phase = STEP_DONE
	if hosting:
		hosted.emit(peer_id, room_code)
		_announce_host()
	else:
		joined.emit(peer_id, room_code)


func _announce_host() -> void:
	if not RoomProtocol.is_local_url(configured_url):
		notice.emit("Friends on any network can join with this code.")
		return
	if want_publish:
		notice.emit("Share this code. Opening it for other networks...")
		_start_publish()
		return
	notice.emit("Friends on your network can join with this code.")


func _on_attempt_failed(message: String) -> void:
	if sealed or handed or fail_queued:
		return
	last_error = message
	fail_queued = true
	call_deferred("_advance_after_failure")


func _advance_after_failure() -> void:
	fail_queued = false
	if sealed or handed:
		return
	if phase == STEP_WAIT:
		_fail_final()
	elif phase == STEP_LOCAL:
		_enter(STEP_DISCOVER)
	elif phase == STEP_DISCOVER:
		_enter(STEP_LOOKUP)
	elif phase == STEP_REMOTE:
		_next_remote()


func _fail_final() -> void:
	if sealed:
		return
	sealed = true
	active = false
	phase = STEP_DONE
	_close_discover()
	_close_peer_quiet()
	var message := last_error
	if message.contains("Unknown room"):
		message = "No room found for that code. Check the code and that the host is still in the game."
	elif message.is_empty():
		message = "Could not join that room."
	failed.emit(message)


func _ensure_relay(port: int) -> void:
	if relay and relay.is_listening() and relay.listen_port == port:
		return
	_stop_relay()
	relay = RoomRelay.new()
	if relay.start(port) != OK:
		relay = null
		return
	add_child(relay)


func _stop_relay() -> void:
	if relay == null:
		return
	var node := relay
	relay = null
	node.stop()
	if node.get_parent() == self and not is_queued_for_deletion():
		node.queue_free()


func _drop_current_peer() -> void:
	if peer == null:
		return
	var parent_node := get_parent()
	if parent_node and not parent_node.is_queued_for_deletion() and parent_node.multiplayer.multiplayer_peer == peer:
		parent_node.multiplayer.multiplayer_peer = null
	peer.shutdown()
	peer = null


func _close_peer_quiet() -> void:
	_drop_current_peer()


func _open_discovery() -> void:
	_close_discover()
	discover = PacketPeerUDP.new()
	if discover.bind(0) != OK:
		discover = null
		return
	discover.set_broadcast_enabled(true)
	var packet := RoomProtocol.discover_request(code)
	var dest_port := listen_port + 1
	discover.set_dest_address("255.255.255.255", dest_port)
	discover.put_packet(packet)
	for address in RoomProtocol.lan_addresses():
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		parts[3] = "255"
		discover.set_dest_address(".".join(parts), dest_port)
		discover.put_packet(packet)


func _read_discovery() -> String:
	if discover == null:
		return ""
	while discover.get_available_packet_count() > 0:
		var packet := discover.get_packet()
		var port := RoomProtocol.parse_discover_response(packet)
		var ip := discover.get_packet_ip()
		if port <= 0 or ip.is_empty() or ip == "0.0.0.0":
			continue
		return "ws://%s:%d" % [ip, port]
	return ""


func _close_discover() -> void:
	if discover:
		discover.close()
		discover = null


func _start_lookup() -> void:
	lookup_done = false
	lookup_message = ""
	lookup_http = HTTPRequest.new()
	lookup_http.timeout = 5.0
	add_child(lookup_http)
	lookup_http.request_completed.connect(_on_lookup)
	var error := lookup_http.request("https://ntfy.sh/%s/json?poll=1&since=20m" % RoomProtocol.topic_for(code))
	if error != OK:
		lookup_done = true


func _on_lookup(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	lookup_done = true
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		lookup_message = _latest_ntfy_message(body.get_string_from_utf8())
	if lookup_http:
		lookup_http.queue_free()
		lookup_http = null


func _start_publish() -> void:
	if publish_started:
		return
	publish_started = true
	upnp_done = false
	upnp_ip = ""
	upnp_posted = false
	thread_joined = false
	upnp_thread = Thread.new()
	upnp_thread.start(_upnp_work)


func _upnp_work() -> void:
	var public_ip := ""
	var mapper := UPNP.new()
	if mapper.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
		if mapper.add_port_mapping(listen_port, listen_port, "Oathbound", "TCP", 7200) == UPNP.UPNP_RESULT_SUCCESS:
			public_ip = mapper.query_external_address()
	upnp_mutex.lock()
	upnp_ip = public_ip
	upnp_done = true
	upnp_mutex.unlock()


func _advance_publish() -> void:
	if sealed or not publish_started or upnp_posted or upnp_thread == null:
		return
	upnp_mutex.lock()
	var done := upnp_done
	var public_ip := upnp_ip
	upnp_mutex.unlock()
	if not done:
		return
	upnp_posted = true
	_finish_thread()
	if sealed:
		return
	_post_listing(public_ip)


func _post_listing(public_ip: String) -> void:
	var urls: PackedStringArray = PackedStringArray()
	for address in RoomProtocol.lan_addresses():
		urls.append("ws://%s:%d" % [address, listen_port])
	listed_public = RoomProtocol.is_public_ip(public_ip)
	if listed_public:
		urls.append("ws://%s:%d" % [public_ip, listen_port])
	if urls.is_empty():
		notice.emit("Friends on your network can join with this code. No address could be listed for other networks.")
		return
	publish_http = HTTPRequest.new()
	publish_http.timeout = 8.0
	add_child(publish_http)
	publish_http.request_completed.connect(_on_published)
	var error := publish_http.request(
		"https://ntfy.sh/%s" % RoomProtocol.topic_for(code),
		PackedStringArray(["Content-Type: text/plain; charset=utf-8"]),
		HTTPClient.METHOD_POST,
		"\n".join(urls)
	)
	if error != OK:
		notice.emit("Friends on your network can join with this code. The code could not be listed for other networks.")


func _on_published(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var listed := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if publish_http:
		publish_http.queue_free()
		publish_http = null
	if sealed:
		return
	if listed and listed_public:
		notice.emit("Friends on other networks can join with this code.")
	elif listed_public:
		notice.emit("The router port is open, but the code could not be listed for other networks.")
	else:
		notice.emit("Friends on your network can join with this code. This router did not open a port for other networks.")


func _finish_thread() -> void:
	if upnp_thread == null or thread_joined:
		return
	if upnp_thread.is_started():
		upnp_thread.wait_to_finish()
	thread_joined = true
	upnp_thread = null


func _abort_http() -> void:
	if lookup_http:
		lookup_http.cancel_request()
		lookup_http.queue_free()
		lookup_http = null
	if publish_http:
		publish_http.cancel_request()
		publish_http.queue_free()
		publish_http = null


func _urls_from_message(message: String) -> PackedStringArray:
	var public_urls := PackedStringArray()
	var private_urls := PackedStringArray()
	for line in message.split("\n"):
		var url := line.strip_edges()
		if not (url.begins_with("ws://") or url.begins_with("wss://")):
			continue
		if RoomProtocol.is_local_url(url):
			continue
		if RoomProtocol.is_public_ip(RoomProtocol.host_of(url)):
			public_urls.append(url)
		else:
			private_urls.append(url)
	var ordered := PackedStringArray()
	ordered.append_array(public_urls)
	ordered.append_array(private_urls)
	return ordered


func _latest_ntfy_message(body: String) -> String:
	var latest := ""
	for line in body.split("\n"):
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary and parsed.has("message"):
			latest = str(parsed.message)
	return latest


func _exit_tree() -> void:
	shutdown()
