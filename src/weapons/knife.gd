class_name Knife
extends Node
## The hunting knife: a melee weapon that never takes a loadout slot
## (docs/plano_faca_mochila_folego.md 1.4, 1.7, 2.6).
##
## Jogo 0.9.9: the knife is **equipped**, not a one-off swing. The Player puts it in the hand with the
## `knife` action (X / the Faca button) and it stays there until the hunter asks for a weapon again;
## while it is in the hand the `fire` action swings it. Equipping and unequipping are instant (the knife
## is always on the belt): no draw time, no animation to wait for.
##
## Child of the Player, which owns the gates (dead, downed, spectating, binoculars, item in use,
## reviving, weapon switch) and calls set_equipped() and swing().
## Every number comes from data/upgrades.json through Data.get_upgrade(Ids.KNIFE): reach, aim assist,
## swing time, cadence, noise and the damage of the level. No knife in the data = no knife at all.
##
## The hit lands on the press, before the animation ends (risk R11, accepted): one ray of `reach_m`
## from the eye and, only when that ray found no HitZone, one sphere query of `assist_radius_m` at the
## end of the reach. 1 ray + at most 1 shape query per swing (section 1.7).

## The swing starts: the Player cancels the reload, drops the buffered shot and hides the weapon.
signal swing_started(duration_s: float)

## Aim assist: most HitZones a single sphere query reports (docs 2.6).
const ASSIST_MAX_RESULTS: int = 8
## Two HitZones this close to the look line count as a tie (metres); the one nearer the eye wins.
const ASSIST_TIE_EPS_M: float = 0.001
## Blood effects of the knife alive at once (the gun has its own budget; docs 7.10).
const MAX_ACTIVE_VFX: int = 2
## Effect lifetime multiplier before the node is freed (docs 7.10).
const VFX_FREE_LIFETIME_MULT: float = 2.0
const VIEW_NAME: String = "View_knife"

var _level: int = 0
var _stats: Dictionary = {}
var _damage: float = 0.0
var _cooldown_left: float = 0.0
var _swing_left: float = 0.0
var _holder: Node3D = null
var _view: WeaponViewBase = null
## The view stands in a rest pose from Player.setup until hunt_started, so the pre-warm compiles its
## materials behind the loading overlay (risk R3). After that it shows while the knife is in the hand.
var _rest_visible: bool = true
## The knife is in the hand (0.9.9): the Player hides the weapon view and routes `fire` to swing().
var _equipped: bool = false
var _active_vfx: int = 0


## Knife of `level` (clamped to 1..Data.get_upgrade_level_count). False when the data has no knife: the
## Player then has no knife at all (no swing, no touch button).
func setup(level: int, holder: Node3D) -> bool:
	var count: int = Data.get_upgrade_level_count(Ids.KNIFE)
	if count <= 0:
		return false
	_level = clampi(level, 1, count)
	_stats = Data.get_upgrade(Ids.KNIFE).get("stats", {})
	_damage = float(Data.get_upgrade_level_def(Ids.KNIFE, _level).get("damage", 0.0))
	_holder = holder
	_create_view()
	return true


func get_level() -> int:
	return _level


func get_damage() -> float:
	return _damage


func get_reach_m() -> float:
	return _stat("reach_m")


func get_swing_s() -> float:
	return _stat("swing_s")


func get_swing_interval_s() -> float:
	return _stat("swing_interval_s")


func get_noise_radius_m() -> float:
	return _stat("noise_radius_m")


## True while the swing animation locks firing, aiming, reloading, switching and items.
func is_swinging() -> bool:
	return _swing_left > 0.0


## 1 right after a swing .. 0 ready.
func get_cooldown_frac() -> float:
	var interval: float = get_swing_interval_s()
	if interval <= 0.0:
		return 0.0
	return clampf(_cooldown_left / interval, 0.0, 1.0)


func is_ready() -> bool:
	return _level > 0 and _cooldown_left <= 0.0 and _swing_left <= 0.0


