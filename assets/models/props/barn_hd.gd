extends RefCounted
## HD farm barn (prop `barn`): Mato Grosso machine/hay shed open on the front (-Z). Timber frame (posts, front
## plate, king-post trusses, purlins), two-pitch corrugated zinc roof with rust, vertical-board back and gable
## walls on a concrete plinth, earth floor, hay bales, a stall rail and a feed trough inside for scale.
## 100% procedural, one mesh, one shared material (prop_materials.gd). Origin on the ground at the footprint
## centre, front = -Z, 16 x 7 x 10 m. The interior (x +-7.85, z -4.7..4.8) is kept free in the middle for the
## corn stock of the horde mode (barn_corn.gd).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")

# roof (gable along X): half depth, half length, underside height at the eave, pitch, slab thickness
const EAVE_Z: float = 5.4
const EAVE_X: float = 8.4
const EAVE_Y: float = 4.9
const RISE: float = 2.0
const PITCH: float = RISE / EAVE_Z
const SLAB: float = 0.09
const SLOPE_K: float = 1.0655           # sqrt(1 + PITCH^2)

# walls
const WALL_X: float = 7.9               # centre of the gable walls
const WALL_T: float = 0.1
const WALL_Z0: float = -4.85
const WALL_Z1: float = 4.91
const POST_Z: float = -4.7
const POST_XS: Array[float] = [-7.6, -3.8, 0.0, 3.8, 7.6]

const AO_RAYS: int = 8
const AO_RADIUS: float = 1.2

static var _cache: Dictionary = {}


## { mesh: ArrayMesh, triangles, vertices, build_ms, materials }  (built once)
static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func roof_u(z: float) -> float:
	return EAVE_Y + PITCH * (EAVE_Z - absf(z))


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	_ground(m)
	_walls(m)
	_frame(m)
	_roof(m)
	_interior(m)
	var t1: int = Time.get_ticks_usec()
	var built: Dictionary = m.build()
	var t2: int = Time.get_ticks_usec()
	var tm: TriangleMesh = TriangleMesh.new()
	tm.create_from_faces(m.get_faces())
	HDMesh.bake_ao(built, tm, AO_RAYS, AO_RADIUS, 1.0, 0.45)
	var t3: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, PM.surfaces())
	var verts: int = 0
	for si: int in built["surfaces"]:
		verts += (built["surfaces"][si]["pos"] as PackedVector3Array).size()
	return {
		"mesh": mesh, "triangles": m.triangle_count(), "vertices": verts, "materials": 1,
		"build_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"emit_ms": float(t1 - t0) / 1000.0, "weld_ms": float(t2 - t1) / 1000.0, "ao_ms": float(t3 - t2) / 1000.0,
	}


# --- brushes -----------------------------------------------------------------------------------------

static func _paint(m: HDMesh, color: Color, rough: float, feature: int, grain: float = 0.0) -> void:
	m.paint(color, 0.0, rough, grain, feature)


static func _box(m: HDMesh, c: Vector3, size: Vector3, bevel: float = 0.0) -> void:
	m.cbox(c, size, bevel)


static func _rbox(m: HDMesh, c: Vector3, size: Vector3, basis: Basis, bevel: float = 0.0) -> void:
	m.xf = Transform3D(basis, c)
	m.cbox(Vector3.ZERO, size, bevel)
	m.xf = Transform3D.IDENTITY


## Beam between two points in a YZ plane (same x): `wx` wide along X, `wt` thick across the run.
static func _beam(m: HDMesh, a: Vector3, b: Vector3, wx: float, wt: float) -> void:
	var d: Vector3 = (b - a).normalized()
	var perp: Vector3 = d.cross(Vector3.RIGHT)
	_rbox(m, (a + b) * 0.5, Vector3(wx, wt, a.distance_to(b)), Basis(Vector3.RIGHT, perp, d))


## Convex polygon, fan triangulated, front face towards `out`.
static func _panel(m: HDMesh, pts: Array[Vector3], out: Vector3) -> void:
	for i in range(1, pts.size() - 1):
		m.tri(pts[0], pts[i], pts[i + 1], out)


## Basis lying on a roof slope: local X along the ridge, local Z down/up the slope, local Y the slope normal.
## front = true is the -Z slope (rising towards +Z).
static func _slope_basis(front: bool) -> Basis:
	var d: Vector3 = Vector3(0.0, PITCH, 1.0) / SLOPE_K if front else Vector3(0.0, -PITCH, 1.0) / SLOPE_K
	return Basis(Vector3.RIGHT, d.cross(Vector3.RIGHT), d)


