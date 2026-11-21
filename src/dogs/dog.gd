class_name Dog
extends Node3D
## Hunting dog (docs/arquitetura.md section 8.10). Kinematic steering over the heightmap, no physics
## body. Obeys GameEvents.dog_command_requested: "Pega!" from follow, "Volta!" otherwise.
## Abilities by breed data: point (caramelo), bay (foxhound), hold (dogo). Never dies.
## Network (docs/multiplayer.md section 6.5): the host simulates one Dog per hunter that brought one
## (owner_slot); a client sees DogPuppet replicas. Offline = owner_slot 0 = the local hunter, as before.

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
## EV_MESSAGE codes 3..5 (docs/multiplayer.md section 4.5) -> the text the owner reads.
const NET_MSG_NO_BOAR: int = 3
const NET_MSG_RETREAT: int = 4
const NET_MSG_RECOVERED: int = 5
const MESSAGES: Dictionary = {NET_MSG_NO_BOAR: MSG_NO_BOAR, NET_MSG_RETREAT: MSG_RETREAT, NET_MSG_RECOVERED: MSG_RECOVERED}
## Snapshot state byte (docs/multiplayer.md section 4.5): b0-2 index in NetCodec.DOG_STATES, b3 retreating, b4 biting.
const NET_ST_STATE_MASK: int = 7
const NET_ST_RETREATING: int = 8
const NET_ST_BITING: int = 16

var breed_id: StringName = &""
var owner_slot: int = 0
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
var _local: bool = true                # this dog belongs to the hunter of this machine (always true offline)
# Horde: the way round the open barn (_way_to). Rooms = route obstacles with an exit, their rect shrunk by
# route_room_inset_m (walls, not the roof overhang); empty outside the horde.
var _rooms: Array[Dictionary] = []
var _route: PackedVector2Array = PackedVector2Array()
var _route_i: int = 0
var _route_goal: Vector2 = Vector2.INF
var _route_timer: float = 0.0
var _route_corner_out: float = 0.0
var _route_arrive: float = 0.0           # a waypoint counts as reached this close (route_dog_arrive_m)
var _route_replan: float = 0.0           # the goal moved this far since the plan: plan again (route_waypoint_arrive_m)


func setup(p_breed_id: StringName, world: HuntController, spawn_position: Vector3, p_owner_slot: int = 0) -> void:
	breed_id = p_breed_id
	owner_slot = p_owner_slot
	_world = world
	_local = _world.get_local_slot() == owner_slot
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
	_read_rooms()
	var p: Vector2 = _world.obstacles.resolve(Vector2(spawn_position.x, spawn_position.z), BODY_RADIUS_M)
	position = Vector3(p.x, _world.get_height(p.x, p.y), p.y)
	var owner_hunter: PlayerBase = _world.get_hunter(owner_slot)
	if owner_hunter != null:
		_yaw = owner_hunter.rotation.y
	rotation.y = _yaw
	if _local:
		# Only the dog of this machine's hunter obeys the local command and talks to this machine's HUD.
		if not GameEvents.dog_command_requested.is_connected(command):
			GameEvents.dog_command_requested.connect(command)
		GameEvents.dog_state_changed.emit(state)
		_send_health(true)


func get_health_pct() -> float:
	return health / max_health * 100.0


func get_xz() -> Vector2:
	return Vector2(position.x, position.z)


## Where the boar this dog is after stands now; Vector3.INF without a living target (follow, retreat, return).
func get_target_position() -> Vector3:
	return _target.global_position if _target_alive() else Vector3.INF


func get_yaw() -> float:
	return _yaw


func is_local_owner() -> bool:
	return _local


## Host: stops what it is doing and leaves the world (its owner left the hunt).
func leave() -> void:
	_release_target()
	queue_free()


## State byte of the H_SNAPSHOT DOG record (docs/multiplayer.md section 4.5).
func net_state_byte() -> int:
	var b: int = maxi(NetCodec.DOG_STATES.find(state), 0) & NET_ST_STATE_MASK
	if state == Ids.DS_RETREAT:
		b |= NET_ST_RETREATING
	if state == Ids.DS_HOLD:
		b |= NET_ST_BITING
	return b


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

## "Pega!" from follow, "Volta!" otherwise. The local dog gets it from GameEvents.dog_command_requested;
## the others from the host's HuntHostSync (C_DOG_CMD of their owner).
func command() -> void:
	if _world == null or _world.is_hunt_over() or not _owner_alive():
		return
	if state == Ids.DS_FOLLOW:
		_target = _world.spawner.find_nearest_alive(get_xz(), _search_radius)
		_set_state(Ids.DS_SEEK)
		_report_command(Ids.CMD_ATTACK)
		Sfx.play_3d(&"dog_bark", global_position)
		return
	if state != Ids.DS_RETREAT:
		_enter_return()
	_report_command(Ids.CMD_RECALL)


func _report_command(cmd: StringName) -> void:
	if _local:
		GameEvents.dog_command_executed.emit(cmd)
	_world.report_dog_command(owner_slot, cmd)


# --- Frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _world == null:
		return
	_state_time += delta
	_speed = 0.0
	_hurt_timer = maxf(_hurt_timer - delta, 0.0)
	if state != Ids.DS_FOLLOW and state != Ids.DS_RETURN and state != Ids.DS_RETREAT and not _owner_alive():
		_enter_return()   # the owner died: let go of the boar and stay put
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


func _owner_alive() -> bool:
	var hunter: PlayerBase = _world.get_hunter(owner_slot)
	return hunter != null and hunter.is_alive()


