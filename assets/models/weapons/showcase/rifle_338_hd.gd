extends "res://assets/models/weapons/showcase/hd_view.gd"
## HD .338 long-range bolt rifle: dark laminated stock with a high straight comb, wide flat free-floating fore-end,
## heavy barrel ending in a four-baffle muzzle brake, long action with the .308 style bolt (the Mover, scaled up),
## and a big 8x scope with a 41 mm objective. No arms (weapon_view.gd adds them).
## Same gun space as rifle_308_hd.gd: s = distance forward from the butt plate (z = -s), y up from the bore
## axis, x to the shooter's right. Nodes: Gun > Body (stock, hard surface, lens), Gun > Mover (bolt).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const HDScope := preload("res://assets/models/weapons/showcase/hd_scope.gd")

const SURF_WOOD: int = 0
const SURF_HARD: int = 1
const SURF_LENS: int = 2

const HIP_ORIGIN: Vector3 = Vector3(0.21, -0.080, -0.24)
const HIP_YAW: float = 0.10
const HIP_PIVOT: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.09, -0.03)
## Viewmodel depth scale k (weapon_view.gd scales Gun by (1, 1, k) about the eye): the gun renders as if with
## its own narrower FOV, tan(fov'/2) = k * tan(75/2) -> k 0.55 ~ 46 degrees, bigger and closer than the world.
const VIEW_DEPTH: float = 0.55
const RHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.08, -0.29)
const LHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.06, -0.62)

const FWD: Vector3 = Vector3(0.0, 0.0, -1.0)
const MUZZLE_S: float = 1.14
const SCOPE_Y: float = 0.0605
const SCOPE_S0: float = 0.285          # rear of the eye cup
const SCOPE_LEN: float = 0.440
const SCOPE_R: float = 0.0205
const SCOPE_BELL_R: float = 0.0405
const RAIL_TOP: float = 0.0265
const ADS_S: float = 0.270             # in front of the eye, centre of the ocular
const STOCK_POINTS: int = 22
const RECV_R: float = 0.0190
const STOCK_END: float = 0.83
const BOLT_SHIFT: float = 0.040
const AO_RAYS: int = 10
const AO_RADIUS: float = 0.045

const TOP: Array = [[0.0, -0.0190], [0.03, -0.0185], [0.12, -0.0170], [0.20, -0.0185], [0.23, -0.0270],
	[0.255, -0.0365], [0.285, -0.0375], [0.31, -0.0300], [0.33, -0.0170], [0.355, -0.0070],
	[0.38, -0.0050], [0.50, -0.0050], [0.60, -0.0120], [0.66, -0.0200], [0.83, -0.0205]]
const BOT: Array = [[0.0, -0.165], [0.03, -0.164], [0.14, -0.130], [0.22, -0.100], [0.245, -0.0950],
	[0.262, -0.1120], [0.275, -0.1230], [0.295, -0.1235], [0.305, -0.1140], [0.314, -0.0920],
	[0.324, -0.0720], [0.340, -0.0620], [0.40, -0.0580], [0.55, -0.0545], [0.70, -0.0510], [0.83, -0.0475]]
const WID: Array = [[0.0, 0.0215], [0.15, 0.0210], [0.235, 0.0185], [0.275, 0.0190], [0.31, 0.0215],
	[0.35, 0.0260], [0.55, 0.0275], [0.70, 0.0270], [0.83, 0.0250]]
const WIDEST: Array = [[0.0, 0.40], [0.26, 0.45], [0.35, 0.36], [0.83, 0.40]]
const EXP_TOP: Array = [[0.0, 2.1], [0.20, 2.0], [0.30, 2.3], [0.35, 4.0], [0.83, 4.0]]
const EXP_BOT: Array = [[0.0, 1.9], [0.265, 3.0], [0.33, 2.8], [0.40, 3.4], [0.83, 3.4]]

static var _cache: Dictionary = {}
static var _curves: Dictionary = {}
static var _materials: Dictionary = {}


func _init() -> void:
	super()
	hip_origin = HIP_ORIGIN
	hip_yaw = HIP_YAW
	hip_pivot = HIP_PIVOT
	view_depth = VIEW_DEPTH
	muzzle_s = MUZZLE_S
	ads_gun = Vector2(ADS_S, SCOPE_Y)


func _model() -> Dictionary:
	return get_model()


