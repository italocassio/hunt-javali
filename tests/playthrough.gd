extends Node
## tests/playthrough.tscn: a bot plays whole hunts (docs/arquitetura.md section 12).
## Horde scenarios H1-H4 (docs/horda.md section 14) and extras come after the contract ones.
## Scenarios: victory with real shots, crop defeat, death defeat, two boars killed in the same frame,
## whole herd killed in the same frame, abandon, defeat priority, hunt_ended exactly once.
##
## Run: tools/godot.sh --headless --fixed-fps 60 --path . res://tests/playthrough.tscn [-- --strict]

const TestCase := preload("res://tests/lib/test_case.gd")
const HuntBot := preload("res://tests/bot/hunt_bot.gd")

const WATCHDOG_REAL_S: float = 300.0
const TIME_SCALE: float = 4.0
const VICTORY_TIMEOUT_S: float = 900.0   # hunt time
const CROP_DEFEAT_TIMEOUT_S: float = 400.0
const SEED: int = 12345

var _t: RefCounted
var _totals: Dictionary = {}
var _strict: bool = false
var _start_ms: int = 0
var _finished: bool = false

var _hunt: HuntController = null
var _ended: Array[HuntResult] = []
var _started: int = 0
var _counts: Array[Vector2i] = []
var _kills: Array[KillInfo] = []
var _hits: int = 0
var _conns: Array[Array] = []
var _horde_log: Array[Array] = []   # ["changed", wave, count, phase, countdown] / ["progress", remaining, total] / ["counts", killed, total]
var _states: Array[Array] = []      # [boar_id, state] of every boar_state_changed


func _ready() -> void:
	_strict = "--strict" in OS.get_cmdline_user_args()
	_start_ms = Time.get_ticks_msec()
	TestCase.install_catcher()
	_totals = TestCase.new_totals()
	_t = TestCase.new()
	_t.set("host", self)
	_t.set("strict", _strict)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _finished and float(Time.get_ticks_msec() - _start_ms) / 1000.0 > WATCHDOG_REAL_S:
		_finished = true
		print("FAIL watchdog: playthrough excedeu %d s reais" % int(WATCHDOG_REAL_S))
		_totals["fail"] = int(_totals["fail"]) + 1
		_quit()


func _quit() -> void:
	Engine.time_scale = 1.0
	var code: int = TestCase.finish(_totals)
	TestCase.remove_catcher()
	get_tree().quit(code)


func _run() -> void:
	await get_tree().process_frame
	_t.call("cleanup_test_files")
	await _case("victory_contract_0_with_real_shots", _scn_victory)
	await _case("defeat_crop_destroyed", _scn_defeat_crop)
	await _case("defeat_player_death", _scn_defeat_death)
	await _case("two_boars_killed_same_frame", _scn_double_kill)
	await _case("whole_herd_killed_same_frame_one_victory", _scn_herd_same_frame)
	await _case("abandon_ends_once", _scn_abandon)
	await _case("death_has_priority_over_crop", _scn_priority)
	await _case("force_end_is_idempotent", _scn_force_end)
	for weapon_id: StringName in [&"shotgun_12", &"rifle_308", &"rifle_3006", &"rifle_338"]:
		await _case("victory_with_%s" % weapon_id, _scn_weapon.bind(weapon_id))
	await _case("contract_keeps_finite_reserve_and_no_horde_signals", _scn_contract_reserve_still_spent)
	await _case("horde_h1_victory_all_waves_real_shot_and_debug_kills", _scn_horde_victory)
	await _case("horde_h2_barn_eaten_defeat_crop", _scn_horde_defeat_crop)
	await _case("horde_h4_reserve_constant_after_reloads_all_weapons", _scn_horde_reserve_constant)
	await _case("horde_wave_cleared_same_frame_once", _scn_horde_wave_cleared_same_frame)
	await _case("horde_debug_skip_guards_and_natural_countdown", _scn_horde_skip_guards)
	await _case("horde_death_and_abandon", _scn_horde_death_and_abandon)
	await _case("contract_after_horde_has_no_leftovers", _scn_contract_after_horde)
	_t.call("cleanup_test_files")
	if not _finished:
		_finished = true
		_quit()


func _case(label: String, fn: Callable) -> void:
	if _finished:
		return
	_t.call("begin")
	await fn.call()
	await _close()
	_t.call("conclude", label, _totals)


# --------------------------------------------------------------------------------------------
# Hunt plumbing
# --------------------------------------------------------------------------------------------

func _connect(sig: Signal, handler: Callable) -> void:
	sig.connect(handler)
	_conns.append([sig, handler])


func _open(contract_index: int = 0, weapon_id: StringName = &"", mode: StringName = Ids.MODE_CONTRACT) -> bool:
	_t.call("fresh_profile")
	if weapon_id != &"":
		Profile.add_money(50000)
		Profile.add_gold(1000)
		var bought: StringName = Profile.buy(weapon_id)
		if bought != &"ok" and bought != &"already_owned":
			_t.call("fail", "nao consegui comprar %s: %s" % [weapon_id, bought])
		if not Profile.set_loadout_weapon(0, weapon_id):
			_t.call("fail", "nao consegui equipar %s no slot 0" % weapon_id)
		if not Profile.set_loadout_weapon(1, &""):
			pass
	_ended.clear()
	_counts.clear()
	_kills.clear()
	_started = 0
	_hits = 0
	_connect(GameEvents.hunt_started, func(_r: HuntRequest) -> void: _started += 1)
	_connect(GameEvents.hunt_ended, func(r: HuntResult) -> void: _ended.append(r))
	_connect(GameEvents.boar_counts_changed, func(k: int, total: int) -> void:
		_counts.append(Vector2i(k, total))
		_horde_log.append(["counts", k, total]))
	_horde_log.clear()
	_states.clear()
	_connect(GameEvents.boar_state_changed, func(id: int, st: StringName) -> void: _states.append([id, st]))
	_connect(GameEvents.horde_wave_changed, func(w: int, n: int, ph: StringName, cd: float) -> void: _horde_log.append(["changed", w, n, ph, cd]))
	_connect(GameEvents.horde_wave_progress, func(rem: int, tot: int) -> void: _horde_log.append(["progress", rem, tot]))
	_connect(GameEvents.boar_killed, func(k: KillInfo) -> void: _kills.append(k))
	_connect(GameEvents.boar_hit, func(_id: int, _z: StringName, _d: float, _p: Vector3, _s: int) -> void: _hits += 1)
	var req: HuntRequest = Profile.build_hunt_request(&"mato_grosso", contract_index)
	if mode == Ids.MODE_HORDE:
		req = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE)   # all weapons, loadout ignored
	req.rng_seed = SEED
	req.quality = Ids.Q_LOW
	Router.set_pending_request(req)
	var packed: PackedScene = load(ScenePaths.HUNT) as PackedScene
	_hunt = packed.instantiate() as HuntController
	if _hunt == null:
		_t.call("fail", "hunt.tscn nao instanciou HuntController")
		return false
	_hunt.route_on_finish = false
	add_child(_hunt)
	var t0: int = Time.get_ticks_msec()
	while not _hunt.is_world_ready():
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 60000:
			_t.call("fail", "mundo nao ficou pronto em 60 s")
			return false
	Engine.time_scale = TIME_SCALE
	return true


