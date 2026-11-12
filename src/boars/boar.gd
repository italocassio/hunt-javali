class_name Boar
extends Node3D
## One wild boar. Kinematic steering over the heightmap (no physics body) plus the behaviour state
## machine of docs/arquitetura.md section 8.9. The four HitZone children belong to this root, not to
## the visual. Usage: instantiate -> setup() -> add_child -> start().

signal died(boar: Boar)

# --- Rules the contract fixes in text (not present in data/) ---
const VISION_CROUCH_MULT: float = 0.6
const VISION_SPRINT_MULT: float = 1.3
const SEPARATION_RADIUS_M: float = 1.5
const AVOID_LOOKAHEAD_M: float = 4.0
const MAP_MARGIN_M: float = 4.0
const CHARGE_OVERSHOOT_M: float = 4.0
const HIT_BASE_RADIUS_M: float = 0.5
const HIT_RADIUS_PER_SCALE_M: float = 0.6
## Snout tip of the reference model (scale 1), see section 7.1.
const SNOUT_OFFSET_M: float = 0.8
const EYE_HEIGHT_M: float = 0.6
const BODY_RADIUS_M: float = 0.35

# --- Package tuning (movement feel) ---
const SEPARATION_WEIGHT: float = 1.2
const AVOID_WEIGHT: float = 1.0
const MIN_ALIGN_SPEED_FRAC: float = 0.25
const TILT_LERP_PER_S: float = 8.0
const ARRIVE_M: float = 1.0
const SLOW_RADIUS_M: float = 2.5
const TROT_FRAC: float = 0.45

# --- Package tuning (behaviour) ---
const WANDER_RADIUS_M: float = 10.0
const WANDER_PAUSE_MIN_S: float = 1.0
const WANDER_PAUSE_MAX_S: float = 4.0
const WANDER_LEG_TIMEOUT_S: float = 12.0
const HERD_SPREAD_M: float = 7.0
const EAT_SHIFT_MIN_S: float = 8.0
const EAT_SHIFT_MAX_S: float = 16.0
const EAT_SHIFT_RADIUS_M: float = 5.0
const BAIT_RING_M: float = 0.9
const ALERT_MEMORY_S: float = 0.5
const FLEE_ARRIVE_M: float = 4.0
const FLEE_SPREAD_M: float = 5.0
const FLEE_AWAY_M: float = 45.0
const FLEE_REPLAN_S: float = 4.0
## A charge starts (scrape) at this fraction of charge_max_distance_m; farther boars close in first.
const CHARGE_START_FRAC: float = 0.6
const APPROACH_TIMEOUT_S: float = 12.0
const CHARGE_BLOCKED_FRAC: float = 0.3
const CHARGE_HEIGHT_TOLERANCE_M: float = 2.0
const RECOVER_SLIDE_S: float = 0.5
const RECOVER_SLIDE_SPEED_FRAC: float = 0.5
const RECOVER_TURN_FRAC: float = 0.35
const DISENGAGE_RANGE_MULT: float = 1.5
const GRUNT_MIN_S: float = 6.0
const GRUNT_MAX_S: float = 16.0
const EAT_SOUND_CHANCE: float = 0.5
const SNORT_CHANCE: float = 0.5
const QUIET_DB: float = -6.0
const ROAR_DB: float = 3.0
const HIT_ZONE_NODES: Dictionary = {
	&"head": ^"HitHead", &"vital": ^"HitVital", &"body": ^"HitBody", &"rear": ^"HitRear",
}

var boar_id: int = -1
var type_id: StringName = &""
var weight_kg: float = 100.0
var state: StringName = &""
var herd: BoarHerd = null
var health: float = 100.0
var max_health: float = 100.0
var wounded: bool = false
var killing_zone: StringName = &""
var body_scale: float = 1.0

var _world: HuntController = null
var _visual: BoarVisualBase = null
var _zone_mults: Dictionary = {}

# Type data (cached, typed)
var _walk_speed: float = 1.4
var _run_speed: float = 7.0
var _charge_speed: float = 0.0
var _turn_rate: float = PI
var _aggression: StringName = &"never"
var _aggro_radius: float = 0.0
var _max_charges: int = 0
var _charge_damage: float = 0.0
var _telegraph_s: float = 0.8
var _charge_max_dist: float = 0.0
var _recover_s: float = 0.0
var _vision_range: float = 35.0
var _cos_half_fov: float = 0.5
var _hearing_mult: float = 1.0
var _alert_time: float = 1.0
var _drain_pct_per_s: float = 0.1
var _wounded_frac: float = 0.35
var _wounded_speed_mult: float = 0.6
var _rest_min: float = 20.0
var _rest_max: float = 35.0
var _dog_damage_per_s: float = 0.0
var _perception_interval: float = 0.2
var _sprint_threshold_mps: float = 5.0
var _knockback_mps: float = 6.0

