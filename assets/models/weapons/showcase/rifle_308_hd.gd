extends WeaponViewBase
## SHOWCASE (not wired into gameplay): bolt action .308 with scope at the highest detail level that
## is still 100% procedural and Compatibility-safe. Same camera-space contract as weapon_view.gd:
## at position (0,0,0) the rifle sits at the hip, eye at the origin looking -Z. No arms.
##
## Gun space used by every part below: s = distance forward from the butt plate (z = -s),
## y = up from the bore axis, x = to the shooter's right.
## Nodes: Gun > Body (wood, hard surface, lens), Gun > Bolt (animated), Muzzle, AdsAnchor.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const WOOD_SHADER: Shader = preload("res://assets/models/weapons/showcase/hd_wood.gdshader")
const HARD_SHADER: Shader = preload("res://assets/models/weapons/showcase/hd_hard.gdshader")
const LENS_SHADER: Shader = preload("res://assets/models/weapons/showcase/hd_lens.gdshader")

const SURF_WOOD: int = 0
const SURF_HARD: int = 1
const SURF_LENS: int = 2

## Butt plate centre of the bore axis in camera space, and the toe-in toward screen centre.
const HIP_ORIGIN: Vector3 = Vector3(0.20, -0.175, -0.33)
const HIP_YAW: float = 0.19
const HIP_PIVOT: Vector3 = Vector3(0.20, -0.22, -0.30)

const FWD: Vector3 = Vector3(0.0, 0.0, -1.0)
const NOISE_SIZE: int = 512
const STOCK_POINTS: int = 24
const SCOPE_Y: float = 0.0490
const SCOPE_SEGS: int = 28
const RECV_R: float = 0.0172
const MUZZLE_S: float = 1.10
const AO_RAYS: int = 40
const AO_RADIUS: float = 0.045

# finishes: [albedo sRGB, metallic, roughness]
const BLUED: Array = [Color(0.315, 0.335, 0.395), 1.0, 0.27]
const BLUED_SATIN: Array = [Color(0.270, 0.285, 0.325), 1.0, 0.44]
const SCOPE_BLACK: Array = [Color(0.200, 0.200, 0.212), 0.0, 0.38]
const SCOPE_GLOSS: Array = [Color(0.165, 0.165, 0.178), 0.0, 0.30]
const STEEL: Array = [Color(0.80, 0.80, 0.82), 1.0, 0.20]
const STEEL_DARK: Array = [Color(0.48, 0.48, 0.50), 1.0, 0.30]
const RUBBER: Array = [Color(0.105, 0.102, 0.100), 0.0, 0.80]
const SPACER: Array = [Color(0.86, 0.83, 0.74), 0.0, 0.50]
const VOID: Array = [Color(0.012, 0.012, 0.012), 0.0, 0.95]

# stock side profile (s, y) and plan/section controls
const TOP: Array = [[0.0, -0.0300], [0.025, -0.0295], [0.10, -0.0260], [0.175, -0.0225], [0.195, -0.0240],
	[0.215, -0.0315], [0.235, -0.0375], [0.265, -0.0385], [0.290, -0.0320], [0.310, -0.0200],
	[0.330, -0.0100], [0.350, -0.0050], [0.38, -0.0040], [0.80, -0.0045], [0.82, -0.0060]]
const BOT: Array = [[0.0, -0.157], [0.025, -0.156], [0.12, -0.126], [0.215, -0.096], [0.238, -0.092],
	[0.250, -0.097], [0.261, -0.1070], [0.270, -0.1115], [0.292, -0.1110], [0.301, -0.1030],
	[0.310, -0.0860], [0.320, -0.0690], [0.332, -0.0600], [0.350, -0.0560], [0.40, -0.0540],
	[0.52, -0.0515], [0.60, -0.0450], [0.76, -0.0375], [0.82, -0.0360]]
const WID: Array = [[0.0, 0.0205], [0.025, 0.021], [0.15, 0.0205], [0.235, 0.0175], [0.275, 0.0180],
	[0.31, 0.0205], [0.35, 0.0240], [0.52, 0.0240], [0.60, 0.0225], [0.76, 0.0200], [0.82, 0.0190]]
## Share of the section height (from the top) where it is widest.
const WIDEST: Array = [[0.0, 0.36], [0.20, 0.38], [0.26, 0.45], [0.30, 0.40], [0.35, 0.30], [0.82, 0.32]]
## Superellipse exponents of the upper and lower halves (2 = ellipse, higher = boxier).
const EXP_TOP: Array = [[0.0, 2.1], [0.20, 2.0], [0.30, 2.2], [0.35, 5.0], [0.82, 5.0]]
const EXP_BOT: Array = [[0.0, 1.9], [0.22, 2.1], [0.265, 3.0], [0.295, 3.0], [0.33, 2.8], [0.40, 3.2], [0.60, 2.7], [0.82, 2.5]]

