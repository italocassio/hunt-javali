extends Node
## Package B self-test of horde level 2 (docs/plano_horda_nivel2.md section 8, package B): runs hunt.tscn headless
## offline with HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, 2).
##   assembly  level 2, hunter born near the level's spawn, farm bounds, three ammo crates in the barn, route obstacles
##   crates    standing on a crate takes nothing; a press of interact takes it once (owner's Q4): it disappears, adds
##             ammo and comes back after respawn_s (needs Player.needs_ammo, package A)
##   sow       level 2 overrides on the boars; a sow 9 m from a standing hunter scrapes >= telegraph before charging
##   ends      DEFEAT_CROP and VICTORY results carry horde_level 2 and level 2 prizes; solo death = DEFEAT_DEATH
## A piglet never scrapes and no wander / flee state is ever emitted.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/horde2_selftest.tscn [-- --only=sow]
## Not part of the game; the qa-tester owns the real tests in tests/.

const LEVEL: int = 2
const WATCHDOG_REAL_S: float = 900.0
const BARN_XZ: Vector2 = Vector2(38.0, -88.0)
const SPAWN_XZ: Vector2 = Vector2(30.0, -74.0)
const SPAWN_TOL_M: float = 4.0
const BOUNDS_WANT: Rect2 = Rect2(-19.4, -109.4, 73.8, 46.8)
const CRATES_WANT: Array[Vector2] = [Vector2(35.0, -90.0), Vector2(38.0, -90.0), Vector2(41.0, -90.0)]
const POS_TOL_M: float = 0.01
const SAFE_XZ: Vector2 = Vector2(-15.0, -105.0)   # far corner of the farm, away from the boars' ways
const TAKE_WAIT_S: float = 1.0
const STAND_S: float = 0.5                         # standing on a crate this long without a press takes nothing
const RESPAWN_EARLY_S: float = 1.0
const RESPAWN_LATE_S: float = 1.0
const STOCK_RESET_BELOW: float = 40.0
const SOW_DIST_M: float = 9.0
const SOW_FIND_S: float = 90.0
const SOW_MIN_BARN_DIST_M: float = 18.0
const SOW_INSET_M: float = 3.0
const SOW_PLACE_INSET_M: float = 1.0
const CHARGE_WAIT_S: float = 10.0
const TELEGRAPH_TOL_S: float = 0.001
const KILLS_WANTED: int = 2
const KILL_WAIT_S: float = 30.0

var _passed: int = 0
var _failed: int = 0
var _hunt: HuntController = null
var _cfg: Dictionary = {}
var _ended: Array[HuntResult] = []
var _states: Dictionary = {}            # boar_id -> Array of [state, time]
var _forbidden: Array = []
var _scraped_piglets: Array[int] = []
var _downed: Array[int] = []
var _start_ms: int = 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_cfg = Data.get_horde_level(LEVEL)
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	GameEvents.boar_state_changed.connect(_on_state)
	GameEvents.hunter_downed.connect(func(s: int) -> void: _downed.append(s))
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	_check("level_2_data", not _cfg.is_empty() and int(_cfg.get("level", 0)) == LEVEL, "levels=%d" % Data.get_horde_level_count())
	var all: Dictionary = {"assembly": _test_assembly, "crates": _test_crates, "sow": _test_sow, "ends": _test_ends}
	for key: String in all.keys():
		if only.is_empty() or only.has(key):
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


# --- Plumbing ------------------------------------------------------------------------------------

func _open() -> void:
	_ended.clear()
	_states.clear()
	_downed.clear()
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, LEVEL)
	req.rng_seed = 2626
	req.quality = Ids.Q_LOW
	Router.set_pending_request(req)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	add_child(_hunt)
	while not _hunt.is_world_ready():
		await get_tree().process_frame


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


## Waits game time, keeping the barn's stock up (the boars eat while the test looks elsewhere).
func _sleep(seconds: float) -> void:
	var limit: float = _hunt.get_elapsed_s() + seconds
	while _hunt.get_elapsed_s() < limit:
		if _hunt.get_crop_health_pct() < STOCK_RESET_BELOW:
			_hunt.debug_set_crop_health(100.0)
		await get_tree().process_frame


