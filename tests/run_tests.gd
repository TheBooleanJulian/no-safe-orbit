extends SceneTree
## Headless unit-test runner.
##   godot --headless --path . -s res://tests/run_tests.gd
## Exit code 0 = all passed, 1 = at least one failure or load error.

const TEST_DIRS: Array[String] = ["res://tests/unit"]


func _initialize() -> void:
	var total := 0
	var failed := 0
	var load_errors := 0
	for dir_path in TEST_DIRS:
		for file_name in _test_files(dir_path):
			var path := dir_path.path_join(file_name)
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate():
				print("LOAD ERROR  %s" % path)
				load_errors += 1
				continue
			var suite: TestCase = script.new()
			print("\n== %s" % file_name)
			for method in suite.get_method_list():
				var name: String = method["name"]
				if not name.begins_with("test_"):
					continue
				total += 1
				suite.begin_test()
				suite.call(name)
				var problems := suite.failures()
				if problems.is_empty():
					print("  PASS  %s" % name)
				else:
					failed += 1
					print("  FAIL  %s" % name)
					for p in problems:
						print("        - %s" % p)
	print("\n%d tests, %d passed, %d failed, %d load errors" % [total, total - failed, failed, load_errors])
	quit(1 if failed > 0 or load_errors > 0 or total == 0 else 0)


func _test_files(dir_path: String) -> PackedStringArray:
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(dir_path):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	return files
