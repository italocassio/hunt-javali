extends "res://assets/models/weapons/showcase/hd_view.gd"
## HD .30-06 semi-automatic hunting rifle: reddish walnut with a full-length fore-end ("telha"), long round receiver
## with a small operating handle on the right (the Mover, static: this gun has no bolt cycle), detachable box
## magazine hanging below the action, gas tube under the barrel, medium scope. No arms (weapon_view.gd adds them).
## Same gun space as rifle_308_hd.gd: s = distance forward from the butt plate (z = -s), y up from the bore
## axis, x to the shooter's right. Nodes: Gun > Body (wood, hard surface, lens), Gun > Mover (operating handle).

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
const RHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.075, -0.29)
const LHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.057, -0.6)

const FWD: Vector3 = Vector3(0.0, 0.0, -1.0)
const MUZZLE_S: float = 1.10
const SCOPE_Y: float = 0.0480
const SCOPE_S0: float = 0.245          # rear of the eye cup
const SCOPE_LEN: float = 0.310
const SCOPE_R: float = 0.0145
const SCOPE_BELL_R: float = 0.0265
const RAIL_TOP: float = 0.0250
const ADS_S: float = 0.231             # in front of the eye, centre of the ocular
const STOCK_POINTS: int = 22
const RECV_R: float = 0.0185
const AO_RAYS: int = 10
const AO_RADIUS: float = 0.045
const STOCK_END: float = 0.72

const TOP: Array = [[0.0, -0.0300], [0.025, -0.0295], [0.10, -0.0255], [0.18, -0.0225], [0.20, -0.0245],
	[0.22, -0.0320], [0.24, -0.0375], [0.265, -0.0385], [0.29, -0.0315], [0.31, -0.0200],
	[0.33, -0.0100], [0.36, -0.0050], [0.40, -0.0030], [0.60, -0.0010], [0.72, -0.0010]]
const BOT: Array = [[0.0, -0.157], [0.025, -0.156], [0.12, -0.126], [0.215, -0.096], [0.238, -0.092],
	[0.250, -0.097], [0.261, -0.1070], [0.270, -0.1115], [0.292, -0.1110], [0.301, -0.1030],
	[0.310, -0.0860], [0.320, -0.0690], [0.332, -0.0600], [0.36, -0.0575], [0.45, -0.0565],
	[0.56, -0.0540], [0.62, -0.0525], [0.72, -0.0495]]
const WID: Array = [[0.0, 0.0205], [0.025, 0.021], [0.15, 0.0205], [0.235, 0.0175], [0.275, 0.0180],
	[0.31, 0.0210], [0.35, 0.0245], [0.52, 0.0250], [0.60, 0.0245], [0.72, 0.0232]]
const WIDEST: Array = [[0.0, 0.36], [0.20, 0.38], [0.26, 0.45], [0.30, 0.40], [0.35, 0.34], [0.72, 0.36]]
const EXP_TOP: Array = [[0.0, 2.1], [0.20, 2.0], [0.30, 2.2], [0.35, 3.4], [0.72, 3.0]]
const EXP_BOT: Array = [[0.0, 1.9], [0.22, 2.1], [0.265, 3.0], [0.295, 3.0], [0.33, 2.8], [0.40, 3.0], [0.72, 2.6]]

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


## Reddish walnut: the .308 wood shader, warmer and lighter, checkering on the grip and the fore-end.
static func get_materials() -> Dictionary:
	if not _materials.is_empty():
		return _materials
	var base: Dictionary = RifleHD.get_materials()
	var wood: ShaderMaterial = ShaderMaterial.new()
	wood.shader = (base[SURF_WOOD] as ShaderMaterial).shader
	wood.set_shader_parameter(&"noise_tex", (base[SURF_WOOD] as ShaderMaterial).get_shader_parameter(&"noise_tex"))
	wood.set_shader_parameter(&"col_dark", Color(0.120, 0.055, 0.028))
	wood.set_shader_parameter(&"col_mid", Color(0.300, 0.145, 0.070))
	wood.set_shader_parameter(&"col_light", Color(0.420, 0.235, 0.120))
	wood.set_shader_parameter(&"varnish_roughness", 0.34)
	wood.set_shader_parameter(&"smoke_amount", 0.30)
	wood.set_shader_parameter(&"ring_amount", 0.35)
	wood.set_shader_parameter(&"warp_amount", 0.5)
	wood.set_shader_parameter(&"tone_amount", 0.6)
	wood.set_shader_parameter(&"fore_panel", Vector4(0.575, -0.0260, 0.090, 0.0125))
	wood.set_shader_parameter(&"fore_angle", 0.0)
	wood.set_shader_parameter(&"tip_plane", 0.700)
	_materials = {SURF_WOOD: wood, SURF_HARD: base[SURF_HARD], SURF_LENS: base[SURF_LENS]}
	return _materials


