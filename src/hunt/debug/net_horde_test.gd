extends Node
## Package B sandbox of the horde mode over the network (docs/horda.md sections 9.2, 9.3 and 14, "net_horde"): a
## host hunt and a client hunt in one process (test_net_role hooks, client inside a SubViewport with its own
## World3D), wired through the same record byte paths the Net session uses, like net_sync_test.
##   1. after every phase change the client has the host's wave, phase, wave total, remaining and countdown;
##      the stock drains on both and no EV_CROP_EATEN ever goes out;
##   2. the link drops for two phases; the rejoin full sync carries exactly one EV_HORDE_WAVE (after the journal,
##      before any EV_HUNT_END) and no EV_CROP_EATEN, and the client that lost those events catches up;
##   3. the rest of the waves -> VICTORY on both, mode horde, same waves cleared, kills add up to the total.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_horde_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/ (net_unit --only=net_horde).

const WATCHDOG_REAL_S: float = 300.0
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SNAP_INTERVAL_S: float = 0.1
const MAP_ID: StringName = &"mato_grosso"
const SEED: int = 5151
const PLAYERS: int = 2
const ASSEMBLE_S: float = 120.0
const SYNC_WAIT_S: float = 1.0
const SPAWN_WAIT_S: float = 30.0
const EAT_WAIT_S: float = 120.0
const WAVE_KILL_S: float = 120.0
const COUNTDOWN_TOL_S: float = 0.35
const STOCK_TOL_PCT: float = 0.6
const HOST_PARK: Vector2 = Vector2(-118.0, -118.0)
const CLIENT_PARK: Vector2 = Vector2(118.0, -118.0)

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _host: HuntController = null
var _client: HuntController = null
var _vp: SubViewport = null
var _pump_on: bool = false
var _accum: float = 0.0
var _event_types: PackedInt32Array = PackedInt32Array()   # every EV_* the host sent through the pump
var _give_client: int = 0               # kills still to be credited to the client slot


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	await _run()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
		print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed + 1])
		get_tree().quit(1)
		return
	if not _pump_on or _host == null or _client == null:
		return
	_accum += delta
	if _accum >= SNAP_INTERVAL_S:
		_accum = fmod(_accum, SNAP_INTERVAL_S)
		pump()


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _run() -> void:
	if not await _open_pair():
		await _close_pair()
		return
	var n: int = _host.get_horde_wave_count()
	var planned: int = 0
	for wave_groups: Variant in HordeDirector.plan_waves(Data.get_horde(), PLAYERS):
		for g: Variant in wave_groups:
			planned += ((g as Dictionary)["members"] as Array).size()
	_check("host_horde_scaled_for_2", _host.is_horde() and _client.is_horde() and n == (Data.get_horde()["waves"] as Array).size()
		and _host.get_boars_total() == planned, "waves=%d total=%d planned=%d" % [n, _host.get_boars_total(), planned])
	_check("client_before_first_event", _client.get_horde_wave() == 0 and _client.get_horde_phase() == &""
		and _client.get_horde_wave_count() == 0)
	_check("objective_on_both", _host.get_objective_position().is_finite()
		and _host.get_objective_position().distance_to(_client.get_objective_position()) < 0.01)
	_park(_host, HOST_PARK)
	_park(_client, CLIENT_PARK)

	# 1. Wave 1 announced, started, eaten at, killed: the client follows every phase.
	await _wait_s(SYNC_WAIT_S)
	_check_same("intermission_1")
	_host.debug_horde_start_next_wave()
	_client.debug_horde_start_next_wave()   # a client's call must do nothing
	await _wait_s(SYNC_WAIT_S)
	_check_same("wave_1_started")
	var eating: bool = await _wait_until(func() -> bool:
		return _host.crop.get_eater_count() >= 1 and _host.get_crop_health_pct() < 99.0, EAT_WAIT_S)
	await _wait_s(SYNC_WAIT_S)
	_check("stock_drains_on_both", eating and absf(_host.get_crop_health_pct() - _client.get_crop_health_pct()) <= STOCK_TOL_PCT
		and _host.crop.get_patch_eaten() == 0 and _client.crop.get_patch_eaten() == 0,
		"host=%.2f client=%.2f eaters=%d" % [_host.get_crop_health_pct(), _client.get_crop_health_pct(), _host.crop.get_eater_count()])
	var ids: Array[int] = _alive_of_wave(0)
	if ids.size() >= 2:
		_kill(ids[0], CLIENT_SLOT)
		await _wait_s(SYNC_WAIT_S)
		_check_same("wave_1_after_a_kill")
	_give_client = 1
	var cleared: bool = await _clear_wave(0)
	await _wait_s(SYNC_WAIT_S)
	_check("wave_1_cleared", cleared)
	_check_same("intermission_2")
	_check("client_waves_cleared_1", _client.get_horde_waves_cleared() == 1 and _host.get_horde_waves_cleared() == 1)
	_check("no_crop_eaten_records", _event_types.count(NetCodec.EV_CROP_EATEN) == 0 and _event_types.count(NetCodec.EV_HORDE_WAVE) == 3,
		"horde_wave=%d crop_eaten=%d" % [_event_types.count(NetCodec.EV_HORDE_WAVE), _event_types.count(NetCodec.EV_CROP_EATEN)])

	# 2. The link drops; the host plays wave 2 to the end and starts wave 3 with a kill.
	_pump_on = false
	GameEvents.net_reconnect_changed.emit(true)
	_host.debug_horde_start_next_wave()
	await _wait_s(0.1)
	_give_client = 1
	cleared = await _clear_wave(1)
	_host.debug_horde_start_next_wave()
	await _wait_until(func() -> bool: return _alive_of_wave(2).size() >= 2, SPAWN_WAIT_S)
	var w3: Array[int] = _alive_of_wave(2)
	if not w3.is_empty():
		_kill(w3[0], CLIENT_SLOT)
	await _wait_s(0.2)
	_check("drop_client_is_behind", cleared and _host.get_horde_wave() == 3 and _host.get_horde_phase() == Ids.HP_WAVE
		and _client.get_horde_wave() == 2 and _client.get_horde_phase() == Ids.HP_INTERMISSION,
		"host %d/%s client %d/%s" % [_host.get_horde_wave(), _host.get_horde_phase(), _client.get_horde_wave(), _client.get_horde_phase()])
	var drain: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(drain)   # what the other links get before the cut (section 4.7.4)
	var drained: PackedInt32Array = _record_types(drain.data_array)
	_check("drop_events_queued_on_host", drained.count(NetCodec.EV_HORDE_WAVE) == 3 and drained.count(NetCodec.EV_CROP_EATEN) == 0,
		"horde_wave=%d" % drained.count(NetCodec.EV_HORDE_WAVE))
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_full_sync(out)
	var data: PackedByteArray = out.data_array
	var types: PackedInt32Array = _record_types(data)
	var wave_at: int = types.find(NetCodec.EV_HORDE_WAVE)
	var last_journal: int = maxi(_last_index(types, NetCodec.EV_BOAR_SPAWN), _last_index(types, NetCodec.EV_BOAR_DEATH))
	_check("full_sync_one_horde_wave_no_patches", types.size() > 1 and types[0] == NetCodec.EV_FULL_SYNC
		and types.count(NetCodec.EV_HORDE_WAVE) == 1 and types.count(NetCodec.EV_CROP_EATEN) == 0 and wave_at > last_journal
		and types.count(NetCodec.EV_HUNT_END) == 0 and data.decode_u16(11) == types.size() - 1,
		"records=%d horde_wave@%d last_journal@%d crop_eaten=%d" % [types.size() - 1, wave_at, last_journal, types.count(NetCodec.EV_CROP_EATEN)])
	_check("full_sync_horde_wave_bytes", _horde_wave_body_ok(data, wave_at), "")
	_apply_events(data)
	GameEvents.net_reconnect_changed.emit(false)
	_check_same("after_full_sync")
	_check("after_full_sync_counts", _client.get_boars_killed() == _host.get_boars_killed()
		and _client.get_horde_waves_cleared() == 2 and _client.debug_partial_result().kills.size() == 4,
		"killed %d/%d cleared=%d own=%d" % [_client.get_boars_killed(), _host.get_boars_killed(), _client.get_horde_waves_cleared(),
		_client.debug_partial_result().kills.size()])
	var digest: Array = _wave_state(_client)
	_apply_events(data)
	_check("full_sync_twice_same_wave_state", _wave_state(_client) == digest, "%s vs %s" % [digest, _wave_state(_client)])

	# 3. Back online: the rest of the hunt.
	_pump_on = true
	await _wait_s(SYNC_WAIT_S)
	_check_same("wave_3_after_rejoin")
	var all_done: bool = true
	for w: int in range(2, n):
		if _host.is_hunt_over():
			break
		if _host.get_horde_phase() == Ids.HP_INTERMISSION:
			_host.debug_horde_start_next_wave()
			await _wait_s(0.1)
		all_done = all_done and await _clear_wave(w)
		await _wait_s(SYNC_WAIT_S)
		if w < n - 1:
			_check_same("intermission_%d" % (w + 2))
	await _wait_until(func() -> bool: return _client.is_hunt_over(), 5.0)
	var h: HuntResult = _host.get_result()
	var c: HuntResult = _client.get_result()
	_check("victory_on_both", all_done and h != null and c != null and h.outcome == HuntResult.Outcome.VICTORY
		and c.outcome == HuntResult.Outcome.VICTORY, "host=%s client=%s" % [_outcome_name(h), _outcome_name(c)])
	if h != null and c != null:
		_check("client_result_horde", c.mode == Ids.MODE_HORDE and h.mode == Ids.MODE_HORDE and not c.counts_for_progression
			and not h.counts_for_progression)
		_check("same_waves_cleared", c.horde_waves_cleared == h.horde_waves_cleared and c.horde_wave_count == h.horde_wave_count
			and h.horde_waves_cleared == n, "host %d/%d client %d/%d" % [h.horde_waves_cleared, h.horde_wave_count, c.horde_waves_cleared, c.horde_wave_count])
		_check("same_bonus", c.contract_bonus == h.contract_bonus and h.contract_bonus == Profile.horde_bonus(h.crop_health_pct),
			"host=%d client=%d" % [h.contract_bonus, c.contract_bonus])
		_check("kills_add_up", h.kills.size() + c.kills.size() == planned and c.team_kills == planned and c.boars_total == planned,
			"host=%d client=%d total=%d" % [h.kills.size(), c.kills.size(), planned])
		var rewards: bool = true
		for k: KillInfo in c.kills:
			rewards = rewards and k.reward_money == Profile.horde_kill_reward(k.type_id, k.weight_kg, k.killing_zone, k.one_shot)
		_check("client_rewards_from_host", rewards and c.money_from_kills > 0)
	_check("never_crop_eaten", _event_types.count(NetCodec.EV_CROP_EATEN) == 0 and _host.crop.get_patch_eaten() == 0)
	_check("two_horde_wave_events_per_wave", _event_types.count(NetCodec.EV_HORDE_WAVE) + 3 == 2 * n,
		"pumped=%d + 3 in the drop, wanted %d" % [_event_types.count(NetCodec.EV_HORDE_WAVE), 2 * n])
	await _close_pair()


