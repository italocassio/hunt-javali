class_name DogPuppet
extends Node3D
## Client replica of one host dog (docs/multiplayer.md section 6.5). Visual only: no steering, no boars, no
## health rules. The pose comes from the DOG records of H_SNAPSHOT, interpolated by HuntReplica's clock with a
## fixed delay and never extrapolated (same idea as BoarPuppet). One-off sounds (barks, growls) run on local
## timers from the replicated state. When the dog belongs to the hunter of this machine, state and health go
## to the HUD through GameEvents, exactly as the Dog of a solo hunt does.

const RING: int = 8                      # snapshot samples kept per dog
const FIELDS: int = 6                    # t_ms, x, z, yaw, st, health
const SPEED_SMOOTH_PER_S: float = 10.0   # locomotion speed low-pass (cosmetic)
const MIN_SAMPLE_GAP_MS: float = 0.5
const HEALTH_EPS_PCT: float = 0.5

var owner_slot: int = 0
var breed_id: StringName = &""
var state: StringName = Ids.DS_FOLLOW
var health_pct: float = 100.0

var _hm: Heightmap = null
var _visual: DogVisualBase = null
var _samples: PackedFloat64Array = PackedFloat64Array()
var _head: int = 0
var _count: int = 0
var _xz: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _st: int = 0
var _speed: float = 0.0
var _hurt_timer: float = 0.0
var _sound_timer: float = 0.0
var _local_owner: bool = false
var _last_pct_sent: int = -1
var _retreating: bool = false
var _biting: bool = false


func setup(p_owner_slot: int, p_breed_id: StringName, xz: Vector2, yaw: float, hm: Heightmap) -> void:
	owner_slot = p_owner_slot
	breed_id = p_breed_id
	_hm = hm
	name = "DogPuppet_%d" % owner_slot
	_samples.resize(RING * FIELDS)
	_build_visual()
	_xz = xz
	_yaw = yaw
	_apply_pose()


func get_xz() -> Vector2:
	return _xz


func get_yaw() -> float:
	return _yaw


func get_health_pct() -> float:
	return health_pct


func is_local_owner() -> bool:
	return _local_owner


## The dog of this machine's hunter: its state and health reach the HUD (initial values go out now).
func set_local_owner(on: bool) -> void:
	_local_owner = on
	if on:
		GameEvents.dog_state_changed.emit(state)
		_send_health(true)


## One snapshot entry at host time t_ms. Older or repeated times are dropped (the state lane may reorder).
func push_sample(t_ms: float, xz: Vector2, yaw: float, st: int, health: float) -> void:
	if _count > 0 and t_ms <= _samples[_index(_count - 1) * FIELDS] + MIN_SAMPLE_GAP_MS:
		return
	var at: int = _head * FIELDS
	_samples[at] = t_ms
	_samples[at + 1] = xz.x
	_samples[at + 2] = xz.y
	_samples[at + 3] = yaw
	_samples[at + 4] = float(st)
	_samples[at + 5] = health
	_head = (_head + 1) % RING
	_count = mini(_count + 1, RING)


## Moves the puppet to the pose at host time render_t_ms. Holds the oldest/newest pose outside the buffer.
func update_pose(render_t_ms: float, delta: float) -> void:
	var before: Vector2 = _xz
	if _count > 0:
		_sample_at(render_t_ms)
	var moved: float = _xz.distance_to(before)
	var inst: float = moved / delta if delta > 0.0 else 0.0
	_speed = lerpf(_speed, inst, clampf(SPEED_SMOOTH_PER_S * delta, 0.0, 1.0))
	_hurt_timer = maxf(_hurt_timer - delta, 0.0)
	_apply_pose()
	_visual.set_locomotion(_speed)
	_tick_voice(delta)


## EV_DOG_CMD for this dog: "Pega!" barks (the host's dog does the same on its machine).
func play_command(cmd: int) -> void:
	if cmd == 0:
		Sfx.play_3d(&"dog_bark", global_position)


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
	_apply_health(_samples[a + 5])


## State byte reached by the interpolation (Dog.net_state_byte): state change, retreat and bite flags.
func _apply_st(st: int) -> void:
	_st = st
	var retreating: bool = (st & Dog.NET_ST_RETREATING) != 0
	if retreating != _retreating:
		_retreating = retreating
		_visual.set_retreating(retreating)
	var biting: bool = (st & Dog.NET_ST_BITING) != 0
	if biting != _biting:
		_biting = biting
		_visual.play_bite(biting)
	var idx: int = st & Dog.NET_ST_STATE_MASK
	var new_state: StringName = NetCodec.DOG_STATES[idx] if idx < NetCodec.DOG_STATES.size() else state
	if new_state == state:
		return
	state = new_state
	_sound_timer = 0.0
	if _local_owner:
		GameEvents.dog_state_changed.emit(state)
	match state:
		Ids.DS_POINT:
			_visual.set_locomotion(0.0)
			_visual.play_point()
		Ids.DS_RETREAT:
			Sfx.play_3d(&"dog_whine", global_position)


func _apply_health(pct: float) -> void:
	if pct < health_pct - HEALTH_EPS_PCT and _hurt_timer <= 0.0:
		_hurt_timer = Dog.HURT_FEEDBACK_S
		_visual.play_hurt()
		Sfx.play_3d(&"dog_yelp", global_position)
	health_pct = pct
	_send_health(false)


func _send_health(force: bool) -> void:
	var pct: int = int(round(health_pct))
	if force or pct != _last_pct_sent:
		_last_pct_sent = pct
		if _local_owner:
			GameEvents.dog_health_changed.emit(health_pct)


func _apply_pose() -> void:
	var y: float = _hm.get_height(_xz.x, _xz.y) if _hm != null else 0.0
	position = Vector3(_xz.x, y, _xz.y)
	rotation.y = _yaw


## Barks and growls of the abilities, drawn locally from the replicated state (same rhythm as Dog).
func _tick_voice(delta: float) -> void:
	if state != Ids.DS_POINT and state != Ids.DS_BAY and state != Ids.DS_HOLD:
		return
	_sound_timer -= delta
	if _sound_timer > 0.0:
		return
	match state:
		Ids.DS_POINT:
			_sound_timer = Dog.BARK_POINT_S
			Sfx.play_3d(&"dog_bark", global_position)
		Ids.DS_BAY:
			_sound_timer = Dog.BARK_BAY_S
			_visual.play_bark()
			Sfx.play_3d(&"dog_bark", global_position)
		Ids.DS_HOLD:
			_sound_timer = Dog.GROWL_S
			Sfx.play_3d(&"dog_growl", global_position)


func _build_visual() -> void:
	var node: Node = AssetLoader.instantiate(ScenePaths.DOG_VISUAL)
	_visual = node as DogVisualBase
	if _visual == null:
		if node != null:
			node.free()
		_visual = DogVisualBase.create_fallback()
	_visual.name = "Visual"
	_visual.setup(breed_id)
	add_child(_visual)
