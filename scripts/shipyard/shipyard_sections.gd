class_name ShipyardSections
extends RefCounted
## The shipyard as a station (Milestone 12; play-test batch 6: "more
## gameplay and immersive, less spreadsheet tabs"). A station directory
## down the left lists its places by district — DRYDOCK (the berth, the
## refit bay, repair crews, the armoury), CONCOURSE (the mission board, crew
## quarters, the ship dealer), OPERATIONS (hangar and bank, station tech,
## the nav chart, salvage odds) — each with a live line saying what it
## needs from you (amber) or that it is fine. STATION is your berth: the
## ship in a docking bay, its service tags over the view and the
## dockmaster's log. Each place is a page; the builder (REFIT) is one of
## them, with the directory narrowed beside it.

const SECTIONS := ["STATION", "MISSIONS", "DEALER", "HANGAR", "REFIT", "CREW", "SERVICES", "QUARTERMASTER", "UPGRADES", "MAP", "LOOT"]
const START := "STATION"
const HINTS := {
	"STATION": "Your ship, what it needs, the next sortie",
	"MISSIONS": "People at the yard with work — contracts",
	"DEALER": "Ships for credits, crew included",
	"HANGAR": "Your vessels and their service record",
	"REFIT": "Design and refit: the builder",
	"CREW": "Who serves aboard, who rests ashore, who is for hire",
	"SERVICES": "Repair, rearm and refuel — and the cargo hold",
	"QUARTERMASTER": "Parts and spare parts for sale",
	"UPGRADES": "Station technology for your ships",
	"MAP": "Where you launch from, how many you meet",
	"LOOT": "Every crate drop and its odds",
}

## The directory: [district, [[section, place name], ...]].
const DIRECTORY := [
	["DRYDOCK", [["STATION", "Berth"], ["REFIT", "Refit bay"], ["SERVICES", "Service bay"]]],
	["CONCOURSE", [["MISSIONS", "Mission board"], ["CREW", "Crew manifest"], ["DEALER", "Ship dealer"], ["QUARTERMASTER", "Quartermaster"]]],
	["OPERATIONS", [["HANGAR", "Hangar & bank"], ["UPGRADES", "Station tech"], ["MAP", "Nav chart"], ["LOOT", "Salvage odds"]]],
]
const DIRECTORY_WIDTH := 232.0
const DIRECTORY_WIDTH_REFIT := 150.0

var yard: Shipyard
var current := ""
var buttons: Dictionary = {}  # section -> Button (its directory entry)
var status_labels: Dictionary = {}  # section -> Label (its live line)
var _dots: Dictionary = {}  # section -> Label (● needs you / fine)
var directory: PanelContainer
var wallet_label: RichTextLabel
var pages: Dictionary = {}  # section -> Control (REFIT: the builder body)
## STATION.
var station_label: RichTextLabel
var station_preview: ShipPreview3D
var station_cards: Dictionary = {}  # key -> RichTextLabel
var station_buttons: Dictionary = {}  # key -> Button
## MISSIONS.
var missions_box: VBoxContainer
var accept_buttons: Dictionary = {}  # contract id -> Button
var abandon_button: Button
## DEALER: one card per template, three across (play-test batch 11).
const DEALER_COLUMNS := 3
const DEALER_SHOT_H := 150.0
var dealer_box: GridContainer
var dealer_rows: Dictionary = {}  # template path -> Button (buy)
## What the dealer knows of each template — {bp, editor, price, capital,
## text} by path — worked out once a session (templates don't change while
## the game runs; a super-heavy takes ~0.3 s to load, check and price). The
## cards are built the first time the dealer opens; a card shows its
## catalogue picture (DealerShots) — or, the first time, builds its 3D view
## (~0.2 s for a super-heavy) once it scrolls into view and keeps a picture
## of it.
static var _templates: Dictionary = {}
var _dealer_filled := false
var _dealer_order: Array[int] = []  # the cards' prices, in the order shown
var _dealer_views: Dictionary = {}  # path -> the card's 3D view, not built yet
var _dealer_scroll: ScrollContainer
## SERVICES: a big button each to repair, rearm and refuel, what each costs.
var service_labels: Dictionary = {}  # repair / rearm / refuel -> RichTextLabel
var service_buttons: Dictionary = {}  # repair / rearm / refuel -> Button
## HANGAR.
var scrap_button: Button
## The station bank (play-test batch 9).
var bank_label: RichTextLabel
var bank_box: VBoxContainer
var bank_amount: SpinBox
var fleet_box: HFlowContainer
## Builder-only controls in the top bar (hidden outside REFIT).
var _builder_bar: Array[Control] = []


func _init(p_yard: Shipyard) -> void:
	yard = p_yard


## Build the directory and the pages; move the old right-hand tabs' pages
## into full-width sections.
func build() -> void:
	var vbox := yard.get_node("Margin/VBox") as VBoxContainer
	var body := yard.get_node("Margin/VBox/Body") as Control
	var bar := yard.get_node("Margin/VBox/TopBar")
	for n in ["NameEdit", "DesignList", "LoadDesign", "Undo", "Redo", "Save"]:
		_builder_bar.append(bar.get_node(n))
	var concourse := HBoxContainer.new()
	concourse.name = "Concourse"
	concourse.size_flags_vertical = Control.SIZE_EXPAND_FILL
	concourse.add_theme_constant_override("separation", CyberTheme.SPACE_M)
	vbox.add_child(concourse)
	vbox.move_child(concourse, body.get_index())
	directory = _build_directory()
	concourse.add_child(directory)
	var stage := VBoxContainer.new()
	stage.name = "Stage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	concourse.add_child(stage)
	body.reparent(stage, false)
	pages["REFIT"] = body
	for s in SECTIONS:
		if s == "REFIT":
			continue
		var page := PanelContainer.new()
		page.name = "Page" + s.capitalize().replace(" ", "")
		page.add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.CYAN, CyberTheme.SPACE_M))
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = false
		stage.add_child(page)
		pages[s] = page
	_build_station()
	_build_missions()
	_build_dealer()
	_build_services()
	_adopt_hangar_tabs()
	_build_bank()


