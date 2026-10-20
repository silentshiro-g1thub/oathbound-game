extends RefCounted
## Shared camera-follow step. Each frame measures how far the view turned,
## then lets a held offset trail that turn and settle back.


static func advance(camera: Camera3D, previous: Vector2, lag: Vector2, delta: float, strength: float, limit: Vector2, settle_rate: float) -> Dictionary:
	var yaw := camera.global_rotation.y
	var pitch := camera.global_rotation.x
	var yaw_step := wrapf(yaw - previous.x, -PI, PI)
	var pitch_step := pitch - previous.y
	var followed := lag
	followed.x = clampf(followed.x - yaw_step * strength, -limit.x, limit.x)
	followed.y = clampf(followed.y + pitch_step * strength, -limit.y, limit.y)
	followed = followed.lerp(Vector2.ZERO, 1.0 - exp(-settle_rate * delta))
	return {"previous": Vector2(yaw, pitch), "lag": followed}
