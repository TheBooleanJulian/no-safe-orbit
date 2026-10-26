extends SceneTree
## Builds the prebuilt roster (2026-10-26) — the nine hulls the dealer sells,
## the frigate every new captain starts in and the traffic each station's
## encounters are built on — and writes each to data/blueprints/ only when it
## validates clean (no errors, no warnings) and passes the roster's own
## checks below. Replaces the batch-6/10 capital generator, whose hulls were
## one stepped slab at nine sizes.
##
## One industrial family, in a brutalist military idiom (after the
## principles of the UNSC ships of the Halo games, not their shapes): long
## axial slabs built round their main guns, flat armoured bows with the
## spinal gun's muzzle in them, chamfered edges, stepped armour, boxy engine
## blocks wider than the hull ahead of them, low command spaces. Every hull
## is drawn in the same vocabulary:
## - 3 m cells; pressurised hull in 2 × 2 blocks paired outwards from the
##   centreline (1 × 1 where a pair won't fit), open structure in truss;
## - skirts: sloped wedge armour along the top and bottom edges of a slab
##   (a chamfered, hexagonal section — and spaced, angled armour to a round);
## - a chisel prow ahead of every exposed front (long wedges for a sharp
##   one), except where a flat face carries something (a gun's muzzle, a
##   truck's cab);
## - parts at their tier's size (light 1, medium 2, large 3 cells across,
##   standing that far out) with that space clear; landing legs (1 × 1 × 2)
##   under every hull, three or more on its keel;
## - a keel corridor down the main deck with the rooms either side, hatches
##   at the frames, ladders between decks, no hatch blocked by machinery;
## - engineering aft: reactor room, then engine rooms with the tanks, main
##   engines on the aft face around the centre of mass, RCS at the
##   extremities (more lever arm, not more blocks, turns a long hull);
## - radiators where the armour isn't: fins off trusses and engine blocks,
##   or flat in the waists between armoured sections;
## - guns on the dorsal and ventral centreline with their arcs clear,
##   launchers and point defence where nothing stands within three cells of
##   their face; armour where a fight comes from (bow and flanks) unless the
##   class says otherwise;
## - power and coolant auto-routed from the distribution units and the
##   reactors (ShipEditor), with extra trunks on the ships meant to survive
##   a cut.
## Rarer parts come with a bought hull (ServiceYard.dealer_price prices them,
## PlayerProfile.buy_ship banks them and unlocks its rarer rooms); the
## frigate is the starting ship, so it carries only what a new captain is
## given (PlayerProfile.ensure_vessel).
##   godot --headless --path . -s res://tools/make_roster.gd [-- <id>…]

const ROSTER := [
	["cutter_mk1", "_interceptor"],
	["corvette_mk1", "_missile_corvette"],
	["frigate_mk1", "_escort_frigate"],
	["destroyer_mk1", "_gun_destroyer"],
	["cruiser_mk1", "_heavy_cruiser"],
	["battleship_mk1", "_battleship"],
	["carrier_mk1", "_fleet_carrier"],
	["scout_mk1", "_scout"],
	["freighter_mk1", "_heavy_freighter"],
]

var cat: ConstructionCatalog


func _initialize() -> void:
	cat = ConstructionCatalog.default_catalog()
	var only := OS.get_cmdline_user_args()
	for spec: Array in ROSTER:
		if not only.is_empty() and not only.has(spec[0]):
			continue
		var draft: Draft = call(spec[1])
		var bp := draft.finish()
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		var report := ShipValidator.validate(bp, cat, grid, stats)
		var problems := draft.problems.duplicate()
		problems.append_array(_roster_checks(draft, bp, grid, stats))
		_describe(spec[0], bp, grid, stats)
		var seen := {}
		for issue in report.issues:
			if not seen.has(issue.code):
				print("   %s %s" % [issue.code, issue.message.left(300)])
			seen[issue.code] = int(seen.get(issue.code, 0)) + 1
		for p in problems:
			print("   roster: %s" % p)
		if report.issues.is_empty() and problems.is_empty():
			var path := "%s/%s.json" % [BlueprintIO.TEMPLATE_DIR, spec[0]]
			print("   wrote %s (%s)" % [path, error_string(BlueprintIO.save(bp, path))])
		else:
			print("   NOT WRITTEN (%d validator issues %s, %d roster problems)" % [report.issues.size(), seen, problems.size()])
	quit()


## One line of numbers per hull, for the log and the docs.
func _describe(id: String, bp: ShipBlueprint, grid: ShipGrid, s: ShipStats) -> void:
	var b := grid.cell_bounds()
	var cfg := s.to_ship_config(bp.name)
	var price := ServiceYard.dealer_price(bp, cat, grid, s)
	var pd := PdCoverage.of(grid)
	print("%s — %s (%s)" % [id, bp.name, bp.designer])
	print("   %.0f × %.0f × %.0f m · %d modules · %.0f t dry, %.0f t propellant · %.2f g · Δv %.0f m/s (Isp %.0f s) · turn %.2f/%.2f/%.2f rad/s" % [
		b.size.x * 3.0, b.size.y * 3.0, b.size.z * 3.0, bp.modules.size(), s.mass_kg / 1000.0, s.propellant_capacity_kg / 1000.0,
		s.thrust_forward_n / s.mass_kg / ShipDynamics.G0, s.delta_v_m_s(), s.main_isp_s,
		cfg.assist_max_rate_rad_s.x, cfg.assist_max_rate_rad_s.y, cfg.assist_max_rate_rad_s.z])
	print("   power %.0f / %.0f kW · heat %.0f / %.0f kW · berths %d, crew %d %s · rounds %d, PD %d · cargo %.0f m³ · PD %d/%d (%d %%) · %d cr (rarer parts %d)" % [
		s.power_generation_kw, s.power_draw_kw, s.heat_generation_kw, s.heat_rejection_kw, s.crew_capacity, int(price.crew_count),
		CrewRoster.complement_for(bp, grid, s), s.rounds_capacity, s.pd_rounds_capacity, s.cargo_m3, int(pd.mounts), int(pd.recommended),
		roundi(float(pd.coverage) * 100.0), int(price.total), int(price.units)])
	var kit := {}
	for e in bp.equipment:
		kit[e.def_id] = int(kit.get(e.def_id, 0)) + 1
	print("   kit %s" % kit)


## What the validator doesn't ask but the roster promises.
func _roster_checks(draft: Draft, bp: ShipBlueprint, grid: ShipGrid, s: ShipStats) -> PackedStringArray:
	var out := PackedStringArray()
	var K := EquipmentDefinition.Kind
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		var e := bp.equipment[i]
		if def == null:
			continue
		# Weapons, launchers, sensors and engine plumes: three clear cells off
		# the face (more for a bigger part) across its whole patch.
		if def.is_external() and def.kind in [K.CANNON, K.POINT_DEFENCE, K.MISSILE_LAUNCHER, K.MAIN_ENGINE, K.SENSOR, K.DECOY_LAUNCHER]:
			var n: Vector3i = ShipGrid.FACE_NORMALS[e.face]
			var blocked := false
			for c in grid.external_cells(i):
				for k in range(1, maxi(def.size_cells, 3) + 1):
					if not blocked and grid.is_hull(c + n * k):
						out.append("%s %s: hull %d cell%s off its %s face" % [def.display_name, e.id, k, "" if k == 1 else "s", e.face])
						blocked = true
	# No hatch blocked by machinery.
	for h in bp.hatches:
		for c: Vector3i in [h.a, h.b]:
			if grid.equipment_at.has(c):
				out.append("hatch %s: %s stands in it at %s" % [h.id, bp.equipment[grid.equipment_at[c]].id, c])
	# Rarer rooms and hull only where the dealer sells it (the starter can't have them).
	if draft.starter:
		for r in bp.rooms:
			if (cat.rooms[r.def_id] as RoomDefinition).rarity != Rarity.Tier.COMMON:
				out.append("the starting ship has a rarer room: %s" % r.def_id)
	if not draft.pd_exempt:
		var pd := PdCoverage.of(grid)
		if int(pd.mounts) < int(pd.recommended):
			out.append("PD: %d mounts, the hull wants %d" % [pd.mounts, pd.recommended])
	return out


# --- The vocabulary ---------------------------------------------------------------

