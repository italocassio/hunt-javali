class_name Dog
extends Node3D
## Hunting dog (docs/arquitetura.md section 8.10). Kinematic steering over the heightmap, no physics
## body. Obeys GameEvents.dog_command_requested: "Pega!" from follow, "Volta!" otherwise.
## Abilities by breed data: point (caramelo), bay (foxhound), hold (dogo). Never dies.

# --- Rules the contract fixes in text (not present in data/) ---
const POINT_DISTANCE_M: float = 15.0
const BOAR_DAMAGE_RANGE_M: float = 2.5
const MIN_HEALTH: float = 1.0
const AVOID_LOOKAHEAD_M: float = 4.0
const MAP_MARGIN_M: float = 4.0

# --- Package tuning ---
const BODY_RADIUS_M: float = 0.25
const TURN_RATE_RAD_S: float = 9.0
const MIN_ALIGN_SPEED_FRAC: float = 0.3
const FOLLOW_SIDE_M: float = 1.0
const FOLLOW_STOP_M: float = 0.8
const FOLLOW_RUN_M: float = 8.0
const FOLLOW_SLOW_RADIUS_M: float = 2.0
const RETURN_DONE_M: float = 2.5
const POINT_LOSE_MULT: float = 1.6
const BAY_START_M: float = 3.5
const BAY_RING_M: float = 2.8
const BAY_RING_SWING_M: float = 0.9
const BAY_SWING_RAD_S: float = 2.0
const BAY_ORBIT_RAD_S: float = 0.7
const HOLD_GAP_M: float = 0.35
const BARK_POINT_S: float = 1.6
const BARK_BAY_S: float = 0.6
const GROWL_S: float = 1.5
const HURT_FEEDBACK_S: float = 0.8
const REMARK_FRAC: float = 0.8
const RETARGET_S: float = 0.5
const MSG_NO_BOAR: String = "O cão não farejou nenhum javali por perto."
const MSG_RETREAT: String = "Seu cão se feriu e recuou!"
const MSG_RECOVERED: String = "Seu cão está pronto de novo."
const MSG_S: float = 3.0

var breed_id: StringName = &""
var state: StringName = Ids.DS_FOLLOW
var health: float = 100.0
var max_health: float = 100.0

var _world: HuntController = null
var _visual: DogVisualBase = null
var _ability: StringName = &"point"
var _regen_per_s: float = 5.0
var _follow_speed: float = 5.5
var _run_speed: float = 8.5
var _follow_distance: float = 3.0
var _search_radius: float = 120.0
var _mark_duration: float = 6.0
var _bay_duration: float = 0.0
var _hold_duration: float = 0.0
var _alpha_break_free: float = 0.0
var _bite_dps: float = 0.0
var _retreat_frac: float = 0.3
var _return_frac: float = 0.7

var _yaw: float = 0.0
var _speed: float = 0.0
var _target: Boar = null
var _state_time: float = 0.0
var _ability_until: float = 0.0
var _sound_timer: float = 0.0
var _mark_timer: float = 0.0
var _retarget_timer: float = 0.0
var _hurt_timer: float = 0.0
var _orbit_angle: float = 0.0
var _last_pct_sent: int = -1


