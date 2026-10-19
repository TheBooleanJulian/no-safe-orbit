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
	for entry in plan:
		for k in mini(entry[1], berths - roster.members.size()):
			roster._add(entry[0], _station(bp, grid, entry[2], k))
	var n := 0
	while roster.members.size() < berths:
		roster._add(Role.GENERAL, _station(bp, grid, [&"quarters", &"access", &"command"], n))
		n += 1
	return roster


## k-th station among the rooms of the first role in `roles` that exists
## (spreading a role over several such rooms); the first room otherwise.
static func _station(bp: ShipBlueprint, grid: ShipGrid, roles: Array, k: int) -> int:
	for role in roles:
		var rooms: Array[int] = []
		for i in bp.rooms.size():
			var def: RoomDefinition = grid.catalog.rooms.get(bp.rooms[i].def_id)
			if def != null and def.role == role:
				rooms.append(i)
		if not rooms.is_empty():
			return rooms[k % rooms.size()]
	return 0


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