class Draft:
	var cat: ConstructionCatalog
	var bp := ShipBlueprint.new()
	## Hull cells: Vector3i -> true (pressurised block) or false (open truss).
	var cells := {}
	## Wedge cells: Vector3i -> [def id, rotation, flip].
	var wedges := {}
	## Twice the centreline's x: columns x and mid2 − x mirror each other.
	var mid2 := 0
	## External faces in use: "cell|face" -> true.
	var taken := {}
	## Cells internal equipment stands in.
	var inside := {}
	## Power conduit laid after auto-routing: second trunks and cross-ties.
	var trunks: Array[Vector3i] = []
	## Armour painted in order once the hull is tiled: [mm, faces, filter(cell) -> bool].
	var plating: Array = []
	## The freighter isn't armed for its hull's size: it needs an escort.
	var pd_exempt := false
	## The starting ship: common rooms and hull only.
	var starter := false
	var problems := PackedStringArray()

	func _init(p_cat: ConstructionCatalog, name: String, designer: String, width: int) -> void:
		cat = p_cat
		bp.name = name
		bp.designer = designer
		mid2 = width - 1

	func hull(x0: int, x1: int, d0: int, d1: int, z0: int, z1: int) -> void:
		_fill(x0, x1, d0, d1, z0, z1, true)

	func truss(x0: int, x1: int, d0: int, d1: int, z0: int, z1: int) -> void:
		_fill(x0, x1, d0, d1, z0, z1, false)

	func cut(x0: int, x1: int, d0: int, d1: int, z0: int, z1: int) -> void:
		for x in range(x0, x1 + 1):
			for d in range(d0, d1 + 1):
				for z in range(z0, z1 + 1):
					cells.erase(Vector3i(x, d, z))

	func _fill(x0: int, x1: int, d0: int, d1: int, z0: int, z1: int, pressurised: bool) -> void:
		for x in range(x0, x1 + 1):
			for d in range(d0, d1 + 1):
				for z in range(z0, z1 + 1):
					cells[Vector3i(x, d, z)] = pressurised

	func wedge(cell: Vector3i, rotation: int = 0, flip: bool = false, def: StringName = &"wedge_short") -> void:
		wedges[cell] = [def, rotation, flip]

	## Sloped armour along a hull edge: wedges in the empty cells at column
	## `x` of `deck`, z0…z1, leaning on the hull to their `inboard` side
	## (&"starboard": they slope down to port; &"port": down to starboard) —
	## from its top deck (`top`) or under its bottom one.
	func skirt(x: int, deck: int, z0: int, z1: int, inboard: StringName, top: bool = true) -> void:
		for z in range(z0, z1 + 1):
			var c := Vector3i(x, deck, z)
			if not cells.has(c) and not wedges.has(c):
				wedges[c] = [&"wedge_short", 1 if inboard == &"starboard" else 3, not top]

	## Skirts down both flanks of the slab x0…x1 on `deck` (outside it).
	func skirts(x0: int, x1: int, deck: int, z0: int, z1: int, top: bool = true) -> void:
		skirt(x0 - 1, deck, z0, z1, &"starboard", top)
		skirt(x1 + 1, deck, z0, z1, &"port", top)

	## Landing legs on the ventral faces of these cells.
	func legs(at: Array) -> void:
		for c: Vector3i in at:
			fit(&"landing_leg", c, &"ventral")

	## Wedges ahead of every pressurised cell with nothing ahead of it (where
	## `only` agrees): sloped up with hull below, down with hull above, none
	## between two decks (that face stays flat). `sharp`: two cells long.
	func prow(only: Callable = Callable(), sharp: bool = false) -> void:
		for c: Vector3i in cells.keys():
			var ahead := c + Vector3i(0, 0, -1)
			var far := c + Vector3i(0, 0, -2)
			if not cells[c] or cells.has(ahead) or wedges.has(ahead) or (only.is_valid() and not only.call(c)):
				continue
			var above := cells.has(c + Vector3i.UP)
			var below := cells.has(c + Vector3i.DOWN)
			if above and below:
				continue
			if sharp and not cells.has(far) and not wedges.has(far):
				wedges[far] = [&"wedge_long", 0, above and not below]
				wedges[ahead] = [&"", 0, false]  # held by the long wedge
			else:
				wedges[ahead] = [&"wedge_short", 0, above and not below]

	func room(def: StringName, deck: int, x0: int, z0: int, w: int, d: int) -> void:
		bp.add_room(def, deck, Rect2i(x0, z0, w, d))

	func door(a: Vector3i, b: Vector3i) -> void:
		bp.add_hatch(a, b)

	func ladder(x: int, z: int, lower: int, upper: int) -> void:
		door(Vector3i(x, lower, z), Vector3i(x, upper, z))

	## Rooms in a row down one side of a corridor, aft from `z0`: entries
	## [role, length] or [role, length, parts]. Each room gets a hatch onto
	## the corridor in its first row, from column `door_x` to `hall_x`; its
	## parts (internal equipment ids) are fitted 2 × 2 ones first, away from
	## that hatch, then 1 × 1 ones in the cells left. Returns the next z.
	func run(deck: int, x0: int, w: int, z0: int, door_x: int, hall_x: int, plan: Array) -> int:
		var z := z0
		for entry: Array in plan:
			var length: int = entry[1]
			room(entry[0], deck, x0, z, w, length)
			door(Vector3i(door_x, deck, z), Vector3i(hall_x, deck, z))
			if entry.size() > 2:
				furnish(entry[2], deck, Rect2i(x0, z, w, length), Vector3i(door_x, deck, z))
			z += length
		return z

	## Fit `parts` into the room cells of `rect` on `deck`, never on `keep`
	## (a hatch's cell) or the column it stands in when the room is wider
	## than two (the walkway), nor its row when it isn't.
	func furnish(parts: Array, deck: int, rect: Rect2i, keep: Vector3i) -> void:
		var walk := func(c: Vector3i) -> bool:
			if rect.size.x > 2:
				return c.x == keep.x
			return c.z == keep.z
		for def: StringName in parts:
			var e: EquipmentDefinition = cat.equipment[def]
			var fp := e.footprint_cells
			var done := false
			for z in range(rect.position.y, rect.end.y - fp.y + 1):
				for x in range(rect.position.x, rect.end.x - fp.x + 1):
					var ok := true
					for dx in fp.x:
						for dz in fp.y:
							var c := Vector3i(x + dx, deck, z + dz)
							ok = ok and not inside.has(c) and not walk.call(c)
					if ok:
						fit(def, Vector3i(x, deck, z))
						done = true
						break
				if done:
					break
			if not done:
				problems.append("no room for %s in %s on deck %d" % [def, rect, deck])

	## `n` of `def`, for furnish().
	static func many(def: StringName, n: int) -> Array:
		var out := []
		for k in n:
			out.append(def)
		return out

	func mx(x: int) -> int:
		return mid2 - x

	static func mirror_face(face: StringName) -> StringName:
		match face:
			&"port":
				return &"starboard"
			&"starboard":
				return &"port"
		return face

	func fit(def: StringName, cell: Vector3i, face: StringName = &"", rotation: int = 0) -> void:
		var e: EquipmentDefinition = cat.equipment.get(def)
		if e == null:
			problems.append("no such part %s" % def)
			return
		if e.is_external():
			var span: Array[Vector3i] = [cell]
			if e.size_cells > 1:
				span = ShipGrid.patch(cell, face, e.size_cells)
			elif not ShipGrid.is_fin(e, rotation):
				var step := ShipGrid.external_step(face, rotation)
				for k in range(1, maxi(e.length_cells, 1)):
					span.append(cell + step * k)
			for c in span:
				var key := "%s|%s" % [c, face]
				if taken.has(key):
					problems.append("%s at %s: its %s face is taken" % [def, c, face])
				taken[key] = true
		else:
			for dx in e.footprint_cells.x:
				for dz in e.footprint_cells.y:
					inside[cell + Vector3i(dx, 0, dz)] = true
		bp.add_equipment(def, cell, face, rotation)

	## `def` at `cell` and at its mirror image across the centreline.
	func pair(def: StringName, cell: Vector3i, face: StringName = &"", rotation: int = 0) -> void:
		fit(def, cell, face, rotation)
		var e: EquipmentDefinition = cat.equipment.get(def)
		var width := 1
		if e != null and not e.is_external():
			width = e.footprint_cells.y if posmod(rotation, 2) == 1 else e.footprint_cells.x
		elif e != null and ShipGrid.face_tangents(face)[0].x != 0:
			width = e.size_cells  # a sized part's patch runs across the ship from its cell
		fit(def, Vector3i(mx(cell.x) - (width - 1), cell.y, cell.z), mirror_face(face), rotation)

	## Plates of `mm` on the plateable `faces` of every hull cell `where` says.
	func armour(mm: int, faces: Array, where: Callable = Callable()) -> void:
		plating.append([mm, faces, where])

	func finish() -> ShipBlueprint:
		_tile()
		var keys := wedges.keys()
		keys.sort()
		for c: Vector3i in keys:
			if wedges[c][0] != &"":
				bp.add_module(wedges[c][0], c, wedges[c][1], wedges[c][2])
		var grid := ShipGrid.build(bp, cat)
		var hull_cells: Array = grid.module_at.keys()
		hull_cells.sort()
		for rule: Array in plating:
			for c: Vector3i in hull_cells:
				if (rule[2] as Callable).is_valid() and not (rule[2] as Callable).call(c):
					continue
				for face in grid.plateable_faces(c):
					if (rule[1] as Array).has(face):
						var key := ShipBlueprint.plate_key(c, face)
						if int(rule[0]) > 0:
							bp.armor[key] = int(rule[0])
						else:
							bp.armor.erase(key)
		var editor := ShipEditor.new(bp, cat)
		editor.auto_route_bus()
		for c in trunks:
			if grid.is_hull(c):
				bp.bus[ShipBlueprint.cell_key(c)] = true
			else:
				problems.append("trunk cell %s is not hull" % c)
		editor.auto_route_coolant()
		return bp

	## Pressurised cells in 2 × 2 blocks, paired outwards from the centreline
	## (and fore to aft from the bow), 1 × 1 where a pair won't fit; truss in
	## 1 × 2 lengths along the hull.
	func _tile() -> void:
		var keys := cells.keys()
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			if a.z != b.z:
				return a.z < b.z
			return a.x < b.x)
		var z0 := 0
		for c: Vector3i in keys:
			z0 = mini(z0, c.z)
		var placed := {}
		for c: Vector3i in keys:
			if placed.has(c):
				continue
			var pressurised: bool = cells[c]
			var az := c.z - posmod(c.z - z0, 2)
			# The preferred pairing first; where a frame or an edge breaks it,
			# the other way along x, then along z.
			var zs: Array[int] = [az, c.z if az != c.z else c.z - 1]
			var done := false
			if pressurised:
				var ax := _x_anchor(c.x)
				var xs: Array[int] = [ax, c.x if ax != c.x else c.x - 1]
				for bz in zs:
					for bx in xs:
						if 2 * bx == mid2 or 2 * (bx + 1) == mid2:
							continue  # an odd beam's centre column stays whole, for symmetry
						var block: Array[Vector3i] = [Vector3i(bx, c.y, bz), Vector3i(bx + 1, c.y, bz), Vector3i(bx, c.y, bz + 1), Vector3i(bx + 1, c.y, bz + 1)]
						if not done and block.all(func(b: Vector3i) -> bool: return cells.get(b, false) == true and not placed.has(b)):
							bp.add_module(&"hull_block", block[0])
							for b in block:
								placed[b] = true
							done = true
				if not done:
					bp.add_module(&"hull_block_1x1", c)
					placed[c] = true
			else:
				for bz in zs:
					var pair_cells: Array[Vector3i] = [Vector3i(c.x, c.y, bz), Vector3i(c.x, c.y, bz + 1)]
					if not done and pair_cells.all(func(b: Vector3i) -> bool: return cells.has(b) and cells[b] == false and not placed.has(b)):
						bp.add_module(&"truss_block", pair_cells[0])
						for b in pair_cells:
							placed[b] = true
						done = true
				if not done:
					bp.add_module(&"truss_1x1", c)
					placed[c] = true

	## The lower x of the block column pair `x` belongs to, pairing outwards
	## from the centreline (an odd beam's centre column pairs with nothing).
	func _x_anchor(x: int) -> int:
		if 2 * x == mid2:
			return x
		if 2 * x < mid2:
			return x - 1 if ((mid2 - 1 - 2 * x) / 2) % 2 == 0 else x
		return x if ((2 * x - mid2 - 1) / 2) % 2 == 0 else x - 1


