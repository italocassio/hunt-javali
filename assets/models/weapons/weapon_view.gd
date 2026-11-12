extends WeaponViewBase
## First-person weapon + arms, procedural. One script for the five weapons; setup(weapon_id) picks the model.
## Camera space, looking -Z. At position (0,0,0) the weapon sits at hip position (lower right).
## Nodes: Gun (animated) > Body, Mover (bolt / pump), RightArm, LeftArm, plus Muzzle + AdsAnchor at the root.

const X: float = 0.20
const HIP_YAW: float = 0.19   # ~11 degrees
const PIVOT: Vector3 = Vector3(0.20, -0.22, -0.30)

const WOOD: Color = Color(0.52, 0.35, 0.20)
const WOOD_RED: Color = Color(0.58, 0.25, 0.14)
const WOOD_LIGHT: Color = Color(0.62, 0.50, 0.34)
const SYNTH: Color = Color(0.20, 0.21, 0.24)
const WOOD_DARK: Color = Color(0.30, 0.20, 0.14)
const METAL: Color = Color(0.30, 0.32, 0.36)
const METAL_LIGHT: Color = Color(0.52, 0.54, 0.58)
const SLEEVE: Color = Color(0.34, 0.39, 0.22)
const SLEEVE_LIGHT: Color = Color(0.42, 0.47, 0.28)
const SKIN: Color = Color(0.80, 0.60, 0.45)

static var _cache: Dictionary = {}
static var _flash_tex: GradientTexture2D = null

## Set by each <weapon_id>_view.tscn so the scene shows its model even before setup() is called.
@export var weapon_id: StringName = &""

var _gun: Node3D
var _body: MeshInstance3D
var _mover: MeshInstance3D
var _rarm: MeshInstance3D
var _larm: MeshInstance3D
var _muzzle: Marker3D
var _ads: Marker3D
var _flash: Sprite3D

var _flash_t: float = 0.0
var _recoil: float = 0.0
var _cycle_t: float = -1.0
var _cycle_d: float = 0.0
var _reload_t: float = -1.0
var _reload_d: float = 0.0
var _draw_t: float = -1.0
var _draw_d: float = 0.0
var _time: float = 0.0
var _kind: StringName = &"bolt"
var _recoil_kick: float = 0.06


func _init() -> void:
	_gun = Node3D.new()
	_gun.name = "Gun"
	add_child(_gun)
	_body = _mi("Body")
	_mover = _mi("Mover")
	_rarm = _mi("RightArm")
	_larm = _mi("LeftArm")
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(X, -0.19, -1.25)
	add_child(_muzzle)
	_ads = Marker3D.new()
	_ads.name = "AdsAnchor"
	_ads.position = Vector3(X, -0.15, -0.6)
	add_child(_ads)
	_flash = Sprite3D.new()
	_flash.name = "Flash"
	_flash.texture = _get_flash_texture()
	_flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.shaded = false
	_flash.double_sided = true
	_flash.transparent = true
	_flash.no_depth_test = false
	_flash.modulate = Color(1.0, 0.85, 0.5, 1.0)
	_flash.pixel_size = 0.004
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_flash.material_override = _flash_material()
	_muzzle.add_child(_flash)


func _ready() -> void:
	if _body.mesh == null:
		setup(weapon_id if weapon_id != &"" else &"carbine_22")


func _mi(node_name: String) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(m)
	return m


static var _flash_mat: StandardMaterial3D = null


static func _flash_material() -> StandardMaterial3D:
	if _flash_mat == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _get_flash_texture()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		_flash_mat = m
	return _flash_mat


static func _get_flash_texture() -> GradientTexture2D:
	if _flash_tex == null:
		var g: Gradient = Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 0.9, 1), Color(1.0, 0.8, 0.35, 0.95), Color(1.0, 0.5, 0.1, 0.4), Color(1.0, 0.4, 0.0, 0.0)])
		var t: GradientTexture2D = GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_flash_tex = t
	return _flash_tex