## The client agrees with the host on the wave state (the countdown within one pump of lag).
func _check_same(label: String) -> void:
	var hs: Array = _wave_state(_host)
	var cs: Array = _wave_state(_client)
	var cd_ok: bool = absf(_host.get_horde_countdown_s() - _client.get_horde_countdown_s()) <= COUNTDOWN_TOL_S
	_check("same_state_" + label, hs == cs and cd_ok and hs[0] >= 1,
		"host=%s cd=%.2f client=%s cd=%.2f" % [hs, _host.get_horde_countdown_s(), cs, _client.get_horde_countdown_s()])


func _wave_state(world: HuntController) -> Array:
	return [world.get_horde_wave(), world.get_horde_wave_count(), world.get_horde_phase(), world.get_horde_wave_total(),
		world.get_horde_wave_remaining()]


## EV_HORDE_WAVE body of the full sync = the host's state now.
func _horde_wave_body_ok(data: PackedByteArray, record_index: int) -> bool:
	if record_index < 0:
		return false
	var pos: int = 0
	for i: int in record_index:
		pos += 3 + data.decode_u16(pos + 1)
	if data.decode_u16(pos + 1) != 7:
		return false
	var b: int = pos + 3
	return data[b] == _host.get_horde_wave() and data[b + 1] == _host.get_horde_wave_count() \
		and data[b + 2] == NetCodec.HORDE_PHASES.find(_host.get_horde_phase()) and data.decode_u16(b + 3) == 0 \
		and data[b + 5] == _host.get_horde_wave_total() \
		and data[b + 6] == _host.get_boars_killed() - (_host.get_horde_wave_total() - _host.get_horde_wave_remaining())


