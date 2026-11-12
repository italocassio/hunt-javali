extends SceneTree
## Quick parser check while tests/check_scripts.tscn does not exist yet.
## Loads every .gd and .tscn under the given folders and reports what fails to load.
##
## Usage (from the project root):
##   tools/godot.sh --headless --path . -s res://tools/check_parse.gd
##   tools/godot.sh --headless --path . -s res://tools/check_parse.gd -- --only=res://src/player,res://src/weapons
##
## Run `tools/godot.sh --headless --path . --import` first when you added a script with class_name.

const DEFAULT_ROOTS: PackedStringArray = ["res://src", "res://assets", "res://tests"]

var _failed: int = 0
var _checked: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var roots := DEFAULT_ROOTS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			roots = PackedStringArray(arg.trim_prefix("--only=").split(",", false))

	var files := PackedStringArray()
	for root_path in roots:
		_scan(root_path, files)

	for path in files:
		_checked += 1
		if path.ends_with(".gd"):
			var script := ResourceLoader.load(path) as GDScript
			if script == null or not script.can_instantiate():
				_fail(path, "script does not compile")
		else:
			var scene := ResourceLoader.load(path) as PackedScene
			if scene == null:
				_fail(path, "scene does not load")

	print("RESULT: %d checked, %d failed" % [_checked, _failed])
	quit(0 if _failed == 0 else 1)


func _fail(path: String, reason: String) -> void:
	_failed += 1
	print("FAIL %s: %s" % [path, reason])


func _scan(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.ends_with(".gd") or file_name.ends_with(".tscn"):
			out.append(dir_path.path_join(file_name))
