extends Node3D
## Preview of the HD trees (assets/models/flora/trees_hd.gd). Headless: prints the budget table and quits.
## With a window: renders the shots to PNG and quits.
##   tools/godot.sh --headless --path . res://assets/preview/preview_trees_hd.tscn
##   tools/godot.sh --path . --windowed --resolution 960x540 res://assets/preview/preview_trees_hd.tscn -- \
##       --out=C:/abs/dir [--shots=trees_studio,trees_map,trees_backlight,trees_far] [--frames=30]
##       [--cam=px,py,pz,tx,ty,tz]   (overrides the camera of every shot)

const TreesHD := preload("res://assets/models/flora/trees_hd.gd")
const FLORA_LIB: String = "res://assets/models/flora/flora_library.gd"
const MAP_SCENE: String = "res://src/world/maps/mato_grosso/mato_grosso_map.tscn"
const ENV_SCENE: String = "res://assets/env/mato_grosso_env.tscn"
const HUNTER_SCENE: String = "res://assets/models/hunter/hunter_visual.tscn"
const IDS: Array[StringName] = [&"cerrado_tree", &"ipe", &"buriti"]
const OLD_FUNCS: Dictionary = {&"cerrado_tree": "_cerrado_tree", &"ipe": "_ipe", &"buriti": "_buriti"}
const DEFAULT_SHOTS: String = "trees_studio,trees_map,trees_backlight,trees_far"
const HARD_TIMEOUT_S: float = 150.0

var _out_dir: String = "user://trees_hd"
var _frames: int = 30
var _cam_override: String = ""
var _world: Node3D


func _ready() -> void:
	var shots: String = DEFAULT_SHOTS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 4)
		elif a.begins_with("--cam="):
			_cam_override = a.trim_prefix("--cam=")
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	if DisplayServer.get_name() == "headless":
		_measure()
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false))


func _on_timeout() -> void:
	printerr("preview_trees_hd: timed out")
	get_tree().quit(1)


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


static func _tris(m: Mesh) -> int:
	var n: int = 0
	for s in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		if arr[Mesh.ARRAY_INDEX] != null:
			n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# --- stats -------------------------------------------------------------------------------------------------

func _measure() -> void:
	var t0: int = Time.get_ticks_usec()
	TreesHD._noise()
	print("preview_trees_hd: shared noise texture (warm in the hunt: 1st-person gun) %.1f ms" % _ms(t0))
	var lib: Script = load(FLORA_LIB)
	var new_t: Dictionary = {}
	var old_t: Dictionary = {}
	var total_ms: float = 0.0
	var mats: Dictionary = {}
	print("preview_trees_hd: id           | tris (old) | surfaces | materials | verts | aabb size / pos | cold ms")
	for id: StringName in IDS:
		var ts: int = Time.get_ticks_usec()
		var m: Mesh = TreesHD.build(id)
		var cold: float = _ms(ts)
		total_ms += cold
		var verts: int = 0
		var local: Dictionary = {}
		for s in m.get_surface_count():
			verts += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			local[m.surface_get_material(s).get_instance_id()] = true
			mats[m.surface_get_material(s).get_instance_id()] = true
		var old: Mesh = lib.call(OLD_FUNCS[id])
		new_t[id] = _tris(m)
		old_t[id] = _tris(old)
		var bb: AABB = m.get_aabb()
		print("preview_trees_hd: %-12s | %4d (%3d) | %d | %d | %4d | %s / %s | %.1f" % [id, new_t[id], old_t[id],
			m.get_surface_count(), local.size(), verts, bb.size, bb.position, cold])
	print("preview_trees_hd: three trees cold total %.1f ms, distinct materials %d" % [total_ms, mats.size()])
	# through the library (cache) as the gameplay calls it
	var tl: int = Time.get_ticks_usec()
	for id: StringName in IDS:
		lib.call(&"build_mesh", id)
	print("preview_trees_hd: flora_library.build_mesh x3 (trees_hd already compiled) %.1f ms" % _ms(tl))
	# instances in the real map
	for d: float in [0.5, 1.0]:
		var map: Node3D = (load(MAP_SCENE) as PackedScene).instantiate()
		add_child(map)
		map.call(&"build_heightmap")
		map.call(&"build_flora", d)
		var before: int = 0
		var after: int = 0
		var parts: PackedStringArray = PackedStringArray()
		for id: StringName in IDS:
			var c: int = (map.call(&"get_flora_positions", id) as PackedVector2Array).size()
			before += c * int(old_t[id])
			after += c * int(new_t[id])
			parts.append("%s %d" % [id, c])
		print("preview_trees_hd: flora_density %.2f: %s -> tree tris on the map: before %d, after %d (x%.2f)" % [d,
			", ".join(parts), before, after, float(after) / float(maxi(before, 1))])
		map.free()


