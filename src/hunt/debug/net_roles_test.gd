extends Node
## Package B sandbox for the F2 network roles: builds the hunt as host and as client in one process, with a
## synthetic roster and no real network (HuntController.test_net_role hook; the Net autoload is not touched).
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_roles_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 240.0
const POS_TOLERANCE_M: float = 0.05
const FEED_TIMEOUT_MS: int = 4000
const BOAR_WAIT_S: float = 60.0
const HOST_TELEPORT: Vector2 = Vector2(20.0, -15.0)
const HOST_TELEPORT_2: Vector2 = Vector2(30.0, 5.0)
const CLIENT_TELEPORT: Vector2 = Vector2(-30.0, 10.0)

var _passed: int = 0
var _failed: int = 0
var _started: int = 0
var _joined: Array = []
var _left: Array = []
var _ended: Array[HuntResult] = []
var _start_ms: int = 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	GameEvents.hunt_started.connect(func(_r: HuntRequest) -> void: _started += 1)
	GameEvents.hunter_joined.connect(func(s: int, n: String) -> void: _joined.append([s, n]))
	GameEvents.hunter_left.connect(func(s: int) -> void: _left.append(s))
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	await _scenario("real_remote", false)
	await _scenario("fallback_remote", true)
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
		get_tree().quit(1)


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _roster() -> Array[NetPeerInfo]:
	var out: Array[NetPeerInfo] = []
	var names: Array[String] = ["Anfitriao", "Ana"]
	for i: int in 2:
		var info: NetPeerInfo = NetPeerInfo.new()
		info.slot = i
		info.display_name = names[i]
		info.is_host = i == 0
		info.weapon_id = Ids.W_CARBINE_22
		out.append(info)
	return out


func _make(role: int, local_slot: int, fallback_remote: bool) -> HuntController:
	var hunt: HuntController = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	hunt.route_on_finish = false
	hunt.test_net_role = role
	hunt.test_net_local_slot = local_slot
	hunt.test_net_roster = _roster()
	hunt.test_fallback_remote = fallback_remote
	add_child(hunt)
	return hunt


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _wait_ready(hunt: HuntController) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready():
		if Time.get_ticks_msec() - t0 > 120000:
			return false
		await get_tree().process_frame
	return true


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _teleport(hunt: HuntController, xz: Vector2) -> void:
	hunt.get_player().bot_teleport(Vector3(xz.x, hunt.get_height(xz.x, xz.y) + 0.05, xz.y))


## Host -> client: one snapshot through the real byte path.
func _send_snapshot(host: HuntController, client: HuntController) -> int:
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	host.net_write_snapshot(out)
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = out.data_array
	client.net_apply_snapshot(inp)
	return out.get_size()


## Keeps feeding snapshots until the client's view of `slot` is within tolerance of `target`.
func _feed_until_at(host: HuntController, client: HuntController, slot: int, target: Vector2) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < FEED_TIMEOUT_MS:
		_send_snapshot(host, client)
		var h: PlayerBase = client.get_hunter(slot)
		if h != null and _xz(h.global_position).distance_to(target) <= POS_TOLERANCE_M:
			return true
		await get_tree().process_frame
	return false


