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
const TAB_NAMES := ["DAMAGE", "CREW", "POWER", "WING", "TARGET", "CARGO", "WEAPONS", "POLICY"]
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
var _crew_map: ShipSchematic
var _crew_deck_row: HBoxContainer
var _crew_decks: Array[int] = []
var _crew_tree: Tree
var _crew_key := ""
## The crew member picked in the roster ("" = none), and where to send them.
var crew_selected := ""
var _crew_pick_label: Label
var _reassign_role: OptionButton
var _party_label: Label
## The profile (missile mode and order; set by the HUD).
var profile: PlayerProfile
var _missile_label: RichTextLabel
var _mode_buttons: Array[Button] = []
var _order_box: VBoxContainer
var _order_key := ""
## The encounter's ships (Hud.contact_rows) and the player's policy (set by the HUD).
var contacts: Array[Dictionary] = []
var policy: ShipPolicy
var _contacts_box: HFlowContainer
var _contacts_key := ""
var _policy_label: RichTextLabel
var _policy_box: VBoxContainer
var _policy_key := ""
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
	_build_weapons_tab()
	_build_policy_tab()
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


## Crew: who is where (a map with a dot per person, coloured by post), the
## roster by post, and the orders — send someone to a new post, cover a
## post with general crew, how to meet boarders, our boarding party.
func _build_crew_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	scroll.add_child(box)
	_crew_label = _rich(box, 18)
	_crew_deck_row = HBoxContainer.new()
	box.add_child(_crew_deck_row)
	_crew_map = ShipSchematic.new()
	_crew_map.custom_minimum_size = Vector2(0, 180)
	box.add_child(_crew_map)
	var legend := _rich(box, 16)
	legend.text = "%s   ○ wounded" % CrewRoster.role_legend()
	legend.add_theme_font_size_override("normal_font_size", CyberTheme.SIZE_SMALL)
	_crew_tree = Tree.new()
	_crew_tree.columns = 4
	_crew_tree.column_titles_visible = true
	for c in 4:
		_crew_tree.set_column_title(c, ["CREW", "POST", "WHERE", "STATUS"][c])
		_crew_tree.set_column_expand(c, c != 1)
	_crew_tree.hide_root = true
	_crew_tree.select_mode = Tree.SELECT_ROW
	_crew_tree.custom_minimum_size = Vector2(0, 240)
	_crew_tree.item_selected.connect(_on_crew_picked)
	box.add_child(_crew_tree)
	var send := HBoxContainer.new()
	_crew_pick_label = Label.new()
	_crew_pick_label.text = "Pick someone above"
	_crew_pick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_pick_label.clip_text = true
	send.add_child(_crew_pick_label)
	_reassign_role = OptionButton.new()
	for n in CrewRoster.ROLE_NAMES:
		_reassign_role.add_item("→ " + n)
	send.add_child(_reassign_role)
	send.add_child(_button("Send", func() -> void:
		if crew_selected != "":
			command.emit(&"reassign", [crew_selected, _reassign_role.selected])))
	box.add_child(send)
	box.add_child(_heading("COVER A POST", CyberTheme.CYAN))
	box.add_child(_caption_label("The nearest free general crew member walks to that post's station."))
	var cover := GridContainer.new()
	cover.columns = 4
	for role in COVERABLE:
		cover.add_child(_button(CrewRoster.ROLE_NAMES[role], func() -> void: command.emit(&"cover", role)))
	box.add_child(cover)
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
	_contacts_box = HFlowContainer.new()
	box.add_child(_contacts_box)
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
			_refresh_crew(sys)
			var collars := Docking.collars(sys)
			var can_go := BoardingAction.candidates(sys, collars[0].room if not collars.is_empty() else -1, party_size).size()
			_party_label.text = "  %d of up to %d · %d would go now  " % [party_size, BoardingAction.MAX_TEAM, can_go]
		2:
			_refresh_power(sys)
		3:
			_update_wing(wing)
		4:
			_refresh_target(target, boarding, sim_time, close_look)
		5:
			_refresh_cargo(sys)
		6:
			_refresh_weapons(sys)
		7:
			_refresh_policy()


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
	_refresh_contact_buttons()
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
	_target_map.hostile_crew = true
	_target_map.boarders = {}
	if boarding != null:
		var control := boarding.room_control()
		for room in control:
			_target_map.room_overlay[room] = ShipSchematic.control_color(control[room], sim_time)
		if boarding.room >= 0:
			_target_map.boarders[boarding.room] = boarding.fit_team()
		lines.append("[b]BOARDING[/b] %s · team %d/%d  (cyan taken · magenta fighting · red defended)" % [
			BoardingAction.PHASE_NAMES[boarding.phase].to_upper(), boarding.fit_team().size(), boarding.team.size()])
		for l in boarding.log.slice(maxi(boarding.log.size() - 5, 0)):
			lines.append(l)
	_target_label.text = "\n".join(lines)


