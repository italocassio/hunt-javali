extends RefCounted
## Fast organic mesh builder for the HD boar (boar_hd_model.gd). Every part is a grid of rings (closed loops with
## the same point count), so smooth normals come straight from the grid neighbours: no weld pass, no AO rays.
## That is what keeps a cold build of the four LODs of one boar type under a few milliseconds.
##
## Vertex layout read by boar_fur.gdshader:
##   COLOR.rgb  albedo (used as stored) COLOR.a  baked (analytic) ambient occlusion
##   UV         x = around (integer tiles, seamless), y = along the part (tiles of U_TILE_M metres)
##   UV2        x = feature id + 0.5 * coarseness, y = around share 0..1 (0 = belly), for the piglet stripes
##   TANGENT    around direction (the hair runs along UV.y, the shader tilts the normal across it)

const U_TILE_M: float = 0.25

const FEAT_FUR: float = 0.0
const FEAT_MANE: float = 1.0
const FEAT_SKIN: float = 2.0
const FEAT_HOOF: float = 3.0
const FEAT_TUSK: float = 4.0
const FEAT_EYE: float = 5.0

var xf: Transform3D = Transform3D.IDENTITY

var _pos: PackedVector3Array = PackedVector3Array()
var _nrm: PackedVector3Array = PackedVector3Array()
var _tan: PackedFloat32Array = PackedFloat32Array()
var _col: PackedColorArray = PackedColorArray()
var _uv: PackedVector2Array = PackedVector2Array()
var _uv2: PackedVector2Array = PackedVector2Array()
var _idx: PackedInt32Array = PackedInt32Array()


func triangle_count() -> int:
	@warning_ignore("integer_division")
	return _idx.size() / 3


## Skins `rings` (Array of PackedVector3Array, m points each, closed loops, part space before `xf`).
## `paint` (p: Vector3, n: Vector3, around: float, along: float) -> Color gives albedo (rgb) and AO (a);
## p and n are in part space, around is 0..1 from the first ring point, along 0..1 from the first ring.
## `code` goes to UV2.x (feature + 0.5 * coarseness). `cap0` / `cap1` close the ends with a pole fan
## (`pole0` / `pole1`: pole offset from the end ring centre). `swap_uv` runs the hair across the rings
## (mane, ears). `stripes` writes the around share to UV2.y. `planar` (Vector4: cx, cy, 1/sx, 1/sy) maps UV
## to the part XY plane instead (snout disc).
func grid(rings: Array, paint: Callable, code: float, cap0: bool = false, cap1: bool = false,
		pole0: Vector3 = Vector3.ZERO, pole1: Vector3 = Vector3.ZERO, swap_uv: bool = false, stripes: bool = false,
		planar: Vector4 = Vector4.ZERO) -> void:
	var nr: int = rings.size()
	var m: int = (rings[0] as PackedVector3Array).size()
	var centers: PackedVector3Array = PackedVector3Array()
	centers.resize(nr)
	for r in nr:
		var ring: PackedVector3Array = rings[r]
		var c: Vector3 = Vector3.ZERO
		for p in ring:
			c += p
		centers[r] = c / float(m)
	# along coordinate: centre to centre distance
	var along: PackedFloat32Array = PackedFloat32Array()
	along.resize(nr)
	along[0] = 0.0
	for r in range(1, nr):
		along[r] = along[r - 1] + centers[r].distance_to(centers[r - 1])
	var total: float = maxf(along[nr - 1], 1e-6)
	var circ: float = 0.0
	@warning_ignore("integer_division")
	var mid_ring: PackedVector3Array = rings[nr / 2]
	for i in m:
		circ += mid_ring[i].distance_to(mid_ring[(i + 1) % m])
	var u_tiles: float = maxf(1.0, roundf(circ / U_TILE_M))
	var basis: Basis = xf.basis
	var base: int = _pos.size()
	var stride: int = m + 1
	for r in nr:
		var ring: PackedVector3Array = rings[r]
		var prev: PackedVector3Array = rings[maxi(r - 1, 0)]
		var next: PackedVector3Array = rings[mini(r + 1, nr - 1)]
		var t_along: float = along[r] / total
		var first_n: Vector3 = Vector3.ZERO
		var first_t: Vector3 = Vector3.ZERO
		var first_c: Color = Color.WHITE
		for i in m:
			var p: Vector3 = ring[i]
			var du: Vector3 = ring[(i + 1) % m] - ring[(i + m - 1) % m]
			var dv: Vector3 = next[i] - prev[i]
			var n: Vector3 = du.cross(dv)
			if n.length_squared() < 1e-14:
				n = p - centers[r]
				if n.length_squared() < 1e-14:
					n = centers[mini(r + 1, nr - 1)] - centers[maxi(r - 1, 0)]
					if r == 0:
						n = -n
			n = n.normalized()
			if n.dot(p - centers[r]) < 0.0 and (p - centers[r]).length_squared() > 1e-10:
				n = -n
			var tg: Vector3 = (du - n * du.dot(n))
			tg = tg.normalized() if tg.length_squared() > 1e-14 else n.cross(Vector3.UP).normalized()
			var a: float = float(i) / float(m)
			var c: Color = paint.call(p, n, a, t_along)
			if i == 0:
				first_n = n
				first_t = tg
				first_c = c
			_emit(p, n, tg, c, _uv_of(p, a * u_tiles, along[r] / U_TILE_M, swap_uv, planar), Vector2(code, a if stripes else 0.0), basis)
		# seam column: same point, closing UV
		_emit(ring[0], first_n, first_t, first_c, _uv_of(ring[0], u_tiles, along[r] / U_TILE_M, swap_uv, planar), Vector2(code, 1.0 if stripes else 0.0), basis)
	for r in nr - 1:
		for i in m:
			var a0: int = base + r * stride + i
			var b0: int = a0 + 1
			var a1: int = a0 + stride
			var b1: int = a1 + 1
			_quad(a0, b0, b1, a1)
	if cap0:
		_cap(base, m, centers[0] + pole0, (centers[0] - centers[mini(1, nr - 1)]).normalized(), paint, code, 0.0, swap_uv, planar, basis, stripes)
	if cap1:
		_cap(base + (nr - 1) * stride, m, centers[nr - 1] + pole1, (centers[nr - 1] - centers[maxi(nr - 2, 0)]).normalized(), paint, code, 1.0, swap_uv, planar, basis, stripes)


