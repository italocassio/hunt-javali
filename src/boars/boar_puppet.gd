class_name BoarPuppet
extends Node3D
## Client replica of one host boar (docs/multiplayer.md decision A3 and section 6.3). Built in code: root +
## Visual + the same four HitZone of Boar, so the local hitscan works unchanged. No state machine, herd
## nor RNG of gameplay: the pose comes from the host snapshots, interpolated by HuntReplica's clock with a
## fixed delay and never extrapolated; one-off moments (hit, attack, death) come as events.
## The charge is judged here, against the local hunter, with the pose this machine shows ("favor the victim").

## The local weapon hit one of the zones (prediction: HuntReplica shows it and claims it to the host).
signal hit_by_local(puppet: BoarPuppet, hit: HitInfo)

const RING: int = 8                      # snapshot samples kept per boar
const FIELDS: int = 5                    # t_ms, x, z, yaw, st
const SPEED_SMOOTH_PER_S: float = 10.0   # locomotion speed low-pass (cosmetic)
const MIN_SAMPLE_GAP_MS: float = 0.5

var boar_id: int = -1
var type_id: StringName = &""
var weight_kg: float = 100.0
var body_scale: float = 1.0
var state: StringName = Ids.BS_WANDER
var wounded: bool = false
var alive: bool = true

var _hm: Heightmap = null
var _visual: BoarVisualBase = null
var _zones: Array[HitZone] = []
var _zone_mults: Dictionary = {}
var _samples: PackedFloat64Array = PackedFloat64Array()
var _head: int = 0                       # next write index
var _count: int = 0
var _xz: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _st: int = 0
var _up: Vector3 = Vector3.UP
var _speed: float = 0.0
var _eating: bool = false
var _highlight: bool = false
var _charge_toggle: int = -1
var _charge_hit_done: bool = false
var _charge_damage: float = 0.0
var _knockback_mps: float = 6.0
var _voice_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()   # cosmetic only (voices)


func setup(p_id: int, p_type_id: StringName, p_weight_kg: float, xz: Vector2, yaw: float, hm: Heightmap) -> void:
	boar_id = p_id
	type_id = p_type_id
	weight_kg = p_weight_kg
	_hm = hm
	name = "BoarPuppet_%d" % boar_id
	body_scale = BoarVisualBase.scale_for_weight(weight_kg)
	var def: Dictionary = Data.get_boar_type(type_id)
	_charge_damage = float(def.get("charge_damage", 0.0))
	_knockback_mps = float(Data.get_game().get("player", {}).get("knockback_mps", _knockback_mps))
	_zone_mults = Data.get_boar_rules().get("zone_multipliers", {})
	_samples.resize(RING * FIELDS)
	_rng.seed = hash(boar_id)
	_voice_time = _rng.randf_range(Boar.GRUNT_MIN_S, Boar.GRUNT_MAX_S)
	_build_visual()
	_zones = Boar.make_hit_zones(self, boar_id, body_scale)
	for hz: HitZone in _zones:
		hz.hit_received.connect(_on_hit_received)
	_xz = xz
	_yaw = yaw
	_up = _hm.get_normal(xz.x, xz.y) if _hm != null else Vector3.UP
	_apply_pose()


func get_xz() -> Vector2:
	return _xz


func get_yaw() -> float:
	return _yaw


func get_zone_position(zone: StringName) -> Vector3:
	if not BoarVisualBase.HIT_ZONES.has(zone):
		return Vector3.INF
	var def: Array = BoarVisualBase.HIT_ZONES[zone] as Array
	return to_global((def[0] as Vector3) * body_scale)


func zone_multiplier(zone: StringName) -> float:
	return float(_zone_mults.get(String(zone), 1.0))


func set_highlight(on: bool) -> void:
	var want: bool = on and alive
	if want == _highlight:
		return
	_highlight = want
	_visual.set_highlight(want)


func is_highlighted() -> bool:
	return _highlight


