extends RefCounted
## Body meshes of the third-person hunter (hunter_visual.gd): field shirt, blaze vest and cap in the slot colour,
## jeans, leather boots, gloved hands, a plain face under the cap brim. Smooth lofts built with the showcase
## mesh builder (hd_mesh.gd) and drawn with the ONE material of the first-person HD arms (hd_arms.gdshader,
## shared by every hunter): albedo in the vertex colour, fabric / glove / skin told apart by the feature id.
##
## Slot colour without a material per player: the vest and the cap are painted with a sentinel vertex colour;
## the torso and head arrays are built once and recoloured per slot (copy of the colour array, no rebuild).
## Every other part is shared by all slots. All meshes are cached in static memory.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const ArmsHD := preload("res://assets/models/weapons/showcase/arms_hd.gd")
const Rig := preload("res://assets/models/hunter/hunter_rig.gd")

const N_TORSO: int = 18
const N_HEAD: int = 14
const N_LIMB: int = 12

# brushes: [albedo sRGB (alpha = AO, also drives the dust of the shader), roughness, feature]
# features (hd_arms.gdshader): 0 twill fabric, 1 glove / leather, 2 glove cuff, 3 skin, 4 plain
const SHIRT: Array = [Color(0.62, 0.58, 0.42), 0.92, 0]
const SHIRT_DARK: Array = [Color(0.52, 0.49, 0.35), 0.92, 0]
const DENIM: Array = [Color(0.34, 0.39, 0.48), 0.90, 0]
const DENIM_DARK: Array = [Color(0.28, 0.32, 0.40), 0.90, 0]
const BELT: Array = [Color(0.20, 0.12, 0.07), 0.55, 1]
const BRASS: Array = [Color(0.72, 0.60, 0.34), 0.35, 4]
const BOOT: Array = [Color(0.40, 0.26, 0.15), 0.60, 1]
const SOLE: Array = [Color(0.09, 0.085, 0.08), 0.85, 4]
const GLOVE: Array = ArmsHD.GLOVE
const GLOVE_CUFF: Array = ArmsHD.GLOVE_CUFF
const SKIN: Array = [Color(0.66, 0.49, 0.37), 0.55, 3]
const HAIR: Array = [Color(0.10, 0.075, 0.06), 0.80, 4]
const EYE: Array = [Color(0.05, 0.04, 0.035), 0.30, 4]
const ZIP: Array = [Color(0.12, 0.12, 0.12), 0.60, 4]
## Slot-coloured fabric: the sentinel albedo is replaced per slot (blue channel = shade / 2).
const SLOT_SENTINEL_R: float = 1.0
const DYE_GREEN: float = 1.35
const STRAP_SECTION: PackedVector2Array = [Vector2(0.033, 0.007), Vector2(-0.033, 0.007), Vector2(-0.033, -0.007), Vector2(0.033, -0.007)]

static var _shared: Dictionary = {}
static var _slots: Dictionary = {}


## { torso, head, arm_upper, arm_full_l, arm_full_r, thigh_l, thigh_r, shin_l, shin_r: ArrayMesh, tris: {part: int} }
static func get_parts(slot: int) -> Dictionary:
	if _shared.is_empty():
		_shared = _build_shared()
	if not _slots.has(slot):
		var c: Color = _dye(HunterVisualBase.slot_color(slot))
		_slots[slot] = {"torso": _recolor(_shared["torso_built"], c), "head": _recolor(_shared["head_built"], c)}
	var out: Dictionary = _shared.duplicate()
	out.merge(_slots[slot], true)
	return out


## Fabric dye of a slot colour: green lifted in linear space so the warm late-afternoon sun of the maps does not
## turn yellow into orange and orange into red (the name tag and HUD keep the exact slot colour).
static func _dye(c: Color) -> Color:
	var lin: Color = c.srgb_to_linear()
	lin.g = minf(lin.g * DYE_GREEN, 1.0)
	return lin.linear_to_srgb()


