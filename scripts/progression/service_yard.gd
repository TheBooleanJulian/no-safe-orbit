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
	EquipmentDefinition.Kind.POINT_DEFENCE: &"combat",
	EquipmentDefinition.Kind.RADIATOR: &"combat",
	EquipmentDefinition.Kind.MAIN_ENGINE: &"mobility",
	EquipmentDefinition.Kind.RCS: &"mobility",
	EquipmentDefinition.Kind.PROPELLANT_TANK: &"mobility",
	EquipmentDefinition.Kind.DOCKING_COLLAR: &"hull",
	EquipmentDefinition.Kind.GRAPPLE: &"hull",
	EquipmentDefinition.Kind.CRAFT_MOUNT: &"combat",
}


class Job:
	## &"repair", &"replace" (destroyed part), &"module", &"breach", &"hatch",
	## &"recruit" (one replacement crew member; subject = role name),
	## &"craft" (replace or repair the craft on rack `subject`),
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


## Resupply at launch, in credits: propellant per tonne, rounds per credit.
const PROPELLANT_CREDITS_PER_T := 1.0
const ROUNDS_PER_CREDIT := 10


## Propellant (kg) and rounds the vessel used last sortie, and what topping
## them up costs: {propellant_kg, rounds, credits}.
static func resupply_needs(vessel: ShipInstance, catalog: ConstructionCatalog) -> Dictionary:
	var stores: Dictionary = vessel.condition.get("stores", {})
	if stores.is_empty():
		return {"propellant_kg": 0.0, "rounds": 0, "credits": 0}
	var stats := ShipStats.compute(vessel.blueprint, ShipGrid.build(vessel.blueprint, catalog))
	var prop := maxf(stats.propellant_capacity_kg - float(stores.get("propellant_kg", stats.propellant_capacity_kg)), 0.0)
	var rounds := maxi(stats.rounds_capacity - int(stores.get("rounds", stats.rounds_capacity)), 0)
	return {"propellant_kg": prop, "rounds": rounds,
		"credits": ceili(prop / 1000.0 * PROPELLANT_CREDITS_PER_T - 1e-9) + ceili(float(rounds) / ROUNDS_PER_CREDIT - 1e-9)}


## Top up propellant (first) and rounds with what the credits allow. Returns
## what was bought ("" if nothing was needed).
static func resupply(vessel: ShipInstance, profile: PlayerProfile, catalog: ConstructionCatalog) -> String:
	var need := resupply_needs(vessel, catalog)
	if need.credits == 0:
		vessel.condition.erase("stores")
		return ""
	var stores: Dictionary = vessel.condition.stores
	if profile.credits >= int(need.credits):
		profile.credits -= int(need.credits)
		vessel.condition.erase("stores")
		var line := "Resupplied %.1f t propellant and %d rounds for %d credits" % [need.propellant_kg / 1000.0, need.rounds, need.credits]
		vessel.record(line)
		return line
	# Short of credits: as much propellant, then as many rounds, as they buy.
	var budget := float(profile.credits)
	var kg := minf(float(need.propellant_kg), budget / PROPELLANT_CREDITS_PER_T * 1000.0)
	budget -= ceilf(kg / 1000.0 * PROPELLANT_CREDITS_PER_T)
	var rounds := mini(int(need.rounds), int(maxf(budget, 0.0)) * ROUNDS_PER_CREDIT)
	budget -= ceilf(float(rounds) / ROUNDS_PER_CREDIT)
	profile.credits = maxi(int(budget), 0)
	stores["propellant_kg"] = float(stores.get("propellant_kg", 0.0)) + kg
	stores["rounds"] = int(stores.get("rounds", 0)) + rounds
	var line := "Partly resupplied (credits short): %.1f t propellant, %d rounds" % [kg / 1000.0, rounds]
	vessel.record(line)
	return line


## Power bus conduit: a part per BUS_CELLS_PER_PART cells.
const BUS_CELLS_PER_PART := 2


static func bus_cost(cells: int) -> int:
	return ceili(float(cells) / BUS_CELLS_PER_PART) if cells > 0 else 0


