class_name HudFormat
extends RefCounted
## Pure string formatting for HUD readouts (unit-tested).


static func distance(metres: float) -> String:
	if absf(metres) < 1000.0:
		return "%d m" % roundi(metres)
	if absf(metres) < 100_000.0:
		return "%.2f km" % (metres / 1000.0)
	return "%.0f km" % (metres / 1000.0)


static func signed_speed(mps: float) -> String:
	return "%+.1f m/s" % mps


## "CLOSING" / "OPENING" / "STEADY" from a range rate (m/s).
static func closure(range_rate_mps: float) -> String:
	if range_rate_mps < -0.05:
		return "CLOSING"
	if range_rate_mps > 0.05:
		return "OPENING"
	return "STEADY"


static func clock(seconds: float) -> String:
	var s := int(floor(seconds))
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Countdown / interval: "m:ss" under an hour, "h:mm:ss" above; "—" if unknown.
static func duration(seconds: float) -> String:
	if is_nan(seconds) or is_inf(seconds) or seconds < 0.0:
		return "—"
	var s := int(floor(seconds))
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


## Altitude above the surface in km; "—" for unbounded values.
static func altitude(metres: float) -> String:
	if is_nan(metres) or is_inf(metres):
		return "—"
	return "%.1f km" % (metres / 1000.0)
