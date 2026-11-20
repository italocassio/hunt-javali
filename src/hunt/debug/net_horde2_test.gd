extends Node
## Package B sandbox of horde level 2 over the network (docs/plano_horda_nivel2.md sections 4.6-4.8 and 8): a host hunt
## and a client hunt in one process (test_net_role hooks, client inside a SubViewport with its own World3D), wired
## through the same record byte paths the Net session uses (snapshot, events, the client's HUNTER_STATE, claims).
## The real RemoteHunter is used (HF_DOWNED), so the downed / revive parts need package A's Player and RemoteHunter.
##   crates   the client standing on a crate claims nothing; its press of interact -> EV_AMMO_CRATE with taker = client,
##            its reserve goes up, hidden on both; two claims for one crate -> one winner; host and client pressing on
##            one crate -> one winner; the full sync carries one EV_AMMO_CRATE per crate
##   revive   client down -> hunter_downed on both; host holds interact 4 s -> EV_HUNTER_REVIVED, client alive with 50;
##            host down -> client stands it up through C_REVIVE; a claim out of radius + tolerance is ignored;
##            both down -> DEFEAT_DEATH on both
##   bleed    (second pair) the client bleeds out -> hunter_died on both, the hunt goes on
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_horde2_test.tscn [-- --only=bleed]
## Not part of the game; the qa-tester owns the real tests in tests/ (net_unit --only=net_horde2).

const LEVEL: int = 2
const WATCHDOG_REAL_S: float = 600.0
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SNAP_INTERVAL_S: float = 0.1
const MAP_ID: StringName = &"mato_grosso"
const SEED: int = 7272
const PLAYERS: int = 2
const ASSEMBLE_S: float = 120.0
const SYNC_PUMPS: int = 3          # > hunter_interp_delay_ms of real time: both ends show the other's last state
const PUMP_WAIT_REAL_MS: int = 5000
const TAKE_WAIT_S: float = 20.0     # game time; the claim crosses on the next real-time pump
const HOST_PARK: Vector2 = Vector2(-15.0, -105.0)     # west end of the farm, far from the boars' ways
const CLIENT_PARK: Vector2 = Vector2(-5.0, -105.0)    # 10 m from the host: out of revive radius + tolerance
const NEAR_OFFSET: Vector2 = Vector2(1.0, 0.0)
const CRATE_SIDE_M: float = 2.5                       # outside pickup_radius_m, inside pickup + claim tolerance
const STOCK_RESET_BELOW: float = 40.0
const HOLD_SLACK_S: float = 2.0
const DOWN_WAIT_S: float = 5.0      # RemoteHunter shows a state ~150 ms of real time late (interpolation delay)
const BLEED_SLACK_S: float = 3.0
const END_WAIT_S: float = 3.0
const HEALTH_TOL: float = 0.01
const HOLD_TOL_S: float = 0.05
const PUPPET_WAIT_S: float = 30.0

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _host: HuntController = null
var _client: HuntController = null
var _vp: SubViewport = null
var _pump_on: bool = false
var _last_pump_ms: int = 0
var _pump_count: int = 0
var _cfg: Dictionary = {}
var _crate_events: Array = []           # [crate, available, taker] of every EV_AMMO_CRATE the host sent through the pump
var _revived_events: Array = []        # [target, by] of every EV_HUNTER_REVIVED the host sent through the pump
var _downed: Array[int] = []           # hunter_downed slots (both machines share the bus: one emission per machine)
var _died: Array[int] = []
var _revived: Array = []                # hunter_revived [target, by]


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_cfg = Data.get_horde_level(LEVEL)
	GameEvents.hunter_downed.connect(func(s: int) -> void: _downed.append(s))
	GameEvents.hunter_died.connect(func(s: int) -> void: _died.append(s))
	GameEvents.hunter_revived.connect(func(s: int, by: int) -> void: _revived.append([s, by]))
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	_check("level_2_data", not _cfg.is_empty() and bool((_cfg["revive"] as Dictionary)["enabled"]))
	if only.is_empty() or only.has("crates") or only.has("revive"):
		if await _open_pair():
			if only.is_empty() or only.has("crates"):
				print("--- crates")
				await _test_crates()
			if only.is_empty() or only.has("revive"):
				print("--- revive")
				await _test_revive()
		await _close_pair()
	if only.is_empty() or only.has("bleed"):
		print("--- bleed")
		if await _open_pair():
			await _test_bleed()
		await _close_pair()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
		print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed + 1])
		get_tree().quit(1)
		return
	if not _pump_on or _host == null or _client == null:
		return
	if not _host.is_hunt_over() and _host.get_crop_health_pct() < STOCK_RESET_BELOW:
		_host.debug_set_crop_health(100.0)
	# Real-time pump, as net_sync_test: the RemoteHunter interpolates on the real clock (hunter_interp_delay_ms), and
	# headless --fixed-fps runs the game clock much faster than that.
	if Time.get_ticks_msec() - _last_pump_ms >= int(SNAP_INTERVAL_S * 1000.0):
		_last_pump_ms = Time.get_ticks_msec()
		pump()


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