static var _cache: Dictionary = {}
static var _materials: Dictionary = {}
static var _keys: Dictionary = {}

var _gun: Node3D
var _body: MeshInstance3D
var _bolt: MeshInstance3D
var _muzzle: Marker3D
var _ads: Marker3D
var _hip: bool = true
var _recoil: float = 0.0
var _cycle_t: float = -1.0
var _cycle_d: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_gun = Node3D.new()
	_gun.name = "Gun"
	add_child(_gun)
	_body = _mesh_instance("Body")
	_bolt = _mesh_instance("Bolt")
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	add_child(_muzzle)
	_ads = Marker3D.new()
	_ads.name = "AdsAnchor"
	add_child(_ads)


func _ready() -> void:
	if _body.mesh == null:
		setup(&"rifle_308")


func _mesh_instance(node_name: String) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(m)
	return m


func setup(_weapon_id: StringName) -> void:
	var model: Dictionary = get_model()
	_body.mesh = model["body"]
	_bolt.mesh = model["bolt"]
	_apply_pose()


## false = gun space (butt plate at the origin, bore along -Z): used by the studio renders.
func set_hip_pose(enabled: bool) -> void:
	_hip = enabled
	_apply_pose()


func set_cast_shadows(enabled: bool) -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.cast_shadow = mode
	_bolt.cast_shadow = mode


## { triangles, vertices, surfaces, materials, mesh_instances, texture_px, build_ms }
static func get_stats() -> Dictionary:
	return get_model()["stats"]


func play_fire() -> void:
	_recoil = 1.0


func play_cycle(duration_s: float) -> void:
	_cycle_d = maxf(duration_s, 0.05)
	_cycle_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	_recoil = maxf(_recoil - delta * 5.0, 0.0)
	if _cycle_t >= 0.0:
		_cycle_t += delta
		if _cycle_t >= _cycle_d:
			_cycle_t = -1.0
	_apply_pose()


func _apply_pose() -> void:
	var base: Transform3D = Transform3D.IDENTITY
	if _hip:
		var hip: float = clampf(1.0 - absf(position.x) / HIP_ORIGIN.x, 0.0, 1.0)
		var rec: float = _recoil * _recoil
		var rot: Basis = Basis.from_euler(Vector3(rec * 0.15, HIP_YAW * hip + rec * 0.01, 0.0))
		var sway: Vector3 = Vector3(0.0, sin(_time * 1.7) * 0.0015 + rec * 0.018, rec * 0.07)
		base = Transform3D(Basis.IDENTITY, HIP_PIVOT + sway) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis.IDENTITY, HIP_ORIGIN - HIP_PIVOT)
	_gun.transform = base
	_muzzle.transform = base * Transform3D(Basis.IDENTITY, _v(MUZZLE_S, 0.0, 0.0))
	_ads.transform = base * Transform3D(Basis.IDENTITY, _v(0.27, SCOPE_Y, 0.0))
	var lift: float = 0.0
	var back: float = 0.0
	if _cycle_t >= 0.0:
		var t: float = _cycle_t / _cycle_d
		lift = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t))
		back = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.55, 0.85, t))
	_bolt.rotation = Vector3(0.0, 0.0, 1.05 * lift)
	_bolt.position = Vector3(0.0, 0.0, 0.085 * back)


# --- model ---------------------------------------------------------------------------------------

static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = _build_model()
	return _cache


static func _v(s: float, y: float, x: float) -> Vector3:
	return Vector3(x, y, -s)


static func _keys_of(table: Array) -> PackedVector2Array:
	var id: int = table.hash()
	if not _keys.has(id):
		var out: PackedVector2Array = PackedVector2Array()
		for k: Array in table:
			out.push_back(Vector2(k[0], k[1]))
		_keys[id] = out
	return _keys[id]


static func _fin(k: HDMesh, finish: Array, wear: float = 0.0, feature: int = 0) -> void:
	k.surface(SURF_HARD)
	k.paint(finish[0], finish[1], finish[2], wear, feature)