static func _slope_normal(front: bool) -> Vector3:
	return _slope_basis(front).y


# --- ground ------------------------------------------------------------------------------------------

static func _ground(m: HDMesh) -> void:
	_paint(m, PM.EARTH, 1.0, PM.F_EARTH)
	m.begin_part()
	m.quad(Vector3(-7.85, 0.02, POST_Z), Vector3(7.85, 0.02, POST_Z), Vector3(7.85, 0.02, 4.81), Vector3(-7.85, 0.02, 4.81), Vector3.UP)
	# cement apron under the front eave
	_paint(m, PM.CEMENT_GREY, 0.75, PM.F_CEMENT)
	_box(m, Vector3(0.0, 0.04, -5.02), Vector3(16.0, 0.08, 0.76), 0.012)
	# plinth under the walls
	_box(m, Vector3(0.0, 0.17, 4.86), Vector3(16.1, 0.34, 0.2), 0.01)
	for sx: float in [-1.0, 1.0]:
		_box(m, Vector3(sx * WALL_X, 0.17, (WALL_Z0 + WALL_Z1) * 0.5), Vector3(0.2, 0.34, WALL_Z1 - WALL_Z0), 0.01)


# --- walls -------------------------------------------------------------------------------------------

static func _walls(m: HDMesh) -> void:
	_paint(m, PM.BARN_RED, 0.92, PM.F_PLANK)
	# back wall
	m.begin_part()
	_box(m, Vector3(0.0, 2.55, 4.86), Vector3(15.8, 5.1, WALL_T), 0.0)
	# gable walls: pentagons that stop under the roof, both faces
	for sx: float in [-1.0, 1.0]:
		var ph: Array[Vector3] = []
		var zs: Array[float] = [WALL_Z0, WALL_Z1]
		var xo: float = sx * (WALL_X + WALL_T * 0.5)
		var xi: float = sx * (WALL_X - WALL_T * 0.5)
		for x: float in [xo, xi]:
			ph.clear()
			ph.append(Vector3(x, 0.0, WALL_Z0))
			ph.append(Vector3(x, 0.0, WALL_Z1))
			ph.append(Vector3(x, roof_u(WALL_Z1) - 0.01, WALL_Z1))
			ph.append(Vector3(x, EAVE_Y + RISE - 0.02, 0.0))
			ph.append(Vector3(x, roof_u(WALL_Z0) - 0.01, WALL_Z0))
			m.begin_part()
			var face: Vector3 = Vector3(sx, 0.0, 0.0) if x == xo else Vector3(-sx, 0.0, 0.0)
			if x == xo:
				_panel(m, ph, face)
			else:
				var rev: Array[Vector3] = []
				for i in range(ph.size() - 1, -1, -1):
					rev.append(ph[i])
				_panel(m, rev, face)
		# closing strip on the open front edge
		m.begin_part()
		m.quad(Vector3(xi, 0.0, WALL_Z0), Vector3(xo, 0.0, WALL_Z0), Vector3(xo, roof_u(WALL_Z0) - 0.01, WALL_Z0), Vector3(xi, roof_u(WALL_Z0) - 0.01, WALL_Z0), Vector3.FORWARD)
	# horizontal girts (travessas) on the outside, grey timber
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	for y: float in [1.3, 2.6, 3.9]:
		_box(m, Vector3(0.0, y, 4.96), Vector3(16.1, 0.11, 0.06), 0.0)
		for sx2: float in [-1.0, 1.0]:
			_box(m, Vector3(sx2 * (WALL_X + 0.08), y, (WALL_Z0 + WALL_Z1) * 0.5), Vector3(0.06, 0.11, WALL_Z1 - WALL_Z0), 0.0)
	# corner boards
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	for sx3: float in [-1.0, 1.0]:
		_box(m, Vector3(sx3 * (WALL_X + 0.07), 2.5, 4.98), Vector3(0.18, 5.0, 0.12), 0.0)


# --- timber frame ------------------------------------------------------------------------------------