# --- A. Interceptor -------------------------------------------------------------------

## Halley-class interceptor: a low armoured dart in front of a boxy engine
## block twice its height. The cockpit rides over the nose behind a chisel
## prow; four crew, two compact reactors, the magazine and tanks along the keel;
## sloped strakes down both flanks (angled armour where a pursuit is shot at
## from the side); two medium high-thrust engines in the middle of the
## block's stern and a pair of standard ones either side, two radiator fins
## over it like a tail. Two light guns, two PD mounts,
## legs under the keel and the block. Short legs in the other sense too:
## 600 s engines and three tanks. No collar: it catches, it doesn't hold.
func _interceptor() -> Draft:
	var s := Draft.new(cat, "Halley-class interceptor", "Earth Shipyard", 6)
	var tank := &"propellant_tank"
	s.hull(2, 3, 0, 0, 0, 9)
	s.hull(2, 3, 1, 1, 1, 4)
	s.hull(0, 5, 0, 1, 10, 12)
	s.skirts(2, 3, 0, 3, 9)
	s.prow(Callable(), true)
	s.room(&"bridge", 1, 2, 1, 2, 2)
	s.room(&"crew_quarters", 1, 2, 3, 1, 2)
	s.room(&"life_support", 1, 3, 3, 1, 2)
	s.door(Vector3i(2, 1, 2), Vector3i(2, 1, 3))
	s.door(Vector3i(3, 1, 2), Vector3i(3, 1, 3))
	s.room(&"magazine", 0, 2, 0, 2, 1)
	s.room(&"corridor", 0, 2, 1, 2, 3)
	s.ladder(2, 1, 0, 1)
	s.door(Vector3i(2, 0, 0), Vector3i(2, 0, 1))
	s.room(&"reactor_room", 0, 2, 4, 2, 3)
	s.door(Vector3i(2, 0, 3), Vector3i(2, 0, 4))
	s.fit(&"power_distribution_unit", Vector3i(3, 0, 4))
	s.fit(&"compact_reactor", Vector3i(3, 0, 5))
	s.fit(&"compact_reactor", Vector3i(3, 0, 6))
	s.room(&"engine_room", 0, 2, 7, 2, 3)
	s.door(Vector3i(2, 0, 6), Vector3i(2, 0, 7))
	s.fit(tank, Vector3i(2, 0, 8))
	s.room(&"engine_room", 0, 0, 10, 6, 3)
	s.room(&"engine_room", 1, 0, 10, 6, 3)
	s.fit(tank, Vector3i(1, 0, 10))
	s.fit(tank, Vector3i(3, 0, 10))
	s.ladder(1, 12, 0, 1)
	s.pair(&"main_engine_high_thrust", Vector3i(1, 0, 12), &"aft")
	for d in [0, 1]:
		s.pair(&"main_engine", Vector3i(0, d, 12), &"aft")
	s.fit(&"autocannon", Vector3i(3, 1, 4), &"dorsal")
	s.fit(&"autocannon", Vector3i(2, 0, 2), &"ventral")
	s.fit(&"sensor_mast", Vector3i(2, 1, 4), &"dorsal")
	s.fit(&"point_defence", Vector3i(2, 1, 12), &"dorsal")
	s.fit(&"point_defence", Vector3i(3, 0, 6), &"ventral")
	s.fit(&"flare_launcher", Vector3i(3, 1, 12), &"dorsal")
	s.pair(&"rcs_block", Vector3i(2, 0, 0), &"port")
	s.pair(&"rcs_block", Vector3i(0, 1, 12), &"port")
	s.fit(&"rcs_block", Vector3i(2, 1, 1), &"dorsal")
	s.fit(&"rcs_block", Vector3i(3, 0, 0), &"ventral")
	s.fit(&"rcs_block", Vector3i(3, 1, 11), &"dorsal")
	s.fit(&"rcs_block", Vector3i(2, 0, 12), &"ventral")
	s.pair(&"radiator_long", Vector3i(1, 1, 10), &"dorsal", ShipGrid.FIN_ROTATION)
	s.legs([Vector3i(1, 0, 11), Vector3i(4, 0, 11), Vector3i(2, 0, 5), Vector3i(3, 0, 3)])
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"fore", &"dorsal", &"port", &"starboard"], func(c: Vector3i) -> bool: return c.z <= 2 or (c.y == 1 and c.z <= 4))
	return s


# --- B. Missile corvette -------------------------------------------------------------

## Goddard-class missile corvette: three sections you can tell apart from
## outside. A chamfered two-deck crew capsule forward (bridge, quarters, the
## one gun's magazine, a small hold); a launcher cage amidships — an open
## truss frame round a pressurised keel with the corridor over a tank deck —
## carrying eight missile racks on its flanks and top, each with clear space
## off its face; and a boxy drive block aft, wider than the rest (reactor,
## engine rooms, tanks, four engines, radiators flat on its top and bottom).
## Two masts (one hardened) for the targeting it fires on; one autocannon
## and three PD mounts for anything that gets close. Its weapons are
## finite: 96 missiles, then home to rearm.
func _missile_corvette() -> Draft:
	var s := Draft.new(cat, "Goddard-class missile corvette", "Earth Shipyard", 6)
	var tank := &"propellant_tank"
	s.hull(1, 4, 0, 1, 0, 4)
	s.hull(2, 3, 0, 1, 5, 12)
	s.truss(1, 1, 0, 1, 5, 12)
	s.truss(4, 4, 0, 1, 5, 12)
	s.hull(0, 5, 0, 1, 13, 18)
	s.skirts(1, 4, 1, 0, 4)
	s.skirts(1, 4, 0, 0, 4, false)
	s.prow(func(c: Vector3i) -> bool: return c.z == 0 or c.z == 13)
	# Capsule.
	s.room(&"bridge", 1, 1, 0, 4, 2)
	s.room(&"corridor", 1, 2, 2, 2, 3)
	s.room(&"life_support", 1, 1, 2, 1, 3)
	s.room(&"crew_quarters", 1, 4, 2, 1, 3)
	s.room(&"cargo_hold", 0, 1, 0, 4, 2)
	s.room(&"corridor", 0, 2, 2, 2, 3)
	s.room(&"crew_quarters", 0, 1, 2, 1, 3)
	s.room(&"magazine", 0, 4, 2, 1, 3)
	s.door(Vector3i(2, 1, 1), Vector3i(2, 1, 2))
	s.door(Vector3i(2, 1, 3), Vector3i(1, 1, 3))
	s.door(Vector3i(3, 1, 3), Vector3i(4, 1, 3))
	s.ladder(3, 4, 0, 1)
	s.door(Vector3i(2, 0, 3), Vector3i(1, 0, 3))
	s.door(Vector3i(3, 0, 3), Vector3i(4, 0, 3))
	s.door(Vector3i(2, 0, 2), Vector3i(2, 0, 1))
	# Launcher cage: the keel corridor over the tank deck.
	s.room(&"corridor", 1, 2, 5, 2, 8)
	s.room(&"cargo_hold", 0, 2, 5, 2, 8)
	s.door(Vector3i(2, 1, 4), Vector3i(2, 1, 5))
	s.ladder(3, 9, 0, 1)
	for z in [5, 7, 10]:
		s.fit(tank, Vector3i(2, 0, z))
	# Drive block.
	s.room(&"reactor_room", 1, 0, 13, 6, 2)
	s.door(Vector3i(2, 1, 12), Vector3i(2, 1, 13))
	s.fit(&"fusion_reactor", Vector3i(3, 1, 13))
	s.fit(&"power_distribution_unit", Vector3i(0, 1, 13))
	s.room(&"engine_room", 1, 0, 15, 6, 4)
	s.door(Vector3i(2, 1, 14), Vector3i(2, 1, 15))
	s.fit(tank, Vector3i(0, 1, 15))
	s.fit(tank, Vector3i(4, 1, 15))
	s.ladder(2, 18, 0, 1)
	s.room(&"engine_room", 0, 0, 13, 6, 6)
	for x in [0, 4]:
		for z in [13, 15]:
			s.fit(tank, Vector3i(x, 0, z))
	s.fit(&"power_distribution_unit", Vector3i(3, 0, 13))
	for x in [2, 3]:
		for d in [0, 1]:
			s.fit(&"main_engine", Vector3i(x, d, 18), &"aft")
	# Launchers: four on the cage's top rails, two down each flank.
	for z in [6, 10]:
		s.pair(&"missile_rack", Vector3i(1, 1, z), &"dorsal")
	for z in [7, 11]:
		s.pair(&"missile_rack", Vector3i(1, 0, z), &"port")
	s.fit(&"autocannon", Vector3i(3, 1, 3), &"dorsal")
	s.fit(&"sensor_mast", Vector3i(3, 1, 0), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(2, 0, 0), &"ventral")
	s.fit(&"point_defence", Vector3i(1, 1, 2), &"dorsal")
	s.fit(&"point_defence", Vector3i(4, 0, 3), &"ventral")
	s.fit(&"point_defence", Vector3i(5, 1, 16), &"dorsal")
	s.fit(&"rcs_block", Vector3i(2, 1, 0), &"dorsal")
	s.fit(&"rcs_block", Vector3i(3, 0, 0), &"ventral")
	s.pair(&"rcs_block", Vector3i(0, 1, 14), &"port")
	s.pair(&"rcs_block", Vector3i(0, 0, 18), &"port")
	s.fit(&"rcs_block", Vector3i(1, 1, 18), &"dorsal")
	s.fit(&"rcs_block", Vector3i(4, 0, 18), &"ventral")
	s.fit(&"radiator_long", Vector3i(1, 1, 15), &"dorsal")
	s.fit(&"radiator_long", Vector3i(4, 0, 15), &"ventral")
	s.pair(&"flare_launcher", Vector3i(0, 1, 18), &"dorsal")
	s.legs([Vector3i(1, 0, 2), Vector3i(4, 0, 1), Vector3i(0, 0, 14), Vector3i(5, 0, 14)])
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"fore", &"dorsal", &"ventral", &"port", &"starboard"], func(c: Vector3i) -> bool: return c.z <= 4)
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"port", &"starboard"], func(c: Vector3i) -> bool: return c.z >= 13)
	return s