func _place(x: float, z: float) -> void:
	_hunt.get_player().bot_teleport(Vector3(x, _hunt.get_height(x, z) + 0.05, z))


## The Player toggles crouch on a short press of the "crouch" action and reads no action while in bot mode.
func _set_crouch(on: bool) -> void:
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	p.bot_set_move(Vector2.ZERO, false)
	if on != p.is_crouching():
		p.bot_set_enabled(false)
		Input.action_press(&"crouch")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(&"crouch")
		await get_tree().process_frame
		p.bot_set_enabled(true)
		p.bot_set_move(Vector2.ZERO, false)


func _park_safe() -> void:
	_place(SAFE_XZ.x, SAFE_XZ.y)
	await _set_crouch(true)


func _state_time(id: int, state: StringName, after: float) -> float:
	for e: Array in _states.get(id, []):
		if e[0] == state and float(e[1]) >= after:
			return float(e[1])
	return -1.0


func _find_alive(type_id: StringName, state: StringName) -> Boar:
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if b != null and b.type_id == type_id and b.state == state:
			return b
	return null


# --- Assembly ------------------------------------------------------------------------------------

func _test_assembly() -> void:
	await _open()
	_check("horde_level_is_2", _hunt.is_horde() and _hunt.get_horde_level() == LEVEL and _hunt.debug_partial_result().horde_level == LEVEL,
		"level=%d" % _hunt.get_horde_level())
	var p: PlayerBase = _hunt.get_player()
	var at: Vector2 = Vector2(p.global_position.x, p.global_position.z)
	_check("hunter_born_at_level_spawn", at.distance_to(SPAWN_XZ) <= SPAWN_TOL_M, "at %s" % at)
	var b: Rect2 = _hunt.get_player_bounds()
	_check("player_bounds_farm_inset", b.position.distance_to(BOUNDS_WANT.position) < POS_TOL_M and b.size.distance_to(BOUNDS_WANT.size) < POS_TOL_M,
		"%s" % b)
	var crates: PackedVector3Array = _hunt.get_ammo_crate_positions()
	var crates_ok: bool = crates.size() == CRATES_WANT.size()
	for i: int in mini(crates.size(), CRATES_WANT.size()):
		crates_ok = crates_ok and Vector2(crates[i].x, crates[i].z).distance_to(CRATES_WANT[i]) < POS_TOL_M \
			and absf(crates[i].y - _hunt.get_height(crates[i].x, crates[i].z)) < POS_TOL_M
	_check("three_crates_in_the_barn", crates_ok, "%s" % crates)
	var node: HordeAmmoCrates = _hunt.get_node_or_null("AmmoCrates") as HordeAmmoCrates
	var visuals_ok: bool = node != null and node.get_child_count() == CRATES_WANT.size()
	if node != null:
		for c: Node in node.get_children():
			visuals_ok = visuals_ok and (c as Node3D).visible
	_check("crate_visuals", visuals_ok, "%s" % [node.get_child(0).get_script().resource_path if node != null and node.get_child_count() > 0
		and node.get_child(0).get_script() != null else "fallback box"])
	_check("route_obstacles", _hunt.horde_route_obstacles.size() == 2, "%d" % _hunt.horde_route_obstacles.size())


# --- Ammo crates ---------------------------------------------------------------------------------

