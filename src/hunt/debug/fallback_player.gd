class_name FallbackPlayer
extends PlayerBase
## Stand-in hunter used when player.tscn does not exist (or with the user arg --fallback-player).
## A capsule with a camera, keyboard movement, health and a single hitscan shot: enough to run and
## test the hunt without Package A. No HUD, no reload, no items.

const GRAVITY_MPS2: float = 20.0
const TURN_SPEED_RAD_S: float = 2.0
const DEFAULT_EYE_HEIGHT_M: float = 1.65

var _world: HuntWorld = null
var _health: float = 100.0
var _max_health: float = 100.0
var _alive: bool = true
var _input_enabled: bool = true
var _bot: bool = false
var _bot_move: Vector2 = Vector2.ZERO
var _bot_sprint: bool = false
var _walk_speed: float = 4.0
var _sprint_speed: float = 6.5
var _noise_walk: float = 8.0
var _noise_sprint: float = 22.0
var _eye_height: float = DEFAULT_EYE_HEIGHT_M
var _pitch: float = 0.0
var _weapon_id: StringName = &""
var _weapon: Dictionary = {}
var _cooldown: float = 0.0
var _knock: Vector3 = Vector3.ZERO
var _camera: Camera3D = null
var _sprinting: bool = false

static var _shot_counter: int = 0


func _init() -> void:
	collision_layer = Layers.PLAYER
	collision_mask = Layers.MASK_PLAYER_BODY
	var def: Dictionary = Data.get_game().get("player", {})
	_max_health = float(def.get("max_health", 100.0))
	_health = _max_health
	_walk_speed = float(def.get("walk_speed_mps", 4.0))
	_sprint_speed = float(def.get("sprint_speed_mps", 6.5))
	_noise_walk = float(def.get("noise_radius_walk_m", 8.0))
	_noise_sprint = float(def.get("noise_radius_sprint_m", 22.0))
	_eye_height = float(def.get("standing_eye_height_m", DEFAULT_EYE_HEIGHT_M))
	var radius: float = float(def.get("capsule_radius_m", 0.35))
	var height: float = float(def.get("capsule_height_m", 1.8))
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(cs)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.position = Vector3(0.0, _eye_height, 0.0)
	_camera.fov = float(def.get("base_fov_deg", 75.0))
	add_child(_camera)


func setup(request: HuntRequest, world: HuntWorld) -> void:
	_world = world
	if request != null and not request.weapon_ids.is_empty():
		_weapon_id = request.weapon_ids[0]
		_weapon = Data.get_weapon(_weapon_id)
	var quality: Dictionary = Data.get_game().get("quality_presets", {}).get(String(Ids.Q_MEDIUM), {})
	_camera.far = float(quality.get("view_distance_m", 220.0))
	_camera.current = true


func apply_damage(amount: float, source_position: Vector3, knockback_mps: float = 0.0) -> void:
	if not _alive or amount <= 0.0:
		return
	_health = maxf(_health - amount, 0.0)
	var away: Vector3 = global_position - source_position
	away.y = 0.0
	if away.length_squared() > 0.0001:
		_knock = away.normalized() * knockback_mps
	GameEvents.player_damaged.emit(amount, source_position, _health)
	if _health <= 0.0:
		_alive = false
		_input_enabled = false
		GameEvents.player_died.emit()


func heal(amount: float) -> void:
	if _alive and amount > 0.0:
		_health = minf(_health + amount, _max_health)
		GameEvents.player_healed.emit(amount, _health)


func is_alive() -> bool:
	return _alive


func get_health() -> float:
	return _health


func get_max_health() -> float:
	return _max_health


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, _eye_height, 0.0)


func get_look_direction() -> Vector3:
	return -_camera.global_transform.basis.z


func get_noise_radius() -> float:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if speed < 0.5:
		return 0.0
	return _noise_sprint if _sprinting else _noise_walk


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func get_current_weapon_id() -> StringName:
	return _weapon_id


