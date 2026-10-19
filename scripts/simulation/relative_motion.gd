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


## Straight-line closest approach (no gravity, no thrust — good over the
## seconds-to-minutes of an intercept): {time} until it (s, 0 if already
## past / opening) and the {miss} distance then (m).
static func closest_approach(
		observer_pos: Vector3, observer_vel: Vector3,
		target_pos: Vector3, target_vel: Vector3) -> Dictionary:
	var r := target_pos - observer_pos
	var v := target_vel - observer_vel
	var vv := v.length_squared()
	var t := 0.0 if vv < 1e-9 else maxf(-r.dot(v) / vv, 0.0)
	return {"time": t, "miss": (r + v * t).length()}