## One button per ship of the encounter (the selected one marked ▸).
func _refresh_contact_buttons() -> void:
	var key := ",".join(contacts.map(func(c: Dictionary) -> String: return "%s%s%s" % [c.id, c.selected, c.state]))
	if key == _contacts_key:
		return
	_contacts_key = key
	for b in _contacts_box.get_children():
		b.queue_free()
	for c in contacts:
		var id: String = c.id
		var b := _button("%s%s · %s · %s" % ["▸ " if c.selected else "", c.name, c.state, c.role],
			func() -> void: command.emit(&"select_contact", id), CyberTheme.MAGENTA)
		_contacts_box.add_child(b)


# --- Policy ------------------------------------------------------------------------------

## Tab › POLICY: the ship's automation (ShipPolicy), on top of manual control
## — manual input always wins. Saved with the vessel.
func _build_policy_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	scroll.add_child(box)
	box.add_child(_heading("SHIP POLICY — automation on top of your controls", CyberTheme.CYAN))
	box.add_child(_caption_label("Manual input always wins: your trigger and M fire whatever the policy says; automation only adds."))
	_policy_label = _rich(box, 36)
	_policy_box = VBoxContainer.new()
	box.add_child(_policy_box)


func _refresh_policy() -> void:
	if policy == null:
		_policy_label.text = "No policy."
		return
	_policy_label.text = policy.summary()
	var key := JSON.stringify(policy.to_dict())
	if key == _policy_key:
		return
	_policy_key = key
	for c in _policy_box.get_children():
		c.queue_free()
	var row := func(label: String) -> HBoxContainer:
		var r := HBoxContainer.new()
		var l := Label.new()
		l.text = label
		l.custom_minimum_size = Vector2(150, 0)
		r.add_child(l)
		_policy_box.add_child(r)
		return r
	var set_value := func(field: String, value: Variant) -> void: command.emit(&"policy_set", [field, value])
	var stepper := func(r: HBoxContainer, field: String, value: float, step: float, text: String) -> void:
		r.add_child(_button("−", func() -> void: set_value.call(field, value - step)))
		var v := Label.new()
		v.text = "  %s  " % text
		r.add_child(v)
		r.add_child(_button("+", func() -> void: set_value.call(field, value + step)))
	var presets: HBoxContainer = row.call("Preset")
	for name in ShipPolicy.PRESETS:
		presets.add_child(_button(("▸ " if policy.preset_name == name else "") + name, func() -> void: command.emit(&"policy_preset", name)))
	var disc: HBoxContainer = row.call("Fire discipline")
	for d in ShipPolicy.Discipline.size():
		disc.add_child(_button(("▸ " if policy.discipline == d else "") + ShipPolicy.DISCIPLINE_NAMES[d], func() -> void: set_value.call("discipline", d),
			CyberTheme.AMBER))
	_policy_box.add_child(_heading("POINT DEFENCE", CyberTheme.CYAN))
	var pd: HBoxContainer = row.call("Auto point defence")
	pd.add_child(_button("ON" if policy.pd_enabled else "OFF", func() -> void: set_value.call("pd_enabled", not policy.pd_enabled)))
	var order := policy.pd_order()
	for i in order.size():
		var r: HBoxContainer = row.call("  %d. %s" % [i + 1, ShipPolicy.PD_KIND_NAMES[order[i]]])
		var kind := order[i]
		var up := _button("↑ earlier", func() -> void: command.emit(&"pd_order_up", String(kind)))
		up.disabled = i == 0
		r.add_child(up)
	stepper.call(row.call("Engagement range"), "pd_range_m", policy.pd_range_m, 250.0, HudFormat.distance(policy.pd_range_m))
	stepper.call(row.call("Ammo reserve"), "pd_reserve_fraction", policy.pd_reserve_fraction, 0.05,
		"%d %% (first priority only)" % roundi(policy.pd_reserve_fraction * 100.0))
	_policy_box.add_child(_heading("AUTO-SALVO (selected contact)", CyberTheme.AMBER))
	var sv: HBoxContainer = row.call("Auto-salvo")
	sv.add_child(_button("ON" if policy.salvo_enabled else "OFF", func() -> void: set_value.call("salvo_enabled", not policy.salvo_enabled)))
	stepper.call(row.call("Lock quality ≥"), "salvo_min_confidence", policy.salvo_min_confidence, 0.1,
		"%d %%" % roundi(policy.salvo_min_confidence * 100.0))
	stepper.call(row.call("Range from"), "salvo_min_range_m", policy.salvo_min_range_m, 1000.0, HudFormat.distance(policy.salvo_min_range_m))
	stepper.call(row.call("Range to"), "salvo_max_range_m", policy.salvo_max_range_m, 1000.0, HudFormat.distance(policy.salvo_max_range_m))
	var mode: HBoxContainer = row.call("Warheads")
	mode.add_child(_button(MissileSalvo.MODE_NAMES[clampi(policy.salvo_mode, 0, MissileSalvo.MODE_NAMES.size() - 1)],
		func() -> void: set_value.call("salvo_mode", (policy.salvo_mode + 1) % MissileSalvo.Mode.size()), CyberTheme.AMBER))
	stepper.call(row.call("Missiles a salvo"), "salvo_count", float(policy.salvo_count), 1.0,
		str(policy.salvo_count) if policy.salvo_count > 0 else "all")
	stepper.call(row.call("Interval"), "salvo_interval_s", policy.salvo_interval_s, 5.0, "%.0f s" % policy.salvo_interval_s)
	_policy_box.add_child(_heading("AUTO-FIRE (guns)", CyberTheme.AMBER))
	var af: HBoxContainer = row.call("Auto-fire")
	af.add_child(_button("ON" if policy.autofire_enabled else "OFF", func() -> void: set_value.call("autofire_enabled", not policy.autofire_enabled)))
	stepper.call(row.call("Tolerance"), "autofire_tolerance_deg", policy.autofire_tolerance_deg, 0.1, "%.1f°" % policy.autofire_tolerance_deg)
	_policy_box.add_child(_caption_label("Auto-fire pulls the trigger while your aim is on the lead within the tolerance and you hold a lock; discipline TIGHT fires only at hostile contacts, HOLD never."))


