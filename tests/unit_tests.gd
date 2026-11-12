extends Node
## tests/unit_tests.tscn: runs every tests/unit/test_*.gd (methods named test_*; docs/arquitetura.md section 12).
##
## Run: tools/godot.sh --headless --path . res://tests/unit_tests.tscn [-- --strict]

const TestCase := preload("res://tests/lib/test_case.gd")

const WATCHDOG_S: float = 60.0
const UNIT_DIR: String = "res://tests/unit"

var _totals: Dictionary = {}
var _strict: bool = false
var _start_ms: int = 0
var _finished: bool = false


func _ready() -> void:
	_strict = "--strict" in OS.get_cmdline_user_args()
	_start_ms = Time.get_ticks_msec()
	TestCase.install_catcher()
	_totals = TestCase.new_totals()
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _finished and float(Time.get_ticks_msec() - _start_ms) / 1000.0 > WATCHDOG_S:
		_finished = true
		print("FAIL watchdog: unit_tests excedeu %d s" % int(WATCHDOG_S))
		_totals["fail"] = int(_totals["fail"]) + 1
		_quit()


func _quit() -> void:
	Engine.time_scale = 1.0
	var code: int = TestCase.finish(_totals)
	TestCase.remove_catcher()
	get_tree().quit(code)


func _run() -> void:
	await get_tree().process_frame
	var scripts: Array[String] = TestCase.list_scripts(UNIT_DIR, "test_")
	if scripts.is_empty():
		print("FAIL nenhum tests/unit/test_*.gd encontrado")
		_totals["fail"] = int(_totals["fail"]) + 1
	for path: String in scripts:
		if _finished:
			return
		await TestCase.run_script(path, self, _strict, _totals)
	var cleaner: RefCounted = TestCase.new()
	cleaner.call("cleanup_test_files")
	if not _finished:
		_finished = true
		_quit()
