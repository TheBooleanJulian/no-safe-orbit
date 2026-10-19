class_name Hud
extends CanvasLayer
## Flight HUD: text panels, warning banner, world-marker overlay and radar.
## Reads simulation state only; owns no gameplay logic.

const COLOR_WARN := Color(0.96, 0.78, 0.26)
const COLOR_DANGER := Color(1.0, 0.38, 0.32)
const COLOR_TARGET := Color(1.0, 0.45, 0.3, 0.95)
const COLOR_APSIS := Color(0.35, 1.0, 0.55, 0.9)
## Below this eccentricity, apsis positions and times are meaningless.
const CIRCULAR_ECCENTRICITY := 1e-4
const PATH_SAMPLES := 180
const NEAR_PATH_DEG := 20.0
const NEAR_PATH_SAMPLES := 80

@onready var overlay: HudOverlay = $Root/Overlay
@onready var radar: RadarDisplay = $Root/Radar
@onready var flight_label: Label = $Root/LeftColumn/FlightPanel/Margin/FlightLabel
@onready var orbit_label: Label = $Root/LeftColumn/OrbitPanel/Margin/OrbitLabel
@onready var target_label: Label = $Root/TargetPanel/Margin/TargetLabel
@onready var warning_label: Label = $Root/WarningLabel
@onready var controls: ControlsPanel = $Root/Controls
@onready var hit_cam: HitCam = $Root/HitCam

## Real-sky frame, for the sunlight / eclipse readout (set by Main).
var celestial: CelestialFrame

## Main sets this when the target is shooting back (T).
var target_hostile: bool = false
## Persistent player state, for spare parts (set by Main).
var profile: PlayerProfile
## Salvage results panel (created in _ready).
var loot: LootPanel

var _last_hit_time := -INF
var _hits_scored := 0
var _rounds_near := 0
var _rounds_far := 0
## Latest damage report on the target (our hits) and on us (incoming).
var _outgoing: DamageReport
var _incoming: DamageReport
var _incoming_time := -INF
var _hits_taken := 0
var _notice := ""
var _notice_time := -INF
const NOTICE_S := 6.0


func _ready() -> void:
	loot = LootPanel.new()
	loot.name = "Loot"
	$Root.add_child(loot)
	loot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)


## A one-line message on the flight panel for a few seconds.
func notice(text: String, sim_time: float) -> void:
	_notice = text
	_notice_time = sim_time


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

	_update_flight_panel(player, input, world.sim_time, has_target)
	_update_orbit_panel(world, player, orbit)
	_update_target_panel(world, player, target)
	_rounds_near = world.projectiles().size()
	_rounds_far = world.far_projectiles().size()
	_update_warning(world, player, orbit)

	overlay.camera = camera
	overlay.ship_render_pos = player.interpolated_position(alpha) - render_origin
	overlay.ship_forward = player.interpolated_orientation(alpha) * Vector3.FORWARD
	overlay.ship_velocity = orbit.velocity.to_vector3() if orbit != null else player.velocity
	overlay.mouse_stick = input.mouse_stick
	overlay.has_target = has_target
	overlay.has_lead = false
	if has_target:
		overlay.target_render_pos = target.interpolated_position(alpha) - render_origin
		overlay.target_label = HudFormat.distance(player.position.distance_to(target.position))
		var lead := _lead_solution(player, target)
		if not lead.is_empty():
			overlay.has_lead = true
			overlay.lead_render_pos = overlay.ship_render_pos + (lead.direction as Vector3) * HudOverlay.MARKER_DISTANCE_M
			overlay.lead_label = "%.2f s" % lead.time
	_update_orbit_path(world, orbit, alpha, render_origin)
	overlay.queue_redraw()

	_update_radar(player, target if has_target else null)


func _update_flight_panel(player: ShipState, input: PlayerInput, sim_time: float, has_target: bool) -> void:
	var v_body := player.body_velocity()
	var w := player.angular_velocity
	var cannon := player.config.cannon
	var gun := "—"
	if cannon != null:
		gun = "%d / %d%s" % [player.cannon_rounds, cannon.magazine_rounds,
			"  EMPTY" if player.cannon_rounds == 0 else ""]
	flight_label.text = "\n".join([
		"NO SAFE ORBIT  //  ORBITAL SANDBOX",
		"ASSIST     %s   [Z][X]" % _assist_text(input, has_target),
		"LOCAL VEL  %.1f m/s" % player.velocity.length(),
		"  fwd      %s" % HudFormat.signed_speed(-v_body.z),
		"  right    %s" % HudFormat.signed_speed(v_body.x),
		"  up       %s" % HudFormat.signed_speed(v_body.y),
		"RATE °/s   P %+5.1f  Y %+5.1f  R %+5.1f" % [rad_to_deg(w.x), rad_to_deg(w.y), rad_to_deg(w.z)],
		"Δv SPENT   %.1f m/s" % player.delta_v_expended,
		"PROPELLANT %s" % _propellant_text(player),
		"CANNON     %s" % gun,
		"ROUNDS UP  %d near · %d far orbit   recoil %.1f kN·s" % [
			_rounds_near, _rounds_far, player.recoil_impulse / 1000.0],
	] + _systems_lines(player, sim_time) + [
		"T+         %s" % HudFormat.clock(sim_time),
	])