# Motion
var _yaw: float = 0.0
var _speed: float = 0.0
var _up: Vector3 = Vector3.UP
var _radius: float = BODY_RADIUS_M

# Behaviour
var _state_time: float = 0.0
var _perception_timer: float = 0.0
var _detects: bool = false
var _threat: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _pause_until: float = 0.0
var _leg_until: float = 0.0
var _eating_here: bool = false
var _eat_shift_time: float = 0.0
var _bait: Bait = null
var _approaching: bool = false
var _flee_resting: bool = false
var _flee_replan_time: float = 0.0
var _charges_done: int = 0
var _engaged: bool = false
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_travelled: float = 0.0
var _charge_limit: float = 0.0
var _charge_hit_done: bool = false
var _dog: Node3D = null
var _dog_until: float = 0.0
var _voice_time: float = 0.0
var _highlight: bool = false

# One-shot bookkeeping
var _first_shot_id: int = 0
var _multi_shot: bool = false
var _dog_damaged: bool = false

var _los_query: PhysicsRayQueryParameters3D = null


func setup(p_id: int, p_type_id: StringName, p_weight_kg: float, p_herd: BoarHerd, p_world: HuntController) -> void:
	boar_id = p_id
	type_id = p_type_id
	weight_kg = p_weight_kg
	herd = p_herd
	_world = p_world
	name = "Boar_%d" % boar_id
	body_scale = BoarVisualBase.scale_for_weight(weight_kg)
	_radius = BODY_RADIUS_M * body_scale
	_read_type(Data.get_boar_type(type_id))
	_zone_mults = Data.get_boar_rules().get("zone_multipliers", {})
	var game: Dictionary = Data.get_game()
	var hunt: Dictionary = game.get("hunt", {})
	var player_def: Dictionary = game.get("player", {})
	_perception_interval = maxf(float(hunt.get("boar_perception_interval_s", 0.2)), 0.02)
	_sprint_threshold_mps = (float(player_def.get("walk_speed_mps", 4.0)) + float(player_def.get("sprint_speed_mps", 6.5))) * 0.5
	_knockback_mps = float(player_def.get("knockback_mps", 6.0))
	_perception_timer = fmod(float(boar_id) * 0.37, 1.0) * _perception_interval
	_build_visual()
	_build_hit_zones()
	herd.add(self)


## Places the boar and enters the first state. Call after add_child.
func start(pos: Vector2, yaw: float) -> void:
	_yaw = yaw
	position = Vector3(pos.x, _world.heightmap.get_height(pos.x, pos.y), pos.y)
	_up = _world.heightmap.get_normal(pos.x, pos.y)
	_apply_basis()
	_voice_time = _world.rng.randf_range(GRUNT_MIN_S, GRUNT_MAX_S)
	_enter_wander()


func is_alive() -> bool:
	return state != Ids.BS_DEAD


func get_xz() -> Vector2:
	return Vector2(position.x, position.z)


func get_zone_position(zone: StringName) -> Vector3:
	if not BoarVisualBase.HIT_ZONES.has(zone):
		return Vector3.INF
	var def: Array = BoarVisualBase.HIT_ZONES[zone] as Array
	return to_global((def[0] as Vector3) * body_scale)


func is_one_shot() -> bool:
	return _first_shot_id != 0 and not _multi_shot and not _dog_damaged


func is_aggressive_type() -> bool:
	return _aggression == &"provoked" or _aggression == &"always"


## Damage per second this boar deals to a dog within DOG_DAMAGE_RANGE_M (only provoked/always).
func get_dog_damage_per_s() -> float:
	return _dog_damage_per_s if is_aggressive_type() else 0.0


func hearing_radius(noise_radius_m: float) -> float:
	return noise_radius_m * _hearing_mult


func set_highlight(on: bool) -> void:
	if on == _highlight or state == Ids.BS_DEAD:
		return
	_highlight = on
	_visual.set_highlight(on)


# --- Herd interface ------------------------------------------------------------------------------

## Shared alert: a herd mate saw or heard the player.
func receive_alert(threat: Vector2) -> void:
	if not _is_calm():
		return
	_threat = threat
	_enter_alert(false)


## Shared reaction (shot heard, a member hit, or an alert that ended still detecting).
func react(threat: Vector2, herd_hit: bool) -> void:
	if state == Ids.BS_DEAD or state == Ids.BS_BAYED or state == Ids.BS_HELD:
		return
	_threat = threat
	if herd_hit and is_aggressive_type():
		_engaged = true
	if state == Ids.BS_SCRAPE or state == Ids.BS_CHARGE or state == Ids.BS_RECOVER:
		return
	if state == Ids.BS_ALERT and _approaching:
		return
	if state == Ids.BS_FLEE and not _flee_resting and not (herd_hit and is_aggressive_type()):
		return
	_decide(threat, herd_hit)


