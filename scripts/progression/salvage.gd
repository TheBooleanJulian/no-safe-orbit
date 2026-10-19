class_name Salvage
extends RefCounted
## Salvaging a disabled enemy (spec §15: "Salvage yields recoverable
## components and materials based on wreck condition and access"; recovery
## requires proximity). Close in, match velocity, press G.
##
## Yield scales with how much of the wreck's systems survived, so a clean
## disabling shot pays better than shooting it to pieces:
##   spare parts = 10 + 50 × intact fraction
##   loot pulls  = 1 + ⌊4 × intact fraction⌋   (1–5)

const MAX_RANGE_M := 500.0
const MAX_RELATIVE_SPEED_MPS := 5.0
## A ship taken by boarders hands over its stores: extra crates.
const CAPTURE_BONUS_PULLS := 2
## Station bounty (credits, paid at once): base + per intact fraction; × 2
## for a captured ship.
const BOUNTY_BASE := 100
const BOUNTY_INTACT := 100


## Why `wreck` cannot be salvaged by `ship` right now ("" = it can).
static func block_reason(ship: ShipState, wreck: ShipState) -> String:
	if wreck == null or not wreck.is_active():
		return "no wreck"
	if wreck.systems == null or not wreck.systems.is_disabled():
		return "target still fighting — disable it first"
	var range_m := ship.position.distance_to(wreck.position)
	if range_m > MAX_RANGE_M:
		return "close to < %.0f m (now %.0f m)" % [MAX_RANGE_M, range_m]
	var rel := ship.velocity.distance_to(wreck.velocity)
	if rel > MAX_RELATIVE_SPEED_MPS:
		return "match velocity to < %.0f m/s (now %.1f m/s)" % [MAX_RELATIVE_SPEED_MPS, rel]
	return ""


static func spare_parts_for(wreck: ShipSystems) -> int:
	return roundi(10.0 + 50.0 * wreck.intact_fraction())


static func bounty_for(wreck: ShipSystems) -> int:
	return roundi(BOUNTY_BASE + BOUNTY_INTACT * wreck.intact_fraction()) * (2 if wreck.captured else 1)


## What a completed scan reports (before its error): spare parts and crates
## the wreck would yield now, and the bounty on it.
static func scan_estimate(wreck: ShipSystems) -> Dictionary:
	return {"parts": spare_parts_for(wreck), "crates": pulls_for(wreck), "bounty": bounty_for(wreck)}


static func pulls_for(wreck: ShipSystems) -> int:
	return clampi(1 + floori(4.0 * wreck.intact_fraction()), 1, 5) + (CAPTURE_BONUS_PULLS if wreck.captured else 0)
