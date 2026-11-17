extends RefCounted
## HD fazenda headquarters (prop `farmhouse`): whitewashed masonry with a red-earth skirt, clay hip roof with
## ridge and hip caps, front porch (-Z) with timber posts, brackets, rail and steps, recessed doors and
## windows with louvered shutters, chimney. 100% procedural, one mesh, one shared material (prop_materials.gd).
## Origin on the ground at the footprint centre, front = -Z, 12 x 6 x 8 m.
##
## The roof is the master shape: roof_u(x, z) is the height of its underside. Walls stop exactly under it,
## so the front wall (under the long porch slope) is taller than the back wall.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")

# roof (hip): eave rectangle, pitch (rise per metre of run), underside height at the eave, slab thickness
const EAVE_X: float = 6.0
const EAVE_Z: float = 4.0
const PITCH: float = 0.5
const EAVE_Y: float = 2.55
const SLAB: float = 0.12
const SLOPE_K: float = 1.118034            # sqrt(1 + PITCH^2): slope length per metre of run
const TILE_PITCH: float = 0.30             # keep in sync with prop_hd.gdshader

# walls
const WALL_X: float = 5.4
const WALL_FRONT_Z: float = -1.4
const WALL_BACK_Z: float = 3.5
const REVEAL: float = 0.16                 # window / door recess depth

# porch
const FLOOR_H: float = 0.38
const POST_Z: float = -3.4
const BEAM_Y0: float = 2.625

const AO_RAYS: int = 8
const AO_RADIUS: float = 0.6

static var _cache: Dictionary = {}


## { mesh: ArrayMesh, triangles, vertices, build_ms, materials }  (built once)
static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func roof_u(x: float, z: float) -> float:
	return EAVE_Y + PITCH * minf(EAVE_X - absf(x), EAVE_Z - absf(z))


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	_walls(m)
	_roof(m)
	_porch(m)
	_chimney(m)
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


# --- brushes -----------------------------------------------------------------------------------------

static func _paint(m: HDMesh, color: Color, rough: float, feature: int, grain: float = 0.0) -> void:
	m.paint(color, 0.0, rough, grain, feature)


static func _box(m: HDMesh, c: Vector3, size: Vector3, bevel: float = 0.0) -> void:
	m.cbox(c, size, bevel)


static func _rbox(m: HDMesh, c: Vector3, size: Vector3, basis: Basis, bevel: float = 0.0) -> void:
	m.xf = Transform3D(basis, c)
	m.cbox(Vector3.ZERO, size, bevel)
	m.xf = Transform3D.IDENTITY


# --- walls -------------------------------------------------------------------------------------------

## A wall panel in a local (s along, y up) frame.
class Wall extends RefCounted:
	var p0: Vector3
	var along: Vector3
	var out: Vector3
	var shade_k: float

	func _init(origin: Vector3, along_dir: Vector3, out_dir: Vector3, shade_length: float) -> void:
		p0 = origin
		along = along_dir
		out = out_dir
		shade_k = shade_length

	func p(s: float, y: float) -> Vector3:
		return p0 + along * s + Vector3.UP * y

	func top(s: float) -> float:
		var q: Vector3 = p0 + along * s
		return EAVE_Y + PITCH * minf(EAVE_X - absf(q.x), EAVE_Z - absf(q.z))

	## UV of a wall point: metres along, depth below the roof edge in units of the overhang shade length.
	func uv(s: float, y: float) -> Vector2:
		return Vector2(s, maxf(top(s) - y, 0.0) / shade_k + 0.002)


