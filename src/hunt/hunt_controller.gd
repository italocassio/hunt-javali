class_name HuntController
extends HuntWorld
## Root of hunt.tscn. Assembles the hunt (map, environment, player, dog, boars), implements the
## HuntWorld contract and decides how the hunt ends (docs/arquitetura.md sections 8.1, 8.2, 8.8).

const LOADING_TEXT: String = "Preparando a caçada…"
const ARG_FALLBACK_PLAYER: String = "--fallback-player"
const ARG_TIMING: String = "--hunt-timing"
const ARG_NO_WARMUP: String = "--no-warmup"   # A/B measurements: skips the shader warm-up (world appears at once)
const DOG_SIDE_OFFSET_M: float = 1.5
const DEFAULT_END_DELAY_S: float = 2.5
const AMBIENCE_LOOPS: Array[StringName] = [&"amb_cerrado_loop", &"amb_wind_loop"]
const AMBIENCE_DB: float = -6.0
## Web only: caps window.devicePixelRatio while hunting (preset "max_pixel_ratio"). Godot Web sizes the canvas from it
## every loop iteration, so this is cheaper than scaling_3d_scale (which adds a fixed intermediate target + blit).
## The getter is installed once and keeps the browser's real value; window.__huntMaxDpr <= 0 means no cap.
const JS_DPR_CAP_INSTALL: String = PowerManager.JS_DPR_CAP_INSTALL
const JS_DPR_CAP_READ: String = "(window.__huntMaxDpr > 0) ? window.__huntMaxDpr : 0"
const MSG_GROUP: String = "Uma vara saiu da mata!"
const MSG_LONER: String = "Um javali solitário saiu da mata!"
const MSG_ALPHA: String = "O cachaço alfa entrou na área!"
const MSG_S: float = 3.0
const WAITING_TEXT: String = "Aguardando os outros caçadores…"
const SNAPSHOT_HEADER_BYTES: int = 10        # t_ms u32, crop u16, killed u8, total u8, flags u8, n_hunters u8
const SNAPSHOT_BOAR_BYTES: int = 7
const SNAPSHOT_DOG_BYTES: int = 8
const CROP_WIRE_SCALE: float = 100.0
const SNAP_FLAG_CROP_ATTACK: int = 1         # H_SNAPSHOT flags b0: boars at the crop
## EV_MESSAGE msg 0..2 (docs/multiplayer.md section 4.5): same texts as the host's group announcements.
## msg 3..5 are the dog's (Dog.MESSAGES).
const NET_MESSAGES: Array[String] = [MSG_GROUP, MSG_LONER, MSG_ALPHA]
const NET_MSG_GROUP: int = 0
const NET_MSG_LONER: int = 1
const NET_MSG_ALPHA: int = 2
const MSG_HOST_ALONE: String = "Conexão perdida: você continua sozinho."
const DEFAULT_HUNTER_NAME: String = "Caçador %d"
## A client's own bait (shown at once) and the host's EV_BAIT for it are the same bait within this distance.
const BAIT_MATCH_M: float = 0.25
const HUNTER_FLAGS_OFFSET: int = 10          # flags byte inside the 14 bytes of HUNTER_STATE

## Tests set this to false before add_child so the hunt does not change scene when it ends.
var route_on_finish: bool = true

## Test hook (no Net): set before add_child to force a network role without touching the Net autoload.
## -1 = read Net; otherwise Net.Role.HOST / Net.Role.CLIENT. test_net_roster is the synthetic roster.
## With the hook on, bind_world/hunt_go are skipped: the test calls debug_net_go() to release the hunt.
var test_net_role: int = -1
var test_net_roster: Array[NetPeerInfo] = []
var test_net_local_slot: int = 0
var test_fallback_remote: bool = false   # use FallbackRemoteHunter even if ScenePaths.REMOTE_HUNTER exists

# Package-internal services (boars, dog, spawner).
var heightmap: Heightmap = null
var obstacles: ObstacleGrid = ObstacleGrid.new()
var crop: CropManager = null
var retreat_zones: PackedVector2Array = PackedVector2Array()
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var crop_drain_mult: float = 1.0
var spawner: BoarSpawner = null
## Horde (docs/plano_horda_nivel2.md C2): rectangles the boars' route goes around, from MapRoot after the props step.
var horde_route_obstacles: Array[Dictionary] = []

var _request: HuntRequest = null
var _map: MapRoot = null
var _player: PlayerBase = null
var _dog: Dog = null                    # the dog of this machine's hunter (offline and host)
var _dogs: Dictionary = {}              # slot -> Dog (offline and host)
var _dog_list: Array[Dog] = []
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
var _prev_max_dpr: float = 0.0
var _dpr_cap_applied: bool = false
var _timing: bool = false
var _warmup_on: bool = true
var _progress: LoadingProgress = LoadingProgress.new()
var _warmup: ShaderWarmup = ShaderWarmup.new()

# Network (docs/multiplayer.md section 6.1). _net_role == Net.Role.OFFLINE is the solo path.
var _net_role: int = 0
var _net_hooked: bool = false
var _local_slot: int = 0
var _go: bool = true                   # false while waiting for Net.hunt_go
var _go_received: bool = false
var _assembled: bool = false
var _t0_ms: int = 0
var _spawn_base: Vector3 = Vector3.ZERO
var _spawn_right: Vector3 = Vector3.RIGHT
var _spawn_yaw: float = 0.0
var _go_elapsed: float = 0.0
var _remotes: Dictionary = {}          # slot -> PlayerBase
var _hunters_list: Array[PlayerBase] = []
var _snap_hunters: StreamPeerBuffer = StreamPeerBuffer.new()
var _snap_scratch: StreamPeerBuffer = StreamPeerBuffer.new()
var _net_t_ms: int = 0
var _net_crop_pct: float = 100.0
var _net_killed: int = 0
var _net_total: int = 0
var _host_sync: HuntHostSync = null      # HOST: boar replication (section 6.3)
var _replica: HuntReplica = null        # CLIENT: boar puppets (section 6.3)
var _dead_slots: Dictionary = {}        # slot -> true once hunter_died was emitted for it
var _slot_names: Dictionary = {}        # slot -> display name, captured at assembly (leavers keep theirs)
var _slot_stats: Dictionary = {}        # slot -> {kills: int, money: int, weight_kg: float}, every kill seen here
var _host_entries: Array = []           # CLIENT: EV_HUNT_END entries {slot, kills, money}
var _pending_baits: PackedVector2Array = PackedVector2Array()   # CLIENT: own baits waiting for their EV_BAIT
var _conn_lost: bool = false
var _away_slots: Dictionary = {}        # slot -> true while that remote's snapshot record carries HF_AWAY

# Horde mode (docs/horda.md section 5). Nothing here runs with request.mode == contract.
var _horde: Dictionary = {}             # data/horde.json (empty outside the horde)
var _director: HordeDirector = null     # offline and host
var _objective: Vector3 = Vector3.INF   # barn origin on the ground
var _eat_ring_m: float = 0.0
var _stock_visual: CornStockVisualBase = null
var _carcasses: Array[Node3D] = []      # dead boars (host) / dead puppets (client), oldest first
var _max_carcasses: int = 0
# CLIENT: the last EV_HORDE_WAVE (section 9.2); the countdown keeps running here.
var _hw_wave: int = 0
var _hw_count: int = 0
var _hw_phase: StringName = &""
var _hw_countdown: float = 0.0
var _hw_total: int = 0
var _hw_killed_before: int = 0
# Horde levels (docs/plano_horda_nivel2.md). _horde above is the resolved level (Data.get_horde_level).
var _horde_level: int = 0               # 0 outside the horde
var _player_bounds: Rect2 = Rect2()     # confine.enabled: the farm fence rect, inset
var _ammo_crates: HordeAmmoCrates = null
var _downed_slots: Dictionary = {}      # slot -> true once hunter_downed was emitted (cleared when alive again)

# Counters for tests and diagnostics.
var revives_accepted: int = 0
var revives_rejected: int = 0
var ammo_claims_accepted: int = 0
var ammo_claims_rejected: int = 0

@onready var _boars_root: Node3D = $Boars
@onready var _baits_root: Node3D = $Baits
@onready var _loading: CanvasLayer = $LoadingOverlay


func _ready() -> void:
	spawner = $BoarSpawner as BoarSpawner
	_resolve_net_role()
	if _net_role == Net.Role.CLIENT:
		# The client does not simulate boars: no spawner (section 6.1).
		if spawner != null:
			spawner.free()
			spawner = null
	_timing = OS.get_cmdline_user_args().has(ARG_TIMING)
	_warmup_on = not OS.get_cmdline_user_args().has(ARG_NO_WARMUP)
	_prev_scaling = get_viewport().scaling_3d_scale
	var label: Label = _loading.get_node_or_null(^"Label") as Label
	if label != null:
		label.text = LOADING_TEXT
	_loading.visible = true
	_progress.setup(_loading, label, LOADING_TEXT, Data.get_game().get("loading", {}).get("step_weights", {}))
	if _timing:
		_progress.changed.connect(_on_progress_changed)
	_warmup.setup(self)
	_assemble()