func _test_crates() -> void:
	await _open()
	var crates: HordeAmmoCrates = _hunt.debug_ammo_crates()
	var p: PlayerBase = _hunt.get_player()
	if crates == null:
		_check("crates_built", false)
		return
	await _set_crouch(false)
	var respawn: float = float((_cfg["ammo_crates"] as Dictionary)["respawn_s"])
	var r0: int = p.get_ammo_reserve()
	var needs: bool = p.needs_ammo()
	var at: Vector3 = crates.get_crate_position(0)
	_place(at.x, at.z)
	var walked: bool = await _wait(func() -> bool: return not crates.is_available(0), STAND_S)
	_check("crate_not_taken_by_standing", not walked and p.get_ammo_reserve() == r0 and p.get_ammo_crate_target() == 0,
		"available=%s target=%d reserve %d -> %d" % [crates.is_available(0), p.get_ammo_crate_target(), r0, p.get_ammo_reserve()])
	p.bot_set_interact(true)
	await get_tree().process_frame
	p.bot_set_interact(false)
	var taken: bool = await _wait(func() -> bool: return not crates.is_available(0), TAKE_WAIT_S)
	var t_taken: float = _hunt.get_elapsed_s()
	_check("crate_taken_by_press", taken and not (crates.get_child(0) as Node3D).visible
		and _hunt.get_ammo_crate_positions().size() == CRATES_WANT.size() - 1,
		"needs_ammo=%s available=%s (Player.needs_ammo is package A)" % [needs, crates.is_available(0)])
	_check("crate_gives_ammo", p.get_ammo_reserve() > r0, "reserve %d -> %d" % [r0, p.get_ammo_reserve()])
	_check("crate_taken_once", crates.is_available(1) and crates.is_available(2)
		and _hunt.get_ammo_crate_positions().size() == CRATES_WANT.size() - 1)
	await _park_safe()
	if not taken:
		return
	await _sleep(maxf(respawn - RESPAWN_EARLY_S - (_hunt.get_elapsed_s() - t_taken), 0.0))
	var early: bool = crates.is_available(0)
	var back: bool = await _wait(func() -> bool: return crates.is_available(0), RESPAWN_EARLY_S + RESPAWN_LATE_S)
	_check("crate_back_after_respawn_s", not early and back and (crates.get_child(0) as Node3D).visible
		and _hunt.get_ammo_crate_positions().size() == CRATES_WANT.size(),
		"early=%s back after %.2f s (respawn_s %.1f)" % [early, _hunt.get_elapsed_s() - t_taken, respawn])


# --- Level 2 aggression --------------------------------------------------------------------------

func _test_sow() -> void:
	await _open()
	await _park_safe()
	_hunt.debug_horde_start_next_wave()
	var pick: Array = [null]   # lambdas capture locals by value: the found sow goes through an array
	var bounds: Rect2 = _hunt.get_player_bounds().grow(-SOW_INSET_M)
	var found: bool = await _wait(func() -> bool:
		if _hunt.get_crop_health_pct() < STOCK_RESET_BELOW:
			_hunt.debug_set_crop_health(100.0)
		var s: Boar = _find_alive(Ids.SOW, Ids.BS_TO_CROP)
		if s != null and bounds.has_point(s.get_xz()) and s.get_xz().distance_to(BARN_XZ) > SOW_MIN_BARN_DIST_M:
			pick[0] = s
			return true
		return false, SOW_FIND_S)
	_check("sow_inside_the_farm", found)
	if not found:
		return
	var sow: Boar = pick[0] as Boar
	var want: Dictionary = Data.get_horde_boar_type(Ids.SOW, LEVEL)
	_check("sow_level_2_overrides", sow._aggression == StringName(str(want["aggression"])) and sow._aggression == &"provoked"
		and is_equal_approx(sow._charge_damage, float(want["charge_damage"])) and is_equal_approx(sow._aggro_radius, float(want["aggro_radius_m"]))
		and sow._max_charges == int(want["max_charges"]) and is_equal_approx(sow._telegraph_s, float(want["charge_telegraph_s"]))
		and is_equal_approx(sow._to_barn_frac, float(_cfg["to_barn_speed_frac"])),
		"aggr=%s dmg=%.1f radius=%.1f telegraph=%.2f frac=%.2f" % [sow._aggression, sow._charge_damage, sow._aggro_radius, sow._telegraph_s, sow._to_barn_frac])
	await _set_crouch(false)
	var fwd: Vector3 = -sow.global_transform.basis.z
	var place: Vector2 = sow.get_xz() + Vector2(fwd.x, fwd.z).normalized() * SOW_DIST_M
	var inner: Rect2 = _hunt.get_player_bounds().grow(-SOW_PLACE_INSET_M)
	place = Vector2(clampf(place.x, inner.position.x, inner.end.x), clampf(place.y, inner.position.y, inner.end.y))
	var t1: float = _hunt.get_elapsed_s()
	_place(place.x, place.y)
	var dist0: float = place.distance_to(sow.get_xz())
	var id: int = sow.boar_id
	var ok: bool = await _wait(func() -> bool: return _state_time(id, Ids.BS_CHARGE, t1) >= 0.0, CHARGE_WAIT_S)
	var t_scrape: float = _state_time(id, Ids.BS_SCRAPE, t1)
	var t_charge: float = _state_time(id, Ids.BS_CHARGE, t1)
	_check("sow_9m_scrapes_then_charges", ok and t_scrape >= 0.0 and t_charge - t_scrape >= float(want["charge_telegraph_s"]) - TELEGRAPH_TOL_S,
		"dist %.1f m, scrape at +%.2f, charge %.3f s later; %s" % [dist0, t_scrape - t1, t_charge - t_scrape, str(_states.get(id, [])).right(240)])
	await _park_safe()
	await _sleep(1.0)