# --- Dog interface -------------------------------------------------------------------------------

## Foxhound: the boar stops and faces the dog. Alpha breaks free earlier.
func start_bayed(dog: Node3D, duration_s: float, alpha_break_free_s: float) -> void:
	if state == Ids.BS_DEAD:
		return
	_leave_activity()
	_dog = dog
	_dog_until = _now() + _dog_time(duration_s, alpha_break_free_s)
	_set_state(Ids.BS_BAYED)
	_visual.play_alert()


## Dogo: the boar cannot move. Alpha breaks free earlier.
func start_held(dog: Node3D, duration_s: float, alpha_break_free_s: float) -> void:
	if state == Ids.BS_DEAD:
		return
	_leave_activity()
	_dog = dog
	_dog_until = _now() + _dog_time(duration_s, alpha_break_free_s)
	_set_state(Ids.BS_HELD)


func release_from_dog() -> void:
	if state == Ids.BS_BAYED or state == Ids.BS_HELD:
		_dog = null
		_reevaluate()


func apply_dog_damage(amount: float) -> void:
	if state == Ids.BS_DEAD or amount <= 0.0:
		return
	_dog_damaged = true
	health -= amount
	if health <= 0.0:
		_die(Ids.ZONE_DOG)
		return
	_update_wounded()


# --- Debug ---------------------------------------------------------------------------------------

func debug_kill() -> void:
	if state == Ids.BS_DEAD:
		return
	health = 0.0
	_multi_shot = true
	_die(Ids.ZONE_BODY)


# --- Frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if state == Ids.BS_DEAD or _world == null:
		return
	_state_time += delta
	_speed = 0.0
	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer += _perception_interval
		_perceive()
		_after_perception()
		if state == Ids.BS_DEAD:
			return
	match state:
		Ids.BS_WANDER:
			_tick_wander(delta)
		Ids.BS_TO_CROP:
			_tick_to_crop(delta)
		Ids.BS_TO_BAIT:
			_tick_to_bait(delta)
		Ids.BS_EAT:
			_tick_eat(delta)
		Ids.BS_ALERT:
			_tick_alert(delta)
		Ids.BS_FLEE:
			_tick_flee(delta)
		Ids.BS_SCRAPE:
			_tick_scrape(delta)
		Ids.BS_CHARGE:
			_tick_charge(delta)
		Ids.BS_RECOVER:
			_tick_recover(delta)
		Ids.BS_BAYED, Ids.BS_HELD:
			_tick_dog_locked(delta)
	_settle(delta)
	_visual.set_locomotion(_speed)
	_tick_voice(delta)


# --- Perception ----------------------------------------------------------------------------------

func _perceive() -> void:
	_detects = false
	var player: PlayerBase = _world.get_player()
	if player == null or not player.is_alive():
		return
	var ppos: Vector3 = player.global_position
	var to: Vector2 = Vector2(ppos.x - position.x, ppos.z - position.z)
	var dist: float = to.length()
	if dist < player.get_noise_radius():
		_detects = true
		return
	var vision: float = _vision_range
	if player.is_crouching():
		vision *= VISION_CROUCH_MULT
	elif Vector2(player.velocity.x, player.velocity.z).length() > _sprint_threshold_mps:
		vision *= VISION_SPRINT_MULT
	if dist > vision:
		return
	if dist > 0.5 and Steering.dir_from_yaw(_yaw).dot(to / dist) < _cos_half_fov:
		return
	_detects = _has_line_of_sight(player)


func _has_line_of_sight(player: PlayerBase) -> bool:
	if not is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return true
	if _los_query == null:
		_los_query = PhysicsRayQueryParameters3D.new()
		_los_query.collision_mask = Layers.MASK_LINE_OF_SIGHT
		_los_query.collide_with_areas = false
		_los_query.collide_with_bodies = true
	_los_query.from = global_position + Vector3(0.0, EYE_HEIGHT_M * body_scale, 0.0)
	_los_query.to = player.get_eye_position()
	return space.intersect_ray(_los_query).is_empty()


func _after_perception() -> void:
	if _detects:
		var player: PlayerBase = _world.get_player()
		_threat = Vector2(player.global_position.x, player.global_position.z)
		herd.last_detect_time = _now()
		if _is_calm():
			herd.raise_alert(self, _threat)
			return
	if state == Ids.BS_WANDER or state == Ids.BS_TO_CROP or (state == Ids.BS_EAT and _bait == null):
		var bait: Bait = _world.find_bait(get_xz(), boar_id)
		if bait != null:
			_bait = bait
			_enter_to_bait()


