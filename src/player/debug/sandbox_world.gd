class_name SandboxWorld
extends HuntWorld
## Package A sandbox: flat 200x200 ground (layer 1), three shootable targets with HitZones and a
## kill counter. Stands in for the hunt so the player, weapons and HUD run without Package B.
## Command line (after "--"): --touch=on|off, --weapons=a,b, --items=a,b, --aim, --demo, --horde, --dog,
## --dog_state=<Ids.DS_*>, --dog_hp=<0-100>, --dog_breed=<Ids.D_*>, --onboarding (or --hunts=N: throwaway profile that
## has played N hunts, so the first-hunts HUD shows)
## Map markers (docs §8.4): --minimap_tex (test image as the minimap texture), --marked (target 0 is a marked boar),
## --bait (a bait at (-30, -40)), --reveal (the drone reveals every alive target), --heading=<deg> (compass heading),
## --crop_alert (forces the "Javalis na lavoura!" alert and a context message at the same time)
## Weapon panel and health bar (docs §8.4): --hp=<1-100> (health in percent), --slot=<1-5> (weapon in hand),
## --mag=<n> (rounds in the magazine of the weapon in hand, to see the low-ammo colour)
## --horde (or horde_mode = true before add_child): horde request, fake barn objective and a simple wave loop over the
## three targets (intermission, wave, intermission...). horde_auto = false leaves the wave state to the caller.
## Horde level (docs/plano_horda_nivel2.md): --horde_level=N (or horde_level = N before add_child; default 1) picks the
## rules of Data.get_horde_level(N) for the Player (counted ammo, revive, confinement). Tests may also set player_bounds,
## ammo_crate_positions and extra_hunters (fake allies) and read revive_requests (slots passed to request_revive) and
## ammo_crate_requests (crates passed to request_ammo_crate; the sandbox takes nothing, the reach is the level's
## ammo_crates.pickup_radius_m).

const GROUND_SIZE_M: float = 200.0
const TARGET_DISTANCES_M: Array[float] = [10.0, 30.0, 60.0]
const TARGET_WEIGHT_KG: float = 100.0
const TARGET_HEALTH_PER_KG: float = 1.2
const HORDE_WAVE_COUNT: int = 3
const HORDE_FIRST_DELAY_S: float = 12.0
const HORDE_INTERMISSION_S: float = 6.0
const HORDE_OBJECTIVE: Vector3 = Vector3(0.0, 0.0, -40.0)
const SANDBOX_SAVE_PATH: String = "user://sandbox_save.json"
const DEMO_DOG_POSITION: Vector3 = Vector3(-4.0, 0.0, -6.0)
const TEST_MAP_PX: int = 100                        # --minimap_tex: 100x100 image for the 200 m ground (2 m per px)
const TEST_MAP_BG: Color = Color("#8C8C50")
const TEST_MAP_GRID: Color = Color("#6E6E3C")
const TEST_MAP_GRID_STEP_PX: int = 10
const TEST_MAP_CROP: Color = Color("#5E9A3A")
const TEST_MAP_CORNER: Color = Color("#D9452B")
const TEST_MAP_CORNER_PX: int = 6
const TEST_BAIT_POSITION: Vector3 = Vector3(-30.0, 0.0, -40.0)
const TEST_BAIT_DURATION_S: float = 600.0
const TEST_CONTEXT_TEXT: String = "Ceva colocada: os javalis vão para longe da lavoura"   # --crop_alert: context line shown with the alert
const ZONE_BOXES: Dictionary = {
	"head": [Vector3(0.0, 0.75, -0.55), Vector3(0.3, 0.3, 0.3)],
	"vital": [Vector3(0.0, 0.6, -0.2), Vector3(0.45, 0.4, 0.5)],
	"body": [Vector3(0.0, 0.5, 0.2), Vector3(0.5, 0.5, 0.6)],
	"rear": [Vector3(0.0, 0.5, 0.65), Vector3(0.45, 0.45, 0.35)],
}