func setup(p_breed_id: StringName, world: HuntController, spawn_position: Vector3) -> void:
	breed_id = p_breed_id
	_world = world
	var def: Dictionary = Data.get_dog(breed_id)
	_ability = StringName(String(def.get("ability", "point")))
	max_health = maxf(float(def.get("max_health", 100.0)), MIN_HEALTH)
	health = max_health
	_regen_per_s = float(def.get("regen_per_s", 5.0))
	_follow_speed = float(def.get("follow_speed_mps", 5.5))
	_run_speed = float(def.get("run_speed_mps", 8.5))
	_follow_distance = float(def.get("follow_distance_m", 3.0))
	_search_radius = float(def.get("search_radius_m", 120.0))
	_mark_duration = float(def.get("mark_duration_s", 6.0))
	_bay_duration = float(def.get("bay_duration_s", 0.0))
	_hold_duration = float(def.get("hold_duration_s", 0.0))
	_alpha_break_free = float(def.get("alpha_break_free_s", 0.0))
	_bite_dps = float(def.get("bite_dps", 0.0))
	_retreat_frac = float(def.get("retreat_health_frac", 0.3))
	_return_frac = float(def.get("return_health_frac", 0.7))
	_build_visual()
	var p: Vector2 = _world.obstacles.resolve(Vector2(spawn_position.x, spawn_position.z), BODY_RADIUS_M)
	position = Vector3(p.x, _world.get_height(p.x, p.y), p.y)
	var player: PlayerBase = _world.get_player()
	if player != null:
		_yaw = player.rotation.y
	rotation.y = _yaw
	if not GameEvents.dog_command_requested.is_connected(_on_command):
		GameEvents.dog_command_requested.connect(_on_command)
	GameEvents.dog_state_changed.emit(state)
	_send_health(true)


func get_health_pct() -> float:
	return health / max_health * 100.0


func get_xz() -> Vector2:
	return Vector2(position.x, position.z)


## Damage from boars. The dog never dies: health stops at MIN_HEALTH and it retreats.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(health - amount, MIN_HEALTH)
	_send_health(false)
	if _hurt_timer <= 0.0:
		_hurt_timer = HURT_FEEDBACK_S
		_visual.play_hurt()
		Sfx.play_3d(&"dog_yelp", global_position)
	if state != Ids.DS_RETREAT and health < max_health * _retreat_frac:
		_enter_retreat()


# --- Commands ------------------------------------------------------------------------------------

func _on_command() -> void:
	if _world == null or _world.is_hunt_over():
		return
	if state == Ids.DS_FOLLOW:
		_target = _world.spawner.find_nearest_alive(get_xz(), _search_radius)
		_set_state(Ids.DS_SEEK)
		GameEvents.dog_command_executed.emit(Ids.CMD_ATTACK)
		Sfx.play_3d(&"dog_bark", global_position)
		return
	if state != Ids.DS_RETREAT:
		_enter_return()
	GameEvents.dog_command_executed.emit(Ids.CMD_RECALL)


# --- Frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _world == null:
		return
	_state_time += delta
	_speed = 0.0
	_hurt_timer = maxf(_hurt_timer - delta, 0.0)
	match state:
		Ids.DS_FOLLOW:
			_tick_follow(delta)
			_regen(delta)
		Ids.DS_SEEK:
			_tick_seek(delta)
		Ids.DS_POINT:
			_tick_point(delta)
		Ids.DS_BAY:
			_tick_bay(delta)
		Ids.DS_HOLD:
			_tick_hold(delta)
		Ids.DS_RETREAT:
			_tick_retreat(delta)
		Ids.DS_RETURN:
			_tick_return(delta)
	position.y = _world.get_height(position.x, position.z)
	rotation.y = _yaw
	_visual.set_locomotion(_speed)


func _follow_point() -> Vector2:
	var player: PlayerBase = _world.get_player()
	if player == null:
		return get_xz()
	var fwd: Vector2 = Steering.dir_from_yaw(player.rotation.y)
	var right: Vector2 = Vector2(-fwd.y, fwd.x)
	var pp: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	return pp - fwd * _follow_distance + right * FOLLOW_SIDE_M


func _go_to_follow_point(delta: float, always_run: bool) -> float:
	var point: Vector2 = _follow_point()
	var dist: float = get_xz().distance_to(point)
	if dist > FOLLOW_STOP_M:
		var speed: float = _run_speed if (always_run or dist > FOLLOW_RUN_M) else _follow_speed
		_steer(Steering.seek(get_xz(), point), speed * Steering.arrive_scale(dist, FOLLOW_SLOW_RADIUS_M), delta)
	return dist


func _tick_follow(delta: float) -> void:
	_go_to_follow_point(delta, false)


