extends Node
## Fixture of tests/unit/test_child_runner.gd: a child process that misbehaves on purpose.
##   -- --mode=fail       prints a failing "RESULT" line and exits 1
##   -- --mode=nosummary  prints a FAIL line and exits 0 without any summary (what a crash looks like)
##   -- --mode=pass       prints a green "RESULT" line and exits 0
## Not part of the game.


func _ready() -> void:
	var mode: String = "pass"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
	match mode:
		"fail":
			print("PASS first check")
			print("FAIL second check: expected 1, got 2")
			print("RESULT: 1 passed, 1 failed, 0 skipped")
			get_tree().quit(1)
		"nosummary":
			print("FAIL the child never got to the summary")
			get_tree().quit(0)
		_:
			print("PASS only check")
			print("RESULT: 1 passed, 0 failed, 0 skipped")
			get_tree().quit(0)
