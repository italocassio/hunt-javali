extends RefCounted
## HD cerrado trees for flora_library.gd: cerrado_tree (twisted corky tree), ipe (yellow ipe in full bloom),
## buriti (fan palm). Loaded by path, no class_name. build(id) -> ArrayMesh with two surfaces each:
## 0 = bark (tree_bark.gdshader), 1 = crown (tree_canopy.gdshader); both materials shared by the three ids.
## Origin at the base, Y up. The gameplay adds a random yaw and +-20% scale and draws them as MultiMesh, so the
## triangle counts stay low (the map holds 208 cerrado trees): the detail lives in silhouette, normals and shader.
## Trunks stay inside the colliders of §7.5 (r 0.2 x 3 m, r 0.3 x 4 m, r 0.25 x 6 m around the origin).
##
## Vertex layout: see the two shaders. Colours are stored as they are shown (no sRGB decode, like the other flora).

const BARK_SHADER: Shader = preload("res://assets/models/flora/tree_bark.gdshader")
const CANOPY_SHADER: Shader = preload("res://assets/models/flora/tree_canopy.gdshader")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")

const KIND_CORK: float = 0.0
const KIND_IPE: float = 1.0
const KIND_PALM: float = 2.0
const BARK_TILE_M: float = 0.3      # around: one noise tile per this much circumference (rounded, seamless)
const NOISE_UV_PER_M: float = 0.9   # crown noise coordinates

## Icosahedron (12 vertices, 20 faces): the crown tuft primitive.
const ICO_F: Array[int] = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6,
	7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]

static var _bark_mat: ShaderMaterial = null
static var _canopy_mat: ShaderMaterial = null


static func build(id: StringName) -> Mesh:
	match id:
		&"cerrado_tree": return _cerrado_tree()
		&"ipe": return _ipe()
		&"buriti": return _buriti()
	return null


static func bark_material() -> ShaderMaterial:
	if _bark_mat == null:
		_bark_mat = ShaderMaterial.new()
		_bark_mat.shader = BARK_SHADER
		_bark_mat.set_shader_parameter(&"noise_tex", _noise())
	return _bark_mat


static func canopy_material() -> ShaderMaterial:
	if _canopy_mat == null:
		_canopy_mat = ShaderMaterial.new()
		_canopy_mat.shader = CANOPY_SHADER
		_canopy_mat.set_shader_parameter(&"noise_tex", _noise())
	return _canopy_mat


## The 512x512 RG noise shared with the HD guns and boars (already warm in the hunt).
static func _noise() -> Texture2D:
	var wood: ShaderMaterial = RifleHD.get_materials()[RifleHD.SURF_WOOD]
	return wood.get_shader_parameter(&"noise_tex")


