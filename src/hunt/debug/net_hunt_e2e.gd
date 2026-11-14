extends Node
## Two-process network hunt scenarios (docs/multiplayer.md section 9, F4 "N3" and F5 "N4"/"N5"), package B's
## own orchestrator. Starts the local Bun room server and, per scenario, two headless Godot processes running
## this same scene as players. Both go through the Net autoload (no lobby screen): the host creates the room,
## the client joins with the code, the host starts contract 0 of Mato Grosso with a fixed seed.
## Scenarios (-- --scenario=NAME, default victory; "all" runs every one, one after the other):
##   victory      client bot kills 3 boar replicas, host bot kills the rest -> VICTORY on BOTH; each result
##                has only its own kills and money, the full bonus, the same scoreboard and crop; the money
##                credited by Router.finish_hunt matches.
##   crop         host drains the crop (debug) -> DEFEAT_CROP on both, same eaten patches on both.
##   death        client dies (hunt goes on), then the host dies -> DEFEAT_DEATH on both.
##   host_drop    N4: client kills 1, the host process is killed -> client DISCONNECTED within
##                net.host_timeout_s + 2 s, its kill paid, no bonus, no progression.
##   host_freeze  N4 by deadline: the host process stays up but its Net stops (socket open, no snapshots) ->
##                client DISCONNECTED by net.host_timeout_s, within host_timeout_s + 2 s.
##   client_drop  N5: the client process is killed -> the host sees hunter_left and wins alone.
##
## Run (from the project root; Bun on PATH, in BUN or ~/.bun/bin, or -- --bun=<path>):
##   tools/godot.sh --headless --path . res://src/hunt/debug/net_hunt_e2e.tscn [-- --scenario=all]
## Exit code 0 and "NET_HUNT_E2E checks=N failures=0" when green. Every child process is killed on exit.

const PEER_ARG: String = "--hunt-peer="
const DIR_ARG: String = "--hunt-dir="
const CODE_ARG: String = "--hunt-code="
const SCENARIO_ARG: String = "--scenario="
const BUN_ARG: String = "--bun="
const SERVER_ARG: String = "--server="   # read by the autoload Net in the children
const SCENARIOS: Array[String] = ["victory", "crop", "death", "host_drop", "host_freeze", "client_drop"]

const HOST_ADDR: String = "127.0.0.1"
const PORT_MIN: int = 20000
const PORT_SPAN: int = 30000
const PORT_TRIES: int = 40
const SERVER_READY_MS: int = 10000
const CODE_MS: int = 40000
const RESULTS_MS: int = 280000
const SCENARIO_MS: int = 320000
const KILL_WAIT_MS: int = 6000
const PEER_MAX_FPS: int = 60
const DROP_WAIT_MS: int = 120000
const ROUTE_WAIT_MS: int = 10000
const DROP_SLACK_S: float = 2.0

const MAP_ID: StringName = &"mato_grosso"
const CONTRACT: int = 0
const FIXED_SEED: int = 20261113
const CLIENT_KILLS: int = 3
const CLIENT_KILL_S: float = 150.0
const HOST_KILL_S: float = 200.0
const OVER_WAIT_MS: int = 30000
const PEER_LIMIT_MS: int = 300000
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const CROP_FIRST_PCT: float = 40.0
const CROP_STEP_WAIT_MS: int = 1500
const SPAWN_WAIT_MS: int = 8000
const DEAD_CHECK_MS: int = 3000
const LEFT_WAIT_MS: int = 40000
const KILL_DAMAGE: float = 100000.0

# Bot (same idea as tests/bot/hunt_bot.gd, kept here so package B owns its scenario).
const STAND_M: float = 14.0
const AIM_SETTLE_S: float = 0.35
const AFTER_SHOT_S: float = 0.25
const RELOAD_WAIT_S: float = 0.2
const PARK: Vector2 = Vector2(-118.0, -118.0)
const SPOT_ANGLES: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
const EYE_M: float = 1.65

var _dir: String = ""
var _base_dir: String = ""
var _pids: Dictionary = {}
var _checks: int = 0
var _failures: int = 0
var _finished: bool = false
var _deadline_ms: int = 0
var _tcp: StreamPeerTCP = null

# Peer mode
var _role: String = ""
var _scenario: String = ""
var _result: Dictionary = {}
var _go: bool = false
var _done: bool = false
var _killers: Dictionary = {}           # boar_id -> killer slot, as this machine heard it
var _died: Array = []                   # hunter_died slots heard here
var _left: Array = []                   # hunter_left slots heard here
var _errors: Array = []
var _money0: int = 0


