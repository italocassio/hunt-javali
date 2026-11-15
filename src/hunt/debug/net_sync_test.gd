extends Node
## Package B sandbox for F8 (docs/multiplayer.md sections 4.7.6, 4.7.7 and 4.7.10, "sandbox de sync"): the rejoin
## sync in one process and without the Net autoload. A host hunt and a client hunt (inside a SubViewport with its
## own World3D) are wired through the real byte paths, like net_flow_test. The "drop" is this sandbox no longer
## pumping records between them, plus GameEvents.net_reconnect_changed(true), which only the client world obeys.
## The "rejoin" does what the session does: drain net_take_events (the other links), net_write_full_sync, and
## every record of that buffer through net_apply_event.
## Cases (one fresh host/client pair each):
##   rejoin  kills (one of them the client's own, lost in the drop), a group born and a boar born AND killed
##           during the drop, eaten patches, baits and a mark. While reconnecting the replica judges no charge
##           and claims nothing. After the sync: same live ids, same dead, same patches, same scoreboard, same
##           baits and mark, the lost kill credited once; the same sync again changes nothing; events after it
##           count once. Then hunter_away_changed from the HF_AWAY bit on both ends (real RemoteHunter).
##   end     the hunt ends on the host while the client is away (it counts as alive for "everybody down"): the
##           sync carries the real EV_HUNT_END and the client ends with the same outcome, bonus and scoreboard.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_sync_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 300.0
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SNAP_INTERVAL_S: float = 0.1
const MAP_ID: StringName = &"mato_grosso"
const CONTRACT: int = 0
const SEED: int = 8181
const ASSEMBLE_S: float = 120.0
const BOAR_WAIT_S: float = 30.0
const GROUP_WAIT_S: float = 60.0
const ALL_SPAWN_S: float = 150.0
const SETTLE_S: float = 0.4
const FIRST_GROUP: int = 5              # contract 0: the group that is there from the start
const SECOND_WAVE: int = 8              # ...and with the group that enters 20 s later
const TOTAL_TWO_PLAYERS: int = 14
const CROP_BEFORE_PCT: float = 92.0
const CROP_DURING_PCT: float = 75.0
const MARK_S: float = 20.0
const MARK_GONE_S: float = 0.05
const MARK_TOL_S: float = 0.25
const BAIT_TOL_M: float = 0.05
const BAIT_TIME_TOL_S: float = 1.05
const POSE_TOL_M: float = 6.0
const KILL_DAMAGE: float = 100000.0
const WEIGHT_TOL_KG: float = 0.05
const AWAY_SLACK_MS: int = 2500
const BACK_MS: int = 3000
const REAL_FRAME_MS: int = 15           # keeps the simulation near real time while waiting on the wall clock
const HOST_PARK: Vector2 = Vector2(-118.0, -118.0)
const CLIENT_PARK: Vector2 = Vector2(118.0, -118.0)
const HUNTER_RECORD_BYTES: int = 15     # slot u8 + HUNTER_STATE
const SNAP_HEADER_BYTES: int = 10
const FLAGS_AT: int = 11                # flags byte inside a hunter record of H_SNAPSHOT (slot + 10)

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
var _away: Array = []                   # [slot, away] of every hunter_away_changed (both hunts share the bus)
var _left: Array[int] = []
var _killed_heard: Array[int] = []      # boar ids of every boar_killed (both hunts)
var _spawned_heard: int = 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	GameEvents.hunter_away_changed.connect(func(s: int, a: bool) -> void: _away.append([s, a]))
	GameEvents.hunter_left.connect(func(s: int) -> void: _left.append(s))
	GameEvents.boar_killed.connect(func(k: KillInfo) -> void: _killed_heard.append(k.boar_id))
	GameEvents.boar_spawned.connect(func(_id: int, _t: StringName, _w: float) -> void: _spawned_heard += 1)
	await _rejoin_case()
	await _end_case()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
		get_tree().quit(1)
		return
	if not _pump_on or _host == null or _client == null:
		return
	if _pump_real:
		if Time.get_ticks_msec() - _last_pump_ms >= int(SNAP_INTERVAL_S * 1000.0):
			_last_pump_ms = Time.get_ticks_msec()
			pump()
	else:
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


# --- Rejoin --------------------------------------------------------------------------------------