static func _rng(seed_text: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash(seed_text)
	return r


static func _dir(deg: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(cos(a), 0.0, sin(a))


static func _finish(bark: Surf, crown: Surf) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	bark.commit(mesh, bark_material())
	crown.commit(mesh, canopy_material())
	return mesh


# --- surface builder ---------------------------------------------------------------------------------------

class Surf:
	var pos: PackedVector3Array = PackedVector3Array()
	var nrm: PackedVector3Array = PackedVector3Array()
	var col: PackedColorArray = PackedColorArray()
	var uv: PackedVector2Array = PackedVector2Array()
	var uv2: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()

	func v(p: Vector3, n: Vector3, c: Color, t: Vector2, t2: Vector2) -> int:
		pos.push_back(p)
		nrm.push_back(n)
		col.push_back(c)
		uv.push_back(t)
		uv2.push_back(t2)
		return pos.size() - 1

	## Triangle whose front faces `out` (Godot front faces are clockwise: (b-a)x(c-a) points inward).
	func tri(a: int, b: int, c: int, out: Vector3) -> void:
		if (pos[b] - pos[a]).cross(pos[c] - pos[a]).dot(out) > 0.0:
			idx.append_array(PackedInt32Array([a, c, b]))
		else:
			idx.append_array(PackedInt32Array([a, b, c]))

	func triangles() -> int:
		@warning_ignore("integer_division")
		return idx.size() / 3

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# --- primitives --------------------------------------------------------------------------------------------

## Limb along `path` with ring radii `radii` (a last radius of 0 ends in a point). Smooth radial normals,
## parallel-transport frames (no twist). `crown_y`: limbs above it sit in the crown shade (AO).
static func _tube(s: Surf, path: PackedVector3Array, radii: PackedFloat32Array, sides: int, kind: float,
		c0: Color, c1: Color, r: RandomNumberGenerator, crown_y: float, lumpy: float = 0.0) -> void:
	var n: int = path.size()
	var tiles: float = maxf(1.0, roundf(TAU * radii[0] / BARK_TILE_M))
	var side: Vector3 = Vector3.ZERO
	var along: float = 0.0
	var prev_ring: PackedInt32Array = PackedInt32Array()
	var bumps: PackedFloat32Array = PackedFloat32Array()
	for i in sides:
		bumps.push_back(1.0 + r.randf_range(-lumpy, lumpy))
	for k in n:
		var t: Vector3 = (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		if k > 0:
			along += path[k].distance_to(path[k - 1])
		if k == 0:
			side = t.cross(Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT).normalized()
		else:
			side = (side - t * side.dot(t)).normalized()
		var up2: Vector3 = t.cross(side)
		var p0: Vector3 = path[k]
		var ao: float = _bark_ao(p0.y, crown_y)
		var ring: PackedInt32Array = PackedInt32Array()
		if radii[k] <= 0.0005:
			var c: Color = c0.lerp(c1, r.randf())
			c.a = ao
			ring.push_back(s.v(p0, t, c, Vector2(tiles * 0.5, along), Vector2(kind, 0.0)))
		else:
			for i in sides + 1:
				var a: float = TAU * float(i) / float(sides)
				var d: Vector3 = side * cos(a) + up2 * sin(a)
				var c: Color = c0.lerp(c1, r.randf())
				c.a = ao
				var rr: float = radii[k] * bumps[i % sides]
				ring.push_back(s.v(p0 + d * rr, d, c, Vector2(tiles * float(i) / float(sides), along), Vector2(kind, 0.0)))
		if k > 0:
			var mid: Vector3 = (path[k] + path[k - 1]) * 0.5
			if ring.size() == 1:
				for i in sides:
					s.tri(prev_ring[i], prev_ring[i + 1], ring[0], (s.pos[prev_ring[i]] + s.pos[prev_ring[i + 1]]) * 0.5 - mid)
			else:
				for i in sides:
					var a0: int = prev_ring[i]
					var b0: int = prev_ring[i + 1]
					var a1: int = ring[i]
					var b1: int = ring[i + 1]
					var out: Vector3 = (s.pos[a0] + s.pos[b1]) * 0.5 - mid
					s.tri(a0, b0, b1, out)
					s.tri(a0, b1, a1, out)
		prev_ring = ring


static func _bark_ao(y: float, crown_y: float) -> float:
	var ground: float = lerpf(0.55, 1.0, clampf(y / 0.7, 0.0, 1.0))
	var shade: float = lerpf(1.0, 0.72, clampf((y - crown_y + 0.6) / 1.2, 0.0, 1.0))
	return ground * shade


## Crown tuft: jittered icosahedron (20 tris) with "inflated" normals blended from the tuft centre and the crown
## centre (`crown_c`, radii `crown_r`), so the crown shades as one soft volume. Colours from dark (inside, bottom)
## to light (outside, top).
static func _tuft(s: Surf, center: Vector3, radii: Vector3, crown_c: Vector3, crown_r: Vector3, r: RandomNumberGenerator,
		dark: Color, light: Color, trans: float, wind: Vector2) -> void:
	var phi: float = (1.0 + sqrt(5.0)) * 0.5
	var raw: Array[Vector3] = [Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1)]
	var yaw: Basis = Basis(Vector3.UP, r.randf() * TAU)
	var tilt: Basis = Basis(Vector3.RIGHT, r.randf_range(-0.35, 0.35))
	var base: int = s.pos.size()
	var uv_off: Vector2 = Vector2(r.randf(), r.randf()) * 4.0
	var top: float = crown_c.y + crown_r.y
	var bottom: float = crown_c.y - crown_r.y
	for q0: Vector3 in raw:
		var u: Vector3 = (yaw * tilt * q0).normalized()
		var j: float = r.randf_range(0.72, 1.22)
		var q: Vector3 = u * j
		if q.y < 0.0:
			q.y *= 0.8   # flatter underside
		var p: Vector3 = center + q * radii
		var n_tuft: Vector3 = (q / radii).normalized()
		var to_c: Vector3 = (p - crown_c) / crown_r
		var n_crown: Vector3 = to_c.normalized() if to_c.length_squared() > 1e-6 else Vector3.UP
		var nrm: Vector3 = (n_tuft * 0.4 + n_crown * 0.6).normalized()
		var hf: float = clampf((p.y - bottom) / maxf(top - bottom, 0.01), 0.0, 1.0)
		var outer: float = clampf(0.5 + 0.5 * u.dot(n_crown), 0.0, 1.0)
		var c: Color = dark.lerp(light, clampf(0.15 + 0.45 * hf + 0.25 * outer + r.randf_range(-0.12, 0.12), 0.0, 1.0))
		c.a = lerpf(0.58, 1.0, outer) * lerpf(0.78, 1.0, clampf(nrm.y * 0.5 + 0.5, 0.0, 1.0))
		var t: Vector2 = Vector2(p.x + p.y * 0.35, p.z - p.y * 0.35) * NOISE_UV_PER_M + uv_off
		s.v(p, nrm, c, t, Vector2(lerpf(wind.x, wind.y, hf * 0.6 + outer * 0.4), trans * lerpf(0.5, 1.0, outer)))
	for f in range(0, ICO_F.size(), 3):
		var a: int = base + ICO_F[f]
		var b: int = base + ICO_F[f + 1]
		var c2: int = base + ICO_F[f + 2]
		s.tri(a, b, c2, (s.pos[a] + s.pos[b] + s.pos[c2]) / 3.0 - center)


## Flat-shaded triangle (own vertices): normal = face normal bent toward `bend`.
static func _flat_tri(s: Surf, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, wa: Vector2, wb: Vector2,
		wc: Vector2, side_hint: Vector3, bend: Vector3) -> void:
	var fn: Vector3 = (b - a).cross(c - a)
	if fn.length_squared() < 1e-12:
		return
	fn = fn.normalized()
	if fn.dot(side_hint) < 0.0:
		fn = -fn
	var n: Vector3 = (fn + bend * 0.35).normalized()
	var ia: int = s.v(a, n, ca, Vector2(a.x + a.y * 0.35, a.z - a.y * 0.35) * NOISE_UV_PER_M * 1.7, wa)
	var ib: int = s.v(b, n, cb, Vector2(b.x + b.y * 0.35, b.z - b.y * 0.35) * NOISE_UV_PER_M * 1.7, wb)
	var ic: int = s.v(c, n, cc, Vector2(c.x + c.y * 0.35, c.z - c.y * 0.35) * NOISE_UV_PER_M * 1.7, wc)
	s.tri(ia, ib, ic, n)


# --- cerrado tree ------------------------------------------------------------------------------------------

## Twisted cerrado tree (pequizeiro / lixeira look): leaning corky trunk, three tortuous limbs, open crown of
## six flattish tufts. ~4.5 m tall, crown ~3.3 m.
static func _cerrado_tree() -> Mesh:
	var r: RandomNumberGenerator = _rng("cerrado_tree_hd")
	var bark: Surf = Surf.new()
	var crown: Surf = Surf.new()
	var b0: Color = Color(0.33, 0.27, 0.22)
	var b1: Color = Color(0.44, 0.37, 0.30)
	var crown_y: float = 2.9
	_tube(bark, PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.06, 0.8, 0.03), Vector3(-0.05, 1.55, 0.08),
		Vector3(0.08, 2.2, 0.01), Vector3(0.0, 2.75, 0.06)]),
		PackedFloat32Array([0.26, 0.2, 0.18, 0.15, 0.0]), 6, KIND_CORK, b0, b1, r, crown_y, 0.1)
	var leaf_d: Color = Color(0.25, 0.33, 0.14)
	var leaf_l: Color = Color(0.6, 0.66, 0.33)
	var cc: Vector3 = Vector3(0.0, 3.55, 0.0)
	var cr: Vector3 = Vector3(1.4, 0.8, 1.4)
	var limbs: Array = [[12.0, 1.85, 0.11], [138.0, 2.15, 0.1], [252.0, 2.4, 0.095]]
	for L: Array in limbs:
		var az: float = L[0]
		var y0: float = L[1]
		var rad: float = L[2]
		var start: Vector3 = Vector3(0.02, y0, 0.04)
		var k1: Vector3 = start + _dir(az) * 0.36 + Vector3.UP * 0.5
		var k2: Vector3 = k1 + _dir(az + 32.0) * 0.32 + Vector3.UP * 0.25
		var tip: Vector3 = k2 + _dir(az - 20.0) * 0.28 + Vector3.UP * 0.3
		_tube(bark, PackedVector3Array([start, k1, k2, tip]), PackedFloat32Array([rad, rad * 0.7, rad * 0.45, 0.0]), 3,
			KIND_CORK, b0, b1, r, crown_y)
		_tuft(crown, tip + Vector3(0, 0.12, 0), Vector3(0.74, 0.5, 0.7) * r.randf_range(0.9, 1.1), cc, cr, r,
			leaf_d, leaf_l, 0.8, Vector2(0.45, 1.0))
		# a twig off the elbow ends in a second, smaller tuft
		if az < 200.0:
			var twig_tip: Vector3 = k1 + _dir(az - 70.0) * 0.48 + Vector3.UP * 0.5
			_tube(bark, PackedVector3Array([k1, twig_tip]), PackedFloat32Array([rad * 0.5, 0.0]), 3, KIND_CORK, b0, b1, r, crown_y)
			_tuft(crown, twig_tip + Vector3(0, 0.08, 0), Vector3(0.6, 0.44, 0.58), cc, cr, r, leaf_d, leaf_l, 0.8, Vector2(0.4, 0.9))
	# crown top
	_tuft(crown, Vector3(0.05, 3.98, -0.05), Vector3(0.8, 0.5, 0.78), cc, cr, r, leaf_d, leaf_l, 0.8, Vector2(0.5, 1.0))
	return _finish(bark, crown)


