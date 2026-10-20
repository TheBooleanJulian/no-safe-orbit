class_name Main
extends Node3D
## Orbital sandbox entry point. Wires input → simulation → views each frame.
## The WorldSimulation is the source of truth; everything under this node is
## a view of it, rendered around a floating origin at the player ship.

const PLAYER_ID := &"player"
## The lead contact's slot id (the encounter's ships are target_01,
## target_02, …; a slot is reused once its ship is retired as a wreck).
const TARGET_ID := &"target_01"
const SHIPYARD_SCENE := "res://scenes/shipyard/shipyard.tscn"
const SHIP_VIEW_SCENE: PackedScene = preload("res://scenes/ships/ship_view.tscn")
## Where this sortie flies (the profile's location, picked on the shipyard
## map): its body, start orbit (prograde, equatorial, on the day side) and
## station.
var location: Location
## Real sky date (UTC): sets the Sun, the stars' orientation and the body's spin.
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
## Moonlight (earthlight at the Moon) on ships: from the other body in the
## sky, by its phase (PlanetSky.sky_body_light); not drawn in the sky.
var sky_light: DirectionalLight3D
## Flares in flight (Milestone 11).
var decoy_view: DecoyView
@onready var stars: Starfield = $Starfield
@onready var projectile_view: ProjectileView = $ProjectileView
@onready var hit_flashes: HitFlashes = $HitFlashes
var gangways := GangwayView.new()
var audio := ShipAudio.new()
var _rounds_heard := 0

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
## Every enemy ship in the current encounter, and the selected one (U).
var encounter := Encounter.new()
## The selected contact's state under the names the single-target code and
## the tests use: hostility, our track of it, inbound, its air wing.
var target_hostile: bool:
	get:
		var c := encounter.selected_contact()
		return c != null and c.hostile
var track: SensorTrack:
	get:
		var c := encounter.selected_contact()
		return c.track if c != null else _no_track
var _target_arriving: bool:
	get:
		var c := encounter.selected_contact()
		return c != null and c.arriving
	set(value):
		var c := encounter.selected_contact()
		if c != null:
			c.arriving = value
var target_wing: AirWing:
	get:
		var c := encounter.selected_contact()
		return c.wing if c != null else null
var _no_track := SensorTrack.new()
## When the player's automation may fire its next salvo (ShipPolicy).
var _auto_salvo_at := 0.0
## A contact has been beaten this sortie (for the tutorial).
var _beaten_any := false
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
## The player's autonomous craft (Milestone 6); each contact has its own wing.
var player_wing: AirWing
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
## Dimensional jump drive: hold [B] this long (s) to jump to the location's station.
const JUMP_HOLD_S := 5.0
## The jump drive is blocked while a hostile has fired on us this recently.
const UNDER_FIRE_S := 10.0
## When a hostile (ship or craft) last fired, and the rounds counted so far.
var _last_enemy_fire := -INF
var _enemy_rounds_seen := {}
## A beaten enemy that runs this far is gone: no payout, the next contact comes.
const ESCAPE_RANGE_M := 40_000.0
## Enemies try to board a disabled player from this mission on.
const ENEMY_BOARD_FROM_MISSION := 2
## After we cut its gangway the enemy waits this long before trying again (s).
const ENEMY_REBOARD_DELAY_S := 20.0
## How our crew defends against boarders (chosen in Tab → CREW).
var player_defence: int = BoardingAction.Defence.HOLD_BRIDGE
var _jump_hold := 0.0
## SEQUENCE missile mode: which warhead the next press of M fires.
var _sequence_index := 0
var _craft_views: Dictionary = {}  # craft id -> CraftView
var _missile_views: Dictionary = {}  # missile id -> MissileView
## The salvo M started, still firing (null when done).
var salvo: MissileSalvo
## Beaten contacts left drifting (ids, oldest first) and their wings; the
## oldest goes once there are more than MAX_WRECKS.
const MAX_WRECKS := 4
const WRECK_DRIFT_MPS := 4.0
var _wrecks: Array[StringName] = []
var _derelict_wings: Array[AirWing] = []
var _wreck_count := 0
## An enemy boarding party is at most this big (ours: BoardingAction.MAX_TEAM).
const ENEMY_BOARDING_TEAM := 8
## Where the encounter's ships start, relative to the player (the first of
## a sortie; arrivals come from ARRIVAL_DISTANCE_M out).
const CONTACT_OFFSETS := [Vector3(400, 120, -2500), Vector3(-1500, -250, -3800), Vector3(2300, 450, -4400)]
## The campaign's current goal and the guided first sortie (Milestone 8).
var mission: MissionChain
var tutorial: Tutorial
## The escort mission's courier (a craft-like ship of ours, unarmed).
const COURIER_ID := &"courier"
## A contact has been salvaged or taken this sortie (for the tutorial).
var _salvaged := false
var _wing_log_seen := {}  # AirWing -> log_count already shown


static func get_profile() -> PlayerProfile:
	if profile == null:
		# `-- --profile=user://x.json`: play on another profile (the checks
		# boot the game this way, never touching the player's own save).
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--profile="):
				PlayerProfile.path = arg.trim_prefix("--profile=")
		profile = PlayerProfile.load_or_new()
	return profile


func _ready() -> void:
	GameLog.hold(true)
	InputBindings.apply_saved()
	gangways.name = "Gangways"
	add_child(gangways)
	audio.name = "Audio"
	add_child(audio)
	location = Location.by_id(get_profile().location)
	celestial = CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso(SCENARIO_EPOCH_UTC), SUN_ANGLE_FROM_UP_DEG, location.body)
	stars.build(celestial)
	hud.celestial = celestial
	hud.overview.command.connect(_on_overview_command)
	hud.station_name = location.station_name
	decoy_view = DecoyView.new()
	decoy_view.name = "DecoyView"
	add_child(decoy_view)
	sky_light = DirectionalLight3D.new()
	sky_light.name = "SkyBodyLight"
	sky_light.light_color = PlanetSky.NIGHT_LIGHT_COLOR
	sky_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sky_light.light_energy = 0.0
	add_child(sky_light)
	sky.configure(location.body, location.sky_body)
	_start_scenario()


func _start_scenario() -> void:
	for view in _views.values():
		(view as ShipView).queue_free()
	_views.clear()
	for view in _craft_views.values():
		(view as Node).queue_free()
	_craft_views.clear()
	for view in _missile_views.values():
		(view as Node).queue_free()
	_missile_views.clear()
	_wrecks.clear()
	_derelict_wings.clear()
	encounter = Encounter.new()
	salvo = null
	_beaten_any = false
	hud.reset()
	hit_flashes.clear()

	var template := _load_template()
	var p := get_profile()
	hud.profile = p
	var vessel := p.ensure_vessel(launch_blueprint if launch_blueprint != null else template)
	vessel.ensure_crew(ConstructionCatalog.default_catalog())
	_designs[PLAYER_ID] = _compile(vessel.blueprint, template)

	world = WorldSimulation.new()
	var body := location.body
	var r0 := location.start_radius_m()
	world.set_central_body(body, Vec3d.new(0, r0, 0), Vec3d.new(0, 0, -body.circular_speed(r0)))
	world.anchor_id = PLAYER_ID
	var player := ShipState.create(PLAYER_ID, "PLAYER", _designs[PLAYER_ID].config)
	player.side = &"player"
	player.policy = ShipPolicy.from_dict(vessel.policy)
	_auto_salvo_at = 0.0
	var systems := _new_systems(PLAYER_ID)
	systems.tech = p.tech.duplicate()
	if _designs[PLAYER_ID].blueprint == vessel.blueprint:
		# The vessel's own crew; the damage it was left with.
		systems.use_crew_plan(vessel.crew)
		systems.apply_condition(vessel.condition)
		# Stores as left (the yard tops them up at launch, for credits).
		var stores: Dictionary = vessel.condition.get("stores", {})
		player.propellant_kg = minf(float(stores.get("propellant_kg", player.propellant_kg)), player.propellant_kg)
		player.propellant_kg = minf(player.propellant_kg, _intact_tank_capacity(systems))
		player.set_rounds(mini(int(stores.get("rounds", player.cannon_rounds)), player.cannon_rounds))
	player.attach_systems(systems)
	world.add_ship(player)
	player_wing = AirWing.for_ship(player)
	if _designs[PLAYER_ID].blueprint == vessel.blueprint:
		player_wing.apply_state(vessel.wing)
	world.wings.append(player_wing)
	hud.player_wing = player_wing
	hud.encounter = encounter
	_spawn_view(PLAYER_ID, Color.WHITE)
	_spawn_encounter()
	_sortie_closed = false
	combat_log = CombatLog.begin(player, world.sim_time)
	if hud.debrief != null:
		hud.debrief.visible = false

	mission = MissionChain.from_dict(p.campaign)
	mission.contract = p.active_contract.duplicate()
	tutorial = Tutorial.from_dict(p.tutorial)
	_salvaged = false
	if mission.goal() == MissionChain.Goal.ESCORT:
		_spawn_courier(player)
	hud.notice("%s — %s" % [mission.number_text(), mission.current().brief], world.sim_time)
	if PlayerProfile.load_notice != "":
		hud.notice(PlayerProfile.load_notice, world.sim_time)
		combat_log.record(world.sim_time, "profile", PlayerProfile.load_notice)
		PlayerProfile.load_notice = ""
	GameLog.info("main", "Orbital sandbox ready: player flies '%s' (%.0f t), %s orbit at %.0f km, fixed dt %.4f s" % [
		_designs[PLAYER_ID].config.display_name, _designs[PLAYER_ID].config.mass_kg / 1000.0,
		location.body.display_name, location.start_altitude_m / 1000.0, world.fixed_dt])


