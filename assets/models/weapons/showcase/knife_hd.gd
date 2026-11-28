extends Node3D
## HD procedural hunting knife in four tiers (1 farm knife .. 4 premium hunter's knife), blade about 0.15-0.23 m.
## Knife space: s = distance forward from the pommel (z = -s), so the TIP points to -Z and the HANDLE sits at +Z;
## y up (the cutting edge is the lower one), x to the right. One mesh, two surfaces (wood, hard surface) that use
## the materials already shared by the guns. weapon-art tool contract: set_hip_pose(on), set_cast_shadows(on).
## knife_view.gd uses only the static get_model(level). The handle (position, length, grip point) is IDENTICAL on every
## tier, because the first-person arm is built once around it: only blade, guard, bolster, pommel, pins and colours change.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const CarbineHD := preload("res://assets/models/weapons/showcase/carbine_22_hd.gd")

const SURF_WOOD: int = 0
const SURF_HARD: int = 1

const HANDLE_LEN: float = 0.120
const MAX_LEVEL: int = 4
const AO_RAYS: int = 6
const AO_RADIUS: float = 0.012
const SEGS: int = 10
const BLADE_HALF_THICK: float = 0.0016
const BLADE_BEVEL: float = 0.0013

## Hip pose of the standalone model (only used outside the weapon art tool): tilted like the in-game rest pose.
const HIP_EULER: Vector3 = Vector3(0.55, 0.25, 0.0)

## Painted steel / brass are NON-metal on purpose: a metallic surface only mirrors the dark studio and game sky and
## reads as a black or bluish plank. [albedo, metallic, roughness]
const STEEL: Array = [Color(0.54, 0.55, 0.58), 0.0, 0.32]
const BRASS: Array = [Color(0.62, 0.52, 0.30), 0.0, 0.42]
const DARK_BRASS: Array = [Color(0.30, 0.24, 0.14), 0.0, 0.45]
const DARK_STEEL: Array = [Color(0.20, 0.205, 0.23), 0.0, 0.40]

## Handle profile (s, radius): identical on every level.
const HANDLE_PROFILE: Array = [
	Vector3(0.008, 0.0, 0.0), Vector3(0.008, 0.0100, 0.0), Vector3(0.016, 0.0124, 0.0), Vector3(0.036, 0.0140, 0.0),
	Vector3(0.060, 0.0132, 0.0), Vector3(0.084, 0.0142, 0.0), Vector3(0.104, 0.0134, 0.0), Vector3(0.112, 0.0120, 0.0),
	Vector3(0.112, 0.0, 0.0)]

static var _cache: Dictionary = {}   # level -> model

var _body: MeshInstance3D


func _init() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)


func _ready() -> void:
	if _body.mesh == null:
		_body.mesh = get_model()["body"]


## Standalone node: picks the tier (the weapon art tool asks for 4, the premium knife).
func set_level(level: int) -> void:
	_body.mesh = get_model(level)["body"]


## false = knife space (pommel at the origin, tip to -Z): the studio renders.
func set_hip_pose(on: bool) -> void:
	rotation = HIP_EULER if on else Vector3.ZERO


func set_cast_shadows(on: bool) -> void:
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## { body: ArrayMesh (2 surfaces), triangles: int, tip: Vector3, grip: Vector3 (handle centre) }. Level 1..4, cached per level.
static func get_model(level: int = 1) -> Dictionary:
	var lv: int = clampi(level, 1, MAX_LEVEL)
	if not _cache.has(lv):
		_cache[lv] = _build_model(lv)
	return _cache[lv]


static func get_materials() -> Dictionary:
	return {SURF_WOOD: CarbineHD.get_materials()[SURF_WOOD], SURF_HARD: RifleHD.get_materials()[SURF_HARD]}


static func _v(s: float, y: float, x: float = 0.0) -> Vector3:
	return Vector3(x, y, -s)


static func _tip_s(level: int) -> float:
	return [0.272, 0.300, 0.345, 0.330][level - 1]


static func _build_model(level: int) -> Dictionary:
	var k: HDMesh = HDMesh.new()
	k.crease_deg = 55.0
	_handle(k, level)
	_metal(k, level)
	_blade(k, level)
	var built: Dictionary = k.build()
	var occluders: TriangleMesh = TriangleMesh.new()
	occluders.create_from_faces(k.get_faces())
	HDMesh.bake_ao(built, occluders, AO_RAYS, AO_RADIUS, 1.0, 0.25)
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, get_materials())
	return {
		"body": mesh, "triangles": k.triangle_count(),
		"tip": _v(_tip_s(level), 0.003), "grip": _v(HANDLE_LEN * 0.5, 0.0),
	}


static func _paint_arr(k: HDMesh, f: Array) -> void:
	k.paint(f[0], f[1], f[2], 0.0, 0)


