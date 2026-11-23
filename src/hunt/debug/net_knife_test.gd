extends Node
## Package B sandbox for the knife swing over the network (docs/plano_faca_mochila_folego.md sections 1.5 and 2.8): a host
## hunt and a client hunt in one process (test_net_role hooks, the client inside a SubViewport with its own World3D),
## wired through the real byte paths (H_SNAPSHOT, EV_*, C_*). The swing itself is Package A's job (Player / Knife); here
## it is played the way the Knife does it: a HitInfo with weapon_id = Ids.KNIFE on a puppet hit zone, then
## HuntReplica._on_shot_fired(Ids.KNIFE, ...) closes the C_SHOT. The pump is paused for the claim cases so the bytes of the
## C_SHOT can be read before they reach the host.
## Cases: the C_SHOT carries weapon 254 and is applied (damage = hit damage x zone multiplier, any level up to the top one);
## the reach edge (2.2 m) is accepted; damage above the top level, a hit beyond the reach, two hits in one swing and a
## swing without a knife in the data are refused (hits_rejected); a miss is heard; a gun's claim and an unknown weapon
## still behave as before; a knife kill reaches the client with the killer and one_shot.
## Slots: host 0, client 1 (like net_sync_test).
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_knife_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/ (net_unit).

const WATCHDOG_REAL_S: float = 300.0
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SNAP_INTERVAL_S: float = 0.1
const MAP_ID: StringName = &"mato_grosso"
const CONTRACT: int = 0
const SEED: int = 9393
const ASSEMBLE_S: float = 120.0
const BOAR_WAIT_S: float = 30.0
const DEATH_WAIT_S: float = 3.0
const MIN_BOARS: int = 3
const SWING_DIST_M: float = 1.5
const OVER_REACH_M: float = 3.0         # past reach_m (2.2) + DIST_SLACK_M, still inside hit_claim_tolerance_m
const GUN_DIST_M: float = 10.0
const OVER_DAMAGE: float = 5.0          # above the top level's damage + DAMAGE_SLACK
const BIG_HEALTH: float = 100000.0
const HOST_PARK: Vector2 = Vector2(-118.0, -118.0)
const CLIENT_PARK: Vector2 = Vector2(118.0, -118.0)
const C_SHOT_WEAPON_AT: int = 4         # weapon byte inside a C_SHOT body (after shot_id u32)

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _host: HuntController = null
var _client: HuntController = null
var _vp: SubViewport = null
var _pump_on: bool = false
var _accum: float = 0.0
var _shot_counter: int = 0
var _client_kills: Array[KillInfo] = []


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	await _run()
	await _close_pair()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
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
	var knife_levels: int = Data.get_upgrade_level_count(Ids.KNIFE)
	_check("knife_in_data", knife_levels >= 1, "levels=%d" % knife_levels)
	if knife_levels < 1:
		return
	var stats: Dictionary = Data.get_upgrade(Ids.KNIFE).get("stats", {})
	var top: float = float(Data.get_upgrade_level_def(Ids.KNIFE, knife_levels).get("damage", 0.0))
	var low: float = float(Data.get_upgrade_level_def(Ids.KNIFE, 1).get("damage", 0.0))
	var reach: float = float(stats.get("reach_m", 0.0))
	var mults: Dictionary = Data.get_boar_rules()["zone_multipliers"]
	var body_mult: float = float(mults["body"])
	if not await _open_pair():
		return
	var sync: HuntHostSync = _host.debug_host_sync()
	var replica: HuntReplica = _client.debug_replica()
	replica.kill_confirmed.connect(func(k: KillInfo, _a: int, _b: int) -> void: _client_kills.append(k))
	_park(_host, HOST_PARK)
	_park(_client, CLIENT_PARK)
	var seen: bool = await _wait_until(func() -> bool:
		return _host.get_alive_boar_ids().size() >= MIN_BOARS and _same_ids(), BOAR_WAIT_S)
	_check("boars_on_both", seen, "host=%s client=%s" % [_host.get_alive_boar_ids(), _client.get_alive_boar_ids()])
	if not seen:
		return
	_pump_on = false
	await _wait_s(0.3)   # the last records of the pump reach their ends

	# The limits the host judges a swing by, built once at setup from the top level and the knife stats.
	var want_def: Dictionary = {"damage": top, "pellets": 1, "max_range_m": reach, "noise_radius_m": float(stats.get("noise_radius_m", 0.0))}
	_check("host_knife_def_from_data", sync._knife_def == want_def, "def=%s" % str(sync._knife_def))

	var ids: PackedInt32Array = _host.get_alive_boar_ids().duplicate()
	var target: Boar = _host.spawner.get_boar(ids[0])
	target.health = BIG_HEALTH
	var health: float = target.health

	# 1. A swing at the top level's damage: weapon byte 254, applied by the host at damage x zone multiplier.
	var acc0: int = sync.hits_accepted
	var rej0: int = sync.hits_rejected
	var heard0: int = sync.shots_heard
	var records: Array = _deliver(_swing(target, &"body", top, SWING_DIST_M, Ids.KNIFE))
	var weapon_byte: int = (records[0][1] as PackedByteArray)[C_SHOT_WEAPON_AT] if not records.is_empty() else -1
	_check("knife_claim_is_one_c_shot_with_weapon_254", records.size() == 1 and int(records[0][0]) == NetCodec.C_SHOT
		and weapon_byte == NetCodec.KNIFE_WEAPON_INDEX and NetCodec.KNIFE_WEAPON_INDEX == 254, "records=%d weapon=%d" % [records.size(), weapon_byte])
	_check("host_applies_top_level_swing", sync.hits_accepted == acc0 + 1 and sync.hits_rejected == rej0
		and sync.shots_heard == heard0 + 1 and is_equal_approx(health - target.health, top * body_mult),
		"accepted +%d rejected +%d lost %.1f (want %.1f)" % [sync.hits_accepted - acc0, sync.hits_rejected - rej0, health - target.health, top * body_mult])
	health = target.health

	# 2. A lower level's damage is fine (the host judges against the top level, not the claimant's level); the head
	#    multiplier is the boar's, not the client's.
	acc0 = sync.hits_accepted
	_deliver(_swing(target, &"head", low, SWING_DIST_M, Ids.KNIFE))
	_check("host_applies_level_1_swing_on_head", sync.hits_accepted == acc0 + 1
		and is_equal_approx(health - target.health, low * float(mults["head"])),
		"lost %.1f (want %.1f)" % [health - target.health, low * float(mults["head"])])
	health = target.health

	# 3. Exactly at the reach: accepted.
	acc0 = sync.hits_accepted
	_deliver(_swing(target, &"body", top, reach, Ids.KNIFE))
	_check("host_accepts_swing_at_reach", sync.hits_accepted == acc0 + 1 and is_equal_approx(health - target.health, top * body_mult),
		"reach=%.2f lost %.1f" % [reach, health - target.health])
	health = target.health

	# 4. Damage above the top level (+ rounding slack): refused.
	rej0 = sync.hits_rejected
	acc0 = sync.hits_accepted
	_deliver(_swing(target, &"body", top + OVER_DAMAGE, SWING_DIST_M, Ids.KNIFE))
	_check("host_rejects_damage_above_top_level", sync.hits_rejected == rej0 + 1 and sync.hits_accepted == acc0
		and is_equal_approx(target.health, health), "rejected +%d health %.1f -> %.1f" % [sync.hits_rejected - rej0, health, target.health])

	# 5. A hit beyond the reach (a gun-range claim under the knife byte): refused.
	for far: float in [OVER_REACH_M, GUN_DIST_M]:
		rej0 = sync.hits_rejected
		_deliver(_swing(target, &"body", top, far, Ids.KNIFE))
		_check("host_rejects_hit_beyond_reach_%.0fm" % far, sync.hits_rejected == rej0 + 1 and is_equal_approx(target.health, health),
			"rejected +%d health %.1f -> %.1f" % [sync.hits_rejected - rej0, health, target.health])

	# 6. Two hits in one swing (a knife has one "pellet"): both refused.
	rej0 = sync.hits_rejected
	_deliver(_swing_many(target, [&"body", &"vital"], top, SWING_DIST_M, Ids.KNIFE))
	_check("host_rejects_two_hits_in_one_swing", sync.hits_rejected == rej0 + 2 and is_equal_approx(target.health, health),
		"rejected +%d health %.1f -> %.1f" % [sync.hits_rejected - rej0, health, target.health])

	# 7. A miss is claimed and heard (noise 0), nothing is rejected.
	rej0 = sync.hits_rejected
	heard0 = sync.shots_heard
	var miss: Array = _deliver(_swing_many(target, [], top, SWING_DIST_M, Ids.KNIFE))
	_check("host_hears_missed_swing", miss.size() == 1 and sync.shots_heard == heard0 + 1 and sync.hits_rejected == rej0
		and is_equal_approx(target.health, health), "records=%d heard +%d" % [miss.size(), sync.shots_heard - heard0])

	# 8. No knife in the data (the limits are empty): the swing is refused, like an unknown weapon.
	var saved_def: Dictionary = sync._knife_def
	sync._knife_def = {}
	rej0 = sync.hits_rejected
	heard0 = sync.shots_heard
	_deliver(_swing(target, &"body", low, SWING_DIST_M, Ids.KNIFE))
	_check("host_rejects_swing_without_knife_in_data", sync.hits_rejected == rej0 + 1 and sync.shots_heard == heard0
		and is_equal_approx(target.health, health), "rejected +%d heard +%d" % [sync.hits_rejected - rej0, sync.shots_heard - heard0])
	sync._knife_def = saved_def

	# 9. A gun still goes through its own index and limits; an unknown id goes out as "no weapon" and is refused.
	var gun: StringName = Ids.W_CARBINE_22
	var gun_index: int = Data.get_weapon_ids().find(gun)
	var gun_damage: float = float(Data.get_weapon(gun)["damage"])
	acc0 = sync.hits_accepted
	rej0 = sync.hits_rejected
	var gun_records: Array = _deliver(_swing(target, &"body", gun_damage, GUN_DIST_M, gun))
	var gun_byte: int = (gun_records[0][1] as PackedByteArray)[C_SHOT_WEAPON_AT] if not gun_records.is_empty() else -1
	_check("gun_claim_unchanged", gun_records.size() == 1 and gun_byte == gun_index
		and sync.hits_accepted == acc0 + 1 and sync.hits_rejected == rej0 and is_equal_approx(health - target.health, gun_damage * body_mult),
		"index=%d byte=%d accepted +%d lost %.1f" % [gun_index, gun_byte, sync.hits_accepted - acc0, health - target.health])
	health = target.health
	rej0 = sync.hits_rejected
	heard0 = sync.shots_heard
	var odd: Array = _deliver(_swing(target, &"body", low, SWING_DIST_M, &"not_a_weapon"))
	var odd_byte: int = (odd[0][1] as PackedByteArray)[C_SHOT_WEAPON_AT] if not odd.is_empty() else -1
	_check("unknown_weapon_still_refused", odd.size() == 1 and odd_byte == HuntReplica.NO_INDEX
		and sync.hits_rejected == rej0 + 1 and sync.shots_heard == heard0 and is_equal_approx(target.health, health),
		"weapon byte=%d rejected +%d" % [odd_byte, sync.hits_rejected - rej0])

	# 10. A knife kill reaches the client with the killer and "one shot": the weakest other boar, one head swing at the top level.
	var weak: Boar = null
	for id: int in ids:
		var cand: Boar = _host.spawner.get_boar(id)
		if cand != target and cand.is_alive() and (weak == null or cand.health < weak.health):
			weak = cand
	var head_damage: float = top * float(mults["head"])
	if weak.health > head_damage:
		print("trace knife: lowest health %.1f > %.1f, set to the head damage" % [weak.health, head_damage])
		weak.health = head_damage
	var weak_id: int = weak.boar_id
	var kills0: int = _client_kills.size()
	_deliver(_swing(weak, &"head", top, SWING_DIST_M, Ids.KNIFE))
	_check("host_boar_dies_to_the_swing", not weak.is_alive() and weak.killer_slot == CLIENT_SLOT, "alive=%s killer=%d" % [weak.is_alive(), weak.killer_slot])
	_pump_on = true
	var got: bool = await _wait_until(func() -> bool: return _client_kills.size() > kills0, DEATH_WAIT_S)
	_check("client_gets_the_knife_kill", got and _client_kills[-1].boar_id == weak_id and _client_kills[-1].killer_slot == CLIENT_SLOT
		and _client_kills[-1].one_shot, JSON.stringify(_client_kills[-1].to_dict()) if got else "no kill")
	_pump_on = false


