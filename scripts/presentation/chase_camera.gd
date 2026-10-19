class_name ChaseCamera
extends Camera3D
## Third-person camera that rides behind the ship. Rotation lags slightly so
## turns are readable; position is rigid so translation is never hidden.
## `orbit` swings it around the ship (right-drag); `zoomed` narrows the view
## for gunnery and lifts the camera clear of the hull.

## Camera position in the ship's body frame (+Z is aft, +Y is up).
@export var offset_body: Vector3 = Vector3(0, 16, 85)
## Zoomed position: higher and closer, so the gun line clears the hull.
@export var offset_zoomed: Vector3 = Vector3(0, 18, 40)
## Aim point ahead of the ship, in metres along its nose.
@export var look_ahead_m: float = 400.0
## Higher = stiffer rotation follow (1/s).
@export var rotation_stiffness: float = 6.0

## Normal and zoomed (Shift toggles, for precise gunnery) field of view, degrees.
@export var fov_normal: float = 70.0
@export var fov_zoomed: float = 22.0
## How fast the zoom settles (1/s).
@export var zoom_speed: float = 10.0

## Set by Main from the player's zoom toggle.
var zoomed: bool = false
## Orbit around the ship: x = yaw, y = pitch (radians), set by Main.
var orbit: Vector2 = Vector2.ZERO

var _smoothed: Quaternion = Quaternion.IDENTITY
var _initialized := false
var _zoom := 0.0
var _orbit := Vector2.ZERO


func follow(target: Node3D, delta: float) -> void:
	var target_q := target.quaternion
	if not _initialized:
		_smoothed = target_q
		_initialized = true
	else:
		_smoothed = _smoothed.slerp(target_q, 1.0 - exp(-rotation_stiffness * delta))
	# Zoom and orbit ease in and out.
	var k := 1.0 - exp(-zoom_speed * delta)
	_zoom = lerpf(_zoom, 1.0 if zoomed else 0.0, k)
	_orbit = _orbit.lerp(orbit, k)
	fov = lerpf(fov_normal, fov_zoomed, _zoom)
	var b := Basis(_smoothed) * Basis(Vector3.UP, _orbit.x) * Basis(Vector3.RIGHT, _orbit.y)
	var offset := offset_body.lerp(offset_zoomed, _zoom)
	global_position = target.global_position + b * offset
	look_at(target.global_position + b * Vector3(0, 0, -look_ahead_m * lerpf(1.0, 4.0, _zoom)), b.y)
