extends Node
## tests/net_unit.tscn: the single-process sandboxes of the multiplayer phases F2, F4 and F5, run as child Godot
## processes with their failures propagated to the exit code. No socket and no Bun are involved (the two-process
## scenarios over the relay are in tests/net_test.tscn).
##
## Why a separate suite and not tests/unit_tests.tscn: those sandboxes are whole scenes (they build a host hunt
## and a client hunt, run with --fixed-fps 60, tick for many simulated seconds and call get_tree().quit()
## themselves), so each needs its own process; unit_tests runs every test in one process under a 60 s watchdog.
## The pure-logic parts live in tests/unit (test_coop.gd, test_economy.gd, test_net.gd) and run there.
##
## Sandbox          what it proves                                                                  summary line
##   net_roles      host and client hunts with a synthetic roster: roles, joins/leaves, state feed   RESULT:
##   net_boars      replication: flora layout, puppets, interpolation, real weapon -> C_SHOT -> kill  RESULT:
##   net_flow       crop mirror, bait, thermal, drone, end of hunt, drops, economy, scoreboard        RESULT:
##   hud_net        shot ids with the local slot, hit marker ignores allies, ally kill message        RESULT:
##   link_selftest  NetLink over NetLoopback: loss, reordering, RTC promotion/downgrade, relay rate   LINK_SELFTEST
##   spectator      F6: allies on minimap/compass, SpectatorCamera, "Assistindo" banner, solo untouched  RESULT:
##   remote_hunter  RemoteHunter over the byte path of the network (wall clock, no --fixed-fps)        remote_sandbox:
## A child that exits without its summary line (crash, parse error, hang killed by the limit) is a FAIL.
##
## Run: tools/godot.sh --headless --path . res://tests/net_unit.tscn [-- --only=net_flow,link_selftest]

const TestCase := preload("res://tests/lib/test_case.gd")
const ChildRunner := preload("res://tests/lib/child_runner.gd")

const ONLY_ARG: String = "--only="
const WATCHDOG_SLACK_S: float = 30.0
const FIXED_FPS: Array = ["--fixed-fps", "60"]
## "limit_s" is the per-sandbox limit (the slowest measured run is about 11 s); the watchdog of the suite is the
## sum of the selected limits plus WATCHDOG_SLACK_S.
## "wall_clock": true = run WITHOUT --fixed-fps (the sandbox compares against the wall clock: RemoteHunter
## interpolates by Time.get_ticks_msec(), which a fixed-fps headless run outruns).
const SANDBOXES: Array[Dictionary] = [
	{"name": "net_roles", "scene": "res://src/hunt/debug/net_roles_test.tscn", "limit_s": 120.0},
	{"name": "net_boars", "scene": "res://src/hunt/debug/net_boars_test.tscn", "limit_s": 120.0},
	{"name": "net_flow", "scene": "res://src/hunt/debug/net_flow_test.tscn", "limit_s": 120.0},
	{"name": "hud_net", "scene": "res://src/hud/debug/hud_net_test.tscn", "limit_s": 90.0},
	{"name": "link_selftest", "scene": "res://src/net/debug/link_selftest.tscn", "limit_s": 90.0},
	{"name": "spectator", "scene": "res://src/player/debug/spectator_sandbox.tscn", "limit_s": 90.0},
	{"name": "remote_hunter", "scene": "res://src/player/debug/remote_sandbox.tscn", "limit_s": 60.0, "wall_clock": true},
]

var _totals: Dictionary = {}
var _start_ms: int = 0
var _finished: bool = false
var _watchdog_s: float = 0.0
var _runner: ChildRunner = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	_totals = TestCase.new_totals()
	_runner = ChildRunner.new(self)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _finished and _watchdog_s > 0.0 and float(Time.get_ticks_msec() - _start_ms) / 1000.0 > _watchdog_s:
		_finished = true
		print("FAIL watchdog: net_unit excedeu %d s" % int(_watchdog_s))
		_totals["fail"] = int(_totals["fail"]) + 1
		_quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _runner != null:
			_runner.kill()


func _quit() -> void:
	_runner.kill()
	_runner.cleanup_logs()
	get_tree().quit(TestCase.finish(_totals))


func _abort_requested() -> bool:
	return _finished


func _run() -> void:
	var list: Array[Dictionary] = []
	var spec: String = ChildRunner.user_arg(ONLY_ARG)
	if spec == "":
		list.assign(SANDBOXES)
	else:
		var wanted: PackedStringArray = spec.split(",", false)
		var names: PackedStringArray = PackedStringArray()
		for s: Dictionary in SANDBOXES:
			names.append(str(s["name"]))
			if str(s["name"]) in wanted:
				list.append(s)
		var unknown: Array[String] = []
		for w: String in wanted:
			if not names.has(w):
				unknown.append(w)
		if not unknown.is_empty() or list.is_empty():
			TestCase.report("FAIL", "net_unit::--only", ["nome(s) desconhecido(s): %s (validos: %s)" % [str(unknown), ", ".join(names)]], _totals)
			_finished = true
			_quit()
			return
	_watchdog_s = WATCHDOG_SLACK_S
	for s: Dictionary in list:
		_watchdog_s += float(s["limit_s"])
	for s: Dictionary in list:
		if _finished:
			return
		await _run_sandbox(s)
	if not _finished:
		_finished = true
		print("net_unit: tempo total %.1f s" % (float(Time.get_ticks_msec() - _start_ms) / 1000.0))
		_quit()


func _run_sandbox(sandbox: Dictionary) -> void:
	var label: String = "net_unit::%s" % sandbox["name"]
	var engine_args: Array = [] if bool(sandbox.get("wall_clock", false)) else FIXED_FPS
	var r: Dictionary = await _runner.run(sandbox["scene"], str(sandbox["name"]), engine_args, [],
		float(sandbox["limit_s"]), _abort_requested)
	if bool(r["aborted"]):
		return
	var detail: Array = ChildRunner.problems(r, "RESULT: N passed ... / LINK_SELFTEST checks= / remote_sandbox: PASS")
	if detail.is_empty():
		TestCase.report("PASS", "%s (%d verificacoes, %.1f s)" % [label, int(r["checks"]), float(r["secs"])], [], _totals)
	else:
		TestCase.report("FAIL", label, detail, _totals)
