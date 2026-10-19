class_name Main
extends Node3D
## Orbital sandbox entry point. Wires input → simulation → views each frame.
## The WorldSimulation is the source of truth; everything under this node is
## a view of it, rendered around a floating origin at the player ship.

const PLAYER_ID := &"player"
const TARGET_ID := &"target_01"
const EARTH: OrbitalBody = preload("res://data/bodies/earth.tres")
const SHIPYARD_SCENE := "res://scenes/shipyard/shipyard.tscn"
const SHIP_VIEW_SCENE: PackedScene = preload("res://scenes/ships/ship_view.tscn")
## Scenario: prograde equatorial orbit at ISS-like altitude, on the day side.
const START_ALTITUDE_M := 400_000.0
## Real sky date (UTC): sets the Sun, the stars' orientation and Earth's spin.
const SCENARIO_EPOCH_UTC := "2026-10-19T12:00:00"
## Sun's in-plane angle behind the start zenith: ~24 minutes before sunset.
const SUN_ANGLE_FROM_UP_DEG := 15.0
const SUN_ENERGY := 1.4

@onready var camera: ChaseCamera = $ChaseCamera
@onready var hud: Hud = $Hud
@onready var dust: DustField = $DustField
@onready var dust_far: DustField = $DustFieldFar
@onready var sky: PlanetSky = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var stars: Starfield = $Starfield
@onready var projectile_view: ProjectileView = $ProjectileView
@onready var hit_flashes: HitFlashes = $HitFlashes
var gangways := GangwayView.new()

## Design the player flies; set by the shipyard before it switches to this
## scene. Null = the default template. Only used to commission the first
## hangar vessel; after that the profile's vessel is flown.
static var launch_blueprint: ShipBlueprint
## Persistent player state (spare parts, loot, hangar vessel); loaded on
## first use from PlayerProfile.path.
static var profile: PlayerProfile
## The station shows the last debrief when it opens after a sortie.
static var debrief_pending: bool = false

var world: WorldSimulation
var celestial: CelestialFrame
## The target shoots back (toggle with T).
var target_hostile: bool = false
## Boarding party size the player has chosen (tactical overview).
var boarding_party_size: int = BoardingAction.MAX_TEAM
var player_input := PlayerInput.new()
var _views: Dictionary = {}  # StringName -> ShipView
## Compiled designs: {blueprint, grid, stats, config} per ship id.
var _designs: Dictionary = {}
## This sortie's outcome (docked or lost) is already in the profile.
var _sortie_closed := false
## This sortie's record, for the debrief.
var combat_log: CombatLog
## The player's and the target's autonomous craft (Milestone 6).
var player_wing: AirWing
var target_wing: AirWing
## Enemy fighters launch from this mission on, once the target is hostile.
const ENEMY_WING_FROM_MISSION := 3
## A contact arriving after a salvage starts this far out, closing at this
## speed, until it holds ENGAGE_STANDOFF_M.
const ARRIVAL_DISTANCE_M := 30_000.0
const ARRIVAL_SPEED_MPS := 150.0
const ENGAGE_STANDOFF_M := 2500.0
## A hostile contact holds fire this long after the player first detects it.
const ENGAGE_GRACE_S := 5.0
## Aim point distance without a contact (m).
const DEFAULT_AIM_RANGE_M := 2000.0
## Dimensional jump drive: hold [B] this long (s) to jump to Earth Shipyard.
const JUMP_HOLD_S := 5.0
const STATION_NAME := "Earth Shipyard"
var _jump_hold := 0.0
## The current target surrendered to our boarders and has been paid out;
## it leaves once the boarders are home.
var _prize_taken := false
## What the player's sensors know about the target, and the target's about the player.
var track := SensorTrack.new()
var enemy_track := SensorTrack.new()
var _target_arriving := false
var _craft_views: Dictionary = {}  # craft id -> CraftView
var _wing_log_seen := {}  # AirWing -> log_count already shown


static func get_profile() -> PlayerProfile:
	if profile == null:
		profile = PlayerProfile.load_or_new()
	return profile


func _ready() -> void:
	InputBindings.apply_saved()
	gangways.name = "Gangways"
	add_child(gangways)
	celestial = CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso(SCENARIO_EPOCH_UTC), SUN_ANGLE_FROM_UP_DEG)
	stars.build(celestial)
	hud.celestial = celestial
	hud.overview.command.connect(_on_overview_command)
	sky.configure(EARTH)
	_start_scenario()


