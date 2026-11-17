extends RefCounted
## HD water tower (prop `water_tank`): four slightly tapered timber posts with X bracing and ties, a plank
## platform, a fibre-cement tank with two steel straps and a conical lid, a front ladder and a blue PVC pipe
## coming down to a tap. 100% procedural, one mesh, one shared material (prop_materials.gd).
## Origin on the ground at the footprint centre, front = -Z (ladder side), 3 x 8 x 3 m.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")

const BASE_H: float = 1.22              # post half spacing at the ground
const TOP_H: float = 1.02               # ... and at the platform
const POST_TOP: float = 5.1
const DECK_Y: float = 5.16              # centre of the deck slab (0.12 thick)
const TANK_Y: float = 5.22
const TANK_R: float = 1.28
const SEGS: int = 14
const LADDER_Z0: float = -1.6
const LADDER_Z1: float = -1.42
const LADDER_TOP: float = 5.4

const AO_RAYS: int = 8
const AO_RADIUS: float = 0.8

static var _cache: Dictionary = {}


## { mesh: ArrayMesh, triangles, vertices, build_ms, materials }  (built once)
static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	_tower(m)
	_tank(m)
	_ladder(m)
	_pipe(m)
	var t1: int = Time.get_ticks_usec()
	var built: Dictionary = m.build()
	var t2: int = Time.get_ticks_usec()
	var tm: TriangleMesh = TriangleMesh.new()
	tm.create_from_faces(m.get_faces())
	HDMesh.bake_ao(built, tm, AO_RAYS, AO_RADIUS, 1.0, 0.5)
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


static func _paint(m: HDMesh, color: Color, rough: float, feature: int, grain: float = 0.0) -> void:
	m.paint(color, 0.0, rough, grain, feature)


## Square-section beam between two arbitrary points.
static func _beam(m: HDMesh, a: Vector3, b: Vector3, w: float, t: float) -> void:
	var d: Vector3 = (b - a).normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(d.y) > 0.9 else Vector3.UP
	var x: Vector3 = ref.cross(d).normalized()
	var y: Vector3 = d.cross(x)
	m.xf = Transform3D(Basis(x, y, d), (a + b) * 0.5)
	m.cbox(Vector3.ZERO, Vector3(w, t, a.distance_to(b)), 0.0)
	m.xf = Transform3D.IDENTITY


## Point on the post line (corner sx, sz) at height y.
static func _post_pt(sx: float, sz: float, y: float) -> Vector3:
	var h: float = lerpf(BASE_H, TOP_H, clampf(y / POST_TOP, 0.0, 1.0))
	return Vector3(sx * h, y, sz * h)


static func _tower(m: HDMesh) -> void:
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_beam(m, _post_pt(sx, sz, 0.0), _post_pt(sx, sz, POST_TOP), 0.18, 0.18)
	# horizontal ties and the X bracing of the two panels, on all four faces
	var levels: Array[float] = [0.4, 2.75, 4.95]
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	for li in range(1, 3):
		var y: float = levels[li]
		for sx2: float in [-1.0, 1.0]:
			_beam(m, _post_pt(sx2, -1.0, y), _post_pt(sx2, 1.0, y), 0.1, 0.12)
			_beam(m, _post_pt(-1.0, sx2, y), _post_pt(1.0, sx2, y), 0.1, 0.12)
	for pi in 2:
		var y0: float = levels[pi]
		var y1: float = levels[pi + 1]
		for sg: float in [-1.0, 1.0]:
			# faces z = +-1 (running along x) and x = +-1 (running along z)
			_beam(m, _post_pt(-1.0, sg, y0), _post_pt(1.0, sg, y1), 0.07, 0.07)
			_beam(m, _post_pt(1.0, sg, y0), _post_pt(-1.0, sg, y1), 0.07, 0.07)
			_beam(m, _post_pt(sg, -1.0, y0), _post_pt(sg, 1.0, y1), 0.07, 0.07)
			_beam(m, _post_pt(sg, 1.0, y0), _post_pt(sg, -1.0, y1), 0.07, 0.07)
	# platform: joists under a plank deck
	_paint(m, PM.WOOD_LIGHT, 0.9, PM.F_WOOD, PM.GRAIN_X)
	m.cbox(Vector3(0.0, DECK_Y, 0.0), Vector3(2.95, 0.12, 2.95), 0.015)