## Behind and beside the owner. A dead (or gone) owner leaves the dog where it is.
func _follow_point() -> Vector2:
	var player: PlayerBase = _world.get_hunter(owner_slot)
	if player == null or not player.is_alive():
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
		var way: Vector2 = _way_to(point, delta)
		var direct: bool = way == point
		var slow: float = Steering.arrive_scale(dist, FOLLOW_SLOW_RADIUS_M) if direct else 1.0
		_steer(Steering.seek(get_xz(), way), speed * slow, delta, direct)
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
		_say(NET_MSG_RECOVERED)


func _tick_seek(delta: float) -> void:
	_retarget_timer -= delta
	if not _target_alive() or _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_S
		var nearest: Boar = _world.spawner.find_nearest_alive(get_xz(), _search_radius)
		if not _target_alive() or nearest != null:
			_target = nearest
	if not _target_alive():
		_target = null
		_say(NET_MSG_NO_BOAR)
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
	var way: Vector2 = _way_to(_target.get_xz(), delta)
	_steer(Steering.seek(get_xz(), way), _run_speed, delta, way == _target.get_xz())


# --- Way round the barn (horde) ------------------------------------------------------------------

## Horde (docs/plano_horda_nivel2.md C1-C2): the barn is an open room the dog walks in and out of by its front.
## Its walls are a row of steering circles a straight seek cannot get round, so the way to a goal goes through
## HordeRoute over the rooms among the horde route obstacles (the corn field is not one: the dog crosses it).
func _read_rooms() -> void:
	_rooms.clear()
	var horde: Dictionary = Data.get_horde_level(_world.get_horde_level()) if _world.is_horde() else {}
	_route_corner_out = maxf(float(horde.get("route_corner_out_m", 0.0)), 0.0)
	_route_arrive = maxf(float(horde.get("route_dog_arrive_m", 0.0)), 0.0)
	_route_replan = maxf(float(horde.get("route_waypoint_arrive_m", 0.0)), 0.0)
	# The route rect runs to the roof's edge: a dog under the eave behind a wall is outside, not in the room.
	var inset: float = maxf(float(horde.get("route_room_inset_m", 0.0)), 0.0)
	for o: Dictionary in _world.horde_route_obstacles:
		var exit: Vector2 = o.get("exit", Vector2.INF) as Vector2
		if exit.is_finite():
			_rooms.append({"rect": (o["rect"] as Rect2).grow(-inset), "exit": exit})


## The point to seek now on the way to `goal`: `goal` itself outside the horde or on the last leg, else the next
## waypoint (out of the room by its exit, round its corners, in by the exit). A leg to a waypoint is steered without
## obstacle avoidance (the route already keeps off the walls, and the sideways pushes of a row of wall circles can
## turn the dog into them); obstacles.resolve still keeps it out of every circle. Replanned every RETARGET_S and when
## the goal (the hunter's side, a boar) has moved more than route_waypoint_arrive_m since the plan.
func _way_to(goal: Vector2, delta: float) -> Vector2:
	if _rooms.is_empty():
		return goal
	_route_timer -= delta
	if _route_timer <= 0.0 or _route.is_empty() or goal.distance_to(_route_goal) > _route_replan:
		_route_timer = RETARGET_S
		_route_goal = goal
		_route = _plan_route(get_xz(), goal)
		_route_i = 0
	while _route_i < _route.size() - 1 and get_xz().distance_to(_route[_route_i]) < _route_arrive:
		_route_i += 1
	if _route_i >= _route.size() - 1:
		return goal
	return _route[_route_i]


## HordeRoute.plan over the rooms. A goal inside a room the dog is not in: to that room's exit first, then in.
func _plan_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	for o: Dictionary in _rooms:
		var r: Rect2 = o["rect"] as Rect2
		if r.has_point(to) and not r.has_point(from):
			var way: PackedVector2Array = HordeRoute.plan(from, o["exit"] as Vector2, _rooms, _route_corner_out)
			way.append(to)
			return way
	return HordeRoute.plan(from, to, _rooms, _route_corner_out)


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
	GameEvents.dog_marked_boar.emit(_target.global_position, _mark_duration)   # a mark is good for the whole team
	_world.report_dog_mark(owner_slot, _target.boar_id, _mark_duration)


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
	_say(NET_MSG_RETREAT)


func _set_state(new_state: StringName) -> void:
	if state == new_state:
		return
	state = new_state
	_state_time = 0.0
	if _local:
		GameEvents.dog_state_changed.emit(state)


# --- Helpers -------------------------------------------------------------------------------------

## HUD message for the owner: straight to the bus on this machine, EV_MESSAGE for a remote owner.
func _say(code: int) -> void:
	if _local:
		GameEvents.hud_message_requested.emit(String(MESSAGES[code]), MSG_S)
	else:
		_world.report_dog_message(owner_slot, code)


func _regen(delta: float) -> void:
	if health < max_health:
		health = minf(health + _regen_per_s * delta, max_health)
		_send_health(false)


func _send_health(force: bool) -> void:
	var pct: int = int(round(get_health_pct()))
	if force or pct != _last_pct_sent:
		_last_pct_sent = pct
		if _local:
			GameEvents.dog_health_changed.emit(get_health_pct())


func _steer(desired: Vector2, speed: float, delta: float, avoid: bool = true) -> void:
	var pos: Vector2 = get_xz()
	var fwd: Vector2 = Steering.dir_from_yaw(_yaw)
	var dir: Vector2 = desired
	if avoid:
		dir += _world.obstacles.avoidance(pos, fwd, AVOID_LOOKAHEAD_M, BODY_RADIUS_M)
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
