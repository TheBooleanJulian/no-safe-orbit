class_name GameLog
extends RefCounted
## Minimal categorised logging. Output goes to stdout and Godot's log file
## (debug/file_logging is enabled in project.godot: user://logs/godot.log).


static func info(category: String, message: String) -> void:
	print("[INFO][%s] %s" % [category, message])


static func warn(category: String, message: String) -> void:
	push_warning("[%s] %s" % [category, message])


static func error(category: String, message: String) -> void:
	push_error("[%s] %s" % [category, message])