# --- ipe ---------------------------------------------------------------------------------------------------

## Yellow ipe in full bloom: straight grey furrowed trunk, four ascending limbs forking into twigs that carry
## fourteen yellow flower clusters (almost no leaves). ~7 m tall, crown ~5.3 m.
static func _ipe() -> Mesh:
	var r: RandomNumberGenerator = _rng("ipe_hd")
	var bark: Surf = Surf.new()
	var crown: Surf = Surf.new()
	var b0: Color = Color(0.36, 0.34, 0.31)
	var b1: Color = Color(0.5, 0.47, 0.42)
	var crown_y: float = 4.3
	_tube(bark, PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.03, 1.2, 0.0), Vector3(0.0, 2.6, 0.04),
		Vector3(0.05, 3.7, 0.02), Vector3(0.03, 4.4, 0.0)]),
		PackedFloat32Array([0.37, 0.3, 0.27, 0.23, 0.0]), 7, KIND_IPE, b0, b1, r, crown_y, 0.06)
	# flowers: stored values lean green on purpose, the golden afternoon sun (1.0, 0.66, 0.32) pulls them to yellow
	var fl_d: Color = Color(0.8, 0.74, 0.1)
	var fl_l: Color = Color(0.96, 1.0, 0.3)
	var cc: Vector3 = Vector3(0.0, 5.6, 0.0)
	var cr: Vector3 = Vector3(2.5, 1.2, 2.5)
	var inner: Array[Vector3] = []
	for j in 6:
		var a: float = float(j) * 60.0 + 15.0 + r.randf_range(-12.0, 12.0)
		inner.append(_dir(a) * r.randf_range(1.05, 1.35) + Vector3.UP * r.randf_range(5.85, 6.2))
	var outer: Array[Vector3] = []
	for j in 7:
		var a2: float = float(j) * 51.43 + r.randf_range(-10.0, 10.0)
		outer.append(_dir(a2) * r.randf_range(1.8, 2.05) + Vector3.UP * r.randf_range(4.95, 5.4))
	for i in 4:
		var az: float = float(i) * 90.0 + 30.0 + r.randf_range(-10.0, 10.0)
		var start: Vector3 = Vector3(0.03, 3.45 + 0.15 * float(i), 0.0)
		var k1: Vector3 = start + _dir(az) * 0.6 + Vector3.UP * 0.95
		var tip: Vector3 = _nearest(inner, k1 + _dir(az) * 0.5 + Vector3.UP)
		_tube(bark, PackedVector3Array([start, k1, tip]), PackedFloat32Array([0.13, 0.085, 0.0]), 4, KIND_IPE, b0, b1, r, crown_y)
		# two twigs from the elbow to the outer clusters around this limb
		var used: Array[Vector3] = []
		for t in 2:
			var target: Vector3 = _nearest(outer, k1 + _dir(az + (t * 2 - 1) * 35.0) * 1.6, used)
			used.append(target)
			_tube(bark, PackedVector3Array([k1, target]), PackedFloat32Array([0.05, 0.0]), 3, KIND_IPE, b0, b1, r, crown_y)
	for p: Vector3 in inner:
		_tuft(crown, p, Vector3(0.92, 0.62, 0.88) * r.randf_range(0.9, 1.08), cc, cr, r, fl_d, fl_l, 1.0, Vector2(0.45, 0.9))
	for p: Vector3 in outer:
		_tuft(crown, p, Vector3(0.82, 0.55, 0.8) * r.randf_range(0.88, 1.08), cc, cr, r, fl_d, fl_l, 1.0, Vector2(0.5, 1.0))
	_tuft(crown, Vector3(0.05, 6.45, 0.0), Vector3(0.95, 0.55, 0.9), cc, cr, r, fl_d, fl_l, 1.0, Vector2(0.5, 1.0))
	return _finish(bark, crown)


