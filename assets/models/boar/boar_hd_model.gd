extends RefCounted
## HD boar meshes and materials (static, cached per type and LOD; shared by every instance).
## Rest pose, root space at scale 1 = 100 kg: origin on the ground, forward -Z. Parts:
##   body  trunk + dorsal mane (rig space)          head  head, snout disc, ears, eyes, tusks (Head space)
##   leg_f / leg_h  one leg hanging from its pivot  tail  hanging from TAIL_ROOT
##   far   everything in one mesh (rest pose), for > 60 m
## The trunk and head stay inside BoarVisualBase.HIT_ZONES (+-5 cm); only mane, ears and tusks reach out.

const BMesh := preload("res://assets/models/boar/boar_hd_mesh.gd")
const HdMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const FUR_SHADER: Shader = preload("res://assets/models/boar/boar_fur.gdshader")

const LOD_NEAR: int = 0
const LOD_MID: int = 1
const LOD_FAR: int = 2

const HEAD_REST: Vector3 = Vector3(0.0, 0.55, -0.62)
## The head (and its neck, buried in the trunk) turns about this point.
const NECK_PIVOT: Vector3 = Vector3(0.0, 0.56, -0.36)
const LEG_HIPS: Array[Vector3] = [
	Vector3(-0.125, 0.50, -0.30),  # front left
	Vector3(0.125, 0.50, -0.30),   # front right
	Vector3(-0.11, 0.54, 0.43),    # rear left
	Vector3(0.11, 0.54, 0.43),     # rear right
]
const TAIL_ROOT: Vector3 = Vector3(0.0, 0.565, 0.685)

## Ring resolution per LOD.
const RES: Array[Dictionary] = [
	{"trunk_m": 20, "trunk_r": 26, "mane_n": 20, "mane_m": 8, "head_m": 18, "head_r": 16, "disc_r": 2, "ear_m": 6, "ear_r": 4,
		"eye_m": 8, "tusk_m": 5, "tusk_steps": 1, "leg_m": 8, "leg_steps": 1, "hoof_r": 3, "tail_m": 6, "tail_steps": 1},
	{"trunk_m": 12, "trunk_r": 12, "mane_n": 8, "mane_m": 6, "head_m": 10, "head_r": 8, "disc_r": 1, "ear_m": 4, "ear_r": 3,
		"eye_m": 0, "tusk_m": 3, "tusk_steps": 0, "leg_m": 5, "leg_steps": 0, "hoof_r": 2, "tail_m": 3, "tail_steps": 0},
	{"trunk_m": 8, "trunk_r": 7, "head_m": 6, "head_r": 5, "leg_m": 4, "ear_m": 3},
]

# --- shape tables (root space; head tables in Head space, s = local z) -------------------------------------
# Profile: deep low chest, belly rising to the groin, back falling from the withers to a lower, narrower rump.
# The trunk tops out at 0.745 (vital hit box); the hump above the withers is the dorsal bristle crest (mane).
const TRUNK_Z0: float = -0.50
const TRUNK_Z1: float = 0.712
const TRUNK_TOP: Array = [[-0.50, 0.66], [-0.42, 0.70], [-0.34, 0.735], [-0.25, 0.745], [-0.12, 0.742], [0.05, 0.728],
	[0.20, 0.71], [0.35, 0.69], [0.45, 0.672], [0.55, 0.648], [0.62, 0.618], [0.67, 0.585], [0.70, 0.55], [0.712, 0.52]]
const TRUNK_BOT: Array = [[-0.50, 0.42], [-0.42, 0.34], [-0.34, 0.29], [-0.25, 0.268], [-0.12, 0.27], [0.05, 0.29],
	[0.20, 0.325], [0.35, 0.365], [0.45, 0.395], [0.55, 0.42], [0.62, 0.44], [0.67, 0.46], [0.70, 0.48], [0.712, 0.50]]
const TRUNK_HW: Array = [[-0.50, 0.12], [-0.42, 0.18], [-0.34, 0.22], [-0.25, 0.235], [-0.12, 0.235], [0.05, 0.226],
	[0.20, 0.212], [0.35, 0.195], [0.45, 0.185], [0.55, 0.17], [0.62, 0.15], [0.67, 0.12], [0.70, 0.085], [0.712, 0.045]]
## share of the height, from the top, where the trunk is widest
const TRUNK_WIDEST: Array = [[-0.50, 0.5], [-0.32, 0.58], [0.10, 0.55], [0.50, 0.45], [0.712, 0.45]]
## superellipse exponents of the upper and lower half along the trunk (lower = narrower back ridge)
const TRUNK_ET: Array = [[-0.50, 2.0], [-0.25, 1.85], [0.20, 2.0], [0.55, 2.3], [0.712, 2.2]]
const TRUNK_EB: Array = [[-0.50, 2.2], [0.0, 2.4], [0.712, 2.3]]
## Dorsal crest: share of the type's mane height along z (rises behind the poll, peaks over the withers,
## gone by mid back); a slow wobble keeps the edge irregular without spikes.
const MANE_PROFILE: Array = [[-0.47, 0.0], [-0.40, 0.55], [-0.30, 0.95], [-0.20, 1.0], [-0.08, 0.8], [0.05, 0.5],
	[0.16, 0.2], [0.26, 0.0]]
## Alpha crest: starts at the nape, long and low with a rounded peak, gone near z = +0.35.
const MANE_PROFILE_LONG: Array = [[-0.47, 0.0], [-0.42, 0.45], [-0.34, 0.85], [-0.22, 1.0], [-0.08, 0.92], [0.08, 0.66],
	[0.22, 0.34], [0.35, 0.0]]

# Head: a long wedge seen from the side, straight brow running into the snout, deep jowls.
const HEAD_S0: float = 0.33     # back, buried in the neck
const HEAD_S1: float = -0.182   # snout disc rim
const HEAD_TOP: Array = [[-0.182, 0.006], [-0.165, 0.014], [-0.13, 0.030], [-0.08, 0.053], [-0.02, 0.081],
	[0.04, 0.108], [0.10, 0.135], [0.16, 0.160], [0.22, 0.176], [0.28, 0.165], [0.33, 0.145]]
const HEAD_BOT: Array = [[-0.182, -0.094], [-0.165, -0.098], [-0.13, -0.106], [-0.08, -0.120], [-0.02, -0.140],
	[0.04, -0.163], [0.10, -0.185], [0.16, -0.203], [0.22, -0.212], [0.28, -0.20], [0.33, -0.175]]
