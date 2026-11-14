extends Node
## Package B sandbox for F5 (docs/multiplayer.md section 9, F5): crop, items, end of hunt, drops and economy
## of a network hunt, in one process and without the Net autoload. A host hunt and a client hunt (inside a
## SubViewport with its own World3D) are wired through the real byte paths (H_SNAPSHOT, EV_*, C_STATE, C_*),
## like net_boars_test. Slots: host 0, client 1 (no real weapon shots here, so Net's slot 0 does not matter).
## Both hunts share GameEvents, so this sandbox calls the controllers' handlers directly instead of emitting
## bus signals that both would hear (item_used, hunt_abandon_requested).
## Cases (one fresh host/client pair each):
##   scale     BoarSpawner.scale_groups numbers (pure function) and the host total with 2 hunters.
##   features  crop mirror (same eaten indices, health, under-attack flag), bait both ways (no duplicate echo),
##             thermal on puppets, drone getters, group message; ends by crop -> DEFEAT_CROP on both.
##   death     client dies (hunt goes on, hunter_died on both), host dies -> DEFEAT_DEATH on both.
##   victory   kills split between the two -> VICTORY on both; economy and scoreboard match.
##   drop      client credited 1 kill; client leaves (host: net_peer_left) and loses the host (client:
##             net_connection_lost) -> client DISCONNECTED, paid, no bonus, no progression; host wins alone.
##   abandon   host abandons -> both ABANDONED, client without progression.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_flow_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 600.0
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SNAP_INTERVAL_S: float = 0.1
const MAP_ID: StringName = &"mato_grosso"
const CONTRACT: int = 0
const SEED: int = 5151
const ASSEMBLE_S: float = 120.0
const BOAR_WAIT_S: float = 30.0
const END_WAIT_S: float = 3.0
const ALL_SPAWN_S: float = 150.0
const CLIENT_KILLS: int = 3
const DRAIN_PCT_PER_S: float = 6.0
const DRAIN_S: float = 1.5
const EATER_ID: int = 900
const BAIT_OFFSET: Vector3 = Vector3(6.0, 0.0, 4.0)
const THERMAL_WAIT_S: float = 0.6
const KILL_DAMAGE: float = 100000.0
const WEIGHT_TOL_KG: float = 0.05
const REMOTE_STATE_MS: int = 3000

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _host: HuntController = null
var _client: HuntController = null
var _vp: SubViewport = null
var _pump_on: bool = false
var _accum: float = 0.0
var _pump_real: bool = false
var _last_pump_ms: int = 0
var _died: Array[int] = []              # hunter_died slots, from both hunts (shared bus)
var _left: Array[int] = []
var _messages: int = 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	GameEvents.hunter_died.connect(func(s: int) -> void: _died.append(s))
	GameEvents.hunter_left.connect(func(s: int) -> void: _left.append(s))
	_scale_case()
	await _features_case()
	await _death_case()
	await _victory_case()
	await _drop_case()
	await _abandon_case()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
		get_tree().quit(1)
		return
	if _pump_on and _pump_real and _host != null and _client != null:
		if Time.get_ticks_msec() - _last_pump_ms >= int(SNAP_INTERVAL_S * 1000.0):
			_last_pump_ms = Time.get_ticks_msec()
			pump()
	elif _pump_on and _host != null and _client != null:
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


# --- Scale (section 6.10) ------------------------------------------------------------------------

