extends Node
## End-to-end test of multiplayer F2 over the relay, in native Godot (docs/multiplayer.md section 9, F2).
## Starts the local Bun room server on a free port and two headless Godot processes running this same
## scene as players (net_e2e_peer.gd): the host creates the room through the lobby, the client joins with
## the code the host wrote to a temp file, the host starts, both reach Net.hunt_go, walk and stop.
## In between, this process itself checks the server refusals with bare NetSessions: a different version,
## a fifth peer, and a join after the hunt started. Every child process is killed on every way out.
##
## Run (from the project root; Bun found on PATH, in BUN or in ~/.bun/bin, or pass -- --bun=<path>):
##   tools/godot.sh --headless --path . res://src/net/debug/net_e2e.tscn
## Optional user args: --bun=<bun executable>  --e2e-dir=<scratch dir>  --keep (keep the scratch dir)
##   --host-drops: at the end the host process exits instead of the client; the client must get host_left
##   and end its hunt as DISCONNECTED (docs/multiplayer.md section 6.9).
##   --deadlines: instead of the two players, runs net_deadlines.gd (F5): real sessions in this process
##   against the server: stall warning, host timeout, absent / removed clients, load deadline, room lock,
##   Net.flush, ping/pong, server dying mid-hunt. Shortened timeouts unless --real-timeouts is also passed.
## Exit code 0 and "NET_E2E checks=N failures=0" when green.

const PEER_ARG: String = "--e2e-peer="
const DIR_ARG: String = "--e2e-dir="
const CODE_ARG: String = "--e2e-code="
const BUN_ARG: String = "--bun="
const KEEP_ARG: String = "--keep"
const DROP_ARG: String = "--host-drops"     # scenario: the host process exits mid-hunt instead of the client
const DEADLINES_ARG: String = "--deadlines"  # scenario: stalls, absences, timeouts, lock, flush (net_deadlines.gd)
const REAL_TIMEOUTS_ARG: String = "--real-timeouts"   # with --deadlines: data/net.json values, not shortened ones
const SERVER_ARG: String = "--server="       # read by the autoload Net in the children

const HOST_ADDR: String = "127.0.0.1"
const PORT_MIN: int = 20000
const PORT_SPAN: int = 30000
const PORT_TRIES: int = 40
const SERVER_READY_MS: int = 10000
const CODE_MS: int = 40000
const JOIN_MS: int = 40000
const SESSION_MS: int = 10000
const RESULTS_MS: int = 90000
const TOTAL_MS: int = 150000
const REAL_TIMEOUTS_TOTAL_MS: int = 540000   # --deadlines --real-timeouts waits for the real 20 s / 30 s / 25 s
const LATE_JOIN_DELAY_MS: int = 500
const KILL_WAIT_MS: int = 3000
const PEER_MAX_FPS: int = 60

const MAX_REMOTE_ERROR_M: float = 0.5        # F2 acceptance: remote hunter within 0.5 m after 1 s stopped
const STOPPED_FOR_MS: int = 1000
const MIN_WALK_M: float = 1.0
const OLD_VERSION: String = "0.0.0-e2e"

var _dir: String = ""
var _keep: bool = false
var _host_drops: bool = false
var _pids: Dictionary = {}        # label -> pid
var _sessions: Array[NetSession] = []
var _checks: int = 0
var _failures: int = 0
var _finished: bool = false
var _deadline_ms: int = 0
var _tcp: StreamPeerTCP = null    # probe of the server port


func _ready() -> void:
	var peer_role: String = _arg(PEER_ARG)
	if peer_role != "":
		_become_peer(peer_role)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deadline_ms = Time.get_ticks_msec() + (REAL_TIMEOUTS_TOTAL_MS if OS.get_cmdline_user_args().has(REAL_TIMEOUTS_ARG) else TOTAL_MS)
	_run.call_deferred()


func _process(delta: float) -> void:
	for s: NetSession in _sessions:
		s.process(delta)
	if not _finished and _deadline_ms > 0 and Time.get_ticks_msec() > _deadline_ms:
		_ok(false, "total time limit")
		_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_kill_all()


