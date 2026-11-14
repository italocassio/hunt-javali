extends Node
## Package B sandbox for F4 (docs/multiplayer.md section 9, F4): boar replication in one process, without
## the Net autoload. The host hunt and the client hunt (inside a SubViewport with its own World3D, so the
## client's hitscan only meets puppets) are wired through the real byte paths: H_SNAPSHOT, EV_*, C_STATE, C_*.
## Covers: flora layout equal on every quality with sync_layout; spawn -> puppets; position error after the
## interpolation settles; multi-target perception (a remote hunter becomes the target); the client's real
## weapon killing a puppet (C_SHOT -> host -> EV_BOAR_HIT/EV_BOAR_DEATH -> credit only on the client);
## forged claims rejected; a charge judged on the client (damage + C_CHARGE_HIT -> EV_BOAR_ATTACK).
## Slots: the client is slot 0 and the host slot 1. With Net offline the weapon stamps slot 0 on its
## shot_id (weapon.gd uses Net.get_local_slot()), so the shooter must be slot 0 for the claim to be valid.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_boars_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 300.0
const HOST_SLOT: int = 1
const CLIENT_SLOT: int = 0
const SNAP_INTERVAL_S: float = 0.1
const MIN_BOARS: int = 5
const BOAR_WAIT_S: float = 30.0
const SETTLE_S: float = 0.8
const MAX_POS_ERROR_M: float = 0.01
const SHOT_STAND_M: float = 10.0
const MAX_SHOTS: int = 40
const AIM_SETTLE_FRAMES: int = 6
const EVENT_WAIT_S: float = 2.0
const TARGET_DIST_M: float = 6.0
const PERCEIVE_WAIT_S: float = 1.5
const FLORA_DENSITIES: Array[float] = [0.5, 0.75, 1.0]
const TRUNK_IDS: Array[StringName] = [&"ipe", &"cerrado_tree", &"buriti", &"termite_mound"]
const SCALED_ID: StringName = &"grass_tuft"
const SPOT_ANGLES: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _host: HuntController = null
var _client: HuntController = null
var _pump_on: bool = false
var _snapshots_on: bool = true
var _accum: float = 0.0
var _kills: Array[KillInfo] = []
var _client_kills: Array = []           # [kill, killed, total] from the replica


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	GameEvents.boar_killed.connect(func(k: KillInfo) -> void: _kills.append(k))
	await _flora_case()
	await _replication_case()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: sandbox timed out")
		get_tree().quit(1)
		return
	if _pump_on:
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


# --- Flora (section 6.4) -------------------------------------------------------------------------

func _flora_case() -> void:
	print("--- flora")
	var synced: Array[int] = []
	var plain: Array[int] = []
	var grass: Array[int] = []
	for d: float in FLORA_DENSITIES:
		var r: Array = _flora_hash(d, true)
		synced.append(int(r[0]))
		grass.append(int(r[1]))
		plain.append(int(_flora_hash(d, false)[0]))
		await get_tree().process_frame
	_check("flora_sync_trunks_equal_low_medium_high", synced[0] == synced[1] and synced[1] == synced[2], str(synced))
	_check("flora_sync_grass_still_scales", grass[0] < grass[1] and grass[1] < grass[2], str(grass))
	_check("flora_sync_high_equals_solo_high", synced[2] == plain[2], "%d / %d" % [synced[2], plain[2]])
	print("INFO flora solo (no sync) trunk hashes %s (A4: differ between qualities)" % str(plain))


## [hash of the trunk-like flora positions, count of the density-scaled id].
func _flora_hash(density: float, sync_layout: bool) -> Array:
	var map: MapRoot = (load(ScenePaths.map_scene(&"mato_grosso")) as PackedScene).instantiate() as MapRoot
	add_child(map)
	map.build_heightmap()
	map.build_terrain()
	map.build_props_and_water()
	map.build_flora(density, sync_layout)
	var all: PackedVector2Array = PackedVector2Array()
	for id: StringName in TRUNK_IDS:
		all.append_array(map.get_flora_positions(id))
	var out: Array = [hash(var_to_bytes(all)), map.get_flora_positions(SCALED_ID).size(), all.size()]
	map.queue_free()
	return out