static func _handle_radius(s: float) -> float:
	for i in range(1, HANDLE_PROFILE.size() - 1):
		var a: Vector3 = HANDLE_PROFILE[i - 1]
		var b: Vector3 = HANDLE_PROFILE[i]
		if s <= b.x:
			return lerpf(a.y, b.y, inverse_lerp(a.x, b.x, s))
	return 0.012


## Oval wooden handle (same geometry on all levels; only the wood changes). Slightly flattened sideways.
static func _handle(k: HDMesh, level: int) -> void:
	# the wood shader ignores vertex colour (it draws its own pale beech): level 1 is that plain pale wood, the others
	# paint the handle on the hard surface (vertex colour) so each tier reads differently
	k.surface(SURF_WOOD if level == 1 else SURF_HARD)
	match level:
		1: k.paint(Color(0.66, 0.48, 0.29), 0.0, 0.80, 0.0, 0)
		2: k.paint(Color(0.42, 0.16, 0.07), 0.0, 0.30, 0.0, 0)    # dark varnished, glossy
		3: k.paint(Color(0.56, 0.34, 0.15), 0.0, 0.60, 0.0, 0)
		_: k.paint(Color(0.17, 0.155, 0.15), 0.0, 0.55, 0.0, 0)
	var keep: Transform3D = k.xf
	k.xf = Transform3D(Basis.from_scale(Vector3(0.86, 1.0, 1.0)), Vector3.ZERO)
	k.lathe(HANDLE_PROFILE, SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	if level == 4:
		# transverse grip grooves: thin near-black creases just proud of the surface, on a lighter grip body
		k.paint(Color(0.02, 0.02, 0.022), 0.0, 0.70, 0.0, 0)
		for gi in 10:
			var s0: float = 0.022 + 0.0088 * gi
			var r0: float = _handle_radius(s0 + 0.001) + 0.0003
			k.lathe([Vector3(s0, r0, 0.0), Vector3(s0 + 0.0022, r0, 0.0)], SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	k.xf = keep
	if level == 3:
		# wooden scales: two slightly proud slabs of real (shader) wood on the flanks
		k.surface(SURF_WOOD)
		for sx: float in [-1.0, 1.0]:
			k.cbox(_v(0.058, 0.0, 0.0121 * sx), Vector3(0.0012, 0.0225, 0.090), 0.0004)


## Pommel, bolster, guard and pins, per level.
static func _metal(k: HDMesh, level: int) -> void:
	k.surface(SURF_HARD)
	var keep: Transform3D = k.xf
	var flat: Transform3D = Transform3D(Basis.from_scale(Vector3(0.86, 1.0, 1.0)), Vector3.ZERO)
	# pommel cap
	match level:
		1: _paint_arr(k, STEEL)
		2: _paint_arr(k, BRASS)
		3: _paint_arr(k, STEEL)
		_: _paint_arr(k, DARK_BRASS)
	k.xf = flat
	if level == 4:
		k.lathe([Vector3(-0.007, 0.0, 0.0), Vector3(-0.007, 0.0060, 0.0), Vector3(-0.003, 0.0105, 0.0), Vector3(0.008, 0.0118, 0.0),
			Vector3(0.008, 0.0, 0.0)], SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	else:
		k.lathe([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0090, 0.0), Vector3(0.003, 0.0110, 0.0), Vector3(0.008, 0.0112, 0.0),
			Vector3(0.008, 0.0, 0.0)], SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	# bolster between the handle and the guard
	if level >= 2:
		_paint_arr(k, DARK_BRASS if level == 4 else BRASS)
		k.lathe([Vector3(0.112, 0.0, 0.0), Vector3(0.112, 0.0124, 0.0), Vector3(0.1145, 0.0130, 0.0), Vector3(0.1175, 0.0120, 0.0),
			Vector3(0.1175, 0.0, 0.0)], SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	else:
		_paint_arr(k, STEEL)
		k.lathe([Vector3(0.112, 0.0, 0.0), Vector3(0.112, 0.0118, 0.0), Vector3(0.118, 0.0118, 0.0), Vector3(0.118, 0.0, 0.0)],
			SEGS, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3.UP)
	k.xf = keep
	if level == 3:
		# lanyard ring behind the pommel (the hole runs side to side)
		_paint_arr(k, STEEL)
		k.lathe([Vector3(-0.0030, 0.0036, 0.0), Vector3(-0.0030, 0.0078, 0.0), Vector3(0.0030, 0.0078, 0.0), Vector3(0.0030, 0.0036, 0.0),
			Vector3(-0.0030, 0.0036, 0.0)], 10, _v(-0.010, 0.0), Vector3.RIGHT, Vector3.UP)
	# guard
	match level:
		1:
			_paint_arr(k, STEEL)
			k.cbox(_v(0.1215, 0.0), Vector3(0.019, 0.036, 0.0075), 0.0020)
		2:
			_paint_arr(k, STEEL)
			k.cbox(_v(0.1245, 0.0), Vector3(0.0215, 0.058, 0.0095), 0.0022)
		3:
			# curved quillons sweeping toward the tip: a chunky crescent seen in profile
			_paint_arr(k, STEEL)
			_guard(k, [Vector2(0.1175, 0.0200), Vector2(0.1215, 0.0290), Vector2(0.1280, 0.0370), Vector2(0.1370, 0.0420),
				Vector2(0.1450, 0.0405), Vector2(0.1400, 0.0300), Vector2(0.1350, 0.0215), Vector2(0.1350, -0.0215),
				Vector2(0.1400, -0.0310), Vector2(0.1450, -0.0410), Vector2(0.1370, -0.0430), Vector2(0.1280, -0.0380),
				Vector2(0.1215, -0.0295), Vector2(0.1175, -0.0200)], 0.0100)
		_:
			# aggressive guard: long upper quillon sweeping to the tip, a heavy hooked lower quillon as a finger stop
			_paint_arr(k, [Color(0.46, 0.46, 0.51), 0.0, 0.38])
			_guard(k, [Vector2(0.1175, 0.0205), Vector2(0.1220, 0.0300), Vector2(0.1300, 0.0390), Vector2(0.1420, 0.0450),
				Vector2(0.1560, 0.0460), Vector2(0.1470, 0.0350), Vector2(0.1400, 0.0270), Vector2(0.1380, 0.0210),
				Vector2(0.1380, -0.0215), Vector2(0.1420, -0.0290), Vector2(0.1500, -0.0365), Vector2(0.1620, -0.0440),
				Vector2(0.1500, -0.0460), Vector2(0.1380, -0.0435), Vector2(0.1290, -0.0372), Vector2(0.1220, -0.0290),
				Vector2(0.1175, -0.0205)], 0.0105)
	# pins
	if level == 3:
		_paint_arr(k, BRASS)
		for s: float in [0.030, 0.058, 0.088]:
			k.sphere(_v(s, 0.0, 0.0128), Vector3(0.0026, 0.0026, 0.0026), 8, 5)
			k.sphere(_v(s, 0.0, -0.0128), Vector3(0.0026, 0.0026, 0.0026), 8, 5)
	elif level == 2:
		_paint_arr(k, BRASS)
		for s2: float in [0.040, 0.086]:
			k.sphere(_v(s2, 0.0, 0.0118), Vector3(0.0020, 0.0020, 0.0020), 6, 4)
			k.sphere(_v(s2, 0.0, -0.0118), Vector3(0.0020, 0.0020, 0.0020), 6, 4)


## Guard: side profile (s, y) extruded across x (+-half_w).
static func _guard(k: HDMesh, pts: Array, half_w: float) -> void:
	var poly: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		poly.append(p)
	var frame: Transform3D = Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3.RIGHT), Vector3.ZERO)
	k.extrude(poly, frame, -half_w, half_w, 0.0018)


## Blade side profile (s, y): spine on top, cutting edge below. Levels 2..4 share one drop-point shape, scaled.
static func _blade_poly(level: int, serrated: bool = true) -> PackedVector2Array:
	if level == 1:
		return PackedVector2Array([
			Vector2(0.118, 0.0150), Vector2(0.215, 0.0150), Vector2(0.244, 0.0122), Vector2(0.261, 0.0072), Vector2(0.272, 0.0030),
			Vector2(0.266, -0.0030), Vector2(0.248, -0.0100), Vector2(0.222, -0.0148), Vector2(0.185, -0.0166),
			Vector2(0.150, -0.0164), Vector2(0.118, -0.0156)])
	var base: Array = [
		Vector2(0.120, 0.0172), Vector2(0.255, 0.0172), Vector2(0.282, 0.0152), Vector2(0.304, 0.0100), Vector2(0.322, 0.0030),
		Vector2(0.316, -0.0030), Vector2(0.298, -0.0105), Vector2(0.268, -0.0165), Vector2(0.226, -0.0202),
		Vector2(0.180, -0.0214), Vector2(0.140, -0.0208), Vector2(0.120, -0.0190)]
	var ls: float = (_tip_s(level) - 0.120) / (0.322 - 0.120)
	var ys: float = [1.0, 1.0, 1.14, 1.04][level - 1]
	var pts: PackedVector2Array = PackedVector2Array()
	for i in base.size():
		var b: Vector2 = base[i]
		var p: Vector2 = Vector2(0.120 + (b.x - 0.120) * ls, b.y * ys)
		if level == 4 and i == 0:
			pts.append(p)
			continue
		if level == 4 and i == 1 and serrated:
			# serrated spine just ahead of the guard: saw teeth
			var top: float = p.y
			for t in 8:
				var s0: float = 0.150 + 0.0095 * t
				pts.append(Vector2(s0, top))
				pts.append(Vector2(s0 + 0.0050, top - 0.0036))
			pts.append(Vector2(0.2260, top))
			pts.append(p)
			continue
		pts.append(p)
	return pts


## Drop-point blade as a side profile extruded across its thickness; both faces taper to the edge (bevel).
static func _blade(k: HDMesh, level: int) -> void:
	k.surface(SURF_HARD)
	# satin steel painted as a lit, non-metal grey: a flat metallic blade only mirrors the dark sky of the portrait
	# studio and of the game's low sun, and would read as a black plank
	match level:
		1: k.paint(Color(0.56, 0.57, 0.60), 0.0, 0.60, 0.0, 0)      # dull, matte
		2: k.paint(Color(0.95, 0.96, 1.00), 0.0, 0.12, 0.0, 0)      # bright polished
		3: k.paint(Color(0.76, 0.78, 0.82), 0.0, 0.25, 0.0, 0)
		_: k.paint(Color(0.30, 0.31, 0.35), 0.0, 0.35, 0.0, 0)     # dark, patterned below
	k.bevel_wear = 1.0   # the ground bevels and the spine corner wear to bright steel
	var frame: Transform3D = Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3.RIGHT), Vector3.ZERO)
	k.extrude(_blade_poly(level), frame, -BLADE_HALF_THICK, BLADE_HALF_THICK, BLADE_BEVEL)
	k.bevel_wear = 0.0
	var e: float = BLADE_HALF_THICK + 0.00006
	if level == 2:
		k.paint(Color(0.78, 0.80, 0.86), 0.0, 0.45, 0.0, 0)
		k.extrude(PackedVector2Array([Vector2(0.150, 0.0090), Vector2(0.250, 0.0090), Vector2(0.258, 0.0075), Vector2(0.250, 0.0060),
			Vector2(0.150, 0.0060)]), frame, -e, e, 0.0)
	elif level == 3:
		k.paint(Color(0.50, 0.52, 0.58), 0.0, 0.45, 0.0, 0)
		k.extrude(PackedVector2Array([Vector2(0.150, 0.0125), Vector2(0.285, 0.0125), Vector2(0.300, 0.0095), Vector2(0.285, 0.0060),
			Vector2(0.150, 0.0060)]), frame, -e, e, 0.0)
	elif level == 4:
		# damascus: wavy bands that follow the blade (spine and edge curves) as fractions of the local width, thinning to
		# nothing at both ends, so no straight border shows
		var plain: PackedVector2Array = _blade_poly(4, false)
		var s_a: float = 0.138
		var s_b: float = _tip_s(4) - 0.016
		var count: int = 9
		for b in count:
			var t_c: float = lerpf(0.20, 0.74, float(b) / float(count - 1))
			var ph: float = 2.3 * b
			var up: PackedVector2Array = PackedVector2Array()
			var dn: PackedVector2Array = PackedVector2Array()
			for j in 13:
				var u: float = float(j) / 12.0
				var sp: float = lerpf(s_a, s_b, u)
				var span: Vector2 = _blade_span(plain, sp)
				var width: float = span.y - span.x
				var taper: float = pow(sin(PI * u), 0.7)
				var tc: float = t_c + 0.016 * sin(sp * 150.0 + ph) + 0.006 * sin(sp * 380.0 + ph * 1.7)
				var half: float = (0.028 + 0.006 * float(b % 3)) * taper
				up.append(Vector2(sp, span.x + width * (tc + half)))
				dn.append(Vector2(sp, span.x + width * (tc - half)))
			dn.reverse()
			up.append_array(dn)
			if b % 2 == 0:
				k.paint(Color(0.44, 0.46, 0.52), 0.0, 0.30, 0.0, 0)
			else:
				k.paint(Color(0.19, 0.19, 0.22), 0.0, 0.45, 0.0, 0)
			var eb: float = e + 0.00003 * float(b)
			k.extrude(up, frame, -eb, eb, 0.0)


## (min y, max y) of the blade polygon at forward position s: the edge and spine heights.
static func _blade_span(poly: PackedVector2Array, sp: float) -> Vector2:
	var lo: float = 1.0
	var hi: float = -1.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if (a.x <= sp and b.x >= sp) or (b.x <= sp and a.x >= sp):
			var y: float = a.y if absf(b.x - a.x) < 1e-6 else lerpf(a.y, b.y, (sp - a.x) / (b.x - a.x))
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return Vector2(lo, hi)
