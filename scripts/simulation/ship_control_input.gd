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
## Flight assist damps rotation to the requested rate and, if
## `hold_translation` is set, thrusts uncommanded axes to hold a velocity.
var flight_assist: bool = true
## Assist only: hold `hold_velocity` on uncommanded axes. When false,
## uncommanded axes coast — the ship keeps its current orbit and spends no Δv.
var hold_translation: bool = true
## Local-frame velocity to hold. Overwritten each tick from `hold_target_id`.
var hold_velocity: Vector3 = Vector3.ZERO
## If set, the simulation holds this ship's velocity (match target).
var hold_target_id: StringName = &""
## Trigger held for the main cannon.
var fire: bool = false
## Turret aim: the point the guns train on, as an offset from the ship's
## position (world axes, m). Without one the turrets face the nose.
var has_aim: bool = false
var aim_offset: Vector3 = Vector3.ZERO


static func create(p_translation: Vector3, p_rotation: Vector3, p_assist: bool) -> ShipControlInput:
	var input := ShipControlInput.new()
	input.translation = p_translation
	input.rotation = p_rotation
	input.flight_assist = p_assist
	input.hold_translation = p_assist
	return input


## No thrust, no torque, no assist: the ship coasts.
static func neutral() -> ShipControlInput:
	return create(Vector3.ZERO, Vector3.ZERO, false)