func _alive_of_wave(wave_index: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in _host.get_alive_boar_ids():
		var b: Boar = _host.spawner.get_boar(id)
		if b != null and b.wave == wave_index:
			out.append(id)
	return out


## Kills every boar of that wave as it is born (the first _give_client of them for the client).
func _clear_wave(wave_index: int) -> bool:
	return await _wait_until(func() -> bool:
		for id: int in _alive_of_wave(wave_index):
			if _give_client > 0:
				_give_client -= 1
				_kill(id, CLIENT_SLOT)
			else:
				_kill(id, HOST_SLOT)
		return _host.get_horde_waves_cleared() > wave_index or _host.is_hunt_over(), WAVE_KILL_S)


# --- Pair plumbing (same as net_sync_test) --------------------------------------------------------

func _roster() -> Array[NetPeerInfo]:
	var out: Array[NetPeerInfo] = []
	for i: int in PLAYERS:
		var info: NetPeerInfo = NetPeerInfo.new()
		info.slot = i
		info.display_name = "Anfitriao" if i == HOST_SLOT else "Cliente"
		info.is_host = i == HOST_SLOT
		info.weapon_id = Ids.W_CARBINE_22
		out.append(info)
	return out


func _make(role: int, local_slot: int, parent: Node) -> HuntController:
	var hunt: HuntController = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	hunt.route_on_finish = false
	hunt.test_net_role = role
	hunt.test_net_local_slot = local_slot
	hunt.test_net_roster = _roster()
	hunt.test_fallback_remote = true
	parent.add_child(hunt)
	return hunt


func _open_pair() -> bool:
	var req: HuntRequest = HuntRequest.make_debug(MAP_ID, 0, Ids.MODE_HORDE)
	req.rng_seed = SEED
	req.quality = Ids.Q_LOW
	req.player_count = PLAYERS
	Router.set_pending_request(req)
	_host = _make(Net.Role.HOST, HOST_SLOT, self)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_client = _make(Net.Role.CLIENT, CLIENT_SLOT, _vp)
	var ok: bool = await _wait_until(func() -> bool: return _host.is_world_ready() and _client.is_world_ready(), ASSEMBLE_S)
	_check("pair_assembled", ok)
	if not ok:
		return false
	_host.debug_net_go()
	_client.debug_net_go()
	_pump_on = true
	return true


func _close_pair() -> void:
	_pump_on = false
	GameEvents.net_reconnect_changed.emit(false)
	if _host != null:
		_host.queue_free()
	if _vp != null:
		_vp.queue_free()
	_host = null
	_client = null
	_vp = null
	Router.set_pending_request(null)
	await get_tree().process_frame
	await get_tree().process_frame


## Host -> client and client -> host, through the record byte paths Net uses.
func pump() -> void:
	var snap: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_snapshot(snap)
	var sin: StreamPeerBuffer = StreamPeerBuffer.new()
	sin.data_array = snap.data_array
	_client.net_apply_snapshot(sin)
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)
	_event_types.append_array(_record_types(ev.data_array))
	_apply_events(ev.data_array)
	var cl: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.net_take_claims(cl)
	_for_records(cl.data_array, func(type: int, i: StreamPeerBuffer, n: int) -> void: _host.net_apply_claim(CLIENT_SLOT, type, i, n))


