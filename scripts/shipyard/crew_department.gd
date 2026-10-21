class_name CrewDepartment
extends PanelContainer
## A department on the crew manifest (play-test batches 9 and 11): drop a
## crew badge here to post that crew member to this role (a resting one
## comes aboard to it). `role` -1 is Resting crew: dropping an aboard badge
## there sends them ashore.

signal crew_dropped(index: int, role: int)
signal resting_dropped(index: int, role: int)

var role := 0


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and (data as Dictionary).has("crew_index")):
		return false
	# Resting crew onto Resting crew: nothing to do.
	return not (role < 0 and bool((data as Dictionary).get("resting", false)))


func _drop_data(_at: Vector2, data: Variant) -> void:
	var d := data as Dictionary
	if bool(d.get("resting", false)):
		resting_dropped.emit(int(d.crew_index), role)
	else:
		crew_dropped.emit(int(d.crew_index), role)
