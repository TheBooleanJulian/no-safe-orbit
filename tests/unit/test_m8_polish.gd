extends TestCase
## Measures: Milestone 8 — the mission chain and its rewards, the guided
## first sortie, save/load hardening (atomic write, rolling backup,
## recovery from a damaged profile, schema 5 migration), the sortie summary
## in the debrief, the hit-cam caption, the design tokens and the
## simulation's frame budget under load.

const TEST_PROFILE := "user://test_m8_profile.json"


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	return BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp", ".unreadable", ".v4"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE + suffix))


func _write(file_path: String, text: String) -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Runs load_or_new() against TEST_PROFILE.
func _load() -> PlayerProfile:
	var saved := PlayerProfile.path
	PlayerProfile.path = TEST_PROFILE
	var p := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	return p


# --- Missions ----------------------------------------------------------------------

func test_the_mission_chain_pays_and_moves_on() -> void:
	var p := PlayerProfile.new(1)
	var m := MissionChain.from_dict(p.campaign)
	assert_true(m.goal() == MissionChain.Goal.DISABLE and m.hud_line().begins_with("MISSION 1/4 ▸ FIRST BLOOD"), m.hud_line())
	var credits := p.credits
	assert_true(m.contact_beaten(), "disabling the contact meets 'First blood'")
	var line := m.complete(p)
	assert_true(p.credits == credits + 150 and line.contains("COMPLETE") and p.campaign.step == 1, "150 cr paid, on to mission 2 (%s)" % line)
	assert_true(m.goal() == MissionChain.Goal.CAPTURE and not m.contact_beaten() and m.contact_captured(), "capture needs the bridge taken, not a disable")
	var parts := p.spare_parts
	m.complete(p)
	assert_true(p.spare_parts == parts + 20, "the capture pays parts too")
	assert_true(m.goal() == MissionChain.Goal.ESCORT, "then the escort")
	m.escort_lost()
	assert_true(not m.contact_beaten() and m.hud_line().contains("FAILED"), "a lost courier fails it: %s" % m.hud_line())
	var again := MissionChain.from_dict(p.campaign)
	assert_true(again.goal() == MissionChain.Goal.ESCORT and again.failed == "", "a failed goal is tried again next sortie")
	again.contact_beaten()
	again.complete(p)
	assert_true(not again.contact_beaten() and again.hud_line().contains("(1/2)") and again.contact_beaten(), "two waves to hold the line")
	again.complete(p)
	assert_true(again.goal() == MissionChain.Goal.PATROL and again.number_text() == "PATROL" and again.contact_beaten(), "then patrols")
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	assert_true(int(q.campaign.step) == MissionChain.CHAIN.size(), "progress is saved")


func test_the_courier_is_a_target_the_enemy_can_kill() -> void:
	var cfg := MissionChain.courier_config()
	assert_true(cfg.validate().is_empty(), "a valid flight config: %s" % ", ".join(cfg.validate()))
	assert_true(cfg.hull_hp == MissionChain.COURIER_HULL_HP and cfg.cannon == null, "unarmed, with hull points")


# --- Tutorial ----------------------------------------------------------------------

func test_the_tutorial_follows_what_the_player_does() -> void:
	var t := Tutorial.from_dict({})
	assert_true(t.state == Tutorial.State.OFFER and t.prompt().contains("[F2]"), "offered: %s" % t.prompt())
	t.toggle()
	assert_true(t.running() and t.current_id() == "fly" and t.prompt().begins_with("TUTORIAL 1/7 ▸ FLY"), t.prompt())
	assert_true(not t.observe({"aim": true}), "it waits for the step it is on")
	assert_true(t.observe({"fly": true, "aim": true}) and t.current_id() == "fire", "steps already done are passed in order")
	t.observe({"fire": true, "disable": true, "salvage": true, "jump": true})
	assert_true(t.current_id() == "repair", "jumped home: the repair is left for the station")
	var saved := Tutorial.from_dict(t.to_dict())
	assert_true(saved.current_id() == "repair", "and it carries over in the profile")
	saved.observe({"repair": true})
	assert_true(saved.state == Tutorial.State.DONE and saved.prompt() == "", "done after the repair")
	var s := Tutorial.from_dict({"state": "running", "step": 2})
	s.toggle()
	assert_true(s.state == Tutorial.State.SKIPPED and s.prompt() == "", "F2 while running skips it")
	s.toggle()
	assert_true(s.running() and s.step == 0, "F2 later starts it again from the top")
	var o := Tutorial.from_dict({})
	o.decline_offer()
	assert_true(o.state == Tutorial.State.SKIPPED, "a first sortie without it: no more offers")
	assert_true(Tutorial.from_dict({"state": "nonsense", "step": 99}).state == Tutorial.State.OFFER, "bad saved state falls back safely")


