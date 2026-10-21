extends TestCase
## Measures: play-test batch 10 — the Moon's surface. NASA's LOLA heights
## load (8 pixels a degree) and put the Moon's highest ground where it is;
## no instant loss at 11 km — ships meet the real ground: slow, they land
## and stay there (the frame keeping up) until they thrust away; fast, they
## crash. Below 11 km the ground is drawn to the horizon; Earth's entry
## plays a re-entry cutscene that takes the hull apart.

const DT := 1.0 / 60.0


func _moon() -> OrbitalBody:
	return load("res://data/bodies/moon.tres")


func _frigate(id: StringName) -> ShipState:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, ConstructionCatalog.default_catalog())
	var stats := ShipStats.compute(bp, grid)
	var s := ShipState.create(id, String(id), stats.to_ship_config(String(id)))
	# Nose up (body −Z along local +Y, which is "up" here): the main engines lift.
	s.orientation = Quaternion(Vector3.RIGHT, PI * 0.5)
	return s


## A world over the Moon at lat 0°, lon 90° (local +Y up), the ship `above`
## m over the ground, falling at `sink` m/s.
func _world(above: float, sink: float) -> Array:
	var moon := _moon()
	var map := moon.terrain()
	var ship := _frigate(&"lander")
	var ground := moon.radius_m + map.height_at(Vector3(0, 1, 0)) + ship.contact_radius_m()
	var w := WorldSimulation.new(DT)
	w.set_central_body(moon, Vec3d.new(0, ground + above, 0), Vec3d.new(0, -sink, 0))
	w.terrain = map
	w.anchor_id = ship.id
	w.add_ship(ship)
	return [w, ship]


func test_the_lola_map() -> void:
	var map := _moon().terrain()
	assert_true(map != null, "the map loads")
	if map == null:
		return
	var lo := INF
	var hi := -INF
	for lat in range(-89, 90, 1):
		for lon in range(-180, 180, 1):
			var h := map.mapped_height(lat, lon)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var summit := map.mapped_height(5.4, -158.6)
	print("    measured: %d × %d; a 1° scan %.1f … %.1f km; near the Selenean summit (5.4° N, 158.6° W) %.1f km" % [map.width, map.height,
		lo / 1000.0, hi / 1000.0, summit / 1000.0])
	assert_true(map.width == 2880 and map.height == 1440, "8 pixels a degree")
	assert_true(lo < -7000.0 and lo > -9500.0 and hi > 9000.0 and hi < 11000.0, "the Moon's range (−9.1 … +10.8 km)")
	assert_true(summit > 9000.0, "its highest ground where it is")
	var detail := absf(map.height_at(Vector3(1, 0, 0)) - map.mapped_height(0.0, 0.0))
	assert_true(detail <= TerrainMap.DETAIL_M, "fine detail within %.0f m of the map (%.0f)" % [TerrainMap.DETAIL_M, detail])


func test_a_slow_touchdown_lands_and_stays() -> void:
	var a := _world(3.0, 1.0)
	var w: WorldSimulation = a[0]
	var ship: ShipState = a[1]
	var t := 0.0
	while not ship.landed and ship.is_active() and t < 30.0:
		w.step()
		t += DT
	print("    measured: from 3 m at 1 m/s — %s after %.1f s at %.2f m/s" % ["landed" if ship.landed else "not landed", t, ship.touchdown_mps])
	assert_true(ship.landed and ship.is_active() and ship.touchdown_mps < _moon().safe_landing_mps, "landed")
	var spot := w.frame.pci_position(ship.position).to_vector3()
	for i in roundi(120.0 / DT):
		w.step()
	var drift := w.frame.pci_position(ship.position).to_vector3().distance_to(spot)
	print("    measured: 120 s on the ground — moved %.2f m, height above ground %.2f m, local speed %.1f m/s" % [drift,
		w.height_above_ground(ship), ship.velocity.length()])
	assert_true(ship.landed and ship.is_active() and drift < 1.0, "it stays put")
	assert_true(ship.velocity.length() < WorldSimulation.LANDED_REBASE_MPS + 5.0, "the frame keeps up with it")
	# Main engines up: off it goes.
	w.set_input(ship.id, ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, false))
	for i in roundi(5.0 / DT):
		w.step()
	print("    measured: 5 s on the main engines — %.0f m above the ground" % w.height_above_ground(ship))
	assert_true(not ship.landed and w.height_above_ground(ship) > 20.0, "lifted off")
	assert_true(w.take_landing_events().size() >= 2, "touchdown and lift-off reported")


func test_a_fast_one_crashes_and_11_km_no_longer_kills() -> void:
	var a := _world(5000.0, 0.0)
	var w: WorldSimulation = a[0]
	var ship: ShipState = a[1]
	var alt0 := w.altitude_of(ship)
	for i in roundi(10.0 / DT):
		w.step()
	print("    measured: started %.1f km above the mean radius (under the old 11 km line): still flying %s" % [alt0 / 1000.0, ship.is_active()])
	assert_true(alt0 < _moon().entry_interface_altitude_m and ship.is_active(), "below 11 km and still flying")
	var t := 0.0
	while ship.is_active() and t < 200.0:
		w.step()
		t += DT
	print("    measured: fell 5 km — hit at %.0f m/s after %.0f s" % [ship.touchdown_mps, t])
	assert_true(not ship.is_active() and ship.status == ShipState.Status.ENTERED_ATMOSPHERE and ship.touchdown_mps > 20.0, "crashed")


func test_the_ground_drawn_below_11_km() -> void:
	var a := _world(2000.0, 0.0)
	var w: WorldSimulation = a[0]
	var ship: ShipState = a[1]
	var view := TerrainView.new()
	view._ready()
	view.update_view(w, ship, Vector3.ZERO, 0.1)
	var shown := view.visible
	var morph := view.morph
	var verts := view.built_vertices
	print("    measured: %.1f km up — ground %s, %d vertices, heights at %d %%" % [w.altitude_of(ship) / 1000.0, "drawn" if shown else "hidden",
		verts, roundi(morph * 100.0)])
	assert_true(shown and verts == (TerrainView.RINGS + 1) * TerrainView.SEGMENTS and morph > 0.99, "drawn, full height")
	var high := _world(20000.0, 0.0)
	view.update_view(high[0], high[1], Vector3.ZERO, 0.1)
	assert_true(not view.visible, "20 km up: the sky's sphere only")
	view.free()


func test_earth_reentry_takes_the_hull_apart() -> void:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, ConstructionCatalog.default_catalog())
	var view := ShipView.new()
	view.blueprint = bp
	view.grid = grid
	view.stats = ShipStats.compute(bp, grid)
	view._ready()
	view.show_reentry(0.1, Vector3.BACK)
	var early := view.reentry_broken
	var glow := view._plasma_mat.albedo_color.a
	view.show_reentry(1.0, Vector3.BACK)
	print("    measured: modules broken off %d at 10 %%, %d of %d at the end; plasma %.2f → %.2f" % [early, view.reentry_broken,
		bp.modules.size(), glow, view._plasma_mat.albedo_color.a])
	assert_true(early == 0 and view.reentry_broken == bp.modules.size(), "the hull comes apart as it goes")
	assert_true(view._plasma_mat.albedo_color.a > glow, "the sheath brightens")
	assert_true(not _moon().has_atmosphere and (load("res://data/bodies/earth.tres") as OrbitalBody).elevation_map == "",
		"Earth keeps its entry interface; the Moon has ground instead")
	view.free()