func _close() -> void:
	for c: Array in _conns:
		var sig: Signal = c[0]
		if sig.is_connected(c[1]):
			sig.disconnect(c[1])
	_conns.clear()
	if _hunt != null and is_instance_valid(_hunt):
		_hunt.queue_free()
	_hunt = null
	Router.set_pending_request(null)
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await get_tree().process_frame


func _sleep(seconds: float) -> void:
	var limit: float = _hunt.get_elapsed_s() + seconds
	while _hunt.get_elapsed_s() < limit:
		await get_tree().process_frame


func _wait_until(cond: Callable, max_s: float) -> bool:
	var limit: float = _hunt.get_elapsed_s() + max_s
	while _hunt.get_elapsed_s() < limit:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _park() -> void:
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	p.bot_teleport(Vector3(-118.0, _hunt.get_height(-118.0, -118.0) + 0.1, -118.0))


func _check_result_coherent(r: HuntResult, label: String) -> void:
	_t.call("eq", r.total_money, r.money_from_kills + r.contract_bonus, "%s: total_money = kills + bonus" % label)
	var sum: int = 0
	for k: KillInfo in r.kills:
		sum += k.reward_money
	_t.call("eq", r.money_from_kills, sum, "%s: money_from_kills = soma das recompensas" % label)
	_t.call("eq", r.map_id, &"mato_grosso", "%s: map_id" % label)
	_t.call("eq", r.contract_index, 0, "%s: contract_index" % label)
	_t.call("ok", r.crop_health_pct >= 0.0 and r.crop_health_pct <= 100.0, "%s: crop_health_pct em [0,100]: %s" % [label, r.crop_health_pct])
	_t.call("ok", r.duration_s > 0.0, "%s: duration_s > 0" % label)
	_t.call("ok", r.shots_hit <= r.shots_fired, "%s: shots_hit (%d) <= shots_fired (%d)" % [label, r.shots_hit, r.shots_fired])
	var ids: Dictionary = {}
	for k: KillInfo in r.kills:
		_t.call("ok", not ids.has(k.boar_id), "%s: abate duplicado do javali %d" % [label, k.boar_id])
		ids[k.boar_id] = true


# --------------------------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------------------------

func _scn_victory() -> void:
	if not await _open(0):
		return
	var bot: RefCounted = HuntBot.new()
	bot.call("setup", self, _hunt)
	var done: bool = await bot.call("kill_all", VICTORY_TIMEOUT_S)
	await _sleep(2.0)   # extra time: hunt_ended must not repeat
	var total: int = _hunt.get_boars_total()
	var pl: PlayerBase = _hunt.get_player()
	print("INFO victory: hunt_time=%.1f s, bot_shots=%d, reloads=%d, teleports=%d, killed=%d/%d, hits=%d, player_health=%.0f/%.0f, crop=%.1f%%, ammo mag=%d reserve=%d" % [
		_hunt.get_elapsed_s(), int(bot.get("shots_fired")), int(bot.get("reloads")), int(bot.get("teleports")),
		_hunt.get_boars_killed(), total, _hits, pl.get_health(), pl.get_max_health(), _hunt.get_crop_health_pct(),
		pl.get_ammo_in_mag(), pl.get_ammo_reserve()])
	_t.call("ok", done and _hunt.is_hunt_over(), "bot nao terminou a caçada (killed %d/%d, ammo mag=%d reserva=%d)" % [
		_hunt.get_boars_killed(), total, _hunt.get_player().get_ammo_in_mag(), _hunt.get_player().get_ammo_reserve()])
	_t.call("eq", _started, 1, "hunt_started 1x")
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_t.call("eq", r.outcome, HuntResult.Outcome.VICTORY, "outcome")
	_t.call("eq", r.kills.size(), total, "kills.size() == boars_total")
	_t.call("eq", r.boars_total, total, "result.boars_total")
	_t.call("eq", _hunt.get_boars_killed(), total, "get_boars_killed")
	_t.call("eq", _kills.size(), total, "sinais boar_killed")
	_t.call("ok", r.contract_bonus > 0, "bonus de contrato > 0 na vitoria")
	_t.call("ok", r.money_from_kills > 0, "dinheiro dos abates > 0")
	_t.call("ok", int(bot.get("shots_fired")) >= 1 and r.shots_fired >= 1, "ao menos 1 tiro real")
	_t.call("ok", r.shots_hit >= 1, "ao menos 1 acerto real (shots_hit=%d)" % r.shots_hit)
	_t.call("ok", _hunt.get_result() == r, "get_result() == resultado do sinal")
	_t.call("eq", _counts[-1] if not _counts.is_empty() else Vector2i(-1, -1), Vector2i(total, total), "ultimo boar_counts_changed")
	_check_result_coherent(r, "vitoria")
	# Applying the result to the profile pays the money exactly once.
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	_t.call("eq", Profile.get_money(), money0 + r.total_money, "Profile.apply_hunt_result paga total_money")
	_t.call("ok", Profile.is_contract_unlocked(&"mato_grosso", 1), "contrato 1 desbloqueado apos vitoria")


