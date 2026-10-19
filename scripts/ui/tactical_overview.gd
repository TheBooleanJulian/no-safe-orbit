class_name TacticalOverview
extends PanelContainer
## Ship management drawer (Tab), docked on the right so the fight stays in
## view. Tabs:
##   DAMAGE  deck-by-deck schematic; click a system or room to see its state
##           and act on it — patch it, switch a load off to reroute power,
##           divert power to its channel, isolate / reopen a compartment
##   CREW    who is where, cover a lost role, boarding party size
##   POWER   distribution pips and every load's switch
##   WING    per-craft orders
##   TARGET  the target's schematic (with boarding control) and status
## The game keeps running. Main handles the commands it emits.

## `name`: &"divert" (arg Channel), &"balance", &"cover" (arg CrewRoster.Role),
## &"party" (arg +/-1), &"repair_pick" (arg equipment id), &"repair",
## &"power_toggle" (arg equipment id), &"isolate" (arg room id),
## &"craft_launch" / &"craft_recall" (arg craft id), &"craft_directive" /
## &"craft_risk" / &"craft_priority" (arg [craft id, value]).
signal command(name: StringName, arg: Variant)

const COVERABLE := [CrewRoster.Role.COMMAND, CrewRoster.Role.WEAPONS, CrewRoster.Role.ENGINEERING, CrewRoster.Role.DAMAGE_CONTROL]
const TAB_NAMES := ["DAMAGE", "CREW", "POWER", "WING", "TARGET", "CARGO"]
const CHANNEL_FOR_KIND := {
	EquipmentDefinition.Kind.MAIN_ENGINE: ShipSystems.Channel.ENG,
	EquipmentDefinition.Kind.CANNON: ShipSystems.Channel.WEP,
	EquipmentDefinition.Kind.RCS: ShipSystems.Channel.SYS,
}

var _tabs: TabContainer
var _caption: Label
var _map: ShipSchematic
var _deck_buttons: HBoxContainer
var _decks: Array[int] = []
var _selection_text: RichTextLabel
var _actions: HFlowContainer
var _actions_key := ""
var _crew_label: RichTextLabel
var _reassign_pick: OptionButton
var _reassign_key := ""
var _party_label: Label
var _power_label: RichTextLabel
var _loads_box: VBoxContainer
var _loads_key := ""
var _wing_box: VBoxContainer
var _wing_rows: Dictionary = {}  # craft id -> Label
var _wing_ref: AirWing
var _target_map: ShipSchematic
var _target_label: RichTextLabel
var _sys: ShipSystems
## The vessel whose hold the CARGO tab shows (set by the HUD).
var vessel: ShipInstance
var _cargo_label: RichTextLabel
var _cargo_box: VBoxContainer
var _cargo_key := ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.CYAN, CyberTheme.SPACE_M, 0.93))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	add_child(root)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "SHIP · DAMAGE CONTROL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close [Tab]", func() -> void: visible = false))
	root.add_child(head)
	_caption = Label.new()
	_caption.theme_type_variation = &"Caption"
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_caption)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build_damage_tab()
	_build_crew_tab()
	_build_power_tab()
	_build_wing_tab()
	_build_target_tab()
	_build_cargo_tab()
	for i in TAB_NAMES.size():
		_tabs.set_tab_title(i, TAB_NAMES[i])


func toggle() -> void:
	visible = not visible


## Open on `id` (a system or room): DAMAGE tab, its deck, selected.
func select_subject(id: String) -> void:
	_tabs.current_tab = 0
	_map.selected_id = id
	_map.alert_id = id
	if _sys != null:
		var e := _sys.equipment_by_id(id)
		if e != null:
			_map.deck = _sys.blueprint.equipment[e.index].cell.y
		else:
			for r in _sys.blueprint.rooms:
				if r.id == id:
					_map.deck = r.deck
	_actions_key = ""


func selected_id() -> String:
	return _map.selected_id


func current_tab_name() -> String:
	return TAB_NAMES[_tabs.current_tab]


func show_tab(tab_name: String) -> void:
	_tabs.current_tab = maxi(TAB_NAMES.find(tab_name), 0)


