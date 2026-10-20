extends Node

var got: Array[String] = []


@rpc("any_peer", "call_local", "reliable")
func ping(value: String) -> void:
	got.append("%s:%s" % [multiplayer.get_remote_sender_id(), value])
