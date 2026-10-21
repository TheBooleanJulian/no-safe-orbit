class_name MissionChain
extends RefCounted
## The campaign's stated goals (spec §17 Milestone 8 "mission objectives"):
## a short chain — disable, capture, escort, survive waves — then open
## patrols. The current goal shows on the HUD and in the debrief; meeting it
## pays its reward and moves the chain on. A goal not met stays for the next
## sortie. Saved in the profile as {"step": n} (PlayerProfile.campaign).

## DELIVER (play-test batch 9): a cargo contract — no fight; it is met on
## arriving at the destination with the freight aboard (ContractBoard.deliver).
enum Goal { DISABLE, CAPTURE, ESCORT, WAVES, PATROL, DELIVER }

const CHAIN := [
	{"goal": Goal.DISABLE, "title": "First blood",
		"brief": "Disable the contact: knock out its engines, its guns or its reactor",
		"credits": 150, "parts": 0},
	{"goal": Goal.CAPTURE, "title": "Prize crew",
		"brief": "Capture the contact: gangway [V], boarders [N], take its bridge",
		"credits": 250, "parts": 20},
	{"goal": Goal.ESCORT, "title": "Courier run",
		"brief": "Escort the courier: keep it alive until the contact is disabled",
		"credits": 300, "parts": 10},
	{"goal": Goal.WAVES, "title": "Hold the line", "waves": 2,
		"brief": "Survive 2 waves: beat 2 contacts in one sortie, no jumping home between",
		"credits": 400, "parts": 30},
]
## After the chain: every contact beaten pays a patrol bonus.
const PATROL := {"goal": Goal.PATROL, "title": "Patrol",
	"brief": "Disable or capture the contact", "credits": 100, "parts": 0}
## The escort's courier: how tough it is (hull points, as a craft's).
const COURIER_HULL_HP := 1500.0

var step: int = 0
## An accepted contract (ContractBoard) runs instead of the chain's goal:
## its goal, brief and reward; completing it doesn't move the chain on.
var contract: Dictionary = {}
## This sortie: contacts beaten so far, and why the goal failed ("" = it hasn't).
var waves_beaten: int = 0
var failed: String = ""


static func from_dict(d: Dictionary) -> MissionChain:
	var m := MissionChain.new()
	m.step = clampi(int(d.get("step", 0)), 0, CHAIN.size())
	return m


func to_dict() -> Dictionary:
	return {"step": step}


func current() -> Dictionary:
	if not contract.is_empty():
		return contract
	return CHAIN[step] if step < CHAIN.size() else PATROL


func goal() -> Goal:
	return current().goal


## "MISSION 2/4" while the chain lasts, then "PATROL".
func number_text() -> String:
	if not contract.is_empty():
		return "CONTRACT · %s" % ContractBoard.giver(contract).role.to_upper()
	return "MISSION %d/%d" % [step + 1, CHAIN.size()] if step < CHAIN.size() else "PATROL"


static func reward_text(m: Dictionary) -> String:
	return "%d cr%s" % [int(m.credits), " + %d parts" % int(m.parts) if int(m.parts) > 0 else ""]


## The objective line for the HUD and the hangar.
func hud_line() -> String:
	var m := current()
	var progress := ""
	if goal() == Goal.WAVES:
		progress = " (%d/%d)" % [mini(waves_beaten, int(m.waves)), int(m.waves)]
	if failed != "":
		return "%s ▸ %s — FAILED: %s · next sortie, again" % [number_text(), str(m.title).to_upper(), failed]
	return "%s ▸ %s — %s%s · reward %s" % [number_text(), str(m.title).to_upper(), m.brief, progress, reward_text(m)]


## A contact was beaten (disabled, or captured before it was disabled).
## True when that meets the goal.
func contact_beaten() -> bool:
	waves_beaten += 1
	if failed != "":
		return false
	match goal():
		Goal.DISABLE, Goal.ESCORT, Goal.PATROL:
			return true
		Goal.WAVES:
			return waves_beaten >= int(current().waves)
	return false


## Our boarders took the contact's bridge. True when that meets the goal.
func contact_captured() -> bool:
	return failed == "" and (goal() == Goal.CAPTURE or goal() == Goal.PATROL)


func escort_lost() -> void:
	if goal() == Goal.ESCORT and failed == "":
		failed = "the courier was destroyed"


## The goal is met: pay its reward into `profile` and move on. Returns the
## line for the HUD and the log.
func complete(profile: PlayerProfile) -> String:
	var m := current()
	profile.credits += int(m.credits)
	profile.spare_parts += int(m.parts)
	var line := "%s COMPLETE — %s: +%s" % [number_text(), m.title, reward_text(m)]
	if not contract.is_empty():
		contract = {}
		profile.active_contract = {}
	elif step < CHAIN.size():
		step += 1
	waves_beaten = 0
	profile.campaign = to_dict()
	return line


## A flight config for the escort's courier: a slow, unarmed freighter with
## a craft's hull points (rounds take penetration off them).
static func courier_config() -> ShipConfig:
	var cfg := ShipConfig.new()
	cfg.display_name = "Courier"
	cfg.mass_kg = 90_000.0
	cfg.inertia_kgm2 = Vector3(1.2e6, 1.2e6, 3.0e5)
	cfg.thrust_forward_n = 2.0e5
	cfg.thrust_reverse_n = 5.0e4
	cfg.thrust_lateral_n = 5.0e4
	cfg.thrust_vertical_n = 5.0e4
	cfg.hit_box_center = Vector3.ZERO
	cfg.hit_box_half_extents = Vector3(3.0, 3.0, 12.0)
	cfg.cannon_muzzles_body = PackedVector3Array()
	cfg.hull_hp = COURIER_HULL_HP
	return cfg


## The escort's courier as a ship on our side: with no side, our point
## defence took it for hostile craft (play-test batch 9: "automatic weapons
## fire upon friendly escorts"); our craft's IFF spares it too.
static func courier_ship(id: StringName, position: Vector3, velocity: Vector3, orientation: Quaternion) -> ShipState:
	var c := ShipState.create(id, "COURIER", courier_config(), position, velocity, orientation)
	c.side = &"player"
	return c
