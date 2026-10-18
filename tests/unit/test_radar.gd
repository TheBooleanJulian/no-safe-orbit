extends TestCase
## Measures: flat-radar geometry (bearing, elevation, plot position, range
## scale) and orbital HUD formatting.


func test_bearing_follows_body_axes() -> void:
	assert_near(RadarMath.bearing_deg(Vector3(0, 0, -100)), 0.0, 1e-4, "dead ahead bearing (°)")
	assert_near(RadarMath.bearing_deg(Vector3(100, 0, 0)), 90.0, 1e-4, "right bearing (°)")
	assert_near(RadarMath.bearing_deg(Vector3(-100, 0, 0)), -90.0, 1e-4, "left bearing (°)")
	assert_near(absf(RadarMath.bearing_deg(Vector3(0, 0, 100))), 180.0, 1e-4, "astern bearing (°)")


func test_elevation_above_and_below() -> void:
	assert_near(RadarMath.elevation_deg(Vector3(0, 100, -100)), 45.0, 1e-4, "45° above (°)")
	assert_near(RadarMath.elevation_deg(Vector3(0, -50, 0)), -90.0, 1e-4, "straight below (°)")
	assert_near(RadarMath.elevation_deg(Vector3(30, 0, -40)), 0.0, 1e-4, "level contact (°)")


func test_plot_scales_and_clamps_to_ring() -> void:
	var p := RadarMath.plot(Vector3(500, 999, -1000), 2000.0)
	assert_true(p.is_equal_approx(Vector2(0.25, -0.5)), "plot ignores height, ahead is −y: %s" % p)
	var far := RadarMath.plot(Vector3(0, 0, -9000), 2000.0)
	assert_true(far.is_equal_approx(Vector2(0, -1)), "out-of-range contact clamps to ring: %s" % far)


func test_nice_scale_steps() -> void:
	assert_near(RadarMath.nice_scale(2600.0), 5000.0, 0.0, "2.6 km contact → 5 km scale")
	assert_near(RadarMath.nice_scale(700.0), 1000.0, 0.0, "0.7 km contact → 1 km minimum scale")
	assert_near(RadarMath.nice_scale(12_000.0), 20_000.0, 0.0, "12 km contact → 20 km scale")


func test_duration_and_altitude_format() -> void:
	assert_true(HudFormat.duration(754.9) == "12:34", "754.9 s → '%s'" % HudFormat.duration(754.9))
	assert_true(HudFormat.duration(5544.9) == "1:32:24", "5544.9 s → '%s'" % HudFormat.duration(5544.9))
	assert_true(HudFormat.duration(NAN) == "—", "unknown duration → '—'")
	assert_true(HudFormat.altitude(412_345.0) == "412.3 km", "altitude → '%s'" % HudFormat.altitude(412_345.0))
	assert_true(HudFormat.altitude(INF) == "—", "unbounded altitude → '—'")
