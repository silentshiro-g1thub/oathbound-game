extends Node3D

## One team's flag: a pole, a cloth, and the heal disc that follows it.

enum State { HOME, CARRIED, DROPPED, FLIGHT }

const Rules = preload("res://scenes/flag/flag_rules.gd")

@export var team: int = Rules.Team.RED
@export var state: int = State.HOME
@export var carrier_peer_id: int = 0
var home: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var rolling := false
var heal_zone: MeshInstance3D


func _ready() -> void:
	_build_visual()
	update_zone_pose()


func update_zone_pose() -> void:
	if heal_zone == null:
		return
	var drop := Rules.CARRY_HEIGHT if state == State.CARRIED else 0.0
	heal_zone.position.y = 0.04 - drop


func reset_to_home() -> void:
	state = State.HOME
	carrier_peer_id = 0
	velocity = Vector3.ZERO
	rolling = false
	global_position = home
	update_zone_pose()


func _build_visual() -> void:
	var color := Rules.team_color(team)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.045
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 1.7
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position.y = 0.85
	pole.material_override = _solid(color.darkened(0.35))
	add_child(pole)

	var cloth := MeshInstance3D.new()
	var cloth_mesh := BoxMesh.new()
	cloth_mesh.size = Vector3(0.9, 0.48, 0.05)
	cloth.mesh = cloth_mesh
	cloth.position = Vector3(0.48, 1.45, 0.0)
	cloth.material_override = _solid(color)
	add_child(cloth)

	heal_zone = MeshInstance3D.new()
	heal_zone.name = "HealZone"
	var zone_mesh := CylinderMesh.new()
	zone_mesh.top_radius = Rules.HEAL_RADIUS
	zone_mesh.bottom_radius = Rules.HEAL_RADIUS
	zone_mesh.height = 0.08
	zone_mesh.radial_segments = 40
	heal_zone.mesh = zone_mesh
	heal_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var zone_material := StandardMaterial3D.new()
	zone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_material.albedo_color = Color(color.r, color.g, color.b, 0.22)
	heal_zone.material_override = zone_material
	add_child(heal_zone)


func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	return material
