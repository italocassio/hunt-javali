extends Node
## Package B self-test of the horde mode (docs/horda.md section 14, package B, items a-e): runs hunt.tscn headless
## offline with HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE).
##   assembly  mode, barn objective, corn stock visual, first horde_wave_changed before the first boar
##   waves     every wave: debug_horde_start_next_wave, all boars born reach `eat` (<= 90 s each), the stock drains
##             without eating a patch, debug kills; then VICTORY and the result checks (c)
##   ends      DEFEAT_CROP and DEFEAT_DEATH
##   charge    a male 8 m from the hunter scrapes >= 0.8 s before charging; a piglet never scrapes
##   layout    level 1 (docs/plano_horda_nivel2.md C1-C3): a bullet ray goes through the fence in the horde and stops on it
##             in the contract; the barn is open (a bot walks in between the front posts and stops at the grain bin);
##             static shapes <= 400; route obstacles and HordeRoute vectors. "waves" also checks that no boar on its
##             way to the barn is ever inside the corn field.
## No wander / flee state is ever emitted in any of them.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/horde_selftest.tscn [-- --only=waves]
## Not part of the game; the qa-tester owns the real tests in tests/.

const WATCHDOG_REAL_S: float = 900.0
const PARK: Vector2 = Vector2(-110.0, -110.0)
const BARN_XZ: Vector2 = Vector2(38.0, -88.0)
const OBJECTIVE_TOL_M: float = 0.1
const ARRIVE_LIMIT_S: float = 90.0
const WAVE_LIMIT_S: float = 240.0
const STOCK_RESET_BELOW: float = 40.0
const DRAIN_SAMPLE_S: float = 2.0
const MALE_DIST_M: float = 8.0
const PIGLET_DIST_M: float = 8.0
const PIGLET_WATCH_S: float = 6.0
const TELEGRAPH_TOL_S: float = 0.001
const RETURN_LIMIT_S: float = 30.0
# Layout (docs/plano_horda_nivel2.md section 8, package B acceptance)
const FENCE_RAY_FROM: Vector2 = Vector2(14.0, -58.0)     # in front of FenceS8 (z = -62); x = 10 is the gate
const FENCE_AT: Vector2 = Vector2(14.0, -62.0)
const FENCE_RAY_HEIGHT_M: float = 1.2
const FENCE_RAY_LENGTH_M: float = 10.0
const WALK_FROM: Vector2 = Vector2(40.0, -100.0)
const WALK_IN_Z: float = -89.0
const WALK_TO_Z: float = -78.0
const BIN_FRONT_Z: float = -86.4        # barn z + 1.6: front face of the grain bin
const BACK_WALL_Z: float = -83.24       # barn z + 4.76: inner face of the back wall
const BIN_STOP_SLACK_M: float = 1.2     # the capsule stops up to its radius (plus slack) before the bin
const WALK_LIMIT_S: float = 8.0
const WALK_PUSH_S: float = 3.0
const CORN_CORE: Rect2 = Rect2(27.0, -15.0, 56.0, 70.0)  # the corn field itself (no route margin)
const ROUTE_CORN: Rect2 = Rect2(23.0, -19.0, 64.0, 78.0)
const ROUTE_TOL_M: float = 0.01