# --- Ammo crates ---------------------------------------------------------------------------------

func _crate_takes(crate: int) -> Array:
	var out: Array = []
	for e: Array in _crate_events:
		if e[0] == crate and e[1] == 0:
			out.append(e)
	return out


func _test_crates() -> void:
	var hc: HordeAmmoCrates = _host.debug_ammo_crates()
	var cc: HordeAmmoCrates = _client.debug_ammo_crates()
	_check("crates_on_both", hc != null and cc != null and hc.get_count() == 3 and cc.get_count() == 3
		and _client.get_ammo_crate_positions().size() == 3)
	if hc == null or cc == null:
		return
	var cp: PlayerBase = _client.get_player()
	var hp: PlayerBase = _host.get_player()
	# 1. The client walks onto crate 1: nothing until it presses interact (owner's Q4).
	var r0: int = cp.get_ammo_reserve()
	var claims0: int = _client.debug_replica().ammo_crates_claimed
	_teleport(_client, hc.get_crate_position(1))
	await _wait_pumps(SYNC_PUMPS)   # the host now knows the client is at the crate
	_check("client_standing_claims_nothing", cc.is_available(1) and hc.is_available(1) and cp.get_ammo_reserve() == r0
		and _client.debug_replica().ammo_crates_claimed == claims0 and cp.get_ammo_crate_target() == 1,
		"claims=%d target=%d" % [_client.debug_replica().ammo_crates_claimed - claims0, cp.get_ammo_crate_target()])
	await _press_interact([cp])
	var taken: bool = await _wait_until(func() -> bool: return not cc.is_available(1), TAKE_WAIT_S)
	var takes: Array = _crate_takes(1)
	_check("client_crate_taken_by_client", taken and takes.size() == 1 and takes[0][2] == CLIENT_SLOT,
		"events=%s needs_ammo=%s claims=%d" % [str(_crate_events), cp.needs_ammo(), _client.debug_replica().ammo_crates_claimed])
	_check("client_reserve_up", cp.get_ammo_reserve() > r0, "%d -> %d" % [r0, cp.get_ammo_reserve()])
	_check("crate_hidden_on_both", not hc.is_available(1) and not cc.is_available(1) and not (hc.get_child(1) as Node3D).visible
		and not (cc.get_child(1) as Node3D).visible and _host.get_ammo_crate_positions().size() == 2
		and _client.get_ammo_crate_positions().size() == 2)
	# 2. Two claims for crate 0 in one pump: one winner.
	var c0: Vector3 = hc.get_crate_position(0)
	_teleport(_client, c0 + Vector3(0.0, 0.0, -CRATE_SIDE_M))
	await _wait_pumps(SYNC_PUMPS)
	var rejected0: int = _host.ammo_claims_rejected
	_client.debug_replica().queue_ammo_crate_claim(0)
	_client.debug_replica().queue_ammo_crate_claim(0)
	await _wait_pumps(SYNC_PUMPS)
	_check("two_claims_one_winner", _crate_takes(0).size() == 1 and _host.ammo_claims_rejected == rejected0 + 1
		and not cc.is_available(0), "takes=%s rejected=%d" % [str(_crate_takes(0)), _host.ammo_claims_rejected - rejected0])
	# 3. Host and client on crate 2 at once: one winner.
	_teleport(_client, _park_point(_client))
	await _wait_pumps(SYNC_PUMPS)
	var c2: Vector3 = hc.get_crate_position(2)
	_teleport(_host, c2)
	_teleport(_client, c2)
	await _wait_pumps(SYNC_PUMPS)
	await _press_interact([hp, cp])
	await _wait_until(func() -> bool: return not cc.is_available(2) and not hc.is_available(2), TAKE_WAIT_S)
	await _wait_s(1.5)   # a late client claim would show up here
	await _wait_pumps(SYNC_PUMPS)
	_check("host_and_client_one_winner", _crate_takes(2).size() == 1, "takes=%s host_needs=%s" % [str(_crate_takes(2)), hp.needs_ammo()])
	_park_both()
	await _wait_pumps(SYNC_PUMPS)
	# 4. Full sync: one EV_AMMO_CRATE per crate, taker 255, with the host's state.
	var drain: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(drain)
	_apply_events(drain.data_array)
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_full_sync(out)
	var data: PackedByteArray = out.data_array
	var recs: Array = _records(data)
	var crate_recs: Array = []
	for r: Array in recs:
		if r[0] == NetCodec.EV_AMMO_CRATE:
			crate_recs.append(r)
	var sync_ok: bool = crate_recs.size() == hc.get_count() and data.decode_u16(11) == recs.size() - 1
	for i: int in crate_recs.size():
		var body: PackedByteArray = crate_recs[i][1]
		sync_ok = sync_ok and body.size() == 3 and body[0] == i and (body[1] == 1) == hc.is_available(i) and body[2] == NetCodec.NO_SLOT
	_check("full_sync_one_crate_record_each", sync_ok, "crate records=%d of %d" % [crate_recs.size(), recs.size() - 1])