var player: Player = null
var killed: int = 0
var crop_pct: float = 87.0
## Horde state (docs/horda.md section 4.2). The sandbox runs a toy wave loop; tests may set horde_auto = false and
## write these fields (and emit the signals) by hand.
var horde_mode: bool = false
var horde_auto: bool = true
var horde_wave: int = 0
var horde_wave_count: int = 0
var horde_phase: StringName = &""
var horde_countdown_s: float = 0.0
var horde_wave_total: int = 0
var horde_wave_remaining: int = 0
var horde_waves_cleared: int = 0
var horde_objective: Vector3 = HORDE_OBJECTIVE
var horde_level: int = 1
var player_bounds: Rect2 = Rect2()
var ammo_crate_positions: PackedVector3Array = PackedVector3Array()
var extra_hunters: Array[PlayerBase] = []
var revive_requests: Array[int] = []
var ammo_crate_requests: Array[int] = []
var dog_present: bool = false
var dog_state: StringName = Ids.DS_FOLLOW
## Fake dog for the HUD card, compass and minimap (INF = not placed). --dog_state=seek places the dog and
## aims it at target 1; --dog_hp=N sets its health.
var dog_position: Vector3 = Vector3.INF
var dog_target_position: Vector3 = Vector3.INF
var dog_health_pct: float = 100.0
var kill_log: Array[KillInfo] = []
var hit_log: Array[HitInfo] = []
var _targets: Dictionary = {}     # id -> {node, health, zones, last_shot, one_shot, alive}
var _ready_flag: bool = false
var _elapsed: float = 0.0
var _multipliers: Dictionary = {}
var _args: Dictionary = {}
var _test_map: ImageTexture = null


func _ready() -> void:
	_args = _parse_args()
	if _args.has("horde"):
		horde_mode = true
	if _args.has("horde_level"):
		horde_mode = true
		horde_level = int(_args["horde_level"])
	_multipliers = Data.get_boar_rules().get("zone_multipliers", {})
	if _args.has("onboarding") or _args.has("hunts"):
		_use_throwaway_profile(int(_args.get("hunts", "0")))
	if _args.has("dog_state"):
		dog_state = StringName(String(_args["dog_state"]))
		dog_position = DEMO_DOG_POSITION
		dog_target_position = Vector3(0.0, 0.0, -TARGET_DISTANCES_M[1]) if dog_state != Ids.DS_FOLLOW else Vector3.INF
	if _args.has("dog_hp"):
		dog_health_pct = float(_args["dog_hp"])
	if _args.has("minimap_tex"):
		_test_map = _make_test_map()
	_build_ground()
	add_child(MapEnvironmentBase.create_fallback())
	_build_targets()
	_spawn_player()
	_ready_flag = true
	world_ready.emit()
	GameEvents.boar_counts_changed.emit(0, _targets.size())
	GameEvents.crop_health_changed.emit(crop_pct)
	GameEvents.hunt_started.emit(_request())
	if horde_mode and horde_auto:
		horde_wave = 1
		horde_wave_count = HORDE_WAVE_COUNT
		horde_phase = Ids.HP_INTERMISSION
		horde_countdown_s = HORDE_FIRST_DELAY_S
		GameEvents.horde_wave_changed.emit(horde_wave, horde_wave_count, horde_phase, horde_countdown_s)


## --onboarding (or --hunts=N): a fresh profile with N hunts played (default 0 = in the onboarding), in a save file of
## its own so the real save is never touched. The HUD shows the objectives, the legend and the touch labels only then.
func _use_throwaway_profile(hunts_played: int) -> void:
	Profile.set_save_path(SANDBOX_SAVE_PATH)
	Profile.reset_progress()
	for i: int in hunts_played:
		var result: HuntResult = HuntResult.new()
		result.outcome = HuntResult.Outcome.DEFEAT_DEATH
		Profile.apply_hunt_result(result)


func _process(delta: float) -> void:
	_elapsed += delta
	if horde_mode and horde_auto and horde_phase == Ids.HP_INTERMISSION:
		horde_countdown_s = maxf(horde_countdown_s - delta, 0.0)
		if horde_countdown_s <= 0.0:
			_horde_begin_wave()


