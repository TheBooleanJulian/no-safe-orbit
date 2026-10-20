class_name ShipAudio
extends Node
## What you hear aboard: there is no sound in vacuum, so everything is your
## own ship heard through the hull — your guns firing, missiles leaving the
## tubes, the main engines' rumble and the RCS hiss, the clang of hits
## taken, the deep thud of a warhead or a reactor going up (faint when it is
## the enemy's, picked up through the sensors), the machinery's hum, the
## jump drive spooling up, and the alarms (a sound per alert class, Pass A).
##
## Recorded CC0 samples (data/audio, Kenney's Sci-Fi, Impact and Interface
## packs; data/ATTRIBUTION.md) where a slot has one; any slot without one —
## or a sample that fails to load — is synthesised at startup instead.
## Three buses: Effects (one-shots and engines), Alarms and Ambience; an
## alarm ducks the other two so it is always heard.

const MIX_RATE := 22050
const VOLUME_DB := -6.0
const AUDIO_DIR := "res://data/audio/"
## One-shots: slot -> sample variants (one picked at random, pitch ±4 %).
const SAMPLES := {
	"gun": ["impactPunch_heavy_000", "impactPunch_heavy_002"],
	"hit": ["impactMetal_heavy_001", "impactMetal_002"],
	"ricochet": ["impactBell_heavy_001"],
	"explosion": ["lowFrequency_explosion_000"],
	"detonation": ["explosionCrunch_003", "explosionCrunch_000"],
	"launch": ["thrusterFire_000"],
	"dock": ["doorClose_001"],
	"tick": ["tick_001"],
	"ack": ["toggle_001"],
}
## A one-shot cut short (s): the launch is a 5 s motor sample.
const CUT_S := {"launch": 1.3}
## Alarms by alert class (AlertQueue.CLASSES): sample, and how many blips a
## danger / caution / advisory sounds.
const ALARMS := {
	&"threat": "error_008",
	&"damage": "error_004",
	&"systems": "error_002",
	&"nav": "bong_001",
	&"info": "select_002",
}
const ALARM_REPEATS := [1, 2, 3]  # by level: advisory, caution, danger
const ALARM_GAP_S := 0.18
## Loops: engines, RCS, machinery hum.
const ENGINE_SAMPLE := "spaceEngineLow_000"
const RCS_SAMPLE := "thrusterFire_000"
const AMBIENCE_SAMPLE := "computerNoise_000"
const AMBIENCE_DB := -30.0
## Buses and ducking.
const BUS_EFFECTS := &"Effects"
const BUS_ALARMS := &"Alarms"
const BUS_AMBIENCE := &"Ambience"
const DUCK_DB := -9.0
const DUCK_RELEASE_S := 0.8

## False: synthesise every slot (no samples), e.g. to test the fallback.
var use_samples := true
## Headless runs (tests, checks) have a dummy audio driver that never
## retires a playback, so anything played would still be held at exit:
## there, nothing is actually played (the logic still runs).
var silent := DisplayServer.get_name() == "headless"
## Slots served by a recorded sample (the rest are synthesised).
var sampled: Dictionary = {}

var _streams: Dictionary = {}  # name -> AudioStream (first variant)
var _variants: Dictionary = {}  # name -> Array[AudioStream]
var _players: Dictionary = {}  # name -> AudioStreamPlayer
var _alarms: Dictionary = {}  # class -> AudioStreamPlayer
var _engine: AudioStreamPlayer
var _rcs: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _jump: AudioStreamPlayer
var _duck := 0.0  # seconds of ducking left
var _pending: Array[Dictionary] = []  # {class, at} alarm blips still to sound
var _cuts: Array[Dictionary] = []  # {player, at}
var _clock := 0.0
## Engine rumble level at a whisper of thrust and at full burn (dB), and
## the RCS hiss's.
const ENGINE_DB := Vector2(-20.0, 0.0)
const RCS_DB := Vector2(-34.0, -16.0)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	_ensure_buses()
	var synth := {
		"gun": _make(0.4, _gun), "hit": _make(0.5, _clang), "ricochet": _make(0.35, _ping),
		"explosion": _make(2.6, _boom), "alert": _make(0.3, _beep), "dock": _make(0.6, _thunk),
		"tick": _make(0.04, _tick), "launch": _make(1.2, _whoosh), "detonation": _make(3.0, _deep_boom),
		"ack": _make(0.04, _tick),
	}
	for n: String in synth:
		var variants: Array[AudioStream] = []
		if use_samples:
			for f: String in SAMPLES.get(n, []):
				var s := _load(f)
				if s != null:
					variants.append(s)
		if variants.is_empty():
			variants.append(synth[n])
		else:
			sampled[n] = true
		_variants[n] = variants
		_streams[n] = variants[0]
		var p := AudioStreamPlayer.new()
		p.stream = variants[0]
		p.volume_db = VOLUME_DB
		p.max_polyphony = 4
		p.bus = BUS_EFFECTS
		add_child(p)
		_players[n] = p
	for cls: StringName in ALARMS:
		var s := _load(ALARMS[cls]) if use_samples else null
		if s != null:
			sampled["alarm_%s" % cls] = true
		var p := AudioStreamPlayer.new()
		p.stream = s if s != null else synth["alert"]
		p.volume_db = VOLUME_DB + 2.0
		p.max_polyphony = 3
		p.bus = BUS_ALARMS
		add_child(p)
		_alarms[cls] = p
	_engine = _loop_player(ENGINE_SAMPLE, _make(2.0, _rumble, true), BUS_EFFECTS)
	_rcs = _loop_player(RCS_SAMPLE, _make(1.0, _hiss, true), BUS_EFFECTS)
	_ambience = _loop_player(AMBIENCE_SAMPLE, null, BUS_AMBIENCE)
	if _ambience != null:
		_ambience.volume_db = AMBIENCE_DB
	if is_inside_tree() and not silent:
		_engine.play()
		_rcs.play()
		if _ambience != null:
			_ambience.play()
	_jump = AudioStreamPlayer.new()
	_jump.stream = _make(5.0, _spool)
	_jump.volume_db = VOLUME_DB - 2.0
	_jump.bus = BUS_EFFECTS
	add_child(_jump)