## One press of interact (one frame held) by each of these bot hunters, in the same frame.
func _press_interact(hunters: Array) -> void:
	for h: PlayerBase in hunters:
		h.bot_set_interact(true)
	await get_tree().process_frame
	for h: PlayerBase in hunters:
		h.bot_set_interact(false)
	await get_tree().process_frame


func _park_point(world: HuntController) -> Vector3:
	var xz: Vector2 = HOST_PARK if world == _host else CLIENT_PARK
	return Vector3(xz.x, 0.0, xz.y)


# --- Downed and revive ---------------------------------------------------------------------------

func _test_revive() -> void:
	var cp: PlayerBase = _client.get_player()
	var hp: PlayerBase = _host.get_player()
	var hold: float = float((_cfg["revive"] as Dictionary)["hold_s"])
	var health: float = float((_cfg["revive"] as Dictionary)["health"])
	_park_both()
	await _wait_pumps(SYNC_PUMPS)
	# 1. The client goes down.
	_downed.clear()
	cp.apply_damage(9999.0, cp.global_position)
	var remote_c: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	await _wait_until(func() -> bool: return remote_c.is_downed() and _downed.count(CLIENT_SLOT) == 2, DOWN_WAIT_S)
	_check("client_downed_on_both", cp.is_downed() and not cp.is_alive() and remote_c.is_downed() and _downed.count(CLIENT_SLOT) == 2
		and not _host.is_hunt_over(), "local downed=%s remote downed=%s emits=%s" % [cp.is_downed(), remote_c.is_downed(), _downed])
	# 2. The host stands it up.
	_teleport(_host, cp.global_position + Vector3(NEAR_OFFSET.x, 0.0, NEAR_OFFSET.y))
	await _wait_pumps(SYNC_PUMPS)
	var t0: float = _host.get_elapsed_s()
	hp.bot_set_interact(true)
	var up: bool = await _wait_until(func() -> bool: return cp.is_alive(), hold + HOLD_SLACK_S)
	var took: float = _host.get_elapsed_s() - t0
	hp.bot_set_interact(false)
	await _wait_until(func() -> bool: return remote_c.is_alive(), DOWN_WAIT_S)
	_check("host_revives_client", up and absf(cp.get_health() - health) < HEALTH_TOL and took >= hold - HOLD_TOL_S
		and _revived_events.has([CLIENT_SLOT, HOST_SLOT]) and _revived.count([CLIENT_SLOT, HOST_SLOT]) == 2 and remote_c.is_alive(),
		"up=%s health=%.1f after %.2f s events=%s" % [up, cp.get_health(), took, str(_revived_events)])
	# 3. The host goes down; the client stands it up (C_REVIVE).
	hp.apply_damage(9999.0, hp.global_position)
	var remote_h: PlayerBase = _client.get_hunter(HOST_SLOT)
	await _wait_until(func() -> bool: return remote_h.is_downed() and _downed.count(HOST_SLOT) == 2, DOWN_WAIT_S)
	_check("host_downed_on_both", hp.is_downed() and remote_h.is_downed() and _downed.count(HOST_SLOT) == 2, "emits=%s" % [_downed])
	_teleport(_client, hp.global_position + Vector3(NEAR_OFFSET.x, 0.0, NEAR_OFFSET.y))
	await _wait_pumps(SYNC_PUMPS)
	var claims0: int = _client.debug_replica().revives_claimed
	cp.bot_set_interact(true)
	up = await _wait_until(func() -> bool: return hp.is_alive(), hold + HOLD_SLACK_S)
	cp.bot_set_interact(false)
	await _wait_pumps(SYNC_PUMPS)
	_check("client_revives_host", up and absf(hp.get_health() - health) < HEALTH_TOL
		and _client.debug_replica().revives_claimed == claims0 + 1 and _revived_events.has([HOST_SLOT, CLIENT_SLOT]),
		"up=%s health=%.1f claims=%d events=%s" % [up, hp.get_health(), _client.debug_replica().revives_claimed - claims0, str(_revived_events)])
	# 4. Host down again, client 10 m away: its claim is ignored.
	_park_both()
	await _wait_until(func() -> bool:
		return _host.get_hunter(CLIENT_SLOT).global_position.distance_to(_park_point(_client)) < 1.0, DOWN_WAIT_S)
	hp.apply_damage(9999.0, hp.global_position)
	await _wait_until(func() -> bool: return hp.is_downed(), DOWN_WAIT_S)
	var rejected0: int = _host.revives_rejected
	var events0: int = _revived_events.size()
	_client.debug_replica().queue_revive_claim(HOST_SLOT)
	await _wait_pumps(SYNC_PUMPS)
	_check("far_claim_ignored", _host.revives_rejected == rejected0 + 1 and _revived_events.size() == events0 and hp.is_downed(),
		"rejected=%d host downed=%s" % [_host.revives_rejected - rejected0, hp.is_downed()])
	# 5. The client goes down too: nobody is up -> DEFEAT_DEATH on both.
	cp.apply_damage(9999.0, cp.global_position)
	await _wait_until(func() -> bool: return _host.is_hunt_over() and _client.is_hunt_over(), END_WAIT_S)
	var h: HuntResult = _host.get_result()
	var c: HuntResult = _client.get_result()
	_check("both_down_defeat_death", h != null and c != null and h.outcome == HuntResult.Outcome.DEFEAT_DEATH
		and c.outcome == HuntResult.Outcome.DEFEAT_DEATH and h.horde_level == LEVEL and c.horde_level == LEVEL,
		"host=%s client=%s" % [_outcome_name(h), _outcome_name(c)])
	_check("nobody_died_for_good", not _died.has(HOST_SLOT) and not _died.has(CLIENT_SLOT), "died=%s" % [_died])


