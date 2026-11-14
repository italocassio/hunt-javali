extends Node
## Package B sandbox for F7 (docs/multiplayer.md section 9, F7 "N6"): the dogs of a network hunt in one process,
## without the Net autoload. A host hunt (slot 0, foxhound) and a client hunt (slot 1, caramelo, inside a
## SubViewport with its own World3D) are wired through the real byte paths (H_SNAPSHOT, EV_*, C_STATE, C_*), like
## net_flow_test. Both hunts share GameEvents, so counts on the bus are the sum of both machines: the checks
## are written so that a wrong extra emission (a remote-owned dog talking to the local HUD) shows up as a count.
## Cases (one pair, in order):
##   setup      host simulates 2 dogs (one per owner, right breeds); the client has none but 2 puppets (after
##              the first snapshot); has_dog() answers by the local hunter's dog on both.
##   signals    HUD signals of dogs: exactly one source per owner (no copy from the remote-owned Dog).
##   command    the client's C_DOG_CMD changes only the client's dog; dog_command_executed once (client HUD).
##   mark       the dog of the client points at a boar: the mark is on BOTH machines (marked positions and
##              dog_marked_boar); the puppet shows `point`; the client HUD gets dog_state_changed(point).
##   message    EV_MESSAGE goes to the owner only (retreat of the client's dog -> one message, on the client).
##   follow     the client's dog follows the client when it walks away; settled puppet <= 1 cm from the Dog.
##   killer     a kill by the dog counts for its owner (Boar.killer_slot).
##   owner_dead host hunter dies: its dog stays where it is and ignores commands; the client's dog goes on.
##   owner_left net_peer_left(1): the Dog is removed on the host and the puppet on the client.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_dogs_test.tscn
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 400.0
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SNAP_INTERVAL_S: float = 0.1
const MAP_ID: StringName = &"mato_grosso"
const CONTRACT: int = 0
const SEED: int = 7373
const ASSEMBLE_S: float = 120.0
const BOAR_WAIT_S: float = 40.0
const PUPPET_WAIT_S: float = 3.0
const SETTLE_TOL_M: float = 0.01
const FOLLOW_MAX_M: float = 6.0
const WALK_OFFSET: Vector3 = Vector3(25.0, 0.0, 0.0)
const POINT_DISTANCE_M: float = 10.0
const FAR_OFFSET: Vector3 = Vector3(30.0, 0.0, 0.0)
const KILL_DAMAGE: float = 100000.0
const HURT_DAMAGE: float = 90.0
const REAL_WAIT_MS: int = 8000
const STILL_EPS_M: float = 0.001
const STILL_TRIES: int = 60
const FAR_FROM_BOAR_M: float = 70.0

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _host: HuntController = null
var _client: HuntController = null
var _vp: SubViewport = null
var _pump_on: bool = false
var _pump_real: bool = false
var _accum: float = 0.0
var _last_pump_ms: int = 0
var _states: Array[StringName] = []      # dog_state_changed on the shared bus
var _healths: Array[float] = []
var _commands: Array[StringName] = []
var _marks: int = 0
var _texts: Array[String] = []


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	GameEvents.dog_state_changed.connect(func(s: StringName) -> void: _states.append(s))
	GameEvents.dog_health_changed.connect(func(p: float) -> void: _healths.append(p))
	GameEvents.dog_command_executed.connect(func(c: StringName) -> void: _commands.append(c))
	GameEvents.dog_marked_boar.connect(func(_p: Vector3, _d: float) -> void: _marks += 1)
	GameEvents.hud_message_requested.connect(func(t: String, _s: float) -> void: _texts.append(t))
	if await _open_pair():
		await _setup_checks()
		await _signal_checks()
		await _command_checks()
		await _mark_checks()
		await _message_checks()
		await _follow_checks()
		await _killer_checks()
		await _owner_dead_checks()
		await _owner_left_checks()
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


# --- Pair plumbing -------------------------------------------------------------------------------

func _roster() -> Array[NetPeerInfo]:
	var out: Array[NetPeerInfo] = []
	for i: int in 2:
		var info: NetPeerInfo = NetPeerInfo.new()
		info.slot = i
		info.display_name = "Anfitriao" if i == HOST_SLOT else "Cliente"
		info.is_host = i == HOST_SLOT
		info.weapon_id = Ids.W_CARBINE_22
		info.dog_id = Ids.D_FOXHOUND if i == HOST_SLOT else Ids.D_CARAMELO
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


func _replica() -> HuntReplica:
	return _client.debug_replica()


func _dog(slot: int) -> Dog:
	return _host.get_dog_of(slot)


