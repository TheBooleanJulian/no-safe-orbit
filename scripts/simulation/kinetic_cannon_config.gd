class_name KineticCannonConfig
extends Resource
## Immutable definition of a kinetic cannon. Data lives in data/weapons/*.tres.
## Rounds are unguided: they inherit the firing ship's velocity plus muzzle
## velocity along the nose, then follow the same gravity as everything else —
## forever, until they hit something or re-enter.

@export var display_name: String = "Kinetic cannon"
## Round speed relative to the firing ship (m/s).
@export var muzzle_velocity_mps: float = 1500.0
@export var rate_of_fire_rpm: float = 240.0
@export var magazine_rounds: int = 400
## Projectile mass (kg). Also sets recoil: Δv_ship = m_round · v_muzzle / m_ship.
@export var round_mass_kg: float = 4.0
## Armour penetration (mm of hull armour) at an impact speed equal to the
## muzzle velocity. Scales with impact speed^1.4 (de Marre-style).
@export var penetration_mm: float = 60.0
## Turret training speed (°/s); 0 = a fixed gun firing along the nose.
## Turrets only exist on ships built from a blueprint (mount faces known).
@export var traverse_deg_s: float = 0.0
## Round-to-round spread (standard deviation, degrees) of a turret.
@export var dispersion_deg: float = 0.0

const PENETRATION_SPEED_EXPONENT := 1.4


func fire_interval_s() -> float:
	return 60.0 / rate_of_fire_rpm


## Penetration (mm) at a given impact speed relative to the target.
func penetration_at(impact_speed_mps: float) -> float:
	return penetration_mm * pow(maxf(impact_speed_mps, 0.0) / muzzle_velocity_mps, PENETRATION_SPEED_EXPONENT)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if muzzle_velocity_mps <= 0.0:
		problems.append("muzzle_velocity_mps must be positive")
	if rate_of_fire_rpm <= 0.0:
		problems.append("rate_of_fire_rpm must be positive")
	if magazine_rounds < 0:
		problems.append("magazine_rounds must not be negative")
	if round_mass_kg <= 0.0:
		problems.append("round_mass_kg must be positive")
	return problems