func _scn_defeat_crop() -> void:
	if not await _open(0):
		return
	_park()
	# Real defeat clock: let the herd eat for 30 s, then speed up.
	await _sleep(30.0)
	var h_mid: float = _hunt.get_crop_health_pct()
	_hunt.debug_set_crop_health(5.0)
	var ended: bool = await _wait_until(func() -> bool: return _hunt.is_hunt_over(), CROP_DEFEAT_TIMEOUT_S)
	await _sleep(2.0)
	print("INFO crop defeat: crop at 30 s = %.1f%%, ended=%s at t=%.1f" % [h_mid, ended, _hunt.get_elapsed_s()])
	_t.call("ok", ended, "lavoura nao foi destruida pelo bando")
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_t.call("eq", r.outcome, HuntResult.Outcome.DEFEAT_CROP, "outcome")
	_t.call("eq", r.contract_bonus, 0, "sem bonus na derrota")
	_t.call("near", r.crop_health_pct, 0.0, 0.001, "crop_health_pct no resultado")
	_t.call("eq", r.kills.size(), _hunt.get_boars_killed(), "kills.size() == killed")
	_check_result_coherent(r, "derrota lavoura")
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	_t.call("eq", Profile.get_money(), money0 + r.total_money, "dinheiro da derrota = so abates (total_money)")
	_t.call("ok", not Profile.is_contract_completed(&"mato_grosso", 0), "contrato 0 nao concluido na derrota")


func _scn_defeat_death() -> void:
	if not await _open(0):
		return
	_park()
	await _sleep(1.0)
	var p: PlayerBase = _hunt.get_player()
	p.apply_damage(9999.0, Vector3.ZERO)
	await _sleep(1.0)
	_t.call("ok", not p.is_alive(), "jogador deveria estar morto")
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	if _ended.is_empty():
		return
	_t.call("eq", _ended[0].outcome, HuntResult.Outcome.DEFEAT_DEATH, "outcome")
	_t.call("eq", _ended[0].contract_bonus, 0, "sem bonus")
	# Dead hunter: further damage and fire do not end the hunt again nor shoot.
	p.apply_damage(50.0, Vector3.ZERO)
	_t.call("eq", p.bot_fire(), false, "jogador morto nao atira")
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended continua 1x depois de dano extra")
	_check_result_coherent(_ended[0], "derrota morte")


func _scn_double_kill() -> void:
	if not await _open(0):
		return
	_park()
	var got: bool = await _wait_until(func() -> bool: return _hunt.get_alive_boar_ids().size() >= 3, 60.0)
	_t.call("ok", got, "menos de 3 javalis vivos em 60 s")
	if not got:
		return
	var ids: PackedInt32Array = _hunt.get_alive_boar_ids().duplicate()
	var before: int = _hunt.get_boars_killed()
	_hunt.debug_kill_boar(ids[0])
	_hunt.debug_kill_boar(ids[1])
	_hunt.debug_kill_boar(ids[1])   # repeated: must not count twice
	_hunt.debug_kill_boar(ids[0])
	_t.call("eq", _hunt.get_boars_killed(), before + 2, "dois abates no mesmo frame, repeticao ignorada")
	_t.call("eq", _kills.size(), 2, "boar_killed emitido 2x")
	_t.call("eq", _counts[-1].x if not _counts.is_empty() else -1, before + 2, "boar_counts_changed refletiu 2 abates")
	_t.call("eq", _hunt.get_alive_boar_ids().size(), ids.size() - 2, "vivos diminuiu em 2 (no mesmo frame)")
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 0, "caçada nao termina com 2 abates")
	_t.call("ok", not _hunt.get_alive_boar_ids().has(ids[0]) and not _hunt.get_alive_boar_ids().has(ids[1]), "mortos fora da lista de vivos")
	# Killing a boar id that never existed or is already dead is harmless.
	_hunt.debug_kill_boar(99999)
	_hunt.debug_kill_boar(-1)
	_t.call("eq", _hunt.get_boars_killed(), before + 2, "id invalido ignorado")