static func is_cached(slot: int) -> bool:
	return not _shared.is_empty() and _slots.has(slot)


static func _build_shared() -> Dictionary:
	var tris: Dictionary = {}
	var out: Dictionary = {}
	var k: HDMesh = HDMesh.new()
	_torso(k)
	out["torso_built"] = k.build()
	tris["torso"] = k.triangle_count()
	k = HDMesh.new()
	_head(k)
	out["head_built"] = k.build()
	tris["head"] = k.triangle_count()
	k = HDMesh.new()
	_upper_arm(k)
	out["arm_upper"] = _commit(k)
	tris["arm_upper"] = k.triangle_count()
	for side in 2:
		var tag: String = "_l" if side == 0 else "_r"
		k = HDMesh.new()
		_full_arm(k, side)
		out["arm_full" + tag] = _commit(k)
		tris["arm_full" + tag] = k.triangle_count()
		k = HDMesh.new()
		_thigh(k, side)
		out["thigh" + tag] = _commit(k)
		tris["thigh" + tag] = k.triangle_count()
		k = HDMesh.new()
		_shin(k, side)
		out["shin" + tag] = _commit(k)
		tris["shin" + tag] = k.triangle_count()
	out["tris"] = tris
	return out


static func _commit(k: HDMesh) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(k.build(), mesh, {0: ArmsHD.get_material()})
	return mesh


## Copy of a built mesh with the sentinel colour replaced by the slot colour (shade kept in the blue channel).
static func _recolor(built: Dictionary, slot_col: Color) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var sd: Dictionary = built["surfaces"][0]
	var col: PackedColorArray = (sd["col"] as PackedColorArray).duplicate()
	for i in col.size():
		var c: Color = col[i]
		if c.r >= SLOT_SENTINEL_R and c.g <= 0.0:
			var f: float = c.b * 2.0
			col[i] = Color(minf(slot_col.r * f, 1.0), minf(slot_col.g * f, 1.0), minf(slot_col.b * f, 1.0), c.a)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sd["pos"]
	arrays[Mesh.ARRAY_NORMAL] = sd["nrm"]
	arrays[Mesh.ARRAY_TEX_UV] = sd["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = sd["uv2"]
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = sd["idx"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ArmsHD.get_material())
	return mesh


# --- painting and shapes ---------------------------------------------------------------------------

static func _pt(k: HDMesh, brush: Array, ao: float = 1.0) -> void:
	var c: Color = brush[0]
	c.a = ao
	k.paint(c, 0.0, brush[1], 0.0, brush[2])


## Slot-coloured fabric with a relative shade (1 = the slot colour).
static func _slot(k: HDMesh, shade: float, ao: float = 1.0) -> void:
	k.paint(Color(SLOT_SENTINEL_R, 0.0, shade * 0.5, ao), 0.0, 0.88, 0.0, 0)


## Superellipse ring in the plane (u, v) around p: half size `wu` along u, `vp` toward +v and `vn` toward -v.
static func _ring(p: Vector3, u: Vector3, v: Vector3, wu: float, vp: float, vn: float, n: int, e: float = 2.2) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(n)
	var ex: float = 2.0 / e
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var c: float = cos(a)
		var s: float = sin(a)
		var x: float = wu * signf(c) * pow(absf(c), ex)
		var y: float = (vp if s >= 0.0 else vn) * signf(s) * pow(absf(s), ex)
		out[i] = p + u * x + v * y
	return out


## Horizontal ring (torso, legs): x half width `w`, `front` toward -Z, `back` toward +Z, centred at (cx, y, cz).
static func _hring(y: float, w: float, front: float, back: float, n: int, e: float = 2.2, cz: float = 0.0, cx: float = 0.0) -> PackedVector3Array:
	return _ring(Vector3(cx, y, cz), Vector3.RIGHT, Vector3.BACK, w, back, front, n, e)


## Lofts consecutive rings painted band by band (`brushes[i]` paints the band ending at ring i + 1), one
## smoothing island. Brush entries: Array (plain brush) or float (slot shade).
static func _bands(k: HDMesh, rings: Array, brushes: Array, cap_start: bool, cap_end: bool, aos: PackedFloat32Array = PackedFloat32Array()) -> void:
	var last: int = rings.size() - 2
	for i in last + 1:
		var b: Variant = brushes[mini(i, brushes.size() - 1)]
		var ao: float = aos[i] if i < aos.size() else 1.0
		if b is Array:
			_pt(k, b, ao)
		else:
			_slot(k, b, ao)
		k.loft([rings[i], rings[i + 1]], cap_start and i == 0, cap_end and i == last, i == 0)


## Tube through `pts` with elliptic sections (`size[i]` = half width along `ref`, half depth), rings perpendicular to
## the path. `ref` fixes the width axis.
static func _tube(k: HDMesh, pts: Array, size: Array, ref: Vector3, n: int, brushes: Array, cap_start: bool, cap_end: bool, e: float = 2.2) -> void:
	var rings: Array = []
	var m: int = pts.size()
	for i in m:
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, m - 1)]
		var t: Vector3 = (b - a).normalized()
		var u: Vector3 = (ref - t * ref.dot(t)).normalized()
		var v: Vector3 = t.cross(u)
		var s: Vector2 = size[i]
		rings.append(_ring(pts[i], u, v, s.x, s.y, s.y, n, e))
	_bands(k, rings, brushes, cap_start, cap_end)


