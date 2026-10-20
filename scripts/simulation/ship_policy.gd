class_name ShipPolicy
extends Resource
## How a ship's automation fights (spec §14: "automation policies with
## explicit priorities and understandable outcomes"). One engine for both
## sides: the player's ship runs it under manual control (manual input
## always wins — automation only ever adds fire, never blocks it), and an
## enemy ship *is* a policy plus a role, built by EnemyFactory.
##
## Presets: data/policies/{hold,defensive,standard,aggressive}.tres. A
## vessel's own copy is saved in the profile (ShipInstance.policy).
## Units: metres, seconds, degrees (tolerances), fractions 0–1.

enum Discipline {
	## Automation never fires guns or missiles (point defence still defends).
	HOLD,
	## Automation fires only at contacts that are hostile.
	TIGHT,
	## Automation fires at any contact it has a solution on.
	FREE,
}
const DISCIPLINE_NAMES := ["hold", "tight", "free"]

## Enemy tactics: a closer works in to gun range, a standoff ship holds off
## and fires missiles, a flanker works round to the stern.
enum Role { CLOSER, STANDOFF, FLANKER }
const ROLE_NAMES := ["closer", "standoff", "flanker"]
## Fighting range per role (m) and how hard it works round to the stern.
const ROLE_KEEP := [Vector2(1200.0, 3500.0), Vector2(5000.0, 9000.0), Vector2(1500.0, 4000.0)]
const ROLE_FLANK := [0.5, 0.0, 1.0]

## What point defence can engage. Rounds are big kinetic slugs on a
## collision course: PD flak bursts beside them (WorldSimulation).
const PD_KINDS: Array[StringName] = [&"missile", &"craft", &"round"]
const PD_KIND_NAMES := {&"missile": "missiles", &"craft": "craft", &"round": "rounds"}

@export var preset_name: String = "Defensive"
@export var discipline: Discipline = Discipline.TIGHT

@export_group("Point defence")
@export var pd_enabled: bool = true
## Engagement order: the first kind present in range is engaged first.
@export var pd_priorities: Array[StringName] = [&"missile", &"craft", &"round"]
## Point defence engages inside this range of its mount (m).
@export var pd_range_m: float = 2000.0
## A mount with fewer rounds than this fraction of its magazine keeps the
## rest for its first priority only.
@export var pd_reserve_fraction: float = 0.15

@export_group("Auto-salvo")
@export var salvo_enabled: bool = false
## Needs a lock and at least this track confidence (0–1).
@export var salvo_min_confidence: float = 0.8
@export var salvo_min_range_m: float = 2000.0
@export var salvo_max_range_m: float = 12000.0
## A MissileSalvo.Mode.
@export var salvo_mode: int = 1
## Missiles per salvo (0 = every missile the mode allows).
@export var salvo_count: int = 3
## Seconds between automatic salvos.
@export var salvo_interval_s: float = 20.0

@export_group("Auto-fire")
## Pull the trigger while the guns' solution is within tolerance and a lock is held.
@export var autofire_enabled: bool = false
@export var autofire_tolerance_deg: float = 0.5
## Auto-fire's share of the guns' rated rate of fire (play-test batch 6):
## automation saves rounds and heat; your own trigger is always full rate.
@export var autofire_rate: float = 0.5

@export_group("Countermeasures")
## Fire flares on their own when a missile is this close in time (s).
@export var cm_auto: bool = false
@export var cm_lead_s: float = 4.0

@export_group("Tactics (AI ships)")
@export var role: Role = Role.CLOSER
## Several AI ships shoot at the same target instead of each at its nearest.
@export var focus_fire: bool = true


## A fresh copy of a preset ("Hold", "Defensive", "Standard", "Aggressive").
static func preset(name: String) -> ShipPolicy:
	var path := "res://data/policies/%s.tres" % name.to_lower()
	var base: ShipPolicy = load(path) if ResourceLoader.exists(path) else null
	if base == null:
		return ShipPolicy.new()
	var p := base.duplicate(true) as ShipPolicy
	p.pd_priorities = base.pd_priorities.duplicate()
	return p


const PRESETS := ["Hold", "Defensive", "Standard", "Aggressive"]


## Its role's fighting range (m): x = closest, y = furthest.
func keep_range() -> Vector2:
	return ROLE_KEEP[role]


func flank_bias() -> float:
	return ROLE_FLANK[role]


## May automation fire at a contact that is (or isn't) hostile?
func allows_fire(hostile: bool) -> bool:
	match discipline:
		Discipline.HOLD:
			return false
		Discipline.TIGHT:
			return hostile
	return true


## The engagement order, every kind once, unknown ones dropped.
func pd_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in pd_priorities:
		if PD_KINDS.has(k) and not out.has(k):
			out.append(k)
	for k in PD_KINDS:
		if not out.has(k):
			out.append(k)
	return out


## Rank of a kind in the engagement order (0 = first).
func pd_rank(kind: StringName) -> int:
	return pd_order().find(kind)


## May a mount with `rounds_left` of `magazine` engage this kind? Below the
## reserve it keeps its rounds for the first priority.
func pd_allows(kind: StringName, rounds_left: int, magazine: int) -> bool:
	if not pd_enabled:
		return false
	if float(rounds_left) <= pd_reserve_fraction * float(magazine):
		return pd_rank(kind) == 0
	return true


## Auto-fire: pull the trigger? Needs a lock, a hostile-enough contact for
## the discipline, a target still fighting (`fightable`: not a derelict, not
## disabled; automation never wastes rounds on a wreck), and the guns' aim
## within tolerance of the solution.
func autofire(locked: bool, hostile: bool, aim_error_deg: float, fightable: bool = true) -> bool:
	return autofire_enabled and locked and fightable and allows_fire(hostile) and aim_error_deg <= autofire_tolerance_deg