## Peer mode: the scene itself is replaced by hunt.tscn, so the peer runs as a copy under the root.
var is_driver: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_role = _arg(PEER_ARG)
	_dir = _arg(DIR_ARG)
	_scenario = _arg(SCENARIO_ARG)
	if _scenario == "":
		_scenario = "victory"
	if _role != "":
		if not is_driver:
			var driver: Node = (get_script() as GDScript).new() as Node
			driver.name = "NetHuntPeer"
			driver.set("is_driver", true)
			get_tree().root.add_child.call_deferred(driver)
			_role = ""
			set_process(false)
			return
		_deadline_ms = Time.get_ticks_msec() + PEER_LIMIT_MS
		_run_peer.call_deferred()
		return
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _role != "":
		if not _done and Time.get_ticks_msec() > _deadline_ms:
			_peer_finish("hard time limit")
		return
	if not _finished and _deadline_ms > 0 and Time.get_ticks_msec() > _deadline_ms:
		_ok(false, "tempo do cenário (%d s)" % (SCENARIO_MS / 1000))
		_finish()


func _notification(what: int) -> void:
	if _role == "" and (what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST):
		_kill_all()


# === Orchestrator ================================================================================

func _run() -> void:
	_deadline_ms = Time.get_ticks_msec() + SCENARIO_MS   # also covers a setup that never reaches a scenario
	_base_dir = _dir if _dir != "" else OS.get_temp_dir().path_join("javali_hunt_e2e_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_base_dir)
	var list: Array[String] = []
	if _scenario == "all":
		list.assign(SCENARIOS)
	else:
		list.append(_scenario)
	if not SCENARIOS.has(list[0]):
		_ok(false, "cenário conhecido (%s; use %s ou all)" % [_scenario, str(SCENARIOS)])
		_finish()
		return
	var bun: String = _find_bun()
	if not _ok(bun != "", "Bun encontrado (use -- --bun=<caminho>)"):
		_finish()
		return
	var port: int = _free_port()
	if not _ok(port > 0, "porta livre"):
		_finish()
		return
	_spawn("bun", bun, [ProjectSettings.globalize_path("res://server/server.js"), "--port", str(port), "--host", HOST_ADDR])
	if not _ok(await _wait(_port_open.bind(port), SERVER_READY_MS), "servidor Bun na porta %d" % port):
		_finish()
		return
	var url: String = "ws://%s:%d/ws" % [HOST_ADDR, port]
	for sc: String in list:
		_scenario = sc
		_dir = _base_dir.path_join(sc)
		DirAccess.make_dir_recursive_absolute(_dir)
		print("=== cenário %s" % sc)
		_deadline_ms = Time.get_ticks_msec() + SCENARIO_MS
		await _run_scenario(url)
		await _end_scenario()
	_finish()


func _run_scenario(url: String) -> void:
	_spawn("host", OS.get_executable_path(), _peer_args("host", url, ""))
	if not _ok(await _wait(_has_file.bind("code"), CODE_MS), "[%s] anfitrião criou a sala" % _scenario):
		return
	_spawn("client", OS.get_executable_path(), _peer_args("client", url, _read("code").strip_edges()))
	match _scenario:
		"host_drop":
			if not _ok(await _wait(_has_file.bind("client_kill"), DROP_WAIT_MS), "[host_drop] cliente abateu antes da queda"):
				return
			_write("host_killed", str(Time.get_unix_time_from_system()))
			OS.kill(int(_pids["host"]))
			_ok(await _wait(_has_file.bind("result_client.json"), RESULTS_MS), "[host_drop] cliente escreveu o resultado")
			_check_host_drop("host_killed")
		"host_freeze":
			_ok(await _wait(_has_file.bind("result_client.json"), RESULTS_MS), "[host_freeze] cliente escreveu o resultado")
			_check_host_drop("host_frozen")
		"client_drop":
			if not _ok(await _wait(_has_file.bind("client_ready"), DROP_WAIT_MS), "[client_drop] cliente entrou na caçada"):
				return
			OS.kill(int(_pids["client"]))
			_write("client_killed", "1")
			_ok(await _wait(_has_file.bind("result_host.json"), RESULTS_MS), "[client_drop] anfitrião escreveu o resultado")
			_check_client_drop()
		_:
			var both: bool = await _wait(func() -> bool:
				return _has_file("result_host.json") and _has_file("result_client.json"), RESULTS_MS)
			_ok(both, "[%s] os dois processos escreveram o resultado" % _scenario)
			match _scenario:
				"victory":
					_check_victory()
				"crop":
					_check_crop()
				"death":
					_check_death()


func _end_scenario() -> void:
	var all_gone: bool = await _wait(func() -> bool:
		for label: String in ["host", "client"]:
			if _pids.has(label) and OS.is_process_running(int(_pids[label])):
				return false
		return true, KILL_WAIT_MS)
	_ok(all_gone, "[%s] processos do Godot encerraram sozinhos (ou foram derrubados pelo cenário)" % _scenario)
	for label: String in ["host", "client"]:
		if _pids.has(label) and OS.is_process_running(int(_pids[label])):
			OS.kill(int(_pids[label]))
	for peer: String in ["host", "client"]:
		var path: String = _dir.path_join("%s.log" % peer)
		if FileAccess.file_exists(path):
			for line: String in FileAccess.get_file_as_string(path).split("\n"):
				if line.contains("NET_HUNT_PEER") or line.contains("SCRIPT ERROR") or line.contains("ERROR:"):
					print("  [%s/%s] %s" % [_scenario, peer, line.strip_edges()])
	_pids.erase("host")
	_pids.erase("client")


func _both() -> Array[Dictionary]:
	var host: Dictionary = _read_json("result_host.json")
	var client: Dictionary = _read_json("result_client.json")
	for r: Dictionary in [host, client]:
		if not r.is_empty():
			_ok(bool(r.get("ok", false)), "[%s] %s terminou sem erro %s" % [_scenario, r.get("role", "?"), str(r.get("error", ""))])
	return [host, client]


func _check_victory() -> void:
	var pair: Array[Dictionary] = _both()
	var host: Dictionary = pair[0]
	var client: Dictionary = pair[1]
	if host.is_empty() or client.is_empty():
		return
	var total: int = int(host.get("total", -1))
	var host_ids: Array = host.get("credited", [])
	var client_ids: Array = client.get("credited", [])
	_ok(client_ids.size() >= CLIENT_KILLS, "cliente abateu %d javalis atirando nas réplicas (mínimo %d)" % [client_ids.size(), CLIENT_KILLS])
	_ok(total == 14, "contrato 0 com 2 jogadores tem 14 javalis (%d)" % total)
	_ok(_outcome(host) == HuntResult.Outcome.VICTORY and _outcome(client) == HuntResult.Outcome.VICTORY,
		"VICTORY nos dois (anfitrião %s, cliente %s)" % [str(host.get("outcome")), str(client.get("outcome"))])
	_ok(int(client.get("boars_total", -2)) == total and int(client.get("team_kills", -1)) == total
		and int(host.get("team_kills", -1)) == total, "equipe = total nos dois (%s / %s / %d)"
		% [str(client.get("team_kills")), str(host.get("team_kills")), total])
	_ok(host_ids.size() + client_ids.size() == total, "soma dos abates = total (%d + %d = %d)" % [host_ids.size(), client_ids.size(), total])
	var union: Dictionary = {}
	var twice: Array = []
	for id: Variant in host_ids + client_ids:
		if union.has(int(id)):
			twice.append(int(id))
		union[int(id)] = true
	_ok(twice.is_empty() and union.size() == total, "cada abate creditado a um só caçador (repetidos %s)" % str(twice))
	var host_seen: Dictionary = host.get("killers", {})
	var client_seen: Dictionary = client.get("killers", {})
	var agree: bool = host_seen.size() == total and client_seen.size() == total
	for key: Variant in host_seen:
		agree = agree and int(client_seen.get(key, -1)) == int(host_seen[key])
	_ok(agree, "os dois viram o mesmo atirador em cada abate (%d / %d)" % [host_seen.size(), client_seen.size()])
	var right: bool = true
	for id: Variant in host_ids:
		right = right and int(host_seen.get(str(int(id)), -1)) == HOST_SLOT
	for id: Variant in client_ids:
		right = right and int(host_seen.get(str(int(id)), -1)) == CLIENT_SLOT
	_ok(right, "cada abate creditado a quem atirou")
	for r: Dictionary in [host, client]:
		var who: String = str(r.get("role"))
		_ok(int(r.get("money_from_kills", -1)) == int(r.get("own_reward_sum", -2)) and int(r.get("money_from_kills", 0)) > 0,
			"%s: dinheiro de abate = só os abates dele (%s = %s)" % [who, str(r.get("money_from_kills")), str(r.get("own_reward_sum"))])
		_ok(int(r.get("total_money", -1)) == int(r.get("money_from_kills", 0)) + int(r.get("contract_bonus", 0)),
			"%s: total = abates + bônus (%s)" % [who, str(r.get("total_money"))])
		_ok(int(r.get("money_delta", -1)) == int(r.get("total_money", -2)), "%s: Router.finish_hunt creditou %s (resultado %s)"
			% [who, str(r.get("money_delta")), str(r.get("total_money"))])
		_ok(bool(r.get("counts_for_progression", false)) and int(r.get("player_count", 0)) == 2, "%s: conta progresso, 2 jogadores" % who)
	_ok(int(host.get("contract_bonus", -1)) == int(client.get("contract_bonus", -2)) and int(host.get("contract_bonus", 0)) > 0,
		"bônus cheio igual nos dois (%s / %s)" % [str(host.get("contract_bonus")), str(client.get("contract_bonus"))])
	_ok(_boards_equal(host.get("scoreboard", []), client.get("scoreboard", [])), "placar igual nos dois %s" % str(client.get("scoreboard")))
	var board_ok: bool = false
	for e: Variant in client.get("scoreboard", []):
		var d: Dictionary = e
		if int(d["slot"]) == CLIENT_SLOT:
			board_ok = int(d["kills"]) == client_ids.size() and int(d["money"]) == int(client.get("money_from_kills", -1))
	_ok(board_ok, "placar do cliente = abates e dinheiro do resultado dele")
	_check_crop_equal(host, client)
	print("NET_HUNT_E2E host claims accepted=%s rejected=%s heard=%s charge_acc=%s | client shots=%s hits=%s charges=%s"
		% [host.get("hits_accepted"), host.get("hits_rejected"), host.get("shots_heard"), host.get("charge_accepted"),
		client.get("shots_claimed"), client.get("hits_claimed"), client.get("charge_hits")])


func _check_crop() -> void:
	var pair: Array[Dictionary] = _both()
	if pair[0].is_empty() or pair[1].is_empty():
		return
	_ok(_outcome(pair[0]) == HuntResult.Outcome.DEFEAT_CROP and _outcome(pair[1]) == HuntResult.Outcome.DEFEAT_CROP,
		"DEFEAT_CROP nos dois (%s / %s)" % [str(pair[0].get("outcome")), str(pair[1].get("outcome"))])
	_ok(is_zero_approx(float(pair[1].get("crop", -1.0))) and int(pair[1].get("contract_bonus", -1)) == 0,
		"cliente: lavoura 0%% e sem bônus (%s)" % str(pair[1].get("crop")))
	_check_crop_equal(pair[0], pair[1])
	_ok(int(pair[0].get("eaten_n", 0)) > 0, "canteiros comidos: %s" % str(pair[0].get("eaten_n")))


func _check_crop_equal(host: Dictionary, client: Dictionary) -> void:
	_ok(int(host.get("eaten_n", -1)) == int(client.get("eaten_n", -2)) and int(host.get("eaten_hash", 1)) == int(client.get("eaten_hash", 2)),
		"mesmo conjunto de canteiros comidos (%s / %s)" % [str(host.get("eaten_n")), str(client.get("eaten_n"))])


func _check_death() -> void:
	var pair: Array[Dictionary] = _both()
	if pair[0].is_empty() or pair[1].is_empty():
		return
	_ok(bool(pair[0].get("alive_after_client_died", false)), "anfitrião seguiu caçando com o cliente morto")
	_ok(_has_int(pair[0].get("died", []), CLIENT_SLOT) and _has_int(pair[0].get("died", []), HOST_SLOT)
		and _has_int(pair[1].get("died", []), CLIENT_SLOT), "hunter_died: anfitrião %s, cliente %s"
		% [str(pair[0].get("died")), str(pair[1].get("died"))])
	_ok(_outcome(pair[0]) == HuntResult.Outcome.DEFEAT_DEATH and _outcome(pair[1]) == HuntResult.Outcome.DEFEAT_DEATH,
		"DEFEAT_DEATH nos dois (%s / %s)" % [str(pair[0].get("outcome")), str(pair[1].get("outcome"))])


func _check_host_drop(mark_file: String) -> void:
	var client: Dictionary = _read_json("result_client.json")
	if client.is_empty():
		return
	_ok(bool(client.get("ok", false)), "[%s] cliente terminou sem erro %s" % [_scenario, str(client.get("error", ""))])
	var killed_at: float = float(_read(mark_file))
	var ended_at: float = float(client.get("ended_unix", 0.0))
	var limit: float = float(Data.get_net().get("host_timeout_s", 20.0)) + DROP_SLACK_S
	_ok(_outcome(client) == HuntResult.Outcome.DISCONNECTED, "cliente terminou DISCONNECTED (%s)" % str(client.get("outcome")))
	_ok(ended_at > 0.0 and ended_at - killed_at <= limit, "fim %.2f s depois da queda (limite %.1f s)" % [ended_at - killed_at, limit])
	_ok((client.get("credited", []) as Array).size() >= 1 and int(client.get("money_from_kills", 0)) == int(client.get("own_reward_sum", -1))
		and int(client.get("money_from_kills", 0)) > 0, "abates do cliente pagos (%s, $%s)"
		% [str(client.get("credited")), str(client.get("money_from_kills"))])
	_ok(int(client.get("contract_bonus", -1)) == 0 and not bool(client.get("counts_for_progression", true)),
		"sem bônus e sem progresso")
	_ok(int(client.get("money_delta", -1)) == int(client.get("total_money", -2)), "Router.finish_hunt creditou %s"
		% str(client.get("money_delta")))


func _check_client_drop() -> void:
	var host: Dictionary = _read_json("result_host.json")
	if host.is_empty():
		return
	_ok(bool(host.get("ok", false)), "[client_drop] anfitrião terminou sem erro %s" % str(host.get("error", "")))
	_ok(_has_int(host.get("left", []), CLIENT_SLOT), "anfitrião recebeu hunter_left(%d) %s" % [CLIENT_SLOT, str(host.get("left"))])
	_ok(int(host.get("hunters_at_end", -1)) == 1, "só o anfitrião ficou no mundo (%s)" % str(host.get("hunters_at_end")))
	_ok(_outcome(host) == HuntResult.Outcome.VICTORY and (host.get("credited", []) as Array).size() == int(host.get("total", -1)),
		"anfitrião venceu sozinho (%s, %d de %s)" % [str(host.get("outcome")), (host.get("credited", []) as Array).size(), str(host.get("total"))])


## JSON numbers come back as floats: Array.has(int) would never match them.
func _has_int(values: Array, wanted: int) -> bool:
	for v: Variant in values:
		if int(v) == wanted:
			return true
	return false


func _outcome(r: Dictionary) -> int:
	return int(r.get("outcome", -1))


func _boards_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i: int in a.size():
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		if int(x["slot"]) != int(y["slot"]) or int(x["kills"]) != int(y["kills"]) or int(x["money"]) != int(y["money"]) \
				or str(x["name"]) != str(y["name"]) or absf(float(x["weight_kg"]) - float(y["weight_kg"])) > 0.05:
			return false
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_kill_all()
	await _sleep(200)
	var alive: Array[String] = []
	for label: String in _pids:
		if OS.is_process_running(int(_pids[label])):
			alive.append(label)
	_ok(alive.is_empty(), "nenhum processo filho ficou rodando %s" % str(alive))
	_cleanup()
	print("NET_HUNT_E2E checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _peer_args(peer: String, url: String, code: String) -> PackedStringArray:
	var args: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--max-fps", str(PEER_MAX_FPS), "--log-file", _dir.path_join("%s.log" % peer), scene_file_path, "--",
		PEER_ARG + peer, DIR_ARG + _dir, SERVER_ARG + url, SCENARIO_ARG + _scenario])
	if code != "":
		args.append(CODE_ARG + code)
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