# --- Building -------------------------------------------------------------------

func _build_damage_tab() -> void:
	var box := _tab_box()
	_deck_buttons = HBoxContainer.new()
	box.add_child(_deck_buttons)
	_map = ShipSchematic.new()
	_map.interactive = true
	_map.show_legend = true
	_map.custom_minimum_size = Vector2(0, 230)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.picked.connect(func(_kind: StringName, _id: String) -> void: _actions_key = "")
	box.add_child(_map)
	var sel := PanelContainer.new()
	sel.add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.CYAN, CyberTheme.SPACE_S, 0.6))
	var sbox := VBoxContainer.new()
	sel.add_child(sbox)
	_selection_text = _rich(sbox, 80)
	_actions = HFlowContainer.new()
	sbox.add_child(_actions)
	box.add_child(sel)
	box.add_child(_caption_label("Click a system or room. Amber ring = what the alert is about. C patches the next damaged system."))


func _build_crew_tab() -> void:
	var box := _tab_box()
	_crew_label = _rich(box, 170)
	box.add_child(_caption_label("Cover a role: the nearest free general crew member walks to that role's station."))
	var cover := GridContainer.new()
	cover.columns = 2
	for role in COVERABLE:
		cover.add_child(_button("Cover %s" % CrewRoster.ROLE_NAMES[role], func() -> void: command.emit(&"cover", role)))
	box.add_child(cover)
	box.add_child(_caption_label("Reassign: pick a crew member, then their new post — they walk there."))
	_reassign_pick = OptionButton.new()
	box.add_child(_reassign_pick)
	var posts := GridContainer.new()
	posts.columns = 3
	for role in CrewRoster.Role.size():
		posts.add_child(_button("→ %s" % CrewRoster.ROLE_NAMES[role], func() -> void:
			if _reassign_pick.selected >= 0:
				command.emit(&"reassign", [_reassign_pick.get_item_metadata(_reassign_pick.selected), role])))
	box.add_child(posts)
	box.add_child(_heading("IF WE ARE BOARDED", CyberTheme.AMBER))
	var defence := HBoxContainer.new()
	for d in BoardingAction.Defence.size():
		defence.add_child(_button("Defence: %s" % BoardingAction.DEFENCE_NAMES[d], func() -> void: command.emit(&"defence", d), CyberTheme.AMBER))
	box.add_child(defence)
	box.add_child(_heading("BOARDING PARTY", CyberTheme.MAGENTA))
	var row := HBoxContainer.new()
	row.add_child(_button("−", func() -> void: command.emit(&"party", -1), CyberTheme.MAGENTA))
	_party_label = Label.new()
	_party_label.add_theme_color_override("font_color", CyberTheme.MAGENTA)
	row.add_child(_party_label)
	row.add_child(_button("+", func() -> void: command.emit(&"party", 1), CyberTheme.MAGENTA))
	box.add_child(row)


func _build_power_tab() -> void:
	var box := _tab_box()
	_power_label = _rich(box, 64)
	var row := HFlowContainer.new()
	for ch in ShipSystems.Channel.size():
		row.add_child(_button("+ %s [%d]" % [ShipSystems.CHANNEL_NAMES[ch], ch + 1], func() -> void: command.emit(&"divert", ch)))
	row.add_child(_button("Balance [4]", func() -> void: command.emit(&"balance", null)))
	box.add_child(row)
	box.add_child(_heading("LOADS — switch off to reroute power", CyberTheme.CYAN))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	_loads_box = VBoxContainer.new()
	_loads_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_loads_box)
	box.add_child(scroll)


func _build_wing_tab() -> void:
	var box := _tab_box()
	box.add_child(_caption_label("[[] launch all  ·  []] recall all"))
	_wing_box = VBoxContainer.new()
	box.add_child(_wing_box)


func _build_target_tab() -> void:
	var box := _tab_box()
	_target_map = ShipSchematic.new()
	_target_map.accent = CyberTheme.MAGENTA
	_target_map.custom_minimum_size = Vector2(0, 220)
	_target_map.show_legend = true
	box.add_child(_target_map)
	_target_label = _rich(box, 160)