static func _build_model() -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var body: HDMesh = HDMesh.new()
	var bolt: HDMesh = HDMesh.new()
	_stock(body)
	_barrel(body)
	_receiver(body)
	_rail(body)
	_scope(body)
	_scope_rings(body)
	_bottom_metal(body)
	_swivels(body)
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
	var verts: int = 0
	for built: Dictionary in [built_body, built_bolt]:
		for si: int in built["surfaces"]:
			verts += (built["surfaces"][si]["pos"] as PackedVector3Array).size()
	var stats: Dictionary = {
		"triangles": body.triangle_count() + bolt.triangle_count(),
		"triangles_body": body.triangle_count(),
		"triangles_bolt": bolt.triangle_count(),
		"vertices": verts,
		"surfaces": body_mesh.get_surface_count() + bolt_mesh.get_surface_count(),
		"materials": mats.size(),
		"mesh_instances": 2,
		"texture_px": NOISE_SIZE,
		"build_ms": Time.get_ticks_msec() - t0,
	}
	return {"body": body_mesh, "bolt": bolt_mesh, "stats": stats}


static func get_materials() -> Dictionary:
	if _materials.is_empty():
		var noise: Texture2D = _noise_texture()
		var wood: ShaderMaterial = ShaderMaterial.new()
		wood.shader = WOOD_SHADER
		wood.set_shader_parameter(&"noise_tex", noise)
		var hard: ShaderMaterial = ShaderMaterial.new()
		hard.shader = HARD_SHADER
		hard.set_shader_parameter(&"noise_tex", noise)
		var lens: ShaderMaterial = ShaderMaterial.new()
		lens.shader = LENS_SHADER
		_materials = {SURF_WOOD: wood, SURF_HARD: hard, SURF_LENS: lens}
	return _materials


## One seamless RG noise texture shared by wood and metal: R = broad fbm, G = fine fbm.
static func _noise_texture() -> Texture2D:
	var broad: FastNoiseLite = FastNoiseLite.new()
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.seed = 308
	broad.frequency = 4.0 / float(NOISE_SIZE)
	broad.fractal_octaves = 4
	broad.fractal_gain = 0.5
	var fine: FastNoiseLite = FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.seed = 1911
	fine.frequency = 14.0 / float(NOISE_SIZE)
	fine.fractal_octaves = 3
	fine.fractal_gain = 0.55
	var a: PackedByteArray = broad.get_seamless_image(NOISE_SIZE, NOISE_SIZE, false, false, 0.2, true).get_data()
	var b: PackedByteArray = fine.get_seamless_image(NOISE_SIZE, NOISE_SIZE, false, false, 0.2, true).get_data()
	var step_a: int = a.size() / (NOISE_SIZE * NOISE_SIZE)
	var step_b: int = b.size() / (NOISE_SIZE * NOISE_SIZE)
	var rg: PackedByteArray = PackedByteArray()
	rg.resize(NOISE_SIZE * NOISE_SIZE * 2)
	for i in NOISE_SIZE * NOISE_SIZE:
		rg[i * 2] = a[i * step_a]
		rg[i * 2 + 1] = b[i * step_b]
	var img: Image = Image.create_from_data(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_RG8, rg)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- stock ---------------------------------------------------------------------------------------

## Cross-section of the stock at station s, scaled around its widest point (tip and pad rounding).
static func _stock_ring(s: float, scale: float = 1.0, at_s: float = -1.0) -> PackedVector3Array:
	var top: float = HDMesh.pchip(_keys_of(TOP), s)
	var bot: float = HDMesh.pchip(_keys_of(BOT), s)
	var w: float = HDMesh.pchip(_keys_of(WID), s)
	var ym: float = lerpf(top, bot, HDMesh.pchip(_keys_of(WIDEST), s))
	var nt: float = HDMesh.pchip(_keys_of(EXP_TOP), s)
	var nb: float = HDMesh.pchip(_keys_of(EXP_BOT), s)
	# Monte Carlo cheek piece on the left flank of the butt
	var cheek: float = 0.0065 * smoothstep(0.035, 0.075, s) * (1.0 - smoothstep(0.150, 0.195, s))
	var out: PackedVector3Array = PackedVector3Array()
	var zs: float = s if at_s < 0.0 else at_s
	for i in STOCK_POINTS:
		var a: float = TAU * float(i) / float(STOCK_POINTS)
		var c: float = cos(a)
		var sn: float = sin(a)
		var e: float = 2.0 / (nt if sn >= 0.0 else nb)
		var x: float = w * signf(c) * pow(absf(c), e)
		var y: float = ym + (top - ym if sn >= 0.0 else ym - bot) * signf(sn) * pow(absf(sn), e)
		if c < 0.0 and cheek > 0.0:
			x -= cheek * smoothstep(top - 0.074, top - 0.058, y) * smoothstep(0.0, 0.45, -c)
		out.push_back(_v(zs, ym + (y - ym) * scale, x * scale))
	return out


