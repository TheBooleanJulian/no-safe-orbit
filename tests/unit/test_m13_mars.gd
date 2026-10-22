extends TestCase
## Measures: Milestone 13 (part 2) — Sun-centred positions (Standish's
## elements) match published Earth–Mars distances, need double precision,
## and give Mars its own Sun; Mars as a location (gravity, rotation, air,
## shelves, traffic); information brokers sell locations; the jump to Mars
## is long but one full tank (with the reserve) covers it.


func _jd(iso: String) -> float:
	return CelestialFrame.julian_date_from_iso(iso)


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(9)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	return p


func test_mars_distances_match_published_approaches() -> void:
	# Closest approaches (NASA): 2018-07-31 57.59 Mkm, 2020-10-06 62.07 Mkm,
	# 2025-01-12 96.08 Mkm.
	for row in [["2018-07-31T07:50:00", 57.59e9], ["2020-10-06T14:18:00", 62.07e9], ["2025-01-12T12:00:00", 96.08e9]]:
		var d := CelestialFrame.separation_m(&"earth", &"mars", _jd(row[0]))
		print("    measured: %s Earth–Mars %.2f Mkm (published %.2f)" % [str(row[0]).left(10), d / 1e9, float(row[1]) / 1e9])
		assert_near(d / float(row[1]), 1.0, 0.003, "%s within 0.3 %%" % str(row[0]).left(10))
	var lo := INF
	var hi := 0.0
	for day in range(0, 687, 3):
		var r := CelestialFrame.heliocentric_icrs(&"mars", J2000() + day).length() / CelestialFrame.AU_M
		lo = minf(lo, r)
		hi = maxf(hi, r)
	print("    measured: Mars from the Sun %.3f–%.3f AU" % [lo, hi])
	assert_near(lo, 1.381, 0.003, "perihelion (AU)")
	assert_near(hi, 1.666, 0.003, "aphelion (AU)")


func J2000() -> float:
	return CelestialFrame.J2000_JD


func test_earths_sun_agrees_up_to_precession() -> void:
	# The Almanac Sun is of date, the elements are J2000: they differ by the
	# precession since J2000 (50.3″ a year), nothing more.
	for iso in ["2001-03-01T00:00:00", "2026-10-19T12:00:00"]:
		var jd := _jd(iso)
		var almanac := CelestialFrame.sun_direction_icrs(jd)
		var kepler := CelestialFrame.heliocentric_icrs(&"earth", jd).times(-1.0).normalized().to_vector3()
		var precession := 50.29 / 3600.0 * (jd - J2000()) / 365.25
		var diff := rad_to_deg(almanac.angle_to(kepler))
		print("    measured: %s Sun almanac vs elements %.3f° (precession %.3f°)" % [iso.left(10), diff, precession])
		assert_near(diff, precession, 0.06, "the difference is the precession (deg)")


func test_sun_centred_positions_need_doubles() -> void:
	var jd := _jd(Main.SCENARIO_EPOCH_UTC)
	var mars := CelestialFrame.heliocentric_icrs(&"mars", jd)
	var ship := Vec3d.new(3_689_500.0, 1234.5, -987.25)  # low Mars orbit, relative to Mars
	var back := mars.plus(ship).minus(mars)
	var err_d := back.minus(ship).length()
	var mv := mars.to_vector3()
	var err_f := Vec3d.from_vector3((mv + ship.to_vector3()) - mv).minus(ship).length()
	print("    measured: a ship 3,690 km from Mars, %.0f M km from the Sun: Vec3d error %s m, Vector3 error %.0f m" % [mars.length() / 1e9, String.num_scientific(err_d), err_f])
	assert_true(err_d < 1e-3, "doubles keep the ship's position to a millimetre")
	assert_true(err_f > 100.0, "single-precision Vector3 would not")


