extends RefCounted
## Procedural flora and crop meshes for the Mato Grosso cerrado. No class_name (loaded by path).
## Usage: var m: Mesh = lib.call(&"build_mesh", &"ipe"). Origin at the base, Y up. null for unknown ids.

const WIND_SHADER: String = "res://assets/shaders/foliage_wind.gdshader"

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
		&"grass_tuft": mesh = _grass_tuft()
		&"shrub": mesh = _shrub()
		&"cerrado_tree": mesh = _cerrado_tree()
		&"ipe": mesh = _ipe()
		&"buriti": mesh = _buriti()
		&"termite_mound": mesh = _termite_mound()
		&"soy_patch": mesh = _soy_patch()
		&"soy_eaten": mesh = _soy_eaten()
		&"corn_patch": mesh = _corn_patch()
		&"corn_eaten": mesh = _corn_eaten()
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


# --- grass -----------------------------------------------------------------------------------

static func _grass_tuft() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var r: RandomNumberGenerator = _rng("grass")
	var base: Color = Color(0.52, 0.47, 0.22)
	var tip: Color = Color(0.86, 0.76, 0.40)
	# 4 double-sided blades = 8 triangles
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + r.randf() * 0.4
		var h: float = 0.3 + r.randf() * 0.12
		var lean: float = 0.10 + r.randf() * 0.10
		var rad: float = 0.03 + r.randf() * 0.04
		var c: Vector3 = Vector3(cos(a), 0, sin(a))
		var side: Vector3 = Vector3(-sin(a), 0, cos(a)) * 0.04
		var p: Vector3 = c * rad
		k.tri_double(p - side, p + side, p + c * lean + Vector3(0, h, 0), base, base, tip)
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, wind_material(&"grass"))
	return mesh


static func _shrub() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var dark: Color = Color(0.22, 0.32, 0.14)
	var light: Color = Color(0.42, 0.50, 0.22)
	k.ellipsoid(Vector3(-0.28, 0.42, 0.05), Vector3(0.45, 0.42, 0.42), 5, 3, dark, light)
	k.ellipsoid(Vector3(0.30, 0.38, -0.08), Vector3(0.42, 0.38, 0.40), 5, 3, MeshKit.shade(dark, 1.1), MeshKit.shade(light, 0.92))
	k.ellipsoid(Vector3(0.02, 0.62, 0.0), Vector3(0.38, 0.38, 0.36), 5, 3, dark, MeshKit.shade(light, 1.08))
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, wind_material(&"shrub"))
	return mesh


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


static func _termite_mound() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var base: Color = Color(0.55, 0.23, 0.14)
	var top: Color = Color(0.72, 0.36, 0.22)
	k.frustum(Vector3.ZERO, 0.62, 0.46, 0.5, 7, MeshKit.shade(base, 0.85), base, false, false, Vector2(0.0, 0.0))
	k.frustum(Vector3(0, 0.5, 0), 0.46, 0.30, 0.45, 7, base, top, false, false, Vector2(0.04, -0.03))
	k.frustum(Vector3(0.04, 0.95, -0.03), 0.30, 0.0, 0.25, 7, top, MeshKit.shade(top, 1.1), false, false, Vector2(0.02, 0.0))
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, MeshKit.vcol_material())
	return mesh


# --- crops -----------------------------------------------------------------------------------

## Triangular-prism row (6 triangles, no bottom). Runs along X.
static func _row(k: MeshKit, center_z: float, length: float, width: float, height: float, base: Color, top: Color) -> void:
	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var c: Vector3 = Vector3(0, height * 0.4, center_z)
	var b0: Vector3 = Vector3(-hl, 0, center_z - hw)
	var b1: Vector3 = Vector3(hl, 0, center_z - hw)
	var b2: Vector3 = Vector3(hl, 0, center_z + hw)
	var b3: Vector3 = Vector3(-hl, 0, center_z + hw)
	var t0: Vector3 = Vector3(-hl * 0.92, height, center_z)
	var t1: Vector3 = Vector3(hl * 0.92, height, center_z)
	k.tri(b0, b1, t1, base, base, top, c)
	k.tri(b0, t1, t0, base, top, top, c)
	k.tri(b2, b3, t0, base, base, top, c)
	k.tri(b2, t0, t1, base, top, top, c)
	k.tri(b0, t0, b3, base, top, base, c)
	k.tri(b1, b2, t1, base, base, top, c)


