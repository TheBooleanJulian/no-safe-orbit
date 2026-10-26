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
## Main engines on faces other than aft, by the body direction they push:
## index axis × 2 + (0 for +, 1 for −); [4] is reverse (+Z). Added to the
## RCS thrust on that side. (Aft engines are thrust_forward_n.)
@export var engine_thrust_n: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])

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
## The primary gun (mount 0; the HUD's lead marker); null means unarmed.
@export var cannon: KineticCannonConfig
## Each mount's own gun (same order as the muzzles); empty = every mount
## fires `cannon`. Batteries may mix guns: each mount has its own fire
## control (WorldSimulation trains each on its own lead).
@export var mount_cannons: Array[KineticCannonConfig] = []
## One muzzle per mount, body frame. All fire along the nose (-Z).
@export var cannon_muzzles_body: PackedVector3Array = PackedVector3Array([Vector3(0, 0, -34)])
## Blueprint equipment id of each mount (same order), for damage tracking.
@export var cannon_mount_ids: PackedStringArray = PackedStringArray()
## Outward normal of each mount's hull face (same order); empty = fixed guns.
## A turret trains anywhere above its face plane (see WorldSimulation).
@export var cannon_mount_normals_body: PackedVector3Array = PackedVector3Array()
## How far each turret's barrel rides off its face (m; same order) — a
## bigger gun's turret stands taller. Empty = WorldSimulation.TURRET_HEIGHT_M.
@export var cannon_turret_heights: PackedFloat32Array = PackedFloat32Array()
## Point-defence turrets: gun, mounts (body), face normals and ids. They
## pick their own targets (hostile craft) and have their own magazines.
@export var pd_gun: KineticCannonConfig
## Point-defence rounds in the magazine, shared by every mount (0: each
## mount carries its gun's own magazine_rounds — craft and hand-built configs).
@export var pd_magazine_rounds: int = 0
@export var pd_mounts_body: PackedVector3Array = PackedVector3Array()
@export var pd_normals_body: PackedVector3Array = PackedVector3Array()
@export var pd_mount_ids: PackedStringArray = PackedStringArray()
## Extra spread (radians, standard deviation) on top of the gun's own, e.g.
## the ship AI laying the guns without a bridge crew.
@export var cannon_extra_dispersion_rad: float = 0.0

## A craft's role, which picks how CraftAI flies its directives: &"fighter"
## (gun runs, dogfights), &"interceptor" (hunts inbound missiles and craft
## first), &"bomber" (long, steady gun runs on ships from range), &"recon"
## (watches, never fires), &"ew" (holds station to jam for the carrier).
@export var craft_role: StringName = &"fighter"
## A craft's jammer (an EW drone): ships of its side within
## WorldSimulation.EW_ESCORT_M share its noise (0 = none).
@export var jam_strength: float = 0.0
@export_group("Damage")
## Craft without a systems model: hit points of the whole hull (mm of
## penetration absorbed); 0 = never destroyed (fixed test configs).
@export var hull_hp: float = 0.0


## Mass with full tanks.
func wet_mass_kg() -> float:
	return mass_kg + (0.0 if unlimited_propellant else propellant_capacity_kg)


## Muzzle used for fire-control solutions.
func primary_muzzle() -> Vector3:
	return cannon_muzzles_body[0] if not cannon_muzzles_body.is_empty() else Vector3.ZERO


## The gun on mount k.
func mount_cannon(k: int) -> KineticCannonConfig:
	return mount_cannons[k] if k < mount_cannons.size() and mount_cannons[k] != null else cannon


## Mount k's barrel height off its face (m).
func turret_height(k: int) -> float:
	return cannon_turret_heights[k] if k < cannon_turret_heights.size() else WorldSimulation.TURRET_HEIGHT_M


## Whether mount k is a trainable turret (else it fires along the nose).
func is_turret(k: int) -> bool:
	var gun := mount_cannon(k)
	return gun != null and gun.traverse_deg_s > 0.0 and k < cannon_mount_normals_body.size()


## Every gun's rate of fire × `factor` (copies; the shared resources stay).
func scale_rate_of_fire(factor: float) -> void:
	if cannon == null:
		return
	var scaled := {}
	# A fresh array: `duplicate()` of a config shares this one with the base
	# config, and scaling it in place compounded on every recompute.
	mount_cannons = mount_cannons.duplicate()
	for gun in [cannon] + mount_cannons:
		if gun != null and not scaled.has(gun):
			var copy: KineticCannonConfig = gun.duplicate()
			copy.rate_of_fire_rpm *= factor
			scaled[gun] = copy
	cannon = scaled[cannon]
	for k in mount_cannons.size():
		if mount_cannons[k] != null:
			mount_cannons[k] = scaled[mount_cannons[k]]


## Maximum thrust (N) that can push the ship along `axis` (0=X, 1=Y, 2=Z)
## in the positive or negative body direction.
func max_thrust(axis: int, positive: bool) -> float:
	var extra := engine_thrust_n[axis * 2 + (0 if positive else 1)] if engine_thrust_n.size() == 6 else 0.0
	match axis:
		0:
			return thrust_lateral_n + extra
		1:
			return thrust_vertical_n + extra
		2:
			# Body +Z is aft, so positive Z thrust comes from reverse thrusters.
			return thrust_reverse_n + extra if positive else thrust_forward_n
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
