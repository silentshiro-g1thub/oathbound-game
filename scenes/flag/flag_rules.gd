extends RefCounted

## Shared flag numbers. The match, the flag visual, and tests all read these.

enum Team { NONE, RED, BLUE }

const HEAL_RADIUS := 10.0
const PICKUP_RADIUS := 2.0
const SPEED_SCALE := 1.35
const HEAL_PER_SECOND := 20.0
const THROW_MIN_SPEED := 8.0
const THROW_MAX_SPEED := 20.0
const THROW_SPEED := THROW_MAX_SPEED
const THROW_CHARGE_TIME := 0.85
## Baseball toss: gravity bends a fast throw into an arc. Air barely slows it.
const THROW_GRAVITY := 11.0
const THROW_DRAG := 0.08
const THROW_RESTITUTION := 0.5
const THROW_ROLL_FRICTION := 6.0
const THROW_BOUNCE_CUTOFF := 2.0
const THROW_REST_SPEED := 0.8
const CARRY_HEIGHT := 1.35
const RED_HOME := Vector3(-12.0, -0.45, 0.0)
const BLUE_HOME := Vector3(12.0, -0.45, 0.0)


static func team_color(team: int) -> Color:
	if team == Team.BLUE:
		return Color(0.18, 0.42, 0.95)
	return Color(0.86, 0.14, 0.16)


static func team_name(team: int) -> String:
	if team == Team.BLUE:
		return "blue"
	if team == Team.RED:
		return "red"
	return "none"


static func within(a: Vector3, b: Vector3, radius: float) -> bool:
	return a.distance_to(b) <= radius


## 0 is a tap, 1 is a full hold.
static func throw_strength(held_seconds: float) -> float:
	if THROW_CHARGE_TIME <= 0.0:
		return 1.0
	return clampf(held_seconds / THROW_CHARGE_TIME, 0.0, 1.0)


static func throw_speed(strength: float) -> float:
	return lerpf(THROW_MIN_SPEED, THROW_MAX_SPEED, clampf(strength, 0.0, 1.0))


## Aim is the camera's look direction, including pitch. Strength only changes speed.
static func throw_velocity(aim: Vector3, strength: float = 1.0) -> Vector3:
	if aim.length_squared() < 0.0000001:
		aim = Vector3.FORWARD
	return aim.normalized() * throw_speed(strength)


## Gravity first, then a little drag, then the move. That is a thrown ball's arc.
static func step_flight(position: Vector3, velocity: Vector3, delta: float) -> Dictionary:
	var next_velocity := velocity + Vector3.DOWN * THROW_GRAVITY * delta
	next_velocity *= exp(-THROW_DRAG * delta)
	return {
		"position": position + next_velocity * delta,
		"velocity": next_velocity,
	}


## Bounce off a surface, or start rolling when the rebound is too weak.
static func land(velocity: Vector3, normal: Vector3) -> Dictionary:
	var n := normal.normalized()
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	var into := velocity.dot(n)
	if into >= 0.0:
		return {"velocity": velocity.slide(n), "rolling": true}
	var reflected := velocity - 2.0 * into * n
	var outgoing := reflected * THROW_RESTITUTION
	if outgoing.dot(n) < THROW_BOUNCE_CUTOFF:
		return {"velocity": velocity.slide(n), "rolling": true}
	return {"velocity": outgoing, "rolling": false}


static func carry_position(player: Node3D) -> Vector3:
	var side := player.global_basis * Vector3(0.55, 0.0, 0.2)
	return player.global_position + Vector3(0.0, CARRY_HEIGHT, 0.0) + side
