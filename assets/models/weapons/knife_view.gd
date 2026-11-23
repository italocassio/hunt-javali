extends WeaponViewBase
## First-person hunting knife with the gloved right arm, procedural. Camera space, looking -Z.
## Nodes: Swing (animated) > Body (knife), RightArm; Muzzle (blade tip) and AdsAnchor (required by the base, unused).
## Budget (docs/plano_faca_mochila_folego.md 1.7): 2 MeshInstance3D, 3 materials (the guns' wood and hard surface +
## the arms shader), no shadows, no new shader. Visible at rest in the lower right corner; play_melee() cuts across.

const KnifeHD := preload("res://assets/models/weapons/showcase/knife_hd.gd")
const ArmsHD := preload("res://assets/models/weapons/showcase/arms_hd.gd")
const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")

## Pose = [hand position in camera space, pitch, yaw, roll]. The hand (middle of the handle) is the pivot of the
## knife; pitch up lifts the tip, yaw > 0 turns it toward the left (the screen centre).
const REST: Array = [Vector3(0.200, -0.215, -0.340), 0.55, 0.30, 0.0]
## Windup (drawn back, tip up), strike (the tip crosses the screen centre), follow through (past the centre).
const WINDUP: Array = [Vector3(0.265, -0.205, -0.335), 0.95, 0.05, 0.25]
const STRIKE: Array = [Vector3(0.090, -0.125, -0.470), 0.48, 0.36, -0.10]
const FOLLOW: Array = [Vector3(-0.030, -0.100, -0.520), 0.22, 0.55, -0.45]
## Fractions of the swing at which each key pose is reached (the tip crosses the centre at T_STRIKE).
const T_WINDUP: float = 0.12
const T_STRIKE: float = 0.30
const T_FOLLOW: float = 0.46

const RING_AO_RAYS: int = 6
const RING_AO_RADIUS: float = 0.05

static var _arm_mesh: ArrayMesh = null
static var _arm_tris: int = 0
static var _grip: Vector3 = Vector3.ZERO

var _swing: Node3D
var _body: MeshInstance3D
var _arm: MeshInstance3D
var _muzzle: Marker3D
var _ads: Marker3D
var _t: float = -1.0
var _duration: float = 0.0
var _tip: Vector3 = Vector3.ZERO


func _init() -> void:
	_swing = Node3D.new()
	_swing.name = "Swing"
	add_child(_swing)
	_body = _mi("Body")
	_arm = _mi("RightArm")
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	add_child(_muzzle)
	_ads = Marker3D.new()
	_ads.name = "AdsAnchor"
	_ads.position = Vector3(0.0, 0.0, -0.4)
	add_child(_ads)
	set_process(false)


func _ready() -> void:
	if _body.mesh == null:
		setup(Ids.KNIFE)


func _mi(node_name: String) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swing.add_child(m)
	return m


func setup(_weapon_id: StringName) -> void:
	var model: Dictionary = KnifeHD.get_model()
	_body.mesh = model["body"]
	_tip = model["tip"]
	if _arm_mesh == null:
		_build_arm(model)
	_arm.mesh = _arm_mesh
	_apply(_pose(0.0))


## One knife swing over `duration_s`: windup, strike (tip over the screen centre at T_STRIKE), follow through, back to rest.
func play_melee(duration_s: float) -> void:
	_duration = maxf(duration_s, 0.05)
	_t = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	_t += delta
	if _t >= _duration:
		_t = -1.0
		_apply(_pose(0.0))
		set_process(false)
		return
	_apply(_pose(_t / _duration))


## Hand pose at swing fraction u in 0..1 (0 = rest). Each leg eases: the strike accelerates into the target.
func _pose(u: float) -> Array:
	if u <= 0.0 or u >= 1.0:
		return REST
	if u < T_WINDUP:
		return _mix(REST, WINDUP, smoothstep(0.0, 1.0, u / T_WINDUP))
	if u < T_STRIKE:
		var k: float = (u - T_WINDUP) / (T_STRIKE - T_WINDUP)
		return _mix(WINDUP, STRIKE, k * k)
	if u < T_FOLLOW:
		var k2: float = (u - T_STRIKE) / (T_FOLLOW - T_STRIKE)
		return _mix(STRIKE, FOLLOW, 1.0 - (1.0 - k2) * (1.0 - k2))
	return _mix(FOLLOW, REST, smoothstep(0.0, 1.0, (u - T_FOLLOW) / (1.0 - T_FOLLOW)))


static func _mix(a: Array, b: Array, w: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0] as Vector3, w), lerpf(a[1], b[1], w), lerpf(a[2], b[2], w), lerpf(a[3], b[3], w)]