## The next encounter: the size picked on the shipyard map, in slots
## target_01, target_02, …, each with its own policy and role. The first of
## a sortie is already close (the lead 2.5 km ahead, crossing the bow at
## ~25 m/s); one arriving after a salvage (`arriving`) starts
## ARRIVAL_DISTANCE_M out and closes; it must be detected before it engages.
func _spawn_encounter(arriving: bool = false) -> void:
	var mission_no := get_profile().missions_completed + 1
	# A contract sets how dangerous the ships are (its threat level).
	if not get_profile().active_contract.is_empty():
		mission_no = maxi(int(get_profile().active_contract.get("threat", mission_no)), 1)
	for i in EnemyFactory.encounter_size(get_profile().encounter_size):
		_spawn_contact(i, mission_no, arriving)
	encounter.ensure_selection(world)
	player_wing.target_id = encounter.selected


## Ship `index` of the encounter, in slot target_<index + 1>.
func _spawn_contact(index: int, mission_no: int, arriving: bool) -> Contact:
	var id := StringName("target_%02d" % (index + 1))
	var player := world.get_ship(PLAYER_ID)
	var template := _load_template()
	_designs[id] = _compile(EnemyFactory.design(mission_no, template, ConstructionCatalog.default_catalog(), index), template)
	var class_name_word: String = (_designs[id].blueprint as ShipBlueprint).name.split("-")[0].to_upper()
	var offset: Vector3 = CONTACT_OFFSETS[index % CONTACT_OFFSETS.size()] * (1.0 + float(index / CONTACT_OFFSETS.size()))
	var pos := player.position + offset
	var vel := player.velocity + Vector3(-25, 1.5, 6.0)
	var attitude := Quaternion(Vector3.UP, 0.9)
	if arriving:
		var dir := (Basis(Vector3.UP, 1.3 * mission_no + 0.4 * index) * Vector3(0.35, 0.1, -1.0)).normalized()
		pos = player.position + dir * (ARRIVAL_DISTANCE_M + 1500.0 * index)
		vel = player.velocity - dir * ARRIVAL_SPEED_MPS
		attitude = Basis.looking_at(-dir, Vector3.UP).get_rotation_quaternion()
	var label := "TGT-%02d%s %s" % [mission_no, "" if index == 0 else "ABCDEFGH"[index % 8], class_name_word]
	var ship := ShipState.create(id, label, _designs[id].config, pos, vel, attitude)
	ship.angular_velocity = Vector3.ZERO if arriving else Vector3(0.0, 0.03, 0.01)
	ship.side = &"hostile"
	var c := Contact.create(id, index, EnemyFactory.policy(mission_no, index))
	ship.policy = c.policy
	c.arriving = arriving
	c.salvo_at = world.sim_time + c.policy.salvo_interval_s * 0.5
	ship.attach_systems(_new_systems(id))
	world.add_ship(ship)
	world.set_input(id, ShipControlInput.neutral())
	# Its craft (they launch once it is hostile, from ENEMY_WING_FROM_MISSION).
	c.wing = AirWing.for_ship(ship)
	c.wing.target_id = PLAYER_ID
	world.wings.append(c.wing)
	encounter.add(c)
	_spawn_view(id, Color(1.0, 0.78, 0.72))
	return c


## The selected contact's id (&"" when there is none) and its ship.
func target_id() -> StringName:
	return encounter.selected


func target_ship() -> ShipState:
	return world.get_ship(encounter.selected) if encounter.selected != &"" else null


## Select a contact (U cycles; the drawer's list picks one).
func select_contact(id: StringName) -> void:
	if encounter.select(id):
		hud.selected_id = &""
		player_wing.target_id = id
		hud.reset_target()
		hud.notice("TARGET: %s" % world.get_ship(id).display_name, world.sim_time)


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


## A panel that needs the mouse is open (Tab drawer, controls, loot, debrief):
## clicks are for it, and the cursor stays free.
func menu_open() -> bool:
	return hud.overview.visible or hud.controls.visible or (hud.loot != null and hud.loot.visible) \
		or (hud.debrief != null and hud.debrief.visible)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu_open():
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
	elif event.is_action_pressed("grapple"):
		toggle_grapple()
		return
	elif event.is_action_pressed("fire_missile"):
		fire_missile()
		return
	elif event.is_action_pressed("missile_mode"):
		cycle_missile_mode()
	elif event.is_action_pressed("countermeasures"):
		fire_countermeasures()
	elif event.is_action_pressed("ack_alert"):
		if hud.alert_queue.acknowledge():
			audio.play("ack")
		return
	elif event.is_action_pressed("tutorial"):
		toggle_tutorial()
		return
	elif event.is_action_pressed("cycle_target"):
		cycle_target()
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


## The encounter turns hostile (or stands down) together: fire on one of
## its ships and they all fight. T toggles it.
func set_target_hostile(on: bool, why: String = "") -> void:
	var lead := target_ship()
	for c in encounter.live(world):
		c.hostile = on
		if not on:
			world.set_input(c.id, ShipControlInput.neutral())
	hud.target_hostile = on
	GameLog.info("main", "Encounter %s%s" % ["HOSTILE — guns free" if on else "passive", " (%s)" % why if why != "" else ""])
	if why != "" and lead != null:
		var who := lead.display_name if encounter.live(world).size() <= 1 else "%s and %d more" % [lead.display_name, encounter.live(world).size() - 1]
		hud.notice("%s turn%s HOSTILE — %s" % [who, "s" if encounter.live(world).size() <= 1 else "", why], world.sim_time)
		combat_log.record(world.sim_time, "contact", "%s turned hostile: %s" % [who, why])


## Turrets train on the point under the aim cursor, at the target's range
## (render space is centred on the player, so it is already an offset).
func _aim(input: ShipControlInput, player: ShipState, target: ShipState) -> void:
	var screen := get_viewport().get_visible_rect().size * 0.5 + player_input.aim_offset
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var range_m := DEFAULT_AIM_RANGE_M
	if hud.selected_id != &"" and not world.has_ship(hud.selected_id):
		hud.selected_id = &""
	var craft := world.get_ship(hud.selected_id) if hud.selected_id != &"" else null
	if craft != null:
		range_m = clampf((craft.position - player.position - origin).length(), 200.0, 30_000.0)
	elif target != null and target.is_active() and track.detected:
		var pos := target.position if track.in_contact else track.estimated_position(player, world.sim_time)
		range_m = clampf((pos - player.position - origin).length(), 200.0, 30_000.0)
	player_input.aim_range_m = range_m
	input.has_aim = true
	input.aim_offset = origin + dir * range_m
	# With a lock (or a craft picked with U), fire control corrects other guns' leads.
	if craft != null:
		input.lead_target_id = craft.id
	else:
		input.lead_target_id = target.id if target != null and target.is_active() and track.locked else &""


