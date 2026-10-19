class_name ServiceYard
extends RefCounted
## Repairs and refits at the shipyard (spec §15), paid in spare parts.
##
## Costs (docs/ARCHITECTURE.md → Progression):
## - Building a part new: equipment 1 part per tonne; a hull module 1 per
##   4 t of structure; a room 1 per 2 t. Rarer equipment comes from the
##   player's own units, so fitting one costs a quarter (labour).
## - Repairing a part costs its new-build cost × the fraction it is damaged,
##   so removing a damaged part and fitting a new one never beats repairing.
## - A destroyed part is rebuilt at full cost; a destroyed rarer unit needs
##   another owned unit to replace it.
## - A refit (launching an edited design) builds every part the vessel does
##   not have yet and must be paid in full. Repairs are optional: unrepaired
##   parts fly as they are, chosen by priority when parts are short.

enum Priority { FULL, COMBAT, MOBILITY, HULL }

const PRIORITY_NAMES := ["Full restoration", "Combat readiness", "Mobility", "Hull integrity"]
const RARE_FIT_FACTOR := 0.25
const BREACH_PATCH_COST := 2
const HATCH_COST := 1
## Recruiting and training one replacement crew member.
const RECRUIT_COST := 2
## Category order per priority.
const ORDER := {
	Priority.FULL: [&"combat", &"mobility", &"crew", &"hull"],
	Priority.COMBAT: [&"combat", &"crew", &"hull", &"mobility"],
	Priority.MOBILITY: [&"mobility", &"hull", &"crew", &"combat"],
	Priority.HULL: [&"hull", &"crew", &"combat", &"mobility"],
}
const CATEGORY := {
	EquipmentDefinition.Kind.REACTOR: &"combat",
	EquipmentDefinition.Kind.CANNON: &"combat",
	EquipmentDefinition.Kind.RADIATOR: &"combat",
	EquipmentDefinition.Kind.MAIN_ENGINE: &"mobility",
	EquipmentDefinition.Kind.RCS: &"mobility",
	EquipmentDefinition.Kind.PROPELLANT_TANK: &"mobility",
	EquipmentDefinition.Kind.DOCKING_COLLAR: &"hull",
}


class Job:
	## &"repair", &"replace" (destroyed part), &"module", &"breach", &"hatch",
	## &"recruit" (one replacement crew member; subject = role name),
	## &"build" (refit: a part the vessel does not have yet).
	var kind: StringName
	var subject: String
	var label: String
	var cost: int
	var category: StringName = &"hull"
	## Rarer equipment that needs an owned unit to replace or fit.
	var needs_unit: StringName = &""
	var order: float = 0.0


# --- Costs ---------------------------------------------------------------------

static func equipment_cost(def: EquipmentDefinition) -> int:
	var factor := RARE_FIT_FACTOR if def.rarity != Rarity.Tier.COMMON else 1.0
	return maxi(ceili(def.mass_kg / 1000.0 * factor), 1)


static func module_cost(def: HullModuleDefinition) -> int:
	return maxi(ceili(def.structure_mass_kg / 4000.0), 1)


static func room_cost(def: RoomDefinition, cells: int) -> int:
	return maxi(ceili(def.mass_per_cell_kg * cells / 2000.0), 1)


static func damaged_cost(full: int, damage: float) -> int:
	return clampi(ceili(full * clampf(damage, 0.0, 1.0) - 1e-9), 0, full)


# --- Jobs ------------------------------------------------------------------------

