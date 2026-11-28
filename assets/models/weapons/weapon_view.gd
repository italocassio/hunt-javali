extends WeaponViewBase
## First-person weapon + arms, procedural. One script for the five weapons; setup(weapon_id) picks the model.
## Camera space, looking -Z. At position (0,0,0) the weapon sits at hip position (lower right).
## Nodes: Gun (animated) > Body, Mover (bolt / pump), RightArm, LeftArm, plus Muzzle + AdsAnchor at the root.
## Guns: HD procedural meshes (showcase/<id>_hd.gd). Arms: HD gloved arms (showcase/arms_hd.gd), one material.

const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const CarbineHD := preload("res://assets/models/weapons/showcase/carbine_22_hd.gd")
const ShotgunHD := preload("res://assets/models/weapons/showcase/shotgun_12_hd.gd")
const Rifle3006HD := preload("res://assets/models/weapons/showcase/rifle_3006_hd.gd")
const Rifle338HD := preload("res://assets/models/weapons/showcase/rifle_338_hd.gd")
const ArmsHD := preload("res://assets/models/weapons/showcase/arms_hd.gd")

## Viewmodel FOV: Gun is scaled by (1, 1, k) about the eye (the root origin = camera origin). With a perspective
## camera x / (k z) = (1 / k) x / z, so the gun and arms render exactly as with their own narrower FOV,
## tan(fov' / 2) = k * tan(fov / 2), with no SubViewport or shader. x / y are untouched, so AdsAnchor still
## centres the sight line. Each HD model brings its k (VIEW_DEPTH); 1.0 = off.
## Side effect: a pitch or yaw of the Gun reads about 1 / k larger on screen (the gun is shorter in z), so the
## animation pitches and yaws below are multiplied by k; roll is in the screen plane and needs no correction.
const DEFAULT_VIEW_DEPTH: float = 1.0

## Recoil: back by `kick`, up by kick * RECOIL_RISE, pitch kick * RECOIL_PITCH (before the k correction).
const RECOIL_RISE: float = 0.25
const RECOIL_PITCH: float = 2.2
const RECOIL_YAW: float = 0.01
const RECOIL_DECAY: float = 5.0
## Reload: the gun rolls toward the shooter's left (bolt and magazine come into view), muzzle up a little,
## and drops toward the lower right. Angles in radians at the peak of the move.
const RELOAD_ROLL: float = 0.45
const RELOAD_PITCH: float = 0.06
const RELOAD_YAW: float = 0.06
const RELOAD_DROP: Vector3 = Vector3(0.01, -0.028, 0.0)
## Draw: comes up from below the screen, muzzle low, canted.
const DRAW_DROP: Vector3 = Vector3(0.12, -0.34, 0.0)
const DRAW_PITCH: float = -0.5
const DRAW_ROLL: float = -0.20
const SWAY_FREQ: float = 1.7
const SWAY_AMP: float = 0.0015

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
	_muzzle.position = RifleHD.HIP_ORIGIN + Vector3(0.0, 0.0, -RifleHD.MUZZLE_S)
	add_child(_muzzle)
	_ads = Marker3D.new()
	_ads.name = "AdsAnchor"
	_ads.position = RifleHD.HIP_ORIGIN + Vector3(0.0, RifleHD.SCOPE_Y, -0.285)
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
	_arms = model["arms"]
	_view_depth = model.get("k", DEFAULT_VIEW_DEPTH)
	_pivot = model["pivot"]
	_hip_yaw = model["yaw"]
	_hip_roll = model.get("roll", 0.0)
	_muzzle_rest = model["muzzle"]
	_muzzle.position = _depth_xf() * _muzzle_rest
	var ads: Vector3 = model["ads"]
	_ads.position = Vector3(ads.x, ads.y, ads.z * _view_depth)
	_kind = model["kind"]
	_recoil_kick = model["kick"]
	_flash.pixel_size = model["flash_size"]   # sits at the compressed depth: grows with the gun
	_origin = model["origin"]
	_rot_sign = model.get("rot_sign", 1.0)
	_body.position = _origin
	_apply_pose(0.0)


