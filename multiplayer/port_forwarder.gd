extends Node
class_name PortForwarder
## Opens the game's port on the home router from inside the game, so rooms are
## reachable from other networks without anyone visiting the router page.
## UPnP is tried first; NAT-PMP is tried when the router speaks that instead.
## The lease is renewed while the room lives and released on exit, so long
## sessions keep working and the port is not left behind.

signal opened(external_port: int, public_ip: String, method: String)
signal renewed(external_port: int, public_ip: String)
signal failed(reason: String)
signal closed

const METHOD_UPNP := "UPnP"
const METHOD_NATPMP := "NAT-PMP"
const DEFAULT_LEASE := 7200
const NATPMP_GATEWAY_PORT := 5351
const DESCRIPTION := "Oathbound"
const PROTOCOL_TCP := "TCP"
const NATPMP_REFUSED := 2
## One wait per attempt, growing a little each time like RFC 6886 asks.
const NATPMP_WAITS := [0.4, 0.7, 1.1]
## Renewal failures tolerated before the mapping counts as lost.
const MAX_RENEW_FAILURES := 3

## Tests aim these at a fake router on loopback; live games leave them alone.
var lease_seconds := DEFAULT_LEASE
var skip_upnp := false
var gateway_override := ""
var natpmp_port_override := 0

var internal_port := 0
var external_port := 0
var public_ip := ""
var active_method := ""
var renew_interval := 0.0
var since_renew := 0.0
var renew_failures := 0
var opening := false
var renewing := false
var closing := false
var want_close := false

var _thread: Thread
var _mutex := Mutex.new()
var _result: Dictionary = {}
var _upnp_gateway: UPNP
var _natpmp_gateway := ""
var _granted_lifetime := 0


## Ask the router to open [param port] for the room relay and report back through
## the opened, renewed, failed, and closed signals.
func open_port(port: int) -> void:
	if _thread != null or (opening or (active_method != "" and internal_port == port)):
		return
	internal_port = port
	external_port = 0
	public_ip = ""
	active_method = ""
	opening = true
	since_renew = 0.0
	renew_failures = 0
	_start_job({"kind": "open"})


## Refresh the lease immediately; the timer calls this halfway through it.
func renew_now() -> void:
	if _thread != null or opening or active_method == "":
		return
	renewing = true
	_start_job({"kind": "renew"})


## Release the router mapping. Safe to call at any time, including on exit.
func close_port() -> void:
	if closing:
		return
	if _thread != null:
		want_close = true
		return
	if active_method == "" and not opening:
		return
	closing = true
	_start_job({"kind": "close"})


func is_open() -> bool:
	return active_method != "" and not opening


func _process(delta: float) -> void:
	if _thread != null:
		if not _thread.is_alive():
			_thread.wait_to_finish()
			_thread = null
			_take_result()
		else:
			return
	if active_method != "" and not closing and not renewing:
		since_renew += delta
		if since_renew >= renew_interval:
			renew_now()
	if want_close and _thread == null:
		want_close = false
		close_port()


func _start_job(job: Dictionary) -> void:
	_thread = Thread.new()
	_thread.start(_work.bind(job))


## Network calls block, so all router traffic stays on the worker thread.
func _work(job: Dictionary) -> void:
	var posted: Dictionary
	match str(job.kind):
		"open":
			posted = _work_open()
		"renew":
			posted = _work_renew()
		"close":
			posted = _work_close()
		_:
			posted = {}
	_mutex.lock()
	_result = posted
	_mutex.unlock()


func _take_result(silent := false) -> void:
	_mutex.lock()
	var posted := _result
	_result = {}
	_mutex.unlock()
	if posted.is_empty():
		return
	opening = false
	renewing = false
	closing = false
	var granted := int(posted.get("lifetime", 0))
	match str(posted.kind):
		"opened":
			active_method = str(posted.method)
			external_port = int(posted.external_port)
			public_ip = str(posted.public_ip)
			renew_interval = _next_renewal(granted)
			since_renew = 0.0
			renew_failures = 0
			if not silent:
				opened.emit(external_port, public_ip, active_method)
		"renewed":
			external_port = int(posted.external_port)
			public_ip = str(posted.public_ip)
			renew_interval = _next_renewal(granted)
			since_renew = 0.0
			renew_failures = 0
			if not silent:
				renewed.emit(external_port, public_ip)
		"renew_failed":
			renew_failures += 1
			if renew_failures >= MAX_RENEW_FAILURES:
				active_method = ""
				if not silent:
					failed.emit("The router stopped keeping the port open.")
		"failed":
			active_method = ""
			if not silent:
				failed.emit(str(posted.reason))
		"closed":
			active_method = ""
			if not silent:
				closed.emit()


## Renew halfway through the lease the router actually granted, within limits.
func _next_renewal(granted: int) -> float:
	var span := granted if granted > 0 else lease_seconds
	return clampf(float(span) * 0.5, 15.0, 1800.0)