static func _stock(k: HDMesh) -> void:
	# recoil pad (rubber) and white-line spacer
	k.crease_deg = 50.0
	k.bevel_wear = 0.0
	_fin(k, RUBBER)
	k.loft([_stock_ring(0.025, 0.93, 0.0), _stock_ring(0.025, 0.985, 0.0035), _stock_ring(0.025, 1.003, 0.008), _stock_ring(0.025, 1.003, 0.0215)], true, false)
	_fin(k, SPACER)
	k.loft([_stock_ring(0.025, 1.003, 0.0215), _stock_ring(0.025, 1.003, 0.025)], false, false)
	# wood
	k.surface(SURF_WOOD)
	k.paint(Color.WHITE, 0.0, 0.3)
	var rings: Array = []
	var s: float = 0.025
	while s < 0.160:
		rings.append(_stock_ring(s))
		s += 0.0225
	s = 0.160
	while s < 0.356:
		rings.append(_stock_ring(s))
		s += 0.0075
	s = 0.36
	while s < 0.785:
		rings.append(_stock_ring(s))
		s += 0.0305
	for t: float in [0.0, 0.35, 0.62, 0.82, 0.94, 1.0]:
		rings.append(_stock_ring(0.79 + 0.024 * t, sqrt(1.0 - t * t * 0.97)))
	k.crease_deg = 60.0
	k.loft(rings, false, true)
	k.crease_deg = 50.0


# --- barrel and action ---------------------------------------------------------------------------

static func _barrel(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, BLUED)
	k.lathe([
		Vector3(0.530, 0.0152, 0), Vector3(0.553, 0.0152, 0), Vector3(0.566, 0.0139, 0), Vector3(0.586, 0.0126, 0),
		Vector3(0.615, 0.0117, 0), Vector3(0.66, 0.0111, 0), Vector3(0.85, 0.0100, 0), Vector3(1.0985, 0.0089, 0),
		Vector3(1.1000, 0.0079, 0), Vector3(1.1000, 0.0066, 0), Vector3(1.0975, 0.0050, 0), Vector3(1.0975, 0.0039, 0)],
		20, Vector3.ZERO, FWD)
	_fin(k, VOID)
	k.lathe([Vector3(1.0975, 0.0039, 0), Vector3(1.075, 0.0039, 0), Vector3(1.075, 0.0, 0)], 12, Vector3.ZERO, FWD)


static func _receiver(k: HDMesh) -> void:
	k.bevel_wear = 0.9
	_fin(k, BLUED)
	# rings 2..6 of 24 = 30..105 degrees from the top toward the right: ejection port
	var profile: Array = [
		Vector3(0.345, 0.0095, 0), Vector3(0.345, 0.0162, 0), Vector3(0.3462, RECV_R, 0), Vector3(0.418, RECV_R, 0),
		Vector3(0.494, RECV_R, 0), Vector3(0.5338, RECV_R, 0), Vector3(0.535, 0.0162, 0), Vector3(0.535, 0.0150, 0)]
	var port: Callable = func(ring: int, seg: int) -> bool: return ring == 3 and seg >= 2 and seg <= 6
	k.lathe(profile, 24, Vector3.ZERO, FWD, Vector3.UP, port, 0.0093)
	# dark raceway, only seen through the port while the bolt is drawn back
	_fin(k, VOID)
	k.lathe([Vector3(0.500, 0.0092, 0), Vector3(0.345, 0.0092, 0)], 12, Vector3.ZERO, FWD)
	# magazine follower: hides the stock under the open action
	_fin(k, STEEL_DARK)
	k.cbox(_v(0.455, -0.0030, 0.0), Vector3(0.0165, 0.0014, 0.0860), 0.0004)
	_fin(k, BLUED)
	# bolt stop on the left flank, gas vent
	k.cbox(_v(0.368, 0.0035, -0.0172), Vector3(0.0045, 0.0075, 0.030), 0.0012)
	_fin(k, VOID)
	k.lathe([Vector3(0.01735, 0.0015, 0), Vector3(0.01735, 0.0, 0)], 8, _v(0.515, 0.0, 0.0), Vector3.LEFT, Vector3.UP)
	# roll mark on the left flank: engine font turned into geometry and wrapped on the receiver
	k.paint(Color(0.66, 0.63, 0.52), 0.0, 0.55)
	_roll_mark(k, ".308 WIN", 0.478, 0.0042, RECV_R + 0.00012, deg_to_rad(8.0))
	# tang behind the action, following the wrist
	_fin(k, BLUED)
	var side: Transform3D = _side_frame()
	k.extrude(PackedVector2Array([
		Vector2(0.2960, -0.0370), Vector2(0.346, -0.0140), Vector2(0.346, -0.0045), Vector2(0.330, -0.0092),
		Vector2(0.312, -0.0185), Vector2(0.3000, -0.0262), Vector2(0.2960, -0.0282)]), side, -0.0055, 0.0055, 0.0010)
	# safety lever on the right of the tang
	_fin(k, BLUED_SATIN)
	k.cbox(_v(0.318, -0.0085, 0.0098), Vector3(0.0045, 0.0050, 0.016), 0.001)
	_fin(k, STEEL_DARK)
	k.lathe([Vector3(0.0, 0.0, 0), Vector3(0.0, 0.0032, 0), Vector3(0.006, 0.0032, 0.0006), Vector3(0.0066, 0.0024, 0), Vector3(0.0066, 0.0, 0)], 12, _v(0.312, -0.0075, 0.0105), Vector3.UP, FWD)


