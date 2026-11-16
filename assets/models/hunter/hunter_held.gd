extends RefCounted
## What the third-person hunter holds: light versions of the five HD guns (same stock profiles, barrels, scopes
## and materials as showcase/<id>_hd.gd, at a fraction of the triangles, no baked AO) or binoculars when unarmed,
## each with BOTH gloved forearms baked in. The forearms are posed once by two-bone IK for the shouldered aim
## (hunter_rig.gd); at run time only the upper arms move (shoulder -> elbow), so the whole hold is one mesh.
##
## Gun space as the HD guns: origin on the butt plate at the bore axis, s forward (z = -s), y up, x right.
## Surfaces: 0 = wood (the HD gun's own walnut / laminate material), 1 = hard surface (shared with every HD gun),
## 2 = sleeves and gloves (the HD arms material). Cached per weapon id.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const ArmsHD := preload("res://assets/models/weapons/showcase/arms_hd.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const CarbineHD := preload("res://assets/models/weapons/showcase/carbine_22_hd.gd")
const ShotgunHD := preload("res://assets/models/weapons/showcase/shotgun_12_hd.gd")
const Rifle3006HD := preload("res://assets/models/weapons/showcase/rifle_3006_hd.gd")
const Rifle338HD := preload("res://assets/models/weapons/showcase/rifle_338_hd.gd")
const Rig := preload("res://assets/models/hunter/hunter_rig.gd")
const Body := preload("res://assets/models/hunter/hunter_body.gd")

const SURF_WOOD: int = 0
const SURF_HARD: int = 1
const SURF_CLOTH: int = 2
const STOCK_POINTS: int = 10
const SEGS: int = 8
const BINOCULARS: StringName = &""
const DEFAULT_GUN: StringName = &"carbine_22"
const LENS: Array = [Color(0.05, 0.06, 0.08), 0.0, 0.08]
const GUARD_SECTION: PackedVector2Array = [Vector2(0.005, 0.0018), Vector2(-0.005, 0.0018), Vector2(-0.005, -0.0018), Vector2(0.005, -0.0018)]

## Carry poses in torso space: Euler (YXZ) of the gun and where the right fist (grip centre) goes. Each pose has
## its own forearms baked by IK, with these elbow pole hints: [left, right].
## Low carry: the gun across the front of the hips, about 35 degrees off horizontal, muzzle down and to the
## left, scope turned out; right fist on the grip by the right hip, left hand on the fore-end, arm relaxed.
const LOW_EULER: Vector3 = Vector3(-0.58, 1.27, -0.5)
const LOW_GRIP: Vector3 = Vector3(0.03, 0.11, -0.19)
const LOW_POLES: Array = [Vector3(-0.6, -0.2, 0.4), Vector3(0.6, -0.3, 0.8)]
const RELOAD_EULER: Vector3 = Vector3(0.05, 0.55, 0.55)
const RELOAD_GRIP: Vector3 = Vector3(0.09, 0.22, -0.26)
const RELOAD_POLES: Array = [Vector3(-0.6, -1.0, 0.0), Vector3(0.8, -0.8, 0.5)]
## Fallen (play_death): the gun across the chest, both hands still on it; after the body falls on its back it lies flat.
const DEAD_EULER: Vector3 = Vector3(0.12, PI * 0.5, -PI * 0.5)
const DEAD_GRIP: Vector3 = Vector3(0.03, 0.27, -0.17)
const DEAD_POLES: Array = [Vector3(-1.0, -0.3, 0.6), Vector3(1.0, -0.3, 0.6)]
const AIM_POLES: Array = [Vector3(-0.6, -1.0, 0.05), Vector3(1.0, -0.55, 0.35)]
const BINO_POLES: Array = [Vector3(-0.9, -1.0, 0.3), Vector3(0.9, -1.0, 0.3)]