## HD models are authored in gun space (butt plate at the origin); _origin puts them at the hip.
var _origin: Vector3 = Vector3.ZERO
var _muzzle_rest: Vector3 = Vector3.ZERO
var _rot_sign: float = 1.0
var _view_depth: float = DEFAULT_VIEW_DEPTH
var _pivot: Vector3 = RifleHD.HIP_PIVOT
var _hip_yaw: float = RifleHD.HIP_YAW
var _hip_roll: float = RifleHD.HIP_ROLL
## ArmsHD.get_arms() of the current gun: meshes plus the hand / elbow / knob / magazine points used by the poses.
var _arms: Dictionary = {}


## The viewmodel depth compression about the eye, applied on top of the Gun pose.
func _depth_xf() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(1.0, 1.0, _view_depth)), Vector3.ZERO)


func _build_model(id: StringName) -> Dictionary:
	match id:
		&"rifle_308": return _build_rifle_308_hd()
		&"shotgun_12": return _build_shotgun_12_hd()
		&"rifle_3006": return _build_rifle_3006_hd()
		&"rifle_338": return _build_rifle_338_hd()
	return _build_carbine_22_hd()


## Adds the HD arms of `id` to an HD gun model: RightArm / LeftArm meshes (one shared material) and the pose
## points. The gun triangles (gun space) darken the hands where they touch the gun (baked contact shadow).
static func _with_arms(id: StringName, model: Dictionary) -> Dictionary:
	var faces: PackedVector3Array = (model["body"] as Mesh).get_faces()
	faces.append_array((model["mover"] as Mesh).get_faces())
	var bounds: AABB = (model["body"] as Mesh).get_aabb().merge((model["mover"] as Mesh).get_aabb())
	var arms: Dictionary = ArmsHD.get_arms(id, faces, bounds)
	model["rarm"] = arms["right"]
	model["larm"] = arms["left"]
	model["arms"] = arms
	return model


## Rifle .308 (bolt): Body = 3 surfaces (wood, hard surface, lens), Mover = bolt, plus the two HD arms:
## 4 nodes, 4 materials.
func _build_rifle_308_hd() -> Dictionary:
	var hd: Dictionary = RifleHD.get_model()
	var o: Vector3 = RifleHD.HIP_ORIGIN
	return _with_arms(&"rifle_308", {
		"body": hd["body"], "mover": hd["bolt"],
		"muzzle": o + Vector3(0.0, 0.0, -RifleHD.MUZZLE_S), "ads": o + Vector3(0.0, RifleHD.SCOPE_Y, -0.285),
		"kind": &"bolt", "kick": 0.07, "flash_size": 0.0045,
		"origin": o, "rot_sign": -1.0,
		"pivot": RifleHD.HIP_PIVOT, "yaw": RifleHD.HIP_YAW, "roll": RifleHD.HIP_ROLL, "k": RifleHD.VIEW_DEPTH,
	})


## Carbine .22 (bolt, open sights). Mover = bolt.
func _build_carbine_22_hd() -> Dictionary:
	var hd: Dictionary = CarbineHD.get_model()
	var o: Vector3 = CarbineHD.HIP_ORIGIN
	return _with_arms(&"carbine_22", {
		"body": hd["body"], "mover": hd["mover"],
		"muzzle": o + Vector3(0.0, 0.0, -CarbineHD.MUZZLE_S), "ads": o + Vector3(0.0, CarbineHD.SIGHT_Y, -CarbineHD.SIGHT_S),
		"kind": &"bolt", "kick": 0.04, "flash_size": 0.003,
		"origin": o, "rot_sign": -1.0,
		"pivot": CarbineHD.HIP_PIVOT, "yaw": CarbineHD.HIP_YAW, "roll": CarbineHD.HIP_ROLL, "k": CarbineHD.VIEW_DEPTH,
	})