func _exit_tree() -> void:
	if _net_role != Net.Role.OFFLINE and not _net_hooked:
		Net.unbind_world(self)
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.scaling_3d_scale = _prev_scaling
	_restore_pixel_ratio()
	for id: StringName in AMBIENCE_LOOPS:
		Sfx.stop_loop(id)


## Web only: limits the canvas pixel ratio during the hunt (menus keep the native one). 0 = no cap.
func _apply_pixel_ratio_cap(max_ratio: float) -> void:
	if not OS.has_feature("web") or max_ratio <= 0.0:
		return
	JavaScriptBridge.eval(JS_DPR_CAP_INSTALL, true)
	if not _dpr_cap_applied:
		_prev_max_dpr = float(JavaScriptBridge.eval(JS_DPR_CAP_READ, true))
	_dpr_cap_applied = true
	JavaScriptBridge.eval("window.__huntMaxDpr = %s;" % str(max_ratio), true)


func _restore_pixel_ratio() -> void:
	if not _dpr_cap_applied:
		return
	_dpr_cap_applied = false
	JavaScriptBridge.eval("window.__huntMaxDpr = %s;" % str(_prev_max_dpr), true)


# --- Assembly (section 8.1) ----------------------------------------------------------------------

func _assemble() -> void:
	var t0: int = Time.get_ticks_msec()
	_t0_ms = t0
	# 1. Request
	_request = Router.get_pending_request()
	if _request == null:
		_request = HuntRequest.make_debug()
	_result = HuntResult.new()
	_result.map_id = _request.map_id
	_result.contract_index = _request.contract_index
	if _net_role != Net.Role.OFFLINE:
		_result.player_count = maxi(_roster().size(), 1)
		# Progression only for whoever already had this contract (section 6.10).
		_result.counts_for_progression = Profile.is_contract_unlocked(_request.map_id, _request.contract_index)
		_capture_slot_names()
	if _request.rng_seed != 0:
		rng.seed = _request.rng_seed
	else:
		rng.randomize()
	var contract: Dictionary = Data.get_contract(_request.map_id, _request.contract_index)
	var plan: Array = []
	if _request.is_horde():
		# Horde (docs/horda.md section 5.1, steps 1-2): the waves replace the contract groups. Every horde setting is
		# the resolved level's (docs/plano_horda_nivel2.md section 4.2).
		_horde_level = _resolve_horde_level()
		_horde = Data.get_horde_level(_horde_level)
		_result.mode = Ids.MODE_HORDE
		_result.horde_level = _horde_level
		_result.counts_for_progression = false
		if _horde.is_empty():
			push_error("HuntController: horde requested but data/horde.json is empty or invalid")
			_ready_flag = true
			_loading.visible = false
			_finish(HuntResult.Outcome.ABANDONED)
			return
		_result.contract_index = _request.contract_index
		_eat_ring_m = float(_horde.get("eat_ring_m", 0.0))
		_max_carcasses = maxi(int(_horde.get("max_carcasses", 0)), 0)
		contract = {"crop_drain_mult": float(_horde.get("barn_drain_mult", 1.0)), "groups": []}
		if _net_role != Net.Role.CLIENT:
			plan = HordeDirector.plan_waves(_horde, _result.player_count if _net_role == Net.Role.HOST else 1)
			_result.horde_wave_count = plan.size()
			var flat: Array = []
			for wave_groups: Variant in plan:
				flat.append_array(wave_groups as Array)
			contract["groups"] = flat
	elif _net_role == Net.Role.HOST:
		# More hunters, more boars (section 6.10). The client never simulates the groups.
		contract = contract.duplicate(true)
		contract["groups"] = BoarSpawner.scale_groups(contract.get("groups", []), _result.player_count,
			Data.get_game().get("coop", {}))
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
	_map.set_horde_layout(is_horde())
	_map.build_props_and_water()
	if is_horde() and not _build_objective():
		return
	t = _lap("props_water", t)
	if not await _next_frame():
		return
	t = Time.get_ticks_msec()
	# Network: every peer gets the same trunks whatever its quality (section 6.4).
	_map.build_flora(float(preset.get("flora_density", 1.0)), _net_role != Net.Role.OFFLINE)
	t = _lap("flora", t)
	if not await _next_frame():
		return
	# Top-down map image for the HUD minimap; every role builds it (section 8.1, 1.4).
	t = Time.get_ticks_msec()
	_map.build_minimap(Data.get_game().get("minimap", {}) as Dictionary)
	t = _lap("minimap", t)
	if not await _next_frame():
		return
	t = Time.get_ticks_msec()
	crop = CropManager.new()
	crop.name = "CropManager"
	add_child(crop)
	crop.setup(heightmap, _map.get_crop_fields(), rng, _map.flora.get_mesh)
	if is_horde():
		crop.set_store_mode(true)   # the crop health is the barn's corn stock (section 5.4)
	retreat_zones = _map.get_retreat_zones()
	t = _lap("crop", t)
	# From here the world stays hidden until the shader warm-up shows it part by part (section 8.1).
	if _warmup_on:
		var extra: Array = []
		if _stock_visual != null:
			extra.append(_stock_visual)
		if _ammo_crates != null:
			extra.append(_ammo_crates)
		_warmup.hide_world(_map, crop, extra)
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
	_apply_pixel_ratio_cap(float(preset.get("max_pixel_ratio", 0.0)))
	t = _lap("environment", t)
	if not await _next_frame():
		return

	# 4. Player
	t = Time.get_ticks_msec()
	_player = _create_player()
	_player.name = "Player"
	_player.slot = _local_slot
	add_child(_player)
	var spawn: Marker3D = _map.get_player_spawn()
	var spawn_pos: Vector3 = spawn.global_position if spawn != null else Vector3.ZERO
	var spawn_yaw: float = spawn.global_rotation.y if spawn != null else 0.0
	var level_spawn: Array = _horde.get("player_spawn", []) if is_horde() else []
	if level_spawn.size() >= 3:
		# Horde level: [x, z, yaw_deg] replaces the map's PlayerSpawn (inside the farm when confined).
		spawn_pos = Vector3(float(level_spawn[0]), 0.0, float(level_spawn[1]))
		spawn_yaw = deg_to_rad(float(level_spawn[2]))
	spawn_pos.y = get_height(spawn_pos.x, spawn_pos.z)
	_player.global_position = spawn_pos
	_player.rotation.y = spawn_yaw
	if _net_role != Net.Role.OFFLINE:
		_spawn_base = spawn_pos
		_spawn_right = _player.global_transform.basis.x
		_spawn_yaw = _player.rotation.y
		spawn_pos = _spread_spawn(_local_slot)
		_player.global_position = spawn_pos
		_player.set_input_enabled(false)   # released by hunt_go
	_player.setup(_request, self)
	_player.set_input_enabled(false)   # closed while the overlay is up; released by _announce_start
	_player.slot = _local_slot   # Player.setup reads Net; the test hook may have chosen another slot
	_hunters_list.append(_player)
	if _net_role != Net.Role.OFFLINE:
		_create_remote_hunters()
	t = _lap("player", t)
	if not await _next_frame():
		return

	# 5. Dogs: offline the local hunter's; host one per hunter that brought one; client: puppets (replica)
	if _net_role != Net.Role.CLIENT and not _dog_breeds().is_empty():
		t = Time.get_ticks_msec()
		_create_dogs()
		if _warmup_on:
			_warmup.hide_group(ShaderWarmup.GROUP_DOGS, _dog_list)
		t = _lap("dog", t)
		if not await _next_frame():
			return
	else:
		_progress.skip("dog")

	# 5b. Boar visual warm-up: build the cached meshes now, not when the first boar spawns (all roles: puppets too)
	t = Time.get_ticks_msec()
	if not await _warm_boar_visuals():
		return
	t = _lap("boar_warmup", t)
	if not await _next_frame():
		return

	# 5c. Shader warm-up behind the overlay (section 8.1): the world appears part by part, then the actors.
	t = Time.get_ticks_msec()
	if _warmup_on and not await _warmup.run(_player, _warm_breeds(), _player_has_thermal(), _on_warmup_progress):
		return
	t = _lap("shader_warmup", t)
	if _timing:
		print("HUNT_TIMING warmup_detail frames=%d %s" % [_warmup.get_frames_used(), " ".join(_warmup.get_timing())])
	if not await _next_frame():
		return

	# 5d. Ambience loops, one per frame (building the stream costs ~100 ms each in the browser: not in the start frame).
	t = Time.get_ticks_msec()
	for id: StringName in AMBIENCE_LOOPS:
		Sfx.play_loop(id, AMBIENCE_DB)
		if not await _next_frame():
			return
	t = _lap("ambience", t)

	# 6. Boars and start
	if _net_role == Net.Role.CLIENT:
		_finish_assembly_client()
		return
	t = Time.get_ticks_msec()
	spawner.setup(self, _boars_root, contract, _map.get_spawn_zones())
	spawner.boar_died.connect(_on_boar_died)
	spawner.group_entered.connect(_on_group_entered)
	if is_horde():
		# After the controller's boar_died connection (section 5.1, step 5).
		_director = HordeDirector.new()
		_director.name = "HordeDirector"
		add_child(_director)
		_director.setup(self, spawner, _horde, plan)
		_director.wave_changed.connect(_on_director_wave_changed)
		_director.wave_progress.connect(_on_director_wave_progress)
	if _net_role == Net.Role.HOST:
		_host_sync = HuntHostSync.new()
		_host_sync.name = "HuntHostSync"
		add_child(_host_sync)
		_host_sync.setup(self, spawner)
	if _timing:
		print("HUNT_TIMING start_spawner_ms=%d" % (Time.get_ticks_msec() - t))
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.hunt_abandon_requested.connect(_on_abandon_requested)
	GameEvents.item_used.connect(_on_item_used)
	GameEvents.shot_fired.connect(_on_shot_fired)
	GameEvents.boar_hit.connect(_on_boar_hit)
	_result.boars_total = spawner.get_total()
	GameEvents.boar_counts_changed.emit(0, spawner.get_total())
	GameEvents.crop_health_changed.emit(100.0)
	_ready_flag = true
	if _net_role == Net.Role.OFFLINE:
		spawner.begin()
		if _director != null:
			_director.begin()
		world_ready.emit()
		_announce_start()
	else:
		_enter_wait()