## Text as flat geometry bent around the bore axis on the left side of a cylinder of radius r.
## `s_mid` = station of the text centre, `height` = cap height, `lift` = angle above horizontal.
static func _roll_mark(k: HDMesh, text: String, s_mid: float, height: float, r: float, lift: float) -> void:
	var tm: TextMesh = TextMesh.new()
	tm.text = text
	tm.font_size = 32
	tm.pixel_size = height / 23.0
	tm.depth = 0.0
	tm.curve_step = 9.0
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if tm.get_surface_count() == 0:
		return
	var arrays: Array = tm.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	k.begin_part()
	for i in range(0, idx.size(), 3):
		# keep the front faces only (text plane facing +Z)
		if normals[idx[i]].z < 0.5:
			continue
		var p: Array[Vector3] = []
		for j in 3:
			var v: Vector3 = verts[idx[i + j]]
			var ang: float = lift + v.y / r
			# reads from the muzzle toward the butt when looking at the left side
			p.append(Vector3(-cos(ang) * r, sin(ang) * r, -s_mid + v.x))
		k.tri(p[0], p[1], p[2], Vector3.LEFT)


## Frame whose XY plane is the side view (x = s, y = y) and whose Z axis is the shooter's right.
static func _side_frame() -> Transform3D:
	return Transform3D(Basis(FWD, Vector3.UP, Vector3.RIGHT), Vector3.ZERO)


static func _rail(k: HDMesh) -> void:
	k.bevel_wear = 0.8
	_fin(k, BLUED_SATIN)
	var s0: float = 0.347
	var s1: float = 0.533
	var yb: float = 0.0148
	var yt: float = 0.0245
	var pitch: float = 0.0124
	var slot: float = 0.0056
	var depth: float = 0.0032
	var poly: PackedVector2Array = PackedVector2Array([Vector2(s0, yb), Vector2(s1, yb), Vector2(s1, yt)])
	var sa: float = s1 - 0.0062
	while sa - slot > s0 + 0.004:
		poly.push_back(Vector2(sa, yt))
		poly.push_back(Vector2(sa, yt - depth))
		poly.push_back(Vector2(sa - slot, yt - depth))
		poly.push_back(Vector2(sa - slot, yt))
		sa -= pitch
	poly.push_back(Vector2(s0, yt))
	k.extrude(poly, _side_frame(), -0.0106, 0.0106, 0.0017)


# --- scope ---------------------------------------------------------------------------------------

