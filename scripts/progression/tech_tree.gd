class_name TechTree
extends RefCounted
## Earth Shipyard's upgrades, bought with credits: ship technology (applies
## to every vessel) and the captain's training. Each node has MAX_LEVEL
## levels at COSTS; ShipSystems reads the levels (player ships only).

const MAX_LEVEL := 3
const COSTS := [300, 700, 1500]

## id, name, branch, what one level does, effect per level (fraction).
const NODES := [
	{"id": "thrusters", "name": "Tuned thrusters", "branch": "SHIP", "text": "+5 % thrust from every engine and RCS block", "per": 0.05},
	{"id": "radiators", "name": "Radiator coatings", "branch": "SHIP", "text": "+8 % heat rejected by radiators", "per": 0.08},
	{"id": "reactor", "name": "Reactor tuning", "branch": "SHIP", "text": "+8 % reactor output", "per": 0.08},
	{"id": "gunnery", "name": "Gunnery drills", "branch": "CAPTAIN", "text": "+5 % rate of fire", "per": 0.05},
	{"id": "damage_control", "name": "Damage-control training", "branch": "CAPTAIN", "text": "+15 % faster field repairs and hull sealing", "per": 0.15},
	{"id": "medicine", "name": "Field medicine", "branch": "CAPTAIN", "text": "+15 % faster treatment of the wounded", "per": 0.15},
	{"id": "salvage", "name": "Salvage contacts", "branch": "CAPTAIN", "text": "+5 % credits for scrap", "per": 0.05},
]


static func node(id: String) -> Dictionary:
	for n in NODES:
		if n.id == id:
			return n
	return {}


## Multiplier for `id` at `level` (1 + per × level).
static func factor(id: String, level: int) -> float:
	var n := node(id)
	return 1.0 + float(n.get("per", 0.0)) * clampi(level, 0, MAX_LEVEL)


## Credits for the next level, or -1 at the top.
static func next_cost(level: int) -> int:
	return COSTS[level] if level < MAX_LEVEL else -1
