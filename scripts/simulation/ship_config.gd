class_name ShipConfig
extends Resource
## Immutable flight-tuning data for one ship design (placeholder until the
## blueprint system in Milestone 2 derives these values from modules).
##
## Units: kg, N, N·m, kg·m², rad/s.
## Body axes (Godot convention): +X right, +Y up, -Z forward (nose), +Z aft.

@export var display_name: String = "Unnamed hull"

@export_group("Mass properties")
@export var mass_kg: float = 250_000.0
## Principal moments of inertia about body X (pitch), Y (yaw) and Z (roll).
@export var inertia_kgm2: Vector3 = Vector3(7.8e7, 8.0e7, 7.7e6)

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

@export_group("Collision")
## Body-frame hit box (placeholder until hull modules provide real geometry).
@export var hit_box_center: Vector3 = Vector3(0, 1.5, -4)
@export var hit_box_half_extents: Vector3 = Vector3(10, 6, 30)

@export_group("Armament")
## Optional; null means unarmed. Placeholder for a blueprint weapon mount.
@export var cannon: KineticCannonConfig
## Muzzle position in the body frame. Rounds fire along the nose (-Z).
@export var cannon_muzzle_body: Vector3 = Vector3(0, 0, -34)


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
	if cannon != null:
		for p in cannon.validate():
			problems.append("cannon: %s" % p)
	return problems
