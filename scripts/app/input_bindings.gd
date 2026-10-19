class_name InputBindings
extends RefCounted
## Player-rebindable controls. Defaults are project.godot's InputMap; changes
## are saved to user://input_bindings.cfg and re-applied at startup. Each
## action has one keyboard/mouse binding and one gamepad binding; rebinding
## replaces the binding of the same kind and keeps the other.

const SAVE_PATH := "user://input_bindings.cfg"
## Joystick deflection that counts as "this axis" when rebinding.
const AXIS_CAPTURE := 0.6

## [action, label] in display order.
const ACTIONS := [
	[&"thrust_forward", "Main engine (forward)"],
	[&"thrust_backward", "Reverse thrust"],
	[&"strafe_left", "Strafe left"],
	[&"strafe_right", "Strafe right"],
	[&"thrust_up", "Thrust up"],
	[&"thrust_down", "Thrust down"],
	[&"pitch_up", "Pitch up"],
	[&"pitch_down", "Pitch down"],
	[&"yaw_left", "Yaw left"],
	[&"yaw_right", "Yaw right"],
	[&"roll_left", "Roll left"],
	[&"roll_right", "Roll right"],
	[&"fire", "Fire cannon"],
	[&"toggle_flight_assist", "Flight assist on/off"],
	[&"toggle_velocity_hold", "Hold orbit / match target"],
	[&"restart_scenario", "Restart scenario"],
	[&"open_shipyard", "Open shipyard"],
	[&"toggle_target_ai", "Target hostile on/off"],
	[&"salvage", "Salvage disabled target"],
	[&"field_repair", "Damage control (workshop repair)"],
	[&"dock", "Extend / release gangway"],
	[&"board", "Send boarders / withdraw"],
	[&"release_mouse", "Release mouse"],
	[&"toggle_controls", "Controls panel"],
]

enum Kind { KEYBOARD_MOUSE, GAMEPAD, NONE }

static var _applied := false


## Apply saved bindings once per run (`force` re-applies, for tests).
static func apply_saved(path: String = SAVE_PATH, force: bool = false) -> void:
	if _applied and not force:
		return
	_applied = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action) or not cfg.has_section_key("bindings", action):
			continue
		var events: Variant = cfg.get_value("bindings", action)
		if events is Array:
			InputMap.action_erase_events(action)
			for ev in events:
				if ev is InputEvent:
					InputMap.action_add_event(action, ev)


static func save(path: String = SAVE_PATH) -> Error:
	var cfg := ConfigFile.new()
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if InputMap.has_action(action):
			cfg.set_value("bindings", action, InputMap.action_get_events(action))
	return cfg.save(path)


## Restore project defaults and forget saved changes.
static func reset(path: String = SAVE_PATH) -> void:
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func kind_of(event: InputEvent) -> Kind:
	if event is InputEventKey or event is InputEventMouseButton:
		return Kind.KEYBOARD_MOUSE
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return Kind.GAMEPAD
	return Kind.NONE


## A clean, storable binding from a captured event, or null if it isn't one
## (releases, small stick deflections, mouse motion).
static func binding_from(event: InputEvent) -> InputEvent:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := InputEventKey.new()
		k.physical_keycode = (event as InputEventKey).physical_keycode
		if k.physical_keycode == KEY_NONE:
			k.physical_keycode = (event as InputEventKey).keycode
		return k
	if event is InputEventMouseButton and event.pressed:
		var mb := InputEventMouseButton.new()
		mb.button_index = (event as InputEventMouseButton).button_index
		return mb
	if event is InputEventJoypadButton and event.pressed:
		var jb := InputEventJoypadButton.new()
		jb.button_index = (event as InputEventJoypadButton).button_index
		return jb
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= AXIS_CAPTURE:
		var jm := InputEventJoypadMotion.new()
		jm.axis = (event as InputEventJoypadMotion).axis
		jm.axis_value = signf((event as InputEventJoypadMotion).axis_value)
		return jm
	return null


## Replace `action`'s binding of the same kind as `binding`.
static func rebind(action: StringName, binding: InputEvent) -> void:
	var kind := kind_of(binding)
	for ev in InputMap.action_get_events(action):
		if kind_of(ev) == kind:
			InputMap.action_erase_event(action, ev)
	InputMap.action_add_event(action, binding)


## Text of the action's binding of one kind ("—" if none).
static func describe(action: StringName, kind: Kind) -> String:
	for ev in InputMap.action_get_events(action):
		if kind_of(ev) == kind:
			if ev is InputEventJoypadMotion:
				var m := ev as InputEventJoypadMotion
				return "Axis %d %s" % [m.axis, "+" if m.axis_value > 0.0 else "−"]
			if ev is InputEventJoypadButton:
				return "Button %d" % (ev as InputEventJoypadButton).button_index
			if ev is InputEventKey:
				var k := ev as InputEventKey
				return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
			return ev.as_text()
	return "—"
