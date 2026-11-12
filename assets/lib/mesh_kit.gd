class_name MeshKit
extends RefCounted
## Procedural low-poly mesh builder (flat shaded, vertex colors). Art-director tool.
## Geometry is added in local space and transformed by `xf`. Normals are flat and oriented
## away from a reference center so winding never has to be reasoned about by callers.

var xf: Transform3D = Transform3D.IDENTITY
var tri_count: int = 0

var _v: PackedVector3Array = PackedVector3Array()
var _n: PackedVector3Array = PackedVector3Array()
var _c: PackedColorArray = PackedColorArray()

static var _vcol_mat: StandardMaterial3D = null
static var _vcol_mat_double: StandardMaterial3D = null


## Shared opaque vertex-color material (one instance for the whole game).
static func vcol_material() -> StandardMaterial3D:
	if _vcol_mat == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.metallic = 0.0
		m.metallic_specular = 0.2
		_vcol_mat = m
	return _vcol_mat


## Same but with culling off (flat leaves, grass blades, flags).
static func vcol_material_double() -> StandardMaterial3D:
	if _vcol_mat_double == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.metallic_specular = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_vcol_mat_double = m
	return _vcol_mat_double


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)


func set_xf(pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var b: Basis = Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	b = b * Basis.from_scale(scl)
	xf = Transform3D(b, pos)


func reset_xf() -> void:
	xf = Transform3D.IDENTITY


## Single triangle, flat normal pointing away from `center` (local space).
func tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, center: Vector3) -> void:
	var ta: Vector3 = xf * a
	var tb: Vector3 = xf * b
	var tc: Vector3 = xf * c
	var out: Vector3 = (ta + tb + tc) / 3.0 - xf * center
	_emit(ta, tb, tc, ca, cb, cc, out)