# --- A swing, played the way the Knife does it ----------------------------------------------------

## One swing with one hit on `zone` of the boar's puppet (shot_id of the client slot), closed by shot_fired(weapon_id).
## Returns the bytes of the claims the client queued.
func _swing(boar: Boar, zone: StringName, damage: float, dist: float, weapon_id: StringName) -> PackedByteArray:
	return _swing_many(boar, [zone], damage, dist, weapon_id)


func _swing_many(boar: Boar, zones: Array, damage: float, dist: float, weapon_id: StringName) -> PackedByteArray:
	var replica: HuntReplica = _client.debug_replica()
	var puppet: BoarPuppet = replica.get_puppet(boar.boar_id)
	_shot_counter += 1
	var shot_id: int = NetCodec.make_shot_id(CLIENT_SLOT, _shot_counter)
	var target_at: Vector3 = boar.get_zone_position(&"body")
	var origin: Vector3 = target_at + Vector3(dist, 0.0, 0.0)
	for zone: StringName in zones:
		var hit: HitInfo = HitInfo.new()
		hit.shot_id = shot_id
		hit.weapon_id = weapon_id
		hit.damage = damage
		hit.origin = origin
		hit.position = target_at
		hit.direction = (target_at - origin).normalized()
		hit.distance_m = dist
		hit.shooter_slot = CLIENT_SLOT
		(puppet.get_node(Boar.HIT_ZONE_NODES[zone] as NodePath) as HitZone).receive_hit(hit)
	replica._on_shot_fired(weapon_id, origin, (target_at - origin).normalized(), 0.0)
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.net_take_claims(out)
	return out.data_array