func _animate_mover(t: float) -> void:
	var lift: float = 0.0
	var back: float = 0.0
	if t >= 0.0:
		lift = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t))
		back = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.55, 0.85, t))
	_mover.rotation = Vector3(0.0, 0.0, 1.05 * lift)
	_mover.position = Vector3(0.0, 0.0, 0.085 * back)


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
	return _curves


static func _ring(s: float, scale: float = 1.0, at_s: float = -1.0) -> PackedVector3Array:
	return HDMesh.section_ring(_curve_set(), s, STOCK_POINTS, scale, at_s)


static func _side_frame() -> Transform3D:
	return Transform3D(Basis(FWD, Vector3.UP, Vector3.RIGHT), Vector3.ZERO)


## Dark slate laminate: the .308 wood shader in near-black blue-grey, no checkering, no ebony tip, no cap.
static func get_materials() -> Dictionary:
	if not _materials.is_empty():
		return _materials
	var base: Dictionary = RifleHD.get_materials()
	var wood: ShaderMaterial = ShaderMaterial.new()
	wood.shader = (base[SURF_WOOD] as ShaderMaterial).shader
	wood.set_shader_parameter(&"noise_tex", (base[SURF_WOOD] as ShaderMaterial).get_shader_parameter(&"noise_tex"))
	wood.set_shader_parameter(&"col_dark", Color(0.030, 0.034, 0.042))
	wood.set_shader_parameter(&"col_mid", Color(0.060, 0.067, 0.080))
	wood.set_shader_parameter(&"col_light", Color(0.110, 0.122, 0.145))
	wood.set_shader_parameter(&"varnish_roughness", 0.48)
	wood.set_shader_parameter(&"smoke_amount", 0.12)
	wood.set_shader_parameter(&"ring_amount", 0.25)
	wood.set_shader_parameter(&"warp_amount", 0.4)
	wood.set_shader_parameter(&"tone_amount", 0.5)
	wood.set_shader_parameter(&"grip_panel", Vector4(9.0, 0.0, 0.01, 0.0))
	wood.set_shader_parameter(&"fore_panel", Vector4(9.0, 0.0, 0.01, 0.0))
	wood.set_shader_parameter(&"tip_plane", 9.0)
	wood.set_shader_parameter(&"cap_plane", Vector3(9.0, 10.0, 0.0))
	_materials = {SURF_WOOD: wood, SURF_HARD: base[SURF_HARD], SURF_LENS: base[SURF_LENS]}
	return _materials


static func _build_model() -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var body: HDMesh = HDMesh.new()
	var bolt: HDMesh = HDMesh.new()
	_stock(body)
	_barrel(body)
	_receiver(body)
	_rail(body)
	HDScope.build(body, SCOPE_S0, SCOPE_Y, SCOPE_LEN, SCOPE_R, SCOPE_BELL_R, [0.135, 0.295], RAIL_TOP, 0.215)
	_bottom_metal(body)
	_bolt_parts(bolt)
	var built_body: Dictionary = body.build()
	var built_bolt: Dictionary = bolt.build()
	var faces: PackedVector3Array = body.get_faces().duplicate()
	faces.append_array(bolt.get_faces())
	var occluders: TriangleMesh = TriangleMesh.new()
	occluders.create_from_faces(faces)
	HDMesh.bake_ao(built_body, occluders, AO_RAYS, AO_RADIUS, 1.25, 0.12)
	HDMesh.bake_ao(built_bolt, occluders, AO_RAYS, AO_RADIUS, 1.25, 0.12)
	var mats: Dictionary = get_materials()
	var body_mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_body, body_mesh, mats)
	var bolt_mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_bolt, bolt_mesh, mats)
	var stats: Dictionary = {
		"triangles": body.triangle_count() + bolt.triangle_count(),
		"surfaces": body_mesh.get_surface_count() + bolt_mesh.get_surface_count(),
		"materials": mats.size(),
		"mesh_instances": 2,
		"build_ms": Time.get_ticks_msec() - t0,
	}
	return {"body": body_mesh, "bolt": bolt_mesh, "mover": bolt_mesh, "stats": stats}


# --- stock ---------------------------------------------------------------------------------------

