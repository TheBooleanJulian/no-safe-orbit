class_name ShipState
extends RefCounted
## Authoritative runtime state of one physical vessel. Rendering reads this;
## it never writes it. Positions are in the local engagement frame (metres).

## Stable identity — never derived from scene-tree position.
var id: StringName
var display_name: String
var config: ShipConfig

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY
## Angular velocity in the BODY frame (rad/s about body X, Y, Z).
var angular_velocity: Vector3 = Vector3.ZERO

## State at the start of the most recent tick, for render interpolation.
var prev_position: Vector3 = Vector3.ZERO
var prev_orientation: Quaternion = Quaternion.IDENTITY

## Thrust (N) and torque (N·m) applied during the last tick, body frame.
var last_thrust_body: Vector3 = Vector3.ZERO
var last_torque_body: Vector3 = Vector3.ZERO

## Total thruster delta-v spent so far (m/s), summed per axis because each
## thruster group burns propellant independently. Feeds the future propellant model.
var delta_v_expended: float = 0.0


static func create(
		p_id: StringName,
		p_display_name: String,
		p_config: ShipConfig,
		p_position: Vector3 = Vector3.ZERO,
		p_velocity: Vector3 = Vector3.ZERO,
		p_orientation: Quaternion = Quaternion.IDENTITY) -> ShipState:
	var state := ShipState.new()
	state.id = p_id
	state.display_name = p_display_name
	state.config = p_config
	state.position = p_position
	state.velocity = p_velocity
	state.orientation = p_orientation.normalized()
	state.snapshot_previous()
	return state


func snapshot_previous() -> void:
	prev_position = position
	prev_orientation = orientation


func basis() -> Basis:
	return Basis(orientation)


## Unit vector of the ship's nose in world space.
func forward() -> Vector3:
	return orientation * Vector3.FORWARD


## Velocity expressed along the ship's own axes (x right, y up, z aft).
func body_velocity() -> Vector3:
	return orientation.inverse() * velocity


func interpolated_position(alpha: float) -> Vector3:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))


func interpolated_orientation(alpha: float) -> Quaternion:
	return prev_orientation.slerp(orientation, clampf(alpha, 0.0, 1.0))
