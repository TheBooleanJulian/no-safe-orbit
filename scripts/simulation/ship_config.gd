class_name ShipConfig
extends Resource
## Immutable flight-tuning data for one ship design, compiled from a
## blueprint by ShipStats.to_ship_config() (data/ships/*.tres are fixed
## fixtures for flight tests).
##
## Units: kg, N, N·m, kg·m², rad/s, s (Isp).
## Body axes (Godot convention): +X right, +Y up, -Z forward (nose), +Z aft.

@export var display_name: String = "Unnamed hull"

@export_group("Mass properties")
## Dry mass: everything except propellant.
@export var mass_kg: float = 250_000.0
## Principal moments of inertia about body X (pitch), Y (yaw) and Z (roll),
## with full tanks. Scaled by current/full mass as propellant burns.
@export var inertia_kgm2: Vector3 = Vector3(7.8e7, 8.0e7, 7.7e6)

@export_group("Propellant")
## No propellant model: engines never run dry (test fixtures).
@export var unlimited_propellant: bool = true
@export var propellant_capacity_kg: float = 0.0
## Specific impulse of the main engines and of the RCS (s).
@export var main_isp_s: float = 900.0
@export var rcs_isp_s: float = 300.0

@export_group("Translation thrust")
## Main engines, pushing the ship towards -Z (forward).
@export var thrust_forward_n: float = 2.5e6
## Reverse thrusters, pushing the ship towards +Z (aft).
@export var thrust_reverse_n: float = 5.0e5
## RCS thrust available in each lateral direction (left or right).
@export var thrust_lateral_n: float = 5.0e5
## RCS thrust available in each vertical direction (up or down).
@export var thrust_vertical_n: float = 5.0e5

@export_group("Rotation")
## Maximum RCS torque magnitude about body X, Y and Z (symmetric).
@export var max_torque_nm: Vector3 = Vector3(2.4e7, 2.4e7, 3.0e6)
## Angular rate that full rotation input requests while flight assist is on.
@export var assist_max_rate_rad_s: Vector3 = Vector3(0.5, 0.5, 0.9)
## Torque the main engines exert about the centre of mass at full thrust
## (non-zero when they are mounted off-axis).
@export var thrust_torque_body: Vector3 = Vector3.ZERO

@export_group("Collision")
## Body-frame hit box (placeholder until hull modules provide real geometry).
@export var hit_box_center: Vector3 = Vector3(0, 1.5, -4)
@export var hit_box_half_extents: Vector3 = Vector3(10, 6, 30)

@export_group("Armament")
## Weapon type shared by every mount; null means unarmed.
@export var cannon: KineticCannonConfig
## One muzzle per mount, body frame. All fire along the nose (-Z).
@export var cannon_muzzles_body: PackedVector3Array = PackedVector3Array([Vector3(0, 0, -34)])
## Blueprint equipment id of each mount (same order), for damage tracking.
@export var cannon_mount_ids: PackedStringArray = PackedStringArray()


## Mass with full tanks.
func wet_mass_kg() -> float:
	return mass_kg + (0.0 if unlimited_propellant else propellant_capacity_kg)


## Muzzle used for fire-control solutions.
func primary_muzzle() -> Vector3:
	return cannon_muzzles_body[0] if not cannon_muzzles_body.is_empty() else Vector3.ZERO


## Maximum thrust (N) that can push the ship along `axis` (0=X, 1=Y, 2=Z)
## in the positive or negative body direction.
func max_thrust(axis: int, positive: bool) -> float:
	match axis:
		0:
			return thrust_lateral_n
		1:
			return thrust_vertical_n
		2:
			# Body +Z is aft, so positive Z thrust comes from reverse thrusters.
			return thrust_reverse_n if positive else thrust_forward_n
	push_error("ShipConfig.max_thrust: invalid axis %d" % axis)
	return 0.0


## Returns human-readable problems; empty means the config is usable.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if mass_kg <= 0.0:
		problems.append("mass_kg must be positive (got %s)" % mass_kg)
	for axis in 3:
		if inertia_kgm2[axis] <= 0.0:
			problems.append("inertia_kgm2[%d] must be positive" % axis)
		if max_torque_nm[axis] < 0.0:
			problems.append("max_torque_nm[%d] must not be negative" % axis)
		if assist_max_rate_rad_s[axis] < 0.0:
			problems.append("assist_max_rate_rad_s[%d] must not be negative" % axis)
		if max_thrust(axis, true) < 0.0 or max_thrust(axis, false) < 0.0:
			problems.append("thrust on axis %d must not be negative" % axis)
		if hit_box_half_extents[axis] <= 0.0:
			problems.append("hit_box_half_extents[%d] must be positive" % axis)
	if propellant_capacity_kg < 0.0:
		problems.append("propellant_capacity_kg must not be negative")
	if not unlimited_propellant and (main_isp_s <= 0.0 or rcs_isp_s <= 0.0):
		problems.append("Isp must be positive when propellant is modelled")
	if cannon != null:
		for p in cannon.validate():
			problems.append("cannon: %s" % p)
		if cannon_muzzles_body.is_empty():
			problems.append("cannon needs at least one muzzle")
	return problems
