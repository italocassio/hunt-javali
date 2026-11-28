extends Node
## Measures the fight against the Cachaco rei of horde level 2 (docs/plano_horda_boss.md section 2 and task F5b):
## how many shots and how many seconds it takes to die, how many charges land on the hunter and what they cost,
## how much of the barn is lost during wave 10 and whether the counted ammo closes in a one-hunter room.
## Every scenario fast-forwards waves 1..9 with debug kills (the only mechanism there is) and then plays wave 10
## for real, with the test bot's own shots.
##   duel_338    wave 10 with every other boar killed on sight: the boss alone against the .338
##   duel_3006   the same against the .30-06
##   wave10      the whole of wave 10 with the .338, no debug kills: barn loss and the ammo budget
## This scene MEASURES and reports; it only fails on something that makes the measurement meaningless (the wave was
## never reached, the boss never died). The numbers are a balancing decision for the coordination, not a test.
## Run: tools/godot.sh --headless --fixed-fps 60 --path . res://tests/boss_fight.tscn [-- --only=duel_338]

const HuntBot := preload("res://tests/bot/hunt_bot.gd")

const LEVEL: int = 2
const BOSS_WAVE: int = 10
const WATCHDOG_REAL_S: float = 1500.0
const SEED: int = 2626
const SAFE_XZ: Vector2 = Vector2(-15.0, -105.0)
const FF_TIME_SCALE: float = 8.0
const FIGHT_TIME_SCALE: float = 1.0      # the fight itself runs at the real pace: the numbers have to mean something
const WAVE_CLEAR_S: float = 180.0
const BOSS_SPAWN_S: float = 30.0
const FIGHT_TIMEOUT_S: float = 400.0
const WAVE10_TIMEOUT_S: float = 600.0
const HEAL_BELOW_FRAC: float = 0.45      # the hunter is healed before it falls, so the fight can be measured to the end
const CRATE_TRIP_S: float = 90.0         # respawn_s is 60 s: time budget to wait for a crate and take it
const CRATE_WAIT_S: float = 2.0

var _passed: int = 0
var _failed: int = 0
var _start_ms: int = 0
var _hunt: HuntController = null
var _ended: Array[HuntResult] = []
var _boss_hp: Array[Array] = []          # [pct, hunt time]
var _boss_id: int = -1
var _charges: int = 0                    # BS_CHARGE entered by the boss
var _zones: Dictionary = {}              # hit zone -> shots that landed on the boss
var _boss_damage: float = 0.0            # damage the shots did to the boss (zone multiplier included)
var _damage: Array[float] = []           # every drop of the hunter's health while the fight is watched
var _healed: float = 0.0
var _watch: bool = false
var _hp_last: float = -1.0
var _seed: int = SEED


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	GameEvents.horde_boss_health_changed.connect(func(pct: float) -> void:
		_boss_hp.append([pct, _hunt.get_elapsed_s() if _hunt != null else 0.0]))
	GameEvents.boar_state_changed.connect(func(id: int, state: StringName) -> void:
		if id == _boss_id and state == Ids.BS_CHARGE:
			_charges += 1)
	GameEvents.boar_hit.connect(func(id: int, zone: StringName, damage: float, _at: Vector3, _shot: int) -> void:
		if id != _boss_id:
			return
		_zones[zone] = int(_zones.get(zone, 0)) + 1
		_boss_damage += damage)
	var only: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--seed="):
			_seed = int(arg.trim_prefix("--seed="))   # another run of the same fight, for the spread of the numbers
	var all: Dictionary = {"duel_338": _scn_duel.bind(&"rifle_338"), "duel_3006": _scn_duel.bind(&"rifle_3006"),
		"wave10": _scn_wave10}
	for key: String in all.keys():
		if only.is_empty() or only.has(key):
			print("--- %s (semente %d)" % [key, _seed])
			await (all[key] as Callable).call()
			await _close()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("FAIL watchdog: a medicao estourou %d s reais" % int(WATCHDOG_REAL_S))
		print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed + 1])
		get_tree().quit(1)
		return
	if not _watch or _hunt == null or not is_instance_valid(_hunt) or _hunt.is_hunt_over():
		return
	var p: PlayerBase = _hunt.get_player()
	if p == null or not is_instance_valid(p):
		return
	var hp: float = p.get_health()
	if _hp_last >= 0.0 and hp < _hp_last - 0.01:
		_damage.append(_hp_last - hp)
	if hp > 0.0 and hp < p.get_max_health() * HEAL_BELOW_FRAC:
		_healed += p.get_max_health() - hp
		p.heal(p.get_max_health())
		hp = p.get_health()
	_hp_last = hp


