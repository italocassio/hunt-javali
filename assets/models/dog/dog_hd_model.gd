extends RefCounted
## HD dog meshes (static, cached per breed, LOD and part; shared by every instance) and the one fur material shared by
## the three breeds (the coat pattern is vertex colour). Rest pose, root space: origin on the ground, forward -Z, real
## size per breed (docs/arquitetura.md 7.2). Parts:
##   body   trunk (Rig space)                     head  neck + skull + muzzle + nose + eyes (Head space = neck pivot)
##   ears   both ears (Ears space, child of Head)   tail  from the tail root
##   leg_fl / leg_fr / leg_rl / leg_rr  one leg hanging from its pivot (shoulder / hip joint), paw on the ground
##   far    everything in one mesh (rest pose), for > 50 m
## Built with the ring-grid builder of the HD boar (smooth normals from the grid, analytic AO in COLOR.a).

const BMesh := preload("res://assets/models/boar/boar_hd_mesh.gd")
const HdMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const BoarModel := preload("res://assets/models/boar/boar_hd_model.gd")
const FUR_SHADER: Shader = preload("res://assets/models/dog/dog_fur.gdshader")

const LOD_NEAR: int = 0
const LOD_MID: int = 1
const LOD_FAR: int = 2

const FEAT_FUR: float = 0.0
const FEAT_NOSE: float = 2.0
const FEAT_PAW: float = 3.0
const FEAT_EYE: float = 5.0

const BREED_IDS: Array[StringName] = [&"caramelo", &"foxhound", &"dogo"]
## Animated parts (near + mid meshes each); the legs in the order of the visual's pivots FL, FR, RL, RR.
const PARTS: Array[String] = ["body", "head", "ears", "tail", "leg_fl", "leg_fr", "leg_rl", "leg_rr"]

## Ring resolution per LOD.
const RES: Array[Dictionary] = [
	{"trunk_m": 16, "trunk_r": 20, "neck_m": 10, "head_m": 14, "head_r": 13, "nose_m": 10, "eye_m": 8,
		"ear_m": 6, "ear_steps": 1, "tail_m": 6, "tail_steps": 1, "leg_m": 8, "leg_steps": 1, "paw_m": 7, "paw_r": 4},
	{"trunk_m": 10, "trunk_r": 10, "neck_m": 7, "head_m": 8, "head_r": 7, "nose_m": 6, "eye_m": 0,
		"ear_m": 4, "ear_steps": 0, "tail_m": 4, "tail_steps": 0, "leg_m": 5, "leg_steps": 0, "paw_m": 5, "paw_r": 2},
	{"trunk_m": 6, "trunk_r": 6, "head_m": 5, "leg_m": 4, "ear_m": 3, "tail_m": 3},
]

## Breed shapes (metres): h withers, l nose to buttock, yc chest floor (elbow), yt belly at the loin, cw / waist / hipw
## trunk half widths, bone leg thickness factor, hl head length (occiput to nose), skull_hw / muzzle_hw head half widths,
## mzh muzzle depth factor, stop share of the head behind the stop, head_y skull height / h, head_pitch nose-down (rad),
## neck thickness factor, eye radius, ear / tail style. Animation: ear_back (rad, ears pinned back), tail_tuck /
## tail_run / tail_point (rad added to the tail pitch when retreating / galloping / pointing).
const BREEDS: Dictionary = {
	&"caramelo": {"h": 0.52, "l": 0.85, "yc": 0.252, "yt": 0.335, "cw": 0.080, "waist": 0.062, "hipw": 0.073,
		"bone": 1.0, "hl": 0.205, "skull_hw": 0.054, "muzzle_hw": 0.027, "mzh": 1.0, "stop": 0.47, "head_y": 1.12,
		"head_pitch": 0.18, "neck": 1.12, "eye_r": 0.0115, "ear": "semi", "tail": "curl",
		"ear_back": 0.75, "tail_tuck": 1.75, "tail_run": 1.0, "tail_point": 1.2},
	&"foxhound": {"h": 0.60, "l": 0.95, "yc": 0.33, "yt": 0.425, "cw": 0.076, "waist": 0.056, "hipw": 0.070,
		"bone": 0.92, "hl": 0.22, "skull_hw": 0.050, "muzzle_hw": 0.027, "mzh": 1.1, "stop": 0.45, "head_y": 1.15,
		"head_pitch": 0.2, "neck": 1.02, "eye_r": 0.012, "ear": "drop", "tail": "sickle",
		"ear_back": -0.45, "tail_tuck": 1.9, "tail_run": 0.9, "tail_point": 1.0},
	&"dogo": {"h": 0.64, "l": 1.00, "yc": 0.29, "yt": 0.40, "cw": 0.126, "waist": 0.090, "hipw": 0.104,
		"bone": 1.24, "hl": 0.225, "skull_hw": 0.088, "muzzle_hw": 0.051, "mzh": 1.42, "stop": 0.5, "head_y": 1.04,
		"head_pitch": 0.08, "neck": 1.35, "eye_r": 0.012, "ear": "short", "tail": "low",
		"ear_back": 0.6, "tail_tuck": 0.55, "tail_run": -0.5, "tail_point": -0.9,
		# optional shape keys (defaults keep the other breeds as they are): dome skull top factor, cheek lower-half
		# exponent of the skull (fuller masseters), blunt muzzle front, nose_z nose tip at -nose_z * l, flat_back straight
		# topline, muscle upper-leg thickness, hock hind angulation, tail_len / tail_r tail scale, leg_ao_top shade where
		# the legs leave the trunk, crease muscle shading, res_near ring overrides of the near LOD
		"dome": 1.2, "cheek_e": 3.0, "blunt": 0.65, "nose_z": 0.455, "flat_back": 1.0, "muscle": 1.12, "hock": 0.65,
		"tail_len": 0.8, "tail_r": 1.25, "leg_ao_top": 0.82, "crease": 1.0, "neck_top": [0.058, 0.04, 0.075], "chest_round": true,
		"res_near": {"trunk_m": 18, "trunk_r": 18, "neck_m": 12}},
}

# Head shape in units of hl, against the unwarped head coordinate u (0 occiput .. 1 nose tip; the stop sits at 0.46).
const HEAD_STOP_U: float = 0.46
const HEAD_TOP: Array = [[0.0, 0.10], [0.06, 0.18], [0.16, 0.235], [0.30, 0.24], [0.38, 0.225], [0.45, 0.19], [0.51, 0.145],
	[0.58, 0.125], [0.72, 0.115], [0.88, 0.11], [0.96, 0.10], [1.0, 0.075]]
const HEAD_BOT: Array = [[0.0, -0.12], [0.08, -0.21], [0.18, -0.255], [0.30, -0.255], [0.42, -0.225], [0.55, -0.195],
	[0.70, -0.185], [0.85, -0.178], [0.94, -0.165], [0.985, -0.14], [1.0, -0.115]]
## Head half width shape: skull part (scaled by skull_hw / 0.26 hl) and muzzle part (scaled by muzzle_hw / 0.145 hl).
const HEAD_HW: Array = [[0.0, 0.12], [0.08, 0.21], [0.20, 0.26], [0.32, 0.26], [0.42, 0.215], [0.52, 0.165], [0.64, 0.15],
	[0.80, 0.145], [0.92, 0.14], [0.975, 0.125], [1.0, 0.10]]
const HEAD_WIDEST: Array = [[0.0, 0.5], [0.3, 0.58], [0.6, 0.52], [1.0, 0.48]]
const EYE_U: float = 0.36
const EYE_Y: float = 0.11
const EYE_DARK: Color = Color(0.035, 0.022, 0.015)
const EYE_IRIS: Color = Color(0.22, 0.12, 0.05)
const EYE_LID: Array = [[0.0, 1.5, 1.25], [0.32, 1.15, 0.92], [0.42, 1.0, 0.76]]
const EYE_GLOBE: Array = [[0.3, 1.0, 0.75], [0.66, 0.78, 0.58], [0.86, 0.42, 0.33]]
const EYE_POLE: float = 0.93
const EAR_U: float = 0.17