# --- shots -------------------------------------------------------------------------------------------------

func _run(shots: PackedStringArray) -> void:
	for shot: String in shots:
		if _world != null:
			_world.free()
		_world = Node3D.new()
		add_child(_world)
		var cam: Camera3D = Camera3D.new()
		cam.near = 0.05
		cam.far = 500.0
		cam.fov = 70.0
		match shot:
			"trees_studio":
				_studio()
				_tree(&"cerrado_tree", Vector3(7.0, 0.0, 0.0), 30.0)
				_tree(&"ipe", Vector3(0.5, 0.0, -1.0), 200.0)
				_tree(&"buriti", Vector3(-7.5, 0.0, 0.0), 0.0)
				var hunter: Node3D = (load(HUNTER_SCENE) as PackedScene).instantiate()
				_world.add_child(hunter)
				hunter.position = Vector3(3.6, 0.0, 1.5)
				hunter.rotation.y = deg_to_rad(20.0)
				cam.fov = 50.0
				_look(cam, Vector3(0.0, 5.6, 0.0), Vector3(-2.0, 4.0, 25.0))
			"trees_map":
				var m: Node3D = _map()
				_look_map(cam, m, Vector2(-36.0, -18.0), 1.7, Vector2(-62.0, -50.0), 4.0)
			"trees_backlight":
				var m2: Node3D = _map()
				_look_map(cam, m2, Vector2(-38.0, 76.0), 1.7, Vector2(-27.0, 104.0), 5.5)
			"trees_far":
				var m3: Node3D = _map()
				_look_map(cam, m3, Vector2(20.0, 2.0), 3.0, Vector2(112.0, -40.0), 4.0)
		if not _cam_override.is_empty():
			var v: PackedStringArray = _cam_override.split(",")
			if cam.get_parent() == null:
				_world.add_child(cam)
			cam.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
		cam.make_current()
		for i in _frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("%s.png" % shot)
		var err: Error = image.save_png(path)
		print("preview_trees_hd: %s %s" % ["saved" if err == OK else "FAILED", path])
	get_tree().quit(0)


func _look(cam: Camera3D, target: Vector3, from: Vector3) -> void:
	_world.add_child(cam)
	cam.position = from
	cam.look_at(target)


func _tree(id: StringName, pos: Vector3, yaw_deg: float) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = load(FLORA_LIB).call(&"build_mesh", id)
	mi.position = pos
	mi.rotation.y = deg_to_rad(yaw_deg)
	_world.add_child(mi)


func _studio() -> void:
	var env_root: Node3D = (load(ENV_SCENE) as PackedScene).instantiate()
	_world.add_child(env_root)
	(env_root.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	(env_root.get_node("Sun") as DirectionalLight3D).directional_shadow_max_distance = 45.0
	var we: WorldEnvironment = env_root.get_node("WorldEnvironment")
	we.environment.fog_enabled = false
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.6, 0.5, 0.32)
	ground.material_override = gm
	_world.add_child(ground)


## The real hunt map (terrain, props, flora as MultiMesh at high density) under the game light (medium shadows).
func _map() -> Node3D:
	var env_root: Node3D = (load(ENV_SCENE) as PackedScene).instantiate()
	_world.add_child(env_root)
	(env_root.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	(env_root.get_node("Sun") as DirectionalLight3D).directional_shadow_max_distance = 30.0
	var map: Node3D = (load(MAP_SCENE) as PackedScene).instantiate()
	_world.add_child(map)
	map.call(&"build_heightmap")
	map.call(&"build_terrain")
	map.call(&"build_props_and_water")
	map.call(&"build_flora", 1.0)
	return map


func _look_map(cam: Camera3D, map: Node3D, from: Vector2, eye: float, to: Vector2, up: float) -> void:
	var hm: Object = map.get(&"heightmap")
	var f: Vector3 = Vector3(from.x, float(hm.call(&"get_height", from.x, from.y)) + eye, from.y)
	var t: Vector3 = Vector3(to.x, float(hm.call(&"get_height", to.x, to.y)) + up, to.y)
	_look(cam, t, f)
	print("preview_trees_hd: camera %s -> %s (%.0f m)" % [f, t, f.distance_to(t)])