# --- Replication ---------------------------------------------------------------------------------

func _roster() -> Array[NetPeerInfo]:
	var out: Array[NetPeerInfo] = []
	for i: int in 2:
		var info: NetPeerInfo = NetPeerInfo.new()
		info.slot = i
		info.display_name = "Cliente" if i == CLIENT_SLOT else "Anfitriao"
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


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()):
		if float(Time.get_ticks_msec() - t0) > timeout_s * 1000.0:
			return false
		await get_tree().process_frame
	return true


func _wait_s(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _replication_case() -> void:
	print("--- replication")
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0)
	req.rng_seed = 4242
	req.quality = Ids.Q_LOW
	req.player_count = 2
	Router.set_pending_request(req)
	_host = _make(Net.Role.HOST, HOST_SLOT, self)
	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(64, 64)
	add_child(vp)
	_client = _make(Net.Role.CLIENT, CLIENT_SLOT, vp)
	var ready: bool = await _wait_until(func() -> bool: return _host.is_world_ready() and _client.is_world_ready(), 120.0)
	_check("assembled", ready)
	if not ready:
		return
	_client.debug_replica().kill_confirmed.connect(func(k: KillInfo, a: int, b: int) -> void: _client_kills.append([k, a, b]))
	_host.debug_net_go()
	_client.debug_net_go()
	_pump_on = true
	var spawned: bool = await _wait_until(func() -> bool: return _host.get_alive_boar_ids().size() >= MIN_BOARS, BOAR_WAIT_S)
	_check("host_boars_spawn", spawned, "alive=%d" % _host.get_alive_boar_ids().size())
	await _wait_s(0.5)
	await _check_spawned()
	await _check_settled()
	await _check_multi_target()
	await _check_shoot_and_kill()
	_check_forged_claims()
	await _check_charge()
	_pump_on = false
	_host.queue_free()
	_client.queue_free()
	Router.set_pending_request(null)
	await get_tree().process_frame


## Host -> client and client -> host, through the record byte paths Net uses.
func pump() -> void:
	var snap: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_write_snapshot(snap)
	if _snapshots_on:
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = snap.data_array
		_client.net_apply_snapshot(inp)
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)
	_for_records(ev.data_array, func(type: int, inp: StreamPeerBuffer, n: int) -> void: _client.net_apply_event(type, inp, n))
	var st: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.get_player().net_write_state(st)
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	if st.get_size() == NetCodec.HUNTER_STATE_BYTES and remote != null:
		var sin: StreamPeerBuffer = StreamPeerBuffer.new()
		sin.data_array = st.data_array
		remote.net_apply_state(sin)
	var cl: StreamPeerBuffer = StreamPeerBuffer.new()
	_client.net_take_claims(cl)
	_for_records(cl.data_array, func(type: int, inp: StreamPeerBuffer, n: int) -> void: _host.net_apply_claim(CLIENT_SLOT, type, inp, n))


func _for_records(data: PackedByteArray, fn: Callable) -> void:
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= data.size():
		var type: int = data[pos]
		var n: int = data.decode_u16(pos + 1)
		var body: PackedByteArray = data.slice(pos + 3, pos + 3 + n)
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = body
		fn.call(type, inp, n)
		pos += 3 + n