const HEAD_HW: Array = [[-0.182, 0.050], [-0.165, 0.056], [-0.13, 0.064], [-0.08, 0.080], [-0.02, 0.10],
	[0.04, 0.122], [0.10, 0.142], [0.16, 0.158], [0.22, 0.167], [0.28, 0.162], [0.33, 0.145]]
const HEAD_WIDEST: Array = [[-0.182, 0.5], [-0.05, 0.56], [0.10, 0.58], [0.33, 0.55]]
const EYE_S: float = 0.06
const EYE_Y: float = 0.074
const EYE_R: float = 0.016
## Wet, almost black eye globe (the shader adds the sky catchlight).
const EYE_DARK: Color = Color(0.03, 0.02, 0.015)
## Eye rings (near LOD), in EYE_R units: [height along the eye axis, horizontal radius, vertical radius].
## Lid: outer ring laid on the head surface, raised rim (lighter skin), dark inner margin; globe: tucked under the margin, domed out of it.
const EYE_LID: Array = [[0.0, 1.85, 1.5], [0.4, 1.32, 1.02], [0.46, 1.04, 0.74]]
const EYE_GLOBE: Array = [[0.3, 1.0, 0.7], [0.62, 0.82, 0.57], [0.84, 0.46, 0.32]]
const EYE_POLE: float = 0.92
const EAR_S: float = 0.165
const EAR_X: float = 0.062

## Leg control points in pivot space: [x, y, z, rx (side), rz (front-back)]. Thick forearm / ham coming out of the
## trunk, thin short cannon down to the hoof.
const LEG_FRONT: Array = [[0.0, 0.07, 0.0, 0.08, 0.11], [0.0, -0.10, 0.02, 0.075, 0.10], [0.0, -0.20, 0.02, 0.062, 0.078],
	[0.0, -0.28, 0.008, 0.045, 0.054], [0.0, -0.335, -0.002, 0.030, 0.034], [0.0, -0.42, 0.0, 0.022, 0.026],
	[0.0, -0.468, -0.022, 0.025, 0.027]]
const LEG_HIND: Array = [[0.0, 0.06, 0.0, 0.075, 0.10], [0.0, -0.10, 0.02, 0.078, 0.125], [0.0, -0.19, 0.0, 0.068, 0.10],
	[0.0, -0.255, 0.03, 0.048, 0.064], [0.0, -0.31, 0.058, 0.030, 0.042], [0.0, -0.43, 0.034, 0.022, 0.026],
	[0.0, -0.485, 0.016, 0.025, 0.028], [0.0, -0.508, -0.004, 0.025, 0.027]]
## Hoof rings (relative to the last leg point): [dy, dz, rx, rz]; the sole sits on the ground.
const HOOF: Array = [[0.004, 0.002, 0.029, 0.033], [-0.016, -0.012, 0.031, 0.040], [-0.032, -0.024, 0.030, 0.042]]
## The tilted sole ring dips below its centre: lift the centre so the toe tips touch the ground.
const HOOF_LIFT: float = 0.016
const TAIL: Array = [[0.0, 0.0, -0.012, 0.017], [0.0, -0.025, 0.03, 0.015], [0.0, -0.075, 0.055, 0.012],
	[0.0, -0.135, 0.064, 0.010], [0.0, -0.19, 0.062, 0.010], [0.0, -0.228, 0.058, 0.017], [0.0, -0.272, 0.052, 0.006]]

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _highlight: StandardMaterial3D = null
static var _curves: Dictionary = {}
static var _tris: Dictionary = {}
# per-type shape modifiers, set by build_part (piglet: shorter snout, rounder trunk)
static var _snout: float = 1.0
static var _round: float = 1.0


# --- palette / type ----------------------------------------------------------------------------------------

## Albedo colours per type (used as stored, see boar_fur.gdshader). tip = grizzled bristle tips (shader), stripe = piglet stripes (shader).
static func palette(type_id: StringName) -> Dictionary:
	match type_id:
		Ids.PIGLET:
			return {"back": Color(0.50, 0.34, 0.20), "belly": Color(0.70, 0.56, 0.40), "dorsal": Color(0.30, 0.20, 0.12),
				"leg": Color(0.30, 0.21, 0.14), "muzzle": Color(0.32, 0.23, 0.17), "cheek": Color(0.66, 0.54, 0.40),
				"disc": Color(0.50, 0.36, 0.32), "lid": Color(0.30, 0.19, 0.13), "tip": Color(0.85, 0.72, 0.52), "tip_amount": 0.35,
				"stripe": Color(0.85, 0.72, 0.52), "stripe_amount": 0.45, "mane": 0.045, "tusk": 0.0, "tusk_w": 0.0,
				"snout": 0.72, "round": 1.12}
		Ids.SOW:
			return {"back": Color(0.34, 0.29, 0.24), "belly": Color(0.44, 0.38, 0.31), "dorsal": Color(0.22, 0.18, 0.15),
				"leg": Color(0.15, 0.12, 0.10), "muzzle": Color(0.20, 0.16, 0.14), "cheek": Color(0.55, 0.50, 0.43),
				"disc": Color(0.40, 0.30, 0.28), "lid": Color(0.42, 0.33, 0.28), "tip": Color(0.66, 0.60, 0.52), "tip_amount": 0.45,
				"stripe": Color.BLACK, "stripe_amount": 0.0, "mane": 0.075, "tusk": 0.45, "tusk_w": 0.75}
		Ids.ALPHA:
			return {"back": Color(0.075, 0.065, 0.058), "belly": Color(0.12, 0.10, 0.09), "dorsal": Color(0.04, 0.035, 0.032),
				"leg": Color(0.04, 0.035, 0.032), "muzzle": Color(0.06, 0.05, 0.045), "cheek": Color(0.30, 0.27, 0.24),
				"disc": Color(0.22, 0.17, 0.16), "lid": Color(0.30, 0.24, 0.21), "tip": Color(0.45, 0.41, 0.37), "tip_amount": 0.5,
				"stripe": Color.BLACK, "stripe_amount": 0.0, "mane": 0.11, "mane_long": true, "tusk": 1.35, "tusk_w": 1.3}
		Ids.BOSS:
			# older, darker and greyer than the alpha: frosted bristles, huge tusks, long mane
			return {"back": Color(0.055, 0.050, 0.047), "belly": Color(0.10, 0.09, 0.082), "dorsal": Color(0.03, 0.028, 0.026),
				"leg": Color(0.03, 0.028, 0.026), "muzzle": Color(0.05, 0.043, 0.04), "cheek": Color(0.38, 0.36, 0.33),
				"disc": Color(0.20, 0.15, 0.14), "lid": Color(0.26, 0.20, 0.18), "tip": Color(0.62, 0.60, 0.56), "tip_amount": 0.62,
				"stripe": Color.BLACK, "stripe_amount": 0.0, "mane": 0.13, "mane_long": true, "tusk": 1.8, "tusk_w": 1.6}
		_:
			return {"back": Color(0.20, 0.15, 0.115), "belly": Color(0.28, 0.22, 0.17), "dorsal": Color(0.10, 0.08, 0.065),
				"leg": Color(0.08, 0.065, 0.055), "muzzle": Color(0.12, 0.095, 0.08), "cheek": Color(0.42, 0.37, 0.31),
				"disc": Color(0.30, 0.22, 0.21), "lid": Color(0.36, 0.27, 0.21), "tip": Color(0.55, 0.48, 0.40), "tip_amount": 0.5,
				"stripe": Color.BLACK, "stripe_amount": 0.0, "mane": 0.125, "tusk": 0.95, "tusk_w": 1.0}