static func _wall(m: HDMesh, w: Wall, length: float, openings: Array, breaks: Array) -> void:
	m.begin_part()
	_paint(m, PM.WHITEWASH, 0.92, PM.F_PLASTER)
	var cuts: Array = [0.0, length]
	for o: Dictionary in openings:
		cuts.append(o["s0"])
		cuts.append(o["s1"])
	cuts.append_array(breaks)
	cuts.sort()
	for i in cuts.size() - 1:
		var sa: float = cuts[i]
		var sb: float = cuts[i + 1]
		if sb - sa < 1e-4:
			continue
		var hole: Dictionary = {}
		for o: Dictionary in openings:
			if o["s0"] <= sa + 1e-4 and o["s1"] >= sb - 1e-4:
				hole = o
		var lo_y: float = 0.0
		if not hole.is_empty():
			var y0: float = hole["y0"]
			if y0 > 0.001:
				_wall_quad(m, w, sa, sb, 0.0, 0.0, y0, y0)
			lo_y = hole["y1"]
		_wall_quad(m, w, sa, sb, lo_y, lo_y, w.top(sa), w.top(sb))
	for o: Dictionary in openings:
		var s0: float = o["s0"]
		var s1: float = o["s1"]
		var y0: float = o["y0"]
		var y1: float = o["y1"]
		var d: Vector3 = w.out * REVEAL
		var shade: float = 0.30
		var uv_a: Vector2 = Vector2(s0, shade)
		var uv_b: Vector2 = Vector2(s1, shade)
		m.quad(w.p(s0, y0), w.p(s0, y1), w.p(s0, y1) - d, w.p(s0, y0) - d, w.along, uv_a, uv_a, Vector2(s0 + REVEAL, shade), Vector2(s0 + REVEAL, shade))
		m.quad(w.p(s1, y0), w.p(s1, y1), w.p(s1, y1) - d, w.p(s1, y0) - d, -w.along, uv_b, uv_b, Vector2(s1 - REVEAL, shade), Vector2(s1 - REVEAL, shade))
		m.quad(w.p(s0, y1), w.p(s1, y1), w.p(s1, y1) - d, w.p(s0, y1) - d, Vector3.DOWN, uv_a, uv_b, uv_b, uv_a)
		var lit: Vector2 = Vector2(0.0, 1.2)
		m.quad(w.p(s0, y0), w.p(s1, y0), w.p(s1, y0) - d, w.p(s0, y0) - d, Vector3.UP, lit, lit, lit, lit)


static func _wall_quad(m: HDMesh, w: Wall, sa: float, sb: float, yla: float, ylb: float, yta: float, ytb: float) -> void:
	if yta - yla < 1e-4 and ytb - ylb < 1e-4:
		return
	m.quad(w.p(sa, yla), w.p(sb, ylb), w.p(sb, ytb), w.p(sa, yta), w.out, w.uv(sa, yla), w.uv(sb, ylb), w.uv(sb, ytb), w.uv(sa, yta))


static func _opening(sc: float, width: float, y0: float, y1: float) -> Dictionary:
	return {"s0": sc - width * 0.5, "s1": sc + width * 0.5, "y0": y0, "y1": y1}


static func _walls(m: HDMesh) -> void:
	var span: float = WALL_X * 2.0
	var depth: float = WALL_BACK_Z - WALL_FRONT_Z
	# front (porch side)
	var front: Wall = Wall.new(Vector3(-WALL_X, 0.0, WALL_FRONT_Z), Vector3.RIGHT, Vector3.FORWARD, 2.2)
	var f_open: Array = [_opening(WALL_X, 1.25, FLOOR_H, 2.68)]
	for x: float in [-4.2, -2.4, 2.4, 4.2]:
		f_open.append(_opening(WALL_X + x, 1.2, 1.3, 2.6))
	_wall(m, front, span, f_open, [2.0, 8.8])
	# back
	var back: Wall = Wall.new(Vector3(-WALL_X, 0.0, WALL_BACK_Z), Vector3.RIGHT, Vector3.BACK, 0.9)
	var b_open: Array = [_opening(WALL_X, 1.1, 0.22, 2.35)]
	for x: float in [-4.1, -2.1, 2.1, 4.1]:
		b_open.append(_opening(WALL_X + x, 1.1, 1.0, 2.3))
	_wall(m, back, span, b_open, [])
	# sides
	var right: Wall = Wall.new(Vector3(WALL_X, 0.0, WALL_FRONT_Z), Vector3.BACK, Vector3.RIGHT, 1.0)
	var left: Wall = Wall.new(Vector3(-WALL_X, 0.0, WALL_FRONT_Z), Vector3.BACK, Vector3.LEFT, 1.0)
	var s_open: Array = [_opening(1.9, 1.1, 1.0, 2.3), _opening(3.9, 1.1, 1.0, 2.3)]
	_wall(m, right, depth, s_open, [4.8])
	_wall(m, left, depth, s_open, [4.8])
	# openings: details
	var open_deg: Array = [100.0, 96.0, 104.0, 98.0]
	for i in 4:
		_window(m, front, f_open[i + 1], open_deg[i])
	for i in 4:
		_window(m, back, b_open[i + 1], 0.0 if i % 2 == 0 else 55.0)
	for i in 2:
		_window(m, right, s_open[i], 92.0 + 8.0 * i)
		_window(m, left, s_open[i], 0.0 if i == 0 else 100.0)
	_door(m, front, f_open[0], true)
	_door(m, back, b_open[0], false)
	# back door step
	_paint(m, PM.CEMENT_GREY, 0.8, PM.F_CEMENT)
	_box(m, Vector3(0.0, 0.1, 3.76), Vector3(1.7, 0.2, 0.52), 0.015)


