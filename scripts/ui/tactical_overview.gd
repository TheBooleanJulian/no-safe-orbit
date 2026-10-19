class_name TacticalOverview
extends PanelContainer
## Tactical overview (Tab): your ship deck by deck, the target, and the
## ship's management — power distribution, crew (who is where, covering lost
## roles), damage control priorities and the boarding party. The game keeps
## running underneath. Built in code; Main handles the commands it emits.

## `name`: &"divert" (arg Channel), &"balance", &"cover" (arg CrewRoster.Role),
## &"party" (arg new size), &"repair_pick" (arg equipment id), &"repair",
## &"craft_launch" / &"craft_recall" (arg craft id), &"craft_directive" /
## &"craft_risk" / &"craft_priority" (arg [craft id, value]).
signal command(name: StringName, arg: Variant)

const COVERABLE := [CrewRoster.Role.COMMAND, CrewRoster.Role.WEAPONS, CrewRoster.Role.ENGINEERING, CrewRoster.Role.DAMAGE_CONTROL]

var _own_maps: Array[ShipSchematic] = []
var _own_box: VBoxContainer
var _target_map: ShipSchematic
var _power_label: RichTextLabel
var _crew_label: RichTextLabel
var _target_label: RichTextLabel
var _party_label: Label
var _repair_pick: OptionButton
var _repair_ids: PackedStringArray = PackedStringArray()
var _decks: Array[int] = []
var _wing_box: VBoxContainer
var _wing_rows: Dictionary = {}  # craft id -> Label (status line)
var _wing_ref: AirWing


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.CYAN, 14, 0.97))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)
	# Own ship.
	_own_box = VBoxContainer.new()
	_own_box.add_child(_heading("YOUR SHIP — DECK BY DECK", CyberTheme.CYAN))
	columns.add_child(_own_box)
	# Management.
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(380, 0)
	mid.add_theme_constant_override("separation", 6)
	columns.add_child(mid)
	mid.add_child(_heading("POWER  [1][2][3]  [4] balance", CyberTheme.CYAN))
	_power_label = _rich(mid, 64)
	var prow := HBoxContainer.new()
	for ch in ShipSystems.Channel.size():
		prow.add_child(_button("+ %s" % ShipSystems.CHANNEL_NAMES[ch], func() -> void: command.emit(&"divert", ch)))
	prow.add_child(_button("Balance", func() -> void: command.emit(&"balance", null)))
	mid.add_child(prow)
	mid.add_child(_heading("CREW", CyberTheme.CYAN))
	_crew_label = _rich(mid, 150)
	var crow := HBoxContainer.new()
	for role in COVERABLE:
		crow.add_child(_button("Cover %s" % CrewRoster.ROLE_NAMES[role].split(" ")[0], func() -> void: command.emit(&"cover", role)))
	mid.add_child(crow)
	mid.add_child(_heading("DAMAGE CONTROL", CyberTheme.CYAN))
	var rrow := HBoxContainer.new()
	_repair_pick = OptionButton.new()
	_repair_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair_pick.item_selected.connect(func(i: int) -> void:
		command.emit(&"repair_pick", _repair_ids[i] if i < _repair_ids.size() else ""))
	rrow.add_child(_repair_pick)
	rrow.add_child(_button("Patch now [C]", func() -> void: command.emit(&"repair", null)))
	mid.add_child(rrow)
	mid.add_child(_heading("BOARDING PARTY", CyberTheme.MAGENTA))
	var brow := HBoxContainer.new()
	brow.add_child(_button("−", func() -> void: command.emit(&"party", -1), CyberTheme.MAGENTA))
	_party_label = Label.new()
	_party_label.add_theme_color_override("font_color", CyberTheme.MAGENTA)
	brow.add_child(_party_label)
	brow.add_child(_button("+", func() -> void: command.emit(&"party", 1), CyberTheme.MAGENTA))
	mid.add_child(brow)
	mid.add_child(_heading("AIR WING  [L] launch all  [K] recall all", CyberTheme.CYAN))
	_wing_box = VBoxContainer.new()
	mid.add_child(_wing_box)
	var close := _button("Close [Tab]", func() -> void: visible = false)
	mid.add_child(close)
	# Target.
	var right := VBoxContainer.new()
	right.add_child(_heading("TARGET", CyberTheme.MAGENTA))
	_target_map = ShipSchematic.new()
	_target_map.accent = CyberTheme.MAGENTA
	_target_map.custom_minimum_size = Vector2(380, 200)
	_target_map.show_legend = true
	right.add_child(_target_map)
	_target_label = _rich(right, 220)
	columns.add_child(right)


