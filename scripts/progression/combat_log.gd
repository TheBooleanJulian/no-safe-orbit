class_name CombatLog
extends RefCounted
## One sortie's record, saved for the post-combat debrief so the player can
## see what hurt them and design a better ship: hits given and taken, which
## side the incoming rounds came from, what armour stopped, which systems
## were lost and how, crew losses, explosions, boarding, salvage and the
## outcome. Saved as JSON under user://debriefs/; rendered from the saved
## data so an old debrief reads the same.

const DIR := "user://debriefs"
const EVENT_LIMIT := 200
## Body-frame face a round came in through, from its direction of travel.
const SIDES := ["fore", "aft", "port", "starboard", "dorsal", "ventral"]

var ship_name: String = ""
var design: String = ""
var started_utc: String = ""
var sim_start: float = 0.0
var sim_end: float = 0.0
var events: Array[Dictionary] = []  # {t, kind, text}
var shots_fired: int = 0
var hits_scored: int = 0
var systems_destroyed: int = 0
var hits_taken: int = 0
var stopped_by_armor: int = 0
var hits_by_side: Dictionary = {}  # side -> count
var systems_lost: Array[Dictionary] = []  # {id, name, side, t}
var crew_lost: int = 0
var crew_wounded: int = 0
var explosions: int = 0
var dv_spent: float = 0.0
var outcome: String = ""
var aftermath: PackedStringArray = PackedStringArray()
var has_workshop: bool = false
## Loot gained this sortie: "Rare: Railgun (1 unit) — in the hold" etc.
var loot: PackedStringArray = PackedStringArray()
## Mission goals met or failed this sortie ("✔ …", "✕ …", "▲ … not met yet").
var objectives: PackedStringArray = PackedStringArray()
var missiles_launched: int = 0
## Our missiles that struck (their hits are not gun hits: accuracy is
## rounds only).
var missile_hits: int = 0
var missiles_inbound: int = 0


static func begin(ship: ShipState, sim_time: float) -> CombatLog:
	var log := CombatLog.new()
	log.ship_name = ship.display_name
	log.design = ship.config.display_name
	log.started_utc = Time.get_datetime_string_from_system(true)
	log.sim_start = sim_time
	if ship.systems != null:
		for i in ship.systems.blueprint.rooms.size():
			log.has_workshop = log.has_workshop or ship.systems.room_role(i) == &"workshop"
	return log


func record(t: float, kind: String, text: String) -> void:
	events.append({"t": t - sim_start, "kind": kind, "text": text})
	if events.size() > EVENT_LIMIT:
		events.remove_at(0)


## A hit event, either way. `world` resolves names of what was hit.
func note_hit(ev: HitEvent, player_id: StringName, t: float, world: WorldSimulation) -> void:
	if ev.report == null:
		return
	var r := ev.report
	if ev.shooter_id == player_id or String(ev.shooter_id).begins_with(String(player_id) + "_"):
		if ev.missile:
			missile_hits += 1
		else:
			hits_scored += 1
		systems_destroyed += r.destroyed_ids.size()
		var target := world.get_ship(ev.target_id)
		record(t, "hit", "%s %s: %s" % ["Missile hit" if ev.missile else "Hit", target.display_name if target != null else String(ev.target_id), r.headline()])
	elif ev.target_id == player_id:
		hits_taken += 1
		var side := side_of(r)
		hits_by_side[side] = int(hits_by_side.get(side, 0)) + 1
		if r.stopped_by_armor:
			stopped_by_armor += 1
		var me := world.get_ship(player_id)
		for id in r.destroyed_ids:
			var e := me.systems.equipment_by_id(id) if me != null and me.systems != null else null
			systems_lost.append({"id": id, "name": e.def.display_name if e != null else id, "side": side, "t": t - sim_start})
		record(t, "taken", "Hit from the %s: %s" % [side, r.headline()])


## Face a round entered through: opposite its direction of travel.
static func side_of(r: DamageReport) -> String:
	if r.path_body.size() < 2:
		return "unknown"
	var travel := r.path_body[1] - r.path_body[0]
	var from := -travel
	var a := from.abs()
	if a.z >= a.x and a.z >= a.y:
		return "fore" if from.z < 0.0 else "aft"
	if a.x >= a.y:
		return "port" if from.x < 0.0 else "starboard"
	return "ventral" if from.y < 0.0 else "dorsal"