# --- Save / load ---------------------------------------------------------------------

func test_saves_keep_a_rolling_backup_and_never_leave_temp_files() -> void:
	_clean()
	var p := PlayerProfile.new(2)
	p.credits = 111
	assert_true(p.save(TEST_PROFILE) == OK and not FileAccess.file_exists(TEST_PROFILE + ".bak"), "first save: no backup yet")
	p.credits = 222
	assert_true(p.save(TEST_PROFILE) == OK, "second save")
	var bak := PlayerProfile.load_file(TEST_PROFILE + ".bak", PackedStringArray())
	var now := PlayerProfile.load_file(TEST_PROFILE, PackedStringArray())
	assert_true(bak != null and bak.credits == 111 and now.credits == 222, "the save before is the backup")
	assert_true(not FileAccess.file_exists(TEST_PROFILE + ".tmp"), "no temporary file left behind")
	_clean()


func test_a_damaged_profile_is_restored_from_its_backup() -> void:
	_clean()
	var p := PlayerProfile.new(2)
	p.credits = 111
	p.save(TEST_PROFILE)
	p.credits = 222
	p.save(TEST_PROFILE)
	_write(TEST_PROFILE, "{ \"schema_version\": 5, \"credits\": 9")  # cut off mid-write
	var got := _load()
	assert_true(got != null and got.credits == 111, "the backup is loaded, not a fresh start (credits %d)" % got.credits)
	assert_true(PlayerProfile.load_notice.contains("restored") and PlayerProfile.load_notice.contains(".unreadable"),
		"with a clear message: %s" % PlayerProfile.load_notice)
	assert_true(FileAccess.file_exists(TEST_PROFILE + ".unreadable"), "the damaged file is kept")
	# A save cut off between its renames: the new file is whole in .tmp.
	_clean()
	p.credits = 333
	p.save(TEST_PROFILE)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(TEST_PROFILE), ProjectSettings.globalize_path(TEST_PROFILE + ".tmp"))
	got = _load()
	assert_true(got != null and got.credits == 333 and PlayerProfile.load_notice.contains("RECOVERED") and FileAccess.file_exists(TEST_PROFILE),
		"the interrupted save is finished (%s)" % PlayerProfile.load_notice)
	# A profile deleted on purpose stays deleted (the backup is not resurrected).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	p.save(TEST_PROFILE + ".bak")
	got = _load()
	assert_true(got.credits == PlayerProfile.STARTING_CREDITS and PlayerProfile.load_notice == "", "deleted: a new profile")
	# Nothing usable at all: a new profile, and the player is told.
	_clean()
	_write(TEST_PROFILE, "garbage")
	got = _load()
	assert_true(got.credits == PlayerProfile.STARTING_CREDITS and PlayerProfile.load_notice.contains("no usable backup"),
		"no backup: a new profile, said plainly (%s)" % PlayerProfile.load_notice)
	PlayerProfile.load_notice = ""
	_clean()


