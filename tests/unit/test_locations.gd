extends TestCase
## Measures: locations (the map) — Earth and the Moon as data that
## validates, real lunar figures (μ, radius, low-orbit speed and period);
## the celestial frame generalised to any body, unchanged for Earth, with
## the Moon's IAU pole ~1.5° from the ecliptic pole and its 27.3-day spin;
## the Moon's shadow; profile schema 7 (where the vessel is docked, the
## locations known, the encounter size picked) with migration from v6; the
## other body in each sky (the Moon's position against Meeus's worked
## example and the 2024 eclipse and full moon; Earth from the Moon); the
## light each reflects onto the other by its phase (moonlight, earthlight).

const TEST_PROFILE := "user://test_locations_profile.json"
const EPOCH_UTC := "2026-10-19T12:00:00"


func _clean() -> void:
	for s in ["", ".bak", ".tmp", ".v6"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE + s))


func test_locations_are_valid_data() -> void:
	var ids := []
	for loc in Location.all():
		assert_true(loc.validate().is_empty(), "%s validates: %s" % [loc.id, ", ".join(loc.validate())])
		assert_true(loc.id not in ids, "ids are unique (%s)" % loc.id)
		assert_true(loc.body.surface_map != null, "%s has a surface map" % loc.id)
		ids.append(loc.id)
	assert_true(ids.slice(0, 3) == ["earth", "moon", "mars"] and ids.size() == 11,
		"Earth, the Moon and Mars first, then Milestone 16's eight (%s)" % [ids])
	assert_true(Location.by_id("pluto").id == "earth", "an unknown id falls back to Earth")
	var earth := Location.by_id("earth")
	assert_true(earth.station_name == "Earth Shipyard" and earth.start_altitude_m == 400_000.0 and earth.body.has_atmosphere,
		"Earth: the shipyard, 400 km, air")


func test_lunar_figures() -> void:
	var moon := Location.by_id("moon")
	var b := moon.body
	assert_near(b.mu_m3_s2, 4.902800118e12, 1e3, "lunar μ (m³/s², JPL DE440 GM 4902.800118 km³/s²)")
	assert_near(b.radius_m, 1_737_400.0, 0.0, "lunar mean radius (m)")
	assert_true(not b.has_atmosphere and b.entry_word() == "terrain impact", "airless: crossing the floor is a crash")
	# Selenean summit, the highest point: 10.8 km above the mean radius.
	assert_true(b.entry_interface_altitude_m > 10_786.0 and b.entry_interface_altitude_m < 15_000.0,
		"the floor clears the highest terrain (%.0f m)" % b.entry_interface_altitude_m)
	var r := moon.start_radius_m()
	var v := b.circular_speed(r)
	var period := TAU * sqrt(r * r * r / b.mu_m3_s2)
	print("    measured: 100 km lunar orbit %.1f m/s, period %.1f min (expected ~1633 m/s, ~118 min)" % [v, period / 60.0])
	assert_near(v, 1633.5, 1.0, "circular speed at 100 km (m/s)")
	assert_near(period / 60.0, 117.8, 0.5, "period at 100 km (min)")
	assert_true(moon.station_name == "Lunar Shipyard" and moon.start_altitude_m == 100_000.0, "the Lunar Shipyard, 100 km")


func test_frame_is_unchanged_for_earth() -> void:
	# Reference values from the Earth-only frame before it was generalised.
	var jd := CelestialFrame.julian_date_from_iso(EPOCH_UTC)
	var frames: Array[CelestialFrame] = [CelestialFrame.for_scenario(jd, 120.0),
		CelestialFrame.for_scenario(jd, 120.0, load("res://data/bodies/earth.tres"))]
	for f in frames:
		assert_near(f.twist, -0.624546327, 1e-7, "twist (rad)")
		var b := f.pci_to_body_fixed(1234.0)
		assert_vec_near(b.x, Vector3(0, 0, -1), 1e-6, "body-fixed basis x")
		assert_vec_near(b.y, Vector3(-0.35972562, 0.93305814, 0), 1e-6, "body-fixed basis y")
		assert_vec_near(b.z, Vector3(0.93305814, 0.35972562, 0), 1e-6, "body-fixed basis z")
		assert_vec_near(f.icrs_to_pci(Vector3(0.3, -0.5, 0.81).normalized()), Vector3(-0.8115842, 0.53678095, 0.23064566), 1e-6, "ICRS → PCI")


