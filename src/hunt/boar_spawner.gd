class_name BoarSpawner
extends Node
## Spawns the contract groups (herds) over time, owns the boar registry and routes world events
## that concern every boar (gunshot noise, thermal highlight).

signal boar_died(boar: Boar)
signal group_entered(leader_type: StringName, count: int)
## A boar entered the world (placed and registered). The network host replicates it.
signal boar_added(boar: Boar)

const SPAWN_TRIES: int = 12
const THERMAL_REFRESH_S: float = 0.25
const DEFAULT_SPAWN_RADIUS_M: float = 8.0
const DEFAULT_MAX_ALIVE: int = 18

var _world: HuntController = null
var _parent: Node3D = null
var _scene: PackedScene = null
var _groups: Array[Dictionary] = []     # {members: Array[StringName], zone: Vector2, delay: float, herd: BoarHerd, next: int}
var _herds: Array[BoarHerd] = []
var _by_id: Dictionary = {}             # int -> Boar (alive and dead)
var _alive: Array[Boar] = []
var _alive_ids: PackedInt32Array = PackedInt32Array()
var _total: int = 0
var _next_id: int = 1
var _spawn_radius: float = DEFAULT_SPAWN_RADIUS_M
var _max_alive: int = DEFAULT_MAX_ALIVE
var _wander_min: float = 5.0
var _wander_max: float = 15.0
var _thermal_on: bool = false
var _thermal_range: float = 150.0
var _thermal_timer: float = 0.0
var _active: bool = false


func setup(world: HuntController, parent: Node3D, contract: Dictionary, spawn_zones: PackedVector2Array) -> void:
	_world = world
	_parent = parent
	_scene = load(ScenePaths.BOAR) as PackedScene
	var hunt: Dictionary = Data.get_game().get("hunt", {})
	_spawn_radius = float(hunt.get("spawn_radius_m", DEFAULT_SPAWN_RADIUS_M))
	_max_alive = int(hunt.get("max_alive_boars", DEFAULT_MAX_ALIVE))
	_wander_min = float(hunt.get("wander_before_crop_min_s", 5.0))
	_wander_max = maxf(float(hunt.get("wander_before_crop_max_s", 15.0)), _wander_min)
	_thermal_range = float(Data.get_equipment(Ids.I_THERMAL_SCOPE).get("effect", {}).get("highlight_range_m", 150.0))
	var groups: Array = contract.get("groups", [])
	for g: Variant in groups:
		var def: Dictionary = g as Dictionary
		var members: Array[StringName] = []
		for m: Variant in def.get("members", []):
			members.append(StringName(String(m)))
		if members.is_empty():
			continue
		var zone: Vector2 = Vector2.ZERO
		if not spawn_zones.is_empty():
			zone = spawn_zones[posmod(int(def.get("spawn_zone", 0)), spawn_zones.size())]
		_groups.append({"members": members, "zone": zone, "delay": float(def.get("delay_s", 0.0)), "herd": null, "next": 0})
		_total += members.size()
	if not GameEvents.shot_fired.is_connected(_on_shot_fired):
		GameEvents.shot_fired.connect(_on_shot_fired)
	if not GameEvents.thermal_vision_changed.is_connected(_on_thermal_changed):
		GameEvents.thermal_vision_changed.connect(_on_thermal_changed)


## Network: more boars for more hunters (docs/multiplayer.md section 6.10). Pure function.
## target = round(base_total x coop.boar_count_mult_by_players[n - 1]). Whole groups are cloned in order
## (groups led by or containing an alpha are skipped), each clone in spawn_zone + 1 + lap and delayed by
## max contract delay + coop.extra_group_delay_s x (clone order, from 1); the last clone loses members
## from the end (never the leader) so the total lands on the target. Solo / no growth: a deep copy.
static func scale_groups(groups: Array, player_count: int, coop: Dictionary) -> Array:
	var out: Array = groups.duplicate(true)
	var mults: Array = coop.get("boar_count_mult_by_players", [])
	if player_count <= 1 or mults.is_empty():
		return out
	var mult: float = float(mults[clampi(player_count - 1, 0, mults.size() - 1)])
	var base: int = 0
	var max_delay: float = 0.0
	var sources: Array[Dictionary] = []
	for g: Variant in groups:
		var def: Dictionary = g as Dictionary
		var members: Array = def.get("members", [])
		base += members.size()
		max_delay = maxf(max_delay, float(def.get("delay_s", 0.0)))
		if not members.is_empty() and not members.has(String(Ids.ALPHA)) and not members.has(Ids.ALPHA):
			sources.append(def)
	var target: int = roundi(float(base) * mult)
	if target <= base or sources.is_empty():
		return out
	var extra_delay: float = float(coop.get("extra_group_delay_s", 0.0))
	var count: int = base
	var order: int = 0
	while count < target:
		var src: Dictionary = sources[order % sources.size()]
		var lap: int = order / sources.size()
		var clone: Dictionary = src.duplicate(true)
		var members: Array = clone["members"]
		var need: int = target - count
		if members.size() > need:
			members.resize(need)   # need >= 1: the leader (index 0) always stays
		clone["spawn_zone"] = int(src.get("spawn_zone", 0)) + 1 + lap
		clone["delay_s"] = max_delay + extra_delay * float(order + 1)
		out.append(clone)
		count += members.size()
		order += 1
	return out