## Per gun: stock curves of the HD model, stock end station, receiver [s0, s1, r], barrel profile [[s, r]...],
## scope [s0, length, y, tube r, bell r] or [], hands (grip centre, fore-end hand centre), flash scale.
const SPECS: Dictionary = {
	&"rifle_308": {"hd": "308", "stock_end": 0.814, "pad": 0.025, "recv": [0.345, 0.535, 0.0172],
		"barrel": [[0.53, 0.0152], [0.62, 0.0117], [1.10, 0.0089]], "muzzle": 1.10,
		"scope": [0.2845, 0.356, 0.049, 0.015, 0.0295], "grip": Vector3(0.0, -0.083, -0.284), "fore": Vector3(0.0, -0.040, -0.50),
		"bolt": Vector3(0.0535, -0.0375, -0.3335), "flash": 0.8},
	&"carbine_22": {"hd": "22", "stock_end": 0.607, "pad": 0.015, "recv": [0.262, 0.428, 0.0128],
		"barrel": [[0.42, 0.0098], [0.60, 0.0082], [0.945, 0.0068]], "muzzle": 0.945,
		"scope": [], "grip": Vector3(0.0, -0.0785, -0.284), "fore": Vector3(0.0, -0.028, -0.46),
		"bolt": Vector3(0.0418, -0.0298, -0.313), "flash": 0.5},
	&"shotgun_12": {"hd": "12", "stock_end": 0.385, "pad": 0.028, "recv": [],
		"barrel": [[0.56, 0.0130], [0.95, 0.0122], [0.99, 0.0132]], "muzzle": 0.99,
		"scope": [], "grip": Vector3(0.0, -0.083, -0.284), "fore": Vector3(0.0, -0.040, -0.64),
		"bolt": Vector3.ZERO, "flash": 1.0},
	&"rifle_3006": {"hd": "3006", "stock_end": 0.72, "pad": 0.025, "recv": [0.30, 0.58, 0.0185],
		"barrel": [[0.56, 0.0150], [0.70, 0.0128], [1.10, 0.0098]], "muzzle": 1.10,
		"scope": [0.245, 0.31, 0.048, 0.0145, 0.0265], "grip": Vector3(0.0, -0.083, -0.284), "fore": Vector3(0.0, -0.045, -0.54),
		"bolt": Vector3(0.0345, 0.0016, -0.434), "flash": 0.85},
	&"rifle_338": {"hd": "338", "stock_end": 0.83, "pad": 0.025, "recv": [0.385, 0.575, 0.019],
		"barrel": [[0.57, 0.0172], [0.90, 0.0152], [1.046, 0.0144]], "muzzle": 1.14,
		"scope": [0.285, 0.44, 0.0605, 0.0205, 0.0405], "grip": Vector3(0.0, -0.086, -0.284), "fore": Vector3(0.0, -0.05, -0.55),
		"bolt": Vector3(0.0589, -0.0413, -0.3735), "flash": 1.2},
}

static var _cache: Dictionary = {}


static func is_cached(id: StringName) -> bool:
	return _cache.has(_key(id))


static func _key(id: StringName) -> StringName:
	if id == BINOCULARS or SPECS.has(id):
		return id
	return DEFAULT_GUN