func _check(test_name: String, ok: bool, detail: String = "") -> bool:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])
	return ok


# --- Plumbing ------------------------------------------------------------------------------------

func _open() -> bool:
	_ended.clear()
	_boss_hp.clear()
	_damage.clear()
	_charges = 0
	_zones.clear()
	_boss_damage = 0.0
	_boss_id = -1
	_healed = 0.0
	_hp_last = -1.0
	_watch = false
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, LEVEL)
	req.rng_seed = _seed
	req.quality = Ids.Q_LOW
	Router.set_pending_request(req)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	add_child(_hunt)
	var t0: int = Time.get_ticks_msec()
	while not _hunt.is_world_ready():
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 120000:
			_check("world_ready", false, "o mundo nao ficou pronto em 120 s")
			return false
	return true


func _close() -> void:
	_watch = false
	Engine.time_scale = 1.0
	if _hunt == null:
		return
	_hunt.queue_free()
	_hunt = null
	Router.set_pending_request(null)
	await get_tree().process_frame
	await get_tree().process_frame


func _park_safe() -> void:
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	p.bot_set_move(Vector2.ZERO, false)
	p.bot_teleport(Vector3(SAFE_XZ.x, _hunt.get_height(SAFE_XZ.x, SAFE_XZ.y) + 0.05, SAFE_XZ.y))


func _wait(cond: Callable, max_s: float) -> bool:
	var limit: float = _hunt.get_elapsed_s() + max_s
	while _hunt.get_elapsed_s() < limit and not _hunt.is_hunt_over():
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _hit_count() -> int:
	var n: int = 0
	for z: StringName in _zones.keys():
		n += int(_zones[z])
	return n


func _find_boss() -> Boar:
	for id: int in _hunt.get_alive_boar_ids():
		var b: Boar = _hunt.spawner.get_boar(id)
		if b != null and b.type_id == Ids.BOSS and b.is_alive():
			return b
	return null


## Clears waves 1..wave-1 with debug kills and leaves the hunt in the intermission before `wave`.
func _reach_wave(wave: int) -> bool:
	Engine.time_scale = FF_TIME_SCALE
	for w: int in range(1, wave):
		_hunt.debug_horde_start_next_wave()
		await get_tree().process_frame
		var limit: float = _hunt.get_elapsed_s() + WAVE_CLEAR_S
		while _hunt.get_elapsed_s() < limit and not _hunt.is_hunt_over() and _hunt.get_horde_waves_cleared() < w:
			for id: int in _hunt.get_alive_boar_ids().duplicate():
				_hunt.debug_kill_boar(id)
			if _hunt.get_crop_health_pct() < 60.0:
				_hunt.debug_set_crop_health(100.0)
			await get_tree().process_frame
		if _hunt.is_hunt_over() or _hunt.get_horde_waves_cleared() < w:
			Engine.time_scale = 1.0
			return false
	Engine.time_scale = 1.0
	await get_tree().process_frame
	_hunt.debug_set_crop_health(100.0)
	return _hunt.get_horde_wave() == wave and _hunt.get_horde_phase() == Ids.HP_INTERMISSION


## Stands on an available crate and presses interact. True if the reserve went up.
func _take_crate() -> bool:
	var p: PlayerBase = _hunt.get_player()
	var crates: HordeAmmoCrates = _hunt.debug_ammo_crates()
	if crates == null:
		return false
	var before: int = p.get_ammo_reserve()
	var found: bool = await _wait(func() -> bool:
		for i: int in crates.get_count():
			if crates.is_available(i):
				return true
		return false, CRATE_TRIP_S)
	if not found:
		return false
	for i: int in crates.get_count():
		if not crates.is_available(i):
			continue
		var at: Vector3 = crates.get_crate_position(i)
		p.bot_set_enabled(true)
		p.bot_set_move(Vector2.ZERO, false)
		p.bot_teleport(Vector3(at.x, _hunt.get_height(at.x, at.z) + 0.05, at.z))
		await get_tree().process_frame
		await get_tree().process_frame
		p.bot_set_interact(true)
		await get_tree().process_frame
		p.bot_set_interact(false)
		await _wait(func() -> bool: return p.get_ammo_reserve() > before, CRATE_WAIT_S)
		if p.get_ammo_reserve() > before:
			return true
	return false


## Fills the reserve from every crate standing (the hunter stocks up before the last wave, as the plan assumes).
func _stock_up() -> int:
	var trips: int = 0
	var crates: HordeAmmoCrates = _hunt.debug_ammo_crates()
	if crates == null:
		return 0
	for i: int in crates.get_count():
		if await _take_crate():
			trips += 1
		else:
			break
	return trips


