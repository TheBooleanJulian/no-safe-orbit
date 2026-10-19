class_name BoardingAction
extends RefCounted
## Abstract boarding (spec §9): a team crosses a sealed gangway and fights
## room by room through the target's access graph towards its bridge. No
## teleporting, no instant kills; everything takes simulated time.
##
## - Muster: the team walks from their stations to our collar's room
##   (CrewRoster.ROOM_TRANSIT_S per room), then crosses (GANGWAY_CROSS_S).
## - Defenders' policy, stated plainly: security crew fall back to hold the
##   bridge (walking there takes time; a vented route stops them); everyone
##   else fights where they stand; doors ahead of the boarders are locked.
## - Moving on: one room at a time towards the bridge. A locked (intact)
##   hatch takes HATCH_CUT_S to cut; a hatch already destroyed is open.
## - Fighting: while both sides are in a room, each side loses KILL_RATE ×
##   the other side's strength in hit points per second (Lanchester's square
##   law). Strength = Σ CrewRoster.COMBAT_STRENGTH by role; defenders on
##   their own ship × DEFENDER_BONUS. A person at 0 hit points is out:
##   alternately wounded and killed. Numbers, roles, where the defenders are
##   and how far the boarders must go decide it — no room kills outright.
## - Capture: boarders hold the bridge with no fit defender in it → the
##   target surrenders (`prize`) and the team withdraws on its own. Withdraw:
##   walk back and cross home — only while the gangway is sealed; otherwise
##   the team is stranded.

enum Phase { MUSTER, CROSSING, ABOARD, WITHDRAWING, CAPTURED, REPELLED, STRANDED, RETURNED, ABORTED }

const PHASE_NAMES := ["mustering", "crossing", "aboard", "withdrawing", "CAPTURED", "REPELLED", "STRANDED", "returned", "aborted"]
const GANGWAY_CROSS_S := 5.0
const HATCH_CUT_S := 20.0
const KILL_RATE := 0.08
const DEFENDER_BONUS := 1.25
const MAX_TEAM := 8
const LOG_LIMIT := 12

var link: DockingLink
var attacker: ShipSystems
var defender: ShipSystems
var team: Array[CrewRoster.Member] = []
var phase: Phase = Phase.MUSTER
## Target room the team is in (-1 = not aboard).
var room: int = -1
var objective: int = -1
var elapsed: float = 0.0
## Current action: &"" (none), &"move", &"cut", &"cross".
var action: StringName = &""
var action_left: float = 0.0
var next_room: int = -1
var log: PackedStringArray = PackedStringArray()
## Lines ever written to `log` (it keeps only the last LOG_LIMIT).
var log_count: int = 0
## Target rooms the boarders have cleared and hold (room index -> true).
var captured_rooms: Dictionary = {}
## The target surrendered to this boarding (the team then comes home).
var prize: bool = false

var _locked: Dictionary = {}  # hatch id -> true: locked by defenders
var _cut: Dictionary = {}     # hatch id -> true: cut open by the boarders
var _hp: Dictionary = {}      # member id (prefixed a:/d:) -> hit points left
var _arrive_in: Dictionary = {}  # defender member id -> seconds until in position
var _casualties: int = 0


## Start a boarding over a sealed link. Returns null if nobody can go.
static func start(p_link: DockingLink, p_attacker: ShipSystems, p_defender: ShipSystems, max_team: int = MAX_TEAM) -> BoardingAction:
	if p_link == null or not p_link.sealed() or p_attacker.crew == null:
		return null
	var b := BoardingAction.new()
	b.link = p_link
	b.attacker = p_attacker
	b.defender = p_defender
	b.objective = p_defender.command_room()
	var muster := 0.0
	for role in [CrewRoster.Role.SECURITY, CrewRoster.Role.GENERAL]:
		for m in p_attacker.crew.members:
			if b.team.size() >= mini(max_team, MAX_TEAM) or m.role != role or not m.available():
				continue
			var path := p_attacker.route(m.location, p_link.a_port.room)
			if path.is_empty():
				continue
			b.team.append(m)
			m.busy = true
			muster = maxf(muster, (path.size() - 1) * CrewRoster.ROOM_TRANSIT_S)
	if b.team.is_empty():
		return null
	b.action = &"muster"
	b.action_left = muster
	b._rally_defenders()
	b._note("Boarding party of %d mustering at %s (%.0f s)" % [b.team.size(), p_attacker.blueprint.rooms[p_link.a_port.room].id, muster])
	return b


