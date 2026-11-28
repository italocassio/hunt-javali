extends Node
## Package B self-test of horde level 2 (docs/plano_horda_nivel2.md section 8, package B): runs hunt.tscn headless
## offline with HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, 2).
##   assembly  level 2, hunter born near the level's spawn, farm bounds, three ammo crates in the barn, route obstacles
##   crates    standing on a crate takes nothing; a press of interact takes it once (owner's Q4): it disappears, adds
##             ammo and comes back after respawn_s (needs Player.needs_ammo, package A)
##   sow       level 2 overrides on the boars; a sow 9 m from a standing hunter scrapes >= telegraph before charging
##   ends      DEFEAT_CROP and VICTORY results carry horde_level 2 and level 2 prizes; solo death = DEFEAT_DEATH
##   boss      wave 10 (docs/plano_horda_boss.md sections 2, 3.1 and 4.2): the Cachaco rei is the only boss of the
##             level, comes alone and first, announces itself with MSG_BOSS without stealing the dog's EV_MESSAGE
##             codes, and feeds GameEvents.horde_boss_health_changed: 100 at birth, falling (dog damage included,
##             which never passes through boar_hit), never rising, at most 4 Hz and a single 0 on its death.
##             The waves before it are cleared with debug kills, so this is the only permanent case that gets there.
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
## Boss of the last wave (docs/plano_horda_boss.md section 3.1).
const BOSS_WAVE: int = 10
const FF_TIME_SCALE: float = 8.0        # fast-forward of the waves before the boss (game clock only)
const WAVE_CLEAR_S: float = 180.0       # game time budget to clear one fast-forwarded wave
const BOSS_SPAWN_S: float = 25.0
const BOSS_TICK_S: float = 2.0          # game time budget for one 4 Hz tick of the boss health
const BOSS_DOG_BITES: int = 4
const BOSS_DOG_BITE: float = 400.0      # ~9% of the boss health per bite, so every bite shows on the bar
const BOSS_PCT_TOL: float = 0.02
const BOSS_RATE_TOL_S: float = 0.01
const BOSS_SCALE_MIN: float = 2.0       # ~2.125 by the plan (weight scale ~1.85 x body_scale_mult 1.15)
const BOSS_SCALE_MAX: float = 2.25
const BOSS_QUIET_S: float = 1.5         # watched after the death: a second 0 would show up here

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
var _boss_hp: Array[Array] = []          # [pct, hunt time] of every GameEvents.horde_boss_health_changed
var _messages: Array[String] = []        # text of every GameEvents.hud_message_requested
var _spawned: Array[Array] = []          # [boar_id, type_id] of every GameEvents.boar_spawned


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_cfg = Data.get_horde_level(LEVEL)
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	GameEvents.boar_state_changed.connect(_on_state)
	GameEvents.hunter_downed.connect(func(s: int) -> void: _downed.append(s))
	GameEvents.horde_boss_health_changed.connect(func(pct: float) -> void:
		_boss_hp.append([pct, _hunt.get_elapsed_s() if _hunt != null else 0.0]))
	GameEvents.hud_message_requested.connect(func(text: String, _s: float) -> void: _messages.append(text))
	GameEvents.boar_spawned.connect(func(id: int, type_id: StringName, _kg: float) -> void: _spawned.append([id, type_id]))
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	_check("level_2_data", not _cfg.is_empty() and int(_cfg.get("level", 0)) == LEVEL, "levels=%d" % Data.get_horde_level_count())
	var all: Dictionary = {"assembly": _test_assembly, "crates": _test_crates, "sow": _test_sow, "ends": _test_ends,
		"boss": _test_boss}
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
	_boss_hp.clear()
	_messages.clear()
	_spawned.clear()
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
	Engine.time_scale = 1.0
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


# --- Boss of the last wave -----------------------------------------------------------------------

## Waits game time without touching the barn's stock (used while the boss is the only thing happening).
func _wait_plain(seconds: float) -> void:
	var limit: float = _hunt.get_elapsed_s() + seconds
	while _hunt.get_elapsed_s() < limit:
		await get_tree().process_frame


## The living boss, or null.
func _find_boss() -> Boar:
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if b != null and b.type_id == Ids.BOSS and b.is_alive():
			return b
	return null


