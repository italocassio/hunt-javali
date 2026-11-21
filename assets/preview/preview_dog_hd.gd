extends Node3D
## Preview of the HD dog prototype (assets/models/dog/dog_visual.gd). Prints budgets and build times, then renders
## the requested shots to PNG and quits (stats only with --headless).
##   tools/godot.sh --path . --fixed-fps 60 --resolution 960x540 res://assets/preview/preview_dog_hd.tscn -- \
##       --out=C:/abs/dir [--shots=breeds_studio,sheet_caramelo,sheet_foxhound,sheet_dogo,heads,lod,custom]
##       [--breed=caramelo] [--pose=idle|walk|trot|gallop|point|bark|bite|hurt|retreat] [--dist=3] [--yaw=90] [--frames=40]

const DogHD := preload("res://assets/models/dog/dog_visual.gd")
const Model := preload("res://assets/models/dog/dog_hd_model.gd")
const BoarHD := preload("res://assets/models/boar/boar_visual.gd")
const HUNTER_SCENE: String = "res://assets/models/hunter/hunter_visual.tscn"
const MAP_SCENE: String = "res://assets/preview/preview_map.tscn"
const DEFAULT_SHOTS: String = "breeds_studio,sheet_caramelo,sheet_foxhound,sheet_dogo,heads,lod"
const BREEDS: Array[StringName] = [&"caramelo", &"foxhound", &"dogo"]
const SHEET_POSES: Array[String] = ["idle", "walk", "gallop", "point", "bark", "bite", "retreat", "hurt"]
const HARD_TIMEOUT_S: float = 150.0
const GAME_FOV: float = 75.0

var _out_dir: String = "user://dog_hd"
var _frames: int = 40
var _breed: StringName = &"caramelo"
var _pose: String = "idle"
var _dist: float = 3.0
var _yaw: float = 90.0
var _world: Node3D
var _map: Node3D


func _ready() -> void:
	var shots: String = DEFAULT_SHOTS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 12)
		elif a.begins_with("--breed="):
			_breed = StringName(a.trim_prefix("--breed="))
		elif a.begins_with("--pose="):
			_pose = a.trim_prefix("--pose=")
		elif a.begins_with("--dist="):
			_dist = float(a.trim_prefix("--dist="))
		elif a.begins_with("--yaw="):
			_yaw = float(a.trim_prefix("--yaw="))
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	if DisplayServer.get_name() == "headless":
		_print_stats()
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false))


func _on_timeout() -> void:
	printerr("preview_dog_hd: timed out")
	get_tree().quit(1)


# --- stats -------------------------------------------------------------------------------------------------

func _print_stats() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var t0: int = Time.get_ticks_usec()
	Model.get_material()
	lines.append("shared material + noise texture (already warm in the hunt: 1st-person gun): %.1f ms" % _ms(t0))
	for b: StringName in BREEDS:
		var d: DogVisualBase = DogHD.new()
		var ts: int = Time.get_ticks_usec()
		d.setup(b)
		var cold: float = _ms(ts)
		ts = Time.get_ticks_usec()
		var d2: DogVisualBase = DogHD.new()
		d2.setup(b)
		var inst: float = _ms(ts)
		lines.append("setup(%s): cold %.2f ms, new instance + setup (cached) %.3f ms" % [b, cold, inst])
		d.free()
		d2.free()
	lines.append("breed    | LOD  | tris | visible MeshInstance3D")
	for b: StringName in BREEDS:
		var near: int = 0
		var mid: int = 0
		for part: String in Model.PARTS:
			near += Model.triangles(b, Model.LOD_NEAR, part)
			mid += Model.triangles(b, Model.LOD_MID, part)
		var far: int = Model.triangles(b, Model.LOD_FAR, "far")
		var d3: DogVisualBase = DogHD.new()
		d3.setup(b)
		var vis: Array[int] = [0, 0, 0]
		var mats: Dictionary = {}
		var shadow: Array[String] = []
		for mi: MeshInstance3D in d3.find_children("*", "MeshInstance3D", true, false):
			var lod: int = 2 if mi.name == "Far" else (0 if str(mi.name).ends_with("Near") else 1)
			vis[lod] += 1
			for si in mi.mesh.get_surface_count():
				mats[mi.mesh.surface_get_material(si).get_instance_id()] = true
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow.append(str(mi.get_parent().name) + "/" + str(mi.name))
		lines.append("%-8s | near | %4d | %d" % [b, near, vis[0]])
		lines.append("%-8s | mid  | %4d | %d" % [b, mid, vis[1]])
		lines.append("%-8s | far  | %4d | %d" % [b, far, vis[2]])
		var parts: PackedStringArray = PackedStringArray()
		for part: String in ["body", "head", "ears", "tail", "leg_fl", "leg_rl"]:
			parts.append("%s %d/%d" % [part, Model.triangles(b, Model.LOD_NEAR, part), Model.triangles(b, Model.LOD_MID, part)])
		lines.append("%-8s   parts near/mid: %s; materials %d; shadow casters %s; Mouth %s" % [b, ", ".join(parts), mats.size(),
			", ".join(shadow), str((d3.get_node("Mouth") as Node3D).position)])
		d3.free()
	for l in lines:
		print("preview_dog_hd: " + l)
	_zoom_lod_check()


