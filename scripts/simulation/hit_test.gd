class_name HitTest
extends RefCounted
## Swept collision queries. Rounds cross tens of metres per tick, so testing
## only end positions would let them tunnel through hulls; these test the
## whole segment travelled during the tick.


## Earliest fraction t in [0, 1] at which the segment a→b touches the
## axis-aligned box (centre, half extents), or -1 if it never does.
## Coordinates must already be in the box's own frame.
static func segment_box(a: Vector3, b: Vector3, center: Vector3, half: Vector3) -> float:
	var t_enter := 0.0
	var t_exit := 1.0
	var d := b - a
	for axis in 3:
		var lo := center[axis] - half[axis]
		var hi := center[axis] + half[axis]
		if absf(d[axis]) < 1e-12:
			if a[axis] < lo or a[axis] > hi:
				return -1.0
			continue
		var t1 := (lo - a[axis]) / d[axis]
		var t2 := (hi - a[axis]) / d[axis]
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		t_enter = maxf(t_enter, t1)
		t_exit = minf(t_exit, t2)
		if t_enter > t_exit:
			return -1.0
	return t_enter


## Segment of a round relative to a moving, rotating ship over one tick, in
## the ship's body frame. Relative motion within the tick is treated as linear
## and the ship's end-of-tick orientation is used (rotation per tick is tiny).
static func round_vs_ship(round_prev: Vector3, round_now: Vector3, ship: ShipState) -> float:
	var inv := ship.orientation.inverse()
	var a := inv * (round_prev - ship.prev_position)
	var b := inv * (round_now - ship.position)
	return segment_box(a, b, ship.config.hit_box_center, ship.config.hit_box_half_extents)