static func _nearest(points: Array[Vector3], to: Vector3, exclude: Array[Vector3] = []) -> Vector3:
	var best: Vector3 = points[0]
	var bd: float = INF
	for p: Vector3 in points:
		if exclude.has(p):
			continue
		var d: float = p.distance_squared_to(to)
		if d < bd:
			bd = d
			best = p
	return best


# --- buriti ------------------------------------------------------------------------------------------------

## Buriti palm: tall smooth ringed trunk, crown shaft and an irregular ball of eleven costapalmate fan leaves on
## long bare petioles (9 radiating segments each, tips split and hanging), plus a skirt of three dead, straw-brown
## fans hanging along the trunk. ~12 m tall, crown ~6 m.
static func _buriti() -> Mesh:
	var r: RandomNumberGenerator = _rng("buriti_hd")
	var bark: Surf = Surf.new()
	var crown: Surf = Surf.new()
	var b0: Color = Color(0.46, 0.42, 0.36)
	var b1: Color = Color(0.58, 0.53, 0.45)
	var top: float = 10.0
	_tube(bark, PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.05, 3.5, 0.02), Vector3(0.12, 7.0, 0.05),
		Vector3(0.16, top - 0.5, 0.06), Vector3(0.17, top + 0.25, 0.06), Vector3(0.17, top + 0.9, 0.06)]),
		PackedFloat32Array([0.27, 0.25, 0.235, 0.22, 0.32, 0.0]), 7, KIND_PALM, b0, b1, r, top + 5.0)
	var head: Vector3 = Vector3(0.17, top + 0.35, 0.06)
	var green_d: Color = Color(0.16, 0.3, 0.11)
	var green_l: Color = Color(0.46, 0.6, 0.25)
	var leaves: int = 11
	for i in leaves:
		var yaw: float = float(i) * 137.5 + r.randf_range(-8.0, 8.0)
		var tier: float = float(i) / float(leaves - 1)            # 0 = youngest (upright) .. 1 = oldest (low)
		var elev: float = lerpf(62.0, -22.0, tier) + r.randf_range(-6.0, 6.0)
		var pet: float = lerpf(1.05, 1.6, tier) * r.randf_range(0.92, 1.08)
		var blade: float = lerpf(1.3, 1.55, tier) * r.randf_range(0.94, 1.06)
		_fan_leaf(crown, head + Vector3(0, 0.15 - 0.4 * tier, 0), yaw, elev, pet, blade, 210.0, 9,
			lerpf(0.45, 0.8, tier), r, green_d, green_l, lerpf(1.0, 0.82, tier))
	# dead skirt: closed fans hanging from the crown shaft
	var dead_d: Color = Color(0.38, 0.32, 0.23)
	var dead_l: Color = Color(0.58, 0.5, 0.36)
	for i in 3:
		_fan_leaf(crown, head + Vector3(0, -0.4, 0), 40.0 + 120.0 * float(i) + r.randf_range(-20.0, 20.0),
			r.randf_range(-72.0, -62.0), 0.55, 1.0, 80.0, 3, 0.55, r, dead_d, dead_l, 0.75)
	return _finish(bark, crown)