func _scale_case() -> void:
	print("--- scale")
	var coop: Dictionary = Data.get_game().get("coop", {})
	var c0: Array = Data.get_contract(MAP_ID, 0).get("groups", [])
	var c1: Array = Data.get_contract(MAP_ID, 1).get("groups", [])
	_check("scale_first_contract_1_2_4", _sum(BoarSpawner.scale_groups(c0, 1, coop)) == _sum(c0)
		and _sum(BoarSpawner.scale_groups(c0, 2, coop)) == 14 and _sum(BoarSpawner.scale_groups(c0, 4, coop)) == 23,
		"base=%d 2p=%d 3p=%d 4p=%d" % [_sum(c0), _sum(BoarSpawner.scale_groups(c0, 2, coop)),
		_sum(BoarSpawner.scale_groups(c0, 3, coop)), _sum(BoarSpawner.scale_groups(c0, 4, coop))])
	print("INFO contract index 1: base=%d 2p=%d 4p=%d" % [_sum(c1), _sum(BoarSpawner.scale_groups(c1, 2, coop)),
		_sum(BoarSpawner.scale_groups(c1, 4, coop))])
	var solo: Array = BoarSpawner.scale_groups(c0, 1, coop)
	_check("scale_solo_is_unchanged_copy", solo == c0 and solo != null and not is_same(solo, c0))
	var g4: Array = BoarSpawner.scale_groups(c0, 4, coop)
	var max_delay: float = 0.0
	for g: Dictionary in c0:
		max_delay = maxf(max_delay, float(g.get("delay_s", 0.0)))
	var clones_ok: bool = true
	for i: int in range(c0.size(), g4.size()):
		var g: Dictionary = g4[i]
		var members: Array = g["members"]
		clones_ok = clones_ok and not members.is_empty() and not members.has("alpha") \
			and float(g["delay_s"]) > max_delay and float(g["delay_s"]) > float((g4[i - 1] as Dictionary)["delay_s"]) - 0.001
	_check("scale_clones_after_contract_no_alpha", clones_ok and g4.size() > c0.size(), str(g4.slice(c0.size())))
	var worst: int = 0
	for map_id: Variant in Data.get_map_ids():
		for index: int in Data.get_contract_count(StringName(map_id)):
			var gs: Array = Data.get_contract(StringName(map_id), index).get("groups", [])
			worst = maxi(worst, _sum(BoarSpawner.scale_groups(gs, int(Data.get_net().get("max_players", 4)), coop)))
	_check("scale_ids_fit_u8", worst <= HuntHostSync.MAX_WIRE_ID, "largest scaled contract=%d boars" % worst)
	var alpha_contract: Array = Data.get_contract(MAP_ID, Data.get_contract_count(MAP_ID) - 1).get("groups", [])
	var ga: Array = BoarSpawner.scale_groups(alpha_contract, 4, coop)
	var alphas: int = 0
	for g: Dictionary in ga:
		alphas += (g["members"] as Array).count("alpha")
	var alphas_base: int = 0
	for g: Dictionary in alpha_contract:
		alphas_base += (g["members"] as Array).count("alpha")
	_check("scale_never_clones_alpha", alphas == alphas_base, "alphas %d -> %d, total %d" % [alphas_base, alphas, _sum(ga)])


func _sum(groups: Array) -> int:
	var n: int = 0
	for g: Variant in groups:
		n += ((g as Dictionary).get("members", []) as Array).size()
	return n


# --- Pair plumbing -------------------------------------------------------------------------------

func _roster() -> Array[NetPeerInfo]:
	var out: Array[NetPeerInfo] = []
	for i: int in 2:
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
	parent.add_child(hunt)
	return hunt


func _open_pair(label: String) -> bool:
	print("--- " + label)
	var req: HuntRequest = HuntRequest.make_debug(MAP_ID, CONTRACT)
	req.rng_seed = SEED
	req.quality = Ids.Q_LOW
	req.player_count = 2
	req.item_ids = [Ids.I_CORN_BAIT]
	req.item_counts = {Ids.I_CORN_BAIT: 3}
	Router.set_pending_request(req)
	_host = _make(Net.Role.HOST, HOST_SLOT, self)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_client = _make(Net.Role.CLIENT, CLIENT_SLOT, _vp)
	var ok: bool = await _wait_until(func() -> bool: return _host.is_world_ready() and _client.is_world_ready(), ASSEMBLE_S)
	_check("%s_assembled" % label, ok)
	if not ok:
		return false
	_died.clear()
	_left.clear()
	_host.debug_net_go()
	_client.debug_net_go()
	_pump_on = true
	return true


func _close_pair() -> void:
	_pump_on = false
	_pump_real = false
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
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = snap.data_array
	_client.net_apply_snapshot(inp)
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)
	_for_records(ev.data_array, func(type: int, i: StreamPeerBuffer, n: int) -> void: _client.net_apply_event(type, i, n))
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	if remote != null and not remote.is_local():
		var st: StreamPeerBuffer = StreamPeerBuffer.new()
		_client.get_player().net_write_state(st)
		if st.get_size() == NetCodec.HUNTER_STATE_BYTES:
			var sin: StreamPeerBuffer = StreamPeerBuffer.new()
			sin.data_array = st.data_array
			remote.net_apply_state(sin)
	var cl: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.net_take_claims(cl)
	if remote != null:
		_for_records(cl.data_array, func(type: int, i: StreamPeerBuffer, n: int) -> void: _host.net_apply_claim(CLIENT_SLOT, type, i, n))