func _start_scenario() -> void:
	for view in _views.values():
		(view as ShipView).queue_free()
	_views.clear()
	for view in _craft_views.values():
		(view as Node).queue_free()
	_craft_views.clear()
	hud.reset()
	hit_flashes.clear()

	var template := _load_template()
	var p := get_profile()
	hud.profile = p
	var vessel := p.ensure_vessel(launch_blueprint if launch_blueprint != null else template)
	_designs[PLAYER_ID] = _compile(vessel.blueprint, template)

	world = WorldSimulation.new()
	var r0 := EARTH.radius_m + START_ALTITUDE_M
	world.set_central_body(EARTH, Vec3d.new(0, r0, 0), Vec3d.new(0, 0, -EARTH.circular_speed(r0)))
	world.anchor_id = PLAYER_ID
	var player := ShipState.create(PLAYER_ID, "PLAYER", _designs[PLAYER_ID].config)
	var systems := _new_systems(PLAYER_ID)
	if _designs[PLAYER_ID].blueprint == vessel.blueprint:
		# The vessel flies as it was left: damage persists between sorties.
		systems.apply_condition(vessel.condition)
		player.propellant_kg = minf(player.propellant_kg, _intact_tank_capacity(systems))
	player.attach_systems(systems)
	world.add_ship(player)
	player_wing = AirWing.for_ship(player)
	player_wing.target_id = TARGET_ID
	if _designs[PLAYER_ID].blueprint == vessel.blueprint:
		player_wing.apply_state(vessel.wing)
	world.wings.append(player_wing)
	hud.player_wing = player_wing
	_spawn_target()
	_sortie_closed = false
	combat_log = CombatLog.begin(player, world.sim_time)
	if hud.debrief != null:
		hud.debrief.visible = false

	_spawn_view(PLAYER_ID, Color.WHITE)
	_spawn_view(TARGET_ID, Color(1.0, 0.78, 0.72))
	GameLog.info("main", "Orbital sandbox ready: player flies '%s' (%.0f t), %s orbit at %.0f km, fixed dt %.4f s" % [
		_designs[PLAYER_ID].config.display_name, _designs[PLAYER_ID].config.mass_kg / 1000.0,
		EARTH.display_name, START_ALTITUDE_M / 1000.0, world.fixed_dt])


## Next contact. The first of a sortie is already close: 2.5 km ahead and
## off-axis, crossing the bow at ~25 m/s. One arriving after a salvage
## (`arriving`) starts ARRIVAL_DISTANCE_M out and closes; it must be
## detected before it engages.
func _spawn_target(arriving: bool = false) -> void:
	var player := world.get_ship(PLAYER_ID)
	var mission := get_profile().missions_completed + 1
	var template := _load_template()
	_designs[TARGET_ID] = _compile(EnemyFactory.design(mission, template, ConstructionCatalog.default_catalog()), template)
	var class_name_word: String = (_designs[TARGET_ID].blueprint as ShipBlueprint).name.split("-")[0].to_upper()
	var pos := player.position + Vector3(400, 120, -2500)
	var vel := player.velocity + Vector3(-25, 1.5, 6.0)
	var attitude := Quaternion(Vector3.UP, 0.9)
	if arriving:
		var dir := (Basis(Vector3.UP, 1.3 * mission) * Vector3(0.35, 0.1, -1.0)).normalized()
		pos = player.position + dir * ARRIVAL_DISTANCE_M
		vel = player.velocity - dir * ARRIVAL_SPEED_MPS
		attitude = Basis.looking_at(-dir, Vector3.UP).get_rotation_quaternion()
	var target := ShipState.create(TARGET_ID, "TGT-%02d %s" % [mission, class_name_word], _designs[TARGET_ID].config, pos, vel, attitude)
	target.angular_velocity = Vector3.ZERO if arriving else Vector3(0.0, 0.03, 0.01)
	_target_arriving = arriving
	_prize_taken = false
	track = SensorTrack.new()
	enemy_track = SensorTrack.new()
	target.attach_systems(_new_systems(TARGET_ID))
	world.add_ship(target)
	world.set_input(TARGET_ID, ShipControlInput.neutral())
	# Its craft (they launch once it is hostile, from ENEMY_WING_FROM_MISSION).
	if target_wing != null:
		world.wings.erase(target_wing)
		for c in target_wing.crafts:
			if world.has_ship(c.id):
				world.remove_ship(c.id)
	target_wing = AirWing.for_ship(target)
	target_wing.target_id = PLAYER_ID
	world.wings.append(target_wing)
	if player_wing != null:
		player_wing.target_id = TARGET_ID


static func _intact_tank_capacity(systems: ShipSystems) -> float:
	var kg := 0.0
	for e in systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.PROPELLANT_TANK and not e.destroyed():
			kg += e.def.propellant_capacity_kg
	return kg


static func _load_template() -> ShipBlueprint:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	assert(bp != null, "Default template failed to load: %s" % ", ".join(errors))
	return bp


## Validates and compiles a design; a design with errors falls back to `fallback`.
func _compile(bp: ShipBlueprint, fallback: ShipBlueprint) -> Dictionary:
	var catalog := ConstructionCatalog.default_catalog()
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var report := ShipValidator.validate(bp, catalog, grid, stats)
	if report.has_errors():
		if bp == fallback:
			GameLog.error("main", "Template '%s' is invalid:\n%s" % [bp.name, report.summary()])
		else:
			GameLog.warn("main", "Design '%s' has errors; flying the template instead:\n%s" % [bp.name, report.summary()])
			return _compile(fallback, fallback)
	return {"blueprint": bp, "grid": grid, "stats": stats, "config": stats.to_ship_config(bp.name)}


func _new_systems(id: StringName) -> ShipSystems:
	var d: Dictionary = _designs[id]
	return ShipSystems.create(d.blueprint, d.grid, d.stats, d.config)