## Open patch between rows of points (same count): hair, cap bill. `out_fn` gives the outward side of a quad.
static func _patch(k: HDMesh, rows: Array, out_dir: Callable) -> void:
	for r in rows.size() - 1:
		var ra: PackedVector3Array = rows[r]
		var rb: PackedVector3Array = rows[r + 1]
		for j in ra.size() - 1:
			var mid: Vector3 = (ra[j] + ra[j + 1] + rb[j] + rb[j + 1]) * 0.25
			k.quad(ra[j], ra[j + 1], rb[j + 1], rb[j], out_dir.call(mid))


# --- torso -----------------------------------------------------------------------------------------

static func _torso(k: HDMesh) -> void:
	var n: int = N_TORSO
	# jeans: crotch to the belt
	var pants: Array = [_hring(-0.105, 0.115, 0.070, 0.075, n, 2.2, 0.005), _hring(-0.06, 0.158, 0.094, 0.108, n, 2.4, 0.005),
		_hring(0.02, 0.170, 0.099, 0.112, n, 2.6, 0.005), _hring(0.105, 0.163, 0.096, 0.100, n, 2.6)]
	_bands(k, pants, [DENIM], true, false, PackedFloat32Array([0.8, 0.95, 1.0]))
	# shirt tucked in under the belt, up to the collar
	var shirt: Array = [_hring(0.10, 0.160, 0.093, 0.098, n, 2.6), _hring(0.24, 0.168, 0.104, 0.104, n, 2.6),
		_hring(0.36, 0.192, 0.115, 0.106, n, 2.8), _hring(0.44, 0.205, 0.106, 0.102, n, 2.9),
		_hring(0.488, 0.192, 0.088, 0.092, n, 2.6), _hring(0.53, 0.130, 0.066, 0.074, n, 2.3),
		_hring(0.56, 0.075, 0.058, 0.064, n, 2.0, 0.008)]
	_bands(k, shirt, [SHIRT], false, false)
	# collar: a flared band around the neck, points at the front
	_bands(k, [_hring(0.54, 0.074, 0.066, 0.068, n, 2.0, 0.008), _hring(0.585, 0.071, 0.064, 0.070, n, 2.0, 0.010)],
		[SHIRT_DARK], false, false, PackedFloat32Array([0.85]))
	for sx: float in [-1.0, 1.0]:
		k.xf = Transform3D(Basis(Vector3.BACK, sx * 0.5) * Basis(Vector3.RIGHT, -0.35), Vector3(sx * 0.03, 0.545, -0.062))
		_pt(k, SHIRT_DARK)
		k.cbox(Vector3.ZERO, Vector3(0.04, 0.032, 0.008), 0.0)
	k.xf = Transform3D.IDENTITY
	# neck
	_bands(k, [_hring(0.50, 0.050, 0.046, 0.054, 12, 2.0, 0.012), _hring(0.665, 0.047, 0.045, 0.050, 12, 2.0, 0.006)], [SKIN], false, false)
	# belt with a brass buckle and a knife sheath on the right hip
	_bands(k, [_hring(0.092, 0.167, 0.099, 0.103, n, 2.6), _hring(0.142, 0.167, 0.099, 0.103, n, 2.6)], [BELT], false, false)
	_pt(k, BRASS)
	k.cbox(Vector3(0.0, 0.117, -0.101), Vector3(0.056, 0.044, 0.012), 0.004)
	_pt(k, BELT, 0.9)
	k.cbox(Vector3(0.150, 0.04, 0.055), Vector3(0.024, 0.16, 0.05), 0.008)
	# blaze vest over the shirt: open at the top, straps over the shoulders, zip, pockets, game pouch at the back
	var vest: Array = [_hring(0.13, 0.172, 0.105, 0.110, n, 2.6), _hring(0.24, 0.180, 0.117, 0.116, n, 2.6),
		_hring(0.36, 0.204, 0.128, 0.118, n, 2.8), _hring(0.45, 0.216, 0.118, 0.114, n, 2.9)]
	_bands(k, vest, [1.0], false, false, PackedFloat32Array([0.9, 1.0, 1.0]))
	for sx: float in [-1.0, 1.0]:
		_slot(k, 1.0)
		var strap: Array = [Vector3(sx * 0.125, 0.44, -0.117), Vector3(sx * 0.13, 0.50, -0.09), Vector3(sx * 0.135, 0.53, 0.0),
			Vector3(sx * 0.13, 0.50, 0.093), Vector3(sx * 0.125, 0.44, 0.116)]
		k.sweep(strap, STRAP_SECTION, Vector3.RIGHT)
		# chest pocket with its flap, lower pocket
		_slot(k, 0.82)
		k.cbox(Vector3(sx * 0.088, 0.355, -0.126), Vector3(0.075, 0.075, 0.016), 0.005)
		_slot(k, 0.72)
		k.cbox(Vector3(sx * 0.088, 0.397, -0.130), Vector3(0.080, 0.022, 0.018), 0.0)
		_slot(k, 0.82)
		k.cbox(Vector3(sx * 0.092, 0.205, -0.121), Vector3(0.085, 0.08, 0.018), 0.006)
	_slot(k, 0.78)
	k.cbox(Vector3(0.0, 0.25, 0.122), Vector3(0.27, 0.14, 0.03), 0.01)
	_pt(k, ZIP)
	k.cbox(Vector3(0.0, 0.29, -0.124), Vector3(0.008, 0.31, 0.006), 0.0)
	# shirt button between the vest and the collar
	_pt(k, BRASS)
	k.cbox(Vector3(0.0, 0.49, -0.084), Vector3(0.012, 0.012, 0.006), 0.0)


