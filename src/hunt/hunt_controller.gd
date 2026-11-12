class_name HuntController
extends HuntWorld
## Root of hunt.tscn. Assembles the hunt (map, environment, player, dog, boars), implements the
## HuntWorld contract and decides how the hunt ends (docs/arquitetura.md sections 8.1, 8.2, 8.8).

const LOADING_TEXT: String = "Preparando a caçada…"
const ARG_FALLBACK_PLAYER: String = "--fallback-player"
const ARG_TIMING: String = "--hunt-timing"
const DOG_SIDE_OFFSET_M: float = 1.5
const DEFAULT_END_DELAY_S: float = 2.5
const AMBIENCE_LOOPS: Array[StringName] = [&"amb_cerrado_loop", &"amb_wind_loop"]
const AMBIENCE_DB: float = -6.0
const MSG_GROUP: String = "Uma vara saiu da mata!"
const MSG_LONER: String = "Um javali solitário saiu da mata!"
const MSG_ALPHA: String = "O cachaço alfa entrou na área!"
const MSG_S: float = 3.0

## Tests set this to false before add_child so the hunt does not change scene when it ends.
var route_on_finish: bool = true

# Package-internal services (boars, dog, spawner).
var heightmap: Heightmap = null
var obstacles: ObstacleGrid = ObstacleGrid.new()
var crop: CropManager = null
var retreat_zones: PackedVector2Array = PackedVector2Array()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var crop_drain_mult: float = 1.0
var spawner: BoarSpawner = null

var _request: HuntRequest = null
var _map: MapRoot = null
var _player: PlayerBase = null
var _dog: Dog = null
var _env: MapEnvironmentBase = null
var _ready_flag: bool = false
var _over: bool = false
var _result: HuntResult = null
var _final_result: HuntResult = null
var _elapsed: float = 0.0
var _killed: int = 0
var _player_died: bool = false
var _abandon: bool = false
var _map_rect: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)
var _baits: Array[Bait] = []
var _marks: Dictionary = {}            # boar_id -> world time when the mark expires
var _marked_out: PackedVector3Array = PackedVector3Array()
var _hit_shots: Dictionary = {}        # shot_id -> true
var _clean_zones: Array = []
var _prev_scaling: float = 1.0
var _timing: bool = false

@onready var _boars_root: Node3D = $Boars
@onready var _baits_root: Node3D = $Baits
@onready var _loading: CanvasLayer = $LoadingOverlay


func _ready() -> void:
	spawner = $BoarSpawner as BoarSpawner
	_timing = OS.get_cmdline_user_args().has(ARG_TIMING)
	_prev_scaling = get_viewport().scaling_3d_scale
	var label: Label = _loading.get_node_or_null(^"Label") as Label
	if label != null:
		label.text = LOADING_TEXT
	_loading.visible = true
	_assemble()


func _exit_tree() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.scaling_3d_scale = _prev_scaling
	for id: StringName in AMBIENCE_LOOPS:
		Sfx.stop_loop(id)


# --- Assembly (section 8.1) ----------------------------------------------------------------------

