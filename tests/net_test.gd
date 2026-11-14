extends Node
## tests/net_test.tscn: multiplayer end-to-end suite over the real relay server (docs/multiplayer.md section 9,
## phases F2, F4 and F5). Every scenario runs in a child Godot process (see tests/lib/child_runner.gd) against
## the local Bun room server, and its "checks=N failures=M" summary becomes one "PASS/FAIL/SKIP" line plus the
## usual "RESULT: N passed, M failed, K skipped".
##
## Scenarios (short name -> orchestrator scene):
##   relay_normal      net_e2e: lobby -> room -> hunt_go -> walking -> remote hunter within 0.5 m, version mismatch,
##                     fifth peer and late join refused; the client leaves at the end and the host sees it
##   relay_host_drops  net_e2e --host-drops: the host process exits mid-hunt, the client ends DISCONNECTED
##   deadlines         net_e2e --deadlines (F5): stall warning, host_timeout_s, peer_timeout_s, load timeout,
##                     Net.flush, locked room, ping/pong, dead server
##   victory           net_hunt_e2e (N3): client and host bots split the boars -> VICTORY on both, same scoreboard
##   crop              net_hunt_e2e: the crop is drained -> DEFEAT_CROP on both, same eaten patches
##   death             net_hunt_e2e: the client dies (hunt goes on), then the host -> DEFEAT_DEATH on both
##   host_drop         net_hunt_e2e (N4): the host process dies -> client DISCONNECTED within host_timeout_s + 2 s
##   host_freeze       net_hunt_e2e (N4): the host stays up but its Net stops -> client DISCONNECTED by timeout
##   client_drop       net_hunt_e2e (N5): the client process dies -> the host sees hunter_left and wins alone
## Without Bun (PATH, $BUN, ~/.bun/bin or -- --bun=<path>) every selected scenario is reported as SKIP, explicitly.
## Exit code 1 if any scenario fails, times out or the child dies without its summary line.
##
## Run (all, ~6 min): tools/godot.sh --headless --path . res://tests/net_test.tscn
## Subset:              ... res://tests/net_test.tscn -- --only=victory,crop     (short names, or the groups
##                      "relay" and "hunt"; an unknown name is a FAIL, never a silent pass)
## Other user args:     --bun=<bun executable>

const TestCase := preload("res://tests/lib/test_case.gd")
const ChildRunner := preload("res://tests/lib/child_runner.gd")

const E2E_SCENE: String = "res://src/net/debug/net_e2e.tscn"
const HUNT_SCENE: String = "res://src/hunt/debug/net_hunt_e2e.tscn"
const ONLY_ARG: String = "--only="
const WATCHDOG_SLACK_S: float = 30.0
## "limit_s" is the per-scenario limit, about 2x the time measured on 2026-11-13 (full run: 353 s; relay_normal 15 s,
## relay_host_drops 16, deadlines 82, victory 71, crop 23, death 25, host_drop 14, host_freeze 34, client_drop 72).
## The global watchdog is the sum of the limits of the selected scenarios plus WATCHDOG_SLACK_S (790 s for all),
## so a filtered run gets a proportionally short watchdog.
const SCENARIOS: Array[Dictionary] = [
	{"name": "relay_normal", "group": "relay", "scene": E2E_SCENE, "args": [], "limit_s": 40.0},
	{"name": "relay_host_drops", "group": "relay", "scene": E2E_SCENE, "args": ["--host-drops"], "limit_s": 40.0},
	{"name": "deadlines", "group": "relay", "scene": E2E_SCENE, "args": ["--deadlines"], "limit_s": 160.0},
	{"name": "victory", "group": "hunt", "scene": HUNT_SCENE, "args": ["--scenario=victory"], "limit_s": 150.0},
	{"name": "crop", "group": "hunt", "scene": HUNT_SCENE, "args": ["--scenario=crop"], "limit_s": 50.0},
	{"name": "death", "group": "hunt", "scene": HUNT_SCENE, "args": ["--scenario=death"], "limit_s": 50.0},
	{"name": "host_drop", "group": "hunt", "scene": HUNT_SCENE, "args": ["--scenario=host_drop"], "limit_s": 40.0},
	{"name": "host_freeze", "group": "hunt", "scene": HUNT_SCENE, "args": ["--scenario=host_freeze"], "limit_s": 80.0},
	{"name": "client_drop", "group": "hunt", "scene": HUNT_SCENE, "args": ["--scenario=client_drop"], "limit_s": 150.0},
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
		print("FAIL watchdog: net_test excedeu %d s" % int(_watchdog_s))
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


## Scenarios selected by "-- --only=a,b" (all when absent). Returns null after reporting an unknown name.
func _select() -> Variant:
	var spec: String = ChildRunner.user_arg(ONLY_ARG)
	if spec == "":
		return SCENARIOS
	var wanted: PackedStringArray = spec.split(",", false)
	var known: Dictionary = {}
	for s: Dictionary in SCENARIOS:
		known[s["name"]] = true
		known[s["group"]] = true
	var unknown: Array[String] = []
	for w: String in wanted:
		if not known.has(w.strip_edges()):
			unknown.append(w)
	if not unknown.is_empty() or wanted.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for s: Dictionary in SCENARIOS:
			names.append(str(s["name"]))
		TestCase.report("FAIL", "net_test::--only", ["nome(s) desconhecido(s): %s (validos: %s e os grupos relay, hunt)" % [
			str(unknown), ", ".join(names)]], _totals)
		return null
	var out: Array[Dictionary] = []
	for s: Dictionary in SCENARIOS:
		if str(s["name"]) in wanted or str(s["group"]) in wanted:
			out.append(s)
	return out


func _run() -> void:
	var selected: Variant = _select()
	if selected == null:
		_finished = true
		_quit()
		return
	var list: Array[Dictionary] = []
	list.assign(selected)
	var total_limit: float = WATCHDOG_SLACK_S
	for s: Dictionary in list:
		total_limit += float(s["limit_s"])
	_watchdog_s = total_limit
	var bun: String = ChildRunner.find_bun()
	if bun == "":
		for s: Dictionary in list:
			TestCase.report("SKIP", "net_test::%s" % s["name"],
				["Bun nao encontrado (PATH, $BUN, ~/.bun/bin ou -- --bun=<caminho>): cenario de rede NAO executado"], _totals)
		_finished = true
		_quit()
		return
	print("net_test: Bun em %s; %d cenario(s), watchdog %d s" % [bun, list.size(), int(_watchdog_s)])
	for s: Dictionary in list:
		if _finished:
			return
		await _run_scenario(s, bun)
	if not _finished:
		_finished = true
		print("net_test: tempo total %.1f s" % (float(Time.get_ticks_msec() - _start_ms) / 1000.0))
		_quit()


func _run_scenario(scenario: Dictionary, bun: String) -> void:
	var label: String = "net_test::%s" % scenario["name"]
	var user_args: Array = [ChildRunner.BUN_ARG + bun]
	user_args.append_array(scenario["args"])
	var r: Dictionary = await _runner.run(scenario["scene"], str(scenario["name"]), [], user_args,
		float(scenario["limit_s"]), _abort_requested)
	if bool(r["aborted"]):
		return
	var detail: Array = ChildRunner.problems(r, "NET_E2E / NET_HUNT_E2E checks=")
	if detail.is_empty():
		TestCase.report("PASS", "%s (%d verificacoes, %.1f s)" % [label, int(r["checks"]), float(r["secs"])], [], _totals)
	else:
		TestCase.report("FAIL", label, detail, _totals)
