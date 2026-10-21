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

const SECTIONS := ["STATION", "MISSIONS", "DEALER", "HANGAR", "REFIT", "CREW", "ARMOURY", "REPAIRS", "UPGRADES", "MAP", "LOOT"]
const START := "STATION"
const HINTS := {
	"STATION": "Your ship, what it needs, the next sortie",
	"MISSIONS": "People at the yard with work — contracts",
	"DEALER": "Ships for credits, crew included",
	"HANGAR": "Your vessels, the hold and the bank, history",
	"REFIT": "Design and refit: the builder",
	"CREW": "Who serves aboard, who is for hire",
	"ARMOURY": "Rearm, refuel, the quartermaster's parts",
	"REPAIRS": "Damage and what fixing it costs",
	"UPGRADES": "Station technology for your ships",
	"MAP": "Where you launch from, how many you meet",
	"LOOT": "Every crate drop and its odds",
}

## The directory: [district, [[section, place name], ...]].
const DIRECTORY := [
	["DRYDOCK", [["STATION", "Berth"], ["REFIT", "Refit bay"], ["REPAIRS", "Repair crews"], ["ARMOURY", "Armoury"]]],
	["CONCOURSE", [["MISSIONS", "Mission board"], ["CREW", "Crew quarters"], ["DEALER", "Ship dealer"]]],
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
## DEALER: one card per template.
var dealer_box: HFlowContainer
var dealer_rows: Dictionary = {}  # template path -> Button (buy)
## ARMOURY.
var armoury_label: RichTextLabel
var resupply_button: Button
## HANGAR.
var scrap_button: Button
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
	for n in ["NameEdit", "TemplateList", "LoadTemplate", "DesignList", "LoadDesign", "Undo", "Redo", "Save"]:
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
	_build_armoury()
	_adopt_hangar_tabs()


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
		var cost := TechTree.next_cost(p.tech_level(n.id))
		if cost > 0 and cost <= p.credits:
			affordable += 1
	var here := Location.by_id(p.location)
	return {
		"STATION": [v.name, false],
		"REFIT": [v.blueprint.name, false],
		"REPAIRS": ["%d job%s · %d parts" % [jobs.size(), "" if jobs.size() == 1 else "s", ServiceYard.total_cost(jobs)], true] if not jobs.is_empty() else ["in full repair", false],
		"ARMOURY": ["restock %d cr" % need.credits, true] if int(need.credits) > 0 else ["stocked · %d on the shelf" % p.vendor_stock.size(), false],
		"MISSIONS": ["on contract · %s" % p.active_contract.title, false] if not p.active_contract.is_empty() else ["%d offers posted" % p.board.size(), not p.board.is_empty()],
		"CREW": ["%d / %d aboard · %d for hire" % [v.crew.size(), berths, p.hire_pool.size()], v.crew.size() < berths],
		"DEALER": ["%d hulls for sale" % BlueprintIO.list_templates().size(), false],
		"HANGAR": ["%d vessel%s · hold %.0f m³" % [p.vessels.size(), "" if p.vessels.size() == 1 else "s", held], held > 0.0],
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
	var where := {"SERVICE": "REPAIRS", "CARGO & BANK": "HANGAR", "HISTORY": "HANGAR", "LOOT TABLES": "LOOT", "MAP": "MAP",
		"CREW": "CREW", "QUARTERMASTER": "ARMOURY", "UPGRADES": "UPGRADES"}
	var titles := {"SERVICE": "Repairs and refit", "CARGO & BANK": "The hold and the bank", "HISTORY": "Service record",
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
		if section in ["HANGAR", "ARMOURY"]:
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
	for spec in [["repairs", "Repair crews", "REPAIRS", CyberTheme.AMBER], ["rearm", "Armoury", "ARMOURY", CyberTheme.AMBER],
			["crew", "Crew quarters", "CREW", CyberTheme.CYAN], ["sortie", "Next sortie", "MISSIONS", CyberTheme.AMBER]]:
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
	(station_buttons.repairs as Button).text = "Repair crews ›"
	var need := ServiceYard.resupply_needs(v, cat)
	(station_cards.rearm as RichTextLabel).text = CyberTheme.tint("✔ full", CyberTheme.CYAN) if int(need.credits) == 0 \
		else "%d credits to fill propellant, rounds, missiles and flares (or at launch)" % need.credits
	(station_buttons.rearm as Button).text = "Armoury ›"
	(station_cards.crew as RichTextLabel).text = "%d / %d aboard · %d for hire" % [v.crew.size(), stats.crew_capacity, p.hire_pool.size()]
	(station_buttons.crew as Button).text = "Crew quarters ›"
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
	dealer_box = HFlowContainer.new()
	dealer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dealer_box.add_theme_constant_override("h_separation", CyberTheme.SPACE_M)
	dealer_box.add_theme_constant_override("v_separation", CyberTheme.SPACE_M)
	scroll.add_child(dealer_box)
	var paths: Array = Array(BlueprintIO.list_templates())
	paths.sort_custom(func(a: String, b: String) -> bool: return _price_of(a) < _price_of(b))
	for path in paths:
		var bp := BlueprintIO.load_file(path, PackedStringArray())
		if bp == null:
			continue
		var c := card(dealer_box, bp.name.to_upper(), CyberTheme.AMBER if _is_capital(bp) else CyberTheme.CYAN, Vector2(460, 0))
		var preview := ShipPreview3D.new()
		preview.custom_minimum_size = Vector2(440, 200)
		c.add_child(preview)
		preview.show_design(ShipEditor.new(bp, yard.editor.catalog))
		var info := _rich()
		info.text = _offer_text(bp)
		c.add_child(info)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(0, 34)
		CyberTheme.style_button(buy, CyberTheme.AMBER, true)
		buy.pressed.connect(func() -> void: yard.buy_ship(path))
		c.add_child(buy)
		dealer_rows[path] = buy


func _price_of(path: String) -> int:
	var bp := BlueprintIO.load_file(path, PackedStringArray())
	return int(ServiceYard.dealer_price(bp, yard.editor.catalog).total) if bp != null else 0


## A capital ship: 900 t or more (the Destroyer and up).
func _is_capital(bp: ShipBlueprint) -> bool:
	var grid := ShipGrid.build(bp, yard.editor.catalog)
	return ShipStats.compute(bp, grid).mass_kg >= 900_000.0


func _offer_text(bp: ShipBlueprint) -> String:
	var cat := yard.editor.catalog
	var grid := ShipGrid.build(bp, cat)
	var stats := ShipStats.compute(bp, grid)
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
	var price := ServiceYard.dealer_price(bp, cat)
	return "%s%.0f t · %.2f g · Δv %.0f m/s · crew %d · cargo %.0f m³\n%s\n%s" % [
		CyberTheme.tint("CAPITAL SHIP · ", CyberTheme.AMBER) if _is_capital(bp) else "",
		stats.mass_kg / 1000.0, stats.thrust_forward_n / maxf(stats.mass_kg, 1.0) / ShipDynamics.G0, stats.delta_v_m_s(),
		int(price.crew_count), stats.cargo_m3, " · ".join(arms),
		CyberTheme.tint("hull and parts %d cr%s · crew %d × %d cr" % [price.ship,
			" · rarer parts %d cr (yours with it)" % price.units if int(price.units) > 0 else "", price.crew_count, PlayerProfile.HIRE_FEE], CyberTheme.TEXT_DIM)]


# --- ARMOURY ----------------------------------------------------------------------

func _build_armoury() -> void:
	var box := _content("ARMOURY")
	var c := card(box, "Rearm & refuel", CyberTheme.AMBER)
	armoury_label = _rich()
	c.add_child(armoury_label)
	resupply_button = Button.new()
	resupply_button.custom_minimum_size = Vector2(240, 34)
	CyberTheme.style_button(resupply_button, CyberTheme.AMBER, true)
	resupply_button.pressed.connect(func() -> void: yard.rearm_now())
	c.add_child(resupply_button)


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
			for path in dealer_rows:
				var price := _price_of(path)
				var b: Button = dealer_rows[path]
				b.text = "BUY · %d cr" % price
				b.disabled = price > yard.profile.credits
				b.tooltip_text = "Short of credits (you have %d)" % yard.profile.credits if b.disabled else "Buy it: it joins your hangar as the active vessel"
		"ARMOURY":
			armoury_label.text = _armoury_text()
			var need := ServiceYard.resupply_needs(yard.profile.vessel, yard.editor.catalog)
			resupply_button.text = "REARM & REFUEL · %d cr" % need.credits if int(need.credits) > 0 else "Nothing to restock"
			resupply_button.disabled = int(need.credits) <= 0 or int(need.credits) > yard.profile.credits
		"HANGAR":
			_refresh_fleet()
			scrap_button.disabled = yard.profile.vessels.size() <= 1
			scrap_button.tooltip_text = "Scrap it for %d spare parts (not your last ship)" % ServiceYard.scrap_value(yard.profile.vessel, yard.editor.catalog)
