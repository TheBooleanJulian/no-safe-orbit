class_name GameSettings
extends RefCounted
## The settings menu's values (Esc): UI scale, graphics and volumes. Saved
## per user in user://settings.cfg beside the window mode (DisplaySettings),
## not in the profile, and applied at startup by the flight scene and the
## shipyard. Each value is clamped to its range when read.

## Where the settings are kept (tests point it elsewhere).
static var path := DisplaySettings.SAVE_PATH

## key -> [section, default, min, max]
const SPECS := {
	"ui_scale": ["display", 1.0, 0.75, 1.5],
	"vsync": ["graphics", true, false, true],
	"max_fps": ["graphics", 0, 0, 360],
	"msaa": ["graphics", 2, 0, 8],
	"render_scale": ["graphics", 1.0, 0.5, 1.0],
	"volume_master": ["audio", 1.0, 0.0, 1.0],
	"volume_effects": ["audio", 1.0, 0.0, 1.0],
	"volume_ambience": ["audio", 1.0, 0.0, 1.0],
	"volume_alarms": ["audio", 1.0, 0.0, 1.0],
}
## The choices the menu offers.
const UI_SCALES := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5]
const FPS_CAPS := [0, 30, 60, 120, 144, 240]
const MSAA_LEVELS := [0, 2, 4, 8]
const RENDER_SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
## Volume key -> audio bus.
const BUSES := {"volume_master": &"Master", "volume_effects": &"Effects", "volume_ambience": &"Ambience", "volume_alarms": &"Alarms"}

static var _cache: Dictionary = {}
static var _loaded_from := ""


static func _load() -> void:
	if _loaded_from == path:
		return
	_loaded_from = path
	_cache.clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in SPECS:
		var spec: Array = SPECS[key]
		if cfg.has_section_key(spec[0], key):
			_cache[key] = cfg.get_value(spec[0], key)


## The value of `key`, clamped to its range (the default if unset or bad).
static func value(key: String) -> Variant:
	_load()
	var spec: Array = SPECS[key]
	var v: Variant = _cache.get(key, spec[1])
	if spec[1] is bool:
		return bool(v) if (v is bool or v is int) else spec[1]
	if not (v is float or v is int):
		return spec[1]
	if spec[1] is int:
		return clampi(int(v), spec[2], spec[3])
	return clampf(float(v), spec[2], spec[3])


## Set `key`, save it (keeping the file's other settings) and apply it.
static func set_value(key: String, v: Variant, tree: SceneTree = null) -> Error:
	_load()
	_cache[key] = v
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	cfg.set_value(SPECS[key][0], key, value(key))
	var err := cfg.save(path)
	apply(tree)
	return err


## Back to the defaults (the window mode is kept).
static func reset(tree: SceneTree = null) -> Error:
	_load()
	_cache.clear()
	var cfg := ConfigFile.new()
	cfg.load(path)
	for key: String in SPECS:
		if cfg.has_section_key(SPECS[key][0], key):
			cfg.erase_section_key(SPECS[key][0], key)
	var err := cfg.save(path)
	apply(tree)
	return err


## The bus's level from its volume setting (dB; ShipAudio ducks below it).
static func volume_db(bus: StringName) -> float:
	for key: String in BUSES:
		if BUSES[key] == bus:
			return linear_to_db(maxf(float(value(key)), 0.0001))
	return 0.0


## Apply everything: UI scale and graphics to the main window (when `tree`
## is given), volumes to the audio buses.
static func apply(tree: SceneTree = null) -> void:
	if tree != null:
		var root := tree.root
		root.content_scale_factor = float(value("ui_scale"))
		root.msaa_3d = _msaa(int(value("msaa")))
		root.scaling_3d_scale = float(value("render_scale"))
		Engine.max_fps = int(value("max_fps"))
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(value("vsync")) else DisplayServer.VSYNC_DISABLED)
	ShipAudio._ensure_buses()
	for key: String in BUSES:
		var i := AudioServer.get_bus_index(BUSES[key])
		if i < 0:
			continue
		AudioServer.set_bus_mute(i, float(value(key)) <= 0.001)
		AudioServer.set_bus_volume_db(i, volume_db(BUSES[key]))


static func _msaa(samples: int) -> Viewport.MSAA:
	if samples >= 8:
		return Viewport.MSAA_8X
	if samples >= 4:
		return Viewport.MSAA_4X
	if samples >= 2:
		return Viewport.MSAA_2X
	return Viewport.MSAA_DISABLED