# --- C. Escort frigate ----------------------------------------------------------------

## Kepler-class escort frigate — every new captain's first ship and the
## yard's reference design. A chamfered slab: sloped armour skirts down the
## main deck's edges and under the bow, a sharp chisel prow, a raised gun
## spine on top (magazine inside, a turret at each end, the mast and the
## missile rack between), cargo sponsons low on each flank and a boxy engine
## block aft, wider than the hull, under two radiator fins. Main deck:
## bridge behind the bow, the keel corridor, quarters, medbay, armoury, a
## big reactor room with the reactor inboard, the engine room. Lower deck:
## the hangar (a Wasp, door underneath), the hold with the tank farm, the
## lower engine room — a second way aft if the corridor is lost — and a
## second distribution unit. Three autocannons, a missile rack, four PD,
## flares, a fighter and a recon drone; collar and grappling arm for
## boarding and salvage; four legs. Common parts but the rack (one: the
## frigate is Earth's traffic too, and EnemyFactory adds no rack to a
## template that has one).
func _escort_frigate() -> Draft:
	var s := Draft.new(cat, "Kepler-class escort frigate", "Earth Shipyard", 8)
	s.starter = true
	var tank := &"propellant_tank"
	s.hull(2, 5, 1, 1, 0, 13)
	s.hull(2, 5, 0, 0, 2, 13)
	s.hull(3, 4, 2, 2, 4, 7)
	s.hull(1, 1, 0, 0, 6, 13)
	s.hull(6, 6, 0, 0, 6, 13)
	s.hull(1, 6, 0, 1, 14, 17)
	s.skirts(2, 5, 1, 0, 13)
	s.skirts(2, 5, 0, 2, 5, false)
	s.prow(func(c: Vector3i) -> bool: return c.y == 1, true)
	s.prow(func(c: Vector3i) -> bool: return c.y != 1)
	# Main deck.
	s.room(&"bridge", 1, 2, 0, 4, 2)
	s.room(&"corridor", 1, 3, 2, 2, 7)
	s.room(&"crew_quarters", 1, 2, 2, 1, 4)
	s.room(&"crew_quarters", 1, 5, 2, 1, 4)
	s.room(&"life_support", 1, 2, 6, 1, 3)
	s.room(&"armoury", 1, 5, 6, 1, 3)
	s.room(&"reactor_room", 1, 2, 9, 4, 5)
	s.room(&"engine_room", 1, 1, 14, 6, 4)
	s.door(Vector3i(3, 1, 1), Vector3i(3, 1, 2))
	s.door(Vector3i(3, 1, 3), Vector3i(2, 1, 3))
	s.door(Vector3i(4, 1, 3), Vector3i(5, 1, 3))
	s.door(Vector3i(3, 1, 7), Vector3i(2, 1, 7))
	s.door(Vector3i(4, 1, 7), Vector3i(5, 1, 7))
	s.door(Vector3i(3, 1, 8), Vector3i(3, 1, 9))
	s.door(Vector3i(3, 1, 13), Vector3i(3, 1, 14))
	s.fit(&"fusion_reactor", Vector3i(3, 1, 10))  # inboard: two cells of rooms and hull either side
	s.fit(&"power_distribution_unit", Vector3i(2, 1, 10))
	s.fit(tank, Vector3i(1, 1, 15))
	s.fit(tank, Vector3i(5, 1, 15))
	# Spine: the gun deck's magazine.
	s.room(&"magazine", 2, 3, 4, 2, 4)
	s.door(Vector3i(3, 2, 5), Vector3i(3, 1, 5))
	# Lower deck.
	s.room(&"hangar", 0, 2, 2, 4, 6)
	s.room(&"cargo_hold", 0, 2, 8, 4, 6)
	s.room(&"engine_room", 0, 1, 14, 6, 4)
	s.room(&"cargo_hold", 0, 1, 6, 1, 8)
	s.room(&"cargo_hold", 0, 6, 6, 1, 8)
	s.ladder(3, 3, 0, 1)
	s.ladder(3, 8, 0, 1)
	s.door(Vector3i(3, 0, 7), Vector3i(3, 0, 8))
	s.door(Vector3i(3, 0, 13), Vector3i(3, 0, 14))
	s.ladder(3, 14, 0, 1)
	s.door(Vector3i(2, 0, 9), Vector3i(1, 0, 9))
	s.door(Vector3i(5, 0, 9), Vector3i(6, 0, 9))
	s.fit(&"fighter_bay", Vector3i(4, 0, 4))
	s.fit(tank, Vector3i(2, 0, 10))
	s.fit(tank, Vector3i(4, 0, 10))
	s.fit(tank, Vector3i(1, 0, 15))
	s.fit(tank, Vector3i(5, 0, 15))
	s.fit(&"power_distribution_unit", Vector3i(3, 0, 16))
	# Drive.
	for x in [2, 3, 4, 5]:
		s.fit(&"main_engine", Vector3i(x, 1, 17), &"aft")
	s.pair(&"main_engine", Vector3i(3, 0, 17), &"aft")
	s.pair(&"radiator_long", Vector3i(1, 1, 14), &"dorsal", ShipGrid.FIN_ROTATION)
	s.pair(&"rcs_block", Vector3i(2, 1, 0), &"dorsal")
	s.pair(&"rcs_block", Vector3i(2, 0, 2), &"ventral")
	s.pair(&"rcs_block", Vector3i(1, 1, 16), &"port")
	s.pair(&"rcs_block", Vector3i(1, 0, 16), &"port")
	s.pair(&"rcs_block", Vector3i(1, 1, 17), &"dorsal")
	s.pair(&"rcs_block", Vector3i(1, 0, 17), &"ventral")
	# Armament.
	s.fit(&"autocannon", Vector3i(3, 2, 4), &"dorsal")
	s.fit(&"autocannon", Vector3i(4, 2, 7), &"dorsal")
	s.fit(&"autocannon", Vector3i(3, 0, 12), &"ventral")
	s.fit(&"missile_rack", Vector3i(3, 2, 6), &"dorsal")
	s.fit(&"point_defence", Vector3i(2, 1, 2), &"dorsal")
	s.fit(&"point_defence", Vector3i(5, 1, 13), &"dorsal")
	s.fit(&"point_defence", Vector3i(1, 0, 7), &"ventral")
	s.fit(&"point_defence", Vector3i(6, 0, 12), &"ventral")
	s.pair(&"flare_launcher", Vector3i(2, 1, 17), &"dorsal")
	s.fit(&"sensor_mast", Vector3i(4, 2, 5), &"dorsal")
	s.fit(&"drone_rack", Vector3i(4, 0, 8), &"ventral")
	s.fit(&"docking_collar", Vector3i(1, 0, 7), &"port")
	s.fit(&"grapple_arm", Vector3i(6, 0, 8), &"starboard")
	s.legs([Vector3i(1, 0, 10), Vector3i(6, 0, 10), Vector3i(2, 0, 16), Vector3i(5, 0, 16)])
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"fore", &"dorsal", &"ventral", &"port", &"starboard"], func(c: Vector3i) -> bool: return c.z <= 2)
	return s


# --- D. Gun destroyer -----------------------------------------------------------------

