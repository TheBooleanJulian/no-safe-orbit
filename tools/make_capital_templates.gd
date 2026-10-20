extends SceneTree
## Builds the capital-ship templates (Milestone 15, brought forward for the
## dealer) from standard (common) parts only and writes them to
## data/blueprints/: a Destroyer, a Cruiser and a Carrier. Each is a slab of
## 2×2 hull blocks: per deck a two-cell corridor down the middle with rooms
## either side, the bridge forward on the top deck, an engine room aft;
## reactors, tanks and (the carrier) fighter bays inside; engines aft, RCS
## at the corners, guns and point defence along the hull, radiators down
## the flanks, a sensor mast, a collar, flares. Prints the validator's
## findings; a template is written only when it validates clean.
##   godot --headless --path . -s res://tools/make_capital_templates.gd

const SPECS := [
	{"id": "destroyer_mk1", "name": "Destroyer Mk I", "w": 6, "l": 32, "decks": 2, "reactors": 2, "hangars": 0,
		"guns_per_side": 4, "pd": 8, "engines": 6, "radiators": 10, "flares": 2, "craft_racks": 2, "quarters": 3},
	{"id": "cruiser_mk1", "name": "Cruiser Mk I", "w": 8, "l": 40, "decks": 3, "reactors": 4, "hangars": 0,
		"guns_per_side": 7, "pd": 14, "engines": 12, "radiators": 22, "flares": 4, "craft_racks": 2, "quarters": 5},
	{"id": "carrier_mk1", "name": "Carrier Mk I", "w": 10, "l": 40, "decks": 2, "reactors": 3, "hangars": 4,
		"guns_per_side": 3, "pd": 12, "engines": 10, "radiators": 18, "flares": 4, "craft_racks": 4, "quarters": 4},
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
		print("%s: %d modules, %d rooms, %d equipment, %.0f t, %.2f g, crew %d — %d errors, %d warnings" % [spec.name, bp.modules.size(),
			bp.rooms.size(), bp.equipment.size(), stats.mass_kg / 1000.0, stats.thrust_forward_n / stats.mass_kg / ShipDynamics.G0,
			stats.crew_capacity, report.errors().size(), report.issues.size() - report.errors().size()])
		var seen := {}
		for issue in report.issues:
			var key := "%s %s" % [issue.code, issue.message.left(90)]
			if not seen.has(issue.code):
				print("   %s" % key)
			seen[issue.code] = int(seen.get(issue.code, 0)) + 1
		print("   counts %s" % seen)
		if report.issues.is_empty():
			var path := "%s/%s.json" % [BlueprintIO.TEMPLATE_DIR, spec.id]
			print("   wrote %s (%s)" % [path, error_string(BlueprintIO.save(bp, path))])
	quit()


static func build(spec: Dictionary, cat: ConstructionCatalog) -> ShipBlueprint:
	var w: int = spec.w
	var l: int = spec.l
	var decks: int = spec.decks
	var bp := ShipBlueprint.new()
	bp.name = spec.name
	bp.designer = "Template"
	for d in decks:
		for i in w / 2:
			for j in l / 2:
				bp.add_module(&"hull_block", Vector3i(i * 2, d, j * 2))
	var cx := w / 2 - 1  # corridor's first column (two wide)
	var side_w := cx  # side rooms' width
	var top := decks - 1
	# Room plan: roles to hand out along the side segments, deck by deck.
	var wanted: Array[StringName] = []
	for k in int(spec.reactors):
		wanted.append(&"reactor_room")
	for k in int(spec.hangars):
		wanted.append(&"hangar")
	# No workshop: it is an uncommon room (a found blueprint), and the
	# templates use standard kit only.
	wanted.append_array([&"magazine", &"magazine", &"life_support", &"life_support"])
	for k in int(spec.quarters):
		wanted.append(&"crew_quarters")
	var segments: Array = []  # [deck, side (-1 left / 1 right), z0, length]
	for d in range(decks - 1, -1, -1):
		var z0 := 2 if d == top else 0
		var z1 := l - 2
		var z := z0
		while z < z1:
			var len := mini(4, z1 - z)
			for side in [-1, 1]:
				segments.append([d, side, z, len])
			z += len
	# Bridge forward (top deck), engine room aft (every deck), corridors.
	bp.add_room(&"bridge", top, Rect2i(0, 0, w, 2))
	for d in decks:
		var z0 := 2 if d == top else 0
		bp.add_room(&"corridor", d, Rect2i(cx, z0, 2, l - 2 - z0))
		bp.add_room(&"engine_room", d, Rect2i(0, l - 2, w, 2))
		bp.add_hatch(Vector3i(cx, d, l - 3), Vector3i(cx, d, l - 2))
		if d > 0:
			bp.add_hatch(Vector3i(cx + 1, d, l / 2), Vector3i(cx + 1, d - 1, l / 2))
	bp.add_hatch(Vector3i(cx, top, 1), Vector3i(cx, top, 2))
	# Side rooms: reactors and hangars in the middle of the bottom deck and
	# fore of it, then the rest; quarters fill what is left.
	segments.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] < b[0]) if a[0] != b[0] else absi(a[2] - l / 2) < absi(b[2] - l / 2))
	var tanks_room: Array[int] = []
	for s in segments:
		# What is left over is cargo space (a tank in each).
		var role: StringName = &"cargo_hold"
		if not wanted.is_empty():
			role = wanted.pop_front()
		var x := 0 if int(s[1]) < 0 else cx + 2
		var room := bp.add_room(role, int(s[0]), Rect2i(x, int(s[2]), side_w, int(s[3])))
		var mid := int(s[2]) + int(s[3]) / 2
		var edge := cx - 1 if int(s[1]) < 0 else cx + 2
		var inner := cx if int(s[1]) < 0 else cx + 1
		bp.add_hatch(Vector3i(edge, int(s[0]), mid), Vector3i(inner, int(s[0]), mid))
		# Internal kit (2×2 footprints).
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
					tanks_room.append(room.deck)
	# Engine rooms: tanks across them.
	for d in decks:
		for i in range(0, w, 2):
			if i == cx:
				continue
			bp.add_equipment(&"propellant_tank", Vector3i(i, d, l - 2))
	# External kit.
	var taken := {}
	var place := func(def: StringName, cell: Vector3i, face: StringName) -> bool:
		var key := "%s|%s" % [cell, face]
		if taken.has(key):
			return false
		taken[key] = true
		bp.add_equipment(def, cell, face)
		return true
	# Engines on the aft face, centred.
	var n := 0
	for d in decks:
		for x in w:
			if n < int(spec.engines) and absi(x * 2 + 1 - w) <= w - 1:
				place.call(&"main_engine", Vector3i(x, d, l - 1), &"aft")
				n += 1
	# RCS at the four corners, fore and aft.
	for z in [0, l - 1]:
		for x in [0, w - 1]:
			for d in [0, top]:
				place.call(&"rcs_block", Vector3i(x, d, z), &"port" if x == 0 else &"starboard")
	for x in [0, w - 1]:
		place.call(&"rcs_block", Vector3i(x, top, 0), &"fore")
		place.call(&"rcs_block", Vector3i(x, 0, l - 1), &"aft") if not taken.has("%s|aft" % Vector3i(x, 0, l - 1)) else null
	# Guns dorsal and ventral along the centreline, spaced.
	var gun_step := maxi((l - 6) / maxi(int(spec.guns_per_side), 1), 2)
	for k in int(spec.guns_per_side):
		var z := 3 + k * gun_step
		place.call(&"autocannon", Vector3i(cx, top, z), &"dorsal")
		place.call(&"autocannon", Vector3i(cx + 1, 0, z), &"ventral")
	# Point defence on the flanks.
	var pd_step := maxi(l / maxi(int(spec.pd) / 2, 1), 2)
	for k in int(spec.pd) / 2:
		var z := 1 + k * pd_step
		place.call(&"point_defence", Vector3i(0, top, z), &"port")
		place.call(&"point_defence", Vector3i(w - 1, top, z), &"starboard")
	# Radiators down the flanks of the lower decks.
	var rad := 0
	for d in range(0, decks):
		for z in range(2, l - 2, 2):
			# A long radiator spans 3 cells along the hull: one every 4.
			if (z - 2) % 4 != 0:
				continue
			for side in [[0, &"port"], [w - 1, &"starboard"]]:
				if rad < int(spec.radiators) and place.call(&"radiator_long", Vector3i(side[0], d, z), side[1]):
					rad += 1
	# Sensor mast forward, a docking collar, flares aft, craft racks.
	place.call(&"sensor_mast", Vector3i(cx + 1, top, 1), &"dorsal")
	place.call(&"docking_collar", Vector3i(0, 0, l / 2 + 1), &"port")
	for k in int(spec.flares):
		place.call(&"flare_launcher", Vector3i(1 + k, 0, l - 1), &"aft") if not taken.has("%s|aft" % Vector3i(1 + k, 0, l - 1)) \
			else place.call(&"flare_launcher", Vector3i(1 + k, top, l - 3), &"dorsal")
	for k in int(spec.craft_racks):
		place.call(&"drone_rack" if k % 2 == 0 else &"fighter_rack", Vector3i(cx + (k % 2), top, l - 6 - 2 * (k / 2)), &"dorsal")
	return bp