func _spawn_view(id: StringName, tint: Color) -> void:
	var view: ShipView = SHIP_VIEW_SCENE.instantiate()
	view.ship_id = id
	view.name = "ShipView_%s" % id
	view.blueprint = _designs[id].blueprint
	view.grid = _designs[id].grid
	view.stats = _designs[id].stats
	view.tint = tint
	view.hull_name = get_profile().vessel.name if id == PLAYER_ID and get_profile().vessel != null else world.get_ship(id).display_name
	add_child(view)
	_views[id] = view


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player_input.suppress_fire = true  # the capture click is not a shot
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("restart_scenario"):
		GameLog.info("main", "Scenario restarted")
		close_sortie()
		_start_scenario()
		return
	elif event.is_action_pressed("open_shipyard"):
		# Lost: straight back to the station. Otherwise B is held to charge
		# the jump drive (_update_jump).
		if not world.get_ship(PLAYER_ID).is_active():
			open_shipyard()
		return
	elif event.is_action_pressed("salvage"):
		_on_salvage_pressed()
		return
	elif event.is_action_pressed("field_repair"):
		start_field_repair()
		return
	elif event.is_action_pressed("dock"):
		toggle_dock()
		return
	elif event.is_action_pressed("board"):
		toggle_boarding()
		return
	elif event.is_action_pressed("divert_balance"):
		world.get_ship(PLAYER_ID).systems.balance_power()
		return
	elif event.is_action_pressed("launch_craft"):
		var n := player_wing.launch_all(world)
		if n == 0:
			var why := PackedStringArray()
			for c in player_wing.crafts:
				why.append(player_wing.launch_block_reason(world, c))
			hud.notice("LAUNCH: " + "; ".join(why), world.sim_time)
		return
	elif event.is_action_pressed("recall_craft"):
		player_wing.recall_all()
		return
	elif event.is_action_pressed("divert_sys"):
		world.get_ship(PLAYER_ID).systems.divert(ShipSystems.Channel.SYS)
		return
	elif event.is_action_pressed("divert_eng"):
		world.get_ship(PLAYER_ID).systems.divert(ShipSystems.Channel.ENG)
		return
	elif event.is_action_pressed("divert_wep"):
		world.get_ship(PLAYER_ID).systems.divert(ShipSystems.Channel.WEP)
		return
	elif event.is_action_pressed("toggle_target_ai"):
		set_target_hostile(not target_hostile)
		return
	elif event.is_action_pressed("tactical_overview"):
		hud.overview.toggle()
		if hud.overview.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# Opened on what the top alert is about.
			if hud.alert_subject != "":
				hud.overview.select_subject(hud.alert_subject)
		return
	elif event.is_action_pressed("toggle_orbit_panel"):
		hud.toggle_orbit_panel()
		return
	elif event.is_action_pressed("toggle_details"):
		hud.toggle_details()
		return
	elif event.is_action_pressed("toggle_help"):
		hud.toggle_help()
		return
	elif event.is_action_pressed("toggle_controls"):
		hud.controls.toggle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	player_input.handle_event(event)


func set_target_hostile(on: bool, why: String = "") -> void:
	target_hostile = on
	hud.target_hostile = on
	GameLog.info("main", "Target %s%s" % ["HOSTILE — guns free" if on else "passive", " (%s)" % why if why != "" else ""])
	if why != "":
		hud.notice("%s turns HOSTILE — %s" % [world.get_ship(TARGET_ID).display_name, why], world.sim_time)
		combat_log.record(world.sim_time, "contact", "%s turned hostile: %s" % [world.get_ship(TARGET_ID).display_name, why])
	if not on:
		world.set_input(TARGET_ID, ShipControlInput.neutral())


## Turrets train on the point under the aim cursor, at the target's range
## (render space is centred on the player, so it is already an offset).
func _aim(input: ShipControlInput, player: ShipState, target: ShipState) -> void:
	var screen := get_viewport().get_visible_rect().size * 0.5 + player_input.aim_offset
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var range_m := DEFAULT_AIM_RANGE_M
	if target.is_active() and track.detected:
		var pos := target.position if track.in_contact else track.estimated_position(player, world.sim_time)
		range_m = clampf((pos - player.position - origin).length(), 200.0, 30_000.0)
	player_input.aim_range_m = range_m
	input.has_aim = true
	input.aim_offset = origin + dir * range_m


## Zooming in: swing the camera to look at the aim point and put the cursor
## in the middle, so the zoomed view is centred on what was being aimed at.
func _center_view_on_aim(player: ShipState) -> void:
	var screen := get_viewport().get_visible_rect().size * 0.5 + player_input.aim_offset
	var aim := camera.project_ray_origin(screen) + camera.project_ray_normal(screen) * player_input.aim_range_m
	var d := (player.orientation.inverse() * aim).normalized()
	player_input.camera_orbit = Vector2(atan2(-d.x, -d.z), clampf(asin(clampf(d.y, -1.0, 1.0)), -PlayerInput.ORBIT_PITCH_LIMIT, PlayerInput.ORBIT_PITCH_LIMIT))
	player_input.aim_offset = Vector2.ZERO


## Put the aim cursor over a point (offset from the player, world axes).
func aim_cursor_at(offset: Vector3) -> void:
	if player_input.zoomed:
		# Zoomed the view itself turns: aim the camera's centre at it.
		var d := (world.get_ship(PLAYER_ID).orientation.inverse() * offset).normalized()
		player_input.camera_orbit = Vector2(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))
		player_input.aim_offset = Vector2.ZERO
		return
	if camera.is_position_behind(offset):
		return
	player_input.aim_offset = camera.unproject_position(offset) - get_viewport().get_visible_rect().size * 0.5


## Cursor on the fire-control lead point for the target (scripted aim for
## the smoke tests and screen captures).
func aim_cursor_at_lead() -> void:
	var player := world.get_ship(PLAYER_ID)
	var target := world.get_ship(TARGET_ID)
	if player.config.cannon == null or not target.is_active():
		return
	var muzzle := player.position + player.orientation * player.config.primary_muzzle()
	var rel := target.position + target.orientation * target.config.hit_box_center - muzzle
	var rel_v := target.velocity - player.velocity
	var t := FireControl.intercept_time(rel, rel_v, player.config.cannon.muzzle_velocity_mps)
	if t > 0.0:
		aim_cursor_at(muzzle - player.position + FireControl.lead_point(rel, rel_v, t))