# --- model building ---------------------------------------------------------------------------

func setup(id: StringName) -> void:
	weapon_id = id
	var key: String = String(id)
	if not _cache.has(key):
		_cache[key] = _build_model(id)
	var model: Dictionary = _cache[key]
	_body.mesh = model["body"]
	_mover.mesh = model["mover"]
	_rarm.mesh = model["rarm"]
	_larm.mesh = model["larm"]
	_muzzle.position = model["muzzle"]
	_ads.position = model["ads"]
	_kind = model["kind"]
	_recoil_kick = model["kick"]
	_flash.pixel_size = model["flash_size"]
	_mover_rest = model["mover_rest"]
	_apply_pose(0.0)


var _mover_rest: Vector3 = Vector3.ZERO


func _build_model(id: StringName) -> Dictionary:
	var body: MeshKit = MeshKit.new()
	var mover: MeshKit = MeshKit.new()
	var info: Dictionary = {}
	match id:
		&"shotgun_12": info = _shotgun(body, mover)
		&"rifle_308": info = _rifle_308(body, mover)
		&"rifle_3006": info = _rifle_3006(body, mover)
		&"rifle_338": info = _rifle_338(body, mover)
		_: info = _carbine(body, mover)
	var rk: MeshKit = MeshKit.new()
	var lk: MeshKit = MeshKit.new()
	_arm(rk, Vector3(0.40, -0.62, 0.10), info["rhand"], true)
	_arm(lk, Vector3(-0.12, -0.60, 0.05), info["lhand"], false)
	return {
		"body": body.build(), "mover": mover.build(), "rarm": rk.build(), "larm": lk.build(),
		"muzzle": info["muzzle"], "ads": info["ads"], "kind": info["kind"], "kick": info["kick"],
		"flash_size": info["flash"], "mover_rest": Vector3.ZERO,
	}


## Cylinder along -Z from z_start (back) to z_end (front).
static func _cyl_z(k: MeshKit, y: float, z_start: float, z_end: float, r0: float, r1: float, sides: int, c0: Color, c1: Color, x: float = X, cap: bool = true) -> void:
	k.set_xf(Vector3(x, y, z_start), Vector3(-90, 0, 0))
	k.frustum(Vector3.ZERO, r0, r1, z_start - z_end, sides, c0, c1, cap, cap)
	k.reset_xf()


static func _stock(k: MeshKit, stations: Array, col: Color) -> void:
	var st: Array = []
	for s in stations:
		st.append([s[0], s[1] / 0.7071, s[2], s[3]])
	k.set_xf(Vector3(X, 0.0, 0.0))
	k.loft(st, 4, MeshKit.shade(col, 0.75), col, true, true)
	k.reset_xf()


static func _arm(k: MeshKit, shoulder: Vector3, wrist: Vector3, right: bool) -> void:
	var dir: Vector3 = wrist - shoulder
	var length: float = dir.length()
	dir = dir / length
	var q: Quaternion = Quaternion(Vector3.UP, dir)
	k.xf = Transform3D(Basis(q), shoulder)
	k.frustum(Vector3.ZERO, 0.068, 0.050, length * 0.84, 6, SLEEVE, SLEEVE_LIGHT, true, false)
	k.frustum(Vector3(0, length * 0.84, 0), 0.054, 0.052, length * 0.09, 6, Color(0.20, 0.23, 0.13), Color(0.20, 0.23, 0.13), true, false)
	k.reset_xf()
	# hand
	if right:
		k.box(wrist + Vector3(0.0, -0.01, 0.0), Vector3(0.062, 0.075, 0.09), SKIN, MeshKit.shade(SKIN, 1.08))
		k.box(wrist + Vector3(-0.005, 0.02, -0.055), Vector3(0.05, 0.03, 0.05), SKIN)
		k.box(wrist + Vector3(0.0, -0.045, -0.04), Vector3(0.055, 0.03, 0.06), MeshKit.shade(SKIN, 0.9))
	else:
		k.box(wrist + Vector3(0.0, -0.025, 0.0), Vector3(0.085, 0.05, 0.10), SKIN, MeshKit.shade(SKIN, 1.08))
		k.box(wrist + Vector3(0.03, 0.015, -0.01), Vector3(0.035, 0.03, 0.08), SKIN)
		k.box(wrist + Vector3(0.0, 0.025, -0.07), Vector3(0.07, 0.02, 0.05), MeshKit.shade(SKIN, 0.9))


