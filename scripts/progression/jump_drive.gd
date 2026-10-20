class_name JumpDrive
extends Resource
## The dimensional jump drive's running costs (Milestone 13, decision 2).
## A jump burns propellant: the main tank first, then the drive's own
## reserve, which thrusters and RCS can't draw on. The cost grows with the
## ship's mass and, slowly (logarithmically), with the distance; a jump home
## within a location covers no distance and costs only the base. A jump
## that can't be paid is refused with the reason; in flight a paid rescue
## tow brings the ship home instead, so nobody is ever stranded.
## Data: data/jump/jump_drive.tres.

const PATH := "res://data/jump/jump_drive.tres"

## Propellant per tonne of ship (kg/t) for any jump.
@export var base_kg_per_t: float = 8.0
## Extra propellant per tonne (kg/t) per decade of distance (log10).
@export var distance_kg_per_t: float = 18.0
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


## Propellant (kg) a jump of `distance_m` costs a ship of `mass_kg`.
func cost_kg(mass_kg: float, distance_m: float) -> float:
	var decades := log(1.0 + maxf(distance_m, 0.0) / distance_scale_m) / log(10.0)
	return mass_kg / 1000.0 * (base_kg_per_t + distance_kg_per_t * decades)


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