func _scn_herd_same_frame() -> void:
	if not await _open(0):
		return
	_park()
	var total: int = _hunt.get_boars_total()
	var got: bool = await _wait_until(func() -> bool: return _hunt.get_alive_boar_ids().size() >= total, 80.0)
	_t.call("ok", got, "nem todos os %d javalis apareceram em 80 s" % total)
	if not got:
		return
	var ids: PackedInt32Array = _hunt.get_alive_boar_ids().duplicate()
	for id: int in ids:
		_hunt.debug_kill_boar(id)
	for id: int in ids:
		_hunt.debug_kill_boar(id)   # second pass in the same frame
	await _sleep(2.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x com o bando inteiro morto no mesmo frame")
	_t.call("eq", _hunt.get_boars_killed(), total, "killed == total")
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_t.call("eq", r.outcome, HuntResult.Outcome.VICTORY, "outcome")
	_t.call("eq", r.kills.size(), total, "kills.size() == total")
	_check_result_coherent(r, "bando inteiro")


func _scn_abandon() -> void:
	if not await _open(0):
		return
	_park()
	await _sleep(1.0)
	GameEvents.hunt_abandon_requested.emit()
	GameEvents.hunt_abandon_requested.emit()
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	if not _ended.is_empty():
		_t.call("eq", _ended[0].outcome, HuntResult.Outcome.ABANDONED, "outcome")
		_t.call("eq", _ended[0].contract_bonus, 0, "sem bonus")
		var money0: int = Profile.get_money()
		Profile.apply_hunt_result(_ended[0])
		_t.call("eq", Profile.get_money(), money0 + _ended[0].total_money, "abandono: so abates pagos")


func _scn_priority() -> void:
	if not await _open(0):
		return
	_park()
	await _sleep(1.0)
	_hunt.get_player().apply_damage(9999.0, Vector3.ZERO)
	_hunt.debug_set_crop_health(0.0)
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	if not _ended.is_empty():
		_t.call("eq", _ended[0].outcome, HuntResult.Outcome.DEFEAT_DEATH, "morte tem prioridade sobre lavoura")


func _scn_force_end() -> void:
	if not await _open(0):
		return
	_park()
	await _sleep(1.0)
	_t.call("eq", _hunt.is_hunt_over(), false, "is_hunt_over false antes do fim")
	_t.call("eq", _hunt.get_result() == null, true, "get_result null antes do fim")
	_hunt.debug_force_end(HuntResult.Outcome.VICTORY)
	_hunt.debug_force_end(HuntResult.Outcome.DEFEAT_CROP)
	_hunt.debug_force_end(HuntResult.Outcome.DEFEAT_DEATH)
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	_t.call("eq", _hunt.is_hunt_over(), true, "is_hunt_over true")
	if not _ended.is_empty():
		_t.call("eq", _ended[0].outcome, HuntResult.Outcome.VICTORY, "primeiro fim vence")
		_t.call("ok", _ended[0].contract_bonus > 0, "bonus pago na vitoria forcada")


func _scn_weapon(weapon_id: StringName) -> void:
	if not await _open(0, weapon_id):
		return
	var p: PlayerBase = _hunt.get_player()
	_t.call("eq", p.get_current_weapon_id(), weapon_id, "arma equipada no inicio")
	var bot: RefCounted = HuntBot.new()
	bot.call("setup", self, _hunt)
	var done: bool = await bot.call("kill_all", VICTORY_TIMEOUT_S)
	await _sleep(1.0)
	print("INFO %s: hunt_time=%.1f s, shots=%d, reloads=%d, killed=%d/%d, ammo mag=%d reserva=%d" % [weapon_id,
		_hunt.get_elapsed_s(), int(bot.get("shots_fired")), int(bot.get("reloads")), _hunt.get_boars_killed(),
		_hunt.get_boars_total(), p.get_ammo_in_mag(), p.get_ammo_reserve()])
	_t.call("ok", done and _hunt.is_hunt_over(), "bot nao venceu com %s (killed %d/%d)" % [weapon_id, _hunt.get_boars_killed(), _hunt.get_boars_total()])
	_t.call("eq", _ended.size(), 1, "hunt_ended 1x")
	if not _ended.is_empty():
		_t.call("eq", _ended[0].outcome, HuntResult.Outcome.VICTORY, "outcome")
		_t.call("ok", _ended[0].shots_hit >= 1, "ao menos 1 acerto (shots_hit=%d)" % _ended[0].shots_hit)
		_check_result_coherent(_ended[0], "vitoria com %s" % weapon_id)


# --------------------------------------------------------------------------------------------
# Horde mode (docs/horda.md section 14, qa-tester): H1 victory, H2 barn eaten, H3 no wander/flee, H4 constant
# reserve; plus same-frame wave clear, death, abandon and the guards of debug_horde_start_next_wave.
# --------------------------------------------------------------------------------------------

func _kill_alive_all() -> void:
	for id: int in _hunt.get_alive_boar_ids().duplicate():
		_hunt.debug_kill_boar(id)


## Kills every boar of the running wave (debug) until `wave` is cleared or the hunt ends.
func _clear_wave_debug(wave: int, timeout_s: float) -> bool:
	var limit: float = _hunt.get_elapsed_s() + timeout_s
	while _hunt.get_elapsed_s() < limit and not _hunt.is_hunt_over() and _hunt.get_horde_waves_cleared() < wave:
		_kill_alive_all()
		await get_tree().process_frame
	return _hunt.get_horde_waves_cleared() >= wave or _hunt.is_hunt_over()


func _wander_or_flee_count() -> int:
	var n: int = 0
	for s: Array in _states:
		if s[1] == &"wander" or s[1] == &"flee":
			n += 1
	return n


func _states_seen(state: StringName) -> int:
	var n: int = 0
	for s: Array in _states:
		if s[1] == state:
			n += 1
	return n


func _changed_log() -> Array:
	var out: Array = []
	for e: Array in _horde_log:
		if e[0] == "changed":
			out.append(e)
	return out


func _visible_carcasses() -> int:
	var n: int = 0
	for c: Variant in _hunt.get("_carcasses"):
		if is_instance_valid(c) and (c as Node3D).visible:
			n += 1
	return n


func _check_horde_result(r: HuntResult, label: String) -> void:
	_t.call("eq", r.mode, Ids.MODE_HORDE, "%s: result.mode" % label)
	_t.call("ok", r.is_horde(), "%s: result.is_horde()" % label)
	_t.call("eq", r.horde_wave_count, 8, "%s: horde_wave_count" % label)
	_t.call("ok", not r.counts_for_progression, "%s: counts_for_progression == false (inclusive offline)" % label)
	_t.call("eq", r.total_money, r.money_from_kills + r.contract_bonus, "%s: total = abates + bonus" % label)
	var sum: int = 0
	var ids: Dictionary = {}
	for k: KillInfo in r.kills:
		sum += k.reward_money
		_t.call("eq", k.reward_money, Profile.horde_kill_reward(k.type_id, k.weight_kg, k.killing_zone, k.one_shot), "%s: premio do javali %d = Profile.horde_kill_reward" % [label, k.boar_id])
		_t.call("ok", k.boar_id >= 1 and k.boar_id <= 255, "%s: id %d cabe em u8" % [label, k.boar_id])
		_t.call("ok", not ids.has(k.boar_id), "%s: abate duplicado %d" % [label, k.boar_id])
		ids[k.boar_id] = true
	_t.call("eq", r.money_from_kills, sum, "%s: money_from_kills = soma dos premios" % label)


func _scn_horde_victory() -> void:
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	var total: int = _hunt.get_boars_total()
	_t.call("eq", total, 85, "boars_total = 85 (solo, a partida inteira)")
	_t.call("eq", _hunt.get_mode(), Ids.MODE_HORDE, "get_mode")
	_t.call("ok", _hunt.crop.is_store_mode(), "CropManager em modo estoque")
	_t.call("eq", _hunt.get_horde_wave(), 1, "onda 1 anunciada")
	_t.call("eq", _hunt.get_horde_wave_count(), 8, "8 ondas")
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_INTERMISSION, "fase inicial: intervalo")
	_t.call("eq", _hunt.get_alive_boar_ids().size(), 0, "nenhum javali antes da onda 1")
	_t.call("eq", _hunt.get_horde_waves_cleared(), 0, "0 ondas vencidas")
	var first: Array = _changed_log()[0] if not _changed_log().is_empty() else []
	_t.call("ok", first.size() == 5 and first[1] == 1 and first[2] == 8 and first[3] == Ids.HP_INTERMISSION and absf(float(first[4]) - float(Data.get_horde()["first_wave_delay_s"])) < 0.5,
		"horde_wave_changed(1, 8, intermission, ~12) antes do 1o javali: %s" % str(first))
	# The wave-1 start, then real shots until it is cleared (at least 1 kill by a real bot shot).
	_hunt.debug_horde_start_next_wave()
	await _sleep(0.2)
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_WAVE, "onda 1 em curso")
	_t.call("eq", _hunt.get_horde_wave_total(), 4, "onda 1 tem 4 javalis")
	_t.call("eq", _hunt.get_horde_wave_remaining(), 4, "faltam 4")
	_t.call("eq", _hunt.get_horde_countdown_s(), 0.0, "contador 0 na fase onda")
	var bot: RefCounted = HuntBot.new()
	bot.call("setup", self, _hunt)
	var stop: Callable = func() -> bool: return _hunt.get_horde_waves_cleared() >= 1
	await bot.call("kill_all", 600.0, stop)
	var shots: int = int(bot.get("shots_fired"))
	print("INFO horde H1 onda 1: bot_shots=%d reloads=%d t=%.1f s" % [shots, int(bot.get("reloads")), _hunt.get_elapsed_s()])
	_t.call("ok", _hunt.get_horde_waves_cleared() >= 1 or _hunt.is_hunt_over(), "onda 1 nao foi vencida pelo bot (killed %d, vivos %d, fase %s)" % [_hunt.get_boars_killed(), _hunt.get_alive_boar_ids().size(), _hunt.get_horde_phase()])
	_t.call("ok", shots >= 1, "ao menos 1 abate por tiro real do bot (%d tiros)" % shots)
	_t.call("eq", _hunt.get_horde_waves_cleared(), 1, "1 onda vencida")
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_INTERMISSION, "volta ao intervalo")
	_t.call("eq", _hunt.get_horde_wave(), 2, "proxima onda anunciada: 2")
	_t.call("ok", _hunt.get_horde_countdown_s() > 0.0 and _hunt.get_horde_countdown_s() <= float(Data.get_horde()["intermission_s"]), "contador do intervalo (%.1f)" % _hunt.get_horde_countdown_s())
	_t.call("eq", _hunt.get_horde_wave_remaining(), 0, "intervalo: 0 faltando")
	bot.call("park_far")
	# Waves 2..8: skip the intermission and clear with debug kills.
	for w: int in range(2, 9):
		if _hunt.is_hunt_over():
			break
		_t.call("eq", _hunt.get_horde_phase(), Ids.HP_INTERMISSION, "onda %d: comeca no intervalo" % w)
		_t.call("eq", _hunt.get_horde_wave(), w, "onda %d anunciada" % w)
		if w == 8:
			_hunt.debug_set_crop_health(87.0)
		_hunt.debug_horde_start_next_wave()
		await get_tree().process_frame
		await get_tree().process_frame
		_t.call("eq", _hunt.get_horde_phase(), Ids.HP_WAVE, "onda %d em curso" % w)
		_t.call("eq", _hunt.get_horde_wave(), w, "onda %d: numero" % w)
		_t.call("ok", _hunt.get_horde_wave_total() > 0 and _hunt.get_horde_wave_remaining() <= _hunt.get_horde_wave_total(), "onda %d: total %d, faltam %d" % [w, _hunt.get_horde_wave_total(), _hunt.get_horde_wave_remaining()])
		var cleared: bool = await _clear_wave_debug(w, 200.0)
		_t.call("ok", cleared, "onda %d nao foi vencida (killed %d/%d)" % [w, _hunt.get_boars_killed(), total])
		_t.call("ok", _visible_carcasses() <= int(Data.get_horde()["max_carcasses"]), "onda %d: carcacas visiveis %d <= max_carcasses" % [w, _visible_carcasses()])
	await _sleep(2.0)   # hunt_ended must not repeat
	_t.call("ok", _hunt.is_hunt_over(), "caçada terminou depois da ultima onda")
	_t.call("eq", _started, 1, "hunt_started 1x")
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	_t.call("eq", _hunt.crop.get_patch_eaten(), 0, "nenhum canteiro comido em horda")
	_t.call("ok", _visible_carcasses() <= int(Data.get_horde()["max_carcasses"]), "carcacas visiveis no fim: %d" % _visible_carcasses())
	_t.call("eq", _hunt.get_boars_killed(), total, "killed == total")
	# H3: no wander and no flee state, ever, in a whole horde hunt.
	_t.call("eq", _wander_or_flee_count(), 0, "H3: nenhum boar_state_changed wander/flee em toda a horda (%d estados vistos)" % _states.size())
	_t.call("ok", _states_seen(&"to_crop") > 0, "H3: sanidade: javalis foram para o celeiro (to_crop)")
	# Wave signals: 8 wave starts + 7 intermissions + the opening one, in order.
	var changed: Array = _changed_log()
	_t.call("eq", changed.size(), 16, "horde_wave_changed: 1 + 8 + 7 emissoes (a onda 8 vencida nao emite)")
	# order: (1,I) (1,W) (2,I) (2,W) ... (8,I) (8,W)
	for i: int in mini(changed.size(), 16):
		var got: Array = [changed[i][1], changed[i][2], changed[i][3]]
		var exp: Array = [i / 2 + 1, 8, Ids.HP_INTERMISSION if i % 2 == 0 else Ids.HP_WAVE]
		_t.call("eq", got, exp, "transicao %d" % i)
	for e: Array in changed:
		if e[3] == Ids.HP_WAVE:
			_t.call("eq", float(e[4]), 0.0, "fase onda: contador 0")
		else:
			_t.call("ok", float(e[4]) > 0.0, "fase intervalo: contador > 0 (%s)" % str(e[4]))
	# horde_wave_progress comes AFTER the boar_counts_changed of the kill that caused it.
	var progress_after_kill: int = 0
	for i: int in _horde_log.size():
		var e: Array = _horde_log[i]
		if e[0] == "progress":
			if int(e[1]) == int(e[2]):
				_t.call("eq", _horde_log[i - 1][0], "changed", "progress(total,total) logo depois do horde_wave_changed da onda")
			else:
				progress_after_kill += 1
				_t.call("eq", _horde_log[i - 1][0], "counts", "progress depois do boar_counts_changed (entrada %d)" % i)
	_t.call("ok", progress_after_kill >= total - 8, "ao menos um progress por abate (%d de %d abates)" % [progress_after_kill, total])
	# Result
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_t.call("eq", r.outcome, HuntResult.Outcome.VICTORY, "outcome")
	_t.call("eq", r.horde_waves_cleared, 8, "horde_waves_cleared == horde_wave_count == 8")
	_t.call("eq", r.kills.size(), total, "kills.size() == boars_total")
	_t.call("eq", r.boars_total, total, "result.boars_total (partida inteira)")
	_t.call("eq", r.contract_bonus, Profile.horde_bonus(r.crop_health_pct), "contract_bonus == Profile.horde_bonus(crop_health_pct)")
	_t.call("ok", r.contract_bonus > 0, "bonus de defesa > 0")
	_t.call("ok", r.crop_health_pct > 0.0 and r.crop_health_pct <= 87.0 + 0.01, "estoque no fim <= 87%% (%.2f)" % r.crop_health_pct)
	_t.call("ok", r.shots_hit >= 1, "ao menos 1 acerto real")
	_check_horde_result(r, "H1")
	_check_result_coherent_horde(r, "H1")
	var money0: int = Profile.get_money()
	var unlocked0: int = Profile.get_unlocked_contract_count(&"mato_grosso")
	Profile.apply_hunt_result(r)
	_t.call("eq", Profile.get_money(), money0 + r.total_money, "Profile.apply_hunt_result paga total_money")
	_t.call("eq", Profile.get_unlocked_contract_count(&"mato_grosso"), unlocked0, "horda nao libera contrato")
	_t.call("ok", not Profile.is_contract_completed(&"mato_grosso", 0), "horda nao conclui o contrato 0")