## Angle (°) between where the guns are aimed and the fire-control lead on
## `target` (180 when there is no solution).
func aim_error_deg(player: ShipState, target: ShipState, input: ShipControlInput) -> float:
	if target == null or not target.is_active() or player.config.cannon == null or not input.has_aim:
		return 180.0
	var muzzle := player.position + player.orientation * player.config.primary_muzzle()
	var rel := target.position + target.orientation * target.config.hit_box_center - muzzle
	var rel_v := target.velocity - player.velocity
	var t := FireControl.intercept_time(rel, rel_v, player.config.cannon.muzzle_velocity_mps)
	if t <= 0.0:
		return 180.0
	var aim := player.position + input.aim_offset - muzzle
	return rad_to_deg(aim.angle_to(FireControl.lead_point(rel, rel_v, t)))


## The player's automation (their vessel's ShipPolicy) on top of manual
## control. It only ever adds fire: the trigger is pulled when the player
## pulls it, or when auto-fire's conditions hold (ShipPolicy.trigger);
## manual input always wins and is never blocked.
func _apply_automation(input: ShipControlInput, player: ShipState, target: ShipState) -> void:
	var policy := player.policy
	var c := encounter.selected_contact()
	if policy == null or c == null or hud.selected_id != &"":
		return
	var fightable := is_fightable(target)
	input.fire = policy.trigger(input.fire, c.track.locked, c.hostile, aim_error_deg(player, target, input), fightable)
	# Auto-salvo at the selected contact (manual M, or a salvo in flight, comes first).
	if salvo == null and target != null and target.is_active() and player.systems != null:
		var range_m := player.position.distance_to(target.position)
		if policy.salvo_due(c.track.locked, c.track.confidence, range_m, c.hostile, world.sim_time, _auto_salvo_at, fightable):
			_auto_salvo_at = world.sim_time + policy.salvo_interval_s
			var s := MissileSalvo.start(PLAYER_ID, c.id, policy.salvo_mode, get_profile().missile_order, policy.salvo_count)
			if s.available(player.systems) > 0:
				salvo = s
				hud.notice("AUTO-SALVO — %s ×%s at %s" % [MissileSalvo.mode_text(policy.salvo_mode, get_profile().missile_order),
					str(policy.salvo_count) if policy.salvo_count > 0 else "all", target.display_name], world.sim_time)


## Space: fire flares from every ready launcher (manual always works).
func fire_countermeasures() -> String:
	var why := world.launch_decoys(PLAYER_ID)
	if why == "":
		audio.play("launch", -8.0)
	else:
		hud.notice("FLARES: " + why, world.sim_time)
	return why


## Automatic flares by policy, for the player and every live contact: as
## soon as an inbound missile is armed and within the policy's lead time.
func _auto_countermeasures(player: ShipState) -> void:
	var ships: Array[ShipState] = [player]
	for c in encounter.live(world):
		ships.append(world.get_ship(c.id))
	for s in ships:
		if s == null or not s.is_active() or s.derelict or s.policy == null or s.systems == null:
			continue
		var t := Hud.missile_inbound_time(world, s, true)
		if s.policy.cm_due(t) and not s.systems.ready_decoy_launchers().is_empty():
			world.launch_decoys(s.id)
			if s == player:
				audio.play("launch", -8.0)


## Shooter ids on the player's side: the player and its craft (their rounds
## are drawn after incoming ones when tracers run short).
func _own_shooters() -> Dictionary:
	var own := {PLAYER_ID: true}
	for c in player_wing.crafts:
		own[c.id] = true
	return own


## Still a fighting ship (for automation): active, not a derelict, not
## disabled. Wrecks and beaten hulls are left for salvage.
static func is_fightable(ship: ShipState) -> bool:
	return ship != null and ship.is_active() and not ship.derelict \
		and (ship.systems == null or ship.systems.disabled_reason() == "")


## Zooming in: swing the camera to look at the aim point and put the cursor
## in the middle, so the zoomed view is centred on what was being aimed at.
func _center_view_on_aim(player: ShipState) -> void:
	var screen := get_viewport().get_visible_rect().size * 0.5 + player_input.aim_offset
	var aim := camera.project_ray_origin(screen) + camera.project_ray_normal(screen) * player_input.aim_range_m
	var d := (player.orientation.inverse() * aim).normalized()
	player_input.camera_orbit = Vector2(atan2(-d.x, -d.z), clampf(asin(clampf(d.y, -1.0, 1.0)), -PlayerInput.ORBIT_PITCH_LIMIT, PlayerInput.ORBIT_PITCH_LIMIT))
	player_input.aim_offset = Vector2.ZERO


## Boarders took our bridge.
func player_captured() -> bool:
	var player := world.get_ship(PLAYER_ID) if world != null else null
	return player != null and player.systems != null and player.systems.captured


## The enemy boards a beaten player: it lines its collar up with one of our
## ports, extends a gangway (V cuts it loose) and sends its party across.
func _enemy_board(c: Contact, target: ShipState, player: ShipState) -> void:
	var link := world.link_for(c.id)
	if link == null:
		if world.sim_time < c.reboard_at:
			world.set_input(c.id, ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true))
			return
		var found := Docking.best(target, player)
		if not found.is_empty() and found.assessment.ok:
			world.dock(c.id, PLAYER_ID)
			var line := "ENEMY GANGWAY — %s is coming aboard! [V] cut it loose" % target.display_name
			hud.notice(line, world.sim_time)
			combat_log.record(world.sim_time, "boarding", line)
			world.set_input(c.id, ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true))
		else:
			world.set_input(c.id, GunneryAI.dock_approach(target, player, found))
		return
	world.set_input(c.id, ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true))
	if link.sealed() and world.boarding_for(link) == null:
		var party := world.start_boarding(link, ENEMY_BOARDING_TEAM)
		if party != null:
			party.set_defence(player_defence)
			var line := "ENEMY BOARDERS crossing (%d) — Tab → CREW: defence policy" % party.team.size()
			hud.notice(line, world.sim_time)
			combat_log.record(world.sim_time, "boarding", line)


## The enemy boarding us right now, or null.
func enemy_boarding() -> BoardingAction:
	for b in world.boardings:
		if b.link.target_id == PLAYER_ID and not b.finished():
			return b
	return null


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
	var target := target_ship()
	if player.config.cannon == null or target == null or not target.is_active():
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
	elif what == NOTIFICATION_EXIT_TREE:
		GameLog.hold(false)


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
	if not player.is_active() or player_captured():
		lines = p.lose_vessel(catalog)
		GameLog.info("main", "Vessel %s — the hold is gone; the station rebuilds the same design" % ("captured" if player_captured() else "lost"))
	elif _designs[PLAYER_ID].blueprint == p.vessel.blueprint:
		var after := player.systems.condition()
		after["stores"] = {"propellant_kg": player.propellant_kg, "rounds": player.cannon_rounds,
			"missiles": player.systems.missile_count()}
		lines.append_array(p.dock(after, catalog))
		GameLog.info("main", "Docked %s after sortie %d%s" % [p.vessel.name, p.vessel.sorties, " (damaged)" if p.vessel.is_damaged() else ""])
	for line in lines:
		GameLog.info("main", line)
	tutorial.decline_offer()
	p.tutorial = tutorial.to_dict()
	p.campaign = mission.to_dict()
	if combat_log != null:
		if mission.failed != "":
			combat_log.objectives.append("✕ %s %s — failed: %s" % [mission.number_text(), mission.current().title, mission.failed])
		elif combat_log.objectives.is_empty():
			combat_log.objectives.append("▲ %s %s — not met yet: %s" % [mission.number_text(), mission.current().title, mission.current().brief])
		var outcome := "vessel captured by boarders" if player_captured() else ("vessel lost" if not player.is_active() else "jumped home to %s" % location.station_name)
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
	var why := Salvage.block_reason(world.get_ship(PLAYER_ID), target_ship())
	if why != "":
		hud.notice("SALVAGE BEACON: " + why, world.sim_time)
		return
	drop_beacon()


