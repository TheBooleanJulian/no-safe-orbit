class_name Encounter
extends RefCounted
## The contact registry: every ship in the current encounter by stable id,
## and which one is selected — the one the target card, the lead marker,
## missiles, salvage, the gangway and boarding work on. The others are
## listed compactly on the HUD; the radar and the tactical overview show all.

var contacts: Array[Contact] = []
## The selected contact's id (&"" when there is none).
var selected: StringName = &""


func add(c: Contact) -> void:
	contacts.append(c)
	if selected == &"":
		selected = c.id


func remove(id: StringName) -> void:
	contacts = contacts.filter(func(c: Contact) -> bool: return c.id != id)
	if selected == id:
		selected = contacts[0].id if not contacts.is_empty() else &""


func get_contact(id: StringName) -> Contact:
	for c in contacts:
		if c.id == id:
			return c
	return null


func has(id: StringName) -> bool:
	return get_contact(id) != null


func selected_contact() -> Contact:
	return get_contact(selected)


## Contacts whose ships are still in the fight (in id order).
func live(world: WorldSimulation) -> Array[Contact]:
	var out: Array[Contact] = []
	for c in contacts:
		var s := world.get_ship(c.id)
		if s != null and s.is_active():
			out.append(c)
	return out


## Select a contact by id; false if it isn't in the encounter.
func select(id: StringName) -> bool:
	if not has(id):
		return false
	selected = id
	return true


## The next live contact after the selected one (wrapping), selected.
func cycle(world: WorldSimulation, step: int = 1) -> StringName:
	var ids: Array[StringName] = []
	for c in live(world):
		ids.append(c.id)
	if ids.is_empty():
		return selected
	var i := ids.find(selected)
	selected = ids[posmod(i + step, ids.size())] if i >= 0 else ids[0]
	return selected


## Keep a live contact selected (the selected one may have been retired).
func ensure_selection(world: WorldSimulation) -> void:
	var c := selected_contact()
	if c != null:
		var s := world.get_ship(c.id)
		if s != null and s.is_active():
			return
	var alive := live(world)
	if not alive.is_empty():
		selected = alive[0].id
	elif not contacts.is_empty():
		selected = contacts[0].id
	else:
		selected = &""


## Any contact hostile and still in the fight?
func any_hostile(world: WorldSimulation) -> bool:
	for c in live(world):
		if c.hostile:
			return true
	return false
