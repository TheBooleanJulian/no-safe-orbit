class_name Hud
extends CanvasLayer
## Flight HUD. Reads simulation state only; owns no gameplay logic.
##
## Always on (kept compact so the 3D view dominates):
##   OWN SHIP card (top left)  assist mode, inertial velocity, attitude
##       relative to the velocity vector, propellant, hull, power / heat,
##       power distribution, and the urgent alerts with the key that acts on
##       each;
##   TARGET card (top right)   identity, sensor track (MEAS / EST / STALE,
##       confidence, lock), range, closing speed, round ETA (an estimate:
##       "~"), status from a close look, and the contextual salvage /
##       docking / boarding lines;
##   weapon strip (bottom)     gun, ammunition, point defence, air wing;
##   event ticker, alert banner, radar, damage map, hit cam.
## On demand: O orbit details, J details & combat log, H help, Tab ship.

const COLOR_TARGET := Color(1.0, 0.17, 0.84, 0.95)
const COLOR_APSIS := Color(0.35, 1.0, 0.55, 0.9)
## Below this eccentricity, apsis positions and times are meaningless.
const CIRCULAR_ECCENTRICITY := 1e-4
const PATH_SAMPLES := 180
const NEAR_PATH_DEG := 20.0
const NEAR_PATH_SAMPLES := 80
const NOTICE_S := 6.0
const HIT_ALERT_S := 8.0
## Layout breakpoint: below this height the side panels shrink.
const COMPACT_HEIGHT := 820.0

@onready var overlay: HudOverlay = $Root/Overlay
@onready var radar: RadarDisplay = $Root/Radar
@onready var flight_label: Label = $Root/LeftColumn/FlightPanel/Margin/FlightLabel
@onready var orbit_label: Label = $Root/LeftColumn/OrbitPanel/Margin/OrbitLabel
@onready var target_label: Label = $Root/TargetPanel/Margin/TargetLabel
@onready var warning_label: Label = $Root/WarningLabel
@onready var controls: ControlsPanel = $Root/Controls
@onready var hit_cam: HitCam = $Root/HitCam
@onready var help_label: Label = $Root/HelpLabel

## Real-sky frame, for the sunlight / eclipse readout (set by Main).
var celestial: CelestialFrame
## Main sets this when the target is shooting back (T).
var target_hostile: bool = false
## Persistent player state (set by Main).
var profile: PlayerProfile
## The player's sensor track of the target (set by Main every frame).
var track: SensorTrack
## Salvage results panel (created in _ready).
var loot: LootCarousel
## With the drawer open, the target card / hit cam / radar still fit to its left.
var right_column_fits: bool = true
var radar_fits: bool = true
## Level ("danger" / "caution") of the alert in the banner, "" if none.
var top_alert_level: String = ""
## Jump drive while [B] is held (Main): {progress, left_s, waiting} or
## {blocked}; {} when not charging.
var jump_state: Dictionary = {}
var _jump_flash: ColorRect
## Post-combat debrief, shown when the ship is lost (created in _ready).
var debrief: DebriefPanel
## Always-visible module and damage map of your ship.
var damage_map: ShipSchematic
## Tab: tactical overview and ship management.
var overview: TacticalOverview
var docking_cam: DockingCam
## Boarding party size chosen in the overview (set by Main).
var boarding_party_size: int = BoardingAction.MAX_TEAM
## The player's craft (set by Main).
var player_wing: AirWing
## Weapon strip and event ticker (created in _ready).
var weapon_label: Label
var ticker_label: Label
## J: details and combat log; H: help.
var details_label: Label
var help_panel: PanelContainer
## System or room id the top alert is about ("" = none): Tab opens the
## damage-control view on it.
var alert_subject: String = ""

var _orbit_panel: PanelContainer
var _details_panel: PanelContainer
var _weapon_panel: PanelContainer
var _target_heading: Label
var _own_heading: Label
var _last_hit_time := -INF
var _hits_scored := 0
var _rounds_near := 0
var _rounds_far := 0
## Latest damage report on the target (our hits) and on us (incoming).
var _outgoing: DamageReport
var _incoming: DamageReport
var _incoming_time := -INF
var _hits_taken := 0
var _notices: Array[Dictionary] = []  # {text, time}
var _orbit_forced := false
var _strip_w := 600.0
var _side_w := 330.0
var _radar_size := 240.0


func _ready() -> void:
	$Root.theme = CyberTheme.build_theme()
	_build_cards()
	_jump_flash = ColorRect.new()
	_jump_flash.name = "JumpFlash"
	_jump_flash.color = Color(0.85, 0.97, 1.0, 0.0)
	_jump_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_jump_flash)
	_jump_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	loot = LootCarousel.new()
	loot.name = "Loot"
	$Root.add_child(loot)
	loot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	debrief = DebriefPanel.new()
	debrief.name = "Debrief"
	$Root.add_child(debrief)
	debrief.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	damage_map = ShipSchematic.new()
	damage_map.name = "DamageMap"
	damage_map.title = "SHIP · MODULES & DAMAGE   [Tab]"
	damage_map.show_legend = true
	$Root.add_child(damage_map)
	docking_cam = DockingCam.new()
	docking_cam.name = "DockingCam"
	$Root.add_child(docking_cam)
	overview = TacticalOverview.new()
	overview.name = "Overview"
	$Root.add_child(overview)
	hit_cam.add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.MAGENTA, CyberTheme.SPACE_XS + 2))
	# The loot window is the one thing drawn over everything else.
	$Root.move_child(loot, -1)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Headings on the cards; weapon strip, ticker, details and help panels.
func _build_cards() -> void:
	_own_heading = _heading_into(flight_label, "OWN SHIP", CyberTheme.CYAN)
	_target_heading = _heading_into(target_label, "TARGET", CyberTheme.MAGENTA)
	($Root/TargetPanel as PanelContainer).add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.MAGENTA, 0))
	for l in [flight_label, target_label, orbit_label]:
		l.add_theme_font_size_override("font_size", CyberTheme.SIZE_BODY)
	orbit_label.remove_theme_color_override("font_color")
	_orbit_panel = $Root/LeftColumn/OrbitPanel
	_orbit_panel.visible = false
	_heading_into(orbit_label, "ORBIT  [O]", CyberTheme.CYAN)
	# Details & combat log (J), under the own-ship card.
	_details_panel = PanelContainer.new()
	_details_panel.visible = false
	var dbox := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		dbox.add_theme_constant_override("margin_" + side, CyberTheme.SPACE_M if side in ["left", "right"] else CyberTheme.SPACE_S)
	_details_panel.add_child(dbox)
	details_label = Label.new()
	details_label.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL + 1)
	dbox.add_child(details_label)
	_heading_into(details_label, "DETAILS & COMBAT LOG  [J]", CyberTheme.CYAN)
	$Root/LeftColumn.add_child(_details_panel)
	# Weapon strip (bottom centre).
	_weapon_panel = PanelContainer.new()
	_weapon_panel.name = "WeaponStrip"
	_weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_label = Label.new()
	weapon_label.add_theme_font_size_override("font_size", CyberTheme.SIZE_BODY)
	_weapon_panel.add_child(weapon_label)
	$Root.add_child(_weapon_panel)
	# Event ticker (above the strip).
	ticker_label = Label.new()
	ticker_label.name = "Ticker"
	ticker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticker_label.add_theme_font_size_override("font_size", CyberTheme.SIZE_BODY)
	ticker_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	ticker_label.add_theme_constant_override("shadow_offset_x", 1)
	ticker_label.add_theme_constant_override("shadow_offset_y", 1)
	$Root.add_child(ticker_label)
	# Alert banner.
	var banner := CyberTheme.panel(CyberTheme.RED, CyberTheme.SPACE_S, 0.82)
	warning_label.add_theme_stylebox_override("normal", banner)
	warning_label.add_theme_font_override("font", CyberTheme.sans())
	warning_label.add_theme_font_size_override("font_size", CyberTheme.SIZE_TITLE)
	warning_label.remove_theme_color_override("font_shadow_color")
	# Help: one line always, the full card with H.
	help_label.text = "[H] help · [F1] keys · [Tab] ship · [O] orbit · [J] log · [Shift] zoom · [RMB] look"
	help_label.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL)
	help_label.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
	help_panel = PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.visible = false
	var help_text := Label.new()
	help_text.text = HELP_TEXT
	help_text.add_theme_font_size_override("font_size", CyberTheme.SIZE_BODY)
	var hbox := VBoxContainer.new()
	var hh := Label.new()
	hh.theme_type_variation = &"Heading"
	hh.text = "CONTROLS  [H] close"
	hbox.add_child(hh)
	hbox.add_child(help_text)
	help_panel.add_child(hbox)
	$Root.add_child(help_panel)