func _rejoin_case() -> void:
	if not await _open_pair("rejoin", false):
		await _close_pair()
		return
	var replica: HuntReplica = _client.debug_replica()
	var sync: HuntHostSync = _host.debug_host_sync()
	var bait_s: float = float(Data.get_equipment(Ids.I_CORN_BAIT).get("effect", {}).get("duration_s", 45.0))
	_park(_host, HOST_PARK)
	_park(_client, CLIENT_PARK)
	var seen: bool = await _wait_until(func() -> bool:
		return _host.get_alive_boar_ids().size() >= FIRST_GROUP and _same_ids(), BOAR_WAIT_S)
	_check("first_group_on_both", seen, "host=%s client=%s" % [_host.get_alive_boar_ids(), _client.get_alive_boar_ids()])
	if not seen:
		await _close_pair()
		return
	var first: PackedInt32Array = _host.get_alive_boar_ids().duplicate()
	var a: int = first[0]       # killed before the drop, by the client
	var b: int = first[1]       # killed during the drop, by the host
	var d: int = first[2]       # marked during the drop
	var rig: int = first[3]     # stays alive: charge rig, expired mark

	# Before the drop: one kill of the client, a bait from each side, some crop. All of it reaches the client.
	_kill(a, CLIENT_SLOT)
	_host._on_item_used(Ids.I_CORN_BAIT, _at(HOST_PARK + Vector2(4.0, 3.0)))
	_client._on_item_used(Ids.I_CORN_BAIT, _at(CLIENT_PARK + Vector2(-4.0, 3.0)))
	_host.debug_set_crop_health(CROP_BEFORE_PCT)
	var before: bool = await _wait_until(_before_drop_synced, 3.0)
	_check("before_drop_in_sync", before and _boards_match(_host.debug_scoreboard(), _client.debug_scoreboard()),
		"client kills=%d baits %d/%d" % [_client.debug_partial_result().kills.size(), _host.get_baits().size(), _client.get_baits().size()])

	# The link stops here. The charge rig proves the replica judges a charge while connected...
	_pump_on = false
	await _wait_s(SETTLE_S)   # the puppets reach their last sample (interpolation delay)
	var puppet: BoarPuppet = replica.get_puppet(rig)
	var puppet_state: StringName = puppet.state
	var snout: Vector2 = puppet.get_xz() + Steering.dir_from_yaw(puppet.get_yaw()) * Boar.SNOUT_OFFSET_M * puppet.body_scale
	var cp: PlayerBase = _client.get_player()
	cp.bot_teleport(Vector3(snout.x, _client.get_height(snout.x, snout.y) + 0.05, snout.y))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hits0: int = replica.charge_hits
	puppet.state = Ids.BS_CHARGE
	await _wait_until(func() -> bool: return replica.charge_hits > hits0, 0.5)
	_check("charge_judged_while_connected", replica.charge_hits == hits0 + 1, "charge_hits %d -> %d" % [hits0, replica.charge_hits])
	puppet.state = puppet_state
	await _wait_s(0.1)        # try_charge_hit forgets the charge it already judged

	# ...and a bait the client used just before the drop never reaches the host: its claim dies with the link.
	_client._on_item_used(Ids.I_CORN_BAIT, _at(CLIENT_PARK + Vector2(-6.0, 6.0)))
	_check("drop_setup_claims_queued", _client.get_baits().size() == 3 and _client._pending_baits.size() == 1,
		"baits=%d pending=%d" % [_client.get_baits().size(), _client._pending_baits.size()])
	GameEvents.net_reconnect_changed.emit(true)
	_check("reconnecting_replica_suspended", replica.is_suspended() and _client._pending_baits.is_empty()
		and not _client.is_hunt_over() and not _host.is_hunt_over())
	var shots0: int = replica.shots_claimed
	var baits0: int = replica.baits_claimed
	replica._on_shot_fired(Ids.W_CARBINE_22, cp.get_eye_position(), Vector3.FORWARD, 0.0)
	replica.queue_bait_claim(cp.global_position)
	replica.request_dog_command()
	var claims: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.net_take_claims(claims)
	_check("reconnecting_no_claims", claims.get_size() == 0 and replica.shots_claimed == shots0 and replica.baits_claimed == baits0,
		"bytes=%d" % claims.get_size())
	hits0 = replica.charge_hits
	var health0: float = cp.get_health()
	puppet.state = Ids.BS_CHARGE
	await _wait_s(0.3)
	_check("reconnecting_charge_not_judged", replica.charge_hits == hits0 and is_equal_approx(cp.get_health(), health0),
		"charge_hits=%d health %.1f -> %.1f" % [replica.charge_hits, health0, cp.get_health()])
	puppet.state = puppet_state
	_park(_client, CLIENT_PARK)

	# During the drop, on the host: a group is born, one of the newcomers dies by the client's last shot (the
	# client never saw it born nor die), an old one dies by the host, crop, a bait, a mark and an expired mark.
	var puppets0: int = _puppet_count()
	var wave: bool = await _wait_until(func() -> bool: return _host_spawned() >= SECOND_WAVE, GROUP_WAIT_S)
	_check("drop_group_born_on_host_only", wave and _puppet_count() == puppets0, "host=%d client puppets=%d" % [_host_spawned(), _puppet_count()])
	var c: int = -1
	for id: int in _host.get_alive_boar_ids():
		if not first.has(id):
			c = id
			break
	_kill(b, HOST_SLOT)
	_kill(c, CLIENT_SLOT)
	_host.debug_set_crop_health(CROP_DURING_PCT)
	_host._on_item_used(Ids.I_CORN_BAIT, _at(HOST_PARK + Vector2(8.0, 3.0)))
	_host.mark_boar(d, MARK_S)
	_host.mark_boar(rig, MARK_GONE_S)
	await _wait_s(0.3)
	_check("drop_client_is_behind", _client.get_boars_killed() == 1 and _host.get_boars_killed() == 3
		and _client.debug_partial_result().kills.size() == 1 and _client.get_baits().size() == 3 and _host.get_baits().size() == 3
		and _client.crop.get_eaten_indices() != _host.crop.get_eaten_indices(),
		"killed %d/%d baits %d/%d" % [_client.get_boars_killed(), _host.get_boars_killed(), _client.get_baits().size(), _host.get_baits().size()])

	# The rejoin, as the session does it: pending events to the links that already existed, then the sync.
	var drain: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(drain)
	_check("cut_pending_events_drained_first", drain.get_size() > 0 and not sync.has_pending_events(), "drained=%d B" % drain.get_size())
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_full_sync(out)
	var data: PackedByteArray = out.data_array
	var types: PackedInt32Array = _record_types(data)
	var header_ok: bool = data.size() >= 13 and data[0] == NetCodec.EV_FULL_SYNC and data.decode_u16(1) == HuntHostSync.FULL_SYNC_BYTES
	var n_records: int = data.decode_u16(11) if header_ok else -1
	_check("sync_header", header_ok and n_records == types.size() - 1 and data[9] == 3 and data[10] == TOTAL_TWO_PLAYERS
		and absi(int(data.decode_u32(3)) - _host.net_time_ms()) <= 1
		and absf(float(data.decode_u16(7)) / 100.0 - _host.get_crop_health_pct()) <= 0.01,
		"bytes=%d n_records=%d killed=%d total=%d" % [data.size(), n_records, data[9] if header_ok else -1, data[10] if header_ok else -1])
	_check("sync_replay_sections", _sections_in_order(types) and types.count(NetCodec.EV_BOAR_SPAWN) == _host_spawned()
		and types.count(NetCodec.EV_BOAR_DEATH) == 3 and types.count(NetCodec.EV_BAIT) == 3
		and types.count(NetCodec.EV_DOG_MARK) == 1 and types.count(NetCodec.EV_HUNT_END) == 0
		and types.count(NetCodec.EV_CROP_EATEN) == ceili(float(_host.crop.get_eaten_indices().size()) / 255.0),
		"spawn=%d death=%d crop=%d bait=%d mark=%d" % [types.count(NetCodec.EV_BOAR_SPAWN), types.count(NetCodec.EV_BOAR_DEATH),
		types.count(NetCodec.EV_CROP_EATEN), types.count(NetCodec.EV_BAIT), types.count(NetCodec.EV_DOG_MARK)])
	var heard0: int = _killed_heard.size()
	var spawned0: int = _spawned_heard
	_apply_events(data)
	GameEvents.net_reconnect_changed.emit(false)
	_check("sync_applied_replica_resumed", replica.full_syncs_applied == 1 and not replica.is_suspended() and not replica.is_replaying())
	_check("sync_same_live_boars", _same_ids() and _client.get_alive_boar_ids().size() == _host_spawned() - 3,
		"host=%s client=%s" % [_sorted(_host.get_alive_boar_ids()), _sorted(_client.get_alive_boar_ids())])
	var dead_ok: bool = _puppet_count() == _host_spawned() and _spawned_heard == spawned0 + (_host_spawned() - puppets0)
	for id: int in [a, b, c]:
		var p: BoarPuppet = replica.get_puppet(id)
		dead_ok = dead_ok and p != null and not p.alive
	_check("sync_same_dead_boars", dead_ok and _client.get_boars_killed() == 3 and _client.get_boars_total() == _host.get_boars_total(),
		"puppets=%d killed=%d total=%d" % [_puppet_count(), _client.get_boars_killed(), _client.get_boars_total()])
	var lost: Array[int] = [b, c]
	_check("sync_kills_announced_once_in_order", _killed_heard.slice(heard0) == lost, "heard=%s wanted=%s" % [_killed_heard.slice(heard0), lost])
	_check("sync_same_eaten_patches", _host.crop.get_eaten_indices() == _client.crop.get_eaten_indices()
		and absf(_client.get_crop_health_pct() - _host.get_crop_health_pct()) <= 0.02,
		"patches %d/%d health %.2f/%.2f" % [_host.crop.get_eaten_indices().size(), _client.crop.get_eaten_indices().size(),
		_host.get_crop_health_pct(), _client.get_crop_health_pct()])
	_check("sync_same_scoreboard", _boards_match(_host.debug_scoreboard(), _client.debug_scoreboard()),
		"host=%s client=%s" % [_host.debug_scoreboard(), _client.debug_scoreboard()])
	var own: Array[int] = _own_kills(_client)
	var mine: Dictionary = _board_entry(_host.debug_scoreboard(), CLIENT_SLOT)
	var own_wanted: Array[int] = [a, c]
	_check("sync_lost_own_kill_credited_once", own == own_wanted and _client.debug_partial_result().money_from_kills == _money(_client.debug_partial_result())
		and int(mine.get("kills", -1)) == 2 and int(mine.get("money", -1)) == _client.debug_partial_result().money_from_kills,
		"own=%s money=%d host says %s" % [own, _client.debug_partial_result().money_from_kills, mine])
	_check("sync_same_baits", _baits_match(bait_s) and _client.get_baits().size() == 3,
		"host=%s client=%s" % [_bait_spots(_host), _bait_spots(_client)])
	var hm: Dictionary = _host._marks
	var cm: Dictionary = _client._marks
	var mark_ok: bool = _live_marks(_host) == [d] and _live_marks(_client) == [d]
	if mark_ok:
		mark_ok = absf((float(cm[d]) - _client.get_elapsed_s()) - (float(hm[d]) - _host.get_elapsed_s())) <= MARK_TOL_S
	_check("sync_same_marks", mark_ok and _client.get_marked_boar_positions().size() == 1,
		"host=%s client=%s" % [_live_marks(_host), _live_marks(_client)])

	# The same sync again (a duplicate must be harmless).
	var digest: Dictionary = _digest(_client)
	heard0 = _killed_heard.size()
	_apply_events(data)
	var same: bool = _digest(_client) == digest
	_check("sync_twice_changes_nothing", same and _killed_heard.size() == heard0 and replica.full_syncs_applied == 2
		and not replica.is_suspended(), "" if same else "before=%s after=%s" % [digest, _digest(_client)])

	# The link is back: what happens from here on counts once, and the puppets take the host's poses.
	_pump_on = true
	var alive_now: PackedInt32Array = _host.get_alive_boar_ids().duplicate()
	var f: int = alive_now[alive_now.size() - 1]
	_kill(f, CLIENT_SLOT)
	_host._on_item_used(Ids.I_CORN_BAIT, _at(HOST_PARK + Vector2(12.0, 3.0)))
	var after: bool = await _wait_until(func() -> bool:
		return _own_kills(_client).size() == 3 and _client.get_baits().size() == 4, 3.0)
	await _wait_s(SETTLE_S)
	own_wanted.append(f)
	_check("after_sync_events_count_once", after and _own_kills(_client) == own_wanted and _client.get_boars_killed() == 4
		and _host.get_baits().size() == 4 and _client.get_baits().size() == 4
		and _boards_match(_host.debug_scoreboard(), _client.debug_scoreboard()) and _same_ids(),
		"own=%s baits %d/%d" % [_own_kills(_client), _host.get_baits().size(), _client.get_baits().size()])
	var worst: float = 0.0
	for id: int in _host.get_alive_boar_ids():
		var hb: Boar = _host.spawner.get_boar(id)
		var pp: BoarPuppet = replica.get_puppet(id)
		if hb != null and pp != null:
			worst = maxf(worst, Vector2(hb.position.x, hb.position.z).distance_to(pp.get_xz()))
	_check("after_sync_puppets_follow_host", worst <= POSE_TOL_M, "worst gap %.2f m" % worst)
	_check("after_sync_claims_flow_again", await _claim_reaches_host(), "baits claimed on host=%d" % sync.baits_claimed)

	await _away_checks()

	# A sync with no replay (n_records = 0): baits released, replica never left suspended.
	var empty: StreamPeerBuffer = StreamPeerBuffer.new()
	empty.put_u8(NetCodec.EV_FULL_SYNC)
	empty.put_u16(HuntHostSync.FULL_SYNC_BYTES)
	empty.put_u32(_host.net_time_ms())
	empty.put_u16(roundi(_host.get_crop_health_pct() * 100.0))
	empty.put_u8(_client.get_boars_killed())
	empty.put_u8(_client.get_boars_total())
	empty.put_u16(0)
	var killed0: int = _client.get_boars_killed()
	_apply_events(empty.data_array)
	_check("empty_sync_resumes_at_once", not replica.is_suspended() and not replica.is_replaying() and _client.get_baits().is_empty()
		and _client.get_boars_killed() == killed0, "baits=%d" % _client.get_baits().size())
	await _close_pair()