## Triangle visible from both sides (leaves, ears).
func tri_double(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var ta: Vector3 = xf * a
	var tb: Vector3 = xf * b
	var tc: Vector3 = xf * c
	var n: Vector3 = (tb - ta).cross(tc - ta)
	_emit(ta, tb, tc, ca, cb, cc, n)
	_emit(ta, tb, tc, ca, cb, cc, -n)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	tri(a, b, c, col, col, col, center)
	tri(a, c, d, col, col, col, center)


func quad_double(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri_double(a, b, c, col, col, col)
	tri_double(a, c, d, col, col, col)


func _emit(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	# Godot front faces are clockwise: (b-a)x(c-a) must point opposite to the outward normal.
	if n.dot(outward) > 0.0:
		var t: Vector3 = b
		b = c
		c = t
		var tc: Color = cb
		cb = cc
		cc = tc
		n = -n
	n = -n.normalized() # cross points inward after the winding fix; the lighting normal is outward
	_v.push_back(a)
	_v.push_back(b)
	_v.push_back(c)
	_n.push_back(n)
	_n.push_back(n)
	_n.push_back(n)
	_c.push_back(ca)
	_c.push_back(cb)
	_c.push_back(cc)
	tri_count += 1


## Axis aligned box centered at `center`.
func box(center: Vector3, size: Vector3, col: Color, col_top: Color = Color(0, 0, 0, 0)) -> void:
	var top: Color = col if col_top.a == 0.0 else col_top
	prism(center - Vector3(0, size.y * 0.5, 0), Vector2(size.x, size.z), Vector2(size.x, size.z), size.y, col, top)


## Hexahedron: rectangular base (Vector2 = x,z size) at `base` center, top rectangle `top_size`
## shifted by `top_offset` (x,z) at height h. Use for legs, wedges, roofs (top_size 0 = ridge/pyramid).
func prism(base: Vector3, base_size: Vector2, top_size: Vector2, h: float, col_b: Color, col_t: Color, top_offset: Vector2 = Vector2.ZERO) -> void:
	var bx: float = base_size.x * 0.5
	var bz: float = base_size.y * 0.5
	var tx: float = top_size.x * 0.5
	var tz: float = top_size.y * 0.5
	var tc: Vector3 = base + Vector3(top_offset.x, h, top_offset.y)
	var b0: Vector3 = base + Vector3(-bx, 0, -bz)
	var b1: Vector3 = base + Vector3(bx, 0, -bz)
	var b2: Vector3 = base + Vector3(bx, 0, bz)
	var b3: Vector3 = base + Vector3(-bx, 0, bz)
	var t0: Vector3 = tc + Vector3(-tx, 0, -tz)
	var t1: Vector3 = tc + Vector3(tx, 0, -tz)
	var t2: Vector3 = tc + Vector3(tx, 0, tz)
	var t3: Vector3 = tc + Vector3(-tx, 0, tz)
	var center: Vector3 = base + Vector3(top_offset.x * 0.5, h * 0.5, top_offset.y * 0.5)
	# sides
	_side(b0, b1, t1, t0, col_b, col_t, center)
	_side(b1, b2, t2, t1, col_b, col_t, center)
	_side(b2, b3, t3, t2, col_b, col_t, center)
	_side(b3, b0, t0, t3, col_b, col_t, center)
	# caps
	quad(t0, t1, t2, t3, col_t, center)
	quad(b0, b1, b2, b3, col_b, center)


func _side(b0: Vector3, b1: Vector3, t1: Vector3, t0: Vector3, cb: Color, ct: Color, center: Vector3) -> void:
	# degenerate top edges (ridge) collapse to one triangle automatically (zero-area skipped)
	tri(b0, b1, t1, cb, cb, ct, center)
	tri(b0, t1, t0, cb, ct, ct, center)


## Vertical (local +Y) frustum with n sides: radius r0 at base, r1 at top. r1 = 0 -> cone.
func frustum(base: Vector3, r0: float, r1: float, h: float, sides: int, col_b: Color, col_t: Color, cap_top: bool = true, cap_bottom: bool = false, offset_top: Vector2 = Vector2.ZERO) -> void:
	var center: Vector3 = base + Vector3(offset_top.x * 0.5, h * 0.5, offset_top.y * 0.5)
	var top_c: Vector3 = base + Vector3(offset_top.x, h, offset_top.y)
	for i in sides:
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var b0: Vector3 = base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var b1: Vector3 = base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var t0: Vector3 = top_c + Vector3(cos(a0) * r1, 0, sin(a0) * r1)
		var t1: Vector3 = top_c + Vector3(cos(a1) * r1, 0, sin(a1) * r1)
		tri(b0, b1, t1, col_b, col_b, col_t, center)
		tri(b0, t1, t0, col_b, col_t, col_t, center)
		if cap_top and r1 > 0.0:
			tri(top_c, t0, t1, col_t, col_t, col_t, center)
		if cap_bottom and r0 > 0.0:
			tri(base, b0, b1, col_b, col_b, col_b, center)


## Low-poly ellipsoid. radii = (rx, ry, rz). Vertex color blends bottom -> top.
func ellipsoid(center: Vector3, radii: Vector3, seg: int, rings: int, col_bot: Color, col_top: Color = Color(0, 0, 0, 0)) -> void:
	var ct: Color = col_bot if col_top.a == 0.0 else col_top
	for r in rings:
		var p0: float = PI * float(r) / float(rings)
		var p1: float = PI * float(r + 1) / float(rings)
		var y0: float = cos(p0)
		var y1: float = cos(p1)
		var s0: float = sin(p0)
		var s1: float = sin(p1)
		var c0: Color = col_bot.lerp(ct, y0 * 0.5 + 0.5)
		var c1: Color = col_bot.lerp(ct, y1 * 0.5 + 0.5)
		for i in seg:
			var a0: float = TAU * float(i) / float(seg)
			var a1: float = TAU * float(i + 1) / float(seg)
			var v00: Vector3 = center + Vector3(cos(a0) * s0 * radii.x, y0 * radii.y, sin(a0) * s0 * radii.z)
			var v01: Vector3 = center + Vector3(cos(a1) * s0 * radii.x, y0 * radii.y, sin(a1) * s0 * radii.z)
			var v10: Vector3 = center + Vector3(cos(a0) * s1 * radii.x, y1 * radii.y, sin(a0) * s1 * radii.z)
			var v11: Vector3 = center + Vector3(cos(a1) * s1 * radii.x, y1 * radii.y, sin(a1) * s1 * radii.z)
			if r > 0:
				tri(v00, v01, v11, c0, c0, c1, center)
			if r < rings - 1:
				tri(v00, v11, v10, c0, c1, c1, center)


## Loft along -Z..+Z. stations: Array of [z, half_width, y_bottom, y_top]. Cross-section is an
## `sides`-gon (even) squashed into that box. Colors: belly -> back gradient. Closed with caps.
func loft(stations: Array, sides: int, col_belly: Color, col_back: Color, cap_front: bool = true, cap_back: bool = true, color_fn: Callable = Callable()) -> void:
	var rings: Array = []
	for st in stations:
		var z: float = st[0]
		var hw: float = st[1]
		var yb: float = st[2]
		var yt: float = st[3]
		var cy: float = (yb + yt) * 0.5
		var hh: float = (yt - yb) * 0.5
		var ring: Array = []
		for i in sides:
			var a: float = TAU * (float(i) + 0.5) / float(sides)
			ring.append(Vector3(cos(a) * hw, cy + sin(a) * hh, z))
		rings.append({"pts": ring, "c": Vector3(0, cy, z)})
	for k in rings.size() - 1:
		var r0: Array = rings[k]["pts"]
		var r1: Array = rings[k + 1]["pts"]
		var cen: Vector3 = (rings[k]["c"] + rings[k + 1]["c"]) * 0.5
		for i in sides:
			var j: int = (i + 1) % sides
			var ci: Color = _lc(r0[i], rings[k]["c"], stations[k], i, col_belly, col_back, color_fn)
			var cj: Color = _lc(r0[j], rings[k]["c"], stations[k], j, col_belly, col_back, color_fn)
			var di: Color = _lc(r1[i], rings[k + 1]["c"], stations[k + 1], i, col_belly, col_back, color_fn)
			var dj: Color = _lc(r1[j], rings[k + 1]["c"], stations[k + 1], j, col_belly, col_back, color_fn)
			tri(r0[i], r0[j], r1[j], ci, cj, dj, cen)
			tri(r0[i], r1[j], r1[i], ci, dj, di, cen)
	if cap_front:
		_cap(rings[0]["pts"], rings[0]["c"], col_belly, col_back, stations[0], Vector3(0, 0, -1))
	if cap_back:
		var last: int = rings.size() - 1
		_cap(rings[last]["pts"], rings[last]["c"], col_belly, col_back, stations[last], Vector3(0, 0, 1))


## color_fn(point: Vector3, lift: float, index: int) -> Color overrides the gradient.
func _lc(p: Vector3, c: Vector3, st: Array, idx: int, cb: Color, ct: Color, fn: Callable) -> Color:
	var l: float = _lift(p, c, st)
	if fn.is_valid():
		return fn.call(p, l, idx)
	return cb.lerp(ct, l)


func _lift(p: Vector3, c: Vector3, st: Array) -> float:
	var hh: float = maxf((st[3] - st[2]) * 0.5, 0.0001)
	return clampf((p.y - c.y) / hh * 0.5 + 0.5, 0.0, 1.0)


func _cap(pts: Array, c: Vector3, cb: Color, ct: Color, st: Array, dir: Vector3) -> void:
	var col: Color = cb.lerp(ct, 0.6)
	for i in pts.size():
		var j: int = (i + 1) % pts.size()
		tri(c, pts[i], pts[j], col, col, col, c - dir)


func is_empty() -> bool:
	return _v.is_empty()


func build(material: Material = null) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material if material != null else vcol_material())
	return mesh


## Adds the accumulated triangles as an extra surface of `mesh` (own material).
func build_into(mesh: ArrayMesh, material: Material) -> void:
	if _v.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


static func count_triangles(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				if idx != null and (idx as PackedInt32Array).size() > 0:
					total += (idx as PackedInt32Array).size() / 3
				else:
					total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for ch in node.get_children():
		total += count_triangles(ch)
	return total
