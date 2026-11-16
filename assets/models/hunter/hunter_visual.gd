extends HunterVisualBase
## Third-person hunter (how allies are seen in the co-op hunt), procedural and detailed, animated by rigid parts.
## Hierarchy: Body > Hips > (Torso > (Head, ArmL, ArmR, Gun), ThighL > ShinL, ThighR > ShinR), Muzzle > Flash,
## NameAnchor. 10 MeshInstance3D. Only the torso casts a shadow; the muzzle flash is unshaded, no light.
##
## Meshes (all cached in static memory, see hunter_body.gd / hunter_held.gd):
##   body parts  shared by every slot, except torso and head (vest and cap in the slot colour: a recoloured copy)
##   Gun         the held gun (or binoculars when unarmed) WITH both forearms baked in; ArmL / ArmR are then
##               the upper arms only, stretched from the shoulder to the elbows of the held item. Unarmed and
##               not aiming: the Gun node hides and ArmL / ArmR swap to whole relaxed arms that swing.
## Materials: the HD arms material (body), the HD hard-surface material and the HD gun's own wood material (gun),
## the flash material. All shared with every instance (and with the first-person HD views).

const Rig := preload("res://assets/models/hunter/hunter_rig.gd")
const Body := preload("res://assets/models/hunter/hunter_body.gd")
const Held := preload("res://assets/models/hunter/hunter_held.gd")

const STRIDE_BASE: float = 2.2
const STRIDE_PER_MPS: float = 0.1
const RUN_SPEED: float = 6.5
const CROUCH_S: float = 0.22
const AIM_RATE: float = 6.5
const MOVE_RATE: float = 5.0
const RECOIL_DECAY: float = 6.0
const FLASH_S: float = 0.06
const HIT_S: float = 0.30
const DEATH_S: float = 0.85
const DEATH_ROT: float = 1.50
const DEATH_LIFT: float = 0.17
const KNEE_CAP: float = 0.055
const AIM_TORSO_PITCH: float = 0.82   # share of the look pitch taken by the torso when aiming (+0.12 always)
## Kneeling (crouched, standing still): left leg forward, right knee on the ground. [thigh, knee] per side.
const KNEEL_L: Vector2 = Vector2(1.36, -1.36)
const KNEEL_R: Vector2 = Vector2(0.10, -1.66)
const HEAD_CHEEK: Vector3 = Vector3(-0.22, 0.0, -0.20)   # head pitch / yaw / roll laid on the stock when aiming

static var _flash_mesh: ArrayMesh = null
## Build time of the last setup() / set_weapon() that had to build something, in ms (0 = served from the cache).
static var last_build_ms: float = 0.0

var _body: Node3D
var _hips: Node3D
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _arm: Array[MeshInstance3D] = []
var _gun: MeshInstance3D
var _thigh: Array[MeshInstance3D] = []
var _shin: Array[MeshInstance3D] = []
var _muzzle: Marker3D
var _name_anchor: Marker3D
var _flash: MeshInstance3D

var _parts: Dictionary = {}
var _held: Dictionary = {}
var _binoculars: Dictionary = {}
var _slot: int = 0
var _weapon: StringName = &""
var _ready_done: bool = false
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
var _full_arms: bool = false
var _pose_key: String = "low"


func _init() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_body.add_child(_hips)
	_torso = _mi("Torso", _hips, true)
	_head = _mi("Head", _torso, false)
	_head.position = Vector3(0.0, Rig.NECK_Y, 0.0)
	for side in 2:
		var arm: MeshInstance3D = _mi("ArmL" if side == 0 else "ArmR", _torso, false)
		arm.position = Rig.shoulder(side)
		_arm.append(arm)
	_gun = _mi("Gun", _torso, false)
	for side in 2:
		var tag: String = "L" if side == 0 else "R"
		var th: MeshInstance3D = _mi("Thigh" + tag, _hips, false)
		th.position = Vector3((-1.0 if side == 0 else 1.0) * Rig.HIP_X, 0.0, 0.0)
		var sh: MeshInstance3D = _mi("Shin" + tag, th, false)
		sh.position = Vector3(0.0, -Rig.LEG_UPPER, 0.0)
		_thigh.append(th)
		_shin.append(sh)
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
	if _parts.is_empty():
		setup(0, Held.DEFAULT_GUN)
	_ready_done = true
	_update_pose(0.0)