static func _scope(k: HDMesh) -> void:
	var o: Vector3 = _v(0.0, SCOPE_Y, 0.0)
	k.bevel_wear = 0.0
	# rubber eyecup
	_fin(k, RUBBER)
	k.lathe([
		Vector3(0.2915, 0.0176, 0), Vector3(0.2852, 0.0182, 0), Vector3(0.2845, 0.0190, 0), Vector3(0.2845, 0.0206, 0),
		Vector3(0.2857, 0.0214, 0), Vector3(0.2972, 0.0214, 0), Vector3(0.2978, 0.0204, 0)], SCOPE_SEGS, o, FWD)
	# main body: eyepiece, tube, objective bell
	k.bevel_wear = 0.55
	_fin(k, SCOPE_BLACK)
	k.lathe([
		Vector3(0.2978, 0.0204, 0), Vector3(0.3360, 0.0204, 0), Vector3(0.3385, 0.0196, 0)], SCOPE_SEGS, o, FWD)
	# magnification marks on the taper behind the zoom ring (same smoothing island)
	_fin(k, SCOPE_BLACK, 0.0, 1)
	k.lathe([Vector3(0.3385, 0.0196, 0), Vector3(0.3490, 0.0182, 0)], SCOPE_SEGS, o, FWD, Vector3.UP, Callable(), 0.0, false)
	_fin(k, SCOPE_BLACK)
	k.lathe([
		Vector3(0.3490, 0.0182, 0), Vector3(0.3680, 0.0182, 0), Vector3(0.3765, 0.0153, 0), Vector3(0.3790, 0.0150, 0),
		Vector3(0.4480, 0.0150, 0), Vector3(0.4492, 0.0168, 0), Vector3(0.4515, 0.0183, 0), Vector3(0.4550, 0.0191, 0),
		Vector3(0.4850, 0.0191, 0), Vector3(0.4885, 0.0183, 0), Vector3(0.4908, 0.0168, 0), Vector3(0.4920, 0.0150, 0),
		Vector3(0.5500, 0.0150, 0),
		Vector3(0.5560, 0.0160, 0), Vector3(0.5900, 0.0280, 0), Vector3(0.5950, 0.0295, 0), Vector3(0.6380, 0.0295, 0),
		Vector3(0.6400, 0.0288, 0), Vector3(0.6408, 0.0278, 0), Vector3(0.6408, 0.0270, 0), Vector3(0.6290, 0.0267, 0)],
		SCOPE_SEGS, o, FWD, Vector3.UP, Callable(), 0.0, false)
	# eyepiece lock ring and zoom ring (serrated)
	k.crease_deg = 35.0
	_fin(k, SCOPE_GLOSS)
	k.lathe([Vector3(0.2996, 0.0203, 0), Vector3(0.3001, 0.0212, 0.0006), Vector3(0.3068, 0.0212, 0.0006), Vector3(0.3073, 0.0203, 0)], 48, o, FWD)
	k.lathe([Vector3(0.3492, 0.0181, 0), Vector3(0.3498, 0.0196, 0.0009), Vector3(0.3672, 0.0196, 0.0009), Vector3(0.3678, 0.0181, 0)], 40, o, FWD)
	k.crease_deg = 50.0
	k.cbox(_v(0.3585, SCOPE_Y + 0.0207, 0.0), Vector3(0.0062, 0.0042, 0.0085), 0.0012)
	# turrets on the saddle
	_turret(k, _v(0.470, SCOPE_Y, 0.0), Vector3.UP, FWD, 0.0126, 0.0165)
	_turret(k, _v(0.470, SCOPE_Y, 0.0), Vector3.RIGHT, FWD, 0.0126, 0.0165)
	_turret(k, _v(0.470, SCOPE_Y, 0.0), Vector3.LEFT, FWD, 0.0148, 0.0105)
	# lenses
	k.surface(SURF_LENS)
	k.paint(Color.WHITE, 0.0, 0.05)
	var ocular: Array = []
	var objective: Array = []
	for j in 4:
		var f: float = float(j) / 3.0
		ocular.append(Vector3(0.2912 - 0.0018 * (1.0 - f * f), 0.0177 * f, 0))
		objective.append(Vector3(-(0.6290 + 0.0036 * (1.0 - f * f)), 0.0268 * f, 0))
	k.lathe(ocular, SCOPE_SEGS, o, FWD)
	k.lathe(objective, SCOPE_SEGS, o, -FWD)


## Dial turret growing from `origin` (on the scope axis) along `axis`.
static func _turret(k: HDMesh, origin: Vector3, axis: Vector3, up_ref: Vector3, radius: float, height: float) -> void:
	var t0: float = 0.0175
	k.bevel_wear = 0.6
	_fin(k, SCOPE_BLACK)
	k.lathe([Vector3(t0, radius - 0.0022, 0), Vector3(t0 + 0.0036, radius - 0.0022, 0), Vector3(t0 + 0.0036, radius - 0.0006, 0)], 18, origin, axis, up_ref)
	_fin(k, SCOPE_BLACK, 0.0, 1)
	k.lathe([Vector3(t0 + 0.0036, radius - 0.0006, 0), Vector3(t0 + 0.0086, radius - 0.0006, 0)], 18, origin, axis, up_ref)
	k.crease_deg = 35.0
	_fin(k, SCOPE_GLOSS)
	var top: float = t0 + 0.0086 + height
	k.lathe([
		Vector3(t0 + 0.0086, radius - 0.0006, 0), Vector3(t0 + 0.0090, radius + 0.0004, 0.0010), Vector3(top - 0.0014, radius + 0.0004, 0.0010),
		Vector3(top, radius - 0.0014, 0), Vector3(top, radius - 0.0045, 0), Vector3(top + 0.0006, radius - 0.0051, 0), Vector3(top + 0.0006, 0.0, 0)],
		36, origin, axis, up_ref)
	k.crease_deg = 50.0


