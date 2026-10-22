class_name ControlsPanel
extends PanelContainer
## In-game control rebinding (F1 / gamepad Guide). Click a binding, then
## press the new key, mouse button, gamepad button or stick direction.
## Esc cancels a pending rebind. Changes save immediately. "Credits &
## licences" swaps the bindings for the credits (Credits.full_text).
## `embedded` (the settings menu's CONTROLS tab): always shown, no Close.

signal closed

var embedded := false

var _rows: Dictionary = {}  # action -> [keyboard Button, gamepad Button]
var _waiting_action: StringName = &""
var _waiting_kind: InputBindings.Kind = InputBindings.Kind.NONE
var _status: Label
var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _credits: ScrollContainer
var _credits_button: Button
var _credits_text: Label
var _title: Label
const BINDINGS_TITLE := "CONTROLS — click a binding, then press the new input"


func _ready() -> void:
	visible = embedded
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	_title = title
	title.text = BINDINGS_TITLE
	box.add_child(title)
	var grid := GridContainer.new()
	_grid = grid
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	# The list scrolls (play-test batch 6: it ran off the bottom of the screen).
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.custom_minimum_size = Vector2(0, 380 if embedded else 560)
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.add_child(grid)
	box.add_child(_grid_scroll)
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
	_credits = ScrollContainer.new()
	_credits.custom_minimum_size = Vector2(900, 560)
	_credits.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_credits.visible = false
	var text := Label.new()
	_credits_text = text  # filled on first show: ~90k characters of licences
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(880, 0)
	text.add_theme_font_size_override("font_size", 12)
	_credits.add_child(text)
	box.add_child(_credits)
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
	_credits_button = Button.new()
	_credits_button.text = "Credits & licences"
	_credits_button.focus_mode = Control.FOCUS_NONE
	_credits_button.pressed.connect(show_credits.bind(true))
	bar.add_child(_credits_button)
	var close := Button.new()
	close.text = "Close [F1]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide_panel)
	close.visible = not embedded
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
	show_credits(false)
	visible = false
	closed.emit()


## Credits in place of the bindings (the button flips back to the bindings).
func show_credits(on: bool) -> void:
	if on and _credits.visible:
		on = false
	if on and _credits_text.text == "":
		_credits_text.text = Credits.full_text()
	_credits.visible = on
	_grid.visible = not on
	_grid_scroll.visible = not on
	_credits_button.text = "Bindings" if on else "Credits & licences"
	_title.text = "CREDITS & LICENCES — No Safe Orbit %s · scroll for the Godot Engine licences" % Credits.version() if on else BINDINGS_TITLE


func is_credits_shown() -> bool:
	return _credits.visible


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