func _build_cargo_tab() -> void:
	var box := _tab_box()
	_cargo_label = _rich(box, 60)
	box.add_child(_button("Vent excess (cheapest first)", func() -> void: command.emit(&"vent_excess", null), CyberTheme.AMBER))
	box.add_child(_heading("HOLD — at risk until banked at Earth Shipyard", CyberTheme.CYAN))
	_cargo_box = VBoxContainer.new()
	box.add_child(_cargo_box)


func _refresh_cargo(sys: ShipSystems) -> void:
	if vessel == null:
		return
	var catalog := ConstructionCatalog.default_catalog()
	var used := vessel.cargo_volume_m3(catalog)
	var cap := sys.stats.cargo_m3
	var frac := used / maxf(cap, 1e-6)
	var bars := clampi(roundi(frac * 20.0), 0, 20)
	var col := CyberTheme.RED if used > cap else (CyberTheme.AMBER if frac > 0.85 else CyberTheme.CYAN)
	_cargo_label.text = "CAPACITY  %s  %.1f / %.0f m³%s" % [CyberTheme.tint("▮".repeat(bars) + "▯".repeat(20 - bars), col), used, cap,
		CyberTheme.tint("  ▲ OVER BY %.1f m³ — vent before the jump" % (used - cap), CyberTheme.RED) if used > cap else ""]
	var lines := vessel.cargo_lines(catalog)
	var key := JSON.stringify(lines)
	if key == _cargo_key:
		return
	_cargo_key = key
	for c in _cargo_box.get_children():
		c.queue_free()
	if lines.is_empty():
		_cargo_box.add_child(_caption_label("Empty."))
	for line in lines:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s ×%d   %.1f m³" % [line.name, line.units, line.m3]
		if int(line.rarity) >= 0:
			l.add_theme_color_override("font_color", Rarity.color_of(int(line.rarity)))
		row.add_child(l)
		var kind: String = line.kind
		var id: String = line.id
		row.add_child(_button("Vent", func() -> void: command.emit(&"vent", [kind, id]), CyberTheme.AMBER))
		_cargo_box.add_child(row)


# --- Refresh -----------------------------------------------------------------------

## Refresh from the simulation (called every frame while open).
func update_view(player: ShipState, target: ShipState, boarding: BoardingAction, party_size: int, sim_time: float,
		wing: AirWing = null, close_look: bool = true) -> void:
	var sys := player.systems
	if sys == null:
		return
	_sys = sys
	_caption.text = "%s · %s" % [sys.crew.summary() if sys.crew != null else "", power_summary(sys)]
	match _tabs.current_tab:
		0:
			_refresh_damage(sys)
		1:
			_crew_label.text = _crew_text(sys)
			_refresh_reassign(sys)
			_party_label.text = "  %d of up to %d  " % [party_size, BoardingAction.MAX_TEAM]
		2:
			_refresh_power(sys)
		3:
			_update_wing(wing)
		4:
			_refresh_target(target, boarding, sim_time, close_look)
		5:
			_refresh_cargo(sys)


static func power_summary(sys: ShipSystems) -> String:
	return "power %.0f / %.0f kW · %s" % [sys.power_demand_kw - sys.power_unmet_kw, sys.power_supply_kw, Hud.power_pips_text(sys)]


func _refresh_damage(sys: ShipSystems) -> void:
	_map.systems = sys
	var decks: Array[int] = [-1]
	var b := sys.grid.cell_bounds()
	for d in range(int(b.end.y) - 1, int(b.position.y) - 1, -1):
		decks.append(d)
	if decks != _decks:
		_decks = decks
		for c in _deck_buttons.get_children():
			c.queue_free()
		for d in decks:
			_deck_buttons.add_child(_button("All decks" if d < 0 else "Deck %d" % d, func() -> void: _map.deck = d))
	_map.title = "ALL DECKS" if _map.deck < 0 else "DECK %d" % _map.deck
	var id := _map.selected_id
	var e := sys.equipment_by_id(id)
	var room := -1
	for i in sys.blueprint.rooms.size():
		if sys.blueprint.rooms[i].id == id:
			room = i
	if e != null:
		_selection_text.text = _equipment_text(sys, e)
		_set_actions("e:%s:%s:%s" % [id, sys.switched_off.has(id), e.destroyed()], _equipment_actions(sys, e))
	elif room >= 0:
		_selection_text.text = _room_text(sys, room)
		_set_actions("r:%s:%s" % [id, sys.isolated_rooms.has(room)], _room_actions(sys, room))
	else:
		_selection_text.text = CyberTheme.tint("Nothing selected — click a system or room on the map.", CyberTheme.TEXT_DIM)
		_set_actions("none", [])