## Shotgun 12 (pump). Mover = pump fore-end.
func _build_shotgun_12_hd() -> Dictionary:
	var hd: Dictionary = ShotgunHD.get_model()
	var o: Vector3 = ShotgunHD.HIP_ORIGIN
	return _with_arms(&"shotgun_12", {
		"body": hd["body"], "mover": hd["mover"],
		"muzzle": o + Vector3(0.0, 0.0, -ShotgunHD.MUZZLE_S), "ads": o + Vector3(0.0, ShotgunHD.SIGHT_Y, -ShotgunHD.SIGHT_S),
		"kind": &"pump", "kick": 0.09, "flash_size": 0.0065,
		"origin": o, "rot_sign": 1.0,
		"pivot": ShotgunHD.HIP_PIVOT, "yaw": ShotgunHD.HIP_YAW, "roll": ShotgunHD.HIP_ROLL, "k": ShotgunHD.VIEW_DEPTH,
	})


## Rifle .30-06 (semi-auto). Mover = operating handle (cycle_s is 0 for this gun: play_cycle is never called).
func _build_rifle_3006_hd() -> Dictionary:
	var hd: Dictionary = Rifle3006HD.get_model()
	var o: Vector3 = Rifle3006HD.HIP_ORIGIN
	return _with_arms(&"rifle_3006", {
		"body": hd["body"], "mover": hd["mover"],
		"muzzle": o + Vector3(0.0, 0.0, -Rifle3006HD.MUZZLE_S), "ads": o + Vector3(0.0, Rifle3006HD.SCOPE_Y, -Rifle3006HD.ADS_S),
		"kind": &"semi", "kick": 0.065, "flash_size": 0.005,
		"origin": o, "rot_sign": 1.0,
		"pivot": Rifle3006HD.HIP_PIVOT, "yaw": Rifle3006HD.HIP_YAW, "roll": Rifle3006HD.HIP_ROLL, "k": Rifle3006HD.VIEW_DEPTH,
	})


## Rifle .338 (bolt, big scope, muzzle brake).
func _build_rifle_338_hd() -> Dictionary:
	var hd: Dictionary = Rifle338HD.get_model()
	var o: Vector3 = Rifle338HD.HIP_ORIGIN
	return _with_arms(&"rifle_338", {
		"body": hd["body"], "mover": hd["mover"],
		"muzzle": o + Vector3(0.0, 0.0, -Rifle338HD.MUZZLE_S), "ads": o + Vector3(0.0, Rifle338HD.SCOPE_Y, -Rifle338HD.ADS_S),
		"kind": &"bolt", "kick": 0.11, "flash_size": 0.0085,
		"origin": o, "rot_sign": -1.0,
		"pivot": Rifle338HD.HIP_PIVOT, "yaw": Rifle338HD.HIP_YAW, "roll": Rifle338HD.HIP_ROLL, "k": Rifle338HD.VIEW_DEPTH,
	})


# --- animation -----------------------------------------------------------------------------------