## Stop and release every stream on the way out: a loop still playing at
## quit would leak its stream (and its OGG data).
func _exit_tree() -> void:
	for p in get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
			(p as AudioStreamPlayer).stream = null


func _process(delta: float) -> void:
	_clock += delta
	# Alarm blips due.
	var still: Array[Dictionary] = []
	for b in _pending:
		if _clock >= float(b.at):
			var p: AudioStreamPlayer = _alarms[b.cls]
			if p.is_inside_tree() and not silent:
				p.play()
		else:
			still.append(b)
	_pending = still
	# One-shots cut short.
	var cuts: Array[Dictionary] = []
	for c in _cuts:
		if _clock >= float(c.at):
			(c.player as AudioStreamPlayer).stop()
		else:
			cuts.append(c)
	_cuts = cuts
	_duck = maxf(_duck - delta, 0.0)
	_apply_duck()


## Play a one-shot (`gain_db` relative to the default level).
func play(sound: String, gain_db: float = 0.0) -> void:
	var p: AudioStreamPlayer = _players.get(sound)
	if p == null:
		return
	var variants: Array = _variants.get(sound, [])
	if variants.size() > 1:
		p.stream = variants[_rng.randi() % variants.size()]
	p.pitch_scale = _rng.randf_range(0.96, 1.04) if sampled.has(sound) else 1.0
	p.volume_db = VOLUME_DB + gain_db
	if silent:
		return
	p.play()
	if CUT_S.has(sound) and sampled.has(sound):
		_cuts.append({"player": p, "at": _clock + float(CUT_S[sound])})


## Sound an alert of `cls` at `level` (0 advisory, 1 caution, 2 danger):
## 1–3 blips of its class's alarm; the effects and ambience duck under it.
func alarm(cls: StringName, level: int) -> void:
	if not _alarms.has(cls):
		cls = &"info"
	var n: int = ALARM_REPEATS[clampi(level, 0, 2)]
	for k in n:
		_pending.append({"cls": cls, "at": _clock + k * ALARM_GAP_S})
	_duck = maxf(_duck, n * ALARM_GAP_S + DUCK_RELEASE_S)
	_apply_duck()


## Whether an alarm currently ducks the effects and ambience.
func ducking() -> bool:
	return _duck > 0.0


func _apply_duck() -> void:
	var k := clampf(_duck / DUCK_RELEASE_S, 0.0, 1.0)
	for bus in [BUS_EFFECTS, BUS_AMBIENCE]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, DUCK_DB * k)


## Effects, Alarms and Ambience buses (sending to Master), made if missing.
static func _ensure_buses() -> void:
	for bus in [BUS_EFFECTS, BUS_ALARMS, BUS_AMBIENCE]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, &"Master")


func _load(file: String) -> AudioStream:
	var path := AUDIO_DIR + file + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## A looping player: the sample (looped) if there is one, else `fallback`
