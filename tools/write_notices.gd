extends SceneTree
## Writes the credits and every licence (Credits.full_text) to a file that
## ships next to the executable. Usage:
##   godot --headless --path . -s res://tools/write_notices.gd -- <out file>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <out file>")
		quit(1)
		return
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % args[0])
		quit(1)
		return
	f.store_string(Credits.full_text())
	f.close()
	print("wrote ", args[0])
	quit()