func _puppet(slot: int) -> DogPuppet:
	return _replica().get_dog_puppet(slot) if _client != null else null


## Puts the dog `dist` m from a live boar, on the side of the map center (always inside the map).
func _place_dog_from_boar(dog: Dog, boar: Vector3, dist: float) -> void:
	var center: Vector2 = _host.get_map_rect().get_center()
	var away: Vector2 = (center - Vector2(boar.x, boar.z)).normalized()
	var xz: Vector2 = Vector2(boar.x, boar.z) + away * dist
	dog.position = Vector3(xz.x, _host.get_height(xz.x, xz.y), xz.y)


## Back beside the owner so a recall finishes at once.
func _bring_back(dog: Dog) -> void:
	var owner_hunter: PlayerBase = _host.get_hunter(dog.owner_slot)
	dog.position = owner_hunter.global_position + Vector3(1.5, 0.0, 0.0)


func _clear_bus() -> void:
	_states.clear()
	_healths.clear()
	_commands.clear()
	_marks = 0
	_texts.clear()


# --- Cases ---------------------------------------------------------------------------------------

func _setup_checks() -> void:
	print("--- setup")
	var dogs: Array[Dog] = _host.get_dogs()
	_check("host_simulates_two_dogs", dogs.size() == 2 and _dog(HOST_SLOT) != null and _dog(CLIENT_SLOT) != null,
		"dogs=%d" % dogs.size())
	_check("dog_owner_and_breed", _dog(HOST_SLOT).owner_slot == HOST_SLOT and _dog(HOST_SLOT).breed_id == Ids.D_FOXHOUND
		and _dog(CLIENT_SLOT).owner_slot == CLIENT_SLOT and _dog(CLIENT_SLOT).breed_id == Ids.D_CARAMELO)
	_check("client_has_no_simulated_dog", _client.get_dogs().is_empty() and _client.get_dog_of(CLIENT_SLOT) == null)
	_check("host_local_dog_is_its_own", _host.has_dog() and _dog(HOST_SLOT).is_local_owner()
		and not _dog(CLIENT_SLOT).is_local_owner() and _host.get_dog_position() == _dog(HOST_SLOT).global_position)
	var got: bool = await _wait_until(func() -> bool: return _puppet(HOST_SLOT) != null and _puppet(CLIENT_SLOT) != null, PUPPET_WAIT_S)
	_check("client_gets_two_puppets", got)
	_check("client_has_dog_is_its_own", _client.has_dog() and _puppet(CLIENT_SLOT).is_local_owner()
		and not _puppet(HOST_SLOT).is_local_owner() and _puppet(CLIENT_SLOT).breed_id == Ids.D_CARAMELO
		and _puppet(HOST_SLOT).breed_id == Ids.D_FOXHOUND)
	_check("client_dog_getters", _client.get_dog_state() == Ids.DS_FOLLOW and _client.get_dog_health_pct() > 99.0
		and _client.get_dog_position() == _puppet(CLIENT_SLOT).global_position)
	await _wait_until(func() -> bool: return _host.get_alive_boar_ids().size() >= 3 and _client.get_alive_boar_ids().size() >= 3, BOAR_WAIT_S)


func _signal_checks() -> void:
	print("--- signals")
	# Two machines on one bus: each local dog announced itself once; the host's copy of the client's dog is silent.
	_check("hud_state_once_per_owner", _states.count(Ids.DS_FOLLOW) == 2 and _states.size() == 2, str(_states))
	_check("hud_health_once_per_owner", _healths.size() == 2 and is_equal_approx(_healths[0], 100.0), str(_healths))


func _command_checks() -> void:
	print("--- command")
	_clear_bus()
	var host_dog: Dog = _dog(HOST_SLOT)
	var client_dog: Dog = _dog(CLIENT_SLOT)
	var ids: PackedInt32Array = _host.get_alive_boar_ids()
	if ids.is_empty():
		_check("command_needs_boar", false, "no live boar")
		return
	_place_dog_from_boar(client_dog, _host.get_boar_position(ids[0]), FAR_FROM_BOAR_M)   # a long run: it stays in seek
	_replica().request_dog_command()   # what GameEvents.dog_command_requested does on the client
	_check("client_claims_dog_command", _replica().dog_commands_claimed == 1)
	await _wait_until(func() -> bool: return client_dog.state != Ids.DS_FOLLOW, 1.0)
	_check("only_client_dog_obeys", client_dog.state != Ids.DS_FOLLOW and host_dog.state == Ids.DS_FOLLOW,
		"client dog=%s host dog=%s" % [client_dog.state, host_dog.state])
	_check("host_applied_one_command", _host.debug_host_sync().dog_commands_applied == 1)
	await _wait_s(0.5)
	_check("command_executed_once_on_client_hud", _commands == [Ids.CMD_ATTACK], str(_commands))
	var seen: bool = await _wait_until(func() -> bool: return _puppet(CLIENT_SLOT).state != Ids.DS_FOLLOW, 1.5)
	_check("client_puppet_follows_state", seen, str(_puppet(CLIENT_SLOT).state))
	_check("host_puppet_untouched", _puppet(HOST_SLOT).state == Ids.DS_FOLLOW)
	# Back to follow for the next case: "Volta!".
	_replica().request_dog_command()
	await _wait_until(func() -> bool: return client_dog.state == Ids.DS_RETURN or client_dog.state == Ids.DS_FOLLOW, 1.0)
	await _wait_s(0.4)   # the EV_DOG_CMD of the recall rides the next snapshot tick
	_check("recall_command", _commands.size() == 2 and _commands[1] == Ids.CMD_RECALL, str(_commands))
	_bring_back(client_dog)
	await _wait_until(func() -> bool: return client_dog.state == Ids.DS_FOLLOW, 5.0)