func _scenario(label: String, fallback_remote: bool) -> void:
	print("--- %s" % label)
	_started = 0
	_joined.clear()
	_left.clear()
	_ended.clear()
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0)
	req.rng_seed = 4242
	req.quality = Ids.Q_LOW
	req.player_count = 2
	Router.set_pending_request(req)
	var host: HuntController = _make(Net.Role.HOST, 0, fallback_remote)
	var client: HuntController = _make(Net.Role.CLIENT, 1, fallback_remote)
	var ok_host: bool = await _wait_ready(host)
	var ok_client: bool = await _wait_ready(client)
	_check("%s_assembled" % label, ok_host and ok_client)
	if not (ok_host and ok_client):
		return
	await _frames(30)

	# --- Roles at assembly, before hunt_go
	_check("%s_host_has_2_hunters" % label, host.get_hunters().size() == 2, str(host.get_hunters().size()))
	_check("%s_client_has_2_hunters" % label, client.get_hunters().size() == 2, str(client.get_hunters().size()))
	_check("%s_local_slots" % label, host.get_local_slot() == 0 and client.get_local_slot() == 1)
	_check("%s_local_first" % label, host.get_hunters()[0] == host.get_player() and client.get_hunters()[0] == client.get_player())
	_check("%s_get_hunter" % label, host.get_hunter(0) == host.get_player() and host.get_hunter(1) != null
		and host.get_hunter(2) == null and client.get_hunter(1) == client.get_player() and client.get_hunter(0) != null)
	_check("%s_remote_not_local" % label, not host.get_hunter(1).is_local() and not client.get_hunter(0).is_local()
		and host.get_hunter(0).is_local())
	_check("%s_remote_slot_and_name" % label, host.get_hunter(1).slot == 1 and host.get_hunter(1).get_display_name() == "Ana"
		and client.get_hunter(0).get_display_name() == "Anfitriao",
		"%s / %s" % [host.get_hunter(1).get_display_name(), client.get_hunter(0).get_display_name()])
	var kind_remote: String = "FallbackRemoteHunter" if fallback_remote else "RemoteHunter"
	_check("%s_remote_kind" % label, (host.get_hunter(1) is FallbackRemoteHunter) == fallback_remote,
		"%s script=%s" % [kind_remote, str(host.get_hunter(1).get_script().resource_path)])
	_check("%s_joined_events" % label, _joined.size() == 2 and _joined.has([1, "Ana"]) and _joined.has([0, "Anfitriao"]), str(_joined))
	var spacing: float = float(Data.get_game()["coop"]["spawn_spacing_m"])
	var gap: float = _xz(host.get_hunter(0).global_position).distance_to(_xz(host.get_hunter(1).global_position))
	_check("%s_spawn_spacing" % label, absf(gap - spacing) < 0.01, "gap=%.3f spacing=%.3f" % [gap, spacing])
	var same_start: bool = _xz(host.get_hunter(0).global_position).distance_to(_xz(client.get_hunter(0).global_position)) < 0.01 \
		and _xz(host.get_hunter(1).global_position).distance_to(_xz(client.get_hunter(1).global_position)) < 0.01
	_check("%s_same_start_positions_both_sides" % label, same_start)
	_check("%s_host_spawner" % label, host.spawner != null and host.spawner.get_total() > 0, "total=%d" % host.get_boars_total())
	_check("%s_client_no_spawner" % label, client.spawner == null and client.get_node_or_null(^"BoarSpawner") == null
		and client.get_boars_total() == 0)
	_check("%s_waiting_for_go" % label, _started == 0 and host.get_elapsed_s() == 0.0 and client.get_elapsed_s() == 0.0
		and host.get_alive_boar_ids().is_empty(), "started=%d" % _started)

	# --- hunt_go releases the hunt
	host.debug_net_go()
	_check("%s_host_started" % label, _started == 1, "started=%d" % _started)
	client.debug_net_go()
	_check("%s_client_started" % label, _started == 2, "started=%d" % _started)
	var waited: float = 0.0
	while host.get_alive_boar_ids().is_empty() and waited < BOAR_WAIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check("%s_host_boars_spawn" % label, not host.get_alive_boar_ids().is_empty(), "alive=%d after %.1fs" % [host.get_alive_boar_ids().size(), waited])
	_check("%s_client_no_boars" % label, client.get_alive_boar_ids().is_empty() and client.get_node(^"Boars").get_child_count() == 0)
	_check("%s_client_not_over" % label, not client.is_hunt_over() and client.get_elapsed_s() > 0.0, "elapsed=%.2f" % client.get_elapsed_s())

	# --- Host -> client: hunters in the snapshot
	_teleport(host, HOST_TELEPORT)
	_send_snapshot(host, client)
	var moved: bool = await _feed_until_at(host, client, 0, HOST_TELEPORT)
	_check("%s_client_sees_host_move" % label, moved, "at=%s want=%s" % [_xz(client.get_hunter(0).global_position), HOST_TELEPORT])
	_teleport(host, HOST_TELEPORT_2)
	moved = await _feed_until_at(host, client, 0, HOST_TELEPORT_2)
	_check("%s_client_follows_host_again" % label, moved, "at=%s want=%s" % [_xz(client.get_hunter(0).global_position), HOST_TELEPORT_2])
	var own_before: Vector3 = client.get_player().global_position
	_send_snapshot(host, client)
	_check("%s_client_ignores_own_slot" % label, client.get_player().global_position.distance_to(own_before) < 0.001)

	# --- Client -> host: C_STATE path (what Net does with the 14 bytes)
	_teleport(client, CLIENT_TELEPORT)
	var state: StreamPeerBuffer = StreamPeerBuffer.new()
	client.get_player().net_write_state(state)
	_check("%s_state_is_14_bytes" % label, state.get_size() == NetCodec.HUNTER_STATE_BYTES, str(state.get_size()))
	var at_host: bool = false
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < FEED_TIMEOUT_MS:
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = state.data_array
		host.get_hunter(1).net_apply_state(inp)
		if _xz(host.get_hunter(1).global_position).distance_to(CLIENT_TELEPORT) <= POS_TOLERANCE_M:
			at_host = true
			break
		await get_tree().process_frame
	_check("%s_host_sees_client_move" % label, at_host, "at=%s want=%s" % [_xz(host.get_hunter(1).global_position), CLIENT_TELEPORT])

	# --- Snapshot layout: header 10 B + 15 B per hunter + n_boars u8 + 7 B per live boar + n_dogs u8 (0)
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	host.net_write_snapshot(out)
	var n_hunters: int = out.data_array[9]
	var n_boars: int = out.data_array[10 + 15 * n_hunters]
	_check("%s_snapshot_layout" % label, n_hunters == 2 and n_boars == host.get_alive_boar_ids().size()
		and out.get_size() == 10 + 15 * n_hunters + 1 + 7 * n_boars + 1,
		"n=%d boars=%d size=%d" % [n_hunters, n_boars, out.get_size()])
	_check("%s_snapshot_relays_client_state" % label, _snapshot_has_slot(out.data_array, 1))
	# Robustness: truncated and empty snapshots do nothing.
	var bad: StreamPeerBuffer = StreamPeerBuffer.new()
	bad.data_array = PackedByteArray([1, 2, 3])
	client.net_apply_snapshot(bad)
	var half: StreamPeerBuffer = StreamPeerBuffer.new()
	half.data_array = out.data_array.slice(0, 20)
	client.net_apply_snapshot(half)
	client.net_apply_snapshot(StreamPeerBuffer.new())
	_check("%s_bad_snapshots_survive" % label, client.get_hunters().size() == 2)
	# The host ignores a snapshot (wrong direction).
	_send_snapshot(client, host)
	_check("%s_host_ignores_snapshot" % label, host.get_hunters().size() == 2)

	# --- Peer leaves / connection lost
	var remote: PlayerBase = host.get_hunter(1)
	host.net_peer_left(1)
	_check("%s_peer_left_hunters" % label, host.get_hunters().size() == 1 and host.get_hunter(1) == null)
	_check("%s_peer_left_event" % label, _left == [1], str(_left))
	host.net_peer_left(1)
	_check("%s_peer_left_idempotent" % label, _left == [1])
	await _frames(3)
	_check("%s_peer_left_node_freed" % label, not is_instance_valid(remote))
	_check("%s_host_survives_peer_left" % label, not host.is_hunt_over() and host.get_player() != null)
	client.net_connection_lost()
	var res: HuntResult = client.get_result()
	_check("%s_client_disconnected_ends" % label, client.is_hunt_over() and res != null
		and res.outcome == HuntResult.Outcome.DISCONNECTED and not res.counts_for_progression and _ended.size() == 1,
		"ended=%d" % _ended.size())

	host.queue_free()
	client.queue_free()
	Router.set_pending_request(null)
	await _frames(3)


func _snapshot_has_slot(data: PackedByteArray, slot: int) -> bool:
	var n: int = data[9]
	for i: int in n:
		if data[10 + i * 15] == slot:
			return true
	return false