## { poses: {aim, low, reload, dead (guns only): {mesh, elbows [left, right] (item space), xf (torso space, bake pose),
##   tris}}, anchor (item point laid on the shoulder / eyes), muzzle (item space), flash, gun_tris, tris, ms }
static func get_item(id: StringName) -> Dictionary:
	var key: StringName = _key(id)
	if not _cache.has(key):
		var t0: int = Time.get_ticks_usec()
		var item: Dictionary = _build_binoculars() if key == BINOCULARS else _build_gun(key)
		item["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
		_cache[key] = item
	return _cache[key]


static func _hd_script(tag: String) -> GDScript:
	match tag:
		"22": return CarbineHD
		"12": return ShotgunHD
		"3006": return Rifle3006HD
		"338": return Rifle338HD
	return RifleHD


static func _materials(tag: String) -> Dictionary:
	var hd: Dictionary
	match tag:
		"22": hd = CarbineHD.get_materials()
		"12": hd = ShotgunHD.get_materials()
		"3006": hd = Rifle3006HD.get_materials()
		"338": hd = Rifle338HD.get_materials()
		_: hd = RifleHD.get_materials()
	return {SURF_WOOD: hd[0], SURF_HARD: RifleHD.get_materials()[RifleHD.SURF_HARD], SURF_CLOTH: ArmsHD.get_material()}


static func _v(s: float, y: float, x: float = 0.0) -> Vector3:
	return Vector3(x, y, -s)


static func _fin(k: HDMesh, finish: Array, ao: float = 1.0) -> void:
	k.surface(SURF_HARD)
	var c: Color = finish[0]
	c.a = ao
	k.paint(c, finish[1], finish[2], 0.0, 0)


# --- guns ------------------------------------------------------------------------------------------

static func _build_gun(id: StringName) -> Dictionary:
	var spec: Dictionary = SPECS[id]
	var tag: String = spec["hd"]
	var hd: GDScript = _hd_script(tag)
	var k: HDMesh = HDMesh.new()
	var consts: Dictionary = hd.get_script_constant_map()
	var curves: Dictionary = {"top": HDMesh.curve(consts["TOP"]), "bot": HDMesh.curve(consts["BOT"]), "wid": HDMesh.curve(consts["WID"]),
		"widest": HDMesh.curve(consts["WIDEST"]), "exp_top": HDMesh.curve(consts["EXP_TOP"]), "exp_bot": HDMesh.curve(consts["EXP_BOT"])}
	_stock(k, curves, spec["pad"], spec["stock_end"])
	var recv: Array = spec["recv"]
	if not recv.is_empty():
		_fin(k, RifleHD.BLUED)
		var r: float = recv[2]
		k.lathe([Vector3(recv[0], 0.0, 0), Vector3(recv[0], r * 0.9, 0), Vector3(recv[0] + 0.004, r, 0), Vector3(recv[1] - 0.003, r, 0),
			Vector3(recv[1], r * 0.9, 0), Vector3(recv[1], 0.0, 0)], SEGS, Vector3.ZERO, Vector3.FORWARD)
	_barrel(k, spec["barrel"], spec["muzzle"], tag)
	var scope: Array = spec["scope"]
	if not scope.is_empty():
		_scope(k, scope, recv)
	var bolt: Vector3 = spec["bolt"]
	if bolt != Vector3.ZERO:
		_fin(k, RifleHD.BLUED)
		k.sweep([Vector3(0.008, bolt.y * 0.4, bolt.z + 0.01), Vector3(bolt.x * 0.75, bolt.y * 0.8, bolt.z + 0.004), bolt],
			HDMesh.circle_section(0.0045, 5), Vector3.FORWARD)
		_fin(k, RifleHD.STEEL_DARK)
		k.sphere(bolt, Vector3.ONE * 0.0085, 6, 4)
	match tag:
		"12": _shotgun_parts(k, consts)
		"22": _carbine_parts(k)
		"3006": _m3006_parts(k)
		"338": _m338_parts(k)
	_trigger_guard(k, tag)
	var grip: Vector3 = spec["grip"]
	var fore: Vector3 = spec["fore"]
	var mag: Vector3 = (ArmsHD.SPECS[id] as Dictionary)["mag"]
	var butt: Vector3 = _v(0.0, (float((consts["TOP"] as Array)[0][1]) + float((consts["BOT"] as Array)[0][1])) * 0.5)
	var built: Dictionary = k.build()
	var mats: Dictionary = _materials(tag)
	var aim: Transform3D = Rig.aim_xf(Basis(Vector3.RIGHT, Rig.AIM_LEAN), Rig.BLADE, 0.0, butt, Rig.POCKET)
	var poses: Dictionary = {
		"aim": _variant(built, k.triangle_count(), mats, aim, grip, fore, AIM_POLES, false),
		"low": _variant(built, k.triangle_count(), mats, _place(LOW_EULER, LOW_GRIP, grip), grip, fore, LOW_POLES, false),
		"reload": _variant(built, k.triangle_count(), mats, _place(RELOAD_EULER, RELOAD_GRIP, grip), grip, mag, RELOAD_POLES, false),
		"dead": _variant(built, k.triangle_count(), mats, _place(DEAD_EULER, DEAD_GRIP, grip), grip, fore, DEAD_POLES, false),
	}
	return {"poses": poses, "anchor": butt, "muzzle": _v(spec["muzzle"], 0.0), "flash": spec["flash"], "gun_tris": k.triangle_count(),
		"tris": maxi(maxi(poses["aim"]["tris"], poses["low"]["tris"]), poses["reload"]["tris"])}


## Gun transform (torso space) with Euler `euler` whose grip point lands on `grip_at`.
static func _place(euler: Vector3, grip_at: Vector3, grip: Vector3) -> Transform3D:
	var b: Basis = Basis.from_euler(euler)
	return Transform3D(b, grip_at - b * grip)


## One hold of the item: its mesh with the forearms baked for the pose `xf` (torso space).
static func _variant(built: Dictionary, item_tris: int, mats: Dictionary, xf: Transform3D, right: Vector3, left: Vector3, poles: Array, binoculars: bool) -> Dictionary:
	var hk: HDMesh = HDMesh.new()
	var elbows: Array = _hands(hk, xf, right, left, poles, binoculars)
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, mats)
	HDMesh.commit(hk.build(), mesh, mats)
	return {"mesh": mesh, "elbows": elbows, "xf": xf, "tris": item_tris + hk.triangle_count()}