const HELP_TEXT := """FLIGHT     W/S main/reverse · A/D turn (strafe on the docking cam) · R/F up/down
           arrows pitch & yaw · Q/E roll · right-drag orbits the camera (right click resets)
ASSIST     Z on/off · X hold orbit ↔ match target (yellow markers = relative to target)
GUNNERY    mouse aims the turrets (click captures; Esc releases) · LMB / Enter fire
           Shift zoom on/off · ◇ lead marker (needs a lock)
POWER      1 SYS · 2 ENG · 3 WEP · 4 balance
SHIP       Tab damage control, crew, power, wing · C patch damage
CONTACTS   T target hostile · G salvage beacon · V gangway · N board / withdraw · L / K launch / recall craft
PANELS     O orbit · J details & combat log · H this help · F1 rebind
MISSION    hold B 5 s: jump drive to Earth Shipyard (out of combat) · Backspace restart / respawn"""


## Puts a sans heading above `label` inside its parent container.
func _heading_into(label: Label, text: String, color: Color) -> Label:
	var parent := label.get_parent()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_XS)
	parent.remove_child(label)
	parent.add_child(box)
	var heading := Label.new()
	heading.theme_type_variation = &"Heading"
	heading.text = text
	heading.add_theme_color_override("font_color", color)
	box.add_child(heading)
	box.add_child(label)
	return heading


## Places panels for the current viewport size (no overlaps at 1280×720
## up to ultrawide).
func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var compact := view.y < COMPACT_HEIGHT
	var gutter := CyberTheme.SPACE_L
	var side_w := clampf(view.x * 0.24, 330.0, 420.0)
	($Root/LeftColumn as Control).custom_minimum_size = Vector2(side_w, 0)
	var tp := $Root/TargetPanel as Control
	tp.custom_minimum_size = Vector2(side_w, 0)
	tp.offset_left = -gutter - side_w
	var radar_size := 190.0 if compact else 240.0
	radar.offset_left = -gutter - radar_size
	radar.offset_top = -gutter - radar_size
	_side_w = side_w
	_radar_size = radar_size
	# Damage map: bottom left, above the help line.
	var map_size := Vector2(minf(side_w, 360.0), 140.0 if compact else 170.0)
	damage_map.anchor_left = 0.0
	damage_map.anchor_right = 0.0
	damage_map.anchor_top = 1.0
	damage_map.anchor_bottom = 1.0
	damage_map.offset_left = gutter
	damage_map.offset_right = gutter + map_size.x
	damage_map.offset_bottom = -48.0
	damage_map.offset_top = -48.0 - map_size.y
	# Help line under the map, wrapped to its width.
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.anchor_left = 0.0
	help_label.anchor_right = 0.0
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_left = gutter
	help_label.offset_right = gutter + map_size.x
	help_label.offset_bottom = -6.0
	help_label.offset_top = -44.0
	# Hit cam: right column, under the target card.
	hit_cam.custom_minimum_size = Vector2.ZERO
	hit_cam.offset_left = -gutter - side_w
	hit_cam.offset_right = -gutter
	hit_cam.offset_top = 300.0 if compact else 360.0
	hit_cam.set_compact(compact)
	# Weapon strip and ticker: bottom centre, between the damage map and the
	# radar.
	var free_w := view.x - 2.0 * (gutter + maxf(map_size.x, radar_size)) - 2.0 * gutter
	var strip_w := clampf(free_w, 300.0, 760.0)
	_strip_w = strip_w
	weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center_bottom(_weapon_panel, strip_w, gutter)
	ticker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ticker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_bottom(ticker_label, strip_w, gutter + 64.0)
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	docking_cam.set_compact(compact)
	docking_cam.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, gutter)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	overview.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	overview.offset_left = -minf(view.x * 0.42, 620.0)
	overview.offset_right = 0
	overview.offset_top = 0
	overview.offset_bottom = 0