func get_ammo_in_mag() -> int:
	return 1


func bot_set_enabled(enabled: bool) -> void:
	_bot = enabled


func bot_set_move(direction: Vector2, sprint: bool) -> void:
	_bot_move = direction.limit_length(1.0)
	_bot_sprint = sprint


func bot_look_at(point: Vector3) -> void:
	var to: Vector3 = point - get_eye_position()
	if to.length_squared() < 0.0001:
		return
	rotation.y = atan2(-to.x, -to.z)
	_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	_camera.rotation.x = _pitch


## One hitscan ray from the eye (section 8.2). Uses the first weapon of the request.
func bot_fire() -> bool:
	if not _alive or _cooldown > 0.0 or _weapon.is_empty() or not is_inside_tree():
		return false
	_cooldown = float(_weapon.get("fire_interval_s", 0.5))
	_shot_counter += 1
	var origin: Vector3 = get_eye_position()
	var dir: Vector3 = get_look_direction()
	var max_range: float = float(_weapon.get("max_range_m", 100.0))
	GameEvents.shot_fired.emit(_weapon_id, origin, dir, float(_weapon.get("noise_radius_m", 60.0)))
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, Layers.MASK_WEAPON_RAY)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var zone: HitZone = res.get("collider") as HitZone
	if zone != null:
		var hit: HitInfo = HitInfo.new()
		hit.shot_id = _shot_counter
		hit.weapon_id = _weapon_id
		hit.origin = origin
		hit.position = res["position"] as Vector3
		hit.normal = res["normal"] as Vector3
		hit.direction = dir
		hit.distance_m = origin.distance_to(hit.position)
		hit.damage = float(_weapon.get("damage", 30.0)) * _falloff(hit.distance_m)
		zone.receive_hit(hit)
	return true


func bot_dog_command() -> void:
	GameEvents.dog_command_requested.emit()


func bot_use_item(item_id: StringName) -> bool:
	var fwd: Vector3 = -global_transform.basis.z
	GameEvents.item_used.emit(item_id, global_position + fwd * 2.0)
	return true


func _falloff(distance_m: float) -> float:
	var start: float = float(_weapon.get("falloff_start_m", 40.0))
	var end: float = float(_weapon.get("falloff_end_m", 120.0))
	var min_mult: float = float(_weapon.get("min_damage_mult", 0.5))
	if distance_m <= start:
		return 1.0
	if distance_m >= end:
		return min_mult
	return lerpf(1.0, min_mult, (distance_m - start) / maxf(end - start, 0.001))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var move: Vector2 = Vector2.ZERO
	_sprinting = false
	if _alive and _input_enabled:
		if _bot:
			move = _bot_move
			_sprinting = _bot_sprint
		else:
			move = _read_keys(delta)
	var speed: float = _sprint_speed if _sprinting else _walk_speed
	var wish: Vector3 = (global_transform.basis.x * move.x - global_transform.basis.z * move.y) * speed
	_knock = _knock.move_toward(Vector3.ZERO, GRAVITY_MPS2 * delta)
	velocity.x = wish.x + _knock.x
	velocity.z = wish.z + _knock.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY_MPS2 * delta
	move_and_slide()


func _read_keys(delta: float) -> Vector2:
	if not InputMap.has_action(&"move_forward"):
		return Vector2.ZERO
	var move: Vector2 = Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back"))
	if Input.is_key_pressed(KEY_Q):
		rotation.y += TURN_SPEED_RAD_S * delta
	if Input.is_key_pressed(KEY_E):
		rotation.y -= TURN_SPEED_RAD_S * delta
	_sprinting = InputMap.has_action(&"sprint") and Input.is_action_pressed(&"sprint")
	if InputMap.has_action(&"fire") and Input.is_action_just_pressed(&"fire"):
		bot_fire()
	return move.limit_length(1.0)
