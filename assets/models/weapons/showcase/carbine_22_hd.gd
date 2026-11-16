extends "res://assets/models/weapons/showcase/hd_view.gd"
## HD .22 bolt carbine: slim pale stock, thin tapered barrel, open sights (the ADS lines up the rear notch and
## the front post), bolt with a ball handle, little box magazine. No scope, no arms (weapon_view.gd adds them).
## Same gun space as rifle_308_hd.gd: s = distance forward from the butt plate (z = -s), y up from the bore
## axis, x to the shooter's right. Nodes: Gun > Body (wood, hard surface), Gun > Mover (bolt).

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
const RHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.0725, -0.29)
const LHAND: Vector3 = HIP_ORIGIN + Vector3(0.0, -0.026, -0.5)

const FWD: Vector3 = Vector3(0.0, 0.0, -1.0)
const MUZZLE_S: float = 0.945
## Sight line (y of the rear notch / front post tip) and the station of the rear sight.
const SIGHT_Y: float = 0.0186
const SIGHT_S: float = 0.455
const STOCK_POINTS: int = 20
const RECV_R: float = 0.0128
const AO_RAYS: int = 10
const AO_RADIUS: float = 0.04

const TOP: Array = [[0.0, -0.0285], [0.03, -0.0280], [0.10, -0.0245], [0.17, -0.0215], [0.20, -0.0230],
	[0.225, -0.0215], [0.245, -0.0150], [0.262, -0.0090], [0.285, -0.0060], [0.33, -0.0050], [0.58, -0.0045], [0.60, -0.0060]]
const BOT: Array = [[0.0, -0.1020], [0.03, -0.1010], [0.12, -0.0850], [0.19, -0.0780], [0.23, -0.0900],
	[0.26, -0.0990], [0.285, -0.1000], [0.300, -0.0940], [0.312, -0.0780], [0.322, -0.0600], [0.335, -0.0470],
	[0.36, -0.0400], [0.42, -0.0370], [0.58, -0.0310], [0.60, -0.0290]]
const WID: Array = [[0.0, 0.0165], [0.03, 0.0168], [0.15, 0.0160], [0.22, 0.0140], [0.26, 0.0150], [0.30, 0.0170],
	[0.36, 0.0190], [0.45, 0.0175], [0.58, 0.0150], [0.60, 0.0140]]
const WIDEST: Array = [[0.0, 0.38], [0.3, 0.40], [0.6, 0.35]]
const EXP_TOP: Array = [[0.0, 2.1], [0.25, 2.2], [0.33, 3.0], [0.6, 3.0]]
const EXP_BOT: Array = [[0.0, 2.0], [0.3, 2.4], [0.6, 2.2]]

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
	ads_gun = Vector2(SIGHT_S, SIGHT_Y)


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


## Pale beech: the .308 wood shader with lighter colours and no grip / fore-end panels.
static func get_materials() -> Dictionary:
	if not _materials.is_empty():
		return _materials
	var base: Dictionary = RifleHD.get_materials()
	var wood: ShaderMaterial = ShaderMaterial.new()
	wood.shader = (base[SURF_WOOD] as ShaderMaterial).shader
	wood.set_shader_parameter(&"noise_tex", (base[SURF_WOOD] as ShaderMaterial).get_shader_parameter(&"noise_tex"))
	wood.set_shader_parameter(&"col_dark", Color(0.20, 0.125, 0.080))
	wood.set_shader_parameter(&"col_mid", Color(0.320, 0.215, 0.145))
	wood.set_shader_parameter(&"col_light", Color(0.400, 0.290, 0.205))
	wood.set_shader_parameter(&"varnish_roughness", 0.40)
	# sober beech: fine, straight veins, no smoky patches
	wood.set_shader_parameter(&"smoke_amount", 0.08)
	wood.set_shader_parameter(&"ring_amount", 0.45)
	wood.set_shader_parameter(&"ring_freq", 34.0)
	wood.set_shader_parameter(&"warp_amount", 0.12)
	wood.set_shader_parameter(&"tone_amount", 0.45)
	wood.set_shader_parameter(&"grip_panel", Vector4(0.285, -0.060, 0.026, 0.0))
	wood.set_shader_parameter(&"fore_panel", Vector4(0.50, -0.02, 0.0, 0.0))
	wood.set_shader_parameter(&"tip_plane", 9.0)
	wood.set_shader_parameter(&"cap_plane", Vector3(9.0, 10.0, 0.0))
	_materials = {SURF_WOOD: wood, SURF_HARD: base[SURF_HARD]}
	return _materials