func _equipment_text(sys: ShipSystems, e: ShipSystems.EquipmentState) -> String:
	var state := CyberTheme.equipment_state(e)
	if sys.switched_off.has(e.id):
		state = [CyberTheme.GLYPH_OFFLINE, CyberTheme.TEXT_DIM, "switched off"]
	var room: int = sys.grid.room_at.get(sys.blueprint.equipment[e.index].cell, -1)
	var where := "outer hull, %s face" % sys.blueprint.equipment[e.index].face
	if not e.def.is_external():
		where = "%s %s (%s)" % [sys._room_name(room), sys.blueprint.rooms[room].id, "pressurised" if sys.rooms[room].pressurized else "VENTED"] if room >= 0 else "—"
	var power := ""
	if e.def.power_kw < 0.0:
		power = " · draws %.0f kW" % -e.def.power_kw
	elif e.def.power_kw > 0.0:
		power = " · makes %.0f kW" % e.def.power_kw
	var lines := PackedStringArray([
		"[b]%s %s %s[/b] — %s" % [CyberTheme.tint(state[0], state[1]), e.def.display_name, e.id, CyberTheme.tint(str(state[2]).to_upper(), state[1])],
		"Condition %d%% (%.0f / %.0f hp) · %s%s" % [roundi(100.0 * e.hp / e.max_hp), e.hp, e.max_hp, "powered" if e.powered else "UNPOWERED", power],
		"Location: %s" % where,
	])
	if sys.repair_task != null and sys.repair_task.equipment_id == e.id:
		lines.append(CyberTheme.tint("Being patched: %d%% (%.0f s left)" % [roundi(sys.repair_task.progress() * 100.0), sys.repair_task.remaining_s], CyberTheme.AMBER))
	return "\n".join(lines)


func _equipment_actions(sys: ShipSystems, e: ShipSystems.EquipmentState) -> Array:
	var out := []
	if not e.destroyed() and e.hp < ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp:
		out.append(["Dispatch repair crew [C]", func() -> void:
			command.emit(&"repair_pick", e.id)
			command.emit(&"repair", null)])
	elif e.destroyed():
		out.append(["Destroyed — replace at the station", Callable()])
	if e.def.power_kw < 0.0 and not e.destroyed():
		var off := sys.switched_off.has(e.id)
		out.append(["Switch on" if off else "Switch off (reroute power)", func() -> void: command.emit(&"power_toggle", e.id)])
	if CHANNEL_FOR_KIND.has(e.def.kind):
		var ch: int = CHANNEL_FOR_KIND[e.def.kind]
		out.append(["Divert power to %s" % ShipSystems.CHANNEL_NAMES[ch], func() -> void: command.emit(&"divert", ch)])
	return out


func _room_text(sys: ShipSystems, room: int) -> String:
	var r := sys.blueprint.rooms[room]
	var state := "pressurised" if sys.rooms[room].pressurized else CyberTheme.tint("VENTED", CyberTheme.MAGENTA)
	if sys.isolated_rooms.has(room):
		state += " · " + CyberTheme.tint("ISOLATED", CyberTheme.AMBER)
	var crew := PackedStringArray()
	if sys.crew != null:
		for m in sys.crew.in_room(room, false):
			crew.append("%s%s" % [CrewRoster.ROLE_NAMES[m.role], "" if m.fit() else " (wounded)"])
	var systems := PackedStringArray()
	for e in sys.equipment:
		if not e.def.is_external() and sys.grid.room_at.get(sys.blueprint.equipment[e.index].cell, -1) == room:
			var s := CyberTheme.equipment_state(e)
			systems.append("%s %s %s" % [CyberTheme.tint(s[0], s[1]), e.def.display_name, e.id])
	return "\n".join([
		"[b]%s %s[/b] — %s · %s" % [sys._room_name(room), r.id, sys.room_role(room), state],
		"Crew: %s" % (", ".join(crew) if not crew.is_empty() else "nobody"),
		"Systems: %s" % (", ".join(systems) if not systems.is_empty() else "none"),
	])


