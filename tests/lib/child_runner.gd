extends RefCounted
## Runs a scene of this project in a child Godot process and turns its console output into a verdict.
## Shared by tests/net_test.gd (two-process network scenarios) and tests/net_unit.gd (single-process sandboxes
## of packages A, B, N and game-systems), which keeps the process handling in one place:
##   - the child writes to a log file (--log-file), read back when it exits;
##   - the whole process tree is killed on timeout, abort or close (Bun server and player children included);
##   - the summary line of every known format is understood (see parse_summary).
## A child that exits without a summary line is a FAIL, never a pass.

const POLL_MS: int = 200
const MAX_FAIL_LINES: int = 12
const BUN_ARG: String = "--bun="
const KILL_GRACE_MS: int = 1500

var host: Node = null
var _pid: int = -1
var _logs: Array[String] = []


func _init(host_node: Node) -> void:
	host = host_node


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## Kills the running child AND its descendants: on Windows a plain kill would leave the Bun server and the two
## player processes of an orchestrator scene running.
func kill() -> void:
	if _pid <= 0:
		return
	var pid: int = _pid
	_pid = -1
	if not OS.is_process_running(pid):
		return
	if OS.has_feature("windows"):
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"], [], true)
	else:
		OS.execute("pkill", ["-KILL", "-P", str(pid)], [], true)
	if OS.is_process_running(pid):
		OS.kill(pid)


func cleanup_logs() -> void:
	for log_path: String in _logs:
		if FileAccess.file_exists(log_path):
			DirAccess.remove_absolute(log_path)
	_logs.clear()


## Runs `scene` (res:// path) headless and waits for it to exit. `engine_args` go before the scene (e.g.
## ["--fixed-fps", "60"]), `user_args` after "--". `should_abort` (optional Callable -> bool) is polled; when it
## returns true the child is killed and the result has "aborted" = true. `timeout_s` <= 0 means no per-run limit.
## Returns {started, aborted, timed_out, exit_code, secs, summary (bool), checks, failures, fail_lines, log_path}.
func run(scene: String, tag: String, engine_args: Array = [], user_args: Array = [], timeout_s: float = 0.0,
		should_abort: Callable = Callable()) -> Dictionary:
	var out: Dictionary = {"started": false, "aborted": false, "timed_out": false, "exit_code": -1, "secs": 0.0,
		"summary": false, "checks": -1, "failures": -1, "fail_lines": [] as Array[String], "log_path": ""}
	var log_path: String = OS.get_temp_dir().path_join("javali_child_%d_%s.log" % [OS.get_process_id(), tag])
	out["log_path"] = log_path
	_logs.append(log_path)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	var args: PackedStringArray = PackedStringArray(["--headless"])
	for a: Variant in engine_args:
		args.append(str(a))
	args.append_array(PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path, scene]))
	if not user_args.is_empty():
		args.append("--")
		for a: Variant in user_args:
			args.append(str(a))
	var t0: int = Time.get_ticks_msec()
	_pid = OS.create_process(OS.get_executable_path(), args, false)
	if _pid <= 0:
		_pid = -1
		return out
	out["started"] = true
	while OS.is_process_running(_pid):
		var elapsed_s: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if should_abort.is_valid() and bool(should_abort.call()):
			out["aborted"] = true
			kill()
			out["secs"] = elapsed_s
			return out
		if timeout_s > 0.0 and elapsed_s > timeout_s:
			out["timed_out"] = true
			kill()
			break
		await host.get_tree().create_timer(float(POLL_MS) / 1000.0, true, false, true).timeout
	if not out["timed_out"]:
		out["exit_code"] = OS.get_process_exit_code(_pid)
	_pid = -1
	out["secs"] = float(Time.get_ticks_msec() - t0) / 1000.0
	# Let the OS flush the log of a killed process before reading it.
	if out["timed_out"]:
		await host.get_tree().create_timer(float(KILL_GRACE_MS) / 1000.0, true, false, true).timeout
	var text: String = FileAccess.get_file_as_string(log_path) if FileAccess.file_exists(log_path) else ""
	var parsed: Dictionary = parse_summary(text)
	out["summary"] = parsed["found"]
	out["checks"] = parsed["checks"]
	out["failures"] = parsed["failures"]
	out["fail_lines"] = parsed["fail_lines"]
	return out