## G: drop a salvage beacon on the disabled wreck. Earth Shipyard's tug
## brings it in: half its scrap value and the bounty in credits now; its
## crates are opened at the beacon's odds and go into our hold. Returns
## the crates (a Drop each, null for an empty one).
func drop_beacon() -> Array:
	var target := target_ship()
	var p := get_profile()
	var catalog := ConstructionCatalog.default_catalog()
	var intact := target.systems.intact_fraction()
	var scrap := roundi(Salvage.scrap_value(target.systems) * Salvage.BEACON_SCRAP_RATE * TechTree.factor("salvage", p.tech_level("salvage")))
	var bounty := Salvage.bounty_for(target.systems)
	var crates := p.open_crates(Salvage.pulls_for(target.systems), Salvage.BEACON_LOOT_CHANCE, catalog)
	var stripped := _stripped_part(target)
	if stripped != null:
		crates.push_front(stripped)
	for d in crates:
		if d != null:
			p.stow(d)
	p.credits += scrap + bounty
	_salvaged = true
	var summary := "Salvage beacon on %s (%d%% intact): %d cr scrap (%d%%) + %d cr bounty; %d crates into the hold" % [
		target.display_name, roundi(intact * 100.0), scrap, roundi(Salvage.BEACON_SCRAP_RATE * 100.0), bounty, crates.size()]
	_record_payout(target, summary, crates, "in the hold")
	hud.loot.show_rewards("SALVAGE BEACON — %s" % target.display_name, PackedStringArray([
		"Wreck %d%% intact · the station's tug brings it in" % roundi(intact * 100.0),
		"+%d cr scrap (%d%% of %d) · +%d cr bounty" % [scrap, roundi(Salvage.BEACON_SCRAP_RATE * 100.0), Salvage.scrap_value(target.systems), bounty],
		"%d crate%s · %d%% chance of loot each · into the cargo hold — banked at %s when you jump home" % [crates.size(), "" if crates.size() == 1 else "s",
			roundi(Salvage.BEACON_LOOT_CHANCE * 100.0), location.station_name],
	]), crates, p)
	_next_contact()
	return crates


## Our boarders took the target's bridge: 80 % of its scrap value and double
## bounty in credits; its stores and crates (better odds, bonus crates) go
## into our cargo hold. The boarders withdraw on their own; once they are
## home the prize crew takes it to Earth Shipyard and the next contact comes.
func take_prize(c: Contact = null) -> Array:
	if c == null:
		c = encounter.selected_contact()
	c.prize_taken = true
	_salvaged = true
	var met := false
	if not c.beaten:
		c.beaten = true
		_beaten_any = true
		met = mission.contact_beaten()
	if mission.contact_captured() or met:
		_complete_mission()
	var target := world.get_ship(c.id)
	var p := get_profile()
	var catalog := ConstructionCatalog.default_catalog()
	var scrap := roundi(Salvage.scrap_value(target.systems) * Salvage.TAKEOVER_SCRAP_RATE * TechTree.factor("salvage", p.tech_level("salvage")))
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
		"Bridge taken · boarders withdrawing · prize crew to %s" % location.station_name,
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


## A contact leaves the encounter (the selected one unless given). A beaten
## one (salvaged or taken) stays where it is as a derelict wreck — its guns,
## point defence and craft silent; one that escaped is simply gone. When no
## live contact is left, the next encounter arrives in the freed slots.
func _next_contact(keep_wreck: bool = true, c: Contact = null) -> void:
	if c == null:
		c = encounter.selected_contact()
	if c == null:
		return
	if keep_wreck:
		_retire_contact(c)
	else:
		for craft in c.wing.crafts:
			if world.has_ship(craft.id):
				world.remove_ship(craft.id)
		world.wings.erase(c.wing)
		world.remove_ship(c.id)
		(_views[c.id] as Node).queue_free()
		_views.erase(c.id)
	encounter.remove(c.id)
	hud.reset()
	if encounter.live(world).is_empty():
		_spawn_encounter(true)
	encounter.ensure_selection(world)
	player_wing.target_id = encounter.selected


func _retire_contact(c: Contact) -> void:
	_wreck_count += 1
	var new_id := StringName("wreck_%02d" % _wreck_count)
	var wreck := world.retire_ship(c.id, new_id)
	if wreck == null:
		return
	wreck.display_name = "WRECK %s" % wreck.display_name.trim_prefix("TGT-")
	# It drifts clear of us (a prize crew or the tug nudges it off), so it
	# doesn't sit in front of our collar or our guns.
	var player := world.get_ship(PLAYER_ID)
	var away := wreck.position - player.position
	wreck.velocity = player.velocity + (away.normalized() if away.length() > 1.0 else Vector3.UP) * WRECK_DRIFT_MPS
	wreck.angular_velocity *= 0.2
	var view: ShipView = _views[c.id]
	_views.erase(c.id)
	view.ship_id = new_id
	view.name = "ShipView_%s" % new_id
	_views[new_id] = view
	if c.wing != null:
		_derelict_wings.append(c.wing)
	_wrecks.append(new_id)
	hud.wreck_ids = _wrecks
	while _wrecks.size() > MAX_WRECKS:
		_drop_wreck(_wrecks.pop_front())


func _drop_wreck(id: StringName) -> void:
	for wing in _derelict_wings.duplicate():
		if wing.carrier_id == id:
			for c in wing.crafts:
				if world.has_ship(c.id):
					world.remove_ship(c.id)
			_derelict_wings.erase(wing)
	world.remove_ship(id)
	if _views.has(id):
		(_views[id] as Node).queue_free()
		_views.erase(id)


## Cargo hold volume beyond its capacity (m³), 0 if it fits.
func cargo_over_m3() -> float:
	var sys := world.get_ship(PLAYER_ID).systems
	var capacity := sys.stats.cargo_m3 if sys != null else 0.0
	return maxf(get_profile().vessel.cargo_volume_m3(ConstructionCatalog.default_catalog()) - capacity, 0.0)


## A hostile contact is shooting at us (one fired in the last UNDER_FIRE_S
## and can still fight): no jumping out. One that has not opened fire yet
## does not stop the jump.
func in_combat() -> bool:
	if world.sim_time - _last_enemy_fire >= UNDER_FIRE_S:
		return false
	for c in encounter.live(world):
		var s := world.get_ship(c.id)
		if c.hostile and s.systems != null and not s.systems.is_disabled():
			return true
	return false


## Note hostile fire: every hostile contact's rounds and its craft's.
func _note_enemy_fire() -> void:
	for c in encounter.contacts:
		var shooters: Array[StringName] = [c.id]
		for craft in c.wing.flying():
			shooters.append(craft.id)
		for id in shooters:
			if not world.has_ship(id):
				continue
			var fired := world.get_ship(id).rounds_fired
			if fired > int(_enemy_rounds_seen.get(id, 0)) and c.hostile:
				_last_enemy_fire = world.sim_time
			_enemy_rounds_seen[id] = fired


## What an emergency jump now would leave behind: craft out, boarders
## across. Empty = everyone is home. (Cargo over capacity is vented.)
func jump_waiting() -> PackedStringArray:
	var out := PackedStringArray()
	var out_craft := player_wing.flying().map(func(c: AirWing.Craft) -> String: return c.label)
	if not out_craft.is_empty():
		out.append("craft %s ([]] recall)" % ", ".join(out_craft))
	for b in world.boardings:
		if b.link.attacker_id == PLAYER_ID and not b.finished() and b.team.any(func(m: CrewRoster.Member) -> bool: return m.location < 0 and m.state != CrewRoster.State.DEAD):
			out.append("the boarding party ([N] withdraw)")
	return out