func test_mars_is_a_place() -> void:
	var mars := Location.by_id("mars")
	assert_true(mars.id == "mars" and mars.validate().is_empty(), "Mars validates: %s" % [mars.validate()])
	var b := mars.body
	var v := b.circular_speed(mars.start_radius_m())
	var period := TAU * mars.start_radius_m() / v
	print("    measured: low Mars orbit %.0f km: %.0f m/s, %.1f min; entry interface %.0f km" % [mars.start_altitude_m / 1000.0, v, period / 60.0, b.entry_interface_altitude_m / 1000.0])
	assert_near(v, 3407.0, 5.0, "circular speed (m/s)")
	assert_near(period / 60.0, 113.4, 0.5, "period (min)")
	assert_true(b.has_atmosphere and not b.clouds_and_seas and b.air_color.r > b.air_color.b, "thin, dusty air: no clouds or seas, a warm haze")
	assert_near(b.rotation_deg_per_day, 350.892, 0.001, "a sol of 24 h 37 min (deg/day)")
	# Its own Sun: the frame puts the Sun where the scenario asks.
	var jd := _jd(Main.SCENARIO_EPOCH_UTC)
	var frame := CelestialFrame.for_scenario(jd, 120.0, b)
	var s := frame.sun_direction_pci(0.0)
	assert_near(rad_to_deg(atan2(s.z, s.y)), 120.0, 0.01, "the Sun sits at the scenario's angle (deg)")
	var from_mars := CelestialFrame.sun_direction_from(&"mars", jd)
	var from_earth := CelestialFrame.sun_direction_from(&"earth", jd)
	print("    measured: the Sun seen from Mars is %.1f° from where Earth sees it" % rad_to_deg(from_mars.angle_to(from_earth)))
	assert_true(from_mars.angle_to(from_earth) > deg_to_rad(5.0), "and it is Mars's Sun, not Earth's")


func test_brokers_sell_the_charts() -> void:
	var p := _profile()
	var mars := Location.by_id("mars")
	for loc in Location.all():
		assert_true(loc.id in PlayerProfile.STARTING_LOCATIONS or loc.broker_price > 0, "%s is known or sold" % loc.id)
	assert_true(mars in p.brokers() and p.brokers().all(func(l: Location) -> bool: return l.charts_after == ""), "a new player can buy Mars (and Mercury, Venus: no charts needed first)")
	p.credits = mars.broker_price - 1
	assert_true(p.buy_location("mars") != "" and "mars" not in p.known_locations, "too few credits: refused")
	p.credits = mars.broker_price + 100
	assert_true(p.buy_location("mars") == "" and "mars" in p.known_locations and p.credits == 100, "bought: on the map")
	assert_true(mars not in p.brokers() and p.buy_location("mars") != "", "Mars isn't sold twice")
	var cost := p.jump_cost_kg("mars", ConstructionCatalog.default_catalog())
	var t := p.vessel_tanks(ConstructionCatalog.default_catalog())
	print("    measured: Earth→Mars %.0f M km: the Frigate burns %.1f t (tanks %.0f t + reserve %.0f t); the Moon %.1f t" % [
		Location.distance_m(Location.by_id("earth"), mars) / 1e9, cost / 1000.0, float(t.capacity_kg) / 1000.0,
		float(t.reserve_capacity_kg) / 1000.0, p.jump_cost_kg("moon", ConstructionCatalog.default_catalog()) / 1000.0])
	assert_true(cost > p.jump_cost_kg("moon", ConstructionCatalog.default_catalog()) * 1.5 and cost < float(t.capacity_kg), "long, but a full tank covers it")
	assert_true(p.relocate("mars") == "" and p.location == "mars", "and the vessel jumps there")
	var s := p.to_dict()
	var q := PlayerProfile.from_dict(s, PackedStringArray())
	assert_true(q != null and "mars" in q.known_locations and q.location == "mars", "the charts and the berth are saved")
	ContractBoard.refresh(q)
	var mars_offers := false
	for i in 12:
		q.board_seed += 1
		for c in ContractBoard.generate(q):
			mars_offers = mars_offers or str(c.location) == "mars"
	assert_true(mars_offers, "contracts now go to Mars too")


func test_mars_traffic_and_shelves() -> void:
	var mars := Location.by_id("mars")
	var seen := {}
	for m in range(1, 20):
		for i in 3:
			seen[mars.enemy_template(m, i)] = true
	print("    measured: Martian traffic %s, threat +%d; shelves %d items up to %s at ×%.1f" % [", ".join(seen.keys()), mars.threat_bonus,
		mars.vendor_stock_size, Rarity.NAMES[mars.vendor_max_rarity], mars.price_factor])
	assert_true(seen.has("destroyer_mk1.json") and seen.has("frigate_mk1.json"), "destroyers among the frigates")
	var cat := ConstructionCatalog.default_catalog()
	var bp := EnemyFactory.design(8, BlueprintIO.load_file("res://data/blueprints/destroyer_mk1.json", PackedStringArray()), cat, 0)
	assert_true(not ShipValidator.validate(bp, cat).has_errors() and bp.name.ends_with("-class destroyer"), "an armed destroyer (%s)" % bp.name)
	var p := _profile()
	p.location = "mars"
	p.refresh_station(cat)
	assert_true(p.vendor_stock.size() == mars.vendor_stock_size, "a deeper quartermaster")