var _passed: int = 0
var _failed: int = 0
var _hunt: HuntController = null
var _horde: Dictionary = {}
var _ended: Array[HuntResult] = []
var _states: Dictionary = {}            # boar_id -> Array of [state, time]
var _seq: Array = []                    # ordered bus events: ["changed", w, n, phase, cd] | ["progress", r, t] | ["counts", k, t] | ["spawn", id]
var _spawn_time: Dictionary = {}        # boar_id -> hunt time of boar_spawned
var _kills: Array[KillInfo] = []
var _max_visible_carcasses: int = 0
var _forbidden: Array = []              # [id, state] of every wander/flee seen in any session
var _scraped_piglets: Array[int] = []
var _in_corn: Array = []                # [id, x, z] of a boar seen in to_crop inside CORN_CORE
var _start_ms: int = 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_horde = Data.get_horde()
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	GameEvents.boar_state_changed.connect(_on_state)
	GameEvents.boar_spawned.connect(_on_spawned)
	GameEvents.boar_killed.connect(func(k: KillInfo) -> void: _kills.append(k))
	GameEvents.boar_counts_changed.connect(func(k: int, t: int) -> void: _seq.append(["counts", k, t]))
	GameEvents.horde_wave_changed.connect(func(w: int, n: int, p: StringName, cd: float) -> void: _seq.append(["changed", w, n, p, cd]))
	GameEvents.horde_wave_progress.connect(func(r: int, t: int) -> void: _seq.append(["progress", r, t]))
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	_check("horde_data_loaded", not _horde.is_empty() and (_horde.get("waves", []) as Array).size() >= 1)
	var all: Dictionary = {"plan": _test_plan, "assembly": _test_assembly, "layout": _test_layout, "waves": _test_waves,
		"ends": _test_ends, "charge": _test_charge, "trim": _test_trim}
	for key: String in all.keys():
		# "trim" (inflated data, prints the expected push_error) only runs when asked for.
		if (only.is_empty() and key != "trim") or only.has(key):
			print("--- %s" % key)
			await (all[key] as Callable).call()
			await _close()
	_check("never_wander_or_flee", _forbidden.is_empty(), str(_forbidden.slice(0, 10)))
	_check("piglet_never_scrapes", _scraped_piglets.is_empty(), str(_scraped_piglets))
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: self-test timed out")
		print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed + 1])
		get_tree().quit(1)


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _on_state(id: int, state: StringName) -> void:
	var t: float = _hunt.get_elapsed_s() if _hunt != null else 0.0
	if not _states.has(id):
		_states[id] = []
	(_states[id] as Array).append([state, t])
	if (state == Ids.BS_WANDER or state == Ids.BS_FLEE) and _hunt != null and _hunt.is_horde():
		_forbidden.append([id, state])
	if state == Ids.BS_SCRAPE and _hunt != null and _hunt.get_boar_type(id) == Ids.PIGLET:
		_scraped_piglets.append(id)


func _on_spawned(id: int, _type_id: StringName, _weight: float) -> void:
	_seq.append(["spawn", id])
	_spawn_time[id] = _hunt.get_elapsed_s() if _hunt != null else 0.0


# --- Plumbing ------------------------------------------------------------------------------------

func _open(mode: StringName = Ids.MODE_HORDE) -> void:
	_ended.clear()
	_states.clear()
	_seq.clear()
	_spawn_time.clear()
	_kills.clear()
	_max_visible_carcasses = 0
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, mode)
	req.rng_seed = 4242
	req.quality = Ids.Q_LOW
	Router.set_pending_request(req)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	add_child(_hunt)
	var t0: int = Time.get_ticks_msec()
	while not _hunt.is_world_ready():
		await get_tree().process_frame
	print("load_ms=%d" % (Time.get_ticks_msec() - t0))


func _close() -> void:
	if _hunt == null:
		return
	_hunt.queue_free()
	_hunt = null
	Router.set_pending_request(null)
	await get_tree().process_frame
	await get_tree().process_frame


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


func _place(x: float, z: float) -> void:
	_hunt.get_player().bot_teleport(Vector3(x, _hunt.get_height(x, z) + 0.05, z))


## Far corner, crouched or standing. The Player toggles crouch on a short press of the "crouch" action and reads
## no action while in bot mode, so the bot is off for those frames. The fallback player cannot crouch.
func _park(crouch: bool) -> void:
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	p.bot_set_move(Vector2.ZERO, false)
	_place(PARK.x, PARK.y)
	if crouch != p.is_crouching():
		p.bot_set_enabled(false)
		Input.action_press(&"crouch")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(&"crouch")
		await get_tree().process_frame
		p.bot_set_enabled(true)
		p.bot_set_move(Vector2.ZERO, false)