## Front leg control points for a 0.40 m pivot: [x, y, z, rx (side), rz (front-back)]: shoulder buried in the trunk,
## upper arm, elbow at the back, straight forearm, wrist, pastern sloping forward.
const LEG_FRONT: Array = [[-0.022, 0.05, 0.015, 0.024, 0.038], [-0.008, 0.01, 0.025, 0.042, 0.062], [0.0, -0.05, 0.035, 0.046, 0.068],
	[0.002, -0.11, 0.045, 0.039, 0.056], [0.0, -0.16, 0.030, 0.029, 0.039], [0.0, -0.24, 0.022, 0.023, 0.029],
	[0.0, -0.312, 0.020, 0.018, 0.021], [0.0, -0.342, 0.010, 0.0185, 0.021], [0.0, -0.366, 0.000, 0.020, 0.024]]
## Hind leg: hip buried, heavy thigh, stifle forward, gaskin, hock behind, near vertical metatarsus.
const LEG_HIND: Array = [[-0.024, 0.055, 0.0, 0.024, 0.044], [-0.010, 0.015, 0.0, 0.046, 0.080], [0.0, -0.05, -0.015, 0.052, 0.084],
	[0.003, -0.12, -0.030, 0.044, 0.068], [0.004, -0.165, -0.035, 0.033, 0.048], [0.0, -0.21, -0.006, 0.027, 0.044],
	[0.0, -0.255, 0.035, 0.020, 0.030], [0.0, -0.282, 0.055, 0.017, 0.026], [0.0, -0.312, 0.050, 0.016, 0.019],
	[0.0, -0.35, 0.034, 0.0165, 0.019], [0.0, -0.368, 0.026, 0.020, 0.022]]
const LEG_MID_FRONT: Array = [0, 2, 3, 5, 6, 8]
const LEG_MID_HIND: Array = [0, 2, 4, 7, 8, 10]
## Paw sections from the toes back, for a 0.40 m pivot: [dz, top, half width]; the sole sits on the ground.
const PAW: Array = [[-0.030, 0.014, 0.017], [-0.020, 0.026, 0.023], [-0.004, 0.034, 0.024], [0.012, 0.033, 0.021],
	[0.026, 0.021, 0.014]]
const PAW_MID: Array = [0, 2, 4]

static var _meshes: Dictionary = {}
static var _tris: Dictionary = {}
static var _material: ShaderMaterial = null
static var _layouts: Dictionary = {}
static var _curves: Dictionary = {}


static func spec(breed: StringName) -> Dictionary:
	return BREEDS.get(breed, BREEDS[&"caramelo"])


static func breed_or_default(breed: StringName) -> StringName:
	return breed if BREEDS.has(breed) else &"caramelo"


# --- layout ------------------------------------------------------------------------------------------------

## Pivots and frames of one breed (root space unless noted):
##   zf / zb trunk front / back, np neck pivot (Head node rest position), skull (skull frame in Head space: origin at the
##   occiput, nose at z = -hl), ears (Ears node rest transform in Head space), mouth (Head space), tail (tail root),
##   hips [FL, FR, RL, RR], leg_k front / hind leg scale against the 0.40 m tables.
static func layout(breed: StringName) -> Dictionary:
	breed = breed_or_default(breed)
	if _layouts.has(breed):
		return _layouts[breed]
	var b: Dictionary = spec(breed)
	var h: float = b["h"]
	var l: float = b["l"]
	var yc: float = b["yc"]
	var zf: float = -0.24 * l
	var zb: float = 0.47 * l
	var tl: float = zb - zf
	var np: Vector3 = Vector3(0.0, yc + 0.60 * (h - yc), zf + 0.12 * tl)
	var hl: float = b["hl"]
	var ph: float = b["head_pitch"]
	var occ: Vector3 = Vector3(0.0, h * float(b["head_y"]), -float(b.get("nose_z", 0.5)) * l + hl * cos(ph))
	var skull: Transform3D = Transform3D(Basis(Vector3.RIGHT, -ph), occ - np)
	var out: Dictionary = {"h": h, "l": l, "zf": zf, "zb": zb, "np": np, "skull": skull, "hl": hl}
	_layouts[breed] = out   # head_y_at below needs the curves only, not the layout
	var ear_y: float = _head_top(breed, EAR_U)
	out["ears"] = skull * Transform3D(Basis.IDENTITY, Vector3(0.0, ear_y - 0.01 * hl, -EAR_U * hl))
	out["mouth"] = skull * Vector3(0.0, -0.03 * hl, -hl - 0.01)
	var fy: float = yc + 0.55 * (h * 0.97 - yc)
	var fz: float = zf + 0.15 * tl
	var fx: float = float(b["cw"]) * 0.62
	var ry: float = h * 0.77
	var rz: float = zf + 0.855 * tl
	var rx: float = float(b["hipw"]) * 0.62
	out["hips"] = [Vector3(-fx, fy, fz), Vector3(fx, fy, fz), Vector3(-rx, ry, rz), Vector3(rx, ry, rz)]
	out["leg_k"] = [fy / 0.40, ry / 0.40]
	out["tail"] = Vector3(0.0, trunk_top(breed, 0.955) - 0.012, zf + 0.955 * tl)
	return out


# --- curves ------------------------------------------------------------------------------------------------

static func _cv(breed: StringName) -> Dictionary:
	if _curves.has(breed):
		return _curves[breed]
	var b: Dictionary = spec(breed)
	var h: float = b["h"]
	var yc: float = b["yc"]
	var yt: float = b["yt"]
	var cw: float = b["cw"]
	var ww: float = b["waist"]
	var hw: float = b["hipw"]
	var top: Array = [[0.0, 0.80 * h], [0.08, 0.92 * h], [0.20, h], [0.30, 0.985 * h], [0.50, 0.955 * h], [0.70, 0.95 * h],
		[0.82, 0.94 * h], [0.92, 0.905 * h], [0.97, 0.85 * h], [1.0, 0.78 * h]]
	var fb: float = b.get("flat_back", 0.0)
	if fb > 0.0:
		var flat: Array = [0.82, 0.94, 1.0, 0.995, 0.987, 0.982, 0.972, 0.935, 0.875, 0.79]
		for i in top.size():
			top[i] = [top[i][0], lerpf(float(top[i][1]), flat[i] * h, fb)]
	var bot: Array = [[0.0, 0.70 * h], [0.05, lerpf(yc, 0.70 * h, 0.45)], [0.16, yc + 0.015], [0.30, yc], [0.42, yc + 0.012],
		[0.56, lerpf(yc, yt, 0.62)], [0.68, yt], [0.80, yt + 0.01], [0.90, lerpf(yt, 0.72 * h, 0.6)], [1.0, 0.72 * h]]
	var wid: Array = [[0.0, 0.50 * cw], [0.08, 0.80 * cw], [0.22, cw], [0.40, 0.97 * cw], [0.55, lerpf(cw, ww, 0.6)],
		[0.66, ww], [0.80, hw], [0.90, 0.95 * hw], [0.97, 0.72 * hw], [1.0, 0.40 * hw]]
	if b.get("chest_round", false):
		# wide chests: the front rings close in to a rounded breast, so the flat front cap shrinks to a dot
		top[0] = [0.0, 0.79 * h]
		bot[0] = [0.0, 0.73 * h]
		wid[0] = [0.0, 0.2 * cw]
		wid[1] = [0.08, 0.74 * cw]
	var c: Dictionary = {"tt": HdMesh.curve(top), "tb": HdMesh.curve(bot), "tw": HdMesh.curve(wid),
		"tm": HdMesh.curve([[0.0, 0.55], [0.3, 0.46], [0.7, 0.42], [1.0, 0.45]]),
		"te": HdMesh.curve([[0.0, 2.2], [0.25, 2.3], [0.7, 2.6], [1.0, 2.4]]),
		"tf": HdMesh.curve([[0.0, 1.9], [0.3, 1.75], [0.65, 2.1], [1.0, 2.2]]),
		"ht": HdMesh.curve(HEAD_TOP), "hb": HdMesh.curve(HEAD_BOT), "hw": HdMesh.curve(HEAD_HW), "hm": HdMesh.curve(HEAD_WIDEST)}
	_curves[breed] = c
	return c