## Tusk size bucket 0..2 from the weight (heavier animals of a type carry longer tusks).
static func tusk_bucket(type_id: StringName, kg: float) -> int:
	match type_id:
		Ids.SOW:
			return clampi(int(round(inverse_lerp(60.0, 110.0, kg) * 2.0)), 0, 2)
		Ids.BOAR:
			return clampi(int(round(inverse_lerp(90.0, 160.0, kg) * 2.0)), 0, 2)
		Ids.ALPHA:
			return clampi(int(round(inverse_lerp(180.0, 260.0, kg) * 2.0)), 0, 2)
		Ids.BOSS:
			return clampi(int(round(inverse_lerp(520.0, 640.0, kg) * 2.0)), 0, 2)
	return 0


static func is_cached(type_id: StringName, bucket: int) -> bool:
	return _meshes.has(_key(type_id, LOD_FAR, "far", 0)) and _meshes.has(_key(type_id, LOD_NEAR, "head", bucket))


static func _key(type_id: StringName, lod: int, part: String, bucket: int) -> String:
	return "%s|%d|%s|%d" % [type_id, lod, part, bucket]


## Every mesh of one type: { "body": [near, mid], "head": [near, mid], "leg_f": [..], "leg_h": [..], "tail": [..], "far": mesh }.
static func get_set(type_id: StringName, bucket: int) -> Dictionary:
	var out: Dictionary = {}
	for part: String in ["body", "head", "leg_f", "leg_h", "tail"]:
		out[part] = [get_mesh(type_id, LOD_NEAR, part, bucket), get_mesh(type_id, LOD_MID, part, bucket)]
	out["far"] = get_mesh(type_id, LOD_FAR, "far", bucket)
	return out


static func get_mesh(type_id: StringName, lod: int, part: String, bucket: int) -> ArrayMesh:
	var b: int = bucket if part == "head" or part == "far" else 0
	var key: String = _key(type_id, lod, part, b)
	if _meshes.has(key):
		return _meshes[key]
	var mesh: ArrayMesh = ArrayMesh.new()
	var k: BMesh = build_part(type_id, lod, part, b)
	k.commit(mesh, get_material(type_id))
	_meshes[key] = mesh
	_tris[key] = k.triangle_count()
	return mesh


static func triangles(type_id: StringName, lod: int, part: String, bucket: int) -> int:
	var b: int = bucket if part == "head" or part == "far" else 0
	get_mesh(type_id, lod, part, b)
	return int(_tris[_key(type_id, lod, part, b)])


static func get_material(type_id: StringName) -> ShaderMaterial:
	if _materials.has(type_id):
		return _materials[type_id]
	var pal: Dictionary = palette(type_id)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = FUR_SHADER
	m.set_shader_parameter(&"noise_tex", noise_texture())
	m.set_shader_parameter(&"tip_color", pal["tip"])
	m.set_shader_parameter(&"tip_amount", pal["tip_amount"])
	m.set_shader_parameter(&"stripe_color", pal["stripe"])
	m.set_shader_parameter(&"stripe_amount", pal["stripe_amount"])
	_materials[type_id] = m
	return m


static func get_highlight_material() -> StandardMaterial3D:
	if _highlight == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.72, 0.38)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.15)
		m.emission_energy_multiplier = 1.6
		_highlight = m
	return _highlight


## The 512x512 RG noise shared with the HD guns (built once per session, already warm in the hunt).
static func noise_texture() -> Texture2D:
	var wood: ShaderMaterial = RifleHD.get_materials()[RifleHD.SURF_WOOD]
	return wood.get_shader_parameter(&"noise_tex")


# --- curves ------------------------------------------------------------------------------------------------

static func _c(id: String) -> PackedVector2Array:
	if _curves.is_empty():
		_curves = {"tt": HdMesh.curve(TRUNK_TOP), "tb": HdMesh.curve(TRUNK_BOT), "tw": HdMesh.curve(TRUNK_HW),
			"tm": HdMesh.curve(TRUNK_WIDEST), "te": HdMesh.curve(TRUNK_ET), "tf": HdMesh.curve(TRUNK_EB), "ht": HdMesh.curve(HEAD_TOP), "hb": HdMesh.curve(HEAD_BOT),
			"hw": HdMesh.curve(HEAD_HW), "hm": HdMesh.curve(HEAD_WIDEST), "mp": HdMesh.curve(MANE_PROFILE), "mpl": HdMesh.curve(MANE_PROFILE_LONG)}
	return _curves[id]


static func trunk_top(z: float) -> float:
	return HdMesh.pchip(_c("tt"), z)


## Trunk section at z: [top, bot, hw, ym, et, eb], with the type's roundness applied.
static func _trunk_sec(z: float) -> Array:
	var r: float = _round - 1.0
	var top: float = HdMesh.pchip(_c("tt"), z)
	var bot: float = HdMesh.pchip(_c("tb"), z) - 0.25 * r
	var hw: float = HdMesh.pchip(_c("tw"), z) * _round
	var ym: float = lerpf(top, bot, HdMesh.pchip(_c("tm"), z))
	return [top, bot, hw, ym, HdMesh.pchip(_c("te"), z) + 2.0 * r, HdMesh.pchip(_c("tf"), z) + 2.0 * r]