# --- Scenarios -----------------------------------------------------------------------------------

## The boss alone: every other boar of wave 10 dies on sight, so every shot and every charge belongs to the duel.
func _scn_duel(weapon_id: StringName) -> void:
	if not await _open():
		return
	var p: PlayerBase = _hunt.get_player()
	_park_safe()
	if not _check("duel_%s_reached_wave_10" % weapon_id, await _reach_wave(BOSS_WAVE),
		"wave=%d killed=%d/%d" % [_hunt.get_horde_wave(), _hunt.get_boars_killed(), _hunt.get_boars_total()]):
		return
	var slot: int = Data.get_weapon_ids().find(weapon_id)
	p.bot_select_weapon(slot)
	await _wait(func() -> bool: return p.get_current_weapon_id() == weapon_id, 5.0)
	var trips: int = await _stock_up()
	var rounds0: int = p.get_ammo_reserve() + p.get_ammo_in_mag()
	_park_safe()
	var mag: int = int(Data.get_weapon(weapon_id).get("mag_size", 0))
	# Wave 10 starts: the boss first, everything else killed on sight.
	_hunt.debug_horde_start_next_wave()
	var born: bool = await _wait(func() -> bool: return _find_boss() != null, BOSS_SPAWN_S)
	var boss: Boar = _find_boss()
	if not _check("duel_%s_boss_born" % weapon_id, born and boss != null):
		return
	_boss_id = boss.boar_id
	var max_health: float = boss.max_health
	var kg: float = boss.weight_kg
	var t0: float = _hunt.get_elapsed_s()
	var crop0: float = _hunt.get_crop_health_pct()
	var bot: RefCounted = HuntBot.new()
	bot.call("setup", self, _hunt)
	Engine.time_scale = FIGHT_TIME_SCALE
	_hp_last = p.get_health()
	_watch = true
	var escort: Callable = func() -> void:
		for id: int in _hunt.get_alive_boar_ids().duplicate():
			if id != _boss_id:
				_hunt.debug_kill_boar(id)
	# The bot fights; between its passes the escort is cleared and the hunter is kept on its feet.
	var deadline: float = _hunt.get_elapsed_s() + FIGHT_TIMEOUT_S
	while not _hunt.is_hunt_over() and _hunt.get_elapsed_s() < deadline and _find_boss() != null:
		escort.call()
		if p.get_ammo_in_mag() + p.get_ammo_reserve() <= 0 and await _take_crate():
			trips += 1
		await bot.call("kill_all", 8.0, func() -> bool: return _find_boss() == null)
		escort.call()
		await get_tree().process_frame
	_watch = false
	Engine.time_scale = 1.0
	var took: float = _hunt.get_elapsed_s() - t0
	var shots: int = int(bot.get("shots_fired"))
	var dead: bool = _find_boss() == null
	var hits: int = _damage.size()
	var taken: float = 0.0
	for d: float in _damage:
		taken += d
	# Killing the boss with its whole wave already down is the last kill of the hunt: VICTORY here is the right end.
	var ended_well: bool = not _hunt.is_hunt_over() or (not _ended.is_empty() and _ended[0].outcome == HuntResult.Outcome.VICTORY)
	_check("duel_%s_boss_died" % weapon_id, dead and ended_well,
		"dead=%s over=%s health=%.0f" % [dead, _hunt.is_hunt_over(), boss.health if is_instance_valid(boss) else -1.0])
	print("MEDIDA duel %s: %d tiros reais (%d acertaram o chefao: %s, dano somado %.0f) em %.1f s de caçada | chefao %.1f kg, vida %.0f | investidas iniciadas %d, acertos no caçador %d, dano total %.0f (cura de teste %.0f) | celeiro %.1f%% -> %.1f%% | municao: %d cartuchos no inicio (%d pentes de %d), %d no fim, %d idas a caixa"
		% [weapon_id, shots, _hit_count(), str(_zones), _boss_damage, took, kg, max_health, _charges, hits, taken,
		_healed, crop0, _hunt.get_crop_health_pct(), rounds0, rounds0 / maxi(mag, 1), mag,
		p.get_ammo_reserve() + p.get_ammo_in_mag(), trips])


