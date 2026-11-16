extends "res://assets/models/weapons/showcase/hd_view.gd"
## HD 12 gauge pump shotgun: deep walnut stock with a rubber pad, thick wide-mouthed barrel with a bead, magazine
## tube under it, and a wooden fore-end (the slide) that is the Mover and racks back on play_cycle. No scope, no arms.
## Same gun space as rifle_308_hd.gd: s = distance forward from the butt plate (z = -s), y up from the bore
## axis, x to the shooter's right. Nodes: Gun > Body (wood, hard surface), Gun > Mover (fore-end).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")

const SURF_WOOD: int = 0
const SURF_HARD: int = 1

const HIP_ORIGIN: Vector3 = Vector3(0.21, -0.080, -0.24)
const HIP_YAW: float = 0.10
const HIP_PIVOT: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.09, -0.03)
## Viewmodel depth scale k (weapon_view.gd scales Gun by (1, 1, k) about the eye): the gun renders as if with
## its own narrower FOV, tan(fov'/2) = k * tan(75/2) -> k 0.55 ~ 46 degrees, bigger and closer than the world.
const VIEW_DEPTH: float = 0.55
const RHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.077, -0.29)
const LHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.045, -0.683)

const FWD: Vector3 = Vector3(0.0, 0.0, -1.0)
const MUZZLE_S: float = 0.990
## Sight line: over the receiver top to the bead (AdsAnchor y), anchor station above the receiver.
const SIGHT_Y: float = 0.0200
const SIGHT_S: float = 0.470
const BEAD_Y: float = 0.0182
const PUMP_TRAVEL: float = 0.13
const STOCK_POINTS: int = 22
const FOREND_POINTS: int = 18
const AO_RAYS: int = 10
const AO_RADIUS: float = 0.045

## Satin grey alloy for the receiver (blued black reads as a flat black box under the studio sky).
const ALLOY: Array = [Color(0.21, 0.22, 0.245), 0.30, 0.50]
const ALLOY_BRIGHT: Array = [Color(0.36, 0.37, 0.40), 0.40, 0.40]
const BRASS: Array = [Color(0.88, 0.72, 0.32), 1.0, 0.28]

const TOP: Array = [[0.0, -0.0440], [0.03, -0.0420], [0.11, -0.0340], [0.19, -0.0275], [0.235, -0.0270],
	[0.265, -0.0295], [0.30, -0.0285], [0.33, -0.0170], [0.355, -0.0075], [0.385, -0.0040]]
const BOT: Array = [[0.0, -0.1500], [0.03, -0.1490], [0.12, -0.1180], [0.20, -0.0980], [0.24, -0.1030],
	[0.275, -0.1100], [0.30, -0.1105], [0.322, -0.0990], [0.338, -0.0720], [0.355, -0.0520], [0.385, -0.0400]]
const WID: Array = [[0.0, 0.0240], [0.03, 0.0245], [0.15, 0.0230], [0.22, 0.0190], [0.28, 0.0185], [0.33, 0.0175], [0.385, 0.0130]]
const WIDEST: Array = [[0.0, 0.40], [0.4, 0.40]]
const EXP_TOP: Array = [[0.0, 2.1], [0.3, 2.4], [0.385, 3.0]]
const EXP_BOT: Array = [[0.0, 2.0], [0.385, 2.4]]

const F_TOP: Array = [[0.575, -0.0035], [0.80, -0.0035]]
const F_BOT: Array = [[0.575, -0.0330], [0.610, -0.0440], [0.660, -0.0515], [0.740, -0.0510], [0.800, -0.0430]]
const F_WID: Array = [[0.575, 0.0120], [0.605, 0.0170], [0.660, 0.0222], [0.740, 0.0222], [0.800, 0.0195]]
const F_WIDEST: Array = [[0.575, 0.45], [0.80, 0.45]]
const F_EXP_TOP: Array = [[0.575, 2.6], [0.80, 2.6]]
const F_EXP_BOT: Array = [[0.575, 2.3], [0.80, 2.3]]

static var _cache: Dictionary = {}
static var _curves: Dictionary = {}
static var _fore_curves: Dictionary = {}
static var _materials: Dictionary = {}


func _init() -> void:
	super()
	hip_origin = HIP_ORIGIN
	hip_yaw = HIP_YAW
	hip_pivot = HIP_PIVOT
	view_depth = VIEW_DEPTH
	muzzle_s = MUZZLE_S
	ads_gun = Vector2(SIGHT_S, SIGHT_Y)


func _model() -> Dictionary:
	return get_model()


