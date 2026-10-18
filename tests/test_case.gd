class_name TestCase
extends RefCounted
## Base class for headless tests. Methods named `test_*` are run by
## tests/run_tests.gd. Each failure message states what was measured, the
## expected value and the actual value.

var _failures: PackedStringArray = PackedStringArray()


func begin_test() -> void:
	_failures.clear()


func failures() -> PackedStringArray:
	return _failures


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, what: String) -> void:
	if not condition:
		fail("%s — expected true, was false" % what)


func assert_near(actual: float, expected: float, tolerance: float, what: String) -> void:
	if not is_finite(actual) or absf(actual - expected) > tolerance:
		fail("%s — expected %s ± %s, actual %s" % [what, expected, tolerance, actual])


func assert_vec_near(actual: Vector3, expected: Vector3, tolerance: float, what: String) -> void:
	if not actual.is_finite() or actual.distance_to(expected) > tolerance:
		fail("%s — expected %s (±%s), actual %s" % [what, expected, tolerance, actual])


func assert_less_equal(actual: float, limit: float, what: String) -> void:
	if not is_finite(actual) or actual > limit:
		fail("%s — expected ≤ %s, actual %s" % [what, limit, actual])
