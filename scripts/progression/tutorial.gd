class_name Tutorial
extends RefCounted
## The opt-in guided first sortie (spec §17 Milestone 8 "tutorial flow"):
## one HUD prompt at a time — fly, aim, fire, disable, salvage, jump, repair
## — each moving on when the player has actually done it. Offered on the
## first sortie; [F2] starts it, skips it while it runs, or restarts it
## later. Saved in the profile as {state, step} (PlayerProfile.tutorial), so
## it carries over the jump home to the repair at the station.

enum State { OFFER, RUNNING, DONE, SKIPPED }
const STATE_NAMES := ["offer", "running", "done", "skipped"]

const STEPS := [
	{"id": "fly", "title": "FLY",
		"text": "Hold R to burn the main engine; W/S pitch, A/D yaw, Q/E roll (Z: flight assist)"},
	{"id": "aim", "title": "AIM",
		"text": "Turn towards the contact and hold it in sensor range until the track LOCKS (target card)"},
	{"id": "fire", "title": "FIRE",
		"text": "Click to capture the mouse, put the cursor on the gold ◇ lead marker and fire (LMB / Enter)"},
	{"id": "disable", "title": "DISABLE",
		"text": "Keep hitting it until it is DISABLED — no engines, guns or reactor (Tab ▸ TARGET lists its systems)"},
	{"id": "salvage", "title": "SALVAGE",
		"text": "Press G: a salvage beacon on the wreck pays scrap and bounty and fills your hold"},
	{"id": "jump", "title": "JUMP HOME",
		"text": "Hold B for 5 s: the jump drive takes you to Earth Shipyard (not while under fire)"},
	{"id": "repair", "title": "REPAIR",
		"text": "HANGAR ▸ SERVICE: pick a priority and press Repair, then LAUNCH ▶"},
]

var state: State = State.OFFER
var step: int = 0


static func from_dict(d: Dictionary) -> Tutorial:
	var t := Tutorial.new()
	t.state = maxi(STATE_NAMES.find(str(d.get("state", "offer"))), 0) as State
	t.step = clampi(int(d.get("step", 0)), 0, STEPS.size())
	if t.state == State.RUNNING and t.step >= STEPS.size():
		t.state = State.DONE
	return t


func to_dict() -> Dictionary:
	return {"state": STATE_NAMES[state], "step": step}


func running() -> bool:
	return state == State.RUNNING


## The step being taught ("" when not running).
func current_id() -> String:
	return STEPS[step].id if running() else ""


## [F2]: start when offered or after it ended; skip while it runs.
func toggle() -> void:
	if state == State.RUNNING:
		state = State.SKIPPED
	else:
		state = State.RUNNING
		step = 0


## The first sortie ended without it being started: don't nag again ([F2]
## still starts it).
func decline_offer() -> void:
	if state == State.OFFER:
		state = State.SKIPPED


## Move on past every step whose fact is true (`facts`: step id -> bool),
## in order. True when it moved.
func observe(facts: Dictionary) -> bool:
	if not running():
		return false
	var moved := false
	while step < STEPS.size() and bool(facts.get(STEPS[step].id, false)):
		step += 1
		moved = true
	if step >= STEPS.size():
		state = State.DONE
	return moved


## The HUD prompt ("" = none).
func prompt() -> String:
	match state:
		State.OFFER:
			return "NEW HERE? [F2] guided first sortie: fly · aim · fire · disable · salvage · jump · repair — or just fly"
		State.RUNNING:
			var s: Dictionary = STEPS[step]
			return "TUTORIAL %d/%d ▸ %s — %s   [F2] skip" % [step + 1, STEPS.size(), s.title, s.text]
	return ""