static func _build_model() -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var body: HDMesh = HDMesh.new()
	var handle: HDMesh = HDMesh.new()
	_stock(body)
	_barrel(body)
	_receiver(body)
	_rail(body)
	HDScope.build(body, SCOPE_S0, SCOPE_Y, SCOPE_LEN, SCOPE_R, SCOPE_BELL_R, [0.115, 0.215], RAIL_TOP, 0.150)
	_magazine(body)
	_bottom_metal(body)
	_handle(handle)
	var built_body: Dictionary = body.build()
	var built_handle: Dictionary = handle.build()
	var faces: PackedVector3Array = body.get_faces().duplicate()
	faces.append_array(handle.get_faces())
	var occluders: TriangleMesh = TriangleMesh.new()
	occluders.create_from_faces(faces)
	HDMesh.bake_ao(built_body, occluders, AO_RAYS, AO_RADIUS, 1.25, 0.12)
	HDMesh.bake_ao(built_handle, occluders, AO_RAYS, AO_RADIUS, 1.25, 0.12)
	var mats: Dictionary = get_materials()
	var body_mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_body, body_mesh, mats)
	var handle_mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built_handle, handle_mesh, mats)
	var stats: Dictionary = {
		"triangles": body.triangle_count() + handle.triangle_count(),
		"surfaces": body_mesh.get_surface_count() + handle_mesh.get_surface_count(),
		"materials": mats.size(),
		"mesh_instances": 2,
		"build_ms": Time.get_ticks_msec() - t0,
	}
	return {"body": body_mesh, "mover": handle_mesh, "stats": stats}


# --- stock and fore-end ------------------------------------------------------------------------------

static func _stock(k: HDMesh) -> void:
	k.crease_deg = 50.0
	k.bevel_wear = 0.0
	_fin(k, RifleHD.RUBBER)
	k.loft([_ring(0.025, 0.93, 0.0), _ring(0.025, 0.985, 0.0035), _ring(0.025, 1.003, 0.008), _ring(0.025, 1.003, 0.0215)], true, false)
	_fin(k, RifleHD.SPACER)
	k.loft([_ring(0.025, 1.003, 0.0215), _ring(0.025, 1.003, 0.025)], false, false)
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	var s: float = 0.025
	while s < 0.160:
		rings.append(_ring(s))
		s += 0.0225
	s = 0.160
	while s < 0.356:
		rings.append(_ring(s))
		s += 0.0075
	s = 0.36
	while s < STOCK_END - 0.01:
		rings.append(_ring(s))
		s += 0.04
	for t: float in [0.0, 0.35, 0.62, 0.82, 0.94, 1.0]:
		rings.append(_ring(STOCK_END, sqrt(1.0 - t * t * 0.97), STOCK_END + 0.022 * t))
	k.crease_deg = 60.0
	k.loft(rings, false, true)
	k.crease_deg = 50.0


# --- barrel, gas tube, receiver ----------------------------------------------------------------------