func _horde_begin_wave() -> void:
	horde_phase = Ids.HP_WAVE
	horde_countdown_s = 0.0
	horde_wave_total = get_alive_boar_ids().size()
	horde_wave_remaining = horde_wave_total
	GameEvents.horde_wave_changed.emit(horde_wave, horde_wave_count, horde_phase, 0.0)
	GameEvents.horde_wave_progress.emit(horde_wave_remaining, horde_wave_total)


func _horde_after_kill() -> void:
	horde_wave_remaining = get_alive_boar_ids().size()
	GameEvents.horde_wave_progress.emit(horde_wave_remaining, horde_wave_total)
	if horde_wave_remaining > 0:
		return
	horde_waves_cleared = horde_wave
	if horde_wave < horde_wave_count:
		horde_wave += 1
		horde_phase = Ids.HP_INTERMISSION
		horde_countdown_s = HORDE_INTERMISSION_S
		GameEvents.horde_wave_changed.emit(horde_wave, horde_wave_count, horde_phase, horde_countdown_s)


func _parse_args() -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
			parsed[pair[0]] = pair[1] if pair.size() > 1 else "1"
	return parsed


func _request() -> HuntRequest:
	var r: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE if horde_mode else Ids.MODE_CONTRACT)
	r.weapon_ids = [Ids.W_CARBINE_22, Ids.W_SHOTGUN_12]
	r.item_ids = [Ids.I_BINOCULARS, Ids.I_LEATHER_VEST, Ids.I_MEDKIT, Ids.I_CORN_BAIT]
	r.item_counts = {Ids.I_MEDKIT: 2, Ids.I_CORN_BAIT: 1}
	if has_dog():
		r.dog_id = StringName(String(_args.get("dog_breed", Ids.D_CARAMELO)))   # --dog_breed=foxhound|dogo
	if _args.has("weapons"):
		r.weapon_ids.clear()
		for id: String in String(_args["weapons"]).split(",", false):
			r.weapon_ids.append(StringName(id))
	if _args.has("items"):
		r.item_ids.clear()
		r.item_counts = {}
		for id: String in String(_args["items"]).split(",", false):
			r.item_ids.append(StringName(id))
			r.item_counts[StringName(id)] = 2
	return r


func _build_ground() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE_M, 1.0, GROUND_SIZE_M)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("#C2A95A")
	plane.material = mat
	mesh_node.mesh = plane
	body.add_child(mesh_node)
	add_child(body)
	# A static prop (wall) to check the "wood" impact path.
	var wall: StaticBody3D = StaticBody3D.new()
	wall.name = "Wall"
	wall.collision_layer = Layers.STATIC
	wall.collision_mask = 0
	var wall_shape: CollisionShape3D = CollisionShape3D.new()
	var wall_box: BoxShape3D = BoxShape3D.new()
	wall_box.size = Vector3(6.0, 2.0, 0.3)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	var wall_mesh: MeshInstance3D = MeshInstance3D.new()
	var wall_box_mesh: BoxMesh = BoxMesh.new()
	wall_box_mesh.size = wall_box.size
	wall_mesh.mesh = wall_box_mesh
	wall.add_child(wall_mesh)
	wall.position = Vector3(-8.0, 1.0, -14.0)
	add_child(wall)