# --- player mode ---------------------------------------------------------------------------------

func _become_peer(peer_role: String) -> void:
	var driver: Node = (load("res://src/net/debug/net_e2e_peer.gd") as GDScript).new()
	driver.name = "NetE2EPeer"
	driver.set("role", peer_role)
	driver.set("dir", _arg(DIR_ARG))
	driver.set("code", _arg(CODE_ARG))
	driver.set("host_drops", OS.get_cmdline_user_args().has(DROP_ARG))
	get_tree().root.add_child.call_deferred(driver)


# --- orchestrator --------------------------------------------------------------------------------

func _run() -> void:
	Profile.set_save_path("user://net_e2e_orchestrator.json")   # never the player's save
	_keep = OS.get_cmdline_user_args().has(KEEP_ARG)
	_host_drops = OS.get_cmdline_user_args().has(DROP_ARG)
	_dir = _arg(DIR_ARG)
	if _dir == "":
		_dir = OS.get_temp_dir().path_join("javali_net_e2e_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_dir)
	_say("scratch dir %s" % _dir)

	# 1. Room server
	var bun: String = _find_bun()
	if not _ok(bun != "", "Bun encontrado (use -- --bun=<caminho>)"):
		_finish()
		return
	var port: int = _free_port()
	if not _ok(port > 0, "porta livre"):
		_finish()
		return
	var server_js: String = ProjectSettings.globalize_path("res://server/server.js")
	_spawn("bun", bun, [server_js, "--port", str(port), "--host", HOST_ADDR])
	if not _ok(await _wait(_port_open.bind(port), SERVER_READY_MS), "servidor Bun ouvindo na porta %d" % port):
		_finish()
		return
	var url: String = "ws://%s:%d/ws" % [HOST_ADDR, port]
	_say("server %s" % url)

	# Deadlines scenario (F5): sessions in this process, no player processes (net_deadlines.gd).
	if OS.get_cmdline_user_args().has(DEADLINES_ARG):
		var deadlines: Node = (load("res://src/net/debug/net_deadlines.gd") as GDScript).new()
		deadlines.name = "NetDeadlines"
		add_child(deadlines)
		await deadlines.call("run", url, _ok, func() -> void: OS.kill(int(_pids["bun"])),
			OS.get_cmdline_user_args().has(REAL_TIMEOUTS_ARG))
		_finish()
		return

	# 2. Host process creates the room through the lobby
	_spawn("host", OS.get_executable_path(), _peer_args("host", url, ""))
	if not _ok(await _wait(_has_file.bind("code"), CODE_MS), "anfitrião criou a sala e escreveu o código"):
		_finish()
		return
	var code: String = _read("code").strip_edges()
	_say("room code %s" % code)

	# 3. Different version refused
	var old: NetSession = _session(url, OLD_VERSION, "Versao velha")
	old.join(code)
	var old_fail: Array = await _wait_failure(old)
	_ok(old_fail[0] == &"version_mismatch", "versão diferente recusada (%s)" % str(old_fail[0]))
	# The host version only comes in the error frame, which native Godot loses with the close (only
	# the close code survives): the message must still name this machine's version.
	_ok(str(old_fail[1]).contains(OLD_VERSION), "mensagem cita a versão local: %s" % str(old_fail[1]))

	# 4. Client process joins with the code
	_spawn("client", OS.get_executable_path(), _peer_args("client", url, code))
	if not _ok(await _wait(_has_file.bind("joined"), JOIN_MS), "cliente entrou na sala pelo lobby"):
		_finish()
		return
	_ok(_read("joined").strip_edges() == "1", "cliente ficou com o slot 1")

	# 5. Two fillers make four; the fifth is refused
	var fillers: Array[NetSession] = []
	for i: int in 2:
		var f: NetSession = _session(url, _version(), "Extra %d" % (i + 1))
		f.join(code)
		fillers.append(f)
	var in_lobby: bool = await _wait(func() -> bool:
		return fillers[0].get_state() == NetSession.STATE_LOBBY and fillers[1].get_state() == NetSession.STATE_LOBBY, SESSION_MS)
	_ok(in_lobby, "mais dois peers entram (sala com 4)")
	if in_lobby:
		_ok(fillers[1].get_player_count() == 4, "quarto peer vê 4 na sala (%d)" % fillers[1].get_player_count())
	var fifth: NetSession = _session(url, _version(), "Quinto")
	fifth.join(code)
	var fifth_fail: Array = await _wait_failure(fifth)
	_ok(fifth_fail[0] == &"room_full", "quinto peer recusado (%s)" % str(fifth_fail[0]))
	for f: NetSession in fillers:
		f.leave()

	# 6. The host starts; a join after that is refused
	_write("start", "1")
	if _ok(await _wait(_has_file.bind("loading"), JOIN_MS), "anfitrião iniciou a caçada"):
		await _sleep(LATE_JOIN_DELAY_MS)
		var late: NetSession = _session(url, _version(), "Atrasado")
		late.join(code)
		var late_fail: Array = await _wait_failure(late)
		_ok(late_fail[0] == &"in_progress", "entrada com a caçada em andamento recusada (%s)" % str(late_fail[0]))

	# 7. Both players report
	var both: bool = await _wait(func() -> bool:
		return _has_file("result_host.json") and _has_file("result_client.json"), RESULTS_MS)
	_ok(both, "os dois processos terminaram e escreveram o resultado")
	_check_results()
	_finish()


func _check_results() -> void:
	var host: Dictionary = _read_json("result_host.json")
	var client: Dictionary = _read_json("result_client.json")
	for r: Dictionary in [host, client]:
		var who: String = str(r.get("role", "?"))
		_ok(bool(r.get("ok", false)), "%s terminou sem erro %s" % [who, str(r.get("error", ""))])
		var states: Array = r.get("states", [])
		var i_loading: int = states.find(float(NetSession.STATE_LOADING))
		var i_hunt: int = states.find(float(NetSession.STATE_IN_HUNT))
		_ok(i_loading >= 0 and i_hunt > i_loading, "%s: room_state_changed LOADING e depois IN_HUNT %s" % [who, str(states)])
		var loading: Dictionary = r.get("loading", {})
		_ok(str(loading.get("map", "")) != "", "%s: mapa selecionado já em LOADING (%s)" % [who, str(loading.get("map", ""))])
		_ok(int(loading.get("player_count", 0)) == 2, "%s: 2 jogadores em LOADING" % who)
		_ok(int(loading.get("seed", 0)) != 0, "%s: get_hunt_seed() já preenchido em LOADING" % who)
		var roster: Array = loading.get("roster", [])
		var weapons_ok: bool = roster.size() == 2
		for p: Variant in roster:
			weapons_ok = weapons_ok and str((p as Dictionary).get("weapon", "")) != "" \
				and str((p as Dictionary).get("name", "")).begins_with("E2E")
		_ok(weapons_ok, "%s: roster completo com nome e arma em LOADING %s" % [who, str(roster)])
		var go: Dictionary = r.get("go", {})
		_ok(bool(go.get("world_bound", false)) and str(go.get("scene", "")) == ScenePaths.HUNT,
			"%s: hunt_go com o mundo da caçada montado (%s)" % [who, str(go.get("scene", ""))])
		_ok(int(go.get("room_state", -1)) == NetSession.STATE_IN_HUNT, "%s: IN_HUNT no hunt_go" % who)
		_ok(int(go.get("request_seed", -1)) == int(go.get("seed", -2)),
			"%s: HuntRequest.rng_seed = semente da sala (%s)" % [who, str(go.get("request_seed"))])
		_ok(int(go.get("request_players", 0)) == 2, "%s: HuntRequest.player_count = 2" % who)
		_ok(int(go.get("link_path", 0)) == NetLink.PATH_RELAY, "%s: enlace pelo relay (path %s)" % [who, str(go.get("link_path"))])
		_ok(bool(go.get("remote_exists", false)), "%s: caçador remoto existe no mundo" % who)
		var walked: float = _dist(r.get("local_start", []), r.get("local_end", []))
		_ok(walked >= MIN_WALK_M, "%s: caçador local andou %.2f m" % [who, walked])
	if host.is_empty() or client.is_empty():
		return
	var host_go: Dictionary = host.get("go", {})
	var client_go: Dictionary = client.get("go", {})
	_ok(int(host_go.get("seed", 0)) == int(client_go.get("seed", 1)), "semente igual nos dois peers (%s / %s)"
		% [str(host_go.get("seed")), str(client_go.get("seed"))])
	_ok(str(host_go.get("request_map", "")) == str(client_go.get("request_map", "-")), "mesmo mapa nos dois")
	_check_view(host, client, "anfitrião vê o cliente")
	_check_view(client, host, "cliente vê o anfitrião")
	if _host_drops:
		_ok((client.get("drop_errors", []) as Array).has("host_left"), "cliente recebeu host_left quando o anfitrião caiu %s"
			% str(client.get("drop_errors", [])))
		_ok(int(client.get("drop_room_state", -1)) == NetSession.STATE_NONE, "cliente voltou a OFFLINE")
		_ok(bool(client.get("drop_hunt_over", false)) and int(client.get("drop_outcome", -1)) == int(client.get("drop_outcome_expected", -2)),
			"caçada do cliente terminou como DISCONNECTED (outcome %s)" % str(client.get("drop_outcome")))
		return
	_ok(bool(host.get("peer_left_seen", false)), "anfitrião recebeu net_peer_left quando o cliente caiu (%s ms)"
		% str(host.get("peer_left_ms", "?")))
	_ok(bool(host.get("hunter_after_left_null", false)), "caçador do cliente saiu do mundo do anfitrião")


## viewer saw the other one: its sample taken at least 1 s after the other stopped vs the other's real position.
func _check_view(viewer: Dictionary, other: Dictionary, label: String) -> void:
	var after_ms: float = float(other.get("stop_wall_ms", 0)) + STOPPED_FOR_MS
	var real: Array = other.get("local_end", [])
	var seen: Array = []
	for s: Variant in viewer.get("remote_samples", []):
		if float((s as Array)[0]) >= after_ms:
			seen = (s as Array).slice(1)
			break
	_ok(not seen.is_empty(), "%s: amostra 1 s depois da parada" % label)
	if seen.is_empty():
		return
	var err: float = _dist(seen, real)
	_ok(err <= MAX_REMOTE_ERROR_M, "%s: erro %.3f m (limite %.1f)" % [label, err, MAX_REMOTE_ERROR_M])
	var moved: float = _dist(viewer.get("remote_start", []), seen)
	_ok(moved >= MIN_WALK_M, "%s: remoto se moveu %.2f m" % [label, moved])
	_say("%s: real %s visto %s erro %.3f m, moveu %.2f m" % [label, str(real), str(seen), err, moved])


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for s: NetSession in _sessions:
		s.leave()
	var all_gone: bool = await _wait(func() -> bool:
		for label: String in _pids:
			if label != "bun" and OS.is_process_running(int(_pids[label])):
				return false
		return true, KILL_WAIT_MS)
	if _failures == 0:
		_ok(all_gone, "processos do Godot encerraram sozinhos")
	_kill_all()
	await _sleep(200)
	var alive: Array[String] = []
	for label: String in _pids:
		if OS.is_process_running(int(_pids[label])):
			alive.append(label)
	_ok(alive.is_empty(), "nenhum processo filho ficou rodando %s" % str(alive))
	_print_child_log("host")
	_print_child_log("client")
	_cleanup_files()
	print("NET_E2E checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- processes -----------------------------------------------------------------------------------

func _peer_args(peer_role: String, url: String, code: String) -> PackedStringArray:
	var args: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--max-fps", str(PEER_MAX_FPS), "--log-file", _dir.path_join("%s.log" % peer_role), scene_file_path, "--",
		PEER_ARG + peer_role, DIR_ARG + _dir, SERVER_ARG + url])
	if code != "":
		args.append(CODE_ARG + code)
	if _host_drops:
		args.append(DROP_ARG)
	return args