static func _stock(k: HDMesh) -> void:
	k.crease_deg = 50.0
	k.bevel_wear = 0.0
	# thick rubber recoil pad
	_fin(k, RifleHD.RUBBER)
	k.loft([_ring(0.030, 0.93, 0.0), _ring(0.030, 0.985, 0.004), _ring(0.030, 1.003, 0.010), _ring(0.030, 1.003, 0.030)], true, false)
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	var s: float = 0.030
	while s < 0.160:
		rings.append(_ring(s))
		s += 0.0245
	s = 0.160
	while s < 0.356:
		rings.append(_ring(s))
		s += 0.0075
	s = 0.36
	while s < STOCK_END - 0.01:
		rings.append(_ring(s))
		s += 0.035
	for t: float in [0.0, 0.35, 0.62, 0.82, 0.94, 1.0]:
		rings.append(_ring(STOCK_END, sqrt(1.0 - t * t * 0.97), STOCK_END + 0.024 * t))
	k.crease_deg = 60.0
	k.loft(rings, false, true)
	k.crease_deg = 50.0


# --- barrel and muzzle brake ----------------------------------------------------------------------

static func _barrel(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	k.lathe([
		Vector3(0.570, 0.0172, 0), Vector3(0.600, 0.0164, 0), Vector3(0.700, 0.0160, 0), Vector3(0.900, 0.0152, 0),
		Vector3(1.040, 0.0144, 0), Vector3(1.046, 0.0152, 0)], 18, Vector3.ZERO, FWD)
	# brake: core with four baffles, solid front cap
	_fin(k, RifleHD.BLUED_SATIN)
	k.bevel_wear = 0.8
	var prof: Array = [Vector3(1.046, 0.0152, 0), Vector3(1.050, 0.0152, 0)]
	for i in 3:
		var s0: float = 1.050 + 0.0195 * float(i)
		prof.append_array([Vector3(s0, 0.0152, 0), Vector3(s0 + 0.0020, 0.0222, 0), Vector3(s0 + 0.0140, 0.0222, 0),
			Vector3(s0 + 0.0160, 0.0152, 0)])
	prof.append_array([Vector3(1.1085, 0.0152, 0), Vector3(1.1105, 0.0222, 0), Vector3(1.1360, 0.0222, 0), Vector3(1.1400, 0.0206, 0),
		Vector3(1.1400, 0.0072, 0), Vector3(1.1375, 0.0058, 0), Vector3(1.1375, 0.0046, 0)])
	k.lathe(prof, 18, Vector3.ZERO, FWD)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(1.1375, 0.0046, 0), Vector3(1.100, 0.0046, 0), Vector3(1.100, 0.0, 0)], 12, Vector3.ZERO, FWD)
	# side ports of the brake: dark slots through the gaps
	for i in 3:
		var sc: float = 1.050 + 0.0195 * float(i) + 0.0160 + 0.0020
		k.cbox(_v(sc, 0.0, 0.0), Vector3(0.0300, 0.0300, 0.0030), 0.0004)


# --- receiver, rail ------------------------------------------------------------------------------

static func _receiver(k: HDMesh) -> void:
	var d: float = BOLT_SHIFT
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	# ring 3 (0.458..0.534): segments 2..6 of 24 = 30..105 degrees from the top toward the right: ejection port
	var profile: Array = [
		Vector3(0.345 + d, 0.0105, 0), Vector3(0.345 + d, 0.0178, 0), Vector3(0.3472 + d, RECV_R, 0), Vector3(0.418 + d, RECV_R, 0),
		Vector3(0.494 + d, RECV_R, 0), Vector3(0.5338 + d, RECV_R, 0), Vector3(0.535 + d, 0.0178, 0), Vector3(0.535 + d, 0.0160, 0)]
	var port: Callable = func(ring: int, seg: int) -> bool: return ring == 3 and seg >= 2 and seg <= 6
	k.lathe(profile, 24, Vector3.ZERO, FWD, Vector3.UP, port, 0.0104)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(0.500 + d, 0.0100, 0), Vector3(0.345 + d, 0.0100, 0)], 12, Vector3.ZERO, FWD)
	# magazine follower under the open action
	_fin(k, RifleHD.STEEL_DARK)
	k.cbox(_v(0.455 + d, -0.0030, 0.0), Vector3(0.0180, 0.0014, 0.0900), 0.0004)
	# barrel nut and recoil lug
	_fin(k, RifleHD.BLUED_SATIN)
	k.bevel_wear = 0.8
	k.lathe([Vector3(0.575, 0.0, 0), Vector3(0.575, 0.0222, 0), Vector3(0.578, 0.0228, 0), Vector3(0.600, 0.0228, 0), Vector3(0.603, 0.0222, 0), Vector3(0.603, 0.0, 0)], 20, Vector3.ZERO, FWD)
	k.cbox(_v(0.589, -0.0235, 0.0), Vector3(0.0300, 0.0140, 0.0120), 0.0015)
	_fin(k, RifleHD.BLUED)
	k.cbox(_v(0.368 + d, 0.0035, -0.0185), Vector3(0.0045, 0.0075, 0.030), 0.0012)
	# roll mark on the left flank
	k.paint(Color(0.66, 0.63, 0.52), 0.0, 0.55)
	RifleHD._roll_mark(k, ".338 LAPUA", 0.515, 0.0046, RECV_R + 0.00012, deg_to_rad(8.0))
	# tang behind the action
	_fin(k, RifleHD.BLUED)
	k.extrude(PackedVector2Array([
		Vector2(0.3300, -0.0395), Vector2(0.386, -0.0140), Vector2(0.386, -0.0045), Vector2(0.370, -0.0092),
		Vector2(0.352, -0.0185), Vector2(0.340, -0.0262), Vector2(0.3300, -0.0300)]), _side_frame(), -0.0058, 0.0058, 0.0010)
	_fin(k, RifleHD.BLUED_SATIN)
	k.cbox(_v(0.358, -0.0085, 0.0104), Vector3(0.0048, 0.0052, 0.016), 0.001)