## Flat frame (casing) around an opening: front face ring and outer sides, standing `prot` proud of the wall.
static func _casing(m: HDMesh, w: Wall, s0: float, s1: float, y0: float, y1: float, b: float, prot: float, with_bottom: bool) -> void:
	var o: Vector3 = w.out * prot
	var a0: float = s0 - b
	var a1: float = s1 + b
	var yb: float = y0 - b if with_bottom else y0
	var yt: float = y1 + b
	m.begin_part()
	# front ring
	m.quad(w.p(a0, yt) + o, w.p(a1, yt) + o, w.p(a1, y1) + o, w.p(a0, y1) + o, w.out)
	m.quad(w.p(a0, y1) + o, w.p(s0, y1) + o, w.p(s0, yb) + o, w.p(a0, yb) + o, w.out)
	m.quad(w.p(s1, y1) + o, w.p(a1, y1) + o, w.p(a1, yb) + o, w.p(s1, yb) + o, w.out)
	if with_bottom:
		m.quad(w.p(s0, y0) + o, w.p(s1, y0) + o, w.p(s1, yb) + o, w.p(s0, yb) + o, w.out)
	# outer sides
	m.quad(w.p(a0, yt), w.p(a1, yt), w.p(a1, yt) + o, w.p(a0, yt) + o, Vector3.UP)
	m.quad(w.p(a0, yb), w.p(a0, yt), w.p(a0, yt) + o, w.p(a0, yb) + o, -w.along)
	m.quad(w.p(a1, yb), w.p(a1, yt), w.p(a1, yt) + o, w.p(a1, yb) + o, w.along)
	if with_bottom:
		m.quad(w.p(a0, yb), w.p(a1, yb), w.p(a1, yb) + o, w.p(a0, yb) + o, Vector3.DOWN)


static func _window(m: HDMesh, w: Wall, o: Dictionary, open_deg: float) -> void:
	var s0: float = o["s0"]
	var s1: float = o["s1"]
	var y0: float = o["y0"]
	var y1: float = o["y1"]
	var gd: Vector3 = w.out * 0.11
	_paint(m, PM.PAINT_BLUE, 0.6, PM.F_GLASS)
	m.begin_part()
	var cols: float = 2.0
	var rows: float = 3.0
	m.quad(w.p(s0, y0) - gd, w.p(s1, y0) - gd, w.p(s1, y1) - gd, w.p(s0, y1) - gd, w.out, Vector2(0.0, 0.0), Vector2(cols, 0.0), Vector2(cols, rows), Vector2(0.0, rows))
	var b: float = 0.09
	var prot: float = 0.025
	_paint(m, PM.PAINT_BLUE, 0.7, PM.F_PAINT)
	_casing(m, w, s0, s1, y0, y1, b, prot, true)
	# shutters: two leaves hinged at the casing edges
	_paint(m, PM.PAINT_BLUE, 0.7, PM.F_LOUVER)
	var lw: float = (s1 - s0) * 0.5 + b - 0.01
	var lh: float = (y1 - y0) + 2.0 * b - 0.03
	var yc: float = (y0 + y1) * 0.5
	var a: float = deg_to_rad(open_deg)
	for side: float in [-1.0, 1.0]:
		var hinge_s: float = s0 - b if side < 0.0 else s1 + b
		var closed_dir: Vector3 = -side * w.along
		var dir: Vector3 = closed_dir * cos(a) + w.out * sin(a)
		var hinge: Vector3 = w.p(hinge_s, yc) + w.out * (prot + 0.025)
		var center: Vector3 = hinge + dir * (lw * 0.5)
		_rbox(m, center, Vector3(lw, lh, 0.035), Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized()))


