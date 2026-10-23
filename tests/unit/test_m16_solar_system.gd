extends TestCase
## Measures: Milestone 16 — the solar system. The planets are where JPL
## Horizons puts them at the scenario epoch; Phobos and Deimos circle Mars
## on their real orbits and keep one face to it; eleven locations, the outer
## planets' charts sold one after another; Mercury, Phobos and Deimos have
## ground to land on — the moons their real lumpy shapes — the giants an
## entry interface; Saturn has rings; every station is a jump a Frigate can
## pay for.

## Horizons, Sun-centred (500@10), ICRF, 2026-10-19 12:00 UT (km),
## queried 2026-10-23.
const HORIZONS_KM := {
	&"mercury": Vector3(4.901033868217014e7, -2.843831793853883e7, -2.027119163554078e7),
	&"venus": Vector3(9.974489604522613e7, 4.080301153748588e7, 1.204999285917852e7),
	&"jupiter": Vector3(-5.379721343363678e8, 5.328888560935802e8, 2.415059909613554e8),
	&"saturn": Vector3(1.381316110235292e9, 2.801573169161950e8, 5.622938654977378e7),
	&"uranus": Vector3(1.326243808033970e9, 2.377282144191216e9, 1.022410367957190e9),
	&"neptune": Vector3(4.463154622150630e9, 2.401086823840734e8, -1.283277746050627e7),
}


func _jd() -> float:
	return CelestialFrame.julian_date_from_iso(Main.SCENARIO_EPOCH_UTC)


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func test_the_planets_are_where_horizons_puts_them() -> void:
	var worst := 0.0
	var lines := PackedStringArray()
	for id: StringName in HORIZONS_KM:
		var want: Vector3 = HORIZONS_KM[id]
		var got := CelestialFrame.heliocentric_icrs(id, _jd()).times(0.001)
		var got_dir := Vector3(got.x, got.y, got.z).normalized()
		var angle := rad_to_deg(got_dir.angle_to(want.normalized()))
		var dist := absf(got.length() / want.length() - 1.0)
		worst = maxf(worst, angle)
		lines.append("%s %.3f° %.2f %%" % [id, angle, dist * 100.0])
		assert_true(angle < 0.3 and dist < 0.005, "%s within 0.3° and 0.5 %% of Horizons" % id)
	print("    measured: %s" % ", ".join(lines))


func test_mars_moons() -> void:
	var jd := _jd()
	var phobos := CelestialFrame.satellite_icrs(&"phobos", jd)
	var deimos := CelestialFrame.satellite_icrs(&"deimos", jd)
	# One orbital period later Phobos is back where it was (two-body; the
	# period from the semi-major axis of its Horizons state, vis-viva).
	var st: Array = CelestialFrame.SATELLITES[&"phobos"]
	var v0 := Vector3(st[3][0], st[3][1], st[3][2]).length() * 1000.0
	var r0 := Vector3(st[2][0], st[2][1], st[2][2]).length() * 1000.0
	var a := 1.0 / (2.0 / r0 - v0 * v0 / float(st[1]))
	var period := TAU * sqrt(a * a * a / float(st[1]))
	var back := CelestialFrame.satellite_icrs(&"phobos", jd + period / 86400.0)
	print("    measured: Phobos %.0f km from Mars (period %.2f h, back within %.1f km), Deimos %.0f km" % [phobos.length() / 1000.0,
		period / 3600.0, back.minus(phobos).length() / 1000.0, deimos.length() / 1000.0])
	assert_true(absf(phobos.length() / 1000.0 - 9376.0) < 60.0 and absf(deimos.length() / 1000.0 - 23458.0) < 60.0, "their real distances")
	assert_true(absf(period / 3600.0 - 7.65) < 0.1 and back.minus(phobos).length() < 1000.0, "Phobos goes round in 7.65 h")
	# Tidally locked: Mars stays near Phobos's prime meridian (the IAU
	# rotation and the Horizons orbit agree), hours apart.
	var phobos_body: OrbitalBody = load("res://data/bodies/phobos.tres")
	var mars_body: OrbitalBody = load("res://data/bodies/mars.tres")
	var frame := CelestialFrame.for_scenario(jd, 30.0, phobos_body)
	var lons := PackedFloat32Array()
	for h in [0.0, 2.0, 5.0]:
		var to_mars := frame.position_of(mars_body, h * 3600.0).normalized()
		var fixed := frame.pci_to_body_fixed(h * 3600.0) * to_mars
		lons.append(rad_to_deg(atan2(fixed.y, fixed.x)))
	print("    measured: Mars over Phobos at longitude %s° (0, 2, 5 h)" % [lons])
	assert_true(Array(lons).all(func(l: float) -> bool: return absf(l) < 15.0), "Mars hangs over Phobos's prime meridian (tidal lock)")
	var mars_loc := Location.by_id("mars")
	assert_true(mars_loc.sky_body != null and mars_loc.sky_body.ephemeris == &"phobos", "Phobos in Mars's sky")
	var seen_from := frame.position_of(mars_body, 0.0).length()
	print("    measured: Mars seen from Phobos %.1f° wide" % rad_to_deg(2.0 * asin(mars_body.radius_m / seen_from)))