## Hold [B]: the dimensional jump drive charges for JUMP_HOLD_S and takes the
## ship home to Earth Shipyard. Not while a hostile is firing on us. Craft
## and boarders still out are left behind (an emergency jump — the countdown
## says so in red); cargo over capacity is vented.
## Returns true when the jump happened (the scene is changing).
func _update_jump(player: ShipState, delta: float) -> bool:
	var state := {}
	if Input.is_action_pressed("open_shipyard") and player.is_active() and not hud.controls.visible:
		if in_combat():
			_jump_hold = 0.0
			state = {"blocked": "under fire — disable the hostile, or get out of its reach until it stops shooting"}
		else:
			_jump_hold = minf(_jump_hold + delta, JUMP_HOLD_S)
			var waiting := jump_waiting()
			state = {"progress": _jump_hold / JUMP_HOLD_S, "left_s": JUMP_HOLD_S - _jump_hold, "waiting": waiting}
			if _jump_hold >= JUMP_HOLD_S:
				hud.jump_state = {}
				var vented := get_profile().vessel.vent_excess(player.systems.stats.cargo_m3, ConstructionCatalog.default_catalog()) \
					if player.systems != null else PackedStringArray()
				if not vented.is_empty():
					combat_log.record(world.sim_time, "jump", "Vented before the jump: %s" % ", ".join(vented))
				combat_log.record(world.sim_time, "jump", "%sump to %s%s" % [
					"Emergency j" if not waiting.is_empty() else "Dimensional j", location.station_name,
					" — left behind: %s" % ", ".join(waiting) if not waiting.is_empty() else ""])
				tutorial.observe({"jump": true})
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
		&"reassign":
			var why := sys.reassign(str(arg[0]), int(arg[1]))
			if why != "":
				hud.notice("CREW: " + why, world.sim_time)
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
		&"defence":
			player_defence = int(arg)
			var b := enemy_boarding()
			if b != null:
				b.set_defence(player_defence)
			hud.notice("Crew defence: %s" % BoardingAction.DEFENCE_NAMES[player_defence], world.sim_time)
		&"vent":
			var went := get_profile().vessel.vent(str(arg[0]), str(arg[1]))
			if went != "":
				hud.notice("Cargo vented: %s" % went, world.sim_time)
				combat_log.record(world.sim_time, "cargo", "Vented %s" % went)
		&"missile_mode":
			set_missile_mode(int(arg))
		&"missile_order_up":
			var p := get_profile()
			var order := MissileSalvo.sanitize_order(p.missile_order)
			var i := order.find(int(arg))
			if i > 0:
				order[i] = order[i - 1]
				order[i - 1] = int(arg)
			p.missile_order = order
			hud.notice("MISSILE SEQUENCE: %s" % MissileSalvo.order_text(order), world.sim_time)
			_save_profile()
		&"select_contact":
			select_contact(StringName(str(arg)))
		&"policy_preset":
			_set_policy(ShipPolicy.preset(str(arg)))
		&"policy_set":
			var pol := world.get_ship(PLAYER_ID).policy
			pol.set(str(arg[0]), arg[1])
			pol.preset_name = "Custom"
			_set_policy(ShipPolicy.from_dict(pol.to_dict()))
		&"pd_order_up":
			var pol2 := world.get_ship(PLAYER_ID).policy
			var order := pol2.pd_order()
			var k := order.find(StringName(str(arg)))
			if k > 0:
				order[k] = order[k - 1]
				order[k - 1] = StringName(str(arg))
			pol2.pd_priorities = order
			pol2.preset_name = "Custom"
			_set_policy(pol2)
		&"vent_excess":
			var capacity := sys.stats.cargo_m3
			var went := get_profile().vessel.vent_excess(capacity, ConstructionCatalog.default_catalog())
			if not went.is_empty():
				hud.notice("Cargo vented: %s" % ", ".join(went), world.sim_time)
				combat_log.record(world.sim_time, "cargo", "Vented %s" % ", ".join(went))


## The player's automation changed (Tab › POLICY): fly it and save it with
## the vessel.
func _set_policy(policy: ShipPolicy) -> void:
	var player := world.get_ship(PLAYER_ID)
	player.policy = policy
	get_profile().vessel.policy = policy.to_dict()
	hud.notice("POLICY: %s" % policy.summary(), world.sim_time)
	_save_profile()


## Sensor tracks both ways for every contact; announce new contacts.
func _update_tracks(player: ShipState, delta: float) -> void:
	var dt := delta if world == null else minf(delta, 0.25)
	for c in encounter.contacts:
		var target := world.get_ship(c.id)
		if target == null:
			continue
		if c.track.update(player, target, world.sim_time, dt, world.jamming_of(target)):
			var line := "CONTACT — %s detected at %.1f km" % [target.display_name, player.position.distance_to(target.position) / 1000.0]
			hud.notice(line, world.sim_time)
			combat_log.record(world.sim_time, "sensors", line)
		if c.track.just_scanned and target.systems != null:
			var est := Salvage.scan_estimate(target.systems)
			var line := "SCAN COMPLETE — %s: ~%d spare parts, ~%d crates aboard · bounty ~%d cr" % [target.display_name,
				roundi(est.parts * c.track.scan_error), roundi(est.crates * c.track.scan_error), roundi(est.bounty * c.track.scan_error)]
			hud.notice(line, world.sim_time)
			combat_log.record(world.sim_time, "sensors", line)
		c.their_track.update(target, player, world.sim_time, dt, world.jamming_of(player))


## Each side's craft hunt the other side's craft in flight.
func _link_wings() -> void:
	var ours: Array[StringName] = []
	var theirs: Array[StringName] = []
	for c in player_wing.flying():
		ours.append(c.id)
	for c in encounter.contacts:
		for craft in c.wing.flying():
			theirs.append(craft.id)
	player_wing.hostile_ids = theirs
	for c in encounter.contacts:
		c.wing.hostile_ids = ours


func _sync_craft_views(alpha: float, render_origin: Vector3) -> void:
	var alive := {}
	var wings: Array[AirWing] = [player_wing]
	for c in encounter.contacts:
		wings.append(c.wing)
	wings.append_array(_derelict_wings)
	for wing in wings:
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
				view.hostile = wing != player_wing
				add_child(view)
				_craft_views[c.id] = view
			view.sync_from(ship, alpha, render_origin)
	for id in _craft_views.keys():
		if not alive.has(id):
			(_craft_views[id] as Node).queue_free()
			_craft_views.erase(id)


func _sync_missile_views(alpha: float, render_origin: Vector3) -> void:
	var alive := {}
	for m in world.missiles:
		if not m.is_active():
			continue
		alive[m.id] = true
		var view: MissileView = _missile_views.get(m.id)
		if view == null:
			view = MissileView.new()
			view.hostile = m.missile_owner != PLAYER_ID and player_wing.by_id(m.missile_owner) == null
			add_child(view)
			_missile_views[m.id] = view
		view.sync_from(m, alpha, render_origin)
	for id in _missile_views.keys():
		if not alive.has(id):
			(_missile_views[id] as Node).queue_free()
			_missile_views.erase(id)


var _courier_view: CraftView


func _sync_courier_view(alpha: float, render_origin: Vector3) -> void:
	var c := world.get_ship(COURIER_ID) if world.has_ship(COURIER_ID) else null
	if c == null or not c.is_active():
		if _courier_view != null:
			_courier_view.queue_free()
			_courier_view = null
		return
	if _courier_view == null:
		_courier_view = CraftView.new()
		_courier_view.craft_id = COURIER_ID
		_courier_view.config = c.config
		_courier_view.callsign = "COURIER"
		_courier_view.scale = Vector3.ONE * 3.0
		add_child(_courier_view)
	_courier_view.sync_from(c, alpha, render_origin)


## A warhead going off. A big anti-ship blast already shows as an explosion
## on the struck ship (ShipSystems.blast_at), a small one as a fireball; EMP
## is a blue ring; a nuclear burst is a fireball and a white flash. A
## missile shot down or self-destructing breaks up in a small fireball.
func _show_burst(burst: Dictionary, player: ShipState) -> void:
	var ship := world.get_ship(burst.ship_id)
	var dist := ship.position.distance_to(player.position) if ship != null else 0.0
	var near := clampf(1.0 - dist / 3000.0, 0.0, 1.0)
	if burst.get("shot_down", false):
		hit_flashes.add_fireball(burst.ship_id, burst.point_body, burst.radius)
		audio.play("detonation", lerpf(-24.0, -10.0, near))
		return
	match int(burst.kind):
		MissileConfig.Warhead.EMP:
			hit_flashes.add_burst(burst.ship_id, burst.point_body, burst.radius, Color(0.45, 0.7, 1.0, 0.9))
			audio.play("detonation", lerpf(-18.0, -6.0, near))
		MissileConfig.Warhead.NUCLEAR:
			hit_flashes.add_explosion(burst.ship_id, burst.point_body, burst.radius, true)
			hud.flash_white()
			audio.play("detonation", lerpf(-10.0, 0.0, near))
			camera.shake(5.0 * clampf(1.0 - dist / 8000.0, 0.0, 1.0))
		_:
			if float(burst.radius) < ShipSystems.SMALL_BLAST_M:
				hit_flashes.add_fireball(burst.ship_id, burst.point_body, burst.radius)
			audio.play("detonation", lerpf(-16.0, -4.0, near))