func _is_calm() -> bool:
	return state == Ids.BS_WANDER or state == Ids.BS_TO_CROP or state == Ids.BS_TO_BAIT \
		or state == Ids.BS_EAT or (state == Ids.BS_FLEE and _flee_resting)


# --- Decisions -----------------------------------------------------------------------------------

func _wants_charge(dist: float, herd_hit: bool) -> bool:
	if _charge_speed <= 0.0 or _charges_done >= _max_charges:
		return false
	var player: PlayerBase = _world.get_player()
	if player == null or not player.is_alive() or _world.is_hunt_over():
		return false
	match _aggression:
		&"always":
			return true
		&"provoked":
			return _engaged or herd_hit or dist <= _aggro_radius
		&"defend_in_herd":
			return not wounded and herd.alive_count() >= 2 and dist <= _aggro_radius
	return false


func _decide(threat: Vector2, herd_hit: bool) -> void:
	var dist: float = get_xz().distance_to(threat)
	if _wants_charge(dist, herd_hit):
		_engaged = true
		_begin_attack(dist)
	else:
		_enter_flee()


func _begin_attack(dist: float) -> void:
	if dist <= _charge_max_dist * CHARGE_START_FRAC:
		_enter_scrape()
	else:
		_enter_approach()


## After recover / dog release: charge again, flee, or go back to feeding.
func _reevaluate() -> void:
	var player: PlayerBase = _world.get_player()
	if player == null or not player.is_alive() or _world.is_hunt_over():
		_resume()
		return
	_threat = Vector2(player.global_position.x, player.global_position.z)
	var dist: float = get_xz().distance_to(_threat)
	var in_reach: bool = dist <= maxf(_vision_range, _aggro_radius) * DISENGAGE_RANGE_MULT
	if in_reach and _wants_charge(dist, false):
		_begin_attack(dist)
	elif _aggression == &"always":
		_resume()
	else:
		_enter_flee()


## Back to the calm routine without resetting the feeding trip.
func _resume() -> void:
	_end_encounter()
	if _bait_valid():
		_enter_to_bait()
	elif _now() < herd.wander_end_time:
		_enter_wander()
	else:
		_enter_to_crop()


func _begin_feeding_trip() -> void:
	_end_encounter()
	if not _bait_valid():
		_bait = _world.find_bait(get_xz(), boar_id)
	if _bait != null:
		_enter_to_bait()
	else:
		_enter_to_crop()


func _end_encounter() -> void:
	_charges_done = 0
	_engaged = false
	_approaching = false


# --- States: calm --------------------------------------------------------------------------------

func _enter_wander() -> void:
	_leave_activity()
	_pick_wander_target()
	_set_state(Ids.BS_WANDER)


func _pick_wander_target() -> void:
	var rng: RandomNumberGenerator = _world.rng
	var ang: float = rng.randf_range(0.0, TAU)
	var rad: float = sqrt(rng.randf()) * WANDER_RADIUS_M
	_target = Steering.clamp_to_rect(herd.anchor + Vector2(cos(ang), sin(ang)) * rad, _world.get_map_rect(), MAP_MARGIN_M)
	_leg_until = _now() + WANDER_LEG_TIMEOUT_S
	_pause_until = 0.0


func _tick_wander(delta: float) -> void:
	var now: float = _now()
	if now >= herd.wander_end_time:
		_begin_feeding_trip()
		return
	if now < _pause_until:
		return
	if _pause_until > 0.0:
		_pick_wander_target()
	var dist: float = get_xz().distance_to(_target)
	if dist < ARRIVE_M or now > _leg_until:
		_pause_until = now + _world.rng.randf_range(WANDER_PAUSE_MIN_S, WANDER_PAUSE_MAX_S)
		return
	_steer(Steering.seek(get_xz(), _target), _speed_for(_walk_speed), delta)


func _enter_to_crop() -> void:
	_leave_activity()
	herd.ensure_crop_target(_world.crop.get_rects(), _now(), _world.rng)
	_target = _spread_point(herd.crop_target, HERD_SPREAD_M, herd.crop_rect)
	_set_state(Ids.BS_TO_CROP)


func _tick_to_crop(delta: float) -> void:
	var dist: float = get_xz().distance_to(_target)
	if dist < ARRIVE_M:
		_enter_eat()
		return
	_steer(Steering.seek(get_xz(), _target), _speed_for(_walk_speed) * Steering.arrive_scale(dist, SLOW_RADIUS_M), delta)


func _enter_to_bait() -> void:
	_leave_activity()
	var ang: float = float(boar_id) * 2.4
	_target = _bait.get_xz() + Vector2(cos(ang), sin(ang)) * (BAIT_RING_M + _radius)
	_set_state(Ids.BS_TO_BAIT)


