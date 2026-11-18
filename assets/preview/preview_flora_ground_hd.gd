extends Node3D
## Preview of the HD ground flora (grass, shrub, termite mound, soy and corn). User args (after the second --):
##   --measure   print tris / surfaces / materials / cold ms for every id, quit
##   --studio    the 7 ids side by side on flat ground
##   --map       grass, shrubs and a termite mound at eye height in the preview map (game light)
##   --crops     healthy and eaten soy and corn in the preview map (game light)
##   --cam=px,py,pz,tx,ty,tz overrides the camera (offsets from the map origin, y is above ground)
## Screenshot: tools/godot.sh --path . --windowed --resolution 960x540 -s res://tools/screenshot.gd -- \
##   --scene=res://assets/preview/preview_flora_ground_hd.tscn --out=<png> -- --studio

const LIB_PATH: String = "res://assets/models/flora/flora_library.gd"
const IDS: Array[StringName] = [&"grass_tuft", &"shrub", &"termite_mound", &"soy_patch", &"soy_eaten", &"corn_patch", &"corn_eaten"]

var _lib: Script = null


func _ready() -> void:
	_lib = load(LIB_PATH)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--measure"):
		_measure()
		return
	var cam: Camera3D = Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	if args.has("--studio"):
		_studio(cam)
	elif args.has("--close"):
		_close(cam)
	elif args.has("--crops"):
		_in_map(cam, false)
	else:
		_in_map(cam, true)
	cam.make_current()
	for a: String in args:
		if a.begins_with("--cam="):
			var v: PackedStringArray = a.trim_prefix("--cam=").split(",")
			cam.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))


func _studio(cam: Camera3D) -> void:
	var env_root: Node = (load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate()
	add_child(env_root)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.50, 0.36, 0.22)
	ground.material_override = gm
	add_child(ground)
	var xs: Array[float] = [0.0, 1.6, 3.4, 5.9, 8.2, 10.8, 13.5]
	for i: int in IDS.size():
		var id: StringName = IDS[i]
		if id == &"grass_tuft":
			var r: RandomNumberGenerator = RandomNumberGenerator.new()
			r.seed = 3
			for j: int in 9:
				_put(id, Vector3(xs[i] + r.randf_range(-0.7, 0.7), 0.0, r.randf_range(-0.7, 0.7)), r.randf_range(0.0, TAU), r.randf_range(0.9, 1.3))
		else:
			_put(id, Vector3(xs[i], 0.0, 0.0), 0.0, 1.0)
	cam.fov = 52.0
	cam.position = Vector3(6.8, 2.8, -9.0)
	cam.look_at(Vector3(6.8, 0.8, 0.0))


func _close(cam: Camera3D) -> void:
	var env_root: Node = (load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate()
	add_child(env_root)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.27, 0.15)
	ground.material_override = gm
	add_child(ground)
	var xs: Array[float] = [-3.0, -1.0, 1.0, 3.0]
	var ids: Array[StringName] = [&"soy_patch", &"soy_eaten", &"corn_patch", &"corn_eaten"]
	for i: int in 4:
		_put(ids[i], Vector3(xs[i], 0.0, 0.0), 0.3 * float(i), 1.0)
	cam.fov = 60.0
	cam.position = Vector3(0.0, 1.5, -4.3)
	cam.look_at(Vector3(0.0, 0.7, 0.0))


func _put(id: StringName, pos: Vector3, yaw: float, s: float) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _lib.call(&"build_mesh", id) as Mesh
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _in_map(cam: Camera3D, ground: bool) -> void:
	var map: Node3D = (load("res://assets/preview/preview_map.tscn") as PackedScene).instantiate()
	map.set("with_boars", false)
	add_child(map)
	var from: Vector3
	var to: Vector3
	if ground:
		var r: RandomNumberGenerator = RandomNumberGenerator.new()
		r.seed = 21
		# dense capim like the game, plus a few shrubs and mounds in the foreground
		_mm(map, &"grass_tuft", 1500, Rect2(-16.0, 17.0, 32.0, 20.0), r, 0.0)
		var spots: Array = [[&"shrub", Vector2(-6.5, 27.0), 1.0], [&"shrub", Vector2(1.0, 29.5), 1.1], [&"shrub", Vector2(5.5, 25.0), 0.9],
			[&"shrub", Vector2(-10.0, 23.0), 1.2], [&"termite_mound", Vector2(-2.0, 24.5), 1.0], [&"termite_mound", Vector2(3.0, 21.0), 0.8]]
		for s: Array in spots:
			var p: Vector2 = s[1]
			_put(s[0], Vector3(p.x, float(map.call("_h", p.x, p.y)), p.y), r.randf_range(0.0, TAU), s[2])
		from = Vector3(-3.0, 0.0, 35.0)
		to = Vector3(-3.0, 0.0, 20.0)
		from.y = float(map.call("_h", from.x, from.z)) + 1.7
		to.y = float(map.call("_h", to.x, to.z)) + 1.0
	else:
		from = Vector3(4.0, 0.0, 9.5)
		to = Vector3(9.0, 0.0, 0.0)
		from.y = float(map.call("_h", from.x, from.z)) + 1.7
		to.y = float(map.call("_h", to.x, to.z)) + 0.6
	cam.position = from
	cam.look_at(to)


func _mm(map: Node3D, id: StringName, count: int, area: Rect2, r: RandomNumberGenerator, _unused: float) -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _lib.call(&"build_mesh", id) as Mesh
	mm.instance_count = count
	for i: int in count:
		var x: float = r.randf_range(area.position.x, area.end.x)
		var z: float = r.randf_range(area.position.y, area.end.y)
		var s: float = 1.0 + r.randf_range(-0.2, 0.2)
		var b: Basis = Basis(Vector3.UP, r.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(x, float(map.call("_h", x, z)), z)))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _measure() -> void:
	var total: float = 0.0
	for id: StringName in IDS:
		var t0: int = Time.get_ticks_usec()
		var mesh: Mesh = _lib.call(&"build_mesh", id) as Mesh
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		var tris: int = 0
		var mats: Dictionary = {}
		for s: int in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			mats[mesh.surface_get_material(s)] = true
		var bb: AABB = mesh.get_aabb()
		print("%s tris=%d surfaces=%d materials=%d cold_ms=%.1f aabb_size=%s aabb_pos=%s" % [id, tris, mesh.get_surface_count(), mats.size(), ms, bb.size, bb.position])
	print("TOTAL cold_ms=%.1f" % total)
	get_tree().quit()