static func _basis(pose: Array) -> Basis:
	return Basis.from_euler(Vector3(pose[1], pose[2], pose[3]))


func _apply(pose: Array) -> void:
	var b: Basis = _basis(pose)
	_swing.transform = Transform3D(b, (pose[0] as Vector3) - b * _grip)
	_muzzle.position = _swing.transform * _tip


## Camera-space position of the blade tip at swing fraction u (for the preview and the tests).
func get_tip_at(u: float) -> Vector3:
	var pose: Array = _pose(u)
	var b: Basis = _basis(pose)
	return (pose[0] as Vector3) + b * (_tip - _grip)


# --- arm --------------------------------------------------------------------------------------------

## Right arm in knife space: fist around the handle (palm below and to the right, fingers over the top to the left,
## thumb on the left of the top toward the guard), forearm leaving by the lower right of the screen.
func _build_arm(model: Dictionary) -> void:
	var g: Vector3 = model["grip"]
	_grip = g
	var a: Vector3 = Vector3(0.0, 0.0, 1.0)      # along the handle, toward the pommel
	var e0: Vector3 = Vector3.RIGHT
	var e1: Vector3 = Vector3.UP                  # fingers wrap over the top
	var half: Vector2 = Vector2(0.0125, 0.0140)
	var fr: Transform3D = Transform3D(Basis(e0, e1, a), g)
	var rest_inv: Basis = _basis(REST).inverse()
	var wrist: Vector3 = g + e0 * 0.040 - e1 * 0.052 + a * 0.012
	var elbow: Vector3 = g + rest_inv * Vector3(0.10, -0.26, 0.30)
	var shoulder: Vector3 = g + rest_inv * Vector3(0.26, -0.52, 0.62)
	var k: HDMesh = HDMesh.new()
	k.crease_deg = 50.0
	var palm: Array = [
		[ArmsHD._wrap(fr, half, 20.0, 0.004, 0.012), 0.036, 0.010],
		[ArmsHD._wrap(fr, half, -20.0, 0.004, 0.015), 0.040, 0.013],
		[ArmsHD._wrap(fr, half, -55.0, 0.006, 0.018), 0.038, 0.016],
		[(ArmsHD._wrap(fr, half, -55.0, 0.006, 0.018) + wrist) * 0.5, 0.034, 0.019],
	]
	ArmsHD._arm_tube(k, palm, wrist, elbow, shoulder, a, 1.0)
	k.surface(0)
	ArmsHD._paint(k, ArmsHD.GLOVE)
	# four fingers over the top, index nearest the guard (h < 0), pinky nearest the pommel
	for f: Array in [[-0.021, 0.0092, 196.0], [-0.003, 0.0096, 202.0], [0.015, 0.0092, 198.0], [0.032, 0.0084, 186.0]]:
		var h: float = f[0]
		var r: float = f[1]
		var pts: Array = []
		for key: Vector2 in [Vector2(14.0, r + 0.007), Vector2(60.0, r + 0.001), Vector2(110.0, r), Vector2(155.0, r * 0.96), Vector2(f[2], r * 0.9)]:
			pts.append(ArmsHD._wrap(fr, half, key.x, h, key.y))
		ArmsHD._finger(k, pts, r, a)
	ArmsHD._filler(k, Basis(e0, e1, a), g + a * 0.004, Vector3(0.014, 0.016, 0.030), Vector3.ZERO)
	# thumb along the left of the top, pointing at the guard
	ArmsHD._finger(k, [ArmsHD._wrap(fr, half, 20.0, 0.030, 0.012), ArmsHD._wrap(fr, half, 55.0, 0.012, 0.0125),
		ArmsHD._wrap(fr, half, 85.0, -0.012, 0.0125), ArmsHD._wrap(fr, half, 92.0, -0.034, 0.0115)], 0.0105, e0)
	var built: Dictionary = k.build()
	var faces: PackedVector3Array = k.get_faces().duplicate()
	faces.append_array((model["body"] as Mesh).get_faces())
	var tm: TriangleMesh = TriangleMesh.new()
	tm.create_from_faces(faces)
	var near: AABB = (model["body"] as Mesh).get_aabb().grow(RING_AO_RADIUS)
	HDMesh.bake_ao(built, tm, RING_AO_RAYS, RING_AO_RADIUS, 0.6, 0.6, near)
	_arm_mesh = ArrayMesh.new()
	HDMesh.commit(built, _arm_mesh, {0: ArmsHD.get_material()})
	_arm_tris = k.triangle_count()