func test_schema_5_migrates_a_v4_save_and_keeps_the_original() -> void:
	_clean()
	var p := PlayerProfile.new(3)
	p.ensure_vessel(_template())
	p.missions_completed = 3
	var d := p.to_dict()
	d.schema_version = 4
	d.erase("tutorial")
	d.erase("campaign")
	_write(TEST_PROFILE, JSON.stringify(d))
	var got := _load()
	assert_true(got != null and got.loaded_schema == 4 and got.missions_completed == 3, "a v4 save loads")
	assert_true(got.tutorial.state == "skipped" and int(got.campaign.step) == 0, "a veteran isn't offered the tutorial; the chain starts")
	assert_true(FileAccess.file_exists(TEST_PROFILE + ".v4"), "the v4 original is kept before anything is written")
	got.save(TEST_PROFILE)
	var again := PlayerProfile.load_file(TEST_PROFILE, PackedStringArray())
	assert_true(again.loaded_schema == PlayerProfile.SCHEMA_VERSION and again.tutorial.state == "skipped", "saved as schema 5")
	var fresh := PlayerProfile.from_dict({"schema_version": 4}, PackedStringArray())
	assert_true(fresh.tutorial.state == "offer", "a new pilot on an old save is offered it")
	_clean()


# --- Reports -------------------------------------------------------------------------

func test_the_debrief_opens_with_a_sortie_summary() -> void:
	var d := {"ship_name": "Kite", "design": "Frigate Mk I", "outcome": "jumped home", "shots_fired": 40, "hits_scored": 10,
		"systems_destroyed": 2, "hits_taken": 5, "stopped_by_armor": 3, "hits_by_side": {"port": 4, "fore": 1},
		"systems_lost": [{"id": "e28", "name": "Fusion reactor", "side": "port"}], "crew_lost": 1, "crew_wounded": 2,
		"missiles_launched": 2, "missiles_inbound": 1, "objectives": ["✔ MISSION 1/4 COMPLETE — First blood: +150 cr"]}
	var lines := CombatLog.summary(d)
	assert_true(lines[0].begins_with("✔ MISSION 1/4"), "the goal first")
	var text := "\n".join(lines)
	assert_true(text.contains("10 hits from 40 rounds (25 %)") and text.contains("2 missiles launched"), "what we dealt:\n%s" % text)
	assert_true(text.contains("most through the port") and text.contains("1 missile fired at us"), "what came at us")
	assert_true(text.contains("Fusion reactor e28 (port)") and text.contains("1 killed · 2 wounded"), "what it cost")
	assert_true(CombatLog.render(d).contains("SORTIE SUMMARY"), "rendered at the top of the debrief")


func test_the_hit_cam_caption_says_how_the_round_got_in() -> void:
	var bp := _template()
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config(bp.name))
	# A heavy round straight in through the bow, along the keel.
	var report := Penetration.apply(sys, Vector3(0, 0, -60), Vector3(0, 0, 1), 400.0)
	var caption := HitCam.caption_for(report)
	var first := caption.get_slice("\n", 0)
	assert_true(first.begins_with("In through the fore") or first.begins_with("Stopped by the fore") or first.begins_with("Deflected"),
		"first line: how it came in (%s)" % first)
	assert_true(caption.split("\n").size() <= 5, "short enough to read during the replay")


func test_design_tokens_match_the_design_system() -> void:
	assert_true(CyberTheme.CYAN.to_html(false) == "00d4c8" and CyberTheme.AMBER.to_html(false) == "f5c842", "teal and gold accents")
	assert_true(Color(CyberTheme.BG, 1.0).to_html(false) == "050508" and Color(CyberTheme.SURFACE, 1.0).to_html(false) == "0a0e14",
		"void and surface")
	assert_true(CyberTheme.SANS_FAMILIES[0] == "Space Grotesk" and CyberTheme.MONO_FAMILIES[0] == "JetBrains Mono"
		and CyberTheme.SANS_FAMILIES.size() > 2 and CyberTheme.MONO_FAMILIES.size() > 2, "brand fonts first, with fallbacks")


func test_the_simulation_keeps_a_60_hz_budget_under_load() -> void:
	var bench: GDScript = load("res://tools/bench_sim.gd")
	var result: Dictionary = bench.run(12, 900)
	var peak_rounds := 0
	for row in result.rows:
		peak_rounds = maxi(peak_rounds, int(row.rounds))
	# Point defence fires a third as many (heavier) rounds since play-test
	# batch 6, so the duel piles up ~50 in 15 s where it used to reach 100+.
	assert_true(peak_rounds > 40, "a real load: %d rounds in flight" % peak_rounds)
	assert_less_equal(result.mean_ms, 8.0, "mean tick time (ms) with %d rounds and 12 missiles" % peak_rounds)
