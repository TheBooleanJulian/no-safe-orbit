extends TestCase
## Measures: HUD unit formatting, so readouts never mislabel units or sign.


func test_distance_switches_units() -> void:
	assert_true(HudFormat.distance(850.0) == "850 m", "850 m → '%s'" % HudFormat.distance(850.0))
	assert_true(HudFormat.distance(2140.0) == "2.14 km", "2140 m → '%s'" % HudFormat.distance(2140.0))
	assert_true(HudFormat.distance(250_000.0) == "250 km", "250 km → '%s'" % HudFormat.distance(250_000.0))


func test_closure_wording_follows_range_rate_sign() -> void:
	assert_true(HudFormat.closure(-12.0) == "CLOSING", "negative range rate reads CLOSING")
	assert_true(HudFormat.closure(12.0) == "OPENING", "positive range rate reads OPENING")
	assert_true(HudFormat.closure(0.0) == "STEADY", "zero range rate reads STEADY")


func test_clock_and_signed_speed() -> void:
	assert_true(HudFormat.clock(3725.9) == "01:02:05", "3725.9 s → '%s'" % HudFormat.clock(3725.9))
	assert_true(HudFormat.signed_speed(3.0) == "+3.0 m/s", "explicit plus sign → '%s'" % HudFormat.signed_speed(3.0))
