extends TestCase
## Measures: real-sky ephemeris (Julian date, Sun position, sidereal time)
## against published worked examples, and the ICRS ↔ PCI ↔ Earth-fixed
## mapping (pole, prograde start orbit, Sun placement, round trips).


func test_julian_date() -> void:
	assert_near(CelestialFrame.julian_date_from_iso("2000-01-01T12:00:00"), 2451545.0, 1e-6, "JD of J2000.0")
	assert_near(CelestialFrame.julian_date_from_iso("1987-04-10T00:00:00"), 2446895.5, 1e-6, "JD of 1987-04-10 0h (Meeus ex. 12.a)")


func test_sidereal_time_matches_meeus_example() -> void:
	# Meeus, Astronomical Algorithms ex. 12.a: 1987-04-10 0h UT → GMST 13h10m46.3668s.
	var expected := deg_to_rad((13.0 + 10.0 / 60.0 + 46.3668 / 3600.0) * 15.0)
	assert_near(CelestialFrame.gmst_rad(2446895.5), expected, deg_to_rad(0.001), "GMST (rad)")


func test_sun_position_matches_meeus_example() -> void:
	# Meeus ex. 25.a: 1992-10-13 0h TD → apparent RA 198.38083°, Dec −7.78507°.
	var s := CelestialFrame.sun_direction_icrs(2448908.5)
	var ra := fposmod(rad_to_deg(atan2(s.y, s.x)), 360.0)
	var dec := rad_to_deg(asin(s.z))
	assert_near(ra, 198.38083, 0.05, "Sun RA (°)")
	assert_near(dec, -7.78507, 0.05, "Sun Dec (°)")


func test_pole_and_prograde_start_orbit() -> void:
	var f := CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso("2026-10-19T12:00:00"), 15.0)
	assert_vec_near(f.north_pole_pci(), Vector3(-1, 0, 0), 1e-6, "celestial north along PCI −X")
	# Start point +Y moving −Z: angular momentum Y × (−Z) = −X = north → prograde.
	assert_vec_near(Vector3.UP.cross(Vector3.FORWARD), f.north_pole_pci(), 1e-6, "start orbit is prograde")
	# Polaris (Dec +89.26°) is within a degree of the pole.
	var polaris := f.icrs_to_pci(CelestialFrame.radec_to_icrs(37.95291, 89.26417))
	assert_true(polaris.angle_to(f.north_pole_pci()) < deg_to_rad(1.0), "Polaris near the pole")


func test_sun_placed_where_the_scenario_asks() -> void:
	var f := CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso("2026-10-19T12:00:00"), 15.0)
	var s := f.sun_direction_pci(0.0)
	assert_near(rad_to_deg(atan2(s.z, s.y)), 15.0, 1e-4, "Sun's in-plane angle from the start zenith (°)")
	# Mid-October the Sun is ~10° south: PCI +X component = −sin(dec) > 0.
	assert_true(s.x > 0.1 and s.x < 0.25, "Sun ~10° south of the equator (x = %.3f)" % s.x)


func test_eclipse_geometry_and_timing() -> void:
	var earth: OrbitalBody = load("res://data/bodies/earth.tres")
	var R := earth.radius_m
	var r := R + 400_000.0
	var sun := Vector3(0, 1, 0)  # in the orbit plane, straight "up" from the start point
	assert_near(CelestialFrame.sunlight_fraction(Vec3d.new(0, r, 0), sun, R), 1.0, 0.0, "sub-solar point lit")
	assert_near(CelestialFrame.sunlight_fraction(Vec3d.new(0, -r, 0), sun, R), 0.0, 0.0, "anti-solar point in shadow")
	assert_near(CelestialFrame.sunlight_fraction(Vec3d.new(R * 1.2, -r, 0), sun, R), 1.0, 0.0, "behind Earth but outside the shadow cylinder")
	# Circular 400 km orbit, Sun in plane: shadow spans 2·asin(R/r) of the orbit.
	var orbit := OrbitElements.from_state(earth.mu_m3_s2, Vec3d.new(0, r, 0), Vec3d.new(0, 0, -sqrt(earth.mu_m3_s2 / r)))
	var sunset := CelestialFrame.next_light_change(orbit, sun, R)
	assert_true(not sunset.is_empty() and not sunset.sunlit_after, "next change from noon is sunset")
	var expected_shadow := 2.0 * asin(R / r) / TAU * orbit.period
	# Sunset is at angle 90° + (90° − shadow half-angle) ahead of noon.
	var expected_sunset := (PI - asin(R / r)) / TAU * orbit.period
	assert_near(sunset.time, expected_sunset, 2.0, "time to sunset from orbital noon (s)")
	assert_near(expected_shadow / 60.0, 36.0, 1.0, "≈36 min of a 92 min LEO orbit is eclipse (min)")


