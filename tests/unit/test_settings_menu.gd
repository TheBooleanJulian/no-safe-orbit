extends TestCase
## Measures: the settings menu (Esc). Settings are saved to and read back
## from their file, clamped, and applied (UI scale, MSAA, 3D resolution,
## volumes, a muted bus); save data, stats and the changelog read right;
## Back up now copies the save without touching it. (The menu itself — Esc,
## its tabs, the pause — is checked in smoke_encounter and smoke_shipyard.)

const SETTINGS := "user://check_settings.cfg"
const PROFILE := "user://check_settings_profile.json"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _use_scratch_settings() -> String:
	var was := GameSettings.path
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS
	return was


func _restore(was: String) -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = was
	GameSettings.apply(_tree())


func test_settings_save_clamp_and_apply() -> void:
	var was := _use_scratch_settings()
	assert_true(GameSettings.value("ui_scale") == 1.0 and GameSettings.value("vsync") == true and GameSettings.value("msaa") == 2, "the defaults")
	GameSettings.set_value("ui_scale", 1.25, _tree())
	GameSettings.set_value("msaa", 4, _tree())
	GameSettings.set_value("render_scale", 0.75, _tree())
	GameSettings.set_value("volume_effects", 0.5, _tree())
	GameSettings.set_value("volume_alarms", 0.0, _tree())
	var root := _tree().root
	var effects := AudioServer.get_bus_index(&"Effects")
	var alarms := AudioServer.get_bus_index(&"Alarms")
	print("    measured: UI ×%.2f, MSAA %d, 3D ×%.2f; effects %.1f dB; alarms muted %s" % [root.content_scale_factor, root.msaa_3d,
		root.scaling_3d_scale, AudioServer.get_bus_volume_db(effects), AudioServer.is_bus_mute(alarms)])
	assert_true(is_equal_approx(root.content_scale_factor, 1.25) and root.msaa_3d == Viewport.MSAA_4X and is_equal_approx(root.scaling_3d_scale, 0.75),
		"applied to the window")
	assert_true(absf(AudioServer.get_bus_volume_db(effects) + 6.02) < 0.05 and AudioServer.is_bus_mute(alarms), "volumes: half is −6 dB, zero is muted")
	# Read back from the file, as at the next start.
	var cfg := ConfigFile.new()
	assert_true(cfg.load(SETTINGS) == OK and is_equal_approx(float(cfg.get_value("display", "ui_scale")), 1.25), "saved in the file")
	GameSettings._loaded_from = ""
	assert_true(is_equal_approx(float(GameSettings.value("ui_scale")), 1.25) and int(GameSettings.value("msaa")) == 4, "read back")
	GameSettings.set_value("ui_scale", 9.0)
	assert_true(is_equal_approx(float(GameSettings.value("ui_scale")), 1.5), "clamped to 150 %")
	GameSettings.reset(_tree())
	assert_true(is_equal_approx(root.content_scale_factor, 1.0) and not AudioServer.is_bus_mute(alarms), "reset to the defaults")
	_restore(was)


func test_save_stats_and_changelog() -> void:
	var p := PlayerProfile.new(3)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	p.credits = 4321
	p.missions_completed = 7
	assert_true(p.save(PROFILE) == OK, "a scratch profile")
	var stats := SettingsMenu.stats_text(p)
	assert_true(stats.contains("4321") and stats.contains("Missions completed") and stats.contains(p.vessel.name), "stats: credits, missions, the ship")
	var save := SettingsMenu.save_text(PROFILE)
	assert_true(save.contains("check_settings_profile.json") and save.contains("format version %d" % PlayerProfile.SCHEMA_VERSION), "the save's file and format")
	# Back up now: a dated copy beside it; the save itself untouched.
	var before := FileAccess.get_file_as_string(PROFILE)
	var copy := PlayerProfile.backup_copy(PROFILE)
	var second := PlayerProfile.backup_copy(PROFILE)
	print("    measured: backups %s, %s" % [copy.get_file(), second.get_file()])
	assert_true(copy != "" and FileAccess.get_file_as_string(copy) == before and FileAccess.get_file_as_string(PROFILE) == before, "copied as it was")
	assert_true(second != copy and FileAccess.file_exists(second), "a second copy never overwrites the first")
	for f in [copy, second, PROFILE, PROFILE + PlayerProfile.BACKUP_SUFFIX]:
		DirAccess.remove_absolute(f)
	# The changelog, as BBCode.
	var md := FileAccess.get_file_as_string(SettingsMenu.CHANGELOG_PATH)
	var bb := SettingsMenu.changelog_bbcode(md)
	print("    measured: changelog %d characters of markdown → %d of BBCode" % [md.length(), bb.length()])
	assert_true(bb.contains("[lb]0.16.0]") and bb.contains("[lb]Unreleased]") and not bb.contains("\n## ") and bb.contains("[b]"), "versions shown, brackets escaped, bold kept")
	assert_true(SettingsMenu.changelog_bbcode("- a **b** `c`\n  wrapped").contains("• a [b]b[/b]") and SettingsMenu.changelog_bbcode("- x\n  wrapped").contains("x wrapped")
		and SettingsMenu.changelog_bbcode("A paragraph\nwrapped on.").contains("A paragraph wrapped on."),
		"bullets, bold, soft-wrapped lines joined")
