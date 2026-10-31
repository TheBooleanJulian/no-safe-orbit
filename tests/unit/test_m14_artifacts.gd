extends TestCase
## Measures: Milestone 14 (part 1) — real objects from NASA/JPL Horizons at
## the scenario epoch: their states match what is known of their orbits;
## the frame takes them in double precision; surveys are picked from where
## they can be flown, deep-space round trips must fit the tanks, the fee is
## paid once and the record kept; v9 saves load with an empty codex.

const AU := CelestialFrame.AU_M


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(21)
	p.ensure_vessel(BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()))
	return p


func _cat() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


## Inclination (deg) of an artifact's orbit to its body's equator.
func _inclination(a: Artifact) -> float:
	var st := a.state_icrs()
	var h := st[0].cross(st[1]).normalized().to_vector3()
	var body := a.location().body
	var pole: Vector3 = CelestialFrame.orientation(body, CelestialFrame.julian_date_from_iso(a.epoch_utc))[0]
	return rad_to_deg(h.angle_to(pole))


func test_every_artifact_is_recorded() -> void:
	assert_true(Artifact.all().size() == 11, "eleven objects")
	var attribution := FileAccess.get_file_as_string("res://data/ATTRIBUTION.md")
	for a in Artifact.all():
		assert_true(a.validate().is_empty(), "%s validates: %s" % [a.id, a.validate()])
		assert_true(a.epoch_utc == Main.SCENARIO_EPOCH_UTC, "%s is at the scenario epoch" % a.id)
		assert_true(attribution.contains(a.horizons_source), "%s's source is in ATTRIBUTION.md" % a.id)
	assert_true(Artifact.by_id("jwst") == null, "JWST (at L2, needs a rotating frame) is left out")


func test_states_match_the_known_orbits() -> void:
	var iss := Artifact.by_id("iss")
	var r := iss.state_icrs()
	var alt := (r[0].length() - 6_371_000.0) / 1000.0
	print("    measured: ISS %.0f km up at %.2f km/s, inclined %.2f°; Hubble %.2f°" % [alt, r[1].length() / 1000.0, _inclination(iss), _inclination(Artifact.by_id("hubble"))])
	assert_true(alt > 400.0 and alt < 440.0, "the ISS is ~420 km up")
	assert_near(_inclination(iss), 51.64, 0.5, "and inclined 51.6° (deg; the frame ignores precession)")
	assert_near(_inclination(Artifact.by_id("hubble")), 28.47, 0.5, "Hubble 28.5° (deg)")
	for id in ["mro", "odyssey"]:
		var m := Artifact.by_id(id)
		var inc := _inclination(m)
		print("    measured: %s %.0f km above Mars, inclined %.1f°" % [id, (m.state_icrs()[0].length() - 3_389_500.0) / 1000.0, inc])
		assert_true(inc > 85.0 and inc < 95.0, "%s is in a near-polar orbit" % id)
	var sun_mu := (load("res://data/bodies/sun.tres") as OrbitalBody).mu_m3_s2
	var car := Artifact.by_id("roadster").state_icrs()
	var el := OrbitElements.from_state(sun_mu, car[0], car[1])
	var peri := el.semi_major_axis * (1.0 - el.eccentricity) / AU
	var apo := el.semi_major_axis * (1.0 + el.eccentricity) / AU
	print("    measured: Roadster a %.3f AU, e %.3f, %.3f–%.3f AU" % [el.semi_major_axis / AU, el.eccentricity, peri, apo])
	assert_near(peri, 0.986, 0.01, "Roadster perihelion (AU)")
	assert_near(apo, 1.66, 0.02, "Roadster aphelion (AU)")
	var v1 := Artifact.by_id("voyager1").state_icrs()
	var energy := 0.5 * v1[1].length() * v1[1].length() - sun_mu / v1[0].length()
	print("    measured: Voyager 1 %.1f AU from the Sun at %.2f km/s" % [v1[0].length() / AU, v1[1].length() / 1000.0])
	assert_near(v1[0].length() / AU, 172.0, 2.0, "Voyager 1 ~172 AU out (AU)")
	assert_true(energy > 0.0, "on an escape path")