## `extra_top` raises the top of the section (alpha shoulder hump, the crest folded into the far LOD).
static func trunk_ring(z: float, m: int, extra_top: float) -> PackedVector3Array:
	var sec: Array = _trunk_sec(z)
	var top: float = float(sec[0]) + extra_top
	var bot: float = sec[1]
	var ym: float = sec[3]
	var ring: PackedVector3Array = BMesh.super_ring(z, top, bot, sec[2], ym, sec[4], sec[5], m)
	# shoulder blades and the heavier forehand: a little more width at mid height
	var sh: float = 0.012 * _bump(z, -0.40, -0.26, -0.12)
	if sh > 0.0:
		for i in m:
			var p: Vector3 = ring[i]
			var hy: float = 1.0 - absf(p.y - (ym + 0.06)) / maxf(top - bot, 0.01) * 2.0
			p.x += signf(p.x) * sh * clampf(hy, 0.0, 1.0)
			ring[i] = p
	return ring


## Height of the trunk's upper surface at (z, x).
static func trunk_y_at(z: float, x: float) -> float:
	var sec: Array = _trunk_sec(z)
	var e: float = sec[4]
	var q: float = clampf(absf(x) / float(sec[2]), 0.0, 1.0)
	return float(sec[3]) + (float(sec[0]) - float(sec[3])) * pow(maxf(1.0 - pow(q, e * 0.5), 0.0), 2.0 / e)


## Dorsal crest height at z for a type crest height `hmax` (smooth, slightly irregular).
static func mane_h(z: float, hmax: float, long: bool = false) -> float:
	var wob: float = 1.0 + 0.10 * sin(z * 21.0 + 0.7) + 0.06 * sin(z * 47.0 + 2.1)
	return hmax * maxf(HdMesh.pchip(_c("mpl" if long else "mp"), z), 0.0) * wob


static func head_ring(s: float, m: int) -> PackedVector3Array:
	var top: float = HdMesh.pchip(_c("ht"), s)
	var bot: float = HdMesh.pchip(_c("hb"), s)
	var hw: float = HdMesh.pchip(_c("hw"), s)
	var ym: float = lerpf(top, bot, HdMesh.pchip(_c("hm"), s))
	return BMesh.super_ring(s * _snout if s < 0.0 else s, top, bot, hw, ym, 2.2, 2.6, m)


## Head surface half width at (s, y) on the upper half.
static func head_x_at(s: float, y: float) -> float:
	var top: float = HdMesh.pchip(_c("ht"), s)
	var bot: float = HdMesh.pchip(_c("hb"), s)
	var hw: float = HdMesh.pchip(_c("hw"), s)
	var ym: float = lerpf(top, bot, HdMesh.pchip(_c("hm"), s))
	var e: float = 2.2 if y >= ym else 2.6
	var h: float = (top - ym) if y >= ym else (ym - bot)
	var q: float = clampf(absf(y - ym) / maxf(h, 1e-4), 0.0, 1.0)
	# inverse of BMesh.super_ring: |x / hw|^e + |(y - ym) / h|^e = 1
	return hw * pow(maxf(1.0 - pow(q, e), 0.0), 1.0 / e)


## Head upper surface height at (s, x).
static func head_y_at(s: float, x: float) -> float:
	var top: float = HdMesh.pchip(_c("ht"), s)
	var bot: float = HdMesh.pchip(_c("hb"), s)
	var hw: float = HdMesh.pchip(_c("hw"), s)
	var ym: float = lerpf(top, bot, HdMesh.pchip(_c("hm"), s))
	var q: float = clampf(absf(x) / hw, 0.0, 1.0)
	return ym + (top - ym) * pow(maxf(1.0 - pow(q, 1.1), 0.0), 1.0 / 1.1)


static func _bump(x: float, a: float, peak: float, b: float) -> float:
	if x <= a or x >= b:
		return 0.0
	var t: float = (x - a) / (peak - a) if x < peak else (b - x) / (b - peak)
	return t * t * (3.0 - 2.0 * t)


static func _hash(p: Vector3) -> float:
	return fposmod(sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453, 1.0)


static func _sat(x: float) -> float:
	return clampf(x, 0.0, 1.0)


static func _mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, _sat(t))


# --- parts -------------------------------------------------------------------------------------------------

static func build_part(type_id: StringName, lod: int, part: String, bucket: int) -> BMesh:
	var pal: Dictionary = palette(type_id)
	var res: Dictionary = RES[lod]
	var k: BMesh = BMesh.new()
	_snout = float(pal.get("snout", 1.0))
	_round = float(pal.get("round", 1.0))
	match part:
		"body":
			_trunk(k, pal, res, type_id)
			if float(pal["mane"]) > 0.0:
				_mane(k, pal, res)
		"head":
			_head(k, pal, res, bucket)
		"leg_f":
			_leg(k, pal, res, LEG_FRONT, LEG_HIPS[0].y, [0, 1, 3, 5, 6])
		"leg_h":
			_leg(k, pal, res, LEG_HIND, LEG_HIPS[2].y, [0, 1, 4, 6, 7])
		"tail":
			_tail(k, pal, res)
		"far":
			_far(k, pal, res, type_id)
	return k


static func _trunk(k: BMesh, pal: Dictionary, res: Dictionary, type_id: StringName) -> void:
	var m: int = res["trunk_m"]
	var nr: int = res["trunk_r"]
	var hump: float = 0.03 if type_id == Ids.BOSS else (0.015 if type_id == Ids.ALPHA else 0.0)
	var rings: Array = []
	for r in nr:
		var u: float = float(r) / float(nr - 1)
		var e: float = lerpf(u, 0.5 - 0.5 * cos(PI * u), 0.55)
		var z: float = lerpf(TRUNK_Z0, TRUNK_Z1, e)
		rings.append(trunk_ring(z, m, hump * _bump(z, -0.42, -0.25, 0.0)))
	var back: Color = pal["back"]
	var belly: Color = pal["belly"]
	var dorsal: Color = pal["dorsal"]
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = _mix(belly, back, smoothstep(-0.65, 0.45, n.y))
		c = _mix(c, dorsal, smoothstep(0.72, 0.97, n.y) * 0.75)
		# darker forehand and lower flanks
		c = _mix(c, dorsal, smoothstep(-0.05, -0.45, p.z) * 0.22)
		var v: float = 0.92 + 0.16 * _hash(p)
		var ao: float = lerpf(0.42, 1.0, smoothstep(-0.95, 0.2, n.y))
		# where the legs leave the body
		var legs: float = maxf(_bump(p.z, -0.48, -0.30, -0.12), _bump(p.z, 0.28, 0.45, 0.66)) * (1.0 - smoothstep(0.30, 0.45, p.y))
		ao *= 1.0 - 0.3 * legs
		return Color(c.r * v, c.g * v, c.b * v, ao)
	k.grid(rings, paint, BMesh.FEAT_FUR + 0.25, true, true, Vector3(0, 0, -0.012), Vector3(0, 0, 0.01), false, true)


