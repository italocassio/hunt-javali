extends HunterVisualBase
## Procedural low-poly third-person hunter (how allies are seen in multiplayer).
## Hierarchy: Body > Hips > (Torso > (Head, ArmL, ArmR, Gun), ThighL > ShinL, ThighR > ShinR).
## 10 MeshInstance3D incl. the muzzle flash. Origin on the ground between the feet, forward -Z.
## The slot color paints the whole vest and the hat band (cached per slot: 4 mesh variants,
## one shared vertex-color material for everything). Muzzle and NameAnchor are root children
## that this script repositions every frame to follow the weapon tip and the head.

const LEG_UPPER: float = 0.46
const LEG_LOWER: float = 0.46
const HIP_X: float = 0.095
const SHOULDER: Vector3 = Vector3(0.235, 0.52, 0.0)   # right shoulder in torso space (x mirrored)
const NECK_Y: float = 0.58
const ARM_LEN: float = 0.58
const ANCHOR_UP: float = 0.55
const STANDING_HIP_Y: float = 0.92

const STRIDE_BASE: float = 2.2
const STRIDE_PER_MPS: float = 0.1
const RUN_SPEED: float = 6.5
const CROUCH_S: float = 0.2
const AIM_RATE: float = 7.0
const FLASH_S: float = 0.06
const HIT_S: float = 0.28
const DEATH_S: float = 0.8
const DEATH_ROT: float = 1.5
const DEATH_LIFT: float = 0.13
const TORSO_AIM_YAW: float = 0.2

const SKIN: Color = Color(0.78, 0.58, 0.44)
const SHIRT: Color = Color(0.66, 0.60, 0.40)
const SHIRT_DARK: Color = Color(0.50, 0.46, 0.30)
const PANTS: Color = Color(0.36, 0.32, 0.22)
const PANTS_DARK: Color = Color(0.27, 0.24, 0.17)
const BELT: Color = Color(0.18, 0.12, 0.08)
const BOOT: Color = Color(0.19, 0.12, 0.08)
const HAT: Color = Color(0.46, 0.33, 0.20)
const HAT_LIGHT: Color = Color(0.56, 0.42, 0.26)
const GLASSES: Color = Color(0.08, 0.08, 0.10)

const WOOD: Color = Color(0.52, 0.35, 0.20)
const WOOD_RED: Color = Color(0.58, 0.25, 0.14)
const WOOD_LIGHT: Color = Color(0.62, 0.50, 0.34)
const WOOD_DARK: Color = Color(0.30, 0.20, 0.14)
const SYNTH: Color = Color(0.20, 0.21, 0.24)
const METAL: Color = Color(0.30, 0.32, 0.36)
const METAL_LIGHT: Color = Color(0.52, 0.54, 0.58)

static var _cache: Dictionary = {}
static var _flash_mat: StandardMaterial3D = null

var _body: Node3D
var _hips: Node3D
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _gun: MeshInstance3D
var _thigh: Array[MeshInstance3D] = []
var _shin: Array[MeshInstance3D] = []
var _muzzle: Marker3D
var _name_anchor: Marker3D
var _flash: MeshInstance3D

var _slot: int = 0
var _weapon: StringName = &""
var _gun_info: Dictionary = {}
var _speed: float = 0.0
var _crouch_on: bool = false
var _aim_on: bool = false
var _pitch: float = 0.0
var _crouch: float = 0.0
var _aim: float = 0.0
var _move: float = 0.0
var _phase: float = 0.0
var _recoil: float = 0.0
var _flash_t: float = 0.0
var _reload_t: float = -1.0
var _reload_d: float = 1.0
var _hit_t: float = -1.0
var _dead: bool = false
var _death_t: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_body.add_child(_hips)
	_torso = _mi("Torso", _hips, true)
	_head = _mi("Head", _torso, false)
	_arm_l = _mi("ArmL", _torso, false)
	_arm_r = _mi("ArmR", _torso, false)
	_gun = _mi("Gun", _torso, false)
	for side in 2:
		var tag: String = "L" if side == 0 else "R"
		var sx: float = -1.0 if side == 0 else 1.0
		var th: MeshInstance3D = _mi("Thigh" + tag, _hips, false)
		th.position = Vector3(sx * HIP_X, 0.0, 0.0)
		var sh: MeshInstance3D = _mi("Shin" + tag, th, false)
		sh.position = Vector3(0.0, -LEG_UPPER, 0.0)
		_thigh.append(th)
		_shin.append(sh)
	_head.position = Vector3(0.0, NECK_Y, 0.0)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	add_child(_muzzle)
	_name_anchor = Marker3D.new()
	_name_anchor.name = "NameAnchor"
	add_child(_name_anchor)
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_muzzle.add_child(_flash)