func _work_open() -> Dictionary:
	if not skip_upnp:
		var via_upnp := _try_upnp()
		if not via_upnp.is_empty():
			return via_upnp
	var via_natpmp := _try_natpmp()
	if not via_natpmp.is_empty():
		return via_natpmp
	return {"kind": "failed", "reason": "This router answers to neither UPnP nor NAT-PMP."}


func _work_renew() -> Dictionary:
	if active_method == METHOD_UPNP and _upnp_gateway != null:
		if _upnp_add(_upnp_gateway):
			return {"kind": "renewed", "external_port": internal_port, "public_ip": _upnp_gateway.query_external_address(), "lifetime": lease_seconds}
		return {"kind": "renew_failed", "reason": "The router refused to renew the port."}
	if active_method == METHOD_NATPMP and not _natpmp_gateway.is_empty():
		var socket := _natpmp_socket()
		if socket != null:
			var mapped := _natpmp_map(socket, 2)
			var reply := _natpmp_exchange(socket, natpmp_address_request(), 0)
			socket.close()
			if mapped > 0:
				return {"kind": "renewed", "external_port": mapped, "public_ip": str(reply.address), "lifetime": _granted_lifetime}
		return {"kind": "renew_failed", "reason": "The router stopped answering about the port."}
	return {"kind": "renew_failed", "reason": "Nothing is holding the port open."}


func _work_close() -> Dictionary:
	if active_method == METHOD_UPNP and _upnp_gateway != null:
		_upnp_gateway.remove_port_mapping(external_port, PROTOCOL_TCP)
	elif active_method == METHOD_NATPMP and not _natpmp_gateway.is_empty():
		var socket := _natpmp_socket()
		if socket != null:
			_natpmp_exchange(socket, natpmp_map_request(internal_port, external_port, 0, 2), 2)
			socket.close()
	return {"kind": "closed"}


func _try_upnp() -> Dictionary:
	var mapper := UPNP.new()
	if mapper.discover(2000, 2, "InternetGatewayDevice") != UPNP.UPNP_RESULT_SUCCESS:
		return {}
	var gateway := mapper.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {}
	if not _upnp_add(mapper):
		return {}
	# Only the TCP relay port is mapped. Friend discovery is LAN broadcast and
	# never crosses the internet, so it needs no hole in the router.
	_upnp_gateway = mapper
	return {"kind": "opened", "method": METHOD_UPNP, "external_port": internal_port, "public_ip": mapper.query_external_address(), "lifetime": lease_seconds}


func _upnp_add(mapper: UPNP) -> bool:
	if mapper.add_port_mapping(internal_port, internal_port, DESCRIPTION, PROTOCOL_TCP, lease_seconds) == UPNP.UPNP_RESULT_SUCCESS:
		return true
	# Some routers refuse leases; a permanent mapping still works because
	# renewals refresh it on the same schedule.
	return mapper.add_port_mapping(internal_port, internal_port, DESCRIPTION, PROTOCOL_TCP, 0) == UPNP.UPNP_RESULT_SUCCESS


func _try_natpmp() -> Dictionary:
	var socket := _natpmp_socket()
	if socket == null:
		return {}
	var address_reply := _natpmp_exchange(socket, natpmp_address_request(), 0)
	var address := str(address_reply.address)
	if address.is_empty():
		socket.close()
		return {}
	var mapped := _natpmp_map(socket, 2)
	socket.close()
	if mapped < 0:
		return {}
	_natpmp_gateway = _current_gateway()
	return {"kind": "opened", "method": METHOD_NATPMP, "external_port": mapped, "public_ip": address, "lifetime": _granted_lifetime}


func _natpmp_socket() -> PacketPeerUDP:
	var gateway := _current_gateway()
	if gateway.is_empty():
		return null
	var socket := PacketPeerUDP.new()
	if socket.bind(0) != OK:
		return null
	var port := natpmp_port_override if natpmp_port_override > 0 else NATPMP_GATEWAY_PORT
	socket.set_dest_address(gateway, port)
	return socket


func _current_gateway() -> String:
	return gateway_override.strip_edges() if not gateway_override.strip_edges().is_empty() else detect_gateway()


## Map one TCP port and return the public port the router chose, or -1.
func _natpmp_map(socket: PacketPeerUDP, opcode: int) -> int:
	var suggested := internal_port
	for _attempt in 4:
		var reply := _natpmp_exchange(socket, natpmp_map_request(internal_port, suggested, lease_seconds, opcode), opcode)
		if int(reply.result) == 0 and int(reply.external_port) > 0:
			_granted_lifetime = int(reply.lifetime)
			return int(reply.external_port)
		if int(reply.result) == NATPMP_REFUSED and suggested != 0:
			# RFC 6886: a refused public port means ask again without a preference.
			suggested = 0
	return -1