func _spawn(label: String, path: String, args: PackedStringArray) -> void:
	var pid: int = OS.create_process(path, args, false)
	_ok(pid > 0, "processo %s iniciado" % label)
	if pid > 0:
		_pids[label] = pid


func _kill_all() -> void:
	for label: String in _pids:
		var pid: int = int(_pids[label])
		if OS.is_process_running(pid):
			OS.kill(pid)


func _find_bun() -> String:
	var candidates: Array[String] = [_arg(BUN_ARG), OS.get_environment("BUN")]
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


func _free_port() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i: int in PORT_TRIES:
		var port: int = PORT_MIN + rng.randi_range(0, PORT_SPAN)
		var probe: TCPServer = TCPServer.new()
		if probe.listen(port, HOST_ADDR) == OK:
			probe.stop()
			return port
	return 0


func _port_open(port: int) -> bool:
	if _tcp == null:
		_tcp = StreamPeerTCP.new()
		_tcp.connect_to_host(HOST_ADDR, port)
	_tcp.poll()
	var status: int = _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.disconnect_from_host()
		_tcp = null
		return true
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_tcp = null   # not listening yet: try again next frame
	return false


# --- sessions ------------------------------------------------------------------------------------

func _session(url: String, version: String, player_name: String) -> NetSession:
	var s: NetSession = NetSession.new()
	s.setup(Data.get_net(), {"url": url, "version": version, "name": player_name, "rtc": false})
	_sessions.append(s)
	return s


