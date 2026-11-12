extends Node
## Package B self-test: runs hunt.tscn headless and checks the rules of the hunt.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/hunt_selftest.tscn -- \
##            --fallback-player [--only=flow,ends,charge,bait,dog,perf]
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 280.0
const FAR_CORNER: Vector3 = Vector3(-118.0, 0.0, -118.0)

var _passed: int = 0
var _failed: int = 0
var _hunt: HuntController = null
var _ended: Array[HuntResult] = []
var _started: int = 0
var _counts: Array[Vector2i] = []
var _crop_values: PackedFloat32Array = PackedFloat32Array()
var _states: Dictionary = {}          # boar_id -> Array of [state, time]
var _player_damage_events: int = 0
var _dog_states: Array[StringName] = []
var _dog_commands: Array[StringName] = []
var _dog_marks: int = 0
var _bait_events: int = 0
var _attack_flags: Array[bool] = []
var _watchdog_start_ms: int = 0
var _hits: Array = []
var _kills: Array[KillInfo] = []


func _ready() -> void:
	_watchdog_start_ms = Time.get_ticks_msec()
	GameEvents.hunt_started.connect(func(_r: HuntRequest) -> void: _started += 1)
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	GameEvents.boar_counts_changed.connect(func(k: int, t: int) -> void: _counts.append(Vector2i(k, t)))
	GameEvents.crop_health_changed.connect(func(p: float) -> void: _crop_values.append(p))
	GameEvents.boar_state_changed.connect(_on_state)
	GameEvents.player_damaged.connect(func(_a: float, _s: Vector3, _h: float) -> void: _player_damage_events += 1)
	GameEvents.dog_state_changed.connect(func(s: StringName) -> void: _dog_states.append(s))
	GameEvents.dog_command_executed.connect(func(c: StringName) -> void: _dog_commands.append(c))
	GameEvents.dog_marked_boar.connect(func(_p: Vector3, _d: float) -> void: _dog_marks += 1)
	GameEvents.bait_placed.connect(func(_p: Vector3, _d: float) -> void: _bait_events += 1)
	GameEvents.crop_under_attack.connect(func(a: bool) -> void: _attack_flags.append(a))
	GameEvents.boar_hit.connect(func(id: int, zone: StringName, dmg: float, _p: Vector3, shot: int) -> void: _hits.append([id, zone, dmg, shot]))
	GameEvents.boar_killed.connect(func(k: KillInfo) -> void: _kills.append(k))
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	var all: Dictionary = {
		"flow": _test_flow, "ends": _test_ends, "charge": _test_charge, "bait": _test_bait,
		"shoot": _test_shoot, "dog": _test_dog, "perf": _test_perf, "closeup": _test_closeup,
		"obstacle": _test_obstacle, "misc": _test_misc,
	}
	for key: String in all.keys():
		if only.is_empty() or only.has(key):
			print("--- %s" % key)
			await (all[key] as Callable).call()
			await _close()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	# Wall clock: timers follow the simulated time under --fixed-fps.
	if float(Time.get_ticks_msec() - _watchdog_start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: self-test timed out")
		get_tree().quit(1)


func _on_state(id: int, state: StringName) -> void:
	if not _states.has(id):
		_states[id] = []
	(_states[id] as Array).append([state, _hunt.get_elapsed_s() if _hunt != null else 0.0])


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _open(contract_index: int, dog_id: StringName = &"", rng_seed: int = 12345) -> void:
	_ended.clear()
	_counts.clear()
	_crop_values.clear()
	_states.clear()
	_dog_states.clear()
	_dog_commands.clear()
	_attack_flags.clear()
	_hits.clear()
	_kills.clear()
	_started = 0
	_player_damage_events = 0
	_dog_marks = 0
	_bait_events = 0
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", contract_index)
	req.rng_seed = rng_seed
	req.dog_id = dog_id
	req.quality = Ids.Q_MEDIUM
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			req.quality = StringName(arg.trim_prefix("--quality="))
	Router.set_pending_request(req)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	add_child(_hunt)
	var t0: int = Time.get_ticks_msec()
	while not _hunt.is_world_ready():
		await get_tree().process_frame
	print("load_ms=%d" % (Time.get_ticks_msec() - t0))


func _close() -> void:
	if _hunt != null:
		_hunt.queue_free()
		_hunt = null
	Router.set_pending_request(null)
	await get_tree().process_frame
	await get_tree().process_frame


## Waits (in hunt time) until cond() is true. Returns false on timeout.
func _wait(cond: Callable, max_s: float) -> bool:
	var limit: float = _hunt.get_elapsed_s() + max_s
	while _hunt.get_elapsed_s() < limit:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _sleep(seconds: float) -> void:
	var limit: float = _hunt.get_elapsed_s() + seconds
	while _hunt.get_elapsed_s() < limit:
		await get_tree().process_frame


func _park_player() -> void:
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	p.bot_teleport(Vector3(FAR_CORNER.x, _hunt.get_height(FAR_CORNER.x, FAR_CORNER.z) + 0.1, FAR_CORNER.z))


func _place_player(x: float, z: float) -> void:
	_hunt.get_player().bot_teleport(Vector3(x, _hunt.get_height(x, z) + 0.05, z))


func _boars_in_state(state: StringName) -> int:
	var n: int = 0
	for id: int in _hunt.get_alive_boar_ids():
		if _hunt.spawner.get_boar(id).state == state:
			n += 1
	return n


func _had_state(id: int, state: StringName) -> bool:
	for e: Array in _states.get(id, []):
		if e[0] == state:
			return true
	return false


func _max_ground_error() -> float:
	var worst: float = 0.0
	for id: int in _hunt.get_alive_boar_ids():
		var p: Vector3 = _hunt.get_boar_position(id)
		worst = maxf(worst, absf(p.y - _hunt.get_height(p.x, p.z)))
	return worst


func _min_obstacle_clearance() -> float:
	# Negative = a boar is inside a footprint obstacle.
	var worst: float = INF
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if not _hunt.obstacles.is_free(b.get_xz(), 0.0):
			worst = minf(worst, -1.0)
	return worst


# --- Scenarios -----------------------------------------------------------------------------------

func _test_flow() -> void:
	await _open(0)
	_check("hunt_started_once", _started == 1, "started=%d" % _started)
	_check("counts_initial_0_5", _counts.size() >= 1 and _counts[0] == Vector2i(0, 5), str(_counts))
	_check("player_is_playerbase", _hunt.get_player() != null, str(_hunt.get_player()))
	_check("crop_rects_2", _hunt.get_crop_rects().size() == 2, str(_hunt.get_crop_rects()))
	_park_player()
	var ground_err: float = 0.0
	var inside_obstacle: bool = false
	var ok: bool = await _wait(func() -> bool: return _hunt.get_alive_boar_ids().size() == 5, 40.0)
	_check("all_5_spawned", ok, "alive=%d t=%.1f" % [_hunt.get_alive_boar_ids().size(), _hunt.get_elapsed_s()])
	# Walk to the crop and eat.
	var t_end: float = _hunt.get_elapsed_s() + 150.0
	while _hunt.get_elapsed_s() < t_end and _boars_in_state(Ids.BS_EAT) < 4:
		ground_err = maxf(ground_err, _max_ground_error())
		inside_obstacle = inside_obstacle or _min_obstacle_clearance() < 0.0
		await get_tree().process_frame
	_check("boars_reach_crop_and_eat", _boars_in_state(Ids.BS_EAT) >= 4, "eating=%d t=%.1f" % [_boars_in_state(Ids.BS_EAT), _hunt.get_elapsed_s()])
	var h0: float = _hunt.get_crop_health_pct()
	await _sleep(15.0)
	var h1: float = _hunt.get_crop_health_pct()
	_check("crop_drains", h1 < h0, "%.3f -> %.3f" % [h0, h1])
	var decreasing: bool = _crop_values.size() >= 2
	for i: int in range(1, _crop_values.size()):
		if _crop_values[i] > _crop_values[i - 1]:
			decreasing = false
	_check("crop_health_changed_decreasing", decreasing, str(_crop_values))
	_check("crop_under_attack_true", _attack_flags.has(true), str(_attack_flags))
	_check("boars_on_ground", ground_err < 0.05, "max_err=%.4f" % ground_err)
	_check("boars_outside_obstacles", not inside_obstacle)
	# A gunshot nearby: the herd flees, rests and comes back.
	var eater: int = -1
	for id: int in _hunt.get_alive_boar_ids():
		if _hunt.spawner.get_boar(id).state == Ids.BS_EAT:
			eater = id
			break
	var bp: Vector3 = _hunt.get_boar_position(eater)
	_place_player(bp.x, bp.z - 45.0)
	await get_tree().physics_frame
	var player: PlayerBase = _hunt.get_player()
	player.bot_look_at(Vector3(bp.x, bp.y + 30.0, bp.z))   # shoot over their heads
	var fired: bool = player.bot_fire()
	await get_tree().process_frame
	_park_player()
	_check("shot_fired", fired)
	_check("shot_makes_herd_flee", _boars_in_state(Ids.BS_FLEE) >= 3, "fleeing=%d" % _boars_in_state(Ids.BS_FLEE))
	var t_flee: float = _hunt.get_elapsed_s()
	ok = await _wait(func() -> bool: return _hunt.spawner.get_boar(eater).state == Ids.BS_TO_CROP, 120.0)
	_check("boar_returns_after_flee", ok, "state=%s after %.1f s" % [_hunt.spawner.get_boar(eater).state, _hunt.get_elapsed_s() - t_flee])
	_check("result_null_before_end", _hunt.get_result() == null and not _hunt.is_hunt_over())
	# Two boars killed in the same frame, then the rest: one victory.
	var ids: PackedInt32Array = _hunt.get_alive_boar_ids().duplicate()
	_hunt.debug_kill_boar(ids[0])
	_hunt.debug_kill_boar(ids[1])
	_hunt.debug_kill_boar(ids[1])
	_check("double_kill_counts", _hunt.get_boars_killed() == 2 and _counts[-1] == Vector2i(2, 5), str(_counts))
	for i: int in range(2, ids.size()):
		_hunt.debug_kill_boar(ids[i])
	await get_tree().process_frame
	await get_tree().process_frame
	await _sleep(1.0)
	_check("victory_once", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.VICTORY, "ended=%d" % _ended.size())
	if _ended.size() >= 1:
		var r: HuntResult = _ended[0]
		_check("result_coherent", r.kills.size() == 5 and r.boars_total == 5 and r.total_money == r.money_from_kills + r.contract_bonus
			and r.money_from_kills > 0 and r.contract_bonus > 0 and r.shots_fired == 1 and _hunt.get_result() == r,
			JSON.stringify(r.to_dict()).left(400))
	_check("stays_in_scene", get_tree().current_scene == self)


func _test_ends() -> void:
	await _open(0)
	_park_player()
	await _sleep(1.0)
	_hunt.debug_set_crop_health(0.0)
	await _sleep(0.5)
	_check("defeat_crop", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.DEFEAT_CROP and _ended[0].contract_bonus == 0,
		"ended=%d" % _ended.size())
	_check("crop_zero_signal", _crop_values.size() > 0 and _crop_values[-1] == 0.0, str(_crop_values))
	await _close()

	await _open(0)
	await _sleep(1.0)
	_hunt.get_player().apply_damage(9999.0, Vector3.ZERO)
	_hunt.debug_set_crop_health(0.0)   # death has priority over the crop
	await _sleep(0.5)
	_check("defeat_death", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.DEFEAT_DEATH, "ended=%d" % _ended.size())
	await _close()

	await _open(0)
	await _sleep(1.0)
	GameEvents.hunt_abandon_requested.emit()
	GameEvents.hunt_abandon_requested.emit()
	await _sleep(0.5)
	_check("abandoned", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.ABANDONED, "ended=%d" % _ended.size())
	await _close()

	await _open(0)
	await _sleep(1.0)
	_hunt.debug_force_end(HuntResult.Outcome.VICTORY)
	_hunt.debug_force_end(HuntResult.Outcome.DEFEAT_CROP)
	await _sleep(0.5)
	_check("force_end_once", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.VICTORY and _ended[0].contract_bonus > 0,
		"ended=%d" % _ended.size())


func _find_type(type_id: StringName) -> int:
	for id: int in _hunt.get_alive_boar_ids():
		if _hunt.get_boar_type(id) == type_id:
			return id
	return -1


func _state_time(id: int, state: StringName, after: float) -> float:
	for e: Array in _states.get(id, []):
		if e[0] == state and float(e[1]) >= after:
			return float(e[1])
	return -1.0


func _test_charge() -> void:
	await _open(1)   # contract 2: lone male at 40 s
	_park_player()
	var ok: bool = await _wait(func() -> bool: return _find_type(Ids.BOAR) >= 0, 60.0)
	_check("male_spawned", ok)
	if not ok:
		return
	var id: int = _find_type(Ids.BOAR)
	var boar: Boar = _hunt.spawner.get_boar(id)
	await _sleep(1.0)
	# Stand 9 m in front of it (inside aggro_radius 12 m) and stay.
	var fwd: Vector3 = -boar.global_transform.basis.z
	var t0: float = _hunt.get_elapsed_s()
	_place_player(boar.position.x + fwd.x * 9.0, boar.position.z + fwd.z * 9.0)
	_player_damage_events = 0
	ok = await _wait(func() -> bool: return _state_time(id, Ids.BS_RECOVER, t0) >= 0.0, 20.0)
	var t_alert: float = _state_time(id, Ids.BS_ALERT, t0)
	var t_scrape: float = _state_time(id, Ids.BS_SCRAPE, t0)
	var t_charge: float = _state_time(id, Ids.BS_CHARGE, t0)
	_check("alert_before_scrape", t_alert >= 0.0 and t_scrape > t_alert, "alert=%.2f scrape=%.2f" % [t_alert - t0, t_scrape - t0])
	_check("scrape_at_least_0_8s", t_scrape >= 0.0 and t_charge - t_scrape >= 0.8 - 0.001, "scrape lasted %.3f s" % (t_charge - t_scrape))
	_check("charge_hits_once", ok and _player_damage_events == 1, "damage_events=%d health=%.0f" % [_player_damage_events, _hunt.get_player().get_health()])
	# Second charge: step aside as soon as it starts running.
	var t1: float = _hunt.get_elapsed_s()
	ok = await _wait(func() -> bool: return _state_time(id, Ids.BS_CHARGE, t1) >= 0.0, 20.0)
	_check("charges_again", ok, str(_states.get(id, [])).right(160))
	if ok:
		_player_damage_events = 0
		var dir: Vector3 = -boar.global_transform.basis.z
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		var pp: Vector3 = _hunt.get_player().global_position
		var start: Vector3 = boar.position
		_place_player(pp.x + side.x * 4.0, pp.z + side.z * 4.0)
		var t2: float = _hunt.get_elapsed_s()
		ok = await _wait(func() -> bool: return _state_time(id, Ids.BS_RECOVER, t2) >= 0.0, 10.0)
		var run: float = Vector2(boar.position.x - start.x, boar.position.z - start.z).length()
		var dev: float = absf(Vector2(boar.position.x - start.x, boar.position.z - start.z).normalized().dot(Vector2(side.x, side.z)))
		_check("dodge_no_damage", ok and _player_damage_events == 0, "damage_events=%d" % _player_damage_events)
		_check("charge_runs_straight_past", run > 5.0 and dev < 0.05, "run=%.1f m lateral_frac=%.3f" % [run, dev])
	_park_player()
	ok = await _wait(func() -> bool: return boar.state == Ids.BS_FLEE or boar.state == Ids.BS_TO_CROP or boar.state == Ids.BS_WANDER, 30.0)
	_check("disengages_when_hunter_gone", ok, "state=%s" % boar.state)


func _test_bait() -> void:
	await _open(0)
	_park_player()
	var ok: bool = await _wait(func() -> bool: return _boars_in_state(Ids.BS_EAT) >= 5, 220.0)
	_check("five_eating_crop", ok, "eating=%d" % _boars_in_state(Ids.BS_EAT))
	var eater: int = _hunt.get_alive_boar_ids()[0]
	var bp: Vector3 = _hunt.get_boar_position(eater)
	var bait_pos: Vector3 = Vector3(bp.x + 25.0, 0.0, bp.z + 30.0)
	GameEvents.item_used.emit(Ids.I_CORN_BAIT, bait_pos)
	_check("bait_placed_signal", _bait_events == 1)
	await _sleep(1.0)
	var going: int = _boars_in_state(Ids.BS_TO_BAIT)
	_check("bait_attracts_up_to_4", going >= 1 and going <= 4, "to_bait=%d" % going)
	ok = await _wait(func() -> bool: return _boars_in_state(Ids.BS_TO_BAIT) == 0 and _boars_in_state(Ids.BS_EAT) >= going, 30.0)
	var at_bait: int = 0
	for id: int in _hunt.get_alive_boar_ids():
		var p: Vector3 = _hunt.get_boar_position(id)
		if Vector2(p.x - bait_pos.x, p.z - bait_pos.z).length() < 3.0:
			at_bait += 1
	_check("boars_eat_at_bait", ok and at_bait == going, "at_bait=%d" % at_bait)
	# Boars at the bait must not be registered as crop eaters; the others keep draining.
	var baited_draining: int = 0
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		var p: Vector3 = b.global_position
		var near: bool = Vector2(p.x - bait_pos.x, p.z - bait_pos.z).length() < 3.0
		print("trace boar %d %s state=%s near_bait=%s crop_eater=%s" % [id, b.type_id, b.state, near, _hunt.crop.has_eater(id)])
		if near and _hunt.crop.has_eater(id):
			baited_draining += 1
	_check("bait_eaters_do_not_drain", baited_draining == 0 and _hunt.crop.get_eater_count() <= 5 - going,
		"crop_eaters=%d" % _hunt.crop.get_eater_count())
	var bait_node: Bait = _hunt.get_node("Baits").get_child(0) as Bait
	_check("bait_reserved_max_4", bait_node.get_reserved_count() == going and going <= bait_node.max_boars, "reserved=%d" % bait_node.get_reserved_count())
	var t_bait: float = _hunt.get_elapsed_s()
	ok = await _wait(func() -> bool: return _hunt.get_node("Baits").get_child_count() == 0, 60.0)
	_check("bait_expires_after_45s", ok and absf(_hunt.get_elapsed_s() - t_bait - 45.0) < 20.0, "after %.1f s" % (_hunt.get_elapsed_s() - t_bait))
	await _sleep(0.5)
	_check("boars_return_to_crop", _boars_in_state(Ids.BS_TO_CROP) >= going, "to_crop=%d" % _boars_in_state(Ids.BS_TO_CROP))
	var used: int = int(_hunt._result.consumables_used.get(Ids.I_CORN_BAIT, 0))
	_check("consumable_counted", used == 1, "used=%d" % used)


func _test_dog() -> void:
	if not ResourceLoader.exists(ScenePaths.DOG):
		_check("dog_scene_exists", false, "missing %s" % ScenePaths.DOG)
		return
	var breeds: Array[StringName] = [Ids.D_CARAMELO, Ids.D_FOXHOUND, Ids.D_DOGO]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--breed="):
			breeds = [StringName(arg.trim_prefix("--breed="))]
	for breed: StringName in breeds:
		await _open(1, breed)
		var p: PlayerBase = _hunt.get_player()
		p.bot_set_enabled(true)
		_check("%s_has_dog" % breed, _hunt.has_dog() and _hunt.get_dog_state() == Ids.DS_FOLLOW, str(_hunt.get_dog_state()))
		_place_player(0.0, 60.0)
		var ok: bool = await _wait(func() -> bool:
			var d: Vector3 = _hunt.get_dog_position()
			return Vector2(d.x - p.global_position.x, d.z - p.global_position.z).length() < 6.0, 30.0)
		_check("%s_follows" % breed, ok)
		ok = await _wait(func() -> bool: return _hunt.get_alive_boar_ids().size() >= 3, 30.0)
		print("trace alive>=3 t=%.1f dog=%s" % [_hunt.get_elapsed_s(), _hunt.get_dog_position()])
		await _sleep(20.0)
		print("trace slept t=%.1f dog=%s player=%s" % [_hunt.get_elapsed_s(), _hunt.get_dog_position(), p.global_position])
		_dog_commands.clear()
		_dog_states.clear()
		GameEvents.dog_command_requested.emit()
		_check("%s_attack_command" % breed, _dog_commands == [Ids.CMD_ATTACK] and _hunt.get_dog_state() == Ids.DS_SEEK, "%s %s" % [_dog_commands, _hunt.get_dog_state()])
		var ability_state: StringName = {Ids.D_CARAMELO: Ids.DS_POINT, Ids.D_FOXHOUND: Ids.DS_BAY, Ids.D_DOGO: Ids.DS_HOLD}[breed]
		ok = await _wait(func() -> bool: return _dog_states.has(ability_state), 60.0)
		_check("%s_reaches_%s" % [breed, ability_state], ok and _dog_marks > 0, "states=%s marks=%d" % [_dog_states, _dog_marks])
		_check("%s_marked_positions" % breed, _hunt.get_marked_boar_positions().size() >= 1)
		await _sleep(1.0)
		GameEvents.dog_command_requested.emit()
		_check("%s_recall_command" % breed, _dog_commands.size() >= 2 and _dog_commands[-1] == Ids.CMD_RECALL and _hunt.get_dog_state() == Ids.DS_RETURN,
			"%s %s" % [_dog_commands, _hunt.get_dog_state()])
		ok = await _wait(func() -> bool: return _hunt.get_dog_state() == Ids.DS_FOLLOW, 60.0)
		_check("%s_returns_to_follow" % breed, ok, str(_hunt.get_dog_state()))
		# Low health: retreats, never dies, refuses to attack until healed.
		var dog: Node3D = _hunt.get_node("Dog") as Node3D
		dog.call(&"take_damage", 99999.0)
		_check("%s_never_dies" % breed, _hunt.get_dog_health_pct() > 0.0 and _hunt.get_dog_state() == Ids.DS_RETREAT,
			"pct=%.2f state=%s" % [_hunt.get_dog_health_pct(), _hunt.get_dog_state()])
		_dog_commands.clear()
		GameEvents.dog_command_requested.emit()
		_check("%s_retreat_ignores_attack" % breed, not _dog_commands.has(Ids.CMD_ATTACK) and _hunt.get_dog_state() == Ids.DS_RETREAT, str(_dog_commands))
		ok = await _wait(func() -> bool: return _hunt.get_dog_state() == Ids.DS_FOLLOW, 60.0)
		_check("%s_recovers" % breed, ok and _hunt.get_dog_health_pct() >= 69.0, "pct=%.1f" % _hunt.get_dog_health_pct())
		await _close()


func _test_perf() -> void:
	await _open(4)
	_park_player()
	var ok: bool = await _wait(func() -> bool: return _hunt.get_alive_boar_ids().size() == 17, 80.0)
	_check("contract5_17_boars", ok, "alive=%d" % _hunt.get_alive_boar_ids().size())
	if DisplayServer.get_name() == "headless":
		var frames: int = 600
		var t0: int = Time.get_ticks_usec()
		for i: int in frames:
			await get_tree().process_frame
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
		print("headless_frame_ms=%.3f (17 boars, no rendering)" % ms)
		_check("headless_frame_budget", ms < 4.0, "%.3f ms/frame" % ms)
		return
	# With a window: real frame rate and render counters from typical views.
	var shots_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	var player: PlayerBase = _hunt.get_player()
	var herd_pos: Vector3 = _hunt.get_boar_position(_hunt.get_alive_boar_ids()[0])
	var views: Array = [
		["spawn_south", Vector3(10.0, 0.0, -50.0), Vector3(10.0, 0.0, 20.0)],
		["crop_center", Vector3(10.0, 0.0, 20.0), Vector3(-40.0, 0.0, 60.0)],
		["herd_20m", Vector3(herd_pos.x, 0.0, herd_pos.z - 20.0), herd_pos],
		["farm", Vector3(10.0, 0.0, -45.0), Vector3(15.0, 3.0, -85.0)],
		["pond", Vector3(-45.0, 0.0, -35.0), Vector3(-70.0, 0.0, -55.0)],
	]
	var worst_fps: float = INF
	for v: Array in views:
		var at: Vector3 = v[1] as Vector3
		if v[0] == "herd_20m":
			herd_pos = _hunt.get_boar_position(_hunt.get_alive_boar_ids()[0])
			at = Vector3(herd_pos.x, 0.0, herd_pos.z - 20.0)
			v[2] = herd_pos
		_place_player(at.x, at.z)
		var look: Vector3 = v[2] as Vector3
		if look.y == 0.0:
			look.y = _hunt.get_height(look.x, look.z) + 1.0
		for i: int in 5:
			await get_tree().physics_frame
		player.bot_look_at(look)
		for i: int in 20:
			await get_tree().process_frame
		var frames2: int = 0
		var t1: int = Time.get_ticks_usec()
		while Time.get_ticks_usec() - t1 < 3000000:
			await get_tree().process_frame
			frames2 += 1
		var fps: float = float(frames2) / (float(Time.get_ticks_usec() - t1) / 1000000.0)
		worst_fps = minf(worst_fps, fps)
		print("view=%s fps=%.1f draw_calls=%d primitives=%d objects=%d" % [v[0], fps,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
		if shots_dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots_dir.path_join("%s.png" % v[0]))
	_check("fps_at_least_60", worst_fps >= 60.0, "worst=%.1f" % worst_fps)


## Real bullets (FallbackPlayer or Player hitscan) against the hit zones.
func _test_shoot() -> void:
	await _open(0)
	_park_player()
	var ok: bool = await _wait(func() -> bool: return _boars_in_state(Ids.BS_EAT) >= 4, 200.0)
	var player: PlayerBase = _hunt.get_player()
	var weapon: Dictionary = Data.get_weapon(Ids.W_CARBINE_22)
	var sow: int = _find_type(Ids.SOW)
	var boar: Boar = _hunt.spawner.get_boar(sow)
	# Broadside at 15 m, aiming at the vitals.
	var side: Vector3 = boar.global_transform.basis.x
	_place_player(boar.position.x + side.x * 15.0, boar.position.z + side.z * 15.0)
	for i: int in 3:
		await get_tree().physics_frame
	player.bot_set_aim(true)
	await _sleep(0.6)
	var health0: float = boar.health
	player.bot_look_at(_hunt.get_boar_zone_position(sow, Ids.ZONE_VITAL))
	await get_tree().physics_frame
	var fired: bool = player.bot_fire()
	await get_tree().physics_frame
	await get_tree().process_frame
	var expected: float = float(weapon["damage"]) * float(Data.get_boar_rules()["zone_multipliers"]["vital"])
	_check("vital_hit_registered", fired and _hits.size() == 1 and _hits[0][0] == sow and _hits[0][1] == Ids.ZONE_VITAL,
		"fired=%s hits=%s" % [fired, _hits])
	if _hits.size() >= 1:
		_check("vital_damage_38x2", is_equal_approx(float(_hits[0][2]), expected) and is_equal_approx(health0 - boar.health, expected),
			"damage=%.1f expected=%.1f" % [float(_hits[0][2]), expected])
	await _sleep(0.3)
	var fleeing: int = _boars_in_state(Ids.BS_FLEE)
	_check("hit_scatters_herd", fleeing >= 3, "fleeing=%d sow_state=%s" % [fleeing, boar.state])
	# Keep shooting the same sow until it drops.
	var shots: int = 1
	while boar.is_alive() and shots < 12:
		_place_player(boar.position.x + boar.global_transform.basis.x.x * 12.0, boar.position.z + boar.global_transform.basis.x.z * 12.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		player.bot_look_at(_hunt.get_boar_zone_position(sow, Ids.ZONE_VITAL))
		await get_tree().physics_frame
		if player.bot_fire():
			shots += 1
		await _sleep(0.4)
	_check("sow_killed_by_bullets", not boar.is_alive() and _kills.size() == 1, "shots=%d hits=%d health=%.0f" % [shots, _hits.size(), boar.health])
	if _kills.size() == 1:
		var k: KillInfo = _kills[0]
		var states: Array = _states.get(sow, [])
		_check("kill_info", k.boar_id == sow and k.type_id == Ids.SOW and k.reward_money > 0 and not k.one_shot
			and k.clean_kill == (k.killing_zone == Ids.ZONE_HEAD or k.killing_zone == Ids.ZONE_VITAL) and states[-1][0] == Ids.BS_DEAD,
			JSON.stringify(k.to_dict()))
		_check("counts_after_kill", _counts[-1] == Vector2i(1, 5) and _hunt.get_boars_killed() == 1, str(_counts))
		# A carcass ignores bullets.
		var n_hits: int = _hits.size()
		player.bot_look_at(_hunt.get_boar_zone_position(sow, Ids.ZONE_BODY))
		await _sleep(0.5)
		player.bot_fire()
		await _sleep(0.2)
		_check("carcass_ignores_hits", _hits.size() == n_hits and _hunt.get_boars_killed() == 1, "hits %d -> %d" % [n_hits, _hits.size()])
	# One shot, clean kill on a piglet (38 * 2.5 head > piglet health).
	var piglet: int = _find_type(Ids.PIGLET)
	var pb: Boar = _hunt.spawner.get_boar(piglet)
	var done: bool = false
	for attempt: int in 6:
		_place_player(pb.position.x + pb.global_transform.basis.x.x * 10.0, pb.position.z + pb.global_transform.basis.x.z * 10.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		player.bot_look_at(_hunt.get_boar_zone_position(piglet, Ids.ZONE_HEAD))
		await get_tree().physics_frame
		player.bot_fire()
		await _sleep(0.5)
		if not pb.is_alive():
			done = true
			break
	if done and _kills[-1].boar_id == piglet:
		var pk: KillInfo = _kills[-1]
		print("trace piglet kill %s" % JSON.stringify(pk.to_dict()))
		_check("piglet_reward_formula", pk.reward_money == Profile.kill_reward(Ids.PIGLET, pk.weight_kg, pk.killing_zone, pk.one_shot, &"mato_grosso", 0))
	else:
		_check("piglet_killed", false, "alive after 6 shots")


## Windowed only: close view of a boar with its hit zones drawn (integration risk R1).
func _test_closeup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var shots_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	# Crop at 55 %: eaten patches replace healthy ones.
	await _open(0)
	_park_player()
	_hunt.debug_set_crop_health(55.0)
	print("crop patches total=%d eaten=%d health=%.1f" % [_hunt.crop.get_patch_total(), _hunt.crop.get_patch_eaten(), _hunt.get_crop_health_pct()])
	_place_player(-35.0, -24.0)
	for i: int in 3:
		await get_tree().physics_frame
	_hunt.get_player().bot_look_at(Vector3(-35.0, _hunt.get_height(-35.0, 15.0), 15.0))
	for i: int in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if shots_dir != "":
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("crop_55pct.png"))
	await _close()
	get_tree().debug_collisions_hint = true
	await _open(2, Ids.D_FOXHOUND)
	_park_player()
	await _wait(func() -> bool: return _hunt.get_alive_boar_ids().size() >= 6, 20.0)
	await _sleep(2.0)
	var id: int = _find_type(Ids.BOAR)
	var boar: Boar = _hunt.spawner.get_boar(id)
	var side: Vector3 = boar.global_transform.basis.x
	var player: PlayerBase = _hunt.get_player()
	_place_player(boar.position.x + side.x * 4.0, boar.position.z + side.z * 4.0)
	for i: int in 3:
		await get_tree().physics_frame
	player.bot_look_at(_hunt.get_boar_zone_position(id, Ids.ZONE_BODY))
	for i: int in 10:
		await get_tree().process_frame
	player.bot_look_at(_hunt.get_boar_zone_position(id, Ids.ZONE_BODY))
	await RenderingServer.frame_post_draw
	if shots_dir != "":
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("closeup_boar_hitzones.png"))
	print("closeup boar state=%s weight=%.0f scale=%.2f" % [boar.state, boar.weight_kg, boar.body_scale])
	get_tree().debug_collisions_hint = false


## Boars routed straight through the pond, the farmhouse and the barn must walk around them.
func _test_obstacle() -> void:
	await _open(0)
	_park_player()
	await _wait(func() -> bool: return _hunt.get_alive_boar_ids().size() >= 4, 10.0)
	var cases: Array = [
		["pond", Vector2(-70.0, -55.0), 18.0, Vector2(-70.0, -84.0), Vector2(-68.0, -26.0)],
		["farmhouse", Vector2(10.0, -85.0), 6.0, Vector2(10.0, -100.0), Vector2(10.5, -70.0)],
		["barn", Vector2(38.0, -88.0), 8.0, Vector2(20.0, -88.0), Vector2(54.0, -87.0)],
	]
	var ids: PackedInt32Array = _hunt.get_alive_boar_ids().duplicate()
	print("trace obstacles count=%d map_same=%s resolve_pond=%s free_pond=%s free_house=%s" % [_hunt.obstacles.get_count(),
		_hunt.obstacles == (_hunt.get_node("Map") as MapRoot).obstacles, _hunt.obstacles.resolve(Vector2(-70.0, -50.0), 0.3),
		_hunt.obstacles.is_free(Vector2(-70.0, -50.0), 0.3), _hunt.obstacles.is_free(Vector2(10.0, -84.0), 0.3)])
	for k: int in cases.size():
		var c: Array = cases[k]
		var boar: Boar = _hunt.spawner.get_boar(ids[k])
		var from: Vector2 = c[3] as Vector2
		var to: Vector2 = c[4] as Vector2
		var center: Vector2 = c[1] as Vector2
		boar.herd.wander_end_time = 0.0
		boar._enter_to_crop()
		boar.position = Vector3(from.x, _hunt.get_height(from.x, from.y), from.y)
		boar._target = to
		var min_d: float = INF
		var t0: float = _hunt.get_elapsed_s()
		var arrived: bool = false
		while _hunt.get_elapsed_s() - t0 < 120.0:
			boar._target = to
			if boar.state != Ids.BS_TO_CROP:
				arrived = boar.get_xz().distance_to(to) < 2.0
				break
			min_d = minf(min_d, boar.get_xz().distance_to(center))
			await get_tree().process_frame
		_check("walks_around_%s" % c[0], arrived and min_d >= float(c[2]) - 0.01,
			"arrived=%s in %.1f s, min_dist=%.2f (radius %.1f), state=%s" % [arrived, _hunt.get_elapsed_s() - t0, min_d, float(c[2]), boar.state])
		# The same route at flee speed.
		boar._set_eating_here(false)
		boar.position = Vector3(from.x, _hunt.get_height(from.x, from.y), from.y)
		boar._threat = from + (from - to)
		boar._enter_flee()
		min_d = INF
		t0 = _hunt.get_elapsed_s()
		arrived = false
		while _hunt.get_elapsed_s() - t0 < 40.0:
			boar._target = to
			if boar._flee_resting:
				arrived = true
				break
			min_d = minf(min_d, boar.get_xz().distance_to(center))
			await get_tree().process_frame
		_check("runs_around_%s" % c[0], arrived and min_d >= float(c[2]) - 0.01,
			"arrived=%s in %.1f s, min_dist=%.2f" % [arrived, _hunt.get_elapsed_s() - t0, min_d])


## Perception (footsteps behind the boar), pause and thermal highlight.
func _test_misc() -> void:
	await _open(0)
	_park_player()
	var ok: bool = await _wait(func() -> bool: return _boars_in_state(Ids.BS_EAT) >= 4, 200.0)
	var player: PlayerBase = _hunt.get_player()
	var id: int = -1
	for i: int in _hunt.get_alive_boar_ids():
		var cand: Boar = _hunt.spawner.get_boar(i)
		if cand.state == Ids.BS_EAT and cand._eating_here and cand.herd.alive_count() >= 2:
			id = i
			break
	var boar: Boar = _hunt.spawner.get_boar(id)
	# Standing still 7.5 m behind it: outside the vision cone and silent.
	var back: Vector3 = boar.global_transform.basis.z
	_place_player(boar.position.x + back.x * 7.5, boar.position.z + back.z * 7.5)
	var t0: float = _hunt.get_elapsed_s()
	await _sleep(2.5)
	var alerted: bool = false
	for bid: int in _hunt.get_alive_boar_ids():
		if _state_time(bid, Ids.BS_ALERT, t0) >= 0.0 or _state_time(bid, Ids.BS_FLEE, t0) >= 0.0:
			alerted = true
	if alerted:
		print("SKIP silent_behind_not_detected: another herd member was facing the hunter")
	else:
		_check("silent_behind_not_detected", boar.state == Ids.BS_EAT, "state=%s" % boar.state)
	# Walking makes noise (8 m): alert first, reaction after alert_time_s.
	t0 = _hunt.get_elapsed_s()
	player.bot_look_at(boar.global_position + Vector3(0.0, 1.0, 0.0))
	player.bot_set_move(Vector2(1.0, 0.0), false)
	ok = await _wait(func() -> bool: return _state_time(id, Ids.BS_FLEE, t0) >= 0.0 or _state_time(id, Ids.BS_SCRAPE, t0) >= 0.0, 6.0)
	player.bot_set_move(Vector2.ZERO, false)
	var t_alert: float = _state_time(id, Ids.BS_ALERT, t0)
	var t_react: float = maxf(_state_time(id, Ids.BS_FLEE, t0), _state_time(id, Ids.BS_SCRAPE, t0))
	_check("footsteps_alert_then_react", ok and t_alert >= 0.0 and t_react - t_alert >= float(Data.get_boar_type(boar.herd.get_leader().type_id)["alert_time_s"]) - 0.02,
		"alert at +%.2f s, reaction %.2f s later" % [t_alert - t0, t_react - t_alert])
	_check("alert_shared_by_herd", _boars_in_state(Ids.BS_FLEE) + _boars_in_state(Ids.BS_SCRAPE) + _boars_in_state(Ids.BS_CHARGE) >= 3,
		"reacting=%d" % (_boars_in_state(Ids.BS_FLEE) + _boars_in_state(Ids.BS_SCRAPE) + _boars_in_state(Ids.BS_CHARGE)))
	# Thermal highlight follows thermal_vision_changed.
	GameEvents.thermal_vision_changed.emit(true)
	await _sleep(0.5)
	var lit: int = 0
	var expected: int = 0
	var pp: Vector3 = player.global_position
	for bid: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(bid)
		if b._highlight:
			lit += 1
		if Vector2(b.position.x - pp.x, b.position.z - pp.z).length() <= 150.0:
			expected += 1
	_check("thermal_highlight_on", lit == expected and lit >= 1, "lit=%d expected=%d" % [lit, expected])
	GameEvents.thermal_vision_changed.emit(false)
	lit = 0
	for bid: int in _hunt.get_alive_boar_ids():
		if _hunt.spawner.get_boar(bid)._highlight:
			lit += 1
	_check("thermal_highlight_off", lit == 0, "lit=%d" % lit)
	# Pause: the hunt clock and the boars stop.
	var e0: float = _hunt.get_elapsed_s()
	var p0: Vector3 = boar.position
	var h0: float = _hunt.get_crop_health_pct()
	get_tree().paused = true
	for i: int in 60:
		await get_tree().process_frame
	var frozen: bool = _hunt.get_elapsed_s() == e0 and boar.position == p0 and _hunt.get_crop_health_pct() == h0
	get_tree().paused = false
	await _sleep(0.5)
	_check("pause_freezes_hunt", frozen and _hunt.get_elapsed_s() > e0, "elapsed %.2f -> %.2f" % [e0, _hunt.get_elapsed_s()])