## Every repair the vessel's condition calls for.
static func repair_jobs(vessel: ShipInstance, catalog: ConstructionCatalog) -> Array[Job]:
	var jobs: Array[Job] = []
	var bp := vessel.blueprint
	var eq: Dictionary = vessel.condition.get("equipment", {})
	for e in bp.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def == null or not eq.has(e.id):
			continue
		var frac := clampf(float(eq[e.id]), 0.0, 1.0)
		var j := Job.new()
		j.subject = e.id
		j.category = CATEGORY.get(def.kind, &"combat")
		j.order = ShipSystems.FIELD_REPAIR_ORDER.get(def.kind, 9) + frac
		if frac <= 0.0:
			j.kind = &"replace"
			j.cost = equipment_cost(def)
			j.label = "Replace %s %s (destroyed)" % [def.display_name, e.id]
		else:
			j.kind = &"repair"
			j.cost = damaged_cost(equipment_cost(def), 1.0 - frac)
			j.label = "Repair %s %s (%d%%)" % [def.display_name, e.id, roundi(frac * 100.0)]
		jobs.append(j)
	var mods: Dictionary = vessel.condition.get("modules", {})
	for m in bp.modules:
		var def: HullModuleDefinition = catalog.hull.get(m.def_id)
		if def == null or not mods.has(m.id):
			continue
		var entry: Dictionary = mods[m.id]
		var structure := clampf(float(entry.get("structure", 1.0)), 0.0, 1.0)
		var armor := clampf(float(entry.get("armor", 1.0)), 0.0, 1.0)
		var j := Job.new()
		j.kind = &"module"
		j.subject = m.id
		# Armour is half the module's value, structure the other half.
		j.cost = maxi(damaged_cost(module_cost(def), 0.5 * (1.0 - structure) + 0.5 * (1.0 - armor)), 1)
		j.label = "Rebuild %s %s (structure %d%%, armour %d%%)" % [def.display_name, m.id, roundi(structure * 100.0), roundi(armor * 100.0)]
		j.order = structure
		jobs.append(j)
	for id in vessel.condition.get("breached", []):
		var j := Job.new()
		j.kind = &"breach"
		j.subject = str(id)
		j.cost = BREACH_PATCH_COST
		j.label = "Patch breach in %s" % id
		j.order = 2.0
		jobs.append(j)
	for id in vessel.condition.get("hatches", []):
		var j := Job.new()
		j.kind = &"hatch"
		j.subject = str(id)
		j.cost = HATCH_COST
		j.label = "Replace hatch %s" % id
		j.order = 3.0
		jobs.append(j)
	var dead := vessel.dead_crew()
	for role_name in dead:
		for k in int(dead[role_name]):
			var j := Job.new()
			j.kind = &"recruit"
			j.subject = str(role_name)
			j.cost = RECRUIT_COST
			j.category = &"crew"
			j.label = "Recruit a %s crew member" % role_name
			j.order = CrewRoster.ROLE_NAMES.find(str(role_name))
			jobs.append(j)
	return jobs


## Parts of `new_bp` the vessel does not have (new ids, or an id now holding
## a different part): all must be built before launch.
static func refit_jobs(vessel: ShipInstance, new_bp: ShipBlueprint, catalog: ConstructionCatalog) -> Array[Job]:
	var jobs: Array[Job] = []
	var old := vessel.blueprint
	for m in new_bp.modules:
		var was: Variant = old.find(m.id)
		var def: HullModuleDefinition = catalog.hull.get(m.def_id)
		if def != null and (was == null or not was is ShipBlueprint.PlacedModule or was.def_id != m.def_id):
			jobs.append(_build(m.id, def.display_name, module_cost(def), &""))
	for r in new_bp.rooms:
		var was: Variant = old.find(r.id)
		var def: RoomDefinition = catalog.rooms.get(r.def_id)
		if def != null and (was == null or not was is ShipBlueprint.PlacedRoom or was.def_id != r.def_id):
			jobs.append(_build(r.id, def.display_name, room_cost(def, r.rect.size.x * r.rect.size.y), &""))
	for e in new_bp.equipment:
		var was: Variant = old.find(e.id)
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def != null and (was == null or not was is ShipBlueprint.PlacedEquipment or was.def_id != e.def_id):
			jobs.append(_build(e.id, def.display_name, equipment_cost(def), e.def_id if def.rarity != Rarity.Tier.COMMON else &""))
	return jobs


static func _build(id: String, what: String, cost: int, unit: StringName) -> Job:
	var j := Job.new()
	j.kind = &"build"
	j.subject = id
	j.cost = cost
	j.label = "Build %s %s" % [what, id]
	j.needs_unit = unit
	return j