## Dorsal crest: a thick bristle volume grown out of the back (its rim sinks into the trunk surface), highest over
## the withers and gone by mid back. It makes the hump and the wedge the trunk cannot have inside the hit boxes.
static func _mane(k: BMesh, pal: Dictionary, res: Dictionary) -> void:
	var n: int = res["mane_n"]
	var m: int = res["mane_m"]
	var hmax: float = pal["mane"]
	var long: bool = pal.get("mane_long", false)
	var prof: Array = MANE_PROFILE_LONG if long else MANE_PROFILE
	var back: Color = pal["back"]
	var belly: Color = pal["belly"]
	var dark: Color = pal["dorsal"]
	var tip: Color = _mix(pal["dorsal"], pal["tip"], 0.3)
	var z0: float = float((prof[0] as Array)[0])
	var z1: float = float((prof[prof.size() - 1] as Array)[0])
	# (share of the half width, share of the height above the surface), one side, top excluded
	var side: Array = [[1.0, -0.12], [0.70, 0.42], [0.34, 0.86]] if m >= 8 else [[1.0, -0.12], [0.5, 0.66]]
	var rings: Array = []
	for i in n:
		var u: float = float(i) / float(n - 1)
		var z: float = lerpf(z0, z1, u)
		var h: float = mane_h(z, hmax, long) + 0.003
		var hw: float = float(_trunk_sec(z)[2])
		var w: float = minf(0.05 + 0.55 * h, hw * 0.75)
		var yt: float = trunk_top(z)
		var lean: float = h * 0.25
		var ring: PackedVector3Array = PackedVector3Array([Vector3(0.0, yt - 0.06, z)])
		for q: Array in side:
			var x: float = w * float(q[0])
			var sink: float = 0.012 if float(q[1]) < 0.0 else 0.0
			ring.push_back(Vector3(x, trunk_y_at(z, x) + h * float(q[1]) - sink, z + lean * maxf(float(q[1]), 0.0)))
		ring.push_back(Vector3(0.0, yt + h, z + lean))
		for j in range(side.size() - 1, -1, -1):
			var q2: Array = side[j]
			var x2: float = w * float(q2[0])
			var sink2: float = 0.012 if float(q2[1]) < 0.0 else 0.0
			ring.push_back(Vector3(-x2, trunk_y_at(z, x2) + h * float(q2[1]) - sink2, z + lean * maxf(float(q2[1]), 0.0)))
		rings.append(ring)
	var paint: Callable = func(p: Vector3, nrm: Vector3, _a: float, _t: float) -> Color:
		var hz: float = maxf(mane_h(p.z, hmax, long), 0.01)
		var rel: float = clampf((p.y - trunk_y_at(p.z, p.x)) / hz, 0.0, 1.0)
		var c: Color = _mix(_mix(belly, back, smoothstep(-0.65, 0.45, nrm.y)), dark, 0.25 + 0.75 * smoothstep(0.0, 0.85, rel))
		c = _mix(c, tip, smoothstep(0.6, 1.0, rel) * 0.45)
		var v: float = 0.92 + 0.16 * _hash(p)
		return Color(c.r * v, c.g * v, c.b * v, lerpf(0.82, 1.0, rel))
	k.grid(rings, paint, BMesh.FEAT_FUR + 0.45)