static func _barrel(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	k.lathe([
		Vector3(0.560, 0.0150, 0), Vector3(0.600, 0.0140, 0), Vector3(0.700, 0.0128, 0), Vector3(0.900, 0.0112, 0),
		Vector3(1.060, 0.0102, 0), Vector3(1.0970, 0.0098, 0), Vector3(1.1000, 0.0090, 0), Vector3(1.1000, 0.0066, 0),
		Vector3(1.0975, 0.0050, 0), Vector3(1.0975, 0.0039, 0)], 16, Vector3.ZERO, FWD)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(1.0975, 0.0039, 0), Vector3(1.075, 0.0039, 0), Vector3(1.075, 0.0, 0)], 12, Vector3.ZERO, FWD)
	# barrel band and gas block where the fore-end ends, gas tube running forward under the barrel
	_fin(k, RifleHD.BLUED_SATIN)
	k.lathe([Vector3(0.722, 0.0, 0), Vector3(0.722, 0.0158, 0), Vector3(0.726, 0.0164, 0), Vector3(0.752, 0.0164, 0), Vector3(0.756, 0.0158, 0), Vector3(0.756, 0.0, 0)], 16, Vector3.ZERO, FWD)
	k.cbox(_v(0.740, -0.0185, 0.0), Vector3(0.0170, 0.0120, 0.0300), 0.0018)
	k.lathe([Vector3(0.756, 0.0048, 0), Vector3(0.940, 0.0048, 0), Vector3(0.944, 0.0040, 0), Vector3(0.944, 0.0, 0)], 10, _v(0.0, -0.0172, 0.0), FWD)
	k.cbox(_v(0.940, -0.0090, 0.0), Vector3(0.0100, 0.0200, 0.0100), 0.0012)
	# front sight on a ramp
	k.cbox(_v(1.060, 0.0112, 0.0), Vector3(0.0085, 0.0060, 0.0240), 0.0012)
	_fin(k, RifleHD.STEEL)
	k.cbox(_v(1.068, 0.0164, 0.0), Vector3(0.0036, 0.0080, 0.0040), 0.0007)


static func _receiver(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	# ring 3 (0.402..0.478), segments 2..6 of 24 = 30..105 degrees from the top toward the right: ejection port
	var profile: Array = [
		Vector3(0.300, 0.0100, 0), Vector3(0.300, 0.0170, 0), Vector3(0.3022, RECV_R, 0), Vector3(0.402, RECV_R, 0),
		Vector3(0.478, RECV_R, 0), Vector3(0.578, RECV_R, 0), Vector3(0.580, 0.0170, 0), Vector3(0.580, 0.0150, 0)]
	var port: Callable = func(ring: int, seg: int) -> bool: return ring == 3 and seg >= 2 and seg <= 6
	k.lathe(profile, 24, Vector3.ZERO, FWD, Vector3.UP, port, 0.0098)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(0.475, 0.0097, 0), Vector3(0.405, 0.0097, 0)], 12, Vector3.ZERO, FWD)
	# bolt carrier seen through the port
	_fin(k, RifleHD.STEEL_DARK)
	k.lathe([Vector3(0.405, 0.0078, 0), Vector3(0.470, 0.0078, 0)], 12, Vector3.ZERO, FWD)
	# roll mark on the left flank
	k.paint(Color(0.66, 0.63, 0.52), 0.0, 0.55)
	RifleHD._roll_mark(k, ".30-06", 0.455, 0.0045, RECV_R + 0.00012, deg_to_rad(8.0))
	# tang behind the action, following the wrist
	_fin(k, RifleHD.BLUED)
	k.extrude(PackedVector2Array([
		Vector2(0.262, -0.0395), Vector2(0.306, -0.0150), Vector2(0.306, -0.0050), Vector2(0.296, -0.0095),
		Vector2(0.282, -0.0200), Vector2(0.272, -0.0290), Vector2(0.262, -0.0330)]), _side_frame(), -0.0055, 0.0055, 0.0010)
	# safety button on the right of the trigger guard front, bolt hold-open lever on the left
	_fin(k, RifleHD.BLUED_SATIN)
	k.cbox(_v(0.428, -0.0455, 0.0105), Vector3(0.0055, 0.0055, 0.0150), 0.001)
	k.cbox(_v(0.470, -0.0050, -0.0190), Vector3(0.0120, 0.0045, 0.0100), 0.001)
	# gas vent on the left of the front receiver
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(0.01865, 0.0015, 0), Vector3(0.01865, 0.0, 0)], 8, _v(0.545, 0.0, 0.0), Vector3.LEFT, Vector3.UP)


static func _rail(k: HDMesh) -> void:
	k.bevel_wear = 0.8
	_fin(k, RifleHD.BLUED_SATIN)
	k.cbox(_v(0.395, 0.0215, 0.0), Vector3(0.0200, 0.0075, 0.1700), 0.0016)


# --- detachable magazine, trigger group --------------------------------------------------------------