## Docking camera out of our collar while a target is in boarding range and
## no gangway is sealed yet.
func _update_docking_cam(player: ShipState, target: ShipState, alpha: float, render_origin: Vector3) -> void:
	var link := world.link_for(PLAYER_ID)
	var mine := Docking.collars(player.systems)
	if target == null or not target.is_active() or mine.is_empty() or (link != null and link.sealed()) or player.position.distance_to(target.position) > DockingCam.SHOW_RANGE_M:
		hud.docking_cam.visible = false
		return
	var found := Docking.best(player, target)
	var port: Docking.Port = found.a_port if not found.is_empty() else mine[0]
	var q := player.interpolated_orientation(alpha)
	var from := player.interpolated_position(alpha) + q * port.position_body - render_origin
	hud.docking_cam.show_view(from, q * port.normal_body, q * Vector3.UP, found.get("assessment", {}))


## U: the next target — every ship of the encounter, then each hostile
## craft out, in turn. A ship becomes the selected contact (target card,
## missiles, salvage, gangway); a craft only takes the lead marker and fire
## control.
func cycle_target() -> void:
	var ids: Array[StringName] = []
	for c in encounter.live(world):
		ids.append(c.id)
	for c in encounter.live(world):
		for craft in c.wing.flying():
			if world.has_ship(craft.id):
				ids.append(craft.id)
	if ids.is_empty():
		return
	var current := hud.selected_id if hud.selected_id != &"" else encounter.selected
	var next := ids[(ids.find(current) + 1) % ids.size()]
	if encounter.has(next):
		select_contact(next)
	else:
		hud.selected_id = next
		hud.notice("TARGET: %s (lead and fire control)" % world.get_ship(next).display_name, world.sim_time)


## M: a missile from the next ready launcher at the craft picked with U, or
## else the target ship — which needs a sensor lock (a craft: within sensor
## range). Returns "" when one is away, or why not (also a HUD notice).
## M: a salvo — every missile the missile mode allows ([,] cycles it; Tab ›
## WEAPONS sets the sequence) — at the craft picked with U, or else the
## target ship, which needs a sensor lock (a craft: within sensor range). M
## again while it is firing holds the rest. Returns "" when it started, or
## why not (also a HUD notice).
func fire_missile() -> String:
	if salvo != null and not salvo.done():
		hud.notice("MISSILES: salvo held — %d launched" % salvo.launched, world.sim_time)
		salvo = null
		# Holding counts as a decision: automation waits its interval too.
		if world.get_ship(PLAYER_ID).policy != null:
			_auto_salvo_at = world.sim_time + world.get_ship(PLAYER_ID).policy.salvo_interval_s
		return ""
	var player := world.get_ship(PLAYER_ID)
	var at := hud.selected_id if hud.selected_id != &"" and world.has_ship(hud.selected_id) else encounter.selected
	var p := get_profile()
	var why := ""
	var contact := encounter.get_contact(at)
	if at == &"" or not world.has_ship(at):
		why = "no target"
	elif contact != null and not contact.track.locked:
		why = "no sensor lock on %s" % world.get_ship(at).display_name
	elif contact == null and player.systems != null \
			and world.get_ship(at).position.distance_to(player.position) > player.systems.sensor_range_m():
		why = "that craft is outside sensor range"
	elif player.systems == null or player.systems.missiles_of() == 0:
		why = "no missiles ready (launchers empty, offline or not fitted)"
	else:
		var s := MissileSalvo.volley(PLAYER_ID, at, p.missile_mode, p.missile_order, player.systems, _sequence_index)
		if s.volley_ids.is_empty():
			why = "no %s missiles ready ([,] changes the missile mode)" % MissileSalvo.mode_text(p.missile_mode, p.missile_order)
		else:
			_sequence_index = s.next_sequence_index
			salvo = s
			hud.notice("MSL ×%d → %s" % [s.volley_missiles(player.systems), world.get_ship(at).display_name], world.sim_time)
			_step_salvo()
	if why != "":
		hud.notice("MISSILE: " + why, world.sim_time)
	return why


## The salvo in progress: fire whatever launchers have cycled.
func _step_salvo() -> void:
	if salvo == null:
		return
	var n := salvo.step(world)
	if n > 0:
		audio.play("launch")
		combat_log.missiles_launched += n
		var c := encounter.get_contact(salvo.target_id)
		if c != null and not c.hostile:
			set_target_hostile(true, "missiles launched at it")
	if salvo.done():
		salvo = null


## Every contact's salvo in flight: fire what has cycled.
func _step_contact_salvos() -> void:
	for c in encounter.contacts:
		if c.salvo == null:
			continue
		var n := c.salvo.step(world)
		if n > 0:
			_last_enemy_fire = world.sim_time
			if c.salvo.target_id == PLAYER_ID or c.salvo.target_id == COURIER_ID:
				combat_log.missiles_inbound += n
		if c.salvo.done():
			c.salvo = null


## [,]: the next missile mode (all → conventional → EMP → nuclear → sequence).
func cycle_missile_mode() -> void:
	var p := get_profile()
	set_missile_mode((p.missile_mode + 1) % MissileSalvo.Mode.size())


func set_missile_mode(mode: int) -> void:
	var p := get_profile()
	p.missile_mode = clampi(mode, 0, MissileSalvo.Mode.size() - 1)
	hud.notice("MISSILE MODE: %s" % MissileSalvo.mode_text(p.missile_mode, p.missile_order), world.sim_time)
	_save_profile()


## F2: start the guided first sortie (or restart it), or skip it.
func toggle_tutorial() -> void:
	tutorial.toggle()
	get_profile().tutorial = tutorial.to_dict()
	_save_profile()
	hud.notice("Tutorial started — follow the prompts at the top" if tutorial.running() else "Tutorial skipped — [F2] starts it again",
		world.sim_time)


## The current goal is met: reward, log, and the next goal.
func _complete_mission() -> void:
	var was_escort := mission.goal() == MissionChain.Goal.ESCORT
	var line := mission.complete(get_profile())
	hud.notice(line, world.sim_time)
	audio.play("dock")
	combat_log.record(world.sim_time, "mission", line)
	combat_log.objectives.append("✔ " + line)
	GameLog.info("main", line)
	if was_escort and world.has_ship(COURIER_ID):
		hud.notice("The courier jumps out — thanks for the escort", world.sim_time)
		world.remove_ship(COURIER_ID)
	_save_profile()


## The escort mission's courier: ahead and to starboard, drifting with us.
func _spawn_courier(player: ShipState) -> void:
	var c := ShipState.create(COURIER_ID, "COURIER", MissionChain.courier_config(),
		player.position + player.orientation * Vector3(300, 60, -400), player.velocity + player.orientation * Vector3(0, 0, -4), player.orientation)
	world.add_ship(c)
	world.set_input(COURIER_ID, ShipControlInput.neutral())
	hud.escort_id = COURIER_ID


## Contacts beaten, the escort's courier and the tutorial's prompts, each frame.
func _update_goals(player: ShipState) -> void:
	for c in encounter.live(world):
		var s := world.get_ship(c.id)
		if not c.beaten and s.systems != null and s.systems.is_disabled():
			c.beaten = true
			_beaten_any = true
			if mission.contact_beaten():
				_complete_mission()
	if world.has_ship(COURIER_ID) and not world.get_ship(COURIER_ID).is_active():
		mission.escort_lost()
		var line := "COURIER DESTROYED — %s failed" % mission.number_text()
		hud.notice(line, world.sim_time)
		combat_log.record(world.sim_time, "mission", line)
		world.remove_ship(COURIER_ID)
		hud.escort_id = &""
	if tutorial.running() and tutorial.observe({
			"fly": player.delta_v_expended > 2.0,
			"aim": track.locked,
			"fire": combat_log.hits_scored > 0,
			"disable": _beaten_any,
			"salvage": _salvaged}):
		get_profile().tutorial = tutorial.to_dict()
		audio.play("tick")
	var guide := PackedStringArray([mission.hud_line()])
	if tutorial.prompt() != "":
		guide.append(tutorial.prompt())
	hud.guide_lines = guide