## Client: map, local player and remote hunters only. Boars, crop damage and dogs come from the host.
func _finish_assembly_client() -> void:
	_replica = HuntReplica.new()
	_replica.name = "HuntReplica"
	add_child(_replica)
	_replica.setup(self, heightmap, _map_rect, crop)
	_replica.set_dog_breeds(_dog_breeds())
	_replica.dog_mark_received.connect(_on_dog_mark)
	_replica.kill_confirmed.connect(_on_replica_kill)
	_replica.bait_received.connect(_on_bait_received)
	_replica.message_received.connect(_on_net_message)
	_replica.hunt_end_received.connect(_on_host_hunt_end)
	_replica.full_sync_started.connect(_on_full_sync_started)
	_replica.full_sync_finished.connect(_on_full_sync_finished)
	if is_horde():
		_replica.horde_wave_received.connect(_on_horde_wave_received)
		_replica.hunter_revived_received.connect(_on_hunter_revived_received)
		_replica.ammo_crate_received.connect(_on_ammo_crate_received)
	GameEvents.net_reconnect_changed.connect(_on_net_reconnect_changed)
	GameEvents.hunt_abandon_requested.connect(_on_abandon_requested)
	GameEvents.item_used.connect(_on_item_used)
	GameEvents.shot_fired.connect(_on_shot_fired)
	GameEvents.boar_hit.connect(_on_boar_hit)
	GameEvents.boar_counts_changed.emit(0, 0)
	GameEvents.crop_health_changed.emit(100.0)
	_ready_flag = true
	_enter_wait()


func _announce_start() -> void:
	_progress.finish()
	if _player != null and is_instance_valid(_player) and not _over:
		_player.set_input_enabled(true)
	GameEvents.hunt_started.emit(_request)
	_loading.visible = false
	if _timing:
		print("HUNT_TIMING total_ms=%d shapes=%d" % [Time.get_ticks_msec() - _t0_ms, _map.get_static_shapes_used()])


# --- Network roles (section 6.1) ------------------------------------------------------------------

func _resolve_net_role() -> void:
	if test_net_role >= 0:
		_net_hooked = true
		_net_role = test_net_role
		_local_slot = test_net_local_slot
	elif Net.is_active():
		_net_role = Net.get_role()
		_local_slot = Net.get_local_slot()
	if _net_role != Net.Role.OFFLINE:
		_go = false


func _roster() -> Array[NetPeerInfo]:
	return test_net_roster if _net_hooked else Net.get_roster()


## Start position of a slot: PlayerSpawn shifted along the right axis, centered on the spawn.
func _spread_spawn(for_slot: int) -> Vector3:
	var count: int = maxi(_roster().size(), 1)
	var spacing: float = float(Data.get_game().get("coop", {}).get("spawn_spacing_m", 2.0))
	var offset: float = (float(for_slot) - float(count - 1) * 0.5) * spacing
	var pos: Vector3 = _spawn_base + _spawn_right * offset
	pos.y = get_height(pos.x, pos.z)
	return pos


func _create_remote_hunters() -> void:
	for info: NetPeerInfo in _roster():
		if info.slot == _local_slot or _remotes.has(info.slot):
			continue
		var node: Node = null if test_fallback_remote else AssetLoader.instantiate(ScenePaths.REMOTE_HUNTER)
		var hunter: PlayerBase = node as PlayerBase
		if hunter == null:
			if node != null:
				node.free()
			hunter = FallbackRemoteHunter.new()
		hunter.name = "Hunter_%d" % info.slot
		hunter.slot = info.slot
		add_child(hunter)
		hunter.global_position = _spread_spawn(info.slot)
		hunter.rotation.y = _spawn_yaw
		hunter.setup_remote(info.slot, info.display_name, info.weapon_id, self)
		_remotes[info.slot] = hunter
		_hunters_list.append(hunter)
		GameEvents.hunter_joined.emit(info.slot, info.display_name)


## Network start: the overlay stays up until Net.hunt_go. Net.hunt_go is connected before bind_world so a
## synchronous emission is not lost.
func _enter_wait() -> void:
	_progress.finish()   # everything is loaded here; what is left is waiting for the others
	var label: Label = _loading.get_node_or_null(^"Label") as Label
	if label != null:
		label.text = WAITING_TEXT
	if not _net_hooked:
		Net.hunt_go.connect(_on_net_go, CONNECT_ONE_SHOT)
		Net.bind_world(self)
	world_ready.emit()
	_assembled = true
	if not _net_hooked and not Net.is_active():
		_conn_lost = true   # the room went away while this machine was loading: nobody will call us
	if _conn_lost:
		net_connection_lost()
	elif _go_received:
		_begin_net_hunt()


func _capture_slot_names() -> void:
	for info: NetPeerInfo in _roster():
		var shown: String = info.display_name.strip_edges()
		_slot_names[info.slot] = shown if shown != "" else DEFAULT_HUNTER_NAME % (info.slot + 1)
		_slot_stats[info.slot] = {"kills": 0, "money": 0, "weight_kg": 0.0}


func _on_net_go() -> void:
	_go_received = true
	if _assembled and not _go:
		_begin_net_hunt()


func _begin_net_hunt() -> void:
	if _go:
		return
	_go = true
	_go_elapsed = _elapsed
	if _net_role == Net.Role.HOST and spawner != null:
		spawner.begin()
		if _director != null:
			_director.begin()
	if _player != null and is_instance_valid(_player):
		_player.set_input_enabled(true)
	_announce_start()


## Instantiates the boar visual once per boar type and weight (min, middle, max of the type's range from
## data) so the static mesh caches are filled before the first spawn. Instances are freed outside the tree.
## One type per frame (the overlay keeps redrawing); false if the hunt left the tree meanwhile.
func _warm_boar_visuals() -> bool:
	var type_ids: Array[StringName] = Data.get_boar_type_ids()
	for i: int in type_ids.size():
		var type_id: StringName = type_ids[i]
		var def: Dictionary = Data.get_boar_type(type_id)
		var w_min: float = float(def.get("weight_min_kg", 0.0))
		var w_max: float = maxf(float(def.get("weight_max_kg", w_min)), w_min)
		for kg: float in [w_min, (w_min + w_max) * 0.5, w_max]:
			var node: Node = AssetLoader.instantiate(ScenePaths.BOAR_VISUAL)
			var visual: BoarVisualBase = node as BoarVisualBase
			if visual == null:
				if node != null:
					node.free()
				return true   # asset missing: the fallback needs no warm-up
			visual.setup(type_id, kg)
			visual.free()
		_progress.set_fraction("boar_warmup", float(i + 1) / float(type_ids.size()))
		if i < type_ids.size() - 1 and not await _next_frame():
			return false
	return true


## Dog breeds shown by the warm-up (every distinct breed of the hunt, puppets included).
func _warm_breeds() -> Array[StringName]:
	var out: Array[StringName] = []
	var breeds: Dictionary = _dog_breeds()
	for slot: Variant in breeds:
		var breed: StringName = breeds[slot] as StringName
		if not out.has(breed):
			out.append(breed)
	return out


func _player_has_thermal() -> bool:
	return _player != null and _player.has_method(&"has_thermal") and bool(_player.call(&"has_thermal"))


func _on_warmup_progress(fraction: float) -> void:
	_progress.set_fraction("shader_warmup", fraction)


func _on_progress_changed(value: float) -> void:
	print("HUNT_PROGRESS %d t_ms=%d" % [roundi(value * 100.0), Time.get_ticks_msec() - _t0_ms])


func _next_frame() -> bool:
	await get_tree().process_frame
	return is_inside_tree()


