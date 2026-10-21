class_name ContractBoard
extends RefCounted
## The station's mission board (Milestone 12/13): people at the yard with
## work — a bounty, a capture, an escort, a defence — each a contract the
## player can accept for the next sortie. A contract fixes where the sortie
## flies, how many ships it meets and how dangerous they are, and pays its
## reward when its goal is met (MissionChain runs it like a chain goal).
## Offers are seeded by the profile and refreshed after every sortie.

const OFFERS := 4

## Who offers work: name, what they do, their colour on the board.
const GIVERS := [
	{"name": "Cmdr. Hollis Reyes", "role": "Navy liaison", "color": Color(0.35, 0.75, 1.0)},
	{"name": "Ines Okonkwo-Vale", "role": "Merchant guild factor", "color": Color(0.96, 0.78, 0.26)},
	{"name": "\"Nine\" Castellane", "role": "Bounty broker", "color": Color(1.0, 0.36, 0.5)},
	{"name": "Dr. Saoirse Lund", "role": "Salvage boss", "color": Color(0.5, 0.9, 0.55)},
	{"name": "Chief Oyelaran", "role": "Station security", "color": Color(0.8, 0.55, 1.0)},
]

## Kinds of work: the goal it runs as, its title and brief, who offers it,
## and its base pay (credits, spare parts) per ship met.
const KINDS := [
	{"kind": "bounty", "goal": MissionChain.Goal.DISABLE, "title": "Bounty: %s", "giver": 2,
		"brief": "Disable the %s and the bounty is yours", "credits": 160, "parts": 0},
	{"kind": "capture", "goal": MissionChain.Goal.CAPTURE, "title": "Seize the %s", "giver": 0,
		"brief": "Board the %s and take its bridge — the Navy wants the hull", "credits": 240, "parts": 15},
	{"kind": "escort", "goal": MissionChain.Goal.ESCORT, "title": "Courier for the guild", "giver": 1,
		"brief": "Keep the guild courier alive until its attackers are disabled", "credits": 220, "parts": 10},
	{"kind": "defend", "goal": MissionChain.Goal.WAVES, "title": "Hold the approach", "giver": 4,
		"brief": "Beat %d contacts in one sortie; no jumping home between", "credits": 200, "parts": 20},
	{"kind": "salvage", "goal": MissionChain.Goal.DISABLE, "title": "Wreck for the salvage boss", "giver": 3,
		"brief": "Disable the %s intact enough to strip: the yard pays for the hull", "credits": 140, "parts": 35},
]

const TARGETS := ["Kestrel raider", "Harrier pirate", "Shrike smuggler", "Goshawk deserter", "Saker privateer"]


## Fresh offers for `profile` (deterministic for its seed and sortie count).
static func generate(profile: PlayerProfile) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("board|%d|%d" % [profile.board_seed, profile.sorties_flown()])
	var out := []
	var known: Array = profile.known_locations
	for i in OFFERS:
		var k: Dictionary = KINDS[rng.randi() % KINDS.size()]
		var ships := rng.randi_range(1, PlayerProfile.MAX_ENCOUNTER)
		if k.kind == "defend":
			ships = maxi(ships, 2)
		var level := profile.missions_completed + 1 + ships - 1 + rng.randi_range(0, 1)
		var target: String = TARGETS[rng.randi() % TARGETS.size()]
		var pay := float(ships) * (1.0 + 0.15 * float(level - 1))
		var title: String = k.title % target if str(k.title).contains("%s") else k.title
		var brief: String = (k.brief % ships) if k.kind == "defend" else (k.brief % target if str(k.brief).contains("%s") else k.brief)
		out.append({
			"id": "c%d_%d" % [profile.sorties_flown(), i],
			"kind": k.kind, "goal": int(k.goal), "title": title, "brief": brief,
			"giver": int(k.giver), "location": known[rng.randi() % known.size()],
			"ships": ships, "threat": level, "waves": ships if k.kind == "defend" else 0,
			"credits": roundi(float(k.credits) * pay / 10.0) * 10, "parts": roundi(float(k.parts) * pay),
		})
	return out


## The giver of a contract.
static func giver(c: Dictionary) -> Dictionary:
	return GIVERS[clampi(int(c.get("giver", 0)), 0, GIVERS.size() - 1)]


## Accept offer `id` from the board: it becomes the active contract and sets
## the next sortie's encounter size and its launch point — the course
## (PlayerProfile.launch_point): the jump there happens at LAUNCH, paid then
## (play-test batch 7). "" or why not: a jump beyond what the ship can
## carry, even with full tanks, leaves the offer up.
static func accept(profile: PlayerProfile, id: String) -> String:
	if not profile.active_contract.is_empty():
		return "Finish or abandon %s first" % profile.active_contract.title
	for c in profile.board:
		if str(c.id) == id:
			var loc := Location.by_id(str(c.location))
			var need := profile.jump_dv(loc.id)
			var full := float(profile.vessel_tanks(ConstructionCatalog.default_catalog()).dv_full_mps)
			if need > full:
				return "The jump to %s needs %s; full tanks and the reserve give this ship %s" % [loc.station_name,
					JumpDrive.dv_text(need), JumpDrive.dv_text(full)]
			profile.jump_target = ""
			profile.active_contract = (c as Dictionary).duplicate()
			profile.board.erase(c)
			profile.encounter_size = int(c.ships)
			return ""
	return "That offer is gone"


## Give the active contract up (no pay, no penalty beyond the lost work).
static func abandon(profile: PlayerProfile) -> void:
	profile.active_contract = {}


## After a sortie: new offers if the board is stale.
static func refresh(profile: PlayerProfile) -> void:
	if profile.board_sortie != profile.sorties_flown() or profile.board.is_empty():
		profile.board = generate(profile)
		profile.board_sortie = profile.sorties_flown()