static func trunk_top(breed: StringName, t: float) -> float:
	return HdMesh.pchip(_cv(breed)["tt"], t)


## Trunk section at t (0 front .. 1 back): [z, top, bot, hw, ym, et, eb].
static func _trunk_sec(breed: StringName, t: float) -> Array:
	var c: Dictionary = _cv(breed)
	var lay: Dictionary = _layouts[breed] if _layouts.has(breed) else layout(breed)
	var top: float = HdMesh.pchip(c["tt"], t)
	var bot: float = HdMesh.pchip(c["tb"], t)
	return [lerpf(lay["zf"], lay["zb"], t), top, bot, HdMesh.pchip(c["tw"], t), lerpf(top, bot, HdMesh.pchip(c["tm"], t)),
		HdMesh.pchip(c["te"], t), HdMesh.pchip(c["tf"], t)]


static func trunk_ring(breed: StringName, t: float, m: int) -> PackedVector3Array:
	var s: Array = _trunk_sec(breed, t)
	var ring: PackedVector3Array = BMesh.super_ring(s[0], s[1], s[2], s[3], s[4], s[5], s[6], m)
	# shoulder blades: a little more width high on the forehand
	var sh: float = 0.010 * _bump(t, 0.05, 0.2, 0.36) * float(spec(breed)["cw"]) / 0.078
	if sh > 0.0:
		var top: float = s[1]
		var bot: float = s[2]
		for i in m:
			var p: Vector3 = ring[i]
			var hy: float = 1.0 - absf(p.y - lerpf(bot, top, 0.68)) / maxf(top - bot, 0.01) * 2.5
			p.x += signf(p.x) * sh * clampf(hy, 0.0, 1.0)
			ring[i] = p
	return ring


## Warps the head coordinate so the breed's stop lands on HEAD_STOP_U of the tables.
static func _hu(breed: StringName, u: float) -> float:
	var st: float = spec(breed)["stop"]
	if u < st:
		return u * HEAD_STOP_U / st
	return HEAD_STOP_U + (u - st) * (1.0 - HEAD_STOP_U) / (1.0 - st)


## Head section at u (skull frame, metres): [z, top, bot, hw, ym].
static func _head_sec(breed: StringName, u: float) -> Array:
	var b: Dictionary = spec(breed)
	var c: Dictionary = _cv(breed)
	var hl: float = b["hl"]
	var w: float = _hu(breed, u)
	var muz: float = smoothstep(0.40, 0.58, w)
	var depth: float = lerpf(1.0, float(b["mzh"]), muz)
	# blunt: the muzzle keeps its section up to the nose instead of tapering
	var wf: float = lerpf(w, minf(w, 0.9), float(b.get("blunt", 0.0)))
	var dome: float = lerpf(float(b.get("dome", 1.0)), 1.0, smoothstep(0.38, 0.5, w))
	var top: float = HdMesh.pchip(c["ht"], wf) * hl * lerpf(1.0, depth, 0.5) * dome
	var bot: float = HdMesh.pchip(c["hb"], wf) * hl * depth
	var shape: float = HdMesh.pchip(c["hw"], wf) * hl
	var hw: float = lerpf(shape * float(b["skull_hw"]) / (0.26 * hl), shape * float(b["muzzle_hw"]) / (0.145 * hl), muz)
	return [-u * hl, top, bot, hw, lerpf(top, bot, HdMesh.pchip(c["hm"], w))]


## Superellipse exponents of the head section at u: upper (boxy muzzle top) and lower (full cheeks on the dogo).
static func _head_e(breed: StringName, u: float) -> Vector2:
	var eb: float = lerpf(float(spec(breed).get("cheek_e", 2.2)), 2.2, smoothstep(0.42, 0.6, u))
	return Vector2(lerpf(2.3, 2.8, smoothstep(0.45, 0.6, u)), eb)


static func head_ring(breed: StringName, u: float, m: int) -> PackedVector3Array:
	var s: Array = _head_sec(breed, u)
	var e: Vector2 = _head_e(breed, u)
	return BMesh.super_ring(s[0], s[1], s[2], s[3], s[4], e.x, e.y, m)


static func _head_top(breed: StringName, u: float) -> float:
	return float(_head_sec(breed, u)[1])


## Head surface half width at (u, y) (skull frame), inverse of the super ring.
static func head_x_at(breed: StringName, u: float, y: float) -> float:
	var s: Array = _head_sec(breed, u)
	var top: float = s[1]
	var bot: float = s[2]
	var ym: float = s[4]
	var he: Vector2 = _head_e(breed, u)
	var e: float = he.x if y >= ym else he.y
	var hh: float = (top - ym) if y >= ym else (ym - bot)
	var q: float = clampf(absf(y - ym) / maxf(hh, 1e-4), 0.0, 1.0)
	return float(s[3]) * pow(maxf(1.0 - pow(q, e), 0.0), 1.0 / e)


## Head upper surface height at (u, x) (skull frame).
static func head_y_at(breed: StringName, u: float, x: float) -> float:
	var s: Array = _head_sec(breed, u)
	var e: float = _head_e(breed, u).x
	var q: float = clampf(absf(x) / float(s[3]), 0.0, 1.0)
	return float(s[4]) + (float(s[1]) - float(s[4])) * pow(maxf(1.0 - pow(q, e), 0.0), 1.0 / e)


static func _bump(x: float, a: float, peak: float, b: float) -> float:
	if x <= a or x >= b:
		return 0.0
	var t: float = (x - a) / (peak - a) if x < peak else (b - x) / (b - peak)
	return t * t * (3.0 - 2.0 * t)


static func _hash(p: Vector3) -> float:
	return fposmod(sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453, 1.0)


static func _mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


# --- coat --------------------------------------------------------------------------------------------------

const Z_BODY: int = 0
const Z_NECK: int = 1
const Z_HEAD: int = 2
const Z_LEG: int = 3
const Z_TAIL: int = 4
const Z_EAR: int = 5