func _room_actions(sys: ShipSystems, room: int) -> Array:
	var out := []
	var id := sys.blueprint.rooms[room].id
	out.append(["Reopen compartment" if sys.isolated_rooms.has(room) else "Isolate compartment", func() -> void: command.emit(&"isolate", id)])
	for e in sys.equipment:
		if not e.def.is_external() and sys.grid.room_at.get(sys.blueprint.equipment[e.index].cell, -1) == room \
				and not e.destroyed() and e.hp < ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp:
			var eid := e.id
			out.append(["Repair %s here" % eid, func() -> void:
				command.emit(&"repair_pick", eid)
				command.emit(&"repair", null)])
			break
	return out


func _set_actions(key: String, actions: Array) -> void:
	if key == _actions_key:
		return
	_actions_key = key
	for c in _actions.get_children():
		c.queue_free()
	for a in actions:
		var call: Callable = a[1]
		var b := _button(a[0], call if call.is_valid() else func() -> void: pass)
		b.disabled = not call.is_valid()
		_actions.add_child(b)


func _refresh_power(sys: ShipSystems) -> void:
	var pips := PackedStringArray()
	for ch in ShipSystems.Channel.size():
		pips.append("%s %s %d%%" % [ShipSystems.CHANNEL_NAMES[ch],
			CyberTheme.tint("■".repeat(sys.pips[ch]), CyberTheme.CYAN) + CyberTheme.tint("□".repeat(ShipSystems.PIPS_MAX - sys.pips[ch]), CyberTheme.TEXT_FAINT),
			roundi(sys.channel_factor(ch) * 100.0)])
	_power_label.text = "   ".join(pips) + "\nSYS: turning + repairs · ENG: thrust · WEP: rate of fire\nReactor %.0f / %.0f kW · %s%s" % [
		sys.power_demand_kw - sys.power_unmet_kw, sys.power_supply_kw, ["normal", "THROTTLED", "SCRAM"][sys.reactor_state],
		CyberTheme.tint("  · SHORT %.0f kW" % sys.power_unmet_kw, CyberTheme.AMBER) if sys.power_unmet_kw > 0.0 else ""]
	var key := ""
	for e in sys.equipment:
		if e.def.power_kw < 0.0:
			key += "%s%s%s%s|" % [e.id, sys.switched_off.has(e.id), e.powered, e.destroyed()]
	if key == _loads_key:
		return
	_loads_key = key
	for c in _loads_box.get_children():
		c.queue_free()
	for e in sys.equipment:
		if e.def.power_kw >= 0.0:
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		var s := CyberTheme.equipment_state(e)
		var off := sys.switched_off.has(e.id)
		l.text = "%s %s %s · %.0f kW%s" % [CyberTheme.GLYPH_OFFLINE if off else s[0], e.def.display_name, e.id, -e.def.power_kw, " · OFF" if off else ""]
		l.add_theme_color_override("font_color", CyberTheme.TEXT_DIM if off else s[1])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var eid := e.id
		var b := _button("On" if off else "Off", func() -> void: command.emit(&"power_toggle", eid))
		b.disabled = e.destroyed()
		row.add_child(b)
		_loads_box.add_child(row)


