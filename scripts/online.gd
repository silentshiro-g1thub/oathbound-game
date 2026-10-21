extends Node

## Epic Online Services login, join-code lobbies, and P2P peer setup.

const PRODUCT_NAME := "Oathbound"
const PRODUCT_VERSION := "0.1"
const PRODUCT_ID := "d2aabfc289c943ffa6bd13a4a640b3d1"
const CLIENT_ID := "xyza7891QutshOwKImqV9uFFTJzcVIPC"
const CLIENT_SECRET := "bn6cVumBnB7iEo2M5uUQnjDuAELcxowA35bk4m9R9tA"
const SANDBOX_ID := "68bce6ca04a94eb1931f69ee4912de1f"
const DEPLOYMENT_ID := "802a9f948b3646eda09e49ea5cffcc6c"
const SOCKET_NAME := "OATHBOUND"
const BUCKET_ID := "oathbound"
const CODE_KEY := "CODE"
const STARTED_KEY := "STARTED"
const NAME_KEY := "NAME"
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_MEMBERS := 10

signal lobby_changed
signal kicked

var lobby: HLobby
var join_code: String = ""
var last_error: String = ""

var _eos_ready := false


func make_join_code() -> String:
	var code := ""
	for _i in 6:
		code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code


func is_in_lobby() -> bool:
	return lobby != null and lobby.is_valid()


func is_host() -> bool:
	return is_in_lobby() and lobby.is_owner()


func is_match_started() -> bool:
	if not is_in_lobby():
		return false
	var attr: Dictionary = lobby.get_attribute(STARTED_KEY)
	return str(attr.get("value", "")) == "1"


func member_names() -> PackedStringArray:
	var names: PackedStringArray = []
	if not is_in_lobby():
		return names
	for member in lobby.members:
		var attr: Dictionary = member.get_attribute(NAME_KEY)
		var shown := str(attr.get("value", ""))
		if shown.is_empty():
			shown = member.display_name if member.display_name else member.product_user_id.substr(0, 8)
		if member.is_owner():
			shown += " (host)"
		names.append(shown)
	return names


func login_and_host(display_name: String) -> bool:
	if not await _login(display_name):
		return false
	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = BUCKET_ID
	opts.max_lobby_members = MAX_MEMBERS
	opts.presence_enabled = true
	opts.enable_join_by_id = true
	opts.enable_rtc_room = false
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	lobby = await HLobbies.create_lobby_async(opts)
	if lobby == null:
		last_error = "Could not create a lobby."
		return false
	join_code = make_join_code()
	lobby.add_attribute(CODE_KEY, join_code)
	lobby.add_current_member_attribute(NAME_KEY, display_name)
	if not await lobby.update_async():
		last_error = "Could not publish the join code."
		return false
	_hook_lobby()
	lobby_changed.emit()
	return true


func login_and_join(display_name: String, code: String) -> bool:
	code = code.strip_edges().to_upper()
	if code.length() != 6:
		last_error = "Join codes are 6 characters."
		return false
	if not await _login(display_name):
		return false
	var found = await HLobbies.search_by_attribute_async({
		key = CODE_KEY,
		value = code,
		comparison = EOS.ComparisonOp.Equal,
	})
	if found == null or found.is_empty():
		last_error = "No lobby found for that code."
		return false
	lobby = await HLobbies.join_async(found[0])
	if lobby == null:
		last_error = "Could not join that lobby."
		return false
	join_code = code
	lobby.add_current_member_attribute(NAME_KEY, display_name)
	await lobby.update_async()
	_hook_lobby()
	lobby_changed.emit()
	return true


func create_host_peer() -> MultiplayerPeer:
	var peer := _new_p2p_peer()
	if peer == null:
		return null
	var err: Error = peer.create_server(SOCKET_NAME)
	if err != OK:
		last_error = "Could not start P2P host (%s)." % error_string(err)
		return null
	peer.set_auto_accept_connection_requests(true)
	return peer


func create_client_peer() -> MultiplayerPeer:
	if not is_in_lobby():
		last_error = "Not in a lobby."
		return null
	var peer := _new_p2p_peer()
	if peer == null:
		return null
	var err: Error = peer.create_client(SOCKET_NAME, lobby.owner_product_user_id)
	if err != OK:
		last_error = "Could not connect to host (%s)." % error_string(err)
		return null
	return peer


func mark_match_started() -> bool:
	if not is_host():
		return false
	lobby.add_attribute(STARTED_KEY, 1)
	return await lobby.update_async()


func leave_lobby() -> void:
	if lobby == null:
		return
	_unhook_lobby()
	if lobby.is_owner():
		await lobby.destroy_async()
	else:
		await lobby.leave_async()
	lobby = null
	join_code = ""
	lobby_changed.emit()


func _login(display_name: String) -> bool:
	display_name = display_name.strip_edges()
	if display_name.is_empty():
		display_name = "Player"
	if not await _setup_eos():
		return false
	if HAuth.product_user_id:
		return true
	if not await HAuth.login_anonymous_async(display_name):
		last_error = "Epic login failed. Check the client IDs and that this product is published to the sandbox."
		return false
	# Connect login sets EOSGMultiplayerPeer's local user id in native code.
	# set_local_user_id is not bound to GDScript.
	HP2P.set_relay_control(EOS.P2P.RelayControl.AllowRelays)
	return true


func _setup_eos() -> bool:
	if _eos_ready:
		return true
	if not ClassDB.class_exists("EOSGMultiplayerPeer"):
		last_error = "EOSGMultiplayerPeer is missing. Enable the Epic Online Services plugin and restart Godot."
		return false
	HLog.log_level = HLog.LogLevel.INFO
	var credentials := HCredentials.new()
	credentials.product_name = PRODUCT_NAME
	credentials.product_version = PRODUCT_VERSION
	credentials.product_id = PRODUCT_ID
	credentials.sandbox_id = SANDBOX_ID
	credentials.deployment_id = DEPLOYMENT_ID
	credentials.client_id = CLIENT_ID
	credentials.client_secret = CLIENT_SECRET
	if not await HPlatform.setup_eos_async(credentials):
		last_error = "Could not start Epic Online Services."
		return false
	_eos_ready = true
	return true


func _new_p2p_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("EOSGMultiplayerPeer"):
		last_error = "EOSGMultiplayerPeer is missing."
		return null
	return ClassDB.instantiate("EOSGMultiplayerPeer")


func _hook_lobby() -> void:
	if lobby.lobby_updated.is_connected(_on_lobby_updated):
		return
	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.kicked_from_lobby.connect(_on_kicked)


func _unhook_lobby() -> void:
	if lobby == null:
		return
	if lobby.lobby_updated.is_connected(_on_lobby_updated):
		lobby.lobby_updated.disconnect(_on_lobby_updated)
	if lobby.kicked_from_lobby.is_connected(_on_kicked):
		lobby.kicked_from_lobby.disconnect(_on_kicked)


func _on_lobby_updated() -> void:
	var attr: Dictionary = lobby.get_attribute(CODE_KEY)
	if attr.has("value"):
		join_code = str(attr.value)
	lobby_changed.emit()


func _on_kicked() -> void:
	_unhook_lobby()
	lobby = null
	join_code = ""
	kicked.emit()
	lobby_changed.emit()