## Coat colour (as stored, see dog_fur.gdshader) at a rest-pose point p / normal n in root space. `q`: skull-frame
## point for the head (muzzle, blaze, lips), tail / ear share along the part in q.x.
static func coat(breed: StringName, zone: int, p: Vector3, n: Vector3, q: Vector3 = Vector3.ZERO) -> Color:
	var b: Dictionary = spec(breed)
	var lay: Dictionary = layout(breed)
	var h: float = b["h"]
	var yc: float = b["yc"]
	var hl: float = b["hl"]
	var zf: float = lay["zf"]
	var zb: float = lay["zb"]
	var u: float = -q.z / hl
	var lip: float = _lip_y(breed, u)
	match breed:
		&"foxhound":
			var tan: Color = Color(0.64, 0.41, 0.22)
			var black: Color = Color(0.085, 0.07, 0.06)
			var white: Color = Color(0.90, 0.88, 0.83)
			var c: Color = _mix(tan, Color(0.55, 0.34, 0.17), smoothstep(0.6, 0.95, n.y) * 0.5)
			match zone:
				Z_BODY, Z_NECK:
					# black saddle from behind the withers to the croup, wavy lower edge
					var zt: float = inverse_lerp(zf, zb, p.z)
					var edge: float = lerpf(yc, h, 0.42) + 0.018 * sin(p.z * 37.0 + 0.6) + 0.01 * sin(p.z * 83.0)
					var sad: float = smoothstep(edge - 0.012, edge + 0.012, p.y) * smoothstep(0.24, 0.32, zt) * (1.0 - smoothstep(0.86, 0.93, zt))
					c = _mix(c, black, sad)
					# white chest, throat and belly
					var under: float = 1.0 - smoothstep(-0.55, -0.2, n.y)
					var chest: float = (1.0 - smoothstep(-0.05, 0.25, n.y)) * (1.0 - smoothstep(0.08, 0.30, zt)) * smoothstep(0.1, 0.5, -n.z)
					var throat: float = 0.0
					if zone == Z_NECK:
						throat = smoothstep(0.15, 0.5, -n.z) * (1.0 - smoothstep(-0.2, 0.35, n.y))
					c = _mix(c, white, maxf(maxf(under, chest), throat))
				Z_HEAD:
					# white blaze up the muzzle to the forehead, white muzzle sides and chin
					var bw: float = lerpf(0.006, 0.016, smoothstep(0.3, 0.6, u))
					var blaze: float = (1.0 - smoothstep(bw * 0.7, bw * 1.3, absf(q.x))) * smoothstep(0.22, 0.32, u) * smoothstep(0.1, 0.5, n.y)
					var muzzle: float = smoothstep(0.52, 0.62, u) * (1.0 - smoothstep(lip + 0.004, lip + 0.03 * hl / 0.235, q.y))
					var chin: float = (1.0 - smoothstep(-0.6, -0.2, n.y)) * smoothstep(0.35, 0.5, u)
					c = _mix(c, white, maxf(blaze, maxf(muzzle, chin)))
				Z_LEG:
					# white legs, tan high on the thigh / arm outside
					var tan_up: float = smoothstep(yc * 0.95, yc * 1.12, p.y) * smoothstep(0.1, 0.5, absf(n.x))
					c = _mix(white, c, tan_up)
				Z_TAIL:
					c = _mix(_mix(white, black, smoothstep(-0.3, 0.2, n.y)), tan, 0.15)
					c = _mix(c, white, smoothstep(0.70, 0.78, q.x))
				Z_EAR:
					c = _mix(tan, Color(0.30, 0.17, 0.08), smoothstep(0.45, 1.0, q.x) * 0.7)
			return c
		&"dogo":
			# warm cream white, kept below 1 so the sun leaves room for the muscle shading
			var white2: Color = Color(0.83, 0.79, 0.72)
			var shade: Color = Color(0.64, 0.59, 0.53)
			var pink: Color = Color(0.80, 0.58, 0.54)
			var c2: Color = _mix(shade, white2, smoothstep(-0.7, 0.45, n.y))
			match zone:
				Z_BODY:
					c2 = _mix(c2, Color(0.80, 0.70, 0.66), (1.0 - smoothstep(-0.9, -0.6, n.y)) * smoothstep(0.45, 0.6, inverse_lerp(zf, zb, p.z)) * 0.5)
					c2 *= 1.0 - 0.16 * _crease(breed, p)
				Z_HEAD:
					var lips: float = smoothstep(0.55, 0.7, u) * (1.0 - smoothstep(0.0, 0.012, absf(q.y - lip - 0.006)))
					c2 = _mix(c2, pink, lips * 0.55)
				Z_EAR:
					c2 = _mix(c2, pink, smoothstep(0.6, 1.0, q.y) * 0.4)
			return c2
		_:
			var back: Color = Color(0.72, 0.48, 0.27)
			var light: Color = Color(0.88, 0.76, 0.58)
			var dark: Color = Color(0.56, 0.35, 0.18)
			var c3: Color = _mix(light, back, smoothstep(-0.55, 0.2, n.y))
			c3 = _mix(c3, dark, smoothstep(0.78, 0.98, n.y) * 0.35)
			match zone:
				Z_BODY, Z_NECK:
					var zt2: float = inverse_lerp(zf, zb, p.z)
					var front: float = smoothstep(0.2, 0.6, -n.z) * (1.0 - smoothstep(0.0, 0.4, n.y)) * (1.0 - smoothstep(0.1, 0.25, zt2))
					c3 = _mix(c3, light, front * 0.8)
				Z_HEAD:
					var muz: float = smoothstep(0.50, 0.62, u) * (1.0 - smoothstep(lip + 0.004, lip + 0.022, q.y))
					var cheek: float = smoothstep(0.2, 0.32, u) * (1.0 - smoothstep(-0.07 * hl, 0.0, q.y)) * 0.55
					var mask: float = smoothstep(0.78, 0.95, u) * smoothstep(0.2, 0.7, n.y) * 0.45
					c3 = _mix(c3, light, maxf(muz, cheek))
					c3 = _mix(c3, dark, mask)
				Z_LEG:
					c3 = _mix(c3, light, smoothstep(0.3, 0.8, n.z) * 0.25)
				Z_TAIL:
					c3 = _mix(c3, light, (1.0 - smoothstep(-0.5, 0.1, n.y)) * 0.6)
					c3 = _mix(c3, dark, smoothstep(0.75, 1.0, q.x) * 0.3)
				Z_EAR:
					c3 = _mix(back, dark, smoothstep(0.55, 1.0, q.x) * 0.6)
			return c3


## Muscle grooves painted on a trunk point (0..1): behind the shoulder blade, in front of the thigh.
## Only breeds with "crease" (dogo).
static func _crease(breed: StringName, p: Vector3) -> float:
	var b: Dictionary = spec(breed)
	var k: float = b.get("crease", 0.0)
	if k <= 0.0:
		return 0.0
	var lay: Dictionary = layout(breed)
	var t: float = inverse_lerp(lay["zf"], lay["zb"], p.z)
	var y: float = p.y / float(b["h"])
	var shoulder: float = _bump(t, 0.24, 0.31, 0.38) * _bump(y, 0.48, 0.70, 0.92)
	var flank: float = _bump(t, 0.66, 0.74, 0.82) * _bump(y, 0.55, 0.70, 0.88)
	return k * maxf(shoulder, flank)


## Lip line height (skull frame) at head coordinate u: from under the nose back to the mouth corner.
static func _lip_y(breed: StringName, u: float) -> float:
	var hl: float = spec(breed)["hl"]
	var mzh: float = spec(breed)["mzh"]
	return lerpf(-0.13, -0.06, smoothstep(0.58, 1.0, u)) * hl * mzh


static func _nose_color(breed: StringName) -> Color:
	return Color(0.62, 0.40, 0.38) if breed == &"dogo" else Color(0.07, 0.055, 0.05)


static func _rim_color(breed: StringName) -> Color:
	return Color(0.42, 0.27, 0.25) if breed == &"dogo" else Color(0.10, 0.07, 0.055)


static func _ao_side(n: Vector3) -> float:
	return lerpf(0.5, 1.0, smoothstep(-0.95, 0.2, n.y))


# --- cache -------------------------------------------------------------------------------------------------

static func _key(breed: StringName, lod: int, part: String) -> String:
	return "%s|%d|%s" % [breed, lod, part]


static func is_cached(breed: StringName) -> bool:
	return _meshes.has(_key(breed_or_default(breed), LOD_FAR, "far"))


## Every mesh of one breed: { "body": [near, mid], "head": [..], "ears": [..], "tail": [..], "leg_fl" / "leg_fr" / "leg_rl" /
## "leg_rr": [..] (mirrored pairs), "far": mesh }.
static func get_set(breed: StringName) -> Dictionary:
	breed = breed_or_default(breed)
	var out: Dictionary = {}
	for part: String in PARTS:
		out[part] = [get_mesh(breed, LOD_NEAR, part), get_mesh(breed, LOD_MID, part)]
	out["far"] = get_mesh(breed, LOD_FAR, "far")
	return out


