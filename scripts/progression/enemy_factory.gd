class_name EnemyFactory
extends RefCounted
## Enemy designs that get tougher mission by mission: the Frigate Mk I
## template with some of its parts swapped for rarer ones. Deterministic per
## mission number (same mission, same enemy), and always a valid design —
## if a variant fails validation, the plain template flies instead.
##
## Chances per swap rise with the mission number m:
##   gun        heavy kinetic cannon from m ≥ 2 (the template's guns are
##              autocannons), railgun from m ≥ 4           (p = 0.15·m, ≤ 0.6)
##   armour     plates on exposed faces from m ≥ 2           (p = 0.06·m, ≤ 0.4 per face;
##              80 mm instead of 40 from m ≥ 4, 1 in 3)
##   RCS        heavy RCS blocks from m ≥ 2                  (p = 0.1·m,  ≤ 0.5)
##   reactor    Mk II fusion reactor from m ≥ 3              (p = 0.08·m, ≤ 0.4)
##   missiles   a missile rack from m ≥ 4 (always); an EMP launcher too from
##              m ≥ 6 (p = 0.5) — each on a free exterior face, dropped again
##              if it makes the design invalid
## Mission 1 is always the plain template.

const MISSILE_RACK_FROM_MISSION := 4
const EMP_LAUNCHER_FROM_MISSION := 6
## Countermeasures (Milestone 11): flares from mission 3, a jammer on some
## ships from mission 6.
const FLARES_FROM_MISSION := 3
const JAMMER_FROM_MISSION := 6

const CLASS_NAMES := ["Kestrel", "Harrier", "Shrike", "Goshawk", "Peregrine", "Merlin", "Hobby", "Saker"]


## Ships per encounter: what the player picked on the shipyard map
## (PlayerProfile.encounter_size), within 1–PlayerProfile.MAX_ENCOUNTER.
static func encounter_size(chosen: int) -> int:
	return clampi(chosen, 1, PlayerProfile.MAX_ENCOUNTER)


## An enemy ship's policy (ShipPolicy): the Standard preset with a role by
## its place in the encounter (closer, standoff, flanker, …), focus fire,
## and missile salvos of a few missiles inside its role's reach.
const LEAD_FIRE_RATE := 0.7
const WINGMAN_FIRE_RATE := 0.45


static func policy(mission: int, index: int) -> ShipPolicy:
	var p := ShipPolicy.preset("Standard")
	p.preset_name = "Enemy"
	p.role = (index % ShipPolicy.Role.size()) as ShipPolicy.Role
	p.focus_fire = true
	p.autofire_tolerance_deg = GunneryAI.FIRE_CONE_DEG
	p.salvo_enabled = true
	p.salvo_mode = MissileSalvo.Mode.ALL
	p.salvo_count = 4 if p.role == ShipPolicy.Role.STANDOFF else (3 if mission >= 6 else 2)
	p.salvo_min_confidence = 0.5
	p.salvo_min_range_m = 1500.0
	p.salvo_max_range_m = 15000.0 if p.role == ShipPolicy.Role.STANDOFF else 12000.0
	p.salvo_interval_s = 25.0
	p.cm_auto = true
	p.cm_lead_s = 3.5
	# Their guns are automation too: the lead at 70 % of the rated rate, the
	# wingmen at 45 % (play-test batch 6: more than one ship was too much).
	p.autofire_rate = LEAD_FIRE_RATE if index == 0 else WINGMAN_FIRE_RATE
	return p


## The mission a ship is fitted as: the lead at the mission's level, the
## wingmen as for earlier missions (the second two back, the third three) —
## play-test batch 6: every ship of a 1v3 carried the lead's full kit.
static func kit_mission(mission: int, variant: int) -> int:
	return mission if variant <= 0 else maxi(mission - 1 - variant, 1)