## True while the knife is in the hand (0.9.9). The Player keeps the weapon view hidden meanwhile.
func is_equipped() -> bool:
	return _equipped and _level > 0


## Puts the knife in the hand, or back on the belt. Instant: no draw time, the view swaps the same frame.
## Refused without a knife in the data or in the middle of a swing (the swing_s lock also locks the toggle).
## Returns true when the knife is in the requested state after the call.
func set_equipped(on: bool) -> bool:
	if _level <= 0:
		return not on
	if on == _equipped:
		return true
	if is_swinging():
		return false
	_equipped = on
	_refresh_view()
	return true


## The hunt started: the view leaves the rest pose and shows only while the knife is in the hand (section 1.7).
func set_rest_visible(on: bool) -> void:
	_rest_visible = on
	_refresh_view()


## Driven by the Player (no _process of its own, so the order inside the frame is fixed).
func tick(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _swing_left > 0.0:
		_swing_left = maxf(_swing_left - delta, 0.0)
		if _swing_left <= 0.0:
			_refresh_view()   # still in the hand: the knife stays, back to its rest pose


## One swing, one click of `fire` (the Player only swings with the knife in the hand; a swing asked with the knife
## on the belt still works and shows the view for its duration, which the sandbox and the tests use).
## The gates of section 1.4 are the Player's; here only the cadence and the data.
## Returns true when the swing happened.
func swing(cam: Camera3D, exclude: Array[RID], vfx_parent: Node) -> bool:
	if not is_ready() or cam == null or not cam.is_inside_tree():
		return false
	_cooldown_left = get_swing_interval_s()
	_swing_left = maxf(get_swing_s(), 0.0)
	swing_started.emit(_swing_left)
	_set_view_visible(true)
	if _view != null:
		_view.play_melee(_swing_left)
	Sfx.play(&"knife_swing")
	var xf: Transform3D = cam.global_transform
	var origin: Vector3 = xf.origin
	var forward: Vector3 = (-xf.basis.z).normalized()
	_resolve_hit(cam, origin, forward, exclude, vfx_parent)
	# After the hit: the client closes its C_SHOT on this signal (weapon byte NetCodec.KNIFE_WEAPON_INDEX)
	# and package B counts the swing as a shot. The swing never touches the net shot sequence.
	GameEvents.shot_fired.emit(Ids.KNIFE, origin, forward, get_noise_radius_m())
	if _swing_left <= 0.0:
		_refresh_view()
	return true


## A swing that must not finish (death, going down): no lock, cadence kept. The Player unequips right after.
func abort_swing() -> void:
	_swing_left = 0.0
	_refresh_view()


func _stat(key: String) -> float:
	return float(_stats.get(key, 0.0))


# ---------------------------------------------------------------------------
# Hit
# ---------------------------------------------------------------------------

func _resolve_hit(cam: Camera3D, origin: Vector3, forward: Vector3, exclude: Array[RID], vfx_parent: Node) -> void:
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	if space == null:
		return
	var shot_id: int = Weapon.take_shot_id(Net.get_local_slot())
	var reach_m: float = get_reach_m()
	var hit: Dictionary = Hitscan.cast(space, origin, forward, reach_m, exclude)
	var collider: Object = hit.get("collider")
	if collider is HitZone:
		_apply_hit(collider as HitZone, shot_id, origin, forward, hit["position"], hit["normal"],
			float(hit["distance"]), vfx_parent)
		return
	# No HitZone on the ray: one sphere query at the end of the reach forgives a near miss.
	var zone: HitZone = _assist_zone(space, origin, forward, reach_m)
	if zone != null:
		var position: Vector3 = zone.global_position
		_apply_hit(zone, shot_id, origin, forward, position, -forward,
			minf(origin.distance_to(position), reach_m), vfx_parent)
		return
	if hit.is_empty():
		return
	# Terrain or a static prop within reach: only the sound, no damage and no effect.
	var is_static: bool = collider is CollisionObject3D \
		and ((collider as CollisionObject3D).collision_layer & Layers.STATIC) != 0
	Sfx.play_3d(&"impact_wood" if is_static else &"impact_dirt", hit["position"])


func _apply_hit(zone: HitZone, shot_id: int, origin: Vector3, forward: Vector3, position: Vector3,
		normal: Vector3, distance_m: float, vfx_parent: Node) -> void:
	var info: HitInfo = HitInfo.new()
	info.shot_id = shot_id
	info.shooter_slot = NetCodec.shot_slot(shot_id)
	info.weapon_id = Ids.KNIFE
	info.damage = _damage        # melee: no distance falloff
	info.origin = origin
	info.position = position
	info.normal = normal
	info.direction = forward
	info.distance_m = distance_m
	zone.receive_hit(info)
	Sfx.play_3d(&"impact_flesh", position)
	_spawn_blood(vfx_parent, position, normal)


## The HitZone whose global_position is nearest to the look line (a tie goes to the one nearer the eye);
## null when the sphere at the end of the reach touches none.
func _assist_zone(space: PhysicsDirectSpaceState3D, origin: Vector3, forward: Vector3, reach_m: float) -> HitZone:
	var radius: float = _stat("assist_radius_m")
	if radius <= 0.0:
		return null
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), origin + forward * (reach_m - radius))
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Layers.BOAR_HITZONE
	var results: Array[Dictionary] = space.intersect_shape(query, ASSIST_MAX_RESULTS)
	var best: HitZone = null
	var best_off: float = INF
	var best_distance: float = INF
	for result: Dictionary in results:
		var zone: HitZone = result.get("collider") as HitZone
		if zone == null:
			continue
		var to_zone: Vector3 = zone.global_position - origin
		var off: float = to_zone.cross(forward).length()   # distance to the look line (forward is unit length)
		var distance: float = to_zone.length()
		if off < best_off - ASSIST_TIE_EPS_M \
				or (off <= best_off + ASSIST_TIE_EPS_M and distance < best_distance):
			best = zone
			best_off = off
			best_distance = distance
	return best