func _mi(node_name: String, parent: Node, shadow: bool) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


# --- API ---------------------------------------------------------------------------------------

func setup(slot: int, weapon_id: StringName) -> void:
	var t0: int = Time.get_ticks_usec()
	var cold: bool = not Body.is_cached(posmod(slot, SLOT_COUNT)) or not Held.is_cached(weapon_id) or not Held.is_cached(Held.BINOCULARS)
	_slot = posmod(slot, SLOT_COUNT)
	_parts = Body.get_parts(_slot)
	_torso.mesh = _parts["torso"]
	_head.mesh = _parts["head"]
	for side in 2:
		_thigh[side].mesh = _parts["thigh_l" if side == 0 else "thigh_r"]
		_shin[side].mesh = _parts["shin_l" if side == 0 else "shin_r"]
	_binoculars = Held.get_item(Held.BINOCULARS)
	if _flash_mesh == null:
		_flash_mesh = _build_flash()
	_flash.mesh = _flash_mesh
	_full_arms = false
	_apply_weapon(weapon_id)
	last_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0 if cold else 0.0


func set_weapon(weapon_id: StringName) -> void:
	if _parts.is_empty():   # before setup: setup() picks it up
		_weapon = weapon_id
		return
	var t0: int = Time.get_ticks_usec()
	var cold: bool = not Held.is_cached(weapon_id)
	_apply_weapon(weapon_id)
	last_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0 if cold else 0.0
	if _ready_done:
		_update_pose(0.0)


func _apply_weapon(weapon_id: StringName) -> void:
	_weapon = weapon_id
	_held = _binoculars if weapon_id == Held.BINOCULARS else Held.get_item(weapon_id)
	_pose_key = "aim" if weapon_id == Held.BINOCULARS else "low"
	_gun.mesh = _held["poses"][_pose_key]["mesh"]
	_set_full_arms(weapon_id == Held.BINOCULARS)


func _set_full_arms(on: bool) -> void:
	if on == _full_arms and _arm[0].mesh != null:
		return
	_full_arms = on
	_arm[0].mesh = _parts["arm_full_l"] if on else _parts["arm_upper"]
	_arm[1].mesh = _parts["arm_full_r"] if on else _parts["arm_upper"]
	_gun.visible = not on


func set_locomotion(speed_mps: float) -> void:
	_speed = maxf(speed_mps, 0.0)


func set_crouching(on: bool) -> void:
	if not _dead:
		_crouch_on = on


func set_aiming(on: bool) -> void:
	if not _dead:
		_aim_on = on


func set_look_pitch(pitch_rad: float) -> void:
	_pitch = clampf(pitch_rad, -1.2, 1.2)


func play_fire() -> void:
	if _dead or _weapon == Held.BINOCULARS:
		return
	_recoil = 1.0
	_flash_t = FLASH_S
	_flash.visible = true
	_flash.rotation = Vector3(0.0, 0.0, randf() * TAU)
	_flash.scale = Vector3.ONE * (float(_held["flash"]) * randf_range(0.85, 1.15))


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
	_aim_on = false
	_crouch_on = false
	if instant:
		_aim = 0.0
		_crouch = 0.0
		_move = 0.0
		_update_pose(0.0)   # final pose right now, no animation


# --- animation ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_pose(delta)
	if _dead and _death_t >= DEATH_S:
		set_process(false)   # frozen on the ground: no more per-frame cost