static func _stock(k: HDMesh, curves: Dictionary, pad: float, end: float) -> void:
	k.crease_deg = 55.0
	_fin(k, RifleHD.RUBBER)
	k.loft([HDMesh.section_ring(curves, pad, STOCK_POINTS, 0.93, 0.0), HDMesh.section_ring(curves, pad, STOCK_POINTS, 1.0, pad * 0.4),
		HDMesh.section_ring(curves, pad, STOCK_POINTS, 1.0, pad)], true, false)
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	var s: float = pad
	while s < end - 0.03:
		rings.append(HDMesh.section_ring(curves, s, STOCK_POINTS))
		s += 0.042 if (s > 0.19 and s < 0.36) else 0.075
	for t: float in [0.0, 0.7, 1.0]:
		rings.append(HDMesh.section_ring(curves, end - 0.015 + 0.015 * t, STOCK_POINTS, sqrt(1.0 - t * t * 0.9)))
	k.loft(rings, false, true)
	k.crease_deg = 50.0


static func _barrel(k: HDMesh, prof: Array, muzzle: float, tag: String) -> void:
	_fin(k, RifleHD.BLUED)
	var p: Array = []
	for key: Array in prof:
		p.append(Vector3(key[0], key[1], 0))
	var last_r: float = (prof[prof.size() - 1] as Array)[1]
	if tag == "338":
		# muzzle brake
		p.append_array([Vector3(1.05, 0.0222, 0), Vector3(muzzle - 0.003, 0.0222, 0), Vector3(muzzle, 0.019, 0)])
		last_r = 0.019
	elif muzzle > float((prof[prof.size() - 1] as Array)[0]):
		p.append(Vector3(muzzle, last_r, 0))
	p.append(Vector3(muzzle, last_r * 0.55, 0))
	k.lathe(p, SEGS, Vector3.ZERO, Vector3.FORWARD)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(muzzle, last_r * 0.55, 0), Vector3(muzzle - 0.01, last_r * 0.5, 0), Vector3(muzzle - 0.01, 0.0, 0)], 6, Vector3.ZERO, Vector3.FORWARD)


static func _scope(k: HDMesh, sc: Array, recv: Array) -> void:
	var s0: float = sc[0]
	var length: float = sc[1]
	var y: float = sc[2]
	var rt: float = sc[3]
	var rb: float = sc[4]
	var e: float = rt * 1.36
	var end: float = s0 + length
	var bs: float = rb / 0.0295
	var o: Vector3 = _v(0.0, y)
	_fin(k, RifleHD.SCOPE_BLACK)
	k.lathe([Vector3(s0, e * 0.86, 0), Vector3(s0, e, 0), Vector3(s0 + 0.085, e, 0), Vector3(s0 + 0.10, rt, 0),
		Vector3(end - 0.09 * bs, rt, 0), Vector3(end - 0.05 * bs, rb, 0), Vector3(end, rb, 0), Vector3(end, rb * 0.86, 0)],
		SEGS, o, Vector3.FORWARD)
	_fin(k, LENS)
	k.lathe([Vector3(s0 + 0.004, 0.0, 0), Vector3(s0, e * 0.86, 0)], SEGS, o, Vector3.FORWARD)
	k.lathe([Vector3(end, rb * 0.86, 0), Vector3(end - 0.004, 0.0, 0)], SEGS, o, Vector3.FORWARD)
	# turret block and the two ring mounts down to the receiver
	_fin(k, RifleHD.SCOPE_BLACK)
	var ts: float = s0 + length * 0.5
	k.cbox(_v(ts, y + rt + 0.006), Vector3(0.022, 0.014, 0.022), 0.0)
	k.cbox(_v(ts, y, rt + 0.006), Vector3(0.014, 0.022, 0.022), 0.0)
	_fin(k, RifleHD.BLUED_SATIN)
	var r: float = recv[2] if not recv.is_empty() else 0.015
	for m: float in [s0 + length * 0.3, s0 + length * 0.68]:
		var h: float = y - r
		k.cbox(_v(m, r + h * 0.5 - 0.002), Vector3(0.016, h + 0.004, 0.014), 0.0)