func _tick_to_bait(delta: float) -> void:
	if not _bait_valid():
		_bait = null
		_begin_feeding_trip()
		return
	var dist: float = get_xz().distance_to(_target)
	if dist < ARRIVE_M:
		_enter_eat()
		return
	var trot: float = lerpf(_walk_speed, _run_speed, TROT_FRAC)
	_steer(Steering.seek(get_xz(), _target), _speed_for(trot) * Steering.arrive_scale(dist, SLOW_RADIUS_M), delta)


func _enter_eat() -> void:
	_eat_shift_time = _now() + _world.rng.randf_range(EAT_SHIFT_MIN_S, EAT_SHIFT_MAX_S)
	_target = get_xz()
	_set_state(Ids.BS_EAT)
	_set_eating_here(true)


func _tick_eat(delta: float) -> void:
	if _bait != null:
		if not _bait_valid():
			_bait = null
			_set_eating_here(false)
			_begin_feeding_trip()
		return
	var now: float = _now()
	var dist: float = get_xz().distance_to(_target)
	if dist > ARRIVE_M:
		_steer(Steering.seek(get_xz(), _target), _speed_for(_walk_speed), delta)
		return
	if not _eating_here:
		_set_eating_here(true)
	if now >= _eat_shift_time:
		_eat_shift_time = now + _world.rng.randf_range(EAT_SHIFT_MIN_S, EAT_SHIFT_MAX_S)
		_target = _spread_point(get_xz(), EAT_SHIFT_RADIUS_M, herd.crop_rect)
		if get_xz().distance_to(_target) > ARRIVE_M:
			_set_eating_here(false)


## Head down + crop drain (the bait holds the boar without draining).
func _set_eating_here(on: bool) -> void:
	_eating_here = on
	_visual.set_eating(on)
	if on and _bait == null:
		_world.crop.register_eater(boar_id, _drain_pct_per_s * _world.crop_drain_mult, get_xz())
	else:
		_world.crop.unregister_eater(boar_id)


# --- States: alert / approach --------------------------------------------------------------------

func _enter_alert(is_source: bool) -> void:
	_leave_activity()
	_approaching = false
	_set_state(Ids.BS_ALERT)
	_visual.play_alert()
	if is_source or _world.rng.randf() < SNORT_CHANCE:
		Sfx.play_3d(&"boar_snort_alert", global_position, 0.0, _voice_pitch())


## Aggressive boar too far for a charge: runs at the player, then scrapes. Reported as "alert"
## (the contract has no state id for closing in).
func _enter_approach() -> void:
	_leave_activity()
	_approaching = true
	if state != Ids.BS_ALERT:
		_set_state(Ids.BS_ALERT)
	_state_time = 0.0


func _tick_alert(delta: float) -> void:
	if _approaching:
		_tick_approach(delta)
		return
	_face(_threat, delta, 1.0)
	if _state_time < _alert_time:
		return
	if _now() - herd.last_detect_time <= ALERT_MEMORY_S:
		herd.raise_reaction(_threat, false)
		if state == Ids.BS_ALERT and not _approaching:
			_decide(_threat, false)
	else:
		_resume()


func _tick_approach(delta: float) -> void:
	var player: PlayerBase = _world.get_player()
	if player == null or not player.is_alive() or _world.is_hunt_over():
		_resume()
		return
	_threat = Vector2(player.global_position.x, player.global_position.z)
	var dist: float = get_xz().distance_to(_threat)
	if dist <= _charge_max_dist * CHARGE_START_FRAC:
		_enter_scrape()
		return
	if _state_time > APPROACH_TIMEOUT_S:
		if _aggression == &"always":
			_resume()
		else:
			_enter_flee()
		return
	_steer(Steering.seek(get_xz(), _threat), _speed_for(_run_speed), delta)


# --- States: flee --------------------------------------------------------------------------------

func _enter_flee() -> void:
	_leave_activity()
	_release_bait()
	_approaching = false
	_flee_resting = false
	_plan_flee()
	if state != Ids.BS_FLEE:
		_set_state(Ids.BS_FLEE)
		if type_id == Ids.PIGLET or wounded:
			Sfx.play_3d(&"boar_squeal", global_position, QUIET_DB, _voice_pitch())
	_state_time = 0.0


func _plan_flee() -> void:
	var pos: Vector2 = get_xz()
	var retreat: Vector2 = herd.get_retreat(_threat, pos, _world.retreat_zones, _now())
	if pos.distance_to(retreat) < FLEE_ARRIVE_M * 2.0:
		# Already at the refuge and still threatened: run straight away from the hunter.
		retreat = pos + Steering.flee(pos, _threat) * FLEE_AWAY_M
	_target = Steering.clamp_to_rect(_spread_point(retreat, FLEE_SPREAD_M, _world.get_map_rect()),
		_world.get_map_rect(), MAP_MARGIN_M)
	_flee_replan_time = _now() + FLEE_REPLAN_S