## Gauss-class gun destroyer: a ship built round one large railgun. Its
## muzzle fills the flat bow of a square, three-deck gun housing 36 m long,
## on the centreline so its recoil goes through the centre of mass; inside
## the housing the dense magazine at the breech and two reactors either side
## of the keel feed the gun's 900 kW, with tanks above and below. Behind it a
## chamfered three-deck hull — bridge, workshop, crew, the secondaries'
## magazine, the tank farm — and a boxy engine block, wider still, under an
## X of radiator fins. Heavy RCS at the gun's tip and the block's corners
## swing the whole ship onto a target (the gun traverses only 12°/s). Two
## autocannons, PD and flares; nothing else.
func _gun_destroyer() -> Draft:
	var s := Draft.new(cat, "Gauss-class gun destroyer", "Caloris Foundry", 7)
	var tank := &"propellant_tank"
	s.hull(2, 4, 0, 2, 0, 11)
	s.hull(1, 5, 0, 2, 12, 25)
	s.hull(0, 6, 0, 2, 26, 29)
	s.skirts(1, 5, 2, 12, 25)
	s.skirts(1, 5, 0, 12, 25, false)
	s.prow(func(c: Vector3i) -> bool: return c.z > 0)  # the muzzle's face stays flat
	# Gun housing: the breech's dense magazine, the gun's reactors, tanks.
	s.room(&"dense_magazine", 1, 2, 0, 3, 5)
	s.room(&"reactor_room", 1, 2, 5, 3, 7)
	s.door(Vector3i(4, 1, 4), Vector3i(4, 1, 5))
	s.fit(&"fusion_reactor", Vector3i(2, 1, 6))
	s.fit(&"fusion_reactor", Vector3i(2, 1, 9))
	s.fit(&"power_distribution_unit", Vector3i(2, 1, 5))
	s.fit(&"power_distribution_unit", Vector3i(2, 1, 11))
	for d in [0, 2]:
		s.room(&"engine_room", d, 2, 0, 3, 12)
		s.ladder(4, 8, mini(d, 1), maxi(d, 1))
		s.furnish(Draft.many(tank, 4), d, Rect2i(2, 0, 3, 12), Vector3i(4, d, 8))
	# Main hull: keel corridor on the main deck, rooms either side.
	s.room(&"corridor", 1, 3, 12, 1, 14)
	s.door(Vector3i(3, 1, 11), Vector3i(3, 1, 12))
	s.run(1, 1, 2, 12, 2, 3, [[&"bridge", 4], [&"crew_quarters", 3], [&"life_support", 3], [&"magazine", 4]])
	s.run(1, 4, 2, 12, 4, 3, [[&"workshop", 4], [&"crew_quarters", 3], [&"cafeteria", 3], [&"armoury", 4]])
	for d in [0, 2]:
		s.room(&"engine_room", d, 1, 12, 5, 14)
		s.ladder(3, 18, mini(d, 1), maxi(d, 1))
		s.furnish(Draft.many(tank, 6), d, Rect2i(1, 12, 5, 14), Vector3i(3, d, 18))
	# Engine block.
	for d in 3:
		s.room(&"engine_room", d, 0, 26, 7, 4)
		s.furnish(Draft.many(tank, 2), d, Rect2i(0, 26, 7, 4), Vector3i(3, d, 26))
	s.door(Vector3i(3, 1, 25), Vector3i(3, 1, 26))
	for x in [2, 3, 4]:
		for d in 3:
			s.fit(&"main_engine", Vector3i(x, d, 29), &"aft")
	# The gun and what points it.
	s.fit(&"railgun", Vector3i(2, 0, 0), &"fore")
	for d in [0, 2]:
		s.pair(&"rcs_block_heavy", Vector3i(2, d, 1), &"port")
		s.pair(&"rcs_block_heavy", Vector3i(0, d, 29), &"port")
	s.fit(&"autocannon", Vector3i(3, 2, 23), &"dorsal")
	s.fit(&"autocannon", Vector3i(3, 0, 23), &"ventral")
	s.fit(&"point_defence", Vector3i(3, 2, 6), &"dorsal")
	s.fit(&"point_defence", Vector3i(3, 0, 6), &"ventral")
	s.pair(&"point_defence", Vector3i(1, 2, 14), &"dorsal")
	s.pair(&"point_defence", Vector3i(1, 0, 22), &"ventral")
	s.fit(&"sensor_mast", Vector3i(2, 2, 13), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(4, 0, 13), &"ventral")
	s.fit(&"docking_collar", Vector3i(1, 1, 17), &"port")
	s.pair(&"radiator_long", Vector3i(0, 2, 27), &"dorsal", ShipGrid.FIN_ROTATION)
	s.pair(&"radiator_long", Vector3i(0, 0, 27), &"ventral", ShipGrid.FIN_ROTATION)
	s.pair(&"flare_launcher", Vector3i(1, 2, 29), &"dorsal")
	s.legs([Vector3i(1, 0, 13), Vector3i(5, 0, 13), Vector3i(1, 0, 29), Vector3i(5, 0, 29)])
	s.armour(ShipBlueprint.PLATE_THICK_MM, [&"fore", &"dorsal", &"ventral", &"port", &"starboard"], func(c: Vector3i) -> bool: return c.z <= 4)
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"dorsal", &"ventral", &"port", &"starboard"], func(c: Vector3i) -> bool: return c.z > 4 and c.z <= 11)
	return s


# --- E. Heavy cruiser -----------------------------------------------------------------

## Laplace-class heavy cruiser: built to fight alone, far from a yard. Three
## armoured blocks on two narrow waists — the battery forward (two bow guns
## and two turrets over their magazines), the citadel (bridge, two reactor
## rooms, workshop, crew, missile racks along its top edges) and
## engineering aft (an auxiliary bridge, a third reactor, engine rooms and
## twelve high-Isp engines for the range). Two keel corridors, on the main
## and upper decks, run bow to stern through both waists: a breach vents
## one, the other stays pressurised, and the power bus is laid down both.
## Radiators line the waists, between the blocks that shield them. Drones
## for the work it can't come home for: two repair, a salvage, a recon.
func _heavy_cruiser() -> Draft:
	var s := Draft.new(cat, "Laplace-class heavy cruiser", "Martian Shipyard", 8)
	s.hull(1, 6, 0, 2, 0, 9)
	s.hull(3, 4, 1, 2, 10, 13)
	s.hull(0, 7, 0, 2, 14, 27)
	s.hull(3, 4, 1, 2, 28, 31)
	s.hull(1, 6, 0, 2, 32, 43)
	for z: Array in [[0, 9], [32, 43]]:
		s.skirts(1, 6, 2, z[0], z[1])
		s.skirts(1, 6, 0, z[0], z[1], false)
	# A flat bow over the chin: the two bow guns' ports.
	s.prow(func(c: Vector3i) -> bool: return c.z == 0 and not (c.y >= 1 and c.x >= 2 and c.x <= 5), true)
	s.prow(func(c: Vector3i) -> bool: return c.z > 0)
	var tank := &"propellant_tank"
	s.room(&"corridor", 1, 3, 2, 2, 42)
	s.room(&"corridor", 2, 3, 0, 2, 44)
	for d in [1, 2]:
		for z in range(2, 44):
			s.trunks.append(Vector3i(3 if d == 1 else 4, d, z))
	for z in [5, 20, 36]:
		s.ladder(4, z, 1, 2)
	# Battery.
	s.room(&"magazine", 1, 1, 0, 6, 2)
	s.door(Vector3i(3, 1, 1), Vector3i(3, 1, 2))
	s.run(1, 1, 2, 2, 2, 3, [[&"crew_quarters", 4], [&"armoury", 4]])
	s.run(1, 5, 2, 2, 5, 4, [[&"crew_quarters", 4], [&"life_support", 4]])
	s.run(2, 1, 2, 0, 2, 3, [[&"crew_quarters", 6], [&"life_support", 4]])
	s.run(2, 5, 2, 0, 5, 4, [[&"magazine", 6], [&"cargo_hold", 4]])
	s.room(&"engine_room", 0, 1, 0, 6, 10)
	s.ladder(3, 5, 0, 1)
	s.furnish(Draft.many(tank, 8), 0, Rect2i(1, 0, 6, 10), Vector3i(3, 0, 5))
	# Citadel.
	s.run(1, 0, 3, 14, 2, 3, [[&"reactor_room", 4, [&"fusion_reactor", &"power_distribution_unit"]], [&"bridge", 4], [&"crew_quarters", 6]])
	s.run(1, 5, 3, 14, 5, 4, [[&"reactor_room", 4, [&"fusion_reactor", &"power_distribution_unit"]], [&"workshop", 4], [&"cafeteria", 3], [&"life_support", 3]])
	s.run(2, 0, 3, 14, 2, 3, [[&"magazine", 6], [&"engine_room", 8, Draft.many(tank, 4)]])
	s.run(2, 5, 3, 14, 5, 4, [[&"cargo_hold", 6], [&"engine_room", 8, Draft.many(tank, 4)]])
	s.room(&"engine_room", 0, 0, 14, 8, 14)
	s.ladder(3, 15, 0, 1)
	s.ladder(4, 26, 0, 1)
	s.furnish(Draft.many(tank, 12), 0, Rect2i(0, 14, 8, 14), Vector3i(3, 0, 15))
	# Engineering.
	s.run(1, 1, 2, 32, 2, 3, [[&"bridge", 4], [&"engine_room", 8, Draft.many(tank, 3)]])
	s.run(1, 5, 2, 32, 5, 4, [[&"reactor_room", 4, [&"fusion_reactor", &"power_distribution_unit"]], [&"engine_room", 8, Draft.many(tank, 3)]])
	s.run(2, 1, 2, 32, 2, 3, [[&"crew_quarters", 4], [&"engine_room", 8, Draft.many(tank, 3)]])
	s.run(2, 5, 2, 32, 5, 4, [[&"armoury", 4], [&"engine_room", 8, Draft.many(tank, 3)]])
	s.room(&"engine_room", 0, 1, 32, 6, 12)
	s.ladder(3, 33, 0, 1)
	s.furnish(Draft.many(tank, 8), 0, Rect2i(1, 32, 6, 12), Vector3i(3, 0, 33))
	for x in range(1, 7):
		for d in [0, 2]:
			s.fit(&"main_engine_high_isp", Vector3i(x, d, 43), &"aft")
	# Guns: two on the bow, two turrets over the battery, two aft.
	s.pair(&"kinetic_cannon", Vector3i(2, 1, 0), &"fore")
	s.fit(&"kinetic_cannon", Vector3i(3, 2, 3), &"dorsal")
	s.fit(&"kinetic_cannon", Vector3i(3, 2, 7), &"dorsal")
	s.fit(&"kinetic_cannon", Vector3i(3, 2, 39), &"dorsal")
	s.fit(&"kinetic_cannon", Vector3i(3, 0, 39), &"ventral")
	s.pair(&"autocannon", Vector3i(0, 2, 16), &"port")
	s.pair(&"autocannon", Vector3i(0, 2, 25), &"port")
	for z in [18, 21, 24]:
		s.pair(&"missile_rack", Vector3i(1, 2, z), &"dorsal")
	s.pair(&"point_defence", Vector3i(1, 2, 2), &"dorsal")
	s.pair(&"point_defence", Vector3i(1, 0, 8), &"ventral")
	s.pair(&"point_defence", Vector3i(0, 2, 14), &"dorsal")
	s.pair(&"point_defence", Vector3i(0, 0, 27), &"ventral")
	s.pair(&"point_defence", Vector3i(1, 0, 36), &"ventral")
	s.pair(&"point_defence", Vector3i(2, 2, 42), &"dorsal")
	s.pair(&"point_defence", Vector3i(3, 1, 11), &"ventral")
	s.fit(&"sensor_mast", Vector3i(4, 2, 20), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(3, 2, 11), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(4, 1, 29), &"ventral")
	s.pair(&"repair_drone_rack", Vector3i(1, 2, 34), &"dorsal")
	s.fit(&"drone_rack", Vector3i(6, 0, 22), &"ventral")
	s.fit(&"salvage_drone_rack", Vector3i(1, 0, 22), &"ventral")
	s.fit(&"docking_collar", Vector3i(0, 0, 20), &"port")
	s.fit(&"grapple_arm", Vector3i(7, 0, 16), &"starboard")
	s.pair(&"flare_launcher", Vector3i(2, 2, 43), &"dorsal")
	s.pair(&"flare_launcher", Vector3i(2, 0, 43), &"ventral")
	s.legs([Vector3i(1, 0, 4), Vector3i(6, 0, 4), Vector3i(1, 0, 38), Vector3i(6, 0, 38)])
	# Heavy RCS at the four corners of bow and stern, more at the citadel's.
	for z in [0, 9, 32, 43]:
		s.pair(&"rcs_block_heavy", Vector3i(1, 1, z), &"port")
	for z in [1, 43]:
		s.pair(&"rcs_block_heavy", Vector3i(1, 2, z), &"dorsal")
		s.pair(&"rcs_block_heavy", Vector3i(1, 0, z), &"ventral")
	s.pair(&"rcs_block", Vector3i(0, 1, 14), &"port")
	s.pair(&"rcs_block", Vector3i(0, 1, 27), &"port")
	for z in [10, 28]:
		for d in [1, 2]:
			s.pair(&"radiator_long", Vector3i(3, d, z), &"port")
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"dorsal", &"ventral"], func(c: Vector3i) -> bool: return c.z < 32 and (c.z < 10 or c.z > 13))
	s.armour(ShipBlueprint.PLATE_THICK_MM, [&"port", &"starboard"], func(c: Vector3i) -> bool: return c.z < 32 and (c.z < 10 or c.z > 13))
	s.armour(ShipBlueprint.PLATE_THICK_MM, [&"fore", &"dorsal", &"ventral"], func(c: Vector3i) -> bool: return c.z <= 0)
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"port", &"starboard", &"fore"], func(c: Vector3i) -> bool: return c.z >= 32)
	return s