# --- The directory ----------------------------------------------------------------

func _build_directory() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Directory"
	panel.custom_minimum_size = Vector2(DIRECTORY_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.CYAN, CyberTheme.SPACE_S, 0.5))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", CyberTheme.SPACE_XS)
	scroll.add_child(box)
	wallet_label = _rich()
	wallet_label.add_theme_font_override("normal_font", CyberTheme.mono())
	wallet_label.add_theme_font_size_override("normal_font_size", CyberTheme.SIZE_SMALL)
	box.add_child(wallet_label)
	for district: Array in DIRECTORY:
		var head := Label.new()
		head.text = district[0]
		head.add_theme_font_override("font", CyberTheme.mono())
		head.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL)
		head.add_theme_color_override("font_color", CyberTheme.TEXT_FAINT)
		box.add_child(head)
		for entry: Array in district[1]:
			box.add_child(_directory_entry(entry[0], entry[1]))
	return panel


## One place: a button with its name and its live line.
func _directory_entry(section: String, title: String) -> Button:
	var b := Button.new()
	b.name = "Go" + section.capitalize().replace(" ", "")
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = HINTS.get(section, "")
	b.custom_minimum_size = Vector2(0, 46)
	CyberTheme.style_button(b, CyberTheme.AMBER if section in ["REFIT", "MISSIONS"] else CyberTheme.CYAN)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = CyberTheme.SPACE_S
	row.offset_right = -CyberTheme.SPACE_XS
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	b.add_child(row)
	var dot := Label.new()
	dot.text = "●"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_color_override("font_color", CyberTheme.TEXT_FAINT)
	row.add_child(dot)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var place := Label.new()
	place.text = title
	place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place.add_theme_font_size_override("font_size", CyberTheme.SIZE_BODY + 1)
	place.add_theme_color_override("font_color", CyberTheme.TEXT)
	col.add_child(place)
	var status := Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_override("font", CyberTheme.mono())
	status.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL)
	status.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
	col.add_child(status)
	b.pressed.connect(func() -> void: yard.show_section(section))
	buttons[section] = b
	status_labels[section] = status
	_dots[section] = dot
	return b


## Each place's live line, and whether it needs you: {section: [text, bool]}.
func directory_status() -> Dictionary:
	var p := yard.profile
	var v := p.vessel
	var cat := yard.editor.catalog
	ContractBoard.refresh(p)
	if p.hire_pool.is_empty() and p.vendor_stock.is_empty():
		p.refresh_station(cat)
	var jobs := ServiceYard.repair_jobs(v, cat)
	var need := ServiceYard.resupply_needs(v, cat)
	var berths := p.berths(cat)
	var held := v.cargo_volume_m3(cat)
	var affordable := 0
	for n in TechTree.NODES:
		var cost := TechTree.next_cost(p.tech_level(n.id), n.id)
		if cost > 0 and cost <= p.credits and TechTree.block_reason(n.id, p.tech) == "":
			affordable += 1
	var here := Location.by_id(p.location)
	return {
		"STATION": [v.name, false],
		"REFIT": [v.blueprint.name, false],
		"SERVICES": ["%s%s" % ["%d job%s · " % [jobs.size(), "" if jobs.size() == 1 else "s"] if not jobs.is_empty() else "",
			"restock %d cr" % need.credits if int(need.credits) > 0 else "stocked"], true] if not jobs.is_empty() or int(need.credits) > 0
			else ["repaired, armed, fuelled", false],
		"QUARTERMASTER": ["%d on the shelf · %d parts" % [p.vendor_stock.size(), p.spare_parts], false],
		"MISSIONS": ["on contract · %s" % p.active_contract.title, false] if not p.active_contract.is_empty() else ["%d offers posted" % p.board.size(), not p.board.is_empty()],
		"CREW": ["%d / %d aboard · %d resting" % [v.crew.size(), berths, p.resting.size()], v.crew.size() < berths],
		"DEALER": ["%d hulls for sale" % BlueprintIO.list_templates().size(), false],
		"HANGAR": ["%d vessel%s%s" % [p.vessels.size(), "" if p.vessels.size() == 1 else "s",
			" · owe %d cr" % p.debt() if p.debt() > 0 else (" · %d cr deposited" % p.bank_deposit if p.bank_deposit > 0 else "")], held > 0.0 or p.debt() > 0],
		"UPGRADES": ["%d upgrade%s within reach" % [affordable, "" if affordable == 1 else "s"], affordable > 0],
		"MAP": [("→ %s · %s" % [Location.by_id(p.launch_point()).display_name, JumpDrive.dv_text(p.jump_dv(p.launch_point()))])
			if p.launch_point() != p.location else "%s · %d ship%s" % [here.display_name, p.encounter_size, "" if p.encounter_size == 1 else "s"], false],
		"LOOT": ["every crate's odds", false],
	}


func _refresh_directory() -> void:
	var refit := current == "REFIT"
	directory.custom_minimum_size.x = DIRECTORY_WIDTH_REFIT if refit else DIRECTORY_WIDTH
	var p := yard.profile
	wallet_label.text = "[color=#%s]%s[/color]\nCREDITS [color=#%s]%d[/color] · PARTS %d" % [CyberTheme.TEXT_DIM.to_html(false),
		Location.by_id(p.location).station_name.to_upper(), CyberTheme.AMBER.to_html(false), p.credits, p.spare_parts]
	for s in status_labels:
		(status_labels[s] as Label).visible = not refit
	if refit:
		return  # the builder refreshes on every edit: no need to work these out
	var status := directory_status()
	for s in status:
		var line: Array = status[s]
		(status_labels[s] as Label).text = line[0]
		(status_labels[s] as Label).add_theme_color_override("font_color", CyberTheme.AMBER if line[1] else CyberTheme.TEXT_DIM)
		(_dots[s] as Label).add_theme_color_override("font_color", CyberTheme.AMBER if line[1] else CyberTheme.CYAN)