static func _soy_patch() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var base: Color = Color(0.20, 0.42, 0.14)
	var top: Color = Color(0.46, 0.72, 0.24)
	# two rows of three bushy plants (6 cones x 4 tris = 24 tris); bare earth shows between rows
	var i: int = 0
	for z: float in [-0.5, 0.5]:
		for x: float in [-0.67, 0.0, 0.67]:
			k.set_xf(Vector3(x, 0.0, z), Vector3(0.0, 45.0 * float(i % 2) + 12.0 * float(i), 0.0))
			k.frustum(Vector3.ZERO, 0.40, 0.0, 0.62, 4, base, top, false, false)
			k.reset_xf()
			i += 1
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, wind_material(&"crop"))
	return mesh


static func _soy_eaten() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var base: Color = Color(0.30, 0.24, 0.12)
	var top: Color = Color(0.48, 0.42, 0.18)
	_row(k, -0.55, 1.9, 0.7, 0.15, base, top)
	_row(k, 0.55, 1.8, 0.7, 0.13, base, top)
	k.tri_double(Vector3(-0.3, 0.02, 0.0), Vector3(0.2, 0.02, -0.2), Vector3(0.3, 0.05, 0.15), Color(0.26, 0.3, 0.1), Color(0.3, 0.34, 0.12), Color(0.26, 0.3, 0.1))
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, wind_material(&"crop"))
	return mesh


static func _corn_patch() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var stalk_b: Color = Color(0.45, 0.50, 0.16)
	var stalk_t: Color = Color(0.78, 0.74, 0.28)
	var spots: Array[Vector2] = [Vector2(-0.55, -0.5), Vector2(0.55, -0.45), Vector2(-0.5, 0.55), Vector2(0.5, 0.5)]
	for s in spots:
		k.frustum(Vector3(s.x, 0, s.y), 0.17, 0.05, 2.0, 3, stalk_b, stalk_t, false, false)
	# long drooping leaves (double sided)
	var leaf_b: Color = Color(0.42, 0.55, 0.16)
	var leaf_t: Color = Color(0.82, 0.78, 0.30)
	var lp: Array = [
		[Vector3(0, 1.3, -0.5), Vector3(-1.0, 0.95, -0.7), Vector3(-0.2, 1.1, -0.15)],
		[Vector3(0.1, 1.5, 0.5), Vector3(1.0, 1.0, 0.8), Vector3(0.25, 1.1, 0.2)],
		[Vector3(0.0, 1.7, 0.0), Vector3(0.1, 1.2, -0.9), Vector3(0.35, 1.45, -0.2)],
	]
	for l in lp:
		k.tri_double(l[0], l[1], l[2], leaf_b, leaf_t, leaf_b)
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, wind_material(&"crop"))
	return mesh


static func _corn_eaten() -> Mesh:
	var k: MeshKit = MeshKit.new()
	var b: Color = Color(0.36, 0.32, 0.14)
	var t: Color = Color(0.66, 0.60, 0.26)
	var spots: Array[Vector3] = [Vector3(-0.5, 0, -0.4), Vector3(0.45, 0, 0.1), Vector3(-0.1, 0, 0.6)]
	for s in spots:
		k.frustum(s, 0.16, 0.07, 0.5, 3, b, t, false, false, Vector2(0.06, 0.04))
	k.tri_double(Vector3(-0.8, 0.03, 0.3), Vector3(-0.1, 0.03, 0.0), Vector3(-0.4, 0.07, 0.7), Color(0.30, 0.34, 0.12), Color(0.5, 0.5, 0.2), Color(0.3, 0.34, 0.12))
	var mesh: ArrayMesh = ArrayMesh.new()
	k.build_into(mesh, wind_material(&"crop"))
	return mesh