func _update_pose(delta: float) -> void:
	if _parts.is_empty():
		return
	_time += delta
	var death_e: float = 0.0
	if _dead:
		_death_t = minf(_death_t + delta, DEATH_S)
		var td: float = clampf(_death_t / DEATH_S, 0.0, 1.0)
		death_e = td * td * (3.0 - 2.0 * td)
	_aim = move_toward(_aim, 1.0 if (_aim_on and not _dead) else 0.0, delta * AIM_RATE)
	_crouch = move_toward(_crouch, 1.0 if (_crouch_on and not _dead) else 0.0, delta / CROUCH_S)
	var spd: float = 0.0 if _dead else _speed
	_move = move_toward(_move, 1.0 if spd > 0.3 else 0.0, delta * MOVE_RATE)
	_phase = fmod(_phase + delta * TAU * spd / (STRIDE_BASE + STRIDE_PER_MPS * spd), TAU * 64.0)
	_recoil = maxf(_recoil - delta * RECOIL_DECAY, 0.0)
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
	if _reload_t >= 0.0:
		_reload_t += delta
		var rt: float = clampf(_reload_t / _reload_d, 0.0, 1.0)
		bell = smoothstep(0.0, 0.15, rt) * (1.0 - smoothstep(0.85, 1.0, rt))
		if _reload_t >= _reload_d:
			_reload_t = -1.0

	var armed: bool = _weapon != Held.BINOCULARS
	var aim_e: float = _aim * _aim * (3.0 - 2.0 * _aim)
	var aim_gun: float = aim_e * (1.0 - bell)
	var run: float = clampf(spd / RUN_SPEED, 0.0, 1.0)
	var kneel: float = _crouch * (1.0 - _move)
	var squat: float = _crouch * _move
	var amp: float = lerpf(0.0, 0.85, pow(run, 0.8)) * (1.0 - 0.45 * squat) * _move
	var breathe: float = sin(_time * 1.7)

	# --- legs; the hip height puts the lowest foot (or the kneeling knee) on the ground
	var depth: float = 0.0
	for side in 2:
		var ph: float = _phase + PI * float(side)
		var th: float = sin(ph) * amp + 1.0 * squat
		var knee: float = -(0.06 + maxf(0.0, cos(ph)) * amp * 1.5) - 0.95 * squat
		var kp: Vector2 = KNEEL_L if side == 0 else KNEEL_R
		th = lerpf(th, kp.x, kneel)
		knee = lerpf(knee, kp.y, kneel)
		th = lerpf(th, 0.30 if side == 0 else 0.12, death_e)
		knee = lerpf(knee, -0.55 if side == 0 else -0.25, death_e)
		_thigh[side].rotation = Vector3(th, 0.0, 0.0)
		_shin[side].rotation = Vector3(knee, 0.0, 0.0)
		depth = maxf(depth, Rig.LEG_UPPER * cos(th) + Rig.LEG_LOWER * cos(th + knee))
		depth = maxf(depth, Rig.LEG_UPPER * cos(th) + KNEE_CAP)
	depth = lerpf(depth, Rig.HIP_Y, death_e)
	var stance: float = Rig.BLADE * aim_e * (1.0 if armed else 0.0) * (1.0 - 0.5 * _move)
	_hips.position = Vector3(0.0, depth, 0.0)
	_hips.rotation = Vector3(0.0, stance + sin(_phase) * 0.05 * amp, 0.0)

	# --- torso
	var rec: float = _recoil * _recoil
	# aiming: the torso carries most of the look pitch so the gun keeps its hold and the arms do not stretch
	var torso_pitch: float = Rig.AIM_LEAN * aim_gun + _pitch * 0.12 - 0.10 * run - 0.08 * squat + 0.012 * breathe
	torso_pitch += rec * 0.05 * aim_e - flinch * 0.22 - 0.10 * death_e
	var torso_roll: float = sin(_phase) * 0.03 * amp + (sin(_hit_t * 50.0) * 0.06 * flinch if _hit_t >= 0.0 else 0.0)
	var torso_yaw: float = -sin(_phase) * 0.07 * amp
	_torso.position = Vector3(0.0, 0.003 * breathe, rec * 0.02 * aim_e)
	# the aim share of the pitch turns about the root X axis (not the bladed one), exactly like the gun
	var aim_axis: Vector3 = Basis(Vector3.UP, -_hips.rotation.y) * Vector3.RIGHT
	_torso.basis = Basis(aim_axis, _pitch * AIM_TORSO_PITCH * aim_gun) * Basis.from_euler(Vector3(torso_pitch, torso_yaw, torso_roll))
	var tb: Basis = _torso.basis

	# --- held item and arms
	var gun_xf: Transform3D
	var show_gun: bool = armed or _aim > 0.5
	var poses: Dictionary = _held["poses"]
	if armed:
		var aim_xf: Transform3D = Rig.aim_xf(tb, _hips.rotation.y, _pitch, _held["anchor"], Rig.POCKET)
		var low: Transform3D = poses["low"]["xf"]
		low.origin.y += sin(_phase * 2.0) * 0.012 * _move
		low.origin.x += sin(_phase) * 0.012 * _move
		gun_xf = _blend(low, aim_xf, aim_e)
		if bell > 0.0:
			var rl: Transform3D = poses["reload"]["xf"]
			var jig: float = sin(clampf(_reload_t / _reload_d, 0.0, 1.0) * TAU * 3.0) * 0.025 * bell
			rl.origin.y += jig
			gun_xf = _blend(gun_xf, rl, bell)
		if death_e > 0.0:
			gun_xf = _blend(gun_xf, poses["dead"]["xf"], death_e)
		gun_xf = gun_xf * Transform3D(Basis(Vector3.RIGHT, rec * 0.14), Vector3(0.0, rec * 0.01, rec * 0.07))
		gun_xf.origin.y -= flinch * 0.03
	else:
		var eyes: Vector3 = Vector3(0.0, Rig.NECK_Y, 0.0) + Rig.EYE
		gun_xf = Rig.aim_xf(tb, _hips.rotation.y, _pitch, _held["anchor"], eyes)
	_set_full_arms(not show_gun)
	_gun.transform = gun_xf
	if show_gun:
		var key: String = "aim"
		if armed:
			key = "reload" if bell > 0.5 else ("aim" if aim_e > 0.5 else "low")
			if death_e > 0.3:
				key = "dead"
		if key != _pose_key:
			_pose_key = key
			_gun.mesh = poses[key]["mesh"]
		var elbows: Array = poses[_pose_key]["elbows"]
		for side in 2:
			_point_arm(_arm[side], Rig.shoulder(side), gun_xf * (elbows[side] as Vector3))
	else:
		var swing: float = sin(_phase) * amp * 0.9
		var raise: float = smoothstep(0.0, 0.5, _aim) * 1.1
		for side in 2:
			var sx: float = -1.0 if side == 0 else 1.0
			var sw: float = swing * (-1.0 if side == 0 else 1.0)
			_arm[side].position = Rig.shoulder(side)
			_arm[side].basis = Basis(Vector3.RIGHT, sw + raise - 0.12 * squat + 0.35 * death_e) * Basis(Vector3.BACK, sx * (0.07 + 0.25 * death_e))

	# --- head: faces the look direction, laid on the stock when aiming
	var hp: float = _pitch * lerpf(0.55, 0.9, aim_e) + flinch * 0.3 + 0.25 * death_e
	var hr: float = 0.0
	if armed:
		hp += HEAD_CHEEK.x * aim_gun
		hr += HEAD_CHEEK.z * aim_gun
	var head_root: Basis = Basis.from_euler(Vector3(hp, sin(_phase) * 0.04 * amp, hr))
	_head.basis = (Basis(Vector3.UP, _hips.rotation.y) * tb).inverse() * head_root

	# --- death fall
	_body.rotation = Vector3(DEATH_ROT * death_e, 0.0, 0.0)
	_body.position = Vector3(0.0, DEATH_LIFT * death_e, 0.0)

	# --- markers follow the model
	var chain: Transform3D = _body.transform * _hips.transform * _torso.transform
	_muzzle.transform = chain * gun_xf * Transform3D(Basis.IDENTITY, _held["muzzle"])
	_name_anchor.position = chain * Vector3(0.0, Rig.NECK_Y, 0.0) + Vector3(0.0, Rig.ANCHOR_UP, 0.0)


static func _blend(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var q: Quaternion = a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)
	return Transform3D(Basis(q), a.origin.lerp(b.origin, t))


## Upper arm from the shoulder to the elbow of the held item (stretched to fit).
func _point_arm(arm: MeshInstance3D, shoulder: Vector3, elbow: Vector3) -> void:
	var d: Vector3 = elbow - shoulder
	var dist: float = d.length()
	arm.position = shoulder
	if dist < 0.05:
		return
	var q: Quaternion = Quaternion(Vector3.DOWN, d / dist)
	arm.basis = Basis(q) * Basis.from_scale(Vector3(1.0, clampf(dist / Rig.UPPER_ARM, 0.6, 1.5), 1.0))


# --- muzzle flash ----------------------------------------------------------------------------------

static func _build_flash() -> ArrayMesh:
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
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return fk.build(m)