static func _frame(m: HDMesh) -> void:
	# front posts (square, chamfered) and the plate they carry
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	for x: float in POST_XS:
		_box(m, Vector3(x, 2.45, POST_Z), Vector3(0.28, 4.9, 0.28), 0.02)
		_box(m, Vector3(x, 2.45, 4.7), Vector3(0.22, 4.9, 0.22), 0.0)
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	_box(m, Vector3(0.0, 4.7, POST_Z), Vector3(16.0, 0.3, 0.26), 0.015)
	# 45 degree knee braces under the plate
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	var braces: Array = [[-7.6, 1.0], [-3.8, -1.0], [-3.8, 1.0], [0.0, -1.0], [0.0, 1.0], [3.8, -1.0], [3.8, 1.0], [7.6, -1.0]]
	for b: Array in braces:
		var side: float = b[1]
		var c: Vector3 = Vector3(float(b[0]) + side * 0.55, 4.55 - 0.40, POST_Z - 0.01)
		_rbox(m, c, Vector3(0.12, 1.15, 0.12), Basis(Vector3(0, 0, 1), -side * deg_to_rad(45.0)))
	# king-post trusses on every post line
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Z)
	for x2: float in POST_XS:
		_box(m, Vector3(x2, 4.72, 0.0), Vector3(0.18, 0.2, 9.5), 0.0)
		_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Y)
		_box(m, Vector3(x2, (4.82 + 6.62) * 0.5, 0.0), Vector3(0.17, 1.8, 0.17), 0.0)
		_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Z)
		for sz: float in [-1.0, 1.0]:
			var front: bool = sz < 0.0
			var nrm: Vector3 = _slope_normal(front)
			var za: float = 5.25 * sz
			var zb: float = 0.06 * sz
			var a: Vector3 = Vector3(x2, roof_u(za), za) - nrm * 0.19
			var b2: Vector3 = Vector3(x2, roof_u(zb), zb) - nrm * 0.19
			_beam(m, a, b2, 0.14, 0.18)
			_beam(m, Vector3(x2, 4.82, 2.9 * sz), Vector3(x2, 6.05, 0.05 * sz), 0.12, 0.14)
	# ridge beam and purlins
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	_box(m, Vector3(0.0, 6.62, 0.0), Vector3(16.2, 0.16, 0.18), 0.0)
	for sz2: float in [-1.0, 1.0]:
		var front2: bool = sz2 < 0.0
		var basis: Basis = _slope_basis(front2)
		for z: float in [1.9, 3.8, 5.1]:
			var zz: float = z * sz2
			var under: Vector3 = Vector3(0.0, roof_u(zz), zz)
			_rbox(m, under - basis.y * 0.05, Vector3(16.5, 0.1, 0.14), basis)


# --- roof --------------------------------------------------------------------------------------------

static func _roof(m: HDMesh) -> void:
	var rl: float = EAVE_Z * SLOPE_K       # slope length
	for pass_i in 2:
		var top: bool = pass_i == 0
		var up: float = SLAB if top else 0.0
		var dir: Vector3 = Vector3.UP if top else Vector3.DOWN
		if top:
			_paint(m, PM.ROOF_ZINC, 0.45, PM.F_ROOF_ZINC)
		else:
			_paint(m, PM.ROOF_ZINC * 0.55, 0.6, PM.F_ROOF_ZINC)
		m.begin_part()
		m.quad(Vector3(-EAVE_X, EAVE_Y + up, -EAVE_Z), Vector3(EAVE_X, EAVE_Y + up, -EAVE_Z), Vector3(EAVE_X, EAVE_Y + RISE + up, 0.0), Vector3(-EAVE_X, EAVE_Y + RISE + up, 0.0), dir,
			Vector2(-EAVE_X, 0.0), Vector2(EAVE_X, 0.0), Vector2(EAVE_X, rl), Vector2(-EAVE_X, rl))
		m.begin_part()
		m.quad(Vector3(EAVE_X, EAVE_Y + up, EAVE_Z), Vector3(-EAVE_X, EAVE_Y + up, EAVE_Z), Vector3(-EAVE_X, EAVE_Y + RISE + up, 0.0), Vector3(EAVE_X, EAVE_Y + RISE + up, 0.0), dir,
			Vector2(EAVE_X, 0.0), Vector2(-EAVE_X, 0.0), Vector2(-EAVE_X, rl), Vector2(EAVE_X, rl))
	# thickness: eave edges and barge edges
	_paint(m, PM.ROOF_ZINC * 0.8, 0.6, PM.F_ROOF_ZINC)
	m.begin_part()
	m.quad(Vector3(-EAVE_X, EAVE_Y, -EAVE_Z), Vector3(EAVE_X, EAVE_Y, -EAVE_Z), Vector3(EAVE_X, EAVE_Y + SLAB, -EAVE_Z), Vector3(-EAVE_X, EAVE_Y + SLAB, -EAVE_Z), Vector3.FORWARD)
	m.begin_part()
	m.quad(Vector3(EAVE_X, EAVE_Y, EAVE_Z), Vector3(-EAVE_X, EAVE_Y, EAVE_Z), Vector3(-EAVE_X, EAVE_Y + SLAB, EAVE_Z), Vector3(EAVE_X, EAVE_Y + SLAB, EAVE_Z), Vector3.BACK)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.begin_part()
			m.quad(Vector3(sx * EAVE_X, EAVE_Y, sz * EAVE_Z), Vector3(sx * EAVE_X, EAVE_Y, 0.0), Vector3(sx * EAVE_X, EAVE_Y + RISE + SLAB, 0.0), Vector3(sx * EAVE_X, EAVE_Y + SLAB, sz * EAVE_Z), Vector3(sx, 0.0, 0.0))
	# ridge cap: two slabs along the slopes
	_paint(m, PM.ROOF_ZINC * 0.9, 0.5, PM.F_ZINC)
	for sz2: float in [-1.0, 1.0]:
		var basis: Basis = _slope_basis(sz2 < 0.0)
		var zc: float = 0.15 * sz2
		var c: Vector3 = Vector3(0.0, EAVE_Y + PITCH * (EAVE_Z - 0.15) + SLAB, zc) + basis.y * 0.022
		_rbox(m, c, Vector3(16.9, 0.04, 0.34), basis)