func _apply_events(data: PackedByteArray) -> void:
	_for_records(data, func(type: int, i: StreamPeerBuffer, n: int) -> void: _client.net_apply_event(type, i, n))


func _for_records(data: PackedByteArray, fn: Callable) -> void:
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= data.size():
		var type: int = data[pos]
		var n: int = data.decode_u16(pos + 1)
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = data.slice(pos + 3, pos + 3 + n)
		fn.call(type, inp, n)
		pos += 3 + n


func _record_types(data: PackedByteArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= data.size():
		out.append(data[pos])
		pos += 3 + data.decode_u16(pos + 1)
	return out


func _last_index(types: PackedInt32Array, type: int) -> int:
	for i: int in range(types.size() - 1, -1, -1):
		if types[i] == type:
			return i
	return -1


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t: float = 0.0
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()):
		if t > timeout_s or float(Time.get_ticks_msec() - t0) > timeout_s * 1000.0 * 4.0:
			return false
		await get_tree().process_frame
		t += get_process_delta_time()
	return true


func _wait_s(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _park(world: HuntController, xz: Vector2) -> void:
	var player: PlayerBase = world.get_player()
	player.bot_set_enabled(true)
	player.bot_teleport(Vector3(xz.x, world.get_height(xz.x, xz.y) + 0.1, xz.y))


func _kill(boar_id: int, killer: int) -> void:
	var b: Boar = _host.spawner.get_boar(boar_id)
	if b != null and b.is_alive():
		b.killer_slot = killer
		b.debug_kill()


func _outcome_name(r: HuntResult) -> String:
	return HuntResult.Outcome.keys()[r.outcome] if r != null else "null"