## The LOD ranges follow the camera zoom: a dog at 52 m seen through a 4x scope keeps the near meshes.
func _zoom_lod_check() -> void:
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var d: Node3D = DogHD.new()
	add_child(d)
	d.position = Vector3(0.0, 0.0, -52.0)
	for fov: float in [GAME_FOV, GAME_FOV / 4.0]:
		cam.fov = fov
		d.call(&"_process", 0.016)
		var near: MeshInstance3D = d.get_node("Rig/BodyNear")
		var far: MeshInstance3D = d.get_node("Rig/Far")
		print("preview_dog_hd: camera fov %.1f: near LOD up to %.0f m, far LOD from %.0f m -> dog at 52 m drawn %s" % [fov,
			near.visibility_range_end, far.visibility_range_begin, "NEAR" if 52.0 < near.visibility_range_end else ("FAR" if 52.0 > far.visibility_range_begin else "MID")])
	d.free()
	cam.free()


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


# --- shots -------------------------------------------------------------------------------------------------

func _run(shots: PackedStringArray) -> void:
	for shot in shots:
		_clear()
		var cam: Camera3D
		var dogs: Array = []      # [dog, pose]
		match shot:
			"breeds_studio":
				cam = _studio()
				var hunter: Node3D = (load(HUNTER_SCENE) as PackedScene).instantiate()
				hunter.call(&"setup", 0, &"rifle_308")
				_world.add_child(hunter)
				hunter.position = Vector3(-2.15, 0.0, -0.3)
				hunter.rotation.y = deg_to_rad(-70.0)
				for i in 3:
					dogs.append([_dog(BREEDS[i], Vector3(-1.05 + float(i) * 1.15, 0.0, 0.0), 90.0), "idle"])
				var boar: BoarVisualBase = BoarHD.new()
				boar.setup(&"boar", 100.0)
				_world.add_child(boar)
				boar.position = Vector3(2.65, 0.0, -0.1)
				boar.rotation.y = deg_to_rad(90.0)
				_look(cam, Vector3(0.25, 0.62, 0.0), Vector3(0.25, 1.05, 5.0), 38.0)
			"sheet_caramelo", "sheet_foxhound", "sheet_dogo":
				cam = _studio()
				var b: StringName = StringName(shot.trim_prefix("sheet_"))
				var sp: float = Model.spec(b)["l"] * 1.18
				for i in SHEET_POSES.size():
					@warning_ignore("integer_division")
					var row: int = i / 4
					var col: int = i % 4
					dogs.append([_dog(b, Vector3((float(col) - 1.5) * sp, 0.0, -float(row) * 1.6 + 0.8), 90.0), SHEET_POSES[i]])
				_look(cam, Vector3(0.0, 0.3, 0.0), Vector3(0.0, 2.3, 3.9 * sp), 40.0)
			"heads", "heads_side":
				# the three heads, 3/4 front, about 1.3 m away, game sun
				cam = _game_light_flat()
				for i in 3:
					var yaw: float = 90.0 if shot == "heads_side" else 180.0 + 38.0
					var lay: Dictionary = Model.layout(BREEDS[i])
					var hc: Vector3 = (lay["np"] as Vector3) + (lay["skull"] as Transform3D) * Vector3(0.0, 0.0, -0.5 * float(lay["hl"]))
					var off: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * hc
					var gap: float = 0.55 if shot == "heads_side" else 0.46
					var d: DogVisualBase = _dog(BREEDS[i], Vector3((float(i) - 1.0) * gap - off.x, 0.0, -off.z + (0.35 * float(i - 1) if shot == "heads_side" else 0.0)), yaw)
					dogs.append([d, "still"])
				_look(cam, Vector3(0.0, 0.62, 0.0), Vector3(0.12, 0.78, 1.3 if shot == "heads" else 1.75), 40.0)
			"lod", "lod_scope":
				# open cerrado west of the crops, looking east (+X); the dogs in profile at 10, 30 and 60 m
				cam = _map_scene()
				var eye: Vector3 = _ground(Vector3(-50.0, 0.0, 30.0)) + Vector3(0.0, 1.7, 0.0)
				var dists: Array[float] = [10.0, 30.0, 60.0]
				var lat: Array[float] = [1.6, -5.0, 9.0]
				for i in 3:
					var at: Vector3 = _ground(Vector3(eye.x + dists[i], 0.0, eye.z + lat[i]))
					dogs.append([_dog(_breed, at, 0.0 if i != 1 else 180.0), "idle"])
					_clear_sight(eye, at)
				var target: Vector3 = (dogs[2][0] as Node3D).position + Vector3(0, 0.35, 0) if shot == "lod_scope" else _ground(Vector3(eye.x + 25.0, 0.0, eye.z)) + Vector3(0.0, 0.5, 0.0)
				_look(cam, target, eye, GAME_FOV if shot == "lod" else GAME_FOV / 4.0)
			"custom":
				cam = _studio()
				dogs.append([_dog(_breed, Vector3.ZERO, _yaw), _pose])
				_look(cam, Vector3(0.0, 0.35, 0.0), Vector3(0.0, 0.7, _dist), 36.0)
			_:
				printerr("preview_dog_hd: unknown shot '%s'" % shot)
				continue
		for e: Array in dogs:
			_start_pose(e[0], e[1])
		for f in _frames:
			for e: Array in dogs:
				var d2: DogVisualBase = e[0]
				match String(e[1]):
					"bark":
						if f == _frames - 9:
							d2.play_bark()
					"hurt":
						if f == _frames - 7:
							d2.play_hurt()
					"walk": d2.set_locomotion(1.2)
					"trot": d2.set_locomotion(3.2)
					"gallop": d2.set_locomotion(9.0)
					"still": d2.set_process(false)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("%s.png" % shot)
		var err: Error = image.save_png(path)
		print("preview_dog_hd: %s %s" % ["saved" if err == OK else "FAILED", path])
		if shot == "lod":
			_save_crops(image, cam, dogs, _out_dir.path_join("lod_crops.png"))
	get_tree().quit(0)