func _test_bleed() -> void:
	var cp: PlayerBase = _client.get_player()
	var bleed: float = float((_cfg["revive"] as Dictionary)["bleed_out_s"])
	_park_both()
	await _wait_pumps(SYNC_PUMPS)
	_died.clear()
	_downed.clear()
	cp.apply_damage(9999.0, cp.global_position)
	await _wait_until(func() -> bool: return _downed.count(CLIENT_SLOT) == 2, DOWN_WAIT_S)
	_check("bleed_client_downed", cp.is_downed() and _downed.count(CLIENT_SLOT) == 2, "emits=%s" % [_downed])
	var dead: bool = await _wait_until(func() -> bool: return _died.count(CLIENT_SLOT) == 2, bleed + BLEED_SLACK_S)
	_check("bleed_out_hunter_died_on_both", dead and not cp.is_alive() and not cp.is_downed()
		and not _host.get_hunter(CLIENT_SLOT).is_downed() and not _host.is_hunt_over(),
		"died=%s over=%s" % [_died, _host.is_hunt_over()])
	# N3 on the client: a sow puppet judges its charge with the level's damage.
	var want: float = float(Data.get_horde_boar_type(Ids.SOW, LEVEL)["charge_damage"])
	var pick: Array = [null]
	var found: bool = await _wait_until(func() -> bool:
		for id: int in _client.get_alive_boar_ids():
			var p: BoarPuppet = _client.debug_replica().get_puppet(id)
			if p != null and p.type_id == Ids.SOW:
				pick[0] = p
				return true
		return false, PUPPET_WAIT_S)
	var puppet: BoarPuppet = pick[0] as BoarPuppet
	_check("client_sow_puppet_level_2_damage", found and is_equal_approx(puppet._charge_damage, want)
		and not is_equal_approx(want, float(Data.get_boar_type(Ids.SOW)["charge_damage"])),
		"damage=%s want=%.1f" % [puppet._charge_damage if puppet != null else -1.0, want])


