class_name SandboxWorld
extends HuntWorld
## Package A sandbox: flat 200x200 ground (layer 1), three shootable targets with HitZones and a
## kill counter. Stands in for the hunt so the player, weapons and HUD run without Package B.
## Command line (after "--"): --touch=on|off, --weapons=a,b, --items=a,b, --aim, --demo

const GROUND_SIZE_M: float = 200.0
const TARGET_DISTANCES_M: Array[float] = [10.0, 30.0, 60.0]
const TARGET_WEIGHT_KG: float = 100.0
const TARGET_HEALTH_PER_KG: float = 1.2
const ZONE_BOXES: Dictionary = {
	"head": [Vector3(0.0, 0.75, -0.55), Vector3(0.3, 0.3, 0.3)],
	"vital": [Vector3(0.0, 0.6, -0.2), Vector3(0.45, 0.4, 0.5)],
	"body": [Vector3(0.0, 0.5, 0.2), Vector3(0.5, 0.5, 0.6)],
	"rear": [Vector3(0.0, 0.5, 0.65), Vector3(0.45, 0.45, 0.35)],
}

var player: Player = null
var killed: int = 0
var crop_pct: float = 87.0
var kill_log: Array[KillInfo] = []
var hit_log: Array[HitInfo] = []
var _targets: Dictionary = {}     # id -> {node, health, zones, last_shot, one_shot, alive}
var _ready_flag: bool = false
var _elapsed: float = 0.0
var _multipliers: Dictionary = {}
var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	_multipliers = Data.get_boar_rules().get("zone_multipliers", {})
	_build_ground()
	add_child(MapEnvironmentBase.create_fallback())
	_build_targets()
	_spawn_player()
	_ready_flag = true
	world_ready.emit()
	GameEvents.boar_counts_changed.emit(0, _targets.size())
	GameEvents.crop_health_changed.emit(crop_pct)
	GameEvents.hunt_started.emit(_request())


func _process(delta: float) -> void:
	_elapsed += delta


func _parse_args() -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
			parsed[pair[0]] = pair[1] if pair.size() > 1 else "1"
	return parsed


func _request() -> HuntRequest:
	var r: HuntRequest = HuntRequest.make_debug()
	r.weapon_ids = [Ids.W_CARBINE_22, Ids.W_SHOTGUN_12]
	r.item_ids = [Ids.I_BINOCULARS, Ids.I_LEATHER_VEST, Ids.I_MEDKIT, Ids.I_CORN_BAIT]
	r.item_counts = {Ids.I_MEDKIT: 2, Ids.I_CORN_BAIT: 1}
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
	if _args.has("aim"):
		player.bot_set_enabled(true)
		player.bot_set_aim(true)
	if _args.has("demo"):
		_run_demo.call_deferred()
	if _args.has("stick"):
		_run_stick_demo.call_deferred()


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


# --- HuntWorld overrides ---
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