# --- F. Battleship --------------------------------------------------------------------

## Newton-class battleship: firepower and protection bought with everything
## else. Two railguns at the tips of twin gun booms (each a dense magazine
## under 80 mm, feeding back into the bow's magazine block); a faceted,
## stepped bow; behind it a broad, deep hull — three full-beam decks with a
## turret deck over and under them — plated 80 mm on every face but the
## stern. Two more railguns and six heavy guns on the centreline turret
## decks over their own magazines, eight autocannons down the flanks, point
## defence all round. Four Mk II reactors in two reactor rooms either side
## of the main keel corridor, a bridge and a second one opposite, keel
## corridors on all three main decks. What it gave up: no craft, no
## missiles, a small hold, short legs on standard engines (it refuels at
## every station: a jump to Mars burns a thousand tonnes), a slow turn,
## the biggest crew and the biggest repair bills in the yard.
func _battleship() -> Draft:
	var s := Draft.new(cat, "Newton-class battleship", "Galilean Yards", 12)
	s.hull(2, 4, 1, 3, 0, 7)
	s.hull(7, 9, 1, 3, 0, 7)
	s.hull(1, 10, 1, 3, 8, 13)
	s.hull(0, 11, 1, 3, 14, 49)
	s.hull(3, 8, 0, 0, 16, 47)
	s.hull(3, 8, 4, 4, 16, 47)
	s.skirts(3, 8, 4, 16, 47)
	s.skirts(3, 8, 0, 16, 47, false)
	s.prow(func(c: Vector3i) -> bool: return c.z > 0, true)  # the guns' muzzles stay flat
	var tank := &"propellant_tank"
	# Keel corridors on the three main decks; the turret decks have their own.
	s.room(&"corridor", 2, 5, 8, 2, 42)
	for d in [1, 3]:
		s.room(&"corridor", d, 5, 8, 2, 42)
	for d in [0, 4]:
		s.room(&"corridor", d, 5, 16, 2, 32)
	for d in [1, 2, 3]:
		for z in range(10, 50):
			s.trunks.append(Vector3i(5, d, z))
	# The spinal guns' booms: each gun's dense magazine down its middle deck,
	# tanks above and below; the bow block's magazines behind them.
	for b: Array in [[2, 4], [7, 7]]:
		var x0: int = b[0]
		var walk: int = b[1]
		s.room(&"dense_magazine", 2, x0, 0, 3, 8)
		s.door(Vector3i(x0 + 1, 2, 7), Vector3i(x0 + 1, 2, 8))
		for d in [1, 3]:
			s.room(&"engine_room", d, x0, 0, 3, 8)
			s.ladder(walk, 3, mini(d, 2), maxi(d, 2))
			s.furnish(Draft.many(tank, 2), d, Rect2i(x0, 0, 3, 8), Vector3i(walk, d, 3))
	s.run(2, 1, 4, 8, 4, 5, [[&"magazine", 3], [&"cafeteria", 3]])
	s.run(2, 7, 4, 8, 7, 6, [[&"magazine", 3], [&"workshop", 3]])
	s.run(1, 1, 4, 8, 4, 5, [[&"crew_quarters", 6]])
	s.run(1, 7, 4, 8, 7, 6, [[&"life_support", 6]])
	s.run(3, 1, 4, 8, 4, 5, [[&"life_support", 6]])
	s.run(3, 7, 4, 8, 7, 6, [[&"armoury", 6]])
	for d in [1, 3]:
		s.ladder(5, 11, mini(d, 2), maxi(d, 2))
	# Main deck.
	s.run(2, 0, 5, 14, 4, 5, [[&"reactor_room", 6, [&"fusion_reactor_mk2", &"fusion_reactor_mk2", &"power_distribution_unit"]],
		[&"bridge", 6], [&"crew_quarters", 4], [&"life_support", 4], [&"workshop", 4], [&"engine_room", 12, Draft.many(&"armored_propellant_tank", 4)]])
	s.run(2, 7, 5, 14, 7, 6, [[&"reactor_room", 6, [&"fusion_reactor_mk2", &"fusion_reactor_mk2", &"power_distribution_unit"]],
		[&"bridge", 6], [&"crew_quarters", 4], [&"cafeteria", 4], [&"armoury", 4], [&"engine_room", 12, Draft.many(&"armored_propellant_tank", 4)]])
	# The decks over and under it.
	for d in [1, 3]:
		var aft := [&"engine_room", 32, Draft.many(tank, 12)]
		s.run(d, 0, 5, 14, 4, 5, [[&"crew_quarters" if d == 3 else &"armoury", 4], aft])
		s.run(d, 7, 5, 14, 7, 6, [[&"crew_quarters" if d == 3 else &"life_support", 4], aft])
		for z in [15, 30, 45]:
			s.ladder(5, z, mini(d, 2), maxi(d, 2))
	# Turret decks: a magazine over (under) every turret.
	s.run(4, 3, 2, 16, 4, 5, [[&"magazine", 6], [&"crew_quarters", 10], [&"magazine", 6], [&"life_support", 10]])
	s.run(4, 7, 2, 16, 7, 6, [[&"crew_quarters", 10], [&"magazine", 6], [&"cafeteria", 10], [&"magazine", 6]])
	s.run(0, 3, 2, 16, 4, 5, [[&"magazine", 6], [&"engine_room", 10, Draft.many(tank, 3)], [&"cargo_hold", 6], [&"engine_room", 10, Draft.many(tank, 3)]])
	s.run(0, 7, 2, 16, 7, 6, [[&"engine_room", 16, Draft.many(tank, 6)], [&"magazine", 6], [&"engine_room", 10, Draft.many(tank, 3)]])
	for z in [17, 33]:
		s.ladder(6, z, 3, 4)
		s.ladder(6, z, 0, 1)
	# Guns.
	s.pair(&"railgun", Vector3i(2, 1, 0), &"fore")
	for z in [18, 23, 28, 44]:
		s.fit(&"kinetic_cannon", Vector3i(5, 4, z), &"dorsal")
	s.fit(&"railgun", Vector3i(4, 4, 33), &"dorsal")
	s.fit(&"kinetic_cannon", Vector3i(5, 0, 20), &"ventral")
	s.fit(&"railgun", Vector3i(4, 0, 33), &"ventral")
	s.fit(&"kinetic_cannon", Vector3i(5, 0, 44), &"ventral")
	for z in [17, 26, 37, 46]:
		s.pair(&"autocannon", Vector3i(0, 3, z), &"port")
	for z in [14, 24, 34, 44]:
		s.pair(&"point_defence", Vector3i(0, 3, z), &"dorsal")
		s.pair(&"point_defence", Vector3i(0, 1, z + 4), &"ventral")
	s.pair(&"point_defence", Vector3i(3, 4, 16), &"dorsal")
	s.pair(&"point_defence", Vector3i(3, 0, 47), &"ventral")
	s.pair(&"point_defence", Vector3i(2, 3, 10), &"dorsal")
	s.fit(&"sensor_mast", Vector3i(4, 4, 39), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(7, 4, 39), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(7, 0, 39), &"ventral")
	s.pair(&"docking_collar", Vector3i(0, 2, 27), &"port")
	for z in [44, 48]:
		s.pair(&"flare_launcher", Vector3i(1, 3, z), &"dorsal")
	s.pair(&"flare_launcher", Vector3i(1, 1, 48), &"ventral")
	for x in range(2, 10):
		for d in [1, 3]:
			s.fit(&"main_engine", Vector3i(x, d, 49), &"aft")
	# Heavy RCS on the booms' tips, the bow shoulders and the stern corners.
	s.pair(&"rcs_block_heavy", Vector3i(2, 2, 1), &"port")
	s.pair(&"rcs_block_heavy", Vector3i(3, 3, 1), &"dorsal")
	s.pair(&"rcs_block_heavy", Vector3i(3, 1, 1), &"ventral")
	for d in [1, 3]:
		s.pair(&"rcs_block_heavy", Vector3i(0, d, 14), &"port")
		s.pair(&"rcs_block_heavy", Vector3i(0, d, 49), &"port")
	s.pair(&"rcs_block_heavy", Vector3i(3, 4, 47), &"dorsal")
	s.pair(&"rcs_block_heavy", Vector3i(3, 0, 16), &"ventral")
	# Heat-pipe radiators as fins off the stern quarter, above and below.
	for z in [40, 45]:
		s.pair(&"heat_pipe_radiator", Vector3i(1, 3, z), &"dorsal", ShipGrid.FIN_ROTATION)
		s.pair(&"heat_pipe_radiator", Vector3i(1, 1, z), &"ventral", ShipGrid.FIN_ROTATION)
	s.legs([Vector3i(3, 0, 24), Vector3i(8, 0, 24), Vector3i(3, 0, 41), Vector3i(8, 0, 41)])
	s.armour(ShipBlueprint.PLATE_THICK_MM, [&"fore", &"dorsal", &"ventral", &"port", &"starboard"])
	return s