func _assemble() -> void:
	var t0: int = Time.get_ticks_msec()
	# 1. Request
	_request = Router.get_pending_request()
	if _request == null:
		_request = HuntRequest.make_debug()
	_result = HuntResult.new()
	_result.map_id = _request.map_id
	_result.contract_index = _request.contract_index
	if _request.rng_seed != 0:
		rng.seed = _request.rng_seed
	else:
		rng.randomize()
	var contract: Dictionary = Data.get_contract(_request.map_id, _request.contract_index)
	crop_drain_mult = float(contract.get("crop_drain_mult", 1.0))
	_clean_zones = Data.get_boar_rules().get("reward", {}).get("clean_zones", [])
	var quality: StringName = _resolve_quality()
	var preset: Dictionary = Data.get_game().get("quality_presets", {}).get(String(quality), {})
	if not await _next_frame():
		return

	# 2. Map
	var path: String = ScenePaths.map_scene(_request.map_id)
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	_map = packed.instantiate() as MapRoot if packed != null else null
	if _map == null:
		push_error("HuntController: map scene missing or invalid: %s" % path)
		_ready_flag = true
		_loading.visible = false
		_finish(HuntResult.Outcome.ABANDONED)
		return
	_map.name = "Map"
	_map.obstacles = obstacles
	add_child(_map)
	_map_rect = _map.get_map_rect()
	var t: int = Time.get_ticks_msec()
	_map.build_heightmap()
	heightmap = _map.heightmap
	t = _lap("heightmap", t)
	if not await _next_frame():
		return
	t = Time.get_ticks_msec()
	_map.build_terrain()
	t = _lap("terrain", t)
	if not await _next_frame():
		return
	t = Time.get_ticks_msec()
	_map.build_props_and_water()
	t = _lap("props_water", t)
	if not await _next_frame():
		return
	t = Time.get_ticks_msec()
	_map.build_flora(float(preset.get("flora_density", 1.0)))
	t = _lap("flora", t)
	if not await _next_frame():
		return
	t = Time.get_ticks_msec()
	crop = CropManager.new()
	crop.name = "CropManager"
	add_child(crop)
	crop.setup(heightmap, _map.get_crop_fields(), rng, _map.flora.get_mesh)
	retreat_zones = _map.get_retreat_zones()
	t = _lap("crop", t)
	if not await _next_frame():
		return

	# 3. Environment
	t = Time.get_ticks_msec()
	var env_node: Node = AssetLoader.instantiate(ScenePaths.environment(_request.map_id))
	_env = env_node as MapEnvironmentBase
	if _env == null:
		if env_node != null:
			env_node.free()
		_env = MapEnvironmentBase.create_fallback()
	_env.name = "Environment"
	add_child(_env)
	_env.apply_quality(quality)
	get_viewport().scaling_3d_scale = clampf(float(preset.get("render_scale", 1.0)), 0.25, 1.0)
	t = _lap("environment", t)
	if not await _next_frame():
		return

	# 4. Player
	t = Time.get_ticks_msec()
	_player = _create_player()
	_player.name = "Player"
	add_child(_player)
	var spawn: Marker3D = _map.get_player_spawn()
	var spawn_pos: Vector3 = spawn.global_position if spawn != null else Vector3.ZERO
	spawn_pos.y = get_height(spawn_pos.x, spawn_pos.z)
	_player.global_position = spawn_pos
	_player.rotation.y = spawn.global_rotation.y if spawn != null else 0.0
	_player.setup(_request, self)
	t = _lap("player", t)
	if not await _next_frame():
		return

	# 5. Dog
	if _request.dog_id != &"":
		t = Time.get_ticks_msec()
		var dog_scene: PackedScene = load(ScenePaths.DOG) as PackedScene
		var dog_node: Node = dog_scene.instantiate() if dog_scene != null else null
		_dog = dog_node as Dog
		if _dog != null:
			_dog.name = "Dog"
			add_child(_dog)
			_dog.setup(_request.dog_id, self, spawn_pos + _player.global_transform.basis.x * DOG_SIDE_OFFSET_M)
		else:
			push_error("HuntController: %s root is not a Dog" % ScenePaths.DOG)
			if dog_node != null:
				dog_node.free()
		t = _lap("dog", t)

	# 6. Boars and start
	spawner.setup(self, _boars_root, contract, _map.get_spawn_zones())
	spawner.boar_died.connect(_on_boar_died)
	spawner.group_entered.connect(_on_group_entered)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.hunt_abandon_requested.connect(_on_abandon_requested)
	GameEvents.item_used.connect(_on_item_used)
	GameEvents.shot_fired.connect(_on_shot_fired)
	GameEvents.boar_hit.connect(_on_boar_hit)
	_result.boars_total = spawner.get_total()
	for id: StringName in AMBIENCE_LOOPS:
		Sfx.play_loop(id, AMBIENCE_DB)
	GameEvents.boar_counts_changed.emit(0, spawner.get_total())
	GameEvents.crop_health_changed.emit(100.0)
	_ready_flag = true
	spawner.begin()
	world_ready.emit()
	GameEvents.hunt_started.emit(_request)
	_loading.visible = false
	if _timing:
		print("HUNT_TIMING total_ms=%d shapes=%d" % [Time.get_ticks_msec() - t0, _map.get_static_shapes_used()])


func _next_frame() -> bool:
	await get_tree().process_frame
	return is_inside_tree()


func _lap(label: String, since: int) -> int:
	var now: int = Time.get_ticks_msec()
	if _timing:
		print("HUNT_TIMING %s_ms=%d" % [label, now - since])
	return now


func _resolve_quality() -> StringName:
	var q: String = String(_request.quality)
	if q == "":
		q = str(Profile.get_setting("quality"))
	if q == String(Ids.Q_LOW) or q == String(Ids.Q_MEDIUM) or q == String(Ids.Q_HIGH):
		return StringName(q)
	return Ids.Q_LOW if InputSetup.is_touch_mode() else Ids.Q_MEDIUM