func _tick_return(delta: float) -> void:
	if _go_to_follow_point(delta, true) <= RETURN_DONE_M:
		_set_state(Ids.DS_FOLLOW)


func _tick_retreat(delta: float) -> void:
	_go_to_follow_point(delta, true)
	_regen(delta)
	if health >= max_health * _return_frac:
		_visual.set_retreating(false)
		_set_state(Ids.DS_FOLLOW)
		GameEvents.hud_message_requested.emit(MSG_RECOVERED, MSG_S)


func _tick_seek(delta: float) -> void:
	_retarget_timer -= delta
	if not _target_alive() or _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_S
		var nearest: Boar = _world.spawner.find_nearest_alive(get_xz(), _search_radius)
		if not _target_alive() or nearest != null:
			_target = nearest
	if not _target_alive():
		_target = null
		GameEvents.hud_message_requested.emit(MSG_NO_BOAR, MSG_S)
		_enter_return()
		return
	var dist: float = get_xz().distance_to(_target.get_xz())
	match _ability:
		&"bay":
			if dist <= BAY_START_M:
				_enter_bay()
				return
		&"hold":
			if dist <= _hold_distance():
				_enter_hold()
				return
		_:
			if dist <= POINT_DISTANCE_M:
				_enter_point()
				return
	_steer(Steering.seek(get_xz(), _target.get_xz()), _run_speed, delta)


# --- Abilities -----------------------------------------------------------------------------------

func _enter_point() -> void:
	_set_state(Ids.DS_POINT)
	_visual.set_locomotion(0.0)
	_visual.play_point()
	_sound_timer = 0.0
	_mark_target()


func _tick_point(delta: float) -> void:
	if not _target_alive():
		_enter_return()
		return
	var dist: float = get_xz().distance_to(_target.get_xz())
	if dist > POINT_DISTANCE_M * POINT_LOSE_MULT:
		_set_state(Ids.DS_SEEK)
		return
	_face(_target.get_xz(), delta)
	_tick_mark(delta)
	_sound_timer -= delta
	if _sound_timer <= 0.0:
		_sound_timer = BARK_POINT_S
		Sfx.play_3d(&"dog_bark", global_position)


func _enter_bay() -> void:
	_target.start_bayed(self, _bay_duration, _alpha_break_free)
	_ability_until = _world.get_elapsed_s() + _bay_duration
	var from_boar: Vector2 = get_xz() - _target.get_xz()
	_orbit_angle = atan2(from_boar.y, from_boar.x)
	_sound_timer = 0.0
	_set_state(Ids.DS_BAY)
	_mark_target()


func _tick_bay(delta: float) -> void:
	if not _target_alive() or _target.state != Ids.BS_BAYED or _world.get_elapsed_s() >= _ability_until:
		_release_target()
		_enter_return()
		return
	# Darts in and out around the boar, barking.
	_orbit_angle += BAY_ORBIT_RAD_S * delta
	var ring: float = BAY_RING_M + BAY_RING_SWING_M * sin(_state_time * BAY_SWING_RAD_S)
	var spot: Vector2 = _target.get_xz() + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * ring
	var dist: float = get_xz().distance_to(spot)
	if dist > 0.3:
		_steer(Steering.seek(get_xz(), spot), _follow_speed * Steering.arrive_scale(dist, FOLLOW_SLOW_RADIUS_M), delta)
	else:
		_face(_target.get_xz(), delta)
	_tick_mark(delta)
	_sound_timer -= delta
	if _sound_timer <= 0.0:
		_sound_timer = BARK_BAY_S
		_visual.play_bark()
		Sfx.play_3d(&"dog_bark", global_position)
	_take_boar_damage(delta)


func _enter_hold() -> void:
	_target.start_held(self, _hold_duration, _alpha_break_free)
	_sound_timer = 0.0
	_set_state(Ids.DS_HOLD)
	_visual.play_bite(true)
	_mark_target()