## Fixed width, centred, sitting `bottom` px above the screen's bottom edge
## and growing upwards with its content.
static func _center_bottom(c: Control, w: float, bottom: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_bottom = -bottom
	c.offset_top = -bottom - 20.0


## With the drawer open, the bottom strip and ticker re-centre in the view
## that is left (and narrow to fit it).
func _reflow_for_drawer() -> void:
	var view := get_viewport().get_visible_rect().size
	var right := overview.get_global_rect().position.x if overview.visible else view.x
	var w := minf(_strip_w, right - 2.0 * CyberTheme.SPACE_L)
	var shift := (right - view.x) * 0.5
	for c: Control in [_weapon_panel, ticker_label]:
		c.offset_left = -w * 0.5 + shift
		c.offset_right = w * 0.5 + shift
	# The ticker sits just above the strip, however tall the strip is.
	var above := _weapon_panel.size.y + CyberTheme.SPACE_L + CyberTheme.SPACE_S
	ticker_label.offset_bottom = -above
	ticker_label.offset_top = -above - 20.0
	# The right-hand column (target card, hit cam, radar) moves to the left of
	# the open drawer when there is room beside the own-ship card.
	var gutter := float(CyberTheme.SPACE_L)
	var drawer := view.x - right
	var tp := $Root/TargetPanel as Control
	tp.offset_left = -gutter - _side_w - drawer
	tp.offset_right = -gutter - drawer
	hit_cam.offset_left = -gutter - _side_w - drawer
	hit_cam.offset_right = -gutter - drawer
	radar.offset_left = -gutter - _radar_size - drawer
	radar.offset_right = -gutter - drawer
	var left_end := ($Root/LeftColumn as Control).get_global_rect().end.x
	right_column_fits = drawer <= 0.0 or right - gutter - _side_w >= left_end + gutter
	# The radar also needs to clear the (re-centred) weapon strip.
	radar_fits = drawer <= 0.0 or right - gutter - _radar_size >= right * 0.5 + w * 0.5 + gutter


## The banner sits in the gap between the two cards; if that gap is too
## narrow, below them. Measured from the cards' real size every frame.
func _place_banner() -> void:
	var view := get_viewport().get_visible_rect().size
	var left_card := ($Root/LeftColumn/FlightPanel as Control).get_global_rect()
	var right_card := ($Root/TargetPanel as Control).get_global_rect()
	if overview.visible:
		right_card = overview.get_global_rect()
	var gutter := float(CyberTheme.SPACE_M)
	var x0 := left_card.end.x + gutter
	var x1 := right_card.position.x - gutter
	var top := float(CyberTheme.SPACE_L)
	if x1 - x0 < 300.0:
		x0 = view.x * 0.5 - 300.0
		x1 = view.x * 0.5 + 300.0
		top = maxf(left_card.end.y, right_card.end.y) + gutter
	if x1 - x0 > 760.0:
		var mid := (x0 + x1) * 0.5
		x0 = mid - 380.0
		x1 = mid + 380.0
	warning_label.anchor_left = 0.0
	warning_label.anchor_right = 0.0
	warning_label.anchor_top = 0.0
	warning_label.anchor_bottom = 0.0
	warning_label.offset_left = x0
	warning_label.offset_right = x1
	warning_label.offset_top = top
	warning_label.offset_bottom = top + 20.0


func toggle_orbit_panel() -> void:
	_orbit_panel.visible = not _orbit_panel.visible
	_orbit_forced = false


func toggle_details() -> void:
	_details_panel.visible = not _details_panel.visible


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


## A message in the event ticker for a few seconds.
func notice(text: String, sim_time: float) -> void:
	_notices.append({"text": text, "time": sim_time})
	if _notices.size() > 3:
		_notices.pop_front()


## Notices still showing.
func ticker_text() -> String:
	return ticker_label.text


func reset() -> void:
	_last_hit_time = -INF
	_hits_scored = 0
	_outgoing = null
	_incoming = null
	_incoming_time = -INF
	_hits_taken = 0


## Call with each frame's hit events (from WorldSimulation.take_hit_events).
func note_hits(events: Array[HitEvent], player_id: StringName, sim_time: float) -> void:
	for ev in events:
		if ev.shooter_id == player_id:
			_hits_scored += 1
			_last_hit_time = sim_time
			_outgoing = ev.report
		elif ev.target_id == player_id:
			_hits_taken += 1
			_incoming = ev.report
			_incoming_time = sim_time


func update_display(world: WorldSimulation, player_id: StringName, target_id: StringName,
		alpha: float, render_origin: Vector3, camera: Camera3D, input: PlayerInput) -> void:
	var player := world.get_ship(player_id)
	var target := world.get_ship(target_id)
	var orbit := world.orbit_of(player)
	var has_target := target != null and target.is_active()
	var t := world.sim_time
	var contact := has_target and (track == null or track.detected)

	var alerts := _alerts(world, player, orbit)
	_update_own_card(world, player, orbit, input, has_target, alerts)
	_update_orbit_panel(world, player, orbit)
	_update_target_card(world, player, target)
	_update_weapon_strip(player)
	_update_details(world, player)
	_update_banner(alerts)
	_update_ticker(t)
	_rounds_near = world.projectiles().size()
	_rounds_far = world.far_projectiles().size()

	overlay.camera = camera
	overlay.ship_render_pos = player.interpolated_position(alpha) - render_origin
	overlay.ship_forward = player.interpolated_orientation(alpha) * Vector3.FORWARD
	overlay.velocity_relative_to_target = has_target and input.flight_assist and input.velocity_hold == PlayerInput.VelocityHold.TARGET
	if overlay.velocity_relative_to_target:
		overlay.ship_velocity = player.velocity - target.velocity
	else:
		overlay.ship_velocity = orbit.velocity.to_vector3() if orbit != null else player.velocity
	overlay.aim_point = overlay.size * 0.5 + input.aim_offset
	overlay.has_target = contact
	overlay.has_lead = false
	overlay.target_estimated = false
	if contact:
		var measured := track == null or track.in_contact
		var target_pos := target.interpolated_position(alpha) if measured else track.estimated_position(player, t)
		overlay.target_render_pos = target_pos - render_origin
		overlay.target_estimated = not measured
		var dist := player.position.distance_to(target_pos)
		overlay.target_label = HudFormat.distance(dist) if measured else "~%s ?" % HudFormat.distance(dist)
		var lead := _lead_solution(player, target)
		if not lead.is_empty() and (track == null or track.locked):
			overlay.has_lead = true
			overlay.lead_render_pos = overlay.ship_render_pos + (lead.offset as Vector3)
			overlay.lead_label = "~%.2f s" % lead.time
			# Other gun types: their own (smaller) lead markers.
			overlay.extra_leads = []
			var seen := {player.config.cannon.display_name: true}
			for k in player.config.cannon_muzzles_body.size():
				var gun := player.config.mount_cannon(k)
				if seen.has(gun.display_name):
					continue
				seen[gun.display_name] = true
				var other := _lead_solution(player, target, gun, k)
				if not other.is_empty():
					overlay.extra_leads.append({"pos": overlay.ship_render_pos + (other.offset as Vector3), "label": gun.display_name.left(1)})
	_update_gun_reticles(player, alpha, render_origin, input)
	# The jump: the view whitens over the last second and a half of the charge.
	var flash := 0.0
	if jump_state.has("progress") and (jump_state.waiting as PackedStringArray).is_empty():
		flash = clampf((float(jump_state.progress) - 0.7) / 0.3, 0.0, 1.0)
	_jump_flash.color.a = flash * flash * 0.9
	_update_orbit_path(world, orbit, alpha, render_origin)
	overlay.queue_redraw()

	_update_radar(world, player, target if contact else null)
	damage_map.systems = player.systems
	# The docking camera takes the damage map's corner while it is up.
	damage_map.visible = not overview.visible and not docking_cam.visible
	help_label.visible = not overview.visible and not docking_cam.visible
	_reflow_for_drawer()
	($Root/TargetPanel as Control).visible = right_column_fits
	radar.visible = right_column_fits and radar_fits
	if not right_column_fits and not hit_cam.showing_boarding():
		hit_cam.visible = false
	if overview.visible:
		overview.vessel = profile.vessel if profile != null else null
		var link := world.link_for(player.id)
		overview.update_view(player, target, world.boarding_for(link) if link != null else null, boarding_party_size, t,
			player_wing, contact and (player_wing == null or player_wing.has_close_look(world, target)))


# --- Own ship ----------------------------------------------------------------------

func _update_own_card(world: WorldSimulation, player: ShipState, orbit: OrbitElements, input: PlayerInput,
		has_target: bool, alerts: Array[Dictionary]) -> void:
	_own_heading.text = "OWN SHIP · %s" % player.config.display_name
	var w := player.angular_velocity
	var lines := PackedStringArray([
		"ASSIST  %s  [Z][X]" % _assist_text(input, has_target),
		"VEL     %s" % _velocity_text(player, orbit),
		"ATT     %s" % _attitude_text(player, orbit),
		"        P %+5.1f  Y %+5.1f  R %+5.1f °/s" % [rad_to_deg(w.x), rad_to_deg(w.y), rad_to_deg(w.z)],
		"PROP    %s" % _propellant_text(player),
	])
	var sys := player.systems
	if sys != null:
		lines.append("HULL    %s" % _hull_text(sys))
		var pwr: Array = [CyberTheme.GLYPH_OK, "nominal"]
		if sys.reactor_state == ShipSystems.Reactor.SCRAM or sys.power_supply_kw <= 0.0:
			pwr = [CyberTheme.GLYPH_CRITICAL, "NO POWER"]
		elif sys.power_unmet_kw > 0.0 or sys.reactor_state == ShipSystems.Reactor.THROTTLED:
			pwr = [CyberTheme.GLYPH_DEGRADED, "SHORT %.0f kW" % sys.power_unmet_kw if sys.power_unmet_kw > 0.0 else "THROTTLED"]
		var heat: String = CyberTheme.GLYPH_OK if sys.temperature_k < ShipSystems.THROTTLE_TEMP_K else (CyberTheme.GLYPH_DEGRADED if sys.temperature_k < ShipSystems.SCRAM_TEMP_K else CyberTheme.GLYPH_CRITICAL)
		lines.append("POWER   %s %.0f/%.0f kW %s   HEAT %s %.0f K" % [pwr[0], sys.power_demand_kw - sys.power_unmet_kw,
			sys.power_supply_kw, pwr[1], heat, sys.temperature_k])
		lines.append("DIVERT  %s  [1-4]" % power_pips_text(sys))
	if alerts.is_empty():
		lines.append("ALERTS  none")
	else:
		for k in mini(alerts.size(), 3):
			var a: Dictionary = alerts[k]
			lines.append("%s %s  %s" % ["ALERTS " if k == 0 else "       ", a.glyph, a.short])
	flight_label.text = "\n".join(lines)


func _velocity_text(player: ShipState, orbit: OrbitElements) -> String:
	var inertial := orbit.speed if orbit != null else player.velocity.length()
	return "%.1f m/s %s · local %.1f m/s" % [inertial, "orbital" if orbit != null else "inertial", player.velocity.length()]


## Where the nose points relative to where the ship is going.
func _attitude_text(player: ShipState, orbit: OrbitElements) -> String:
	var v := orbit.velocity.to_vector3() if orbit != null else player.velocity
	if v.length() < 0.5:
		return "nose — no velocity vector"
	var off := rad_to_deg(player.forward().angle_to(v))
	return "nose %.1f° off prograde%s" % [off, "  (retrograde)" if off > 150.0 else ""]


func _hull_text(sys: ShipSystems) -> String:
	var s := 0.0
	var m := 0.0
	for mod in sys.modules:
		s += mod.structure
		m += mod.max_structure
	var frac := s / maxf(m, 1.0)
	var degraded := 0
	var lost := 0
	for e in sys.equipment:
		if e.destroyed():
			lost += 1
		elif e.hp < e.max_hp or not e.powered:
			degraded += 1
	var glyph := CyberTheme.GLYPH_OK if frac > 0.99 else (CyberTheme.GLYPH_DEGRADED if frac > 0.5 else CyberTheme.GLYPH_CRITICAL)
	var parts := ["%s %d%%" % [glyph, roundi(frac * 100.0)]]
	parts.append("systems ok" if degraded + lost == 0 else "%s%d degraded %s%d lost" % [
		CyberTheme.GLYPH_DEGRADED, degraded, CyberTheme.GLYPH_DESTROYED, lost])
	if sys.breached_count() > 0:
		parts.append("%d vented" % sys.breached_count())
	return "  ".join(parts)


## One line per wing: callsign, state or directive, hull.
static func wing_text(wing: AirWing) -> String:
	var parts := PackedStringArray()
	for c in wing.crafts:
		var state: String = AirWing.STATUS_NAMES[c.status]
		if c.status == AirWing.Status.FLYING:
			state = CraftAI.DIRECTIVE_NAMES[c.directive].to_lower() if c.override_reason == "" else "RTB"
		elif c.status == AirWing.Status.DOCKED and c.service_left_s > 0.0:
			state = "servicing %.0fs" % c.service_left_s
		parts.append("%s %s %d%%" % [c.label.split(" ")[-1], state, roundi(c.hull_fraction * 100.0)])
	return " · ".join(parts)


static func power_pips_text(sys: ShipSystems) -> String:
	var parts := PackedStringArray()
	for ch in ShipSystems.Channel.size():
		parts.append("%s %s" % [ShipSystems.CHANNEL_NAMES[ch], "■".repeat(sys.pips[ch]) + "□".repeat(ShipSystems.PIPS_MAX - sys.pips[ch])])
	return "  ".join(parts)


func _repair_text(sys: ShipSystems) -> String:
	if sys.repair_task != null:
		var t := sys.repair_task
		return "patching %s  %d%%  (%.0f s)" % [t.equipment_id, roundi(t.progress() * 100.0), t.remaining_s]
	var why := sys.field_repair_block_reason()
	if why == "":
		var e := sys.field_repair_target()
		return "[C] patch %s %s (%d%%)" % [e.def.display_name, e.id, roundi(100.0 * e.hp / e.max_hp)]
	return why


func _propellant_text(ship: ShipState) -> String:
	if ship.config.unlimited_propellant:
		return "unlimited"
	if ship.propellant_kg <= 0.0:
		return "%s EMPTY — no thrust" % CyberTheme.GLYPH_CRITICAL
	var frac := ship.propellant_kg / maxf(ship.config.propellant_capacity_kg, 1.0)
	var bars := roundi(frac * 10.0)
	return "%s %.1f t · Δv %.0f m/s" % ["█".repeat(bars) + "░".repeat(10 - bars), ship.propellant_kg / 1000.0, ship.delta_v_remaining()]


func _assist_text(input: PlayerInput, has_target: bool) -> String:
	if not input.flight_assist:
		return "OFF — MANUAL"
	if input.velocity_hold == PlayerInput.VelocityHold.TARGET:
		return "ON · MATCH TARGET" if has_target else "ON · MATCH TARGET (none) → HOLD ORBIT"
	return "ON · HOLD ORBIT"


# --- Alerts ------------------------------------------------------------------------

## Urgent conditions, worst first: {level ("danger"/"caution"), glyph,
## short (card), text (banner), action, subject (system/room id or "")}.
func _alerts(world: WorldSimulation, player: ShipState, orbit: OrbitElements) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := world.sim_time
	if not player.is_active():
		out.append(_alert("danger", "VESSEL LOST", "VESSEL LOST AT T+%s" % HudFormat.clock(player.status_time), "[BACKSPACE] respawn · [B] station"))
		return out
	if not player.config.unlimited_propellant and player.propellant_kg <= 0.0:
		out.append(_alert("danger", "PROPELLANT EXHAUSTED", "PROPELLANT EXHAUSTED — NO THRUST, NO RCS", "[B] dock to refuel"))
	var incoming := incoming_round_time(world, player)
	if incoming >= 0.0:
		out.append(_alert("danger", "INCOMING %.1f s" % incoming, "INCOMING ROUND — IMPACT IN %.1f s" % incoming, "evade: [W][S][A][D][R][F]"))
	if jump_state.has("blocked"):
		out.append(_alert("caution", "JUMP BLOCKED", "JUMP DRIVE BLOCKED — %s" % str(jump_state.blocked).to_upper(), "release [B]"))
	elif jump_state.has("progress"):
		var waiting: PackedStringArray = jump_state.waiting
		var bars := roundi(float(jump_state.progress) * 10.0)
		if waiting.is_empty():
			out.append(_alert("caution", "JUMP %.1f s" % jump_state.left_s, "DIMENSIONAL JUMP DRIVE %s %.1f s TO EARTH SHIPYARD" % [
				"▮".repeat(bars) + "▯".repeat(10 - bars), jump_state.left_s], "keep holding [B]"))
		else:
			out.append(_alert("caution", "JUMP HOLDING", "JUMP DRIVE %s HOLDING — %s BEFORE THE JUMP" % [
				"▮".repeat(bars) + "▯".repeat(10 - bars), " · ".join(waiting).to_upper()], "keep holding [B]"))
	var link := world.link_for(player.id)
	var b := world.boarding_for(link) if link != null else null
	if link != null and link.attacker_id != player.id:
		var where := "ON THE GANGWAY" if b == null or b.room < 0 else "IN %s" % player.systems.blueprint.rooms[b.room].id
		out.append(_alert("danger", "ENEMY BOARDERS", "ENEMY BOARDING — %s%s" % [where if b != null else "GANGWAY EXTENDING",
			" · %d/%d FIT · DEFENCE: %s" % [b.fit_team().size(), b.team.size(), BoardingAction.DEFENCE_NAMES[b.defence].to_upper()] if b != null else ""],
			"[V] cut the gangway · [Tab] CREW › defence"))
	elif b != null and not b.finished() and not b.prize and b.phase == BoardingAction.Phase.ABOARD:
		out.append(_alert("caution", "BOARDERS ACROSS", "BOARDING PARTY ON %s — %d/%d FIT" % [
			world.get_ship(link.target_id).display_name.to_upper(), b.fit_team().size(), b.team.size()], "[N] withdraw"))
	if profile != null and profile.vessel != null and player.systems != null:
		var over := profile.vessel.cargo_volume_m3(ConstructionCatalog.default_catalog()) - player.systems.stats.cargo_m3
		if over > 0.0:
			out.append(_alert("caution", "HOLD +%.0f m³" % over, "CARGO HOLD OVER CAPACITY BY %.1f m³" % over, "[Tab] CARGO › vent excess"))
	var sys := player.systems
	if sys != null:
		var reactor := ""
		for e in sys.equipment:
			if e.def.kind == EquipmentDefinition.Kind.REACTOR:
				reactor = e.id
				break
		if sys.reactor_state == ShipSystems.Reactor.SCRAM:
			out.append(_alert("danger", "REACTOR SCRAM %.0f K" % sys.temperature_k,
				"REACTOR SCRAM — %.0f K — NO POWER UNTIL BELOW %.0f K" % [sys.temperature_k, ShipSystems.RESTART_TEMP_K], "cut thrust · [Tab] reactor", reactor))
		elif sys.reactor_state == ShipSystems.Reactor.THROTTLED:
			out.append(_alert("caution", "REACTOR THROTTLED", "REACTOR THROTTLED — OVERHEATING (%.0f K)" % sys.temperature_k, "ease off the engines · [Tab]", reactor))
		elif sys.power_unmet_kw > 0.0:
			out.append(_alert("caution", "POWER SHORT %.0f kW" % sys.power_unmet_kw, "POWER SHORT BY %.0f kW — LOW-PRIORITY SYSTEMS SHED" % sys.power_unmet_kw, "[Tab] power"))
		if world.weapons_locked(player.id) and player.config.cannon != null:
			out.append(_alert("caution", "GUNS LOCKED", "GANGWAY ATTACHED — PRIMARY WEAPONS LOCKED (CRAFT STILL FIGHT)", "[V] release gangway"))
		if not sys.has_command():
			out.append(_alert("caution", "SHIP AI IN CONTROL", "BRIDGE CREW LOST — SHIP AI FLYING: %d %% THRUST AND TURN RATE, GUNS AT HALF RATE" % roundi(ShipSystems.SHIP_AI_FACTOR * 100.0),
				"[Tab] crew → cover command", sys.blueprint.rooms[sys.command_room()].id if sys.command_room() >= 0 else ""))
		if not sys.has_gun_crew():
			out.append(_alert("caution", "NO GUN CREW", "NO GUN CREW — AUTOLOADERS ONLY, HALF RATE OF FIRE", "[Tab] crew → cover weapons"))
		for e in sys.equipment:
			if not e.destroyed() and e.hp < 0.35 * e.max_hp:
				out.append(_alert("caution", "%s %s %d%%" % [e.def.display_name, e.id, roundi(100.0 * e.hp / e.max_hp)],
					"%s %s CRITICAL — %d %%" % [e.def.display_name.to_upper(), e.id, roundi(100.0 * e.hp / e.max_hp)], "[C] patch · [Tab]", e.id))
				break
	if _incoming != null and t - _incoming_time < HIT_ALERT_S:
		var subject := _incoming.destroyed_ids[0] if not _incoming.destroyed_ids.is_empty() else (_incoming.damaged_ids[0] if not _incoming.damaged_ids.is_empty() else "")
		out.append(_alert("caution", "HIT TAKEN: %s" % _incoming.headline(), "HIT TAKEN — %s" % _incoming.headline().to_upper(), "[J] log · [Tab] damage", subject))
	if orbit != null:
		var t_entry := orbit.time_to_radius_descending(world.body.entry_radius_m())
		if not is_nan(t_entry):
			out.append(_alert("caution", "ENTRY IN %s" % HudFormat.duration(t_entry), "PERIAPSIS BELOW %.0f km — ENTRY IN %s" % [
				world.body.entry_interface_altitude_m / 1000.0, HudFormat.duration(t_entry)], "[O] orbit · burn prograde"))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.level == "danger" and b.level != "danger")
	return out