func _for_records(data: PackedByteArray, fn: Callable) -> void:
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= data.size():
		var type: int = data[pos]
		var n: int = data.decode_u16(pos + 1)
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = data.slice(pos + 3, pos + 3 + n)
		fn.call(type, inp, n)
		pos += 3 + n


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t: float = 0.0
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()):
		if t > timeout_s or float(Time.get_ticks_msec() - t0) > timeout_s * 1000.0 * 4.0:
			return false
		await get_tree().process_frame
		t += get_process_delta_time()
	return true


func _until_real(cond: Callable, timeout_ms: int) -> bool:
	var limit: int = Time.get_ticks_msec() + timeout_ms
	while not bool(cond.call()):
		if Time.get_ticks_msec() > limit:
			return false
		await get_tree().process_frame
	return true


func _wait_s(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _outcome_name(r: HuntResult) -> String:
	return HuntResult.Outcome.keys()[r.outcome] if r != null else "null"


func _both_ended(outcome: HuntResult.Outcome) -> bool:
	var h: HuntResult = _host.get_result()
	var c: HuntResult = _client.get_result()
	return h != null and c != null and h.outcome == outcome and c.outcome == outcome


func _kill(boar_id: int, killer: int) -> void:
	var b: Boar = _host.spawner.get_boar(boar_id)
	if b != null and b.is_alive():
		b.killer_slot = killer
		b.debug_kill()


## Kills every boar of the contract as it spawns; the first `client_kills` go to the client.
func _kill_all(client_kills: int) -> bool:
	var given: Array[int] = [0]
	return await _wait_until(func() -> bool:
		for id: int in _host.get_alive_boar_ids().duplicate():
			var to_client: bool = given[0] < client_kills
			if to_client:
				given[0] += 1
			_kill(id, CLIENT_SLOT if to_client else HOST_SLOT)
		return _host.is_hunt_over(), ALL_SPAWN_S)


# --- Features: crop, items, messages; crop defeat -------------------------------------------------

func _features_case() -> void:
	if not await _open_pair("features"):
		await _close_pair()
		return
	await _wait_until(func() -> bool: return _host.get_alive_boar_ids().size() >= 3, BOAR_WAIT_S)
	await _crop_checks()
	await _bait_checks()
	await _thermal_and_drone_checks()
	await _message_checks()
	# Crop defeat: decided on the host, the same outcome on the client.
	_host.debug_set_crop_health(0.0)
	var ended: bool = await _wait_until(func() -> bool: return _both_ended(HuntResult.Outcome.DEFEAT_CROP), END_WAIT_S)
	_check("crop_defeat_on_both", ended, "host=%s client=%s" % [_outcome_name(_host.get_result()), _outcome_name(_client.get_result())])
	await _wait_s(0.3)
	var he: PackedInt32Array = _host.crop.get_eaten_indices()
	var ce: PackedInt32Array = _client.crop.get_eaten_indices()
	_check("crop_defeat_same_eaten_patches", he == ce and he.size() > 0, "host=%d client=%d" % [he.size(), ce.size()])
	if ended:
		_check("crop_defeat_client_crop_zero", is_zero_approx(_client.get_result().crop_health_pct)
			and _client.get_result().contract_bonus == 0, "crop=%.2f" % _client.get_result().crop_health_pct)
	await _close_pair()


func _crop_checks() -> void:
	var host_crop: CropManager = _host.crop
	var at: Vector2 = host_crop.get_rects()[0].get_center()
	host_crop.register_eater(EATER_ID, DRAIN_PCT_PER_S, at)
	await _wait_s(DRAIN_S)
	_check("crop_attack_flag_reaches_client", _client.crop.is_under_attack(), "host eaters=%d" % host_crop.get_eater_count())
	host_crop.unregister_eater(EATER_ID)
	# Other eaters may be real boars: the client mirrors the host's flag either way.
	await _wait_s(0.4)
	_check("crop_attack_flag_mirrors_host", _client.crop.is_under_attack() == (host_crop.get_eater_count() > 0),
		"host eaters=%d client=%s" % [host_crop.get_eater_count(), str(_client.crop.is_under_attack())])
	var he: PackedInt32Array = host_crop.get_eaten_indices()
	var ce: PackedInt32Array = _client.crop.get_eaten_indices()
	_check("crop_same_eaten_patches", he == ce and he.size() > 0, "host=%d client=%d" % [he.size(), ce.size()])
	_check("crop_health_mirrored", absf(_client.get_crop_health_pct() - host_crop.get_health_pct()) <= 0.02
		and host_crop.get_health_pct() < 100.0,
		"host=%.3f client=%.3f" % [host_crop.get_health_pct(), _client.get_crop_health_pct()])
	_host.debug_set_crop_health(60.0)
	await _wait_s(0.3)
	he = host_crop.get_eaten_indices()
	ce = _client.crop.get_eaten_indices()
	_check("crop_bulk_same_patches", he == ce and he.size() > 900, "host=%d client=%d (sent %d)"
		% [he.size(), ce.size(), _host.debug_host_sync().patches_sent])


func _bait_checks() -> void:
	var host_baits0: int = _host.get_baits().size()
	var client_baits0: int = _client.get_baits().size()
	var cp: Vector3 = _client.get_player().global_position + BAIT_OFFSET
	_client._on_item_used(Ids.I_CORN_BAIT, cp)
	_check("client_bait_shows_at_once", _client.get_baits().size() == client_baits0 + 1)
	await _wait_s(0.4)
	_check("client_bait_placed_on_host", _host.get_baits().size() == host_baits0 + 1
		and _host.debug_host_sync().baits_claimed == 1, "host baits %d -> %d" % [host_baits0, _host.get_baits().size()])
	var hb: Bait = _host.get_baits()[-1] if not _host.get_baits().is_empty() else null
	_check("client_bait_attracts_on_host", hb != null and hb.get_xz().distance_to(Vector2(cp.x, cp.z)) < 0.05
		and _host.find_bait(hb.get_xz(), EATER_ID) == hb)
	if hb != null:
		hb.release(EATER_ID)
	_check("client_bait_echo_not_duplicated", _client.get_baits().size() == client_baits0 + 1, str(_client.get_baits().size()))
	var hp: Vector3 = _host.get_player().global_position - BAIT_OFFSET
	_host._on_item_used(Ids.I_CORN_BAIT, hp)
	await _wait_s(0.4)
	var cb: Bait = _client.get_baits()[-1] if not _client.get_baits().is_empty() else null
	_check("host_bait_appears_on_client", _client.get_baits().size() == client_baits0 + 2 and cb != null
		and cb.get_xz().distance_to(Vector2(hp.x, hp.z)) < 0.05 and absf(cb.duration_s - _host.get_baits()[-1].duration_s) <= 0.5)
	_check("consumables_counted_per_machine",
		int(_client.debug_partial_result().consumables_used.get(Ids.I_CORN_BAIT, 0)) == 1
		and int(_host.debug_partial_result().consumables_used.get(Ids.I_CORN_BAIT, 0)) == 1)


func _thermal_and_drone_checks() -> void:
	var replica: HuntReplica = _client.debug_replica()
	var ids: PackedInt32Array = _client.get_alive_boar_ids()
	var host_ids: PackedInt32Array = _host.get_alive_boar_ids().duplicate()
	var sorted_ids: PackedInt32Array = ids.duplicate()
	sorted_ids.sort()
	host_ids.sort()
	var positions_ok: bool = not ids.is_empty()
	for id: int in ids:
		positions_ok = positions_ok and _client.get_boar_position(id) != Vector3.INF
	_check("drone_sees_puppets", positions_ok and sorted_ids == host_ids and _client.get_nearest_boar_position(
		_client.get_player().global_position) != Vector3.INF, "client=%s host=%s" % [sorted_ids, host_ids])
	if ids.is_empty():
		return
	var range_m: float = float(Data.get_equipment(Ids.I_THERMAL_SCOPE)["effect"]["highlight_range_m"])
	var near: Vector3 = _client.get_boar_position(ids[0])
	_client.get_player().bot_set_enabled(true)
	_client.get_player().bot_teleport(Vector3(near.x + 5.0, _client.get_height(near.x + 5.0, near.z) + 0.05, near.z))
	GameEvents.thermal_vision_changed.emit(true)
	await _wait_s(THERMAL_WAIT_S)
	var right: bool = true
	var lit: int = 0
	var me: Vector2 = Vector2(_client.get_player().global_position.x, _client.get_player().global_position.z)
	for id: int in _client.get_alive_boar_ids():
		var p: BoarPuppet = replica.get_puppet(id)
		var want: bool = me.distance_to(p.get_xz()) <= range_m
		right = right and p.is_highlighted() == want
		lit += 1 if p.is_highlighted() else 0
	_check("thermal_highlights_puppets_in_range", right and lit >= 1, "lit=%d of %d" % [lit, _client.get_alive_boar_ids().size()])
	GameEvents.thermal_vision_changed.emit(false)
	await get_tree().process_frame
	var off: bool = true
	for id: int in _client.get_alive_boar_ids():
		off = off and not replica.get_puppet(id).is_highlighted()
	_check("thermal_off_clears_puppets", off)


func _message_checks() -> void:
	var replica: HuntReplica = _client.debug_replica()
	_messages = 0
	var count_fn: Callable = func(_m: int) -> void: _messages += 1
	replica.message_received.connect(count_fn)
	_host._on_group_entered(&"alpha", 6)
	await _wait_s(0.3)
	replica.message_received.disconnect(count_fn)
	_check("group_message_reaches_client", _messages == 1, str(_messages))


# --- Death ----------------------------------------------------------------------------------------

func _death_case() -> void:
	if not await _open_pair("death"):
		await _close_pair()
		return
	await _wait_s(0.5)
	var cp: PlayerBase = _client.get_player()
	cp.apply_damage(KILL_DAMAGE, cp.global_position + Vector3.FORWARD)
	# RemoteHunter interpolates on the wall clock (net.hunter_interp_delay_ms): headless --fixed-fps runs
	# faster than real time, so here the pump follows the wall clock too (as Net does in a real hunt).
	_pump_real = true
	await _until_real(func() -> bool: return _died.count(CLIENT_SLOT) >= 2, REMOTE_STATE_MS)
	await _wait_s(0.5)
	_check("client_dead_hunt_goes_on", not cp.is_alive() and not _host.is_hunt_over() and not _client.is_hunt_over())
	_check("hunter_died_on_both_for_client", _died.count(CLIENT_SLOT) == 2, "died=%s" % str(_died))
	var hp: PlayerBase = _host.get_player()
	hp.apply_damage(KILL_DAMAGE, hp.global_position + Vector3.FORWARD)
	var ended: bool = await _until_real(func() -> bool: return _both_ended(HuntResult.Outcome.DEFEAT_DEATH), REMOTE_STATE_MS)
	_check("all_dead_defeat_on_both", ended, "host=%s client=%s" % [_outcome_name(_host.get_result()), _outcome_name(_client.get_result())])
	_check("hunter_died_for_host", _died.count(HOST_SLOT) >= 1, "died=%s" % str(_died))
	await _close_pair()


# --- Victory and economy -------------------------------------------------------------------------

func _victory_case() -> void:
	if not await _open_pair("victory"):
		await _close_pair()
		return
	var total: int = _host.get_boars_total()
	_check("host_total_scaled_for_two", total == 14, str(total))
	var done: bool = await _kill_all(CLIENT_KILLS)
	await _wait_s(0.5)
	var ended: bool = _both_ended(HuntResult.Outcome.VICTORY)
	_check("victory_on_both", done and ended, "host=%s client=%s" % [_outcome_name(_host.get_result()), _outcome_name(_client.get_result())])
	if not ended:
		await _close_pair()
		return
	var h: HuntResult = _host.get_result()
	var c: HuntResult = _client.get_result()
	_check("kills_add_up", h.kills.size() + c.kills.size() == total and c.kills.size() == CLIENT_KILLS,
		"%d + %d = %d" % [h.kills.size(), c.kills.size(), total])
	_check("team_kills_and_player_count", h.team_kills == total and c.team_kills == total and h.player_count == 2
		and c.player_count == 2 and c.boars_total == total)
	_check("money_only_own_kills", h.money_from_kills == _money(h) and c.money_from_kills == _money(c) and c.money_from_kills > 0)
	var bonus: int = Profile.contract_bonus(MAP_ID, CONTRACT, h.crop_health_pct)
	_check("full_bonus_each", h.contract_bonus == bonus and c.contract_bonus == bonus and bonus > 0,
		"host=%d client=%d expected=%d" % [h.contract_bonus, c.contract_bonus, bonus])
	_check("total_money_each", h.total_money == h.money_from_kills + bonus and c.total_money == c.money_from_kills + bonus)
	_check("progression_counts", h.counts_for_progression and c.counts_for_progression)
	_check("scoreboards_match", _boards_match(h.scoreboard, c.scoreboard), "host=%s client=%s" % [h.scoreboard, c.scoreboard])
	var by_slot: Dictionary = {}
	for e: Dictionary in h.scoreboard:
		by_slot[int(e["slot"])] = e
	_check("scoreboard_values", by_slot.size() == 2 and int(by_slot[CLIENT_SLOT]["kills"]) == c.kills.size()
		and int(by_slot[CLIENT_SLOT]["money"]) == c.money_from_kills and int(by_slot[HOST_SLOT]["money"]) == h.money_from_kills
		and absf(float(by_slot[CLIENT_SLOT]["weight_kg"]) - _weight(c)) < WEIGHT_TOL_KG
		and str(by_slot[CLIENT_SLOT]["name"]) == "Cliente", str(by_slot))
	_check("crop_same_at_end", _host.crop.get_eaten_indices() == _client.crop.get_eaten_indices()
		and absf(h.crop_health_pct - c.crop_health_pct) <= 0.01, "%.3f / %.3f" % [h.crop_health_pct, c.crop_health_pct])
	await _close_pair()


func _money(r: HuntResult) -> int:
	var m: int = 0
	for k: KillInfo in r.kills:
		m += k.reward_money
	return m


func _weight(r: HuntResult) -> float:
	var w: float = 0.0
	for k: KillInfo in r.kills:
		w += k.weight_kg
	return w


func _boards_match(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i: int in a.size():
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		var keys_ok: bool = x.has("slot") and x.has("name") and x.has("kills") and x.has("money") and x.has("weight_kg")
		if not keys_ok or int(x["slot"]) != int(y["slot"]) or int(x["kills"]) != int(y["kills"]) \
				or int(x["money"]) != int(y["money"]) or str(x["name"]) != str(y["name"]) \
				or absf(float(x["weight_kg"]) - float(y["weight_kg"])) > WEIGHT_TOL_KG:
			return false
	return true


# --- Drops (section 6.9) -------------------------------------------------------------------------

func _drop_case() -> void:
	if not await _open_pair("drop"):
		await _close_pair()
		return
	await _wait_until(func() -> bool: return not _host.get_alive_boar_ids().is_empty(), BOAR_WAIT_S)
	_kill(_host.get_alive_boar_ids()[0], CLIENT_SLOT)
	var got: bool = await _wait_until(func() -> bool: return _client.debug_partial_result().kills.size() == 1, 1.0)
	_check("drop_client_kill_credited", got)
	# The client goes away: the host only hears net_peer_left; the client only hears net_connection_lost.
	_pump_on = false
	_host.net_peer_left(CLIENT_SLOT)
	_client.net_connection_lost()
	var c: HuntResult = _client.get_result()
	_check("client_disconnected", c != null and c.outcome == HuntResult.Outcome.DISCONNECTED, _outcome_name(c))
	if c != null:
		_check("disconnected_paid_no_bonus_no_progress", c.kills.size() == 1 and c.money_from_kills == _money(c)
			and c.money_from_kills > 0 and c.contract_bonus == 0 and c.total_money == c.money_from_kills
			and not c.counts_for_progression, "kills=%d money=%d bonus=%d progress=%s" % [c.kills.size(),
			c.money_from_kills, c.contract_bonus, str(c.counts_for_progression)])
	_check("host_hunter_left", _left.has(CLIENT_SLOT) and _host.get_hunter(CLIENT_SLOT) == null
		and _host.get_hunters().size() == 1)
	await _wait_s(1.0)
	_check("host_goes_on_alone", not _host.is_hunt_over())
	# Pump stays off: the host runs alone.
	var done: bool = await _wait_until(func() -> bool:
		for id: int in _host.get_alive_boar_ids().duplicate():
			_kill(id, HOST_SLOT)
		return _host.is_hunt_over(), ALL_SPAWN_S)
	var h: HuntResult = _host.get_result()
	_check("host_wins_alone", done and h != null and h.outcome == HuntResult.Outcome.VICTORY
		and h.kills.size() == h.boars_total - 1, "%s kills=%d total=%d" % [_outcome_name(h), h.kills.size() if h != null else -1,
		h.boars_total if h != null else -1])
	await _close_pair()


# --- Host abandons -------------------------------------------------------------------------------

func _abandon_case() -> void:
	if not await _open_pair("abandon"):
		await _close_pair()
		return
	await _wait_s(0.5)
	_host._on_abandon_requested()
	var ended: bool = await _wait_until(func() -> bool: return _both_ended(HuntResult.Outcome.ABANDONED), END_WAIT_S)
	_check("host_abandon_ends_both", ended, "host=%s client=%s" % [_outcome_name(_host.get_result()), _outcome_name(_client.get_result())])
	if ended:
		_check("client_abandon_no_progress", not _client.get_result().counts_for_progression
			and _client.get_result().contract_bonus == 0)
	await _close_pair()