static func _tank(m: HDMesh) -> void:
	var r: float = TANK_R
	# body, split in chunks so the two steel straps take another surface
	_paint(m, PM.FIBRO_GREY, 0.86, PM.F_FIBRO)
	var org: Vector3 = Vector3(0.0, TANK_Y, 0.0)
	m.lathe([Vector3(0.0, r, 0.0), Vector3(0.43, r, 0.0)], SEGS, org, Vector3.UP)
	m.lathe([Vector3(0.54, r, 0.0), Vector3(1.33, r, 0.0)], SEGS, org, Vector3.UP)
	m.lathe([Vector3(1.44, r, 0.0), Vector3(1.92, r, 0.0), Vector3(1.94, r + 0.05, 0.0), Vector3(2.0, r + 0.05, 0.0)], SEGS, org, Vector3.UP)
	_paint(m, PM.ZINC_GREY * 0.7, 0.45, PM.F_ZINC)
	var sr: float = r + 0.04
	m.lathe([Vector3(0.43, r, 0.0), Vector3(0.45, sr, 0.0), Vector3(0.52, sr, 0.0), Vector3(0.54, r, 0.0)], SEGS, org, Vector3.UP)
	m.lathe([Vector3(1.33, r, 0.0), Vector3(1.35, sr, 0.0), Vector3(1.42, sr, 0.0), Vector3(1.44, r, 0.0)], SEGS, org, Vector3.UP)
	# conical lid with a small vent cap
	_paint(m, PM.FIBRO_GREY * 0.82, 0.85, PM.F_FIBRO)
	m.lathe([Vector3(2.0, r + 0.05, 0.0), Vector3(2.5, 0.22, 0.0), Vector3(2.53, 0.12, 0.0), Vector3(2.62, 0.12, 0.0), Vector3(2.66, 0.0, 0.0)], SEGS, org, Vector3.UP)


static func _ladder(m: HDMesh) -> void:
	_paint(m, PM.WOOD_LIGHT, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	for sx: float in [-1.0, 1.0]:
		_beam(m, Vector3(sx * 0.3, 0.0, LADDER_Z0), Vector3(sx * 0.3, LADDER_TOP, LADDER_Z1), 0.08, 0.07)
	_paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	var n: int = 10
	for i in n:
		var y: float = 0.45 + (LADDER_TOP - 0.7) * float(i) / float(n - 1)
		var z: float = lerpf(LADDER_Z0, LADDER_Z1, y / LADDER_TOP)
		m.cbox(Vector3(0.0, y, z), Vector3(0.6, 0.05, 0.05), 0.0)


static func _pipe(m: HDMesh) -> void:
	_paint(m, PM.PAINT_BLUE, 0.55, PM.F_PAINT)
	var p: Vector3 = Vector3(0.85, 0.0, -0.8)
	m.lathe([Vector3(0.3, 0.05, 0.0), Vector3(TANK_Y - 0.1, 0.05, 0.0)], 8, p, Vector3.UP)
	m.lathe([Vector3(0.0, 0.05, 0.0), Vector3(0.55, 0.05, 0.0)], 8, p + Vector3(0.0, 0.3, 0.0), Vector3.RIGHT)
	# tap
	_paint(m, PM.ZINC_GREY * 0.7, 0.45, PM.F_ZINC)
	m.cbox(p + Vector3(0.6, 0.24, 0.0), Vector3(0.08, 0.16, 0.08), 0.0)