static func _build_model() -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var body: HDMesh = HDMesh.new()
	var bolt: HDMesh = HDMesh.new()
	_stock(body)
	_barrel(body)
	_receiver(body)
	_sights(body)
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
	_fin(k, RifleHD.RUBBER)
	k.loft([_ring(0.015, 0.93, 0.0), _ring(0.015, 0.985, 0.003), _ring(0.015, 1.003, 0.007), _ring(0.015, 1.003, 0.015)], true, false)
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	var s: float = 0.015
	while s < 0.30:
		rings.append(_ring(s))
		s += 0.025
	s = 0.30
	while s < 0.595:
		rings.append(_ring(s))
		s += 0.045
	for t: float in [0.0, 0.5, 0.85, 1.0]:
		rings.append(_ring(0.595 + 0.012 * t, sqrt(1.0 - t * t * 0.97)))
	k.crease_deg = 60.0
	k.loft(rings, false, true)
	k.crease_deg = 50.0


# --- barrel, receiver ----------------------------------------------------------------------------

static func _barrel(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	k.lathe([
		Vector3(0.420, 0.0098, 0), Vector3(0.50, 0.0092, 0), Vector3(0.60, 0.0082, 0), Vector3(0.80, 0.0073, 0),
		Vector3(0.925, 0.0068, 0), Vector3(0.9425, 0.0068, 0), Vector3(0.9450, 0.0062, 0), Vector3(0.9450, 0.0038, 0)],
		14, Vector3.ZERO, FWD)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(0.9450, 0.0038, 0), Vector3(0.925, 0.0038, 0), Vector3(0.925, 0.0, 0)], 10, Vector3.ZERO, FWD)
	# barrel band where the wood ends
	_fin(k, RifleHD.BLUED_SATIN)
	k.lathe([Vector3(0.5600, 0.0, 0), Vector3(0.5600, 0.0128, 0), Vector3(0.5640, 0.0132, 0), Vector3(0.5760, 0.0132, 0), Vector3(0.5790, 0.0128, 0), Vector3(0.5790, 0.0, 0)], 14, Vector3.ZERO, FWD)


static func _receiver(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, RifleHD.BLUED)
	var profile: Array = [
		Vector3(0.262, 0.0085, 0), Vector3(0.262, 0.0120, 0), Vector3(0.2645, RECV_R, 0), Vector3(0.325, RECV_R, 0),
		Vector3(0.395, RECV_R, 0), Vector3(0.4255, RECV_R, 0), Vector3(0.4280, 0.0120, 0), Vector3(0.4280, 0.0100, 0)]
	# segments 2..6 of 24 = 30..105 degrees from the top toward the right: ejection port
	var port: Callable = func(ring: int, seg: int) -> bool: return ring == 3 and seg >= 2 and seg <= 6
	k.lathe(profile, 24, Vector3.ZERO, FWD, Vector3.UP, port, 0.0083)
	_fin(k, RifleHD.VOID)
	k.lathe([Vector3(0.390, 0.0082, 0), Vector3(0.325, 0.0082, 0)], 12, Vector3.ZERO, FWD)
	# dovetail block under the rear sight, bolt stop on the left flank
	_fin(k, RifleHD.BLUED)
	k.cbox(_v(0.352, 0.0030, -0.0128), Vector3(0.0040, 0.0070, 0.020), 0.0012)
	# tang: wrist to receiver rear, in the side plane
	var tang: Transform3D = _side_frame()
	k.extrude(PackedVector2Array([
		Vector2(0.2480, -0.0150), Vector2(0.2640, 0.0060), Vector2(0.2640, -0.0090), Vector2(0.2560, -0.0220)]), tang, -0.0046, 0.0046, 0.0008)
	# safety lever on the right of the tang
	_fin(k, RifleHD.BLUED_SATIN)
	k.cbox(_v(0.272, -0.0120, 0.0100), Vector3(0.0040, 0.0045, 0.014), 0.001)


static func _sights(k: HDMesh) -> void:
	k.bevel_wear = 0.5
	# rear leaf: U notch seen from behind, extruded along the bore
	_fin(k, RifleHD.BLUED_SATIN)
	var frame: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -SIGHT_S))
	var by: float = 0.0085
	var ny: float = SIGHT_Y - 0.0026
	var ty: float = SIGHT_Y + 0.0040
	k.extrude(PackedVector2Array([
		Vector2(-0.0105, by), Vector2(0.0105, by), Vector2(0.0105, ty), Vector2(0.0034, ty),
		Vector2(0.0030, ny), Vector2(-0.0030, ny), Vector2(-0.0034, ty), Vector2(-0.0105, ty)]), frame, -0.0045, 0.0045, 0.0006)
	# front: ramp block and post
	k.cbox(_v(0.912, 0.0085, 0.0), Vector3(0.0085, 0.0052, 0.022), 0.0012)
	_fin(k, RifleHD.STEEL)
	k.cbox(_v(0.920, SIGHT_Y - 0.0036, 0.0), Vector3(0.0040, 0.0072, 0.0042), 0.0007)