func _alert(level: String, short: String, text: String, action: String, subject: String = "") -> Dictionary:
	return {"level": level, "glyph": CyberTheme.GLYPH_CRITICAL if level == "danger" else CyberTheme.GLYPH_DEGRADED,
		"short": short, "text": text, "action": action, "subject": subject}


func _update_banner(alerts: Array[Dictionary]) -> void:
	alert_subject = ""
	top_alert_level = ""
	if alerts.is_empty():
		warning_label.visible = false
		return
	var a: Dictionary = alerts[0]
	top_alert_level = a.level
	alert_subject = a.subject
	var color := CyberTheme.RED if a.level == "danger" else CyberTheme.AMBER
	warning_label.text = "%s %s   ·   %s" % [a.glyph, a.text, a.action]
	warning_label.add_theme_color_override("font_color", color)
	(warning_label.get_theme_stylebox("normal") as StyleBoxFlat).border_color = Color(color.r, color.g, color.b, 0.7)
	warning_label.visible = true
	_place_banner()
	_orbit_forced = a.text.begins_with("PERIAPSIS")


# --- Target --------------------------------------------------------------------------

func _update_target_card(world: WorldSimulation, player: ShipState, target: ShipState) -> void:
	var t := world.sim_time
	if target == null:
		_target_heading.text = "TARGET"
		target_label.text = "NO TARGET"
		return
	if not target.is_active():
		_target_heading.text = "TARGET · %s" % target.display_name
		target_label.text = "%s LOST — %s at T+%s\nHITS    %d" % [CyberTheme.GLYPH_DESTROYED,
			"atmospheric entry" if target.status == ShipState.Status.ENTERED_ATMOSPHERE else "destroyed", HudFormat.clock(target.status_time), _hits_scored]
		return
	var range_km := SensorTrack.range_of(player) / 1000.0
	if track != null and not track.detected:
		_target_heading.text = "TARGET · NO CONTACT"
		target_label.text = "\n".join([
			"TRACK   %s none — nothing inside sensor range" % CyberTheme.GLYPH_OFFLINE,
			"SENSORS %.0f km %s" % [range_km, "(mast)" if range_km > ShipSystems.VISUAL_RANGE_M / 1000.0 + 0.1 else "— VISUAL ONLY, sensors down"],
		])
		return
	var hostile := "%s HOSTILE" % CyberTheme.GLYPH_CRITICAL if target_hostile else "%s passive" % CyberTheme.GLYPH_OFFLINE
	_target_heading.text = "TARGET · %s   %s [T]" % [target.display_name, hostile]
	var measured := track == null or track.in_contact
	var quality := "MEAS" if track == null else track.quality(t)
	var est := "" if measured else "~"
	var pos := target.position if measured else track.estimated_position(player, t)
	var vel := target.velocity if measured else track.last_velocity
	var rng := player.position.distance_to(pos)
	var rr := RelativeMotion.range_rate(player.position, player.velocity, pos, vel)
	var rel_v := (vel - player.velocity).length()
	var track_line := "TRACK   %s %s" % [CyberTheme.GLYPH_CREW if measured else CyberTheme.GLYPH_OFFLINE, quality]
	if track != null:
		if not measured:
			track_line += " %.0f s old" % track.age(t)
		track_line += " · conf %d%% · %s" % [roundi(track.confidence * 100.0), "LOCK ●" if track.locked else "no lock ○"]
	var lead := _lead_solution(player, target)
	var eta := "—"
	if not lead.is_empty():
		eta = "~%.2f s round%s" % [lead.time, " (lead ◇)" if track == null or track.locked else " (no lock: no lead)"]
	var lines := PackedStringArray([
		"CLASS   %s" % target.config.display_name,
		track_line,
		"RANGE   %s%s   CLOSING %s%s" % [est, HudFormat.distance(rng), est, HudFormat.signed_speed(-rr)],
		"REL     %s%.1f m/s   ETA %s" % [est, rel_v, eta],
	])
	var close_look := measured and (player_wing == null or player_wing.has_close_look(world, target))
	if target.systems != null:
		if not close_look:
			lines.append("STATUS  %s hull only — close look needs < %.0f km or a recon drone" % [CyberTheme.GLYPH_OFFLINE, AirWing.INSPECT_RANGE_M / 1000.0])
		elif target.systems.is_disabled():
			var why := Salvage.block_reason(player, target)
			lines.append("STATUS  %s DISABLED — %s · %d%% intact" % [CyberTheme.GLYPH_DESTROYED, target.systems.disabled_reason().to_upper(), roundi(target.systems.intact_fraction() * 100.0)])
			if not target.systems.captured:
				lines.append("BEACON  %s" % ("READY — press [G] · %d%% of scrap · or board it for %d%%" % [
					roundi(Salvage.BEACON_SCRAP_RATE * 100.0), roundi(Salvage.TAKEOVER_SCRAP_RATE * 100.0)] if why == "" else why))
		else:
			lines.append("STATUS  %s combat-capable · %s" % [CyberTheme.GLYPH_OK, target.systems.status_line()])
		if track != null:
			lines.append(_scan_line(player, target))
		if close_look:
			lines.append_array(_boarding_lines(world, player, target))
	var hit_age := t - _last_hit_time
	if hit_age < 3.0 and _outgoing != null:
		lines.append("HIT     %s  (+%.1f s)  [J] log" % [_outgoing.headline(), hit_age])
	target_label.text = "\n".join(lines)