## One snapshot entry at host time t_ms. Older or repeated times are dropped (the state lane may reorder).
func push_sample(t_ms: float, xz: Vector2, yaw: float, st: int) -> void:
	if not alive:
		return
	if _count > 0 and t_ms <= _samples[_index(_count - 1) * FIELDS] + MIN_SAMPLE_GAP_MS:
		return
	var at: int = _head * FIELDS
	_samples[at] = t_ms
	_samples[at + 1] = xz.x
	_samples[at + 2] = xz.y
	_samples[at + 3] = yaw
	_samples[at + 4] = float(st)
	_head = (_head + 1) % RING
	_count = mini(_count + 1, RING)


## Moves the puppet to the pose at host time render_t_ms. Holds the oldest/newest pose outside the buffer.
func update_pose(render_t_ms: float, delta: float) -> void:
	if not alive:
		return
	var before: Vector2 = _xz
	if _count > 0:
		_sample_at(render_t_ms)
	var moved: float = _xz.distance_to(before)
	var inst: float = moved / delta if delta > 0.0 else 0.0
	_speed = lerpf(_speed, inst, clampf(SPEED_SMOOTH_PER_S * delta, 0.0, 1.0))
	if _hm != null:
		var n: Vector3 = _hm.get_normal(_xz.x, _xz.y)
		_up = _up.lerp(n, clampf(Boar.TILT_LERP_PER_S * delta, 0.0, 1.0)).normalized()
	_apply_pose()
	_visual.set_locomotion(_speed)
	_tick_voice(delta)


## Charge judged on the victim's machine: once per charge (b7 of the state byte flips on each new one).
## Returns true when it hit `hunter` (damage already applied here).
func try_charge_hit(hunter: PlayerBase) -> bool:
	if not alive or state != Ids.BS_CHARGE:
		_charge_hit_done = false
		return false
	var toggle: int = 1 if (_st & Boar.NET_ST_CHARGE_TOGGLE) != 0 else 0
	if toggle != _charge_toggle:
		_charge_toggle = toggle
		_charge_hit_done = false
	if _charge_hit_done or hunter == null or not hunter.is_alive():
		return false
	if not Boar.charge_hits(_xz, Steering.dir_from_yaw(_yaw), body_scale, position.y, hunter.global_position):
		return false
	_charge_hit_done = true
	hunter.apply_damage(_charge_damage, global_position, _knockback_mps)
	_visual.play_attack()
	return true


## Feedback of a hit confirmed by the host (EV_BOAR_HIT from another hunter's shot).
func play_hit_feedback(zone: StringName) -> void:
	if not alive:
		return
	_visual.play_hit(zone)
	Sfx.play_3d(&"boar_squeal", global_position, 0.0, _voice_pitch())


func play_attack() -> void:
	if alive:
		_visual.play_attack()


## EV_BOAR_DEATH: final pose from the host, zones off, death animation and sound.
func die(xz: Vector2, yaw: float) -> void:
	if not alive:
		return
	alive = false
	_xz = xz
	_yaw = yaw
	_apply_pose()
	for hz: HitZone in _zones:
		hz.disable()
	_highlight = false
	_visual.set_highlight(false)
	_visual.set_eating(false)
	_visual.set_locomotion(0.0)
	_visual.play_death()
	Sfx.play_3d(&"boar_death", global_position, 0.0, _voice_pitch())
	state = Ids.BS_DEAD
	GameEvents.boar_state_changed.emit(boar_id, state)


# --- Internals -----------------------------------------------------------------------------------

func _index(k: int) -> int:
	# k = 0 oldest .. _count - 1 newest
	return (_head - _count + k + RING) % RING


func _sample_at(t: float) -> void:
	var newest: int = _index(_count - 1) * FIELDS
	var oldest: int = _index(0) * FIELDS
	if t >= _samples[newest] or _count == 1:
		_set_from(newest, newest, 0.0)
		return
	if t <= _samples[oldest]:
		_set_from(oldest, oldest, 0.0)
		return
	for k: int in range(_count - 2, -1, -1):
		var a: int = _index(k) * FIELDS
		if _samples[a] <= t:
			var b: int = _index(k + 1) * FIELDS
			var span: float = _samples[b] - _samples[a]
			_set_from(a, b, (t - _samples[a]) / span if span > 0.0 else 1.0)
			return


