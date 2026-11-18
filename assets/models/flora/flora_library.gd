extends RefCounted
## Procedural flora and crop meshes for the Mato Grosso cerrado. No class_name (loaded by path).
## Usage: var m: Mesh = lib.call(&"build_mesh", &"ipe"). Origin at the base, Y up. null for unknown ids.

const WIND_SHADER: String = "res://assets/shaders/foliage_wind.gdshader"
const GroundHD := preload("res://assets/models/flora/flora_ground_hd.gd")

static var _cache: Dictionary = {}
static var _wind_mats: Dictionary = {}


static func ids() -> PackedStringArray:
	return PackedStringArray(["grass_tuft", "shrub", "cerrado_tree", "ipe", "buriti", "termite_mound",
		"soy_patch", "soy_eaten", "corn_patch", "corn_eaten"])


static func build_mesh(id: StringName) -> Mesh:
	if _cache.has(id):
		return _cache[id]
	var mesh: Mesh = null
	match id:
		&"grass_tuft": mesh = GroundHD.build(&"grass_tuft")
		&"shrub": mesh = GroundHD.build(&"shrub")
		&"cerrado_tree": mesh = load("res://assets/models/flora/trees_hd.gd").call(&"build", id) as Mesh
		&"ipe": mesh = load("res://assets/models/flora/trees_hd.gd").call(&"build", id) as Mesh
		&"buriti": mesh = load("res://assets/models/flora/trees_hd.gd").call(&"build", id) as Mesh
		&"termite_mound": mesh = GroundHD.build(&"termite_mound")
		&"soy_patch": mesh = GroundHD.build(&"soy_patch")
		&"soy_eaten": mesh = GroundHD.build(&"soy_eaten")
		&"corn_patch": mesh = GroundHD.build(&"corn_patch")
		&"corn_eaten": mesh = GroundHD.build(&"corn_eaten")
		_: return null
	_cache[id] = mesh
	return mesh


## Shared wind material per (strength, sway height) preset.
static func wind_material(kind: StringName) -> Material:
	if _wind_mats.has(kind):
		return _wind_mats[kind]
	var m: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = load(WIND_SHADER) as Shader
	if shader == null:
		return MeshKit.vcol_material_double()
	m.shader = shader
	match kind:
		&"grass":
			m.set_shader_parameter("wind_strength", 0.16)
			m.set_shader_parameter("sway_height", 0.4)
			m.set_shader_parameter("wind_speed", 1.8)
		&"shrub":
			m.set_shader_parameter("wind_strength", 0.05)
			m.set_shader_parameter("sway_height", 1.0)
		&"crop":
			m.set_shader_parameter("wind_strength", 0.06)
			m.set_shader_parameter("sway_height", 1.0)
			m.set_shader_parameter("wind_speed", 1.6)
		&"canopy":
			m.set_shader_parameter("wind_strength", 0.012)
			m.set_shader_parameter("sway_height", 3.0)
			m.set_shader_parameter("wind_speed", 1.0)
		_:
			m.set_shader_parameter("wind_strength", 0.03)
	_wind_mats[kind] = m
	return m