func test_eleven_locations_and_chart_chains() -> void:
	var ids := PackedStringArray()
	for loc in Location.all():
		ids.append(loc.id)
		assert_true(loc.validate().is_empty(), "%s validates %s" % [loc.id, loc.validate()])
		assert_true(loc.body.surface_map != null and loc.map_name() != "", "%s: a map and a name" % loc.id)
		var speed := loc.body.circular_speed(loc.start_radius_m())
		assert_true(speed > 0.0, "%s: an orbit" % loc.id)
	print("    measured: %s" % ", ".join(ids))
	for id in ["mercury", "venus", "phobos", "deimos", "jupiter", "saturn", "uranus", "neptune"]:
		assert_true(id in ids, "%s is a location" % id)
	var p := PlayerProfile.new(5)
	var offered := p.brokers().map(func(l: Location) -> String: return l.id)
	print("    measured: a new player's brokers %s" % [offered])
	assert_true(offered.has("mars") and offered.has("mercury") and offered.has("venus") and not offered.has("jupiter") and not offered.has("phobos"),
		"at first: Mars, Mercury, Venus")
	p.credits = 1_000_000
	assert_true(p.buy_location("jupiter").contains("first") and "jupiter" not in p.known_locations, "Jupiter's charts need Mars's")
	assert_true(p.buy_location("mars") == "", "Mars bought")
	offered = p.brokers().map(func(l: Location) -> String: return l.id)
	assert_true(offered.has("jupiter") and offered.has("phobos") and offered.has("deimos") and not offered.has("saturn"), "then Phobos, Deimos, Jupiter")
	for id in ["jupiter", "saturn", "uranus", "neptune"]:
		assert_true(p.buy_location(id) == "", "%s in turn" % id)
	# A Frigate can pay for the longest jump.
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	var cost := p.jump_cost_kg("neptune", _catalog())
	var t := p.vessel_tanks(_catalog())
	print("    measured: Earth→Neptune %.0f M km, %.1f t of %.0f t + reserve %.0f t" % [Location.distance_m(Location.by_id("earth"), Location.by_id("neptune")) / 1e9,
		cost / 1000.0, float(t.capacity_kg) / 1000.0, float(t.reserve_capacity_kg) / 1000.0])
	assert_true(cost < float(t.capacity_kg) + float(t.reserve_capacity_kg), "Neptune is in reach of a Frigate's tanks")


func test_ground_and_air() -> void:
	for id in ["mercury", "phobos", "deimos"]:
		var b := Location.by_id(id).body
		var map := b.terrain()
		var h := map.height_at(Vector3(0.3, 0.5, 0.81).normalized()) if map != null else NAN
		assert_true(map != null and not b.has_atmosphere and absf(h) < b.entry_interface_altitude_m, "%s: ground to land on (%.0f m)" % [id, h])
	var mercury := Location.by_id("mercury").body.terrain()
	assert_true(mercury.width == 0, "Mercury: smooth ground with fine relief (no map)")
	for id in ["venus", "jupiter", "saturn", "uranus", "neptune"]:
		var b := Location.by_id(id).body
		assert_true(b.terrain() == null and b.has_atmosphere and b.entry_word() == "atmospheric entry", "%s: air, no ground" % id)
	# The ground view reaches the horizon, not round the back of a moon.
	var phobos := Location.by_id("phobos").body
	var r := phobos.radius_m
	var horizon := acos(r / (r + 2000.0))
	print("    measured: from 2 km over Phobos the horizon is %.0f° round (%.1f km)" % [rad_to_deg(horizon), r * horizon / 1000.0])
	assert_true(rad_to_deg(horizon) > 30.0 and rad_to_deg(horizon) < 60.0, "a small world's near horizon")