## Scan: hold the lock with an active sensor mast, then the estimated cargo
## and bounty (± SensorTrack.SCAN_ERROR).
func _scan_line(player: ShipState, target: ShipState) -> String:
	if track.scanned:
		var est := Salvage.scan_estimate(target.systems)
		return "SCAN    %s ~%d spare parts · ~%d crates · bounty ~%d cr" % [CyberTheme.GLYPH_OK,
			roundi(est.parts * track.scan_error), roundi(est.crates * track.scan_error), roundi(est.bounty * track.scan_error)]
	if not SensorTrack.has_active_sensors(player):
		return "SCAN    %s needs a working sensor mast" % CyberTheme.GLYPH_OFFLINE
	if not track.locked:
		return "SCAN    %s lock on (< %.0f km) to scan cargo and bounty" % [CyberTheme.GLYPH_OFFLINE, SensorTrack.LOCK_RANGE_M / 1000.0]
	var bars := roundi(track.scan_progress * 10.0)
	return "SCAN    %s %s %d%% — hold the lock" % [CyberTheme.GLYPH_DEGRADED, "▮".repeat(bars) + "▯".repeat(10 - bars), roundi(track.scan_progress * 100.0)]


## Docking tolerances when close, gangway state, and the boarding action.
func _boarding_lines(world: WorldSimulation, player: ShipState, target: ShipState) -> Array:
	var lines := []
	var link := world.link_for(player.id)
	if link == null:
		if player.position.distance_to(target.position) > 300.0:
			return lines
		var found := Docking.best(player, target)
		if found.is_empty():
			return lines
		var s: Dictionary = found.assessment
		lines.append("DOCKING    %s  [V]" % ("READY — %s" % ("collar" if found.b_port.kind == &"collar" else "hull cut") if s.ok else "; ".join(s.problems)))
		lines.append("           port gap %.0f / %.0f m · %.2f / %.1f m/s · %.0f° / %.0f°" % [s.range, Docking.GANGWAY_MAX_M,
			s.rel_speed, Docking.MAX_REL_SPEED_MPS, s.misalign_deg, Docking.MAX_MISALIGN_DEG])
		return lines
	if link.attacker_id != player.id:
		lines.append("GANGWAY    THEIRS — %s  [V] cut it loose" % ("sealed: boarders coming" if link.sealed() else "extending to us"))
		return lines
	if not link.sealed():
		lines.append("GANGWAY    %s %.0f / %.0f s  [V] release" % ["mating" if link.b_port.kind == &"collar" else "cutting in",
			link.progress_s, link.required_s])
		return lines
	var b := world.boarding_for(link)
	if b == null:
		lines.append("GANGWAY    SEALED — [N] send boarders  [V] release")
		return lines
	var where := "on the gangway" if b.room < 0 else target.systems.blueprint.rooms[b.room].id
	var doing: String = {&"cut": "cutting a hatch", &"move": "moving", &"cross": "crossing", &"muster": "mustering"}.get(b.action, "")
	if b.room >= 0 and not b.defenders_in(b.room).is_empty():
		doing = "FIGHTING %d defenders" % b.defenders_in(b.room).size()
	if b.prize:
		lines.append("BOARDING   CAPTURED — prize taken · boarders %s (%d/%d fit)" % [
			"home" if b.finished() else "withdrawing", b.fit_team().size(), b.team.size()])
		return lines
	lines.append("BOARDING   %s  %s %s  team %d/%d fit%s" % [BoardingAction.PHASE_NAMES[b.phase].to_upper(), where, doing,
		b.fit_team().size(), b.team.size(), "  [N] withdraw" if not b.finished() else ""])
	return lines