func _animate_mover(t: float) -> void:
	var p: float = 0.0
	if t >= 0.0:
		p = _pump_curve(t)
	_mover.position = Vector3(0.0, 0.0, PUMP_TRAVEL * p)


## 0 -> 1 -> 0 with a quick rack and a slightly slower return (same curve as weapon_view.gd).
static func _pump_curve(t: float) -> float:
	if t < 0.45:
		return smoothstep(0.0, 0.45, t)
	if t < 0.55:
		return 1.0
	return 1.0 - smoothstep(0.55, 1.0, t)


static func get_stats() -> Dictionary:
	return get_model()["stats"]


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = _build_model()
	return _cache


static func _v(s: float, y: float, x: float) -> Vector3:
	return Vector3(x, y, -s)


static func _fin(k: HDMesh, finish: Array, wear: float = 0.0) -> void:
	k.surface(SURF_HARD)
	k.paint(finish[0], finish[1], finish[2], wear, 0)


static func _curve_set() -> Dictionary:
	if _curves.is_empty():
		_curves = {"top": HDMesh.curve(TOP), "bot": HDMesh.curve(BOT), "wid": HDMesh.curve(WID),
			"widest": HDMesh.curve(WIDEST), "exp_top": HDMesh.curve(EXP_TOP), "exp_bot": HDMesh.curve(EXP_BOT)}
		_fore_curves = {"top": HDMesh.curve(F_TOP), "bot": HDMesh.curve(F_BOT), "wid": HDMesh.curve(F_WID),
			"widest": HDMesh.curve(F_WIDEST), "exp_top": HDMesh.curve(F_EXP_TOP), "exp_bot": HDMesh.curve(F_EXP_BOT)}
	return _curves


static func _ring(s: float, scale: float = 1.0, at_s: float = -1.0) -> PackedVector3Array:
	return HDMesh.section_ring(_curve_set(), s, STOCK_POINTS, scale, at_s)


static func _fore_ring(s: float, scale: float = 1.0, at_s: float = -1.0) -> PackedVector3Array:
	_curve_set()
	return HDMesh.section_ring(_fore_curves, s, FOREND_POINTS, scale, at_s)


static func _side_frame() -> Transform3D:
	return Transform3D(Basis(FWD, Vector3.UP, Vector3.RIGHT), Vector3.ZERO)


## Walnut: the .308 wood shader with the checkering panels moved to the pistol grip and the fore-end.
static func get_materials() -> Dictionary:
	if not _materials.is_empty():
		return _materials
	var base: Dictionary = RifleHD.get_materials()
	var wood: ShaderMaterial = ShaderMaterial.new()
	wood.shader = (base[SURF_WOOD] as ShaderMaterial).shader
	wood.set_shader_parameter(&"noise_tex", (base[SURF_WOOD] as ShaderMaterial).get_shader_parameter(&"noise_tex"))
	wood.set_shader_parameter(&"col_dark", Color(0.12, 0.052, 0.026))
	wood.set_shader_parameter(&"col_mid", Color(0.30, 0.140, 0.070))
	wood.set_shader_parameter(&"col_light", Color(0.46, 0.240, 0.120))
	wood.set_shader_parameter(&"grip_panel", Vector4(0.285, -0.068, 0.034, 0.020))
	wood.set_shader_parameter(&"fore_panel", Vector4(0.690, -0.026, 0.062, 0.0105))
	wood.set_shader_parameter(&"fore_angle", 0.0)
	wood.set_shader_parameter(&"tip_plane", 9.0)
	wood.set_shader_parameter(&"cap_plane", Vector3(9.0, 10.0, 0.0))
	_materials = {SURF_WOOD: wood, SURF_HARD: base[SURF_HARD]}
	return _materials


static func _build_model() -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var body: HDMesh = HDMesh.new()
	var fore: HDMesh = HDMesh.new()
	_stock(body)
	_barrel(body)
	_receiver(body)
	_bottom_metal(body)
	_forend(fore)
	var built_body: Dictionary = body.build()
	var built_fore: Dictionary = fore.build()
	var faces: PackedVector3Array = body.get_faces().duplicate()
	faces.append_array(fore.get_faces())
	var occluders: TriangleMesh = TriangleMesh.new()
	occluders.create_from_faces(faces)
	HDMesh.bake_ao(built_body, occluders, AO_RAYS, AO_RADIUS, 1.25, 0.12)
	HDMesh.bake_ao(built_fore, occluders, AO_RAYS, AO_RADIUS, 1.25, 0.12)
	var mats: Dictionary = get_materials()
	var body_mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_body, body_mesh, mats)
	var fore_mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_fore, fore_mesh, mats)
	var stats: Dictionary = {
		"triangles": body.triangle_count() + fore.triangle_count(),
		"surfaces": body_mesh.get_surface_count() + fore_mesh.get_surface_count(),
		"materials": mats.size(),
		"mesh_instances": 2,
		"build_ms": Time.get_ticks_msec() - t0,
	}
	return {"body": body_mesh, "mover": fore_mesh, "stats": stats}