func finish(ship: ShipState, p_outcome: String, t: float, p_aftermath: PackedStringArray = PackedStringArray()) -> void:
	sim_end = t
	outcome = p_outcome
	aftermath = p_aftermath
	shots_fired = ship.rounds_fired
	dv_spent = ship.delta_v_expended
	if ship.systems != null and ship.systems.crew != null:
		crew_lost = ship.systems.crew.count(CrewRoster.State.DEAD)
		crew_wounded = ship.systems.crew.count(CrewRoster.State.WOUNDED)
	record(t, "end", outcome)


func to_dict() -> Dictionary:
	return {
		"ship_name": ship_name, "design": design, "started_utc": started_utc,
		"duration_s": sim_end - sim_start, "outcome": outcome, "aftermath": Array(aftermath), "loot": Array(loot),
		"shots_fired": shots_fired, "hits_scored": hits_scored, "systems_destroyed": systems_destroyed,
		"hits_taken": hits_taken, "stopped_by_armor": stopped_by_armor, "hits_by_side": hits_by_side.duplicate(),
		"systems_lost": systems_lost.duplicate(true), "crew_lost": crew_lost, "crew_wounded": crew_wounded,
		"explosions": explosions, "dv_spent": dv_spent, "has_workshop": has_workshop, "events": events.duplicate(true),
		"objectives": Array(objectives), "missiles_launched": missiles_launched, "missiles_inbound": missiles_inbound,
		"missile_hits": missile_hits,
	}


## Writes the debrief; returns its path ("" on failure).
func save() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("sortie_%s_%d.json" % [started_utc.replace(":", "").replace("-", ""), Time.get_ticks_msec()])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(to_dict(), "\t", false))
	f.close()
	return path


# --- Reading a debrief -------------------------------------------------------------

