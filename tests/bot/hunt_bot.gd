extends RefCounted
## Test bot: plays a hunt through the production bot hooks (PlayerBase.bot_*), with real shots.
## Strategy: pick the nearest live boar, stand at a clear broadside spot ~STAND_DISTANCE_M away,
## aim at the vital zone, fire respecting cadence, reload on an empty mag.
## Never references package classes by class_name that are not core (HuntWorld/PlayerBase are core).

const STAND_DISTANCE_M: float = 16.0
const MIN_STAND_DISTANCE_M: float = 5.0
const STAND_FALLOFF_FRACTION: float = 0.7
const SETTLE_S: float = 0.35
const MAX_REPOSITIONS_PER_BOAR: int = 40
const ANGLES: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]

var host: Node = null
var world: HuntWorld = null
var player: PlayerBase = null

var stand_distance_m: float = STAND_DISTANCE_M
var shots_fired: int = 0
var reloads: int = 0
var teleports: int = 0
var rounds_empty_events: int = 0
var log_prefix: String = "bot"
var verbose: bool = false


func setup(p_host: Node, p_world: HuntWorld) -> void:
	host = p_host
	world = p_world
	player = world.get_player()
	player.bot_set_enabled(true)
	# Short-range weapons (shotgun) need the bot closer than the damage falloff start.
	var w: Dictionary = Data.get_weapon(player.get_current_weapon_id())
	var falloff_start: float = float(w.get("falloff_start_m", STAND_DISTANCE_M))
	stand_distance_m = clampf(falloff_start * STAND_FALLOFF_FRACTION, MIN_STAND_DISTANCE_M, STAND_DISTANCE_M)


func _frame() -> void:
	await host.get_tree().process_frame


func _phys() -> void:
	await host.get_tree().physics_frame


## Waits in hunt time (follows Engine.time_scale because the hunt clock does).
func wait_hunt_s(seconds: float) -> void:
	var limit: float = world.get_elapsed_s() + seconds
	while world.get_elapsed_s() < limit and not world.is_hunt_over():
		await _frame()


func park_far() -> void:
	## Out of the way, in a corner, so boars do not bother the hunter.
	var x: float = -118.0
	var z: float = -118.0
	player.bot_teleport(Vector3(x, world.get_height(x, z) + 0.1, z))


func _clear_spot(target: Vector3, base_dir: Vector3) -> Vector3:
	## Returns a standing position (Vector3.INF when none) with clear line of sight to `target`.
	var rect: Rect2 = world.get_map_rect().grow(-6.0)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for deg: float in ANGLES:
		var d: Vector3 = base_dir.rotated(Vector3.UP, deg_to_rad(deg))
		var x: float = target.x + d.x * stand_distance_m
		var z: float = target.z + d.z * stand_distance_m
		if not rect.has_point(Vector2(x, z)):
			continue
		var feet: Vector3 = Vector3(x, world.get_height(x, z) + 0.05, z)
		var eye: Vector3 = feet + Vector3(0.0, 1.65, 0.0)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, target, Layers.MASK_LINE_OF_SIGHT)
		if space.intersect_ray(q).is_empty():
			return feet
	return Vector3.INF


## Hunts until the hunt ends or `timeout_s` of hunt time passes. Returns true if the hunt ended.
func kill_all(timeout_s: float) -> bool:
	var deadline: float = world.get_elapsed_s() + timeout_s
	player.bot_set_aim(true)
	var current: int = -1
	var repositions: int = 0
	while not world.is_hunt_over() and world.get_elapsed_s() < deadline:
		var ids: PackedInt32Array = world.get_alive_boar_ids()
		if ids.is_empty():
			park_far()
			await _frame()
			continue
		# Pick the boar closest to the hunter.
		var me: Vector3 = player.global_position
		var best: int = -1
		var best_d: float = INF
		for id: int in ids:
			var p: Vector3 = world.get_boar_position(id)
			var dd: float = Vector2(p.x - me.x, p.z - me.z).length()
			if dd < best_d:
				best_d = dd
				best = id
		if best != current:
			current = best
			repositions = 0
		if player.get_ammo_in_mag() <= 0 and not player.is_reloading():
			if player.get_ammo_reserve() > 0:
				player.bot_reload()
				reloads += 1
			else:
				rounds_empty_events += 1
				return false
		if player.is_reloading():
			await _frame()
			continue
		var target: Vector3 = world.get_boar_zone_position(current, &"vital")
		if target == Vector3.INF:
			await _frame()
			continue
		var base_dir: Vector3 = Vector3(me.x - target.x, 0.0, me.z - target.z)
		if base_dir.length() < 0.5:
			base_dir = Vector3.BACK
		base_dir = base_dir.normalized()
		var spot: Vector3 = _clear_spot(target, base_dir)
		if spot == Vector3.INF:
			repositions += 1
			if repositions > MAX_REPOSITIONS_PER_BOAR:
				# Give up on this boar for now; yield so the others may move.
				await _frame()
			else:
				await _frame()
			continue
		player.bot_teleport(spot)
		teleports += 1
		await _phys()
		await _phys()
		player.bot_set_aim(true)
		# Let the aim settle, then fire. Re-aim every frame: the boar moves.
		var t_end: float = world.get_elapsed_s() + SETTLE_S
		while world.get_elapsed_s() < t_end and not world.is_hunt_over():
			var tv: Vector3 = world.get_boar_zone_position(current, &"vital")
			if tv != Vector3.INF:
				player.bot_look_at(tv)
			await _frame()
		var fired_this_boar: int = 0
		var tries: int = 0
		while not world.is_hunt_over() and world.get_alive_boar_ids().has(current) and tries < 90:
			tries += 1
			var tv2: Vector3 = world.get_boar_zone_position(current, &"vital")
			if tv2 == Vector3.INF:
				break
			player.bot_look_at(tv2)
			if player.get_ammo_in_mag() <= 0:
				break
			if player.bot_fire():
				shots_fired += 1
				fired_this_boar += 1
				if verbose:
					print("%s shot %d at boar %d" % [log_prefix, shots_fired, current])
				# The shot scatters the herd: re-position after every shot.
				break
			await _frame()
	return world.is_hunt_over()