# --- stock ---------------------------------------------------------------------------------------

static func _stock(k: HDMesh) -> void:
	k.crease_deg = 50.0
	k.bevel_wear = 0.0
	_fin(k, RifleHD.RUBBER)
	k.loft([_ring(0.028, 0.93, 0.0), _ring(0.028, 0.985, 0.004), _ring(0.028, 1.003, 0.009), _ring(0.028, 1.003, 0.026)], true, false)
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	var s: float = 0.028
	while s < 0.385:
		rings.append(_ring(s))
		s += 0.025
	rings.append(_ring(0.385))
	k.crease_deg = 60.0
	k.loft(rings, false, true)
	k.crease_deg = 50.0


# --- barrel, receiver, magazine tube ---------------------------------------------------------------

static func _barrel(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	k.lathe([
		Vector3(0.560, 0.0130, 0), Vector3(0.600, 0.0130, 0), Vector3(0.700, 0.0126, 0), Vector3(0.950, 0.0122, 0),
		Vector3(0.9720, 0.0129, 0), Vector3(0.9860, 0.0132, 0), Vector3(0.9900, 0.0126, 0), Vector3(0.9900, 0.0104, 0),
		Vector3(0.9880, 0.0096, 0)], 18, Vector3.ZERO, FWD)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(0.9880, 0.0096, 0), Vector3(0.9400, 0.0096, 0), Vector3(0.9400, 0.0, 0)], 12, Vector3.ZERO, FWD)
	# magazine tube under the barrel, with its end cap, and the hanger that clamps both
	_fin(k, RifleHD.BLUED_SATIN)
	var tube: Vector3 = _v(0.0, -0.0225, 0.0)
	k.lathe([
		Vector3(0.570, 0.0092, 0), Vector3(0.866, 0.0092, 0), Vector3(0.870, 0.0100, 0), Vector3(0.876, 0.0112, 0),
		Vector3(0.892, 0.0112, 0), Vector3(0.896, 0.0100, 0), Vector3(0.896, 0.0, 0)], 14, tube, FWD)
	k.cbox(_v(0.800, -0.0105, 0.0), Vector3(0.0120, 0.0300, 0.012), 0.0014)
	# bead sight on a short stalk
	k.cbox(_v(0.968, 0.0140, 0.0), Vector3(0.0028, 0.0040, 0.006), 0.0006)
	_fin(k, BRASS)
	k.crease_deg = 180.0
	k.sphere(_v(0.968, BEAD_Y, 0.0), Vector3.ONE * 0.0032, 10, 6)
	k.crease_deg = 50.0


