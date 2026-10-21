extends Node3D

## Red and blue flags. The server decides pickup, throw, flight, and drops.
## Each flag heals anyone standing inside its 10m zone. Carrying one raises move speed.
## Holding is the default. Hold G to set throw strength, then release along the camera aim.
## The flag flies like a thrown baseball: a gravity arc, a bounce, then a short roll. A defeat drops it.

const Flag = preload("res://scenes/flag/flag.gd")
const Rules = preload("res://scenes/flag/flag_rules.gd")

var _flags: Array[Node3D] = []
var _heal_bank: Dictionary = {}
var _hint: Label
var _charging := false
var _throw_charge := 0.0
var _preview: MeshInstance3D
var _preview_mesh: ImmediateMesh


func _ready() -> void:
	add_to_group("flag_match")
	_build_hint()
	_build_preview()
	_build_flag(Rules.Team.RED, "RedFlag", Rules.RED_HOME)
	_build_flag(Rules.Team.BLUE, "BlueFlag", Rules.BLUE_HOME)
	if multiplayer.has_multiplayer_peer():
		adopt_server()


func home_for(team: int) -> Vector3:
	if team == Rules.Team.BLUE:
		return Rules.BLUE_HOME
	return Rules.RED_HOME


func flag_for(team: int) -> Node3D:
	for flag in _flags:
		if flag.team == team:
			return flag
	return null


func adopt_server() -> void:
	set_multiplayer_authority(1, true)


func reset_flags() -> void:
	_heal_bank.clear()
	for flag in _flags:
		flag.reset_to_home()
	_apply_speed_scales()


func _physics_process(delta: float) -> void:
	if _is_authority():
		simulate(delta)
	else:
		_apply_speed_scales()


func _process(delta: float) -> void:
	_advance_throw_charge(delta)
	if not _is_authority():
		for flag in _flags:
			if flag.state == Flag.State.CARRIED:
				var carrier := _player_by_id(flag.carrier_peer_id)
				if carrier:
					flag.global_position = Rules.carry_position(carrier)
					flag.rotation.y = carrier.rotation.y
			flag.update_zone_pose()
	_update_hint()
	_update_throw_preview()


func _advance_throw_charge(delta: float) -> void:
	var player := _local_player()
	var carrying: bool = player != null and player.controls_active and _flag_carried_by(_peer_id_of(player)) != null
	if carrying and Input.is_action_pressed("throw_flag"):
		if not _charging:
			_throw_charge = 0.0
		_charging = true
		_throw_charge = minf(_throw_charge + delta, Rules.THROW_CHARGE_TIME)
		return
	if not _charging:
		return
	var strength := Rules.throw_strength(_throw_charge)
	_charging = false
	_throw_charge = 0.0
	if carrying:
		throw_carried_flag(player, strength)


## Advance flight, drops, pickups, and healing. Safe to call from tests.
func simulate(delta: float) -> void:
	if delta <= 0.0:
		_apply_speed_scales()
		return
	for flag in _flags:
		if flag.state == Flag.State.FLIGHT:
			_advance_flight(flag, delta)
		elif flag.state == Flag.State.CARRIED:
			var carrier := _player_by_id(flag.carrier_peer_id)
			if carrier == null or not is_instance_valid(carrier):
				_drop_flag(flag, flag.global_position)
			elif int(carrier.health) <= 0:
				_drop_flag(flag, carrier.global_position)
			else:
				flag.global_position = Rules.carry_position(carrier)
				flag.rotation.y = carrier.rotation.y
	for flag in _flags:
		if flag.state == Flag.State.HOME or flag.state == Flag.State.DROPPED:
			_try_pickup(flag)
	for flag in _flags:
		flag.update_zone_pose()
	_heal(delta)
	_apply_speed_scales()