## Y: grab the target with the grappling arm, or let go.
func toggle_grapple() -> void:
	var held := world.grapple_for(PLAYER_ID)
	if held != null and held.attacker_id == PLAYER_ID:
		held.release()
		hud.notice("Grappling arm released%s" % (" — siphoned %.1f t propellant, %d rounds" % [held.siphoned_kg / 1000.0, held.siphoned_rounds]
			if held.siphoned_kg > 0.0 or held.siphoned_rounds > 0 else ""), world.sim_time)
		return
	var why := world.grab(PLAYER_ID, encounter.selected)
	if why != "":
		hud.notice("GRAPPLE: " + why, world.sim_time)


## V: extend a gangway to the target, or release the one we have.
func toggle_dock() -> void:
	var link := world.link_for(PLAYER_ID)
	if link != null:
		var b := world.boarding_for(link)
		link.release()
		if link.attacker_id != PLAYER_ID:
			var boarder := encounter.get_contact(link.attacker_id)
			if boarder != null:
				boarder.reboard_at = world.sim_time + ENEMY_REBOARD_DELAY_S
			hud.notice("Enemy gangway cut loose%s" % (" — their boarders aboard are cut off!" if b != null and not b.finished() and b.room >= 0 else ""), world.sim_time)
			return
		hud.notice("Gangway released%s" % (" — the boarding party is cut off!" if b != null and not b.finished() and b.room >= 0 else ""), world.sim_time)
		return
	var found := world.dock(PLAYER_ID, encounter.selected)
	if found.is_empty():
		hud.notice("DOCK: no working docking collar opening into a room", world.sim_time)
	elif not found.has("link"):
		hud.notice("DOCK: " + ", ".join(found.assessment.problems), world.sim_time)


## N: send a boarding party over a sealed gangway, or order it home.
func toggle_boarding() -> void:
	var link := world.link_for(PLAYER_ID)
	if link != null and link.attacker_id != PLAYER_ID:
		hud.notice("BOARD: that gangway is theirs — [V] cuts it loose; Tab → CREW sets your defence", world.sim_time)
		return
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


## Where each frame's time went (ms, the last frame): ai (input, contacts,
## automation), sim (world.advance), events (hits, explosions, logs),
## views (ships, craft, missiles), scene (camera, sky, tracers, flashes),
## hud. Read by tools/profile_frames.gd.
var frame_ms := {}
var _frame_t0 := 0


func _lap(section: String) -> void:
	var now := Time.get_ticks_usec()
	frame_ms[section] = (now - _frame_t0) / 1000.0
	_frame_t0 = now


func _process(delta: float) -> void:
	GameLog.flush()  # the last frame's lines, in one print
	_frame_t0 = Time.get_ticks_usec()
	var player := world.get_ship(PLAYER_ID)
	encounter.ensure_selection(world)
	var target := target_ship()
	var aim_id := encounter.selected if target != null and target.is_active() else &""
	if menu_open() and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_input.aim_limit = get_viewport().get_visible_rect().size * 0.5 - Vector2(24, 24)
	var command := player_input.build_input(delta, aim_id, hud.docking_cam.visible)
	_aim(command, player, target)
	_apply_automation(command, player, target)
	world.set_input(PLAYER_ID, command)
	_note_enemy_fire()
	if _update_jump(player, delta):
		return
	_update_tracks(player, delta)
	for c in encounter.live(world):
		var s := world.get_ship(c.id)
		# A beaten enemy that got away.
		if GunneryAI.should_flee(s) and s.position.distance_to(player.position) > ESCAPE_RANGE_M:
			var line := "%s escaped — out of reach" % s.display_name
			hud.notice(line, world.sim_time)
			combat_log.record(world.sim_time, "contact", line)
			_next_contact(false, c)
		# A takeover pays out at once; the prize stays once the boarders are home.
		elif s.systems != null and s.systems.captured and not c.prize_taken:
			take_prize(c)
		elif c.prize_taken:
			var home := true
			for b in world.boardings:
				if b.link.target_id == c.id and not b.finished():
					home = false
			if home:
				var link := world.link_for(PLAYER_ID)
				if link != null:
					link.release()
				hud.notice("Prize crew aboard %s — it holds station" % s.display_name, world.sim_time)
				_next_contact(true, c)
	target = target_ship()
	# General quarters while a hostile is about: every crew in spacesuits.
	var quarters := encounter.any_hostile(world)
	if player.systems != null and player.systems.suited != quarters:
		player.systems.suited = quarters
		hud.notice("General quarters — crew in spacesuits" if quarters else "Stand down — suits off", world.sim_time)
	var courier := world.get_ship(COURIER_ID) if world.has_ship(COURIER_ID) and world.get_ship(COURIER_ID).is_active() else null
	# What the enemy may shoot at: us, our craft out, an escorted courier
	# (never a wreck); with focus fire the courier first, else the player.
	var prey_list: Array[ShipState] = [player]
	if courier != null:
		prey_list.append(courier)
	for craft in player_wing.flying():
		if world.has_ship(craft.id):
			prey_list.append(world.get_ship(craft.id))
	var team_prey := courier if courier != null else player
	# One enemy at a time comes alongside to board a beaten player: the
	# nearest that wants to (or the one already linked); the rest fight on.
	var boarder: Contact = null
	var our_link := world.link_for(PLAYER_ID)
	for c in encounter.live(world):
		var s := world.get_ship(c.id)
		if our_link != null and our_link.attacker_id == c.id:
			boarder = c
			break
		if boarder == null or s.position.distance_squared_to(player.position) < world.get_ship(boarder.id).position.distance_squared_to(player.position):
			boarder = c
	for c in encounter.live(world):
		_drive_contact(c, player, prey_list, team_prey, quarters, c == boarder)
	_link_wings()
	_update_goals(player)
	_step_salvo()
	_step_contact_salvos()
	_auto_countermeasures(player)
	hud.missile_chip = "[SPC]" if player.systems != null and player.systems.decoys_aboard() > 0 else ""
	# Freeze the moment the player is lost (Backspace restarts) and while the
	# controls panel is open.
	if (not player.is_active() or player_captured()) and not _sortie_closed:
		close_sortie()
		var p := get_profile()
		hud.debrief.show_debrief(p.last_debrief, "[BACKSPACE] respawn the %s here  ·  [B] back to %s" % [p.vessel.name, location.station_name])
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var running := player.is_active() and not player_captured() and not hud.controls.visible
	_lap("ai")
	var alpha := world.advance(delta) if running else 1.0
	_lap("sim")
	for line in world.take_link_events():
		if line.contains("sealed") or line.contains("SEALED"):
			audio.play("dock")
		elif line.begins_with("COLLISION"):
			audio.play("hit", 4.0)
		# Our own salvo announces itself once; each launch and break-up of
		# our missiles would flood the ticker (they still go in the log).
		var ours_routine := (line.contains(" launched at ") and not line.contains(" at %s " % player.display_name)) \
			or (line.contains("shot down") and salvo != null)
		if not ours_routine:
			hud.notice(line, world.sim_time)
		var about := "missile" if line.contains("issile") or line.contains("EMP") or line.contains("Nuclear") else "boarding"
		GameLog.info(about, line)
		combat_log.record(world.sim_time, about, line)
	var hits := world.take_hit_events()
	for ev in hits:
		combat_log.note_hit(ev, PLAYER_ID, world.sim_time, world)
		if ev.target_id == PLAYER_ID:
			audio.play("ricochet" if ev.report != null and ev.report.ricochet else "hit")
		# A passive contact fired upon by us (or our craft) fights back — and
		# its encounter with it.
		var struck := encounter.get_contact(ev.target_id)
		if struck != null and not struck.hostile and (ev.shooter_id == PLAYER_ID or player_wing.by_id(ev.shooter_id) != null):
			set_target_hostile(true, "fired upon")
	for id in world.ship_ids():
		var s := world.get_ship(id).systems
		if s == null:
			continue
		for blast in s.take_explosions():
			hit_flashes.add_explosion(id, blast.pos_body, blast.radius)
			audio.play("explosion", 0.0 if id == PLAYER_ID else -14.0)
			# The camera feels it: hard on our own ship, less with distance.
			var dist := world.get_ship(id).position.distance_to(player.position)
			camera.shake(2.5 * clampf(1.0 - dist / 800.0, 0.0, 1.0))
			if id == PLAYER_ID:
				combat_log.explosions += 1
			combat_log.record(world.sim_time, "explosion", "%s: %s" % [world.get_ship(id).display_name, "; ".join(blast.lines)])
			hud.notice("%s: %s" % [world.get_ship(id).display_name, blast.lines[0]], world.sim_time)
			GameLog.info("main", "%s: %s" % [world.get_ship(id).display_name, "; ".join(blast.lines)])
	for burst in world.take_bursts():
		_show_burst(burst, player)
	hud.note_hits(hits, PLAYER_ID, world.sim_time)
	var log_wings: Array[AirWing] = [player_wing]
	for c in encounter.contacts:
		log_wings.append(c.wing)
	for wing in log_wings:
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

	_lap("events")
	var render_origin := player.interpolated_position(alpha)
	_sync_craft_views(alpha, render_origin)
	_sync_missile_views(alpha, render_origin)
	_sync_courier_view(alpha, render_origin)
	for id: StringName in _views:
		var ship := world.get_ship(id)
		var view: ShipView = _views[id]
		view.visible = ship.is_active()
		view.sync_from(ship, alpha, render_origin)

	if player_input.zoom_changed:
		player_input.zoom_changed = false
		if player_input.zoomed:
			_center_view_on_aim(player)
	_lap("views")
	camera.zoomed = player_input.zoomed and not hud.overview.visible
	camera.fov_zoomed = player_input.zoom_fov()
	camera.orbit = player_input.camera_orbit
	camera.follow(_views[PLAYER_ID], delta)
	_update_docking_cam(player, target_ship(), alpha, render_origin)
	var link := world.link_for(PLAYER_ID)
	var boarding := world.boarding_for(link) if link != null and link.attacker_id == PLAYER_ID else null
	if boarding != null and not hud.hit_cam.showing_boarding() and world.has_ship(boarding.link.target_id):
		var boarded := world.get_ship(boarding.link.target_id)
		hud.hit_cam.show_boarding(boarding, _designs[boarding.link.target_id], boarded.systems, boarded.display_name)
	var continuous := world.continuous_position(render_origin)
	dust.update_origin(continuous)
	dust_far.update_origin(continuous)
	var planet_center := Vec3d.new().minus(world.frame.interpolated_origin(alpha).plus_v3(render_origin)).to_vector3()
	_update_sun(player)
	sky.update_view(planet_center, camera, celestial, world.sim_time)
	_update_sky_light()
	stars.update_view(camera, planet_center, world.body, sky.sky_body_center,
		location.sky_body.radius_m if location.sky_body != null else 0.0)
	projectile_view.sync(world.projectiles(), alpha, render_origin, player.velocity, camera.global_position, _own_shooters())
	decoy_view.sync(world.decoys, render_origin, camera.global_position, world.sim_time)
	hit_flashes.update(world, alpha, render_origin, delta)
	gangways.sync(world, alpha, render_origin)
	hud.track = track
	hud.target_hostile = target_hostile
	_lap("scene")
	hud.update_display(world, PLAYER_ID, encounter.selected, alpha, render_origin, camera, player_input)
	_update_audio(player)
	_lap("hud")


