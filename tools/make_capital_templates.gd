extends SceneTree
## Builds the capital-ship templates for the dealer and writes them to
## data/blueprints/. Play-test batch 6 asked for "more space battleship
## shaped and better armed and armoured, rather than a flat flimsy plank",
## so each is:
## - a long hull of 2×2 blocks, a deck or more taller than before, that
##   narrows in steps to a sloped prow (wedges ahead of every step);
## - a raised superstructure amidships holding the bridge, with a mast;
## - armoured: thick (80 mm) plates down the flanks, thin (40 mm) elsewhere;
## - a main battery on the centreline fore and aft of the superstructure
##   (heavy kinetic cannons; the cruiser adds railguns), autocannon
##   secondaries on the flanks, point defence along the hull and the tower,
##   missile racks, flares, craft;
## - inside: a corridor down the middle with rooms either side, reactors,
##   tanks, magazines, quarters, (the carrier) hangars, engine rooms aft.
## Play-test batch 10 asked for more variants, especially super-heavies,
## with better science-fiction shapes (after Elite Dangerous and Halo). The
## hull is now described cell by cell, so a spec can also have:
## - "prow": "hammer" — a full-beam head on a narrower neck (a hammerhead
##   prow: "head" and "neck" block-rows, the neck "neck_half" cells either
##   side of the centreline); "split" — a forked prow, "split" block-rows
##   with a gap "gap_half" cells either side of the centreline;
## - "wing_w", "wing_len", "wing_decks": swept wings flaring out from the
##   aft hull on the lowest decks, engines across their trailing edge;
## - "tower": superstructure levels (2; 3 raises the bridge a level);
## - "rcs_mid": more RCS rows amidships (fractions of the length) for the
##   heaviest, whose engines need the turning authority.
## Rarer parts (heavy cannons, railguns, missile racks) come with the ship
## at the dealer (ServiceYard.dealer_price prices them). Prints the
## validator's findings; a template is written only when it validates clean.
##   godot --headless --path . -s res://tools/make_capital_templates.gd [-- <id>…]

