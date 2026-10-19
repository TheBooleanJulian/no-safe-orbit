class_name MissileConfig
extends Resource
## A guided missile (spec §10 "Missiles"): finite acceleration, Δv and turn
## rate, a proximity fuse and a warhead. In flight it is a small ShipState
## flown by WorldSimulation's guidance (zero-effort-miss proportional
## navigation); rounds and point defence can shoot it down (hull_hp).
## Data lives in data/missiles/*.tres.

enum Warhead {
	## Shaped charge: a penetrator (penetration_mm) along its line of flight
	## plus a small blast (blast_radius_m) at the hull.
	ANTI_SHIP,
	## Disrupts electronics within reach (ShipSystems.emp): exposure 1 at
	## effect_radius_m, falling with the square of the distance.
	EMP,
	## Radiation and heat (ShipSystems.nuclear) with an EMP, exposure 1 at
	## effect_radius_m; no blast wave in vacuum.
	NUCLEAR,
}

const ISP_S := 280.0

@export var display_name: String = "Anti-ship missile"
@export var warhead: Warhead = Warhead.ANTI_SHIP
## Dry mass with the warhead (kg); propellant is on top (delta_v_mps).
@export var mass_kg: float = 250.0
@export var accel_mps2: float = 60.0
@export var delta_v_mps: float = 1500.0
## How fast the guidance can swing the thrust (°/s).
@export var turn_rate_deg_s: float = 120.0
## Detonates within this of the target's hull (m), once armed.
@export var fuse_radius_m: float = 6.0
@export var arm_s: float = 1.5
@export var hull_hp: float = 6.0
## Self-destructs after this long (s).
@export var lifetime_s: float = 150.0
@export var penetration_mm: float = 160.0
@export var blast_radius_m: float = 8.0
@export var effect_radius_m: float = 400.0
## Yard price per missile at resupply (credits).
@export var unit_credits: int = 60


func propellant_kg() -> float:
	return mass_kg * (exp(delta_v_mps / (ISP_S * ShipDynamics.G0)) - 1.0)


## The flight config of one missile: a slender body that only thrusts
## forward (the guidance points it).
func to_ship_config() -> ShipConfig:
	var cfg := ShipConfig.new()
	cfg.display_name = display_name
	cfg.mass_kg = mass_kg
	var wet := mass_kg + propellant_kg()
	cfg.inertia_kgm2 = Vector3(wet * 0.4, wet * 0.4, wet * 0.02)
	cfg.unlimited_propellant = false
	cfg.propellant_capacity_kg = propellant_kg()
	cfg.main_isp_s = ISP_S
	cfg.rcs_isp_s = ISP_S
	cfg.thrust_forward_n = wet * accel_mps2
	cfg.thrust_reverse_n = 0.0
	cfg.thrust_lateral_n = 0.0
	cfg.thrust_vertical_n = 0.0
	cfg.max_torque_nm = Vector3.ONE
	cfg.assist_max_rate_rad_s = Vector3.ONE
	cfg.hit_box_center = Vector3.ZERO
	cfg.hit_box_half_extents = Vector3(0.4, 0.4, 1.4)
	cfg.cannon_muzzles_body = PackedVector3Array()
	cfg.hull_hp = hull_hp
	return cfg
