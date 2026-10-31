class_name CustomAssets
extends RefCounted
## Your own sounds, textures and models, dropped into data/custom/ (2026-10-31):
## a file there takes a slot over from the game's own (recorded sample,
## generated texture, built model); with none, nothing changes. The slots
## below are the whole list (art_templates/custom_assets.xlsx is made from
## them, with templates to paint over: tools/make_art_templates.gd).
##
## - audio/<slot>.ogg|.wav|.mp3 — variants as <slot>_2, <slot>_3 … (one is
##   picked at random each time). Loops are looped by the game.
## - textures/<slot>.png|.jpg — square, tiling; painted in greys where the
##   game tints it (TEXTURE_SLOTS says which).
## - models/<part id>.glb|.gltf|.tscn — an external part's model, in metres
##   at its real size, its origin the centre of what it covers on the hull
##   face, +Y out of the hull (as if on a top face: the bow toward −Z, a
##   long part running along Z); <part id>_turret.* replaces a gun's or
##   point-defence turret's head (origin on its pivot, barrel along −Z).
##
## Godot imports a new file when the editor next opens the project (or
## `godot --headless --path . --import`); until then it isn't seen.

## Where to look (tests point it at fixtures). Godot's own text resources
## (.tres, .tscn) load without importing.
static var dir := "res://data/custom/"
const AUDIO_EXTS := ["ogg", "wav", "mp3", "tres"]
const TEXTURE_EXTS := ["png", "jpg", "webp", "tres"]
const MODEL_EXTS := ["glb", "gltf", "tscn"]
const MAX_VARIANTS := 4

## Sound slots: [slot, kind (one-shot / alarm / loop), when it plays,
## length, what the game has now]. ShipAudio plays them.
const AUDIO_SLOTS := [
	["gun", "one-shot", "each of your gun rounds fired (kinetic guns), heard through the hull", "0.2–0.5 s", "Kenney impactPunch_heavy_000 / _002"],
	["laser", "one-shot", "each of your beam weapons' pulses: the capacitor bank letting go", "0.2–0.4 s", "synthesised (falling whine over a thump)"],
	["hit", "one-shot", "a round hitting your ship; a collision (louder)", "0.3–0.6 s", "Kenney impactMetal_heavy_001 / impactMetal_002"],
	["ricochet", "one-shot", "a round glancing off your armour", "0.2–0.5 s", "Kenney impactBell_heavy_001"],
	["explosion", "one-shot", "a reactor or magazine going up: yours loud, the enemy's faint (through the sensors)", "2–3 s", "Kenney lowFrequency_explosion_000"],
	["detonation", "one-shot", "a missile warhead or nuke: shot down, near you or on target, louder the closer", "2–3 s", "Kenney explosionCrunch_003 / _000"],
	["launch", "one-shot", "a missile leaving its tube; flares (quieter). Cut to 1.3 s", "1–1.5 s", "Kenney thrusterFire_000"],
	["dock", "one-shot", "a docking seal, a gangway sealing, a mission complete", "0.4–0.8 s", "Kenney doorClose_001"],
	["tick", "one-shot", "a tutorial step done", "< 0.1 s", "Kenney tick_001"],
	["ack", "one-shot", "an alert acknowledged (the ack key)", "< 0.1 s", "Kenney toggle_001"],
	["alarm_threat", "alarm", "a threat alert: missile inbound, boarders aboard; 1–3 blips (advisory / caution / danger)", "0.2–0.4 s per blip", "Kenney error_008"],
	["alarm_damage", "alarm", "a damage alert: hit taken, hull breach, fire or smoke, a system critical, bridge lost, ship lost", "0.2–0.4 s per blip", "Kenney error_004"],
	["alarm_systems", "alarm", "a systems alert: reactor hot or scrammed, power short, EMP, guns locked, no gunners, out of propellant", "0.2–0.4 s per blip", "Kenney error_002"],
	["alarm_nav", "alarm", "a navigation alert: ground close, atmosphere entry or terrain, jump charging or blocked, tow, survey", "0.2–0.4 s per blip", "Kenney bong_001"],
	["alarm_info", "alarm", "an information alert (anything not in the four above)", "0.2–0.4 s per blip", "Kenney select_002"],
	["engine_loop", "loop", "the main engines' rumble, louder and a little higher as the throttle opens", "2–5 s, seamless", "Kenney spaceEngineLow_000"],
	["rcs_loop", "loop", "the RCS thrusters' hiss while they fire", "1–3 s, seamless", "Kenney thrusterFire_000"],
	["ambience_loop", "loop", "the machinery's hum aboard, always on (very quiet)", "5–20 s, seamless", "Kenney computerNoise_000"],
	["jump_spool", "one-shot", "the jump drive spooling up, played from where the charge is (5 s charge)", "about 5 s, rising", "synthesised (rising tone)"],
]

## Texture slots: [slot, where, tile size, tinted?, size (px)].
const TEXTURE_SLOTS := [
	["hull_plates", "hull blocks, wedges and trusses: plating with seams, rivets, hatches", "one tile = 12 m (four 3 m panels across)", "yes: by the hull colour (paint greys)", 1024],
	["armour_plates", "armour plates (falls back to hull_plates)", "one tile = 3 m: one plate per cell face", "yes: by the hull colour (paint greys)", 512],
	["part_surface", "every part's metal (engines, guns, racks, masts …): none today, flat colours", "one tile = 2 m", "yes: by each part's colour (paint greys)", 512],
	["hazard_stripes", "the docking collar's ring", "one tile = the ring band, repeated round it", "no: used as painted", 256],
	["gangway_ribs", "the boarding gangway tube's ribs (one rib per tile, along the tube)", "one tile = 2 m along the tube", "yes: white = the gangway's colour", 256],
]
const PART_SURFACE_TILE_M := 2.0

static var _textures: Dictionary = {}
static var _models: Dictionary = {}


## The first file for `base` (a path under `dir` without extension) with one
## of `exts` that Godot has imported, or "".
static func find(base: String, exts: Array) -> String:
	for ext: String in exts:
		var path := dir + base + "." + ext
		if ResourceLoader.exists(path):
			return path
	return ""


## Your recordings for a sound slot (variants in order), or [] if none.
static func audio(slot: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for k in MAX_VARIANTS:
		var path := find("audio/%s%s" % [slot, "" if k == 0 else "_%d" % (k + 1)], AUDIO_EXTS)
		if path == "":
			break
		var s := load(path) as AudioStream
		if s != null:
			out.append(s)
	return out


## A looping copy of `stream` (OGG, MP3 or WAV).
static func looped(stream: AudioStream) -> AudioStream:
	var s: AudioStream = stream.duplicate()
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s


## Your texture for a slot, or null (cached either way).
static func texture(slot: String) -> Texture2D:
	if not _textures.has(slot):
		var path := find("textures/" + slot, TEXTURE_EXTS)
		_textures[slot] = load(path) as Texture2D if path != "" else null
	return _textures[slot]


## Your model for a part (`<part id>` or `<part id>_turret`), or null.
static func model(name: String) -> PackedScene:
	if not _models.has(name):
		var path := find("models/" + name, MODEL_EXTS)
		_models[name] = load(path) as PackedScene if path != "" else null
	return _models[name]


## Forget what was looked up (tests; after importing new files).
static func reset() -> void:
	_textures.clear()
	_models.clear()