static func _magazine(k: HDMesh) -> void:
	# dark magazine well cut into the underside of the stock
	_fin(k, RifleHD.VOID)
	k.cbox(_v(0.502, -0.0572, 0.0), Vector3(0.0235, 0.0030, 0.0900), 0.0006)
	# box: top at the action, slightly bowed forward, with feed lips and a floor plate
	k.bevel_wear = 0.7
	_fin(k, RifleHD.BLUED_SATIN)
	k.extrude(PackedVector2Array([
		Vector2(0.463, -0.0330), Vector2(0.541, -0.0330), Vector2(0.541, -0.0800), Vector2(0.5455, -0.0950),
		Vector2(0.5465, -0.1050), Vector2(0.4630, -0.1050), Vector2(0.4600, -0.0900), Vector2(0.4600, -0.0600)]),
		_side_frame(), -0.0100, 0.0100, 0.0016)
	_fin(k, RifleHD.STEEL_DARK)
	k.cbox(_v(0.5045, -0.1068, 0.0), Vector3(0.0880, 0.0062, 0.0228), 0.0020)
	_fin(k, RifleHD.BLUED)
	k.cbox(_v(0.5040, -0.0605, 0.0), Vector3(0.0840, 0.0090, 0.0190), 0.0012)
	# latch tab on the front
	_fin(k, RifleHD.STEEL)
	k.cbox(_v(0.5450, -0.0620, 0.0), Vector3(0.0045, 0.0120, 0.0100), 0.0008)


static func _bottom_metal(k: HDMesh) -> void:
	k.bevel_wear = 0.85
	_fin(k, RifleHD.BLUED)
	var loop: Array = HDMesh.smooth_path([
		_v(0.3290, -0.0590, 0.0), _v(0.3335, -0.0690, 0.0), _v(0.3390, -0.0810, 0.0), _v(0.3490, -0.0895, 0.0),
		_v(0.3640, -0.0930, 0.0), _v(0.3810, -0.0925, 0.0), _v(0.3950, -0.0880, 0.0), _v(0.4045, -0.0780, 0.0),
		_v(0.4095, -0.0650, 0.0), _v(0.4120, -0.0535, 0.0)], 2)
	var wear: float = k.get_wear()
	k.set_wear(0.35)
	k.sweep(loop, HDMesh.rect_section(0.0130, 0.0034, 0.0010), Vector3.RIGHT)
	k.set_wear(wear)
	_fin(k, RifleHD.STEEL)
	var blade: Array = HDMesh.smooth_path([
		_v(0.3685, -0.0540, 0.0), _v(0.3668, -0.0640, 0.0), _v(0.3672, -0.0730, 0.0), _v(0.3700, -0.0800, 0.0), _v(0.3738, -0.0845, 0.0)], 2)
	var widths: PackedFloat32Array = PackedFloat32Array()
	for i in blade.size():
		widths.push_back(lerpf(1.0, 0.72, float(i) / float(blade.size() - 1)))
	k.sweep(blade, HDMesh.rect_section(0.0062, 0.0036, 0.0010), Vector3.RIGHT, widths)
	# sling studs
	_fin(k, RifleHD.BLUED_SATIN)
	k.bevel_wear = 0.6
	for spot: float in [0.072, 0.640]:
		var y: float = HDMesh.pchip(HDMesh.curve(BOT), spot)
		k.lathe([Vector3(-0.002, 0.0034, 0), Vector3(0.0030, 0.0034, 0), Vector3(0.0040, 0.0026, 0), Vector3(0.0090, 0.0026, 0), Vector3(0.0098, 0.0018, 0), Vector3(0.0098, 0.0, 0)], 10, _v(spot, y, 0.0), Vector3.DOWN, FWD)


# --- operating handle (Mover) --------------------------------------------------------------------------

static func _handle(k: HDMesh) -> void:
	k.bevel_wear = 0.0
	_fin(k, RifleHD.STEEL)
	var path: Array = HDMesh.smooth_path([
		_v(0.4400, 0.0050, 0.0160), _v(0.4385, 0.0040, 0.0250), _v(0.4350, 0.0022, 0.0318)], 2)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in path.size():
		radii.push_back(lerpf(1.0, 0.80, float(i) / float(path.size() - 1)))
	k.crease_deg = 80.0
	k.sweep(path, HDMesh.circle_section(0.0036, 8), FWD, radii)
	k.crease_deg = 180.0
	k.sphere(_v(0.4340, 0.0016, 0.0345), Vector3.ONE * 0.0062, 12, 7)
	k.crease_deg = 50.0