static func _door(m: HDMesh, w: Wall, o: Dictionary, grand: bool) -> void:
	var s0: float = o["s0"]
	var s1: float = o["s1"]
	var y0: float = o["y0"]
	var y1: float = o["y1"]
	var sc: float = (s0 + s1) * 0.5
	var wd: float = s1 - s0
	var h: float = y1 - y0
	var yc: float = (y0 + y1) * 0.5
	_paint(m, PM.WOOD_RAW, 0.85, PM.F_WOOD, PM.GRAIN_Y)
	var base: Basis = Basis(w.along, Vector3.UP, w.along.cross(Vector3.UP).normalized())
	var leaf_c: Vector3 = w.p(sc, yc) - w.out * 0.10
	_rbox(m, leaf_c, Vector3(wd - 0.02, h - 0.02, 0.05), base)
	# raised panels
	_paint(m, PM.WOOD_LIGHT, 0.85, PM.F_WOOD, PM.GRAIN_Y)
	var pw: float = wd * 0.5 - 0.13
	var ph_top: float = h * 0.40
	var ph_low: float = h * 0.30
	for col: float in [-1.0, 1.0]:
		var pc: Vector3 = leaf_c + w.along * (col * (pw * 0.5 + 0.03)) + w.out * 0.03
		_rbox(m, pc + Vector3.UP * (h * 0.22), Vector3(pw, ph_top, 0.026), base)
		_rbox(m, pc - Vector3.UP * (h * 0.27), Vector3(pw, ph_low, 0.026), base)
	# frame and threshold
	_paint(m, PM.PAINT_BLUE, 0.7, PM.F_PAINT)
	_casing(m, w, s0, s1, y0, y1, 0.11, 0.03, false)
	if grand:
		_paint(m, PM.CEMENT_GREY, 0.8, PM.F_CEMENT)
		_box(m, w.p(sc, y0 + 0.01) + w.out * 0.05, Vector3(wd + 0.2, 0.03, 0.22))


# --- roof --------------------------------------------------------------------------------------------

static func _top_pt(x: float, z: float) -> Vector3:
	return Vector3(x, roof_u(x, z) + SLAB, z)


static func _under_pt(x: float, z: float) -> Vector3:
	return Vector3(x, roof_u(x, z), z)