# --- Weapons, ticker, details -----------------------------------------------------------

func _update_weapon_strip(player: ShipState) -> void:
	var cannon := player.config.cannon
	var parts := PackedStringArray()
	if cannon == null:
		parts.append("GUN  none fitted")
	else:
		var frac := float(player.cannon_rounds) / maxf(cannon.magazine_rounds, 1.0)
		var bars := roundi(frac * 10.0)
		parts.append("GUN ▸ %s  %s %d/%d%s" % [battery_text(player.config, player), "▮".repeat(bars) + "▯".repeat(10 - bars),
			player.cannon_rounds, cannon.magazine_rounds, "  EMPTY" if player.cannon_rounds == 0 else ""])
	parts.append(pd_text(player))
	var lines := PackedStringArray(["   ·   ".join(parts)])
	if cannon != null:
		lines.append("GUNS  %s" % turret_summary(player.turret_status))
	if player_wing != null and not player_wing.crafts.is_empty():
		lines.append("WING  %s   [L] launch [K] recall" % wing_text(player_wing))
	weapon_label.text = "\n".join(lines)


## Point defence on the weapon strip: mounts, what they're engaging, rounds.
static func pd_text(ship: ShipState) -> String:
	var cfg := ship.config
	if cfg.pd_gun == null or cfg.pd_mounts_body.is_empty():
		return "PD  %s none fitted" % CyberTheme.GLYPH_OFFLINE
	var engaging := 0
	var rounds := 0
	for k in cfg.pd_mounts_body.size():
		rounds += ship.pd_rounds[k]
		if ship.pd_targets[k] != "":
			engaging += 1
	return "PD  %s ×%d %s · %d rds" % [CyberTheme.GLYPH_CREW if engaging > 0 else CyberTheme.GLYPH_OK, cfg.pd_mounts_body.size(),
		"ENGAGING" if engaging > 0 else "ready", rounds]