## Fast-forwards the horde: clears waves 1..wave-1 with debug kills (the only mechanism there is) and leaves the
## hunt in the intermission before `wave`, which the caller releases with debug_horde_start_next_wave().
## The barn's stock is kept up: this is about reaching the wave, not about the crop.
func _reach_wave(wave: int) -> bool:
	Engine.time_scale = FF_TIME_SCALE
	for w: int in range(1, wave):
		_hunt.debug_horde_start_next_wave()
		await get_tree().process_frame
		var limit: float = _hunt.get_elapsed_s() + WAVE_CLEAR_S
		while _hunt.get_elapsed_s() < limit and not _hunt.is_hunt_over() and _hunt.get_horde_waves_cleared() < w:
			for id: int in _hunt.get_alive_boar_ids().duplicate():
				_hunt.debug_kill_boar(id)
			if _hunt.get_crop_health_pct() < STOCK_RESET_BELOW:
				_hunt.debug_set_crop_health(100.0)
			await get_tree().process_frame
		if _hunt.is_hunt_over() or _hunt.get_horde_waves_cleared() < w:
			Engine.time_scale = 1.0
			return false
	Engine.time_scale = 1.0
	await get_tree().process_frame            # the director puts the next wave in intermission
	_hunt.debug_set_crop_health(100.0)
	return _hunt.get_horde_wave() == wave and _hunt.get_horde_phase() == Ids.HP_INTERMISSION