func _refresh_crew(sys: ShipSystems) -> void:
	if sys.crew == null:
		_crew_label.text = "No crew model."
		return
	_crew_label.text = "%s   %s" % [sys.crew.summary(),
		CyberTheme.tint("● COMMAND OK", CyberTheme.CYAN) if sys.has_command() else CyberTheme.tint("▲ SHIP AI IN CONTROL", CyberTheme.AMBER)]
	_crew_map.systems = sys
	_crew_map.highlight_member = crew_selected
	_deck_buttons_for(sys, _crew_deck_row, _crew_decks, _crew_map)
	_crew_map.title = "CREW · ALL DECKS" if _crew_map.deck < 0 else "CREW · DECK %d" % _crew_map.deck
	var key := ""
	for m in sys.crew.members:
		key += "%s%d%d%d%d|" % [m.id, m.role, m.state, m.location, int(m.busy)]
	for id in sys.crew_orders:
		key += "%s>%d:%d|" % [id, sys.crew_orders[id].role, ceili(sys.crew_orders[id].left_s)]
	if key != _crew_key:
		_crew_key = key
		_fill_crew_tree(sys)


## The roster as a tree: one branch per post (fit / everyone), a row per
## person — name and skill, post, room, and what they are doing.
func _fill_crew_tree(sys: ShipSystems) -> void:
	_crew_tree.clear()
	var root := _crew_tree.create_item()
	for role in CrewRoster.Role.size():
		var people := sys.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.role == role)
		if people.is_empty():
			continue
		var fit := people.filter(func(m: CrewRoster.Member) -> bool: return m.fit()).size()
		var head := _crew_tree.create_item(root)
		head.set_text(0, "%s  %d/%d fit" % [str(CrewRoster.ROLE_NAMES[role]).to_upper(), fit, people.size()])
		head.set_custom_color(0, CrewRoster.ROLE_COLORS[role])
		head.set_metadata(0, "")
		head.set_selectable(0, false)
		for c in range(1, 4):
			head.set_selectable(c, false)
		for m: CrewRoster.Member in people:
			var row := _crew_tree.create_item(head)
			row.set_text(0, "● %s%s" % [m.label(), "  " + "★".repeat(m.skill) if m.skill > 0 else ""])
			row.set_custom_color(0, CrewRoster.ROLE_COLORS[m.role] if m.state != CrewRoster.State.DEAD else CyberTheme.TEXT_FAINT)
			row.set_text(1, CrewRoster.ROLE_SHORT[m.role])
			row.set_text(2, "%s %s" % [sys.blueprint.rooms[m.location].id, sys.room_role(m.location)] if m.location >= 0 else "off the ship")
			row.set_text(3, crew_status(sys, m))
			var status_color := CyberTheme.TEXT if m.state == CrewRoster.State.FIT else (CyberTheme.AMBER if m.state == CrewRoster.State.WOUNDED else CyberTheme.RED)
			row.set_custom_color(3, status_color)
			row.set_metadata(0, m.id)
			if m.id == crew_selected:
				row.select(0)