static func _scope_rings(k: HDMesh) -> void:
	var o: Vector3 = _v(0.0, SCOPE_Y, 0.0)
	for sc: float in [0.400, 0.518]:
		k.bevel_wear = 0.75
		_fin(k, BLUED_SATIN)
		k.lathe([
			Vector3(sc - 0.008, 0.0150, 0), Vector3(sc - 0.008, 0.0187, 0), Vector3(sc - 0.0069, 0.0197, 0),
			Vector3(sc + 0.0069, 0.0197, 0), Vector3(sc + 0.008, 0.0187, 0), Vector3(sc + 0.008, 0.0150, 0)], 20, o, FWD)
		# split flanges (upper and lower half) with cap screws
		for sx: float in [-1.0, 1.0]:
			k.cbox(_v(sc, SCOPE_Y + 0.0026, sx * 0.0222), Vector3(0.0082, 0.0044, 0.0148), 0.0009)
			k.cbox(_v(sc, SCOPE_Y - 0.0026, sx * 0.0222), Vector3(0.0082, 0.0044, 0.0148), 0.0009)
			for ds: float in [-0.0042, 0.0042]:
				_screw(k, _v(sc + ds, SCOPE_Y + 0.0046, sx * 0.0228), Vector3.UP, 0.0021, 0.0013)
		# base clamp down to the rail, with its cross bolt
		_fin(k, BLUED_SATIN)
		k.cbox(_v(sc, 0.0290, 0.0), Vector3(0.0262, 0.0140, 0.0150), 0.0016)
		_fin(k, STEEL_DARK)
		k.crease_deg = 30.0
		k.lathe([Vector3(0.0128, 0.0, 0), Vector3(0.0128, 0.0046, 0), Vector3(0.0162, 0.0046, 0), Vector3(0.0168, 0.0040, 0), Vector3(0.0168, 0.0, 0)], 6, _v(sc, 0.0222, 0.0), Vector3.LEFT, Vector3.UP)
		k.crease_deg = 50.0
		_screw(k, _v(sc, 0.0222, 0.0128), Vector3.RIGHT, 0.0026, 0.0014)


## Socket head cap screw: hex-ish head with a dark recess.
static func _screw(k: HDMesh, origin: Vector3, axis: Vector3, radius: float, height: float) -> void:
	var up_ref: Vector3 = FWD if absf(axis.dot(FWD)) < 0.5 else Vector3.UP
	var wear: float = k.bevel_wear
	k.bevel_wear = 0.0
	_fin(k, STEEL_DARK)
	k.lathe([Vector3(0.0, radius, 0), Vector3(height, radius, 0), Vector3(height, radius * 0.55, 0)], 8, origin, axis, up_ref)
	_fin(k, VOID)
	k.lathe([Vector3(height, radius * 0.55, 0), Vector3(height * 0.3, radius * 0.5, 0), Vector3(height * 0.3, 0.0, 0)], 6, origin, axis, up_ref)
	k.bevel_wear = wear


# --- trigger group, floor plate, swivels ------------------------------------------------------------

static func _bottom_metal(k: HDMesh) -> void:
	k.bevel_wear = 0.85
	_fin(k, BLUED)
	# trigger guard bow: flat strap swept along a loop in the side plane
	var loop: Array = HDMesh.smooth_path([
		_v(0.3170, -0.0590, 0.0), _v(0.3215, -0.0690, 0.0), _v(0.3270, -0.0810, 0.0), _v(0.3370, -0.0895, 0.0),
		_v(0.3520, -0.0930, 0.0), _v(0.3690, -0.0925, 0.0), _v(0.3830, -0.0880, 0.0), _v(0.3925, -0.0780, 0.0),
		_v(0.3975, -0.0650, 0.0), _v(0.4000, -0.0535, 0.0)], 2)
	var wear: float = k.get_wear()
	k.set_wear(0.35)
	k.sweep(loop, HDMesh.rect_section(0.0130, 0.0034, 0.0010), Vector3.RIGHT)
	k.set_wear(wear)
	# floor plate, latch, front guard screw
	k.cbox(_v(0.4575, -0.0535, 0.0), Vector3(0.0270, 0.0036, 0.1180), 0.0012)
	k.cbox(_v(0.3940, -0.0610, 0.0), Vector3(0.0070, 0.0080, 0.0050), 0.0012)
	_fin(k, STEEL_DARK)
	k.lathe([Vector3(0.0, 0.0042, 0), Vector3(0.0012, 0.0042, 0), Vector3(0.0018, 0.0036, 0), Vector3(0.0018, 0.0, 0)], 12, _v(0.5270, -0.0512, 0.0), Vector3.DOWN, FWD)
	_fin(k, VOID)
	k.cbox(_v(0.5270, -0.0531, 0.0), Vector3(0.0010, 0.0008, 0.0070), 0.0)
	# trigger blade
	_fin(k, STEEL)
	var blade: Array = HDMesh.smooth_path([
		_v(0.3565, -0.0540, 0.0), _v(0.3548, -0.0640, 0.0), _v(0.3552, -0.0730, 0.0), _v(0.3580, -0.0800, 0.0), _v(0.3618, -0.0845, 0.0)], 2)
	var widths: PackedFloat32Array = PackedFloat32Array()
	for i in blade.size():
		widths.push_back(lerpf(1.0, 0.72, float(i) / float(blade.size() - 1)))
	k.sweep(blade, HDMesh.rect_section(0.0062, 0.0036, 0.0010), Vector3.RIGHT, widths)


