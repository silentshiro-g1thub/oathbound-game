extends StaticBody3D
## Debug target: destroyed in one hit. Spawned by players pressing F3+1.
## Builds its own capsule body so no extra scene file is needed.

func _ready() -> void:
	add_to_group("dummy")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3.UP * 0.9
	add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.15, 0.15)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = Vector3.UP * 0.9
	add_child(mesh_instance)

@rpc("any_peer", "call_local")
func die() -> void:
	queue_free()