# --- Ends and prizes -----------------------------------------------------------------------------

func _test_ends() -> void:
	await _open()
	await _park_safe()
	_hunt.debug_horde_start_next_wave()
	await _wait(func() -> bool:
		for id: int in _hunt.get_alive_boar_ids():
			_hunt.debug_kill_boar(id)
		return _hunt.get_boars_killed() >= KILLS_WANTED, KILL_WAIT_S)
	await get_tree().process_frame
	_hunt.debug_set_crop_health(0.0)
	await _wait(func() -> bool: return not _ended.is_empty(), 1.0)
	_check("defeat_crop", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.DEFEAT_CROP, "ended=%d" % _ended.size())
	if _ended.size() == 1:
		var r: HuntResult = _ended[0]
		var rewards_ok: bool = r.kills.size() >= KILLS_WANTED
		var differs: bool = false
		for k: KillInfo in r.kills:
			rewards_ok = rewards_ok and k.reward_money == Profile.horde_kill_reward(k.type_id, k.weight_kg, k.killing_zone, k.one_shot, LEVEL)
			differs = differs or k.reward_money != Profile.horde_kill_reward(k.type_id, k.weight_kg, k.killing_zone, k.one_shot, 1)
		_check("defeat_result_level_2", r.horde_level == LEVEL and r.mode == Ids.MODE_HORDE and r.contract_bonus == 0
			and r.to_dict().get("horde_level", -1) == LEVEL, "horde_level=%d bonus=%d" % [r.horde_level, r.contract_bonus])
		_check("kill_rewards_level_2", rewards_ok and differs, "kills=%d money=%d" % [r.kills.size(), r.money_from_kills])
	await _close()

	await _open()
	await _sleep(0.5)
	_hunt.debug_force_end(HuntResult.Outcome.VICTORY)
	await get_tree().process_frame
	if _ended.size() == 1:
		var v: HuntResult = _ended[0]
		_check("victory_bonus_level_2", v.horde_level == LEVEL and v.contract_bonus == Profile.horde_bonus(v.crop_health_pct, LEVEL)
			and v.contract_bonus != Profile.horde_bonus(v.crop_health_pct, 1) and v.total_money == v.money_from_kills + v.contract_bonus,
			"bonus=%d crop=%.1f" % [v.contract_bonus, v.crop_health_pct])
	else:
		_check("victory_bonus_level_2", false, "ended=%d" % _ended.size())
	await _close()

	# Q5: alone there is nobody to stand you up, so death is death (Player decides, package A).
	await _open()
	await _sleep(0.5)
	_hunt.get_player().apply_damage(9999.0, Vector3.ZERO)
	await _sleep(0.5)
	_check("solo_death_is_defeat", _ended.size() == 1 and _ended[0].outcome == HuntResult.Outcome.DEFEAT_DEATH and _downed.is_empty(),
		"ended=%d downed=%s" % [_ended.size(), _downed])