static func total_cost(jobs: Array[Job]) -> int:
	var n := 0
	for j in jobs:
		n += j.cost
	return n


## Jobs that can be done now. A destroyed rarer part is rebuilt from its
## wreckage at its fitting cost (it is not written off), so every repair is
## available; the hook stays for rules that need stock.
static func available(_job: Job, _vessel: ShipInstance, _profile: PlayerProfile) -> bool:
	return true


## Repairs chosen by priority within `budget`: categories in the priority's
## order, most important first within each; anything unaffordable is
## skipped so cheaper jobs further down still get done.
static func plan(jobs: Array[Job], priority: Priority, budget: int, vessel: ShipInstance = null, profile: PlayerProfile = null) -> Array[Job]:
	var order: Array = ORDER[priority]
	var sorted := jobs.duplicate()
	sorted.sort_custom(func(a: Job, b: Job) -> bool:
		var ca := order.find(a.category)
		var cb := order.find(b.category)
		return ca < cb if ca != cb else a.order < b.order)
	var chosen: Array[Job] = []
	var left := budget
	for j: Job in sorted:
		if j.cost > left:
			continue
		if vessel != null and profile != null and not available(j, vessel, profile):
			continue
		chosen.append(j)
		left -= j.cost
	return chosen


## Do the jobs: pay and restore the vessel's condition. Returns parts spent.
static func perform(jobs: Array[Job], vessel: ShipInstance, profile: PlayerProfile) -> int:
	var spent := 0
	var c := vessel.condition
	for j in jobs:
		if j.cost > profile.spare_parts:
			continue
		profile.spare_parts -= j.cost
		spent += j.cost
		match j.kind:
			&"repair", &"replace":
				(c.get("equipment", {}) as Dictionary).erase(j.subject)
			&"module":
				(c.get("modules", {}) as Dictionary).erase(j.subject)
			&"breach":
				(c.get("breached", []) as Array).erase(j.subject)
			&"hatch":
				(c.get("hatches", []) as Array).erase(j.subject)
			&"recruit":
				var dead: Dictionary = c.get("crew", {}).get("dead", {})
				dead[j.subject] = int(dead.get(j.subject, 0)) - 1
				if dead[j.subject] <= 0:
					dead.erase(j.subject)
				if dead.is_empty() and c.has("crew"):
					(c.crew as Dictionary).erase("dead")
					if (c.crew as Dictionary).is_empty():
						c.erase("crew")
		vessel.record("%s (%d parts)" % [j.label, j.cost])
	return spent


## Refit the vessel to `new_bp`: pay for every new part, then adopt the
## design. Parts it no longer has drop out of its condition. Returns ""
## on success, or why it cannot be done.
static func refit(vessel: ShipInstance, new_bp: ShipBlueprint, profile: PlayerProfile, catalog: ConstructionCatalog) -> String:
	var jobs := refit_jobs(vessel, new_bp, catalog)
	var cost := total_cost(jobs)
	if cost > profile.spare_parts:
		return "Refit needs %d spare parts; you have %d" % [cost, profile.spare_parts]
	profile.spare_parts -= cost
	var keep := {}
	for list in [new_bp.modules, new_bp.rooms, new_bp.equipment]:
		for item in list:
			keep[item.id] = true
	for j in jobs:
		keep.erase(j.subject)  # built new: like new
	var c := vessel.condition
	for key in ["equipment", "modules"]:
		var table: Dictionary = c.get(key, {})
		for id in table.keys():
			if not keep.has(id):
				table.erase(id)
	c["breached"] = (c.get("breached", []) as Array).filter(func(id: Variant) -> bool: return keep.has(str(id)))
	c["hatches"] = (c.get("hatches", []) as Array).filter(func(id: Variant) -> bool: return new_bp.find(str(id)) != null)
	if not jobs.is_empty():
		vessel.record("Refitted to %s: %d new parts (%d spare parts)" % [new_bp.name, jobs.size(), cost])
	vessel.blueprint = new_bp.duplicate_blueprint()
	vessel.name = new_bp.name
	return ""
