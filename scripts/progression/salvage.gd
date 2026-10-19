class_name Salvage
extends RefCounted
## Cashing in a beaten enemy (spec §15: "Salvage yields recoverable
## components and materials based on wreck condition and access"). Two ways:
##
## - BEACON (G on a disabled wreck within BEACON_RANGE_M): a beacon marks it
##   for Earth Shipyard's tug. Credits now: BEACON_SCRAP_RATE (50 %) of its
##   scrap value plus the bounty. Its crates (pulls_for) each hold loot with
##   BEACON_LOOT_CHANCE; what is found goes straight to the station bank.
## - TAKEOVER (boarders take its bridge): TAKEOVER_SCRAP_RATE (80 %) of the
##   scrap value plus double bounty; its stores (spare parts) and crates —
##   CAPTURE_BONUS_PULLS more, each with TAKEOVER_LOOT_CHANCE — go into our
##   cargo hold, at risk until banked and limited by its capacity.
##
## Scrap value = what is still intact, at the yard's price: Σ each system's
## and module's build cost (ServiceYard) × its condition, × CREDITS_PER_PART.
## A clean disabling shot pays better than shooting it to pieces:
##   spare parts in its stores = 10 + 50 × intact fraction
##   crates                    = 1 + ⌊4 × intact fraction⌋   (1–5)

const BEACON_RANGE_M := 2000.0
## A ship taken by boarders hands over its stores: extra crates.
const CAPTURE_BONUS_PULLS := 2
## Station bounty (credits, paid at once): base + per intact fraction; × 2
## for a captured ship.
const BOUNTY_BASE := 100
const BOUNTY_INTACT := 100
const BEACON_SCRAP_RATE := 0.5
const TAKEOVER_SCRAP_RATE := 0.8
## Chance that a crate holds loot (else it is empty).
const BEACON_LOOT_CHANCE := 0.4
const TAKEOVER_LOOT_CHANCE := 0.85
## Credits per spare part of build cost (the station sells 10 for 25).
const CREDITS_PER_PART := 2.5


## Why a beacon can't be dropped on `wreck` by `ship` ("" = it can).
static func block_reason(ship: ShipState, wreck: ShipState) -> String:
	if wreck == null or not wreck.is_active():
		return "no wreck"
	if wreck.systems == null or not wreck.systems.is_disabled():
		return "target still fighting — disable it first"
	if wreck.systems.captured:
		return "already taken by our boarders"
	var range_m := ship.position.distance_to(wreck.position)
	if range_m > BEACON_RANGE_M:
		return "close to < %.1f km to drop a beacon (now %.1f km)" % [BEACON_RANGE_M / 1000.0, range_m / 1000.0]
	return ""


static func spare_parts_for(wreck: ShipSystems) -> int:
	return roundi(10.0 + 50.0 * wreck.intact_fraction())


static func bounty_for(wreck: ShipSystems) -> int:
	return roundi(BOUNTY_BASE + BOUNTY_INTACT * wreck.intact_fraction()) * (2 if wreck.captured else 1)


static func pulls_for(wreck: ShipSystems) -> int:
	return clampi(1 + floori(4.0 * wreck.intact_fraction()), 1, 5) + (CAPTURE_BONUS_PULLS if wreck.captured else 0)


## Credits the intact remains are worth at the yard.
static func scrap_value(wreck: ShipSystems) -> int:
	var parts := 0.0
	for e in wreck.equipment:
		parts += ServiceYard.equipment_cost(e.def) * e.hp / maxf(e.max_hp, 1e-6)
	for i in wreck.modules.size():
		var def := wreck.grid.module_def(i)
		if def != null:
			parts += ServiceYard.module_cost(def) * wreck.modules[i].structure / maxf(wreck.modules[i].max_structure, 1e-6)
	return roundi(parts * CREDITS_PER_PART)


## What a completed scan reports (before its error): spare parts and crates
## aboard, scrap value and the bounty on it.
static func scan_estimate(wreck: ShipSystems) -> Dictionary:
	return {"parts": spare_parts_for(wreck), "crates": pulls_for(wreck), "scrap": scrap_value(wreck), "bounty": bounty_for(wreck)}