## The trigger with automation layered on manual control: the player's
## trigger always fires (whatever the discipline); auto-fire only adds.
func trigger(manual: bool, locked: bool, hostile: bool, aim_error_deg: float, fightable: bool = true) -> bool:
	return manual or autofire(locked, hostile, aim_error_deg, fightable)


## The rate the guns fire at: full for a hand on the trigger, autofire_rate
## when only automation is firing.
func trigger_rate(manual: bool) -> float:
	return 1.0 if manual else clampf(autofire_rate, 0.1, 1.0)


## Auto-countermeasures: fire flares now? (`missile_s`: the nearest
## inbound missile's time to impact, < 0 if none.)
func cm_due(missile_s: float) -> bool:
	return cm_auto and missile_s >= 0.0 and missile_s <= cm_lead_s


## Auto-salvo: start one now?
func salvo_due(locked: bool, confidence: float, range_m: float, hostile: bool, now: float, next_at: float,
		fightable: bool = true) -> bool:
	return salvo_enabled and locked and fightable and confidence >= salvo_min_confidence and allows_fire(hostile) \
		and range_m >= salvo_min_range_m and range_m <= salvo_max_range_m and now >= next_at


## One line for the HUD and the drawer.
func summary() -> String:
	var bits := PackedStringArray(["%s · fire %s" % [preset_name, DISCIPLINE_NAMES[discipline]]])
	bits.append("PD %s" % (" › ".join(pd_order().map(func(k: StringName) -> String: return PD_KIND_NAMES[k])) if pd_enabled else "off"))
	if autofire_enabled:
		bits.append("auto-fire ≤%.1f° at %d%% rate" % [autofire_tolerance_deg, roundi(autofire_rate * 100.0)])
	if cm_auto:
		bits.append("auto-flares ≤%.0fs" % cm_lead_s)
	if salvo_enabled:
		bits.append("auto-salvo %s ×%s" % [MissileSalvo.MODE_NAMES[clampi(salvo_mode, 0, MissileSalvo.MODE_NAMES.size() - 1)],
			str(salvo_count) if salvo_count > 0 else "all"])
	return " · ".join(bits)


# --- Persistence ---------------------------------------------------------------------

const SAVED := ["preset_name", "discipline", "pd_enabled", "pd_range_m", "pd_reserve_fraction", "salvo_enabled",
	"salvo_min_confidence", "salvo_min_range_m", "salvo_max_range_m", "salvo_mode", "salvo_count", "salvo_interval_s",
	"autofire_enabled", "autofire_tolerance_deg", "autofire_rate", "cm_auto", "cm_lead_s"]


func to_dict() -> Dictionary:
	var d := {}
	for key in SAVED:
		d[key] = get(key)
	d["pd_priorities"] = Array(pd_order()).map(func(k: StringName) -> String: return String(k))
	return d


## From a saved dictionary; missing or bad values fall back to the
## Defensive preset's, numbers are clamped to sane ranges.
static func from_dict(d: Dictionary) -> ShipPolicy:
	var p := preset(str(d.get("preset_name", "Defensive"))) if PRESETS.has(str(d.get("preset_name", ""))) else preset("Defensive")
	p.preset_name = str(d.get("preset_name", p.preset_name))
	p.discipline = clampi(int(d.get("discipline", p.discipline)), 0, Discipline.size() - 1) as Discipline
	p.pd_enabled = bool(d.get("pd_enabled", p.pd_enabled))
	p.pd_range_m = clampf(float(d.get("pd_range_m", p.pd_range_m)), 200.0, 5000.0)
	p.pd_reserve_fraction = clampf(float(d.get("pd_reserve_fraction", p.pd_reserve_fraction)), 0.0, 0.9)
	p.salvo_enabled = bool(d.get("salvo_enabled", p.salvo_enabled))
	p.salvo_min_confidence = clampf(float(d.get("salvo_min_confidence", p.salvo_min_confidence)), 0.0, 1.0)
	p.salvo_min_range_m = clampf(float(d.get("salvo_min_range_m", p.salvo_min_range_m)), 0.0, 30000.0)
	p.salvo_max_range_m = clampf(float(d.get("salvo_max_range_m", p.salvo_max_range_m)), p.salvo_min_range_m, 30000.0)
	p.salvo_mode = clampi(int(d.get("salvo_mode", p.salvo_mode)), 0, MissileSalvo.Mode.size() - 1)
	p.salvo_count = clampi(int(d.get("salvo_count", p.salvo_count)), 0, 99)
	p.salvo_interval_s = clampf(float(d.get("salvo_interval_s", p.salvo_interval_s)), 2.0, 300.0)
	p.autofire_enabled = bool(d.get("autofire_enabled", p.autofire_enabled))
	p.autofire_tolerance_deg = clampf(float(d.get("autofire_tolerance_deg", p.autofire_tolerance_deg)), 0.05, 5.0)
	p.autofire_rate = clampf(float(d.get("autofire_rate", p.autofire_rate)), 0.1, 1.0)
	p.cm_auto = bool(d.get("cm_auto", p.cm_auto))
	p.cm_lead_s = clampf(float(d.get("cm_lead_s", p.cm_lead_s)), 1.0, 15.0)
	var order: Variant = d.get("pd_priorities", [])
	if order is Array:
		var kinds: Array[StringName] = []
		for k in order:
			kinds.append(StringName(str(k)))
		p.pd_priorities = kinds
		p.pd_priorities = p.pd_order()
	return p