func _check_result_coherent_horde(r: HuntResult, label: String) -> void:
	_t.call("eq", r.map_id, &"mato_grosso", "%s: map_id" % label)
	_t.call("ok", r.crop_health_pct >= 0.0 and r.crop_health_pct <= 100.0, "%s: estoque em [0,100]: %s" % [label, r.crop_health_pct])
	_t.call("ok", r.duration_s > 0.0, "%s: duration_s > 0" % label)
	_t.call("ok", r.shots_hit <= r.shots_fired, "%s: shots_hit <= shots_fired" % label)


func _scn_horde_defeat_crop() -> void:
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	_park()
	await _sleep(30.0)   # the first wave starts at 12 s and runs to the barn
	_t.call("ok", _hunt.get_horde_wave() >= 1, "onda anunciada")
	_hunt.debug_set_crop_health(5.0)
	var ended: bool = await _wait_until(func() -> bool: return _hunt.is_hunt_over(), CROP_DEFEAT_TIMEOUT_S)
	await _sleep(2.0)
	print("INFO horde H2: ended=%s at t=%.1f, ondas vencidas=%d, abates=%d" % [ended, _hunt.get_elapsed_s(), _hunt.get_horde_waves_cleared(), _hunt.get_boars_killed()])
	_t.call("ok", ended, "o estoque do celeiro nao foi devorado pelo bando")
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	_t.call("eq", _hunt.crop.get_patch_eaten(), 0, "nenhum canteiro comido (horda so drena o estoque)")
	_t.call("eq", _wander_or_flee_count(), 0, "H3: nenhum wander/flee durante a derrota")
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_t.call("eq", r.outcome, HuntResult.Outcome.DEFEAT_CROP, "outcome DEFEAT_CROP")
	_t.call("eq", r.contract_bonus, 0, "sem bonus de defesa na derrota")
	_t.call("near", r.crop_health_pct, 0.0, 0.001, "estoque 0 no resultado")
	_t.call("eq", r.horde_waves_cleared, _hunt.get_horde_waves_cleared(), "horde_waves_cleared = ondas vencidas ate o fim")
	_t.call("ok", r.horde_waves_cleared < 8, "nem todas as ondas vencidas")
	_check_horde_result(r, "H2")
	_check_result_coherent_horde(r, "H2")
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	_t.call("eq", Profile.get_money(), money0 + r.total_money, "derrota paga so os abates")
	_t.call("eq", int(Profile.get_stats().get("hunts_won", 0)), 0, "derrota nao conta vitoria")
	_t.call("ok", not Profile.is_contract_completed(&"mato_grosso", 0), "horda nao conclui contrato")