## docs/plano_horda_boss.md sections 2, 3.1, 4.2 items 1, 4 and 6.
func _test_boss() -> void:
	# 1. Data (no hunt needed): the last wave opens with the only boss of the level, alone and with no delay.
	var waves: Array = _cfg.get("waves", [])
	var bosses: int = 0
	var alphas: int = 0
	for w: Variant in waves:
		for g: Variant in (w as Dictionary).get("groups", []):
			for m: Variant in (g as Dictionary).get("members", []):
				if StringName(String(m)) == Ids.BOSS:
					bosses += 1
				elif StringName(String(m)) == Ids.ALPHA:
					alphas += 1
	var last_groups: Array = (waves[waves.size() - 1] as Dictionary).get("groups", []) if not waves.is_empty() else []
	var lead: Array = (last_groups[0] as Dictionary).get("members", []) if not last_groups.is_empty() else []
	_check("wave_10_opens_with_the_only_boss", waves.size() == BOSS_WAVE and bosses == 1 and alphas == 2
		and lead.size() == 1 and StringName(String(lead[0])) == Ids.BOSS
		and is_zero_approx(float((last_groups[0] as Dictionary).get("delay_s", -1.0))),
		"waves=%d boss=%d alpha=%d lead=%s" % [waves.size(), bosses, alphas, str(lead)])
	# The boss announcement takes the first free EV_MESSAGE code; 3..5 stay empty here and fall back to Dog.MESSAGES.
	var holes_free: bool = true
	for code: int in Dog.MESSAGES.keys():
		holes_free = holes_free and code < HuntController.NET_MESSAGES.size() and HuntController.NET_MESSAGES[code].is_empty()
	_check("boss_message_code_does_not_steal_the_dog", HuntController.NET_MSG_BOSS == 6 and holes_free
		and HuntController.NET_MESSAGES.size() > HuntController.NET_MSG_BOSS
		and HuntController.NET_MESSAGES[HuntController.NET_MSG_BOSS] == HuntController.MSG_BOSS
		and String(Dog.MESSAGES[Dog.NET_MSG_NO_BOAR]) == "O cão não farejou nenhum javali por perto.",
		"codes=%s" % str(HuntController.NET_MESSAGES))

	# 2. A real hunt, fast-forwarded to wave 10.
	await _open()
	await _park_safe()
	var reached: bool = await _reach_wave(BOSS_WAVE)
	_check("fast_forward_reached_wave_10", reached, "wave=%d phase=%s cleared=%d killed=%d/%d over=%s" % [_hunt.get_horde_wave(),
		_hunt.get_horde_phase(), _hunt.get_horde_waves_cleared(), _hunt.get_boars_killed(), _hunt.get_boars_total(),
		_hunt.is_hunt_over()])
	if not reached:
		return
	_boss_hp.clear()
	_messages.clear()
	_spawned.clear()
	# The roar is lazily synthesized: Sfx caches boar_boss_roar the first time anything plays it, and in a hunt the
	# only caller is Boar.start() of the boss (docs/plano_horda_boss.md section 4.4).
	var roar_cached_before: bool = (Sfx.get(&"_streams") as Dictionary).has(&"boar_boss_roar")
	_hunt.debug_horde_start_next_wave()
	var born: bool = await _wait(func() -> bool: return _find_boss() != null, BOSS_SPAWN_S)
	var boss: Boar = _find_boss()
	_check("boss_born_in_wave_10", born and boss != null and boss.wave == BOSS_WAVE - 1,
		"wave=%d spawned=%s" % [boss.wave if boss != null else -99, str(_spawned.slice(0, 3))])
	if boss == null:
		return
	_check("boss_is_the_first_boar_of_wave_10", not _spawned.is_empty() and _spawned[0][1] == Ids.BOSS,
		"spawned=%s" % str(_spawned.slice(0, 3)))
	_check("boss_entry_message", _messages.has(HuntController.MSG_BOSS) and not _messages.has(HuntController.MSG_ALPHA),
		"messages=%s" % str(_messages))
	var roar: Variant = (Sfx.get(&"_streams") as Dictionary).get(&"boar_boss_roar")
	var on_a_player: bool = false
	for child: Node in Sfx.get_children():
		if child is AudioStreamPlayer3D and (child as AudioStreamPlayer3D).stream == roar and roar != null:
			on_a_player = true
	_check("boss_roar_was_played", not roar_cached_before and roar is AudioStream and Sfx.has_sound(&"boar_boss_roar"),
		"cached before=%s stream=%s num player 3D=%s" % [roar_cached_before, roar, on_a_player])
	var def: Dictionary = Data.get_horde_boar_type(Ids.BOSS, LEVEL)
	var scale_want: float = BoarVisualBase.scale_for_weight(boss.weight_kg) * float(def.get("body_scale_mult", 1.0))
	_check("boss_body_scale_from_body_scale_mult", is_equal_approx(boss.body_scale, scale_want)
		and boss.body_scale >= BOSS_SCALE_MIN and boss.body_scale <= BOSS_SCALE_MAX,
		"scale=%.3f want=%.3f radius=%.3f m kg=%.1f" % [boss.body_scale, scale_want, boss.body_scale * Boar.BODY_RADIUS_M, boss.weight_kg])
	_check("boss_health_from_data", is_equal_approx(boss.max_health, boss.weight_kg * float(def["health_per_kg"]))
		and boss.max_health >= float(def["weight_min_kg"]) * float(def["health_per_kg"]),
		"max_health=%.0f kg=%.1f" % [boss.max_health, boss.weight_kg])
	_check("boss_bar_starts_full", not _boss_hp.is_empty() and is_equal_approx(float(_boss_hp[0][0]), 100.0),
		"first=%s" % str(_boss_hp.slice(0, 2)))
	if _boss_hp.is_empty():
		return

	# 3. Dog damage: the path that never passes through boar_hit, so the bar can only come from the host's pct.
	var boss_id: int = boss.boar_id
	var falls: int = 0
	for i: int in BOSS_DOG_BITES:
		var before: int = _boss_hp.size()
		var pct_before: float = float(_boss_hp[_boss_hp.size() - 1][0])
		boss.apply_dog_damage(BOSS_DOG_BITE)
		if await _wait(func() -> bool: return _boss_hp.size() > before, BOSS_TICK_S):
			if float(_boss_hp[_boss_hp.size() - 1][0]) < pct_before:
				falls += 1
	_check("dog_damage_lowers_the_boss_bar", falls == BOSS_DOG_BITES,
		"%d of %d bites of %.0f showed up; pct now %.1f, health %.0f/%.0f" % [falls, BOSS_DOG_BITES, BOSS_DOG_BITE,
		float(_boss_hp[_boss_hp.size() - 1][0]), boss.health, boss.max_health])

	# 4. Death: exactly one 0, and no further emission after it.
	var ticks_alive: int = _boss_hp.size()
	boss.apply_dog_damage(boss.max_health * 2.0)
	await _wait(func() -> bool: return not _hunt.get_alive_boar_ids().has(boss_id), BOSS_TICK_S)
	var at_death: int = _boss_hp.size()
	await _wait_plain(BOSS_QUIET_S)
	var zeros: int = 0
	var rises: Array = []
	var too_fast: Array = []
	for i: int in _boss_hp.size():
		var pct: float = float(_boss_hp[i][0])
		if is_zero_approx(pct):
			zeros += 1
		if i == 0:
			continue
		if pct > float(_boss_hp[i - 1][0]) + BOSS_PCT_TOL:
			rises.append([i, float(_boss_hp[i - 1][0]), pct])
		# The 0 of the death is not a 4 Hz tick (it comes from _boss_gone), so the rate only covers the live ticks.
		var gap: float = float(_boss_hp[i][1]) - float(_boss_hp[i - 1][1])
		if not is_zero_approx(pct) and gap < HuntController.BOSS_HP_INTERVAL_S - BOSS_RATE_TOL_S:
			too_fast.append([i, gap])
	_check("boss_bar_one_single_zero_on_death", zeros == 1 and _boss_hp.size() == at_death
		and is_zero_approx(float(_boss_hp[_boss_hp.size() - 1][0])),
		"emissions=%d (alive %d, at death %d) zeros=%d last=%.1f" % [_boss_hp.size(), ticks_alive, at_death, zeros,
		float(_boss_hp[_boss_hp.size() - 1][0])])
	_check("boss_bar_never_rises", rises.is_empty(), str(rises.slice(0, 5)))
	_check("boss_bar_at_most_4_hz", too_fast.is_empty(), "interval=%.2f s violations=%s" % [HuntController.BOSS_HP_INTERVAL_S,
		str(too_fast.slice(0, 5))])
	print("INFO boss: %d emissoes, de %.1f%% a %.1f%% em %.2f s de caçada" % [_boss_hp.size(), float(_boss_hp[0][0]),
		float(_boss_hp[_boss_hp.size() - 1][0]), float(_boss_hp[_boss_hp.size() - 1][1]) - float(_boss_hp[0][1])])