## Send one request and read its reply. Returns a parse result whose "result"
## is -1 when the router never answered.
func _natpmp_exchange(socket: PacketPeerUDP, request: PackedByteArray, opcode: int) -> Dictionary:
	var timeout := {"ok": false, "opcode": -1, "result": -1, "external_port": 0, "lifetime": 0, "address": ""}
	for attempt in NATPMP_WAITS.size():
		if socket.put_packet(request) != OK:
			break
		var deadline := float(NATPMP_WAITS[attempt])
		while deadline > 0.0:
			if socket.get_available_packet_count() > 0:
				var reply := natpmp_parse(socket.get_packet())
				if int(reply.opcode) == opcode + 128:
					return reply
				break
			OS.delay_msec(40)
			deadline -= 0.04
	return timeout


func _exit_tree() -> void:
	want_close = false
	if _thread != null:
		# Let an in-flight job finish so the router mapping is released.
		_thread.wait_to_finish()
		_thread = null
		_take_result(true)
	if active_method != "":
		# No signals at exit; just hand the port back to the router.
		_work_close()
		active_method = ""


static func natpmp_address_request() -> PackedByteArray:
	var buf := _natpmp_buffer()
	buf.put_u8(0)
	buf.put_u8(0)
	buf.put_u16(0)
	return buf.data_array


static func natpmp_map_request(port: int, external_port: int, lifetime: int, opcode: int) -> PackedByteArray:
	var buf := _natpmp_buffer()
	buf.put_u8(0)
	buf.put_u8(opcode)
	buf.put_u16(0)
	buf.put_u16(port)
	buf.put_u16(external_port)
	buf.put_u32(lifetime)
	return buf.data_array


## Parse a NAT-PMP reply. "ok" means success; refusals keep "result" so the
## caller can retry the way RFC 6886 describes.
static func natpmp_parse(packet: PackedByteArray) -> Dictionary:
	var info := {"ok": false, "opcode": -1, "result": -1, "external_port": 0, "lifetime": 0, "address": ""}
	if packet.size() < 4 or packet[0] != 0:
		return info
	var buf := _natpmp_buffer()
	buf.data_array = packet
	buf.seek(1)
	info.opcode = buf.get_u8()
	info.result = buf.get_u16()
	if int(info.result) != 0:
		return info
	match int(info.opcode):
		128:
			if packet.size() < 8:
				return info
			info.address = "%d.%d.%d.%d" % [packet[4], packet[5], packet[6], packet[7]]
			info.ok = true
		129, 130:
			if packet.size() < 12:
				return info
			buf.seek(6)
			info.external_port = buf.get_u16()
			info.lifetime = buf.get_u32()
			info.ok = true
	return info


static func natpmp_result_text(code: int) -> String:
	match code:
		1:
			return "the router speaks a newer NAT-PMP version"
		2:
			return "the router refused the request"
		3:
			return "the router reported a network failure"
		4:
			return "the router is out of mappings"
		5:
			return "the router does not support this operation"
		_:
			return "no reply from the router"


## Find the default gateway by asking the operating system's route table, with
## the usual home-router address as a last resort.
static func detect_gateway() -> String:
	var output: Array = []
	match OS.get_name():
		"Windows":
			OS.execute("route", ["print", "-4"], output)
		"macOS":
			OS.execute("route", ["-n", "get", "default"], output)
		_:
			OS.execute("ip", ["route", "show", "default"], output)
	var lines := PackedStringArray()
	for line in output:
		lines.append(str(line))
	var found := gateway_from_route_output("\n".join(lines))
	return subnet_gateway() if found.is_empty() else found


## Read a default gateway out of `route print -4`, `ip route show default`,
## or `route -n get default` output.
static func gateway_from_route_output(output: String) -> String:
	for line in output.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		# Linux: "default via 192.168.1.1 dev wlan0 proto dhcp ..."
		if trimmed.begins_with("default via "):
			var columns := trimmed.split(" ", false)
			if columns.size() >= 3 and is_ipv4_address(columns[2]):
				return columns[2]
			continue
		# macOS: "    gateway: 192.168.1.1"
		if trimmed.begins_with("gateway:"):
			var gateway := trimmed.trim_prefix("gateway:").strip_edges()
			if is_ipv4_address(gateway):
				return gateway
			continue
		# Windows: "0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.50     25"
		var route := trimmed.split(" ", false)
		if route.size() >= 3 and route[0] == "0.0.0.0" and route[1] == "0.0.0.0":
			if route[2] != "0.0.0.0" and is_ipv4_address(route[2]):
				return route[2]
	return ""


## Address of the first router hop on this machine's own network.
static func subnet_gateway() -> String:
	for address in RoomProtocol.lan_addresses():
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		parts[3] = "254" if parts[3] == "1" else "1"
		return ".".join(parts)
	return ""


static func is_ipv4_address(text: String) -> bool:
	var parts := text.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return false
	return true


static func _natpmp_buffer() -> StreamPeerBuffer:
	# Every multi-byte NAT-PMP field is in network byte order.
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	return buf