func _lap(label: String, since: int) -> int:
	var now: int = Time.get_ticks_msec()
	if _timing:
		print("HUNT_TIMING %s_ms=%d" % [label, now - since])
	_progress.complete(label)
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
	if not _ready_flag or not _go:
		return
	_elapsed += delta
	if _over:
		return
	_track_deaths()
	if _net_role == Net.Role.CLIENT:
		if _hw_phase == Ids.HP_INTERMISSION and _hw_countdown > 0.0:
			_hw_countdown = maxf(_hw_countdown - delta, 0.0)
		# Only the host decides the end (EV_HUNT_END); a client ends alone only by leaving or losing the host.
		if _abandon:
			_finish(HuntResult.Outcome.ABANDONED)
		return
	if _all_hunters_dead():
		_finish(HuntResult.Outcome.DEFEAT_DEATH)
	elif crop != null and crop.get_health_pct() <= 0.0:
		_finish(HuntResult.Outcome.DEFEAT_CROP)
	elif _abandon:
		_finish(HuntResult.Outcome.ABANDONED)
	elif spawner.get_total() > 0 and _killed >= spawner.get_total():
		_finish(HuntResult.Outcome.VICTORY)


## hunter_died(slot) once per hunter (local or remote) whose is_alive() went false (section 6.8). Horde revive
## (docs/plano_horda_nivel2.md section 4.7): a downed hunter is not dead; hunter_downed(slot) once per fall.
func _track_deaths() -> void:
	for h: PlayerBase in _hunters_list:
		if not is_instance_valid(h):
			continue
		if h.is_alive():
			_downed_slots.erase(h.slot)
		elif h.is_downed():
			if not _downed_slots.has(h.slot):
				_downed_slots[h.slot] = true
				GameEvents.hunter_downed.emit(h.slot)
		elif not _dead_slots.has(h.slot):
			_dead_slots[h.slot] = true
			GameEvents.hunter_died.emit(h.slot)


## Solo: player_died received (contract section 8.8, unchanged). Network host: every hunter still in the
## hunt is dead. A hunter that left is out of the list; a briefly silent one (is_present() false) keeps
## counting by its last state, so a network hiccup never ends the hunt.
func _all_hunters_dead() -> bool:
	if _net_role == Net.Role.OFFLINE:
		return _player_died
	var any: bool = false
	for h: PlayerBase in _hunters_list:
		if not is_instance_valid(h):
			continue
		any = true
		if h.is_alive():
			return false
	return any


func _finish(outcome: HuntResult.Outcome) -> void:
	if _over:
		return
	if _ready_flag:
		_track_deaths()   # a death in the same frame as the end still gets its hunter_died
	_over = true
	if _result == null:
		_result = HuntResult.new()
	_result.outcome = outcome
	_result.crop_health_pct = get_crop_health_pct()
	if _net_role == Net.Role.CLIENT:
		_result.boars_total = _net_total
	if outcome == HuntResult.Outcome.DISCONNECTED:
		_result.counts_for_progression = false
	_result.duration_s = _elapsed
	_result.contract_bonus = 0
	if is_horde():
		# Horde (docs/horda.md section 5.5): defense bonus on victory, never progression.
		_result.counts_for_progression = false
		if _net_role == Net.Role.CLIENT and _hw_count > 0:
			_result.horde_wave_count = _hw_count
		if outcome == HuntResult.Outcome.VICTORY:
			_result.contract_bonus = Profile.horde_bonus(_result.crop_health_pct, get_horde_level())
			_result.horde_waves_cleared = _result.horde_wave_count
		else:
			_result.horde_waves_cleared = get_horde_waves_cleared()
	elif outcome == HuntResult.Outcome.VICTORY:
		# Full bonus for every hunter in the room at the end, alive or not (section 6.10).
		_result.contract_bonus = Profile.contract_bonus(_result.map_id, _result.contract_index, _result.crop_health_pct)
	_result.total_money = _result.money_from_kills + _result.contract_bonus
	if _net_role != Net.Role.OFFLINE:
		_result.team_kills = get_boars_killed()
		_result.scoreboard = _build_scoreboard()
	_final_result = _result
	if crop != null:
		crop.freeze()
	if _player != null and is_instance_valid(_player):
		_player.set_input_enabled(false)
	if _host_sync != null:
		# Only the host decides; every client ends with the same outcome (section 6.8).
		_host_sync.queue_hunt_end(outcome, _result.crop_health_pct, _elapsed, _killed, get_boars_total(),
			_wire_entries())
		if not _net_hooked:
			Net.flush()
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
	# Only this machine's shots count as its hits (section 6.3). Solo: every shot is slot 0.
	if _over or _hit_shots.has(shot_id) or NetCodec.shot_slot(shot_id) != _local_slot:
		return
	_hit_shots[shot_id] = true
	_result.shots_hit += 1


func _on_item_used(item_id: StringName, item_position: Vector3) -> void:
	if _over or not _ready_flag:
		return
	# Each machine counts only its own consumables (section 6.6).
	_result.consumables_used[item_id] = int(_result.consumables_used.get(item_id, 0)) + 1
	if item_id == Ids.I_CORN_BAIT:
		if _net_role == Net.Role.CLIENT:
			_client_bait(item_position)
		else:
			_place_bait(item_position)


## Section 8.2 step 5. Order: boar_hit -> boar_state_changed(dead) -> boar_killed -> boar_counts_changed.
func _on_boar_died(boar: Boar) -> void:
	_marks.erase(boar.boar_id)
	if is_horde():
		_add_carcass(boar)
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
	if is_horde():
		kill.reward_money = Profile.horde_kill_reward(boar.type_id, boar.weight_kg, boar.killing_zone, kill.one_shot,
			get_horde_level())
	else:
		kill.reward_money = Profile.kill_reward(boar.type_id, boar.weight_kg, boar.killing_zone, kill.one_shot,
			_result.map_id, _result.contract_index)
	kill.position = boar.global_position
	kill.time_s = _elapsed
	kill.killer_slot = boar.killer_slot
	_note_kill(kill)
	_credit_kill(kill)
	if _host_sync != null:
		_host_sync.queue_death(boar, kill, _killed, spawner.get_total())
	GameEvents.boar_killed.emit(kill)
	GameEvents.boar_counts_changed.emit(_killed, spawner.get_total())


## Each machine keeps only the kills of its own hunter (section 6.10). Solo: every kill is slot 0.
func _credit_kill(kill: KillInfo) -> void:
	if kill.killer_slot != _local_slot:
		return
	_result.kills.append(kill)
	_result.money_from_kills += kill.reward_money


## Client: a boar died on the host (EV_BOAR_DEATH). Same order of signals as the host.
func _on_replica_kill(kill: KillInfo, killed: int, total: int) -> void:
	_marks.erase(kill.boar_id)
	if is_horde() and _replica != null:
		_add_carcass(_replica.get_puppet(kill.boar_id))
	if _over:
		return
	kill.time_s = _elapsed
	_note_kill(kill)
	_credit_kill(kill)
	_net_killed = killed
	_net_total = total
	GameEvents.boar_killed.emit(kill)
	GameEvents.boar_counts_changed.emit(killed, total)
	if is_horde() and _hw_phase == Ids.HP_WAVE:
		GameEvents.horde_wave_progress.emit(_client_wave_remaining(), _hw_total)


## Team tally per slot (scoreboard). Network only: solo leaves the scoreboard empty.
func _note_kill(kill: KillInfo) -> void:
	if _net_role == Net.Role.OFFLINE:
		return
	var s: Dictionary = _slot_stats.get(kill.killer_slot, {"kills": 0, "money": 0, "weight_kg": 0.0})
	s["kills"] = int(s["kills"]) + 1
	s["money"] = int(s["money"]) + kill.reward_money
	s["weight_kg"] = float(s["weight_kg"]) + kill.weight_kg
	_slot_stats[kill.killer_slot] = s


## HuntResult.scoreboard: one {slot, name, kills, money, weight_kg} per hunter that started the hunt (leavers
## included), by slot. money = kill money only (the bonus is the same for everybody). On a client the host's
## EV_HUNT_END counts win over the local tally (they match unless an event was lost).
func _build_scoreboard() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slots: Array = _slot_stats.keys()
	slots.sort()
	for s: Variant in slots:
		var for_slot: int = int(s)
		var stats: Dictionary = _slot_stats[for_slot]
		var kills: int = int(stats["kills"])
		var money: int = int(stats["money"])
		for e: Dictionary in _host_entries:
			if int(e["slot"]) == for_slot:
				kills = int(e["kills"])
				money = int(e["money"])
		out.append({"slot": for_slot, "name": str(_slot_names.get(for_slot, DEFAULT_HUNTER_NAME % (for_slot + 1))),
			"kills": kills, "money": money, "weight_kg": float(stats["weight_kg"])})
	return out


## EV_HUNT_END entries from the host's own tally.
func _wire_entries() -> Array:
	var out: Array = []
	for e: Dictionary in _build_scoreboard():
		out.append({"slot": e["slot"], "kills": e["kills"], "money": e["money"]})
	return out