## A titled card (a framed panel); returns its content box.
static func card(parent: Control, title: String, accent: Color = CyberTheme.CYAN, min_size := Vector2.ZERO) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CyberTheme.panel(accent, CyberTheme.SPACE_S, 0.6))
	panel.custom_minimum_size = min_size
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_XS)
	panel.add_child(box)
	if title != "":
		var t := Label.new()
		t.text = title
		t.add_theme_color_override("font_color", accent)
		t.add_theme_font_size_override("font_size", CyberTheme.SIZE_TITLE)
		box.add_child(t)
	parent.add_child(panel)
	return box


static func _rich(min_width: float = 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(min_width, 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## The old right-hand tabs (SERVICE, CARGO & BANK, HISTORY, LOOT TABLES,
## MAP, CREW, QUARTERMASTER, UPGRADES) become sections of their own.
func _adopt_hangar_tabs() -> void:
	var tabs := yard._hangar_tabs
	var where := {"SERVICE": "SERVICES", "CARGO & BANK": "SERVICES", "HISTORY": "HANGAR", "LOOT TABLES": "LOOT", "MAP": "MAP",
		"CREW": "CREW", "QUARTERMASTER": "QUARTERMASTER", "UPGRADES": "UPGRADES"}
	var titles := {"SERVICE": "Damage report", "CARGO & BANK": "Cargo hold", "HISTORY": "Service record",
		"QUARTERMASTER": "Quartermaster: parts for sale"}
	var columns := {}  # section -> HBoxContainer (several old tabs side by side)
	for child in tabs.get_children():
		var section: String = where.get(String(child.name), "")
		if section == "":
			continue
		tabs.remove_child(child)
		var page := child as Control
		page.visible = true
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var holder: Control = _content(section)
		if section in ["HANGAR", "SERVICES"]:
			if not columns.has(section):
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", CyberTheme.SPACE_M)
				row.size_flags_vertical = Control.SIZE_EXPAND_FILL
				holder.add_child(row)
				columns[section] = row
			holder = columns[section]
		if titles.has(String(child.name)):
			var box := card(holder, titles[String(child.name)])
			box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
			box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			box.add_child(page)
		else:
			holder.add_child(page)
	# The vessel picker and "New ship" go to the hangar page, with Scrap,
	# and a card per vessel above the hold and the history.
	var title: Control = yard.vessel_picker.get_parent()
	title.get_parent().remove_child(title)
	var hangar: Control = _content("HANGAR")
	hangar.add_child(title)
	hangar.move_child(title, 1)
	scrap_button = Button.new()
	scrap_button.text = "Scrap this vessel"
	CyberTheme.style_button(scrap_button, CyberTheme.RED)
	scrap_button.pressed.connect(func() -> void: yard.scrap_active())
	title.add_child(scrap_button)
	fleet_box = HFlowContainer.new()
	fleet_box.add_theme_constant_override("h_separation", CyberTheme.SPACE_S)
	fleet_box.add_theme_constant_override("v_separation", CyberTheme.SPACE_S)
	hangar.add_child(fleet_box)
	hangar.move_child(fleet_box, 2)
	tabs.get_parent().remove_child(tabs)
	tabs.queue_free()
	yard._hangar_tabs = null


## The content box of a section's page (made on first use), under its heading.
func _content(section: String) -> VBoxContainer:
	var page: Control = pages[section]
	if page.get_child_count() > 0:
		return page.get_child(0) as VBoxContainer
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	var heading := Label.new()
	heading.theme_type_variation = &"Heading"
	heading.text = "%s  ›  %s  ·  %s" % [district_of(section), place_name(section).to_upper(), HINTS.get(section, "")]
	box.add_child(heading)
	page.add_child(box)
	return box


static func district_of(section: String) -> String:
	for d: Array in DIRECTORY:
		for e: Array in d[1]:
			if e[0] == section:
				return d[0]
	return ""


static func place_name(section: String) -> String:
	for d: Array in DIRECTORY:
		for e: Array in d[1]:
			if e[0] == section:
				return e[1]
	return section


func show(section: String) -> void:
	if not pages.has(section):
		return
	current = section
	for s in pages:
		(pages[s] as Control).visible = s == section
		(buttons[s] as Button).set_pressed_no_signal(s == section)
	for c in _builder_bar:
		c.visible = section == "REFIT"
	refresh()


# --- STATION ----------------------------------------------------------------------

## The berth: the ship in its docking bay filling the page; over it, its
## plate (top left), the services and the next sortie (right), and the
## dockmaster's log (bottom left).
func _build_station() -> void:
	var box := _content("STATION")
	station_label = _rich()
	station_label.add_theme_font_size_override("normal_font_size", CyberTheme.SIZE_BODY + 1)
	box.add_child(station_label)
	var bay := Control.new()
	bay.name = "Berth"
	bay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bay.custom_minimum_size = Vector2(0, 360)
	bay.clip_contents = true
	box.add_child(bay)
	station_preview = ShipPreview3D.new()
	station_preview.berth = true
	station_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bay.add_child(station_preview)
	var plate := VBoxContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	plate.position = Vector2(CyberTheme.SPACE_L, CyberTheme.SPACE_M)
	plate.custom_minimum_size = Vector2(460, 0)
	bay.add_child(plate)
	station_cards["ship"] = _rich()
	station_cards["ship"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(station_cards["ship"])
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -SERVICE_WIDTH - CyberTheme.SPACE_M
	side.offset_right = -CyberTheme.SPACE_M
	side.offset_top = CyberTheme.SPACE_M
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bay.add_child(side)
	for spec in [["repairs", "Repairs", "SERVICES", CyberTheme.AMBER], ["rearm", "Rearm & refuel", "SERVICES", CyberTheme.AMBER],
			["crew", "Crew manifest", "CREW", CyberTheme.CYAN], ["sortie", "Next sortie", "MISSIONS", CyberTheme.AMBER]]:
		var c := card(side, spec[1], spec[3])
		var label := _rich()
		c.add_child(label)
		station_cards[spec[0]] = label
		var b := Button.new()
		CyberTheme.style_button(b, spec[3])
		var target: String = spec[2]
		b.pressed.connect(func() -> void: yard.show_section(target))
		c.add_child(b)
		station_buttons[spec[0]] = b
	var log_box := card(bay, "Dockmaster's log", CyberTheme.CYAN)
	var log_panel := log_box.get_parent() as Control
	# Pinned to the bottom left, as tall as its lines.
	log_panel.anchor_left = 0.0
	log_panel.anchor_right = 0.0
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_panel.offset_left = CyberTheme.SPACE_L
	log_panel.offset_right = CyberTheme.SPACE_L + 560.0
	log_panel.offset_top = -CyberTheme.SPACE_M
	log_panel.offset_bottom = -CyberTheme.SPACE_M
	station_cards["log"] = _rich()
	station_cards["log"].add_theme_font_override("normal_font", CyberTheme.mono())
	station_cards["log"].add_theme_font_size_override("normal_font_size", CyberTheme.SIZE_SMALL)
	log_box.add_child(station_cards["log"])


const SERVICE_WIDTH := 330.0


## What the station's people have to say about your ship this visit.
func _dock_log() -> String:
	var p := yard.profile
	var v := p.vessel
	var cat := yard.editor.catalog
	var dim := CyberTheme.TEXT_DIM.to_html(false)
	var lines := PackedStringArray()
	var say := func(who: String, what: String) -> void:
		lines.append("[color=#%s]%-14s[/color] %s" % [dim, who, what])
	say.call("DOCKMASTER", "%s in berth %d, clamps locked%s." % [v.name, 4 + p.active_vessel, ", welcome back" if v.sorties > 0 else ""])
	var jobs := ServiceYard.repair_jobs(v, cat)
	say.call("REPAIR CREWS", "hull signed off, nothing to fix." if jobs.is_empty() else "%d job%s waiting — %d spare parts for the lot." % [
		jobs.size(), "" if jobs.size() == 1 else "s", ServiceYard.total_cost(jobs)])
	var best: EquipmentDefinition = null
	for item: Dictionary in p.vendor_stock:
		var def: EquipmentDefinition = cat.equipment.get(StringName(item.id))
		if def != null and (best == null or def.rarity > best.rarity):
			best = def
	say.call("QUARTERMASTER", "a %s just came in (%s)." % [best.display_name, Rarity.name_of(best.rarity).to_lower()] if best != null else "shelves bare until the next freighter.")
	if not p.active_contract.is_empty():
		say.call("BROKERS", "your contract stands: %s." % p.active_contract.title)
	elif not p.board.is_empty():
		say.call("BROKERS", "%d contract%s posted; \"%s\" pays %s." % [p.board.size(), "" if p.board.size() == 1 else "s", p.board[0].title, MissionChain.reward_text(p.board[0])])
	if not p.hire_pool.is_empty():
		say.call("CREW QUARTERS", "%d spacer%s looking for a berth." % [p.hire_pool.size(), "" if p.hire_pool.size() == 1 else "s"])
	return "\n".join(lines)


func _refresh_station() -> void:
	var p := yard.profile
	var v := p.vessel
	var cat := yard.editor.catalog
	var here := Location.by_id(p.location)
	station_label.text = "[b]%s[/b] · %s · docked     CREDITS [color=#%s]%d[/color] · SPARE PARTS %d" % [
		here.station_name.to_upper(), here.display_name, CyberTheme.AMBER.to_html(false), p.credits, p.spare_parts]
	var grid := ShipGrid.build(v.blueprint, cat)
	var stats := ShipStats.compute(v.blueprint, grid)
	station_preview.show_design(ShipEditor.new(v.blueprint.duplicate_blueprint(), cat))
	(station_cards.ship as RichTextLabel).text = "[font_size=%d][b]%s[/b][/font_size]\n[color=#%s]%s · %d sortie%s[/color]\n%.0f t · %.2f g · Δv %.0f m/s · cargo %.0f m³" % [
		CyberTheme.SIZE_TITLE + 9, v.name.to_upper(), CyberTheme.TEXT_DIM.to_html(false), v.blueprint.name, v.sorties, "" if v.sorties == 1 else "s",
		stats.mass_kg / 1000.0, stats.thrust_forward_n / maxf(stats.mass_kg, 1.0) / ShipDynamics.G0, stats.delta_v_m_s(), stats.cargo_m3]
	(station_cards.log as RichTextLabel).text = _dock_log()
	var jobs := ServiceYard.repair_jobs(v, cat)
	(station_cards.repairs as RichTextLabel).text = CyberTheme.tint("✔ in full repair", CyberTheme.CYAN) if jobs.is_empty() \
		else "%d jobs · %d spare parts for everything" % [jobs.size(), ServiceYard.total_cost(jobs)]
	(station_buttons.repairs as Button).text = "Service bay ›"
	var need := ServiceYard.resupply_needs(v, cat)
	(station_cards.rearm as RichTextLabel).text = CyberTheme.tint("✔ full", CyberTheme.CYAN) if int(need.credits) == 0 \
		else "%d credits to fill propellant, rounds, missiles and flares (or at launch)" % need.credits
	(station_buttons.rearm as Button).text = "Service bay ›"
	(station_cards.crew as RichTextLabel).text = "%d / %d aboard · %d for hire" % [v.crew.size(), stats.crew_capacity, p.hire_pool.size()]
	(station_buttons.crew as Button).text = "Crew manifest ›"
	var contract := p.active_contract
	var course := Location.by_id(p.launch_point())
	var where := here.display_name if course == here else "jump to %s (%s) at launch" % [course.display_name, JumpDrive.dv_text(p.jump_dv(course.id))]
	(station_cards.sortie as RichTextLabel).text = "%s · %d ship%s\n%s" % [where, p.encounter_size, "" if p.encounter_size == 1 else "s",
		("CONTRACT  %s — %s" % [contract.title, MissionChain.reward_text(contract)]) if not contract.is_empty()
		else CyberTheme.tint(MissionChain.from_dict(p.campaign).hud_line(), CyberTheme.TEXT_DIM)]
	(station_buttons.sortie as Button).text = "Mission board ›"


# --- MISSIONS ---------------------------------------------------------------------

func _build_missions() -> void:
	var box := _content("MISSIONS")
	var note := Label.new()
	note.text = "Accept a contract and it becomes your next sortie: it sets where you fly, how many ships you meet and how dangerous they are, and pays when its goal is met. New offers after every sortie."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
	box.add_child(note)
	missions_box = VBoxContainer.new()
	missions_box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	box.add_child(missions_box)


func _refresh_missions() -> void:
	var p := yard.profile
	ContractBoard.refresh(p)
	for c in missions_box.get_children():
		c.queue_free()
	accept_buttons.clear()
	abandon_button = null
	if not p.active_contract.is_empty():
		var a := p.active_contract
		var g := ContractBoard.giver(a)
		var box := card(missions_box, "ACCEPTED · %s — %s" % [a.title, g.name], CyberTheme.AMBER)
		var t := _rich()
		t.text = _contract_text(a)
		box.add_child(t)
		abandon_button = Button.new()
		abandon_button.text = "Abandon contract"
		CyberTheme.style_button(abandon_button, CyberTheme.RED)
		abandon_button.pressed.connect(func() -> void:
			ContractBoard.abandon(p)
			yard.save_and_refresh("Contract abandoned"))
		box.add_child(abandon_button)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", CyberTheme.SPACE_S)
	row.add_theme_constant_override("v_separation", CyberTheme.SPACE_S)
	missions_box.add_child(row)
	for c: Dictionary in p.board:
		var g := ContractBoard.giver(c)
		var box := card(row, "", g.color, Vector2(360, 0))
		var who := _rich()
		who.text = "[color=#%s]●[/color] [b]%s[/b] · %s" % [(g.color as Color).to_html(false), g.name, g.role]
		box.add_child(who)
		var t := _rich()
		t.text = "[b]%s[/b]\n%s" % [c.title, _contract_text(c)]
		box.add_child(t)
		var b := Button.new()
		b.text = "Accept · %s" % MissionChain.reward_text(c)
		CyberTheme.style_button(b, CyberTheme.AMBER, true)
		b.disabled = not p.active_contract.is_empty()
		b.tooltip_text = "One contract at a time" if b.disabled else "Take the job: your next sortie"
		var id: String = c.id
		b.pressed.connect(func() -> void: yard.accept_contract(id))
		box.add_child(b)
		accept_buttons[id] = b


static func _contract_text(c: Dictionary) -> String:
	var loc := Location.by_id(str(c.location))
	if str(c.get("kind", "")) == "retrieve":
		return "%s\nat %s · %d ship%s · back to the %s · pays %s" % [c.brief, loc.display_name, int(c.ships), "" if int(c.ships) == 1 else "s",
			Location.by_id(ContractBoard.deliver_to(c)).station_name, MissionChain.reward_text(c)]
	if str(c.get("kind", "")) == "cargo":
		return "%s\nto %s · %d m³ of hold · no fight · pays %s on arrival" % [c.brief, loc.display_name, int(c.freight_m3), MissionChain.reward_text(c)]
	return "%s\n%s · %d ship%s · threat %d · pays %s" % [c.brief, loc.display_name, int(c.ships), "" if int(c.ships) == 1 else "s",
		int(c.threat), MissionChain.reward_text(c)]


# --- DEALER -----------------------------------------------------------------------

func _build_dealer() -> void:
	var box := _content("DEALER")
	var note := Label.new()
	note.text = "Every template, built new with its standard crew hired. Prices are the parts at station rates plus the hull fee, with the dealer's %d %% margin; scrapping a ship returns only %d %% of its parts." % [
		roundi((ServiceYard.DEALER_MARKUP - 1.0) * 100.0), roundi(ServiceYard.SCRAP_RETURN * 100.0)]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	dealer_box = GridContainer.new()
	dealer_box.columns = DEALER_COLUMNS
	dealer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dealer_box.add_theme_constant_override("h_separation", CyberTheme.SPACE_M)
	dealer_box.add_theme_constant_override("v_separation", CyberTheme.SPACE_M)
	scroll.add_child(dealer_box)
	_dealer_scroll = scroll
	# Scrolled: the cards have moved by the next frame.
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void:
		if dealer_box.is_inside_tree() and not dealer_box.get_tree().process_frame.is_connected(_dealer_views_in_sight):
			dealer_box.get_tree().process_frame.connect(_dealer_views_in_sight, CONNECT_ONE_SHOT))


## The cards: one per template, cheapest first — built when the dealer is
## first opened, one a frame, each put in its place by price as it comes. A
## card shows its catalogue picture, or builds a 3D view the first time.
func _fill_dealer() -> void:
	if _dealer_filled:
		return
	_dealer_filled = true
	for path in BlueprintIO.list_templates():
		var info := _template(path)
		if info.is_empty() or not is_instance_valid(dealer_box):
			continue
		var bp: ShipBlueprint = info.bp
		var price := int(info.price.total)
		var c := card(dealer_box, bp.name.to_upper(), _dealer_accent(info))
		(c.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var at := _dealer_order.bsearch(price, false)
		_dealer_order.insert(at, price)
		dealer_box.move_child(c.get_parent(), at)  # the card's panel
		var shot := DealerShots.load_shot(path)
		if shot != null:
			c.add_child(_dealer_picture(shot))
		else:
			var preview := ShipPreview3D.new()
			preview.custom_minimum_size = Vector2(0, DEALER_SHOT_H)
			preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			preview.still = true
			c.add_child(preview)
			_dealer_views[path] = preview
		var text := _rich()
		text.text = info.text
		c.add_child(text)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(0, 34)
		CyberTheme.style_button(buy, CyberTheme.AMBER, true)
		buy.pressed.connect(func() -> void: yard.buy_ship(path))
		c.add_child(buy)
		dealer_rows[path] = buy
		_dealer_button(path)
		if dealer_box.is_inside_tree():  # one a frame: loading and pricing a template is the slow part now
			await dealer_box.get_tree().process_frame
			if not is_instance_valid(dealer_box) or not dealer_box.is_inside_tree():
				return  # the shipyard closed meanwhile
		_dealer_views_in_sight()  # laid out now: where each card is is known


## Build the 3D views of the cards now in sight (all of them when the
## dealer isn't on screen to measure).
func _dealer_views_in_sight() -> void:
	var sight := _dealer_scroll.get_global_rect() if _dealer_scroll != null and _dealer_scroll.is_inside_tree() else Rect2()
	for path: String in _dealer_views.keys():
		var view: ShipPreview3D = _dealer_views[path]
		if not is_instance_valid(view):
			_dealer_views.erase(path)
			continue
		if sight.has_area() and (view.size.x < 1.0 or not sight.intersects(view.get_global_rect())):
			continue  # not laid out yet, or out of sight
		_dealer_views.erase(path)
		var info := _template(path)
		if not info.has("editor"):
			info["editor"] = ShipEditor.new(info.bp, yard.editor.catalog)
		view.show_design(info.editor)
		_keep_picture(path, view, _dealer_accent(info))


func _dealer_accent(info: Dictionary) -> Color:
	return CyberTheme.AMBER if info.capital else CyberTheme.CYAN


func _dealer_picture(tex: Texture2D) -> TextureRect:
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(0, DEALER_SHOT_H)
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return pic


## Once `view` has drawn, save it as the template's catalogue picture and
## show that instead (no picture without a renderer, e.g. headless).
func _keep_picture(path: String, view: ShipPreview3D, accent: Color) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Drawn afresh at the card's laid-out size, then kept — unless the card
	# changed size meanwhile (a stale texture is garbage) or no ship shows.
	var img: Image = null
	for attempt in 5:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(view) or not view.is_inside_tree():
			return
		var size := Vector2i(view.size)
		view.redraw()
		for k in 2:
			await RenderingServer.frame_post_draw
		if not is_instance_valid(view) or not view.is_inside_tree():
			return
		var shot := view.snapshot()
		if Vector2i(view.size) == size and shot != null and shot.get_size() == size and DealerShots.has_subject(shot):
			img = shot
			break
	if img == null:
		return
	var pic := _dealer_picture(DealerShots.save_shot(path, img, accent))
	var at := view.get_index()
	var box := view.get_parent()
	box.remove_child(view)
	view.queue_free()
	box.add_child(pic)
	box.move_child(pic, at)


func _dealer_button(path: String) -> void:
	var price := _price_of(path)
	var b: Button = dealer_rows[path]
	b.text = "BUY · %d cr" % price
	b.disabled = price > yard.profile.credits
	b.tooltip_text = "Short of credits (you have %d)" % yard.profile.credits if b.disabled else "Buy it: it joins your hangar as the active vessel"


## The dealer's facts about a template ({} if it can't be read).
func _template(path: String) -> Dictionary:
	if not _templates.has(path):
		var bp := BlueprintIO.load_file(path, PackedStringArray())
		if bp == null:
			return {}
		var cat := yard.editor.catalog
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		var price := ServiceYard.dealer_price(bp, cat, grid, stats)
		var capital := stats.mass_kg >= CAPITAL_MASS_KG
		_templates[path] = {"bp": bp, "price": price, "capital": capital, "text": _offer_text(bp, stats, price, capital)}
	return _templates[path]


func _price_of(path: String) -> int:
	var info := _template(path)
	return int(info.price.total) if not info.is_empty() else 0


## A capital ship: 900 t or more (the Destroyer and up).
const CAPITAL_MASS_KG := 900_000.0


func _offer_text(bp: ShipBlueprint, stats: ShipStats, price: Dictionary, capital: bool) -> String:
	var cat := yard.editor.catalog
	var counts := {}
	for e in bp.equipment:
		var def: EquipmentDefinition = cat.equipment.get(e.def_id)
		if def != null:
			counts[def.kind] = int(counts.get(def.kind, 0)) + 1
	var K := EquipmentDefinition.Kind
	var arms := PackedStringArray()
	for spec in [[K.CANNON, "gun"], [K.POINT_DEFENCE, "PD"], [K.MISSILE_LAUNCHER, "launcher"], [K.CRAFT_MOUNT, "craft"],
			[K.DECOY_LAUNCHER, "flares"], [K.JAMMER, "jammer"]]:
		var n := int(counts.get(spec[0], 0))
		if n > 0:
			arms.append("%d %s" % [n, spec[1]])
	return "%s%.0f t · %.2f g · Δv %.0f m/s · crew %d · cargo %.0f m³\n%s\n%s" % [
		CyberTheme.tint("CAPITAL SHIP · ", CyberTheme.AMBER) if capital else "",
		stats.mass_kg / 1000.0, stats.thrust_forward_n / maxf(stats.mass_kg, 1.0) / ShipDynamics.G0, stats.delta_v_m_s(),
		int(price.crew_count), stats.cargo_m3, " · ".join(arms),
		CyberTheme.tint("hull and parts %d cr%s · crew %d × %d cr" % [price.ship,
			" · rarer parts %d cr (yours with it)" % price.units if int(price.units) > 0 else "", price.crew_count, PlayerProfile.HIRE_FEE], CyberTheme.TEXT_DIM)]


# --- SERVICE BAY -------------------------------------------------------------------

## Three cards across the top — repair, rearm, refuel — each with what it
## needs and one large button; the damage report and the cargo hold below.
func _build_services() -> void:
	var box := _content("SERVICES")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CyberTheme.SPACE_M)
	box.add_child(row)
	for spec in [["repair", "REPAIR", func() -> void: yard.repair()], ["rearm", "REARM", func() -> void: yard.rearm_only()],
			["refuel", "REFUEL", func() -> void: yard.refuel_now()]]:
		var c := card(row, spec[1], CyberTheme.AMBER)
		c.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := _rich()
		label.custom_minimum_size = Vector2(0, 60)
		c.add_child(label)
		var b := Button.new()
		b.name = String(spec[0]).capitalize() + "Button"
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", CyberTheme.SIZE_TITLE + 5)
		CyberTheme.style_button(b, CyberTheme.AMBER, true)
		b.pressed.connect(spec[2])
		c.add_child(b)
		service_labels[spec[0]] = label
		service_buttons[spec[0]] = b


func _refresh_services() -> void:
	var p := yard.profile
	var v := p.vessel
	var cat := yard.editor.catalog
	var jobs := ServiceYard.repair_jobs(v, cat)
	var parts := ServiceYard.total_cost(jobs)
	(service_labels.repair as RichTextLabel).text = CyberTheme.tint("✔ in full repair", CyberTheme.CYAN) if jobs.is_empty() \
		else "%d job%s · %d spare parts for everything\nyou have %d · what first: the damage report below" % [jobs.size(), "" if jobs.size() == 1 else "s", parts, p.spare_parts]
	var rb: Button = service_buttons.repair
	rb.text = "REPAIR · %d parts" % parts if not jobs.is_empty() else "Nothing to repair"
	rb.disabled = jobs.is_empty() or p.spare_parts <= 0
	var need := ServiceYard.resupply_needs(v, cat)
	var msl := ServiceYard.missile_needs(v, cat)
	var arms_cr := ceili(float(int(need.rounds) + int(need.pd_rounds)) / ServiceYard.ROUNDS_PER_CREDIT - 1e-9) + int(msl.credits)
	var lines := PackedStringArray()
	lines.append("ROUNDS %s" % ("full" if int(need.rounds) <= 0 else "%d to fill" % need.rounds))
	lines.append("POINT DEFENCE %s" % ("full" if int(need.pd_rounds) <= 0 else "%d to fill" % need.pd_rounds))
	lines.append("MISSILES & FLARES %s" % ("full" if int(msl.count) == 0 else "%d to restock" % msl.count))
	(service_labels.rearm as RichTextLabel).text = "\n".join(lines)
	var ab: Button = service_buttons.rearm
	ab.text = "REARM · %d cr" % arms_cr if arms_cr > 0 else "Fully armed"
	ab.disabled = arms_cr <= 0 or p.credits <= 0
	var tanks := p.vessel_tanks(cat)
	var fuel_cr := ceili((float(need.propellant_kg) + float(need.reserve_kg)) / 1000.0 * ServiceYard.PROPELLANT_CREDITS_PER_T - 1e-9)
	(service_labels.refuel as RichTextLabel).text = "PROPELLANT %s\nJUMP RESERVE %s\n%s aboard · %s full" % [
		"full" if float(need.propellant_kg) <= 0.0 else "%.1f t to fill" % (float(need.propellant_kg) / 1000.0),
		"full" if float(need.reserve_kg) <= 0.0 else "%.1f t to fill" % (float(need.reserve_kg) / 1000.0),
		JumpDrive.dv_text(tanks.dv_mps), JumpDrive.dv_text(tanks.dv_full_mps)]
	var fb: Button = service_buttons.refuel
	fb.text = "REFUEL · %d cr" % fuel_cr if fuel_cr > 0 else "Tanks full"
	fb.disabled = fuel_cr <= 0 or p.credits <= 0


func _armoury_text() -> String:
	var v := yard.profile.vessel
	var cat := yard.editor.catalog
	var need := ServiceYard.resupply_needs(v, cat)
	var lines := PackedStringArray(["[b]%s[/b]" % v.name])
	lines.append("PROPELLANT  %s" % ("full" if float(need.propellant_kg) <= 0.0 else "%.1f t to fill" % (float(need.propellant_kg) / 1000.0)))
	var tanks := yard.profile.vessel_tanks(cat)
	lines.append("JUMP RESERVE  %s of %s%s — the jump drive's own; engines can't burn it" % [JumpDrive.tonnes(tanks.reserve_kg),
		JumpDrive.tonnes(tanks.reserve_capacity_kg), "" if float(need.reserve_kg) <= 0.0 else " · %.1f t to fill" % (float(need.reserve_kg) / 1000.0)])
	lines.append("JUMP Δv      %s aboard · %s with full tanks and reserve — jumps cost Δv, the same for every ship (NAV CHART)" % [
		JumpDrive.dv_text(tanks.dv_mps), JumpDrive.dv_text(tanks.dv_full_mps)])
	lines.append("ROUNDS      %s" % ("full" if int(need.rounds) <= 0 else "%d to fill" % need.rounds))
	var msl :=ServiceYard.missile_needs(v, cat)
	lines.append("MISSILES & FLARES  %s" % ("full" if int(msl.count) == 0 else "%d to restock (%d cr)" % [msl.count, msl.credits]))
	lines.append("TOTAL       %d credits (you have %d) — or left to the launch, which restocks what the credits allow" % [need.credits, yard.profile.credits])
	return "\n".join(lines)


# --- HANGAR -----------------------------------------------------------------------

## The bank card: the deposit (deposit / withdraw an amount) and loans —
## those on offer, those taken (repay).
func _build_bank() -> void:
	var c := card(_content("HANGAR"), "Station bank", CyberTheme.AMBER)
	c.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_label = _rich()
	c.add_child(bank_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	c.add_child(row)
	bank_amount = SpinBox.new()
	bank_amount.name = "BankAmount"
	bank_amount.min_value = 100
	bank_amount.max_value = 1_000_000
	bank_amount.step = 100
	bank_amount.value = 500
	bank_amount.custom_minimum_size = Vector2(140, 0)
	row.add_child(bank_amount)
	for spec in [["Deposit", func() -> void: yard.bank_result(yard.profile.deposit(int(bank_amount.value)))],
			["Withdraw", func() -> void: yard.bank_result(yard.profile.withdraw(int(bank_amount.value)))]]:
		var b := Button.new()
		b.text = spec[0]
		CyberTheme.style_button(b, CyberTheme.AMBER)
		b.pressed.connect(spec[1])
		row.add_child(b)
	bank_box = VBoxContainer.new()
	bank_box.add_theme_constant_override("separation", CyberTheme.SPACE_XS)
	c.add_child(bank_box)


func _refresh_bank() -> void:
	var p := yard.profile
	bank_label.text = "DEPOSIT [color=#%s]%d cr[/color] · earns %d %% a sortie, compounding · credits on hand %d · owed %d" % [
		CyberTheme.AMBER.to_html(false), p.bank_deposit, roundi(PlayerProfile.DEPOSIT_RATE * 100.0), p.credits, p.debt()]
	for child in bank_box.get_children():
		child.queue_free()
	for o: Dictionary in PlayerProfile.LOAN_OFFERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", CyberTheme.SPACE_S)
		var text := _rich()
		var l := p.loan(str(o.id))
		var id: String = o.id
		if l.is_empty():
			text.text = "[b]%s[/b] · %d cr at %d %% a sortie over %d sorties (instalments taken on docking)" % [o.name, o.amount, roundi(float(o.rate) * 100.0), o.term]
			row.add_child(text)
			var take := Button.new()
			take.text = "Take · +%d cr" % o.amount
			CyberTheme.style_button(take, CyberTheme.AMBER)
			take.pressed.connect(func() -> void: yard.bank_result(p.take_loan(id)))
			row.add_child(take)
		else:
			text.text = "[b]%s[/b] · [color=#%s]%d cr owed[/color] · %d sorties left · next instalment ~%d cr" % [o.name, CyberTheme.AMBER.to_html(false),
				l.balance, l.sorties_left, PlayerProfile.instalment({"balance": ceili(float(l.balance) * (1.0 + float(l.rate))), "sorties_left": l.sorties_left})]
			row.add_child(text)
			var part := Button.new()
			part.text = "Repay %d" % int(bank_amount.value)
			CyberTheme.style_button(part)
			part.pressed.connect(func() -> void: yard.bank_result(p.repay(id, int(bank_amount.value))))
			row.add_child(part)
			var all := Button.new()
			all.text = "Repay all · %d cr" % l.balance
			all.disabled = p.credits < int(l.balance)
			CyberTheme.style_button(all, CyberTheme.AMBER)
			all.pressed.connect(func() -> void: yard.bank_result(p.repay(id)))
			row.add_child(all)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bank_box.add_child(row)


func _refresh_fleet() -> void:
	for c in fleet_box.get_children():
		c.queue_free()
	var p := yard.profile
	for i in p.vessels.size():
		var v := p.vessels[i]
		var active := i == p.active_vessel
		var box := card(fleet_box, ("▸ " if active else "") + v.name, CyberTheme.AMBER if active else CyberTheme.CYAN, Vector2(300, 0))
		var jobs := ServiceYard.repair_jobs(v, yard.editor.catalog)
		var t := _rich()
		t.text = "%s · %d sorties\n%s" % [v.blueprint.name, v.sorties,
			CyberTheme.tint("in full repair", CyberTheme.CYAN) if jobs.is_empty() else CyberTheme.tint("%d repair jobs" % jobs.size(), CyberTheme.AMBER)]
		box.add_child(t)
		var b := Button.new()
		b.text = "Flying this one" if active else "Fly this one"
		b.disabled = active
		CyberTheme.style_button(b)
		var index := i
		b.pressed.connect(func() -> void: yard.select_vessel(index))
		box.add_child(b)


func refresh() -> void:
	if station_label == null:
		return
	_refresh_directory()
	match current:
		"STATION":
			_refresh_station()
		"MISSIONS":
			_refresh_missions()
		"DEALER":
			_fill_dealer()
			for path in dealer_rows:
				_dealer_button(path)
		"SERVICES":
			_refresh_services()
		"HANGAR":
			_refresh_fleet()
			_refresh_bank()
			scrap_button.disabled = yard.profile.vessels.size() <= 1
			scrap_button.tooltip_text = "Scrap it for %d spare parts (not your last ship)" % ServiceYard.scrap_value(yard.profile.vessel, yard.editor.catalog)