# --- head ------------------------------------------------------------------------------------------

static func _head(k: HDMesh) -> void:
	var n: int = N_HEAD
	# skull: [y, half width, front, back]
	var keys: Array = [[0.018, 0.034, 0.072, 0.0], [0.04, 0.058, 0.088, 0.03], [0.07, 0.068, 0.093, 0.062],
		[0.10, 0.074, 0.096, 0.086], [0.13, 0.078, 0.097, 0.098], [0.16, 0.080, 0.094, 0.104],
		[0.19, 0.077, 0.085, 0.100], [0.215, 0.064, 0.064, 0.080], [0.236, 0.036, 0.034, 0.045]]
	var rings: Array = []
	for key: Array in keys:
		rings.append(_hring(key[0], key[1], key[2], key[3], n, 2.15, 0.0))
	_bands(k, rings, [SKIN], true, true)
	# ears
	_pt(k, SKIN, 0.9)
	for sx: float in [-1.0, 1.0]:
		k.sphere(Vector3(sx * 0.078, 0.118, 0.012), Vector3(0.011, 0.027, 0.019), 6, 4)
	# nose, eyes, brows, moustache
	_pt(k, SKIN)
	k.sweep([Vector3(0.0, 0.142, -0.090), Vector3(0.0, 0.118, -0.106), Vector3(0.0, 0.099, -0.112)],
		HDMesh.rect_section(0.020, 0.018, 0.006), Vector3.RIGHT, PackedFloat32Array([0.55, 0.95, 1.1]))
	_pt(k, EYE)
	for sx: float in [-1.0, 1.0]:
		k.sphere(Vector3(sx * 0.031, 0.134, -0.090), Vector3(0.012, 0.0065, 0.006), 6, 3)
	_pt(k, HAIR)
	for sx: float in [-1.0, 1.0]:
		k.xf = Transform3D(Basis(Vector3.BACK, sx * -0.12), Vector3(sx * 0.032, 0.151, -0.094))
		k.cbox(Vector3.ZERO, Vector3(0.034, 0.008, 0.010), 0.002)
	k.xf = Transform3D.IDENTITY
	k.sweep(HDMesh.smooth_path([Vector3(-0.034, 0.074, -0.093), Vector3(-0.016, 0.083, -0.102), Vector3(0.0, 0.085, -0.104),
		Vector3(0.016, 0.083, -0.102), Vector3(0.034, 0.074, -0.093)], 1), HDMesh.circle_section(0.0075, 5), Vector3.UP)
	# hair under the cap: back and sides
	var hrows: Array = []
	for hy: float in [0.075, 0.115, 0.152]:
		var row: PackedVector3Array = PackedVector3Array()
		var lift: float = 0.004 + (hy - 0.075) * 0.03
		for j in 9:
			var a: float = lerpf(-0.30, PI + 0.30, float(j) / 8.0)
			var w: float = _lerp_key(keys, hy, 1) + lift
			var back: float = _lerp_key(keys, hy, 3) + lift
			var front: float = _lerp_key(keys, hy, 2) + lift
			var z: float = (back if sin(a) >= 0.0 else front) * sin(a)
			row.push_back(Vector3(cos(a) * w, hy + (0.025 if absf(cos(a)) > 0.8 and hy < 0.08 else 0.0), z))
		hrows.append(row)
	_pt(k, HAIR)
	k.begin_part()
	_patch(k, hrows, func(m: Vector3) -> Vector3: return Vector3(m.x, 0.0, m.z))
	# cap (slot colour): crown, button, curved bill
	var crown: Array = [_hring(0.142, 0.086, 0.099, 0.106, n, 2.2), _hring(0.185, 0.085, 0.094, 0.105, n, 2.2),
		_hring(0.222, 0.073, 0.077, 0.090, n, 2.2), _hring(0.248, 0.046, 0.046, 0.056, n, 2.2), _hring(0.258, 0.012, 0.012, 0.014, n, 2.0)]
	_bands(k, crown, [1.0], false, true, PackedFloat32Array([0.85, 1.0, 1.0, 1.0]))
	_slot(k, 0.85)
	k.sphere(Vector3(0.0, 0.262, 0.0), Vector3(0.01, 0.006, 0.01), 6, 3)
	var bill_top: Array = []
	var bill_bot: Array = []
	for r in 3:
		var t: float = float(r) / 2.0
		var top: PackedVector3Array = PackedVector3Array()
		var bot: PackedVector3Array = PackedVector3Array()
		for j in 9:
			var x: float = lerpf(-1.0, 1.0, float(j) / 8.0)
			var half: float = 0.083 * (1.0 - 0.25 * t * t)
			var px: float = x * half
			var base_z: float = -0.097 * sqrt(maxf(1.0 - (px / 0.090) * (px / 0.090), 0.0)) + 0.004
			var reach: float = 0.078 * t * (1.0 - 0.55 * x * x)
			var py: float = 0.146 - 0.018 * x * x * t - 0.028 * t
			top.push_back(Vector3(px, py + 0.004, base_z - reach))
			bot.push_back(Vector3(px, py - 0.003, base_z - reach + 0.002))
		bill_top.append(top)
		bill_bot.append(bot)
	_slot(k, 0.9)
	k.begin_part()
	_patch(k, bill_top, func(_m: Vector3) -> Vector3: return Vector3(0.0, 1.0, -0.25))
	_slot(k, 0.55, 0.8)
	k.begin_part()
	_patch(k, bill_bot, func(_m: Vector3) -> Vector3: return Vector3(0.0, -1.0, 0.0))
	# bill rim
	_slot(k, 0.8)
	k.begin_part()
	var edge_t: PackedVector3Array = bill_top[2]
	var edge_b: PackedVector3Array = bill_bot[2]
	_patch(k, [edge_t, edge_b], func(m: Vector3) -> Vector3: return Vector3(m.x, 0.0, m.z + 0.05))


