class_name HordeDirector
extends Node
## Horde mode waves (docs/horda.md section 5.2). Offline and network host only: plans the waves, holds every
## group of a wave in the BoarSpawner until its intermission ends, and follows the kills of the wave in course.
## The HuntController forwards wave_changed / wave_progress to GameEvents (the only emitter on the bus).

signal wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)
signal wave_progress(remaining: int, wave_total: int)

const WAVE_KEY: String = "wave"

var _world: HuntController = null
var _spawner: BoarSpawner = null
var _plan: Array = []
var _first_delay_s: float = 0.0
var _intermission_s: float = 0.0
var _begun: bool = false
var _wave: int = 0                       # 1-based; 0 before begin()
var _phase: StringName = &""
var _countdown: float = 0.0
var _waves_cleared: int = 0
var _killed_before: int = 0


## One entry per wave: the groups of that wave scaled by BoarSpawner.scale_groups (horde keys, not coop.*), each
## group tagged with "wave" (0-based). The whole plan is kept within NetCodec.MAX_BOARS_PER_HUNT (boar ids are
## u8): members are cut from the end of the plan, emptied groups and waves go. Pure function.
static func plan_waves(horde: Dictionary, player_count: int) -> Array:
	var scale: Dictionary = {
		"boar_count_mult_by_players": horde.get("player_count_mult", []),
		"extra_group_delay_s": float(horde.get("extra_group_delay_s", 0.0)),
	}
	var plan: Array = []
	var total: int = 0
	var waves: Array = horde.get("waves", [])
	for i: int in waves.size():
		var wave_def: Dictionary = waves[i] as Dictionary if waves[i] is Dictionary else {}
		var groups: Array = BoarSpawner.scale_groups(wave_def.get("groups", []), player_count, scale)
		var out: Array[Dictionary] = []
		for g: Variant in groups:
			var def: Dictionary = g as Dictionary
			if (def.get("members", []) as Array).is_empty():
				continue
			def[WAVE_KEY] = i
			total += (def["members"] as Array).size()
			out.append(def)
		if not out.is_empty():
			plan.append(out)
	if total > NetCodec.MAX_BOARS_PER_HUNT:
		push_error("HordeDirector: %d boars in the horde plan, more than %d; trimming the last waves" % [total, NetCodec.MAX_BOARS_PER_HUNT])
		while total > NetCodec.MAX_BOARS_PER_HUNT and not plan.is_empty():
			var last_wave: Array = plan[plan.size() - 1]
			var last_group: Dictionary = last_wave[last_wave.size() - 1]
			var members: Array = last_group["members"]
			members.remove_at(members.size() - 1)
			total -= 1
			if members.is_empty():
				last_wave.remove_at(last_wave.size() - 1)
				if last_wave.is_empty():
					plan.remove_at(plan.size() - 1)
	return plan


func setup(world: HuntController, spawner: BoarSpawner, horde: Dictionary, plan: Array) -> void:
	_world = world
	_spawner = spawner
	_plan = plan
	_first_delay_s = maxf(float(horde.get("first_wave_delay_s", 0.0)), 0.0)
	_intermission_s = maxf(float(horde.get("intermission_s", 0.0)), 0.0)
	# After the controller's own connection: the kill is counted (boar_counts_changed) before wave_progress.
	spawner.boar_died.connect(_on_boar_died)


func begin() -> void:
	if _begun or _plan.is_empty():
		return
	_begun = true
	_wave = 1
	_phase = Ids.HP_INTERMISSION
	_countdown = _first_delay_s
	_killed_before = _world.get_boars_killed()
	wave_changed.emit(_wave, get_wave_count(), _phase, _countdown)


func skip_intermission() -> void:
	if _begun and _phase == Ids.HP_INTERMISSION:
		_countdown = 0.0


func get_wave() -> int:
	return _wave


func get_wave_count() -> int:
	return _plan.size()


func get_phase() -> StringName:
	return _phase


func get_countdown_s() -> float:
	return _countdown if _phase == Ids.HP_INTERMISSION else 0.0


func get_wave_total() -> int:
	return _spawner.get_wave_total(_wave - 1) if _wave >= 1 else 0


func get_wave_remaining() -> int:
	return _spawner.get_wave_remaining(_wave - 1) if _phase == Ids.HP_WAVE else 0


func get_waves_cleared() -> int:
	return _waves_cleared


func get_killed_before() -> int:
	return _killed_before


func _process(delta: float) -> void:
	if not _begun or _world == null or _world.is_hunt_over() or _phase != Ids.HP_INTERMISSION:
		return
	_countdown -= delta
	if _countdown > 0.0:
		return
	_countdown = 0.0
	_phase = Ids.HP_WAVE
	_killed_before = _world.get_boars_killed()
	_spawner.release_wave(_wave - 1)
	var total: int = get_wave_total()
	wave_changed.emit(_wave, get_wave_count(), _phase, 0.0)
	wave_progress.emit(total, total)


func _on_boar_died(boar: Boar) -> void:
	if not _begun or _phase != Ids.HP_WAVE or _world.is_hunt_over() or boar.wave != _wave - 1:
		return
	var remaining: int = _spawner.get_wave_remaining(_wave - 1)
	wave_progress.emit(remaining, get_wave_total())
	if remaining > 0:
		return
	_waves_cleared = _wave
	if _wave >= get_wave_count():
		return   # last wave: the controller ends the hunt (killed == total)
	_wave += 1
	_phase = Ids.HP_INTERMISSION
	_countdown = _intermission_s
	_killed_before = _world.get_boars_killed()
	wave_changed.emit(_wave, get_wave_count(), _phase, _countdown)
