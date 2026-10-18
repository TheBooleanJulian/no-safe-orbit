class_name FireControl
extends RefCounted
## Fire-control solution for an unguided round against a target.
##
## Model: in the shooter's frame the round flies straight at muzzle speed and
## the target moves at constant relative velocity. Both are in free fall, so
## gravity only enters through the tidal term (centimetres over a few seconds
## at engagement range) and is ignored here. Target acceleration is ignored.
## The solution is an estimate; real hits depend on the simulated trajectory.


## Smallest t > 0 with |rel_pos + rel_vel·t| = speed·t, or -1 if the round can
## never catch the target. rel_pos/rel_vel are target minus shooter (muzzle).
static func intercept_time(rel_pos: Vector3, rel_vel: Vector3, speed: float) -> float:
	var a := rel_vel.dot(rel_vel) - speed * speed
	var b := 2.0 * rel_pos.dot(rel_vel)
	var c := rel_pos.dot(rel_pos)
	if absf(a) < 1e-9:
		return -c / b if b < 0.0 else -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t1 := (-b - sq) / (2.0 * a)
	var t2 := (-b + sq) / (2.0 * a)
	var best := INF
	for t in [t1, t2]:
		if t > 0.0 and t < best:
			best = t
	return best if best < INF else -1.0


## Shooter-relative point where the target will be at time t.
static func lead_point(rel_pos: Vector3, rel_vel: Vector3, t: float) -> Vector3:
	return rel_pos + rel_vel * t
