class_name CrewBadge
extends PanelContainer
## A crew member on the crew manifest (play-test batches 9 and 11): a
## placeholder portrait, their name, level (or specialist title), what they
## did before and their sorties (wage on hover); drag the badge onto another
## department to repost them, or onto Resting crew to send them ashore.
## Aboard, its buttons train (a level, for credits) and dismiss; resting,
## bring aboard and dismiss.

signal train_pressed(index: int)
signal dismiss_pressed(index: int)
signal board_pressed(index: int)

const SIZE := Vector2(232, 66)

var index := -1
var entry: Dictionary = {}
var resting := false


func setup(i: int, c: Dictionary, train_cost: int, can_train: bool, is_resting: bool = false) -> void:
	index = i
	entry = c
	resting = is_resting
	custom_minimum_size = SIZE
	var role := clampi(int(c.role), 0, CrewRoster.ROLE_NAMES.size() - 1)
	add_theme_stylebox_override("panel", CyberTheme.panel(CrewRoster.ROLE_COLORS[role], CyberTheme.SPACE_XS, 0.55))
	var skill_now := int(c.get("skill", 0))
	tooltip_text = "%s — formerly %s · %d cr a sortie%s\n%s" % [c.name, c.get("occupation", "a spacer"),
		PlayerProfile.WAGE_BASE + PlayerProfile.WAGE_PER_LEVEL * skill_now, " aboard" if not resting else " (unpaid while resting)",
		"drag onto a department to bring them aboard there" if resting else "drag onto another department to post them there, or onto Resting crew"]
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
	served.text = "ex-%s · %d sorties" % [c.get("occupation", "spacer"), int(c.get("sorties", 0))]
	served.clip_text = true
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
	if resting:
		var aboard := Button.new()
		aboard.name = "Board"
		aboard.text = "▲"
		aboard.tooltip_text = "Bring %s aboard (their own post)" % c.name
		CyberTheme.style_button(aboard, CyberTheme.CYAN)
		aboard.pressed.connect(func() -> void: board_pressed.emit(index))
		buttons.add_child(aboard)
	elif skill < CrewRoster.MAX_SKILL:
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
	return {"crew_index": index, "resting": resting}