## Own-ship power, heat and damage; the latest incoming hit.
func _systems_lines(ship: ShipState, sim_time: float) -> Array:
	var sys := ship.systems
	if sys == null:
		return []
	var lines := [
		"POWER      %.0f / %.0f kW%s" % [sys.power_demand_kw - sys.power_unmet_kw, sys.power_supply_kw,
			"  SHORT %.0f" % sys.power_unmet_kw if sys.power_unmet_kw > 0.0 else ""],
		"HEAT       %.0f K  %s" % [sys.temperature_k, ["reactor normal", "REACTOR THROTTLED", "REACTOR SCRAM"][sys.reactor_state]],
		"SYSTEMS    %s" % sys.status_line(),
		"DMG CTRL   %s" % _repair_text(sys),
	]
	if sys.crew != null and not sys.crew.members.is_empty():
		lines.append("CREW       %s  %s" % [sys.crew.summary(),
			("CMD ok" if sys.has_command() else "NO COMMAND") + (" · GUN CREW ok" if sys.has_gun_crew() else " · NO GUN CREW")])
	if profile != null:
		lines.append("SPARES     %d parts" % profile.spare_parts)
	if _notice != "" and sim_time - _notice_time < NOTICE_S:
		lines.append("» " + _notice.left(60))
	if _incoming != null and sim_time - _incoming_time < 8.0:
		lines.append("HIT TAKEN  %s  (+%.0f s)" % [_incoming.headline(), sim_time - _incoming_time])
		for line in _incoming.lines.slice(maxi(_incoming.lines.size() - 2, 1)):
			lines.append("  " + line.left(58))
	return lines


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
		return "EMPTY — engines dead"
	return "%.1f t  Δv left %.0f m/s" % [ship.propellant_kg / 1000.0, ship.delta_v_remaining()]


func _assist_text(input: PlayerInput, has_target: bool) -> String:
	if not input.flight_assist:
		return "OFF — MANUAL"
	if input.velocity_hold == PlayerInput.VelocityHold.TARGET:
		return "ON · MATCH TARGET" if has_target else "ON · MATCH TARGET (none) → HOLD ORBIT"
	return "ON · HOLD ORBIT"


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


func _update_target_panel(world: WorldSimulation, player: ShipState, target: ShipState) -> void:
	if target == null:
		target_label.text = "NO TARGET"
		return
	if not target.is_active():
		target_label.text = "\n".join([
			"TARGET     %s" % target.display_name,
			"LOST — ATMOSPHERIC ENTRY",
			"           at T+%s" % HudFormat.clock(target.status_time),
			"HITS       %d" % _hits_scored,
		])
		return
	var rng := RelativeMotion.range_between(player.position, target.position)
	var rr := RelativeMotion.range_rate(player.position, player.velocity, target.position, target.velocity)
	var rel_v := RelativeMotion.relative_velocity(player.velocity, target.velocity)
	var lead := _lead_solution(player, target)
	var tof := "NO FIRING SOLUTION"
	if not lead.is_empty():
		tof = "%.2f s  (lead ◇)" % lead.time
	var hit_age := world.sim_time - _last_hit_time
	var hits := "%d" % _hits_scored
	if hit_age < 3.0:
		hits += "   HIT +%.1f s" % hit_age
	var lines := [
		"TARGET     %s%s" % [target.display_name, "   HOSTILE [T]" if target_hostile else ""],
		"           %s" % target.config.display_name,
		"RANGE      %s" % HudFormat.distance(rng),
		"RANGE RATE %s  %s" % [HudFormat.signed_speed(rr), HudFormat.closure(rr)],
		"REL SPEED  %.1f m/s" % rel_v.length(),
		"ROUND TOF  %s" % tof,
		"HITS       %s" % hits,
	]
	if target.systems != null:
		lines.append("SYSTEMS    %s" % target.systems.status_line())
		lines.append("REACTOR    %s  %.0f K" % [["normal", "THROTTLED", "SCRAM"][target.systems.reactor_state], target.systems.temperature_k])
		if target.systems.is_disabled():
			var why := Salvage.block_reason(player, target)
			lines.append("DISABLED   %s  —  %d%% intact" % [target.systems.disabled_reason().to_upper(), roundi(target.systems.intact_fraction() * 100.0)])
			lines.append("SALVAGE    %s" % ("READY — press [G]" if why == "" else why))
		lines.append_array(_boarding_lines(world, player, target))
	if _outgoing != null:
		lines.append("LAST HIT   %s" % _outgoing.headline())
		for line in _outgoing.lines.slice(maxi(_outgoing.lines.size() - 3, 1)):
			lines.append("  " + line.left(58))
	target_label.text = "\n".join(lines)


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
	lines.append("BOARDING   %s  %s %s  team %d/%d fit%s" % [BoardingAction.PHASE_NAMES[b.phase].to_upper(), where, doing,
		b.fit_team().size(), b.team.size(), "  [N] withdraw" if not b.finished() else ""])
	for line in b.log.slice(maxi(b.log.size() - 3, 0)):
		lines.append("  " + line.left(58))
	return lines