## Pixel-exact enlargements (nearest) around each dog, side by side: what the player really gets at that distance.
func _save_crops(image: Image, cam: Camera3D, dogs: Array, path: String) -> void:
	var k_px: Vector2 = Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var side: int = 288
	var cells: Array[int] = [96, 48, 32]
	var out: Image = Image.create(side * dogs.size(), side, false, image.get_format())
	for i in dogs.size():
		var cell: int = cells[mini(i, 2)]
		var c: Vector2 = cam.unproject_position((dogs[i][0] as Node3D).global_position + Vector3(0.0, 0.3, 0.0)) * k_px
		@warning_ignore("integer_division")
		var r: Rect2i = Rect2i(clampi(int(c.x) - cell / 2, 0, image.get_width() - cell), clampi(int(c.y) - cell / 2, 0, image.get_height() - cell), cell, cell)
		var crop: Image = image.get_region(r)
		crop.resize(side, side, Image.INTERPOLATE_NEAREST)
		out.blit_rect(crop, Rect2i(0, 0, side, side), Vector2i(i * side, 0))
	var err: Error = out.save_png(path)
	print("preview_dog_hd: %s %s (screen cells of 96 / 48 / 32 px around the dogs at 10 / 30 / 60 m, enlarged 3x / 6x / 9x)" % ["saved" if err == OK else "FAILED", path])


