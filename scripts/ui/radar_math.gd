class_name RadarMath
extends RefCounted
## Contact geometry for the flat radar, from a body-frame offset
## (x right, y up, −z ahead). Pure functions, unit-tested.


## 0° dead ahead, +90° right, −90° left, ±180° astern.
static func bearing_deg(rel_body: Vector3) -> float:
	return rad_to_deg(atan2(rel_body.x, -rel_body.z))


## +90° straight up (body +Y), −90° straight down.
static func elevation_deg(rel_body: Vector3) -> float:
	return rad_to_deg(atan2(rel_body.y, Vector2(rel_body.x, rel_body.z).length()))


## Position on the radar plane in units of `scale_m` (1 = outer ring),
## clamped to the ring. x = right, y = aft, so "ahead" is up on screen.
static func plot(rel_body: Vector3, scale_m: float) -> Vector2:
	return (Vector2(rel_body.x, rel_body.z) / scale_m).limit_length(1.0)


## Smallest 1-2-5 × 10ⁿ range scale with 25 % headroom over `range_m`
## (minimum 1 km).
static func nice_scale(range_m: float) -> float:
	var wanted := maxf(range_m * 1.25, 1000.0)
	var decade := pow(10.0, floorf(log(wanted) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if m * decade >= wanted - 1e-6:
			return m * decade
	return 10.0 * decade