func finished() -> bool:
	return phase >= Phase.CAPTURED


func fit_team() -> Array[CrewRoster.Member]:
	return team.filter(func(m: CrewRoster.Member) -> bool: return m.fit())


## Defenders able to fight in `r` right now.
func defenders_in(r: int) -> Array[CrewRoster.Member]:
	var out: Array[CrewRoster.Member] = []
	if defender.crew == null:
		return out
	for m in defender.crew.in_room(r):
		if _arrive_in.get(m.id, 0.0) <= 0.0:
			out.append(m)
	return out


func strength(members: Array[CrewRoster.Member]) -> float:
	var s := 0.0
	for m in members:
		s += CrewRoster.COMBAT_STRENGTH[m.role]
	return s


## Control of each target room, for the boarding overlays: room index ->
## &"held" (cleared by the boarders), &"contested" (fighting now) or
## &"defended" (fit defenders there). Rooms nobody holds are left out.
func room_control() -> Dictionary:
	var out := {}
	for i in defender.blueprint.rooms.size():
		var defenders := defenders_in(i)
		if i == room and not defenders.is_empty() and not fit_team().is_empty():
			out[i] = &"contested"
		elif captured_rooms.has(i) and (defenders.is_empty() or defender.captured):
			out[i] = &"held"
		elif not defenders.is_empty():
			out[i] = &"defended"
	if prize:
		for i in defender.blueprint.rooms.size():
			out[i] = &"held"
	return out


## Order the team home.
func withdraw() -> void:
	if phase == Phase.ABOARD:
		phase = Phase.WITHDRAWING
		action = &""
		_note("Withdrawing")
	elif phase == Phase.MUSTER or phase == Phase.CROSSING:
		_end(Phase.ABORTED, "Boarding called off")


## The team comes home with the prize (after a capture).
func bring_home() -> void:
	for m in team:
		m.busy = false
		m.location = m.station if m.state != CrewRoster.State.DEAD else -1


func step(dt: float) -> void:
	if finished():
		return
	elapsed += dt
	for id in _arrive_in:
		_arrive_in[id] = maxf(float(_arrive_in[id]) - dt, 0.0)
	if fit_team().is_empty() and room >= 0:
		_end(Phase.REPELLED, "Boarding party lost")
		return
	match phase:
		Phase.MUSTER, Phase.CROSSING:
			if not link.sealed():
				_end(Phase.ABORTED, "Gangway lost before crossing: boarding called off")
				return
			action_left -= dt
			if action_left > 0.0:
				return
			if phase == Phase.MUSTER:
				phase = Phase.CROSSING
				action_left = GANGWAY_CROSS_S
				for m in team:
					m.location = -1
				_note("Crossing the gangway")
			else:
				phase = Phase.ABOARD
				room = link.b_port.room
				action = &""
				_lock_ahead()
				_note("Aboard: %s" % _room_name(room))
		Phase.ABOARD:
			if _fight(dt):
				return
			captured_rooms[room] = true
			if room == objective:
				_capture()
				return
			_advance(dt, objective)
		Phase.WITHDRAWING:
			if _fight(dt):
				return
			if room == link.b_port.room:
				if not link.sealed():
					_end(Phase.STRANDED, "Stranded: the gangway is gone and there is no way home")
					return
				if action != &"cross":
					action = &"cross"
					action_left = GANGWAY_CROSS_S
				action_left -= dt
				if action_left <= 0.0:
					for m in team:
						if m.state != CrewRoster.State.DEAD:
							m.location = link.a_port.room
						m.busy = false
					_end(Phase.RETURNED, "Boarding party back aboard")
				return
			_advance(dt, link.b_port.room)


# --- Internals ---------------------------------------------------------------------