## Client: the host ended the hunt. Same outcome here, with the host's crop and counts (section 6.8).
func _on_host_hunt_end(outcome: int, crop_pct: float, killed: int, total: int, entries: Array) -> void:
	if _over:
		return
	_host_entries = entries
	_net_killed = killed
	_net_total = total
	_net_crop_pct = crop_pct
	if crop != null:
		crop.set_replicated_health(crop_pct)
	if outcome == HuntResult.Outcome.ABANDONED:
		# The host closed the hunt for everybody: kills are paid, it is not this player's defeat, no progress.
		_result.counts_for_progression = false
	var known: bool = outcome >= 0 and outcome < HuntResult.Outcome.size()
	_finish(outcome as HuntResult.Outcome if known else HuntResult.Outcome.ABANDONED)


func _on_group_entered(leader_type: StringName, count: int) -> void:
	if _over or _elapsed < 1.0:
		return
	if is_horde() and leader_type != Ids.ALPHA:
		return   # D11: the wave banner replaces the herd announcements; only the alpha's stays
	var text: String = MSG_GROUP
	if leader_type == Ids.ALPHA:
		text = MSG_ALPHA
	elif count == 1:
		text = MSG_LONER
	GameEvents.hud_message_requested.emit(text, MSG_S)
	if _host_sync != null:
		var msg: int = NET_MSG_ALPHA if text == MSG_ALPHA else (NET_MSG_LONER if text == MSG_LONER else NET_MSG_GROUP)
		_host_sync.queue_message(NetCodec.NO_SLOT, msg)


## Client: EV_MESSAGE from the host (group announcements).
func _on_net_message(msg: int) -> void:
	if _over:
		return
	if msg >= 0 and msg < NET_MESSAGES.size():
		GameEvents.hud_message_requested.emit(NET_MESSAGES[msg], MSG_S)
	elif Dog.MESSAGES.has(msg):
		GameEvents.hud_message_requested.emit(String(Dog.MESSAGES[msg]), MSG_S)


# --- Bait ----------------------------------------------------------------------------------------

## Solo and network host: the bait that attracts boars. On the host every client hears it (EV_BAIT).
func _place_bait(at: Vector3) -> void:
	var effect: Dictionary = Data.get_equipment(Ids.I_CORN_BAIT).get("effect", {})
	var bait: Bait = _spawn_bait(at, float(effect.get("duration_s", 45.0)))
	if _host_sync != null:
		_host_sync.queue_bait(bait.global_position, bait.duration_s)


## Network host: a client's C_BAIT (HuntHostSync).
func place_bait(at: Vector3) -> void:
	if not _over and _ready_flag:
		_place_bait(at)


func _spawn_bait(at: Vector3, duration_s: float) -> Bait:
	var effect: Dictionary = Data.get_equipment(Ids.I_CORN_BAIT).get("effect", {})
	var p: Vector2 = Steering.clamp_to_rect(Vector2(at.x, at.z), _map_rect, Boar.MAP_MARGIN_M)
	var bait: Bait = Bait.new()
	bait.name = "Bait_%d" % _baits.size()
	_baits_root.add_child(bait)
	bait.setup(Vector3(p.x, get_height(p.x, p.y), p.y), duration_s,
		float(effect.get("attract_radius_m", 80.0)), int(effect.get("max_boars", 4)))
	bait.expired.connect(_on_bait_expired)
	_baits.append(bait)
	Sfx.play_3d(&"bait_drop", bait.global_position)
	GameEvents.bait_placed.emit(bait.global_position, bait.duration_s)
	return bait


## Client: the bait shows at once (visual only, the host's copy attracts the boars) and goes as C_BAIT.
func _client_bait(at: Vector3) -> void:
	var effect: Dictionary = Data.get_equipment(Ids.I_CORN_BAIT).get("effect", {})
	var bait: Bait = _spawn_bait(at, float(effect.get("duration_s", 45.0)))
	if _replica == null or _replica.is_suspended():
		return   # reconnecting: no C_BAIT goes out, so no echo will ever come for this one
	_pending_baits.append(bait.get_xz())
	_replica.queue_bait_claim(bait.global_position)


## Client: EV_BAIT. The echo of this machine's own bait is skipped; anybody else's appears here.
func _on_bait_received(at: Vector3, duration_s: float) -> void:
	if _over:
		return
	var xz: Vector2 = Vector2(at.x, at.z)
	# Rejoin replay: every local bait was released, so nothing here is an echo (section 4.7.6).
	if _replica == null or not _replica.is_replaying():
		for i: int in _pending_baits.size():
			if _pending_baits[i].distance_to(xz) <= BAIT_MATCH_M:
				_pending_baits.remove_at(i)
				return
	_spawn_bait(at, duration_s)


## Client, rejoin: every bait shown here goes away; the host's active ones come back in the replay.
func _release_baits() -> void:
	for bait: Bait in _baits:
		if is_instance_valid(bait):
			if bait.get_parent() != null:
				bait.get_parent().remove_child(bait)
			bait.queue_free()
	_baits.clear()


func get_baits() -> Array[Bait]:
	return _baits


func _on_bait_expired(bait: Bait) -> void:
	_baits.erase(bait)


## An active bait within reach with a free slot; reserves the slot for the boar. Null if none.
func find_bait(from: Vector2, boar_id: int) -> Bait:
	for bait: Bait in _baits:
		if bait.active and from.distance_to(bait.get_xz()) <= bait.attract_radius_m and bait.try_reserve(boar_id):
			return bait
	return null


# --- Dogs (docs/multiplayer.md section 6.5) -------------------------------------------------------

## Breed of each slot that brought a dog: slot -> dog id. Offline: the local request. Network: the roster
## (Net fills NetPeerInfo.dog_id from the lobby records); this machine's own request wins for its own slot.
func _dog_breeds() -> Dictionary:
	var out: Dictionary = {}
	if _net_role != Net.Role.OFFLINE:
		for info: NetPeerInfo in _roster():
			if info.dog_id != &"":
				out[info.slot] = info.dog_id
	if _request != null and _request.dog_id != &"":
		out[_local_slot] = _request.dog_id
	return out


## Offline and host: one simulated Dog per hunter with a dog, beside its owner.
func _create_dogs() -> void:
	var dog_scene: PackedScene = load(ScenePaths.DOG) as PackedScene
	var breeds: Dictionary = _dog_breeds()
	for slot: int in breeds:
		var owner_hunter: PlayerBase = get_hunter(slot)
		var dog_node: Node = dog_scene.instantiate() if dog_scene != null else null
		var dog: Dog = dog_node as Dog
		if dog == null or owner_hunter == null:
			push_error("HuntController: no Dog for slot %d (%s)" % [slot, ScenePaths.DOG])
			if dog_node != null:
				dog_node.free()
			continue
		dog.name = "Dog" if slot == _local_slot else "Dog_%d" % slot
		add_child(dog)
		dog.setup(breeds[slot] as StringName, self,
			owner_hunter.global_position + owner_hunter.global_transform.basis.x * DOG_SIDE_OFFSET_M, slot)
		_dogs[slot] = dog
		_dog_list.append(dog)
	_dog = _dogs.get(_local_slot) as Dog


## Host (and offline): every simulated dog.
func get_dogs() -> Array[Dog]:
	return _dog_list


func get_dog_of(for_slot: int) -> Dog:
	return _dogs.get(for_slot) as Dog


## The owner left the hunt: its dog goes too (host: simulated Dog; client: puppet).
func _remove_dog(for_slot: int) -> void:
	var dog: Dog = _dogs.get(for_slot) as Dog
	if dog != null:
		_dogs.erase(for_slot)
		_dog_list.erase(dog)
		if _dog == dog:
			_dog = null
		dog.leave()
	if _replica != null:
		_replica.remove_dog(for_slot)


## Dog -> host sync (no-ops offline and on a client): command executed, boar marked, HUD message for a remote owner.
func report_dog_command(owner_slot: int, cmd: StringName) -> void:
	if _host_sync != null:
		_host_sync.queue_dog_command(owner_slot, cmd)


func report_dog_mark(owner_slot: int, boar_id: int, duration_s: float) -> void:
	if _host_sync != null:
		_host_sync.queue_dog_mark(owner_slot, boar_id, duration_s)


func report_dog_message(owner_slot: int, code: int) -> void:
	if _host_sync != null:
		_host_sync.queue_message(owner_slot, code)


## Client: EV_DOG_MARK. The mark helps the whole team: it shows on the minimap/compass of every machine.
func _on_dog_mark(boar_id: int, duration_s: float) -> void:
	if _over:
		return
	mark_boar(boar_id, duration_s)
	var at: Vector3 = get_boar_position(boar_id)
	if at.is_finite():
		GameEvents.dog_marked_boar.emit(at, duration_s)


# --- Dog marks -----------------------------------------------------------------------------------

func mark_boar(boar_id: int, duration_s: float) -> void:
	_marks[boar_id] = _elapsed + duration_s


# --- Horde (docs/horda.md section 5) --------------------------------------------------------------