static func _head(k: BMesh, pal: Dictionary, res: Dictionary, bucket: int) -> void:
	var m: int = res["head_m"]
	var nr: int = res["head_r"]
	var rings: Array = []
	for r in nr:
		var u: float = float(r) / float(nr - 1)
		var e: float = lerpf(u, 0.5 - 0.5 * cos(PI * u), 0.35)
		rings.append(head_ring(lerpf(HEAD_S0, HEAD_S1, e), m))
	var back: Color = pal["back"]
	var belly: Color = pal["belly"]
	var dorsal: Color = pal["dorsal"]
	var muzzle: Color = pal["muzzle"]
	var cheek: Color = pal["cheek"]
	var eye_c: Vector3 = Vector3(head_x_at(EYE_S, EYE_Y), EYE_Y, EYE_S)
	var lid: Color = pal["lid"]
	var eye_m: int = res.get("eye_m", 0)
	# mid LOD (no eye geometry): the head vertex nearest the eye is painted as the eye, the ring around it as the lid
	var eye_v: float = -1.0
	if eye_m == 0:
		eye_v = INF
		for ring: PackedVector3Array in rings:
			for q in ring:
				if q.x > 0.0:
					eye_v = minf(eye_v, q.distance_to(eye_c))
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = _mix(belly, back, smoothstep(-0.6, 0.4, n.y))
		c = _mix(c, dorsal, smoothstep(0.75, 0.97, n.y) * 0.6)
		c = _mix(c, muzzle, 1.0 - smoothstep(-0.16, -0.03, p.z))
		c = _mix(c, _mix(belly, back, smoothstep(-0.65, 0.45, n.y)), smoothstep(0.08, 0.2, p.z))
		# pale grizzled cheeks / jowls
		var ck: float = smoothstep(0.35, 0.8, absf(n.x)) * _bump(p.z, -0.07, 0.07, 0.22) * _bump(p.y, -0.21, -0.11, 0.0)
		c = _mix(c, cheek, ck * 0.75)
		# mouth line
		var lip_y: float = lerpf(-0.075, -0.112, smoothstep(-0.17, 0.04, p.z))
		var lip: float = (1.0 - smoothstep(0.004, 0.012, absf(p.y - lip_y))) * (1.0 - smoothstep(0.0, 0.04, p.z)) * smoothstep(0.2, 0.6, absf(n.x))
		c = _mix(c, Color(0.03, 0.025, 0.02), lip * 0.8)
		if eye_v >= 0.0:
			var ed: float = Vector3(absf(p.x), p.y, p.z).distance_to(eye_c) - eye_v
			c = _mix(c, lid, 1.0 - smoothstep(0.05, 0.09, ed))
			c = _mix(c, EYE_DARK, (1.0 - smoothstep(0.002, 0.004, ed)) * 0.8)
		var v: float = 0.92 + 0.16 * _hash(p)
		var ao: float = lerpf(0.5, 1.0, smoothstep(-0.95, 0.1, n.y)) * (1.0 - lip * 0.35)
		return Color(c.r * v, c.g * v, c.b * v, ao)
	k.grid(rings, paint, BMesh.FEAT_FUR + 0.1)
	# snout disc: moist skin with the nostrils drawn by the shader (planar UV over the disc)
	var rim: PackedVector3Array = rings[nr - 1]
	var top: float = HdMesh.pchip(_c("ht"), HEAD_S1)
	var bot: float = HdMesh.pchip(_c("hb"), HEAD_S1)
	var hw: float = HdMesh.pchip(_c("hw"), HEAD_S1)
	var cy: float = (top + bot) * 0.5
	var center: Vector3 = Vector3(0.0, cy, HEAD_S1 * _snout)
	var disc_rings: Array = [rim]
	var steps: int = res["disc_r"]
	for j in steps:
		var f: float = 0.9 if j == 0 else 0.55
		var dz: float = -0.008 if j == 0 else -0.010
		var ring: PackedVector3Array = PackedVector3Array()
		for p in rim:
			ring.push_back(center + (p - center) * f + Vector3(0.0, 0.0, dz))
		disc_rings.append(ring)
	var disc: Color = pal["disc"]
	var disc_paint: Callable = func(p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
		var c: Color = _mix(_mix(disc, muzzle, 0.5), disc, smoothstep(0.0, 0.5, t))
		return Color(c.r, c.g, c.b, lerpf(0.8, 1.0, t))
	k.grid(disc_rings, disc_paint, BMesh.FEAT_SKIN + 0.2, false, true, Vector3.ZERO, Vector3(0, 0, -0.001), false, false,
		Vector4(0.0, cy, 1.0 / hw, 2.0 / (top - bot)))
	# ears: small, erect, cupped forward
	var ear_m: int = res["ear_m"]
	var ear_r: int = res["ear_r"]
	var ear_out: Color = _mix(dorsal, back, 0.4)
	var ear_in: Color = _mix(dorsal, Color(0.30, 0.20, 0.17), 0.35)
	for sx: float in [-1.0, 1.0]:
		var base: Vector3 = Vector3(EAR_X * sx, head_y_at(EAR_S, EAR_X) - 0.008, EAR_S)
		var axis: Vector3 = Vector3(0.38 * sx, 1.0, 0.32).normalized()
		var face: Vector3 = Vector3(0.55 * sx, 0.0, -0.85).normalized()
		var side: Vector3 = axis.cross(face).normalized()
		var path: PackedVector3Array = PackedVector3Array()
		var rx: PackedFloat32Array = PackedFloat32Array()
		var ry: PackedFloat32Array = PackedFloat32Array()
		var prof: Array = [[0.0, 0.031, 0.015], [0.04, 0.032, 0.010], [0.075, 0.021, 0.007], [0.108, 0.006, 0.003]]
		for j in ear_r:
			var q: Array = prof[roundi(float(j) / float(ear_r - 1) * 3.0)]
			var d: float = q[0]
			path.push_back(base + axis * d + Vector3(0.0, 0.0, d * d * 1.6))
			rx.push_back(q[1])
			ry.push_back(q[2])
		var ear_paint: Callable = func(_p: Vector3, n: Vector3, _a: float, t: float) -> Color:
			var inner: float = smoothstep(0.1, 0.6, n.dot(face))
			var c: Color = _mix(ear_out, ear_in, inner)
			return Color(c.r, c.g, c.b, lerpf(0.6, 1.0, t) * (1.0 - inner * 0.3))
		k.grid(BMesh.tube_rings(path, rx, ry, side, ear_m), ear_paint, BMesh.FEAT_FUR + 0.4, false, true, Vector3.ZERO, axis * 0.006, true)
	# eyes: bare lid rim (lighter, warmer than the coat) around a domed wet globe; feature 5.4 = lid, 5.0 = globe
	if eye_m > 0:
		var lid_out: Color = _mix(_mix(belly, back, 0.6), lid, 0.35)
		var lid_margin: Color = _mix(EYE_DARK, lid, 0.25)
		var lid_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
			var c: Color = _mix(_mix(lid_out, lid, smoothstep(0.0, 0.45, t)), lid_margin, smoothstep(0.6, 1.0, t))
			return Color(c.r, c.g, c.b, lerpf(0.9, 0.7, t))
		var globe_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
			return Color(EYE_DARK.r, EYE_DARK.g, EYE_DARK.b, lerpf(0.7, 1.0, t))
		for sx: float in [-1.0, 1.0]:
			var c: Vector3 = Vector3(eye_c.x * sx, EYE_Y, EYE_S)
			var out: Vector3 = Vector3(sx, 0.25, -0.35).normalized()
			var fwd: Vector3 = (Vector3.FORWARD - out * out.dot(Vector3.FORWARD)).normalized()
			var up: Vector3 = fwd.cross(out).normalized() * sx
			var lid_rings: Array = []
			for j in EYE_LID.size():
				var ring: PackedVector3Array = _eye_ring(c, out, fwd, up, EYE_LID[j], eye_m)
				if j == 0:
					# lay the outer ring on the head surface (slightly under it: no seam)
					for i in eye_m:
						var e: Vector3 = ring[i]
						ring[i] = Vector3(sx * (head_x_at(e.z, e.y) - 0.0015), e.y, e.z)
				lid_rings.append(ring)
			k.grid(lid_rings, lid_paint, BMesh.FEAT_EYE + 0.4)
			var globe_rings: Array = []
			for q2: Array in EYE_GLOBE:
				globe_rings.append(_eye_ring(c, out, fwd, up, q2, eye_m))
			k.grid(globe_rings, globe_paint, BMesh.FEAT_EYE, false, true, Vector3.ZERO,
				out * EYE_R * (EYE_POLE - float((EYE_GLOBE[EYE_GLOBE.size() - 1] as Array)[0])))
	# tusks: lower canines curling up and out of the lip
	var tl: float = float(pal["tusk"]) * (1.0 + 0.12 * bucket)
	if tl > 0.0:
		var tw: float = pal["tusk_w"]
		var ctrl: Array = [Vector3(0.046, -0.088, -0.092), Vector3(0.060, -0.082, -0.108), Vector3(0.074, -0.062, -0.120),
			Vector3(0.082, -0.036, -0.122), Vector3(0.081, -0.014, -0.110)]
		var root: Vector3 = ctrl[0]
		var steps_t: int = res["tusk_steps"]
		var pts: Array = HdMesh.smooth_path(ctrl, steps_t) if steps_t > 1 else (ctrl if steps_t == 1 else [ctrl[0], ctrl[2], ctrl[3], ctrl[4]])
		var ivory: Color = Color(0.86, 0.82, 0.70)
		var stain: Color = Color(0.45, 0.36, 0.24)
		var tusk_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
			var c: Color = _mix(stain, ivory, smoothstep(0.0, 0.45, t))
			return Color(c.r, c.g, c.b, lerpf(0.6, 1.0, smoothstep(0.0, 0.3, t)))
		for sx: float in [-1.0, 1.0]:
			var path: PackedVector3Array = PackedVector3Array()
			var rr: PackedFloat32Array = PackedFloat32Array()
			var npts: int = pts.size()
			for j in npts:
				var p: Vector3 = root + ((pts[j] as Vector3) - root) * tl
				path.push_back(Vector3(p.x * sx, p.y, p.z))
				var u: float = float(j) / float(npts - 1)
				rr.push_back(lerpf(0.0105, 0.002, u * u) * tw)
			k.grid(BMesh.tube_rings(path, rr, rr, Vector3(0, 0, 1), res["tusk_m"]), tusk_paint, BMesh.FEAT_TUSK + 0.1,
				false, true, Vector3.ZERO, (path[npts - 1] - path[npts - 2]).normalized() * 0.003)


## One elliptic eye ring around centre `c`: q = [height along `out`, radius along `fwd`, radius along `up`] in EYE_R.
static func _eye_ring(c: Vector3, out: Vector3, fwd: Vector3, up: Vector3, q: Array, m: int) -> PackedVector3Array:
	var ring: PackedVector3Array = PackedVector3Array()
	ring.resize(m)
	var o: Vector3 = c + out * (float(q[0]) * EYE_R)
	for i in m:
		var a: float = TAU * float(i) / float(m)
		ring[i] = o + fwd * (cos(a) * float(q[1]) * EYE_R) + up * (sin(a) * float(q[2]) * EYE_R)
	return ring


## `hip_y`: pivot height (the sole lands on the ground); `mid_pick`: control points kept when the LOD has no smoothing.
static func _leg(k: BMesh, pal: Dictionary, res: Dictionary, ctrl: Array, hip_y: float, mid_pick: Array) -> void:
	var m: int = res["leg_m"]
	var steps: int = res.get("leg_steps", 0)
	var pts: Array = []
	var rads: Array = []
	for q: Array in ctrl:
		pts.append(Vector3(q[0], q[1], q[2]))
		rads.append(Vector3(q[3], q[4], 0.0))
	if steps > 1:
		pts = HdMesh.smooth_path(pts, steps)
		rads = HdMesh.smooth_path(rads, steps)
	elif steps == 0:
		pts = mid_pick.map(func(i: int) -> Vector3: return pts[i])
		rads = mid_pick.map(func(i: int) -> Vector3: return rads[i])
	var path: PackedVector3Array = PackedVector3Array()
	var rx: PackedFloat32Array = PackedFloat32Array()
	var rz: PackedFloat32Array = PackedFloat32Array()
	for i in pts.size():
		path.push_back(pts[i])
		rx.push_back((rads[i] as Vector3).x)
		rz.push_back((rads[i] as Vector3).y)
	var y_top: float = path[0].y
	var y_bot: float = path[path.size() - 1].y
	var side_c: Color = _mix(pal["belly"], pal["back"], 0.5)
	var leg_c: Color = pal["leg"]
	var paint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var t: float = inverse_lerp(y_top, y_bot, p.y)
		var c: Color = _mix(side_c, leg_c, smoothstep(0.3, 0.62, t))
		var v: float = 0.92 + 0.16 * _hash(p)
		var ao: float = lerpf(0.45, 1.0, smoothstep(0.12, 0.42, t)) * lerpf(0.8, 1.0, smoothstep(-0.6, 0.3, n.y))
		return Color(c.r * v, c.g * v, c.b * v, ao)
	k.grid(BMesh.tube_rings(path, rx, rz, Vector3.RIGHT, m), paint, BMesh.FEAT_FUR + 0.15)
	# cloven hoof: notch at the front and back of every ring
	var last: Vector3 = path[path.size() - 1]
	var hoof_rings: Array = []
	var nh: int = res["hoof_r"]
	var hpts: Array = [HOOF[0], HOOF[2]] if nh == 2 else HOOF
	var hoof_path: PackedVector3Array = PackedVector3Array()
	var hrx: PackedFloat32Array = PackedFloat32Array()
	var hrz: PackedFloat32Array = PackedFloat32Array()
	for h: Array in hpts:
		hoof_path.push_back(last + Vector3(0.0, h[0], h[1]))
		hrx.push_back(h[2])
		hrz.push_back(h[3])
	# put the sole on the ground (pivot space: ground = -pivot height)
	var sole: float = -hip_y + HOOF_LIFT
	var shift: float = sole - hoof_path[hoof_path.size() - 1].y
	for i in hoof_path.size():
		var hp: Vector3 = hoof_path[i]
		hp.y += shift * float(i) / float(hoof_path.size() - 1)
		hoof_path[i] = hp
	var rings: Array = BMesh.tube_rings(hoof_path, hrx, hrz, Vector3.RIGHT, m)
	for r in rings.size():
		var ring: PackedVector3Array = rings[r]
		var c: Vector3 = hoof_path[r]
		var f: float = 0.0 if r == 0 else (0.45 if r == rings.size() - 1 else 0.3)
		ring[0] = c + (ring[0] - c) * (1.0 - f)
		@warning_ignore("integer_division")
		var bi: int = m / 2
		ring[bi] = c + (ring[bi] - c) * (1.0 - f * 0.6)
		rings[r] = ring
		hoof_rings.append(ring)
	var hoof_c: Color = Color(0.085, 0.075, 0.07)
	var hoof_paint: Callable = func(_p: Vector3, _n: Vector3, _a: float, t: float) -> Color:
		var c: Color = _mix(Color(0.05, 0.045, 0.042), hoof_c, t)
		return Color(c.r, c.g, c.b, 1.0)
	k.grid(hoof_rings, hoof_paint, BMesh.FEAT_HOOF, false, true)


static func _tail(k: BMesh, pal: Dictionary, res: Dictionary) -> void:
	var m: int = res["tail_m"]
	var steps: int = res.get("tail_steps", 0)
	var pts: Array = []
	var rads: Array = []
	for q: Array in TAIL:
		pts.append(Vector3(q[0], q[1], q[2]))
		rads.append(Vector3(q[3], q[3], 0.0))
	if steps > 1:
		pts = HdMesh.smooth_path(pts, steps)
		rads = HdMesh.smooth_path(rads, steps)
	elif steps == 0:
		pts = [pts[0], pts[2], pts[4], pts[5], pts[6]]
		rads = [rads[0], rads[2], rads[4], rads[5], rads[6]]
	var path: PackedVector3Array = PackedVector3Array()
	var rr: PackedFloat32Array = PackedFloat32Array()
	for i in pts.size():
		path.push_back(pts[i])
		rr.push_back((rads[i] as Vector3).x)
	var back: Color = pal["back"]
	var dorsal: Color = pal["dorsal"]
	var paint: Callable = func(p: Vector3, _n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = _mix(back, dorsal, smoothstep(-0.05, -0.2, p.y))
		return Color(c.r, c.g, c.b, lerpf(0.6, 1.0, smoothstep(0.0, -0.06, p.y)))
	k.grid(BMesh.tube_rings(path, rr, rr, Vector3.RIGHT, m), paint, BMesh.FEAT_MANE + 0.3, false, true)


## Far LOD: trunk, head, ears and four straight legs in the rest pose, one mesh.
static func _far(k: BMesh, pal: Dictionary, res: Dictionary, type_id: StringName) -> void:
	var m: int = res["trunk_m"]
	var nr: int = res["trunk_r"]
	var rings: Array = []
	var hump: float = 0.03 if type_id == Ids.BOSS else (0.015 if type_id == Ids.ALPHA else 0.0)
	for r in nr:
		var u: float = float(r) / float(nr - 1)
		var z: float = lerpf(TRUNK_Z0 + 0.02, TRUNK_Z1 - 0.01, u)
		rings.append(trunk_ring(z, m, hump * _bump(z, -0.42, -0.25, 0.0) + mane_h(z, pal["mane"], pal.get("mane_long", false)) * 0.85))
	var back: Color = pal["back"]
	var belly: Color = pal["belly"]
	var leg_c: Color = pal["leg"]
	var paint: Callable = func(_p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = _mix(belly, back, smoothstep(-0.65, 0.45, n.y))
		return Color(c.r, c.g, c.b, lerpf(0.45, 1.0, smoothstep(-0.95, 0.2, n.y)))
	k.grid(rings, paint, BMesh.FEAT_FUR + 0.25, true, true)
	# head
	k.xf = Transform3D(Basis.IDENTITY, HEAD_REST)
	var hm: int = res["head_m"]
	var hr: int = res["head_r"]
	var hrings: Array = []
	for r in hr:
		var u: float = float(r) / float(hr - 1)
		hrings.append(head_ring(lerpf(0.14, HEAD_S1, u), hm))
	var muzzle: Color = pal["muzzle"]
	var hpaint: Callable = func(p: Vector3, n: Vector3, _a: float, _t: float) -> Color:
		var c: Color = _mix(_mix(belly, back, smoothstep(-0.6, 0.4, n.y)), muzzle, 1.0 - smoothstep(-0.16, -0.03, p.z))
		return Color(c.r, c.g, c.b, lerpf(0.5, 1.0, smoothstep(-0.95, 0.1, n.y)))
	k.grid(hrings, hpaint, BMesh.FEAT_FUR + 0.1, false, true)
	var ear_c: Color = pal["dorsal"]
	var epaint: Callable = func(_p: Vector3, _n: Vector3, _a: float, _t: float) -> Color:
		return Color(ear_c.r, ear_c.g, ear_c.b, 0.9)
	for sx: float in [-1.0, 1.0]:
		var base: Vector3 = Vector3(EAR_X * sx, head_y_at(EAR_S, EAR_X) - 0.008, EAR_S)
		var axis: Vector3 = Vector3(0.38 * sx, 1.0, 0.32).normalized()
		var path: PackedVector3Array = PackedVector3Array([base, base + axis * 0.05])
		k.grid(BMesh.tube_rings(path, PackedFloat32Array([0.03, 0.022]), PackedFloat32Array([0.012, 0.008]), Vector3(0, 0, 1), res["ear_m"]),
			epaint, BMesh.FEAT_FUR, false, true, Vector3.ZERO, axis * 0.06)
	# legs: straight 4-sided posts with a dark lower half
	var lm: int = res["leg_m"]
	for i in 4:
		var hip: Vector3 = LEG_HIPS[i]
		k.xf = Transform3D(Basis.IDENTITY, hip)
		var front: bool = i < 2
		var path: PackedVector3Array = PackedVector3Array([Vector3(0, -0.12, 0.0), Vector3(0, -0.30 if front else -0.26, 0.02 if not front else 0.0), Vector3(0, -hip.y, -0.02)])
		var rx: PackedFloat32Array = PackedFloat32Array([0.06, 0.035, 0.03]) if front else PackedFloat32Array([0.075, 0.04, 0.03])
		var rz: PackedFloat32Array = PackedFloat32Array([0.07, 0.04, 0.035]) if front else PackedFloat32Array([0.11, 0.05, 0.035])
		var lpaint: Callable = func(p: Vector3, _n: Vector3, _a: float, _t: float) -> Color:
			var c: Color = _mix(_mix(belly, back, 0.5), leg_c, 1.0 - smoothstep(-0.32, -0.2, p.y))
			return Color(c.r, c.g, c.b, lerpf(0.6, 1.0, 1.0 - smoothstep(-0.3, -0.12, p.y)))
		k.grid(BMesh.tube_rings(path, rx, rz, Vector3.RIGHT, lm), lpaint, BMesh.FEAT_FUR, false, true)
	k.xf = Transform3D.IDENTITY