func test_saturns_rings() -> void:
	var saturn := Location.by_id("saturn").body
	var span := saturn.ring_span_m()
	var b_ring := saturn.ring_opacity(110_000_000.0)
	var cassini := saturn.ring_opacity(120_000_000.0)
	var encke := saturn.ring_opacity(133_700_000.0)
	print("    measured: rings %.0f–%.0f km; B %.2f, Cassini Division %.2f, Encke Gap %.2f" % [span.x / 1000.0, span.y / 1000.0, b_ring, cassini, encke])
	assert_true(saturn.has_rings() and span.x > saturn.radius_m and b_ring > 0.8 and cassini < 0.1 and encke == 0.0, "B ring bright, the gaps clear")
	var strip := PlanetSky.ring_strip(saturn)
	assert_true(strip.get_width() == PlanetSky.RING_STRIP_PX, "drawn from a strip")
	var start := Location.by_id("saturn")
	assert_true(start.start_radius_m() < span.x and start.start_inclination_deg > 10.0, "the station orbits below the rings, inclined to see them")
	assert_true(not Location.by_id("jupiter").body.has_rings(), "Jupiter's faint rings are not drawn")


func _height(map: TerrainMap, lat: float, lon_east: float) -> float:
	return map.mapped_height(lat, lon_east)


func test_the_moons_are_lumpy() -> void:
	var phobos := Location.by_id("phobos").body
	var map := phobos.terrain()
	assert_true(map != null and map.width == 360 and phobos.shape_mesh, "Phobos: Thomas's shape model, drawn as a mesh")
	# Its long axis points at Mars (0° and 180°), across it is narrower.
	var along := (_height(map, 0, 0) + _height(map, 0, 180)) * 0.5
	var across := (_height(map, 0, 90) + _height(map, 0, -90)) * 0.5
	# Stickney, 9 km across at 1° S 49° W: a floor below its raised rim.
	var floor_h := _height(map, -1, -54)
	var rim := _height(map, -1, -30)
	print("    measured: Phobos radius along the Mars line +%.0f m, across %+.0f m; Stickney floor %+.0f m, rim %+.0f m" % [along, across, floor_h, rim])
	assert_true(along > across + 700.0, "the long axis points at Mars")
	assert_true(rim > floor_h + 1500.0, "Stickney is a hollow in a raised rim (west longitudes read the right way)")
	var mesh := SmallBodyView.build_mesh(phobos, map)
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := 0
	var r_min := INF
	var r_max := 0.0
	for k in v.size():
		if n[k].dot(v[k]) > 0.0:
			outward += 1
		r_min = minf(r_min, v[k].length())
		r_max = maxf(r_max, v[k].length())
	print("    measured: mesh %d vertices, radius %.1f–%.1f km, %.1f %% of normals outward" % [v.size(), r_min / 1000.0, r_max / 1000.0, 100.0 * outward / v.size()])
	assert_true(r_min > 7000.0 and r_max < 15000.0 and r_max - r_min > 4000.0, "lumpy, not a sphere")
	assert_true(outward > v.size() * 0.97, "faces out")
	# The mesh is where the ground collision is.
	var dir := Vector3(0.2, -0.6, 0.4).normalized()
	var k := 0
	var best := -1.0
	for i in v.size():
		var d := v[i].normalized().dot(dir)
		if d > best:
			best = d
			k = i
	assert_true(absf(v[k].length() - (phobos.radius_m + map.height_at(v[k].normalized()))) < 1.0, "the mesh is the collision ground")
	var deimos := Location.by_id("deimos").body
	var dm := deimos.terrain()
	var lo := INF
	var hi := -INF
	for y in range(0, 180, 3):
		for x in range(0, 360, 3):
			lo = minf(lo, dm.pixel(x, y))
			hi = maxf(hi, dm.pixel(x, y))
	print("    measured: Deimos heights %+.0f … %+.0f m about 6.2 km" % [lo, hi])
	assert_true(deimos.shape_mesh and hi - lo > 3000.0, "Deimos too")
