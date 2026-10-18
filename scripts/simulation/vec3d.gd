class_name Vec3d
extends RefCounted
## Minimal double-precision 3-vector. Godot's Vector3 is 32-bit in standard
## builds (~0.5 m resolution at Earth-orbit radius), so planet-centred inertial
## (PCI) positions and the local frame origin use this instead. Hot per-round
## paths take scalar components rather than allocating these.

var x: float
var y: float
var z: float


func _init(p_x := 0.0, p_y := 0.0, p_z := 0.0) -> void:
	x = p_x
	y = p_y
	z = p_z


static func from_vector3(v: Vector3) -> Vec3d:
	return Vec3d.new(v.x, v.y, v.z)


func to_vector3() -> Vector3:
	return Vector3(x, y, z)


func copy() -> Vec3d:
	return Vec3d.new(x, y, z)


func plus(o: Vec3d) -> Vec3d:
	return Vec3d.new(x + o.x, y + o.y, z + o.z)


func minus(o: Vec3d) -> Vec3d:
	return Vec3d.new(x - o.x, y - o.y, z - o.z)


## Adds a 32-bit local offset, promoting it to double first.
func plus_v3(v: Vector3) -> Vec3d:
	return Vec3d.new(x + v.x, y + v.y, z + v.z)


func times(s: float) -> Vec3d:
	return Vec3d.new(x * s, y * s, z * s)


func dot(o: Vec3d) -> float:
	return x * o.x + y * o.y + z * o.z


func cross(o: Vec3d) -> Vec3d:
	return Vec3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)


func length() -> float:
	return sqrt(x * x + y * y + z * z)


func normalized() -> Vec3d:
	var l := length()
	return Vec3d.new() if l == 0.0 else times(1.0 / l)


func _to_string() -> String:
	return "(%.3f, %.3f, %.3f)" % [x, y, z]