func _create_player() -> PlayerBase:
	if not OS.get_cmdline_user_args().has(ARG_FALLBACK_PLAYER):
		var node: Node = AssetLoader.instantiate(ScenePaths.PLAYER)
		var p: PlayerBase = node as PlayerBase
		if p != null:
			return p
		if node != null:
			node.free()
	return FallbackPlayer.new()


# --- Frame / end of hunt (section 8.8) -----------------------------------------------------------

func _process(delta: float) -> void:
	if not _ready_flag:
		return
	_elapsed += delta
	if _over:
		return
	if _player_died:
		_finish(HuntResult.Outcome.DEFEAT_DEATH)
	elif crop != null and crop.get_health_pct() <= 0.0:
		_finish(HuntResult.Outcome.DEFEAT_CROP)
	elif _abandon:
		_finish(HuntResult.Outcome.ABANDONED)
	elif spawner.get_total() > 0 and _killed >= spawner.get_total():
		_finish(HuntResult.Outcome.VICTORY)


func _finish(outcome: HuntResult.Outcome) -> void:
	if _over:
		return
	_over = true
	if _result == null:
		_result = HuntResult.new()
	_result.outcome = outcome
	_result.crop_health_pct = crop.get_health_pct() if crop != null else 100.0
	_result.duration_s = _elapsed
	_result.contract_bonus = 0
	if outcome == HuntResult.Outcome.VICTORY:
		_result.contract_bonus = Profile.contract_bonus(_result.map_id, _result.contract_index, _result.crop_health_pct)
	_result.total_money = _result.money_from_kills + _result.contract_bonus
	_final_result = _result
	if crop != null:
		crop.freeze()
	if _player != null and is_instance_valid(_player):
		_player.set_input_enabled(false)
	GameEvents.hunt_ended.emit(_result)
	Sfx.play(&"victory_sting" if outcome == HuntResult.Outcome.VICTORY else &"defeat_sting")
	_route_after_delay()


func _route_after_delay() -> void:
	if not route_on_finish or not is_inside_tree():
		return
	var delay: float = float(Data.get_game().get("hunt", {}).get("end_delay_s", DEFAULT_END_DELAY_S))
	# Real time: keeps counting while paused and ignores Engine.time_scale.
	await get_tree().create_timer(maxf(delay, 0.01), true, false, true).timeout
	if is_inside_tree() and route_on_finish:
		Router.finish_hunt(_final_result)


# --- Events --------------------------------------------------------------------------------------

func _on_player_died() -> void:
	_player_died = true


func _on_abandon_requested() -> void:
	_abandon = true


func _on_shot_fired(_weapon_id: StringName, _origin: Vector3, _direction: Vector3, _noise_radius_m: float) -> void:
	if not _over:
		_result.shots_fired += 1


func _on_boar_hit(_boar_id: int, _zone: StringName, _damage: float, _hit_position: Vector3, shot_id: int) -> void:
	if _over or _hit_shots.has(shot_id):
		return
	_hit_shots[shot_id] = true
	_result.shots_hit += 1


func _on_item_used(item_id: StringName, item_position: Vector3) -> void:
	if _over or not _ready_flag:
		return
	_result.consumables_used[item_id] = int(_result.consumables_used.get(item_id, 0)) + 1
	if item_id == Ids.I_CORN_BAIT:
		_place_bait(item_position)


## Section 8.2 step 5. Order: boar_hit -> boar_state_changed(dead) -> boar_killed -> boar_counts_changed.
func _on_boar_died(boar: Boar) -> void:
	_marks.erase(boar.boar_id)
	if _over:
		return
	_killed += 1
	var kill: KillInfo = KillInfo.new()
	kill.boar_id = boar.boar_id
	kill.type_id = boar.type_id
	kill.weight_kg = boar.weight_kg
	kill.killing_zone = boar.killing_zone
	kill.one_shot = boar.is_one_shot()
	kill.clean_kill = _clean_zones.has(String(boar.killing_zone))
	kill.reward_money = Profile.kill_reward(boar.type_id, boar.weight_kg, boar.killing_zone, kill.one_shot,
		_result.map_id, _result.contract_index)
	kill.position = boar.global_position
	kill.time_s = _elapsed
	_result.kills.append(kill)
	_result.money_from_kills += kill.reward_money
	GameEvents.boar_killed.emit(kill)
	GameEvents.boar_counts_changed.emit(_killed, spawner.get_total())


func _on_group_entered(leader_type: StringName, count: int) -> void:
	if _over or _elapsed < 1.0:
		return
	var text: String = MSG_GROUP
	if leader_type == Ids.ALPHA:
		text = MSG_ALPHA
	elif count == 1:
		text = MSG_LONER
	GameEvents.hud_message_requested.emit(text, MSG_S)