static func _grip_box(k: MeshKit, y0: float, y1: float, z0: float, z1: float, w: float, col: Color, x: float = X) -> void:
	k.box(Vector3(x, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(w, absf(y1 - y0), absf(z1 - z0)), col)


func _carbine(body: MeshKit, mover: MeshKit) -> Dictionary:
	# slim and light: pale wood, short thin barrel, open sights, no scope
	_stock(body, [[-0.38, 0.018, -0.29, -0.17], [-0.40, 0.016, -0.265, -0.18], [-0.52, 0.015, -0.245, -0.185], [-0.60, 0.015, -0.238, -0.188]], WOOD_LIGHT)
	_grip_box(body, -0.228, -0.172, -0.60, -0.78, 0.030, METAL)
	_cyl_z(body, -0.195, -0.78, -1.08, 0.009, 0.008, 6, METAL, METAL_LIGHT)
	_grip_box(body, -0.236, -0.205, -0.72, -0.98, 0.028, WOOD_LIGHT)
	_grip_box(body, -0.256, -0.236, -0.58, -0.66, 0.010, METAL)
	_grip_box(body, -0.166, -0.150, -0.70, -0.73, 0.022, METAL_LIGHT)      # rear sight leaf
	_grip_box(body, -0.186, -0.162, -1.05, -1.07, 0.008, METAL_LIGHT)      # front post
	mover.box(Vector3(X + 0.025, -0.19, -0.66), Vector3(0.025, 0.009, 0.012), METAL_LIGHT)
	return {"muzzle": Vector3(X, -0.195, -1.08), "ads": Vector3(X, -0.155, -0.715), "kind": &"carbine", "kick": 0.04, "flash": 0.003,
		"rhand": Vector3(X, -0.245, -0.55), "lhand": Vector3(X, -0.25, -0.86)}


func _shotgun(body: MeshKit, mover: MeshKit) -> Dictionary:
	# fat barrel with a magazine tube under it and a big pump slide; no scope
	_stock(body, [[-0.38, 0.026, -0.315, -0.14], [-0.40, 0.024, -0.285, -0.155], [-0.52, 0.022, -0.262, -0.168], [-0.60, 0.021, -0.252, -0.175]], WOOD_DARK)
	_grip_box(body, -0.245, -0.150, -0.60, -0.86, 0.050, METAL)
	_cyl_z(body, -0.178, -0.86, -1.30, 0.024, 0.023, 8, METAL, METAL_LIGHT)
	_cyl_z(body, -0.228, -0.86, -1.22, 0.017, 0.017, 6, METAL_LIGHT, METAL_LIGHT)
	_grip_box(body, -0.272, -0.245, -0.64, -0.74, 0.012, METAL)
	_grip_box(body, -0.138, -0.124, -1.28, -1.30, 0.010, Color(0.9, 0.85, 0.6))   # bead sight
	mover.box(Vector3(X, -0.235, -1.0), Vector3(0.070, 0.070, 0.30), WOOD, WOOD_DARK)
	return {"muzzle": Vector3(X, -0.178, -1.30), "ads": Vector3(X, -0.142, -0.9), "kind": &"pump", "kick": 0.09, "flash": 0.0065,
		"rhand": Vector3(X, -0.255, -0.57), "lhand": Vector3(X, -0.262, -1.0)}


func _scope(k: MeshKit, y: float, z_eye: float, length: float, r: float, obj_r: float) -> void:
	var tube: Color = Color(0.20, 0.21, 0.24)
	_cyl_z(k, y, z_eye, z_eye - 0.07, r * 1.25, r * 1.1, 8, tube, tube)
	_cyl_z(k, y, z_eye - 0.07, z_eye - length + 0.08, r, r, 8, METAL, METAL_LIGHT, X, false)
	_cyl_z(k, y, z_eye - length + 0.08, z_eye - length, r * 1.1, obj_r, 8, tube, tube)
	_grip_box(k, y - 0.04, y - 0.012, z_eye - 0.10, z_eye - 0.14, 0.018, METAL)
	_grip_box(k, y - 0.04, y - 0.012, z_eye - length + 0.14, z_eye - length + 0.18, 0.018, METAL)
	_grip_box(k, y + r * 0.8, y + r * 1.6, z_eye - length * 0.5, z_eye - length * 0.5 - 0.03, 0.02, METAL_LIGHT)


func _rifle_308(body: MeshKit, mover: MeshKit) -> Dictionary:
	# bolt action: medium scope, big bolt handle sticking out of the right side
	_stock(body, [[-0.38, 0.022, -0.30, -0.14], [-0.40, 0.020, -0.28, -0.15], [-0.55, 0.018, -0.255, -0.165], [-0.64, 0.017, -0.24, -0.175]], WOOD)
	_grip_box(body, -0.235, -0.165, -0.64, -0.88, 0.040, METAL)
	_cyl_z(body, -0.19, -0.88, -1.35, 0.0145, 0.012, 7, METAL, METAL_LIGHT)
	_grip_box(body, -0.246, -0.205, -0.84, -1.14, 0.038, WOOD)
	_grip_box(body, -0.268, -0.243, -0.62, -0.70, 0.012, METAL)
	_scope(body, -0.125, -0.54, 0.44, 0.013, 0.021)
	mover.box(Vector3(X + 0.06, -0.19, -0.72), Vector3(0.10, 0.014, 0.016), METAL_LIGHT)
	mover.ellipsoid(Vector3(X + 0.125, -0.19, -0.72), Vector3(0.028, 0.028, 0.028), 5, 3, METAL_LIGHT)
	return {"muzzle": Vector3(X, -0.19, -1.35), "ads": Vector3(X, -0.125, -0.52), "kind": &"bolt", "kick": 0.07, "flash": 0.0045,
		"rhand": Vector3(X, -0.255, -0.60), "lhand": Vector3(X, -0.262, -0.98)}


func _rifle_3006(body: MeshKit, mover: MeshKit) -> Dictionary:
	# semi-auto: long handguard, obvious detachable magazine, short low scope
	_stock(body, [[-0.38, 0.023, -0.31, -0.145], [-0.40, 0.021, -0.285, -0.155], [-0.52, 0.019, -0.26, -0.168], [-0.62, 0.018, -0.245, -0.178]], WOOD_RED)
	_grip_box(body, -0.24, -0.16, -0.62, -0.90, 0.043, METAL)
	_cyl_z(body, -0.19, -0.90, -1.36, 0.0135, 0.0115, 7, METAL, METAL_LIGHT)
	_grip_box(body, -0.248, -0.192, -0.88, -1.27, 0.044, Color(0.42, 0.45, 0.50))
	for zz: float in [-0.96, -1.04, -1.12, -1.20]:
		_grip_box(body, -0.236, -0.206, zz, zz - 0.04, 0.047, Color(0.12, 0.12, 0.14))   # vent slots
	_cyl_z(body, -0.158, -0.95, -1.22, 0.0075, 0.0075, 5, METAL_LIGHT, METAL_LIGHT)
	_grip_box(body, -0.40, -0.24, -0.69, -0.84, 0.036, Color(0.66, 0.60, 0.40))         # detachable box magazine, hangs low
	_grip_box(body, -0.268, -0.243, -0.64, -0.72, 0.012, METAL)
	_scope(body, -0.118, -0.56, 0.17, 0.017, 0.027)
	mover.box(Vector3(X + 0.03, -0.185, -0.78), Vector3(0.028, 0.014, 0.05), METAL_LIGHT)
	return {"muzzle": Vector3(X, -0.19, -1.36), "ads": Vector3(X, -0.118, -0.54), "kind": &"semi", "kick": 0.065, "flash": 0.005,
		"rhand": Vector3(X, -0.255, -0.60), "lhand": Vector3(X, -0.262, -1.02)}


func _rifle_338(body: MeshKit, mover: MeshKit) -> Dictionary:
	# the biggest: dark synthetic stock, heavy long barrel with muzzle brake, large scope
	_stock(body, [[-0.38, 0.030, -0.325, -0.13], [-0.40, 0.027, -0.292, -0.145], [-0.55, 0.023, -0.262, -0.160], [-0.66, 0.021, -0.246, -0.170]], SYNTH)
	_grip_box(body, -0.245, -0.158, -0.66, -0.93, 0.048, METAL)
	_cyl_z(body, -0.19, -0.93, -1.46, 0.029, 0.026, 8, METAL, METAL_LIGHT)
	_cyl_z(body, -0.245, -1.00, -1.32, 0.009, 0.009, 5, METAL_LIGHT, METAL_LIGHT)       # folded bipod
	_grip_box(body, -0.172, -0.140, -0.36, -0.62, 0.05, Color(0.30, 0.31, 0.35))          # cheek rest
	_grip_box(body, -0.26, -0.203, -0.88, -1.20, 0.048, SYNTH)
	k_brake(body)
	_grip_box(body, -0.275, -0.245, -0.66, -0.74, 0.012, METAL)
	_scope(body, -0.098, -0.56, 0.50, 0.034, 0.052)
	mover.box(Vector3(X + 0.055, -0.19, -0.77), Vector3(0.065, 0.014, 0.016), METAL_LIGHT)
	mover.ellipsoid(Vector3(X + 0.10, -0.19, -0.77), Vector3(0.022, 0.022, 0.022), 5, 3, METAL_LIGHT)
	return {"muzzle": Vector3(X, -0.19, -1.55), "ads": Vector3(X, -0.098, -0.52), "kind": &"bolt", "kick": 0.11, "flash": 0.0085,
		"rhand": Vector3(X, -0.255, -0.62), "lhand": Vector3(X, -0.268, -1.05)}


static func k_brake(k: MeshKit) -> void:
	k.box(Vector3(X, -0.19, -1.50), Vector3(0.080, 0.080, 0.12), METAL_LIGHT, METAL)
	k.box(Vector3(X, -0.19, -1.50), Vector3(0.072, 0.036, 0.04), METAL)


# --- animation -----------------------------------------------------------------------------------

func play_fire() -> void:
	_recoil = 1.0
	_flash_t = 0.06
	_flash.visible = true
	_flash.rotation = Vector3(0, 0, randf() * TAU)
	_flash.scale = Vector3.ONE * randf_range(0.85, 1.2)
	# a little extra shake of the off hand
	if _kind == &"bolt":
		pass


func play_cycle(duration_s: float) -> void:
	_cycle_d = maxf(duration_s, 0.05)
	_cycle_t = 0.0


func play_reload(duration_s: float) -> void:
	_reload_d = maxf(duration_s, 0.1)
	_reload_t = 0.0


func play_draw(duration_s: float) -> void:
	_draw_d = maxf(duration_s, 0.05)
	_draw_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	_recoil = maxf(_recoil - delta * 5.0, 0.0)
	if _cycle_t >= 0.0:
		_cycle_t += delta
		if _cycle_t >= _cycle_d:
			_cycle_t = -1.0
	if _reload_t >= 0.0:
		_reload_t += delta
		if _reload_t >= _reload_d:
			_reload_t = -1.0
	if _draw_t >= 0.0:
		_draw_t += delta
		if _draw_t >= _draw_d:
			_draw_t = -1.0
	_apply_pose(delta)


func _apply_pose(_delta: float) -> void:
	var rec: float = _recoil * _recoil
	var pos: Vector3 = Vector3(0, sin(_time * 1.7) * 0.0015, 0)
	var rot: Vector3 = Vector3.ZERO  # pitch (x), yaw (y), roll (z) in radians around PIVOT
	pos.z += rec * _recoil_kick
	pos.y += rec * _recoil_kick * 0.25
	rot.x += rec * _recoil_kick * 2.2
	rot.y += rec * 0.01
	var l_off: Vector3 = Vector3.ZERO
	var m_off: Vector3 = Vector3.ZERO
	var m_rot: float = 0.0

	if _cycle_t >= 0.0:
		var t: float = _cycle_t / _cycle_d
		match _kind:
			&"pump":
				var p: float = _pump_curve(t)
				m_off.z = 0.13 * p
				l_off.z = 0.13 * p
				rot.x += 0.03 * p
			&"bolt":
				# lift handle, pull back, push forward, drop handle
				var lift: float = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t))
				var back: float = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.55, 0.85, t))
				m_rot = -1.1 * lift
				m_off.z = 0.085 * back
				rot.z += 0.02 * lift
			_:
				var p2: float = sin(t * PI)
				m_off.z = 0.04 * p2

	if _reload_t >= 0.0:
		var t: float = _reload_t / _reload_d
		var bell: float = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t))
		rot.z += 0.55 * bell
		rot.x += 0.28 * bell
		pos.y -= 0.03 * bell
		pos.x -= 0.05 * bell
		if _kind == &"pump":
			# feed shells one by one: hand goes to the loading port and back
			var n: float = 4.0
			var ph: float = fposmod(t * n, 1.0)
			l_off = Vector3(-0.02, -0.09 + sin(ph * PI) * 0.10, 0.34) * bell
			m_off.z = 0.0
		else:
			# magazine swap: off hand drops to the magwell, pulls, returns
			var dip: float = sin(clampf((t - 0.15) / 0.7, 0.0, 1.0) * PI)
			l_off = Vector3(-0.03, -0.12 * dip, 0.32 * bell) * 1.0
			if _kind == &"bolt":
				m_rot = -1.0 * smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.85, 1.0, t))
				m_off.z = 0.07 * sin(clampf((t - 0.6) / 0.3, 0.0, 1.0) * PI)

	if _draw_t >= 0.0:
		var t: float = _draw_t / _draw_d
		var e: float = 1.0 - pow(1.0 - t, 3.0)
		pos.y -= 0.34 * (1.0 - e)
		pos.x += 0.12 * (1.0 - e)
		rot.x -= 0.5 * (1.0 - e)
		rot.z -= 0.35 * (1.0 - e)

	# At the hip the gun toes in toward screen center so its left side (profile) shows; fades out when aiming.
	var hip: float = clampf(1.0 - absf(position.x) / X, 0.0, 1.0)
	rot.y += HIP_YAW * hip
	var basis: Basis = Basis.from_euler(Vector3(rot.x, rot.y, rot.z))
	var xf: Transform3D = Transform3D(Basis.IDENTITY, PIVOT + pos) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -PIVOT)
	_gun.transform = xf
	_larm.position = l_off
	_mover.position = m_off
	_mover.rotation = Vector3(0, 0, m_rot)
	if _kind == &"pump":
		_larm.position = l_off


## 0 -> 1 -> 0 with a quick rack and a slightly slower return.
func _pump_curve(t: float) -> float:
	if t < 0.45:
		return smoothstep(0.0, 0.45, t)
	if t < 0.55:
		return 1.0
	return 1.0 - smoothstep(0.55, 1.0, t)