static func _lerp_key(keys: Array, y: float, col: int) -> float:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if y <= float(b[0]):
			return lerpf(a[col], b[col], clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0))
	return float((keys[keys.size() - 1] as Array)[col])


# --- arms ------------------------------------------------------------------------------------------

## Upper arm, pivot at the shoulder joint, hanging along -Y to the elbow (Rig.UPPER_ARM).
static func _upper_arm(k: HDMesh) -> void:
	var u: float = Rig.UPPER_ARM
	# rounded deltoid, full field-shirt sleeve narrowing to the elbow
	var rings: Array = [_hring(0.070, 0.030, 0.030, 0.030, N_LIMB), _hring(0.056, 0.066, 0.064, 0.066, N_LIMB),
		_hring(0.020, 0.086, 0.080, 0.080, N_LIMB), _hring(-0.04, 0.084, 0.078, 0.076, N_LIMB),
		_hring(-0.12, 0.074, 0.074, 0.070, N_LIMB), _hring(-u + 0.04, 0.066, 0.066, 0.065, N_LIMB),
		_hring(-u, 0.064, 0.064, 0.066, N_LIMB), _hring(-u - 0.035, 0.045, 0.045, 0.047, N_LIMB)]
	_bands(k, rings, [SHIRT], true, true, PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.85]))