func _advance(dt: float, goal: int) -> void:
	if action == &"":
		var path := defender.route(room, goal, true)
		if path.size() < 2:
			if phase == Phase.ABOARD:
				_note("No way on to the bridge")
			return
		next_room = path[1]
		var hatch := defender.hatch_between_rooms(room, next_room)
		var locked := _locked.has(hatch) and not _cut.has(hatch) and not defender.destroyed_hatches.has(hatch)
		action = &"cut" if locked else &"move"
		action_left = (HATCH_CUT_S if locked else 0.0) + CrewRoster.ROOM_TRANSIT_S
		if locked:
			_note("Cutting through locked hatch %s" % hatch)
		return
	action_left -= dt
	if action_left > 0.0:
		return
	if action == &"cut":
		_cut[defender.hatch_between_rooms(room, next_room)] = true
	room = next_room
	action = &""
	_note("Into %s" % _room_name(room))
	if phase == Phase.ABOARD:
		_lock_ahead()


## Resolve combat in the team's room for one tick. True while fighting.
func _fight(dt: float) -> bool:
	var ours := fit_team()
	var theirs := defenders_in(room)
	if theirs.is_empty() or ours.is_empty():
		return false
	if action == &"move" or action == &"cut":
		action = &""  # interrupted
	var to_them := KILL_RATE * strength(ours) * dt
	var to_us := KILL_RATE * strength(theirs) * DEFENDER_BONUS * dt
	_hurt("d:", theirs, to_them)
	_hurt("a:", ours, to_us)
	if defenders_in(room).is_empty():
		_note("%s cleared" % _room_name(room))
	return true


func _hurt(side: String, members: Array[CrewRoster.Member], amount: float) -> void:
	var m: CrewRoster.Member = members[0]
	var key := side + m.id
	_hp[key] = float(_hp.get(key, 1.0)) - amount
	if _hp[key] > 0.0:
		return
	m.state = CrewRoster.State.WOUNDED if _casualties % 2 == 0 else CrewRoster.State.DEAD
	_casualties += 1
	var whose := "Boarder" if side == "a:" else "Defender"
	_note("%s %s (%s) %s in %s" % [whose, m.id, CrewRoster.ROLE_NAMES[m.role],
		"wounded" if m.state == CrewRoster.State.WOUNDED else "killed", _room_name(room)])
	(defender if side == "d:" else attacker).invalidate()  # crew-dependent effects (command, guns)


## Defenders lock every intact door out of the room the boarders hold.
func _lock_ahead() -> void:
	for h in defender.blueprint.hatches:
		var ra: int = defender.grid.room_at.get(h.a, -1)
		var rb: int = defender.grid.room_at.get(h.b, -1)
		if (ra == room or rb == room) and not defender.destroyed_hatches.has(h.id) and not _cut.has(h.id):
			_locked[h.id] = true


## Security fall back to the bridge; it takes them the walk to get there.
func _rally_defenders() -> void:
	if defender.crew == null or objective < 0:
		return
	for m in defender.crew.members:
		if m.role != CrewRoster.Role.SECURITY or not m.fit() or m.location == objective:
			continue
		var path := defender.route(m.location, objective)
		if path.is_empty():
			continue
		m.location = objective
		_arrive_in[m.id] = (path.size() - 1) * CrewRoster.ROOM_TRANSIT_S


func _capture() -> void:
	defender.captured = true
	defender.invalidate()
	prize = true
	_note("Bridge taken — %s surrenders; boarding party withdrawing" % defender.blueprint.name)
	phase = Phase.WITHDRAWING
	action = &""


func _end(p: Phase, text: String) -> void:
	phase = p
	action = &""
	if p == Phase.ABORTED:
		for m in team:
			m.busy = false
			if m.location < 0 and m.state != CrewRoster.State.DEAD:
				m.location = link.a_port.room
	elif p == Phase.REPELLED:
		for m in team:
			if m.state == CrewRoster.State.WOUNDED:
				m.state = CrewRoster.State.DEAD  # left behind: lost
	_note(text)


func _room_name(r: int) -> String:
	return "%s %s" % [defender._room_name(r), defender.blueprint.rooms[r].id] if r >= 0 else "gangway"


func _note(text: String) -> void:
	log.append("T+%.0f s  %s" % [elapsed, text])
	log_count += 1
	if log.size() > LOG_LIMIT:
		log.remove_at(0)