func _build_targets() -> void:
	for i: int in TARGET_DISTANCES_M.size():
		var root: Node3D = Node3D.new()
		root.name = "Target%d" % i
		root.position = Vector3((i - 1) * 3.0, 0.0, -TARGET_DISTANCES_M[i])
		add_child(root)
		var body_mesh: MeshInstance3D = MeshInstance3D.new()
		var cap: BoxMesh = BoxMesh.new()
		cap.size = Vector3(0.5, 0.5, 1.3)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color("#6B4A3A")
		cap.material = mat
		body_mesh.mesh = cap
		body_mesh.position = Vector3(0.0, 0.5, 0.1)
		root.add_child(body_mesh)
		var zones: Array[HitZone] = []
		for zone_name: String in ZONE_BOXES.keys():
			var zone: HitZone = HitZone.new()
			zone.name = "Hit_%s" % zone_name
			zone.zone = StringName(zone_name)
			zone.target_id = i
			var cs: CollisionShape3D = CollisionShape3D.new()
			var shape: BoxShape3D = BoxShape3D.new()
			shape.size = ZONE_BOXES[zone_name][1]
			cs.shape = shape
			zone.add_child(cs)
			zone.position = ZONE_BOXES[zone_name][0]
			root.add_child(zone)
			zone.hit_received.connect(_on_hit.bind(i))
			zones.append(zone)
		_targets[i] = {
			"node": root, "health": TARGET_WEIGHT_KG * TARGET_HEALTH_PER_KG, "zones": zones,
			"shot_ids": {}, "alive": true, "type": Ids.BOAR,
		}


func _spawn_player() -> void:
	var packed: PackedScene = load(ScenePaths.PLAYER) as PackedScene
	player = packed.instantiate() as Player
	add_child(player)
	player.global_position = Vector3.ZERO
	var req: HuntRequest = _request()
	player.setup(req, self)
	if _args.get("touch", "") != "":
		InputSetup.set_touch_override(String(_args["touch"]))
	if _args.has("hp"):
		player.debug_set_health(player.get_max_health() * float(_args["hp"]) / 100.0)
	if _args.has("slot"):
		player.bot_select_weapon(int(_args["slot"]) - 1)
	if _args.has("mag"):
		player.get_weapon().ammo_in_mag = int(_args["mag"])   # after --slot: the weapon in hand
	if _args.has("aim"):
		player.bot_set_enabled(true)
		player.bot_set_aim(true)
	if _args.has("heading"):
		player.rotation.y = deg_to_rad(-float(_args["heading"]))
	if _args.has("bait"):
		GameEvents.bait_placed.emit(TEST_BAIT_POSITION, TEST_BAIT_DURATION_S)
	if _args.has("crop_alert"):
		GameEvents.crop_under_attack.emit(true)
		GameEvents.hud_message_requested.emit(TEST_CONTEXT_TEXT, TEST_BAIT_DURATION_S)
	if _args.has("reveal"):
		GameEvents.item_used.emit(Ids.I_SCOUT_DRONE, Vector3.ZERO)
	if _args.has("demo"):
		_run_demo.call_deferred()
	if _args.has("stick"):
		_run_stick_demo.call_deferred()
	if _args.has("help_key"):
		_run_help_key.call_deferred()


## --minimap_tex: test image of the whole 200 m ground, built once. The red corner square (north-west) checks the
## orientation and the plot of get_crop_rects() checks the scale.
func _make_test_map() -> ImageTexture:
	var img: Image = Image.create(TEST_MAP_PX, TEST_MAP_PX, false, Image.FORMAT_RGB8)
	img.fill(TEST_MAP_BG)
	for i: int in TEST_MAP_PX:
		for j: int in range(0, TEST_MAP_PX, TEST_MAP_GRID_STEP_PX):
			img.set_pixel(i, j, TEST_MAP_GRID)
			img.set_pixel(j, i, TEST_MAP_GRID)
	var px_per_m: float = float(TEST_MAP_PX) / GROUND_SIZE_M
	for rect: Rect2 in get_crop_rects():
		var origin: Vector2 = (rect.position - get_map_rect().position) * px_per_m
		img.fill_rect(Rect2i(Vector2i(origin), Vector2i(rect.size * px_per_m)), TEST_MAP_CROP)
	img.fill_rect(Rect2i(0, 0, TEST_MAP_CORNER_PX, TEST_MAP_CORNER_PX), TEST_MAP_CORNER)
	return ImageTexture.create_from_image(img)


## Screenshot helper (--help_key): presses H as a real key event, so the legend folds into its "H: Ajuda" tab.
func _run_help_key() -> void:
	await get_tree().create_timer(0.5).timeout
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_H
	press.pressed = true
	Input.parse_input_event(press)


