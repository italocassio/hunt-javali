extends Node3D
## Preview: a slice of the Mato Grosso map built from the art-director assets.

@export var cam_mode: String = "eye"
@export var with_boars: bool = true

const SIZE: float = 120.0
const STEP: float = 2.0


func _h(x: float, z: float) -> float:
	return sin(x * 0.045) * 1.2 + cos(z * 0.06 + 1.0) * 0.9 + sin((x + z) * 0.11) * 0.25


func _ready() -> void:
	var env: Node = load("res://assets/env/mato_grosso_env.tscn").instantiate()
	add_child(env)
	(env.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	_terrain()
	var lib: Script = load("res://assets/models/flora/flora_library.gd")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	# grass
	_scatter(lib, &"grass_tuft", 900, rng, func(p: Vector2) -> bool: return not _in_crop(p) and p.y > -45.0, 0.4)
	_scatter(lib, &"shrub", 60, rng, func(p: Vector2) -> bool: return not _in_crop(p) and p.y > -40.0, 1.0)
	_scatter(lib, &"cerrado_tree", 26, rng, func(p: Vector2) -> bool: return not _in_crop(p) and p.y > -45.0, 1.0)
	_scatter(lib, &"termite_mound", 7, rng, func(p: Vector2) -> bool: return not _in_crop(p), 1.0)
	_scatter(lib, &"ipe", 3, rng, func(p: Vector2) -> bool: return not _in_crop(p) and p.y < -10.0 and p.y > -50.0 and absf(p.x) > 10, 1.0)
	# gallery forest on the far side
	_scatter(lib, &"cerrado_tree", 70, rng, func(p: Vector2) -> bool: return p.y < -52.0, 1.3)
	# crops
	for gx in range(-20, 22, 2):
		for gz in range(-14, 8, 2):
			var kind: StringName = &"soy_patch"
			var p: Vector2 = Vector2(gx + 1.0, gz + 1.0)
			if gx > 8:
				kind = &"corn_patch"
			if (gx + gz) % 14 == 0:
				kind = &"soy_eaten" if kind == &"soy_patch" else &"corn_eaten"
			_place(lib, kind, p)
	# pond + buritis
	var water: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(16, 16)
	water.mesh = pm
	water.material_override = load("res://assets/materials/water.tres")
	water.position = Vector3(32, _h(32, 20) - 0.2, 20)
	add_child(water)
	for i in 6:
		_place(lib, &"buriti", Vector2(32.0 + cos(i * 1.1) * 11.0, 20.0 + sin(i * 1.1) * 11.0))
	# props if present
	for pr in [[&"farmhouse", Vector2(-30, -10)], [&"barn", Vector2(-48, 4)], [&"water_tank", Vector2(-20, 6)]]:
		var path: String = "res://assets/models/props/%s.tscn" % pr[0]
		if ResourceLoader.exists(path):
			var n: Node3D = (load(path) as PackedScene).instantiate()
			n.position = Vector3(pr[1].x, _h(pr[1].x, pr[1].y), pr[1].y)
			add_child(n)
	if with_boars:
		var scn: PackedScene = load("res://assets/models/boar/boar_visual.tscn")
		var spots: Array = [[Vector2(2, -4), Ids.BOAR, 130.0, 0.0], [Vector2(5, -3), Ids.SOW, 80.0, 40.0], [Vector2(-4, -5), Ids.ALPHA, 230.0, -30.0], [Vector2(8, -2), Ids.PIGLET, 30.0, 70.0]]
		for s in spots:
			var b: BoarVisualBase = scn.instantiate()
			add_child(b)
			b.setup(s[1], s[2])
			b.scale = Vector3.ONE * BoarVisualBase.scale_for_weight(s[2])
			b.position = Vector3(s[0].x, _h(s[0].x, s[0].y), s[0].y)
			b.rotation.y = deg_to_rad(s[3])
			if s[1] == Ids.BOAR:
				b.set_eating(true)
	if OS.get_cmdline_user_args().has("--top"):
		cam_mode = "top"
	if OS.get_cmdline_user_args().has("--walk"):
		cam_mode = "walk"
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	if cam_mode == "eye":
		cam.position = Vector3(2.0, _h(2, 12) + 1.7, 12.0)
		cam.look_at(Vector3(-4.0, 1.4, -10.0))
		cam.fov = 70.0
	elif cam_mode == "walk":
		cam.position = Vector3(-2.0, _h(-2, 10) + 1.7, 12.0)
		cam.look_at(Vector3(-2.0, 0.0, 0.0))
		cam.fov = 70.0
	else:
		cam.position = Vector3(10, 40, 50)
		cam.look_at(Vector3(0, 0, -10))
		cam.fov = 60.0


func _in_crop(p: Vector2) -> bool:
	return p.x > -22.0 and p.x < 22.0 and p.y > -16.0 and p.y < 10.0


func _place(lib: Script, id: StringName, p: Vector2, s: float = 1.0) -> void:
	var m: Mesh = lib.call(&"build_mesh", id)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = m
	mi.position = Vector3(p.x, _h(p.x, p.y), p.y)
	mi.scale = Vector3.ONE * s
	if id in [&"grass_tuft", &"shrub", &"soy_patch", &"corn_patch", &"soy_eaten", &"corn_eaten"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _scatter(lib: Script, id: StringName, count: int, rng: RandomNumberGenerator, ok: Callable, s: float) -> void:
	var placed: int = 0
	var guard: int = 0
	while placed < count and guard < count * 20:
		guard += 1
		var p: Vector2 = Vector2(rng.randf_range(-SIZE * 0.5, SIZE * 0.5), rng.randf_range(-SIZE * 0.6, SIZE * 0.25))
		if not ok.call(p):
			continue
		_place(lib, id, p, s * rng.randf_range(0.8, 1.25))
		placed += 1


func _terrain() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = int(SIZE / STEP)
	for iz in n:
		for ix in n:
			var quad: Array = [Vector2(ix, iz), Vector2(ix + 1, iz), Vector2(ix + 1, iz + 1), Vector2(ix, iz + 1)]
			var order: Array = [0, 1, 2, 0, 2, 3]
			for o in order:
				var q: Vector2 = quad[o]
				var x: float = q.x * STEP - SIZE * 0.5
				var z: float = q.y * STEP - SIZE * 0.5 - 20.0
				var c: Color = Color(0, 0, 0, 1)
				if _in_crop(Vector2(x, z)):
					c.r = 1.0
				if absf(x + 26.0) < 3.0 or (z > 14 and z < 17):
					c.g = 1.0
				if Vector2(x - 32.0, z - 20.0).length() < 10.0:
					c.b = clampf((10.0 - Vector2(x - 32.0, z - 20.0).length()) / 3.0, 0, 1)
				st.set_color(c)
				st.set_uv(Vector2(x, z) / 4.0)
				st.add_vertex(Vector3(x, _h(x, z), z))
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = load("res://assets/materials/terrain.tres")
	add_child(mi)
