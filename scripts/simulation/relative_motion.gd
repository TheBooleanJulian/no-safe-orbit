class_name RelativeMotion
extends RefCounted
## Observer-to-target kinematics used by the HUD and (later) fire control.
## Takes plain vectors so projectiles and missiles can reuse it.


static func range_between(observer_pos: Vector3, target_pos: Vector3) -> float:
	return observer_pos.distance_to(target_pos)


static func relative_velocity(observer_vel: Vector3, target_vel: Vector3) -> Vector3:
	return target_vel - observer_vel


## Rate of change of range (m/s). Negative = closing, positive = opening.
static func range_rate(
		observer_pos: Vector3, observer_vel: Vector3,
		target_pos: Vector3, target_vel: Vector3) -> float:
	var rel_pos := target_pos - observer_pos
	var dist := rel_pos.length()
	if dist < 1e-6:
		return 0.0
	return rel_pos.dot(target_vel - observer_vel) / dist