func _cleanup() -> void:
	for peer: String in ["host", "client"]:
		for suffix: String in [".json", ".bak.json"]:
			var path: String = ProjectSettings.globalize_path("user://net_hunt_e2e_%s%s" % [peer, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	if _base_dir == "":
		return
	var base: DirAccess = DirAccess.open(_base_dir)
	if base == null:
		return
	for sub: String in base.get_directories():
		var d: DirAccess = DirAccess.open(_base_dir.path_join(sub))
		if d != null:
			for f: String in d.get_files():
				d.remove(f)
		DirAccess.remove_absolute(_base_dir.path_join(sub))
	for f: String in base.get_files():
		base.remove(f)
	DirAccess.remove_absolute(_base_dir)


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
		_tcp = null
	return false


func _ok(cond: bool, label: String) -> bool:
	_checks += 1
	if not cond:
		_failures += 1
	print("%s %s" % ["PASS" if cond else "FAIL", label])
	return cond


# === Peer ========================================================================================

func _run_peer() -> void:
	_result = {"role": _role, "scenario": _scenario, "ok": false}
	Profile.set_save_path("user://net_hunt_e2e_%s.json" % _role)   # never the player's save
	Profile.reset_progress()
	Profile.set_setting("player_name", "N %s" % _role)
	Net.room_error.connect(func(c: StringName, m: String) -> void:
		_errors.append(str(c))
		_log("room_error %s: %s" % [c, m]))
	Net.room_state_changed.connect(_on_room_state)
	Net.hunt_go.connect(func() -> void: _go = true)
	GameEvents.boar_killed.connect(func(k: KillInfo) -> void: _killers[k.boar_id] = k.killer_slot)
	GameEvents.hunter_died.connect(func(s: int) -> void: _died.append(s))
	GameEvents.hunter_left.connect(func(s: int) -> void: _left.append(s))
	if _role == "host":
		Net.create_room()
		if not await _until(func() -> bool: return Net.get_room_state() == Net.RoomState.LOBBY, 15000, "room created"):
			return
		Net.host_select_contract(MAP_ID, CONTRACT)
		_write("code", Net.get_room_code())
		var started: bool = await _until(func() -> bool:
			return Net.get_player_count() == 2 and Net.host_start_hunt(), 60000, "host_start_hunt")
		if not started:
			return
	else:
		Net.join_room(_arg(CODE_ARG))
		if not await _until(func() -> bool: return Net.get_room_state() == Net.RoomState.LOBBY, 15000, "room joined"):
			return
		Net.set_ready(true)
	if not await _until(func() -> bool: return _go, 60000, "hunt_go"):
		return
	var world: HuntController = get_tree().current_scene as HuntController
	if world == null or world.get_player() == null:
		_peer_finish("no hunt world at hunt_go")
		return
	_money0 = Profile.get_money()
	_log("go: scenario %s slot %d, total %d" % [_scenario, world.get_local_slot(), world.get_boars_total()])
	var client: bool = _role == "client"
	match _scenario:
		"victory":
			if client:
				await _client_victory(world)
			else:
				await _host_victory(world)
		"crop":
			if client:
				await _client_wait_end(world)
			else:
				await _host_crop(world)
		"death":
			if client:
				await _client_death(world)
			else:
				await _host_death(world)
		"host_drop", "host_freeze":
			if client:
				await _client_host_drop(world)
			elif _scenario == "host_freeze":
				await _host_freeze(world)
			else:
				await _wait_to_be_killed(world)
		"client_drop":
			if client:
				await _wait_to_be_killed(world)
			else:
				await _host_client_drop(world)
		_:
			_peer_finish("unknown scenario " + _scenario)


## Same seed on both machines: the request Net just filled is still pending, the hunt scene loads next.
func _on_room_state(state: int) -> void:
	if state == Net.RoomState.LOADING:
		_fix_seed.call_deferred()


func _fix_seed() -> void:
	var req: HuntRequest = Router.get_pending_request()
	if req != null:
		req.rng_seed = FIXED_SEED


# --- Scenario bodies ---

func _client_victory(world: HuntController) -> void:
	var player: PlayerBase = world.get_player()
	await _kill_until(world, player, func() -> bool: return _credited(world).size() >= CLIENT_KILLS, CLIENT_KILL_S)
	if not is_instance_valid(world) or _done:
		return
	_park(world, player)
	_write("client_done", str(_credited(world).size()))
	_log("client kills %d, waiting for the end of the hunt" % _credited(world).size())
	var replica: HuntReplica = world.debug_replica()
	_result["shots_claimed"] = replica.shots_claimed
	_result["hits_claimed"] = replica.hits_claimed
	_result["charge_hits"] = replica.charge_hits
	if not await _until(func() -> bool: return world.is_hunt_over(), int(HOST_KILL_S * 1000.0) + 30000, "end of hunt (EV_HUNT_END)"):
		return
	_capture(world)
	await _after_route()
	_result["ok"] = (_result["credited"] as Array).size() >= CLIENT_KILLS
	_peer_finish("" if bool(_result["ok"]) else "only %d kills" % (_result["credited"] as Array).size())


func _host_victory(world: HuntController) -> void:
	var player: PlayerBase = world.get_player()
	_park(world, player)
	await _until(func() -> bool: return _has_file("client_done"), int(CLIENT_KILL_S * 1000.0) + 20000, "", false)
	await _kill_until(world, player, func() -> bool: return world.is_hunt_over(), HOST_KILL_S)
	if not is_instance_valid(world) or _done:
		return
	_park(world, player)
	var sync: HuntHostSync = world.debug_host_sync()
	_result["hits_accepted"] = sync.hits_accepted
	_result["hits_rejected"] = sync.hits_rejected
	_result["shots_heard"] = sync.shots_heard
	_result["charge_accepted"] = sync.charge_claims_accepted
	if not world.is_hunt_over():
		_peer_finish("host did not finish")
		return
	_capture(world)
	await _after_route()
	await _stay_for_client()
	_result["ok"] = _outcome(_result) == HuntResult.Outcome.VICTORY
	_peer_finish("" if bool(_result["ok"]) else "host did not win")


func _host_crop(world: HuntController) -> void:
	_park(world, world.get_player())
	await _until(func() -> bool: return _has_file("client_ready"), 30000, "", false)
	await _sleep(SPAWN_WAIT_MS)
	world.debug_set_crop_health(CROP_FIRST_PCT)
	await _sleep(CROP_STEP_WAIT_MS)
	world.debug_set_crop_health(0.0)
	if not await _until(func() -> bool: return world.is_hunt_over(), OVER_WAIT_MS, "crop defeat"):
		return
	_capture(world)
	await _after_route()
	await _stay_for_client()
	_result["ok"] = _outcome(_result) == HuntResult.Outcome.DEFEAT_CROP
	_peer_finish("" if bool(_result["ok"]) else "no crop defeat")


func _client_wait_end(world: HuntController) -> void:
	_park(world, world.get_player())
	_write("client_ready", "1")
	if not await _until(func() -> bool: return world.is_hunt_over(), PEER_LIMIT_MS - 60000, "end of hunt (EV_HUNT_END)"):
		return
	_capture(world)
	await _after_route()
	_result["ok"] = true
	_peer_finish("")


func _client_death(world: HuntController) -> void:
	var player: PlayerBase = world.get_player()
	_park(world, player)
	await _sleep(SPAWN_WAIT_MS)
	player.apply_damage(KILL_DAMAGE, player.global_position + Vector3.FORWARD)
	_write("client_dead", "1")
	if not await _until(func() -> bool: return world.is_hunt_over(), OVER_WAIT_MS + DEAD_CHECK_MS, "end of hunt (EV_HUNT_END)"):
		return
	_capture(world)
	await _after_route()
	_result["ok"] = true
	_peer_finish("")


func _host_death(world: HuntController) -> void:
	var player: PlayerBase = world.get_player()
	_park(world, player)
	if not await _until(func() -> bool: return _has_file("client_dead"), 60000, "client death"):
		return
	await _until(func() -> bool: return _died.has(CLIENT_SLOT), DEAD_CHECK_MS, "", false)
	await _sleep(DEAD_CHECK_MS)
	_result["alive_after_client_died"] = not world.is_hunt_over() and player.is_alive()
	player.apply_damage(KILL_DAMAGE, player.global_position + Vector3.FORWARD)
	if not await _until(func() -> bool: return world.is_hunt_over(), OVER_WAIT_MS, "death defeat"):
		return
	_capture(world)
	await _after_route()
	await _stay_for_client()
	_result["ok"] = _outcome(_result) == HuntResult.Outcome.DEFEAT_DEATH
	_peer_finish("" if bool(_result["ok"]) else "no death defeat")


func _client_host_drop(world: HuntController) -> void:
	var player: PlayerBase = world.get_player()
	await _kill_until(world, player, func() -> bool: return _credited(world).size() >= 1, CLIENT_KILL_S)
	if not is_instance_valid(world) or _done:
		return
	_park(world, player)
	_write("client_kill", str(_credited(world).size()))
	var limit_ms: int = int((float(Data.get_net().get("host_timeout_s", 20.0)) + DROP_SLACK_S) * 1000.0) + DROP_WAIT_MS
	if not await _until(func() -> bool: return world.is_hunt_over(), limit_ms, "DISCONNECTED"):
		return
	_result["ended_unix"] = Time.get_unix_time_from_system()
	_capture(world)
	await _after_route()
	_result["ok"] = true
	_peer_finish("")


func _host_client_drop(world: HuntController) -> void:
	var player: PlayerBase = world.get_player()
	_park(world, player)
	await _until(func() -> bool: return _has_file("client_killed"), DROP_WAIT_MS, "", false)
	await _until(func() -> bool: return _left.has(CLIENT_SLOT), LEFT_WAIT_MS, "", false)
	_log("client left: %s, hunters %d" % [str(_left), world.get_hunters().size()])
	await _kill_until(world, player, func() -> bool: return world.is_hunt_over(), HOST_KILL_S)
	if not is_instance_valid(world) or _done:
		return
	if not world.is_hunt_over():
		_peer_finish("host did not finish alone")
		return
	_result["hunters_at_end"] = world.get_hunters().size()
	_capture(world)
	await _after_route()
	_result["ok"] = _outcome(_result) == HuntResult.Outcome.VICTORY
	_peer_finish("" if bool(_result["ok"]) else "host did not win alone")


## N4 by deadline: Net stops on the host (no snapshot, no close), the client must give up by host_timeout_s.
func _host_freeze(world: HuntController) -> void:
	_park(world, world.get_player())
	if not await _until(func() -> bool: return _has_file("client_kill"), DROP_WAIT_MS, "client kill"):
		return
	_write("host_frozen", str(Time.get_unix_time_from_system()))
	Net.set_process(false)
	await _until(func() -> bool: return _has_file("result_client.json"), RESULTS_MS, "", false)
	Net.set_process(true)
	_result["ok"] = true
	_peer_finish("")


## The other process kills this one (drop scenarios); never ends on its own before the hard limit.
func _wait_to_be_killed(world: HuntController) -> void:
	_park(world, world.get_player())
	if _role == "client":
		_write("client_ready", "1")
	await _until(func() -> bool: return false, PEER_LIMIT_MS, "", false)


# --- Peer helpers ---

## Everything the checks need, read before the 2.5 s end delay frees the hunt scene.
func _capture(world: HuntController) -> void:
	var res: HuntResult = world.get_result()
	if res == null:
		return
	var ids: Array = []
	var reward_sum: int = 0
	for k: KillInfo in res.kills:
		ids.append(k.boar_id)
		reward_sum += k.reward_money
	var eaten: PackedInt32Array = world.crop.get_eaten_indices() if world.crop != null else PackedInt32Array()
	_result["outcome"] = res.outcome
	_result["credited"] = ids
	_result["own_reward_sum"] = reward_sum
	_result["money_from_kills"] = res.money_from_kills
	_result["contract_bonus"] = res.contract_bonus
	_result["total_money"] = res.total_money
	_result["counts_for_progression"] = res.counts_for_progression
	_result["player_count"] = res.player_count
	_result["team_kills"] = res.team_kills
	_result["boars_total"] = res.boars_total
	_result["scoreboard"] = res.scoreboard
	_result["crop"] = res.crop_health_pct
	_result["total"] = world.get_boars_total()
	_result["killed"] = world.get_boars_killed()
	_result["killers"] = _killers
	_result["died"] = _died
	_result["left"] = _left
	_result["eaten_n"] = eaten.size()
	_result["eaten_hash"] = hash(var_to_bytes(eaten))
	_log("over: outcome %d kills %d money %d bonus %d eaten %d" % [res.outcome, ids.size(), res.money_from_kills,
		res.contract_bonus, eaten.size()])


## Waits for Router.finish_hunt (end_delay_s) and records what it credited to the profile.
func _after_route() -> void:
	await _until(func() -> bool: return not (get_tree().current_scene is HuntController), ROUTE_WAIT_MS, "", false)
	_result["money_delta"] = Profile.get_money() - _money0


## Host: stays in the room until the client wrote its result (leaving early would end the client's hunt).
func _stay_for_client() -> void:
	await _until(func() -> bool: return _has_file("result_client.json"), ROUTE_WAIT_MS + OVER_WAIT_MS, "", false)


func _credited(world: HuntController) -> Array:
	if not is_instance_valid(world):
		return []
	var out: Array = []
	for k: KillInfo in world.debug_partial_result().kills:
		out.append(k.boar_id)
	return out


func _park(world: HuntController, player: PlayerBase) -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	player.bot_set_enabled(true)
	player.bot_teleport(Vector3(PARK.x, world.get_height(PARK.x, PARK.y) + 0.1, PARK.y))


## Nearest live boar (puppet on the client), stand at a clear spot, aim at the vital zone, one shot, repeat.
func _kill_until(world: HuntController, player: PlayerBase, done: Callable, timeout_s: float) -> void:
	var limit: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	player.bot_set_enabled(true)
	player.bot_set_aim(true)
	while is_instance_valid(world) and not bool(done.call()) and Time.get_ticks_msec() < limit \
			and not world.is_hunt_over() and not _done:
		var ids: PackedInt32Array = world.get_alive_boar_ids()
		if ids.is_empty() or not player.is_alive():
			await get_tree().process_frame
			continue
		if player.get_ammo_in_mag() <= 0:
			if not player.is_reloading():
				player.bot_reload()
			await _sleep(int(RELOAD_WAIT_S * 1000.0))
			continue
		var me: Vector3 = player.global_position
		var best: int = ids[0]
		var best_d: float = INF
		for id: int in ids:
			var p: Vector3 = world.get_boar_position(id)
			var d: float = Vector2(p.x - me.x, p.z - me.z).length()
			if d < best_d:
				best_d = d
				best = id
		var target: Vector3 = world.get_boar_zone_position(best, &"vital")
		if target == Vector3.INF:
			await get_tree().process_frame
			continue
		var spot: Vector3 = _clear_spot(world, target, me)
		if spot == Vector3.INF:
			await get_tree().process_frame
			continue
		player.bot_teleport(spot)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var aim_until: int = Time.get_ticks_msec() + int(AIM_SETTLE_S * 1000.0)
		while Time.get_ticks_msec() < aim_until and not _done and is_instance_valid(world) and not world.is_hunt_over():
			var tv: Vector3 = world.get_boar_zone_position(best, &"vital")
			if tv != Vector3.INF:
				player.bot_look_at(tv)
			await get_tree().process_frame
		if not is_instance_valid(world) or world.is_hunt_over():
			return
		var tv2: Vector3 = world.get_boar_zone_position(best, &"vital")
		if tv2 != Vector3.INF:
			player.bot_look_at(tv2)
			player.bot_fire()
		await _sleep(int(AFTER_SHOT_S * 1000.0))


func _clear_spot(world: HuntController, target: Vector3, from: Vector3) -> Vector3:
	var rect: Rect2 = world.get_map_rect().grow(-6.0)
	var base: Vector3 = Vector3(from.x - target.x, 0.0, from.z - target.z)
	base = base.normalized() if base.length() > 0.5 else Vector3.BACK
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for deg: float in SPOT_ANGLES:
		var d: Vector3 = base.rotated(Vector3.UP, deg_to_rad(deg))
		var x: float = target.x + d.x * STAND_M
		var z: float = target.z + d.z * STAND_M
		if not rect.has_point(Vector2(x, z)):
			continue
		var feet: Vector3 = Vector3(x, world.get_height(x, z) + 0.05, z)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(feet + Vector3(0.0, EYE_M, 0.0), target,
			Layers.MASK_LINE_OF_SIGHT)
		if space.intersect_ray(q).is_empty():
			return feet
	return Vector3.INF


func _peer_finish(error: String) -> void:
	if _done:
		return
	_done = true
	if error != "":
		_result["ok"] = false
		_result["error"] = error
		_log("FAIL " + error)
	_result["errors"] = _errors
	_write("result_%s.json" % _role, JSON.stringify(_result, "  "))
	_log("done ok=%s" % str(_result.get("ok", false)))
	Net.leave_room()
	get_tree().quit(0 if bool(_result.get("ok", false)) else 1)


func _until(cond: Callable, timeout_ms: int, what: String, fail: bool = true) -> bool:
	var limit: int = Time.get_ticks_msec() + timeout_ms
	while not bool(cond.call()):
		if _done:
			return false
		if Time.get_ticks_msec() >= limit:
			if fail:
				_peer_finish("timeout waiting for " + what)
			return false
		await get_tree().process_frame
	return true


func _log(text: String) -> void:
	print("NET_HUNT_PEER %s %s" % [_role, text])


# === Shared helpers ==============================================================================

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
	var f: FileAccess = FileAccess.open(_dir.path_join(file_name + ".tmp"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(_dir.path_join(file_name + ".tmp"), _dir.path_join(file_name))


func _read_json(file_name: String) -> Dictionary:
	var data: Variant = JSON.parse_string(_read(file_name)) if _has_file(file_name) else null
	return data if data is Dictionary else {}
