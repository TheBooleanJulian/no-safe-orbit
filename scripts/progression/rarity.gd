class_name Rarity
extends RefCounted
## Rarity tiers for catalog parts and loot drops. COMMON parts are standard
## fleet issue: always available, fabricated from spare parts. Everything
## rarer must be found in salvage (LootRoller) before it can be built.

enum Tier { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
## Functional tier colours (UI only, not brand colours): grey, green, teal,
## violet, gold.
const COLORS := [
	Color(0.62, 0.66, 0.72),
	Color(0.44, 0.82, 0.55),
	Color(0.0, 0.83, 0.78),
	Color(0.71, 0.55, 1.0),
	Color(0.96, 0.78, 0.26),
]
## Cascading roll: every drop starts COMMON and climbs one tier at a time
## with these chances (index = current tier).
const UPGRADE_CHANCE := [0.30, 0.30, 0.25, 0.20]


static func name_of(tier: int) -> String:
	return NAMES[clampi(tier, 0, NAMES.size() - 1)]


static func color_of(tier: int) -> Color:
	return COLORS[clampi(tier, 0, COLORS.size() - 1)]


## Exact chance of each final tier from the cascade alone (no pity):
## P(tier t) = Π_{k<t} up_k · (1 − up_t).
static func tier_probabilities() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var reach := 1.0
	for t in Tier.size():
		var stay: float = 1.0 - UPGRADE_CHANCE[t] if t < UPGRADE_CHANCE.size() else 1.0
		out.append(reach * stay)
		if t < UPGRADE_CHANCE.size():
			reach *= UPGRADE_CHANCE[t]
	return out