## Leave flight for the shipyard (dock), taking the design being flown.
func open_shipyard() -> void:
	close_sortie()
	launch_blueprint = _designs[PLAYER_ID].blueprint
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(SHIPYARD_SCENE)


func _notification(what: int) -> void:
	# Quitting mid-sortie docks the ship as it is: no repairs by quitting.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close_sortie()


## Record how the sortie ended and save: docked with the ship's damage, or
## lost (rarer parts aboard are written off; the design survives).
func close_sortie() -> void:
	if _sortie_closed or world == null:
		return
	_sortie_closed = true
	var p := get_profile()
	var player := world.get_ship(PLAYER_ID)
	var catalog := ConstructionCatalog.default_catalog()
	var lines := PackedStringArray()
	# Craft still out are left behind (lost); the rest keep their state.
	for c in player_wing.crafts:
		if c.status == AirWing.Status.FLYING:
			lines.append("%s left behind — lost" % c.label)
	p.vessel.wing = player_wing.state() if _designs[PLAYER_ID].blueprint == p.vessel.blueprint else {}
	# Boarders still on the other ship are left behind.
	for b in world.boardings:
		if b.link.attacker_id == PLAYER_ID and b.phase != BoardingAction.Phase.RETURNED and b.phase != BoardingAction.Phase.ABORTED:
			for m in b.team:
				if m.location < 0 and m.state != CrewRoster.State.DEAD:
					m.state = CrewRoster.State.DEAD
					lines.append("Boarder %s (%s) left behind" % [m.id, CrewRoster.ROLE_NAMES[m.role]])
	if not player.is_active():
		lines = p.lose_vessel(catalog)
		GameLog.info("main", "Vessel lost — the hold is gone; the station rebuilds the same design")
	elif _designs[PLAYER_ID].blueprint == p.vessel.blueprint:
		lines.append_array(p.dock(player.systems.condition(), catalog))
		GameLog.info("main", "Docked %s after sortie %d%s" % [p.vessel.name, p.vessel.sorties, " (damaged)" if p.vessel.is_damaged() else ""])
	for line in lines:
		GameLog.info("main", line)
	if combat_log != null:
		var outcome := "vessel lost" if not player.is_active() else "jumped home to %s" % STATION_NAME
		combat_log.finish(player, outcome, world.sim_time, lines)
		p.last_debrief = combat_log.to_dict()
		var path := combat_log.save()
		if path != "":
			GameLog.info("main", "Debrief saved to %s" % path)
		debrief_pending = true
	_save_profile()


func _save_profile() -> void:
	var err := get_profile().save()
	if err != OK:
		GameLog.warn("main", "Could not save the profile to %s (%s)" % [PlayerProfile.path, error_string(err)])


func _on_salvage_pressed() -> void:
	if hud.loot.visible:
		hud.loot.close()
		return
	var why := Salvage.block_reason(world.get_ship(PLAYER_ID), world.get_ship(TARGET_ID))
	if why != "":
		hud.notice("SALVAGE BEACON: " + why, world.sim_time)
		return
	drop_beacon()


## G: drop a salvage beacon on the disabled wreck. Earth Shipyard's tug
## brings it in: half its scrap value and the bounty in credits now; its
## crates are opened at the beacon's odds and banked at the station. Returns
## the crates (a Drop each, null for an empty one).
func drop_beacon() -> Array:
	var target := world.get_ship(TARGET_ID)
	var p := get_profile()
	var catalog := ConstructionCatalog.default_catalog()
	var intact := target.systems.intact_fraction()
	var scrap := roundi(Salvage.scrap_value(target.systems) * Salvage.BEACON_SCRAP_RATE)
	var bounty := Salvage.bounty_for(target.systems)
	var crates := p.open_crates(Salvage.pulls_for(target.systems), Salvage.BEACON_LOOT_CHANCE, catalog)
	var stripped := _stripped_part(target)
	if stripped != null:
		crates.push_front(stripped)
	for d in crates:
		if d != null:
			p.grant(d)
	p.credits += scrap + bounty
	var summary := "Salvage beacon on %s (%d%% intact): %d cr scrap (%d%%) + %d cr bounty; %d crates banked at %s" % [
		target.display_name, roundi(intact * 100.0), scrap, roundi(Salvage.BEACON_SCRAP_RATE * 100.0), bounty, crates.size(), STATION_NAME]
	_record_payout(target, summary, crates, "banked")
	hud.loot.show_rewards("SALVAGE BEACON — %s" % target.display_name, PackedStringArray([
		"Wreck %d%% intact · the station's tug brings it in" % roundi(intact * 100.0),
		"+%d cr scrap (%d%% of %d) · +%d cr bounty" % [scrap, roundi(Salvage.BEACON_SCRAP_RATE * 100.0), Salvage.scrap_value(target.systems), bounty],
		"%d crate%s · %d%% chance of loot each · found loot is banked at %s" % [crates.size(), "" if crates.size() == 1 else "s",
			roundi(Salvage.BEACON_LOOT_CHANCE * 100.0), STATION_NAME],
	]), crates, p)
	_next_contact()
	return crates