func _before_drop_synced() -> bool:
	return _client.debug_partial_result().kills.size() == 1 and _host.get_baits().size() == 2 		and _client.get_baits().size() == 2 and _client._pending_baits.is_empty() 		and _host.crop.get_eaten_indices() == _client.crop.get_eaten_indices()


## A client bait after the rejoin reaches the host (C_BAIT accepted again) and its echo is not duplicated.
func _claim_reaches_host() -> bool:
	var host0: int = _host.get_baits().size()
	var client0: int = _client.get_baits().size()
	_client._on_item_used(Ids.I_CORN_BAIT, _at(CLIENT_PARK + Vector2(-9.0, 9.0)))
	var got: bool = await _wait_until(func() -> bool: return _host.get_baits().size() == host0 + 1, 2.0)
	await _wait_s(SETTLE_S)
	return got and _client.get_baits().size() == client0 + 1 and _client._pending_baits.is_empty()


## hunter_away_changed comes from the HF_AWAY bit of the snapshot record, on both ends (section 4.7.7).
func _away_checks() -> void:
	# Host: the real RemoteHunter goes quiet for net.peer_absent_s (wall clock) and is relayed as away.
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	_away.clear()
	_left.clear()
	_pump_on = false
	var limit: int = Time.get_ticks_msec() + int(float(Data.get_net().get("peer_absent_s", 3.0)) * 1000.0) + AWAY_SLACK_MS
	var scratch: StreamPeerBuffer = StreamPeerBuffer.new()
	while _away.is_empty() and Time.get_ticks_msec() < limit:
		scratch.clear()
		_host.net_write_snapshot(scratch)   # what the session does 10 times a second, with or without links
		OS.delay_msec(REAL_FRAME_MS)
		await get_tree().process_frame
	_check("host_away_after_silence", _away == [[CLIENT_SLOT, true]] and remote != null and not remote.is_present(), "away=%s" % str(_away))
	_check("host_keeps_absent_hunter", _host.get_hunter(CLIENT_SLOT) == remote and _host.get_hunters().size() == 2 and _left.is_empty()
		and not _host.is_hunt_over(), "hunters=%d left=%s" % [_host.get_hunters().size(), str(_left)])
	scratch.clear()
	_host.net_write_snapshot(scratch)
	var raw: PackedByteArray = scratch.data_array
	var flags_at: int = _hunter_flags_at(raw, CLIENT_SLOT)
	_check("host_snapshot_carries_hf_away", flags_at >= 0 and (raw[flags_at] & NetCodec.HF_AWAY) != 0 and raw[flags_at - 1] == 0,
		"flags=%d speed=%d" % [raw[flags_at] if flags_at >= 0 else -1, raw[flags_at - 1] if flags_at >= 0 else -1])
	_pump_real = true
	_pump_on = true
	var back_limit: int = Time.get_ticks_msec() + BACK_MS
	while _away.size() < 2 and Time.get_ticks_msec() < back_limit:
		OS.delay_msec(REAL_FRAME_MS)
		await get_tree().process_frame
	_check("host_back_after_first_state", _away == [[CLIENT_SLOT, true], [CLIENT_SLOT, false]] and remote.is_present(), "away=%s" % str(_away))
	_pump_on = false
	_pump_real = false

	# Client: the same bit, as received. The host's own hunter never carries it, so the record is patched here.
	_away.clear()
	scratch.clear()
	_host.net_write_snapshot(scratch)
	var plain: PackedByteArray = scratch.data_array
	var patched: PackedByteArray = plain.duplicate()
	var host_flags_at: int = _hunter_flags_at(patched, HOST_SLOT)
	var own_flags_at: int = _hunter_flags_at(patched, CLIENT_SLOT)
	if host_flags_at >= 0 and own_flags_at >= 0:
		patched[host_flags_at] = patched[host_flags_at] | NetCodec.HF_AWAY
		patched[own_flags_at] = patched[own_flags_at] | NetCodec.HF_AWAY   # the local slot must be ignored
	_apply_snapshot(patched)
	_apply_snapshot(patched)
	var went: Array = _away.duplicate()
	_apply_snapshot(plain)
	_check("client_away_from_received_bit", host_flags_at >= 0 and went == [[HOST_SLOT, true]]
		and _away == [[HOST_SLOT, true], [HOST_SLOT, false]], "away=%s" % str(_away))
	_away.clear()
	_pump_on = true