## Blood effect of a flesh hit, same asset and lifetime rule as the gun (docs 7.10), own small budget.
func _spawn_blood(vfx_parent: Node, position: Vector3, normal: Vector3) -> void:
	if vfx_parent == null or _active_vfx >= MAX_ACTIVE_VFX or not is_inside_tree():
		return
	var fx: CPUParticles3D = AssetLoader.instantiate(ScenePaths.vfx(&"impact_blood")) as CPUParticles3D
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
	get_tree().create_timer(fx.lifetime * VFX_FREE_LIFETIME_MULT).timeout.connect(_free_vfx.bind(fx))


## Untyped on purpose: the effect may already be freed (scene change) when the timer fires.
func _free_vfx(fx: Variant) -> void:
	_active_vfx = maxi(_active_vfx - 1, 0)
	if is_instance_valid(fx):
		(fx as Node).queue_free()


# ---------------------------------------------------------------------------
# View
# ---------------------------------------------------------------------------

## The art is optional: without assets/models/weapons/knife_view.tscn the swing still happens, the weapon
## just disappears and comes back (docs 2.6, item 2).
func _create_view() -> void:
	if _holder == null or not AssetLoader.exists(ScenePaths.weapon_view(Ids.KNIFE)):
		return
	var node: Node = AssetLoader.instantiate(ScenePaths.weapon_view(Ids.KNIFE))
	_view = node as WeaponViewBase
	if _view == null:
		if node != null:
			node.queue_free()
		return
	_view.name = VIEW_NAME
	_holder.add_child(_view)
	_view.setup(Ids.KNIFE)
	_view.visible = _rest_visible


## The knife is seen while it is in the hand, while a swing plays and in the rest pose before hunt_started.
func _refresh_view() -> void:
	_set_view_visible(_equipped or _rest_visible or is_swinging())


func _set_view_visible(on: bool) -> void:
	if _view != null and is_instance_valid(_view):
		_view.visible = on


## The first-person knife view, or null when the art is missing (tests only; gameplay never needs it).
func get_view() -> WeaponViewBase:
	return _view
