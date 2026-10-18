class_name ProjectileState
extends RefCounted
## One unguided round in flight. Positions/velocities are in the local frame,
## like ShipState.

var id: int
var shooter_id: StringName
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Position at the start of the most recent tick (swept hits, interpolation).
var prev_position: Vector3 = Vector3.ZERO
var age_s: float = 0.0
var lifetime_s: float = 30.0


func interpolated_position(alpha: float) -> Vector3:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))