static func get_mesh(breed: StringName, lod: int, part: String) -> ArrayMesh:
	var key: String = _key(breed, lod, part)
	if _meshes.has(key):
		return _meshes[key]
	var mesh: ArrayMesh = ArrayMesh.new()
	var k: BMesh = build_part(breed, lod, part)
	k.commit(mesh, get_material())
	_meshes[key] = mesh
	_tris[key] = k.triangle_count()
	return mesh


static func triangles(breed: StringName, lod: int, part: String) -> int:
	get_mesh(breed, lod, part)
	return int(_tris[_key(breed, lod, part)])


static func get_material() -> ShaderMaterial:
	if _material == null:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = FUR_SHADER
		m.set_shader_parameter(&"noise_tex", BoarModel.noise_texture())
		_material = m
	return _material


# --- parts -------------------------------------------------------------------------------------------------

static func build_part(breed: StringName, lod: int, part: String) -> BMesh:
	var res: Dictionary = RES[lod]
	var b: Dictionary = spec(breed)
	if lod == LOD_NEAR and b.has("res_near"):
		res = res.merged(b["res_near"], true)
	var k: BMesh = BMesh.new()
	match part:
		"body":
			_trunk(k, breed, res)
		"head":
			_neck(k, breed, res)
			_head(k, breed, res)
		"ears":
			_ears(k, breed, res)
		"tail":
			_tail(k, breed, res)
		"leg_fl", "leg_fr", "leg_rl", "leg_rr":
			_leg(k, breed, res, part.begins_with("leg_f"), -1.0 if part.ends_with("l") else 1.0)
		"far":
			_far(k, breed, res)
	return k


static func _trunk(k: BMesh, breed: StringName, res: Dictionary) -> void:
	var b: Dictionary = spec(breed)
	var m: int = res["trunk_m"]
	var nr: int = res["trunk_r"]
	var rings: Array = []
	for r in nr:
		var u: float = float(r) / float(nr - 1)
		rings.append(trunk_ring(breed, lerpf(u, 0.5 - 0.5 * cos(PI * u), 0.5), m))
	var lay: Dictionary = layout(breed)
	var hips: Array = lay["hips"]
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = coat(breed, Z_BODY, p, n)
		var v: float = 0.95 + 0.10 * _hash(p)
		var ao: float = _ao_side(n)
		# where the legs leave the body
		var near_leg: float = 0.0
		for hp: Vector3 in hips:
			near_leg = maxf(near_leg, 1.0 - smoothstep(0.04, 0.12, Vector2(p.z - hp.z, p.y - (hp.y - 0.12)).length()))
		ao *= 1.0 - 0.25 * near_leg
		return Color(c.r * v, c.g * v, c.b * v, ao)
	var pole0: Vector3 = b.get("chest_pole", Vector3(0.0, -0.012, -0.02))
	k.grid(rings, paint, FEAT_FUR + 0.1, true, true, pole0, Vector3(0.0, 0.0, 0.018), false, true)


## Neck in Head space: from inside the chest up to under the occiput (buried at both ends).
static func _neck(k: BMesh, breed: StringName, res: Dictionary) -> void:
	var b: Dictionary = spec(breed)
	var lay: Dictionary = layout(breed)
	var skull: Transform3D = lay["skull"]
	var hl: float = b["hl"]
	var kk: float = float(b["h"]) / 0.52 * float(b["neck"])
	var sw: float = b["skull_hw"]
	var top: Vector3 = skull * Vector3(0.0, -0.05 * hl, 0.02 * hl)
	var mid: Vector3 = top * 0.5 + Vector3(0.0, 0.012, 0.012) * kk
	var pts: Array = [Vector3(0.0, -0.035, 0.05) * kk, Vector3.ZERO, mid, top, skull * Vector3(0.0, -0.05 * hl, -0.12 * hl)]
	var rx: Array = [0.068 * kk, 0.064 * kk, 0.050 * kk, maxf(sw * 0.85, 0.042 * kk), sw * 0.7]
	var ry: Array = [0.092 * kk, 0.088 * kk, 0.066 * kk, 0.05 * kk, 0.04 * kk]
	if b.has("neck_top"):
		# heavy necks: keep the top rings inside the head (no sliver under the jaw, no hump behind the skull)
		var nt: Array = b["neck_top"]
		ry[2] = minf(float(ry[2]), float(nt[0]) * 1.25)
		ry[3] = nt[0]
		ry[4] = nt[1]
		rx[3] = nt[2]
	var pick: Array = [0, 1, 2, 3, 4] if int(res["neck_m"]) >= 8 else [0, 2, 3]
	var path: PackedVector3Array = PackedVector3Array()
	var prx: PackedFloat32Array = PackedFloat32Array()
	var pry: PackedFloat32Array = PackedFloat32Array()
	for i: int in pick:
		path.push_back(pts[i])
		prx.push_back(rx[i])
		pry.push_back(ry[i])
	var np: Vector3 = lay["np"]
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = coat(breed, Z_NECK, p + np, n)
		var v: float = 0.95 + 0.10 * _hash(p)
		return Color(c.r * v, c.g * v, c.b * v, lerpf(0.6, 1.0, smoothstep(-0.9, 0.3, n.y)))
	k.grid(BMesh.tube_rings(path, prx, pry, Vector3.RIGHT, res["neck_m"]), paint, FEAT_FUR + 0.1)


