class_name ControlsPanel
extends PanelContainer
## In-game control rebinding (F1 / gamepad Guide). Click a binding, then
## press the new key, mouse button, gamepad button or stick direction.
## Esc cancels a pending rebind. Changes save immediately.

signal closed

var _rows: Dictionary = {}  # action -> [keyboard Button, gamepad Button]
var _waiting_action: StringName = &""
var _waiting_kind: InputBindings.Kind = InputBindings.Kind.NONE
var _status: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "CONTROLS — click a binding, then press the new input"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for header in ["ACTION", "KEYBOARD / MOUSE", "GAMEPAD"]:
		var h := Label.new()
		h.text = header
		h.modulate = Color(1, 1, 1, 0.6)
		grid.add_child(h)
	for entry in InputBindings.ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			continue
		var label := Label.new()
		label.text = entry[1]
		grid.add_child(label)
		var buttons := []
		for kind in [InputBindings.Kind.KEYBOARD_MOUSE, InputBindings.Kind.GAMEPAD]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 0)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_begin_rebind.bind(action, kind))
			grid.add_child(b)
			buttons.append(b)
		_rows[action] = buttons
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	var reset := Button.new()
	reset.text = "Reset defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		InputBindings.reset()
		_status.text = "Defaults restored"
		refresh())
	bar.add_child(reset)
	var close := Button.new()
	close.text = "Close [F1]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide_panel)
	bar.add_child(close)
	refresh()


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		visible = true
		refresh()


func hide_panel() -> void:
	_waiting_action = &""
	visible = false
	closed.emit()


func is_capturing() -> bool:
	return _waiting_action != &""


func refresh() -> void:
	for action in _rows:
		var buttons: Array = _rows[action]
		buttons[0].text = InputBindings.describe(action, InputBindings.Kind.KEYBOARD_MOUSE)
		buttons[1].text = InputBindings.describe(action, InputBindings.Kind.GAMEPAD)


func _begin_rebind(action: StringName, kind: InputBindings.Kind) -> void:
	_waiting_action = action
	_waiting_kind = kind
	var buttons: Array = _rows[action]
	buttons[0 if kind == InputBindings.Kind.KEYBOARD_MOUSE else 1].text = "press…  (Esc cancels)"


func _input(event: InputEvent) -> void:
	if not visible or _waiting_action == &"":
		return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_waiting_action = &""
		_status.text = "Cancelled"
		refresh()
		get_viewport().set_input_as_handled()
		return
	var binding := InputBindings.binding_from(event)
	if binding == null or InputBindings.kind_of(binding) != _waiting_kind:
		return
	InputBindings.rebind(_waiting_action, binding)
	var err := InputBindings.save()
	_status.text = "Saved" if err == OK else "Could not save (%s)" % error_string(err)
	_waiting_action = &""
	refresh()
	get_viewport().set_input_as_handled()