## "Medium kinetic cannon ×1 50 rpm · Railgun ×1 60 rpm" — the battery.
static func battery_text(cfg: ShipConfig, ship: ShipState = null) -> String:
	var counts := {}
	var order: Array[KineticCannonConfig] = []
	for k in cfg.cannon_muzzles_body.size():
		var gun := cfg.mount_cannon(k)
		if not counts.has(gun.display_name):
			order.append(gun)
		counts[gun.display_name] = int(counts.get(gun.display_name, 0)) + 1
	var parts := PackedStringArray()
	for gun in order:
		var rounds := " · %d rds" % ship.rounds_for(gun) if ship != null and order.size() > 1 else ""
		parts.append("%s ×%d %.0f rpm%s" % [gun.display_name, counts[gun.display_name], gun.rate_of_fire_rpm, rounds])
	return " · ".join(parts)


## "● 2 on · ▲ 1 training · ✕ 1 blocked" — what the guns are doing.
static func turret_summary(status: PackedInt32Array) -> String:
	var counts := {}
	for s in status:
		counts[s] = int(counts.get(s, 0)) + 1
	var words := {
		ShipState.Turret.READY: [CyberTheme.GLYPH_CREW, "on target"],
		ShipState.Turret.SLEWING: [CyberTheme.GLYPH_DEGRADED, "training"],
		ShipState.Turret.BLOCKED: [CyberTheme.GLYPH_DESTROYED, "blocked by hull"],
		ShipState.Turret.OUT_OF_ARC: [CyberTheme.GLYPH_DESTROYED, "out of arc"],
		ShipState.Turret.OFFLINE: [CyberTheme.GLYPH_OFFLINE, "offline"],
		ShipState.Turret.LOCKED: [CyberTheme.GLYPH_OFFLINE, "LOCKED (gangway)"],
	}
	var parts := PackedStringArray()
	for s in words:
		if counts.has(s):
			parts.append("%s %d %s" % [words[s][0], counts[s], words[s][1]])
	return " · ".join(parts)


func _update_ticker(t: float) -> void:
	_notices = _notices.filter(func(n: Dictionary) -> bool: return t - float(n.time) < NOTICE_S)
	var lines := PackedStringArray()
	for n in _notices:
		lines.append("» " + str(n.text).left(110))
	ticker_label.text = "\n".join(lines)


## Non-urgent telemetry and the latest damage reports (J).
func _update_details(world: WorldSimulation, player: ShipState) -> void:
	if not _details_panel.visible:
		_orbit_panel.visible = _orbit_panel.visible or _orbit_forced
		return
	_orbit_panel.visible = _orbit_panel.visible or _orbit_forced
	var v_body := player.body_velocity()
	var lines := PackedStringArray([
		"LOCAL VEL  fwd %s · right %s · up %s" % [HudFormat.signed_speed(-v_body.z), HudFormat.signed_speed(v_body.x), HudFormat.signed_speed(v_body.y)],
		"Δv SPENT   %.1f m/s" % player.delta_v_expended,
		"ROUNDS UP  %d near · %d far orbit · recoil %.1f kN·s" % [_rounds_near, _rounds_far, player.recoil_impulse / 1000.0],
		"T+         %s" % HudFormat.clock(world.sim_time),
	])
	var sys := player.systems
	if sys != null:
		lines.append("SYSTEMS    %s" % sys.status_line())
		lines.append("DMG CTRL   %s" % _repair_text(sys))
		if sys.crew != null and not sys.crew.members.is_empty():
			lines.append("CREW       %s" % sys.crew.summary())
	if profile != null and profile.vessel != null:
		lines.append("CREDITS    %d · HOLD %s" % [profile.credits, profile.vessel.cargo_summary().left(48)])
	if _incoming != null:
		lines.append("LAST HIT TAKEN  %s" % _incoming.headline())
		for l in _incoming.lines.slice(maxi(_incoming.lines.size() - 4, 1)):
			lines.append("  " + l.left(64))
	if _outgoing != null:
		lines.append("LAST HIT SCORED %s" % _outgoing.headline())
		for l in _outgoing.lines.slice(maxi(_outgoing.lines.size() - 4, 1)):
			lines.append("  " + l.left(64))
	details_label.text = "\n".join(lines)


# --- Orbit ------------------------------------------------------------------------------

func _update_orbit_panel(world: WorldSimulation, player: ShipState, orbit: OrbitElements) -> void:
	if orbit == null:
		orbit_label.text = "NO CENTRAL BODY — INERTIAL SPACE"
		return
	var body := world.body
	var lines := PackedStringArray([
		"ORBIT      %s" % body.display_name.to_upper(),
		"ALTITUDE   %s" % HudFormat.altitude(world.altitude_of(player)),
		"ORB SPEED  %.1f m/s  (circ %.1f)" % [orbit.speed, body.circular_speed(orbit.radius)],
	])
	var circular := orbit.eccentricity < CIRCULAR_ECCENTRICITY
	if orbit.is_bound():
		var t_apo := "" if circular else "  in %s" % HudFormat.duration(orbit.time_to_apoapsis())
		var t_peri := "" if circular else "  in %s" % HudFormat.duration(orbit.time_to_periapsis())
		lines.append("APOAPSIS   %s%s" % [HudFormat.altitude(orbit.apoapsis_radius - body.radius_m), t_apo])
		lines.append("PERIAPSIS  %s%s" % [HudFormat.altitude(orbit.periapsis_radius - body.radius_m), t_peri])
		lines.append("PERIOD     %s" % HudFormat.duration(orbit.period))
	else:
		lines.append("APOAPSIS   ESCAPE TRAJECTORY")
		lines.append("PERIAPSIS  %s" % HudFormat.altitude(orbit.periapsis_radius - body.radius_m))
	var t_entry := orbit.time_to_radius_descending(body.entry_radius_m())
	var entry_alt_km := body.entry_interface_altitude_m / 1000.0
	if is_nan(t_entry):
		lines.append("ENTRY IF   %.0f km · CLEAR" % entry_alt_km)
	else:
		lines.append("ENTRY IF   %.0f km · IN %s" % [entry_alt_km, HudFormat.duration(t_entry)])
	if celestial != null:
		var sun_dir := celestial.sun_direction_pci(world.sim_time)
		var lit := CelestialFrame.sunlight_fraction(orbit.position, sun_dir, body.radius_m) >= 0.5
		var change := CelestialFrame.next_light_change(orbit, sun_dir, body.radius_m)
		var when := "" if change.is_empty() else "  %s in %s" % [
			"sunrise" if change.sunlit_after else "sunset", HudFormat.duration(change.time)]
		lines.append("SUN        %s%s" % ["LIT" if lit else "ECLIPSE", when])
	orbit_label.text = "\n".join(lines)