# --- Pair plumbing (as net_sync_test) -------------------------------------------------------------

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
	hunt.test_fallback_remote = false   # the real RemoteHunter knows HF_DOWNED
	parent.add_child(hunt)
	return hunt


func _open_pair() -> bool:
	_crate_events.clear()
	_revived_events.clear()
	_downed.clear()
	_died.clear()
	_revived.clear()
	var req: HuntRequest = HuntRequest.make_debug(MAP_ID, 0, Ids.MODE_HORDE, LEVEL)
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
	_check("pair_assembled", ok and _host.get_horde_level() == LEVEL and _client.get_horde_level() == LEVEL)
	if not ok:
		return false
	_host.debug_net_go()
	_client.debug_net_go()
	_host.get_player().bot_set_enabled(true)
	_client.get_player().bot_set_enabled(true)
	_park_both()
	_pump_on = true
	await _wait_pumps(SYNC_PUMPS)
	return true


func _close_pair() -> void:
	_pump_on = false
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


## Host -> client (snapshot, events), client -> host (its HUNTER_STATE, claims), as the Net session does.
func pump() -> void:
	_pump_count += 1
	var snap: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_snapshot(snap)
	var sin: StreamPeerBuffer = StreamPeerBuffer.new()
	sin.data_array = snap.data_array
	_client.net_apply_snapshot(sin)
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)
	_note_events(ev.data_array)
	_apply_events(ev.data_array)
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	if remote != null and not remote.is_local():
		var st: StreamPeerBuffer = StreamPeerBuffer.new()
		_client.get_player().net_write_state(st)
		if st.get_size() == NetCodec.HUNTER_STATE_BYTES:
			var stin: StreamPeerBuffer = StreamPeerBuffer.new()
			stin.data_array = st.data_array
			remote.net_apply_state(stin)
	var cl: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.net_take_claims(cl)
	_for_records(cl.data_array, func(type: int, i: StreamPeerBuffer, n: int) -> void: _host.net_apply_claim(CLIENT_SLOT, type, i, n))


func _note_events(data: PackedByteArray) -> void:
	for r: Array in _records(data):
		var body: PackedByteArray = r[1]
		if r[0] == NetCodec.EV_AMMO_CRATE and body.size() >= 3:
			_crate_events.append([body[0], body[1], body[2]])
		elif r[0] == NetCodec.EV_HUNTER_REVIVED and body.size() >= 2:
			_revived_events.append([body[0], body[1]])


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


## [type, body] of every record.
func _records(data: PackedByteArray) -> Array:
	var out: Array = []
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= data.size():
		var n: int = data.decode_u16(pos + 1)
		out.append([data[pos], data.slice(pos + 3, pos + 3 + n)])
		pos += 3 + n
	return out


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t: float = 0.0
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()):
		if t > timeout_s or float(Time.get_ticks_msec() - t0) > timeout_s * 1000.0 * 4.0:
			return false
		await get_tree().process_frame
		t += get_process_delta_time()
	return true


## Waits for n more pumps (real time), so a record or a state has crossed in both directions.
func _wait_pumps(n: int) -> void:
	var until: int = _pump_count + n
	var t0: int = Time.get_ticks_msec()
	while _pump_count < until and Time.get_ticks_msec() - t0 < PUMP_WAIT_REAL_MS:
		await get_tree().process_frame


func _wait_s(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _teleport(world: HuntController, at: Vector3) -> void:
	var p: PlayerBase = world.get_player()
	p.bot_set_enabled(true)
	p.bot_set_move(Vector2.ZERO, false)
	p.bot_teleport(Vector3(at.x, world.get_height(at.x, at.z) + 0.1, at.z))


func _park_both() -> void:
	_teleport(_host, _park_point(_host))
	_teleport(_client, _park_point(_client))


func _outcome_name(r: HuntResult) -> String:
	return HuntResult.Outcome.keys()[r.outcome] if r != null else "null"
