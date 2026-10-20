extends SceneTree
## Public room relay. Both players point relay.cfg at this machine, then only share a code.
##   Godot --headless --path . --script res://multiplayer/run_relay.gd -- 9050


func _initialize() -> void:
	var port := RoomProtocol.DEFAULT_PORT
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and str(args[0]).is_valid_int():
		port = int(args[0])
	var relay := RoomRelay.new()
	if relay.start(port) != OK:
		push_error("Could not listen on TCP %d." % port)
		quit(1)
		return
	root.add_child(relay)
	print("Oathbound room relay listening on TCP %d." % port)