func _mark_checks() -> void:
	print("--- mark")
	var ids: PackedInt32Array = _host.get_alive_boar_ids()
	if ids.is_empty():
		_check("mark_needs_boar", false, "no live boar")
		return
	var boar: Vector3 = _host.get_boar_position(ids[0])
	var client_dog: Dog = _dog(CLIENT_SLOT)
	client_dog.position = Vector3(boar.x + POINT_DISTANCE_M, boar.y, boar.z)
	_clear_bus()
	_replica().request_dog_command()
	var pointing: bool = await _wait_until(func() -> bool: return client_dog.state == Ids.DS_POINT, 1.5)
	_check("client_dog_points", pointing, str(client_dog.state))
	await _wait_s(0.7)
	_check("mark_on_host", not _host.get_marked_boar_positions().is_empty())
	_check("mark_on_client", not _client.get_marked_boar_positions().is_empty(),
		"client puppets=%d" % _client.get_alive_boar_ids().size())
	_check("dog_marked_boar_on_both", _marks >= 2, "marks=%d" % _marks)
	_check("client_hud_sees_point", _states.has(Ids.DS_POINT) and _puppet(CLIENT_SLOT).state == Ids.DS_POINT
		and _client.get_dog_state() == Ids.DS_POINT, "%s / %s" % [str(_states), _client.get_dog_state()])
	_replica().request_dog_command()   # recall
	await _wait_s(0.3)
	_bring_back(client_dog)
	await _wait_until(func() -> bool: return client_dog.state == Ids.DS_FOLLOW, 5.0)


func _message_checks() -> void:
	print("--- message")
	_clear_bus()
	_dog(CLIENT_SLOT).take_damage(HURT_DAMAGE)   # health under retreat_health_frac: "Seu cão se feriu e recuou!"
	await _wait_s(0.5)
	var retreat: int = _texts.count(Dog.MSG_RETREAT)
	_check("retreat_message_only_to_owner", retreat == 1, "count=%d %s" % [retreat, str(_texts)])
	var shown: bool = await _wait_until(func() -> bool: return _puppet(CLIENT_SLOT).state == Ids.DS_RETREAT, 1.5)
	_check("puppet_retreats", shown)
	_check("client_health_on_hud", _healths.size() > 0 and _client.get_dog_health_pct() < 50.0,
		"pct=%.1f healths=%d" % [_client.get_dog_health_pct(), _healths.size()])
	_clear_bus()
	_dog(HOST_SLOT).take_damage(HURT_DAMAGE)
	await _wait_s(0.5)
	_check("host_dog_message_only_on_host", _texts.count(Dog.MSG_RETREAT) == 1, str(_texts))
	_check("puppet_of_host_dog_retreats", await _wait_until(func() -> bool: return _puppet(HOST_SLOT).state == Ids.DS_RETREAT, 1.5))
	await _wait_until(func() -> bool: return _dog(CLIENT_SLOT).state == Ids.DS_FOLLOW and _dog(HOST_SLOT).state == Ids.DS_FOLLOW, 40.0)
	_check("dogs_recover", _dog(CLIENT_SLOT).state == Ids.DS_FOLLOW and _dog(HOST_SLOT).state == Ids.DS_FOLLOW)