## What a crew member is doing, in a few words.
static func crew_status(sys: ShipSystems, m: CrewRoster.Member) -> String:
	if m.state == CrewRoster.State.DEAD:
		return "killed"
	var state := "wounded" if m.state == CrewRoster.State.WOUNDED else "fit"
	if sys.crew_orders.has(m.id):
		return "%s · → %s, %.0f s" % [state, CrewRoster.ROLE_NAMES[sys.crew_orders[m.id].role], sys.crew_orders[m.id].left_s]
	if m.location < 0:
		return "%s · boarding party" % state
	if m.busy:
		return "%s · on a task" % state
	return state if m.location == m.station else "%s · away from post" % state


func _on_crew_picked() -> void:
	var item := _crew_tree.get_selected()
	crew_selected = str(item.get_metadata(0)) if item != null and item.get_metadata(0) != null else ""
	if crew_selected != "" and _sys != null and _sys.crew != null:
		var m := _sys.crew.by_id(crew_selected)
		_crew_pick_label.text = "%s (%s) — send to:" % [m.label(), CrewRoster.ROLE_NAMES[m.role]] if m != null else "Pick someone above"
	else:
		_crew_pick_label.text = "Pick someone above"


## Deck buttons for `map` ("All decks" first), rebuilt when the decks change.
func _deck_buttons_for(sys: ShipSystems, row: HBoxContainer, known: Array[int], map: ShipSchematic) -> void:
	var decks: Array[int] = [-1]
	var b := sys.grid.cell_bounds()
	for d in range(int(b.end.y) - 1, int(b.position.y) - 1, -1):
		decks.append(d)
	if decks == known:
		return
	known.assign(decks)
	for c in row.get_children():
		c.queue_free()
	for d in decks:
		row.add_child(_button("All decks" if d < 0 else "Deck %d" % d, func() -> void: map.deck = d))