func toggle() -> void:
	visible = not visible


## Refresh from the simulation (called every frame while open).
func update_view(player: ShipState, target: ShipState, boarding: BoardingAction, party_size: int, sim_time: float,
		wing: AirWing = null, close_look: bool = true) -> void:
	var sys := player.systems
	if sys == null:
		return
	_update_wing(wing)
	_ensure_deck_maps(sys)
	var pips := PackedStringArray()
	for ch in ShipSystems.Channel.size():
		pips.append("%s %s  %d %%" % [ShipSystems.CHANNEL_NAMES[ch],
			"[color=%s]%s[/color][color=%s]%s[/color]" % [CyberTheme.html(CyberTheme.CYAN), "■".repeat(sys.pips[ch]),
				CyberTheme.html(CyberTheme.TEXT_DIM), "□".repeat(ShipSystems.PIPS_MAX - sys.pips[ch])],
			roundi(sys.channel_factor(ch) * 100.0)])
	_power_label.text = "  ".join(pips) + "\nSYS: turning + repairs · ENG: thrust · WEP: rate of fire\nReactor %.0f / %.0f kW · %s" % [
		sys.power_demand_kw - sys.power_unmet_kw, sys.power_supply_kw, ["normal", "THROTTLED", "SCRAM"][sys.reactor_state]]
	_crew_label.text = _crew_text(sys)
	_party_label.text = "  %d of up to %d  " % [party_size, BoardingAction.MAX_TEAM]
	_refresh_repairs(sys)
	_target_map.systems = target.systems if target != null and close_look else null
	_target_map.title = (target.display_name if close_look else "%s — no close look (recon drone or < 3 km)" % target.display_name) if target != null else "NO TARGET"
	_target_map.room_overlay = {}
	var lines := PackedStringArray()
	if target != null and target.systems != null and close_look:
		lines.append(target.systems.status_line())
		if target.systems.is_disabled():
			lines.append("[color=%s]DISABLED — %s[/color]" % [CyberTheme.html(CyberTheme.MAGENTA), target.systems.disabled_reason()])
		if target.systems.crew != null:
			lines.append("Crew %s" % target.systems.crew.summary())
	if boarding != null:
		for room in boarding.room_control():
			_target_map.room_overlay[room] = ShipSchematic.control_color(boarding.room_control()[room], sim_time)
		lines.append("[b]BOARDING[/b] %s · team %d/%d" % [BoardingAction.PHASE_NAMES[boarding.phase].to_upper(), boarding.fit_team().size(), boarding.team.size()])
		for l in boarding.log.slice(maxi(boarding.log.size() - 5, 0)):
			lines.append(l)
	_target_label.text = "\n".join(lines)


## One row per craft: status line, then directive / risk / priority pickers
## and launch / recall.
func _update_wing(wing: AirWing) -> void:
	if wing == null:
		return
	if wing != _wing_ref:
		_wing_ref = wing
		for child in _wing_box.get_children():
			child.queue_free()
		_wing_rows.clear()
		for c in wing.crafts:
			var status := Label.new()
			status.add_theme_font_size_override("font_size", 12)
			_wing_box.add_child(status)
			_wing_rows[c.id] = status
			var row := HBoxContainer.new()
			var id := c.id
			row.add_child(_picker(CraftAI.DIRECTIVE_NAMES, c.directive, func(i: int) -> void: command.emit(&"craft_directive", [id, i])))
			row.add_child(_picker(CraftAI.RISK_NAMES, c.risk, func(i: int) -> void: command.emit(&"craft_risk", [id, i])))
			if not c.is_drone():
				row.add_child(_picker(CraftAI.PRIORITY_NAMES, c.priority, func(i: int) -> void: command.emit(&"craft_priority", [id, i])))
			row.add_child(_button("Launch", func() -> void: command.emit(&"craft_launch", id)))
			row.add_child(_button("Recall", func() -> void: command.emit(&"craft_recall", id)))
			_wing_box.add_child(row)
	for c in wing.crafts:
		var label: Label = _wing_rows.get(c.id)
		if label == null:
			continue
		var fuel := "fuel %d%%" % roundi(c.propellant_fraction * 100.0)
		var ammo := " · ammo %d" % c.ammo if c.config.cannon != null else ""
		var state: String = AirWing.STATUS_NAMES[c.status].to_upper()
		if c.status == AirWing.Status.DOCKED and c.service_left_s > 0.0:
			state = "SERVICING %.0f s" % c.service_left_s
		label.text = "%s — %s · hull %d%% · %s%s%s" % [c.label, state, roundi(c.hull_fraction * 100.0), fuel, ammo,
			"  » " + c.override_reason if c.override_reason != "" else ""]
		label.add_theme_color_override("font_color", CyberTheme.DANGER if c.status == AirWing.Status.LOST else CyberTheme.TEXT)