func begin() -> void:
	_active = true


func get_total() -> int:
	return _total


func get_alive_ids() -> PackedInt32Array:
	return _alive_ids


func get_alive() -> Array[Boar]:
	return _alive


func get_boar(boar_id: int) -> Boar:
	return _by_id.get(boar_id) as Boar


## Nearest living boar to an XZ point within max_dist (null if none).
func find_nearest_alive(from: Vector2, max_dist: float = INF) -> Boar:
	var best: Boar = null
	var best_d: float = max_dist * max_dist if max_dist < INF else INF
	for b: Boar in _alive:
		var d: float = from.distance_squared_to(b.get_xz())
		if d < best_d:
			best_d = d
			best = b
	return best


func _process(delta: float) -> void:
	if not _active or _world == null:
		return
	_spawn_step()
	if _thermal_on:
		_thermal_timer -= delta
		if _thermal_timer <= 0.0:
			_thermal_timer = THERMAL_REFRESH_S
			_refresh_thermal()


## At most one boar per frame, so a herd entering never causes a frame spike.
func _spawn_step() -> void:
	if _scene == null or _alive.size() >= _max_alive:
		return
	var now: float = _world.get_elapsed_s()
	for g: Dictionary in _groups:
		var members: Array[StringName] = g["members"]
		var next: int = int(g["next"])
		if next >= members.size() or now < float(g["delay"]):
			continue
		var herd: BoarHerd = g["herd"] as BoarHerd
		if herd == null:
			herd = BoarHerd.new()
			herd.herd_id = _herds.size()
			herd.anchor = g["zone"] as Vector2
			herd.wander_end_time = now + _world.rng.randf_range(_wander_min, _wander_max)
			g["herd"] = herd
			_herds.append(herd)
		_spawn_boar(members[next], herd)
		g["next"] = next + 1
		if next + 1 == members.size():
			group_entered.emit(members[0], members.size())
		return


func _spawn_boar(type_id: StringName, herd: BoarHerd) -> void:
	var rng: RandomNumberGenerator = _world.rng
	var def: Dictionary = Data.get_boar_type(type_id)
	var w_min: float = float(def.get("weight_min_kg", 50.0))
	var w_max: float = float(def.get("weight_max_kg", 100.0))
	var weight: float = lerpf(w_min, w_max, (rng.randf() + rng.randf()) * 0.5)
	var boar: Boar = _scene.instantiate() as Boar
	if boar == null:
		push_error("BoarSpawner: %s root is not a Boar" % ScenePaths.BOAR)
		return
	var id: int = _next_id
	_next_id += 1
	boar.setup(id, type_id, weight, herd, _world)
	boar.died.connect(_on_boar_died)
	_parent.add_child(boar)
	var pos: Vector2 = herd.anchor
	var radius: float = BoarVisualBase.scale_for_weight(weight) * Boar.BODY_RADIUS_M
	for t: int in SPAWN_TRIES:
		var ang: float = rng.randf_range(0.0, TAU)
		var p: Vector2 = herd.anchor + Vector2(cos(ang), sin(ang)) * sqrt(rng.randf()) * _spawn_radius
		p = Steering.clamp_to_rect(p, _world.get_map_rect(), Boar.MAP_MARGIN_M)
		if _world.obstacles.is_free(p, radius + 0.3):
			pos = p
			break
	boar.start(pos, rng.randf_range(0.0, TAU))
	_by_id[id] = boar
	_alive.append(boar)
	_alive_ids.append(id)
	boar_added.emit(boar)
	GameEvents.boar_spawned.emit(id, type_id, weight)


func _on_boar_died(boar: Boar) -> void:
	_alive.erase(boar)
	var idx: int = _alive_ids.find(boar.boar_id)
	if idx >= 0:
		_alive_ids.remove_at(idx)
	boar_died.emit(boar)


func _on_shot_fired(_weapon_id: StringName, origin: Vector3, _direction: Vector3, noise_radius_m: float) -> void:
	notify_shot(origin, noise_radius_m)


## A gunshot heard by any member makes the whole herd react at once. Local shots come from
## GameEvents.shot_fired; a remote hunter's shots come from HuntHostSync (C_SHOT).
func notify_shot(origin: Vector3, noise_radius_m: float) -> void:
	if not _active:
		return
	var src: Vector2 = Vector2(origin.x, origin.z)
	for herd: BoarHerd in _herds:
		for b: Boar in herd.members:
			if b.is_alive() and b.get_xz().distance_to(src) < b.hearing_radius(noise_radius_m):
				herd.last_detect_time = _world.get_elapsed_s()
				herd.raise_reaction(src, false)
				break


func _on_thermal_changed(active: bool) -> void:
	_thermal_on = active
	_thermal_timer = 0.0
	if not active:
		for b: Boar in _alive:
			b.set_highlight(false)


func _refresh_thermal() -> void:
	var player: PlayerBase = _world.get_player()
	if player == null:
		return
	var from: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	for b: Boar in _alive:
		b.set_highlight(from.distance_to(b.get_xz()) <= _thermal_range)