func throw_carried_flag(player: Node = null, strength: float = 1.0) -> bool:
	strength = clampf(strength, 0.0, 1.0)
	if not _is_authority():
		if multiplayer.has_multiplayer_peer():
			request_throw.rpc_id(1, strength)
		return false
	var peer_id := _peer_id_of(player) if player else multiplayer.get_unique_id()
	return _begin_throw(peer_id, strength)


@rpc("any_peer", "reliable")
func request_throw(strength: float = 1.0) -> void:
	if not _is_authority():
		return
	_begin_throw(multiplayer.get_remote_sender_id(), clampf(strength, 0.0, 1.0))


@rpc("any_peer", "reliable")
func notify_carrier_down(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not _is_authority():
		return
	if multiplayer.has_multiplayer_peer():
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != 1 and sender != peer_id:
			return
	var player := _player_by_id(peer_id)
	if player and "health" in player:
		player.health = 0
	_drop_carried_by(peer_id)
	_apply_speed_scales()


func _begin_throw(peer_id: int, strength: float = 1.0) -> bool:
	if peer_id == 0:
		return false
	var flag := _flag_carried_by(peer_id)
	if flag == null:
		return false
	var player := _player_by_id(peer_id)
	if player == null or int(player.health) <= 0:
		return false
	flag.global_position = Rules.carry_position(player)
	flag.velocity = Rules.throw_velocity(_aim_direction(player), strength)
	flag.rolling = false
	flag.state = Flag.State.FLIGHT
	flag.carrier_peer_id = 0
	flag.update_zone_pose()
	_apply_speed_scales()
	return true


func _advance_flight(flag: Node3D, delta: float) -> void:
	var step: Dictionary = _move_projectile(flag.global_position, flag.velocity, flag.rolling, delta)
	flag.global_position = step.position
	flag.velocity = step.velocity
	flag.rolling = step.rolling
	var spin := 2.0 if flag.rolling else 6.0
	flag.rotate_y(delta * spin)
	if step.settled or flag.global_position.y < -8.0:
		_drop_flag(flag, flag.global_position)


func _move_projectile(position: Vector3, velocity: Vector3, rolling: bool, delta: float) -> Dictionary:
	if rolling:
		return _roll_projectile(position, velocity, delta)
	var step: Dictionary = Rules.step_flight(position, velocity, delta)
	var next_position: Vector3 = step.position
	var next_velocity: Vector3 = step.velocity
	var hit := _ray(position, next_position)
	if hit.is_empty():
		return {
			"position": next_position,
			"velocity": next_velocity,
			"rolling": false,
			"settled": next_position.y < -8.0,
		}
	var normal: Vector3 = hit.normal
	var landed: Dictionary = Rules.land(next_velocity, normal)
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	return {
		"position": hit.position + normal.normalized() * 0.08,
		"velocity": landed.velocity,
		"rolling": landed.rolling,
		"settled": landed.velocity.length() <= Rules.THROW_REST_SPEED,
	}


func _roll_projectile(position: Vector3, velocity: Vector3, delta: float) -> Dictionary:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(Vector3.ZERO, Rules.THROW_ROLL_FRICTION * delta)
	if flat.length() <= Rules.THROW_REST_SPEED:
		return {"position": position, "velocity": Vector3.ZERO, "rolling": true, "settled": true}
	var next := position + flat * delta
	var support := _ray(next + Vector3.UP * 0.75, next + Vector3.DOWN * 2.5)
	if support.is_empty():
		return {"position": next, "velocity": flat, "rolling": false, "settled": false}
	return {
		"position": support.position + Vector3.UP * 0.08,
		"velocity": flat,
		"rolling": true,
		"settled": false,
	}


func throw_preview_points(origin: Vector3, velocity: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.push_back(origin)
	var position := origin
	var rolling := false
	var step_dt := 1.0 / 30.0
	for _i in 180:
		var step: Dictionary = _move_projectile(position, velocity, rolling, step_dt)
		position = step.position
		velocity = step.velocity
		rolling = step.rolling
		points.push_back(position)
		if step.settled:
			break
	return points


func _try_pickup(flag: Node3D) -> void:
	var closest: Node = null
	var closest_distance := Rules.PICKUP_RADIUS
	for player in get_tree().get_nodes_in_group("players"):
		if int(player.health) <= 0:
			continue
		var body := player as Node3D
		var peer_id := _peer_id_of(body)
		if peer_id == 0 or _flag_carried_by(peer_id) != null:
			continue
		var distance: float = body.global_position.distance_to(flag.global_position)
		if distance <= closest_distance and (closest == null or distance < closest_distance):
			closest = player
			closest_distance = distance
	if closest:
		_pickup(flag, closest)


func _pickup(flag: Node3D, player: Node) -> void:
	flag.state = Flag.State.CARRIED
	flag.carrier_peer_id = _peer_id_of(player)
	flag.velocity = Vector3.ZERO
	flag.global_position = Rules.carry_position(player)
	flag.rotation.y = player.rotation.y
	flag.update_zone_pose()


func _drop_carried_by(peer_id: int) -> void:
	var flag := _flag_carried_by(peer_id)
	if flag == null:
		return
	var player := _player_by_id(peer_id)
	_drop_flag(flag, player.global_position if player else flag.global_position)


func _drop_flag(flag: Node3D, around: Vector3) -> void:
	var origin := Vector3(around.x, around.y + 2.0, around.z)
	var hit := _ray(origin, origin + Vector3.DOWN * 40.0)
	if hit.is_empty():
		flag.global_position = Vector3(around.x, -0.4, around.z)
	else:
		flag.global_position = hit.position + Vector3.UP * 0.05
	flag.velocity = Vector3.ZERO
	flag.rolling = false
	flag.state = Flag.State.DROPPED
	flag.carrier_peer_id = 0
	flag.update_zone_pose()


func _heal(delta: float) -> void:
	for flag in _flags:
		var origin: Vector3 = flag.heal_zone.global_position if flag.heal_zone else flag.global_position
		for player in get_tree().get_nodes_in_group("players"):
			if int(player.health) <= 0:
				continue
			if not Rules.within(player.global_position, origin, Rules.HEAL_RADIUS):
				continue
			var key := "%s:%s" % [flag.name, _player_key(player)]
			var bank: float = float(_heal_bank.get(key, 0.0)) + Rules.HEAL_PER_SECOND * delta
			var amount := int(bank)
			_heal_bank[key] = bank - float(amount)
			if amount > 0 and player.has_method("apply_heal"):
				_give_heal(player, amount)


func _give_heal(player: Node, amount: int) -> void:
	var peer_id := _peer_id_of(player)
	var connected := multiplayer.has_multiplayer_peer() and peer_id != 0 and peer_id != multiplayer.get_unique_id()
	if connected and multiplayer.get_peers().has(peer_id):
		player.apply_heal.rpc_id(peer_id, amount)
		return
	player.apply_heal(amount)


func _apply_speed_scales() -> void:
	for player in get_tree().get_nodes_in_group("players"):
		var scale := 1.0
		var peer_id := _peer_id_of(player)
		if peer_id != 0 and _flag_carried_by(peer_id) != null:
			scale = Rules.SPEED_SCALE
		player.flag_speed_scale = scale


func _build_flag(team: int, node_name: String, home: Vector3) -> void:
	var flag := Node3D.new()
	flag.set_script(Flag)
	flag.name = node_name
	flag.team = team
	flag.home = home
	flag.position = home
	add_child(flag)
	_flags.append(flag)
	_add_sync(flag)


func _add_sync(flag: Node) -> void:
	var sync := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	for property in ["position", "state", "carrier_peer_id"]:
		var path := NodePath(".:%s" % property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	flag.add_child(sync)


func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 0.0
	_hint.offset_left = -260.0
	_hint.offset_right = 260.0
	_hint.offset_top = 24.0
	_hint.offset_bottom = 64.0
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)


func _build_preview() -> void:
	_preview_mesh = ImmediateMesh.new()
	_preview = MeshInstance3D.new()
	_preview.name = "ThrowPreview"
	_preview.mesh = _preview_mesh
	_preview.top_level = true
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview.material_override = material
	add_child(_preview)
	_preview.global_position = Vector3.ZERO


func _update_throw_preview() -> void:
	if _preview_mesh == null:
		return
	if not _charging:
		_preview_mesh.clear_surfaces()
		return
	var player := _local_player()
	var flag := _flag_carried_by(_peer_id_of(player)) if player else null
	if player == null or flag == null:
		_preview_mesh.clear_surfaces()
		return
	var origin: Vector3 = Rules.carry_position(player)
	var velocity: Vector3 = Rules.throw_velocity(_aim_direction(player), Rules.throw_strength(_throw_charge))
	var points := throw_preview_points(origin, velocity)
	_draw_preview(points, Rules.team_color(flag.team))


func _draw_preview(points: PackedVector3Array, color: Color) -> void:
	_preview_mesh.clear_surfaces()
	if points.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var side_hint := camera.global_basis.x if camera else Vector3.RIGHT
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var half := 0.05
	for i in points.size():
		var ahead: Vector3 = points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var side := ahead.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = side_hint
		side = side.normalized()
		var tint := Color(color.r, color.g, color.b, 0.9)
		_preview_mesh.surface_set_color(tint)
		_preview_mesh.surface_add_vertex(points[i] + side * half)
		_preview_mesh.surface_add_vertex(points[i] - side * half)
	_preview_mesh.surface_end()


func _update_hint() -> void:
	if _hint == null:
		return
	var player := _local_player()
	var flag := _flag_carried_by(_peer_id_of(player)) if player else null
	if flag == null:
		_hint.text = ""
		return
	if _charging:
		var percent := int(round(Rules.throw_strength(_throw_charge) * 100.0))
		_hint.text = "Throw power %d%%" % percent
	else:
		_hint.text = "Holding the %s flag    Hold G to throw" % Rules.team_name(flag.team)
	_hint.add_theme_color_override("font_color", Rules.team_color(flag.team))


func _aim_direction(player: Node3D) -> Vector3:
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	var aim := -camera.global_basis.z if camera else -player.global_basis.z
	if aim.length_squared() < 0.0000001:
		return Vector3.FORWARD
	return aim


func _flag_carried_by(peer_id: int) -> Node3D:
	if peer_id == 0:
		return null
	for flag in _flags:
		if flag.state == Flag.State.CARRIED and flag.carrier_peer_id == peer_id:
			return flag
	return null


func _player_by_id(peer_id: int) -> Node:
	if peer_id == 0:
		return null
	var named := get_parent().get_node_or_null(str(peer_id)) if get_parent() else null
	if named and named.is_in_group("players"):
		return named
	for player in get_tree().get_nodes_in_group("players"):
		if _peer_id_of(player) == peer_id:
			return player
	return null


func _peer_id_of(player: Node) -> int:
	if player == null:
		return 0
	if str(player.name).is_valid_int():
		return int(str(player.name))
	return 0


func _player_key(player: Node) -> String:
	var peer_id := _peer_id_of(player)
	if peer_id != 0:
		return str(peer_id)
	return str(player.get_instance_id())


func _local_player() -> Node:
	if not is_inside_tree():
		return null
	for player in get_tree().get_nodes_in_group("players"):
		if player.has_method("is_multiplayer_authority") and player.is_multiplayer_authority():
			return player
	return null


func _is_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = []
	for player in get_tree().get_nodes_in_group("players"):
		if player is CollisionObject3D:
			exclude.append(player.get_rid())
	query.exclude = exclude
	return space.intersect_ray(query)