func test_the_frame_takes_them_in_doubles() -> void:
	var frame := CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso(Main.SCENARIO_EPOCH_UTC), 15.0, null)
	var small := Vec3d.new(1234.5, -987.25, 4321.0)
	var a := frame.icrs_to_pci_d(small).to_vector3()
	var b := frame.icrs_to_pci(small.to_vector3())
	assert_true(a.distance_to(b) < 1e-3, "icrs_to_pci_d agrees with icrs_to_pci")
	var v1 := Artifact.by_id("voyager1").state_icrs()[0]
	var shift := v1.plus(Vec3d.new(0, 0, 3000.0))
	var gap := frame.icrs_to_pci_d(shift).minus(frame.icrs_to_pci_d(v1)).length()
	print("    measured: 3 km at Voyager 1 survives the rotation as %.6f km" % (gap / 1000.0))
	assert_near(gap, 3000.0, 1e-3, "a 3 km offset at 172 AU is kept to a millimetre (m)")


func test_surveys_are_picked_where_they_can_be_flown() -> void:
	var p := _profile()
	assert_true(p.choose_survey("iss", _cat()) == "" and p.survey_target == "iss", "the ISS from Earth: yes")
	var why := p.choose_survey("lro", _cat())
	assert_true(why.contains("Lunar Shipyard") and p.survey_target == "iss", "LRO from Earth: jump to the Moon first")
	p.jump_target = "moon"
	assert_true(p.choose_survey("lro", _cat()) == "" and p.survey_target == "lro", "with a course for the Moon: yes")
	p.jump_target = ""
	p.survey_target = "iss"
	var t := p.vessel_tanks(_cat())
	var room := float(t.capacity_kg) + float(t.reserve_capacity_kg)
	for id in ["roadster", "new_horizons", "voyager1"]:
		var a := Artifact.by_id(id)
		var need := p.survey_cost_kg(a, _cat())
		var full_mass := float(t.mass_kg) - float(t.main_kg) - float(t.reserve_kg) + room
		print("    measured: %s round trip %.0f t for the Frigate (%.0f t of tank + reserve): %.0f %% of the ship's mass in propellant" % [
			id, need / 1000.0, room / 1000.0, 100.0 * need / full_mass])
	var refused := p.choose_survey("voyager1", _cat())
	print("    measured: Voyager 1 round trip %s; the Frigate carries %s full — %s" % [JumpDrive.dv_text(p.survey_dv(Artifact.by_id("voyager1"))),
		JumpDrive.dv_text(t.dv_full_mps), refused])
	assert_true(refused.contains("more Δv") and p.survey_target == "iss", "Voyager 1 is beyond a Frigate: refused with the reason")
	assert_true(p.choose_survey("", _cat()) == "" and p.survey_target == "", "and a survey can be cancelled")


func test_a_survey_pays_once_and_keeps_the_record() -> void:
	var p := _profile()
	var before := p.credits
	var fee := Artifact.by_id("hubble").survey_credits
	assert_true(p.complete_survey("hubble") == fee and p.credits == before + fee and p.codex.has("hubble"), "surveyed: fee paid, record kept")
	assert_true(p.complete_survey("hubble") == 0 and p.credits == before + fee, "again: no second fee")
	p.survey_target = "iss"
	var q := PlayerProfile.from_dict(p.to_dict(), PackedStringArray())
	assert_true(q.codex.has("hubble") and q.survey_target == "iss", "codex and target saved")
	var d := p.to_dict()
	d.survey_target = "jwst"
	d.codex = {"hubble": 1, "nothing": 2}
	var r := PlayerProfile.from_dict(d, PackedStringArray())
	assert_true(r.survey_target == "" and r.codex.keys() == ["hubble"], "unknown objects are dropped on load")


func test_schema_10_migration() -> void:
	var path := "user://test_m14_profile.json"
	for s in ["", ".bak", ".tmp", ".v9"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var d := _profile().to_dict()
	d.schema_version = 9
	d.erase("survey_target")
	d.erase("codex")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	assert_true(q.loaded_schema == 9 and q.codex.is_empty() and q.survey_target == "", "a v9 save: nothing surveyed")
	assert_true(FileAccess.file_exists(path + ".v9"), "the v9 original is kept")
	q.complete_survey("iss")
	q.save(path)
	var r := PlayerProfile.load_file(path, PackedStringArray())
	assert_true(r.loaded_schema == PlayerProfile.SCHEMA_VERSION and PlayerProfile.SCHEMA_VERSION >= 10 and r.codex.has("iss"), "saved at the current schema (10 or later) with the codex")
	for s in ["", ".bak", ".tmp", ".v9"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
