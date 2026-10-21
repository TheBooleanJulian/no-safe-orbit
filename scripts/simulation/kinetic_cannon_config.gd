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
## Armour penetration (mm of hull armour). Rounds keep it however far they
## fly (vacuum: nothing slows them); a head-on closing speed adds up to
## HEAD_ON_BONUS_MAX, de Marre-style (speed^1.4).
@export var penetration_mm: float = 60.0
## Turret training speed (°/s); 0 = a fixed gun firing along the nose.
## Turrets only exist on ships built from a blueprint (mount faces known).
@export var traverse_deg_s: float = 0.0
## Round-to-round spread (standard deviation, degrees) of a turret.
@export var dispersion_deg: float = 0.0
## Beam weapon (laser) when above 0: its reach (m). A beam has no round —
## each pulse reaches the first hull on its line at once (no travel time, no
## recoil, nothing to dodge or shoot down), with `penetration_mm` falling to
## BEAM_FALLOFF of it at full reach. On a ship it uses no magazine: it costs
## power (its mount's power_kw) and heat (heat_kw per second of fire). On a
## craft `magazine_rounds` are capacitor charges, recharged aboard the carrier.
## Set muzzle_velocity_mps to the speed of light so fire control leads by nothing.
@export var beam_range_m: float = 0.0
## The beam's colour.
@export var beam_color: Color = Color(0.45, 1.0, 0.95)

const PENETRATION_SPEED_EXPONENT := 1.4
const HEAD_ON_BONUS_MAX := 1.3
## A beam's penetration at full reach, as a fraction of its penetration_mm
## (the spot spreads with distance).
const BEAM_FALLOFF := 0.5


func is_beam() -> bool:
	return beam_range_m > 0.0


## A beam's penetration (mm) at `range_m`: falls linearly to BEAM_FALLOFF
## of penetration_mm at full reach; nothing beyond it.
func beam_penetration_at(range_m: float) -> float:
	if range_m > beam_range_m:
		return 0.0
	return penetration_mm * lerpf(1.0, BEAM_FALLOFF, clampf(range_m / beam_range_m, 0.0, 1.0))


func fire_interval_s() -> float:
	return 60.0 / rate_of_fire_rpm


## Penetration (mm) at a given impact speed relative to the target.
func penetration_at(impact_speed_mps: float) -> float:
	var k := pow(maxf(impact_speed_mps, 0.0) / muzzle_velocity_mps, PENETRATION_SPEED_EXPONENT)
	return penetration_mm * clampf(k, 1.0, HEAD_ON_BONUS_MAX)


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
	if beam_range_m < 0.0:
		problems.append("beam_range_m must not be negative")
	return problems
