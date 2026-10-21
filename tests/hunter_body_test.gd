extends SceneTree
## Loads the refined hunter and checks every clip can be selected the same way a remote peer would.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	player.name = "1"
	root.add_child(player)
	await process_frame
	var body := player.get_node("HunterBody")
	var animation: AnimationPlayer = _find_animation_player(body)
	assert(animation != null, "Hunter model has no AnimationPlayer")
	for clip_name in player.BODY_CLIPS:
		assert(animation.has_animation(clip_name), "Missing clip %s" % clip_name)
	var skeleton := _find_skeleton(body)
	assert(skeleton != null, "Hunter model has no skeleton")
	for bone_name in ["Hips", "Head", "LeftFoot", "RightHand"]:
		assert(skeleton.find_bone(bone_name) >= 0, "Missing bone %s" % bone_name)
	player._lock_body("Walk_Forward", 5.0)
	await process_frame
	await process_frame
	if str(animation.current_animation) != "Walk_Forward":
		print("HUNTER BODY FAILED clip ", animation.current_animation)
		quit(1)
		return
	player._lock_body("Reload", 2.8)
	await process_frame
	if str(animation.current_animation) != "Reload":
		print("HUNTER BODY FAILED restart ", animation.current_animation)
		quit(1)
		return
	var remote: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	remote.name = "2"
	root.add_child(remote)
	await process_frame
	assert(remote.get_node("Head/Camera3D/WeaponMount").visible == false)
	assert(player.get_node("Head/Camera3D/WeaponMount").visible == false)
	var head_y: float = (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin).y
	var foot_y: float = (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("LeftFoot")).origin).y
	assert(head_y - foot_y > 1.2 and head_y - foot_y < 2.2, "Unexpected hunter height %s" % (head_y - foot_y))
	print("HUNTER BODY PASSED height ", head_y - foot_y, " clips ", player.BODY_CLIPS.size())
	quit()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