func _refresh_target(target: ShipState, boarding: BoardingAction, sim_time: float, close_look: bool) -> void:
	_target_map.systems = target.systems if target != null and close_look else null
	if target == null:
		_target_map.title = "NO CONTACT"
	elif close_look:
		_target_map.title = target.display_name
	else:
		_target_map.title = "%s — no close look (recon drone or < 3 km)" % target.display_name
	_target_map.room_overlay = {}
	var lines := PackedStringArray()
	if target != null and target.systems != null and close_look:
		lines.append(target.systems.status_line())
		if target.systems.is_disabled():
			lines.append(CyberTheme.tint("%s DISABLED — %s" % [CyberTheme.GLYPH_DESTROYED, target.systems.disabled_reason()], CyberTheme.MAGENTA))
		if target.systems.crew != null:
			lines.append("Crew %s" % target.systems.crew.summary())
	if boarding != null:
		var control := boarding.room_control()
		for room in control:
			_target_map.room_overlay[room] = ShipSchematic.control_color(control[room], sim_time)
		lines.append("[b]BOARDING[/b] %s · team %d/%d  (cyan taken · magenta fighting · red defended)" % [
			BoardingAction.PHASE_NAMES[boarding.phase].to_upper(), boarding.fit_team().size(), boarding.team.size()])
		for l in boarding.log.slice(maxi(boarding.log.size() - 5, 0)):
			lines.append(l)
	_target_label.text = "\n".join(lines)


## Free, fit crew to pick from (rebuilt only when that set changes).
func _refresh_reassign(sys: ShipSystems) -> void:
	var free := sys.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.available() and m.location >= 0) if sys.crew != null else []
	var key := ",".join(free.map(func(m: CrewRoster.Member) -> String: return "%s:%d" % [m.id, m.role]))
	if key == _reassign_key:
		return
	_reassign_key = key
	var keep: Variant = _reassign_pick.get_item_metadata(_reassign_pick.selected) if _reassign_pick.selected >= 0 else null
	_reassign_pick.clear()
	for m: CrewRoster.Member in free:
		_reassign_pick.add_item("%s — %s" % [m.label(), CrewRoster.ROLE_NAMES[m.role]])
		_reassign_pick.set_item_metadata(_reassign_pick.item_count - 1, m.id)
		if m.id == keep:
			_reassign_pick.select(_reassign_pick.item_count - 1)


func _crew_text(sys: ShipSystems) -> String:
	if sys.crew == null:
		return "No crew model."
	var command_state := CyberTheme.tint("● COMMAND OK", CyberTheme.CYAN) if sys.has_command() else CyberTheme.tint("▲ SHIP AI IN CONTROL", CyberTheme.AMBER)
	var lines := PackedStringArray(["%s   %s" % [sys.crew.summary(), command_state]])
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
		var who := sys.crew.by_id(id)
		lines.append(CyberTheme.tint("» %s → %s, %.0f s" % [who.label() if who != null else id, CrewRoster.ROLE_NAMES[sys.crew_orders[id].role], sys.crew_orders[id].left_s], CyberTheme.AMBER))
	return "\n".join(lines)


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
			status.add_theme_font_size_override("font_size", CyberTheme.SIZE_BODY)
			status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_wing_box.add_child(status)
			_wing_rows[c.id] = status
			var row := HFlowContainer.new()
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
		var ammo := " · ammo %d" % c.ammo if c.config.cannon != null else ""
		var state: String = AirWing.STATUS_NAMES[c.status].to_upper()
		if c.status == AirWing.Status.DOCKED and c.service_left_s > 0.0:
			state = "SERVICING %.0f s" % c.service_left_s
		label.text = "%s — %s · hull %d%% · fuel %d%%%s%s" % [c.label, state, roundi(c.hull_fraction * 100.0),
			roundi(c.propellant_fraction * 100.0), ammo, "  » " + c.override_reason if c.override_reason != "" else ""]
		label.add_theme_color_override("font_color", CyberTheme.RED if c.status == AirWing.Status.LOST else CyberTheme.TEXT)


# --- Helpers -------------------------------------------------------------------------

func _tab_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	_tabs.add_child(box)
	return box


func _picker(names: Array, selected: int, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.select(selected)
	o.item_selected.connect(on_pick)
	return o


func _heading(text: String, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"Heading"
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l


func _caption_label(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"Caption"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _rich(parent: Control, height: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.fit_content = true
	r.custom_minimum_size = Vector2(0, height)
	parent.add_child(r)
	return r


func _button(text: String, on_press: Callable, accent: Color = CyberTheme.CYAN) -> Button:
	var b := Button.new()
	b.text = text
	CyberTheme.style_button(b, accent)
	b.pressed.connect(on_press)
	return b
