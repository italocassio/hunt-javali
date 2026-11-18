extends RefCounted
## HD ground flora: grass_tuft, shrub, termite_mound, soy_patch, soy_eaten, corn_patch, corn_eaten.
## Pure procedural. One shared shader (ground_flora_hd.gdshader), four shared materials (grass, shrub, crop, mound),
## one surface per id. Called by flora_library.gd: GroundHD.build(id) -> Mesh (null for unknown ids).
## Triangle counts are flat per id (see the tables in docs/arquitetura.md 7.5); the look comes from the shader,
## from authored normals (up-biased on grass and crops, inflated on shrubs) and from the vertex colour gradient.

const SHADER: Shader = preload("res://assets/models/flora/ground_flora_hd.gdshader")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")

const UP: Vector3 = Vector3(0.0, 1.0, 0.0)

static var _mats: Dictionary = {}


static func ids() -> PackedStringArray:
	return PackedStringArray(["grass_tuft", "shrub", "termite_mound", "soy_patch", "soy_eaten", "corn_patch", "corn_eaten"])


static func build(id: StringName) -> Mesh:
	match id:
		&"grass_tuft": return _grass()
		&"shrub": return _shrub()
		&"termite_mound": return _mound()
		&"soy_patch": return _soy(true)
		&"soy_eaten": return _soy(false)
		&"corn_patch": return _corn(true)
		&"corn_eaten": return _corn(false)
	return null


# --- materials -------------------------------------------------------------------------------------

static func material(kind: StringName) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = SHADER
	var wood: ShaderMaterial = RifleHD.get_materials()[RifleHD.SURF_WOOD]
	m.set_shader_parameter(&"noise_tex", wood.get_shader_parameter(&"noise_tex"))
	match kind:
		&"grass":
			m.set_shader_parameter(&"wind_strength", 0.16)
			m.set_shader_parameter(&"wind_speed", 1.8)
			m.set_shader_parameter(&"inst_tint", 0.22)
			m.set_shader_parameter(&"patch_tint", 0.30)
			m.set_shader_parameter(&"dry_amount", 0.40)
			m.set_shader_parameter(&"translucency", 0.45)
		&"shrub":
			m.set_shader_parameter(&"wind_strength", 0.05)
			m.set_shader_parameter(&"flutter", 0.012)
			m.set_shader_parameter(&"inst_tint", 0.18)
			m.set_shader_parameter(&"patch_tint", 0.10)
			m.set_shader_parameter(&"dry_amount", 0.20)
			m.set_shader_parameter(&"speckle", 0.9)
			m.set_shader_parameter(&"speckle_scale", 4.0)
			m.set_shader_parameter(&"translucency", 0.30)
		&"crop":
			m.set_shader_parameter(&"wind_strength", 0.07)
			m.set_shader_parameter(&"wind_speed", 1.6)
			m.set_shader_parameter(&"flutter", 0.03)
			m.set_shader_parameter(&"inst_tint", 0.14)
			m.set_shader_parameter(&"patch_tint", 0.26)
			m.set_shader_parameter(&"dry_amount", 0.35)
			m.set_shader_parameter(&"speckle", 0.65)
			m.set_shader_parameter(&"speckle_scale", 3.0)
			m.set_shader_parameter(&"translucency", 0.2)
			m.set_shader_parameter(&"height_var", 0.35)
		&"mound":
			m.set_shader_parameter(&"wind_strength", 0.0)
			m.set_shader_parameter(&"inst_tint", 0.12)
			m.set_shader_parameter(&"patch_tint", 0.0)
			m.set_shader_parameter(&"dry_amount", 0.0)
			m.set_shader_parameter(&"mottle", 1.0)
	_mats[kind] = m
	return m


# --- mesh builder ----------------------------------------------------------------------------------

class Builder:
	var p: PackedVector3Array = PackedVector3Array()
	var n: PackedVector3Array = PackedVector3Array()
	var c: PackedColorArray = PackedColorArray()
	var u: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()

	func vtx(pos: Vector3, nrm: Vector3, col: Color, uv: Vector2 = Vector2.ZERO) -> int:
		p.push_back(pos)
		n.push_back(nrm.normalized())
		c.push_back(col)
		u.push_back(uv)
		return p.size() - 1

	## outward != ZERO fixes the winding for single-sided (cull_back) use; the shader here is cull_disabled so it is optional.
	func tri(a: int, b: int, d: int, outward: Vector3 = Vector3.ZERO) -> void:
		if outward != Vector3.ZERO:
			var g: Vector3 = (p[b] - p[a]).cross(p[d] - p[a])
			if g.dot(outward) > 0.0:
				var t: int = b
				b = d
				d = t
		idx.push_back(a)
		idx.push_back(b)
		idx.push_back(d)

	@warning_ignore("integer_division")
	func tris() -> int:
		return idx.size() / 3

	func commit(mat: Material) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = p
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = u
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		return mesh