# --- interior: bales, stall rail, trough ---------------------------------------------------------------

static func _bale(m: HDMesh, c: Vector3, long_x: bool) -> void:
	var size: Vector3 = Vector3(1.1, 0.5, 0.46) if long_x else Vector3(0.46, 0.5, 1.1)
	_paint(m, PM.HAY, 1.0, PM.F_HAY)
	_box(m, c, size, 0.035)
	_paint(m, PM.TWINE, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	if long_x:
		for o: float in [-0.3, 0.3]:
			_box(m, c + Vector3(o, 0.0, 0.0), Vector3(0.03, 0.51, 0.47), 0.0)
	else:
		for o2: float in [-0.3, 0.3]:
			_box(m, c + Vector3(0.0, 0.0, o2), Vector3(0.47, 0.51, 0.03), 0.0)


static func _interior(m: HDMesh) -> void:
	# stack of bales in the front-left corner
	var hx: float = -6.85
	for i in 3:
		_bale(m, Vector3(hx, 0.27, -3.95 + 0.48 * i), true)
	for i2 in 2:
		_bale(m, Vector3(hx + 0.08, 0.78, -3.72 + 0.48 * i2), true)
	_bale(m, Vector3(hx - 0.05, 1.29, -3.48), true)
	# a few bales in the back-right corner
	_bale(m, Vector3(6.85, 0.27, 3.95), true)
	_bale(m, Vector3(6.85, 0.27, 3.47), true)
	_bale(m, Vector3(6.9, 0.78, 3.7), true)
	# stall rail along the right side
	_paint(m, PM.WOOD_LIGHT, 0.88, PM.F_WOOD, PM.GRAIN_Y)
	for z: float in [-4.0, -2.5, -1.0, 0.5, 2.0]:
		_box(m, Vector3(6.3, 0.85, z), Vector3(0.14, 1.7, 0.14), 0.0)
	_paint(m, PM.WOOD_LIGHT, 0.88, PM.F_WOOD, PM.GRAIN_Z)
	for y: float in [0.5, 1.0, 1.5]:
		_box(m, Vector3(6.3, y, -1.0), Vector3(0.08, 0.14, 6.0), 0.0)
	# feed trough against the right wall
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Z)
	var tc: Vector3 = Vector3(7.3, 0.0, -1.0)
	_box(m, tc + Vector3(0.0, 0.42, 0.0), Vector3(0.5, 0.05, 2.4), 0.0)
	_box(m, tc + Vector3(-0.23, 0.58, 0.0), Vector3(0.05, 0.32, 2.4), 0.0)
	_box(m, tc + Vector3(0.23, 0.58, 0.0), Vector3(0.05, 0.32, 2.4), 0.0)
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	for sz: float in [-1.0, 1.0]:
		_box(m, tc + Vector3(0.0, 0.58, 1.18 * sz), Vector3(0.5, 0.32, 0.05), 0.0)
		_box(m, tc + Vector3(0.0, 0.2, 0.85 * sz), Vector3(0.5, 0.4, 0.1), 0.0)