## Our boarders took the target's bridge: 80 % of its scrap value and double
## bounty in credits; its stores and crates (better odds, bonus crates) go
## into our cargo hold. The boarders withdraw on their own; once they are
## home the prize crew takes it to Earth Shipyard and the next contact comes.
func take_prize() -> Array:
	_prize_taken = true
	var target := world.get_ship(TARGET_ID)
	var p := get_profile()
	var catalog := ConstructionCatalog.default_catalog()
	var scrap := roundi(Salvage.scrap_value(target.systems) * Salvage.TAKEOVER_SCRAP_RATE)
	var bounty := Salvage.bounty_for(target.systems)
	var parts := Salvage.spare_parts_for(target.systems)
	p.vessel.cargo["spare_parts"] = int(p.vessel.cargo.get("spare_parts", 0)) + parts
	var crates := p.open_crates(Salvage.pulls_for(target.systems), Salvage.TAKEOVER_LOOT_CHANCE, catalog)
	var stripped := _stripped_part(target)
	if stripped != null:
		crates.push_front(stripped)
	for d in crates:
		if d != null:
			p.stow(d)
	p.credits += scrap + bounty
	var summary := "Prize %s taken: %d cr scrap (%d%%) + %d cr bounty; %d spare parts and %d crates into the hold" % [
		target.display_name, scrap, roundi(Salvage.TAKEOVER_SCRAP_RATE * 100.0), bounty, parts, crates.size()]
	_record_payout(target, summary, crates, "in the hold")
	var lines := PackedStringArray([
		"Bridge taken · boarders withdrawing · prize crew to %s" % STATION_NAME,
		"+%d cr scrap (%d%% of %d) · +%d cr bounty (×2 captured)" % [scrap, roundi(Salvage.TAKEOVER_SCRAP_RATE * 100.0),
			Salvage.scrap_value(target.systems), bounty],
		"+%d spare parts from its stores · %d crates · %d%% chance of loot each — into the cargo hold" % [parts, crates.size(),
			roundi(Salvage.TAKEOVER_LOOT_CHANCE * 100.0)],
	])
	var over := cargo_over_m3()
	if over > 0.0:
		lines.append("[color=#f5c842]▲ HOLD OVER CAPACITY by %.1f m³ — vent excess [Tab › CARGO][/color]" % over)
	hud.loot.show_rewards("PRIZE TAKEN — %s" % target.display_name, lines, crates, p)
	return crates


## The best intact rarer part fitted to the wreck, stripped as a unit (or null).
func _stripped_part(target: ShipState) -> LootRoller.Drop:
	var fitted := EnemyFactory.recoverable_part(target.systems)
	if fitted == null:
		return null
	var part := LootRoller.Drop.new()
	part.kind = &"equipment"
	part.def_id = fitted.def.id
	part.rarity = fitted.def.rarity
	part.display_name = "%s (stripped from the wreck)" % fitted.def.display_name
	return part


func _record_payout(target: ShipState, summary: String, crates: Array, where: String) -> void:
	var p := get_profile()
	p.missions_completed += 1
	p.vessel.salvaged += 1
	p.vessel.record(summary)
	if combat_log != null:
		combat_log.record(world.sim_time, "salvage", summary)
		for d in crates:
			if d != null:
				combat_log.loot.append("%s: %s — %s" % [Rarity.name_of(d.rarity), d.describe(), where])
	_save_profile()
	GameLog.info("main", summary)


## The target leaves (towed or crewed off); the next contact arrives.
func _next_contact() -> void:
	world.remove_ship(TARGET_ID)
	hud.reset()
	_spawn_target(true)
	# New contact, new hull (and its own name on it).
	(_views[TARGET_ID] as Node).queue_free()
	_spawn_view(TARGET_ID, Color(1.0, 0.78, 0.72))


## Cargo hold volume beyond its capacity (m³), 0 if it fits.
func cargo_over_m3() -> float:
	var sys := world.get_ship(PLAYER_ID).systems
	var capacity := sys.stats.cargo_m3 if sys != null else 0.0
	return maxf(get_profile().vessel.cargo_volume_m3(ConstructionCatalog.default_catalog()) - capacity, 0.0)


## A hostile contact we can see is still fighting: no jumping out.
func in_combat() -> bool:
	var target := world.get_ship(TARGET_ID)
	return target_hostile and target.is_active() and target.systems != null and not target.systems.is_disabled() and track.in_contact


## Why the jump drive waits at full charge: craft out, boarders across,
## cargo not secured. Empty = ready.
func jump_waiting() -> PackedStringArray:
	var out := PackedStringArray()
	var out_craft := player_wing.flying().map(func(c: AirWing.Craft) -> String: return c.label)
	if not out_craft.is_empty():
		out.append("recall craft %s [K]" % ", ".join(out_craft))
	for b in world.boardings:
		if b.link.attacker_id == PLAYER_ID and not b.finished() and b.team.any(func(m: CrewRoster.Member) -> bool: return m.location < 0 and m.state != CrewRoster.State.DEAD):
			out.append("withdraw the boarding party [N]")
	if cargo_over_m3() > 0.0:
		out.append("vent excess cargo [Tab › CARGO]")
	return out


