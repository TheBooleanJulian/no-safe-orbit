class_name SensorTrack
extends RefCounted
## What one ship's sensors know about another (spec §14 "Flight HUD":
## measured values vs estimates vs stale data).
##
## Inside the observer's sensor range (ShipSystems.sensor_range_m: its best
## working sensor mast, else eyeballs and backup optics at VISUAL_RANGE_M)
## the target is MEASURED every update. Out of range — or with the sensors
## down — the last measurement is kept and the position is dead-reckoned
## (an ESTIMATE); after STALE_AFTER_S it is shown as STALE and its
## confidence decays with CONFIDENCE_HALF_LIFE_S. A weapons LOCK needs a
## fresh measurement inside LOCK_RANGE_M.
##
## Stored relative to the observer, so local-frame rebases don't move it.

const STALE_AFTER_S := 2.0
const LOCK_RANGE_M := 10_000.0
const CONFIDENCE_HALF_LIFE_S := 15.0
## A SCAN (cargo and bounty estimate) needs the lock held this long with an
## active sensor mast; progress drains back if the lock drops first.
const SCAN_TIME_S := 4.0
## The estimate is off by up to this fraction either way.
const SCAN_ERROR := 0.15

## Ever seen (since this track began).
var detected: bool = false
## Measured this update.
var in_contact: bool = false
var locked: bool = false
## 0..1: 1 = close, fresh measurement; decays while out of contact.
var confidence: float = 0.0
var last_time: float = -INF
var detected_time: float = -INF
## At the last measurement: target position relative to the observer, and
## target velocity (local frame).
var last_relative: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO
## Scan: 0..1 progress, done, and its fixed error factor (1 ± SCAN_ERROR).
var scan_progress: float = 0.0
var scanned: bool = false
var scan_error: float = 1.0
## Set by the update that completed the scan.
var just_scanned: bool = false


static func range_of(observer: ShipState) -> float:
	return observer.systems.sensor_range_m() if observer.systems != null else ShipSystems.VISUAL_RANGE_M


## Measure if possible. Returns true the moment the target is first detected.
func update(observer: ShipState, target: ShipState, now: float, dt: float) -> bool:
	if observer == null or target == null:
		in_contact = false
		locked = false
		return false
	var range_m := range_of(observer)
	var d := observer.position.distance_to(target.position)
	in_contact = observer.is_active() and target.is_active() and d <= range_m
	var newly := false
	if in_contact:
		newly = not detected
		if newly:
			detected_time = now
		detected = true
		last_time = now
		last_relative = target.position - observer.position
		last_velocity = target.velocity
		confidence = clampf(1.0 - 0.6 * d / range_m, 0.2, 1.0)
		locked = d <= minf(range_m, LOCK_RANGE_M)
	else:
		locked = false
		confidence *= pow(0.5, dt / CONFIDENCE_HALF_LIFE_S)
	_update_scan(observer, target, dt)
	return newly


func _update_scan(observer: ShipState, target: ShipState, dt: float) -> void:
	just_scanned = false
	if scanned:
		return
	if locked and has_active_sensors(observer):
		# A bigger bridge works the sensors faster.
		scan_progress = minf(scan_progress + dt * maxf(observer.systems.room_bonus(&"command"), 1.0) / SCAN_TIME_S, 1.0)
		if scan_progress >= 1.0:
			scanned = true
			just_scanned = true
			# Deterministic per contact: the same scan always reads the same.
			var h := absi(hash(String(target.id) + target.display_name))
			scan_error = 1.0 - SCAN_ERROR + 2.0 * SCAN_ERROR * float(h % 1000) / 999.0
	else:
		scan_progress = maxf(scan_progress - dt / SCAN_TIME_S, 0.0)


## A working sensor mast (not just eyeballs): needed to scan.
static func has_active_sensors(observer: ShipState) -> bool:
	return observer.systems != null and observer.systems.sensor_range_m() > ShipSystems.VISUAL_RANGE_M


func age(now: float) -> float:
	return now - last_time


func stale(now: float) -> bool:
	return detected and age(now) > STALE_AFTER_S


## Best guess of where the target is now (local frame): measured, or
## dead-reckoned from the last measurement.
func estimated_position(observer: ShipState, now: float) -> Vector3:
	return observer.position + last_relative + (last_velocity - observer.velocity) * maxf(age(now), 0.0)


## "MEAS", "EST" or "STALE" for labelling values.
func quality(now: float) -> String:
	if not detected:
		return "NONE"
	if in_contact:
		return "MEAS"
	return "STALE" if stale(now) else "EST"