## Every role, end of the props step: the barn is the objective and gets the corn stock visual. False (and the
## hunt ends ABANDONED) if the map has no such prop.
func _build_objective() -> bool:
	var prop_id: StringName = StringName(str(_horde.get("objective_prop_id", "")))
	var spawn: PropSpawn = _map.find_prop_spawn(prop_id)
	if spawn == null:
		push_error("HuntController: horde objective prop '%s' not found in the map" % prop_id)
		_ready_flag = true
		_loading.visible = false
		_finish(HuntResult.Outcome.ABANDONED)
		return false
	var at: Vector3 = spawn.global_position
	at.y = get_height(at.x, at.z)
	_objective = at
	var node: Node = AssetLoader.instantiate(ScenePaths.BARN_CORN)
	_stock_visual = node as CornStockVisualBase
	if _stock_visual == null:
		if node != null:
			push_warning("HuntController: %s is not a CornStockVisualBase; using the fallback" % ScenePaths.BARN_CORN)
			node.free()
		_stock_visual = CornStockVisualBase.create_fallback()
	_stock_visual.setup(_eat_ring_m)
	_stock_visual.name = "BarnCorn"
	add_child(_stock_visual)
	_stock_visual.global_position = _objective
	_stock_visual.rotation.y = spawn.global_rotation.y
	_stock_visual.set_stock_pct(100.0)
	GameEvents.crop_health_changed.connect(_on_stock_changed)
	GameEvents.crop_under_attack.connect(_on_stock_attack)
	_build_horde_level(spawn)
	return true


## request.horde_level within 1..Data.get_horde_level_count() (warning if it was outside). 0 if there is no level.
func _resolve_horde_level() -> int:
	var count: int = Data.get_horde_level_count()
	if count <= 0:
		return 0
	var level: int = clampi(_request.horde_level, 1, count)
	if level != _request.horde_level:
		push_warning("HuntController: horde level %d outside 1..%d; playing level %d" % [_request.horde_level, count, level])
	return level


## Every role, right after the objective (docs/plano_horda_nivel2.md sections 4.2-4.6): the boars' route
## obstacles, the hunter bounds and the ammo crates of the level.
func _build_horde_level(barn: PropSpawn) -> void:
	horde_route_obstacles = _map.get_horde_route_obstacles(_horde.get("route_avoid_crops", []) as Array,
		float(_horde.get("route_crop_margin_m", 0.0)), float(_horde.get("route_corner_out_m", 0.0)))
	var confine: Dictionary = _horde.get("confine", {})
	if bool(confine.get("enabled", false)):
		_player_bounds = _map.get_farm_rect().grow(-float(confine.get("inset_m", 0.0)))
	var crates: Dictionary = _horde.get("ammo_crates", {})
	if not (crates.get("positions", []) as Array).is_empty():
		_ammo_crates = HordeAmmoCrates.new()
		_ammo_crates.name = "AmmoCrates"
		add_child(_ammo_crates)
		_ammo_crates.setup(self, barn.global_transform, crates, _net_role != Net.Role.CLIENT)


func _on_stock_changed(pct: float) -> void:
	if is_instance_valid(_stock_visual):
		_stock_visual.set_stock_pct(pct)


func _on_stock_attack(on: bool) -> void:
	if is_instance_valid(_stock_visual):
		_stock_visual.set_under_attack(on)


## Where boar `boar_id` eats: its own spot (golden angle) on the ring around the barn, inside the map margin.
func get_horde_eat_point(boar_id: int) -> Vector2:
	var a: float = float(boar_id) * 2.3999632
	var p: Vector2 = Vector2(_objective.x, _objective.z) + Vector2(sin(a), -cos(a)) * _eat_ring_m
	return Steering.clamp_to_rect(p, _map_rect, Boar.MAP_MARGIN_M)


## Offline and host: the director's phase changes go to the bus (only emitter) and, on the host, to the clients.
func _on_director_wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float) -> void:
	if _host_sync != null:
		_host_sync.queue_horde_wave(wave, wave_count, phase, countdown_s, _director.get_wave_total(), _director.get_killed_before())
	GameEvents.horde_wave_changed.emit(wave, wave_count, phase, countdown_s)


func _on_director_wave_progress(remaining: int, wave_total: int) -> void:
	GameEvents.horde_wave_progress.emit(remaining, wave_total)


## Client: EV_HORDE_WAVE (live or replayed by a full sync). The countdown restarts from the host's value.
func _on_horde_wave_received(wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int,
		killed_before: int) -> void:
	if _over:
		return
	_hw_wave = wave
	_hw_count = wave_count
	_hw_phase = phase
	_hw_countdown = countdown_s if phase == Ids.HP_INTERMISSION else 0.0
	_hw_total = wave_total
	_hw_killed_before = killed_before
	_result.horde_wave_count = wave_count
	GameEvents.horde_wave_changed.emit(wave, wave_count, phase, _hw_countdown)
	if phase == Ids.HP_WAVE:
		GameEvents.horde_wave_progress.emit(_client_wave_remaining(), wave_total)


func _client_wave_remaining() -> int:
	return clampi(_hw_total - (_net_killed - _hw_killed_before), 0, _hw_total)


## D7: dead boars (host) or dead puppets (client) past horde.max_carcasses are hidden, oldest first. Nothing is
## freed, so every id stays valid.
func _add_carcass(body: Node3D) -> void:
	if body == null or not is_instance_valid(body) or _carcasses.has(body):
		return
	_carcasses.append(body)
	var hide_at: int = _carcasses.size() - 1 - _max_carcasses
	if hide_at >= 0 and is_instance_valid(_carcasses[hide_at]):
		_carcasses[hide_at].visible = false


func get_mode() -> StringName:
	return _request.mode if _request != null else Ids.MODE_CONTRACT


func get_objective_position() -> Vector3:
	return _objective if is_horde() else Vector3.INF


func get_horde_wave() -> int:
	if not is_horde():
		return 0
	return _director.get_wave() if _director != null else _hw_wave


func get_horde_wave_count() -> int:
	if not is_horde():
		return 0
	return _director.get_wave_count() if _director != null else _hw_count


func get_horde_phase() -> StringName:
	if not is_horde():
		return &""
	return _director.get_phase() if _director != null else _hw_phase


func get_horde_countdown_s() -> float:
	if not is_horde():
		return 0.0
	if _director != null:
		return _director.get_countdown_s()
	return _hw_countdown if _hw_phase == Ids.HP_INTERMISSION else 0.0


func get_horde_wave_total() -> int:
	if not is_horde():
		return 0
	return _director.get_wave_total() if _director != null else _hw_total


func get_horde_wave_remaining() -> int:
	if not is_horde():
		return 0
	if _director != null:
		return _director.get_wave_remaining()
	return _client_wave_remaining() if _hw_phase == Ids.HP_WAVE else 0


func get_horde_waves_cleared() -> int:
	if not is_horde():
		return 0
	if _director != null:
		return _director.get_waves_cleared()
	if _over and _result != null and _result.outcome == HuntResult.Outcome.VICTORY:
		return _hw_count
	return maxi(_hw_wave - 1, 0)


func get_horde_level() -> int:
	return _horde_level if is_horde() else 0


func get_player_bounds() -> Rect2:
	return _player_bounds if is_horde() else Rect2()


func get_ammo_crate_positions() -> PackedVector3Array:
	return _ammo_crates.get_available_positions() if _ammo_crates != null else PackedVector3Array()


## Nearest available crate within pickup_radius_m (XZ) of at; -1 = none or no crates (Player.get_ammo_crate_target).
func get_ammo_crate_in_reach(at: Vector3) -> int:
	return _ammo_crates.get_in_reach(at) if _ammo_crates != null else -1


## The local hunter pressed interact at that crate (owner's Q4: crates are taken with a button). Offline / host take
## it now; a client sends C_AMMO_CRATE and the host decides as before.
func request_ammo_crate(crate: int) -> void:
	if _over or not _ready_flag or _ammo_crates == null:
		return
	_ammo_crates.take_local(crate)


## The ammo crates node (horde levels with crates); null otherwise. Tests.
func debug_ammo_crates() -> HordeAmmoCrates:
	return _ammo_crates


# --- Horde revive (docs/plano_horda_nivel2.md sections 4.7 and 4.8) ------------------------------

## The local hunter finished holding interact next to target_slot. Offline: nothing (nobody to revive);
## host: decided here; client: C_REVIVE to the host.
func request_revive(target_slot: int) -> void:
	if not is_horde() or _over or not _ready_flag:
		return
	if _net_role == Net.Role.HOST:
		_host_revive(target_slot, _local_slot)
	elif _net_role == Net.Role.CLIENT and _replica != null:
		_replica.queue_revive_claim(target_slot)


## Host: a client's C_REVIVE (HuntHostSync).
func claim_revive(by_slot: int, target_slot: int) -> void:
	if not _over and _ready_flag:
		_host_revive(target_slot, by_slot)