## Hold [B]: the dimensional jump drive charges for JUMP_HOLD_S and takes the
## ship home to Earth Shipyard. Not while a hostile is engaging; at full
## charge it waits for craft and boarders to come home (amber alerts).
## Returns true when the jump happened (the scene is changing).
func _update_jump(player: ShipState, delta: float) -> bool:
	var state := {}
	if Input.is_action_pressed("open_shipyard") and player.is_active() and not hud.controls.visible:
		if in_combat():
			_jump_hold = 0.0
			state = {"blocked": "hostile contact engaged — disable it or break sensor contact"}
		else:
			_jump_hold = minf(_jump_hold + delta, JUMP_HOLD_S)
			var waiting := jump_waiting()
			state = {"progress": _jump_hold / JUMP_HOLD_S, "left_s": JUMP_HOLD_S - _jump_hold, "waiting": waiting}
			if _jump_hold >= JUMP_HOLD_S and waiting.is_empty():
				hud.jump_state = {}
				combat_log.record(world.sim_time, "jump", "Dimensional jump to %s" % STATION_NAME)
				open_shipyard()
				return true
	else:
		_jump_hold = 0.0
	hud.jump_state = state
	return false


func _on_overview_command(name: StringName, arg: Variant) -> void:
	var sys := world.get_ship(PLAYER_ID).systems
	match name:
		&"divert":
			sys.divert(arg)
		&"balance":
			sys.balance_power()
		&"cover":
			var why := sys.cover_role(arg)
			hud.notice("CREW: " + why if why != "" else "Crew: sending a general crew member to cover %s" % CrewRoster.ROLE_NAMES[arg], world.sim_time)
		&"party":
			boarding_party_size = clampi(boarding_party_size + int(arg), 1, BoardingAction.MAX_TEAM)
			hud.boarding_party_size = boarding_party_size
		&"repair_pick":
			sys.preferred_repair_id = str(arg)
		&"repair":
			start_field_repair()
		&"power_toggle":
			sys.set_switched_off(str(arg), not sys.switched_off.has(str(arg)))
		&"isolate":
			for i in sys.blueprint.rooms.size():
				if sys.blueprint.rooms[i].id == str(arg):
					sys.set_isolated(i, not sys.isolated_rooms.has(i))
		&"craft_launch":
			var why := player_wing.launch(world, player_wing.by_id(arg))
			if why != "":
				hud.notice("LAUNCH: " + why, world.sim_time)
		&"craft_recall":
			player_wing.by_id(arg).directive = CraftAI.Directive.RETURN
		&"craft_directive":
			player_wing.by_id(arg[0]).directive = arg[1]
		&"craft_risk":
			player_wing.by_id(arg[0]).risk = arg[1]
		&"craft_priority":
			player_wing.by_id(arg[0]).priority = arg[1]
		&"vent":
			var went := get_profile().vessel.vent(str(arg[0]), str(arg[1]))
			if went != "":
				hud.notice("Cargo vented: %s" % went, world.sim_time)
				combat_log.record(world.sim_time, "cargo", "Vented %s" % went)
		&"vent_excess":
			var capacity := sys.stats.cargo_m3
			var went := get_profile().vessel.vent_excess(capacity, ConstructionCatalog.default_catalog())
			if not went.is_empty():
				hud.notice("Cargo vented: %s" % ", ".join(went), world.sim_time)
				combat_log.record(world.sim_time, "cargo", "Vented %s" % ", ".join(went))


## Sensor tracks both ways; announce a new contact.
func _update_tracks(player: ShipState, target: ShipState, delta: float) -> void:
	var dt := delta if world == null else minf(delta, 0.25)
	if track.update(player, target, world.sim_time, dt):
		var line := "CONTACT — %s detected at %.1f km" % [target.display_name, player.position.distance_to(target.position) / 1000.0]
		hud.notice(line, world.sim_time)
		combat_log.record(world.sim_time, "sensors", line)
	if track.just_scanned and target.systems != null:
		var est := Salvage.scan_estimate(target.systems)
		var line := "SCAN COMPLETE — %s: ~%d spare parts, ~%d crates aboard · bounty ~%d cr" % [target.display_name,
			roundi(est.parts * track.scan_error), roundi(est.crates * track.scan_error), roundi(est.bounty * track.scan_error)]
		hud.notice(line, world.sim_time)
		combat_log.record(world.sim_time, "sensors", line)
	enemy_track.update(target, player, world.sim_time, dt)


## Each wing's hostiles are the other wing's craft in flight.
func _link_wings() -> void:
	var ours: Array[StringName] = []
	var theirs: Array[StringName] = []
	for c in player_wing.flying():
		ours.append(c.id)
	for c in target_wing.flying():
		theirs.append(c.id)
	player_wing.hostile_ids = theirs
	target_wing.hostile_ids = ours


func _sync_craft_views(alpha: float, render_origin: Vector3) -> void:
	var alive := {}
	for wing in [player_wing, target_wing]:
		var carrier_view: ShipView = _views.get(wing.carrier_id)
		if carrier_view != null:
			for c in wing.crafts:
				carrier_view.show_docked_craft(c.rack_id, c.status == AirWing.Status.DOCKED)
		for c in wing.flying():
			var ship := world.get_ship(c.id)
			if ship == null:
				continue
			alive[c.id] = true
			var view: CraftView = _craft_views.get(c.id)
			if view == null:
				view = CraftView.new()
				view.craft_id = c.id
				view.config = c.config
				view.callsign = c.label
				view.hostile = wing == target_wing
				add_child(view)
				_craft_views[c.id] = view
			view.sync_from(ship, alpha, render_origin)
	for id in _craft_views.keys():
		if not alive.has(id):
			(_craft_views[id] as Node).queue_free()
			_craft_views.erase(id)


