class_name ShipControlInput
extends RefCounted
## Pilot (or AI) command for one simulation tick. Pure data: the simulation
## never reads Godot's Input singleton directly.

## Translation command per body axis, each in [-1, 1].
## x: +right / -left, y: +up / -down, z: -forward / +aft.
var translation: Vector3 = Vector3.ZERO
## Rotation command per body axis, each in [-1, 1].
## x: +pitch up, y: +yaw left, z: +roll left (right-hand rule about each axis).
## With flight assist this is a rate request; in manual it is a torque fraction.
var rotation: Vector3 = Vector3.ZERO
## Flight assist nulls unwanted translation/rotation within thrust limits.
var flight_assist: bool = true


static func create(p_translation: Vector3, p_rotation: Vector3, p_assist: bool) -> ShipControlInput:
	var input := ShipControlInput.new()
	input.translation = p_translation
	input.rotation = p_rotation
	input.flight_assist = p_assist
	return input


## No thrust, no torque, no assist: the ship coasts.
static func neutral() -> ShipControlInput:
	return create(Vector3.ZERO, Vector3.ZERO, false)