# --- G. Fleet carrier -----------------------------------------------------------------

## Galileo-class fleet carrier: two hulls and the hangar deck slung between
## them. The side hulls (bridge in the port one, flight control in the
## starboard one, two reactors and the tanks in each, the engines across
## their sterns) stand a deck taller than the hangar block, so its flanks
## are covered by them and its roof is armoured. Three hangars on the lower
## deck, bulkheaded by magazine rows that also rearm the craft, each with
## its doors underneath: eight Wasp bays and two Mantis bomber bays, room to
## service them on the hangar deck. Over them the servicing deck: workshop,
## stores, pilots' quarters. Open bracing frames between the hulls fore and
## aft. It should never be in a gun duel: autocannons, a lot of point
## defence and flares, two jammers and an EW drone, repair drones.
func _fleet_carrier() -> Draft:
	var s := Draft.new(cat, "Galileo-class fleet carrier", "Galilean Yards", 16)
	s.hull(0, 3, 0, 2, 0, 43)
	s.hull(12, 15, 0, 2, 0, 43)
	s.hull(4, 11, 0, 1, 10, 33)
	s.truss(4, 11, 1, 1, 2, 5)
	s.truss(4, 11, 1, 1, 38, 41)
	# Sloped fillets from each hull's top down onto the armoured hangar roof.
	s.skirt(4, 2, 10, 33, &"port")
	s.skirt(11, 2, 10, 33, &"starboard")
	s.prow(func(c: Vector3i) -> bool: return c.x <= 3 or c.x >= 12, true)
	s.prow(func(c: Vector3i) -> bool: return c.x > 3 and c.x < 12)
	var tank := &"propellant_tank"
	# Side hulls: a corridor down the inboard column of the main deck.
	for side: Array in [[0, 3, 2], [12, 12, 13]]:
		var x0: int = side[0]
		var hall: int = side[1]
		var door_x: int = side[2]
		var rooms_x := x0 if x0 == 0 else 13
		s.room(&"corridor", 1, hall, 0, 1, 44)
		for z in range(0, 44):
			s.trunks.append(Vector3i(hall, 1, z))
		s.run(1, rooms_x, 3, 0, door_x, hall, [[&"bridge", 4], [&"crew_quarters", 6], [&"life_support", 4],
			[&"reactor_room", 6, [&"fusion_reactor", &"power_distribution_unit"]], [&"magazine", 6],
			[&"reactor_room", 6, [&"fusion_reactor"]], [&"engine_room", 12, Draft.many(tank, 5)]])
		# Over and under the main deck: tanks and stores, a ladder down each end.
		for d in [0, 2]:
			s.room(&"engine_room", d, x0, 0, 4, 44)
			s.ladder(hall, 2, mini(d, 1), maxi(d, 1))
			s.ladder(hall, 40, mini(d, 1), maxi(d, 1))
			s.furnish(Draft.many(tank, 8), d, Rect2i(x0, 0, 4, 44), Vector3i(hall, d, 2))
	# Hangar deck: three hangars between magazine rows, doors underneath.
	s.room(&"hangar", 0, 4, 10, 8, 8)
	s.room(&"magazine", 0, 4, 18, 8, 2)
	s.room(&"hangar", 0, 4, 20, 8, 6)
	s.room(&"magazine", 0, 4, 26, 8, 2)
	s.room(&"hangar", 0, 4, 28, 8, 6)
	s.furnish(Draft.many(&"fighter_bay", 4), 0, Rect2i(4, 10, 8, 8), Vector3i(4, 0, 11))
	s.furnish(Draft.many(&"fighter_bay", 4), 0, Rect2i(4, 20, 8, 6), Vector3i(7, 0, 20))
	s.furnish(Draft.many(&"bomber_bay", 2), 0, Rect2i(4, 28, 8, 6), Vector3i(7, 0, 28))
	for z in [11, 25, 31]:
		s.door(Vector3i(3, 0, z), Vector3i(4, 0, z))
		s.door(Vector3i(12, 0, z), Vector3i(11, 0, z))
	# Servicing deck: a corridor across each end joining the side hulls, a
	# keel corridor between, the rooms either side; ladders to each hangar.
	s.room(&"corridor", 1, 4, 10, 8, 1)
	s.room(&"corridor", 1, 4, 33, 8, 1)
	s.room(&"corridor", 1, 7, 11, 2, 22)
	for z in range(10, 34):
		s.trunks.append(Vector3i(7, 1, z))
	s.run(1, 4, 3, 11, 6, 7, [[&"workshop", 6], [&"crew_quarters", 8], [&"cargo_hold", 8]])
	s.run(1, 9, 3, 11, 9, 8, [[&"magazine", 6], [&"crew_quarters", 8], [&"cafeteria", 8]])
	for z in [12, 22, 30]:
		s.ladder(8, z, 0, 1)
	s.ladder(7, 18, 0, 1)
	s.ladder(8, 26, 0, 1)
	for z in range(0, 44):
		s.trunks.append(Vector3i(3, 1, z))
	for x in [0, 1, 2, 13, 14, 15]:
		for d in [0, 2]:
			s.fit(&"main_engine", Vector3i(x, d, 43), &"aft")
	# Defence.
	for z in [6, 20, 34]:
		s.pair(&"autocannon", Vector3i(0, 2, z), &"port")
	for z in [0, 14, 29, 43]:
		s.pair(&"point_defence", Vector3i(0, 2, z), &"dorsal")
		s.pair(&"point_defence", Vector3i(0, 0, z), &"ventral")
	s.pair(&"point_defence", Vector3i(5, 1, 20), &"dorsal")
	s.pair(&"point_defence", Vector3i(4, 1, 2), &"ventral")
	s.pair(&"flare_launcher", Vector3i(1, 2, 41), &"dorsal")
	s.pair(&"flare_launcher", Vector3i(2, 2, 41), &"dorsal")
	s.pair(&"flare_launcher", Vector3i(1, 0, 41), &"ventral")
	s.pair(&"jammer", Vector3i(2, 2, 8), &"dorsal")
	s.fit(&"ew_drone_rack", Vector3i(5, 1, 30), &"dorsal")
	s.pair(&"repair_drone_rack", Vector3i(6, 1, 24), &"dorsal")
	s.pair(&"drone_rack", Vector3i(2, 2, 24), &"dorsal")
	s.fit(&"sensor_mast", Vector3i(1, 2, 2), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(14, 2, 2), &"dorsal")
	s.pair(&"docking_collar", Vector3i(0, 1, 6), &"port")
	for z in [0, 43]:
		for d in [0, 2]:
			s.pair(&"rcs_block_heavy", Vector3i(0, d, z), &"port")
	s.pair(&"rcs_block_heavy", Vector3i(1, 2, 0), &"dorsal")
	s.pair(&"rcs_block_heavy", Vector3i(1, 0, 1), &"ventral")
	s.pair(&"rcs_block_heavy", Vector3i(2, 2, 43), &"dorsal")
	s.pair(&"rcs_block_heavy", Vector3i(2, 0, 42), &"ventral")
	# Radiators flat along the side hulls' outboard flanks, low and aft.
	for z in [24, 30, 36]:
		s.pair(&"radiator_long", Vector3i(0, 0, z), &"port")
		s.pair(&"radiator_long", Vector3i(0, 1, z), &"port")
	s.legs([Vector3i(1, 0, 8), Vector3i(14, 0, 8), Vector3i(1, 0, 38), Vector3i(14, 0, 38)])
	s.armour(ShipBlueprint.PLATE_THICK_MM, [&"dorsal"], func(c: Vector3i) -> bool: return c.x >= 4 and c.x <= 11 and c.z >= 10 and c.z <= 33)
	s.armour(ShipBlueprint.PLATE_THICK_MM, [&"fore", &"dorsal", &"ventral", &"port", &"starboard"], func(c: Vector3i) -> bool: return c.z <= 0)
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"port", &"starboard"], func(c: Vector3i) -> bool: return (c.x <= 3 or c.x >= 12) and c.y == 2)
	return s


# --- H. Reconnaissance ship -----------------------------------------------------------