func _follow_checks() -> void:
	print("--- follow")
	var cp: PlayerBase = _client.get_player()
	_pump_real = true   # RemoteHunter interpolates on the wall clock (see net_flow_test death case)
	cp.bot_set_enabled(true)
	var to: Vector3 = cp.global_position + WALK_OFFSET
	cp.bot_teleport(Vector3(to.x, _client.get_height(to.x, to.z) + 0.05, to.z))
	var remote: PlayerBase = _host.get_hunter(CLIENT_SLOT)
	var dog: Dog = _dog(CLIENT_SLOT)
	var followed: bool = await _until_real(func() -> bool:
		return (dog.global_position.distance_to(remote.global_position) <= FOLLOW_MAX_M
			and remote.global_position.distance_to(cp.global_position) <= FOLLOW_MAX_M), REAL_WAIT_MS * 2)
	_check("client_dog_follows_client", followed, "dog-to-client %.1f m" % dog.global_position.distance_to(cp.global_position))
	_check("host_dog_stays_with_host", _dog(HOST_SLOT).global_position.distance_to(_host.get_player().global_position) <= FOLLOW_MAX_M)
	_pump_real = false
	# Settled: the dog is still, the replica caught up with the last snapshot.
	var still: bool = false
	for i: int in STILL_TRIES:
		var before: Vector2 = dog.get_xz()
		await _wait_s(0.5)
		if dog.get_xz().distance_to(before) <= STILL_EPS_M:
			still = true
			break
	await _wait_s(1.0)
	var p: DogPuppet = _puppet(CLIENT_SLOT)
	var err: float = p.get_xz().distance_to(dog.get_xz())
	_check("puppet_settles_within_1cm", still and err <= SETTLE_TOL_M, "still=%s err=%.4f m" % [str(still), err])
	var near_cp: bool = p.global_position.distance_to(cp.global_position) <= FOLLOW_MAX_M + 2.0
	_check("client_puppet_near_client", near_cp, "%.1f m" % p.global_position.distance_to(cp.global_position))
	var yaw_err: float = absf(angle_difference(p.get_yaw(), dog.get_yaw()))
	_check("puppet_yaw_matches", yaw_err <= TAU / 256.0 + 0.01, "err=%.3f rad" % yaw_err)


func _killer_checks() -> void:
	print("--- killer")
	var ids: PackedInt32Array = _host.get_alive_boar_ids()
	if ids.is_empty():
		_check("killer_needs_boar", false, "no live boar")
		return
	var b: Boar = _host.spawner.get_boar(ids[0])
	var dog: Dog = _dog(CLIENT_SLOT)
	b.start_held(dog, 5.0, 0.0)
	b.apply_dog_damage(KILL_DAMAGE)
	_check("dog_kill_credits_owner", b.killer_slot == CLIENT_SLOT and not b.is_alive(), "killer=%d" % b.killer_slot)
	var got: bool = await _wait_until(func() -> bool: return _client.debug_partial_result().kills.size() == 1, 1.0)
	_check("dog_kill_counts_for_client", got and _host.debug_partial_result().kills.is_empty())


func _owner_dead_checks() -> void:
	print("--- owner_dead")
	var dog: Dog = _dog(HOST_SLOT)
	dog.position += FAR_OFFSET
	var hp: PlayerBase = _host.get_player()
	hp.apply_damage(KILL_DAMAGE, hp.global_position + Vector3.FORWARD)
	await get_tree().process_frame
	var at: Vector2 = dog.get_xz()
	var far: float = at.distance_to(Vector2(hp.global_position.x, hp.global_position.z))
	await _wait_s(1.5)
	_check("dead_owner_dog_stays", not hp.is_alive() and dog.get_xz().distance_to(at) <= STILL_EPS_M and far > FOLLOW_MAX_M,
		"moved %.3f m, %.1f m from the owner" % [dog.get_xz().distance_to(at), far])
	dog.command()
	_check("dead_owner_command_ignored", dog.state == Ids.DS_FOLLOW)
	_check("client_dog_goes_on", _dog(CLIENT_SLOT) != null and not _host.is_hunt_over())


func _owner_left_checks() -> void:
	print("--- owner_left")
	var dog: Dog = _dog(CLIENT_SLOT)
	_host.net_peer_left(CLIENT_SLOT)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("host_removes_leaver_dog", _host.get_dog_of(CLIENT_SLOT) == null and _host.get_dogs().size() == 1
		and (not is_instance_valid(dog) or dog.is_queued_for_deletion()))
	var gone: bool = await _wait_until(func() -> bool: return _puppet(CLIENT_SLOT) == null, PUPPET_WAIT_S)
	_check("client_drops_puppet_of_missing_dog", gone and _puppet(HOST_SLOT) != null)
	_pump_on = false
	_client.net_peer_left(HOST_SLOT)   # a client hears that another hunter left: its dog goes too
	await get_tree().process_frame
	_check("client_removes_puppet_on_peer_left", _puppet(HOST_SLOT) == null)