func _uv_of(p: Vector3, u: float, v: float, swap_uv: bool, planar: Vector4) -> Vector2:
	if planar != Vector4.ZERO:
		return Vector2((p.x - planar.x) * planar.z, (p.y - planar.y) * planar.w)
	return Vector2(v, u) if swap_uv else Vector2(u, v)


func _emit(p: Vector3, n: Vector3, tg: Vector3, c: Color, uv: Vector2, uv2: Vector2, basis: Basis) -> void:
	_pos.push_back(xf * p)
	_nrm.push_back((basis * n).normalized())
	var tw: Vector3 = (basis * tg).normalized()
	_tan.push_back(tw.x)
	_tan.push_back(tw.y)
	_tan.push_back(tw.z)
	_tan.push_back(1.0)
	_col.push_back(c)
	_uv.push_back(uv)
	_uv2.push_back(uv2)


## Two triangles a-b-c, a-c-d, wound so that their front faces the side the vertex normals point to.
func _quad(a: int, b: int, c: int, d: int) -> void:
	var pa: Vector3 = _pos[a]
	var n: Vector3 = (_pos[c] - pa).cross(_pos[d] - _pos[b])
	var out: Vector3 = _nrm[a] + _nrm[b] + _nrm[c] + _nrm[d]
	# Godot front faces are clockwise: (b-a)x(c-a) must point away from the outside
	if n.dot(out) > 0.0:
		_idx.append_array(PackedInt32Array([a, c, b, a, d, c]))
	else:
		_idx.append_array(PackedInt32Array([a, b, c, a, c, d]))


func _cap(ring_start: int, m: int, pole: Vector3, axis: Vector3, paint: Callable, code: float, t_along: float,
		swap_uv: bool, planar: Vector4, basis: Basis, stripes: bool) -> void:
	var c: Color = paint.call(pole, axis, 0.5, t_along)
	var pole_world: Vector3 = xf * pole
	var tg: Vector3 = axis.cross(Vector3.UP)
	if tg.length_squared() < 1e-8:
		tg = Vector3.RIGHT
	var pi: int = _pos.size()
	_emit(pole, axis, tg.normalized(), c, _uv_of(pole, 0.5, t_along, swap_uv, planar), Vector2(code, 0.0 if not stripes else 0.0), basis)
	var out: Vector3 = (basis * axis)
	for i in m:
		var a: int = ring_start + i
		var b: int = ring_start + i + 1
		var n: Vector3 = (_pos[a] - pole_world).cross(_pos[b] - pole_world)
		if n.dot(out) > 0.0:
			_idx.append_array(PackedInt32Array([pi, b, a]))
		else:
			_idx.append_array(PackedInt32Array([pi, a, b]))


## Appends everything to `mesh` as one surface with `material`.
func commit(mesh: ArrayMesh, material: Material) -> void:
	if _idx.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _pos
	arrays[Mesh.ARRAY_NORMAL] = _nrm
	arrays[Mesh.ARRAY_TANGENT] = _tan
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## Positions only (rest pose, part space after `xf`), for the hit-zone check.
func positions() -> PackedVector3Array:
	return _pos


func codes() -> PackedVector2Array:
	return _uv2


# --- ring helpers ------------------------------------------------------------------------------------------

## Superellipse ring in the XY plane at depth z: point 0 at the bottom (belly), walking over +X to the top.
## top / bot: y of the top and bottom; hw: half width; ym: y of the widest line; et / eb: exponents (2 = ellipse,
## higher = boxier) of the upper and lower half.
static func super_ring(z: float, top: float, bot: float, hw: float, ym: float, et: float, eb: float, m: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(m)
	for i in m:
		var a: float = -PI * 0.5 + TAU * float(i) / float(m)
		var c: float = cos(a)
		var s: float = sin(a)
		var e: float = 2.0 / (et if s >= 0.0 else eb)
		var x: float = hw * signf(c) * pow(absf(c), e)
		var y: float = ym + (top - ym if s >= 0.0 else ym - bot) * signf(s) * pow(absf(s), e)
		out[i] = Vector3(x, y, z)
	return out


## Rings along a path: ellipse sections (rx along `side`, ry along the path normal t x side), m points.
## Point 0 points to -(t x side) (the back of a leg when the path runs down and side = +X).
static func tube_rings(path: PackedVector3Array, rx: PackedFloat32Array, ry: PackedFloat32Array, side: Vector3, m: int) -> Array:
	var rings: Array = []
	var n: int = path.size()
	for k in n:
		var t: Vector3 = (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		var sx: Vector3 = (side - t * side.dot(t)).normalized()
		var sy: Vector3 = t.cross(sx)
		var ring: PackedVector3Array = PackedVector3Array()
		ring.resize(m)
		for i in m:
			var a: float = -PI * 0.5 + TAU * float(i) / float(m)
			ring[i] = path[k] + sx * (cos(a) * rx[k]) + sy * (sin(a) * ry[k])
		rings.append(ring)
	return rings