func _wave_ids(wave_index: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if b != null and b.wave == wave_index:
			out.append(id)
	return out


func _had_state(id: int, state: StringName) -> bool:
	for e: Array in _states.get(id, []):
		if e[0] == state:
			return true
	return false


func _state_time(id: int, state: StringName, after: float) -> float:
	for e: Array in _states.get(id, []):
		if e[0] == state and float(e[1]) >= after:
			return float(e[1])
	return -1.0


func _visible_carcasses() -> int:
	var n: int = 0
	for child: Node in _hunt.get_node("Boars").get_children():
		var b: Boar = child as Boar
		if b != null and not b.is_alive() and b.visible:
			n += 1
	return n


func _kill_wave_now(wave_index: int) -> void:
	for id: int in _wave_ids(wave_index):
		_hunt.debug_kill_boar(id)
		_max_visible_carcasses = maxi(_max_visible_carcasses, _visible_carcasses())


func _data_total() -> int:
	var total: int = 0
	for w: Variant in _horde.get("waves", []):
		for g: Variant in (w as Dictionary).get("groups", []):
			total += ((g as Dictionary).get("members", []) as Array).size()
	return total


# --- HordeDirector.plan_waves (pure) -------------------------------------------------------------

func _plan_total(plan: Array) -> int:
	var total: int = 0
	for wave_groups: Variant in plan:
		for g: Variant in wave_groups:
			total += ((g as Dictionary)["members"] as Array).size()
	return total


func _plan_tagged(plan: Array) -> bool:
	for i: int in plan.size():
		if (plan[i] as Array).is_empty():
			return false
		for g: Variant in plan[i]:
			if int((g as Dictionary).get("wave", -1)) != i:
				return false
	return true


func _test_plan() -> void:
	var totals: Array[int] = []
	var tagged: bool = true
	for players: int in range(1, 5):
		var plan: Array = HordeDirector.plan_waves(_horde, players)
		totals.append(_plan_total(plan))
		tagged = tagged and _plan_tagged(plan) and plan.size() == (_horde["waves"] as Array).size()
	var mults: Array = _horde.get("player_count_mult", [])
	var want: Array[int] = []
	for players: int in range(1, 5):
		var w: int = 0
		for wave: Variant in _horde["waves"]:
			var base: int = 0
			for g: Variant in (wave as Dictionary)["groups"]:
				base += ((g as Dictionary)["members"] as Array).size()
			w += maxi(roundi(float(base) * float(mults[players - 1])), base) if players > 1 else base
		want.append(w)
	_check("plan_totals_1_to_4_players", totals == want and totals[totals.size() - 1] <= NetCodec.MAX_BOARS_PER_HUNT and tagged,
		"got=%s want=%s" % [totals, want])


## Inflated data (every wave 4 times, x2.2): the plan is cut to 255 from its end. Prints the expected push_error.
func _test_trim() -> void:
	var big: Dictionary = _horde.duplicate(true)
	var waves: Array = []
	for k: int in 4:
		waves.append_array((_horde["waves"] as Array).duplicate(true))
	big["waves"] = waves
	var plan: Array = HordeDirector.plan_waves(big, 4)
	_check("plan_trimmed_to_255", _plan_total(plan) == NetCodec.MAX_BOARS_PER_HUNT and _plan_tagged(plan) and plan.size() < waves.size(),
		"waves %d -> %d, total=%d" % [waves.size(), plan.size(), _plan_total(plan)])


# --- (a) assembly --------------------------------------------------------------------------------

func _test_assembly() -> void:
	await _open()
	var n: int = (_horde.get("waves", []) as Array).size()
	var first_delay: float = float(_horde.get("first_wave_delay_s", 0.0))
	_check("mode_horde", _hunt.get_mode() == Ids.MODE_HORDE and _hunt.is_horde(), str(_hunt.get_mode()))
	var obj: Vector3 = _hunt.get_objective_position()
	var want: Vector3 = Vector3(BARN_XZ.x, _hunt.get_height(BARN_XZ.x, BARN_XZ.y), BARN_XZ.y)
	_check("objective_is_barn", obj.is_finite() and obj.distance_to(want) <= OBJECTIVE_TOL_M, "%s vs %s" % [obj, want])
	var barn: Node = _hunt.get_node_or_null("BarnCorn")
	_check("barn_corn_visual", barn is CornStockVisualBase and (barn as Node3D).global_position.distance_to(obj) <= OBJECTIVE_TOL_M,
		"%s" % [barn.get_script().resource_path if barn != null and barn.get_script() != null else str(barn)])
	_check("store_mode_on", _hunt.crop.is_store_mode())
	var first: Array = []
	var first_at: int = -1
	var spawn_at: int = -1
	for i: int in _seq.size():
		if _seq[i][0] == "changed" and first_at < 0:
			first_at = i
			first = _seq[i]
		if _seq[i][0] == "spawn" and spawn_at < 0:
			spawn_at = i
	_check("first_wave_changed", first.size() == 5 and first[1] == 1 and first[2] == n and first[3] == Ids.HP_INTERMISSION
		and is_equal_approx(float(first[4]), first_delay), str(first))
	_check("getters_at_start", _hunt.get_horde_wave() == 1 and _hunt.get_horde_wave_count() == n
		and _hunt.get_horde_phase() == Ids.HP_INTERMISSION and _hunt.get_horde_waves_cleared() == 0
		and _hunt.get_horde_wave_total() > 0 and _hunt.get_horde_wave_remaining() == 0,
		"wave=%d/%d phase=%s total=%d" % [_hunt.get_horde_wave(), _hunt.get_horde_wave_count(), _hunt.get_horde_phase(), _hunt.get_horde_wave_total()])
	_check("result_mode_and_no_progress", _hunt.debug_partial_result().mode == Ids.MODE_HORDE
		and not _hunt.debug_partial_result().counts_for_progression and _hunt.debug_partial_result().horde_wave_count == n)
	await _park(true)
	var cd0: float = _hunt.get_horde_countdown_s()
	await _sleep(2.0)
	_check("countdown_decreases", _hunt.get_horde_countdown_s() < cd0 - 1.9 and _hunt.get_alive_boar_ids().is_empty(),
		"%.2f -> %.2f alive=%d" % [cd0, _hunt.get_horde_countdown_s(), _hunt.get_alive_boar_ids().size()])
	var ok: bool = await _wait(func() -> bool: return _hunt.get_horde_phase() == Ids.HP_WAVE, first_delay)
	_check("wave_1_starts_by_itself", ok and _hunt.get_horde_wave() == 1, "t=%.1f" % _hunt.get_elapsed_s())
	ok = await _wait(func() -> bool: return not _hunt.get_alive_boar_ids().is_empty(), 5.0)
	spawn_at = -1
	for i: int in _seq.size():
		if _seq[i][0] == "spawn":
			spawn_at = i
			break
	_check("intermission_announced_before_first_boar", ok and first_at >= 0 and spawn_at > first_at, "changed@%d spawn@%d" % [first_at, spawn_at])
	_hunt.debug_horde_start_next_wave()
	await get_tree().process_frame
	_check("debug_skip_noop_outside_intermission", _hunt.get_horde_phase() == Ids.HP_WAVE and _hunt.get_horde_wave() == 1)


# --- (b) + (c) every wave, then victory ----------------------------------------------------------

func _test_waves() -> void:
	await _open()
	await _park(true)
	var crouched: bool = _hunt.get_player().is_crouching()
	if _hunt.get_player() is FallbackPlayer:
		print("trace fallback player: cannot crouch, parked standing")
	else:
		_check("hunter_parked_crouched", crouched)
	var n: int = _hunt.get_horde_wave_count()
	var intermission: float = float(_horde.get("intermission_s", 0.0))
	var all_reach: bool = true
	var all_drain: bool = true
	var no_patch: bool = true
	var phases_ok: bool = true
	var detail: Array = []
	for w: int in range(1, n + 1):
		if _hunt.get_horde_phase() != Ids.HP_INTERMISSION or _hunt.get_horde_wave() != w:
			phases_ok = false
			detail.append("w%d before: wave=%d phase=%s" % [w, _hunt.get_horde_wave(), _hunt.get_horde_phase()])
		_hunt.debug_horde_start_next_wave()
		await get_tree().process_frame
		await get_tree().process_frame
		var total: int = _hunt.get_horde_wave_total()
		if _hunt.get_horde_phase() != Ids.HP_WAVE or _hunt.get_horde_wave_remaining() != total:
			phases_ok = false
			detail.append("w%d start: phase=%s rem=%d total=%d" % [w, _hunt.get_horde_phase(), _hunt.get_horde_wave_remaining(), total])
		# Every boar of the wave is born and reaches the eat ring.
		var t0: float = _hunt.get_elapsed_s()
		var born: Dictionary = {}
		var eaten_at: Dictionary = {}
		var late: Array = []
		var min_stock: float = 100.0
		while _hunt.get_elapsed_s() - t0 < WAVE_LIMIT_S and not _hunt.is_hunt_over():
			for id: int in _wave_ids(w - 1):
				born[id] = true
				if not eaten_at.has(id) and _had_state(id, Ids.BS_EAT):
					eaten_at[id] = _hunt.get_elapsed_s()
				elif not eaten_at.has(id) and _hunt.get_elapsed_s() - float(_spawn_time.get(id, t0)) > ARRIVE_LIMIT_S and not late.has(id):
					late.append(id)
			if born.size() == total and eaten_at.size() == total:
				break
			min_stock = minf(min_stock, _hunt.get_crop_health_pct())
			_watch_corn()
			if _hunt.get_crop_health_pct() < STOCK_RESET_BELOW:
				_hunt.debug_set_crop_health(100.0)
			await get_tree().process_frame
		var worst: float = 0.0
		for id: Variant in eaten_at:
			worst = maxf(worst, float(eaten_at[id]) - float(_spawn_time.get(id, t0)))
		var reached: bool = born.size() == total and eaten_at.size() == total and late.is_empty()
		for id: Variant in late:
			var lb: Boar = _hunt.spawner.get_boar(int(id))
			if lb != null:
				print("trace late boar %d %s at (%.1f, %.1f) state=%s route=%s" % [int(id), lb.type_id, lb.position.x, lb.position.z,
					lb.state, lb.debug_route()])
		all_reach = all_reach and reached
		print("trace wave %d: total=%d born=%d at_ring=%d slowest=%.1f s late=%s t=%.1f" % [w, total, born.size(), eaten_at.size(), worst, late, _hunt.get_elapsed_s() - t0])
		# The stock drains, no patch is ever eaten.
		var h0: float = _hunt.get_crop_health_pct()
		await _sleep(DRAIN_SAMPLE_S)
		var h1: float = _hunt.get_crop_health_pct()
		var drained: bool = h1 < h0 or min_stock < 100.0
		all_drain = all_drain and drained and _hunt.crop.get_eater_count() > 0
		no_patch = no_patch and _hunt.crop.get_patch_eaten() == 0
		if not reached or not drained:
			detail.append("w%d reached=%s drained %.2f->%.2f eaters=%d" % [w, reached, h0, h1, _hunt.crop.get_eater_count()])
		_kill_wave_now(w - 1)
		_hunt.debug_set_crop_health(100.0)
		await get_tree().process_frame
		await get_tree().process_frame
		if w < n:
			if _hunt.get_horde_phase() != Ids.HP_INTERMISSION or _hunt.get_horde_wave() != w + 1 or _hunt.get_horde_waves_cleared() != w \
					or absf(_hunt.get_horde_countdown_s() - intermission) > 0.1:
				phases_ok = false
				detail.append("w%d end: wave=%d phase=%s cleared=%d cd=%.2f" % [w, _hunt.get_horde_wave(), _hunt.get_horde_phase(),
					_hunt.get_horde_waves_cleared(), _hunt.get_horde_countdown_s()])
		if _hunt.is_hunt_over() and w < n:
			detail.append("hunt over at wave %d" % w)
			phases_ok = false
			break
	_check("every_boar_reaches_the_barn_within_90s", all_reach, str(detail))
	_check("no_boar_on_its_way_inside_the_corn", _in_corn.is_empty(), str(_in_corn.slice(0, 8)))
	_check("stock_drains_without_patches", all_drain and no_patch, "patches=%d %s" % [_hunt.crop.get_patch_eaten(), detail])
	_check("phases_follow_the_waves", phases_ok, str(detail))
	await _sleep(1.0)
	# (c)
	_check("victory_once", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.VICTORY,
		"ended=%d %s" % [_ended.size(), HuntResult.Outcome.keys()[_ended[0].outcome] if _ended.size() > 0 else ""])
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_check("result_waves", r.horde_waves_cleared == r.horde_wave_count and r.horde_wave_count == n and n == (_horde["waves"] as Array).size(),
		"cleared=%d count=%d" % [r.horde_waves_cleared, r.horde_wave_count])
	_check("result_mode_no_progress", r.mode == Ids.MODE_HORDE and r.is_horde() and not r.counts_for_progression)
	_check("result_bonus", r.contract_bonus == Profile.horde_bonus(r.crop_health_pct, 1) and r.contract_bonus > 0
		and r.total_money == r.money_from_kills + r.contract_bonus, "bonus=%d crop=%.2f" % [r.contract_bonus, r.crop_health_pct])
	var rewards_ok: bool = r.kills.size() == _data_total() and r.boars_total == _data_total()
	var max_id: int = 0
	for k: KillInfo in r.kills:
		rewards_ok = rewards_ok and k.reward_money == Profile.horde_kill_reward(k.type_id, k.weight_kg, k.killing_zone, k.one_shot, 1)
		max_id = maxi(max_id, k.boar_id)
	_check("kill_rewards_are_horde_rewards", rewards_ok, "kills=%d total=%d data=%d" % [r.kills.size(), r.boars_total, _data_total()])
	_check("ids_fit_u8", max_id <= NetCodec.MAX_BOARS_PER_HUNT and max_id == r.kills.size(), "max_id=%d" % max_id)
	var max_c: int = int(_horde.get("max_carcasses", 0))
	_check("carcasses_capped", _max_visible_carcasses <= max_c and _visible_carcasses() <= max_c and _visible_carcasses() == mini(max_c, r.kills.size()),
		"max_seen=%d now=%d cap=%d" % [_max_visible_carcasses, _visible_carcasses(), max_c])
	_check("progress_after_counts", _progress_order_ok(), "")
	var changes: int = 0
	for e: Array in _seq:
		if e[0] == "changed":
			changes += 1
	_check("wave_changed_twice_per_wave", changes == 2 * n, "changed=%d" % changes)


## Every horde_wave_progress comes right after a boar_counts_changed (a kill) or right after the wave_changed
## that starts the wave (remaining == total).
func _progress_order_ok() -> bool:
	var count: int = 0
	for i: int in _seq.size():
		var e: Array = _seq[i]
		if e[0] != "progress":
			continue
		count += 1
		var prev: Array = _seq[i - 1] if i > 0 else []
		var after_kill: bool = prev.size() > 0 and prev[0] == "counts"
		var at_start: bool = prev.size() > 0 and prev[0] == "changed" and prev[3] == Ids.HP_WAVE and e[1] == e[2]
		if not after_kill and not at_start:
			print("trace bad progress order at %d: %s after %s" % [i, e, prev])
			return false
	return count > 0


## C2: a boar on its way to the barn (to_crop) never stands inside the corn field itself.
func _watch_corn() -> void:
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if b != null and b.state == Ids.BS_TO_CROP and CORN_CORE.has_point(b.get_xz()) and _in_corn.size() < 50:
			_in_corn.append([id, snappedf(b.position.x, 0.1), snappedf(b.position.z, 0.1)])


# --- Layout: fence, open barn, route (docs/plano_horda_nivel2.md C1-C3) ----------------------------

func _fence_ray(mask: int) -> Dictionary:
	var y: float = _hunt.get_height(FENCE_AT.x, FENCE_AT.y) + FENCE_RAY_HEIGHT_M
	var from: Vector3 = Vector3(FENCE_RAY_FROM.x, y, FENCE_RAY_FROM.y)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 0.0, -FENCE_RAY_LENGTH_M), mask)
	return _hunt.get_world_3d().direct_space_state.intersect_ray(q)