func _scn_horde_reserve_constant() -> void:
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	_park()
	var p: PlayerBase = _hunt.get_player()
	var ids: Array[StringName] = Data.get_weapon_ids()
	_t.call("eq", p.get_weapon_count(), ids.size(), "H4: todas as armas do arquivo")
	_t.call("ok", p.has_infinite_reserve(), "H4: has_infinite_reserve")
	for slot: int in ids.size():
		p.bot_select_weapon(slot)
		await _sleep(0.8)
		_t.call("eq", p.get_current_weapon_id(), ids[slot], "H4: slot %d = %s (ordem do arquivo)" % [slot, ids[slot]])
		var reserve0: int = p.get_ammo_reserve()
		_t.call("ok", reserve0 > 0, "H4: %s: reserva > 0 (%d)" % [ids[slot], reserve0])
		var reloads: int = 3 if slot == 0 else 1
		for n: int in reloads:
			# empty the magazine, then reload
			var tries: int = 0
			while p.get_ammo_in_mag() > 0 and tries < 400 and not _hunt.is_hunt_over():
				p.bot_fire()
				tries += 1
				await get_tree().process_frame
			_t.call("eq", p.get_ammo_in_mag(), 0, "H4: %s: pente esvaziado (%d tentativas)" % [ids[slot], tries])
			p.bot_reload()
			var done: bool = await _wait_until(func() -> bool: return not p.is_reloading() and p.get_ammo_in_mag() > 0, 30.0)
			_t.call("ok", done, "H4: %s: recarga %d terminou" % [ids[slot], n + 1])
			_t.call("eq", p.get_ammo_reserve(), reserve0, "H4: %s: reserva igual depois da recarga %d" % [ids[slot], n + 1])
			_t.call("eq", p.get_ammo_in_mag(), int(Data.get_weapon(ids[slot]).get("mag_size", 0)), "H4: %s: pente cheio" % ids[slot])
	_t.call("eq", _ended.size(), 0, "a caçada seguiu viva durante o teste de municao")