## Seconds until the nearest round on a collision course reaches `ship`
## (straight-line closest approach within the hull's radius, next 10 s;
## includes the ship's own rounds once armed), or -1.
static func incoming_round_time(world: WorldSimulation, ship: ShipState) -> float:
	var radius := ship.config.hit_box_half_extents.length()
	var best := INF
	for shot in world.projectiles():
		if shot.shooter_id == ship.id and shot.age_s < WorldSimulation.ARM_TIME_S:
			continue
		var p := shot.position - ship.position
		var v := shot.velocity - ship.velocity
		var vv := v.length_squared()
		if vv < 1e-6:
			continue
		var t := -p.dot(v) / vv
		if t > 0.0 and t < 10.0 and (p + v * t).length() < radius and t < best:
			best = t
	return best if best < INF else -1.0


## {time, direction} for the player's cannon against the target, or {}.
func _lead_solution(player: ShipState, target: ShipState, gun: KineticCannonConfig = null, mount: int = 0) -> Dictionary:
	var cannon := player.config.cannon if gun == null else gun
	if cannon == null:
		return {}
	var muzzle := player.position + player.orientation * player.config.cannon_muzzles_body[mount]
	var aim := target.position + target.orientation * target.config.hit_box_center
	var rel_pos := aim - muzzle
	var rel_vel := target.velocity - player.velocity
	var t := FireControl.intercept_time(rel_pos, rel_vel, cannon.muzzle_velocity_mps)
	if t < 0.0:
		return {}
	var lead := FireControl.lead_point(rel_pos, rel_vel, t)
	return {"time": t, "direction": lead.normalized(), "offset": muzzle - player.position + lead}


## One reticle per gun: where its barrel points, at the aim range.
func _update_gun_reticles(player: ShipState, alpha: float, render_origin: Vector3, input: PlayerInput) -> void:
	overlay.gun_reticles = []
	var cfg := player.config
	if cfg.cannon == null or not player.is_active():
		return
	var q := player.interpolated_orientation(alpha)
	var base := player.interpolated_position(alpha) - render_origin
	for k in cfg.cannon_muzzles_body.size():
		var muzzle := cfg.cannon_muzzles_body[k]
		if cfg.is_turret(k):
			muzzle += cfg.cannon_mount_normals_body[k] * WorldSimulation.TURRET_HEIGHT_M
		var p := base + q * muzzle + q * player.turret_dirs[k] * input.aim_range_m
		overlay.gun_reticles.append({"pos": p, "status": player.turret_status[k], "label": str(k + 1)})


func _update_orbit_path(world: WorldSimulation, orbit: OrbitElements, alpha: float, render_origin: Vector3) -> void:
	overlay.orbit_path = PackedVector3Array()
	overlay.orbit_markers = []
	if orbit == null:
		overlay.planet_radius = 0.0
		return
	var body := world.body
	# PCI position of the render origin; path points are drawn relative to it.
	var origin_pci := world.frame.interpolated_origin(alpha).plus_v3(render_origin)
	overlay.planet_center = Vec3d.new().minus(origin_pci).to_vector3()
	overlay.planet_radius = body.radius_m
	var entry_r := body.entry_radius_m()
	var path := PackedVector3Array()
	# Dense for the first 20° (the stretch seen near the prograde marker),
	# then every 2°. Start a little ahead: the ship itself is drawn by the 3D
	# view, and the orbit's state is up to one tick ahead of the rendered ship.
	var angles := PackedFloat32Array()
	for i in range(1, NEAR_PATH_SAMPLES + 1):
		angles.append(deg_to_rad(NEAR_PATH_DEG) * i / NEAR_PATH_SAMPLES)
	for i in range(1, PATH_SAMPLES + 1):
		var a := TAU * i / PATH_SAMPLES
		if a > deg_to_rad(NEAR_PATH_DEG):
			angles.append(a)
	for angle in angles:
		var p := orbit.point_at_angle(angle)
		if p == null or p.length() > body.radius_m * 12.0:
			break
		path.append(p.minus(origin_pci).to_vector3())
		if p.length() < entry_r:
			break  # the path ends where it meets the entry interface
	overlay.orbit_path = path

	if orbit.is_bound() and orbit.eccentricity >= CIRCULAR_ECCENTRICITY:
		_add_marker(orbit, origin_pci, PI - orbit.true_anomaly, "Ap %s" % HudFormat.altitude(orbit.apoapsis_radius - body.radius_m), COLOR_APSIS)
		if orbit.periapsis_radius >= entry_r:
			_add_marker(orbit, origin_pci, -orbit.true_anomaly, "Pe %s" % HudFormat.altitude(orbit.periapsis_radius - body.radius_m), COLOR_APSIS)
	if orbit.intersects_radius(entry_r) and orbit.radius > entry_r:
		var cos_nu := clampf((orbit.semi_latus_rectum / entry_r - 1.0) / orbit.eccentricity, -1.0, 1.0)
		_add_marker(orbit, origin_pci, -acos(cos_nu) - orbit.true_anomaly, "ENTRY %.0f km" % (body.entry_interface_altitude_m / 1000.0), CyberTheme.AMBER)


func _add_marker(orbit: OrbitElements, origin_pci: Vec3d, angle: float, text: String, color: Color) -> void:
	var p := orbit.point_at_angle(fposmod(angle, TAU))
	if p != null:
		overlay.orbit_markers.append({"pos": p.minus(origin_pci).to_vector3(), "text": text, "color": color})


## Radar contact at the measured position, or the dead-reckoned estimate
## (dimmed) when the track is not fresh.
func _update_radar(world: WorldSimulation, player: ShipState, target: ShipState) -> void:
	radar.contacts = []
	if target != null:
		var inv := player.orientation.inverse()
		var measured := track == null or track.in_contact
		var pos := target.position if measured else track.estimated_position(player, world.sim_time)
		var vel := target.velocity if measured else track.last_velocity
		var rel := inv * (pos - player.position)
		radar.contacts.append({
			"rel_body": rel,
			"rel_vel_body": inv * (vel - player.velocity),
			"range_rate": RelativeMotion.range_rate(player.position, player.velocity, pos, vel),
			"color": COLOR_TARGET if measured else COLOR_TARGET * Color(1, 1, 1, 0.45),
		})
		radar.scale_m = RadarMath.nice_scale(rel.length())
	radar.queue_redraw()