# --- The hunt ends while the client is away -------------------------------------------------------

func _end_case() -> void:
	if not await _open_pair("end", true):
		await _close_pair()
		return
	_park(_host, HOST_PARK)
	_park(_client, CLIENT_PARK)
	var seen: bool = await _wait_until(func() -> bool:
		return _host.get_alive_boar_ids().size() >= 1 and _same_ids(), BOAR_WAIT_S)
	_check("end_first_boars_on_both", seen)
	if not seen:
		await _close_pair()
		return
	_kill(_host.get_alive_boar_ids()[0], CLIENT_SLOT)
	await _wait_until(func() -> bool: return _client.debug_partial_result().kills.size() == 1, 2.0)
	_away.clear()
	_left.clear()
	GameEvents.net_reconnect_changed.emit(true)
	_pump_on = false
	var remote: FallbackRemoteHunter = _host.get_hunter(CLIENT_SLOT) as FallbackRemoteHunter
	_check("end_fallback_remote_in_use", remote != null)
	if remote == null:
		await _close_pair()
		return
	var scratch: StreamPeerBuffer = StreamPeerBuffer.new()
	remote.debug_away = true
	_host.net_write_snapshot(scratch)
	scratch.clear()
	_host.net_write_snapshot(scratch)
	_check("end_away_signal_once", _away == [[CLIENT_SLOT, true]] and not remote.is_present(), "away=%s" % str(_away))

	# Everybody present is down; the absent hunter was alive when it went quiet, so the hunt goes on.
	var hp: PlayerBase = _host.get_player()
	hp.apply_damage(KILL_DAMAGE, hp.global_position + Vector3.FORWARD)
	await _wait_s(1.0)
	_check("end_absent_counts_as_alive", not hp.is_alive() and remote.is_alive() and not _host.is_hunt_over())
	var done: bool = await _kill_all(1)
	var h: HuntResult = _host.get_result()
	_check("end_host_wins_during_grace", done and h != null and h.outcome == HuntResult.Outcome.VICTORY
		and not _client.is_hunt_over() and _left.is_empty(), "host=%s client over=%s" % [_outcome_name(h), str(_client.is_hunt_over())])
	if h == null:
		await _close_pair()
		return
	remote.debug_away = false
	scratch.clear()
	_host.net_write_snapshot(scratch)
	_check("end_no_away_signal_after_end", _away == [[CLIENT_SLOT, true]], "away=%s" % str(_away))

	# The client comes back before the host leaves the scene: the sync ends with the real EV_HUNT_END.
	var drain: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(drain)
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_full_sync(out)
	var data: PackedByteArray = out.data_array
	var types: PackedInt32Array = _record_types(data)
	_check("end_sync_closes_with_hunt_end", types.size() >= 2 and types[types.size() - 1] == NetCodec.EV_HUNT_END
		and types.count(NetCodec.EV_HUNT_END) == 1 and data.decode_u16(11) == types.size() - 1
		and types.count(NetCodec.EV_BOAR_DEATH) == TOTAL_TWO_PLAYERS and _sections_in_order(types),
		"bytes=%d records=%d" % [data.size(), types.size() - 1])
	_apply_events(data)
	GameEvents.net_reconnect_changed.emit(false)
	var c: HuntResult = _client.get_result()
	_check("end_client_gets_real_outcome", c != null and c.outcome == HuntResult.Outcome.VICTORY, _outcome_name(c))
	if c != null:
		_check("end_client_paid_with_bonus", c.kills.size() == 2 and c.money_from_kills == _money(c) and c.money_from_kills > 0
			and c.contract_bonus == h.contract_bonus and c.contract_bonus > 0 and c.total_money == c.money_from_kills + c.contract_bonus
			and c.counts_for_progression, "kills=%d money=%d bonus=%d/%d" % [c.kills.size(), c.money_from_kills, c.contract_bonus, h.contract_bonus])
		_check("end_same_scoreboard_and_counts", _boards_match(h.scoreboard, c.scoreboard) and c.team_kills == h.team_kills
			and c.team_kills == TOTAL_TWO_PLAYERS and c.boars_total == h.boars_total and h.kills.size() + c.kills.size() == TOTAL_TWO_PLAYERS,
			"host=%s client=%s" % [h.scoreboard, c.scoreboard])
		_check("end_same_crop", _host.crop.get_eaten_indices() == _client.crop.get_eaten_indices()
			and absf(h.crop_health_pct - c.crop_health_pct) <= 0.01, "%.3f / %.3f" % [h.crop_health_pct, c.crop_health_pct])
		var money: int = c.total_money
		_apply_events(data)
		_check("end_sync_twice_changes_nothing", _client.get_result() == c and c.kills.size() == 2 and c.total_money == money)
	await _close_pair()