## Host: target stands up if the level allows revives, it is down, the reviver is alive and both are within
## radius_m + claim_tolerance_m (last known positions). Otherwise ignored. True if accepted.
func _host_revive(target_slot: int, by_slot: int) -> bool:
	var rv: Dictionary = _horde.get("revive", {})
	var target: PlayerBase = get_hunter(target_slot)
	var by: PlayerBase = get_hunter(by_slot)
	var ok: bool = is_horde() and bool(rv.get("enabled", false)) and target_slot != by_slot \
		and target != null and is_instance_valid(target) and by != null and is_instance_valid(by) \
		and target.is_downed() and by.is_alive()
	if ok:
		var d: float = Vector2(target.global_position.x - by.global_position.x, target.global_position.z - by.global_position.z).length()
		ok = d <= float(rv.get("radius_m", 0.0)) + float(rv.get("claim_tolerance_m", 0.0))
	if not ok:
		revives_rejected += 1
		return false
	revives_accepted += 1
	if target_slot == _local_slot:
		_player.revive(float(rv.get("health", 0.0)))
	if _host_sync != null:
		_host_sync.queue_hunter_revived(target_slot, by_slot)
	GameEvents.hunter_revived.emit(target_slot, by_slot)
	return true


## Client: EV_HUNTER_REVIVED. This machine's hunter stands up if it is the target (no-op unless still down).
func _on_hunter_revived_received(target_slot: int, by_slot: int) -> void:
	if _over:
		return
	if target_slot == _local_slot and _player != null and is_instance_valid(_player):
		_player.revive(float(_horde.get("revive", {}).get("health", 0.0)))
	GameEvents.hunter_revived.emit(target_slot, by_slot)


# --- Horde ammo crates (docs/plano_horda_nivel2.md sections 4.6 and 4.8) -------------------------

## Host: a client's C_AMMO_CRATE (HuntHostSync).
func claim_ammo_crate(by_slot: int, crate: int) -> void:
	if _over or not _ready_flag or _ammo_crates == null:
		return
	if _ammo_crates.host_claim(by_slot, crate):
		ammo_claims_accepted += 1
	else:
		ammo_claims_rejected += 1


## HordeAmmoCrates (offline / host): a crate was taken or came back. The host tells every client.
func report_ammo_crate(crate: int, available: bool, taker_slot: int) -> void:
	if _host_sync != null:
		_host_sync.queue_ammo_crate(crate, available, taker_slot)


## HordeAmmoCrates (client): the local hunter pressed interact at an available crate.
func send_ammo_crate_claim(crate: int) -> void:
	if _replica != null and not _over:
		_replica.queue_ammo_crate_claim(crate)


## Client: EV_AMMO_CRATE (live or replayed by a full sync).
func _on_ammo_crate_received(crate: int, available: bool, taker_slot: int) -> void:
	if not _over and _ammo_crates != null:
		_ammo_crates.apply_remote(crate, available, taker_slot)


func debug_horde_start_next_wave() -> void:
	if _director != null and _net_role != Net.Role.CLIENT:
		_director.skip_intermission()


# --- HuntWorld -----------------------------------------------------------------------------------

func is_world_ready() -> bool:
	return _ready_flag


func get_map_id() -> StringName:
	return _request.map_id if _request != null else &""


func get_contract_index() -> int:
	return _request.contract_index if _request != null else 0


func get_map_rect() -> Rect2:
	return _map_rect


func get_minimap_texture() -> Texture2D:
	return _map.get_minimap_texture() if _map != null else null


func get_height(x: float, z: float) -> float:
	return heightmap.get_height(x, z) if heightmap != null else 0.0


func get_normal(x: float, z: float) -> Vector3:
	return heightmap.get_normal(x, z) if heightmap != null else Vector3.UP


func get_crop_rects() -> Array[Rect2]:
	if crop == null:
		return []
	return crop.get_rects()


func get_crop_health_pct() -> float:
	if _net_role == Net.Role.CLIENT:
		return crop.get_health_pct() if crop != null else _net_crop_pct
	return crop.get_health_pct() if crop != null else 100.0


func get_boars_total() -> int:
	return spawner.get_total() if spawner != null else _net_total


func get_boars_killed() -> int:
	return _net_killed if _net_role == Net.Role.CLIENT else _killed


func get_alive_boar_ids() -> PackedInt32Array:
	if _replica != null:
		return _replica.get_alive_ids()
	return spawner.get_alive_ids() if spawner != null else PackedInt32Array()


func get_boar_position(boar_id: int) -> Vector3:
	if _replica != null:
		return _replica.get_boar_position(boar_id)
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	return b.global_position if b != null else Vector3.INF


func get_boar_type(boar_id: int) -> StringName:
	if _replica != null:
		return _replica.get_boar_type(boar_id)
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	return b.type_id if b != null else &""


func get_boar_zone_position(boar_id: int, zone: StringName) -> Vector3:
	if _replica != null:
		return _replica.get_boar_zone_position(boar_id, zone)
	var b: Boar = spawner.get_boar(boar_id) if spawner != null else null
	return b.get_zone_position(zone) if b != null else Vector3.INF


func get_nearest_boar_position(from: Vector3) -> Vector3:
	if _replica != null:
		return _replica.get_nearest_boar_position(from)
	var b: Boar = spawner.find_nearest_alive(Vector2(from.x, from.z)) if spawner != null else null
	return b.global_position if b != null else Vector3.INF


func get_marked_boar_positions() -> PackedVector3Array:
	_marked_out.clear()
	for id: int in _marks.keys():
		if float(_marks[id]) < _elapsed:
			_marks.erase(id)
			continue
		if _replica != null:
			var puppet: BoarPuppet = _replica.get_puppet(id)
			if puppet != null and puppet.alive and puppet.is_inside_tree():
				_marked_out.append(puppet.global_position)
			continue
		var b: Boar = spawner.get_boar(id) if spawner != null else null
		if b != null and b.is_alive():
			_marked_out.append(b.global_position)
	return _marked_out


## The dog of the hunter of this machine: the simulated Dog (offline, host) or its puppet (client).
func has_dog() -> bool:
	return _dog != null or _local_dog_puppet() != null


func get_dog_position() -> Vector3:
	if _dog != null:
		return _dog.global_position
	var puppet: DogPuppet = _local_dog_puppet()
	return puppet.global_position if puppet != null else Vector3.INF


func get_dog_state() -> StringName:
	if _dog != null:
		return _dog.state
	var puppet: DogPuppet = _local_dog_puppet()
	return puppet.state if puppet != null else &""


func get_dog_health_pct() -> float:
	if _dog != null:
		return _dog.get_health_pct()
	var puppet: DogPuppet = _local_dog_puppet()
	return puppet.get_health_pct() if puppet != null else 0.0


## A network client has only the puppet, which knows no target: INF there (docs §8.10).
func get_dog_target_position() -> Vector3:
	return _dog.get_target_position() if _dog != null else Vector3.INF


func _local_dog_puppet() -> DogPuppet:
	return _replica.get_local_dog() if _replica != null else null


func get_player() -> PlayerBase:
	return _player


func get_hunters() -> Array[PlayerBase]:
	return _hunters_list


func get_hunter(for_slot: int) -> PlayerBase:
	if for_slot == _local_slot:
		return _player
	return _remotes.get(for_slot) as PlayerBase


func get_local_slot() -> int:
	return _local_slot


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
	if crop != null and _net_role != Net.Role.CLIENT:
		crop.set_health(pct)


func debug_force_end(outcome: HuntResult.Outcome) -> void:
	if _ready_flag and _net_role != Net.Role.CLIENT:
		_finish(outcome)


## Test hooks (package B sandboxes): the result being built, before the hunt ends; the network helpers.
func debug_partial_result() -> HuntResult:
	return _result


func debug_host_sync() -> HuntHostSync:
	return _host_sync


func debug_replica() -> HuntReplica:
	return _replica


## The scoreboard as it stands (slot tally of every kill seen here), before the hunt ends.
func debug_scoreboard() -> Array[Dictionary]:
	return _build_scoreboard()


# --- Net seam (section 3.6). F2: hunters only; boars, dogs, events and claims arrive in later phases -----

## Host: body of H_SNAPSHOT. Hunters whose net_write_state does not write exactly HUNTER_STATE_BYTES are
## skipped, so a hunter implementation that writes nothing cannot corrupt the frame.
func net_write_snapshot(out: StreamPeerBuffer) -> void:
	var count: int = 0
	_snap_hunters.clear()
	for h: PlayerBase in _hunters_list:
		_snap_scratch.clear()
		h.net_write_state(_snap_scratch)
		if _snap_scratch.get_size() != NetCodec.HUNTER_STATE_BYTES:
			continue
		var state: PackedByteArray = _snap_scratch.data_array
		_snap_hunters.put_u8(h.slot)
		_snap_hunters.put_data(state)
		count += 1
		_note_away(h.slot, state[HUNTER_FLAGS_OFFSET])
	out.put_u32(net_time_ms() & 0xFFFFFFFF)
	out.put_u16(clampi(roundi(get_crop_health_pct() * CROP_WIRE_SCALE), 0, 65535))
	out.put_u8(mini(_killed, 255))
	out.put_u8(mini(get_boars_total(), 255))
	out.put_u8(SNAP_FLAG_CROP_ATTACK if crop != null and crop.get_eater_count() > 0 else 0)
	out.put_u8(count)
	if count > 0:
		out.put_data(_snap_hunters.data_array)
	if _host_sync != null:
		_host_sync.write_boars(out)
	else:
		out.put_u8(0)           # n_boars
	if _host_sync != null:
		_host_sync.write_dogs(out)
	else:
		out.put_u8(0)           # n_dogs


