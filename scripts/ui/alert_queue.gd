class_name AlertQueue
extends RefCounted
## The HUD's alerts (Pass A): terse, prioritised, steady.
##
## Grammar: every alert is a short NOUN, at most one value, a direction
## where it has one and the key that acts on it, e.g. `MSL 2.1s 040↑ [SPC]`,
## `FIRE r12`, `SCRAM 1450K`; never more than MAX_TEXT characters.
##
## Queue: the HUD reports every condition each frame (`update`); the queue
## deduplicates by key, keeps an alert up for CLEAR_DELAY_S after its
## condition clears (no flicker), raises its level at once and lowers it
## only after DOWNGRADE_S, and shows at most MAX_VISIBLE — danger before
## caution before advisory, then by class (threat, damage, systems,
## navigation, information), newest first. A non-danger alert can be
## acknowledged ([.]): hidden until it clears or escalates. New and
## escalated alerts are listed in `raised` for their sound.

enum Level { ADVISORY, CAUTION, DANGER }
## Classes in priority order (each has its own alarm sound, ShipAudio.ALARMS).
const CLASSES: Array[StringName] = [&"threat", &"damage", &"systems", &"nav", &"info"]
const MAX_VISIBLE := 3
const MAX_TEXT := 26
const CLEAR_DELAY_S := 0.8
const DOWNGRADE_S := 1.0
const GLYPHS := ["●", "▲", "◆"]


class Alert:
	var key: StringName
	var cls: StringName = &"info"
	var level: int = Level.CAUTION
	var noun: String = ""
	var value: String = ""
	var dir: String = ""
	var chip: String = ""
	## System or room id it is about (the damage map flashes it).
	var subject: String = ""
	## Towards the threat, ship body frame (screen-edge indicator); zero = none.
	var dir_body := Vector3.ZERO
	## The value as the threat marker shows it (just "2.1s").
	var short: String = ""
	var since: float = 0.0
	var last_seen: float = 0.0
	var acked := false
	var _lower_since: float = -1.0

	## `NOUN value dir [KEY]`, cut to MAX_TEXT.
	func text() -> String:
		var parts := PackedStringArray()
		for s in [noun, value, dir, chip]:
			if s != "":
				parts.append(s)
		var t := " ".join(parts)
		return t if t.length() <= MAX_TEXT else t.substr(0, MAX_TEXT - 1) + "…"

	func glyph() -> String:
		return GLYPHS[clampi(level, 0, 2)]


static func make(key: StringName, cls: StringName, level: int, noun: String, value: String = "", dir: String = "",
		chip: String = "", subject: String = "") -> Alert:
	var a := Alert.new()
	a.key = key
	a.cls = cls
	a.level = level
	a.noun = noun
	a.value = value
	a.dir = dir
	a.chip = chip
	a.subject = subject
	return a


var _active: Dictionary = {}  # key -> Alert
## Alerts that appeared or escalated in the last update (to sound them).
var raised: Array[Alert] = []


## This frame's conditions (`raw`, any order, duplicates allowed) at `now`.
func update(raw: Array[Alert], now: float) -> void:
	raised.clear()
	var by_key := {}
	for a in raw:
		if not by_key.has(a.key) or a.level > (by_key[a.key] as Alert).level:
			by_key[a.key] = a
	for key: StringName in by_key:
		var a: Alert = by_key[key]
		var cur: Alert = _active.get(key)
		if cur == null:
			a.since = now
			a.last_seen = now
			_active[key] = a
			raised.append(a)
			continue
		cur.noun = a.noun
		cur.value = a.value
		cur.dir = a.dir
		cur.chip = a.chip
		cur.subject = a.subject
		cur.dir_body = a.dir_body
		cur.short = a.short
		cur.cls = a.cls
		cur.last_seen = now
		if a.level > cur.level:
			cur.level = a.level
			cur.acked = false
			cur._lower_since = -1.0
			raised.append(cur)
		elif a.level < cur.level:
			if cur._lower_since < 0.0:
				cur._lower_since = now
			elif now - cur._lower_since >= DOWNGRADE_S:
				cur.level = a.level
				cur._lower_since = -1.0
		else:
			cur._lower_since = -1.0
	for key: StringName in _active.keys():
		if not by_key.has(key) and now - (_active[key] as Alert).last_seen >= CLEAR_DELAY_S:
			_active.erase(key)


## What the HUD shows, most urgent first (at most MAX_VISIBLE).
func visible() -> Array[Alert]:
	var out := all_active().filter(func(a: Alert) -> bool: return not a.acked or a.level == Level.DANGER)
	var typed: Array[Alert] = []
	typed.assign(out.slice(0, MAX_VISIBLE))
	return typed


## Every active alert, most urgent first (acknowledged ones included).
func all_active() -> Array[Alert]:
	var out: Array[Alert] = []
	out.assign(_active.values())
	out.sort_custom(_more_urgent)
	return out


static func _more_urgent(a: Alert, b: Alert) -> bool:
	if a.level != b.level:
		return a.level > b.level
	var ca := CLASSES.find(a.cls)
	var cb := CLASSES.find(b.cls)
	if ca != cb:
		return ca < cb
	return a.since > b.since


## Acknowledge the most urgent shown non-danger alert; false if none.
func acknowledge() -> bool:
	for a in visible():
		if a.level < Level.DANGER:
			a.acked = true
			return true
	return false


func has(key: StringName) -> bool:
	return _active.has(key)


func clear() -> void:
	_active.clear()
	raised.clear()