static func _trigger_guard(k: HDMesh, tag: String) -> void:
	var st: float = 0.355 if tag != "338" else 0.385
	var by: float = -0.052
	if tag == "12":
		st = 0.438
		by = -0.033
	elif tag == "22":
		st = 0.345
		by = -0.040
	_fin(k, RifleHD.BLUED)
	k.sweep([_v(st - 0.035, by), _v(st - 0.03, by - 0.020), _v(st + 0.005, by - 0.027), _v(st + 0.035, by - 0.012),
		_v(st + 0.04, by)], GUARD_SECTION, Vector3.RIGHT)


static func _shotgun_parts(k: HDMesh, consts: Dictionary) -> void:
	# alloy receiver block, magazine tube and the wooden slide
	_fin(k, ShotgunHD.ALLOY)
	k.cbox(_v(0.465, -0.0065), Vector3(0.0285, 0.048, 0.215), 0.004)
	_fin(k, RifleHD.BLUED_SATIN)
	k.lathe([Vector3(0.57, 0.0092, 0), Vector3(0.89, 0.0092, 0), Vector3(0.896, 0.0, 0)], 6, _v(0.0, -0.0225), Vector3.FORWARD)
	_fin(k, ShotgunHD.BRASS)
	k.sphere(_v(0.968, 0.017), Vector3.ONE * 0.0035, 4, 3)
	var fc: Dictionary = {"top": HDMesh.curve(consts["F_TOP"]), "bot": HDMesh.curve(consts["F_BOT"]), "wid": HDMesh.curve(consts["F_WID"]),
		"widest": HDMesh.curve(consts["F_WIDEST"]), "exp_top": HDMesh.curve(consts["F_EXP_TOP"]), "exp_bot": HDMesh.curve(consts["F_EXP_BOT"])}
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	for s: float in [0.575, 0.61, 0.66, 0.74, 0.80]:
		rings.append(HDMesh.section_ring(fc, s, STOCK_POINTS))
	k.loft(rings, true, true)


static func _carbine_parts(k: HDMesh) -> void:
	_fin(k, RifleHD.BLUED_SATIN)
	k.lathe([Vector3(0.56, 0.0, 0), Vector3(0.56, 0.013, 0), Vector3(0.579, 0.013, 0), Vector3(0.579, 0.0, 0)], SEGS, Vector3.ZERO, Vector3.FORWARD)
	k.cbox(_v(0.455, 0.014), Vector3(0.020, 0.010, 0.008), 0.0)
	k.cbox(_v(0.915, 0.012), Vector3(0.005, 0.014, 0.012), 0.0)
	k.cbox(_v(0.37, -0.050), Vector3(0.018, 0.030, 0.040), 0.002)


static func _m3006_parts(k: HDMesh) -> void:
	_fin(k, RifleHD.BLUED_SATIN)
	k.cbox(_v(0.503, -0.070), Vector3(0.020, 0.072, 0.085), 0.003)
	k.cbox(_v(0.74, -0.012), Vector3(0.020, 0.030, 0.034), 0.002)
	k.lathe([Vector3(0.756, 0.0048, 0), Vector3(0.944, 0.0048, 0), Vector3(0.944, 0.0, 0)], 5, _v(0.0, -0.0172), Vector3.FORWARD)


static func _m338_parts(k: HDMesh) -> void:
	_fin(k, RifleHD.BLUED)
	k.cbox(_v(0.47, -0.058), Vector3(0.024, 0.012, 0.15), 0.002)


# --- binoculars ------------------------------------------------------------------------------------