static func _roof(m: HDMesh) -> void:
	var rx: float = EAVE_X - EAVE_Z                     # ridge half length
	var ridge_v: float = EAVE_Z * SLOPE_K
	# top (tile): front, back, right and left slopes, UV = (m along the eave, m down the slope)
	_paint(m, PM.TILE_CLAY, 0.8, PM.F_TILE)
	m.begin_part()
	m.quad(_top_pt(-EAVE_X, -EAVE_Z), _top_pt(EAVE_X, -EAVE_Z), _top_pt(rx, 0.0), _top_pt(-rx, 0.0), Vector3.UP,
		Vector2(-EAVE_X, 0.0), Vector2(EAVE_X, 0.0), Vector2(rx, ridge_v), Vector2(-rx, ridge_v))
	m.begin_part()
	m.quad(_top_pt(EAVE_X, EAVE_Z), _top_pt(-EAVE_X, EAVE_Z), _top_pt(-rx, 0.0), _top_pt(rx, 0.0), Vector3.UP,
		Vector2(EAVE_X, 0.0), Vector2(-EAVE_X, 0.0), Vector2(-rx, ridge_v), Vector2(rx, ridge_v))
	m.begin_part()
	m.tri(_top_pt(EAVE_X, -EAVE_Z), _top_pt(EAVE_X, EAVE_Z), _top_pt(rx, 0.0), Vector3.UP,
		Vector2(-EAVE_Z, 0.0), Vector2(EAVE_Z, 0.0), Vector2(0.0, ridge_v * 1.0))
	m.begin_part()
	m.tri(_top_pt(-EAVE_X, EAVE_Z), _top_pt(-EAVE_X, -EAVE_Z), _top_pt(-rx, 0.0), Vector3.UP,
		Vector2(EAVE_Z, 0.0), Vector2(-EAVE_Z, 0.0), Vector2(0.0, ridge_v * 1.0))
	# underside: timber lining running down the slope
	_paint(m, PM.WOOD_LIGHT, 0.88, PM.F_WOOD, PM.GRAIN_Z)
	m.begin_part()
	m.quad(_under_pt(-EAVE_X, -EAVE_Z), _under_pt(EAVE_X, -EAVE_Z), _under_pt(rx, 0.0), _under_pt(-rx, 0.0), Vector3.DOWN)
	m.begin_part()
	m.quad(_under_pt(EAVE_X, EAVE_Z), _under_pt(-EAVE_X, EAVE_Z), _under_pt(-rx, 0.0), _under_pt(rx, 0.0), Vector3.DOWN)
	_paint(m, PM.WOOD_LIGHT, 0.88, PM.F_WOOD, PM.GRAIN_X)
	m.begin_part()
	m.tri(_under_pt(EAVE_X, -EAVE_Z), _under_pt(EAVE_X, EAVE_Z), _under_pt(rx, 0.0), Vector3.DOWN)
	m.begin_part()
	m.tri(_under_pt(-EAVE_X, EAVE_Z), _under_pt(-EAVE_X, -EAVE_Z), _under_pt(-rx, 0.0), Vector3.DOWN)
	# eave edge: fascia band with a scalloped lower edge (tile ends)
	_paint(m, PM.TILE_CAP, 0.8, PM.F_CERAMIC)
	_eave(m, Vector3(-EAVE_X, EAVE_Y, -EAVE_Z), Vector3(EAVE_X, EAVE_Y, -EAVE_Z), Vector3.FORWARD)
	_eave(m, Vector3(EAVE_X, EAVE_Y, EAVE_Z), Vector3(-EAVE_X, EAVE_Y, EAVE_Z), Vector3.BACK)
	_eave(m, Vector3(EAVE_X, EAVE_Y, -EAVE_Z), Vector3(EAVE_X, EAVE_Y, EAVE_Z), Vector3.RIGHT)
	_eave(m, Vector3(-EAVE_X, EAVE_Y, EAVE_Z), Vector3(-EAVE_X, EAVE_Y, -EAVE_Z), Vector3.LEFT)
	# ridge and hip caps
	m.crease_deg = 65.0
	var lift: Vector3 = Vector3.UP * 0.03
	var section: PackedVector2Array = HDMesh.circle_section(0.12, 6)
	var corners: Array = [Vector2(-EAVE_X, -EAVE_Z), Vector2(EAVE_X, -EAVE_Z), Vector2(EAVE_X, EAVE_Z), Vector2(-EAVE_X, EAVE_Z)]
	var ends: Array = [Vector2(-rx, 0.0), Vector2(rx, 0.0), Vector2(rx, 0.0), Vector2(-rx, 0.0)]
	m.sweep([_top_pt(-rx, 0.0) + lift, _top_pt(rx, 0.0) + lift], section, Vector3.UP, PackedFloat32Array(), false, true)
	for i in 4:
		var c: Vector2 = corners[i]
		var e: Vector2 = ends[i]
		m.sweep([_top_pt(c.x, c.y) + lift, _top_pt(e.x, e.y) + lift], section, Vector3.UP, PackedFloat32Array(), false, true)
	m.crease_deg = 50.0


static func _eave(m: HDMesh, a: Vector3, b: Vector3, out: Vector3) -> void:
	var length: float = a.distance_to(b)
	var dir: Vector3 = (b - a) / length
	var n: int = maxi(roundi(length / (TILE_PITCH * 0.5)), 2)
	m.begin_part()
	m.quad(a, b, b + Vector3.UP * SLAB, a + Vector3.UP * SLAB, out)
	for i in n:
		var p0: Vector3 = a + dir * (length * float(i) / float(n))
		var p1: Vector3 = a + dir * (length * float(i + 1) / float(n))
		var apex: Vector3 = (p0 + p1) * 0.5 - Vector3.UP * (0.05 if i % 2 == 0 else 0.022)
		m.tri(p0, p1, apex, out)


# --- porch -------------------------------------------------------------------------------------------