func _tick_hold(delta: float) -> void:
	if not _target_alive() or _target.state != Ids.BS_HELD:
		_visual.play_bite(false)
		_release_target()
		_enter_return()
		return
	_face(_target.get_xz(), delta)
	_tick_mark(delta)
	_sound_timer -= delta
	if _sound_timer <= 0.0:
		_sound_timer = GROWL_S
		Sfx.play_3d(&"dog_growl", global_position)
	_target.apply_dog_damage(_bite_dps * delta)
	if state == Ids.DS_HOLD:
		_take_boar_damage(delta)


func _hold_distance() -> float:
	return _target.body_scale * Boar.BODY_RADIUS_M + BODY_RADIUS_M + HOLD_GAP_M


func _take_boar_damage(delta: float) -> void:
	if not _target_alive():
		return
	var dps: float = _target.get_dog_damage_per_s()
	if dps > 0.0 and get_xz().distance_to(_target.get_xz()) <= BOAR_DAMAGE_RANGE_M:
		take_damage(dps * delta)


func _mark_target() -> void:
	_mark_timer = _mark_duration * REMARK_FRAC
	_world.mark_boar(_target.boar_id, _mark_duration)
	GameEvents.dog_marked_boar.emit(_target.global_position, _mark_duration)


func _tick_mark(delta: float) -> void:
	_mark_timer -= delta
	if _mark_timer <= 0.0:
		_mark_target()


func _release_target() -> void:
	if _target != null and is_instance_valid(_target):
		_target.release_from_dog()
	_target = null


func _target_alive() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_alive()


# --- Transitions ---------------------------------------------------------------------------------

func _enter_return() -> void:
	if state == Ids.DS_HOLD:
		_visual.play_bite(false)
	_release_target()
	_set_state(Ids.DS_RETURN)


func _enter_retreat() -> void:
	if state == Ids.DS_HOLD:
		_visual.play_bite(false)
	_release_target()
	_visual.set_retreating(true)
	Sfx.play_3d(&"dog_whine", global_position)
	_set_state(Ids.DS_RETREAT)
	GameEvents.hud_message_requested.emit(MSG_RETREAT, MSG_S)


func _set_state(new_state: StringName) -> void:
	if state == new_state:
		return
	state = new_state
	_state_time = 0.0
	GameEvents.dog_state_changed.emit(state)


# --- Helpers -------------------------------------------------------------------------------------

func _regen(delta: float) -> void:
	if health < max_health:
		health = minf(health + _regen_per_s * delta, max_health)
		_send_health(false)


func _send_health(force: bool) -> void:
	var pct: int = int(round(get_health_pct()))
	if force or pct != _last_pct_sent:
		_last_pct_sent = pct
		GameEvents.dog_health_changed.emit(get_health_pct())


func _steer(desired: Vector2, speed: float, delta: float) -> void:
	var pos: Vector2 = get_xz()
	var fwd: Vector2 = Steering.dir_from_yaw(_yaw)
	var dir: Vector2 = desired + _world.obstacles.avoidance(pos, fwd, AVOID_LOOKAHEAD_M, BODY_RADIUS_M)
	var align: float = 1.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
		_yaw = Steering.turn_toward(_yaw, Steering.yaw_from_dir(dir), TURN_RATE_RAD_S * delta)
		fwd = Steering.dir_from_yaw(_yaw)
		align = clampf(fwd.dot(dir), 0.0, 1.0)
	var v: float = speed * lerpf(MIN_ALIGN_SPEED_FRAC, 1.0, align)
	var p: Vector2 = Steering.clamp_to_rect(pos + fwd * v * delta, _world.get_map_rect(), MAP_MARGIN_M)
	p = _world.obstacles.resolve(p, BODY_RADIUS_M)
	position = Vector3(p.x, position.y, p.y)
	_speed = v


func _face(point: Vector2, delta: float) -> void:
	var to: Vector2 = point - get_xz()
	if to.length_squared() > 0.01:
		_yaw = Steering.turn_toward(_yaw, Steering.yaw_from_dir(to), TURN_RATE_RAD_S * delta)


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