## Costapalmate fan leaf, 1 + 2 * segs triangles, flat shaded so the folds read:
##   petiole: one long thin triangle from the crown shaft to the insertion point;
##   blade:   a triangle fan of `segs` thin sectors radiating from the insertion point over `span_deg`, alternately
##            raised and sunk (pleats) and cupped up at the sides;
##   tips:    one thin triangle per sector beyond the fan rim, of alternating length and hanging down by `droop`,
##            so the outline is serrated by the vertices themselves.
static func _fan_leaf(s: Surf, base: Vector3, yaw: float, elev: float, pet_len: float, blade_r: float, span_deg: float,
		segs: int, droop: float, r: RandomNumberGenerator, dark: Color, light: Color, ao: float) -> void:
	var d: Vector3 = _dir(yaw)
	var side: Vector3 = Vector3(-d.z, 0.0, d.x)
	var e: float = deg_to_rad(elev)
	var fwd: Vector3 = (d * cos(e) + Vector3.UP * sin(e)).normalized()
	var up_l: Vector3 = side.cross(fwd).normalized()          # leaf "top" normal
	if up_l.y < 0.0:
		up_l = -up_l
	var ins: Vector3 = base + fwd * pet_len + Vector3.DOWN * 0.06 * pet_len   # insertion point (hastula)
	var pc: Color = dark.lerp(light, 0.4)
	pc.a = 0.7 * ao
	_flat_tri(s, base - side * 0.055, base + side * 0.055, ins, pc, pc, pc, Vector2(0.05, 0.4), Vector2(0.05, 0.4),
		Vector2(0.3, 0.6), up_l, up_l)
	var rims: Array[Vector3] = []
	var dirs: Array[Vector3] = []
	var rr_in: float = blade_r * 0.62
	for j in segs + 1:
		var a: float = lerpf(-0.5, 0.5, float(j) / float(segs))
		var ph: float = deg_to_rad(span_deg) * a
		var w: Vector3 = (fwd * cos(ph) + side * sin(ph)).normalized()
		var fold: float = 1.0 if j % 2 == 0 else -1.0
		var cup: float = absf(sin(ph)) * 0.18
		dirs.append(w)
		rims.append(ins + w * rr_in * r.randf_range(0.94, 1.06) + up_l * (cup + 0.06 * fold) + Vector3.DOWN * droop * 0.25)
	var cc: Color = dark.lerp(light, 0.2)
	cc.a = 0.68 * ao
	for j in segs:
		var cm0: Color = dark.lerp(light, r.randf_range(0.45, 0.65))
		cm0.a = 0.85 * ao
		var cm1: Color = cm0
		var ct: Color = dark.lerp(light, r.randf_range(0.8, 1.0))
		ct.a = ao
		_flat_tri(s, ins, rims[j], rims[j + 1], cc, cm0, cm1, Vector2(0.35, 0.8), Vector2(0.7, 0.9), Vector2(0.7, 0.9),
			up_l, up_l)
		# hanging split tip of this segment
		var wm: Vector3 = (dirs[j] + dirs[j + 1]).normalized()
		var long: float = 1.0 if j % 2 == 0 else 0.8
		var tip: Vector3 = (rims[j] + rims[j + 1]) * 0.5 + wm * blade_r * 0.5 * long * r.randf_range(0.9, 1.1) 			+ Vector3.DOWN * droop * long * r.randf_range(0.85, 1.15)
		_flat_tri(s, rims[j], rims[j + 1], tip, cm0, cm1, ct, Vector2(0.7, 0.9), Vector2(0.7, 0.9), Vector2(1.0, 1.0),
			up_l, up_l)
