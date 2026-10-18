class_name ChaseCamera
extends Camera3D
## Third-person camera that rides behind the ship. Rotation lags slightly so
## turns are readable; position is rigid so translation is never hidden.

## Camera position in the ship's body frame (+Z is aft, +Y is up).
@export var offset_body: Vector3 = Vector3(0, 16, 85)
## Aim point ahead of the ship, in metres along its nose.
@export var look_ahead_m: float = 400.0
## Higher = stiffer rotation follow (1/s).
@export var rotation_stiffness: float = 6.0

var _smoothed: Quaternion = Quaternion.IDENTITY
var _initialized := false


func follow(target: Node3D, delta: float) -> void:
	var target_q := target.quaternion
	if not _initialized:
		_smoothed = target_q
		_initialized = true
	else:
		_smoothed = _smoothed.slerp(target_q, 1.0 - exp(-rotation_stiffness * delta))
	var b := Basis(_smoothed)
	global_position = target.global_position + b * offset_body
	look_at(target.global_position + b * Vector3(0, 0, -look_ahead_m), b.y)
