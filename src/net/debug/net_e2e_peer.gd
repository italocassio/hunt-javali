extends Node
## One player process of the end-to-end relay test (net_e2e.gd starts two of these).
## Goes through the real path: lobby buttons -> Net room -> LOADING -> lobby calls Router.start_hunt ->
## hunt.tscn -> Net.hunt_go. Then walks forward, stops, and samples where it sees the other hunter.
## Lives under the root (not as the current scene) so it survives the scene changes.
## Talks to the orchestrator only through files in a shared directory; writes result_<role>.json at the end.

const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const START_DELAY_MS: int = 500         # after hunt_go, before pressing forward (input is released by hunt_go)
const MOVE_MS: int = 1500
const STOPPED_SAMPLE_MS: int = 3500     # sampling after the stop; the check uses the other side's stop + 1 s
const SAMPLE_EVERY_MS: int = 100
const PEER_LEFT_WAIT_MS: int = 10000
const START_RETRY_MS: int = 250
const HARD_LIMIT_MS: int = 110000       # this process never outlives the orchestrator's own deadline
const MOVE_ACTION: StringName = &"move_forward"

var role: String = ""
var dir: String = ""
var code: String = ""
var host_drops: bool = false            # the host process exits in the middle of the hunt (section 6.9)

var _result: Dictionary = {}
var _states: Array = []
var _go: bool = false
var _hunter_left: Array = []
var _errors: Array = []
var _deadline_ms: int = 0
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deadline_ms = Time.get_ticks_msec() + HARD_LIMIT_MS
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _done and Time.get_ticks_msec() > _deadline_ms:
		_finish("hard time limit")


func _run() -> void:
	_result = {"role": role, "ok": false}
	# Own save file: the player's user://save.json is never touched.
	Profile.set_save_path("user://net_e2e_%s.json" % role)
	Profile.reset_progress()
	Profile.set_setting("player_name", "E2E %s" % role)
	Net.room_state_changed.connect(_on_room_state)
	Net.room_error.connect(func(c: StringName, m: String) -> void:
		_errors.append(str(c))
		_log("room_error %s: %s" % [c, m]))
	Net.hunt_go.connect(_on_hunt_go)
	GameEvents.hunter_left.connect(func(slot: int) -> void: _hunter_left.append(slot))
	Router.goto(ScenePaths.LOBBY)
	if not await _until(func() -> bool: return _scene_path() == ScenePaths.LOBBY, 15000, "lobby scene"):
		return
	await get_tree().process_frame
	var lobby: Node = get_tree().current_scene
	if role == "host":
		_button(lobby, "CreateRoomButton").pressed.emit()
		if not await _until(func() -> bool: return Net.get_room_state() == Net.RoomState.LOBBY, 15000, "room created"):
			return
		_write("code", Net.get_room_code())
		_log("room %s" % Net.get_room_code())
		if not await _until(func() -> bool: return FileAccess.file_exists(dir.path_join("start")), 60000, "start file"):
			return
		if not await _until(_try_start.bind(lobby), 20000, "host_start_hunt accepted"):
			return
		_write("loading", "1")
	else:
		var code_edit: LineEdit = _button(lobby, "CodeEdit") as LineEdit
		code_edit.text = code
		code_edit.text_changed.emit(code)   # what typing does: enables %JoinButton
		_button(lobby, "JoinButton").pressed.emit()
		if not await _until(func() -> bool: return Net.get_room_state() == Net.RoomState.LOBBY, 15000, "room joined"):
			return
		_write("joined", str(Net.get_local_slot()))
		_button(lobby, "ReadyButton").pressed.emit()   # F6: clients declare themselves ready
	if not await _until(func() -> bool: return _go, 60000, "hunt_go"):
		return
	await _walk_and_sample()
	if _done:
		return
	if host_drops:
		if role == "client":
			await _until(func() -> bool: return not _errors.is_empty(), PEER_LEFT_WAIT_MS, "", false)
			var world: HuntWorld = _world()
			_result["drop_errors"] = _errors
			_result["drop_room_state"] = Net.get_room_state()
			_result["drop_hunt_over"] = world != null and world.is_hunt_over()
			_result["drop_outcome"] = world.get_result().outcome if world != null and world.get_result() != null else -1
			_result["drop_outcome_expected"] = HuntResult.Outcome.DISCONNECTED
	elif role == "host":
		var t0: int = Time.get_ticks_msec()
		await _until(func() -> bool: return _hunter_left.has(CLIENT_SLOT), PEER_LEFT_WAIT_MS, "", false)
		_result["peer_left_seen"] = _hunter_left.has(CLIENT_SLOT)
		_result["peer_left_ms"] = Time.get_ticks_msec() - t0
		_result["hunter_after_left_null"] = _world() == null or _world().get_hunter(CLIENT_SLOT) == null
		_result["net_state_after_left"] = Net.get_room_state()
		_result["player_count_after_left"] = Net.get_player_count()
	_result["ok"] = true
	_finish("")


