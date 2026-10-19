class_name ShipAudio
extends Node
## What you hear aboard: there is no sound in vacuum, so everything is your
## own ship heard through the hull — your guns firing, the main engines'
## rumble, the clang of hits taken, the deep thud of a reactor going up
## (faint when it is the enemy's, picked up through the sensors), alarms,
## the jump drive spooling up. Every sound is synthesised at startup (no
## audio files); Main and the HUD trigger them.

const MIX_RATE := 22050
const VOLUME_DB := -6.0

var _streams: Dictionary = {}  # name -> AudioStreamWAV
var _players: Dictionary = {}  # name -> AudioStreamPlayer (one voice each)
var _engine: AudioStreamPlayer
var _rcs: AudioStreamPlayer
var _jump: AudioStreamPlayer
## Engine rumble level at a whisper of thrust and at full burn (dB), and
## the RCS hiss's.
const ENGINE_DB := Vector2(-20.0, 0.0)
const RCS_DB := Vector2(-34.0, -16.0)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	_streams["gun"] = _make(0.4, _gun)
	_streams["hit"] = _make(0.5, _clang)
	_streams["ricochet"] = _make(0.35, _ping)
	_streams["explosion"] = _make(2.6, _boom)
	_streams["alert"] = _make(0.3, _beep)
	_streams["dock"] = _make(0.6, _thunk)
	_streams["tick"] = _make(0.04, _tick)
	_streams["launch"] = _make(1.2, _whoosh)
	_streams["detonation"] = _make(3.0, _deep_boom)
	for n in _streams:
		var p := AudioStreamPlayer.new()
		p.stream = _streams[n]
		p.volume_db = VOLUME_DB
		p.max_polyphony = 4
		add_child(p)
		_players[n] = p
	_engine = AudioStreamPlayer.new()
	_engine.stream = _make(2.0, _rumble, true)
	_engine.volume_db = -80.0
	add_child(_engine)
	_rcs = AudioStreamPlayer.new()
	_rcs.stream = _make(1.0, _hiss, true)
	_rcs.volume_db = -80.0
	add_child(_rcs)
	if is_inside_tree():
		_engine.play()
		_rcs.play()
	_jump = AudioStreamPlayer.new()
	_jump.stream = _make(5.0, _spool)
	_jump.volume_db = VOLUME_DB - 2.0
	add_child(_jump)


## Play a one-shot (`gain_db` relative to the default level).
func play(sound: String, gain_db: float = 0.0) -> void:
	var p: AudioStreamPlayer = _players.get(sound)
	if p == null:
		return
	p.volume_db = VOLUME_DB + gain_db
	p.play()


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
	if not _jump.playing:
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