## (null: no player).
func _loop_player(file: String, fallback: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var s: AudioStream = _load(file) if use_samples else null
	if s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		(s as AudioStreamOggVorbis).loop = true
		sampled[file] = true
	elif fallback == null:
		return null
	else:
		s = fallback
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -80.0
	p.bus = bus
	add_child(p)
	return p


## Main engines' rumble (aft, reverse and side engines), 0..1 of full
## thrust: louder and a little higher as the throttle opens.
func set_engine(fraction: float) -> void:
	if _engine == null:
		return
	var k := clampf(fraction, 0.0, 1.0)
	_engine.volume_db = -80.0 if k < 0.01 else lerpf(ENGINE_DB.x, ENGINE_DB.y, sqrt(k))
	_engine.pitch_scale = lerpf(0.9, 1.15, k)


## The RCS thrusters' hiss, 0..1 of their thrust or torque.
func set_rcs(fraction: float) -> void:
	if _rcs == null:
		return
	var k := clampf(fraction, 0.0, 1.0)
	_rcs.volume_db = -80.0 if k < 0.02 else lerpf(RCS_DB.x, RCS_DB.y, k)


## The jump drive spooling (0..1 of the charge); <0 stops it.
func set_jump(progress: float) -> void:
	if _jump == null:
		return
	if progress < 0.0:
		if _jump.playing:
			_jump.stop()
		return
	if not _jump.playing and not silent:
		_jump.play(progress * 5.0)


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


# --- Synthesis ------------------------------------------------------------------

## A loop is rendered a little long and its head crossfaded with the tail
## that runs on past the end, so the seam does not click.
func _make(seconds: float, voice: Callable, loop: bool = false) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var fade := int(0.1 * MIX_RATE) if loop else 0
	var samples := PackedFloat32Array()
	samples.resize(n + fade)
	var state := {"lp": 0.0, "brown": 0.0, "hp": 0.0, "crackle": 0.0}
	for i in n + fade:
		samples[i] = voice.call(float(i) / MIX_RATE, seconds, state)
	for i in fade:
		samples[i] = lerpf(samples[n + i], samples[i], float(i) / fade)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = n
	return wav


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


## Low-passed noise (one-pole filter, `k` = smoothing).
func _lp_noise(state: Dictionary, k: float) -> float:
	state.lp = lerpf(state.lp, _noise(), k)
	return state.lp


func _gun(t: float, _len: float, state: Dictionary) -> float:
	return 0.9 * sin(TAU * 52.0 * t) * exp(-t * 9.0) + 0.6 * _lp_noise(state, 0.25) * exp(-t * 28.0)


func _clang(t: float, _len: float, state: Dictionary) -> float:
	var ring := sin(TAU * 430.0 * t) * 0.5 + sin(TAU * 693.0 * t) * 0.35 + sin(TAU * 1171.0 * t) * 0.2
	return ring * exp(-t * 7.0) + 0.7 * _lp_noise(state, 0.5) * exp(-t * 60.0)


func _ping(t: float, len: float, _state: Dictionary) -> float:
	var f := lerpf(3200.0, 1400.0, t / len)
	return 0.5 * sin(TAU * f * t) * exp(-t * 9.0)


func _boom(t: float, _len: float, state: Dictionary) -> float:
	return 0.8 * _lp_noise(state, 0.04) * 3.0 * exp(-t * 1.6) + 0.5 * sin(TAU * 34.0 * t) * exp(-t * 2.2)


func _beep(t: float, _len: float, _state: Dictionary) -> float:
	var f := 880.0 if t < 0.12 else 660.0
	var on := 1.0 if t < 0.1 or (t > 0.14 and t < 0.26) else 0.0
	return 0.35 * signf(sin(TAU * f * t)) * on


func _thunk(t: float, _len: float, state: Dictionary) -> float:
	return 0.8 * sin(TAU * 80.0 * t) * exp(-t * 12.0) + 0.4 * _lp_noise(state, 0.15) * exp(-t * 20.0)


func _tick(t: float, _len: float, _state: Dictionary) -> float:
	return 0.4 * sin(TAU * 2200.0 * t) * exp(-t * 120.0)


## Engines through the hull: brown noise, a low hum (35–55 Hz, whole cycles
## in the loop) beating against itself, and a sparse crackle of combustion.
func _rumble(t: float, _len: float, state: Dictionary) -> float:
	state.brown = clampf(state.brown * 0.998 + _noise() * 0.05, -1.0, 1.0)
	var hum := 0.32 * sin(TAU * 38.0 * t) + 0.22 * sin(TAU * 46.5 * t) + 0.12 * sin(TAU * 55.0 * t)
	if _rng.randf() < 0.0015:
		state.crackle = _rng.randf_range(0.4, 0.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
	state.crackle *= 0.97
	return 0.75 * state.brown + hum * (0.85 + 0.15 * sin(TAU * 1.5 * t)) + state.crackle * _noise()


## RCS jets: high-passed noise, a thin hiss.
func _hiss(_t: float, _len: float, state: Dictionary) -> float:
	var x := _noise()
	state.hp = lerpf(state.hp, x, 0.3)
	return 0.45 * (x - state.hp)


## A missile leaving its tube: a clunk, then a hiss of the motor falling away.
func _whoosh(t: float, len: float, state: Dictionary) -> float:
	var clunk := 0.7 * sin(TAU * 70.0 * t) * exp(-t * 25.0)
	var hiss := _lp_noise(state, lerpf(0.6, 0.08, t / len)) * 1.6 * exp(-t * 2.5) * minf(t * 20.0, 1.0)
	return clunk + hiss


## A warhead heard through the hull: a long low thud.
func _deep_boom(t: float, _len: float, state: Dictionary) -> float:
	return 0.9 * _lp_noise(state, 0.02) * 4.0 * exp(-t * 1.1) + 0.6 * sin(TAU * 26.0 * t) * exp(-t * 1.4)


func _spool(t: float, len: float, _state: Dictionary) -> float:
	var k := t / len
	var f := lerpf(110.0, 880.0, k * k)
	return (0.25 + 0.2 * k) * sin(TAU * f * t) * (0.7 + 0.3 * sin(TAU * 7.0 * t))