## Preview only: hides the map props (trees, shrubs, mounds) standing within 3 m of the line of sight to a dog.
func _clear_sight(eye: Vector3, at: Vector3) -> void:
	var a: Vector2 = Vector2(eye.x, eye.z)
	var b: Vector2 = Vector2(at.x, at.z)
	for child: Node in _map.get_children():
		var n3: Node3D = child as Node3D
		if n3 == null or n3.position == Vector3.ZERO:
			continue
		var p: Vector2 = Vector2(n3.position.x, n3.position.z)
		var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if t > 0.02 and p.distance_to(a.lerp(b, t)) < 3.0:
			n3.visible = false


func _start_pose(d: DogVisualBase, pose: String) -> void:
	match pose:
		"walk": d.set_locomotion(1.2)
		"trot": d.set_locomotion(3.2)
		"gallop": d.set_locomotion(9.0)
		"point": d.play_point()
		"bite": d.play_bite(true)
		"retreat": d.set_retreating(true)


func _dog(breed: StringName, pos: Vector3, yaw_deg: float) -> DogVisualBase:
	var d: DogVisualBase = DogHD.new()
	d.setup(breed)
	_world.add_child(d)
	d.position = pos
	d.rotation.y = deg_to_rad(yaw_deg)
	return d


func _look(cam: Camera3D, target: Vector3, from: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, target, Vector3.UP)
	cam.make_current()


func _clear() -> void:
	if _world != null:
		_world.free()
	_world = Node3D.new()
	add_child(_world)
	_map = null


func _ground(p: Vector3) -> Vector3:
	if _map == null:
		return Vector3(p.x, 0.0, p.z)
	return Vector3(p.x, float(_map.call(&"_h", p.x, p.z)), p.z)


func _studio() -> Camera3D:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.37, 0.39)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_light(Vector3(-40.0, 35.0, 0.0), Color(1.0, 0.96, 0.9), 1.3, true)
	_light(Vector3(-15.0, -140.0, 0.0), Color(0.8, 0.88, 1.0), 0.45, false)
	_light(Vector3(-25.0, 165.0, 0.0), Color(1.0, 1.0, 1.0), 0.9, false)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.19, 0.18)
	gm.roughness = 0.95
	ground.material_override = gm
	_world.add_child(ground)
	var cam: Camera3D = Camera3D.new()
	cam.near = 0.05
	cam.far = 200.0
	_world.add_child(cam)
	return cam


func _light(rot_deg: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var l: DirectionalLight3D = DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	l.shadow_enabled = shadows
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	l.directional_shadow_max_distance = 15.0
	l.shadow_blur = 1.5
	_world.add_child(l)


func _game_light_flat() -> Camera3D:
	var env: Node3D = (load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate()
	_world.add_child(env)
	(env.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.40, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	_world.add_child(ground)
	var cam: Camera3D = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	_world.add_child(cam)
	return cam


## The art-director map slice (same sky, sun, terrain shader and flora as the hunt), no old boars.
func _map_scene() -> Camera3D:
	var packed: PackedScene = load(MAP_SCENE)
	_map = packed.instantiate()
	_map.set(&"with_boars", false)
	_world.add_child(_map)
	var cam: Camera3D = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	_world.add_child(cam)
	return cam