## [code, message] of the session's failure, or [&"", ""] if it did not fail in time.
func _wait_failure(s: NetSession) -> Array:
	var out: Array = [&"", ""]
	var handler: Callable = func(c: StringName, m: String) -> void:
		out[0] = c
		out[1] = m
	s.failed.connect(handler)
	await _wait(func() -> bool: return out[0] != &"" or s.get_state() == NetSession.STATE_LOBBY, SESSION_MS)
	if s.get_state() == NetSession.STATE_LOBBY:
		s.leave()
	return out


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


# --- helpers -------------------------------------------------------------------------------------

func _ok(cond: bool, label: String) -> bool:
	_checks += 1
	if not cond:
		_failures += 1
	print("%s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _say(text: String) -> void:
	print("NET_E2E %s" % text)


func _wait(cond: Callable, timeout_ms: int) -> bool:
	var limit: int = Time.get_ticks_msec() + timeout_ms
	while not bool(cond.call()):
		if Time.get_ticks_msec() >= limit:
			return false
		await get_tree().process_frame
	return true


func _sleep(ms: int) -> void:
	var limit: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < limit:
		await get_tree().process_frame


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _has_file(file_name: String) -> bool:
	return FileAccess.file_exists(_dir.path_join(file_name))


func _read(file_name: String) -> String:
	return FileAccess.get_file_as_string(_dir.path_join(file_name))


func _write(file_name: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join(file_name), FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _read_json(file_name: String) -> Dictionary:
	var data: Variant = JSON.parse_string(_read(file_name)) if _has_file(file_name) else null
	return data if data is Dictionary else {}


func _dist(a: Variant, b: Variant) -> float:
	if not (a is Array and b is Array) or (a as Array).size() < 3 or (b as Array).size() < 3:
		return INF
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(Vector3(float(b[0]), float(b[1]), float(b[2])))


func _print_child_log(peer_role: String) -> void:
	var path: String = _dir.path_join("%s.log" % peer_role)
	if not FileAccess.file_exists(path):
		return
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.contains("NET_E2E_PEER") or line.contains("ERROR") or line.contains("SCRIPT ERROR"):
			print("  [%s] %s" % [peer_role, line.strip_edges()])


func _cleanup_files() -> void:
	for peer_role: String in ["host", "client", "orchestrator"]:
		for suffix: String in [".json", ".bak.json"]:
			var path: String = ProjectSettings.globalize_path("user://net_e2e_%s%s" % [peer_role, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	if _keep:
		_say("kept %s" % _dir)
		return
	var d: DirAccess = DirAccess.open(_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(_dir)