## An armour plate: a part per tonne.
static func plate_cost(mm: float) -> int:
	return maxi(ceili(ShipStats.plate_mass(mm) / 1000.0), 1)


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
	# Worn armour plates: one job for all of them.
	var worn: Dictionary = vessel.condition.get("plates", {})
	if not worn.is_empty():
		var cost := 0.0
		for key in worn:
			cost += plate_cost(float(bp.armor.get(key, 0.0))) * (1.0 - clampf(float(worn[key]), 0.0, 1.0))
		var j := Job.new()
		j.kind = &"plates"
		j.subject = "plates"
		j.cost = maxi(ceili(cost - 1e-9), 1)
		j.label = "Re-plate %d worn armour plate%s" % [worn.size(), "" if worn.size() == 1 else "s"]
		j.order = 1.5
		jobs.append(j)
	var cuts: Array = vessel.condition.get("bus_cut", [])
	if not cuts.is_empty():
		var j := Job.new()
		j.kind = &"bus"
		j.subject = "bus"
		j.category = &"combat"
		j.cost = bus_cost(cuts.size())
		j.label = "Re-run %d cut power conduit%s" % [cuts.size(), "" if cuts.size() == 1 else "s"]
		j.order = 0.5
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
	for rack_id in vessel.wing:
		var placed: Variant = bp.find(str(rack_id))
		var def: EquipmentDefinition = catalog.equipment.get(placed.def_id) if placed != null else null
		if def == null or def.craft == null:
			continue
		var entry: Dictionary = vessel.wing[rack_id]
		var full := maxi(ceili(def.craft.mass_kg / 1000.0), 1)
		var j := Job.new()
		j.kind = &"craft"
		j.subject = str(rack_id)
		j.category = &"combat"
		j.order = 8.0
		if entry.get("lost", false):
			j.cost = full
			j.label = "Replace lost %s (rack %s)" % [def.craft.display_name, rack_id]
		else:
			j.cost = maxi(damaged_cost(full, 1.0 - float(entry.get("hull", 1.0))), 1)
			j.label = "Repair %s (rack %s, %d%%)" % [def.craft.display_name, rack_id, roundi(float(entry.get("hull", 1.0)) * 100.0)]
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
	# New or thicker armour plates: one job for all of them.
	var plates := 0
	var plate_parts := 0
	for key in new_bp.armor:
		if int(old.armor.get(key, 0)) < int(new_bp.armor[key]):
			plates += 1
			plate_parts += plate_cost(float(new_bp.armor[key]))
	if plates > 0:
		var j := _build("plates", "armour plating", plate_parts, &"")
		j.label = "Fit %d armour plate%s" % [plates, "" if plates == 1 else "s"]
		jobs.append(j)
	var new_bus := 0
	for key in new_bp.bus:
		if not old.bus.has(key):
			new_bus += 1
	if new_bus > 0:
		var jb := _build("bus", "power bus", bus_cost(new_bus), &"")
		jb.label = "Run %d power conduit cell%s" % [new_bus, "" if new_bus == 1 else "s"]
		jobs.append(jb)
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
			&"plates":
				c.erase("plates")
			&"bus":
				c.erase("bus_cut")
			&"breach":
				(c.get("breached", []) as Array).erase(j.subject)
			&"hatch":
				(c.get("hatches", []) as Array).erase(j.subject)
			&"craft":
				vessel.wing.erase(j.subject)
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
	c["bus_cut"] = (c.get("bus_cut", []) as Array).filter(func(k: Variant) -> bool: return new_bp.bus.has(str(k)))
	if (c.bus_cut as Array).is_empty():
		c.erase("bus_cut")
	var worn: Dictionary = c.get("plates", {})
	for key in worn.keys():
		if int(new_bp.armor.get(key, 0)) != int(vessel.blueprint.armor.get(key, 0)):
			worn.erase(key)  # removed, or a new plate fitted there
	if worn.is_empty():
		c.erase("plates")
	c["breached"] = (c.get("breached", []) as Array).filter(func(id: Variant) -> bool: return keep.has(str(id)))
	c["hatches"] = (c.get("hatches", []) as Array).filter(func(id: Variant) -> bool: return new_bp.find(str(id)) != null)
	if not jobs.is_empty():
		vessel.record("Refitted to %s: %d new parts (%d spare parts)" % [new_bp.name, jobs.size(), cost])
	vessel.blueprint = new_bp.duplicate_blueprint()
	vessel.name = new_bp.name
	return ""
