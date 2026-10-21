class_name TechTree
extends RefCounted
## Earth Shipyard's upgrades, bought with credits (play-test batch 9: a
## branching tree, read left to right). It starts from one node — the
## shipyard charter — and branches out: every node has up to MAX_LEVEL
## levels at COSTS, level 1 needs its parent node at the level in "after",
## each further level the one before. A node's column is its tier: its
## parent's tier plus its level. Levels are kept by id (PlayerProfile.tech),
## so upgrades bought before the tree branched are kept. ShipSystems,
## PlayerProfile, AirWing and Main read the levels (player ships only).

const MAX_LEVEL := 3
const COSTS := [300, 700, 1500]
const CHARTER_COST := 150

## id, name, what one level does, effect per level (fraction of 1; negative
## lowers a cost), its parent [id, level] (none: the root), levels.
const NODES := [
	{"id": "charter", "name": "Shipyard charter", "text": "opens the yard's technology to you", "per": 0.0, "after": [], "levels": 1},
	{"id": "thrusters", "name": "Tuned thrusters", "text": "+5 % thrust from every engine and RCS block", "per": 0.05, "after": ["charter", 1]},
	{"id": "gunnery", "name": "Gunnery drills", "text": "+5 % rate of fire", "per": 0.05, "after": ["charter", 1]},
	{"id": "damage_control", "name": "Damage control", "text": "+15 % faster field repairs and hull sealing", "per": 0.15, "after": ["charter", 1]},
	{"id": "reactor", "name": "Reactor tuning", "text": "+8 % reactor output", "per": 0.08, "after": ["thrusters", 1]},
	{"id": "radiators", "name": "Radiator coatings", "text": "+8 % heat rejected by radiators", "per": 0.08, "after": ["reactor", 1]},
	{"id": "jump", "name": "Jump calibration", "text": "−5 % Δv for every jump", "per": -0.05, "after": ["thrusters", 2]},
	{"id": "pd_control", "name": "PD fire control", "text": "+10 % point-defence rate of fire", "per": 0.1, "after": ["gunnery", 1]},
	{"id": "sensors", "name": "Sensor suites", "text": "+10 % sensor range", "per": 0.1, "after": ["gunnery", 2]},
	{"id": "hangar_crews", "name": "Hangar crews", "text": "+15 % faster turnaround of craft", "per": 0.15, "after": ["pd_control", 1]},
	{"id": "medicine", "name": "Field medicine", "text": "+15 % faster treatment of the wounded", "per": 0.15, "after": ["damage_control", 1]},
	{"id": "salvage", "name": "Salvage contacts", "text": "+5 % credits for scrap", "per": 0.05, "after": ["damage_control", 2]},
	{"id": "academy", "name": "Crew academy", "text": "−20 % on crew training", "per": -0.2, "after": ["medicine", 1]},
	{"id": "welfare", "name": "Crew welfare fund", "text": "−20 % on wages", "per": -0.2, "after": ["academy", 1]},
	{"id": "bounty", "name": "Bounty licences", "text": "+10 % bounty on wrecks", "per": 0.1, "after": ["salvage", 2]},
]


static func node(id: String) -> Dictionary:
	for n in NODES:
		if n.id == id:
			return n
	return {}


static func levels(id: String) -> int:
	return int(node(id).get("levels", MAX_LEVEL))


## Multiplier for `id` at `level` (1 + per × level).
static func factor(id: String, level: int) -> float:
	var n := node(id)
	return 1.0 + float(n.get("per", 0.0)) * clampi(level, 0, levels(id))


## Credits for the next level of a node at `level`, or -1 at the top. (An
## old call with only a level prices a three-level node.)
static func next_cost(level: int, id: String = "") -> int:
	if id == "charter":
		return CHARTER_COST if level < 1 else -1
	return COSTS[level] if level < MAX_LEVEL else -1


## What level `level` of `id` needs: [id, level] ([] for the root's first).
static func requirement(id: String, level: int) -> Array:
	if level > 1:
		return [id, level - 1]
	return node(id).get("after", [])


## Its column: the parent's tier plus its level (the charter 0).
static func tier(id: String, level: int) -> int:
	var req := requirement(id, 1)
	if req.is_empty():
		return level - 1
	return tier(str(req[0]), int(req[1])) + level


## Why the next level of `id` can't be bought with `have` (id -> level):
## "" if it can (credits aside).
static func block_reason(id: String, have: Dictionary) -> String:
	if node(id).is_empty():
		return "no such upgrade"
	var level := int(have.get(id, 0))
	if level >= levels(id):
		return "already at the top level"
	var req := requirement(id, level + 1)
	if not req.is_empty() and int(have.get(str(req[0]), 0)) < int(req[1]):
		return "needs %s %s first" % [node(str(req[0])).name, roman(int(req[1]))]
	return ""


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV"][clampi(n, 0, 4)]