## Understands the summary line of every child in this project (the last one wins):
##   "RESULT: N passed, M failed, K skipped"      suites and sandboxes of packages A / B
##   "NET_E2E checks=N failures=M"                 and the same shape for NET_HUNT_E2E and LINK_SELFTEST
##   "profile_net_check: OK" / "profile_net_check: N FAILED"
##   "remote_sandbox: PASS (0 failures)" / "remote_sandbox: FAIL (N failures)"
## Also collects the lines that explain a failure.
static func parse_summary(text: String) -> Dictionary:
	var res: Dictionary = {"found": false, "checks": -1, "failures": -1, "fail_lines": [] as Array[String]}
	var re_checks: RegEx = RegEx.new()
	re_checks.compile("^(?:NET_E2E|NET_HUNT_E2E|LINK_SELFTEST) checks=(\\d+) failures=(\\d+)")
	var re_result: RegEx = RegEx.new()
	re_result.compile("^RESULT: (\\d+) passed, (\\d+) failed, (\\d+) skipped")
	var re_profile: RegEx = RegEx.new()
	re_profile.compile("^profile_net_check: (?:(OK)|(\\d+) FAILED)")
	var re_sandbox: RegEx = RegEx.new()
	re_sandbox.compile("^remote_sandbox: (?:(PASS)|FAIL) \\((\\d+) failures\\)")
	var fails: Array[String] = []
	for line: String in text.split("\n"):
		var l: String = line.strip_edges()
		var m: RegExMatch = re_checks.search(l)
		if m != null:
			res["found"] = true
			res["checks"] = int(m.get_string(1))
			res["failures"] = int(m.get_string(2))
			continue
		m = re_result.search(l)
		if m != null:
			res["found"] = true
			res["checks"] = int(m.get_string(1)) + int(m.get_string(2))
			res["failures"] = int(m.get_string(2))
			continue
		m = re_profile.search(l)
		if m != null:
			res["found"] = true
			res["checks"] = 1   # that sandbox prints no count: one aggregate verdict
			res["failures"] = 0 if m.get_string(1) == "OK" else int(m.get_string(2))
			continue
		m = re_sandbox.search(l)
		if m != null:
			res["found"] = true
			res["checks"] = 1   # that sandbox prints no count: one aggregate verdict
			res["failures"] = int(m.get_string(2))
			if m.get_string(1) == "" and int(m.get_string(2)) == 0:
				res["failures"] = 1   # "FAIL (0 failures)" must never read as green
			continue
		if l.begins_with("FAIL ") or l.contains("SCRIPT ERROR") or l.begins_with("ERROR:") \
				or (l.contains("NET_E2E_PEER") and l.contains("FAIL")):
			fails.append(l)
	res["fail_lines"] = fails
	return res


## Human readable problems of a run result ([] = green). `label` is only used for the messages.
static func problems(r: Dictionary, summary_hint: String) -> Array:
	var detail: Array = []
	if not bool(r["started"]):
		detail.append("nao consegui iniciar o processo filho do Godot")
	elif bool(r["timed_out"]):
		detail.append("filho excedeu o limite de tempo e foi encerrado (%.0f s); log %s" % [float(r["secs"]), r["log_path"]])
	elif not bool(r["summary"]):
		detail.append("filho terminou (codigo %d) sem a linha de resumo (%s); log %s" % [int(r["exit_code"]), summary_hint, r["log_path"]])
	elif int(r["failures"]) != 0:
		detail.append("%d de %d verificacoes falharam (codigo de saida %d)" % [int(r["failures"]), int(r["checks"]), int(r["exit_code"])])
	elif int(r["exit_code"]) != 0:
		detail.append("0 falhas nas %d verificacoes, mas codigo de saida %d" % [int(r["checks"]), int(r["exit_code"])])
	elif int(r["checks"]) <= 0:
		detail.append("o filho reportou 0 verificacoes: nada foi testado")
	if not detail.is_empty():
		var lines: Array[String] = r["fail_lines"]
		for i: int in mini(lines.size(), MAX_FAIL_LINES):
			detail.append(lines[i])
	return detail


## Value of a user arg "--name=value" (empty when absent).
static func user_arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


## Bun for the relay server: -- --bun=<path>, $BUN, ~/.bun/bin, PATH. Empty when not found.
static func find_bun() -> String:
	var candidates: Array[String] = [user_arg(BUN_ARG), OS.get_environment("BUN")]
	var home: String = OS.get_environment("USERPROFILE" if OS.has_feature("windows") else "HOME")
	var exe: String = "bun.exe" if OS.has_feature("windows") else "bun"
	if home != "":
		candidates.append(home.path_join(".bun").path_join("bin").path_join(exe))
	for dir_path: String in OS.get_environment("PATH").split(";" if OS.has_feature("windows") else ":", false):
		candidates.append(dir_path.path_join(exe))
	for c: String in candidates:
		if c != "" and FileAccess.file_exists(c):
			return c
	return ""