## Screenshot helper (--stick or --stick=lock): holds the fixed stick pushed, optionally past the lock ring.
func _run_stick_demo() -> void:
	await get_tree().create_timer(0.4).timeout
	var tc: TouchControls = player.find_child("TouchControls", true, false) as TouchControls
	if tc == null:
		return
	var center: Vector2 = tc.joystick.rest_center
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 1
	down.pressed = true
	down.position = center
	tc._input(down)
	var move: InputEventScreenDrag = InputEventScreenDrag.new()
	move.index = 1
	move.position = center + (Vector2(0.0, -170.0) if String(_args["stick"]) == "lock" else Vector2(55.0, -55.0))
	tc._input(move)


func _run_demo() -> void:
	# Fires a shot at the nearest target and shows a kill message so screenshots show the HUD feedback.
	await get_tree().create_timer(0.6).timeout
	player.bot_set_enabled(true)
	player.bot_look_at(get_boar_zone_position(0, Ids.ZONE_VITAL))
	player.bot_set_aim(true)
	await get_tree().create_timer(0.5).timeout
	player.bot_fire()


func _on_hit(hit: HitInfo, id: int) -> void:
	var t: Dictionary = _targets[id]
	if not t["alive"]:
		return
	hit_log.append(hit)
	var final_damage: float = hit.damage * float(_multipliers.get(String(hit.zone), 1.0))
	t["health"] = float(t["health"]) - final_damage
	(t["shot_ids"] as Dictionary)[hit.shot_id] = true
	GameEvents.boar_hit.emit(id, hit.zone, final_damage, hit.position, hit.shot_id)
	if float(t["health"]) <= 0.0:
		_kill(id, hit.zone)


func _kill(id: int, zone: StringName) -> void:
	var t: Dictionary = _targets[id]
	if not t["alive"]:
		return
	t["alive"] = false
	for z: HitZone in t["zones"]:
		z.disable()
	(t["node"] as Node3D).rotation_degrees.z = 90.0
	var kill: KillInfo = KillInfo.new()
	kill.boar_id = id
	kill.type_id = Ids.BOAR
	kill.weight_kg = TARGET_WEIGHT_KG
	kill.killing_zone = zone
	kill.one_shot = (t["shot_ids"] as Dictionary).size() == 1
	kill.clean_kill = zone in [Ids.ZONE_HEAD, Ids.ZONE_VITAL]
	kill.reward_money = int(TARGET_WEIGHT_KG * 5.0)
	kill.position = (t["node"] as Node3D).global_position
	kill.time_s = _elapsed
	kill_log.append(kill)
	killed += 1
	GameEvents.boar_state_changed.emit(id, Ids.BS_DEAD)
	GameEvents.boar_killed.emit(kill)
	GameEvents.boar_counts_changed.emit(killed, _targets.size())
	if horde_mode and horde_auto and horde_phase == Ids.HP_WAVE:
		_horde_after_kill()


# --- HuntWorld overrides ---
## --dog fakes a dog that follows (Quickbar / touch dog slot); tests may also set dog_present / dog_state.
func has_dog() -> bool:
	return dog_present or _args.has("dog")


func get_dog_state() -> StringName:
	return dog_state


func get_dog_position() -> Vector3:
	return dog_position


func get_dog_health_pct() -> float:
	return dog_health_pct


func get_dog_target_position() -> Vector3:
	return dog_target_position


func get_minimap_texture() -> Texture2D:
	return _test_map


func get_marked_boar_positions() -> PackedVector3Array:
	if _args.has("marked") and _targets.has(0) and _targets[0]["alive"]:
		return PackedVector3Array([get_boar_position(0)])
	return PackedVector3Array()


func get_mode() -> StringName:
	return Ids.MODE_HORDE if horde_mode else Ids.MODE_CONTRACT


func get_objective_position() -> Vector3:
	return horde_objective if horde_mode else Vector3.INF