func test_star_catalogue_contents() -> void:
	var stars := Starfield.load_catalog(Starfield.CATALOG)
	assert_true(stars.size() == 9096, "Bright Star Catalogue entries with positions (got %d)" % stars.size())
	var brightest := stars[0]
	for s in stars:
		if s.z < brightest.z:
			brightest = s
	assert_vec_near(Vector3(brightest.x, brightest.y, brightest.z), Vector3(101.287, -16.716, -1.46), 0.01,
		"brightest star is Sirius (RA °, Dec °, V)")
	# Dubhe (HR 4301) and Merak (HR 4295), the Big Dipper's pointers: 5.37° apart.
	var dubhe := CelestialFrame.radec_to_icrs(165.93196, 61.75103)
	var merak := CelestialFrame.radec_to_icrs(165.46033, 56.38242)
	assert_near(rad_to_deg(dubhe.angle_to(merak)), 5.37, 0.02, "Dubhe–Merak separation (°)")
	var found := 0
	for s in stars:
		if (absf(s.x - 165.932) < 0.01 and absf(s.y - 61.751) < 0.01) or (absf(s.x - 165.460) < 0.01 and absf(s.y - 56.382) < 0.01):
			found += 1
	assert_true(found == 2, "Dubhe and Merak present in the catalogue")
	# Magnitude mapping: brighter is bigger and brighter; colour from B−V.
	assert_true(Starfield.intensity(0.0) > Starfield.intensity(2.0) and Starfield.intensity(2.0) > Starfield.intensity(6.0),
		"intensity falls with magnitude")
	var blue := Starfield.color_from_bv(-0.2)
	var red := Starfield.color_from_bv(1.8)
	assert_true(blue.b > blue.r and red.r > red.b, "hot stars blue-white, cool stars orange")


func test_frame_round_trips() -> void:
	var f := CelestialFrame.for_scenario(2461000.25, -40.0)
	var v := Vector3(0.3, -0.5, 0.81).normalized()
	assert_vec_near(f.pci_to_icrs(f.icrs_to_pci(v)), v, 1e-6, "ICRS → PCI → ICRS")
	# Earth-fixed basis: the pole maps to ECEF +Z; the basis is a rotation.
	var b := f.pci_to_ecef(1234.0)
	assert_vec_near(b * f.north_pole_pci(), Vector3(0, 0, 1), 1e-5, "pole → ECEF +Z")
	assert_near(b.determinant(), 1.0, 1e-5, "ECEF basis is a proper rotation")
	# One sidereal day later Earth has turned once.
	var day := TAU / CelestialFrame.EARTH_ROTATION_RAD_S
	assert_vec_near(f.pci_to_ecef(1234.0 + day) * Vector3.UP, b * Vector3.UP, 1e-4, "Earth-fixed frame repeats after a sidereal day")
	var quarter := f.pci_to_ecef(1234.0 + day * 0.25) * Vector3.UP
	assert_near(rad_to_deg(quarter.angle_to(b * Vector3.UP)), 90.0, 0.1, "Earth turns 90° in a quarter sidereal day (°)")