func play_fire() -> void:
	_recoil = 1.0
	_flash_t = 0.06
	_flash.visible = true
	_flash.rotation = Vector3(0, 0, randf() * TAU)
	_flash.scale = Vector3.ONE * randf_range(0.85, 1.2)


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
	_recoil = maxf(_recoil - delta * RECOIL_DECAY, 0.0)
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
	var k: float = _view_depth
	var rec: float = _recoil * _recoil
	var pos: Vector3 = Vector3(0, sin(_time * SWAY_FREQ) * SWAY_AMP, 0)
	var rot: Vector3 = Vector3.ZERO  # pitch (x), yaw (y), roll (z) in radians around the pivot
	pos.z += rec * _recoil_kick
	pos.y += rec * _recoil_kick * RECOIL_RISE
	rot.x += rec * _recoil_kick * RECOIL_PITCH * k
	rot.y += rec * RECOIL_YAW * k
	var m_off: Vector3 = Vector3.ZERO
	var m_rot: float = 0.0
	var cycle_n: float = -1.0
	var reload_n: float = -1.0
	var reload_bell: float = 0.0

	if _cycle_t >= 0.0:
		var t: float = _cycle_t / _cycle_d
		cycle_n = t
		match _kind:
			&"pump":
				var p: float = _pump_curve(t)
				m_off.z = ShotgunHD.PUMP_TRAVEL * p
				rot.x += 0.03 * p * k
			&"bolt":
				# lift handle, pull back, push forward, drop handle
				var lift: float = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t))
				var back: float = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.55, 0.85, t))
				m_rot = -1.1 * lift
				m_off.z = 0.085 * back
				rot.z += 0.02 * lift
			_:
				m_off.z = 0.04 * sin(t * PI)

	if _reload_t >= 0.0:
		var t: float = _reload_t / _reload_d
		reload_n = t
		var bell: float = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t))
		reload_bell = bell
		rot.z += RELOAD_ROLL * bell
		rot.x += RELOAD_PITCH * bell * k
		rot.y += RELOAD_YAW * bell * k
		pos += RELOAD_DROP * bell
		if _kind == &"pump":
			m_off.z = 0.0
		elif _kind == &"bolt":
			# bolt held open by the right hand while the left one swaps the magazine
			m_rot = -1.0 * smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.85, 1.0, t))
			m_off.z = 0.07 * sin(clampf((t - 0.6) / 0.3, 0.0, 1.0) * PI)

	if _draw_t >= 0.0:
		var t: float = _draw_t / _draw_d
		var e: float = 1.0 - pow(1.0 - t, 3.0)
		pos += DRAW_DROP * (1.0 - e)
		rot.x += DRAW_PITCH * (1.0 - e) * k
		rot.z += DRAW_ROLL * (1.0 - e)

	# At the hip the gun toes in toward screen center so its left side (profile) shows; fades out when aiming.
	# (the aim logic moves the root to -AdsAnchor.x, so |position.x| reaches |AdsAnchor.x| in full ADS)
	var hip: float = clampf(1.0 - absf(position.x) / maxf(absf(_ads.position.x), 0.01), 0.0, 1.0)
	rot.y += _hip_yaw * hip
	# ...and cants about the bore, which swings the support hand out from behind the fore-end. Both fade to
	# zero as the player aims. The pivot sits below the bore, so the cant alone would also slide the gun
	# sideways: that slide is subtracted, leaving a pure roll about the barrel.
	# the reload has its own roll, toward the other side: the carry cant gets out of its way
	var cant: float = _hip_roll * hip * (1.0 - reload_bell)
	rot.z += cant
	var lever: Vector3 = _origin - _pivot
	pos -= Vector3(-lever.y * sin(cant), lever.y * (cos(cant) - 1.0), 0.0)
	var basis: Basis = Basis.from_euler(Vector3(rot.x, rot.y, rot.z))
	var xf: Transform3D = Transform3D(Basis.IDENTITY, _pivot + pos) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_pivot)
	var depth: Transform3D = _depth_xf()
	_gun.transform = depth * xf
	# the Muzzle (effects origin) follows the toe-in, recoil and depth compression of the drawn barrel
	_muzzle.position = depth * xf * _muzzle_rest
	_mover.position = m_off + _origin
	_mover.rotation = Vector3(0, 0, m_rot * _rot_sign)
	_pose_arms(cycle_n, reload_n, m_off.z)


## RightArm / LeftArm for the current state (Gun space): bolt guns work the bolt knob with the right fist and swap
## the magazine with the left hand, the pump rides the fore-end and feeds the loading port, the semi swaps the
## magazine only.
func _pose_arms(cycle_n: float, reload_n: float, mover_z: float) -> void:
	if _arms.is_empty():
		return
	var xf: Array[Transform3D]
	match _kind:
		&"bolt":
			var knob_now: Vector3 = _mover.transform * (_arms["knob_gun"] as Vector3)
			xf = ArmsHD.bolt_pose(_arms, cycle_n, reload_n, knob_now)
		&"pump":
			xf = ArmsHD.pump_pose(_arms, mover_z, reload_n)
		_:
			xf = [Transform3D.IDENTITY, ArmsHD.mag_reach(_arms, reload_n)]
	_rarm.transform = xf[0]
	_larm.transform = xf[1]


## 0 -> 1 -> 0 with a quick rack and a slightly slower return.
func _pump_curve(t: float) -> float:
	if t < 0.45:
		return smoothstep(0.0, 0.45, t)
	if t < 0.55:
		return 1.0
	return 1.0 - smoothstep(0.55, 1.0, t)