func _check_spawned() -> void:
	var host_ids: PackedInt32Array = _host.get_alive_boar_ids().duplicate()
	var client_ids: PackedInt32Array = _client.get_alive_boar_ids().duplicate()
	host_ids.sort()
	client_ids.sort()
	_check("puppets_match_host_boars", host_ids == client_ids, "host=%s client=%s" % [host_ids, client_ids])
	var types_ok: bool = true
	for id: int in host_ids:
		types_ok = types_ok and _host.get_boar_type(id) == _client.get_boar_type(id)
	_check("puppet_types_match", types_ok)
	var p: BoarPuppet = _client.debug_replica().get_puppet(host_ids[0]) if not host_ids.is_empty() else null
	var b: Boar = _host.spawner.get_boar(host_ids[0]) if not host_ids.is_empty() else null
	_check("puppet_has_four_hitzones", p != null and p.get_node_or_null(^"HitHead") is HitZone
		and p.get_node_or_null(^"HitRear") is HitZone and p.get_node_or_null(^"Visual") is BoarVisualBase)
	if p != null and b != null:
		_check("puppet_weight", absf(p.weight_kg - b.weight_kg) < 0.01, "%.3f / %.3f" % [p.weight_kg, b.weight_kg])


## Host boars frozen: after the interpolation delay every puppet sits on its boar (quantization only).
func _check_settled() -> void:
	var moving_err: float = _max_error()
	_freeze(true)
	await _wait_s(SETTLE_S)
	var err: float = _max_error()
	_check("settled_position_error_le_1cm", err <= MAX_POS_ERROR_M, "max=%.4f m (moving, before freeze: %.3f m)" % [err, moving_err])
	var yaw_err: float = 0.0
	for id: int in _host.get_alive_boar_ids():
		var p: BoarPuppet = _client.debug_replica().get_puppet(id)
		yaw_err = maxf(yaw_err, absf(angle_difference(p.get_yaw(), _host.spawner.get_boar(id).get_yaw())))
	_check("settled_yaw_error_le_1_4_deg", yaw_err <= deg_to_rad(1.41), "max=%.2f deg" % rad_to_deg(yaw_err))
	_freeze(false)


func _max_error() -> float:
	var worst: float = 0.0
	for id: int in _host.get_alive_boar_ids():
		var b: Boar = _host.spawner.get_boar(id)
		var p: BoarPuppet = _client.debug_replica().get_puppet(id)
		if p == null:
			return INF
		worst = maxf(worst, p.global_position.distance_to(b.global_position))
	return worst


func _freeze(on: bool) -> void:
	for b: Boar in _host.spawner.get_alive():
		b.set_process(not on)


## The host's local hunter far away, the client's hunter in front of a boar: the boar targets the remote one.
func _check_multi_target() -> void:
	_freeze(true)
	var b: Boar = _host.spawner.get_alive()[0]
	var far: Vector2 = Vector2(-118.0, -118.0)
	_host.get_player().bot_set_enabled(true)
	_host.get_player().bot_teleport(Vector3(far.x, _host.get_height(far.x, far.y) + 0.05, far.y))
	var front: Vector2 = b.get_xz() + Steering.dir_from_yaw(b.get_yaw()) * TARGET_DIST_M
	var cp: PlayerBase = _client.get_player()
	cp.bot_set_enabled(true)
	cp.bot_teleport(Vector3(front.x, _client.get_height(front.x, front.y) + 0.05, front.y))
	cp.bot_look_at(b.global_position)
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	var arrived: bool = await _wait_until(func() -> bool:
		return Vector2(remote.global_position.x, remote.global_position.z).distance_to(front) < 0.1, 3.0)
	_check("remote_hunter_follows_client_state", arrived and remote.is_present(),
		"at %s want %s" % [Vector2(remote.global_position.x, remote.global_position.z), front])
	b.set_process(true)
	var seen: bool = await _wait_until(func() -> bool: return b.get("_target_hunter") == remote, PERCEIVE_WAIT_S)
	_check("boar_targets_remote_hunter", seen, "state=%s target=%s" % [b.state, str(b.get("_target_hunter"))])
	_check("boar_reacted_to_remote", b.state != Ids.BS_WANDER and b.state != Ids.BS_EAT and b.state != Ids.BS_TO_CROP,
		"state=%s" % b.state)
	b.set_process(false)


