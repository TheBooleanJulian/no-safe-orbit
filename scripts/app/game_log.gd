class_name GameLog
extends RefCounted
## Minimal categorised logging. Output goes to stdout and Godot's log file
## (debug/file_logging is enabled in project.godot: user://logs/godot.log).


## While held (Main, during flight), info lines collect and go out in one
## print per frame: a debug build flushes stdout on every print, and through
## a pipe (the editor's output, a terminal) a flush can take milliseconds —
## a missile salvo logs dozens of lines in one frame.
static var _held := false
static var _pending := PackedStringArray()


static func info(category: String, message: String) -> void:
	var line := "[INFO][%s] %s" % [category, message]
	if _held:
		_pending.append(line)
	else:
		print(line)


## Start or stop collecting info lines (stopping prints what is held).
static func hold(on: bool) -> void:
	_held = on
	if not on:
		flush()


static func flush() -> void:
	if not _pending.is_empty():
		print("\n".join(_pending))
		_pending.clear()


static func warn(category: String, message: String) -> void:
	push_warning("[%s] %s" % [category, message])


static func error(category: String, message: String) -> void:
	push_error("[%s] %s" % [category, message])
