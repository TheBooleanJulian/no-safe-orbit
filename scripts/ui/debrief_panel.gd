class_name DebriefPanel
extends PanelContainer
## Post-combat debrief (CombatLog.render): what happened, what hurt, and
## lessons for the shipyard. Built in code; shown in flight when the ship is
## lost and at the station after a sortie.

signal closed

var _text: RichTextLabel
var _footer: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.MAGENTA, 14, 0.97))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.custom_minimum_size = Vector2(720, 460)
	_text.add_theme_color_override("default_color", CyberTheme.TEXT)
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_font_size_override("bold_font_size", 15)
	box.add_child(_text)
	var row := HBoxContainer.new()
	box.add_child(row)
	_footer = Label.new()
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_theme_color_override("font_color", CyberTheme.MAGENTA)
	row.add_child(_footer)
	var close := Button.new()
	close.text = "Close"
	CyberTheme.style_button(close)
	close.pressed.connect(hide_debrief)
	row.add_child(close)


func show_debrief(d: Dictionary, footer: String = "") -> void:
	_text.text = CombatLog.render(d)
	_footer.text = footer
	visible = true


func hide_debrief() -> void:
	visible = false
	closed.emit()


func text() -> String:
	return _text.get_parsed_text()