static func _rng(id: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash(id)
	return r


static func _col(r: float, g: float, b: float, a: float) -> Color:
	return Color(r, g, b, a)


# --- grass: 8 blades, one triangle each ------------------------------------------------------------

static func _grass() -> Mesh:
	var b: Builder = Builder.new()
	var r: RandomNumberGenerator = _rng("grass_hd")
	for i: int in 8:
		var a: float = TAU * (float(i) + r.randf_range(-0.3, 0.3)) / 8.0
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var h: float = r.randf_range(0.26, 0.44)
		if i % 3 == 0:
			h *= 0.7
		var lean: float = r.randf_range(0.05, 0.16) * h / 0.34
		var ld: Vector3 = out.rotated(UP, r.randf_range(-0.6, 0.6))
		var side: Vector3 = Vector3(-ld.z, 0.0, ld.x) * r.randf_range(0.028, 0.042)
		var base: Vector3 = out * r.randf_range(0.015, 0.075)
		var tip: Vector3 = base + ld * lean + Vector3(0.0, h, 0.0)
		var nrm: Vector3 = Vector3(ld.x * 0.35, 1.0, ld.z * 0.35)
		var live: bool = r.randf() < 0.3
		var k: float = r.randf_range(0.88, 1.1)
		var c0: Color = _col(0.27 * k, 0.28 * k, 0.09 * k, 0.0)
		var c1: Color = _col(0.58, 0.62, 0.24, 1.0) if live else _col(0.92 * k, 0.84 * k, 0.48 * k, 1.0)
		b.tri(b.vtx(base - side, nrm, c0, Vector2(0.0, 0.0)), b.vtx(base + side, nrm, c0, Vector2(0.0, 0.0)), b.vtx(tip, nrm, c1, Vector2(1.0, 0.0)))
	return b.commit(material(&"grass"))


# --- shrub: 10 faceted lumps with inflated normals + 14 leaf sprays + 4 stems ----------------------

static func _shrub() -> Mesh:
	var b: Builder = Builder.new()
	var r: RandomNumberGenerator = _rng("shrub_hd")
	var centre: Vector3 = Vector3(0.0, 0.45, 0.0)
	var lumps: Array = []   # [position, radii]
	for i: int in 5:
		var a: float = TAU * (float(i) + r.randf_range(-0.25, 0.25)) / 5.0
		lumps.append([Vector3(cos(a) * 0.40, 0.33 + r.randf_range(-0.04, 0.05), sin(a) * 0.33), Vector3(0.30, 0.27, 0.28)])
	for i: int in 3:
		var a: float = TAU * (float(i) + r.randf_range(-0.2, 0.2)) / 3.0 + 0.5
		lumps.append([Vector3(cos(a) * 0.20, 0.58 + r.randf_range(-0.04, 0.04), sin(a) * 0.18), Vector3(0.29, 0.26, 0.27)])
	lumps.append([Vector3(0.10, 0.80, -0.04), Vector3(0.25, 0.22, 0.24)])
	lumps.append([Vector3(-0.14, 0.74, 0.10), Vector3(0.22, 0.20, 0.22)])
	for l: Array in lumps:
		_lump(b, l[0], l[1], r, centre)
	# leaf sprays: single skinny triangles that break the outline
	for i: int in 14:
		var a: float = TAU * (float(i) + r.randf_range(-0.3, 0.3)) / 14.0
		var d: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var y: float = r.randf_range(0.22, 0.95)
		var rad: float = (0.52 - 0.28 * (y - 0.2)) * r.randf_range(0.85, 1.05)
		var o: Vector3 = d * rad * 0.8 + Vector3(0.0, y, 0.0)
		var tip: Vector3 = o + d * r.randf_range(0.18, 0.30) + Vector3(0.0, r.randf_range(-0.10, 0.14), 0.0)
		var sd: Vector3 = Vector3(-d.z, 0.0, d.x) * 0.05
		var nrm: Vector3 = (d + Vector3(0.0, 0.5, 0.0))
		var cb: Color = _shrub_col(y, r.randf_range(0.9, 1.1))
		var ct: Color = _shrub_col(minf(y + 0.25, 1.0), r.randf_range(1.0, 1.15))
		b.tri(b.vtx(o - sd, nrm, cb, Vector2(0.0, 0.0)), b.vtx(o + sd, nrm, cb, Vector2(0.0, 0.0)), b.vtx(tip, nrm, ct, Vector2(1.0, 0.0)))
	# dark woody stems visible under the foliage
	for i: int in 4:
		var a: float = TAU * (float(i) + r.randf()) / 4.0
		var d: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var sd: Vector3 = Vector3(-d.z, 0.0, d.x) * 0.025
		var cs: Color = _col(0.26, 0.17, 0.12, 0.0)
		var ct2: Color = _col(0.34, 0.24, 0.16, 0.2)
		var nrm2: Vector3 = d + Vector3(0.0, 0.3, 0.0)
		b.tri(b.vtx(d * 0.06 - sd, nrm2, cs), b.vtx(d * 0.06 + sd, nrm2, cs), b.vtx(d * 0.3 + Vector3(0.0, 0.34, 0.0), nrm2, ct2))
	return b.commit(material(&"shrub"))


static func _shrub_col(y: float, k: float) -> Color:
	var t: float = clampf(y / 1.0, 0.0, 1.0)
	var lo: Color = _col(0.19, 0.29, 0.10, 0.0)
	var hi: Color = _col(0.48, 0.56, 0.20, 1.0)
	var c: Color = lo.lerp(hi, t)
	return _col(c.r * k, c.g * k, c.b * k, c.a)


## Five-sided bipyramid (10 triangles) with irregular radii; normals mix the lump and the whole-shrub direction.
static func _lump(b: Builder, pos: Vector3, radii: Vector3, r: RandomNumberGenerator, centre: Vector3) -> void:
	var yaw: float = r.randf() * TAU
	var k: float = r.randf_range(0.92, 1.1)
	var ring: Array[int] = []
	for i: int in 5:
		var a: float = yaw + TAU * float(i) / 5.0
		var rr: float = r.randf_range(0.8, 1.15)
		var off: Vector3 = Vector3(cos(a) * radii.x * rr, r.randf_range(-0.06, 0.06), sin(a) * radii.z * rr)
		ring.append(_lump_vtx(b, pos + off, pos, centre, k))
	var top: int = _lump_vtx(b, pos + Vector3(r.randf_range(-0.05, 0.05), radii.y * r.randf_range(0.9, 1.15), r.randf_range(-0.05, 0.05)), pos, centre, k)
	var bot: int = _lump_vtx(b, pos + Vector3(0.0, -radii.y * 0.9, 0.0), pos, centre, k)
	for i: int in 5:
		var j: int = (i + 1) % 5
		b.tri(ring[i], ring[j], top)
		b.tri(ring[j], ring[i], bot)


static func _lump_vtx(b: Builder, p: Vector3, lump_c: Vector3, centre: Vector3, k: float) -> int:
	var nl: Vector3 = (p - lump_c).normalized()
	var ns: Vector3 = (p - centre).normalized()
	var nrm: Vector3 = nl * 0.55 + ns * 0.45
	var col: Color = _shrub_col(p.y, k)
	return b.vtx(p, nrm, col, Vector2(clampf(p.y, 0.0, 1.0), 0.0))


# --- termite mound: lathe body (5 rings + apex), 5 spires, 3 buttresses ---------------------------

static func _mound() -> Mesh:
	var b: Builder = Builder.new()
	var r: RandomNumberGenerator = _rng("mound_hd")
	var sides: int = 10
	var ys: Array[float] = [0.0, 0.12, 0.30, 0.55, 0.80, 1.00]
	var rs: Array[float] = [0.62, 0.55, 0.46, 0.34, 0.20, 0.10]
	var cols: Array[Color] = [_col(0.26, 0.13, 0.09, 0.0), _col(0.33, 0.16, 0.10, 0.0), _col(0.40, 0.20, 0.12, 0.0),
		_col(0.46, 0.24, 0.15, 0.0), _col(0.51, 0.28, 0.18, 0.0), _col(0.55, 0.31, 0.20, 0.0)]
	var rings: Array = []
	for k: int in ys.size():
		var row: Array[int] = []
		var slope: float = 0.0
		var k0: int = maxi(k - 1, 0)
		var k1: int = mini(k + 1, ys.size() - 1)
		slope = (rs[k0] - rs[k1]) / (ys[k1] - ys[k0])
		var shift: Vector3 = Vector3(0.05, 0.0, -0.035) * ys[k]
		var radii: Array[float] = []
		for i: int in sides:
			radii.append(rs[k] * r.randf_range(0.88, 1.12))
		for i: int in sides + 1:
			var ii: int = i % sides
			var a: float = TAU * float(ii) / float(sides)
			var pos: Vector3 = Vector3(cos(a) * radii[ii], ys[k], sin(a) * radii[ii]) + shift
			var nrm: Vector3 = Vector3(cos(a), slope, sin(a)) + Vector3(r.randf_range(-0.12, 0.12), 0.0, r.randf_range(-0.12, 0.12))
			row.append(b.vtx(pos, nrm, cols[k], Vector2(float(i) / float(sides), ys[k])))
		rings.append(row)
	var centre: Vector3 = Vector3(0.0, 0.5, 0.0)
	for k: int in ys.size() - 1:
		for i: int in sides:
			var a0: int = rings[k][i]
			var a1: int = rings[k][i + 1]
			var b0: int = rings[k + 1][i]
			var b1: int = rings[k + 1][i + 1]
			b.tri(a0, a1, b1, b.p[a0] - centre)
			b.tri(a0, b1, b0, b.p[a0] - centre)
	# apex fan, slightly off axis and irregular
	var apex_p: Vector3 = Vector3(0.07, 1.2, -0.05)
	var apex: int = b.vtx(apex_p, UP, cols[5], Vector2(0.5, 1.2))
	for i: int in sides:
		b.tri(rings[5][i], rings[5][i + 1], apex, apex_p - Vector3(0.0, 0.5, 0.0))
	# spires (torreoes): 6-sided cones rooted on the flanks
	var spires: Array = [[0.10, 0.36, 0.34, 0.40], [1.5, 0.46, 0.30, 0.30], [2.7, 0.30, 0.26, 0.32], [4.1, 0.52, 0.26, 0.26], [5.3, 0.26, 0.30, 0.36]]
	for s: Array in spires:
		_spire(b, float(s[0]), float(s[1]), float(s[2]), float(s[3]), r)
	# buttresses at the foot
	for i: int in 3:
		var a: float = 0.7 + TAU * float(i) / 3.0 + r.randf_range(-0.3, 0.3)
		_cone(b, Vector3(cos(a) * 0.52, 0.0, sin(a) * 0.52), Vector3(cos(a) * 0.36, r.randf_range(0.20, 0.30), sin(a) * 0.36), 0.22, cols[1], cols[2], a, r)
	return b.commit(material(&"mound"))


static func _spire(b: Builder, a: float, y: float, height: float, lean: float, r: RandomNumberGenerator) -> void:
	var rad_at_y: float = 0.62 - 0.42 * clampf(y / 1.0, 0.0, 1.0)
	var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
	var root: Vector3 = out * (rad_at_y - 0.05) + Vector3(0.0, y, 0.0)
	var tip: Vector3 = out * (rad_at_y + lean * 0.5) + Vector3(0.0, y + height, 0.0)
	tip += Vector3(r.randf_range(-0.05, 0.05), 0.0, r.randf_range(-0.05, 0.05))
	var t: float = clampf(y / 1.0, 0.0, 1.0)
	var cb: Color = _col(0.36 + 0.1 * t, 0.17 + 0.07 * t, 0.10 + 0.06 * t, 0.0)
	var ct: Color = _col(0.54, 0.30, 0.19, 0.0)
	_cone(b, root, tip, 0.17, cb, ct, a, r)


## 6-sided cone: ring of radius r0 at `root` (axis along root -> tip), apex at `tip`.
static func _cone(b: Builder, root: Vector3, tip: Vector3, r0: float, cb: Color, ct: Color, a_around: float, r: RandomNumberGenerator) -> void:
	var axis: Vector3 = (tip - root).normalized()
	var s1: Vector3 = axis.cross(UP)
	if s1.length() < 0.1:
		s1 = Vector3(1.0, 0.0, 0.0)
	s1 = s1.normalized()
	var s2: Vector3 = axis.cross(s1).normalized()
	var u0: float = a_around / TAU
	var ring: Array[int] = []
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		var d: Vector3 = s1 * cos(a) + s2 * sin(a)
		var pos: Vector3 = root + d * r0 * r.randf_range(0.85, 1.15)
		var uv: Vector2 = Vector2(u0 + d.dot(s1) * 0.12, pos.y)
		ring.append(b.vtx(pos, d + axis * 0.5 + Vector3(0.0, 0.35, 0.0), cb, uv))
	var ap: int = b.vtx(tip, axis, ct, Vector2(u0, tip.y))
	var centre: Vector3 = (root + tip) * 0.5
	for i: int in 6:
		b.tri(ring[i], ring[(i + 1) % 6], ap, b.p[ring[i]] - centre)


## A stem or leaf lying near the ground: one triangle from the root to a raised tip.
static func _lying(b: Builder, root: Vector3, dir: Vector3, length: float, rise: float, width: float, cb: Color, ct: Color) -> void:
	var sd: Vector3 = Vector3(-dir.z, 0.0, dir.x) * width
	var nrm: Vector3 = Vector3(dir.x * 0.3, 1.0, dir.z * 0.3)
	b.tri(b.vtx(root - sd, nrm, cb, Vector2(0.0, 0.0)), b.vtx(root + sd, nrm, cb, Vector2(0.0, 0.0)),
		b.vtx(root + dir * length + Vector3(0.0, rise, 0.0), nrm, ct, Vector2(1.0, 0.0)))


## Corn leaf: lozenge of two triangles that rises out of the stalk then droops (a dog-leg, so it reads as an arc).
static func _leaf(b: Builder, p0: Vector3, dir: Vector3, reach: float, rise: float, droop: float, width: float, hmax: float, c0: Color, cm: Color, ct: Color) -> void:
	var m: Vector3 = p0 + dir * reach * 0.5 + Vector3(0.0, rise, 0.0)
	var t: Vector3 = m + dir * reach * 0.5 + Vector3(0.0, -droop, 0.0)
	var sd: Vector3 = Vector3(-dir.z, 0.0, dir.x) * width
	var nrm: Vector3 = dir * 0.3 + UP
	c0.a = clampf(p0.y / hmax, 0.0, 1.0)
	cm.a = clampf(m.y / hmax, 0.0, 1.0)
	ct.a = clampf(t.y / hmax, 0.0, 1.0)
	var v0: int = b.vtx(p0, nrm, c0, Vector2(0.0, 0.0))
	var v1: int = b.vtx(m + sd, nrm, cm, Vector2(0.7, 0.0))
	var v2: int = b.vtx(m - sd, nrm, cm, Vector2(0.7, 0.0))
	var v3: int = b.vtx(t, nrm, ct, Vector2(1.0, 0.0))
	b.tri(v0, v1, v2)
	b.tri(v1, v3, v2)


# --- soy: six irregular foliage mounds in a rosette (almost rotation-symmetric, so the instance yaw does not show) ---

static func _pyr(b: Builder, pos: Vector3, rad: float, h: float, r: RandomNumberGenerator, cb: Color, ct: Color, hmax: float, top_rad: float = 0.0) -> void:
	## Four-sided mound. top_rad > 0 makes a truncated bush top (8 triangles, open on top), otherwise a pyramid (4).
	var yaw: float = r.randf() * TAU
	var cbot: Color = cb
	cbot.a = 0.0
	var ring: Array[int] = []
	var tops: Array[int] = []
	var apex: int = -1
	if top_rad <= 0.0:
		var ctop: Color = ct
		ctop.a = clampf(h / hmax, 0.0, 1.0)
		apex = b.vtx(pos + Vector3(r.randf_range(-0.3, 0.3) * rad, h, r.randf_range(-0.3, 0.3) * rad), UP, ctop, Vector2(0.6, 0.0))
	for i: int in 4:
		var a: float = yaw + float(i) * PI * 0.5
		var d: Vector3 = Vector3(cos(a), 0.0, sin(a))
		ring.append(b.vtx(pos + d * rad * r.randf_range(0.82, 1.18), d * 0.6 + Vector3(0.0, 1.0, 0.0), cbot, Vector2(0.0, 0.0)))
		if top_rad > 0.0:
			var hh: float = h * r.randf_range(0.82, 1.1)
			var ctop2: Color = ct
			ctop2.a = clampf(hh / hmax, 0.0, 1.0)
			tops.append(b.vtx(pos + d * top_rad * r.randf_range(0.7, 1.2) + Vector3(0.0, hh, 0.0), d * 0.25 + Vector3(0.0, 1.0, 0.0), ctop2, Vector2(0.6, 0.0)))
	for i: int in 4:
		var j: int = (i + 1) % 4
		if top_rad > 0.0:
			b.tri(ring[i], ring[j], tops[j])
			b.tri(ring[i], tops[j], tops[i])
		else:
			b.tri(ring[i], ring[j], apex)
	if top_rad > 0.0:   # close the top so no hollow shows
		b.tri(tops[0], tops[1], tops[2])
		b.tri(tops[0], tops[2], tops[3])


static func _soy(healthy: bool) -> Mesh:
	var b: Builder = Builder.new()
	var r: RandomNumberGenerator = _rng("soy_hd" if healthy else "soy_eaten_hd")
	if healthy:
		var cb: Color = _col(0.10, 0.22, 0.07, 0.0)
		var ct: Color = _col(0.38, 0.54, 0.21, 1.0)
		_pyr(b, Vector3(0.38, 0.0, -0.30), 0.72, 0.56, r, cb, ct, 0.62, 0.34)
		_pyr(b, Vector3(-0.42, 0.0, 0.22), 0.70, 0.50, r, cb, ct, 0.62, 0.30)
		_pyr(b, Vector3(0.30, 0.0, 0.62), 0.46, 0.38, r, cb, ct, 0.62)
	else:
		var cb: Color = _col(0.30, 0.20, 0.11, 0.0)
		var ct: Color = _col(0.54, 0.43, 0.20, 1.0)
		_pyr(b, Vector3(-0.35, 0.0, -0.3), 0.40, 0.12, r, cb, ct, 0.62)
		_pyr(b, Vector3(0.45, 0.0, 0.35), 0.34, 0.10, r, cb, ct, 0.62)
		var sb: Color = _col(0.38, 0.30, 0.13, 0.0)
		var st: Color = _col(0.68, 0.60, 0.30, 0.3)
		for i: int in 8:
			var a: float = TAU * float(i) / 8.0 + r.randf_range(-0.3, 0.3)
			var pos: Vector3 = Vector3(r.randf_range(-0.8, 0.8), 0.01, r.randf_range(-0.8, 0.8))
			_lying(b, pos, Vector3(cos(a), 0.0, sin(a)), r.randf_range(0.4, 0.6), r.randf_range(0.05, 0.1), 0.055, sb, st)
	return b.commit(material(&"crop"))


# --- corn -----------------------------------------------------------------------------------------

static func _corn(healthy: bool) -> Mesh:
	var b: Builder = Builder.new()
	var r: RandomNumberGenerator = _rng("corn_hd" if healthy else "corn_eaten_hd")
	if healthy:
		# three plants (9 triangles each): stalk, tassel, three arching leaves spread along the stalk, one low yellow leaf
		var plants: Array[Vector2] = [Vector2(-0.45, -0.4), Vector2(0.55, -0.05), Vector2(-0.15, 0.6)]
		var sb: Color = _col(0.30, 0.36, 0.12, 0.0)
		var stp: Color = _col(0.50, 0.50, 0.20, 1.0)
		var heights: Array[float] = [0.45, 0.95, 1.5]
		for pi: int in plants.size():
			var pl: Vector2 = plants[pi] + Vector2(r.randf_range(-0.06, 0.06), r.randf_range(-0.06, 0.06))
			var base: Vector3 = Vector3(pl.x, 0.0, pl.y)
			var h: float = r.randf_range(1.85, 2.0)
			var sdir: Vector3 = Vector3(cos(float(pi) * 2.1), 0.0, sin(float(pi) * 2.1))
			var ss: Vector3 = Vector3(-sdir.z, 0.0, sdir.x) * 0.05
			var snrm: Vector3 = sdir * 0.4 + UP
			var top: Vector3 = base + Vector3(0.03, h, 0.02)
			b.tri(b.vtx(base - ss, snrm, sb, Vector2(0.0, 0.0)), b.vtx(base + ss, snrm, sb, Vector2(0.0, 0.0)), b.vtx(top, snrm, stp, Vector2(0.3, 0.0)))
			# tassel: thin spray at the very top
			var tc: Color = _col(0.70, 0.62, 0.34, 1.0)
			var td: Vector3 = Vector3(cos(float(pi) * 1.3), 0.0, sin(float(pi) * 1.3))
			var ts: Vector3 = Vector3(-td.z, 0.0, td.x) * 0.06
			var tbase: Vector3 = top - Vector3(0.0, 0.32, 0.0)
			b.tri(b.vtx(tbase - ts, UP, stp, Vector2(0.4, 0.0)), b.vtx(tbase + ts, UP, stp, Vector2(0.4, 0.0)), b.vtx(top + td * 0.1 + Vector3(0.0, 0.1, 0.0), UP, tc, Vector2(1.0, 0.0)))
			var a0: float = r.randf() * TAU
			for li: int in 3:
				var ang: float = a0 + float(li) * 2.5 + r.randf_range(-0.3, 0.3)
				var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
				var low: float = 1.0 - float(li) * 0.5          # 1 low, 0 high: low leaves age first (yellow)
				var y: float = heights[li] + r.randf_range(-0.05, 0.05)
				var c0: Color = _col(0.16 + 0.14 * low, 0.28 + 0.08 * low, 0.08 + 0.02 * low, 0.0)
				var cm: Color = _col(0.21 + 0.22 * low, 0.35 + 0.07 * low, 0.10 + 0.04 * low, 0.0)
				var ct: Color = _col(0.58 + 0.04 * low, 0.54, 0.20, 0.0)
				_leaf(b, base + Vector3(0.0, y, 0.0), dir, r.randf_range(0.72, 0.86), 0.16 + 0.05 * float(li), 0.40 + 0.12 * low, 0.10, 2.0, c0, cm, ct)
			var lowdir: Vector3 = Vector3(cos(a0 + 1.2), 0.0, sin(a0 + 1.2))
			_lying(b, base + Vector3(0.0, 0.3, 0.0), lowdir, 0.6, -0.22, 0.06, _col(0.36, 0.38, 0.13, 0.15), _col(0.62, 0.56, 0.22, 0.45))
	else:
		var sb: Color = _col(0.34, 0.30, 0.12, 0.0)
		var st: Color = _col(0.62, 0.56, 0.24, 1.0)
		var stumps: Array[Vector3] = [Vector3(-0.5, 0.0, -0.4), Vector3(0.45, 0.0, 0.1), Vector3(-0.1, 0.0, 0.6)]
		for si: int in stumps.size():
			var s: Vector3 = stumps[si]
			var hh: float = r.randf_range(0.33, 0.5)
			var bend: Vector3 = Vector3(r.randf_range(-0.14, 0.14), 0.0, r.randf_range(-0.14, 0.14))
			for k: int in 2:
				var dd: Vector3 = Vector3(cos(float(k) * PI * 0.5 + float(si)), 0.0, sin(float(k) * PI * 0.5 + float(si)))
				var ss2: Vector3 = Vector3(-dd.z, 0.0, dd.x) * 0.06
				var nn: Vector3 = dd * 0.4 + UP
				var cb2: Color = sb
				var ct2: Color = st
				cb2.a = 0.0
				ct2.a = 0.5
				b.tri(b.vtx(s - ss2, nn, cb2), b.vtx(s + ss2, nn, cb2), b.vtx(s + bend + Vector3(0.0, hh, 0.0), nn, ct2, Vector2(0.3, 0.0)))
		var c0: Color = _col(0.30, 0.34, 0.12, 0.0)
		var cm: Color = _col(0.44, 0.46, 0.18, 0.0)
		var ct: Color = _col(0.62, 0.56, 0.24, 0.0)
		var spots: Array[Vector3] = [Vector3(-0.7, 0.04, 0.5), Vector3(0.1, 0.03, -0.55), Vector3(0.7, 0.04, -0.2),
			Vector3(0.1, 0.03, 0.15), Vector3(-0.2, 0.04, -0.15), Vector3(0.6, 0.03, 0.7)]
		for li: int in spots.size():
			var ang: float = float(li) * 1.1 + r.randf_range(-0.4, 0.4)
			_leaf(b, spots[li], Vector3(cos(ang), 0.0, sin(ang)), r.randf_range(0.7, 0.9), 0.08, 0.02, 0.11, 0.5, c0, cm, ct)
	return b.commit(material(&"crop"))