func test_moon_frame() -> void:
	var moon := Location.by_id("moon").body
	var f := CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso(EPOCH_UTC), 15.0, moon)
	var v := Vector3(0.3, -0.5, 0.81).normalized()
	assert_vec_near(f.pci_to_icrs(f.icrs_to_pci(v)), v, 1e-6, "ICRS → PCI → ICRS")
	assert_vec_near(f.north_pole_pci(), Vector3(-1, 0, 0), 1e-6, "the Moon's north is PCI −X (equatorial prograde start orbit)")
	var b := f.pci_to_body_fixed(1234.0)
	assert_vec_near(b * f.north_pole_pci(), Vector3(0, 0, 1), 1e-5, "pole → body-fixed +Z")
	assert_near(b.determinant(), 1.0, 1e-5, "a proper rotation")
	# The lunar pole sits ~1.54° from the ecliptic pole (Cassini's laws).
	var obliquity := deg_to_rad(23.439)
	var ecliptic_pole := Vector3(0, -sin(obliquity), cos(obliquity))
	var tilt := rad_to_deg(f.pole_icrs.angle_to(ecliptic_pole))
	print("    measured: lunar pole %.2f° from the ecliptic pole (expected ~1.54°)" % tilt)
	assert_near(tilt, 1.54, 0.1, "lunar pole to ecliptic pole (°)")
	# Synchronous rotation: once per 27.32-day sidereal month.
	var month := 360.0 / moon.rotation_deg_per_day * 86400.0
	assert_near(month / 86400.0, 27.3217, 0.001, "sidereal rotation period (days)")
	assert_vec_near(f.pci_to_body_fixed(1234.0 + month) * Vector3.UP, b * Vector3.UP, 1e-4, "the surface repeats after a sidereal month")
	var quarter := f.pci_to_body_fixed(1234.0 + month * 0.25) * Vector3.UP
	assert_near(rad_to_deg(quarter.angle_to(b * Vector3.UP)), 90.0, 0.1, "a quarter turn in a quarter month (°)")
	# Behind the Moon at 100 km: in its shadow.
	var sun := f.sun_direction_pci(0.0)
	var behind := Vec3d.from_vector3(-sun * float(moon.radius_m + 100_000.0))
	assert_near(CelestialFrame.sunlight_fraction(behind, sun, moon.radius_m), 0.0, 1e-6, "night side of the Moon is dark")


func test_schema_7_location_and_encounter_size() -> void:
	_clean()
	var fresh := PlayerProfile.new(1)
	assert_true(fresh.location == "earth" and fresh.known_locations == ["earth", "moon"] and fresh.encounter_size == 1,
		"a new player: docked at Earth, Earth and the Moon known, one ship")
	# A v6 save (no map fields) migrates: Earth, one ship; the original kept.
	var p := PlayerProfile.new(2)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	var d := p.to_dict()
	d.schema_version = 6
	for k in ["location", "known_locations", "encounter_size"]:
		d.erase(k)
	var f := FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = TEST_PROFILE
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	assert_true(q.loaded_schema == 6 and q.location == "earth" and q.encounter_size == 1 and q.known_locations == ["earth", "moon"],
		"a v6 save migrates to Earth, one ship (%s, %d)" % [q.location, q.encounter_size])
	assert_true(FileAccess.file_exists(TEST_PROFILE + ".v6"), "the v6 original is kept before migrating")
	# Round trip at v7.
	assert_true(q.relocate("moon") == "" and q.location == "moon", "relocate to a known location")
	assert_true(q.relocate("mars") != "" and q.location == "moon", "a location not on the map (no charts) is refused")
	q.encounter_size = 3
	q.save(TEST_PROFILE)
	var r := PlayerProfile.load_file(TEST_PROFILE, PackedStringArray())
	assert_true(r.loaded_schema == PlayerProfile.SCHEMA_VERSION and r.location == "moon" and r.encounter_size == 3,
		"saved and loaded at the current schema (%d)" % r.loaded_schema)
	# Bad values are clamped / fall back.
	var bad := PlayerProfile.from_dict({"schema_version": 7, "location": "atlantis", "encounter_size": 9, "known_locations": ["atlantis"]}, PackedStringArray())
	assert_true(bad.location == "earth" and bad.encounter_size == 3 and bad.known_locations == ["earth", "moon"],
		"unknown locations dropped, size clamped (%s, %d, %s)" % [bad.location, bad.encounter_size, bad.known_locations])
	_clean()


