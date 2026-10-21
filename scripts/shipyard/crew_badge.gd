class_name CrewBadge
extends PanelContainer
## A crew member on the crew quarters board (play-test batch 9): a
## placeholder portrait, their name, level (or specialist title), sorties
## and wage; drag the badge onto another department to repost them. Its
## buttons train (a level, for credits) and dismiss.

signal train_pressed(index: int)
signal dismiss_pressed(index: int)

const SIZE := Vector2(232, 66)

var index := -1
var entry: Dictionary = {}


func setup(i: int, c: Dictionary, train_cost: int, can_train: bool) -> void:
	index = i
	entry = c
	custom_minimum_size = SIZE
	var role := clampi(int(c.role), 0, CrewRoster.ROLE_NAMES.size() - 1)
	add_theme_stylebox_override("panel", CyberTheme.panel(CrewRoster.ROLE_COLORS[role], CyberTheme.SPACE_XS, 0.55))
	tooltip_text = "%s — drag onto another department to post them there" % c.name
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	add_child(row)
	var face := CrewPortrait.new()
	face.person = str(c.name)
	face.role = role
	face.custom_minimum_size = Vector2(52, 52)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(face)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var skill := int(c.get("skill", 0))
	var name_label := Label.new()
	name_label.text = str(c.name)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var level := Label.new()
	level.text = "%s %s" % ["★".repeat(skill) + "☆".repeat(CrewRoster.MAX_SKILL - skill), CrewRoster.title(role, skill)]
	level.add_theme_color_override("font_color", CyberTheme.AMBER if skill >= CrewRoster.MAX_SKILL else CyberTheme.TEXT_DIM)
	level.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL)
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(level)
	var served := Label.new()
	served.text = "%d sorties · %d cr a sortie" % [int(c.get("sorties", 0)), PlayerProfile.WAGE_BASE + PlayerProfile.WAGE_PER_LEVEL * skill]
	served.add_theme_color_override("font_color", CyberTheme.TEXT_FAINT)
	served.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL)
	served.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(served)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	row.add_child(buttons)
	var out := Button.new()
	out.text = "✕"
	out.tooltip_text = "Dismiss %s" % c.name
	CyberTheme.style_button(out, CyberTheme.RED)
	out.pressed.connect(func() -> void: dismiss_pressed.emit(index))
	buttons.add_child(out)
	if skill < CrewRoster.MAX_SKILL:
		var up := Button.new()
		up.name = "Train"
		up.text = "▲"
		up.tooltip_text = "Train %s to %s: %d cr" % [c.name, CrewRoster.title(role, skill + 1), train_cost]
		up.disabled = not can_train
		CyberTheme.style_button(up, CyberTheme.AMBER)
		up.pressed.connect(func() -> void: train_pressed.emit(index))
		buttons.add_child(up)


func _get_drag_data(_at: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = "→ %s" % entry.get("name", "")
	preview.add_theme_color_override("font_color", CyberTheme.CYAN)
	set_drag_preview(preview)
	return {"crew_index": index}
