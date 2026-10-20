class_name CrewRoster
extends RefCounted
## Abstract crew (spec §8): every berth holds one person with a role, a
## station room and a current room. Nobody is rendered or walks; moving
## between rooms takes ROOM_TRANSIT_S per room along the access graph
## (rooms joined by hatches). Unsuited crew only pass through pressurised
## rooms.
##
## Default complement (fills berths in this order): 2 command on the bridge,
## 2 engineering, 1 weapons per gun (max 2) at the magazine, 2 damage control
## at a workshop (else a corridor), 1 medical, 4 security in quarters, the
## rest general crew in quarters.

enum Role { COMMAND, ENGINEERING, DAMAGE_CONTROL, WEAPONS, SECURITY, MEDICAL, GENERAL }
enum State { FIT, WOUNDED, DEAD }

const ROLE_NAMES := ["command", "engineering", "damage control", "weapons", "security", "medical", "general"]
## Close-quarters fighting strength by role: security are trained and armed.
const COMBAT_STRENGTH := [0.4, 0.4, 0.5, 0.4, 1.0, 0.2, 0.4]
## Abstract time to move through one room (s).
const ROOM_TRANSIT_S := 5.0
## Map dot colour per role (functional, like rarity colours): command gold,
## engineering orange, damage control violet, weapons red, security teal,
## medical green, general grey.
const ROLE_COLORS := [Color("f5c842"), Color("ff9a3c"), Color("b98cff"), Color("ff5a5a"), Color("00d4c8"),
	Color("6fe08a"), Color("aab4bc")]
const ROLE_SHORT := ["CMD", "ENG", "DC", "WPN", "SEC", "MED", "GEN"]


## The standard complement per role (as default_for fills berths), for a
## ship with `guns` guns: what the station suggests hiring towards.
static func suggested(guns: int) -> Array[int]:
	return [2, 2, 2, mini(guns, 2), 4, 1, 0]


## "● command ● engineering …" in BBCode, for map legends.
static func role_legend() -> String:
	var parts := PackedStringArray()
	for r in ROLE_NAMES.size():
		parts.append("[color=#%s]●[/color] %s" % [(ROLE_COLORS[r] as Color).to_html(false), ROLE_NAMES[r]])
	return "  ".join(parts)


class Member:
	var id: String
	var role: int
	## Room index the member returns to; -1 if the ship has no rooms.
	var station: int = -1
	## Room index now; -1 = off the ship (gangway, boarding party).
	var location: int = -1
	var state: int = State.FIT
	## Assigned to a task (repair, boarding) and not available elsewhere.
	var busy: bool = false
	## Hired crew have a name and a skill (0–2: each level works 20 % faster
	## at repairs and treatment); the standard complement has neither.
	var name: String = ""
	var skill: int = 0

	func label() -> String:
		return "%s (%s)" % [name, id] if name != "" else id

	func fit() -> bool:
		return state == State.FIT

	func available() -> bool:
		return state == State.FIT and not busy


var members: Array[Member] = []


static func default_for(bp: ShipBlueprint, grid: ShipGrid, stats: ShipStats) -> CrewRoster:
	var roster := CrewRoster.new()
	if bp.rooms.is_empty():
		return roster
	var guns := 0
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def != null and def.kind == EquipmentDefinition.Kind.CANNON:
			guns += 1
	var plan := [
		[Role.COMMAND, 2, [&"command"]],
		[Role.ENGINEERING, 2, [&"engineering"]],
		[Role.WEAPONS, mini(guns, 2), [&"magazine", &"command"]],
		[Role.DAMAGE_CONTROL, 2, [&"workshop", &"access"]],
		[Role.MEDICAL, 1, [&"life_support", &"quarters"]],
		[Role.SECURITY, 4, [&"quarters", &"access"]],
	]
	var berths := stats.crew_capacity
	_index = _rooms_by_role(bp, grid)
	for entry in plan:
		for k in mini(entry[1], berths - roster.members.size()):
			roster._add(entry[0], _station(bp, grid, entry[2], k))
	var n := 0
	while roster.members.size() < berths:
		roster._add(Role.GENERAL, _station(bp, grid, [&"quarters", &"access", &"command"], n))
		n += 1
	_index = {}
	return roster