# --- Weapons ---------------------------------------------------------------------------

func _build_weapons_tab() -> void:
	var box := _tab_box()
	box.add_child(_heading("MISSILES — [M] salvo · [,] mode", CyberTheme.AMBER))
	_missile_label = _rich(box, 60)
	box.add_child(_caption_label("What one press of M fires (M again holds the rest of the salvo):"))
	var modes := HFlowContainer.new()
	for mode in MissileSalvo.Mode.size():
		var b := _button(MissileSalvo.MODE_NAMES[mode], func() -> void: command.emit(&"missile_mode", mode), CyberTheme.AMBER)
		_mode_buttons.append(b)
		modes.add_child(b)
	box.add_child(modes)
	box.add_child(_heading("SEQUENCE ORDER", CyberTheme.AMBER))
	box.add_child(_caption_label("In sequence mode every missile of the first warhead goes, then the next — e.g. EMP first to blind their point defence."))
	_order_box = VBoxContainer.new()
	box.add_child(_order_box)


func _refresh_weapons(sys: ShipSystems) -> void:
	var lines := PackedStringArray()
	for e in sys.equipment:
		if e.def.kind != EquipmentDefinition.Kind.MISSILE_LAUNCHER or e.def.missile == null:
			continue
		var state := "ready"
		if e.destroyed():
			state = CyberTheme.tint("✕ destroyed", CyberTheme.RED)
		elif e.disrupted_s > 0.0:
			state = CyberTheme.tint("▲ EMP reset %.0f s" % e.disrupted_s, CyberTheme.AMBER)
		elif not e.powered:
			state = CyberTheme.tint("○ no power", CyberTheme.TEXT_DIM)
		elif sys.missiles_left(e) == 0:
			state = CyberTheme.tint("empty", CyberTheme.TEXT_DIM)
		lines.append("%s %s — %d/%d %s%s · %s" % [e.def.display_name, e.id, sys.missiles_left(e), e.def.missile_capacity,
			MissileSalvo.WARHEAD_NAMES[e.def.missile.warhead], " (%d a launch)" % e.def.missile_salvo if e.def.missile_salvo > 1 else "", state])
	if lines.is_empty():
		lines.append(CyberTheme.tint("No launchers fitted — the shipyard's Weapons palette has them.", CyberTheme.TEXT_DIM))
	var mode := profile.missile_mode if profile != null else 0
	var order: Array = profile.missile_order if profile != null else MissileSalvo.DEFAULT_ORDER
	lines.append("Mode: %s" % CyberTheme.tint(MissileSalvo.mode_text(mode, order).to_upper(), CyberTheme.AMBER))
	_missile_label.text = "\n".join(lines)
	for i in _mode_buttons.size():
		_mode_buttons[i].text = ("▸ " if i == mode else "") + MissileSalvo.MODE_NAMES[i]
	var key := MissileSalvo.order_text(order)
	if key == _order_key:
		return
	_order_key = key
	for c in _order_box.get_children():
		c.queue_free()
	var sorted := MissileSalvo.sanitize_order(order)
	for i in sorted.size():
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%d. %s" % [i + 1, MissileSalvo.WARHEAD_NAMES[sorted[i]]]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var w := sorted[i]
		var up := _button("↑ earlier", func() -> void: command.emit(&"missile_order_up", w), CyberTheme.AMBER)
		up.disabled = i == 0
		row.add_child(up)
		_order_box.add_child(row)


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