# --- Bait ----------------------------------------------------------------------------------------

func _place_bait(at: Vector3) -> void:
	var effect: Dictionary = Data.get_equipment(Ids.I_CORN_BAIT).get("effect", {})
	var p: Vector2 = Steering.clamp_to_rect(Vector2(at.x, at.z), _map_rect, Boar.MAP_MARGIN_M)
	var bait: Bait = Bait.new()
	bait.name = "Bait_%d" % _baits.size()
	_baits_root.add_child(bait)
	bait.setup(Vector3(p.x, get_height(p.x, p.y), p.y), float(effect.get("duration_s", 45.0)),
		float(effect.get("attract_radius_m", 80.0)), int(effect.get("max_boars", 4)))
	bait.expired.connect(_on_bait_expired)
	_baits.append(bait)
	Sfx.play_3d(&"bait_drop", bait.global_position)
	GameEvents.bait_placed.emit(bait.global_position, bait.duration_s)


func _on_bait_expired(bait: Bait) -> void:
	_baits.erase(bait)


## An active bait within reach with a free slot; reserves the slot for the boar. Null if none.
func find_bait(from: Vector2, boar_id: int) -> Bait:
	for bait: Bait in _baits:
		if bait.active and from.distance_to(bait.get_xz()) <= bait.attract_radius_m and bait.try_reserve(boar_id):
			return bait
	return null


# --- Dog marks -----------------------------------------------------------------------------------

func mark_boar(boar_id: int, duration_s: float) -> void:
	_marks[boar_id] = _elapsed + duration_s


# --- HuntWorld -----------------------------------------------------------------------------------

func is_world_ready() -> bool:
	return _ready_flag


func get_map_id() -> StringName:
	return _request.map_id if _request != null else &""


func get_contract_index() -> int:
	return _request.contract_index if _request != null else 0


func get_map_rect() -> Rect2:
	return _map_rect


func get_height(x: float, z: float) -> float:
	return heightmap.get_height(x, z) if heightmap != null else 0.0


func get_normal(x: float, z: float) -> Vector3:
	return heightmap.get_normal(x, z) if heightmap != null else Vector3.UP


func get_crop_rects() -> Array[Rect2]:
	if crop == null:
		return []
	return crop.get_rects()


func get_crop_health_pct() -> float:
	return crop.get_health_pct() if crop != null else 100.0


func get_boars_total() -> int:
	return spawner.get_total() if spawner != null else 0


func get_boars_killed() -> int:
	return _killed


func get_alive_boar_ids() -> PackedInt32Array:
	return spawner.get_alive_ids() if spawner != null else PackedInt32Array()


func get_boar_position(boar_id: int) -> Vector3:
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	return b.global_position if b != null else Vector3.INF


func get_boar_type(boar_id: int) -> StringName:
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	return b.type_id if b != null else &""


func get_boar_zone_position(boar_id: int, zone: StringName) -> Vector3:
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	return b.get_zone_position(zone) if b != null else Vector3.INF


func get_nearest_boar_position(from: Vector3) -> Vector3:
	var b: Boar = spawner.find_nearest_alive(Vector2(from.x, from.z)) if spawner != null else null
	return b.global_position if b != null else Vector3.INF


func get_marked_boar_positions() -> PackedVector3Array:
	_marked_out.clear()
	for id: int in _marks.keys():
		if float(_marks[id]) < _elapsed:
			_marks.erase(id)
			continue
		var b: Boar = spawner.get_boar(id)
		if b != null and b.is_alive():
			_marked_out.append(b.global_position)
	return _marked_out


func has_dog() -> bool:
	return _dog != null


func get_dog_position() -> Vector3:
	return _dog.global_position if _dog != null else Vector3.INF


func get_dog_state() -> StringName:
	return _dog.state if _dog != null else &""


func get_dog_health_pct() -> float:
	return _dog.get_health_pct() if _dog != null else 0.0


func get_player() -> PlayerBase:
	return _player


func get_elapsed_s() -> float:
	return _elapsed


func is_hunt_over() -> bool:
	return _over


func get_result() -> HuntResult:
	return _final_result


# --- Debug hooks (tests) -------------------------------------------------------------------------

func debug_kill_boar(boar_id: int) -> void:
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	if b != null:
		b.debug_kill()


func debug_set_crop_health(pct: float) -> void:
	if crop != null:
		crop.set_health(pct)


func debug_force_end(outcome: HuntResult.Outcome) -> void:
	if _ready_flag:
		_finish(outcome)