## Whole relaxed arm (unarmed): upper arm, elbow slightly bent forward, forearm, gloved hand.
static func _full_arm(k: HDMesh, side: int) -> void:
	_upper_arm(k)
	var sx: float = 1.0 if side == 1 else -1.0
	var e: Vector3 = Vector3(0.0, -Rig.UPPER_ARM, 0.0)
	var d: Vector3 = Vector3(sx * 0.06, -cos(0.32), -sin(0.32)).normalized()
	var f: float = Rig.FOREARM
	var pts: Array = [e - d * 0.04, e - d * 0.012, e + d * 0.09, e + d * (f - 0.07), e + d * (f - 0.045), e + d * (f - 0.04),
		e + d * (f - 0.02), e + d * f, e + d * (f + 0.045), e + d * (f + 0.09), e + d * (f + 0.115)]
	var size: Array = [Vector2(0.040, 0.040), Vector2(0.064, 0.064), Vector2(0.060, 0.058), Vector2(0.052, 0.050), Vector2(0.050, 0.048),
		Vector2(0.036, 0.033), Vector2(0.033, 0.029), Vector2(0.030, 0.024), Vector2(0.044, 0.024), Vector2(0.042, 0.028), Vector2(0.024, 0.018)]
	# full sleeve to a buttoned cuff, glove; width of the hand toward the front, palm facing the thigh
	_tube(k, pts, size, Vector3.FORWARD, N_LIMB, [SHIRT, SHIRT, SHIRT, SHIRT_DARK, GLOVE_CUFF, GLOVE_CUFF, GLOVE, GLOVE, GLOVE, GLOVE], true, true)
	_pt(k, GLOVE)
	k.sweep([e + d * (f + 0.02) + Vector3(-sx * 0.018, 0.0, -0.02), e + d * (f + 0.06) + Vector3(-sx * 0.022, 0.0, -0.03)],
		HDMesh.circle_section(0.011, 5), Vector3.UP)


