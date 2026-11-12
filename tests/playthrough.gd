extends Node
## tests/playthrough.tscn: a bot plays whole hunts (docs/arquitetura.md section 12).
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


func _open(contract_index: int = 0, weapon_id: StringName = &"") -> bool:
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
	_connect(GameEvents.boar_counts_changed, func(k: int, total: int) -> void: _counts.append(Vector2i(k, total)))
	_connect(GameEvents.boar_killed, func(k: KillInfo) -> void: _kills.append(k))
	_connect(GameEvents.boar_hit, func(_id: int, _z: StringName, _d: float, _p: Vector3, _s: int) -> void: _hits += 1)
	var req: HuntRequest = Profile.build_hunt_request(&"mato_grosso", contract_index)
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
	print("INFO victory: hunt_time=%.1f s, bot_shots=%d, reloads=%d, teleports=%d, killed=%d/%d, hits=%d" % [
		_hunt.get_elapsed_s(), int(bot.get("shots_fired")), int(bot.get("reloads")), int(bot.get("teleports")),
		_hunt.get_boars_killed(), total, _hits])
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