## Docking camera out of our collar while a target is in boarding range and
## no gangway is sealed yet.
func _update_docking_cam(player: ShipState, target: ShipState, alpha: float, render_origin: Vector3) -> void:
	var link := world.link_for(PLAYER_ID)
	var mine := Docking.collars(player.systems)
	if not target.is_active() or mine.is_empty() or (link != null and link.sealed()) 			or player.position.distance_to(target.position) > DockingCam.SHOW_RANGE_M:
		hud.docking_cam.visible = false
		return
	var found := Docking.best(player, target)
	var port: Docking.Port = found.a_port if not found.is_empty() else mine[0]
	var q := player.interpolated_orientation(alpha)
	var from := player.interpolated_position(alpha) + q * port.position_body - render_origin
	hud.docking_cam.show_view(from, q * port.normal_body, q * Vector3.UP, found.get("assessment", {}))


## V: extend a gangway to the target, or release the one we have.
func toggle_dock() -> void:
	var link := world.link_for(PLAYER_ID)
	if link != null:
		var b := world.boarding_for(link)
		link.release()
		hud.notice("Gangway released%s" % (" — the boarding party is cut off!" if b != null and not b.finished() and b.room >= 0 else ""), world.sim_time)
		return
	var found := world.dock(PLAYER_ID, TARGET_ID)
	if found.is_empty():
		hud.notice("DOCK: no working docking collar opening into a room", world.sim_time)
	elif not found.has("link"):
		hud.notice("DOCK: " + ", ".join(found.assessment.problems), world.sim_time)


## N: send a boarding party over a sealed gangway, or order it home.
func toggle_boarding() -> void:
	var link := world.link_for(PLAYER_ID)
	var b := world.boarding_for(link) if link != null else null
	if b != null and not b.finished():
		b.withdraw()
		return
	if link == null or not link.sealed():
		hud.notice("BOARD: needs a sealed gangway first [V]", world.sim_time)
		return
	if world.start_boarding(link, boarding_party_size) == null:
		hud.notice("BOARD: no fit security or general crew can reach the collar", world.sim_time)


## Damage control: the crew patch the next damaged system in a working
## workshop, for spare parts. Returns false (with a HUD notice) if blocked.
func start_field_repair() -> bool:
	var sys := world.get_ship(PLAYER_ID).systems
	var why := sys.field_repair_block_reason()
	if why != "":
		hud.notice("DAMAGE CONTROL: " + why, world.sim_time)
		return false
	var e := sys.field_repair_target()
	var cost := maxi(ServiceYard.damaged_cost(ServiceYard.equipment_cost(e.def), sys.field_repair_hp(e) / e.max_hp), 1)
	var p := get_profile()
	if cost > p.spare_parts:
		hud.notice("DAMAGE CONTROL: patching %s needs %d spare parts, you have %d" % [e.id, cost, p.spare_parts], world.sim_time)
		return false
	p.spare_parts -= cost
	sys.start_field_repair()
	hud.notice("Damage control: patching %s %s (%d parts)" % [e.def.display_name, e.id, cost], world.sim_time)
	return true


