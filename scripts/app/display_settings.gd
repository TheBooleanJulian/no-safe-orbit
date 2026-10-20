class_name DisplaySettings
extends RefCounted
## Window mode, saved per user in user://settings.cfg (not the profile) and
## re-applied at startup by the flight scene and the shipyard. F11 toggles.

const SAVE_PATH := "user://settings.cfg"

static var _applied := false


static func load_fullscreen(path: String = SAVE_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value("display", "fullscreen", false))


static func save_fullscreen(fullscreen: bool, path: String = SAVE_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep any other settings; a missing file is fine
	cfg.set_value("display", "fullscreen", fullscreen)
	return cfg.save(path)


## Apply the saved window mode once per run (a no-op headless).
static func apply_saved(path: String = SAVE_PATH) -> void:
	if _applied:
		return
	_applied = true
	if load_fullscreen(path):
		_set_window(true)


## Switch between fullscreen and a window and remember it.
static func toggle_fullscreen(path: String = SAVE_PATH) -> bool:
	var full := not is_fullscreen()
	_set_window(full)
	save_fullscreen(full, path)
	return full


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func _set_window(full: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