# --- Pair plumbing (same as net_flow_test) --------------------------------------------------------

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


func _make(role: int, local_slot: int, parent: Node, fallback_remote: bool) -> HuntController:
	var hunt: HuntController = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	hunt.route_on_finish = false
	hunt.test_net_role = role
	hunt.test_net_local_slot = local_slot
	hunt.test_net_roster = _roster()
	hunt.test_fallback_remote = fallback_remote
	parent.add_child(hunt)
	return hunt


func _open_pair(label: String, fallback_remote: bool) -> bool:
	print("--- " + label)
	var req: HuntRequest = HuntRequest.make_debug(MAP_ID, CONTRACT)
	req.rng_seed = SEED
	req.quality = Ids.Q_LOW
	req.player_count = 2
	req.item_ids = [Ids.I_CORN_BAIT]
	req.item_counts = {Ids.I_CORN_BAIT: 3}
	Router.set_pending_request(req)
	_host = _make(Net.Role.HOST, HOST_SLOT, self, fallback_remote)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_client = _make(Net.Role.CLIENT, CLIENT_SLOT, _vp, fallback_remote)
	var ok: bool = await _wait_until(func() -> bool: return _host.is_world_ready() and _client.is_world_ready(), ASSEMBLE_S)
	_check("%s_assembled" % label, ok)
	if not ok:
		return false
	_away.clear()
	_left.clear()
	_killed_heard.clear()
	_host.debug_net_go()
	_client.debug_net_go()
	_pump_on = true
	return true