## The client's real weapon kills a puppet; the host applies the claims; only the client is credited.
func _check_shoot_and_kill() -> void:
	_freeze(true)
	await _wait_s(SETTLE_S)
	var host_sync: HuntHostSync = _host.debug_host_sync()
	var replica: HuntReplica = _client.debug_replica()
	# Shoot one that cannot charge, so a charger is left for _check_charge.
	var id: int = _host.get_alive_boar_ids()[-1]
	for cand: int in _host.get_alive_boar_ids():
		if float(Data.get_boar_type(_host.get_boar_type(cand)).get("charge_damage", 0.0)) <= 0.0:
			id = cand
			break
	var b: Boar = _host.spawner.get_boar(id)
	var cp: PlayerBase = _client.get_player()
	var target: Vector3 = _client.get_boar_zone_position(id, &"vital")
	var spot: Vector3 = _clear_spot(target, cp.global_position)
	_check("shot_spot_found", spot != Vector3.INF)
	if spot == Vector3.INF:
		return
	cp.bot_teleport(spot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	cp.bot_set_aim(true)
	var kills_before: int = _client_kills.size()
	var shots: int = 0
	var first_hit_checked: bool = false
	var health0: float = b.health
	while b.is_alive() and shots < MAX_SHOTS:
		cp.bot_look_at(_client.get_boar_zone_position(id, &"vital"))
		for i: int in AIM_SETTLE_FRAMES:
			await get_tree().process_frame
		if cp.get_ammo_in_mag() <= 0:
			cp.bot_reload()
			await _wait_s(3.0)
			continue
		if cp.bot_fire():
			shots += 1
			await _wait_s(0.3)
			if not first_hit_checked and replica.hits_claimed > 0:
				first_hit_checked = true
				_check("first_hit_reaches_host", host_sync.hits_accepted > 0 and b.health < health0,
					"claimed=%d accepted=%d health %.1f -> %.1f" % [replica.hits_claimed, host_sync.hits_accepted, health0, b.health])
				_check("boar_killer_slot_is_shooter", b.killer_slot == CLIENT_SLOT, str(b.killer_slot))
	_check("client_shots_kill_host_boar", not b.is_alive(), "shots=%d claimed_hits=%d accepted=%d rejected=%d"
		% [shots, replica.hits_claimed, host_sync.hits_accepted, host_sync.hits_rejected])
	var got: bool = await _wait_until(func() -> bool: return _client_kills.size() > kills_before, EVENT_WAIT_S)
	_check("client_receives_death", got and not replica.get_puppet(id).alive and not _client.get_alive_boar_ids().has(id))
	if not got:
		return
	var k: KillInfo = _client_kills[-1][0]
	_check("death_event_fields", k.boar_id == id and k.killer_slot == CLIENT_SLOT and k.type_id == b.type_id
		and k.reward_money > 0 and int(_client_kills[-1][1]) == _host.get_boars_killed(),
		"id=%d killer=%d reward=%d killed=%d/%d" % [k.boar_id, k.killer_slot, k.reward_money, int(_client_kills[-1][1]), _host.get_boars_killed()])
	var host_res: HuntResult = _host.debug_partial_result()
	var client_res: HuntResult = _client.debug_partial_result()
	_check("credit_only_on_client", _ids_of(client_res).has(id) and not _ids_of(host_res).has(id),
		"client=%s host=%s" % [_ids_of(client_res), _ids_of(host_res)])
	_check("team_counts_equal", _client.get_boars_killed() == _host.get_boars_killed()
		and _client.get_boars_total() == _host.get_boars_total(),
		"%d/%d vs %d/%d" % [_client.get_boars_killed(), _client.get_boars_total(), _host.get_boars_killed(), _host.get_boars_total()])
	_check("shots_hit_only_local", client_res.shots_hit >= 1 and host_res.shots_hit == 0,
		"client=%d host=%d" % [client_res.shots_hit, host_res.shots_hit])
	_check("puppet_zones_disabled_after_death", (replica.get_puppet(id).get_node(^"HitVital") as HitZone).collision_layer == 0)


func _ids_of(r: HuntResult) -> Array:
	var out: Array = []
	for k: KillInfo in r.kills:
		out.append(k.boar_id)
	return out


func _clear_spot(target: Vector3, from: Vector3) -> Vector3:
	var base: Vector3 = Vector3(from.x - target.x, 0.0, from.z - target.z)
	base = base.normalized() if base.length() > 0.5 else Vector3.BACK
	var space: PhysicsDirectSpaceState3D = _client.get_world_3d().direct_space_state
	for deg: float in SPOT_ANGLES:
		var d: Vector3 = base.rotated(Vector3.UP, deg_to_rad(deg))
		var x: float = target.x + d.x * SHOT_STAND_M
		var z: float = target.z + d.z * SHOT_STAND_M
		var feet: Vector3 = Vector3(x, _client.get_height(x, z) + 0.05, z)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(feet + Vector3(0.0, 1.65, 0.0), target,
			Layers.MASK_LINE_OF_SIGHT)
		if space.intersect_ray(q).is_empty():
			return feet
	return Vector3.INF


## Claims the host must refuse: wrong shooter slot, too much damage, impossible distance, dead boar.
func _check_forged_claims() -> void:
	var host_sync: HuntHostSync = _host.debug_host_sync()
	var b: Boar = _host.spawner.get_alive()[0]
	var health0: float = b.health
	var rejected0: int = host_sync.hits_rejected
	var origin: Vector3 = b.get_zone_position(&"vital") + Vector3(10.0, 0.0, 0.0)
	var dist: float = 10.0
	var carbine: int = Data.get_weapon_ids().find(Ids.W_CARBINE_22)
	var damage: float = float(Data.get_weapon(Ids.W_CARBINE_22)["damage"])
	_claim(NetCodec.make_shot_id(HOST_SLOT, 7), carbine, origin, b.boar_id, 1, damage, dist)            # slot of another hunter
	_claim(NetCodec.make_shot_id(CLIENT_SLOT, 8), carbine, origin, b.boar_id, 1, damage * 3.0, dist)     # damage above the weapon
	_claim(NetCodec.make_shot_id(CLIENT_SLOT, 9), carbine, origin, b.boar_id, 1, damage, dist + 40.0)    # far from the boar here
	_check("forged_claims_rejected", host_sync.hits_rejected - rejected0 == 3 and is_equal_approx(b.health, health0),
		"rejected=%d health %.1f -> %.1f" % [host_sync.hits_rejected - rejected0, health0, b.health])
	_claim(NetCodec.make_shot_id(CLIENT_SLOT, 10), carbine, origin, b.boar_id, 1, damage * 0.5, dist + 3.0)  # plausible
	_check("plausible_claim_accepted", b.health < health0, "health %.1f -> %.1f" % [health0, b.health])


func _claim(shot_id: int, weapon: int, origin: Vector3, boar_id: int, zone: int, damage: float, dist: float) -> void:
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	out.put_u32(shot_id)
	out.put_u8(weapon)
	NetCodec.put_xz(out, _host.get_map_rect(), origin.x, origin.z)
	out.put_16(roundi(origin.y * 100.0))
	out.put_u8(1)
	out.put_u8(boar_id)
	out.put_u8(zone)
	out.put_u16(roundi(damage * 10.0))
	out.put_u16(roundi(dist * 10.0))
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = out.data_array
	_host.net_apply_claim(CLIENT_SLOT, NetCodec.C_SHOT, inp, out.get_size())


## The client judges a charge against its own hunter (pose it shows), sends C_CHARGE_HIT once; the host
## accepts it only for a boar charging (or just recovering) and tells everybody with EV_BOAR_ATTACK.
func _check_charge() -> void:
	_freeze(true)
	await _wait_s(SETTLE_S)
	var replica: HuntReplica = _client.debug_replica()
	var host_sync: HuntHostSync = _host.debug_host_sync()
	var p: BoarPuppet = null
	for id: int in _client.get_alive_boar_ids():
		var cand: BoarPuppet = replica.get_puppet(id)
		if float(Data.get_boar_type(cand.type_id).get("charge_damage", 0.0)) > 0.0:
			p = cand
			break
	_check("charging_puppet_found", p != null)
	if p == null:
		return
	var cp: PlayerBase = _client.get_player()
	cp.heal(1000.0)
	var health0: float = cp.get_health()
	# Victim 1 m ahead of the snout, then a snapshot sample saying "charge" (the host state is frozen).
	var ahead: Vector2 = p.get_xz() + Steering.dir_from_yaw(p.get_yaw()) * (Boar.SNOUT_OFFSET_M * p.body_scale + 0.3)
	cp.bot_teleport(Vector3(ahead.x, _client.get_height(ahead.x, ahead.y) + 0.02, ahead.y))
	await get_tree().physics_frame
	_snapshots_on = false
	var charge_st: int = NetCodec.BOAR_STATES.find(Ids.BS_CHARGE) | Boar.NET_ST_CHARGE_TOGGLE
	# Later than every buffered sample (those run up to the delay ahead of the render time).
	var delay_ms: float = float(Data.get_net()["boar_interp_delay_ms"])
	p.push_sample(replica.render_time_ms() + delay_ms * 2.0, p.get_xz(), p.get_yaw(), charge_st)
	var hit: bool = await _wait_until(func() -> bool: return replica.charge_hits > 0, 2.0)
	var dmg: float = float(Data.get_boar_type(p.type_id)["charge_damage"])
	_check("client_judges_charge", hit and absf((health0 - cp.get_health()) - dmg) < 0.01,
		"hits=%d health %.1f -> %.1f (damage %.1f)" % [replica.charge_hits, health0, cp.get_health(), dmg])
	await _wait_s(0.5)
	_check("charge_hit_once_per_charge", replica.charge_hits == 1, str(replica.charge_hits))
	# The claim went out with the pump: the host boar was not charging -> refused.
	var b: Boar = _host.spawner.get_boar(p.boar_id)
	_check("host_refuses_claim_without_charge", host_sync.charge_claims_rejected == 1 and host_sync.charge_claims_accepted == 0,
		"rej=%d acc=%d state=%s" % [host_sync.charge_claims_rejected, host_sync.charge_claims_accepted, b.state])
	# Host boar really charging: the same claim is accepted once, the boar recovers, the clients hear it.
	b.set("_threat", Vector2(cp.global_position.x, cp.global_position.z))
	b.call("_enter_charge")
	var attacks: Array = []
	var ev: StreamPeerBuffer = StreamPeerBuffer.new()
	_host.net_take_events(ev)   # drop what was queued until now
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = PackedByteArray([p.boar_id])
	_host.net_apply_claim(CLIENT_SLOT, NetCodec.C_CHARGE_HIT, inp, 1)
	inp.seek(0)
	_host.net_apply_claim(CLIENT_SLOT, NetCodec.C_CHARGE_HIT, inp, 1)
	ev.clear()
	_host.net_take_events(ev)
	_for_records(ev.data_array, func(type: int, i: StreamPeerBuffer, _n: int) -> void:
		if type == NetCodec.EV_BOAR_ATTACK:
			attacks.append([i.get_u8(), i.get_u8()]))
	_check("host_accepts_charge_claim_once", host_sync.charge_claims_accepted == 1 and b.state == Ids.BS_RECOVER,
		"acc=%d state=%s" % [host_sync.charge_claims_accepted, b.state])
	_check("ev_boar_attack_names_victim", attacks.size() == 1 and int(attacks[0][0]) == p.boar_id and int(attacks[0][1]) == CLIENT_SLOT,
		str(attacks))
	_snapshots_on = true