static func _bottom_metal(k: HDMesh) -> void:
	k.bevel_wear = 0.85
	_fin(k, RifleHD.BLUED)
	var loop: Array = HDMesh.smooth_path([
		_v(0.3160, -0.0470, 0.0), _v(0.3210, -0.0560, 0.0), _v(0.3280, -0.0680, 0.0), _v(0.3400, -0.0750, 0.0),
		_v(0.3560, -0.0780, 0.0), _v(0.3720, -0.0765, 0.0), _v(0.3850, -0.0700, 0.0), _v(0.3940, -0.0600, 0.0),
		_v(0.3990, -0.0480, 0.0), _v(0.4010, -0.0370, 0.0)], 2)
	var wear: float = k.get_wear()
	k.set_wear(0.35)
	k.sweep(loop, HDMesh.rect_section(0.0110, 0.0030, 0.0009), Vector3.RIGHT)
	k.set_wear(wear)
	# detachable box magazine in front of the guard
	k.bevel_wear = 0.7
	_fin(k, RifleHD.BLUED_SATIN)
	k.extrude(PackedVector2Array([
		Vector2(0.4320, -0.0300), Vector2(0.4620, -0.0300), Vector2(0.4635, -0.0600), Vector2(0.4655, -0.0690),
		Vector2(0.4305, -0.0690), Vector2(0.4310, -0.0600)]), _side_frame(), -0.0078, 0.0078, 0.0017)
	_fin(k, RifleHD.STEEL_DARK)
	k.cbox(_v(0.4480, -0.0713, 0.0), Vector3(0.0188, 0.0044, 0.0390), 0.0014)
	# cartridge count slots on both flanks
	_fin(k, RifleHD.VOID)
	for sx: float in [-1.0, 1.0]:
		for y: float in [-0.0400, -0.0470, -0.0540]:
			k.cbox(_v(0.4465, y, sx * 0.0079), Vector3(0.0005, 0.0036, 0.0090), 0.0)
	k.bevel_wear = 0.85
	# trigger blade
	_fin(k, RifleHD.STEEL)
	var blade: Array = HDMesh.smooth_path([
		_v(0.3600, -0.0430, 0.0), _v(0.3585, -0.0520, 0.0), _v(0.3590, -0.0600, 0.0), _v(0.3620, -0.0660, 0.0)], 2)
	var widths: PackedFloat32Array = PackedFloat32Array()
	for i in blade.size():
		widths.push_back(lerpf(1.0, 0.72, float(i) / float(blade.size() - 1)))
	k.sweep(blade, HDMesh.rect_section(0.0054, 0.0032, 0.0009), Vector3.RIGHT, widths)


# --- bolt (rotates about the bore axis and slides back) --------------------------------------------

static func _bolt_parts(k: HDMesh) -> void:
	k.bevel_wear = 0.0
	_fin(k, RifleHD.STEEL)
	k.lathe([Vector3(0.325, 0.0080, 0), Vector3(0.420, 0.0080, 0)], 14, Vector3.ZERO, FWD)
	k.lathe([Vector3(0.3080, 0.0090, 0), Vector3(0.3080, 0.0105, 0), Vector3(0.3090, 0.0111, 0), Vector3(0.3210, 0.0111, 0), Vector3(0.3220, 0.0105, 0)], 14, Vector3.ZERO, FWD)
	# shroud and cocking piece behind the receiver
	k.bevel_wear = 0.8
	_fin(k, RifleHD.BLUED)
	k.lathe([
		Vector3(0.2490, 0.0, 0), Vector3(0.2490, 0.0050, 0), Vector3(0.2510, 0.0072, 0), Vector3(0.2570, 0.0090, 0),
		Vector3(0.2700, 0.0100, 0), Vector3(0.3000, 0.0104, 0), Vector3(0.3080, 0.0098, 0)], 16, Vector3.ZERO, FWD)
	_fin(k, RifleHD.STEEL_DARK)
	k.lathe([Vector3(0.2330, 0.0, 0), Vector3(0.2330, 0.0016, 0), Vector3(0.2340, 0.0022, 0), Vector3(0.2495, 0.0022, 0)], 8, Vector3.ZERO, FWD)
	# handle: bar swept down and out to the ball knob
	_fin(k, RifleHD.STEEL)
	var path: Array = HDMesh.smooth_path([
		_v(0.3165, 0.0000, 0.0070), _v(0.3165, -0.0010, 0.0160), _v(0.3163, -0.0052, 0.0245), _v(0.3155, -0.0125, 0.0318),
		_v(0.3142, -0.0212, 0.0372), _v(0.3134, -0.0276, 0.0405)], 2)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in path.size():
		radii.push_back(lerpf(1.0, 0.74, float(i) / float(path.size() - 1)))
	k.crease_deg = 80.0
	k.sweep(path, HDMesh.circle_section(0.0048, 8), FWD, radii)
	k.crease_deg = 180.0
	k.sphere(_v(0.3130, -0.0298, 0.0418), Vector3.ONE * 0.0088, 12, 7)
	k.crease_deg = 50.0