static func _head(k: BMesh, breed: StringName, res: Dictionary) -> void:
	var b: Dictionary = spec(breed)
	var lay: Dictionary = layout(breed)
	var skull: Transform3D = lay["skull"]
	var np: Vector3 = lay["np"]
	var hl: float = b["hl"]
	var m: int = res["head_m"]
	var nr: int = res["head_r"]
	var rings: Array = []
	for r in nr:
		var t: float = float(r) / float(nr - 1)
		rings.append(head_ring(breed, lerpf(t, 0.5 - 0.5 * cos(PI * t), 0.3), m))
	var eye_r: float = b["eye_r"]
	var eye_c: Vector3 = Vector3(head_x_at(breed, EYE_U, EYE_Y * hl) - 0.3 * eye_r, EYE_Y * hl, -EYE_U * hl)
	var eye_m: int = res["eye_m"]
	var rim: Color = _rim_color(breed)
	var lipc: Color = Color(0.40, 0.25, 0.24) if breed == &"dogo" else Color(0.08, 0.055, 0.045)
	# mid LOD (no eye geometry): the vertices nearest the eye are painted as the eye
	var eye_v: float = -1.0
	if eye_m == 0:
		eye_v = INF
		for ring: PackedVector3Array in rings:
			for q in ring:
				if q.x > 0.0:
					eye_v = minf(eye_v, q.distance_to(eye_c))
	var sb: Basis = skull.basis
	k.xf = skull
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var u: float = -p.z / hl
		var c: Color = coat(breed, Z_HEAD, np + skull * p, sb * n, p)
		# mouth line on the sides, from under the nose to the corner
		var ly: float = _lip_y(breed, u)
		var lip: float = (1.0 - smoothstep(0.0025, 0.007, absf(p.y - ly))) * smoothstep(0.58, 0.66, u) * smoothstep(0.15, 0.5, absf(n.x) + 0.3 * smoothstep(0.92, 1.0, u))
		c = _mix(c, lipc, lip * 0.85)
		# eyebrows / brow shadow above the eyes and the dark rims around them
		if eye_v >= 0.0:
			var ed: float = Vector3(absf(p.x), p.y, p.z).distance_to(eye_c) - eye_v
			c = _mix(c, rim, 1.0 - smoothstep(0.004, 0.012, ed))
			c = _mix(c, EYE_DARK, (1.0 - smoothstep(0.0, 0.004, ed)) * 0.9)
		var v: float = 0.95 + 0.10 * _hash(p)
		var ao: float = lerpf(0.55, 1.0, smoothstep(-0.95, 0.1, n.y)) * (1.0 - lip * 0.3)
		return Color(c.r * v, c.g * v, c.b * v, ao)
	k.grid(rings, paint, FEAT_FUR + 0.05, true, true, Vector3(0.0, 0.0, 0.004), Vector3(0.0, 0.0, -0.006))
	# nose leather: a rounded pad on the tip of the muzzle, nostrils drawn by the shader (planar UV)
	var ns: Array = _head_sec(breed, 1.0)
	var mw: float = b["muzzle_hw"]
	var nrx: float = mw * 0.78
	var nry: float = 0.065 * hl * float(b["mzh"])
	var ncy: float = float(ns[1]) - nry * 0.85
	var nz: float = -hl
	var nose_c: Color = _nose_color(breed)
	var nm: int = res["nose_m"]
	var nose_rings: Array = []
	var nsec: Array = [[0.012, 0.85], [0.002, 1.0], [-0.006, 0.93], [-0.010, 0.66]] if nm >= 8 else [[0.008, 0.95], [-0.008, 0.75]]
	for q: Array in nsec:
		var f: float = q[1]
		nose_rings.append(BMesh.super_ring(nz + float(q[0]), ncy + nry * f, ncy - nry * f, nrx * f, ncy + nry * 0.15 * f, 2.6, 2.0, nm))
	var nose_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
		var c: Color = _mix(_mix(nose_c, Color(0.0, 0.0, 0.0), 0.2), nose_c, smoothstep(0.0, 0.4, t))
		return Color(c.r, c.g, c.b, lerpf(0.75, 1.0, t))
	k.grid(nose_rings, nose_paint, FEAT_NOSE + 0.2, false, true, Vector3.ZERO, Vector3(0.0, 0.0, -0.003), false, false,
		Vector4(0.0, ncy, 1.0 / nrx, 1.0 / nry))
	# eyes: dark lid rim laid on the head surface around a domed wet globe (brown iris ring, black pupil)
	if eye_m > 0:
		var lid_paint: Callable = func(p: Vector3, n: Vector3, _a: float, t: float) -> Color:
			var fur: Color = coat(breed, Z_HEAD, np + skull * p, sb * n, p)
			var c: Color = _mix(_mix(fur, rim, smoothstep(0.15, 0.6, t)), _mix(rim, EYE_DARK, 0.5), smoothstep(0.6, 1.0, t))
			return Color(c.r, c.g, c.b, lerpf(0.95, 0.7, t))
		var globe_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
			var c: Color = _mix(_mix(EYE_DARK, EYE_IRIS, smoothstep(0.0, 0.4, t)), EYE_DARK, smoothstep(0.55, 0.95, t))
			return Color(c.r, c.g, c.b, lerpf(0.75, 1.0, t))
		for sx: float in [-1.0, 1.0]:
			var c: Vector3 = Vector3(eye_c.x * sx, eye_c.y, eye_c.z)
			var out: Vector3 = Vector3(sx * 0.78, 0.12, -0.62).normalized()
			var fwd: Vector3 = (Vector3.FORWARD - out * out.dot(Vector3.FORWARD)).normalized()
			var up: Vector3 = fwd.cross(out).normalized() * sx
			var lid_rings: Array = []
			for j in EYE_LID.size():
				var ring: PackedVector3Array = _eye_ring(c, out, fwd, up, EYE_LID[j], eye_m, eye_r)
				if j == 0:
					for i in eye_m:
						var e: Vector3 = ring[i]
						ring[i] = Vector3(sx * (head_x_at(breed, -e.z / hl, e.y) - 0.0012), e.y, e.z)
				lid_rings.append(ring)
			k.grid(lid_rings, lid_paint, FEAT_EYE + 0.4)
			var globe_rings: Array = []
			for q2: Array in EYE_GLOBE:
				globe_rings.append(_eye_ring(c, out, fwd, up, q2, eye_m, eye_r))
			k.grid(globe_rings, globe_paint, FEAT_EYE, false, true, Vector3.ZERO,
				out * eye_r * (EYE_POLE - float((EYE_GLOBE[EYE_GLOBE.size() - 1] as Array)[0])))
	k.xf = Transform3D.IDENTITY


static func _eye_ring(c: Vector3, out: Vector3, fwd: Vector3, up: Vector3, q: Array, m: int, r: float) -> PackedVector3Array:
	var ring: PackedVector3Array = PackedVector3Array()
	ring.resize(m)
	var o: Vector3 = c + out * (float(q[0]) * r)
	for i in m:
		var a: float = TAU * float(i) / float(m)
		ring[i] = o + fwd * (cos(a) * float(q[1]) * r) + up * (sin(a) * float(q[2]) * r)
	return ring


## Ear control points (Ears space = skull orientation, origin on the skull top line): per point
## [x (outward), y, z, half width, half thickness]; `side` is the ear's wide direction.
static func _ear_spec(breed: StringName) -> Dictionary:
	var b: Dictionary = spec(breed)
	var hl: float = b["hl"]
	var s: float = hl / 0.20
	match String(b["ear"]):
		"drop":
			return {"pts": [[0.0, 0.0, 0.0, 0.022, 0.007], [0.016, 0.008, -0.002, 0.030, 0.007], [0.030, -0.03, -0.008, 0.034, 0.006],
				[0.032, -0.075, -0.014, 0.033, 0.006], [0.027, -0.11, -0.014, 0.027, 0.005], [0.020, -0.132, -0.008, 0.012, 0.004]],
				"side": Vector3(0.0, 0.0, 1.0), "scale": s * 0.86, "x": 0.80}
		"short":
			# small, set high, the tip tipping out sideways (no horn)
			return {"pts": [[0.0, 0.0, 0.0, 0.027, 0.008], [0.016, 0.018, 0.004, 0.024, 0.007], [0.030, 0.028, 0.006, 0.017, 0.006],
				[0.042, 0.026, 0.004, 0.009, 0.005]],
				"side": Vector3(1.0, 0.0, 0.6), "scale": s * 0.82, "x": 0.62}
	# semi-erect: upright base, the top third folds forward and down
	return {"pts": [[0.0, 0.0, 0.0, 0.032, 0.009], [0.014, 0.030, 0.004, 0.030, 0.008], [0.027, 0.054, 0.0, 0.022, 0.005],
		[0.034, 0.066, -0.015, 0.014, 0.004], [0.036, 0.060, -0.033, 0.005, 0.003]],
		"side": Vector3(1.0, 0.0, 0.9), "scale": s, "x": 0.58}


## Ear root on the skull side (Ears space): x (outward) and y.
static func _ear_base(breed: StringName) -> Vector2:
	var hl: float = spec(breed)["hl"]
	var ex: float = float(_head_sec(breed, EAR_U)[3]) * float(_ear_spec(breed)["x"])
	return Vector2(ex, head_y_at(breed, EAR_U, ex) - (_head_top(breed, EAR_U) - 0.01 * hl) - 0.004)