## Lessons for the shipyard, from the record alone.
static func insights(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var taken := int(d.get("hits_taken", 0))
	var shots := int(d.get("shots_fired", 0))
	if shots > 0:
		var acc := 100.0 * int(d.get("hits_scored", 0)) / shots
		out.append("Accuracy %.0f %% (%d of %d rounds hit)%s." % [acc, int(d.get("hits_scored", 0)), shots,
			" — fire on the lead marker ◇, and close in: shorter flight time, smaller lead error" if acc < 25.0 else ""])
	if taken > 0:
		var sides: Dictionary = d.get("hits_by_side", {})
		var worst := ""
		for s in sides:
			if worst == "" or int(sides[s]) > int(sides[worst]):
				worst = s
		out.append("Most hits came in through the %s (%d of %d). Heavier armour or fewer critical systems on that side would help." % [worst, int(sides[worst]), taken])
		out.append("Armour stopped %d of %d incoming rounds at the outer plate." % [int(d.get("stopped_by_armor", 0)), taken])
	var critical := {"reactor": "Your reactor was destroyed (it explodes at 0 %): a second reactor on another module's network keeps power on, and moving it deeper puts more ship in front of it.",
		"engine": "Main engines were lost: spread them apart so one hit can't take several.",
		"cannon": "Your guns were knocked out: a second mount on another face keeps you firing."}
	var said := {}
	for lost in d.get("systems_lost", []):
		var name := str(lost.get("name", "")).to_lower()
		for key in critical:
			if name.contains(key) and not said.has(key):
				said[key] = true
				out.append("%s (%s, through the %s.)" % [critical[key], lost.get("id", ""), lost.get("side", "?")])
	if not (d.get("systems_lost", []) as Array).is_empty() and not d.get("has_workshop", false):
		out.append("No workshop aboard: a workshop room lets damage control patch damaged systems in flight.")
	if int(d.get("crew_lost", 0)) > 0:
		out.append("%d crew killed: rooms that vent kill whoever is inside — keep crew stations away from the outer hull and add hatches to seal compartments." % int(d.crew_lost))
	if out.is_empty():
		out.append("A quiet sortie — nothing to learn from but the view.")
	return out


## The sortie at a glance: the goal, what we did, what was done to us and
## what it cost — one line each, glyph first (■ fine, ▲ hurt, ✕ lost).
static func summary(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for line in d.get("objectives", []):
		out.append(str(line))
	var shots := int(d.get("shots_fired", 0))
	var hits := int(d.get("hits_scored", 0))
	var dealt := "■ DEALT  %d hit%s from %d rounds%s · %d enemy system%s destroyed" % [hits, "" if hits == 1 else "s", shots,
		" (%.0f %%)" % (100.0 * hits / shots) if shots > 0 else "", int(d.get("systems_destroyed", 0)),
		"" if int(d.get("systems_destroyed", 0)) == 1 else "s"]
	if int(d.get("missiles_launched", 0)) > 0:
		dealt += " · %d missile%s launched, %d struck" % [int(d.missiles_launched), "" if int(d.missiles_launched) == 1 else "s",
			int(d.get("missile_hits", 0))]
	out.append(dealt)
	var taken := int(d.get("hits_taken", 0))
	var lost: Array = d.get("systems_lost", [])
	var took := "%s TAKEN  %d hit%s · armour stopped %d" % [CyberTheme.GLYPH_OK if taken == 0 else CyberTheme.GLYPH_DEGRADED, taken,
		"" if taken == 1 else "s", int(d.get("stopped_by_armor", 0))]
	var sides: Dictionary = d.get("hits_by_side", {})
	var worst := ""
	for s in sides:
		if worst == "" or int(sides[s]) > int(sides[worst]):
			worst = s
	if worst != "":
		took += " · most through the %s" % worst
	if int(d.get("missiles_inbound", 0)) > 0:
		took += " · %d missile%s fired at us" % [int(d.missiles_inbound), "" if int(d.missiles_inbound) == 1 else "s"]
	out.append(took)
	if not lost.is_empty():
		var names := PackedStringArray()
		for l in lost:
			names.append("%s %s (%s)" % [l.get("name", "?"), l.get("id", ""), l.get("side", "?")])
		out.append("%s LOST  %s" % [CyberTheme.GLYPH_DESTROYED, ", ".join(names)])
	var dead := int(d.get("crew_lost", 0))
	var hurt := int(d.get("crew_wounded", 0))
	if dead + hurt > 0:
		out.append("%s CREW  %d killed · %d wounded (the wounded recover ashore)" % [CyberTheme.GLYPH_DESTROYED if dead > 0 else CyberTheme.GLYPH_DEGRADED, dead, hurt])
	return out


## BBCode for the debrief panels.
static func render(d: Dictionary) -> String:
	if d.is_empty():
		return "No sortie on record yet."
	var lines := PackedStringArray([
		"[b]DEBRIEF — %s[/b]  (%s)" % [d.get("ship_name", "?"), d.get("design", "?")],
		"%s · %s · Δv spent %.0f m/s" % [str(d.get("outcome", "")).to_upper(), HudFormat.clock(float(d.get("duration_s", 0.0))), float(d.get("dv_spent", 0.0))],
		"",
		"[b]SORTIE SUMMARY[/b]",
	])
	for line in summary(d):
		var color := CyberTheme.TEXT
		if line.begins_with("✔"):
			color = CyberTheme.CYAN
		elif line.begins_with(CyberTheme.GLYPH_DESTROYED):
			color = CyberTheme.RED
		elif line.begins_with(CyberTheme.GLYPH_DEGRADED):
			color = CyberTheme.AMBER
		lines.append(CyberTheme.tint(line, color))
	var sides: Dictionary = d.get("hits_by_side", {})
	if not sides.is_empty():
		var parts := PackedStringArray()
		for s in SIDES:
			if sides.has(s):
				parts.append("%s %d" % [s, int(sides[s])])
		lines.append("Incoming by side: " + " · ".join(parts))
	for line in d.get("aftermath", []):
		lines.append("» %s" % line)
	var gained: Array = d.get("loot", [])
	if not gained.is_empty():
		lines.append("")
		lines.append("[b]LOOT GAINED[/b]")
		for line in gained:
			lines.append("◆ %s" % line)
	lines.append("")
	lines.append("[b]LESSONS FOR THE SHIPYARD[/b]")
	for line in insights(d):
		lines.append("• " + line)
	lines.append("")
	lines.append("[b]LOG[/b]")
	for e in (d.get("events", []) as Array).slice(-25):
		lines.append("%s  %s" % [HudFormat.clock(float(e.get("t", 0.0))), e.get("text", "")])
	return "\n".join(lines)
