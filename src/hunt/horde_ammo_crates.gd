class_name HordeAmmoCrates
extends Node3D
## Horde ammo crates inside the barn (docs/plano_horda_nivel2.md N1 and section 4.6). Internal to package B: node
## "AmmoCrates", child of the HuntController, only when the level lists crate positions. No collision; taken with a
## press of interact (F / touch "Pegar", owner's Q4): the Player asks get_in_reach and calls take_local on the press.
## Offline and host are the authority (take, respawn, EV_AMMO_CRATE through the controller); a client only claims
## (C_AMMO_CRATE) and follows the host's EV_AMMO_CRATE.

const TICK_S: float = 0.1                          # respawn check at 10 Hz
const FALLBACK_SIZE: Vector3 = Vector3(0.6, 0.35, 0.4)
const FALLBACK_COLOR: Color = Color("#4F5B2E")

var _world: HuntController = null
var _authority: bool = true
var _positions: PackedVector3Array = PackedVector3Array()
var _available: PackedByteArray = PackedByteArray()
var _respawn_at: PackedFloat64Array = PackedFloat64Array()
var _claim_at: PackedFloat64Array = PackedFloat64Array()   # client: earliest time of the next claim, per crate
var _visuals: Array[Node3D] = []
var _mags: int = 0
var _respawn_s: float = 0.0
var _pickup_m: float = 0.0
var _tolerance_m: float = 0.0
var _retry_s: float = 0.0
var _tick: float = 0.0
var _out: PackedVector3Array = PackedVector3Array()


## barn: global transform of the barn PropSpawn (positions are in its frame); cfg: the level's "ammo_crates".
## authority: offline or host. Call after add_child.
func setup(world: HuntController, barn: Transform3D, cfg: Dictionary, authority: bool) -> void:
	_world = world
	_authority = authority
	_mags = int(cfg.get("mags_per_crate", 0))
	_respawn_s = float(cfg.get("respawn_s", 0.0))
	_pickup_m = float(cfg.get("pickup_radius_m", 0.0))
	_tolerance_m = float(cfg.get("claim_tolerance_m", 0.0))
	_retry_s = float(cfg.get("claim_retry_s", 0.0))
	var yaw: float = barn.basis.get_euler().y
	for entry: Variant in cfg.get("positions", []):
		var xz: Array = entry as Array
		var at: Vector3 = barn * Vector3(float(xz[0]), 0.0, float(xz[1]))
		at.y = world.get_height(at.x, at.z)
		_positions.append(at)
		_available.append(1)
		_respawn_at.append(0.0)
		_claim_at.append(0.0)
		var node: Node = AssetLoader.instantiate(ScenePaths.AMMO_CRATE)
		var visual: Node3D = node as Node3D
		if visual == null:
			if node != null:
				node.free()
			visual = FallbackMeshes.box(FALLBACK_SIZE, FALLBACK_COLOR)
		visual.name = "Crate_%d" % (_positions.size() - 1)
		add_child(visual)
		visual.global_position = at
		visual.rotation.y = yaw
		_visuals.append(visual)


func get_count() -> int:
	return _positions.size()


func is_available(crate: int) -> bool:
	return crate >= 0 and crate < _available.size() and _available[crate] != 0


func get_crate_position(crate: int) -> Vector3:
	return _positions[crate] if crate >= 0 and crate < _positions.size() else Vector3.INF


## Ground positions of the available crates (HuntWorld.get_ammo_crate_positions).
func get_available_positions() -> PackedVector3Array:
	_out.clear()
	for i: int in _positions.size():
		if _available[i] != 0:
			_out.append(_positions[i])
	return _out


func _process(delta: float) -> void:
	if _world == null or not _world.is_world_ready() or _world.is_hunt_over():
		return
	_tick += delta
	if _tick < TICK_S:
		return
	_tick = fmod(_tick, TICK_S)
	if not _authority:
		return
	var now: float = _world.get_elapsed_s()
	for i: int in _positions.size():
		if _available[i] == 0 and now >= _respawn_at[i]:
			_set_available(i, true)
			_world.report_ammo_crate(i, true, NetCodec.NO_SLOT)


## Nearest available crate within pickup_radius_m (XZ) of at; -1 = none (also before the world is ready / after the end).
func get_in_reach(at: Vector3) -> int:
	if _world == null or not _world.is_world_ready() or _world.is_hunt_over():
		return -1
	var best: int = -1
	var best_d: float = _pickup_m
	for i: int in _positions.size():
		if _available[i] == 0:
			continue
		var d: float = Vector2(at.x - _positions[i].x, at.z - _positions[i].z).length()
		if d <= best_d and (best < 0 or d < best_d):
			best = i
			best_d = d
	return best


## The local hunter pressed interact at that crate (HuntWorld.request_ammo_crate). Needs the hunter alive, wanting ammo
## and within pickup_radius_m of an available crate. Offline / host: taken now; client: C_AMMO_CRATE, at most once per
## claim_retry_s per crate (nothing changes here until the host's EV_AMMO_CRATE). True if taken or claimed.
func take_local(crate: int) -> bool:
	if _world == null or not _world.is_world_ready() or _world.is_hunt_over() or not is_available(crate):
		return false
	var p: PlayerBase = _world.get_player()
	if p == null or not is_instance_valid(p) or not p.is_alive() or not p.needs_ammo():
		return false
	if Vector2(p.global_position.x - _positions[crate].x, p.global_position.z - _positions[crate].z).length() > _pickup_m:
		return false
	if _authority:
		_take(crate, _world.get_local_slot())
		p.add_ammo_mags(_mags)
		return true
	var now: float = _world.get_elapsed_s()
	if now < _claim_at[crate]:
		return false
	_claim_at[crate] = now + _retry_s
	_world.send_ammo_crate_claim(crate)
	return true


## Host: a client's C_AMMO_CRATE. Taken if the crate is there and that hunter is alive within reach (pickup radius
## plus claim tolerance, last known position). True if taken.
func host_claim(from_slot: int, crate: int) -> bool:
	if not _authority or not is_available(crate):
		return false
	var h: PlayerBase = _world.get_hunter(from_slot)
	if h == null or not is_instance_valid(h) or not h.is_alive():
		return false
	var d: float = Vector2(h.global_position.x - _positions[crate].x, h.global_position.z - _positions[crate].z).length()
	if d > _pickup_m + _tolerance_m:
		return false
	_take(crate, from_slot)
	return true


## Client: EV_AMMO_CRATE (live or replayed). The crate taken by this machine's hunter gives it the magazines.
func apply_remote(crate: int, available: bool, taker_slot: int) -> void:
	if _authority or crate < 0 or crate >= _positions.size():
		return
	_set_available(crate, available)
	if available:
		_claim_at[crate] = 0.0
		return
	var p: PlayerBase = _world.get_player()
	if taker_slot == _world.get_local_slot() and p != null and is_instance_valid(p):
		p.add_ammo_mags(_mags)


func _take(crate: int, taker_slot: int) -> void:
	_set_available(crate, false)
	_respawn_at[crate] = _world.get_elapsed_s() + _respawn_s
	_world.report_ammo_crate(crate, false, taker_slot)


func _set_available(crate: int, on: bool) -> void:
	_available[crate] = 1 if on else 0
	_visuals[crate].visible = on