func _tick_flee(delta: float) -> void:
	var now: float = _now()
	if _flee_resting:
		if now >= herd.rest_until:
			_begin_feeding_trip()
		return
	var dist: float = get_xz().distance_to(_target)
	if dist < FLEE_ARRIVE_M:
		_flee_resting = true
		if herd.rest_until < now:
			herd.rest_until = now + _world.rng.randf_range(_rest_min, _rest_max)
		return
	_steer(Steering.seek(get_xz(), _target), _speed_for(_run_speed), delta)


# --- States: scrape / charge / recover -----------------------------------------------------------

func _enter_scrape() -> void:
	_leave_activity()
	_approaching = false
	_set_state(Ids.BS_SCRAPE)
	_visual.play_scrape()
	Sfx.play_3d(&"boar_scrape", global_position, 0.0, _voice_pitch())
	Sfx.play_3d(&"boar_grunt", global_position, 0.0, _voice_pitch())


func _tick_scrape(delta: float) -> void:
	var player: PlayerBase = _world.get_player()
	if player == null or not player.is_alive() or _world.is_hunt_over():
		_resume()
		return
	_threat = Vector2(player.global_position.x, player.global_position.z)
	_face(_threat, delta, 1.0)
	if _state_time >= _telegraph_s:
		_enter_charge()


func _enter_charge() -> void:
	var pos: Vector2 = get_xz()
	var to: Vector2 = _threat - pos
	var dist: float = to.length()
	_charge_dir = to / dist if dist > 0.01 else Steering.dir_from_yaw(_yaw)
	_yaw = Steering.yaw_from_dir(_charge_dir)   # direction is locked from here on
	_charge_travelled = 0.0
	_charge_limit = minf(dist + CHARGE_OVERSHOOT_M, _charge_max_dist)
	_charge_hit_done = false
	_charges_done += 1
	_set_state(Ids.BS_CHARGE)
	Sfx.play_3d(&"boar_charge_roar", global_position, ROAR_DB, _voice_pitch())


func _tick_charge(delta: float) -> void:
	var speed: float = _speed_for(_charge_speed)
	var before: Vector2 = get_xz()
	_move_to(before + _charge_dir * speed * delta)
	var moved: float = get_xz().distance_to(before)
	_speed = speed
	_charge_travelled += moved
	if _try_charge_hit():
		_enter_recover()
		return
	if _charge_travelled >= _charge_limit or moved < speed * delta * CHARGE_BLOCKED_FRAC:
		_enter_recover()


## Section 8.3: snout within reach and the player in the frontal half-circle; once per charge.
func _try_charge_hit() -> bool:
	if _charge_hit_done or _world.is_hunt_over():
		return false
	var player: PlayerBase = _world.get_player()
	if player == null or not player.is_alive():
		return false
	var ppos: Vector3 = player.global_position
	if absf(ppos.y - position.y) > CHARGE_HEIGHT_TOLERANCE_M:
		return false
	var pos: Vector2 = get_xz()
	var pxz: Vector2 = Vector2(ppos.x, ppos.z)
	var snout: Vector2 = pos + _charge_dir * SNOUT_OFFSET_M * body_scale
	if (pxz - pos).dot(_charge_dir) <= 0.0:
		return false
	if snout.distance_to(pxz) >= HIT_BASE_RADIUS_M + HIT_RADIUS_PER_SCALE_M * body_scale:
		return false
	_charge_hit_done = true
	player.apply_damage(_charge_damage, global_position, _knockback_mps)
	_visual.play_attack()
	return true


func _enter_recover() -> void:
	_set_state(Ids.BS_RECOVER)


func _tick_recover(delta: float) -> void:
	if _state_time < RECOVER_SLIDE_S:
		# Momentum carries it past the hunter before it can turn around.
		var k: float = 1.0 - _state_time / RECOVER_SLIDE_S
		var speed: float = _speed_for(_charge_speed) * RECOVER_SLIDE_SPEED_FRAC * k
		_move_to(get_xz() + Steering.dir_from_yaw(_yaw) * speed * delta)
		_speed = speed
	else:
		_face(_threat, delta, RECOVER_TURN_FRAC)
	if _state_time >= maxf(_recover_s, RECOVER_SLIDE_S):
		_reevaluate()


# --- States: dog ---------------------------------------------------------------------------------

func _tick_dog_locked(delta: float) -> void:
	if _dog == null or not is_instance_valid(_dog) or _now() >= _dog_until:
		_dog = null
		_reevaluate()
		return
	if state == Ids.BS_BAYED:
		_face(Vector2(_dog.global_position.x, _dog.global_position.z), delta, 1.0)