static func _porch(m: HDMesh) -> void:
	# floor slab and the two steps (burnt cement)
	_paint(m, PM.CEMENT_RED, 0.55, PM.F_CEMENT)
	_box(m, Vector3(0.0, FLOOR_H * 0.5, -2.5), Vector3(11.2, FLOOR_H, 2.2), 0.02)
	_paint(m, PM.CEMENT_GREY, 0.7, PM.F_CEMENT)
	_box(m, Vector3(0.0, 0.095, -3.74), Vector3(2.6, 0.19, 0.52), 0.02)
	# posts on little pedestals, header beam, brackets
	var px: Array = [-5.35, -3.1, 3.1, 5.35]
	for x: float in px:
		_paint(m, PM.CEMENT_GREY, 0.8, PM.F_CEMENT)
		_box(m, Vector3(x, FLOOR_H + 0.05, POST_Z), Vector3(0.32, 0.1, 0.32), 0.015)
		_paint(m, PM.WOOD_RAW, 0.88, PM.F_WOOD, PM.GRAIN_Y)
		_box(m, Vector3(x, (FLOOR_H + 0.1 + BEAM_Y0) * 0.5, POST_Z), Vector3(0.2, BEAM_Y0 - FLOOR_H - 0.1, 0.2), 0.02)
	_paint(m, PM.WOOD_RAW, 0.88, PM.F_WOOD, PM.GRAIN_X)
	_box(m, Vector3(0.0, BEAM_Y0 + 0.11, POST_Z), Vector3(11.1, 0.22, 0.2), 0.02)
	_paint(m, PM.WOOD_RAW, 0.88, PM.F_WOOD, PM.GRAIN_Z)
	for sx: float in [-1.0, 1.0]:
		_box(m, Vector3(sx * 5.35, BEAM_Y0 + 0.11, (POST_Z + WALL_FRONT_Z) * 0.5), Vector3(0.2, 0.22, WALL_FRONT_Z - POST_Z), 0.0)
	# 45 degree brackets (maos-francesas) between post and beam
	_paint(m, PM.WOOD_RAW, 0.88, PM.F_WOOD, PM.GRAIN_Y)
	var bx: Array = [[-5.35, 1.0], [-3.1, -1.0], [-3.1, 1.0], [3.1, -1.0], [3.1, 1.0], [5.35, -1.0]]
	for b: Array in bx:
		var side: float = b[1]
		var c: Vector3 = Vector3(float(b[0]) + side * 0.30, BEAM_Y0 - 0.30, POST_Z)
		_rbox(m, c, Vector3(0.08, 0.80, 0.12), Basis(Vector3(0, 0, 1), side * deg_to_rad(45.0)))
	# railings: front left and right, and the two sides
	_paint(m, PM.WOOD_LIGHT, 0.85, PM.F_WOOD, PM.GRAIN_X)
	_railing(m, Vector3(-5.25, FLOOR_H, POST_Z), Vector3(-3.2, FLOOR_H, POST_Z))
	_railing(m, Vector3(3.2, FLOOR_H, POST_Z), Vector3(5.25, FLOOR_H, POST_Z))
	_railing(m, Vector3(-5.35, FLOOR_H, POST_Z + 0.1), Vector3(-5.35, FLOOR_H, WALL_FRONT_Z))
	_railing(m, Vector3(5.35, FLOOR_H, POST_Z + 0.1), Vector3(5.35, FLOOR_H, WALL_FRONT_Z))


static func _railing(m: HDMesh, a: Vector3, b: Vector3) -> void:
	var len: float = a.distance_to(b)
	var dir: Vector3 = (b - a) / len
	var mid: Vector3 = (a + b) * 0.5
	var across: Vector3 = Vector3(absf(dir.z), 1.0, absf(dir.x))
	var size_rail: Vector3 = Vector3(0.1, 0.06, 0.1) * across + Vector3(absf(dir.x), 0.0, absf(dir.z)) * len
	_box(m, mid + Vector3.UP * 0.92, size_rail)
	_box(m, mid + Vector3.UP * 0.24, size_rail)
	var n: int = maxi(roundi(len / 0.4) - 1, 1)
	for i in n:
		var p: Vector3 = a + dir * (len * float(i + 1) / float(n + 1))
		_box(m, p + Vector3.UP * 0.58, Vector3(0.045, 0.64, 0.045))


# --- chimney -----------------------------------------------------------------------------------------

static func _chimney(m: HDMesh) -> void:
	var cx: float = 3.2
	var cz: float = 1.3
	_paint(m, PM.WHITEWASH, 0.92, PM.F_PLASTER)
	_box(m, Vector3(cx, (3.6 + 5.62) * 0.5, cz), Vector3(0.76, 5.62 - 3.6, 0.76), 0.012)
	_paint(m, PM.CEMENT_GREY, 0.8, PM.F_CEMENT)
	_box(m, Vector3(cx, 5.69, cz), Vector3(1.0, 0.14, 1.0), 0.015)
	_paint(m, PM.TILE_CAP, 0.8, PM.F_CERAMIC)
	var prof: Array = [Vector3(0.0, 0.14, 0.0), Vector3(0.18, 0.14, 0.0), Vector3(0.18, 0.17, 0.0), Vector3(0.24, 0.17, 0.0), Vector3(0.24, 0.0, 0.0)]
	m.lathe(prof, 8, Vector3(cx, 5.76, cz), Vector3.UP)