func _scn_contract_reserve_still_spent() -> void:
	## Contract regression: the reserve is consumed, only one weapon per loadout slot, no horde signal ever.
	if not await _open(0):
		return
	_park()
	var p: PlayerBase = _hunt.get_player()
	_t.call("ok", not p.has_infinite_reserve(), "contrato: reserva finita")
	_t.call("eq", p.get_weapon_count(), 1, "contrato: so a arma do loadout (carabina)")
	var reserve0: int = p.get_ammo_reserve()
	var tries: int = 0
	while p.get_ammo_in_mag() > 0 and tries < 400:
		p.bot_fire()
		tries += 1
		await get_tree().process_frame
	p.bot_reload()
	await _wait_until(func() -> bool: return not p.is_reloading(), 30.0)
	_t.call("ok", p.get_ammo_reserve() < reserve0, "contrato: a recarga gasta a reserva (%d -> %d)" % [reserve0, p.get_ammo_reserve()])
	# keys 3..5 do nothing in the contract
	var before: StringName = p.get_current_weapon_id()
	for action_name: String in ["weapon_3", "weapon_4", "weapon_5"]:
		Input.action_press(action_name)
		await _sleep(0.2)
		Input.action_release(action_name)
		await _sleep(0.1)
	_t.call("eq", p.get_current_weapon_id(), before, "contrato: teclas 3-5 nao trocam de arma")
	_t.call("eq", _hunt.get_mode(), Ids.MODE_CONTRACT, "contrato: get_mode")
	_t.call("ok", not _hunt.is_horde(), "contrato: is_horde falso")
	_t.call("eq", _hunt.get_horde_wave(), 0, "contrato: get_horde_wave 0")
	_t.call("eq", _hunt.get_horde_phase(), &"", "contrato: fase vazia")
	_t.call("ok", not _hunt.crop.is_store_mode(), "contrato: CropManager sem modo estoque")
	_t.call("eq", _horde_log.filter(func(e: Array) -> bool: return e[0] != "counts").size(), 0, "contrato: nenhum horde_wave_changed/progress emitido")


func _scn_horde_wave_cleared_same_frame() -> void:
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	_park()
	_hunt.debug_horde_start_next_wave()
	var got: bool = await _wait_until(func() -> bool: return _hunt.get_alive_boar_ids().size() >= 4, 60.0)
	_t.call("ok", got, "os 4 javalis da onda 1 nao apareceram em 60 s")
	if not got:
		return
	var n_changed: int = _changed_log().size()
	var ids: PackedInt32Array = _hunt.get_alive_boar_ids().duplicate()
	for id: int in ids:
		_hunt.debug_kill_boar(id)
	for id: int in ids:
		_hunt.debug_kill_boar(id)   # second pass, same frame
	await _sleep(1.0)
	_t.call("eq", _hunt.get_horde_waves_cleared(), 1, "onda 1 vencida exatamente uma vez")
	_t.call("eq", _hunt.get_horde_wave(), 2, "onda 2 anunciada")
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_INTERMISSION, "intervalo")
	_t.call("eq", _changed_log().size(), n_changed + 1, "uma unica emissao (2, 8, intermission, 15)")
	var last: Array = _changed_log().back()
	_t.call("ok", last[1] == 2 and last[3] == Ids.HP_INTERMISSION and float(last[4]) > 0.0, "ultima emissao: %s" % str(last))
	var zero_remaining: int = 0
	for e: Array in _horde_log:
		if e[0] == "progress" and int(e[1]) == 0:
			zero_remaining += 1
	_t.call("eq", zero_remaining, 1, "horde_wave_progress(0, 4) uma unica vez")
	_t.call("eq", _hunt.get_boars_killed(), 4, "4 abates")
	_t.call("eq", _ended.size(), 0, "a caçada continua")
	# killing the dead again, or ids that never existed, changes nothing
	for id: int in ids:
		_hunt.debug_kill_boar(id)
	_hunt.debug_kill_boar(99999)
	await _sleep(0.5)
	_t.call("eq", _hunt.get_boars_killed(), 4, "repeticao ignorada")
	_t.call("eq", _hunt.get_horde_waves_cleared(), 1, "ainda 1 onda vencida")


