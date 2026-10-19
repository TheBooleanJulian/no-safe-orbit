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
var _jump: AudioStreamPlayer
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
	_engine.play()
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


## Main engines' rumble, 0..1 of full thrust.
func set_engine(fraction: float) -> void:
	if _engine == null:
		return
	_engine.volume_db = -80.0 if fraction < 0.01 else lerpf(-28.0, VOLUME_DB, clampf(fraction, 0.0, 1.0))


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

func _make(seconds: float, voice: Callable, loop: bool = false) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var state := {"lp": 0.0, "brown": 0.0}
	for i in n:
		var t := float(i) / MIX_RATE
		var s: float = clampf(voice.call(t, seconds, state), -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
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


func _rumble(_t: float, _len: float, state: Dictionary) -> float:
	state.brown = clampf(state.brown + _noise() * 0.02, -1.0, 1.0)
	return 0.6 * state.brown


func _spool(t: float, len: float, _state: Dictionary) -> float:
	var k := t / len
	var f := lerpf(110.0, 880.0, k * k)
	return (0.25 + 0.2 * k) * sin(TAU * f * t) * (0.7 + 0.3 * sin(TAU * 7.0 * t))