func _ready() -> void:
	if _torso.mesh == null:
		setup(0, &"carbine_22")
	_update_pose(0.0)


func _mi(node_name: String, parent: Node, shadow: bool) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


# --- API ---------------------------------------------------------------------------------------

func setup(slot: int, weapon_id: StringName) -> void:
	_slot = posmod(slot, SLOT_COUNT)
	var key: String = "slot%d" % _slot
	if not _cache.has(key):
		var c: Color = slot_color(_slot)
		_cache[key] = {"torso": _build_torso(c), "head": _build_head(c)}
	if not _cache.has("shared"):
		_cache["shared"] = _build_shared()
	var s: Dictionary = _cache[key]
	var sh: Dictionary = _cache["shared"]
	_torso.mesh = s["torso"]
	_head.mesh = s["head"]
	_arm_l.mesh = sh["arm"]
	_arm_r.mesh = sh["arm"]
	for i in 2:
		_thigh[i].mesh = sh["thigh"]
		_shin[i].mesh = sh["shin"]
	_flash.mesh = sh["flash"]
	set_weapon(weapon_id)


func set_weapon(weapon_id: StringName) -> void:
	_weapon = weapon_id
	if weapon_id == &"":
		_gun.mesh = null
		_gun.visible = false
		_gun_info = {}
		return
	var key: String = "gun_" + String(weapon_id)
	if not _cache.has(key):
		_cache[key] = _build_gun(weapon_id)
	var g: Dictionary = _cache[key]
	_gun.mesh = g["mesh"]
	_gun.visible = true
	_gun_info = g


func set_locomotion(speed_mps: float) -> void:
	_speed = maxf(speed_mps, 0.0)


func set_crouching(on: bool) -> void:
	if not _dead:
		_crouch_on = on


func set_aiming(on: bool) -> void:
	if not _dead:
		_aim_on = on


func set_look_pitch(pitch_rad: float) -> void:
	_pitch = clampf(pitch_rad, -1.4, 1.4)


func play_fire() -> void:
	if _dead or _weapon == &"":
		return
	_recoil = 1.0
	_flash_t = FLASH_S
	_flash.visible = true
	_flash.rotation = Vector3(0.0, 0.0, randf() * TAU)
	_flash.scale = Vector3.ONE * (float(_gun_info["flash"]) * randf_range(0.85, 1.15))


func play_reload(duration_s: float) -> void:
	if _dead:
		return
	_reload_d = maxf(duration_s, 0.1)
	_reload_t = 0.0


func play_hit() -> void:
	if _dead:
		return
	_hit_t = 0.0


func play_death(instant: bool = false) -> void:
	if _dead:
		return
	_dead = true
	_death_t = DEATH_S if instant else 0.0
	_flash_t = 0.0
	_flash.visible = false
	_reload_t = -1.0
	_hit_t = -1.0
	_recoil = 0.0
	if instant:
		_aim = 0.0
		_aim_on = false
		_crouch = 0.0
		_move = 0.0
		_update_pose(0.0)   # final pose right now, no animation


# --- model building ----------------------------------------------------------------------------

static func _build_torso(vest: Color) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	k.box(Vector3(0.0, 0.07, 0.0), Vector3(0.34, 0.16, 0.20), PANTS)                  # pelvis
	k.box(Vector3(0.0, 0.16, 0.0), Vector3(0.35, 0.04, 0.21), BELT)                   # belt
	k.prism(Vector3(0.0, 0.18, 0.0), Vector2(0.34, 0.20), Vector2(0.42, 0.22), 0.40, SHIRT_DARK, SHIRT)
	k.prism(Vector3(0.0, 0.20, 0.0), Vector2(0.355, 0.215), Vector2(0.43, 0.235), 0.33, MeshKit.shade(vest, 0.85), vest)
	var dark: Color = MeshKit.shade(vest, 0.62)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.09, 0.29, -0.125), Vector3(0.10, 0.09, 0.03), dark)       # chest pockets
	k.box(Vector3(0.0, 0.40, 0.122), Vector3(0.30, 0.08, 0.016), MeshKit.shade(vest, 1.22))   # back band
	k.box(Vector3(0.0, 0.60, 0.0), Vector3(0.10, 0.08, 0.10), SKIN)                   # neck
	return k.build()