func _is_fence(hit: Dictionary) -> bool:
	var body: Node = hit.get("collider") as Node
	var spawn: PropSpawn = body.get_parent() as PropSpawn if body != null else null
	return spawn != null and MapRoot.FENCE_IDS.has(spawn.prop_id)


func _hit_name(hit: Dictionary) -> String:
	var body: Node = hit.get("collider") as Node
	return "%s/%s" % [body.get_parent().name, body.name] if body != null and body.get_parent() != null else "nothing"


func _test_layout() -> void:
	# Contract: the fence is a wall for the bullet, as always (Q2).
	await _open(Ids.MODE_CONTRACT)
	var hit: Dictionary = _fence_ray(Layers.MASK_WEAPON_RAY)
	_check("contract_fence_stops_the_bullet", _is_fence(hit), _hit_name(hit))
	var map: MapRoot = _hunt.get_node("Map") as MapRoot
	_check("contract_no_route_no_bounds", _hunt.horde_route_obstacles.is_empty() and _hunt.get_player_bounds() == Rect2()
		and _hunt.get_horde_level() == 0, "obstacles=%d" % _hunt.horde_route_obstacles.size())
	var contract_shapes: int = map.get_static_shapes_used()
	await _close()
	await _open()
	hit = _fence_ray(Layers.MASK_WEAPON_RAY)
	_check("horde_bullet_goes_through_the_fence", not _is_fence(hit), _hit_name(hit))
	hit = _fence_ray(Layers.FENCE)
	_check("horde_fence_body_on_fence_layer", _is_fence(hit) and ((hit["collider"] as CollisionObject3D).collision_layer == Layers.FENCE)
		and (Layers.MASK_PLAYER_BODY & Layers.FENCE) != 0, _hit_name(hit))
	map = _hunt.get_node("Map") as MapRoot
	_check("static_shapes_within_budget", map.get_static_shapes_used() <= MapRoot.STATIC_SHAPE_BUDGET,
		"horde=%d contract=%d" % [map.get_static_shapes_used(), contract_shapes])
	_check("horde_level_1", _hunt.get_horde_level() == 1 and _hunt.get_player_bounds() == Rect2()
		and _hunt.get_ammo_crate_positions().is_empty() and _hunt.debug_partial_result().horde_level == 1)
	var obs: Array[Dictionary] = _hunt.horde_route_obstacles
	var barn_rect: Rect2 = Rect2(BARN_XZ.x - 8.4, BARN_XZ.y - 5.4, 16.8, 10.8)
	var exit_want: Vector2 = Vector2(BARN_XZ.x, BARN_XZ.y - 7.0)
	_check("route_obstacles_corn_and_barn", obs.size() == 2 and (obs[0]["rect"] as Rect2).is_equal_approx(ROUTE_CORN)
		and not (obs[0]["exit"] as Vector2).is_finite() and (obs[1]["rect"] as Rect2).is_equal_approx(barn_rect)
		and (obs[1]["exit"] as Vector2).distance_to(exit_want) < ROUTE_TOL_M, str(obs))
	var corn_only: Array[Dictionary] = [{"rect": ROUTE_CORN, "exit": Vector2.INF}]
	var r1: PackedVector2Array = HordeRoute.plan(Vector2(105.0, 95.0), BARN_XZ, corn_only, 2.0)
	var r2: PackedVector2Array = HordeRoute.plan(Vector2(20.0, 115.0), BARN_XZ, corn_only, 2.0)
	var r3: PackedVector2Array = HordeRoute.plan(Vector2(105.0, 95.0), BARN_XZ, [] as Array[Dictionary], 2.0)
	var r4: PackedVector2Array = HordeRoute.plan(Vector2(38.0, -86.0), Vector2(60.0, -88.0), obs, 2.0)
	_check("route_vectors", _same(r1, [Vector2(89.0, -21.0), BARN_XZ]) and _same(r2, [Vector2(21.0, -21.0), BARN_XZ])
		and _same(r3, [BARN_XZ]) and r4.size() >= 2 and r4[0].distance_to(exit_want) < ROUTE_TOL_M,
		"%s %s %s %s" % [r1, r2, r3, r4])
	# C3: the barn is open at its front (-Z) and the grain bin is solid.
	await _park(false)
	var p: PlayerBase = _hunt.get_player()
	_place(WALK_FROM.x, WALK_FROM.y)
	p.bot_look_at(Vector3(WALK_FROM.x, p.get_eye_position().y, WALK_TO_Z))
	p.bot_set_move(Vector2(0.0, 1.0), false)
	var entered: bool = await _wait(func() -> bool: return p.global_position.z >= WALK_IN_Z, WALK_LIMIT_S)
	var in_at: Vector3 = p.global_position
	var max_z: float = p.global_position.z
	var t0: float = _hunt.get_elapsed_s()
	while _hunt.get_elapsed_s() - t0 < WALK_PUSH_S:
		p.bot_look_at(Vector3(WALK_FROM.x, p.get_eye_position().y, WALK_TO_Z))
		max_z = maxf(max_z, p.global_position.z)
		await get_tree().process_frame
	p.bot_set_move(Vector2.ZERO, false)
	_check("barn_open_front", entered, "at %s" % in_at)
	_check("barn_grain_bin_stops_the_hunter", max_z <= BIN_FRONT_Z and max_z >= BIN_FRONT_Z - BIN_STOP_SLACK_M and max_z < BACK_WALL_Z,
		"max z %.2f (bin front %.2f)" % [max_z, BIN_FRONT_Z])


