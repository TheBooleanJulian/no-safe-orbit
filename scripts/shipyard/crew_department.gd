class_name CrewDepartment
extends PanelContainer
## A department on the crew quarters board (play-test batch 9): drop a
## crew badge here to post that crew member to this role.

signal crew_dropped(index: int, role: int)

var role := 0


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("crew_index")


func _drop_data(_at: Vector2, data: Variant) -> void:
	crew_dropped.emit(int((data as Dictionary).crew_index), role)