## Host: presses %StartButton until Net accepts (the client may still be readying up).
func _try_start(lobby: Node) -> bool:
	if Net.get_player_count() != 2:
		return false
	var t: int = Time.get_ticks_msec()
	if t < int(_result.get("next_start_try", 0)):
		return false
	_result["next_start_try"] = t + START_RETRY_MS
	_button(lobby, "StartButton").pressed.emit()
	return Net.get_room_state() == Net.RoomState.LOADING


func _on_room_state(state: int) -> void:
	_states.append(state)
	if state != Net.RoomState.LOADING:
		return
	# What the lobby sees at this moment, before it builds the HuntRequest.
	var roster: Array = []
	for info: NetPeerInfo in Net.get_roster():
		roster.append({"slot": info.slot, "name": info.display_name, "weapon": str(info.weapon_id),
			"host": info.is_host})
	_result["loading"] = {
		"map": str(Net.get_selected_map_id()),
		"contract": Net.get_selected_contract_index(),
		"player_count": Net.get_player_count(),
		"seed": Net.get_hunt_seed(),
		"roster": roster,
		"local_slot": Net.get_local_slot(),
		"is_active": Net.is_active(),
	}


func _on_hunt_go() -> void:
	_go = true
	var world: HuntWorld = _world()
	var request: HuntRequest = Router.get_pending_request()
	var other: int = CLIENT_SLOT if role == "host" else HOST_SLOT
	_result["go"] = {
		"world_bound": world != null and world.is_world_ready(),
		"scene": _scene_path(),
		"room_state": Net.get_room_state(),
		"seed": Net.get_hunt_seed(),
		"request_seed": request.rng_seed if request != null else -1,
		"request_players": request.player_count if request != null else -1,
		"request_map": str(request.map_id) if request != null else "",
		"link_path": Net.get_link_path(other),
		"remote_exists": world != null and world.get_hunter(other) != null and not world.get_hunter(other).is_local(),
		"wall_ms": _wall_ms(),
	}


func _walk_and_sample() -> void:
	var world: HuntWorld = _world()
	var other: int = CLIENT_SLOT if role == "host" else HOST_SLOT
	if world == null or world.get_player() == null:
		_finish("no world/player at hunt_go")
		return
	var player: PlayerBase = world.get_player()
	var remote: PlayerBase = world.get_hunter(other)
	if remote == null:
		_finish("no remote hunter")
		return
	_result["remote_start"] = _vec(remote.global_position)
	await _sleep(START_DELAY_MS)
	_result["local_start"] = _vec(player.global_position)
	Input.action_press(MOVE_ACTION)
	await _sleep(MOVE_MS)
	Input.action_release(MOVE_ACTION)
	_result["stop_wall_ms"] = _wall_ms()
	var samples: Array = []
	var end_ms: int = Time.get_ticks_msec() + STOPPED_SAMPLE_MS
	var next_ms: int = 0
	while Time.get_ticks_msec() < end_ms and not _done:
		if Time.get_ticks_msec() >= next_ms and is_instance_valid(remote):
			next_ms = Time.get_ticks_msec() + SAMPLE_EVERY_MS
			var s: Array = _vec(remote.global_position)
			s.push_front(_wall_ms())
			samples.append(s)
		await get_tree().process_frame
	_result["remote_samples"] = samples   # [wall_ms, x, y, z]
	_result["local_end"] = _vec(player.global_position)
	_result["local_end_wall_ms"] = _wall_ms()


func _finish(error: String) -> void:
	if _done:
		return
	_done = true
	Input.action_release(MOVE_ACTION)
	_result.erase("next_start_try")
	_result["states"] = _states
	if error != "":
		_result["ok"] = false
		_result["error"] = error
		_log("FAIL " + error)
	_write("result_%s.json" % role, JSON.stringify(_result, "  "))
	_log("done ok=%s" % str(_result["ok"]))
	if role == "host" and not host_drops:
		Net.leave_room()
	# The leaving side just quits, socket open: the other one must see it drop in the middle of the hunt.
	get_tree().quit(0 if bool(_result["ok"]) else 1)


# --- helpers ---

func _until(cond: Callable, timeout_ms: int, what: String, fail: bool = true) -> bool:
	var limit: int = Time.get_ticks_msec() + timeout_ms
	while not bool(cond.call()):
		if _done:
			return false
		if Time.get_ticks_msec() >= limit:
			if fail:
				_finish("timeout waiting for " + what)
			return false
		await get_tree().process_frame
	return true


func _sleep(ms: int) -> void:
	var limit: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < limit and not _done:
		await get_tree().process_frame


func _world() -> HuntWorld:
	return get_tree().current_scene as HuntWorld


func _scene_path() -> String:
	var scene: Node = get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func _button(lobby: Node, node_name: String) -> Control:
	var node: Node = lobby.get_node_or_null("%" + node_name)
	if node == null:
		node = lobby.find_child(node_name, true, false)
	return node as Control


func _write(file_name: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(dir.path_join(file_name + ".tmp"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(dir.path_join(file_name + ".tmp"), dir.path_join(file_name))   # atomic for the reader


func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func _wall_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _log(text: String) -> void:
	print("NET_E2E_PEER %s %s" % [role, text])