static func _rng(id: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash(id)
	return r


# --- trees -----------------------------------------------------------------------------------

static func _cerrado_tree() -> Mesh:
	var trunk: MeshKit = MeshKit.new()
	var canopy: MeshKit = MeshKit.new()
	var bark: Color = Color(0.30, 0.22, 0.17)
	var bark_hi: Color = Color(0.42, 0.32, 0.24)
	# twisted trunk: three offset segments
	trunk.frustum(Vector3(0, 0, 0), 0.24, 0.19, 1.4, 5, bark, bark_hi, false, false, Vector2(0.18, 0.05))
	trunk.frustum(Vector3(0.18, 1.4, 0.05), 0.19, 0.16, 1.3, 5, bark, bark_hi, false, false, Vector2(-0.22, 0.12))
	trunk.frustum(Vector3(-0.04, 2.7, 0.17), 0.16, 0.10, 1.0, 5, bark, bark_hi, true, false, Vector2(0.15, -0.1))
	# two forks
	trunk.set_xf(Vector3(0.0, 2.5, 0.15), Vector3(0, 0, 55))
	trunk.frustum(Vector3.ZERO, 0.075, 0.04, 1.0, 5, bark, bark_hi, true, false)
	trunk.set_xf(Vector3(0.0, 2.7, 0.15), Vector3(25, 0, -50))
	trunk.frustum(Vector3.ZERO, 0.07, 0.035, 0.9, 5, bark, bark_hi, true, false)
	trunk.reset_xf()
	var leaf_d: Color = Color(0.30, 0.38, 0.15)
	var leaf_l: Color = Color(0.50, 0.55, 0.22)
	canopy.ellipsoid(Vector3(0.1, 3.9, 0.1), Vector3(1.3, 0.65, 1.2), 6, 3, leaf_d, leaf_l)
	canopy.ellipsoid(Vector3(-0.95, 3.5, 0.2), Vector3(0.95, 0.5, 0.9), 6, 3, MeshKit.shade(leaf_d, 0.9), leaf_l)
	canopy.ellipsoid(Vector3(1.05, 3.65, -0.2), Vector3(0.9, 0.5, 0.9), 6, 3, leaf_d, MeshKit.shade(leaf_l, 1.1))
	canopy.ellipsoid(Vector3(0.2, 4.15, -0.6), Vector3(0.8, 0.4, 0.75), 6, 3, leaf_d, MeshKit.shade(leaf_l, 1.15))
	var mesh: ArrayMesh = ArrayMesh.new()
	trunk.build_into(mesh, MeshKit.vcol_material())
	canopy.build_into(mesh, wind_material(&"canopy"))
	return mesh


static func _ipe() -> Mesh:
	var trunk: MeshKit = MeshKit.new()
	var canopy: MeshKit = MeshKit.new()
	var bark: Color = Color(0.34, 0.27, 0.21)
	var bark_hi: Color = Color(0.46, 0.38, 0.30)
	trunk.frustum(Vector3.ZERO, 0.32, 0.26, 1.7, 6, bark, bark_hi, false, false, Vector2(0.05, 0.0))
	trunk.frustum(Vector3(0.05, 1.7, 0), 0.26, 0.20, 1.6, 6, bark, bark_hi, true, false, Vector2(-0.08, 0.05))
	# forks into the crown
	for ang in [-1.0, 0.0, 1.0]:
		trunk.set_xf(Vector3(-0.03, 3.1, 0.05), Vector3(0, 120.0 * ang, 35 + absf(ang) * 5))
		trunk.frustum(Vector3.ZERO, 0.11, 0.05, 1.5, 5, bark, bark_hi, true, false)
	trunk.reset_xf()
	var y0: Color = Color(0.93, 0.70, 0.08)
	var y1: Color = Color(1.00, 0.86, 0.22)
	var y2: Color = Color(0.98, 0.78, 0.14)
	canopy.ellipsoid(Vector3(0.0, 5.6, 0.0), Vector3(1.9, 1.15, 1.8), 6, 3, y0, y1)
	canopy.ellipsoid(Vector3(-1.5, 4.9, 0.3), Vector3(1.3, 0.85, 1.25), 6, 3, MeshKit.shade(y0, 0.92), y2)
	canopy.ellipsoid(Vector3(1.55, 5.1, -0.3), Vector3(1.35, 0.9, 1.3), 6, 3, y0, y1)
	canopy.ellipsoid(Vector3(0.3, 4.7, 1.3), Vector3(1.2, 0.75, 1.1), 6, 3, MeshKit.shade(y0, 0.9), y2)
	canopy.ellipsoid(Vector3(-0.2, 6.35, -0.5), Vector3(1.2, 0.7, 1.15), 6, 3, y0, Color(1.0, 0.9, 0.35))
	var mesh: ArrayMesh = ArrayMesh.new()
	trunk.build_into(mesh, MeshKit.vcol_material())
	canopy.build_into(mesh, wind_material(&"canopy"))
	return mesh


static func _buriti() -> Mesh:
	var trunk: MeshKit = MeshKit.new()
	var crown: MeshKit = MeshKit.new()
	var bark: Color = Color(0.45, 0.38, 0.28)
	var ring: Color = Color(0.36, 0.30, 0.22)
	# slender ringed trunk
	for i in 4:
		var y: float = 2.7 * float(i)
		trunk.frustum(Vector3(0, y, 0), 0.25 - i * 0.012, 0.24 - i * 0.012, 2.7, 5, ring if i % 2 == 0 else bark, bark, i == 3, false, Vector2(0.0, 0.0))
	# fruit cluster
	trunk.ellipsoid(Vector3(0.1, 10.9, 0.15), Vector3(0.25, 0.22, 0.25), 5, 2, Color(0.55, 0.25, 0.12), Color(0.7, 0.32, 0.16))
	# fan of drooping fronds
	var r: RandomNumberGenerator = _rng("buriti")
	var fronds: int = 14
	for i in fronds:
		var a: float = TAU * float(i) / float(fronds) + r.randf() * 0.2
		var d: Vector3 = Vector3(cos(a), 0, sin(a))
		var side: Vector3 = Vector3(-sin(a), 0, cos(a))
		var base: Vector3 = Vector3(0, 10.85, 0)
		var m1: Vector3 = base + d * 1.5 + Vector3(0, 0.75, 0)
		var m2: Vector3 = base + d * 2.8 + Vector3(0, 0.45, 0)
		var tip: Vector3 = base + d * 3.5 + Vector3(0, -0.7, 0)
		var w1: float = 0.34
		var w2: float = 0.30
		var dk: Color = Color(0.13, 0.34, 0.14)
		var lt: Color = Color(0.28, 0.52, 0.22)
		crown.tri_double(base, m1 + side * w1, m1 - side * w1, dk, dk, dk)
		crown.tri_double(m1 + side * w1, m2 + side * w2, m2 - side * w2, dk, lt, lt)
		crown.tri_double(m1 + side * w1, m2 - side * w2, m1 - side * w1, dk, lt, dk)
		crown.tri_double(m2 + side * w2, tip, m2 - side * w2, lt, lt, lt)
	var mesh: ArrayMesh = ArrayMesh.new()
	trunk.build_into(mesh, MeshKit.vcol_material())
	crown.build_into(mesh, wind_material(&"canopy"))
	return mesh
