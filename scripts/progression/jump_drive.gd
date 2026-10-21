class_name JumpDrive
extends Resource
## The dimensional jump drive's running costs (Milestone 13, decision 2).
## A jump costs Δv — the same for every ship (play-test batch 7: costs in
## tonnes meant something different for every craft) — growing slowly
## (logarithmically) with the distance; a jump home within a location covers
## no distance and costs only the base. Each ship pays it in propellant by
## the rocket equation at its own main-engine Isp: the main tank first, then
## the drive's own reserve, which thrusters and RCS can't draw on. A jump
## that can't be paid is refused with the reason; in flight a paid rescue
## tow brings the ship home instead, so nobody is ever stranded.
## Data: data/jump/jump_drive.tres.

const PATH := "res://data/jump/jump_drive.tres"

## Δv (m/s) any jump costs.
@export var base_dv_mps: float = 70.0
## Extra Δv (m/s) per decade of distance (log10).
@export var distance_dv_mps: float = 160.0
## Distance unit of the log term (m): 1 000 km.
@export var distance_scale_m: float = 1.0e6
## The drive's reserve, as a share of the ship's propellant capacity.
@export var reserve_fraction: float = 0.25
## The rescue tow's fee: a call-out plus per tonne of ship (credits).
@export var tow_base_credits: int = 150
@export var tow_credits_per_t: float = 0.5

static var _default: JumpDrive


static func standard() -> JumpDrive:
	if _default == null:
		_default = load(PATH) as JumpDrive
	return _default


## A ship without main engines pays at this Isp (s).
const FALLBACK_ISP_S := 300.0


## Δv (m/s) a jump of `distance_m` costs — any ship.
func delta_v(distance_m: float) -> float:
	var decades := log(1.0 + maxf(distance_m, 0.0) / distance_scale_m) / log(10.0)
	return base_dv_mps + distance_dv_mps * decades


## Propellant (kg) a jump of `distance_m` burns for a ship of `mass_kg`
## whose engines run at `isp_s`.
func cost_kg(mass_kg: float, distance_m: float, isp_s: float) -> float:
	return propellant_for(mass_kg, delta_v(distance_m), isp_s)


## Rocket equation: propellant (kg) for `dv` from a ship of `mass_kg`.
static func propellant_for(mass_kg: float, dv: float, isp_s: float) -> float:
	return mass_kg * (1.0 - exp(-maxf(dv, 0.0) / _exhaust(isp_s)))


## Rocket equation: the Δv (m/s) `propellant_kg` of a ship of `mass_kg`
## (propellant included) buys.
static func delta_v_of(mass_kg: float, propellant_kg: float, isp_s: float) -> float:
	var dry := mass_kg - clampf(propellant_kg, 0.0, mass_kg)
	if dry <= 0.0:
		return INF
	return _exhaust(isp_s) * log(mass_kg / dry)


static func _exhaust(isp_s: float) -> float:
	return (isp_s if isp_s > 0.0 else FALLBACK_ISP_S) * ShipDynamics.G0


## The reserve a ship with `capacity_kg` of tankage carries.
func reserve_capacity_kg(capacity_kg: float) -> float:
	return capacity_kg * reserve_fraction


## Pay `cost` from the main tank, then the reserve:
## {ok, main_kg, reserve_kg} with what is left (unchanged when not ok).
static func pay(main_kg: float, reserve_kg: float, cost: float) -> Dictionary:
	if cost > main_kg + reserve_kg + 1e-6:
		return {"ok": false, "main_kg": main_kg, "reserve_kg": reserve_kg}
	var from_main := minf(cost, main_kg)
	return {"ok": true, "main_kg": main_kg - from_main, "reserve_kg": maxf(reserve_kg - (cost - from_main), 0.0)}


## The rescue tow's fee for a ship of `mass_kg` (credits).
func tow_credits(mass_kg: float) -> int:
	return tow_base_credits + ceili(mass_kg / 1000.0 * tow_credits_per_t)


## "4.8 t" for the HUD and the yard.
static func tonnes(kg: float) -> String:
	return "%.1f t" % (kg / 1000.0)


## "Δv 1 250 m/s".
static func dv_text(mps: float) -> String:
	if not is_finite(mps):
		return "Δv ∞"
	return "Δv %s m/s" % SystemMap._thousands(roundi(mps))