static func _build_head(band: Color) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	k.ellipsoid(Vector3(0.0, 0.09, 0.0), Vector3(0.09, 0.105, 0.10), 6, 4, SKIN, MeshKit.shade(SKIN, 1.05))
	k.box(Vector3(0.0, 0.085, -0.105), Vector3(0.025, 0.04, 0.03), MeshKit.shade(SKIN, 0.92))   # nose
	k.box(Vector3(0.0, 0.115, -0.095), Vector3(0.15, 0.025, 0.012), GLASSES)                   # sunglasses (front marker)
	k.frustum(Vector3(0.0, 0.15, 0.0), 0.215, 0.20, 0.012, 8, MeshKit.shade(HAT, 0.8), HAT_LIGHT, true, true)   # brim
	k.frustum(Vector3(0.0, 0.16, 0.0), 0.105, 0.088, 0.085, 8, HAT, HAT_LIGHT, true, false)                      # crown
	k.frustum(Vector3(0.0, 0.158, 0.0), 0.110, 0.110, 0.036, 8, band, band, false, false)                         # hat band
	return k.build()


static func _build_shared() -> Dictionary:
	# arm: pivot at the shoulder, built downward
	var ak: MeshKit = MeshKit.new()
	ak.frustum(Vector3(0.0, -0.50, 0.0), 0.042, 0.056, 0.50, 6, SHIRT_DARK, SHIRT, true, false)
	ak.box(Vector3(0.0, -0.545, 0.0), Vector3(0.075, 0.09, 0.085), SKIN, MeshKit.shade(SKIN, 1.08))
	# thigh: pivot at the hip
	var tk: MeshKit = MeshKit.new()
	tk.prism(Vector3(0.0, -LEG_UPPER, 0.0), Vector2(0.10, 0.11), Vector2(0.14, 0.15), LEG_UPPER, PANTS_DARK, PANTS)
	# shin + boot: pivot at the knee
	var sk: MeshKit = MeshKit.new()
	sk.prism(Vector3(0.0, -0.30, 0.0), Vector2(0.085, 0.09), Vector2(0.10, 0.11), 0.30, PANTS_DARK, PANTS)
	sk.box(Vector3(0.0, -0.34, 0.0), Vector3(0.095, 0.24, 0.10), MeshKit.shade(BOOT, 1.15), BOOT)
	sk.box(Vector3(0.0, -0.4325, -0.045), Vector3(0.10, 0.055, 0.20), BOOT)
	# muzzle flash: crossed spikes + star, unshaded, no light
	var fk: MeshKit = MeshKit.new()
	var core: Color = Color(1.0, 0.97, 0.75)
	var tip: Color = Color(1.0, 0.62, 0.15)
	for plane in 2:
		var s: Vector3 = Vector3(1.0, 0.0, 0.0) if plane == 0 else Vector3(0.0, 1.0, 0.0)
		fk.tri_double(Vector3(0, 0, 0.02), s * 0.05 + Vector3(0, 0, -0.05), Vector3(0, 0, -0.20), core, core, tip)
		fk.tri_double(Vector3(0, 0, 0.02), Vector3(0, 0, -0.20), s * -0.05 + Vector3(0, 0, -0.05), core, tip, core)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.4
		fk.tri_double(Vector3(0, 0, -0.03), Vector3(cos(a), sin(a), 0.0) * 0.12 + Vector3(0, 0, -0.03), Vector3(cos(a + 0.5), sin(a + 0.5), 0.0) * 0.04 + Vector3(0, 0, -0.03), core, tip, tip)
	return {"arm": ak.build(), "thigh": tk.build(), "shin": sk.build(), "flash": fk.build(_get_flash_material())}


static func _get_flash_material() -> StandardMaterial3D:
	if _flash_mat == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flash_mat = m
	return _flash_mat