func _close_pair() -> void:
	_pump_on = false
	_pump_real = false
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
	_apply_snapshot(snap.data_array)
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)
	_apply_events(ev.data_array)
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


func _apply_snapshot(data: PackedByteArray) -> void:
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = data
	_client.net_apply_snapshot(inp)


## EV_* records, one net_apply_event each, as the session delivers them.
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


## Replay order of section 4.7.6: journal (spawn/death), eaten patches, baits, marks, hunt end.
func _sections_in_order(types: PackedInt32Array) -> bool:
	var rank: Dictionary = {NetCodec.EV_BOAR_SPAWN: 1, NetCodec.EV_BOAR_DEATH: 1, NetCodec.EV_CROP_EATEN: 2,
		NetCodec.EV_BAIT: 3, NetCodec.EV_DOG_MARK: 4, NetCodec.EV_HUNT_END: 5}
	if types.is_empty() or types[0] != NetCodec.EV_FULL_SYNC:
		return false
	var last: int = 0
	for i: int in range(1, types.size()):
		var r: int = int(rank.get(types[i], -1))
		if r < last:
			return false
		last = r
	return true


## Offset of the flags byte of that slot's hunter record inside an H_SNAPSHOT body (-1 if not listed).
func _hunter_flags_at(snapshot: PackedByteArray, slot: int) -> int:
	if snapshot.size() < SNAP_HEADER_BYTES:
		return -1
	var n: int = snapshot[SNAP_HEADER_BYTES - 1]
	for i: int in n:
		var at: int = SNAP_HEADER_BYTES + i * HUNTER_RECORD_BYTES
		if at + HUNTER_RECORD_BYTES <= snapshot.size() and snapshot[at] == slot:
			return at + FLAGS_AT
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


