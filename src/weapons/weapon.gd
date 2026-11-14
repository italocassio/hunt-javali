class_name Weapon
extends Node
## One weapon of the loadout: ammo, cadence, reload and the hitscan shot. Pure gameplay, no view.
## All numbers come from data/weapons.json (docs/arquitetura.md §9.2).

signal fired(shot_id: int)
signal dry_fired()
signal cycle_started(duration_s: float)
signal reload_started(duration_s: float)
signal reload_finished()
signal reload_cancelled()
signal ammo_changed()

## Delay between the shot and the start of the bolt/pump animation.
const CYCLE_DELAY_S: float = 0.25
## Minimum time between dry-fire clicks.
const DRY_FIRE_INTERVAL_S: float = 0.3
## Most impact effects alive at once (docs §7.10).
const MAX_ACTIVE_VFX: int = 6
## Effect lifetime multiplier before the node is freed (docs §7.10).
const VFX_FREE_LIFETIME_MULT: float = 2.0

static var _next_shot_id: int = 1
static var _active_vfx: int = 0

var weapon_id: StringName = &""
var def: Dictionary = {}
var ammo_in_mag: int = 0
var ammo_reserve: int = 0

var _cooldown_s: float = 0.0
var _cycle_delay_left: float = -1.0
var _reload_left: float = 0.0
var _reloading: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func reset_shot_counter() -> void:
	_next_shot_id = 1


static func peek_next_shot_id() -> int:
	return _next_shot_id


func setup(id: StringName, reserve_mult: float = 1.0) -> bool:
	weapon_id = id
	def = Data.get_weapon(id)
	_rng.randomize()
	if def.is_empty():
		return false
	ammo_in_mag = int(def["mag_size"])
	ammo_reserve = int(round(float(def["reserve_ammo"]) * reserve_mult))
	return true


func get_def_float(key: String) -> float:
	return float(def.get(key, 0.0))


func is_scoped() -> bool:
	return bool(def.get("scoped", false))


func is_reloading() -> bool:
	return _reloading


func get_reload_progress() -> float:
	if not _reloading:
		return 0.0
	var total: float = maxf(get_def_float("reload_s"), 0.001)
	return clampf(1.0 - _reload_left / total, 0.0, 1.0)


## Half-angle of the shot cone in degrees (also drives the dynamic crosshair).
func get_spread_deg(aim_t: float, move_frac: float) -> float:
	return lerpf(get_def_float("hip_spread_deg"), get_def_float("ads_spread_deg"), clampf(aim_t, 0.0, 1.0)) \
		+ get_def_float("move_spread_add_deg") * clampf(move_frac, 0.0, 1.0)


func is_ready_to_fire() -> bool:
	return _cooldown_s <= 0.0 and not _reloading


## Seconds until the weapon can shoot again (0 when ready).
func get_cooldown_left() -> float:
	return _cooldown_s


func _process(delta: float) -> void:
	if _cooldown_s > 0.0:
		_cooldown_s = maxf(_cooldown_s - delta, 0.0)
		if _cooldown_s == 0.0 and ammo_in_mag <= 0 and ammo_reserve > 0 and not _reloading:
			start_reload()   # auto reload after the last round
	if _cycle_delay_left >= 0.0:
		_cycle_delay_left -= delta
		if _cycle_delay_left < 0.0:
			cycle_started.emit(get_def_float("cycle_s"))
	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


## Fires the weapon along the camera. Returns true if a shot left the barrel.
## aim_t: 0 hip .. 1 fully aimed. move_frac: 0..1 horizontal speed relative to walking.
func fire(cam: Camera3D, aim_t: float, move_frac: float, exclude: Array[RID], vfx_parent: Node) -> bool:
	if def.is_empty() or _reloading or _cooldown_s > 0.0:
		return false
	if ammo_in_mag <= 0:
		_cooldown_s = DRY_FIRE_INTERVAL_S
		dry_fired.emit()
		if ammo_reserve > 0:
			start_reload()
		return false
	ammo_in_mag -= 1
	_cooldown_s = get_def_float("fire_interval_s")
	if get_def_float("cycle_s") > 0.0:
		_cycle_delay_left = CYCLE_DELAY_S
	var shooter_slot: int = Net.get_local_slot()
	var shot_id: int = NetCodec.make_shot_id(shooter_slot, _next_shot_id)
	_next_shot_id += 1
	var xf: Transform3D = cam.global_transform
	var forward: Vector3 = -xf.basis.z
	var spread_deg: float = get_spread_deg(aim_t, move_frac)
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	for i: int in int(def["pellets"]):
		var dir: Vector3 = _spread_direction(xf.basis, deg_to_rad(spread_deg))
		_resolve_pellet(space, xf.origin, dir, shot_id, exclude, vfx_parent)
	GameEvents.shot_fired.emit(weapon_id, xf.origin, forward, get_def_float("noise_radius_m"))
	fired.emit(shot_id)
	ammo_changed.emit()
	return true