## The vessel's own hired crew (ShipInstance.crew: [{name, role, skill}]),
## at most one per berth, at the stations the standard complement uses.
## Berths beyond the list stay empty.
static func from_plan(bp: ShipBlueprint, grid: ShipGrid, stats: ShipStats, plan: Array) -> CrewRoster:
	var roster := CrewRoster.new()
	if bp.rooms.is_empty():
		return roster
	var per_role := {}
	_index = _rooms_by_role(bp, grid)
	for entry in plan.slice(0, stats.crew_capacity):
		var role := clampi(int(entry.get("role", Role.GENERAL)), 0, Role.size() - 1)
		var k: int = per_role.get(role, 0)
		per_role[role] = k + 1
		roster._add(role, _station(bp, grid, STATION_ROLES[role], k))
		var m := roster.members[-1]
		m.name = str(entry.get("name", ""))
		m.skill = clampi(int(entry.get("skill", 0)), 0, 2)
	_index = {}
	return roster


## Where each role is stationed (first room role found), as in default_for.
const STATION_ROLES := [[&"command"], [&"engineering"], [&"workshop", &"access"], [&"magazine", &"command"],
	[&"quarters", &"access"], [&"life_support", &"quarters"], [&"quarters", &"access", &"command"]]


## k-th station among the rooms of the first role in `roles` that exists
## (spreading a role over several such rooms); the first room otherwise.
## Uses the rooms-by-role index of the roster being built (_index_rooms);
## without one it scans the rooms (a capital hull has hundreds: indexing
## once makes a whole roster linear, not rooms × berths).
static func _station(bp: ShipBlueprint, grid: ShipGrid, roles: Array, k: int) -> int:
	var index := _index if not _index.is_empty() else _rooms_by_role(bp, grid)
	for role in roles:
		var rooms: Array = index.get(role, [])
		if not rooms.is_empty():
			return rooms[k % rooms.size()]
	return 0


## While a roster is built: room indices by room role.
static var _index: Dictionary = {}


static func _rooms_by_role(bp: ShipBlueprint, grid: ShipGrid) -> Dictionary:
	var out := {}
	for i in bp.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(bp.rooms[i].def_id)
		if def != null:
			(out.get_or_add(def.role, []) as Array).append(i)
	return out


func _add(role: int, station: int) -> void:
	var m := Member.new()
	m.id = "c%d" % (members.size() + 1)
	m.role = role
	m.station = station
	m.location = station
	members.append(m)


# --- Queries -------------------------------------------------------------------

func count(state: int = State.FIT) -> int:
	return members.filter(func(m: Member) -> bool: return m.state == state).size()


func in_room(room: int, fit_only: bool = true) -> Array[Member]:
	var out: Array[Member] = []
	for m in members:
		if m.location == room and m.state != State.DEAD and (m.fit() or not fit_only):
			out.append(m)
	return out


func by_id(id: String) -> Member:
	for m in members:
		if m.id == id:
			return m
	return null


func summary() -> String:
	return "%d/%d fit · %d wounded · %d dead" % [count(State.FIT), members.size(), count(State.WOUNDED), count(State.DEAD)]


# --- Casualties and persistence ----------------------------------------------------

## A room vented with people in it: half (rounded up) are wounded, the rest
## killed. Returns [killed, wounded].
func vent(room: int) -> Vector2i:
	var caught := in_room(room, false)
	var killed := 0
	var wounded := 0
	for i in caught.size():
		if i % 2 == 0 and caught[i].state == State.FIT:
			caught[i].state = State.WOUNDED
			wounded += 1
		else:
			caught[i].state = State.DEAD
			killed += 1
	return Vector2i(killed, wounded)


## Casualties by role name, for the vessel's saved condition ({} = none).
func casualties() -> Dictionary:
	var out := {}
	for state_key in [["dead", State.DEAD], ["wounded", State.WOUNDED]]:
		var by_role := {}
		for m in members:
			if m.state == state_key[1]:
				by_role[ROLE_NAMES[m.role]] = int(by_role.get(ROLE_NAMES[m.role], 0)) + 1
		if not by_role.is_empty():
			out[state_key[0]] = by_role
	return out


## Re-apply saved casualties: the first N of each role, in roster order.
func apply_casualties(c: Dictionary) -> void:
	for m in members:
		m.state = State.FIT
	for state_key in [["dead", State.DEAD], ["wounded", State.WOUNDED]]:
		var by_role: Dictionary = c.get(state_key[0], {})
		for role_name in by_role:
			var role := ROLE_NAMES.find(str(role_name))
			var left := int(by_role[role_name])
			for m in members:
				if left <= 0:
					break
				if m.role == role and m.state == State.FIT:
					m.state = state_key[1]
					left -= 1