## `variant` > 0: another ship of the same mission's encounter (its own
## rolls, fitted as for an earlier mission, kit_mission); variant 0 is the
## mission's lead ship as before.
static func design(mission: int, template: ShipBlueprint, catalog: ConstructionCatalog, variant: int = 0) -> ShipBlueprint:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * mission + 17 + 104_729 * variant
	var bp := template.duplicate_blueprint()
	bp.name = "%s-class %s" % [CLASS_NAMES[(mission - 1 + variant) % CLASS_NAMES.size()], template.name.split(" ")[0].to_lower()]
	mission = kit_mission(mission, variant)
	var m := float(mission)
	for e in bp.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def == null:
			continue
		match def.kind:
			EquipmentDefinition.Kind.CANNON:
				if mission >= 2 and rng.randf() < minf(0.15 * m, 0.6):
					e.def_id = &"railgun" if mission >= 4 and rng.randf() < 0.4 else &"kinetic_cannon"
			EquipmentDefinition.Kind.RCS:
				if mission >= 2 and rng.randf() < minf(0.1 * m, 0.5):
					e.def_id = &"rcs_block_heavy"
			EquipmentDefinition.Kind.REACTOR:
				if mission >= 3 and rng.randf() < minf(0.08 * m, 0.4):
					e.def_id = &"fusion_reactor_mk2"
			EquipmentDefinition.Kind.CRAFT_MOUNT:
				# Fighter variety: interceptors in place of the recon drone
				# from mission 5, bombers in the bay from mission 7.
				if e.def_id == &"drone_rack" and mission >= 5 and rng.randf() < 0.5:
					e.def_id = &"interceptor_rack"
				elif e.def_id == &"fighter_bay" and mission >= 7 and rng.randf() < 0.5:
					e.def_id = &"bomber_bay"
	if mission >= MISSILE_RACK_FROM_MISSION:
		_fit_launcher(bp, catalog, &"missile_rack", rng)
	if mission >= EMP_LAUNCHER_FROM_MISSION and rng.randf() < 0.5:
		_fit_launcher(bp, catalog, &"emp_launcher", rng)
	if mission >= FLARES_FROM_MISSION:
		_fit_launcher(bp, catalog, &"flare_launcher", rng)
	if mission >= JAMMER_FROM_MISSION and rng.randf() < 0.4:
		_fit_launcher(bp, catalog, &"jammer", rng)
	if mission >= 2:
		var grid := ShipGrid.build(bp, catalog)
		var cells: Array = grid.module_at.keys()
		cells.sort()
		for cell: Vector3i in cells:
			for face in grid.plateable_faces(cell):
				if rng.randf() < minf(0.06 * m, 0.4):
					var thick := mission >= 4 and rng.randf() < 1.0 / 3.0
					bp.armor[ShipBlueprint.plate_key(cell, face)] = ShipBlueprint.PLATE_THICK_MM if thick else ShipBlueprint.PLATE_THIN_MM
	if ShipValidator.validate(bp, catalog).has_errors():
		var plain := template.duplicate_blueprint()
		plain.name = bp.name
		return plain
	return bp


## Mount a launcher on a free exterior face it allows (top faces first, then
## the flanks), on the power bus if the design has one; taken off again if
## the design no longer validates.
static func _fit_launcher(bp: ShipBlueprint, catalog: ConstructionCatalog, def_id: StringName, rng: RandomNumberGenerator) -> void:
	var def: EquipmentDefinition = catalog.equipment.get(def_id)
	if def == null:
		return
	var grid := ShipGrid.build(bp, catalog)
	var taken := {}
	for j in bp.equipment.size():
		var other := grid.equipment_def(j)
		if other != null and other.is_external():
			for c in grid.external_cells(j):
				taken["%s|%s" % [c, bp.equipment[j].face]] = true
	var cells: Array = grid.module_at.keys()
	cells.sort()
	for face: StringName in [&"dorsal", &"port", &"starboard", &"ventral", &"fore"]:
		if not def.allowed_faces.has(face):
			continue
		var spots: Array[Vector3i] = []
		for cell: Vector3i in cells:
			if grid.is_exterior_face(cell, face) and not grid.slope_faces(cell).has(face) and not taken.has("%s|%s" % [cell, face]) 					and (bp.bus.is_empty() or bp.bus.has(ShipBlueprint.cell_key(cell))):
				spots.append(cell)
		if spots.is_empty():
			continue
		var e := bp.add_equipment(def_id, spots[rng.randi_range(0, spots.size() - 1)], face, 0)
		if ShipValidator.validate(bp, catalog).has_errors():
			bp.remove(e.id)
			continue
		return


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
