extends Node
## tests/net_unit.tscn: the single-process sandboxes of the multiplayer phases F2, F4, F5 and F8, run as child Godot
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
##   hud_hints      1.3 onboarding: HintDirector triggers, queue, learned ids, touch text, horde bait   RESULT:
##   link_selftest  NetLink over NetLoopback: loss, reordering, RTC promotion/downgrade, relay rate   LINK_SELFTEST
##   spectator      F6: allies on minimap/compass, SpectatorCamera, "Assistindo" banner, solo untouched  RESULT:
##   net_dogs       F7: one Dog per slot on the host, DogPuppet on the client, dog records, commands  RESULT:
##   net_sync       F8: rejoin sync (EV_FULL_SYNC) in one process: same boars/patches/score, idempotent   RESULT:
##   net_horde      horde mode over the byte path: wave state host -> client, EV_HORDE_WAVE, F8 replay   RESULT:
##   net_horde2     horde level 2 over the byte path: revive (HF_DOWNED, C_REVIVE, EV_HUNTER_REVIVED), ammo   RESULT:
##                  crates (C_AMMO_CRATE, EV_AMMO_CRATE, F8 replay), bleed-out, both down = DEFEAT_DEATH
##   net_mode       room mode (L_LOBBY / L_START byte of the mode), host_select_mode                NET_MODE_SELFTEST
##   player_horde2  A1: horde level 2 player rules: counted ammo, crates, confine, downed / revive, bleed-out   RESULT:
##   player_stamina F2: stamina: sprint drain, exhaustion, regen, recover threshold, message, HealthStrip bar   RESULT:
##   player_knife   F4/0.9.9: equippable knife (X equips, fire swings, hit at the press, cadence, gates, shot ids), Faca button   RESULT:
##   net_knife      F4: the client's knife swing as C_SHOT with weapon byte 254; host validates damage and reach   RESULT:
##   remote_hunter  RemoteHunter over the byte path of the network (wall clock, no --fixed-fps)        remote_sandbox:
##   minimap_bake   1.4 (HF5): Mato Grosso baked to the minimap image: size, orientation, determinism   RESULT:
##                  (src/world/debug/minimap_selftest.tscn; prints MINIMAP_BAKE_MS, budget <= 150 ms)
## net_sync must also print "PASS minimap_same_on_both" (host and client bake the same image): see "must_pass".
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
## "must_pass": names of checks whose "PASS <name>" line has to be in the child's log (a sandbox that silently drops a
## check would otherwise stay green on its RESULT line).
## "wall_clock": true = run WITHOUT --fixed-fps (the sandbox compares against the wall clock: RemoteHunter
## interpolates by Time.get_ticks_msec(), which a fixed-fps headless run outruns).
const SANDBOXES: Array[Dictionary] = [
	{"name": "net_roles", "scene": "res://src/hunt/debug/net_roles_test.tscn", "limit_s": 120.0},
	{"name": "net_boars", "scene": "res://src/hunt/debug/net_boars_test.tscn", "limit_s": 120.0},
	{"name": "net_flow", "scene": "res://src/hunt/debug/net_flow_test.tscn", "limit_s": 120.0},
	{"name": "hud_net", "scene": "res://src/hud/debug/hud_net_test.tscn", "limit_s": 90.0},
	{"name": "hud_hints", "scene": "res://src/hud/debug/hud_hints_test.tscn", "limit_s": 60.0},
	{"name": "link_selftest", "scene": "res://src/net/debug/link_selftest.tscn", "limit_s": 90.0},
	{"name": "spectator", "scene": "res://src/player/debug/spectator_sandbox.tscn", "limit_s": 90.0},
	{"name": "net_dogs", "scene": "res://src/hunt/debug/net_dogs_test.tscn", "limit_s": 120.0},
	{"name": "net_sync", "scene": "res://src/hunt/debug/net_sync_test.tscn", "limit_s": 90.0,
		"must_pass": ["minimap_same_on_both"]},
	{"name": "net_horde", "scene": "res://src/hunt/debug/net_horde_test.tscn", "limit_s": 120.0},
	# net_horde2 used to need wall_clock: it waited for the end of the hunt in GAME seconds while the byte path of the two
	# hunts is pumped in REAL time, so under --fixed-fps 60 the headless run outpaced the wall clock (QA4 2026-11-23).
	# Fixed at the source in 0.9.9: net_horde2_test._wait_until never gives up before WAIT_REAL_FLOOR_S of wall time.
	{"name": "net_horde2", "scene": "res://src/hunt/debug/net_horde2_test.tscn", "limit_s": 120.0},
	{"name": "net_mode", "scene": "res://src/net/debug/net_mode_selftest.tscn", "limit_s": 60.0},
	{"name": "player_horde2", "scene": "res://src/player/debug/player_horde2_test.tscn", "limit_s": 120.0},
	{"name": "player_stamina", "scene": "res://src/player/debug/player_stamina_test.tscn", "limit_s": 120.0},
	{"name": "player_knife", "scene": "res://src/player/debug/player_knife_test.tscn", "limit_s": 120.0},
	{"name": "net_knife", "scene": "res://src/hunt/debug/net_knife_test.tscn", "limit_s": 90.0,
		"must_pass": ["knife_claim_is_one_c_shot_with_weapon_254", "host_rejects_damage_above_top_level",
			"host_rejects_hit_beyond_reach_3m", "host_rejects_swing_without_knife_in_data", "gun_claim_unchanged"]},
	{"name": "remote_hunter", "scene": "res://src/player/debug/remote_sandbox.tscn", "limit_s": 60.0, "wall_clock": true},
	{"name": "minimap_bake", "scene": "res://src/world/debug/minimap_selftest.tscn", "limit_s": 60.0},
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
	var detail: Array = ChildRunner.problems(r, "RESULT: N passed ... / LINK_SELFTEST|NET_MODE_SELFTEST checks= / remote_sandbox: PASS")
	if detail.is_empty() and sandbox.has("must_pass"):
		var log_text: String = FileAccess.get_file_as_string(str(r["log_path"])) if FileAccess.file_exists(str(r["log_path"])) else ""
		for check_name: String in sandbox["must_pass"]:
			if not log_text.contains("PASS %s" % check_name):
				detail.append("o filho nao imprimiu 'PASS %s' (a verificacao sumiu ou falhou); log %s" % [check_name, r["log_path"]])
	if detail.is_empty():
		TestCase.report("PASS", "%s (%d verificacoes, %.1f s)" % [label, int(r["checks"]), float(r["secs"])], [], _totals)
	else:
		TestCase.report("FAIL", label, detail, _totals)