## Hands every record of those bytes to the host as the client's claim; returns [[type, body]] of all the records.
func _deliver(data: PackedByteArray) -> Array:
	var out: Array = []
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= data.size():
		var type: int = data[pos]
		var n: int = data.decode_u16(pos + 1)
		var body: PackedByteArray = data.slice(pos + 3, pos + 3 + n)
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = body
		_host.net_apply_claim(CLIENT_SLOT, type, inp, n)
		out.append([type, body])
		pos += 3 + n
	return out


# --- Pair plumbing (same as net_sync_test) --------------------------------------------------------

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


func _open_pair() -> bool:
	var req: HuntRequest = HuntRequest.make_debug(MAP_ID, CONTRACT)
	req.rng_seed = SEED
	req.quality = Ids.Q_LOW
	req.player_count = 2
	Router.set_pending_request(req)
	_host = _make(Net.Role.HOST, HOST_SLOT, self)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_client = _make(Net.Role.CLIENT, CLIENT_SLOT, _vp)
	var ok: bool = await _wait_until(func() -> bool: return _host.is_world_ready() and _client.is_world_ready(), ASSEMBLE_S)
	_check("assembled", ok)
	if not ok:
		return false
	_host.debug_net_go()
	_client.debug_net_go()
	_pump_on = true
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


## Host -> client and client -> host, through the record byte paths Net uses.
func pump() -> void:
	var snap: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_snapshot(snap)
	var sin: StreamPeerBuffer = StreamPeerBuffer.new()
	sin.data_array = snap.data_array
	_client.net_apply_snapshot(sin)
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)
	_for_records(ev.data_array, func(type: int, i: StreamPeerBuffer, n: int) -> void: _client.net_apply_event(type, i, n))
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	if remote != null and not remote.is_local():
		var st: StreamPeerBuffer = StreamPeerBuffer.new()
		_client.get_player().net_write_state(st)
		if st.get_size() == NetCodec.HUNTER_STATE_BYTES:
			var state_in: StreamPeerBuffer = StreamPeerBuffer.new()
			state_in.data_array = st.data_array
			remote.net_apply_state(state_in)
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
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()):
		if float(Time.get_ticks_msec() - t0) > timeout_s * 1000.0 * 4.0:
			return false
		await get_tree().process_frame
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


func _same_ids() -> bool:
	var a: PackedInt32Array = _host.get_alive_boar_ids().duplicate()
	var b: PackedInt32Array = _client.get_alive_boar_ids().duplicate()
	a.sort()
	b.sort()
	return a == b
