class_name ShipState
extends RefCounted
## Authoritative runtime state of one physical vessel. Rendering reads this;
## it never writes it. Positions are in the local engagement frame (metres).

enum Status {
	ACTIVE,
	## Crossed the body's entry interface; no longer simulated.
	ENTERED_ATMOSPHERE,
}

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

var status: Status = Status.ACTIVE
## Simulation time at which status last changed away from ACTIVE (s).
var status_time: float = 0.0

## Propellant on board (kg); unused when config.unlimited_propellant.
var propellant_kg: float = 0.0

## Runtime condition of a ship built from a blueprint (damage, power, heat,
## pressure); null for fixed test configs. When set, `config` is its
## effective (damage-reduced) config.
var systems: ShipSystems

## Cannon state (unused when config.cannon is null). Rounds are shared by
## every mount; each mount has its own cooldown.
var cannon_rounds: int = 0
var cannon_cooldowns: PackedFloat32Array = PackedFloat32Array()
var rounds_fired: int = 0
## Total recoil impulse from firing (N·s), for the HUD.
var recoil_impulse: float = 0.0
var hits_taken: int = 0


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
	if p_config.cannon != null:
		state.cannon_rounds = p_config.cannon.magazine_rounds
		state.cannon_cooldowns.resize(p_config.cannon_muzzles_body.size())
		state.cannon_cooldowns.fill(0.0)
	if not p_config.unlimited_propellant:
		state.propellant_kg = p_config.propellant_capacity_kg
	state.snapshot_previous()
	return state


## Current mass: dry structure plus propellant on board.
func mass_kg() -> float:
	return config.mass_kg + (0.0 if config.unlimited_propellant else propellant_kg)


## Inertia scaled from full tanks to the current mass (propellant is assumed
## to sit where the tanks are, so the shape of the mass distribution holds).
func inertia_kgm2() -> Vector3:
	return config.inertia_kgm2 * (mass_kg() / config.wet_mass_kg())


## Δv left on the main engines (rocket equation), m/s; INF when unlimited.
func delta_v_remaining() -> float:
	if config.unlimited_propellant:
		return INF
	return config.main_isp_s * ShipDynamics.G0 * log(mass_kg() / config.mass_kg)


func is_active() -> bool:
	return status == Status.ACTIVE


## Attach the runtime systems of the ship's blueprint and fly their config.
func attach_systems(p_systems: ShipSystems) -> void:
	systems = p_systems
	config = p_systems.effective_config()


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