## Ecliptic longitude and latitude (°) of an ICRS vector.
func _ecliptic(v: Vector3, jd: float) -> Vector2:
	var eps := deg_to_rad(23.439 - 0.0000004 * (jd - CelestialFrame.J2000_JD))
	var e := Vector3(v.x, cos(eps) * v.y + sin(eps) * v.z, -sin(eps) * v.y + cos(eps) * v.z).normalized()
	return Vector2(fposmod(rad_to_deg(atan2(e.y, e.x)), 360.0), rad_to_deg(asin(e.z)))


func test_moon_position() -> void:
	# Meeus, Astronomical Algorithms, example 47.a: 1992-04-12 0h TD.
	var jd := 2448724.5
	var m := CelestialFrame.moon_geocentric_icrs(jd)
	var ecl := _ecliptic(m, jd)
	print("    measured: λ %.2f° β %.2f° Δ %.0f km (Meeus 133.16°, −3.23°, 368 410 km)" % [ecl.x, ecl.y, m.length() / 1000.0])
	assert_near(ecl.x, 133.163, 0.5, "lunar longitude (°)")
	assert_near(ecl.y, -3.229, 0.3, "lunar latitude (°)")
	assert_near(m.length() / 1000.0, 368_409.7, 1000.0, "Earth–Moon distance (km)")
	# 2024-04-08 18:18 UTC, mid total solar eclipse: the Moon in front of the Sun.
	var eclipse := CelestialFrame.julian_date_from_iso("2024-04-08T18:18:00")
	var e_sep := rad_to_deg(CelestialFrame.moon_geocentric_icrs(eclipse).angle_to(CelestialFrame.sun_direction_icrs(eclipse)))
	# 2024-04-23 23:49 UTC, full moon: opposite the Sun.
	var full := CelestialFrame.julian_date_from_iso("2024-04-23T23:49:00")
	var f_sep := rad_to_deg(CelestialFrame.moon_geocentric_icrs(full).angle_to(CelestialFrame.sun_direction_icrs(full)))
	print("    measured: Moon–Sun %.2f° at the 2024-04-08 eclipse, %.2f° at the 2024-04-23 full moon" % [e_sep, f_sep])
	assert_true(e_sep < 1.0, "eclipse: the Moon within 1° of the Sun (%.2f°)" % e_sep)
	assert_true(f_sep > 175.0, "full moon: the Moon opposite the Sun (%.2f°)" % f_sep)