## The whole of wave 10 with the .338 and no debug kills: what the barn loses and whether the ammo closes.
func _scn_wave10() -> void:
	if not await _open():
		return
	var p: PlayerBase = _hunt.get_player()
	_park_safe()
	if not _check("wave10_reached_wave_10", await _reach_wave(BOSS_WAVE),
		"wave=%d killed=%d/%d" % [_hunt.get_horde_wave(), _hunt.get_boars_killed(), _hunt.get_boars_total()]):
		return
	var weapon_id: StringName = &"rifle_338"
	var slot: int = Data.get_weapon_ids().find(weapon_id)
	p.bot_select_weapon(slot)
	await _wait(func() -> bool: return p.get_current_weapon_id() == weapon_id, 5.0)
	var cfg: Dictionary = Data.get_horde_level(LEVEL)
	var mag: int = int(Data.get_weapon(weapon_id).get("mag_size", 0))
	var trips: int = await _stock_up()
	var rounds0: int = p.get_ammo_reserve() + p.get_ammo_in_mag()
	var cap_rounds: int = int(cfg["ammo"]["reserve_cap_mags"]) * mag + mag
	_check("wave10_hunter_starts_at_the_ammo_cap", rounds0 == cap_rounds,
		"%d cartuchos (teto %d pentes + 1 carregado = %d) em %d idas a caixa" % [rounds0,
		int(cfg["ammo"]["reserve_cap_mags"]), cap_rounds, trips])
	_park_safe()
	var killed0: int = _hunt.get_boars_killed()
	var wave_total: int = 0
	for g: Variant in ((cfg["waves"] as Array)[BOSS_WAVE - 1] as Dictionary)["groups"]:
		wave_total += ((g as Dictionary)["members"] as Array).size()
	_hunt.debug_set_crop_health(100.0)
	var crop0: float = _hunt.get_crop_health_pct()
	var t0: float = _hunt.get_elapsed_s()
	_hunt.debug_horde_start_next_wave()
	await _wait(func() -> bool: return _find_boss() != null, BOSS_SPAWN_S)
	var boss: Boar = _find_boss()
	_boss_id = boss.boar_id if boss != null else -1
	var bot: RefCounted = HuntBot.new()
	bot.call("setup", self, _hunt)
	Engine.time_scale = FIGHT_TIME_SCALE
	_hp_last = p.get_health()
	_watch = true
	var empties: int = 0
	var boss_t: float = -1.0
	var deadline: float = _hunt.get_elapsed_s() + WAVE10_TIMEOUT_S
	while not _hunt.is_hunt_over() and _hunt.get_elapsed_s() < deadline and _hunt.get_horde_waves_cleared() < BOSS_WAVE:
		if boss_t < 0.0 and _boss_id >= 0 and not _hunt.get_alive_boar_ids().has(_boss_id):
			boss_t = _hunt.get_elapsed_s() - t0
		if p.get_ammo_in_mag() + p.get_ammo_reserve() <= 0:
			empties += 1
			if await _take_crate():
				trips += 1
			if p.get_ammo_in_mag() + p.get_ammo_reserve() <= 0:
				break      # no crate came back in time: the ammo did not close
		await bot.call("kill_all", 10.0, func() -> bool: return _hunt.get_horde_waves_cleared() >= BOSS_WAVE)
		await get_tree().process_frame
	_watch = false
	Engine.time_scale = 1.0
	if boss_t < 0.0 and _boss_id >= 0 and not _hunt.get_alive_boar_ids().has(_boss_id):
		boss_t = _hunt.get_elapsed_s() - t0
	var killed: int = _hunt.get_boars_killed() - killed0
	var taken: float = 0.0
	for d: float in _damage:
		taken += d
	_check("wave10_was_played_out", killed >= wave_total or _hunt.get_horde_waves_cleared() >= BOSS_WAVE,
		"abatidos na onda 10: %d de %d; cleared=%d over=%s" % [killed, wave_total, _hunt.get_horde_waves_cleared(),
		_hunt.is_hunt_over()])
	print("MEDIDA wave10 %s: %d tiros reais (%d no chefao: %s), %d/%d javalis da onda 10 em %.1f s | chefao caiu em %.1f s | celeiro %.1f%% -> %.1f%% (perda %.1f pontos) | municao: %d no inicio, %d no fim, %d vezes sem cartucho, %d idas a caixa | acertos no caçador %d, dano %.0f (cura de teste %.0f), investidas do chefao %d"
		% [weapon_id, int(bot.get("shots_fired")), _hit_count(), str(_zones), killed, wave_total,
		_hunt.get_elapsed_s() - t0, boss_t, crop0, _hunt.get_crop_health_pct(), crop0 - _hunt.get_crop_health_pct(),
		rounds0, p.get_ammo_reserve() + p.get_ammo_in_mag(), empties, trips, _damage.size(), taken, _healed,
		_charges])