const SPECS := [
	{"id": "destroyer_mk1", "name": "Destroyer Mk I", "w": 8, "l": 36, "decks": 3, "bow": 3, "reactors": 3, "hangars": 0,
		"main": [&"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon"], "secondaries": 3, "pd": 10, "missiles": 2,
		"engines": 10, "radiators": 12, "flares": 2, "craft_racks": 2, "quarters": 4},
	{"id": "cruiser_mk1", "name": "Cruiser Mk I", "w": 8, "l": 48, "decks": 4, "bow": 3, "reactors": 5, "hangars": 0,
		"main": [&"railgun", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon", &"railgun"],
		"secondaries": 5, "pd": 16, "missiles": 4, "engines": 16, "radiators": 22, "flares": 4, "craft_racks": 2, "quarters": 6},
	{"id": "carrier_mk1", "name": "Carrier Mk I", "w": 12, "l": 48, "decks": 4, "bow": 3, "reactors": 4, "hangars": 6,
		"main": [&"kinetic_cannon", &"kinetic_cannon"], "secondaries": 4, "pd": 16, "missiles": 2,
		"engines": 16, "radiators": 20, "flares": 4, "craft_racks": 4, "quarters": 5},
	# Play-test batch 10.
	{"id": "halberd_frigate", "name": "Halberd Frigate", "w": 8, "l": 32, "decks": 3, "bow": 0, "prow": "hammer",
		"head": 2, "neck": 3, "neck_half": 2, "reactors": 3, "hangars": 0,
		"main": [&"kinetic_cannon", &"kinetic_cannon"], "secondaries": 3, "pd": 8, "missiles": 2,
		"engines": 9, "radiators": 10, "flares": 2, "craft_racks": 2, "quarters": 4},
	{"id": "wyvern_battlecruiser", "name": "Wyvern Battlecruiser", "w": 10, "l": 52, "decks": 4, "bow": 5, "reactors": 5,
		"hangars": 0, "wing_w": 4, "wing_len": 6, "wing_decks": 1,
		"main": [&"railgun", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon", &"railgun"], "secondaries": 4, "pd": 16,
		"missiles": 4, "engines": 20, "radiators": 20, "flares": 4, "craft_racks": 2, "quarters": 6},
	{"id": "anvil_heavy_cruiser", "name": "Anvil Heavy Cruiser", "w": 10, "l": 56, "decks": 4, "bow": 0, "prow": "hammer",
		"head": 3, "neck": 4, "neck_half": 3, "wing_w": 2, "wing_len": 5, "wing_decks": 1, "reactors": 6, "hangars": 0,
		"main": [&"railgun", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon", &"railgun"],
		"secondaries": 5, "pd": 18, "missiles": 4, "engines": 18, "radiators": 24, "flares": 4, "craft_racks": 2, "quarters": 6},
	{"id": "colossus_battleship", "name": "Colossus Battleship", "w": 12, "l": 64, "decks": 5, "bow": 0, "prow": "hammer",
		"head": 3, "neck": 3, "neck_half": 4, "wing_w": 4, "wing_len": 6, "wing_decks": 2, "tower": 3, "reactors": 8,
		"hangars": 0,
		"main": [&"railgun", &"railgun", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon",
			&"railgun", &"railgun"], "secondaries": 6, "pd": 24, "missiles": 6, "engines": 30, "radiators": 32, "flares": 6,
		"craft_racks": 2, "quarters": 8},
	{"id": "leviathan_dreadnought", "name": "Leviathan Dreadnought", "w": 12, "l": 72, "decks": 5, "bow": 4, "wing_w": 6,
		"wing_len": 8, "wing_decks": 2, "tower": 3, "reactors": 10, "rcs_mid": [0.35, 0.6], "hangars": 2,
		"main": [&"railgun", &"railgun", &"railgun", &"kinetic_cannon", &"kinetic_cannon", &"railgun", &"railgun",
			&"railgun"], "secondaries": 7, "pd": 28, "missiles": 8, "engines": 40, "radiators": 36, "flares": 6,
		"craft_racks": 4, "quarters": 9},
	{"id": "sovereign_supercarrier", "name": "Sovereign Supercarrier", "w": 16, "l": 72, "decks": 4, "bow": 2, "prow": "split",
		"split": 6, "gap_half": 2, "tower": 3, "reactors": 7, "hangars": 12,
		"main": [&"kinetic_cannon", &"kinetic_cannon", &"kinetic_cannon"], "secondaries": 6, "pd": 26, "missiles": 4,
		"engines": 28, "radiators": 30, "flares": 6, "craft_racks": 6, "quarters": 8},
]


func _initialize() -> void:
	var cat := ConstructionCatalog.default_catalog()
	var only := OS.get_cmdline_user_args()
	for spec in SPECS:
		if not only.is_empty() and not only.has(spec.id):
			continue
		var bp := build(spec, cat)
		var report := ShipValidator.validate(bp, cat)
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		print("%s: %d modules, %d rooms, %d equipment, %d plates, %.0f t, %.2f g, crew %d — %d errors, %d warnings" % [spec.name,
			bp.modules.size(), bp.rooms.size(), bp.equipment.size(), bp.armor.size(), stats.mass_kg / 1000.0,
			stats.thrust_forward_n / stats.mass_kg / ShipDynamics.G0, stats.crew_capacity, report.errors().size(),
			report.issues.size() - report.errors().size()])
		var seen := {}
		for issue in report.issues:
			if not seen.has(issue.code):
				print("   %s %s" % [issue.code, issue.message.left(400)])
			seen[issue.code] = int(seen.get(issue.code, 0)) + 1
		print("   counts %s" % seen)
		if report.issues.is_empty():
			var path := "%s/%s.json" % [BlueprintIO.TEMPLATE_DIR, spec.id]
			print("   wrote %s (%s)" % [path, error_string(BlueprintIO.save(bp, path))])
	quit()


## The hull's half-width in 2-cell blocks at row `z` (0 = the prow): full
## beam from `bow` block-rows back, one block narrower per row ahead of it.
static func _row_blocks(spec: Dictionary, z: int) -> int:
	var full: int = int(spec.w) / 2
	var row := z / 2
	var bow: int = spec.bow
	if row >= bow:
		return full
	# A block narrower each side per row ahead: a sharper prow.
	return clampi(full - 2 * (bow - row), 2, full)


## The block columns (main-hull coordinates, each 2 cells wide) of row `z`.
static func _row_cols(spec: Dictionary, z: int) -> Array:
	var w: int = spec.w
	var half := w / 2
	var row := z / 2
	var x0 := 0
	match str(spec.get("prow", "taper")):
		"hammer":
			if row >= int(spec.head) and row < int(spec.head) + int(spec.neck):
				x0 = half - int(spec.neck_half)
		_:
			x0 = half - _row_blocks(spec, z)
	x0 = x0 - x0 % 2
	var out := []
	for i in range(x0, w - x0, 2):
		if str(spec.get("prow", "")) == "split" and row < int(spec.split) \
				and i + 2 > half - int(spec.gap_half) and i < half + int(spec.gap_half):
			continue  # the fork's gap
		out.append(i)
	return out


## The first block-row aft of the prow's shaping: rooms run from here back.
static func _room_start(spec: Dictionary) -> int:
	var z := int(spec.bow) * 2
	match str(spec.get("prow", "taper")):
		"hammer":
			z = maxi(z, (int(spec.head) + int(spec.neck)) * 2)
		"split":
			z = maxi(z, int(spec.split) * 2)
	return z


static func build(spec: Dictionary, cat: ConstructionCatalog) -> ShipBlueprint:
	var w: int = spec.w
	var l: int = spec.l
	var decks: int = spec.decks
	var tower: int = spec.get("tower", 2)
	var wing_w: int = spec.get("wing_w", 0)
	var wing_len: int = spec.get("wing_len", 0)
	var wing_decks: int = spec.get("wing_decks", 0)
	var ox := wing_w  # the main hull sits between the wings
	var W := w + 2 * ox
	var bp := ShipBlueprint.new()
	bp.name = spec.name
	bp.designer = "Template"
	var top := decks - 1
	var half := w / 2
	var hull := {}  # Vector3i cell -> true
	var add_block := func(x: int, d: int, z: int) -> void:
		bp.add_module(&"hull_block", Vector3i(x, d, z))
		for dx in 2:
			for dz in 2:
				hull[Vector3i(x + dx, d, z + dz)] = true
	# Main hull, shaped at the prow.
	for j in l / 2:
		var z := j * 2
		var cols := _row_cols(spec, z)
		for d in decks:
			for i: int in cols:
				add_block.call(ox + i, d, z)
	# Swept wings off the aft hull, wider each row back.
	if wing_w > 0:
		var zw0 := l - wing_len * 2
		for j in wing_len:
			var z := zw0 + j * 2
			var ww := mini(wing_w, 2 * (j + 1))
			for d in wing_decks:
				for x in range(ox - ww, ox, 2):
					add_block.call(x, d, z)
				for x in range(ox + w, ox + w + ww, 2):
					add_block.call(x, d, z)
	# Wedges ahead of every cell with nothing ahead of it: the prow, the
	# shoulders where the hull widens, the wings' leading edges. Sloped up
	# with hull below, down with hull above, none between two decks.
	for j in l / 2:
		var z := j * 2
		for x in W:
			for d in decks:
				if not hull.has(Vector3i(x, d, z)) or hull.has(Vector3i(x, d, z - 1)):
					continue
				var wedge := bp.add_module(&"wedge_short", Vector3i(x, d, z - 1))
				var above := hull.has(Vector3i(x, d + 1, z))
				var below := hull.has(Vector3i(x, d - 1, z))
				if above and not below:
					wedge.flip = true
				if above and below:
					bp.remove(wedge.id)  # middle decks: the slope is above and below
	var cx := ox + half - 1  # corridor's first column (two wide)
	# Superstructure: `tower` levels up, four cells wide, amidships (quarters
	# below, the bridge on top), sloped at the front.
	var tz0 := (l * 2 / 5) / 2 * 2
	var tlen := maxi((l / 5) / 2 * 2, 6)
	var roof := decks + tower - 1
	for level in range(decks, decks + tower):
		for z in range(tz0, tz0 + tlen, 2):
			for i in [ox + half - 2, ox + half]:
				bp.add_module(&"hull_block", Vector3i(i, level, z))
		for x in range(ox + half - 2, ox + half + 2):
			var wedge := bp.add_module(&"wedge_short", Vector3i(x, level, tz0 - 1))
			wedge.flip = level == decks
	# Room plan.
	var wanted: Array[StringName] = []
	for k in int(spec.reactors):
		wanted.append(&"reactor_room")
	for k in int(spec.hangars):
		wanted.append(&"hangar")
	# No workshop: it is an uncommon room (a found blueprint), and the
	# templates are bought, not found.
	wanted.append_array([&"magazine", &"magazine", &"magazine", &"life_support", &"life_support"])
	for k in int(spec.quarters):
		wanted.append(&"crew_quarters")
	var bow_end := _room_start(spec)  # rooms aft of the prow's shaping
	var segments: Array = []  # [deck, side (-1 left / 1 right), z0, length]
	for d in range(decks - 1, -1, -1):
		var z := bow_end
		var z1 := l - 2
		while z < z1:
			var len := mini(4, z1 - z)
			for side in [-1, 1]:
				segments.append([d, side, z, len])
			z += len
	for level in range(decks, roof):
		bp.add_room(&"crew_quarters", level, Rect2i(ox + half - 2, tz0, 4, tlen))
	bp.add_room(&"bridge", roof, Rect2i(ox + half - 2, tz0, 4, tlen))
	bp.add_hatch(Vector3i(cx, decks - 1, tz0 + 1), Vector3i(cx, decks, tz0 + 1))
	bp.add_hatch(Vector3i(cx + 1, decks, tz0 + 3), Vector3i(cx + 1, decks + 1, tz0 + 3))
	if tower > 2:
		bp.add_hatch(Vector3i(cx, decks + 1, tz0 + 5), Vector3i(cx, decks + 2, tz0 + 5))
	var c0 := 0
	while not hull.has(Vector3i(cx, 0, c0)) or not hull.has(Vector3i(cx + 1, 0, c0)):
		c0 += 2  # the corridor starts where the hull closes round the centreline
	for d in decks:
		bp.add_room(&"corridor", d, Rect2i(cx, c0, 2, l - 2 - c0))
		bp.add_room(&"engine_room", d, Rect2i(ox, l - 2, w, 2))
		bp.add_hatch(Vector3i(cx, d, l - 3), Vector3i(cx, d, l - 2))
		if d > 0:
			bp.add_hatch(Vector3i(cx + 1, d, l / 2), Vector3i(cx + 1, d - 1, l / 2))
	var side_w := half - 1
	segments.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] < b[0]) if a[0] != b[0] else absi(a[2] - l / 2) < absi(b[2] - l / 2))
	for s in segments:
		var role: StringName = &"cargo_hold"
		if not wanted.is_empty():
			role = wanted.pop_front()
		var x := ox if int(s[1]) < 0 else cx + 2
		var room := bp.add_room(role, int(s[0]), Rect2i(x, int(s[2]), side_w, int(s[3])))
		var mid := int(s[2]) + int(s[3]) / 2
		var edge := cx - 1 if int(s[1]) < 0 else cx + 2
		var inner := cx if int(s[1]) < 0 else cx + 1
		bp.add_hatch(Vector3i(edge, int(s[0]), mid), Vector3i(inner, int(s[0]), mid))
		if int(s[3]) >= 2 and side_w >= 2:
			match role:
				&"reactor_room":
					bp.add_equipment(&"fusion_reactor", Vector3i(x, int(s[0]), int(s[2])))
					if int(s[3]) >= 4:
						bp.add_equipment(&"propellant_tank", Vector3i(x, int(s[0]), int(s[2]) + 2))
				&"hangar":
					bp.add_equipment(&"fighter_bay", Vector3i(x, int(s[0]), int(s[2])))
					if int(s[3]) >= 4:
						bp.add_equipment(&"fighter_bay", Vector3i(x, int(s[0]), int(s[2]) + 2))
				&"cargo_hold":
					bp.add_equipment(&"propellant_tank", Vector3i(x, int(s[0]), int(s[2])))
		if room == null:
			continue
	for d in decks:
		for i in range(ox, ox + w, 2):
			if i == cx or i == cx + 1:
				continue
			bp.add_equipment(&"propellant_tank", Vector3i(i, d, l - 2))
	# External kit.
	var taken := {}
	var place := func(def: StringName, cell: Vector3i, face: StringName) -> bool:
		# A long part (radiators) claims every cell of its span.
		var span: int = maxi((cat.equipment[def] as EquipmentDefinition).length_cells, 1)
		var step := ShipGrid.external_step(face, 0)
		for k in span:
			if taken.has("%s|%s" % [cell + step * k, face]):
				return false
		for k in span:
			taken["%s|%s" % [cell + step * k, face]] = true
		bp.add_equipment(def, cell, face)
		return true
	# The outermost hull column of a row on a deck (port: the first, starboard: the last).
	var outer := func(d: int, z: int, port: bool) -> int:
		for k in W:
			var x := k if port else W - 1 - k
			if hull.has(Vector3i(x, d, z)):
				return x
		return -1
	# Engines aft, from the middle out.
	var n := 0
	var order: Array = []
	for x in W:
		order.append(x)
	order.sort_custom(func(a: int, b: int) -> bool: return absi(a * 2 + 1 - W) < absi(b * 2 + 1 - W))
	# Engines from the middle out, every deck at each column (the centre of
	# mass sits mid-height).
	for x: int in order:
		for d in decks:
			if n < int(spec.engines) and hull.has(Vector3i(x, d, l - 1)) and place.call(&"main_engine", Vector3i(x, d, l - 1), &"aft"):
				n += 1
	# RCS at the corners of the full-beam hull, fore and aft (and, for the
	# heaviest, rows amidships: "rcs_mid", fractions of the length).
	var zf := bow_end
	var rcs_rows: Array = [zf, l - 1]
	for f: float in spec.get("rcs_mid", []):
		rcs_rows.append(int(l * f) / 2 * 2)
	for z: int in rcs_rows:
		for side: bool in [true, false]:
			for d in [0, top]:
				var x: int = outer.call(d, z, side)
				place.call(&"rcs_block", Vector3i(x, d, z), &"port" if side else &"starboard")
	# Main battery on the centreline: turrets on the hull ahead of the
	# superstructure, and superfiring ones on its roof (nothing ahead of
	# them but the slope below).
	var main: Array = spec.main
	var fore_n := (main.size() + 1) / 2
	var gun := 0
	var z_f := tz0 - 3
	while gun < fore_n and z_f >= c0 + 2:
		place.call(main[gun], Vector3i(cx + (gun % 2), top, z_f), &"dorsal")
		gun += 1
		z_f -= 4
	var z_r := tz0 + 1
	while gun < main.size() and z_r < tz0 + tlen - 1:
		place.call(main[gun], Vector3i(ox + half - 1, roof, z_r), &"dorsal")
		gun += 1
		z_r += 2
	# Secondaries in flank sponsons, and a ventral pair.
	var sec_step := maxi((l - bow_end - 6) / maxi(int(spec.secondaries), 1), 2)
	for k in int(spec.secondaries):
		var z := bow_end + 2 + k * sec_step
		var d := top - 1 if decks > 2 else top
		place.call(&"autocannon", Vector3i(outer.call(d, z, true), d, z), &"port")
		place.call(&"autocannon", Vector3i(outer.call(d, z, false), d, z), &"starboard")
	place.call(&"autocannon", Vector3i(cx, 0, l / 3), &"ventral")
	place.call(&"autocannon", Vector3i(cx + 1, 0, 2 * l / 3), &"ventral")
	# Point defence along the flanks' top and on the superstructure.
	var pd_left: int = spec.pd
	for x in [ox + half - 2, ox + half + 1]:
		if pd_left > 0 and place.call(&"point_defence", Vector3i(x, roof, tz0 + tlen - 1), &"port" if x < ox + half else &"starboard"):
			pd_left -= 1
	var pd_step := maxi((l - bow_end) / maxi(pd_left / 2, 1), 2)
	var zp := bow_end + 1
	while pd_left > 1 and zp < l - 2:
		place.call(&"point_defence", Vector3i(outer.call(top, zp, true), top, zp), &"port")
		place.call(&"point_defence", Vector3i(outer.call(top, zp, false), top, zp), &"starboard")
		pd_left -= 2
		zp += pd_step
	# Radiators down the flanks of the lower decks, where the flank runs
	# straight along the whole panel.
	var rad := 0
	for d in range(0, maxi(top - 1, 1)):
		for z in range(bow_end + 2, l - 2, 4):
			for side: bool in [true, false]:
				var x: int = outer.call(d, z, side)
				var straight := true
				for k in 3:
					straight = straight and outer.call(d, z + k, side) == x
				if straight and rad < int(spec.radiators) and place.call(&"radiator_long", Vector3i(x, d, z), &"port" if side else &"starboard"):
					rad += 1
	# Missile racks on the dorsal hull either side of the battery.
	for k in int(spec.missiles):
		var mz := bow_end + 1 + (k / 2) * 4
		if mz >= tz0 - 1 and mz < tz0 + tlen:
			mz += tlen + 1  # not under the superstructure: aft of it
		place.call(&"missile_rack", Vector3i(cx - 1 if k % 2 == 0 else cx + 2, top, mz), &"dorsal")
	# Mast on the superstructure, a collar, flares aft, craft racks.
	place.call(&"sensor_mast", Vector3i(ox + half, roof, tz0 + tlen - 1), &"dorsal")
	place.call(&"docking_collar", Vector3i(outer.call(0, l / 2 + 1, true), 0, l / 2 + 1), &"port")
	for k in int(spec.flares):
		place.call(&"flare_launcher", Vector3i(cx - 1 + k, top, l - 3), &"dorsal")
	for k in int(spec.craft_racks):
		place.call(&"drone_rack" if k % 2 == 0 else &"fighter_rack", Vector3i(cx + (k % 2), top, l - 6 - 2 * (k / 2)), &"dorsal")
	_armour(bp, cat)
	return bp


## Plates where a battle comes from: 80 mm down the flanks, 40 mm on top
## and on the bow; none underneath or aft (mass: a capital ship still has
## to manoeuvre).
static func _armour(bp: ShipBlueprint, cat: ConstructionCatalog) -> void:
	var grid := ShipGrid.build(bp, cat)
	var cells: Array = grid.module_at.keys()
	cells.sort()
	for cell: Vector3i in cells:
		for face in grid.plateable_faces(cell):
			if face == &"port" or face == &"starboard":
				bp.armor[ShipBlueprint.plate_key(cell, face)] = ShipBlueprint.PLATE_THICK_MM
			elif face == &"dorsal" or face == &"fore":
				bp.armor[ShipBlueprint.plate_key(cell, face)] = ShipBlueprint.PLATE_THIN_MM