func get_horde_wave() -> int:
	return horde_wave


func get_horde_wave_count() -> int:
	return horde_wave_count


func get_horde_phase() -> StringName:
	return horde_phase


func get_horde_countdown_s() -> float:
	return horde_countdown_s


func get_horde_wave_total() -> int:
	return horde_wave_total


func get_horde_wave_remaining() -> int:
	return horde_wave_remaining


func get_horde_waves_cleared() -> int:
	return horde_waves_cleared


func get_horde_level() -> int:
	return horde_level if horde_mode else 0


func get_player_bounds() -> Rect2:
	return player_bounds


func request_revive(target_slot: int) -> void:
	revive_requests.append(target_slot)


func get_ammo_crate_positions() -> PackedVector3Array:
	return ammo_crate_positions


func get_ammo_crate_in_reach(at: Vector3) -> int:
	if not horde_mode:
		return -1
	var crates_cfg: Dictionary = Data.get_horde_level(horde_level).get("ammo_crates", {})
	var best: int = -1
	var best_d: float = float(crates_cfg.get("pickup_radius_m", 0.0))
	for i: int in ammo_crate_positions.size():
		var d: float = Vector2(at.x - ammo_crate_positions[i].x, at.z - ammo_crate_positions[i].z).length()
		if d <= best_d and (best < 0 or d < best_d):
			best = i
			best_d = d
	return best


func request_ammo_crate(crate: int) -> void:
	ammo_crate_requests.append(crate)


func get_hunters() -> Array[PlayerBase]:
	var out: Array[PlayerBase] = []
	if player != null:
		out.append(player)
	out.append_array(extra_hunters)
	return out


func get_hunter(for_slot: int) -> PlayerBase:
	if extra_hunters.is_empty():
		return player   # solo: same as HuntWorld
	for hunter: PlayerBase in get_hunters():
		if hunter.slot == for_slot:
			return hunter
	return null


func debug_horde_start_next_wave() -> void:
	if horde_mode and horde_phase == Ids.HP_INTERMISSION:
		horde_countdown_s = 0.0


func is_world_ready() -> bool:
	return _ready_flag


func get_map_id() -> StringName:
	return &"sandbox"


func get_map_rect() -> Rect2:
	return Rect2(-GROUND_SIZE_M * 0.5, -GROUND_SIZE_M * 0.5, GROUND_SIZE_M, GROUND_SIZE_M)


func get_crop_rects() -> Array[Rect2]:
	return [Rect2(20.0, -70.0, 40.0, 30.0)]


func get_crop_health_pct() -> float:
	return crop_pct


func get_boars_total() -> int:
	return _targets.size()


func get_boars_killed() -> int:
	return killed


func get_alive_boar_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for id: int in _targets:
		if _targets[id]["alive"]:
			ids.append(id)
	return ids


func get_boar_position(boar_id: int) -> Vector3:
	if not _targets.has(boar_id):
		return Vector3.INF
	return (_targets[boar_id]["node"] as Node3D).global_position


func get_boar_type(boar_id: int) -> StringName:
	return Ids.BOAR if _targets.has(boar_id) else &""


func get_boar_zone_position(boar_id: int, zone: StringName) -> Vector3:
	if not _targets.has(boar_id) or not ZONE_BOXES.has(String(zone)):
		return Vector3.INF
	var node: Node3D = _targets[boar_id]["node"]
	return node.global_position + (ZONE_BOXES[String(zone)][0] as Vector3)


func get_nearest_boar_position(from: Vector3) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_d: float = INF
	for id: int in get_alive_boar_ids():
		var p: Vector3 = get_boar_position(id)
		var d: float = from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


func get_player() -> PlayerBase:
	return player


func get_elapsed_s() -> float:
	return _elapsed


func debug_kill_boar(boar_id: int) -> void:
	if _targets.has(boar_id):
		_kill(boar_id, Ids.ZONE_BODY)


func debug_set_crop_health(pct: float) -> void:
	crop_pct = pct
	GameEvents.crop_health_changed.emit(pct)