func _dog_time(duration_s: float, alpha_break_free_s: float) -> float:
	if type_id == Ids.ALPHA and alpha_break_free_s > 0.0:
		return minf(duration_s, alpha_break_free_s)
	return duration_s


# --- Damage --------------------------------------------------------------------------------------

func _on_hit_received(hit: HitInfo) -> void:
	if state == Ids.BS_DEAD:
		return
	var final: float = hit.damage * float(_zone_mults.get(String(hit.zone), 1.0))
	if _first_shot_id == 0:
		_first_shot_id = hit.shot_id
	elif hit.shot_id != _first_shot_id:
		_multi_shot = true
	health -= final
	GameEvents.boar_hit.emit(boar_id, hit.zone, final, hit.position, hit.shot_id)
	if health <= 0.0:
		_die(hit.zone)
		return
	_visual.play_hit(hit.zone)
	Sfx.play_3d(&"boar_squeal", global_position, 0.0, _voice_pitch())
	_update_wounded()
	if is_aggressive_type():
		_engaged = true
	var player: PlayerBase = _world.get_player()
	var threat: Vector2 = Vector2(hit.origin.x, hit.origin.z)
	if player != null:
		threat = Vector2(player.global_position.x, player.global_position.z)
	herd.last_detect_time = _now()
	herd.raise_reaction(threat, true)


func _update_wounded() -> void:
	if wounded or health >= max_health * _wounded_frac:
		return
	wounded = true
	_visual.set_wounded(true)


func _die(zone: StringName) -> void:
	killing_zone = zone
	health = 0.0
	_leave_activity()
	_release_bait()
	for path: NodePath in HIT_ZONE_NODES.values():
		var hz: HitZone = get_node_or_null(path) as HitZone
		if hz != null:
			hz.disable()
	if _highlight:
		_visual.set_highlight(false)
		_highlight = false
	_dog = null
	_speed = 0.0
	_set_state(Ids.BS_DEAD)
	_visual.set_locomotion(0.0)
	_visual.play_death()
	Sfx.play_3d(&"boar_death", global_position, 0.0, _voice_pitch())
	set_process(false)
	died.emit(self)


# --- Motion --------------------------------------------------------------------------------------

func _speed_for(base: float) -> float:
	return base * _wounded_speed_mult if wounded else base


## Steers toward `desired` (unit XZ direction) with herd separation and obstacle avoidance.
func _steer(desired: Vector2, speed: float, delta: float) -> void:
	var pos: Vector2 = get_xz()
	var fwd: Vector2 = Steering.dir_from_yaw(_yaw)
	var dir: Vector2 = desired
	dir += Steering.separation(pos, self, herd.members, SEPARATION_RADIUS_M) * SEPARATION_WEIGHT
	dir += _world.obstacles.avoidance(pos, fwd, AVOID_LOOKAHEAD_M, _radius) * AVOID_WEIGHT
	var align: float = 1.0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
		_yaw = Steering.turn_toward(_yaw, Steering.yaw_from_dir(dir), _turn_rate * delta)
		fwd = Steering.dir_from_yaw(_yaw)
		align = clampf(fwd.dot(dir), 0.0, 1.0)
	var v: float = speed * lerpf(MIN_ALIGN_SPEED_FRAC, 1.0, align)
	_move_to(pos + fwd * v * delta)
	_speed = v


func _face(point: Vector2, delta: float, rate_frac: float) -> void:
	var to: Vector2 = point - get_xz()
	if to.length_squared() < 0.01:
		return
	_yaw = Steering.turn_toward(_yaw, Steering.yaw_from_dir(to), _turn_rate * rate_frac * delta)


func _move_to(pos: Vector2) -> void:
	var p: Vector2 = Steering.clamp_to_rect(pos, _world.get_map_rect(), MAP_MARGIN_M)
	p = _world.obstacles.resolve(p, _radius)
	position = Vector3(p.x, _world.heightmap.get_height(p.x, p.y), p.y)


## Keeps the feet on the ground and tilts the body with the slope.
func _settle(delta: float) -> void:
	position.y = _world.heightmap.get_height(position.x, position.z)
	var n: Vector3 = _world.heightmap.get_normal(position.x, position.z)
	_up = _up.lerp(n, clampf(TILT_LERP_PER_S * delta, 0.0, 1.0)).normalized()
	_apply_basis()


func _apply_basis() -> void:
	var f2: Vector2 = Steering.dir_from_yaw(_yaw)
	var fwd: Vector3 = Vector3(f2.x, 0.0, f2.y)
	var right: Vector3 = fwd.cross(_up)
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var forward: Vector3 = _up.cross(right).normalized()
	basis = Basis(right, _up, -forward)