static func _build_binoculars() -> Dictionary:
	var k: HDMesh = HDMesh.new()
	for sx: float in [-1.0, 1.0]:
		_fin(k, RifleHD.RUBBER)
		k.lathe([Vector3(0.0, 0.0, 0), Vector3(0.0, 0.016, 0), Vector3(0.018, 0.019, 0), Vector3(0.03, 0.022, 0), Vector3(0.11, 0.024, 0),
			Vector3(0.13, 0.026, 0), Vector3(0.13, 0.021, 0)], SEGS, Vector3(sx * 0.034, 0.0, 0.0), Vector3.FORWARD)
		_fin(k, LENS)
		k.lathe([Vector3(0.13, 0.021, 0), Vector3(0.126, 0.0, 0)], SEGS, Vector3(sx * 0.034, 0.0, 0.0), Vector3.FORWARD)
	_fin(k, RifleHD.SCOPE_BLACK)
	k.cbox(Vector3(0.0, 0.004, -0.06), Vector3(0.04, 0.016, 0.07), 0.003)
	var built: Dictionary = k.build()
	var eyes: Vector3 = Vector3(0.0, Rig.NECK_Y, 0.0) + Rig.EYE
	var aim: Transform3D = Rig.aim_xf(Basis(Vector3.RIGHT, Rig.AIM_LEAN), 0.0, 0.0, Vector3.ZERO, eyes)
	var pose: Dictionary = _variant(built, k.triangle_count(), _materials("308"), aim, Vector3(0.05, -0.008, -0.075), Vector3(-0.05, -0.008, -0.075), BINO_POLES, true)
	return {"poses": {"aim": pose}, "anchor": Vector3.ZERO, "muzzle": Vector3(0.0, 0.0, -0.13), "flash": 0.0, "gun_tris": k.triangle_count(), "tris": pose["tris"]}


# --- forearms and gloved hands ---------------------------------------------------------------------

## Bakes both forearms for the item placed at `xf` (torso space): two-bone IK from each shoulder to the wrist.
## Gun: right fist on the grip (`right`), left hand cupped under `left` (fore-end or magazine). Binoculars: one
## fist on each barrel. Returns the elbows [left, right] in item space.
static func _hands(k: HDMesh, xf: Transform3D, right: Vector3, left: Vector3, poles: Array, binoculars: bool) -> Array:
	var inv: Transform3D = xf.affine_inverse()
	var elbows: Array = [Vector3.ZERO, Vector3.ZERO]
	for side in 2:
		var hand: Vector3 = right if side == 1 else left
		var wrist: Vector3
		var fist_r: Vector3
		var fist_b: Basis = Basis.IDENTITY
		if binoculars:
			wrist = hand + Vector3((1.0 if side == 1 else -1.0) * 0.012, -0.05, 0.045)
			fist_r = Vector3(0.026, 0.040, 0.048)
		elif side == 1:
			wrist = hand + Vector3(0.022, -0.046, 0.052)
			fist_r = Vector3(0.030, 0.050, 0.040)
			fist_b = Basis(Vector3.RIGHT, 0.62)
		else:
			wrist = hand + Vector3(-0.026, -0.05, 0.05)
			fist_r = Vector3(0.036, 0.030, 0.050)
			hand += Vector3(-0.004, -0.018, 0.0)
		var e: Vector3 = inv * Rig.elbow(Rig.shoulder(side), xf * wrist, poles[side])
		elbows[side] = e
		var d: Vector3 = (wrist - e).normalized()
		var f: float = e.distance_to(wrist)
		var ref: Vector3 = (Vector3.UP - d * d.y).normalized()
		k.surface(SURF_CLOTH)
		var pts: Array = [e - d * 0.04, e - d * 0.012, e + d * 0.10, e + d * (f - 0.07), e + d * (f - 0.045), e + d * (f - 0.04), wrist]
		var size: Array = [Vector2(0.040, 0.040), Vector2(0.064, 0.064), Vector2(0.060, 0.058), Vector2(0.052, 0.050),
			Vector2(0.050, 0.048), Vector2(0.034, 0.031), Vector2(0.029, 0.025)]
		Body._tube(k, pts, size, ref, 10, [Body.SHIRT, Body.SHIRT, Body.SHIRT, Body.SHIRT_DARK, Body.GLOVE_CUFF, Body.GLOVE], true, false)
		# palm from the wrist into the fist, then the fist closed around the grip, thumb over the top
		Body._pt(k, Body.GLOVE)
		k.begin_part()
		k.loft([Body._ring(wrist, ref, ref.cross(d), 0.025, 0.029, 0.029, 8), Body._ring(hand.lerp(wrist, 0.35), ref, ref.cross(d), 0.028, 0.040, 0.040, 8)], false, false, false)
		var keep: Transform3D = k.xf
		k.xf = Transform3D(fist_b, hand)
		k.sphere(Vector3.ZERO, fist_r, 8, 4, false)
		k.xf = keep
		k.sweep([hand + Vector3(0.0, 0.03, 0.02) + d * -0.01, hand + Vector3(0.0, 0.04, -0.012)], HDMesh.circle_section(0.010, 5), Vector3.RIGHT)
	return elbows