## One enemy ship's turn, by its policy: hold while captured, break free
## from our gangway, board a beaten player (one at a time), close in while
## arriving, else fight its role — whom to shoot (focus fire, never a
## wreck), guns, missile salvos and fighters.
func _drive_contact(c: Contact, player: ShipState, prey_list: Array[ShipState], team_prey: ShipState, quarters: bool,
		may_board: bool = true) -> void:
	var s := world.get_ship(c.id)
	if s.systems != null:
		s.systems.suited = quarters
	var engaging := c.hostile and c.track.detected and world.sim_time - c.track.detected_time >= ENGAGE_GRACE_S \
		and c.their_track.in_contact
	var link := world.link_for(c.id)
	var our_link := world.link_for(PLAYER_ID)
	var someone_else_boarding := our_link != null and our_link.attacker_id != PLAYER_ID and our_link.attacker_id != c.id
	if s.systems != null and s.systems.captured:
		world.set_input(c.id, ShipControlInput.neutral())
	elif link != null and link.attacker_id != c.id and GunneryAI.can_break_contact(s):
		world.set_input(c.id, GunneryAI.break_contact(s, player))
	elif engaging and may_board and not someone_else_boarding and get_profile().missions_completed + 1 >= ENEMY_BOARD_FROM_MISSION \
			and GunneryAI.wants_to_board(s, player):
		_enemy_board(c, s, player)
	elif c.arriving and not s.systems.is_disabled():
		# Inbound: close to its role's standoff, nose on the player; guns only once engaging.
		var input := GunneryAI.command(s, player) if engaging else ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
		if not engaging:
			CraftAI.point(s, player.position - s.position, input)
		var standoff := maxf(ENGAGE_STANDOFF_M, c.policy.keep_range().x)
		var away := (s.position - player.position).normalized()
		CraftAI.steer(s, player.position + away * standoff, player.velocity, input, ARRIVAL_SPEED_MPS)
		world.set_input(c.id, input)
		if s.position.distance_to(player.position) < standoff + 150.0:
			c.arriving = false
	elif engaging:
		var prey := GunneryAI.choose_prey(s, prey_list, team_prey, c.policy)
		if prey == null:
			prey = player
		world.set_input(c.id, GunneryAI.combat(s, prey, world.sim_time, c.policy))
		if c.salvo == null and not s.systems.is_disabled() and c.policy.salvo_due(c.their_track.locked, c.their_track.confidence,
				s.position.distance_to(prey.position), true, world.sim_time, c.salvo_at):
			c.salvo_at = world.sim_time + c.policy.salvo_interval_s
			c.salvo = MissileSalvo.start(c.id, prey.id, c.policy.salvo_mode, [], c.policy.salvo_count)
			if c.salvo.available(s.systems) == 0:
				c.salvo = null
		if get_profile().missions_completed + 1 >= ENEMY_WING_FROM_MISSION and not s.systems.is_disabled():
			for craft in c.wing.crafts:
				if craft.status == AirWing.Status.DOCKED and not craft.is_drone() and craft.service_left_s <= 0.0 and craft.hull_fraction > 0.0:
					c.wing.launch(world, craft)


## Our guns, engines, the jump drive and new danger alerts, heard aboard.
func _update_audio(player: ShipState) -> void:
	if player.rounds_fired > _rounds_heard:
		audio.play("gun")
	_rounds_heard = player.rounds_fired
	var burn := ShipDynamics.thrust_fractions(player.config, player.last_thrust_body, player.last_torque_body) \
		if player.is_active() else Vector2.ZERO
	audio.set_engine(burn.x)
	audio.set_rcs(burn.y)
	audio.set_jump(float(hud.jump_state.progress) if hud.jump_state.has("progress") else -1.0)
	# A sound per alert class as alerts appear or escalate (caution and up;
	# an advisory has its own sound already — the clang of a hit, the spool).
	for a in hud.alert_queue.raised:
		if a.level >= AlertQueue.Level.CAUTION and not a.acked:
			audio.alarm(a.cls, a.level)
			break


## Light from the other body in the sky onto ships: along its direction,
## as bright as its phase gives (0 below the horizon).
func _update_sky_light() -> void:
	var dir := sky.sky_body_light_dir
	sky_light.look_at(-dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	sky_light.light_energy = SUN_ENERGY * sky.sky_body_light


## Real Sun direction for the scenario date; dark while the player is in
## Earth's shadow (ships and the planet's night side agree).
func _update_sun(player: ShipState) -> void:
	var dir := celestial.sun_direction_pci(world.sim_time)
	sun.look_at(-dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	sun.light_energy = SUN_ENERGY * CelestialFrame.sunlight_fraction(world.pci_position(player.position), dir, world.body.radius_m)