static func _receiver(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	# barrel extension ring and the receiver block
	k.lathe([Vector3(0.5700, 0.0, 0), Vector3(0.5700, 0.0150, 0), Vector3(0.5730, 0.0156, 0), Vector3(0.6000, 0.0156, 0), Vector3(0.6030, 0.0150, 0), Vector3(0.6030, 0.0, 0)], 16, Vector3.ZERO, FWD)
	_fin(k, ALLOY)
	k.bevel_wear = 1.0
	var recv: PackedVector2Array = PackedVector2Array([
		Vector2(0.3600, -0.0305), Vector2(0.3565, -0.0130), Vector2(0.3670, 0.0060), Vector2(0.3830, 0.0150),
		Vector2(0.3950, 0.0175), Vector2(0.5450, 0.0175), Vector2(0.5620, 0.0150), Vector2(0.5725, 0.0050), Vector2(0.5725, -0.0305)])
	k.extrude(recv, _side_frame(), -0.01425, 0.01425, 0.0034)
	# ejection window on the right flank: bevelled rim, black recess, bolt face seen inside
	var w: float = 0.01425
	_fin(k, ALLOY_BRIGHT)
	k.extrude(PackedVector2Array([Vector2(0.4580, 0.0146), Vector2(0.5480, 0.0146), Vector2(0.5480, -0.0046), Vector2(0.4760, -0.0046), Vector2(0.4580, 0.0090)]),
		_side_frame(), w - 0.0008, w + 0.0006, 0.0006)
	_fin(k, RifleHD.VOID)
	k.extrude(PackedVector2Array([Vector2(0.4640, 0.0136), Vector2(0.5420, 0.0136), Vector2(0.5420, -0.0036), Vector2(0.4800, -0.0036), Vector2(0.4640, 0.0086)]),
		_side_frame(), w - 0.0008, w + 0.0009, 0.0004)
	_fin(k, ALLOY_BRIGHT)
	k.extrude(PackedVector2Array([Vector2(0.5050, 0.0100), Vector2(0.5400, 0.0100), Vector2(0.5400, -0.0020), Vector2(0.5050, -0.0020)]),
		_side_frame(), w - 0.0008, w + 0.0003, 0.0004)
	# loading port underneath with the shell carrier, and machining lines
	_fin(k, RifleHD.VOID)
	k.cbox(_v(0.5120, -0.0300, 0.0), Vector3(0.0190, 0.0030, 0.0520), 0.0004)
	k.bevel_wear = 0.0
	for sx: float in [-1.0, 1.0]:
		k.cbox(_v(0.4750, -0.0155, sx * w), Vector3(0.0007, 0.0010, 0.1500), 0.0)
		k.cbox(_v(0.3980, -0.0070, sx * w), Vector3(0.0007, 0.0450, 0.0010), 0.0)
	for i in 6:
		k.cbox(_v(0.4100 + 0.0085 * float(i), 0.0174, 0.0), Vector3(0.0215, 0.0008, 0.0012), 0.0)
	k.bevel_wear = 0.9
	_fin(k, ALLOY)
	# slide release and safety button
	k.cbox(_v(0.425, -0.0235, -0.0150), Vector3(0.0035, 0.0045, 0.014), 0.0010)
	_fin(k, RifleHD.STEEL_DARK)
	k.crease_deg = 30.0
	k.lathe([Vector3(0.0, 0.0, 0), Vector3(0.0, 0.0032, 0), Vector3(0.0050, 0.0032, 0.0005), Vector3(0.0054, 0.0024, 0), Vector3(0.0054, 0.0, 0)], 10, _v(0.438, -0.0305, 0.0), Vector3.DOWN, FWD)
	k.crease_deg = 50.0


static func _bottom_metal(k: HDMesh) -> void:
	k.bevel_wear = 0.85
	_fin(k, RifleHD.BLUED)
	k.cbox(_v(0.4300, -0.0330, 0.0), Vector3(0.0245, 0.0040, 0.1300), 0.0012)
	var loop: Array = HDMesh.smooth_path([
		_v(0.4050, -0.0325, 0.0), _v(0.4090, -0.0430, 0.0), _v(0.4180, -0.0530, 0.0), _v(0.4320, -0.0570, 0.0),
		_v(0.4500, -0.0560, 0.0), _v(0.4630, -0.0490, 0.0), _v(0.4700, -0.0390, 0.0), _v(0.4720, -0.0325, 0.0)], 2)
	var wear: float = k.get_wear()
	k.set_wear(0.35)
	k.sweep(loop, HDMesh.rect_section(0.0140, 0.0036, 0.0010), Vector3.RIGHT)
	k.set_wear(wear)
	_fin(k, RifleHD.STEEL)
	var blade: Array = HDMesh.smooth_path([
		_v(0.4360, -0.0340, 0.0), _v(0.4345, -0.0420, 0.0), _v(0.4350, -0.0480, 0.0), _v(0.4380, -0.0530, 0.0)], 2)
	var widths: PackedFloat32Array = PackedFloat32Array()
	for i in blade.size():
		widths.push_back(lerpf(1.0, 0.72, float(i) / float(blade.size() - 1)))
	k.sweep(blade, HDMesh.rect_section(0.0062, 0.0036, 0.0010), Vector3.RIGHT, widths)


# --- fore-end (the slide, Mover) -------------------------------------------------------------------

static func _forend(k: HDMesh) -> void:
	k.crease_deg = 60.0
	k.bevel_wear = 0.0
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	for t: float in [0.0, 0.5, 0.85]:
		rings.append(_fore_ring(0.575, sqrt(1.0 - (1.0 - t) * (1.0 - t) * 0.97), 0.575 + 0.010 * t))
	var s: float = 0.600
	while s < 0.790:
		rings.append(_fore_ring(s))
		s += 0.035
	for t: float in [0.0, 0.5, 0.85, 1.0]:
		rings.append(_fore_ring(0.790, sqrt(1.0 - t * t * 0.97), 0.790 + 0.010 * t))
	k.loft(rings, true, true)
	# steel ring at the front of the fore-end
	_fin(k, RifleHD.BLUED_SATIN)
	k.bevel_wear = 0.7
	k.cbox(_v(0.7975, -0.0225, 0.0), Vector3(0.0420, 0.0460, 0.0050), 0.0014)