## Herschel-class scout: low, single-decked and lopsided on purpose. The
## sensors ride out on a truss boom to starboard — two hardened masts and a
## jammer at its tip, far from the radiators and from each other, so one
## hit can't blind it — with a recon drone and the EW drone at its root and
## a third mast on the hull. The radiators lie flat under the hull, the
## only heat it shows the drones and the sun-side doesn't see (no
## signature model yet: see KNOWN_ISSUES). High-Isp engines and four tanks
## give it the Δv for deep-space surveys (Voyager and back). One gun, two
## PD mounts, flares and a light hull: it looks, it doesn't fight.
func _scout() -> Draft:
	var s := Draft.new(cat, "Herschel-class scout", "Stickney Station", 4)
	s.hull(0, 2, 0, 0, 0, 13)
	s.truss(3, 7, 0, 0, 5, 6)
	s.skirts(0, 2, 0, 2, 12)
	s.prow(Callable(), true)
	s.room(&"bridge", 0, 0, 0, 3, 2)
	s.room(&"corridor", 0, 2, 2, 1, 8)
	s.room(&"crew_quarters", 0, 0, 2, 2, 2)
	s.room(&"life_support", 0, 0, 4, 1, 1)
	s.room(&"magazine", 0, 1, 4, 1, 1)
	s.room(&"reactor_room", 0, 0, 5, 2, 3)
	s.room(&"engine_room", 0, 0, 8, 2, 2)
	s.room(&"engine_room", 0, 0, 10, 3, 4)
	s.door(Vector3i(2, 0, 1), Vector3i(2, 0, 2))
	s.door(Vector3i(2, 0, 2), Vector3i(1, 0, 2))
	s.door(Vector3i(2, 0, 4), Vector3i(1, 0, 4))
	s.door(Vector3i(1, 0, 4), Vector3i(0, 0, 4))
	s.door(Vector3i(2, 0, 5), Vector3i(1, 0, 5))
	s.door(Vector3i(2, 0, 9), Vector3i(2, 0, 10))
	s.fit(&"fusion_reactor", Vector3i(0, 0, 6))
	s.fit(&"power_distribution_unit", Vector3i(0, 0, 5))
	s.fit(&"propellant_tank", Vector3i(0, 0, 8))
	s.fit(&"propellant_tank", Vector3i(0, 0, 10))
	s.fit(&"propellant_tank", Vector3i(0, 0, 12))
	for x in 3:
		s.fit(&"main_engine_high_isp", Vector3i(x, 0, 13), &"aft")
	s.fit(&"sensor_mast_hardened", Vector3i(7, 0, 5), &"dorsal")
	s.fit(&"sensor_mast_hardened", Vector3i(7, 0, 6), &"ventral")
	s.fit(&"jammer", Vector3i(7, 0, 5), &"starboard")
	s.fit(&"sensor_mast", Vector3i(0, 0, 1), &"dorsal")
	s.fit(&"drone_rack", Vector3i(4, 0, 5), &"dorsal")
	s.fit(&"ew_drone_rack", Vector3i(4, 0, 6), &"ventral")
	s.fit(&"autocannon", Vector3i(1, 0, 3), &"dorsal")
	s.fit(&"point_defence", Vector3i(0, 0, 9), &"dorsal")
	s.fit(&"point_defence", Vector3i(2, 0, 3), &"ventral")
	s.fit(&"flare_launcher", Vector3i(1, 0, 12), &"dorsal")
	s.fit(&"flare_launcher", Vector3i(2, 0, 12), &"dorsal")
	s.fit(&"radiator_long", Vector3i(0, 0, 9), &"ventral")
	s.fit(&"radiator_long", Vector3i(1, 0, 9), &"ventral")
	s.fit(&"rcs_block", Vector3i(0, 0, 0), &"port")
	s.fit(&"rcs_block", Vector3i(2, 0, 1), &"starboard")
	s.fit(&"rcs_block", Vector3i(1, 0, 0), &"dorsal")
	s.fit(&"rcs_block", Vector3i(1, 0, 0), &"ventral")
	s.fit(&"rcs_block", Vector3i(0, 0, 13), &"port")
	s.fit(&"rcs_block", Vector3i(2, 0, 13), &"starboard")
	s.fit(&"rcs_block", Vector3i(0, 0, 13), &"dorsal")
	s.fit(&"rcs_block", Vector3i(2, 0, 13), &"ventral")
	s.legs([Vector3i(0, 0, 2), Vector3i(2, 0, 2), Vector3i(0, 0, 13), Vector3i(2, 0, 12)])
	return s


# --- I. Heavy freighter ---------------------------------------------------------------

## Drayman-class heavy freighter — a semi-truck in space. A tall, flat-fronted
## cab (bridge on top behind a sloped windscreen, the galley, quarters for
## ten, an armoury by the crew collar) on a pressurised keel tunnel that runs
## back through the trailer: ten cargo containers clamped in pairs either
## side of it between open truss frames, each a two-deck hold with a hatch
## off the tunnel and a cargo collar under the tunnel amidships. Propellant
## rides in the tunnel's upper deck over the corridor; the drive unit aft
## (reactor, engine rooms, more tanks, four standard engines, two radiator
## fins and a grappling arm for hauling) is all common, cheap kit. Two PD
## mounts, an autocannon covering the stern and flares: enough to discourage
## a raider, not to fight one. Unarmoured, slow to turn, a big hold.
func _heavy_freighter() -> Draft:
	var s := Draft.new(cat, "Drayman-class heavy freighter", "Lunar Shipyard (Merchant Guild)", 8)
	s.pd_exempt = true
	s.hull(2, 5, 1, 3, 0, 4)
	s.hull(3, 4, 1, 2, 5, 32)
	var boxes := [6, 11, 16, 21, 26]
	for z0: int in boxes:
		s.hull(1, 2, 1, 2, z0, z0 + 3)
		s.hull(5, 6, 1, 2, z0, z0 + 3)
	for z: int in [5, 10, 15, 20, 25, 30]:
		s.truss(1, 2, 1, 2, z, z)
		s.truss(5, 6, 1, 2, z, z)
	s.hull(1, 6, 0, 3, 33, 42)
	s.prow(func(c: Vector3i) -> bool: return c.y == 3 and c.z == 0)
	var tank := &"propellant_tank"
	# Cab.
	s.room(&"bridge", 3, 2, 0, 4, 2)
	s.room(&"corridor", 3, 3, 2, 2, 3)
	s.room(&"crew_quarters", 3, 2, 2, 1, 3)
	s.room(&"crew_quarters", 3, 5, 2, 1, 2)
	s.room(&"cafeteria", 2, 2, 0, 4, 2)
	s.room(&"corridor", 2, 3, 2, 2, 3)
	s.room(&"life_support", 2, 2, 2, 1, 3)
	s.room(&"magazine", 2, 5, 2, 1, 1)
	s.room(&"cargo_hold", 2, 5, 3, 1, 2)
	s.room(&"cargo_hold", 1, 2, 0, 4, 2)
	s.room(&"armoury", 1, 2, 2, 1, 3)
	s.room(&"cargo_hold", 1, 5, 2, 1, 3)
	s.door(Vector3i(3, 3, 1), Vector3i(3, 3, 2))
	s.door(Vector3i(3, 3, 3), Vector3i(2, 3, 3))
	s.door(Vector3i(4, 3, 3), Vector3i(5, 3, 3))
	s.door(Vector3i(3, 3, 4), Vector3i(3, 2, 4))
	s.door(Vector3i(3, 2, 2), Vector3i(3, 2, 1))
	s.door(Vector3i(3, 2, 3), Vector3i(2, 2, 3))
	s.door(Vector3i(4, 2, 2), Vector3i(5, 2, 2))
	s.door(Vector3i(4, 2, 3), Vector3i(5, 2, 3))
	s.door(Vector3i(4, 2, 4), Vector3i(4, 1, 4))
	s.door(Vector3i(3, 1, 2), Vector3i(3, 1, 1))
	s.door(Vector3i(3, 1, 3), Vector3i(2, 1, 3))
	s.door(Vector3i(4, 1, 3), Vector3i(5, 1, 3))
	# Keel tunnel: corridor below, the tank deck above.
	s.room(&"corridor", 1, 3, 2, 2, 31)
	s.room(&"engine_room", 2, 3, 5, 2, 28)
	s.ladder(3, 5, 1, 2)
	s.furnish(Draft.many(tank, 13), 2, Rect2i(3, 5, 2, 28), Vector3i(3, 2, 5))
	for z in range(5, 43):
		s.trunks.append(Vector3i(4, 1, z))
	# Containers: a hold on each deck, the hatch off the tunnel, a ladder inside.
	for z0: int in boxes:
		for side: Array in [[1, 2, 3], [5, 5, 4]]:
			s.room(&"cargo_hold", 1, side[0], z0, 2, 4)
			s.room(&"cargo_hold", 2, side[0], z0, 2, 4)
			s.door(Vector3i(side[1], 1, z0 + 1), Vector3i(side[2], 1, z0 + 1))
			s.ladder(side[0], z0 + 2, 1, 2)
	# Drive unit.
	s.room(&"reactor_room", 1, 1, 33, 6, 3)
	s.door(Vector3i(3, 1, 32), Vector3i(3, 1, 33))
	s.fit(&"fusion_reactor", Vector3i(1, 1, 34))
	s.fit(&"power_distribution_unit", Vector3i(6, 1, 33))
	s.room(&"engine_room", 1, 1, 36, 6, 7)
	s.door(Vector3i(3, 1, 35), Vector3i(3, 1, 36))
	s.furnish(Draft.many(tank, 4), 1, Rect2i(1, 36, 6, 7), Vector3i(3, 1, 36))
	for d in [0, 2, 3]:
		s.room(&"engine_room", d, 1, 33, 6, 10)
		if d == 0:
			s.ladder(4, 34, 0, 1)
		else:
			s.ladder(4, 34 if d == 2 else 38, d - 1, d)
		s.furnish(Draft.many(tank, 4 if d != 2 else 2), d, Rect2i(1, 33, 6, 10), Vector3i(4, d, 34 if d != 3 else 38))
	for x in [2, 5]:
		for d in [1, 2]:
			s.fit(&"main_engine", Vector3i(x, d, 42), &"aft")
	s.pair(&"radiator_long", Vector3i(2, 3, 38), &"dorsal", ShipGrid.FIN_ROTATION)
	s.fit(&"grapple_arm", Vector3i(1, 3, 33), &"dorsal")
	s.fit(&"docking_collar", Vector3i(2, 1, 3), &"port")
	s.fit(&"docking_collar", Vector3i(3, 1, 18), &"ventral")
	s.fit(&"point_defence", Vector3i(4, 3, 3), &"dorsal")
	s.fit(&"point_defence", Vector3i(3, 0, 40), &"ventral")
	s.fit(&"autocannon", Vector3i(3, 3, 41), &"dorsal")
	s.pair(&"flare_launcher", Vector3i(1, 3, 42), &"dorsal")
	s.fit(&"sensor_mast", Vector3i(3, 3, 1), &"dorsal")
	s.pair(&"rcs_block", Vector3i(2, 3, 0), &"port")
	s.pair(&"rcs_block", Vector3i(2, 1, 0), &"port")
	s.pair(&"rcs_block", Vector3i(1, 3, 42), &"port")
	s.pair(&"rcs_block", Vector3i(1, 0, 42), &"port")
	s.legs([Vector3i(2, 1, 1), Vector3i(5, 1, 1), Vector3i(1, 0, 40), Vector3i(6, 0, 40)])
	s.armour(ShipBlueprint.PLATE_THIN_MM, [&"fore", &"dorsal"], func(c: Vector3i) -> bool: return c.z <= 0)
	return s