## Client: moves the remote hunters, the boar puppets and the dog puppets.
## Team kills come from EV_BOAR_DEATH only (so boar_killed always precedes its count); the total also
## comes from here.
func net_apply_snapshot(inp: StreamPeerBuffer) -> void:
	if _net_role != Net.Role.CLIENT or inp.get_available_bytes() < SNAPSHOT_HEADER_BYTES:
		return
	_net_t_ms = inp.get_u32()
	var crop_pct: float = float(inp.get_u16()) / CROP_WIRE_SCALE
	inp.get_u8()                # killed: from EV_BOAR_DEATH
	var total: int = inp.get_u8()
	var flags: int = inp.get_u8()
	var n_hunters: int = inp.get_u8()
	if not _over:
		# The crop mirror emits crop_health_changed with the solo step and crop_under_attack on change.
		_net_crop_pct = crop_pct
		if _replica != null:
			_replica.apply_crop_state(crop_pct, flags)
	if total != _net_total and not _over:
		_net_total = total
		GameEvents.boar_counts_changed.emit(_net_killed, total)
	var record_bytes: int = 1 + NetCodec.HUNTER_STATE_BYTES
	var raw: PackedByteArray = inp.data_array
	for i: int in n_hunters:
		if inp.get_available_bytes() < record_bytes:
			return
		var from_slot: int = inp.get_u8()
		var start: int = inp.get_position()
		var h: PlayerBase = _remotes.get(from_slot) as PlayerBase
		if from_slot != _local_slot and h != null:
			h.net_apply_state(inp)
			_note_away(from_slot, raw[start + HUNTER_FLAGS_OFFSET])
		inp.seek(start + NetCodec.HUNTER_STATE_BYTES)
	if inp.get_available_bytes() >= 1:
		var boars_at: int = inp.get_position()
		var n_boars: int = inp.data_array[boars_at]
		if _replica != null:
			_replica.apply_snapshot_boars(inp, _net_t_ms)
		inp.seek(mini(boars_at + 1 + n_boars * SNAPSHOT_BOAR_BYTES, inp.get_size()))
	if inp.get_available_bytes() >= 1:
		var dogs_at: int = inp.get_position()
		var n_dogs: int = inp.data_array[dogs_at]
		if _replica != null:
			_replica.apply_snapshot_dogs(inp, _net_t_ms)
		inp.seek(mini(dogs_at + 1 + n_dogs * SNAPSHOT_DOG_BYTES, inp.get_size()))


## Session clock of the host (ms since the hunt was released): t_ms of H_SNAPSHOT and of EV_FULL_SYNC.
func net_time_ms() -> int:
	return int(maxf(_elapsed - _go_elapsed, 0.0) * 1000.0)


## hunter_away_changed(slot, away) when the HF_AWAY bit of a remote's snapshot record changes (section 4.7.7).
## Same source on both ends: the host reads what it has just written, the client what it has just received.
## Never for the local slot, after the end of the hunt or for a hunter that already left.
func _note_away(for_slot: int, flags: int) -> void:
	if for_slot == _local_slot or _over or not _remotes.has(for_slot):
		return
	var away: bool = (flags & NetCodec.HF_AWAY) != 0
	if away == _away_slots.has(for_slot):
		return
	if away:
		_away_slots[for_slot] = true
	else:
		_away_slots.erase(for_slot)
	GameEvents.hunter_away_changed.emit(for_slot, away)


## Client: this machine lost the host and is trying to come back (section 4.7.7). The replica stops judging
## charges and claiming; baits waiting for their echo will never get it (the claim is not resent). Everything
## resumes at the end of the EV_FULL_SYNC replay, not here.
func _on_net_reconnect_changed(active: bool) -> void:
	if not active or _over or _replica == null:
		return
	_replica.suspend()
	_pending_baits.clear()


## Client, EV_FULL_SYNC header (section 4.7.6, step 2): local baits go, the crop takes the host's health. The
## replayed records that follow rebuild kills, eaten patches, active baits and marks through the usual handlers.
func _on_full_sync_started(crop_pct: float) -> void:
	if _over:
		return
	_release_baits()
	_pending_baits.clear()
	_net_crop_pct = crop_pct
	if crop != null:
		crop.set_replicated_health(crop_pct)


## Client, after the last replayed record (step 4): the header's counts win if the replay left others.
func _on_full_sync_finished(killed: int, total: int) -> void:
	if _over or (killed == _net_killed and total == _net_total):
		return
	push_warning("HuntController: full sync counts %d/%d differ from the replay %d/%d" % [killed, total, _net_killed, _net_total])
	_net_killed = killed
	_net_total = total
	GameEvents.boar_counts_changed.emit(killed, total)


## Host (section 4.7.6): EV_FULL_SYNC for the client that came back, then the replay: spawn/death journal and
## eaten patches (HuntHostSync), one EV_BAIT per active bait, one EV_DOG_MARK per live mark and, if the hunt
## already ended here, the EV_HUNT_END that was sent. The session drains net_take_events to the other links
## first, so the cut is consistent.
func net_write_full_sync(out: StreamPeerBuffer) -> void:
	if _host_sync == null or not _ready_flag:
		return
	var sync_at: int = out.get_position()
	var records: int = _host_sync.write_full_sync(out)
	for bait: Bait in _baits:
		if is_instance_valid(bait) and bait.active and bait.remaining_s > 0.0:
			_host_sync.write_bait_replay(out, bait.global_position, bait.remaining_s)
			records += 1
	for id: int in _marks:
		var left_s: float = float(_marks[id]) - _elapsed
		var b: Boar = spawner.get_boar(id) if spawner != null else null
		if left_s > 0.0 and b != null and b.is_alive():
			_host_sync.write_mark_replay(out, id, left_s)
			records += 1
	if _director != null and _director.get_wave() >= 1:
		# Horde (docs/horda.md section 9.3): the wave state as it is now, countdown = time left.
		_host_sync.write_horde_wave_replay(out, _director.get_wave(), _director.get_wave_count(), _director.get_phase(),
			_director.get_countdown_s(), _director.get_wave_total(), _director.get_killed_before())
		records += 1
	if _ammo_crates != null:
		# Horde level 2 (docs/plano_horda_nivel2.md section 4.8): every crate's state, taker 255.
		for i: int in _ammo_crates.get_count():
			_host_sync.write_ammo_crate_replay(out, i, _ammo_crates.is_available(i))
			records += 1
	if _over:
		records += _host_sync.write_hunt_end_replay(out)
	_host_sync.set_full_sync_count(out, sync_at, records)


## Host: EV_* records queued since the last tick.
func net_take_events(out: StreamPeerBuffer) -> void:
	if _host_sync != null:
		_host_sync.take_events(out)


## Client: one EV_* record from the host.
func net_apply_event(type: int, inp: StreamPeerBuffer, length: int) -> void:
	if _replica != null:
		_replica.apply_event(type, inp, length)


## Client: C_* records queued since the last tick.
func net_take_claims(out: StreamPeerBuffer) -> void:
	if _replica != null:
		_replica.take_claims(out)


## Host: one C_* record from the client in `from_slot`.
func net_apply_claim(from_slot: int, type: int, inp: StreamPeerBuffer, length: int) -> void:
	if _host_sync != null and not _over:
		_host_sync.apply_claim(from_slot, type, inp, length)


func net_peer_left(for_slot: int) -> void:
	var h: PlayerBase = _remotes.get(for_slot) as PlayerBase
	if h == null:
		return
	_remove_dog(for_slot)
	_remotes.erase(for_slot)
	_away_slots.erase(for_slot)   # no hunter_away_changed for a hunter that left
	_downed_slots.erase(for_slot)
	_hunters_list.erase(h)
	h.queue_free()
	GameEvents.hunter_left.emit(for_slot)


## Client: the host is gone (host_left or net.host_timeout_s, decided by Net) -> DISCONNECTED: own kills
## paid, consumables spent, no bonus, no progression (section 6.9). Host: every remote leaves and the hunt
## goes on alone.
func net_connection_lost() -> void:
	_conn_lost = true
	if _net_role == Net.Role.CLIENT:
		if _ready_flag:
			_finish(HuntResult.Outcome.DISCONNECTED)
		return
	for for_slot: int in _remotes.keys():
		net_peer_left(for_slot)
	if not _over and _ready_flag:
		GameEvents.hud_message_requested.emit(MSG_HOST_ALONE, MSG_S)
	if _assembled and not _go:
		_begin_net_hunt()   # nobody else will send hunt_go


## Test hook: same as Net.hunt_go (only meaningful with test_net_role).
func debug_net_go() -> void:
	_on_net_go()