func start_reload() -> bool:
	if _reloading or def.is_empty():
		return false
	if ammo_in_mag >= int(def["mag_size"]) or ammo_reserve <= 0:
		return false
	_reloading = true
	_reload_left = get_def_float("reload_s")
	_cycle_delay_left = -1.0
	reload_started.emit(_reload_left)
	return true


func cancel_reload() -> void:
	if not _reloading:
		return
	_reloading = false
	_reload_left = 0.0
	reload_cancelled.emit()


## Cancels timers that must not survive a weapon switch.
func holster() -> void:
	cancel_reload()
	_cycle_delay_left = -1.0


func _finish_reload() -> void:
	_reloading = false
	_reload_left = 0.0
	var missing: int = int(def["mag_size"]) - ammo_in_mag
	var moved: int = mini(missing, ammo_reserve)
	ammo_in_mag += moved
	ammo_reserve -= moved
	reload_finished.emit()
	ammo_changed.emit()


func _spread_direction(basis: Basis, half_angle_rad: float) -> Vector3:
	var radius: float = sqrt(_rng.randf()) * tan(half_angle_rad)
	var theta: float = _rng.randf() * TAU
	var local: Vector3 = Vector3(cos(theta) * radius, sin(theta) * radius, -1.0)
	return (basis * local).normalized()


func _falloff(distance_m: float) -> float:
	var start_m: float = get_def_float("falloff_start_m")
	var end_m: float = get_def_float("falloff_end_m")
	var min_mult: float = get_def_float("min_damage_mult")
	if distance_m <= start_m:
		return 1.0
	if distance_m >= end_m:
		return min_mult
	return lerpf(1.0, min_mult, (distance_m - start_m) / maxf(end_m - start_m, 0.001))


func _resolve_pellet(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, shot_id: int,
		exclude: Array[RID], vfx_parent: Node) -> void:
	var hit: Dictionary = Hitscan.cast(space, origin, dir, get_def_float("max_range_m"), exclude)
	if hit.is_empty():
		return
	var position: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]
	if collider is HitZone:
		var info: HitInfo = HitInfo.new()
		info.shot_id = shot_id
		info.shooter_slot = NetCodec.shot_slot(shot_id)
		info.weapon_id = weapon_id
		info.damage = get_def_float("damage") * _falloff(float(hit["distance"]))
		info.origin = origin
		info.position = position
		info.normal = normal
		info.direction = dir
		info.distance_m = hit["distance"]
		(collider as HitZone).receive_hit(info)
		_impact(vfx_parent, &"impact_blood", &"impact_flesh", position, normal)
	elif collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer & Layers.STATIC) != 0:
		_impact(vfx_parent, &"impact_wood", &"impact_wood", position, normal)
	else:
		_impact(vfx_parent, &"impact_dust", &"impact_dirt", position, normal)


func _impact(vfx_parent: Node, vfx_id: StringName, sound_id: StringName, position: Vector3, normal: Vector3) -> void:
	Sfx.play_3d(sound_id, position)
	if vfx_parent == null or _active_vfx >= MAX_ACTIVE_VFX or not is_inside_tree():
		return
	var fx: CPUParticles3D = AssetLoader.instantiate(ScenePaths.vfx(vfx_id)) as CPUParticles3D
	if fx == null:
		return
	vfx_parent.add_child(fx)
	fx.global_position = position
	if absf(normal.dot(Vector3.UP)) < 0.99:
		fx.look_at(position + normal, Vector3.UP)
	else:
		fx.look_at(position + normal, Vector3.RIGHT)
	fx.emitting = true
	_active_vfx += 1
	var life: float = fx.lifetime * VFX_FREE_LIFETIME_MULT
	get_tree().create_timer(life).timeout.connect(_free_vfx.bind(fx))


## Untyped on purpose: the effect may already be freed (scene change) when the timer fires.
static func _free_vfx(fx: Variant) -> void:
	_active_vfx = maxi(_active_vfx - 1, 0)
	if is_instance_valid(fx):
		(fx as Node).queue_free()