func _same(got: PackedVector2Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i: int in got.size():
		if got[i].distance_to(want[i] as Vector2) > ROUTE_TOL_M:
			return false
	return true


# --- (d) defeats ---------------------------------------------------------------------------------

func _test_ends() -> void:
	await _open()
	await _park(true)
	await _sleep(1.0)
	_hunt.debug_set_crop_health(0.0)
	await _sleep(0.5)
	_check("defeat_crop", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.DEFEAT_CROP and _ended[0].contract_bonus == 0
		and _ended[0].horde_waves_cleared == 0 and _ended[0].mode == Ids.MODE_HORDE, "ended=%d" % _ended.size())
	await _close()

	await _open()
	await _sleep(1.0)
	_hunt.get_player().apply_damage(9999.0, Vector3.ZERO)
	await _sleep(0.5)
	_check("defeat_death", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.DEFEAT_DEATH and _ended[0].contract_bonus == 0,
		"ended=%d" % _ended.size())


# --- (e) charge rules in the horde ---------------------------------------------------------------

func _find_in_wave(type_id: StringName, wave_index: int, state: StringName) -> int:
	for id: int in _wave_ids(wave_index):
		var b: Boar = _hunt.spawner.get_boar(id)
		if b.type_id == type_id and b.state == state:
			return id
	return -1


func _test_charge() -> void:
	await _open()
	await _park(true)
	# The first waves without a male go by quickly.
	var male_wave: int = -1
	var waves: Array = _horde.get("waves", [])
	for i: int in waves.size():
		for g: Variant in (waves[i] as Dictionary).get("groups", []):
			if ((g as Dictionary).get("members", []) as Array).has("boar") and male_wave < 0:
				male_wave = i
	_check("data_has_a_male_wave", male_wave >= 0)
	if male_wave < 0:
		return
	for w: int in range(0, male_wave):
		_hunt.debug_horde_start_next_wave()
		await _wait(func() -> bool:
			_kill_wave_now(w)
			return _hunt.get_horde_waves_cleared() > w, 60.0)
	_hunt.debug_horde_start_next_wave()
	# A piglet on its way to the barn, 8 m from a standing hunter: it never scrapes.
	await _park(false)
	var ok: bool = await _wait(func() -> bool: return _find_in_wave(Ids.PIGLET, male_wave, Ids.BS_TO_CROP) >= 0, 30.0)
	if ok:
		var pid: int = _find_in_wave(Ids.PIGLET, male_wave, Ids.BS_TO_CROP)
		var pig: Boar = _hunt.spawner.get_boar(pid)
		await _sleep(1.0)
		var fwd: Vector3 = -pig.global_transform.basis.z
		var t0: float = _hunt.get_elapsed_s()
		_place(pig.position.x + fwd.x * PIGLET_DIST_M, pig.position.z + fwd.z * PIGLET_DIST_M)
		await _sleep(PIGLET_WATCH_S)
		_check("piglet_8m_no_scrape", _state_time(pid, Ids.BS_SCRAPE, t0) < 0.0 and not _had_state(pid, Ids.BS_FLEE),
			"states=%s" % str(_states.get(pid, [])).right(200))
		await _park(false)
	else:
		_check("piglet_found", false, "no piglet on its way in wave %d" % (male_wave + 1))
	# The male: 8 m in front of it, standing.
	ok = await _wait(func() -> bool: return _find_in_wave(Ids.BOAR, male_wave, Ids.BS_TO_CROP) >= 0, 60.0)
	_check("male_spawned", ok)
	if not ok:
		return
	var id: int = _find_in_wave(Ids.BOAR, male_wave, Ids.BS_TO_CROP)
	var boar: Boar = _hunt.spawner.get_boar(id)
	await _sleep(1.0)
	var fwd2: Vector3 = -boar.global_transform.basis.z
	var t1: float = _hunt.get_elapsed_s()
	_place(boar.position.x + fwd2.x * MALE_DIST_M, boar.position.z + fwd2.z * MALE_DIST_M)
	ok = await _wait(func() -> bool: return _state_time(id, Ids.BS_CHARGE, t1) >= 0.0, 10.0)
	var t_scrape: float = _state_time(id, Ids.BS_SCRAPE, t1)
	var t_charge: float = _state_time(id, Ids.BS_CHARGE, t1)
	_check("male_scrapes_before_charge", ok and t_scrape >= 0.0 and t_charge - t_scrape >= float(Data.get_boar_type(Ids.BOAR)["charge_telegraph_s"]) - TELEGRAPH_TOL_S,
		"scrape at +%.2f, charge %.3f s later; %s" % [t_scrape - t1, t_charge - t_scrape, str(_states.get(id, [])).right(240)])
	# The hunter goes away: the male goes back to the barn (no flee).
	await _park(true)
	var t2: float = _hunt.get_elapsed_s()
	ok = await _wait(func() -> bool:
		return boar.is_alive() and (boar.state == Ids.BS_TO_CROP or boar.state == Ids.BS_EAT) and _hunt.get_elapsed_s() > t2 + 0.5, RETURN_LIMIT_S)
	_check("male_back_to_the_barn", ok and not _had_state(id, Ids.BS_FLEE), "state=%s" % boar.state)