func _set_from(a: int, b: int, f: float) -> void:
	_xz = Vector2(lerpf(_samples[a + 1], _samples[b + 1], f), lerpf(_samples[a + 2], _samples[b + 2], f))
	_yaw = lerp_angle(_samples[a + 3], _samples[b + 3], f)
	var st: int = int(_samples[a + 4])
	if st != _st:
		_apply_st(st)


## State byte reached by the interpolation: flags and state transitions with their feedback.
func _apply_st(st: int) -> void:
	var prev_st: int = _st
	_st = st
	var w: bool = (st & Boar.NET_ST_WOUNDED) != 0
	if w != wounded:
		wounded = w
		_visual.set_wounded(w)
	var eating: bool = (st & Boar.NET_ST_EATING) != 0
	if eating != _eating:
		_eating = eating
		_visual.set_eating(eating)
	var idx: int = st & Boar.NET_ST_STATE_MASK
	var new_state: StringName = NetCodec.BOAR_STATES[idx] if idx < NetCodec.BOAR_STATES.size() else state
	if new_state == Ids.BS_DEAD:
		return   # death only by EV_BOAR_DEATH
	# Closing in is reported as "alert"; when it stops while still alert, the host played a fresh alert.
	var approach_ended: bool = (st & Boar.NET_ST_APPROACH) == 0 and (prev_st & Boar.NET_ST_APPROACH) != 0
	if new_state == state and not approach_ended:
		return
	var old_state: StringName = state
	state = new_state
	if new_state != old_state:
		GameEvents.boar_state_changed.emit(boar_id, state)
	match new_state:
		Ids.BS_ALERT:
			if (st & Boar.NET_ST_APPROACH) == 0:
				_visual.play_alert()
				if _rng.randf() < Boar.SNORT_CHANCE:
					Sfx.play_3d(&"boar_snort_alert", global_position, 0.0, _voice_pitch())
		Ids.BS_BAYED:
			_visual.play_alert()
		Ids.BS_SCRAPE:
			_visual.play_scrape()
			Sfx.play_3d(&"boar_scrape", global_position, 0.0, _voice_pitch())
			Sfx.play_3d(&"boar_grunt", global_position, 0.0, _voice_pitch())
		Ids.BS_CHARGE:
			Sfx.play_3d(&"boar_charge_roar", global_position, Boar.ROAR_DB, _voice_pitch())
		Ids.BS_FLEE:
			if old_state != Ids.BS_FLEE and (type_id == Ids.PIGLET or wounded):
				Sfx.play_3d(&"boar_squeal", global_position, Boar.QUIET_DB, _voice_pitch())


func _apply_pose() -> void:
	var y: float = _hm.get_height(_xz.x, _xz.y) if _hm != null else 0.0
	position = Vector3(_xz.x, y, _xz.y)
	basis = Boar.basis_for(_yaw, _up)


func _on_hit_received(hit: HitInfo) -> void:
	if alive:
		hit_by_local.emit(self, hit)


func _voice_pitch() -> float:
	return clampf(1.0 / body_scale, 0.75, 1.5)


## Background grunts and chewing, drawn locally (cosmetic).
func _tick_voice(delta: float) -> void:
	_voice_time -= delta
	if _voice_time > 0.0:
		return
	_voice_time = _rng.randf_range(Boar.GRUNT_MIN_S, Boar.GRUNT_MAX_S)
	if state == Ids.BS_EAT and _eating:
		if _rng.randf() < Boar.EAT_SOUND_CHANCE:
			Sfx.play_3d(&"boar_eat", global_position, Boar.QUIET_DB, _voice_pitch())
	elif state == Ids.BS_WANDER or state == Ids.BS_TO_CROP or state == Ids.BS_TO_BAIT:
		Sfx.play_3d(&"boar_grunt", global_position, Boar.QUIET_DB, _voice_pitch())


func _build_visual() -> void:
	var node: Node = AssetLoader.instantiate(ScenePaths.BOAR_VISUAL)
	_visual = node as BoarVisualBase
	if _visual == null:
		if node != null:
			node.free()
		_visual = BoarVisualBase.create_fallback()
	_visual.name = "Visual"
	_visual.setup(type_id, weight_kg)
	_visual.scale = Vector3.ONE * body_scale
	add_child(_visual)