## Cylinder along -Z from z0 (back) to z1 (front).
static func _cyl_z(k: MeshKit, y: float, z0: float, z1: float, r0: float, r1: float, sides: int, c0: Color, c1: Color, cap: bool = true) -> void:
	k.set_xf(Vector3(0.0, y, z0), Vector3(-90.0, 0.0, 0.0))
	k.frustum(Vector3.ZERO, r0, r1, z0 - z1, sides, c0, c1, cap, cap)
	k.reset_xf()


static func _scope(k: MeshKit, z_back: float, length: float, r: float, obj_r: float) -> void:
	var y: float = 0.078
	_cyl_z(k, y, z_back, z_back - length, r, r, 6, METAL, METAL_LIGHT, false)
	_cyl_z(k, y, z_back - length, z_back - length - 0.05, r * 1.1, obj_r, 6, SYNTH, SYNTH, true)
	_cyl_z(k, y, z_back + 0.04, z_back, r * 1.2, r, 6, SYNTH, SYNTH, true)
	k.box(Vector3(0.0, 0.045, z_back - length * 0.2), Vector3(0.02, 0.03, 0.03), METAL)
	k.box(Vector3(0.0, 0.045, z_back - length * 0.8), Vector3(0.02, 0.03, 0.03), METAL)


## Gun in its own space: origin on the barrel axis over the right hand, barrel toward -Z.
static func _build_gun(id: StringName) -> Dictionary:
	var k: MeshKit = MeshKit.new()
	var stock: Color = WOOD
	var muzzle_z: float = -0.65
	var lhand: Vector3 = Vector3(0.0, -0.075, -0.34)
	var flash: float = 1.0
	match id:
		&"shotgun_12": stock = WOOD_DARK
		&"rifle_3006": stock = WOOD_RED
		&"rifle_338": stock = SYNTH
		&"carbine_22": stock = WOOD_LIGHT
	k.set_xf(Vector3(0.0, -0.04, 0.28), Vector3(-8.0, 0.0, 0.0))
	k.box(Vector3.ZERO, Vector3(0.04, 0.11, 0.30), stock)                           # stock
	k.reset_xf()
	k.box(Vector3(0.0, -0.065, 0.08), Vector3(0.03, 0.07, 0.04), stock)             # pistol grip
	k.box(Vector3(0.0, 0.0, -0.02), Vector3(0.04, 0.065, 0.30), METAL)              # receiver
	match id:
		&"shotgun_12":
			_cyl_z(k, 0.005, -0.16, -0.80, 0.016, 0.015, 6, METAL, METAL_LIGHT)
			_cyl_z(k, -0.035, -0.16, -0.62, 0.011, 0.011, 5, METAL_LIGHT, METAL_LIGHT, false)
			k.box(Vector3(0.0, -0.045, -0.40), Vector3(0.055, 0.05, 0.20), WOOD, WOOD_DARK)   # pump slide
			muzzle_z = -0.80
			lhand = Vector3(0.0, -0.08, -0.40)
			flash = 1.0
		&"rifle_308":
			_cyl_z(k, 0.0, -0.16, -0.70, 0.013, 0.011, 6, METAL, METAL_LIGHT)
			k.box(Vector3(0.0, -0.03, -0.40), Vector3(0.04, 0.04, 0.30), WOOD)
			_scope(k, 0.05, 0.36, 0.016, 0.026)
			k.box(Vector3(0.06, 0.005, 0.0), Vector3(0.07, 0.014, 0.014), METAL_LIGHT)         # bolt handle
			muzzle_z = -0.70
			lhand = Vector3(0.0, -0.075, -0.40)
			flash = 0.8
		&"rifle_3006":
			_cyl_z(k, 0.0, -0.16, -0.72, 0.013, 0.011, 6, METAL, METAL_LIGHT)
			k.box(Vector3(0.0, -0.03, -0.42), Vector3(0.046, 0.045, 0.32), Color(0.42, 0.45, 0.50))
			k.box(Vector3(0.0, -0.095, -0.06), Vector3(0.03, 0.10, 0.06), Color(0.66, 0.60, 0.40))   # magazine
			_scope(k, 0.03, 0.22, 0.018, 0.028)
			muzzle_z = -0.72
			lhand = Vector3(0.0, -0.075, -0.42)
			flash = 0.85
		&"rifle_338":
			_cyl_z(k, 0.0, -0.16, -0.82, 0.024, 0.020, 6, METAL, METAL_LIGHT)
			k.box(Vector3(0.0, -0.035, -0.42), Vector3(0.05, 0.05, 0.36), SYNTH)
			k.box(Vector3(0.0, 0.0, -0.87), Vector3(0.07, 0.07, 0.10), METAL_LIGHT, METAL)       # muzzle brake
			_scope(k, 0.06, 0.46, 0.030, 0.045)
			muzzle_z = -0.92
			lhand = Vector3(0.0, -0.085, -0.42)
			flash = 1.2
		_:
			id = &"carbine_22"
			_cyl_z(k, 0.0, -0.16, -0.62, 0.009, 0.008, 6, METAL, METAL_LIGHT)
			k.box(Vector3(0.0, -0.03, -0.34), Vector3(0.036, 0.04, 0.28), WOOD_LIGHT)
			k.box(Vector3(0.0, 0.04, -0.58), Vector3(0.008, 0.02, 0.008), METAL_LIGHT)         # front post
			muzzle_z = -0.62
			lhand = Vector3(0.0, -0.075, -0.34)
			flash = 0.5
	return {"mesh": k.build(), "muzzle": Vector3(0.0, 0.0, muzzle_z), "rhand": Vector3(0.0, -0.085, 0.08),
		"lhand": lhand, "flash": flash}