func _picker(names: Array, selected: int, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.select(selected)
	o.item_selected.connect(on_pick)
	return o


func _crew_text(sys: ShipSystems) -> String:
	if sys.crew == null:
		return "No crew model."
	var lines := PackedStringArray(["%s   %s" % [sys.crew.summary(),
		"[color=%s]COMMAND OK[/color]" % CyberTheme.html(CyberTheme.OK) if sys.has_command() else "[color=%s]SHIP AI IN CONTROL[/color]" % CyberTheme.html(CyberTheme.WARN)]])
	for role in CrewRoster.Role.size():
		var fit := 0
		var hurt := 0
		var dead := 0
		var where := {}
		for m in sys.crew.members:
			if m.role != role:
				continue
			match m.state:
				CrewRoster.State.FIT:
					fit += 1
				CrewRoster.State.WOUNDED:
					hurt += 1
				_:
					dead += 1
			if m.location >= 0 and m.state != CrewRoster.State.DEAD:
				where[sys.blueprint.rooms[m.location].id] = true
		if fit + hurt + dead == 0:
			continue
		lines.append("%-15s %d fit%s%s  %s" % [CrewRoster.ROLE_NAMES[role], fit,
			" · %d wounded" % hurt if hurt > 0 else "", " · %d dead" % dead if dead > 0 else "", ", ".join(where.keys())])
	for id in sys.crew_orders:
		lines.append("[color=%s]» %s → %s, %.0f s[/color]" % [CyberTheme.html(CyberTheme.WARN), id,
			CrewRoster.ROLE_NAMES[sys.crew_orders[id].role], sys.crew_orders[id].left_s])
	return "\n".join(lines)


func _refresh_repairs(sys: ShipSystems) -> void:
	var ids := PackedStringArray()
	var labels := PackedStringArray()
	for e in sys.equipment:
		if not e.destroyed() and e.hp < ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp:
			ids.append(e.id)
			labels.append("%s %s — %d %%" % [e.def.display_name, e.id, roundi(100.0 * e.hp / e.max_hp)])
	if ids == _repair_ids and _repair_pick.item_count == maxi(ids.size(), 1):
		return
	_repair_ids = ids
	_repair_pick.clear()
	if ids.is_empty():
		_repair_pick.add_item("nothing to patch")
		_repair_pick.disabled = true
		return
	_repair_pick.disabled = false
	for i in ids.size():
		_repair_pick.add_item(labels[i])
	var pick := ids.find(sys.preferred_repair_id)
	_repair_pick.select(maxi(pick, 0))


func _ensure_deck_maps(sys: ShipSystems) -> void:
	var decks: Array[int] = []
	var b := sys.grid.cell_bounds()
	for d in range(int(b.position.y), int(b.end.y)):
		decks.append(d)
	if decks == _decks:
		for m in _own_maps:
			m.systems = sys
		return
	_decks = decks
	for m in _own_maps:
		m.queue_free()
	_own_maps.clear()
	for d in range(decks.size() - 1, -1, -1):
		var map := ShipSchematic.new()
		map.deck = decks[d]
		map.title = "DECK %d" % decks[d]
		map.systems = sys
		map.custom_minimum_size = Vector2(380, 170)
		map.show_legend = d == 0
		_own_box.add_child(map)
		_own_maps.append(map)


func _heading(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l


func _rich(parent: Control, height: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(380, height)
	r.add_theme_color_override("default_color", CyberTheme.TEXT)
	r.add_theme_font_size_override("normal_font_size", 12)
	r.add_theme_font_size_override("bold_font_size", 12)
	parent.add_child(r)
	return r


func _button(text: String, on_press: Callable, accent: Color = CyberTheme.CYAN) -> Button:
	var b := Button.new()
	b.text = text
	CyberTheme.style_button(b, accent)
	b.pressed.connect(on_press)
	return b