static func _rail(k: HDMesh) -> void:
	k.bevel_wear = 0.8
	_fin(k, RifleHD.BLUED_SATIN)
	k.cbox(_v(0.5025, 0.0225, 0.0), Vector3(0.0240, 0.0080, 0.2350), 0.0018)


# --- trigger group, floor plate ---------------------------------------------------------------------

static func _bottom_metal(k: HDMesh) -> void:
	var d: float = 0.030
	k.bevel_wear = 0.85
	_fin(k, RifleHD.BLUED)
	var loop: Array = HDMesh.smooth_path([
		_v(0.3170 + d, -0.0600, 0.0), _v(0.3215 + d, -0.0700, 0.0), _v(0.3270 + d, -0.0820, 0.0), _v(0.3370 + d, -0.0905, 0.0),
		_v(0.3520 + d, -0.0940, 0.0), _v(0.3690 + d, -0.0935, 0.0), _v(0.3830 + d, -0.0890, 0.0), _v(0.3925 + d, -0.0790, 0.0),
		_v(0.3975 + d, -0.0660, 0.0), _v(0.4000 + d, -0.0545, 0.0)], 2)
	var wear: float = k.get_wear()
	k.set_wear(0.35)
	k.sweep(loop, HDMesh.rect_section(0.0140, 0.0036, 0.0010), Vector3.RIGHT)
	k.set_wear(wear)
	# floor plate with latch (internal magazine)
	k.cbox(_v(0.5050, -0.0575, 0.0), Vector3(0.0290, 0.0038, 0.1300), 0.0013)
	k.cbox(_v(0.4270, -0.0640, 0.0), Vector3(0.0075, 0.0085, 0.0050), 0.0012)
	_fin(k, RifleHD.STEEL)
	var blade: Array = HDMesh.smooth_path([
		_v(0.3865, -0.0550, 0.0), _v(0.3848, -0.0650, 0.0), _v(0.3852, -0.0740, 0.0), _v(0.3880, -0.0810, 0.0), _v(0.3918, -0.0855, 0.0)], 2)
	var widths: PackedFloat32Array = PackedFloat32Array()
	for i in blade.size():
		widths.push_back(lerpf(1.0, 0.72, float(i) / float(blade.size() - 1)))
	k.sweep(blade, HDMesh.rect_section(0.0064, 0.0038, 0.0010), Vector3.RIGHT, widths)
	# sling studs
	_fin(k, RifleHD.BLUED_SATIN)
	k.bevel_wear = 0.6
	for spot: float in [0.072, 0.740]:
		var y: float = HDMesh.pchip(HDMesh.curve(BOT), spot)
		k.lathe([Vector3(-0.002, 0.0034, 0), Vector3(0.0030, 0.0034, 0), Vector3(0.0040, 0.0026, 0), Vector3(0.0090, 0.0026, 0), Vector3(0.0098, 0.0018, 0), Vector3(0.0098, 0.0, 0)], 10, _v(spot, y, 0.0), Vector3.DOWN, FWD)


# --- bolt (the .308 bolt, a bit bigger and moved back with the longer action) -----------------------------

static func _bolt_parts(k: HDMesh) -> void:
	k.xf = Transform3D(Basis.from_scale(Vector3(1.10, 1.10, 1.0)), Vector3(0.0, 0.0, -BOLT_SHIFT))
	RifleHD._bolt_parts(k)
	k.xf = Transform3D.IDENTITY