func _process(delta: float) -> void:
	var player := world.get_ship(PLAYER_ID)
	var target := world.get_ship(TARGET_ID)
	var target_id := TARGET_ID if target.is_active() else &""
	player_input.aim_limit = get_viewport().get_visible_rect().size * 0.5 - Vector2(24, 24)
	var command := player_input.build_input(delta, target_id, hud.docking_cam.visible)
	_aim(command, player, target)
	world.set_input(PLAYER_ID, command)
	if _update_jump(player, delta):
		return
	_update_tracks(player, target, delta)
	# A takeover pays out at once; the prize leaves once the boarders are home.
	if target.is_active() and target.systems != null and target.systems.captured and not _prize_taken:
		take_prize()
	elif _prize_taken and target.is_active():
		var home := true
		for b in world.boardings:
			if b.link.target_id == TARGET_ID and not b.finished():
				home = false
		if home:
			var link := world.link_for(PLAYER_ID)
			if link != null:
				link.release()
			hud.notice("Prize crew takes %s to %s" % [target.display_name, STATION_NAME], world.sim_time)
			_next_contact()
			target = world.get_ship(TARGET_ID)
	var engaging := target_hostile and target.is_active() and track.detected \
		and world.sim_time - track.detected_time >= ENGAGE_GRACE_S and enemy_track.in_contact
	if target.is_active() and target.systems != null and target.systems.captured:
		world.set_input(TARGET_ID, ShipControlInput.neutral())
	elif world.link_for(TARGET_ID) != null and GunneryAI.can_break_contact(target):
		world.set_input(TARGET_ID, GunneryAI.break_contact(target, player))
	elif _target_arriving and target.is_active() and not target.systems.is_disabled():
		# Inbound: close to the standoff, nose on the player; guns only once engaging.
		var input := GunneryAI.command(target, player) if engaging else ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
		if not engaging:
			CraftAI.point(target, player.position - target.position, input)
		var away := (target.position - player.position).normalized()
		CraftAI.steer(target, player.position + away * ENGAGE_STANDOFF_M, player.velocity, input, ARRIVAL_SPEED_MPS)
		world.set_input(TARGET_ID, input)
		if target.position.distance_to(player.position) < ENGAGE_STANDOFF_M + 150.0:
			_target_arriving = false
	elif engaging:
		world.set_input(TARGET_ID, GunneryAI.command(target, player))
		if get_profile().missions_completed + 1 >= ENEMY_WING_FROM_MISSION and not target.systems.is_disabled():
			for c in target_wing.crafts:
				if c.status == AirWing.Status.DOCKED and not c.is_drone() and c.service_left_s <= 0.0 and c.hull_fraction > 0.0:
					target_wing.launch(world, c)
	_link_wings()
	# Freeze the moment the player is lost (Backspace restarts) and while the
	# controls panel is open.
	if not player.is_active() and not _sortie_closed:
		close_sortie()
		var p := get_profile()
		hud.debrief.show_debrief(p.last_debrief, "[BACKSPACE] respawn the %s here  ·  [B] back to %s" % [p.vessel.name, STATION_NAME])
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var running := player.is_active() and not hud.controls.visible
	var alpha := world.advance(delta) if running else 1.0
	for line in world.take_link_events():
		hud.notice(line, world.sim_time)
		GameLog.info("boarding", line)
		combat_log.record(world.sim_time, "boarding", line)
	var hits := world.take_hit_events()
	for ev in hits:
		combat_log.note_hit(ev, PLAYER_ID, world.sim_time, world)
		# A passive contact fired upon by us (or our craft) fights back.
		if ev.target_id == TARGET_ID and not target_hostile and (ev.shooter_id == PLAYER_ID or player_wing.by_id(ev.shooter_id) != null):
			set_target_hostile(true, "fired upon")
	for id in world.ship_ids():
		var s := world.get_ship(id).systems
		if s == null:
			continue
		for blast in s.take_explosions():
			hit_flashes.add_explosion(id, blast.pos_body, blast.radius)
			# The camera feels it: hard on our own ship, less with distance.
			var dist := world.get_ship(id).position.distance_to(player.position)
			camera.shake(2.5 * clampf(1.0 - dist / 800.0, 0.0, 1.0))
			if id == PLAYER_ID:
				combat_log.explosions += 1
			combat_log.record(world.sim_time, "explosion", "%s: %s" % [world.get_ship(id).display_name, "; ".join(blast.lines)])
			hud.notice("%s: %s" % [world.get_ship(id).display_name, blast.lines[0]], world.sim_time)
			GameLog.info("main", "%s: %s" % [world.get_ship(id).display_name, "; ".join(blast.lines)])
	hud.note_hits(hits, PLAYER_ID, world.sim_time)
	for wing in [player_wing, target_wing]:
		var seen: int = _wing_log_seen.get(wing, 0)
		var fresh := mini(wing.log_count - seen, wing.log.size())
		var who := "Wing" if wing == player_wing else "Enemy wing"
		if fresh > 0:
			for line in wing.log.slice(wing.log.size() - fresh):
				hud.notice("%s: %s" % [who, line], world.sim_time)
				combat_log.record(world.sim_time, "wing", "%s: %s" % [who, line])
		_wing_log_seen[wing] = wing.log_count
	for ev in hits:
		hit_flashes.add(ev)
		var struck_view: ShipView = _views.get(ev.target_id)
		if struck_view != null and ev.report != null and ev.report.penetrated and not ev.report.path_body.is_empty():
			struck_view.add_hole(ev.report.path_body[0], ev.report.entry_normal_body, false)
			if ev.report.exit_pen_mm > 0.0:
				struck_view.add_hole(ev.report.exit_point_body, ev.report.exit_normal_body, true)
		if (ev.shooter_id == PLAYER_ID or player_wing.by_id(ev.shooter_id) != null) and ev.report != null and _designs.has(ev.target_id):
			var struck := world.get_ship(ev.target_id)
			hud.hit_cam.show_hit(ev, _designs[ev.target_id], struck.systems, struck.display_name)

	var render_origin := player.interpolated_position(alpha)
	_sync_craft_views(alpha, render_origin)
	for id: StringName in _views:
		var ship := world.get_ship(id)
		var view: ShipView = _views[id]
		view.visible = ship.is_active()
		view.sync_from(ship, alpha, render_origin)

	if player_input.zoom_changed:
		player_input.zoom_changed = false
		if player_input.zoomed:
			_center_view_on_aim(player)
	camera.zoomed = player_input.zoomed and not hud.overview.visible
	camera.orbit = player_input.camera_orbit
	camera.follow(_views[PLAYER_ID], delta)
	_update_docking_cam(player, target, alpha, render_origin)
	var link := world.link_for(PLAYER_ID)
	var boarding := world.boarding_for(link) if link != null else null
	if boarding != null and not hud.hit_cam.showing_boarding():
		hud.hit_cam.show_boarding(boarding, _designs[TARGET_ID], target.systems, target.display_name)
	var continuous := world.continuous_position(render_origin)
	dust.update_origin(continuous)
	dust_far.update_origin(continuous)
	var planet_center := Vec3d.new().minus(world.frame.interpolated_origin(alpha).plus_v3(render_origin)).to_vector3()
	_update_sun(player)
	sky.update_view(planet_center, camera, celestial, world.sim_time)
	stars.update_view(camera, planet_center, EARTH)
	projectile_view.sync(world.projectiles(), alpha, render_origin, player.velocity, camera)
	hit_flashes.update(world, alpha, render_origin, delta)
	gangways.sync(world, alpha, render_origin)
	hud.track = track
	hud.update_display(world, PLAYER_ID, TARGET_ID, alpha, render_origin, camera, player_input)


## Real Sun direction for the scenario date; dark while the player is in
## Earth's shadow (ships and the planet's night side agree).
func _update_sun(player: ShipState) -> void:
	var dir := celestial.sun_direction_pci(world.sim_time)
	sun.look_at(-dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	sun.light_energy = SUN_ENERGY * CelestialFrame.sunlight_fraction(world.pci_position(player.position), dir, EARTH.radius_m)