func _at(xz: Vector2) -> Vector3:
	return Vector3(xz.x, 0.0, xz.y)


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


func _host_spawned() -> int:
	return _host.get_alive_boar_ids().size() + _host.get_boars_killed()


func _puppet_count() -> int:
	var n: int = 0
	for child: Node in _client.debug_replica().get_children():
		if child is BoarPuppet:
			n += 1
	return n


func _sorted(ids: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = ids.duplicate()
	out.sort()
	return out


func _same_ids() -> bool:
	return _sorted(_host.get_alive_boar_ids()) == _sorted(_client.get_alive_boar_ids())


func _own_kills(world: HuntController) -> Array[int]:
	var out: Array[int] = []
	for k: KillInfo in world.debug_partial_result().kills:
		out.append(k.boar_id)
	return out


func _money(r: HuntResult) -> int:
	var m: int = 0
	for k: KillInfo in r.kills:
		m += k.reward_money
	return m


func _board_entry(board: Array[Dictionary], slot: int) -> Dictionary:
	for e: Dictionary in board:
		if int(e["slot"]) == slot:
			return e
	return {}


func _boards_match(x: Array[Dictionary], y: Array[Dictionary]) -> bool:
	if x.size() != y.size() or x.is_empty():
		return false
	for i: int in x.size():
		var p: Dictionary = x[i]
		var q: Dictionary = y[i]
		if int(p["slot"]) != int(q["slot"]) or int(p["kills"]) != int(q["kills"]) or int(p["money"]) != int(q["money"]) \
				or str(p["name"]) != str(q["name"]) or absf(float(p["weight_kg"]) - float(q["weight_kg"])) > WEIGHT_TOL_KG:
			return false
	return true


## [x, z, remaining_s] of every bait of that world, sorted.
func _bait_spots(world: HuntController) -> Array:
	var out: Array = []
	for bait: Bait in world.get_baits():
		out.append([snappedf(bait.position.x, 0.01), snappedf(bait.position.z, 0.01), snappedf(bait.remaining_s, 0.1)])
	out.sort()
	return out


## Same baits on both sides: same places, and the client's time left is the host's rounded up to the second.
func _baits_match(full_s: float) -> bool:
	var hs: Array = _bait_spots(_host)
	var cs: Array = _bait_spots(_client)
	if hs.size() != cs.size():
		return false
	for i: int in hs.size():
		var p: Array = hs[i]
		var q: Array = cs[i]
		var gap: float = float(q[2]) - float(p[2])
		if absf(float(p[0]) - float(q[0])) > BAIT_TOL_M or absf(float(p[1]) - float(q[1])) > BAIT_TOL_M \
				or gap < -0.11 or gap > BAIT_TIME_TOL_S or float(q[2]) > full_s:
			return false
	return true


func _live_marks(world: HuntController) -> Array:
	var out: Array = []
	var marks: Dictionary = world._marks
	for id: int in marks:
		if float(marks[id]) >= world.get_elapsed_s():
			out.append(id)
	out.sort()
	return out


## Everything a repeated sync must leave alone on the client.
func _digest(world: HuntController) -> Dictionary:
	var spots: Array = []
	for s: Array in _bait_spots(world):
		spots.append([s[0], s[1]])
	return {
		"alive": _sorted(world.get_alive_boar_ids()), "killed": world.get_boars_killed(), "total": world.get_boars_total(),
		"puppets": _puppet_count(), "eaten": world.crop.get_eaten_indices(), "board": world.debug_scoreboard(),
		"own": _own_kills(world), "money": world.debug_partial_result().money_from_kills, "baits": spots,
		"marks": _live_marks(world), "crop": snappedf(world.get_crop_health_pct(), 0.01),
	}


func _outcome_name(r: HuntResult) -> String:
	return HuntResult.Outcome.keys()[r.outcome] if r != null else "null"