func _update_warning(world: WorldSimulation, player: ShipState, orbit: OrbitElements) -> void:
	if not player.is_active():
		warning_label.text = "ATMOSPHERIC ENTRY — VESSEL LOST AT T+%s\n[BACKSPACE] restart" % HudFormat.clock(player.status_time)
		warning_label.add_theme_color_override("font_color", COLOR_DANGER)
		warning_label.visible = true
		return
	if not player.config.unlimited_propellant and player.propellant_kg <= 0.0:
		warning_label.text = "PROPELLANT EXHAUSTED — NO THRUST, NO RCS"
		warning_label.add_theme_color_override("font_color", COLOR_DANGER)
		warning_label.visible = true
		return
	var incoming := incoming_round_time(world, player)
	if incoming >= 0.0:
		warning_label.text = "INCOMING ROUND — IMPACT IN %.1f s" % incoming
		warning_label.add_theme_color_override("font_color", COLOR_DANGER)
		warning_label.visible = true
		return
	var sys := player.systems
	if sys != null and not sys.has_command():
		warning_label.text = "BRIDGE CREW LOST — SHIP AI IN CONTROL: %d %% THRUST AND TURN RATE, ASSIST LOCKED ON" % roundi(ShipSystems.SHIP_AI_FACTOR * 100.0)
		warning_label.add_theme_color_override("font_color", COLOR_WARN)
		warning_label.visible = true
		return
	if sys != null and (sys.reactor_state != ShipSystems.Reactor.NORMAL or sys.power_unmet_kw > 0.0):
		if sys.reactor_state == ShipSystems.Reactor.SCRAM:
			warning_label.text = "REACTOR SCRAM — %.0f K — NO POWER UNTIL IT COOLS BELOW %.0f K" % [sys.temperature_k, ShipSystems.RESTART_TEMP_K]
		elif sys.reactor_state == ShipSystems.Reactor.THROTTLED:
			warning_label.text = "REACTOR THROTTLED — OVERHEATING (%.0f K) — EASE OFF THE ENGINES" % sys.temperature_k
		else:
			warning_label.text = "POWER SHORT BY %.0f kW — LOW-PRIORITY SYSTEMS SHED" % sys.power_unmet_kw
		warning_label.add_theme_color_override("font_color", COLOR_DANGER if sys.reactor_state == ShipSystems.Reactor.SCRAM else COLOR_WARN)
		warning_label.visible = true
		return
	if orbit != null:
		var t_entry := orbit.time_to_radius_descending(world.body.entry_radius_m())
		if not is_nan(t_entry):
			warning_label.text = "PERIAPSIS BELOW %.0f km ENTRY INTERFACE — ENTRY IN %s" % [
				world.body.entry_interface_altitude_m / 1000.0, HudFormat.duration(t_entry)]
			warning_label.add_theme_color_override("font_color", COLOR_WARN)
			warning_label.visible = true
			return
	warning_label.visible = false


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
func _lead_solution(player: ShipState, target: ShipState) -> Dictionary:
	var cannon := player.config.cannon
	if cannon == null:
		return {}
	var muzzle := player.position + player.orientation * player.config.primary_muzzle()
	var aim := target.position + target.orientation * target.config.hit_box_center
	var rel_pos := aim - muzzle
	var rel_vel := target.velocity - player.velocity
	var t := FireControl.intercept_time(rel_pos, rel_vel, cannon.muzzle_velocity_mps)
	if t < 0.0:
		return {}
	return {"time": t, "direction": FireControl.lead_point(rel_pos, rel_vel, t).normalized()}


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
		_add_marker(orbit, origin_pci, -acos(cos_nu) - orbit.true_anomaly, "ENTRY %.0f km" % (body.entry_interface_altitude_m / 1000.0), COLOR_WARN)


func _add_marker(orbit: OrbitElements, origin_pci: Vec3d, angle: float, text: String, color: Color) -> void:
	var p := orbit.point_at_angle(fposmod(angle, TAU))
	if p != null:
		overlay.orbit_markers.append({"pos": p.minus(origin_pci).to_vector3(), "text": text, "color": color})


func _update_radar(player: ShipState, target: ShipState) -> void:
	radar.contacts = []
	if target != null:
		var inv := player.orientation.inverse()
		var rel := inv * (target.position - player.position)
		radar.contacts.append({
			"rel_body": rel,
			"rel_vel_body": inv * (target.velocity - player.velocity),
			"range_rate": RelativeMotion.range_rate(player.position, player.velocity, target.position, target.velocity),
			"color": COLOR_TARGET,
		})
		radar.scale_m = RadarMath.nice_scale(rel.length())
	radar.queue_redraw()
