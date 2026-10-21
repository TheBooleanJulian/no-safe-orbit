extends TestCase
## Measures: play-test batch 10 — more hulls at the dealer, super-heavies
## among them, with science-fiction shapes (tools/make_capital_templates.gd):
## hammerhead prows, a forked prow, swept wings, a taller bridge tower. Each
## validates clean, flies on a new profile with what comes with it, and
## compiles in reasonable time.

const NEW := ["halberd_frigate", "wyvern_battlecruiser", "anvil_heavy_cruiser", "colossus_battleship",
	"leviathan_dreadnought", "sovereign_supercarrier"]
const SUPER_HEAVY := ["colossus_battleship", "leviathan_dreadnought", "sovereign_supercarrier"]


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _bp(id: String) -> ShipBlueprint:
	return BlueprintIO.load_file("res://data/blueprints/%s.json" % id, PackedStringArray())


## Hull cells (x) of a deck's row `z`, from its hull blocks.
func _row(bp: ShipBlueprint, deck: int, z: int) -> Array:
	var xs := {}
	for m in bp.modules:
		if m.def_id == &"hull_block" and m.position.y == deck and (m.position.z == z or m.position.z + 1 == z):
			xs[m.position.x] = true
			xs[m.position.x + 1] = true
	var out := xs.keys()
	out.sort()
	return out


func test_the_new_hulls_are_valid_and_for_sale() -> void:
	var cat := _catalog()
	var listed := BlueprintIO.list_templates()
	print("    measured: %d hulls at the dealer" % listed.size())
	assert_true(listed.size() >= 12, "six more hulls (was 6)")
	for id: String in NEW:
		var bp := _bp(id)
		assert_true(bp != null and listed.has("res://data/blueprints/%s.json" % id), "%s is for sale" % id)
		if bp == null:
			continue
		var report := ShipValidator.validate(bp, cat)
		assert_true(report.issues.is_empty(), "%s validates clean:\n%s" % [id, report.summary()])
		var t0 := Time.get_ticks_usec()
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config(id))
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var price := ServiceYard.dealer_price(bp, cat)
		print("    measured: %s — %d modules, %.0f t, %.2f g, crew %d, %d cr; compiled in %.0f ms" % [bp.name, bp.modules.size(),
			stats.mass_kg / 1000.0, stats.thrust_forward_n / stats.mass_kg / ShipDynamics.G0, sys.crew.members.size(), int(price.total), ms])
		assert_less_equal(ms, 150.0, "%s compiles without a long hitch (ms)" % id)
		if id in SUPER_HEAVY:
			assert_true(stats.mass_kg >= 10_000_000.0, "%s is a super-heavy (%.0f t)" % [id, stats.mass_kg / 1000.0])
			var bridge := 0
			var hull_top := 0
			for r in bp.rooms:
				if r.def_id == &"bridge":
					bridge = r.deck
				elif r.def_id == &"corridor":
					hull_top = maxi(hull_top, r.deck)
			assert_true(bridge - hull_top == 3, "%s: the bridge three levels over the hull's top deck (%d over %d)" % [id, bridge, hull_top])


func test_their_shapes() -> void:
	# Hammerhead: the head (first rows) wider than the neck behind it.
	for id: String in ["halberd_frigate", "anvil_heavy_cruiser", "colossus_battleship"]:
		var bp := _bp(id)
		var head := _row(bp, 0, 0).size()
		var neck := 0
		for z in range(2, 20, 2):
			var n := _row(bp, 0, z).size()
			if n < head:
				neck = n
				break
		print("    measured: %s — head %d cells across, neck %d" % [bp.name, head, neck])
		assert_true(neck > 0 and neck < head, "%s: a hammerhead prow" % id)
	# Forked prow: a gap down the middle of the first rows, closed further aft.
	var sov := _bp("sovereign_supercarrier")
	var prow := _row(sov, 0, 6)
	var aft := _row(sov, 0, 30)
	var gap := 0
	for k in range(1, prow.size()):
		gap = maxi(gap, int(prow[k]) - int(prow[k - 1]) - 1)
	print("    measured: Sovereign — a %d-cell gap between its prongs; %d cells across aft" % [gap, aft.size()])
	assert_true(gap >= 4 and aft.size() == aft[-1] - aft[0] + 1, "a forked prow on a solid hull")
	# Wings: the aft rows wider than the beam amidships.
	for id: String in ["wyvern_battlecruiser", "leviathan_dreadnought"]:
		var bp := _bp(id)
		var mid := _row(bp, 0, 20).size()
		var stern := 0
		for m in bp.modules:
			stern = maxi(stern, m.position.z)
		var tail := _row(bp, 0, stern).size()
		print("    measured: %s — %d cells across amidships, %d across the wings aft" % [bp.name, mid, tail])
		assert_true(tail > mid, "%s: swept wings" % id)