static func _ears(k: BMesh, breed: StringName, res: Dictionary) -> void:
	var b: Dictionary = spec(breed)
	var lay: Dictionary = layout(breed)
	var es: Dictionary = _ear_spec(breed)
	var sc: float = es["scale"]
	var ears_xf: Transform3D = lay["ears"]
	var np: Vector3 = lay["np"]
	var eb: Vector2 = _ear_base(breed)
	var ex: float = eb.x
	var base_y: float = eb.y
	var src: Array = es["pts"]
	@warning_ignore("integer_division")
	var pick: Array = range(src.size()) if int(res["ear_steps"]) > 0 else [0, src.size() / 2, src.size() - 1]
	var inner_c: Color = Color(0.80, 0.60, 0.55) if breed != &"foxhound" else Color(0.55, 0.36, 0.28)
	for sx: float in [-1.0, 1.0]:
		var path: PackedVector3Array = PackedVector3Array()
		var rx: PackedFloat32Array = PackedFloat32Array()
		var ry: PackedFloat32Array = PackedFloat32Array()
		for i: int in pick:
			var q: Array = src[i]
			path.push_back(Vector3(sx * (ex + float(q[0]) * sc), base_y + float(q[1]) * sc, float(q[2]) * sc))
			rx.push_back(float(q[3]) * sc)
			ry.push_back(float(q[4]) * sc)
		var sd: Vector3 = es["side"]
		var side: Vector3 = Vector3(sd.x, sd.y, sd.z * sx).normalized()
		var face: Vector3 = side.cross(Vector3.UP).normalized() * (-1.0 if sd.x > 0.5 else sx)
		var paint: Callable = func(p: Vector3, n: Vector3, _a: float, t: float) -> Color:
			var c: Color = coat(breed, Z_EAR, np + ears_xf * p, ears_xf.basis * n, Vector3(t, t, 0.0))
			var inner: float = smoothstep(0.2, 0.7, n.dot(face)) * (1.0 - smoothstep(0.7, 1.0, t)) * (0.7 if b["ear"] != "drop" else 0.35)
			c = _mix(c, inner_c, inner)
			return Color(c.r, c.g, c.b, lerpf(0.65, 1.0, t) * (1.0 - inner * 0.25))
		k.grid(BMesh.tube_rings(path, rx, ry, side, res["ear_m"]), paint, FEAT_FUR + 0.05, false, true, Vector3.ZERO,
			(path[path.size() - 1] - path[path.size() - 2]).normalized() * 0.002, true)


static func _tail_pts(breed: StringName) -> Array:
	var b: Dictionary = spec(breed)
	var s: float = float(b["h"]) / 0.52
	var pts: Array
	match String(b["tail"]):
		"sickle":
			pts = [[0.0, -0.012, -0.02, 0.019], [0.0, 0.0, 0.0, 0.021], [0.0, 0.05, 0.045, 0.020], [0.0, 0.12, 0.075, 0.018],
				[0.0, 0.20, 0.085, 0.016], [0.0, 0.27, 0.072, 0.014], [0.0, 0.315, 0.045, 0.011], [0.0, 0.335, 0.015, 0.005]]
		"low":
			pts = [[0.0, 0.012, -0.02, 0.026], [0.0, 0.0, 0.0, 0.028], [0.0, -0.03, 0.045, 0.026], [0.0, -0.095, 0.08, 0.022],
				[0.0, -0.17, 0.095, 0.018], [0.0, -0.245, 0.09, 0.014], [0.0, -0.30, 0.075, 0.011], [0.0, -0.325, 0.065, 0.005]]
		_:
			pts = [[0.0, -0.012, -0.02, 0.020], [0.0, 0.0, 0.0, 0.022], [0.0, 0.04, 0.035, 0.021], [0.0, 0.10, 0.058, 0.019],
				[0.0, 0.165, 0.058, 0.017], [0.0, 0.21, 0.032, 0.014], [0.0, 0.232, -0.004, 0.011], [0.0, 0.236, -0.032, 0.005]]
	var tl: float = b.get("tail_len", 1.0)
	var tr: float = b.get("tail_r", 1.0)
	var out: Array = []
	for q: Array in pts:
		out.append([Vector3(q[0], q[1], q[2]) * s * tl, float(q[3]) * s * tr])
	return out


static func _tail(k: BMesh, breed: StringName, res: Dictionary) -> void:
	var src: Array = _tail_pts(breed)
	var pick: Array = range(src.size()) if int(res["tail_steps"]) > 0 else [0, 2, 4, 6, 7]
	var path: PackedVector3Array = PackedVector3Array()
	var rr: PackedFloat32Array = PackedFloat32Array()
	for i: int in pick:
		path.push_back((src[i] as Array)[0])
		rr.push_back((src[i] as Array)[1])
	var lay: Dictionary = layout(breed)
	var root: Vector3 = lay["tail"]
	var brush: float = 0.35 if breed == &"foxhound" else 0.15
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, t: float) -> Color:
		var c: Color = coat(breed, Z_TAIL, p + root, n, Vector3(t, 0.0, 0.0))
		var v: float = 0.95 + 0.10 * _hash(p)
		return Color(c.r * v, c.g * v, c.b * v, lerpf(0.6, 1.0, smoothstep(0.0, 0.25, t)))
	k.grid(BMesh.tube_rings(path, rr, rr, Vector3.RIGHT, res["tail_m"]), paint, FEAT_FUR + brush, false, true)


## One leg, `sx` = -1 left / +1 right (the control points' x runs outward).
static func _leg(k: BMesh, breed: StringName, res: Dictionary, front: bool, sx: float) -> void:
	var b: Dictionary = spec(breed)
	var lay: Dictionary = layout(breed)
	var hip: Vector3 = (lay["hips"] as Array)[(0 if front else 2) + (0 if sx < 0.0 else 1)]
	var ks: float = float((lay["leg_k"] as Array)[0 if front else 1])
	var kr: float = float(b["bone"]) * sqrt(float(b["h"]) / 0.52)
	var ctrl: Array = LEG_FRONT if front else LEG_HIND
	var pick: Array = LEG_MID_FRONT if front else LEG_MID_HIND
	var m: int = res["leg_m"]
	var path: PackedVector3Array = PackedVector3Array()
	var rx: PackedFloat32Array = PackedFloat32Array()
	var rz: PackedFloat32Array = PackedFloat32Array()
	var idx: Array = range(ctrl.size()) if int(res["leg_steps"]) > 0 else pick
	var muscle: float = b.get("muscle", 1.0)
	var hock: float = b.get("hock", 1.0)
	var stifle_z: float = float((LEG_HIND[4] as Array)[2])
	for i: int in idx:
		var q: Array = ctrl[i]
		var z: float = q[2]
		if not front and i >= 5:
			# less hind angulation: gaskin, hock and metatarsus closer to the line under the stifle
			z = stifle_z + (z - stifle_z) * hock
		var mk: float = muscle if i >= 1 and i <= 3 else 1.0
		path.push_back(Vector3(sx * float(q[0]) * ks, float(q[1]) * ks, z * ks))
		rx.push_back(float(q[3]) * kr * mk)
		rz.push_back(float(q[4]) * kr * mk)
	var ao_top: float = b.get("leg_ao_top", 0.55)
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var rp: Vector3 = p + hip
		var c: Color = coat(breed, Z_LEG, rp, n)
		var v: float = 0.95 + 0.10 * _hash(p)
		var ao: float = lerpf(ao_top, 1.0, smoothstep(hip.y + 0.06, hip.y - 0.06, rp.y)) * lerpf(0.82, 1.0, smoothstep(-0.6, 0.3, n.y))
		return Color(c.r * v, c.g * v, c.b * v, ao)
	k.grid(BMesh.tube_rings(path, rx, rz, Vector3.RIGHT, m), paint, FEAT_FUR + 0.1, true, false)
	# paw: same coat as the leg, sole on the ground, built from the toes back (the shader shades soft toe grooves)
	var last: Vector3 = path[path.size() - 1]
	var ground: float = -hip.y + 0.001
	var ps: float = kr
	var pz0: float = last.z - (0.012 if front else -0.008) * ks
	var prs: Array = PAW if int(res["paw_r"]) >= 4 else PAW_MID.map(func(i: int) -> Array: return PAW[i])
	var rings: Array = []
	for q: Array in prs:
		var top: float = ground + float(q[1]) * ps
		rings.append(BMesh.super_ring(pz0 + float(q[0]) * ps, top, ground, float(q[2]) * ps, ground + 0.010 * ps, 2.2, 5.0, res["paw_m"]))
	var pad: Color = Color(0.32, 0.22, 0.21) if breed == &"dogo" else Color(0.09, 0.07, 0.06)
	var paw_paint: Callable = func(p: Vector3, n: Vector3, _a: float, t: float) -> Color:
		var c: Color = coat(breed, Z_LEG, p + hip, n)
		# claw tips: a slight darkening low on the toe front; pads only on the sole itself
		var tip: float = (1.0 - smoothstep(0.0, 0.15, t)) * (1.0 - smoothstep(-0.2, 0.4, n.y))
		c = _mix(c, Color(c.r * 0.6, c.g * 0.58, c.b * 0.55), tip * 0.6)
		c = _mix(c, pad, 1.0 - smoothstep(-0.95, -0.82, n.y))
		return Color(c.r, c.g, c.b, lerpf(0.7, 1.0, smoothstep(-0.7, 0.4, n.y)))
	k.grid(rings, paw_paint, FEAT_PAW, true, true, Vector3(0.0, -0.002, -0.004) * ps, Vector3(0.0, 0.0, 0.003) * ps, false, true)


