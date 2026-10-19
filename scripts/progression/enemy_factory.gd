class_name EnemyFactory
extends RefCounted
## Enemy designs that get tougher mission by mission: the Frigate Mk I
## template with some of its parts swapped for rarer ones. Deterministic per
## mission number (same mission, same enemy), and always a valid design —
## if a variant fails validation, the plain template flies instead.
##
## Chances per swap rise with the mission number m:
##   gun        autocannon from m ≥ 2, railgun from m ≥ 4   (p = 0.15·m, ≤ 0.6)
##   hull       armoured fuselage sections from m ≥ 2        (p = 0.12·m, ≤ 0.5)
##   RCS        heavy RCS blocks from m ≥ 2                  (p = 0.1·m,  ≤ 0.5)
##   reactor    Mk II fusion reactor from m ≥ 3              (p = 0.08·m, ≤ 0.4)
## Mission 1 is always the plain template.

const CLASS_NAMES := ["Kestrel", "Harrier", "Shrike", "Goshawk", "Peregrine", "Merlin", "Hobby", "Saker"]


static func design(mission: int, template: ShipBlueprint, catalog: ConstructionCatalog) -> ShipBlueprint:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * mission + 17
	var bp := template.duplicate_blueprint()
	bp.name = "%s-class frigate" % CLASS_NAMES[(mission - 1) % CLASS_NAMES.size()]
	var m := float(mission)
	for e in bp.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def == null:
			continue
		match def.kind:
			EquipmentDefinition.Kind.CANNON:
				if mission >= 2 and rng.randf() < minf(0.15 * m, 0.6):
					e.def_id = &"railgun" if mission >= 4 and rng.randf() < 0.4 else &"autocannon"
			EquipmentDefinition.Kind.RCS:
				if mission >= 2 and rng.randf() < minf(0.1 * m, 0.5):
					e.def_id = &"rcs_block_heavy"
			EquipmentDefinition.Kind.REACTOR:
				if mission >= 3 and rng.randf() < minf(0.08 * m, 0.4):
					e.def_id = &"fusion_reactor_mk2"
	if mission >= 2:
		for mod in bp.modules:
			if mod.def_id == &"fuselage_section" and rng.randf() < minf(0.12 * m, 0.5):
				mod.def_id = &"armored_fuselage_section"
	if ShipValidator.validate(bp, catalog).has_errors():
		var plain := template.duplicate_blueprint()
		plain.name = bp.name
		return plain
	return bp


## The best intact rarer part fitted to a wreck (salvageable as a unit), or
## null: the highest rarity among systems with at least half their hit points.
static func recoverable_part(wreck: ShipSystems) -> ShipSystems.EquipmentState:
	var best: ShipSystems.EquipmentState
	for e in wreck.equipment:
		if e.def.rarity == Rarity.Tier.COMMON or e.hp < 0.5 * e.max_hp:
			continue
		if best == null or e.def.rarity > best.def.rarity:
			best = e
	return best