# --- animation ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_pose(delta)
	if _dead and _death_t >= DEATH_S:
		set_process(false)   # frozen on the ground: no more per-frame cost


func _update_pose(delta: float) -> void:
	_time += delta
	if _dead:
		_death_t = minf(_death_t + delta, DEATH_S)
	var death_e: float = 0.0
	if _dead:
		var td: float = clampf(_death_t / DEATH_S, 0.0, 1.0)
		death_e = 1.0 - (1.0 - td) * (1.0 - td)

	_aim = move_toward(_aim, 1.0 if (_aim_on and not _dead) else 0.0, delta * AIM_RATE)
	_crouch = move_toward(_crouch, 1.0 if _crouch_on else 0.0, delta / CROUCH_S)
	var spd: float = 0.0 if _dead else _speed
	_move = move_toward(_move, 1.0 if spd > 0.1 else 0.0, delta * 6.0)
	_phase += delta * TAU * spd / (STRIDE_BASE + STRIDE_PER_MPS * spd)
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	var flinch: float = 0.0
	if _hit_t >= 0.0:
		_hit_t += delta
		var kh: float = 1.0 - clampf(_hit_t / HIT_S, 0.0, 1.0)
		flinch = kh * kh
		if _hit_t >= HIT_S:
			_hit_t = -1.0
	var bell: float = 0.0
	var rt: float = 0.0
	if _reload_t >= 0.0:
		_reload_t += delta
		rt = clampf(_reload_t / _reload_d, 0.0, 1.0)
		bell = smoothstep(0.0, 0.14, rt) * (1.0 - smoothstep(0.86, 1.0, rt))
		if _reload_t >= _reload_d:
			_reload_t = -1.0

	var run: float = clampf(spd / RUN_SPEED, 0.0, 1.0)
	var crouch: float = maxf(_crouch, 0.55 * death_e)
	var amp: float = lerpf(0.0, 0.85, pow(run, 0.8)) * (1.0 - 0.45 * crouch) * _move
	var breathe: float = sin(_time * 1.7)

	# --- legs (also decide hip height so the lowest foot touches the ground)
	var depth: float = 0.0
	for side in 2:
		var ph: float = _phase + PI * float(side)
		var th: float = sin(ph) * amp + 1.0 * crouch
		var knee: float = -(0.06 + maxf(0.0, cos(ph)) * amp * 1.5) - 0.95 * crouch
		_thigh[side].rotation = Vector3(th, 0.0, 0.0)
		_shin[side].rotation = Vector3(knee, 0.0, 0.0)
		var d: float = LEG_UPPER * cos(th) + LEG_LOWER * cos(th + knee)
		depth = maxf(depth, d)
	_hips.position = Vector3(0.0, depth, 0.0)

	# --- torso and head
	var torso_pitch: float = _pitch * 0.35 - 0.10 * run - 0.14 * crouch + 0.012 * breathe
	torso_pitch += _recoil * _recoil * 0.05 * _aim - flinch * 0.22 - 0.12 * death_e
	var torso_yaw: float = TORSO_AIM_YAW * _aim + sin(_phase) * 0.06 * amp
	var torso_roll: float = sin(_phase) * 0.03 * amp + sin(_hit_t * 60.0) * 0.05 * flinch if _hit_t >= 0.0 else sin(_phase) * 0.03 * amp
	_torso.position = Vector3(0.0, 0.003 * breathe, 0.0)
	_torso.rotation = Vector3(torso_pitch, torso_yaw, torso_roll)
	_head.rotation = Vector3(_pitch * 0.45 + flinch * 0.25, -TORSO_AIM_YAW * _aim * 0.9 - sin(_phase) * 0.05 * amp, 0.0)

	# --- gun pose in torso space: low carry <-> shouldered, plus reload and recoil
	var armed: bool = _weapon != &""
	var rec: float = _recoil * _recoil
	var gp: Vector3 = Vector3(0.15, 0.40, -0.20).lerp(Vector3(0.08, 0.60, -0.40), _aim)
	var gr: Vector3 = Vector3(-0.10, 0.30, 0.0).lerp(Vector3(0.0, -TORSO_AIM_YAW, 0.0), _aim)
	gp.y += sin(_phase * 2.0) * 0.012 * _move * (1.0 - 0.8 * _aim)
	gp.x += sin(_phase) * 0.010 * _move * (1.0 - _aim)
	gr.x += _pitch * lerpf(0.2, 0.65, _aim)
	if bell > 0.0:
		gp = gp.lerp(Vector3(0.04, 0.36, -0.26), bell)
		gr = gr.lerp(Vector3(0.75, 0.30, 0.50), bell)
	gp.z += rec * 0.08
	gp.y += rec * 0.015
	gr.x += rec * 0.11
	gp.y -= flinch * 0.03
	if death_e > 0.0:
		gr.x = lerpf(gr.x, -0.5, death_e)
	var gun_xf: Transform3D = Transform3D(Basis.from_euler(Vector3(gr.x, gr.y, gr.z)), gp)
	_gun.transform = gun_xf

	# --- arms
	if armed:
		var rh: Vector3 = _gun_info["rhand"]
		var lh: Vector3 = _gun_info["lhand"]
		if bell > 0.0:
			var dip: float = sin(clampf((rt - 0.15) / 0.7, 0.0, 1.0) * PI)
			lh = lh + Vector3(0.0, -0.09 * dip, 0.26 * dip)
		_point_arm(_arm_r, SHOULDER, gun_xf * rh)
		_point_arm(_arm_l, Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z), gun_xf * lh)
	else:
		var swing: float = sin(_phase) * amp * 0.95
		_arm_l.basis = Basis(Vector3.RIGHT, -swing) * Basis(Vector3.BACK, -0.07)
		_arm_r.basis = Basis(Vector3.RIGHT, swing) * Basis(Vector3.BACK, 0.07)
		_arm_l.position = Vector3(-SHOULDER.x, SHOULDER.y, 0.0)
		_arm_r.position = SHOULDER

	# --- death fall
	_body.rotation = Vector3(DEATH_ROT * death_e, 0.0, 0.0)
	_body.position = Vector3(0.0, DEATH_LIFT * death_e, 0.0)

	# --- markers follow the model
	var chain: Transform3D = _body.transform * _hips.transform * _torso.transform
	_muzzle.transform = chain * gun_xf * Transform3D(Basis.IDENTITY, _gun_info.get("muzzle", Vector3(0.0, 0.0, -0.5)))
	_name_anchor.position = chain * Vector3(0.0, NECK_Y, 0.0) + Vector3(0.0, ANCHOR_UP, 0.0)


func _point_arm(arm: MeshInstance3D, shoulder: Vector3, target: Vector3) -> void:
	var d: Vector3 = target - shoulder
	var dist: float = d.length()
	arm.position = shoulder
	if dist < 0.05:
		return
	var q: Quaternion = Quaternion(Vector3.DOWN, d / dist)
	arm.basis = Basis(q) * Basis.from_scale(Vector3(1.0, clampf(dist / ARM_LEN, 0.7, 1.3), 1.0))