## Far LOD: trunk, neck + head, ears, tail and four straight legs in the rest pose, one mesh.
static func _far(k: BMesh, breed: StringName, res: Dictionary) -> void:
	var b: Dictionary = spec(breed)
	var lay: Dictionary = layout(breed)
	var m: int = res["trunk_m"]
	var nr: int = res["trunk_r"]
	var rings: Array = []
	for r in nr:
		var u: float = float(r) / float(nr - 1)
		rings.append(trunk_ring(breed, lerpf(0.02, 0.98, u), m))
	var body_paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = coat(breed, Z_BODY, p, n)
		return Color(c.r, c.g, c.b, _ao_side(n))
	k.grid(rings, body_paint, FEAT_FUR, true, true)
	# neck + head: one tube from the chest to the nose
	var np: Vector3 = lay["np"]
	var skull: Transform3D = lay["skull"]
	var hl: float = b["hl"]
	var kk: float = float(b["h"]) / 0.52 * float(b["neck"])
	var s1: Array = _head_sec(breed, 0.3)
	var s2: Array = _head_sec(breed, 0.75)
	var path: PackedVector3Array = PackedVector3Array([np + Vector3(0.0, -0.02, 0.03) * kk, np + skull * Vector3(0.0, -0.05 * hl, 0.0),
		np + skull * Vector3(0.0, (float(s1[1]) + float(s1[2])) * 0.5, -0.3 * hl),
		np + skull * Vector3(0.0, (float(s2[1]) + float(s2[2])) * 0.5, -0.75 * hl), np + skull * Vector3(0.0, -0.005, -1.0 * hl)])
	var hrx: PackedFloat32Array = PackedFloat32Array([0.064 * kk, 0.045 * kk, s1[3], s2[3], float(s2[3]) * 0.7])
	var hry: PackedFloat32Array = PackedFloat32Array([0.085 * kk, 0.05 * kk, (float(s1[1]) - float(s1[2])) * 0.5,
		(float(s2[1]) - float(s2[2])) * 0.5, (float(s2[1]) - float(s2[2])) * 0.35])
	var nose_c: Color = _nose_color(breed)
	var head_paint: Callable = func(p: Vector3, n: Vector3, _a: float, t: float) -> Color:
		var c: Color = coat(breed, Z_HEAD if t > 0.3 else Z_NECK, p, n, skull.affine_inverse() * (p - np))
		c = _mix(c, nose_c, smoothstep(0.93, 1.0, t))
		return Color(c.r, c.g, c.b, lerpf(0.6, 1.0, smoothstep(-0.9, 0.2, n.y)))
	k.grid(BMesh.tube_rings(path, hrx, hry, Vector3.RIGHT, res["head_m"]), head_paint, FEAT_FUR, false, true)
	# ears: first and last point of the near shape
	var es: Dictionary = _ear_spec(breed)
	var sc: float = es["scale"]
	var src: Array = es["pts"]
	var ears_xf: Transform3D = lay["ears"]
	var eb: Vector2 = _ear_base(breed)
	var ear_c: Color = coat(breed, Z_EAR, Vector3.ZERO, Vector3.UP, Vector3(0.5, 0.5, 0.0))
	var ear_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, _t: float) -> Color:
		return Color(ear_c.r, ear_c.g, ear_c.b, 0.85)
	@warning_ignore("integer_division")
	var mid_i: int = src.size() / 2
	for sx: float in [-1.0, 1.0]:
		var ep: PackedVector3Array = PackedVector3Array()
		var erx: PackedFloat32Array = PackedFloat32Array()
		for i: int in [0, mid_i, src.size() - 1]:
			var q: Array = src[i]
			ep.push_back(np + ears_xf * Vector3(sx * (eb.x + float(q[0]) * sc), eb.y + float(q[1]) * sc, float(q[2]) * sc))
			erx.push_back(maxf(float(q[3]) * sc, 0.006))
		var sd: Vector3 = es["side"]
		k.grid(BMesh.tube_rings(ep, erx, PackedFloat32Array([0.006, 0.006, 0.005]), skull.basis * Vector3(sd.x, sd.y, sd.z * sx).normalized(), res["ear_m"]),
			ear_paint, FEAT_FUR, false, true)
	# tail
	var tp: Array = _tail_pts(breed)
	var root: Vector3 = lay["tail"]
	var tpath: PackedVector3Array = PackedVector3Array()
	var trr: PackedFloat32Array = PackedFloat32Array()
	for i: int in [0, 3, 7]:
		tpath.push_back(root + ((tp[i] as Array)[0] as Vector3))
		trr.push_back(maxf(float((tp[i] as Array)[1]), 0.007))
	var tail_paint: Callable = func(p: Vector3, n: Vector3, _a: float, t: float) -> Color:
		var c: Color = coat(breed, Z_TAIL, p, n, Vector3(t, 0.0, 0.0))
		return Color(c.r, c.g, c.b, 0.9)
	k.grid(BMesh.tube_rings(tpath, trr, trr, Vector3.RIGHT, res["tail_m"]), tail_paint, FEAT_FUR, false, true)
	# legs: straight posts, thick at the top
	var kr: float = float(b["bone"]) * sqrt(float(b["h"]) / 0.52)
	var hips: Array = lay["hips"]
	for i in 4:
		var hip: Vector3 = hips[i]
		var front: bool = i < 2
		var mid_y: float = -0.16 * float((lay["leg_k"] as Array)[0 if front else 1])
		var lp: PackedVector3Array = PackedVector3Array([hip + Vector3(0.0, 0.02, 0.0), hip + Vector3(0.0, mid_y, -0.03 if not front else 0.03),
			Vector3(hip.x, 0.0, hip.z + (-0.01 if front else 0.025))])
		var lrx: PackedFloat32Array = PackedFloat32Array([0.045 * kr, 0.03 * kr, 0.022 * kr])
		var lrz: PackedFloat32Array = PackedFloat32Array([0.065 * kr if front else 0.085 * kr, 0.04 * kr, 0.03 * kr])
		var leg_paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
			var c: Color = coat(breed, Z_LEG, p, n)
			return Color(c.r, c.g, c.b, lerpf(0.6, 1.0, smoothstep(0.0, 0.25, p.y)))
		k.grid(BMesh.tube_rings(lp, lrx, lrz, Vector3.RIGHT, res["leg_m"]), leg_paint, FEAT_FUR, false, true)