static func _swivels(k: HDMesh) -> void:
	k.bevel_wear = 0.6
	for spot: Array in [[0.725, 0.0], [0.072, 0.0]]:
		var s: float = spot[0]
		var y: float = HDMesh.pchip(_keys_of(BOT), s)
		_fin(k, BLUED)
		k.lathe([Vector3(-0.002, 0.0034, 0), Vector3(0.0030, 0.0034, 0), Vector3(0.0040, 0.0026, 0), Vector3(0.0090, 0.0026, 0), Vector3(0.0098, 0.0018, 0), Vector3(0.0098, 0.0, 0)], 10, _v(s, y, 0.0), Vector3.DOWN, FWD)
		# hanging loop: rounded rectangle in the plane across the bore
		var loop: Array = []
		var half_w: float = 0.0150
		var half_h: float = 0.0100
		var yc: float = y - 0.0062 - half_h
		for i in 16:
			var ang: float = TAU * float(i) / 16.0
			var cx: float = signf(cos(ang)) * pow(absf(cos(ang)), 0.5)
			var cy: float = signf(sin(ang)) * pow(absf(sin(ang)), 0.5)
			loop.append(_v(s, yc + cy * half_h, cx * half_w))
		k.set_wear(0.25)
		k.sweep(loop, HDMesh.circle_section(0.0013, 5), FWD, PackedFloat32Array(), true)
		k.set_wear(0.0)


# --- bolt (separate mesh: rotates about the bore axis and slides back) -------------------------------

static func _bolt_parts(k: HDMesh) -> void:
	k.bevel_wear = 0.0
	# body seen through the ejection port, handle root collar
	_fin(k, STEEL)
	k.lathe([Vector3(0.345, 0.0090, 0), Vector3(0.500, 0.0090, 0)], 16, Vector3.ZERO, FWD)
	k.lathe([Vector3(0.3300, 0.0100, 0), Vector3(0.3300, 0.0120, 0), Vector3(0.3310, 0.0129, 0), Vector3(0.3440, 0.0129, 0), Vector3(0.3450, 0.0120, 0)], 20, Vector3.ZERO, FWD)
	# shroud and cocking piece
	k.bevel_wear = 0.8
	_fin(k, BLUED)
	k.lathe([
		Vector3(0.2960, 0.0, 0), Vector3(0.2960, 0.0058, 0), Vector3(0.2975, 0.0082, 0), Vector3(0.3020, 0.0104, 0),
		Vector3(0.3120, 0.0118, 0), Vector3(0.3290, 0.0123, 0), Vector3(0.3300, 0.0115, 0)], 20, Vector3.ZERO, FWD)
	_fin(k, STEEL_DARK)
	k.lathe([Vector3(0.2925, 0.0, 0), Vector3(0.2925, 0.0019, 0), Vector3(0.2932, 0.0025, 0), Vector3(0.2962, 0.0025, 0)], 10, Vector3.ZERO, FWD)
	# handle: swept bar down and back to the ball knob
	_fin(k, STEEL)
	var path: Array = HDMesh.smooth_path([
		_v(0.3375, 0.0000, 0.0085), _v(0.3375, -0.0015, 0.0200), _v(0.3372, -0.0068, 0.0305), _v(0.3362, -0.0160, 0.0400),
		_v(0.3348, -0.0270, 0.0470), _v(0.3338, -0.0350, 0.0515)], 2)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in path.size():
		radii.push_back(lerpf(1.0, 0.74, float(i) / float(path.size() - 1)))
	k.crease_deg = 80.0
	k.sweep(path, HDMesh.circle_section(0.0060, 10), FWD, radii)
	k.crease_deg = 180.0
	k.sphere(_v(0.3335, -0.0375, 0.0535), Vector3.ONE * 0.0110, 16, 9)
	k.crease_deg = 50.0