# --- legs ------------------------------------------------------------------------------------------

## Thigh, pivot at the hip joint, down -Y to the knee. Cargo pocket on the outer side.
static func _thigh(k: HDMesh, side: int) -> void:
	var sx: float = 1.0 if side == 1 else -1.0
	var lu: float = Rig.LEG_UPPER
	var rings: Array = [_hring(0.07, 0.080, 0.088, 0.088, N_LIMB), _hring(0.0, 0.088, 0.095, 0.095, N_LIMB, 2.2, -0.004),
		_hring(-0.13, 0.083, 0.090, 0.086, N_LIMB, 2.2, -0.006), _hring(-0.27, 0.071, 0.076, 0.072, N_LIMB),
		_hring(-lu + 0.06, 0.060, 0.062, 0.060, N_LIMB), _hring(-lu, 0.058, 0.062, 0.058, N_LIMB, 2.2, -0.004),
		_hring(-lu - 0.04, 0.042, 0.044, 0.042, N_LIMB)]
	_bands(k, rings, [DENIM], false, true)
	_pt(k, DENIM_DARK)
	k.xf = Transform3D(Basis(Vector3.BACK, sx * 0.06), Vector3(sx * 0.084, -0.21, -0.004))
	k.cbox(Vector3.ZERO, Vector3(0.022, 0.115, 0.095), 0.008)
	k.cbox(Vector3(sx * 0.004, 0.058, 0.0), Vector3(0.024, 0.026, 0.10), 0.006)
	k.xf = Transform3D.IDENTITY


## Shin with the jeans over a laced leather boot, pivot at the knee; the sole sits at -Rig.LEG_LOWER.
static func _shin(k: HDMesh, _side: int) -> void:
	var ll: float = Rig.LEG_LOWER
	var n: int = N_LIMB
	var pants: Array = [_hring(0.05, 0.055, 0.058, 0.056, n), _hring(0.0, 0.057, 0.061, 0.058, n),
		_hring(-0.10, 0.056, 0.056, 0.068, n), _hring(-0.22, 0.050, 0.050, 0.056, n), _hring(-0.30, 0.054, 0.056, 0.058, n),
		_hring(-0.318, 0.047, 0.049, 0.050, n)]
	_bands(k, pants, [DENIM, DENIM, DENIM, DENIM, DENIM_DARK], false, false, PackedFloat32Array([1.0, 1.0, 0.95, 0.75, 0.6]))
	# boot shaft down to the heel
	var shaft: Array = [_hring(-0.27, 0.044, 0.046, 0.046, n), _hring(-0.36, 0.044, 0.048, 0.050, n), _hring(-0.40, 0.043, 0.050, 0.052, n)]
	_bands(k, shaft, [BOOT], false, false, PackedFloat32Array([0.85, 0.85]))
	# foot, lofted heel to toe
	var foot: Array = []
	for key: Array in [[0.058, -0.412, 0.034, 0.034], [0.035, -0.405, 0.045, 0.048], [-0.04, -0.414, 0.049, 0.040],
			[-0.105, -0.428, 0.050, 0.028], [-0.150, -0.433, 0.044, 0.022], [-0.172, -0.435, 0.026, 0.014]]:
		foot.append(_ring(Vector3(0.0, key[1], key[0]), Vector3.RIGHT, Vector3.UP, key[2], key[3], key[3], n, 2.4))
	_bands(k, foot, [BOOT], true, true, PackedFloat32Array([0.9, 0.9, 0.9, 0.9, 0.9]))
	_pt(k, SOLE)
	k.cbox(Vector3(0.0, -ll + 0.009, -0.052), Vector3(0.100, 0.018, 0.236), 0.005)
