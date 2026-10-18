class_name LootRoller
extends RefCounted
## Salvage loot: cascading weighted rarity with hard pity (docs/ARCHITECTURE.md
## → Progression).
##
## One pull:
##   1. Tier: start COMMON and climb one tier at a time with
##      Rarity.UPGRADE_CHANCE (30 % / 30 % / 25 % / 20 %), so each tier is
##      rarer than the one below by a known factor.
##   2. Pity: after RARE_PITY − 1 pulls in a row below RARE the next is at
##      least RARE; after LEGENDARY_PITY − 1 without a LEGENDARY the next is
##      LEGENDARY.
##   3. Item: weighted pick (drop_weight) among the pool entries of that tier.
##      An empty tier cascades down to the next tier that has entries.
## COMMON parts are never dropped as items (they are fabricated at will);
## the COMMON tier pays out crates of spare parts instead.

const RARE_PITY := 10
const LEGENDARY_PITY := 80
## COMMON-tier payouts: [spare parts, weight].
const SPARES_CRATES := [[8, 60.0], [15, 30.0], [30, 10.0]]


## One pool entry or one drop.
class Drop:
	## &"equipment" (one unit), &"room" / &"hull" (a blueprint unlock) or
	## &"spares" (spare parts).
	var kind: StringName
	var def_id: StringName
	var rarity: int
	var weight: float = 1.0
	var display_name: String
	## Spare parts paid out (spares crates and duplicate unlocks).
	var amount: int = 0
	## A blueprint the player already had: converted to spare parts.
	var duplicate: bool = false

	func describe() -> String:
		match kind:
			&"spares":
				return "%d spare parts" % amount
			&"equipment":
				return "%s (1 unit)" % display_name
		var what := "%s blueprint" % display_name
		return "%s — duplicate, scrapped for %d spare parts" % [what, amount] if duplicate else what


## Every droppable entry: each non-COMMON definition, plus the spares crates.
static func build_pool(catalog: ConstructionCatalog) -> Array[Drop]:
	var pool: Array[Drop] = []
	for c in SPARES_CRATES:
		var d := Drop.new()
		d.kind = &"spares"
		d.def_id = &"spare_parts"
		d.rarity = Rarity.Tier.COMMON
		d.amount = c[0]
		d.weight = c[1]
		d.display_name = "Spare parts"
		pool.append(d)
	for entry in [[&"equipment", catalog.equipment], [&"room", catalog.rooms], [&"hull", catalog.hull]]:
		for id in ConstructionCatalog.sorted_ids(entry[1]):
			var def: Resource = entry[1][id]
			if def.rarity == Rarity.Tier.COMMON or def.drop_weight <= 0.0:
				continue
			var d := Drop.new()
			d.kind = entry[0]
			d.def_id = id
			d.rarity = def.rarity
			d.weight = def.drop_weight
			d.display_name = def.display_name
			pool.append(d)
	return pool


## Cascade roll for the tier, before pity.
static func roll_tier(rng: RandomNumberGenerator) -> int:
	var tier := 0
	while tier < Rarity.UPGRADE_CHANCE.size() and rng.randf() < Rarity.UPGRADE_CHANCE[tier]:
		tier += 1
	return tier


## Tier after pity, given the pull counters (pulls since the last RARE+ and
## since the last LEGENDARY).
static func apply_pity(tier: int, since_rare: int, since_legendary: int) -> int:
	if since_legendary + 1 >= LEGENDARY_PITY:
		return Rarity.Tier.LEGENDARY
	if since_rare + 1 >= RARE_PITY:
		return maxi(tier, Rarity.Tier.RARE)
	return tier


## Weighted pick within `tier`, cascading down past empty tiers. Null only
## if the pool is empty at and below `tier`.
static func pick(rng: RandomNumberGenerator, pool: Array[Drop], tier: int) -> Drop:
	for t in range(tier, -1, -1):
		var entries := pool.filter(func(d: Drop) -> bool: return d.rarity == t and d.weight > 0.0)
		if entries.is_empty():
			continue
		var total := 0.0
		for d in entries:
			total += d.weight
		var x := rng.randf() * total
		for d in entries:
			x -= d.weight
			if x < 0.0:
				return d
		return entries[-1]
	return null


## One full pull. `pity` is {"since_rare": int, "since_legendary": int} and is
## updated in place. Returns a fresh Drop (not the pool entry).
static func pull(rng: RandomNumberGenerator, pool: Array[Drop], pity: Dictionary) -> Drop:
	var since_rare: int = pity.get("since_rare", 0)
	var since_legendary: int = pity.get("since_legendary", 0)
	var tier := apply_pity(roll_tier(rng), since_rare, since_legendary)
	var entry := pick(rng, pool, tier)
	if entry == null:
		return null
	var d := Drop.new()
	d.kind = entry.kind
	d.def_id = entry.def_id
	d.rarity = entry.rarity
	d.weight = entry.weight
	d.display_name = entry.display_name
	d.amount = entry.amount
	pity["since_rare"] = 0 if d.rarity >= Rarity.Tier.RARE else since_rare + 1
	pity["since_legendary"] = 0 if d.rarity >= Rarity.Tier.LEGENDARY else since_legendary + 1
	return d


## Drop-rate disclosure for the loot panel: "C 70% · U 21% · …".
static func rates_text() -> String:
	var parts := PackedStringArray()
	var p := Rarity.tier_probabilities()
	for t in p.size():
		parts.append("%s %s%%" % [Rarity.name_of(t).left(1), String.num(p[t] * 100.0, 2)])
	return " · ".join(parts) + "  (pity: Rare+ every %d, Legendary every %d)" % [RARE_PITY, LEGENDARY_PITY]