func _scn_horde_skip_guards() -> void:
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	_park()
	_hunt.debug_horde_start_next_wave()
	_hunt.debug_horde_start_next_wave()   # same frame: still just one wave
	await get_tree().process_frame
	await get_tree().process_frame
	_t.call("eq", _hunt.get_horde_wave(), 1, "duas chamadas no mesmo frame iniciam so a onda 1")
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_WAVE, "fase onda")
	_hunt.debug_horde_start_next_wave()   # during a wave: nothing
	await _sleep(0.5)
	_t.call("eq", _hunt.get_horde_wave(), 1, "durante a onda a chamada nao faz nada")
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_WAVE, "continua na onda")
	var starts: int = 0
	for e: Array in _changed_log():
		if e[3] == Ids.HP_WAVE:
			starts += 1
	_t.call("eq", starts, 1, "uma unica largada de onda")
	# a very long wave start does not skip intermission twice: after clearing wave 1 the intermission has its full countdown
	await _clear_wave_debug(1, 120.0)
	_t.call("eq", _hunt.get_horde_phase(), Ids.HP_INTERMISSION, "intervalo depois da onda 1")
	_t.call("ok", _hunt.get_horde_countdown_s() > float(Data.get_horde()["intermission_s"]) - 2.0, "intervalo com o contador cheio (%.1f)" % _hunt.get_horde_countdown_s())
	# let the countdown run: the wave starts by itself (no debug)
	var waited: bool = await _wait_until(func() -> bool: return _hunt.get_horde_phase() == Ids.HP_WAVE, float(Data.get_horde()["intermission_s"]) + 5.0)
	_t.call("ok", waited, "o contador do intervalo termina e a onda 2 comeca sozinha")
	_t.call("eq", _hunt.get_horde_wave(), 2, "onda 2")


func _scn_horde_death_and_abandon() -> void:
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	_park()
	await _sleep(1.0)
	var p: PlayerBase = _hunt.get_player()
	p.apply_damage(9999.0, Vector3.ZERO)
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended exatamente 1x")
	if not _ended.is_empty():
		_t.call("eq", _ended[0].outcome, HuntResult.Outcome.DEFEAT_DEATH, "DEFEAT_DEATH")
		_t.call("eq", _ended[0].contract_bonus, 0, "sem bonus")
		_t.call("eq", _ended[0].horde_waves_cleared, 0, "0 ondas vencidas")
		_check_horde_result(_ended[0], "morte")
	# after the end the director is silent even if someone asks for the next wave
	var n: int = _horde_log.size()
	_hunt.debug_horde_start_next_wave()
	await _sleep(1.5)
	_t.call("eq", _horde_log.size(), n, "depois do fim nenhum sinal de onda")
	_t.call("eq", _ended.size(), 1, "hunt_ended continua 1x")
	await _close()
	# abandon
	if not await _open(0, &"", Ids.MODE_HORDE):
		return
	_park()
	await _sleep(1.0)
	GameEvents.hunt_abandon_requested.emit()
	GameEvents.hunt_abandon_requested.emit()
	await _sleep(1.0)
	_t.call("eq", _ended.size(), 1, "abandono: hunt_ended exatamente 1x")
	if not _ended.is_empty():
		_t.call("eq", _ended[0].outcome, HuntResult.Outcome.ABANDONED, "ABANDONED")
		_t.call("eq", _ended[0].contract_bonus, 0, "abandono: sem bonus")
		_check_horde_result(_ended[0], "abandono")
		var money0: int = Profile.get_money()
		Profile.apply_hunt_result(_ended[0])
		_t.call("eq", Profile.get_money(), money0 + _ended[0].total_money, "abandono: so abates pagos")


## A contract hunt right after the horde ones in the same process: nothing of the horde (store mode, director,
## carcass cap, barn, rewards) may leak into it.
func _scn_contract_after_horde() -> void:
	if not await _open(0):
		return
	_park()
	var total: int = _hunt.get_boars_total()
	_t.call("eq", total, 9, "contrato 0 tem 9 javalis (nao os 85 da horda)")
	_t.call("eq", _hunt.get_mode(), Ids.MODE_CONTRACT, "get_mode")
	_t.call("ok", not _hunt.crop.is_store_mode(), "sem modo estoque")
	_t.call("ok", not _hunt.get_objective_position().is_finite(), "sem objetivo (INF)")
	_t.call("ok", _hunt.find_child("BarnCorn", true, false) == null, "sem o visual do estoque de milho")
	_t.call("ok", _hunt.find_child("HordeDirector", true, false) == null, "sem HordeDirector")
	var got: bool = await _wait_until(func() -> bool: return _hunt.get_alive_boar_ids().size() >= total, 80.0)
	_t.call("ok", got, "os %d javalis do contrato apareceram" % total)
	_kill_alive_all()
	await _sleep(2.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended 1x")
	if _ended.is_empty():
		return
	var r: HuntResult = _ended[0]
	_t.call("eq", r.outcome, HuntResult.Outcome.VICTORY, "VICTORY")
	_t.call("eq", r.mode, Ids.MODE_CONTRACT, "result.mode contrato")
	_t.call("ok", r.counts_for_progression, "contrato conta para progressao")
	_t.call("eq", r.horde_wave_count, 0, "sem ondas")
	_t.call("eq", r.contract_bonus, Profile.contract_bonus(&"mato_grosso", 0, r.crop_health_pct), "bonus do contrato (nao o da horda)")
	for k: KillInfo in r.kills:
		_t.call("eq", k.reward_money, Profile.kill_reward(k.type_id, k.weight_kg, k.killing_zone, k.one_shot, &"mato_grosso", 0), "premio do contrato, nao o da horda")
	_t.call("eq", _horde_log.filter(func(e: Array) -> bool: return e[0] != "counts").size(), 0, "nenhum sinal de horda")