func _spread_point(center: Vector2, radius: float, rect: Rect2) -> Vector2:
	var rng: RandomNumberGenerator = _world.rng
	var ang: float = rng.randf_range(0.0, TAU)
	var rad: float = sqrt(rng.randf()) * radius
	var p: Vector2 = center + Vector2(cos(ang), sin(ang)) * rad
	return Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))


# --- Helpers -------------------------------------------------------------------------------------

func _now() -> float:
	return _world.get_elapsed_s()


func _bait_valid() -> bool:
	return _bait != null and is_instance_valid(_bait) and _bait.active


func _release_bait() -> void:
	if _bait != null and is_instance_valid(_bait):
		_bait.release(boar_id)
	_bait = null


## Stops eating (head up, crop drain off). Keeps the bait reservation.
func _leave_activity() -> void:
	if _eating_here or state == Ids.BS_EAT:
		_set_eating_here(false)


func _set_state(new_state: StringName) -> void:
	if state == new_state:
		return
	state = new_state
	_state_time = 0.0
	GameEvents.boar_state_changed.emit(boar_id, state)


func _voice_pitch() -> float:
	# Heavier animals sound deeper.
	return clampf(1.0 / body_scale, 0.75, 1.5)


func _tick_voice(delta: float) -> void:
	_voice_time -= delta
	if _voice_time > 0.0:
		return
	_voice_time = _world.rng.randf_range(GRUNT_MIN_S, GRUNT_MAX_S)
	if state == Ids.BS_EAT and _eating_here:
		if _world.rng.randf() < EAT_SOUND_CHANCE:
			Sfx.play_3d(&"boar_eat", global_position, QUIET_DB, _voice_pitch())
	elif state == Ids.BS_WANDER or state == Ids.BS_TO_CROP or state == Ids.BS_TO_BAIT:
		Sfx.play_3d(&"boar_grunt", global_position, QUIET_DB, _voice_pitch())


func _read_type(def: Dictionary) -> void:
	max_health = maxf(weight_kg * float(def.get("health_per_kg", 1.0)), 1.0)
	health = max_health
	_walk_speed = float(def.get("walk_speed_mps", 1.4))
	_run_speed = float(def.get("run_speed_mps", 7.0))
	_charge_speed = float(def.get("charge_speed_mps", 0.0))
	_turn_rate = deg_to_rad(float(def.get("turn_speed_deg_s", 200.0)))
	_aggression = StringName(String(def.get("aggression", "never")))
	_aggro_radius = float(def.get("aggro_radius_m", 0.0))
	_max_charges = int(def.get("max_charges", 0))
	_charge_damage = float(def.get("charge_damage", 0.0))
	_telegraph_s = float(def.get("charge_telegraph_s", 0.8))
	_charge_max_dist = float(def.get("charge_max_distance_m", 0.0))
	_recover_s = float(def.get("recover_s", 0.0))
	_vision_range = float(def.get("vision_range_m", 35.0))
	_cos_half_fov = cos(deg_to_rad(float(def.get("vision_fov_deg", 120.0)) * 0.5))
	_hearing_mult = float(def.get("hearing_mult", 1.0))
	_alert_time = float(def.get("alert_time_s", 1.0))
	_drain_pct_per_s = float(def.get("crop_drain_pct_per_s", 0.1))
	_wounded_frac = float(def.get("wounded_health_frac", 0.35))
	_wounded_speed_mult = float(def.get("wounded_speed_mult", 0.6))
	_rest_min = float(def.get("flee_rest_min_s", 20.0))
	_rest_max = maxf(float(def.get("flee_rest_max_s", 35.0)), _rest_min)
	_dog_damage_per_s = float(def.get("dog_damage_per_s", 0.0))


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


## Box shapes come already multiplied by the weight scale; physics nodes are never scaled.
func _build_hit_zones() -> void:
	for zone: StringName in HIT_ZONE_NODES.keys():
		var hz: HitZone = get_node_or_null(HIT_ZONE_NODES[zone] as NodePath) as HitZone
		if hz == null:
			push_error("Boar: missing hit zone node for '%s'" % zone)
			continue
		var def: Array = BoarVisualBase.HIT_ZONES[zone] as Array
		hz.zone = zone
		hz.target_id = boar_id
		hz.position = (def[0] as Vector3) * body_scale
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = (def[1] as Vector3) * body_scale
		var cs: CollisionShape3D = hz.get_node_or_null(^"Shape") as CollisionShape3D
		if cs == null:
			cs = CollisionShape3D.new()
			cs.name = "Shape"
			hz.add_child(cs)
		cs.shape = shape
		if not hz.hit_received.is_connected(_on_hit_received):
			hz.hit_received.connect(_on_hit_received)