func test_each_sky_shows_the_other_body() -> void:
	var earth := Location.by_id("earth")
	var moon := Location.by_id("moon")
	assert_true(earth.sky_body == moon.body and moon.sky_body == earth.body, "Earth orbit shows the Moon; lunar orbit shows Earth")
	var jd := CelestialFrame.julian_date_from_iso(EPOCH_UTC)
	var from_earth := CelestialFrame.for_scenario(jd, 15.0, earth.body)
	var from_moon := CelestialFrame.for_scenario(jd, 15.0, moon.body)
	var moon_seen := from_earth.position_of(moon.body, 600.0)
	var earth_seen := from_moon.position_of(earth.body, 600.0)
	# Vector3 is single precision: ~30 m at 400 000 km.
	assert_near(earth_seen.length(), moon_seen.length(), 100.0, "the same distance either way (m)")
	assert_vec_near(from_moon.pci_to_icrs(earth_seen.normalized()), -from_earth.pci_to_icrs(moon_seen.normalized()), 1e-5,
		"Earth from the Moon is exactly opposite the Moon from Earth")
	assert_true(moon_seen.length() > 356_000_000.0 and moon_seen.length() < 407_000_000.0,
		"the Moon is 356 000–407 000 km away (%.0f km)" % (moon_seen.length() / 1000.0))
	# Drawing a body through another frame matches its own frame.
	var own := from_earth.pci_to_body_fixed(1234.0)
	var via := from_earth.body_fixed_of(earth.body, 1234.0)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		assert_vec_near(via * axis, own * axis, 1e-5, "Earth's map through body_fixed_of matches its own frame")
	# Earth's map from the Moon: its north pole maps to Earth-fixed +Z.
	var b := from_moon.body_fixed_of(earth.body, 0.0)
	assert_vec_near(b * from_moon.icrs_to_pci(Vector3(0, 0, 1)), Vector3(0, 0, 1), 1e-5, "Earth's pole → its fixed +Z, seen from the Moon")


func test_moonlight_and_earthlight_follow_the_phase() -> void:
	var moon := Location.by_id("moon").body
	var earth := Location.by_id("earth").body
	var sun := Vector3(1, 0, 0)
	var mean_km := 384_400_000.0
	# Full Moon: the Sun behind the observer.
	var full := CelestialFrame.reflected_fraction(moon, Vector3(-mean_km, 0, 0), sun)
	var half := CelestialFrame.reflected_fraction(moon, Vector3(0, mean_km, 0), sun)
	var new := CelestialFrame.reflected_fraction(moon, Vector3(mean_km, 0, 0), sun)
	print("    measured: full Moon %s of sunlight (~%.2f lux of 127 000), half %.3f of full, new %s" % [
		String.num_scientific(full), full * 127_000.0, half / full, String.num_scientific(new)])
	assert_true(full > 1.5e-6 and full < 3.5e-6, "full-Moon light ~0.2–0.4 lux against ~127 000 lux of sun (%s)" % String.num_scientific(full))
	assert_true(half / full > 0.08 and half / full < 0.13, "a half Moon gives ~1/9 of full-Moon light (%.3f)" % (half / full))
	assert_true(new < full * 1e-3, "a new Moon gives (almost) none")
	# Full Earth seen from the Moon against full Moon seen from Earth.
	var full_earth := CelestialFrame.reflected_fraction(earth, Vector3(-mean_km, 0, 0), sun)
	print("    measured: full Earth from the Moon %.0f × full Moon from Earth" % (full_earth / full))
	assert_true(full_earth / full > 30.0 and full_earth / full < 70.0, "full Earth ~50 × full Moon (%.0f)" % (full_earth / full))
	# Shown: full Moon at NIGHT_LIGHT_FULL_MOON of the Sun, compressed by phase.
	assert_near(PlanetSky.perceived_light(full), PlanetSky.NIGHT_LIGHT_FULL_MOON, 0.005, "full-Moon light as shown")
	assert_true(PlanetSky.perceived_light(half) < PlanetSky.perceived_light(full) * 0.4, "a half Moon shows dimmer")
	assert_true(PlanetSky.perceived_light(full_earth) > PlanetSky.perceived_light(full) * 5.0, "earthlight shows far brighter than moonlight")
	# Below the horizon it lights nothing.
	var center := Vector3(0, -6_771_000.0, 0)
	assert_true(PlanetSky.below_horizon(center, 6_371_000.0, Vector3(0, -mean_km, 0)), "under the planet: below the horizon")
	assert_true(not PlanetSky.below_horizon(center, 6_371_000.0, Vector3(0, mean_km, 0)), "overhead: above it")
