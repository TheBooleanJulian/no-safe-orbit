extends TestCase
## Measures: in-game rebinding — replace one binding kind, keep the other,
## save/load round trip, reset to project defaults; gamepad defaults exist.

const TEST_PATH := "user://test_input_bindings.cfg"


func _cleanup() -> void:
	InputBindings.reset(TEST_PATH)


func test_rebind_keeps_the_other_kind() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_I
	var pad_before := InputBindings.describe(&"thrust_forward", InputBindings.Kind.GAMEPAD)
	InputBindings.rebind(&"thrust_forward", key)
	assert_true(InputBindings.describe(&"thrust_forward", InputBindings.Kind.KEYBOARD_MOUSE) == "I",
		"keyboard binding now I (got %s)" % InputBindings.describe(&"thrust_forward", InputBindings.Kind.KEYBOARD_MOUSE))
	assert_true(InputBindings.describe(&"thrust_forward", InputBindings.Kind.GAMEPAD) == pad_before and pad_before != "—",
		"gamepad binding untouched (%s)" % pad_before)
	_cleanup()
	assert_true(InputBindings.describe(&"thrust_forward", InputBindings.Kind.KEYBOARD_MOUSE) == "W", "reset restores W")


func test_saved_bindings_survive_a_restart() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	InputBindings.rebind(&"fire", key)
	assert_true(InputBindings.save(TEST_PATH) == OK, "bindings saved")
	InputMap.load_from_project_settings()  # as if the game restarted
	InputBindings.apply_saved(TEST_PATH, true)
	assert_true(InputBindings.describe(&"fire", InputBindings.Kind.KEYBOARD_MOUSE) == "K", "saved fire key K re-applied")
	_cleanup()
	assert_true(not FileAccess.file_exists(TEST_PATH), "reset deletes the saved file")


func test_capturing_ignores_releases_and_small_deflections() -> void:
	var small := InputEventJoypadMotion.new()
	small.axis = JOY_AXIS_LEFT_X
	small.axis_value = 0.3
	assert_true(InputBindings.binding_from(small) == null, "small stick deflection is not a binding")
	var big := InputEventJoypadMotion.new()
	big.axis = JOY_AXIS_RIGHT_Y
	big.axis_value = -0.9
	var b := InputBindings.binding_from(big) as InputEventJoypadMotion
	assert_true(b != null and b.axis == JOY_AXIS_RIGHT_Y and b.axis_value == -1.0, "full deflection captured as axis −")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_J
	release.pressed = false
	assert_true(InputBindings.binding_from(release) == null, "key release is not a binding")


func test_every_flight_action_has_gamepad_default() -> void:
	var missing := PackedStringArray()
	for entry in InputBindings.ACTIONS:
		# Keyboard-only by design: releasing the mouse, and the information
		# panel toggles (on a gamepad the Tab overview covers them).
		if entry[0] in [&"release_mouse", &"toggle_orbit_panel", &"toggle_details", &"toggle_help"]:
			continue
		if InputBindings.describe(entry[0], InputBindings.Kind.GAMEPAD) == "—":
			missing.append(String(entry[0]))
	assert_true(missing.is_empty(), "actions without a gamepad default: %s" % ", ".join(missing))
