extends DogVisualBase
## HD dog (prototype of dog_visual.gd, contract docs/arquitetura.md 7.2). Rigid parts, no skeleton: Rig (trunk, tail,
## far LOD), Head (turns about the neck pivot) with Ears, four leg pivots, Mouth marker on the nose tip.
## Three LODs by visibility_range (near <= 20 m, mid 20-50 m, far > 50 m: one mesh, no legs), the ranges stretched by
## the camera zoom (scope) like the HD boar. Meshes and the one shared material come from dog_hd_model.gd (static
## cache per breed). Forward -Z, origin on the ground; the root transform belongs to gameplay.

const Model := preload("res://assets/models/dog/dog_hd_model.gd")

const NEAR_END_M: float = 20.0
const MID_END_M: float = 50.0
const LOD_MARGIN_M: float = 1.0
## Fallback camera FOV with no zoom; the real value is data/game.json player.base_fov_deg (read through Data).
const BASE_FOV_DEG: float = 75.0
const ZOOM_EPS: float = 0.03

const LEG_FL: int = 0
const LEG_FR: int = 1
const LEG_RL: int = 2
const LEG_RR: int = 3
const LEG_NAMES: Array[String] = ["LegFL", "LegFR", "LegRL", "LegRR"]

## Gaits: phase offset per leg [FL, FR, RL, RR] and duty factor (share of the cycle on the ground).
const WALK_OFFSETS: Array[float] = [0.25, 0.75, 0.0, 0.5]
const TROT_OFFSETS: Array[float] = [0.0, 0.5, 0.5, 0.0]
const GALLOP_OFFSETS: Array[float] = [0.0, 0.1, 0.52, 0.62]
const WALK_DUTY: float = 0.62
const TROT_DUTY: float = 0.45
const GALLOP_DUTY: float = 0.34
const TROT_FROM_MPS: float = 1.5
const TROT_FULL_MPS: float = 2.2
const GALLOP_FROM_MPS: float = 4.6
const GALLOP_FULL_MPS: float = 5.4
## Stride for a 0.52 m dog (scaled by the withers height).
const STRIDE_BASE_M: float = 0.42
const STRIDE_PER_MPS: float = 0.2
const STRIDE_MAX_M: float = 2.6
const MOVE_EPS_MPS: float = 0.08
const MAX_SWING: float = 0.62
## The legs are rigid: lifting a whole leg more than this pushes its shoulder / thigh out of the trunk.
const MAX_LIFT_M: float = 0.045

const BARK_S: float = 0.3
const HURT_S: float = 0.3

static var last_build_ms: float = 0.0

var _breed: StringName = &""
var _lay: Dictionary = {}
var _spec: Dictionary = {}

var _rig: Node3D
var _body: Array[MeshInstance3D] = []
var _far: MeshInstance3D
var _tail: Node3D
var _tail_m: Array[MeshInstance3D] = []
var _head: Node3D
var _head_m: Array[MeshInstance3D] = []
var _ears: Node3D
var _ears_m: Array[MeshInstance3D] = []
var _legs: Array[Node3D] = []
var _leg_m: Array = []          # per leg: [near, mid]
var _mouth: Marker3D

var _speed: float = 0.0
var _speed_smooth: float = 0.0
var _cycle: float = 0.0
var _time: float = 0.0
var _retreat_on: bool = false
var _retreat: float = 0.0
var _biting: bool = false
var _bite: float = 0.0
var _pointing: bool = false
var _point: float = 0.0
var _bark_t: float = -1.0
var _hurt_t: float = -1.0
var _zoom_k: float = 1.0


func _init() -> void:
	_build_nodes()


func _ready() -> void:
	if _breed == &"":
		setup(&"caramelo")
	_apply_ranges(1.0)
	_time = fposmod(float(get_instance_id() % 997) * 0.37, 10.0)


func _new_mesh(parent: Node3D, node_name: String, shadow: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, node_name: String) -> Node3D:
	var n: Node3D = Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


func _build_nodes() -> void:
	_rig = _pivot(self, "Rig")
	_body = [_new_mesh(_rig, "BodyNear", true), _new_mesh(_rig, "BodyMid", true)]
	_far = _new_mesh(_rig, "Far", true)
	_tail = _pivot(_rig, "Tail")
	_tail_m = [_new_mesh(_tail, "Near", false), _new_mesh(_tail, "Mid", false)]
	_head = _pivot(self, "Head")
	_head_m = [_new_mesh(_head, "Near", false), _new_mesh(_head, "Mid", false)]
	_ears = _pivot(_head, "Ears")
	_ears_m = [_new_mesh(_ears, "Near", false), _new_mesh(_ears, "Mid", false)]
	for i in 4:
		var pivot: Node3D = _pivot(self, LEG_NAMES[i])
		_legs.append(pivot)
		_leg_m.append([_new_mesh(pivot, "Near", false), _new_mesh(pivot, "Mid", false)])
	_mouth = Marker3D.new()
	_mouth.name = "Mouth"
	add_child(_mouth)


## LOD ranges, stretched by `k` (>= 1 when the camera zooms in).
func _apply_ranges(k: float) -> void:
	_zoom_k = k
	var near_end: float = NEAR_END_M * k
	var mid_end: float = MID_END_M * k
	var sets: Array = [_body, _tail_m, _head_m, _ears_m]
	for l: Array in _leg_m:
		sets.append(l)
	for pair: Array in sets:
		var near: MeshInstance3D = pair[0]
		var mid: MeshInstance3D = pair[1]
		near.visibility_range_end = near_end
		near.visibility_range_end_margin = LOD_MARGIN_M
		mid.visibility_range_begin = near_end
		mid.visibility_range_begin_margin = LOD_MARGIN_M
		mid.visibility_range_end = mid_end
		mid.visibility_range_end_margin = LOD_MARGIN_M
	_far.visibility_range_begin = mid_end
	_far.visibility_range_begin_margin = LOD_MARGIN_M


# --- API ---------------------------------------------------------------------------------------------------

func setup(breed_id: StringName) -> void:
	var t0: int = Time.get_ticks_usec()
	var b: StringName = Model.breed_or_default(breed_id)
	if b == _breed:
		return
	_breed = b
	_spec = Model.spec(b)
	_lay = Model.layout(b)
	var meshes: Dictionary = Model.get_set(b)
	for i in 2:
		_body[i].mesh = (meshes["body"] as Array)[i]
		_head_m[i].mesh = (meshes["head"] as Array)[i]
		_ears_m[i].mesh = (meshes["ears"] as Array)[i]
		_tail_m[i].mesh = (meshes["tail"] as Array)[i]
		for leg in 4:
			((_leg_m[leg] as Array)[i] as MeshInstance3D).mesh = (meshes[Model.PARTS[4 + leg]] as Array)[i]
	_far.mesh = meshes["far"]
	_tail.position = _lay["tail"]
	_ears.transform = _lay["ears"]
	_head.position = _lay["np"]
	for i in 4:
		_legs[i].position = (_lay["hips"] as Array)[i]
	_mouth.position = _head.position + (_lay["mouth"] as Vector3)
	last_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func set_locomotion(speed_mps: float) -> void:
	_speed = clampf(speed_mps, 0.0, 30.0)
	if _speed > 0.05:
		_pointing = false


func set_retreating(on: bool) -> void:
	_retreat_on = on


func play_bark() -> void:
	_bark_t = 0.0


func play_bite(on: bool) -> void:
	_biting = on


func play_hurt() -> void:
	_hurt_t = 0.0


func play_point() -> void:
	_pointing = true
	_speed = 0.0


# --- animation ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _breed == &"":
		return
	_time += delta
	var far: bool = _update_camera()
	var h: float = _spec["h"]
	var hs: float = h / 0.52
	_speed_smooth = lerpf(_speed_smooth, _speed, clampf(delta * 8.0, 0.0, 1.0))
	var s: float = _speed_smooth
	var moving: bool = s > MOVE_EPS_MPS
	var stride: float = clampf(STRIDE_BASE_M + STRIDE_PER_MPS * s, STRIDE_BASE_M, STRIDE_MAX_M) * hs
	if moving:
		_cycle = fposmod(_cycle + delta * s / stride, 1.0)
	_retreat = move_toward(_retreat, 1.0 if _retreat_on else 0.0, delta * 4.0)
	_bite = move_toward(_bite, 1.0 if _biting else 0.0, delta * 6.0)
	_point = move_toward(_point, 1.0 if _pointing and not moving else 0.0, delta * 5.0)

	var w_trot: float = smoothstep(TROT_FROM_MPS, TROT_FULL_MPS, s)
	var w_gal: float = smoothstep(GALLOP_FROM_MPS, GALLOP_FULL_MPS, s)
	var duty: float = lerpf(lerpf(WALK_DUTY, TROT_DUTY, w_trot), GALLOP_DUTY, w_gal)
	var c2: float = _cycle * TAU

	# --- body ---
	var bob: float = 0.0
	var pitch: float = 0.0     # + = nose up
	var roll: float = 0.0
	var shift: Vector3 = Vector3.ZERO
	if moving:
		var amt: float = clampf(s / 1.0, 0.0, 1.0)
		bob = (sin(c2 * 2.0) * 0.006 * (1.0 - w_gal) + sin(c2 - 0.4) * 0.03 * w_gal) * amt * hs
		pitch = sin(c2 + 0.3) * 0.075 * w_gal + sin(c2 * 2.0) * 0.006 * (1.0 - w_gal) * amt
		roll = sin(c2) * 0.022 * (1.0 - w_trot) * amt
	else:
		bob = sin(_time * 2.4) * 0.0025 * hs      # breathing

	# --- head (pitch +: nose up), tail (pitch +: tip back / down for the up-carried tails), ears (+: back) ---
	var hp: float = 0.0
	var hy: float = 0.0
	var hr: float = 0.0
	var hoff: Vector3 = Vector3.ZERO
	var tail_pitch: float = 0.0
	var tail_yaw: float = 0.0
	var ear: float = 0.0
	var ear_back: float = _spec["ear_back"]
	if moving:
		hp = sin(c2 * 2.0 + 0.6) * 0.035 * (1.0 - w_gal) - 0.16 * w_gal + sin(c2 + 1.4) * 0.07 * w_gal
		hoff = Vector3(0.0, -0.02 * w_gal, -0.02 * w_gal) * hs
		tail_pitch = float(_spec["tail_run"]) * w_gal * 0.8 + sin(c2 * 2.0) * 0.08
		tail_yaw = sin(c2) * 0.3 * (1.0 - w_gal)
		ear = sin(c2 * 2.0 + 1.0) * 0.12 * w_gal * signf(ear_back) + 0.25 * w_gal * signf(ear_back)
	else:
		# idle: looks around, sniffs, wags now and then
		hp = sin(_time * 0.9) * 0.05 + maxf(sin(_time * 0.31), 0.0) * -0.18
		hy = sin(_time * 0.47) * 0.35 * maxf(sin(_time * 0.23 + 1.0), 0.0)
		tail_yaw = sin(_time * 9.0) * 0.35 * maxf(sin(_time * 0.6), 0.0)
		ear = maxf(sin(_time * 1.7), 0.0) * 0.06 * signf(ear_back)

	# point: frozen, nose forward on the scent line, tail stiff behind, a fore paw lifted
	if _point > 0.0:
		var p: float = _point
		hp = lerpf(hp, -0.08 + sin(_time * 23.0) * 0.006, p)
		hy = lerpf(hy, 0.0, p)
		hoff = hoff.lerp(Vector3(0.0, -0.01, -0.03) * hs, p)
		pitch -= 0.04 * p
		shift.z -= 0.02 * p * hs
		tail_pitch = lerpf(tail_pitch, float(_spec["tail_point"]), p)
		tail_yaw *= 1.0 - p
		ear = lerpf(ear, -0.12 * signf(ear_back), p)

	# bite: holding on, head low and shaking, body pulling back, tail going
	if _bite > 0.0:
		var bt: float = _bite
		hp = lerpf(hp, -0.30 + sin(_time * 27.0) * 0.06, bt)
		hy = lerpf(hy, sin(_time * 25.0) * 0.32, bt)
		hr = lerpf(hr, sin(_time * 25.0 + 0.8) * 0.16, bt)
		hoff = hoff.lerp(Vector3(0.0, -0.05, -0.02) * hs, bt)
		pitch += 0.05 * bt
		shift.z += (0.04 + sin(_time * 12.0) * 0.012) * bt * hs
		bob -= 0.025 * bt * hs
		tail_yaw = lerpf(tail_yaw, sin(_time * 15.0) * 0.45, bt)
		ear = lerpf(ear, ear_back * 0.45, bt)

	# bark: the head snaps up and forward once (~0.3 s)
	if _bark_t >= 0.0:
		_bark_t += delta
		var k: float = sin(clampf(_bark_t / BARK_S, 0.0, 1.0) * PI)
		hp += 0.38 * k
		hoff += Vector3(0.0, 0.015, -0.025) * k * hs
		shift.z += 0.025 * k * hs
		pitch += 0.04 * k
		ear += 0.25 * k * signf(ear_back)
		if _bark_t >= BARK_S:
			_bark_t = -1.0

	# hurt: a flinch to the side, head and tail down (~0.3 s)
	if _hurt_t >= 0.0:
		_hurt_t += delta
		var f: float = 1.0 - clampf(_hurt_t / HURT_S, 0.0, 1.0)
		var j: float = sin(clampf(_hurt_t / HURT_S, 0.0, 1.0) * PI)
		roll += sin(_hurt_t * 55.0) * 0.1 * f
		shift += Vector3(0.03 * j, 0.0, 0.05 * j) * hs
		bob -= 0.03 * j * hs
		hp -= 0.3 * j
		hy += 0.25 * j
		tail_pitch += float(_spec["tail_tuck"]) * 0.5 * j
		ear = lerpf(ear, ear_back, j)
		if _hurt_t >= HURT_S:
			_hurt_t = -1.0

	# retreat: tail tucked, ears pinned back, head and hindquarters low
	if _retreat > 0.0:
		var r: float = _retreat
		hp -= 0.28 * r
		hoff += Vector3(0.0, -0.03, 0.01) * r * hs
		tail_pitch = lerpf(tail_pitch, float(_spec["tail_tuck"]), r)
		tail_yaw *= 1.0 - 0.8 * r
		ear = lerpf(ear, ear_back, r)
		bob -= 0.03 * r * hs
		pitch -= 0.05 * r

	var rig: Transform3D = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0.0, bob, 0.0) + shift)
	_rig.transform = rig
	_tail.transform = Transform3D(Basis.from_euler(Vector3(tail_pitch, tail_yaw, 0.0)), _lay["tail"])
	_head.transform = rig * Transform3D(Basis.from_euler(Vector3(hp, hy, hr)), (_lay["np"] as Vector3) + hoff)
	_ears.transform = (_lay["ears"] as Transform3D) * Transform3D(Basis(Vector3.RIGHT, ear), Vector3.ZERO)
	_mouth.position = _head.transform * (_lay["mouth"] as Vector3)
	if far:
		return

	# --- legs: planted while on the ground, lifted while swinging ---
	var hips: Array = _lay["hips"]
	var stance_half: float = stride * duty * 0.5
	for i in 4:
		var hip: Vector3 = hips[i]
		var length: float = hip.y
		var front: bool = i < 2
		var amp: float = asin(clampf(stance_half / length, 0.0, sin(MAX_SWING))) if moving else 0.0
		var swing: float = 0.0
		var lift: float = 0.0
		if moving:
			var ph: float = fposmod(_cycle + _offset(i, w_trot, w_gal), 1.0)
			var a: float = amp * (1.0 if front else 0.85)
			if ph < duty:
				swing = lerpf(a, -a, ph / duty)
			else:
				var q: float = (ph - duty) / (1.0 - duty)
				swing = lerpf(-a, a, smoothstep(0.0, 1.0, q))
				# gallop: the fore legs reach far forward, the hind legs kick far back
				swing += sin(q * PI) * 0.25 * w_gal * (1.0 if front else -1.0)
				lift = sin(q * PI) * clampf(0.025 + 0.004 * s, 0.0, MAX_LIFT_M) * hs
		if _point > 0.0 and i == LEG_FL:
			swing = lerpf(swing, -0.55, _point)
			lift = lerpf(lift, MAX_LIFT_M * hs, _point)
		if _bite > 0.0:
			# braced: fore legs forward, hind legs back
			swing = lerpf(swing, 0.22 if front else -0.18, _bite)
		if _retreat > 0.0 and not front:
			swing += 0.12 * _retreat
		var total: float = swing + pitch
		var at: Vector3 = rig * hip
		var ground_y: float = length * cos(total) + lift
		var y: float = lerpf(at.y + lift, ground_y, 0.85 - 0.45 * w_gal)
		y = clampf(y, at.y - 0.10 * hs, at.y + MAX_LIFT_M * hs)
		_legs[i].transform = Transform3D(Basis.from_euler(Vector3(total, 0.0, roll)), Vector3(at.x, y, at.z))


func _offset(leg: int, w_trot: float, w_gal: float) -> float:
	return lerpf(lerpf(WALK_OFFSETS[leg], TROT_OFFSETS[leg], w_trot), GALLOP_OFFSETS[leg], w_gal)


## Updates the zoom-stretched LOD ranges; true when the dog is drawn with the far mesh (legs not animated).
func _update_camera() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return false
	var k: float = 1.0
	if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		k = maxf(tan(deg_to_rad(float(Data.get_game().get("player", {}).get("base_fov_deg", BASE_FOV_DEG))) * 0.5) / tan(deg_to_rad(clampf(cam.fov, 1.0, 179.0)) * 0.5), 1.0)
	if absf(k - _zoom_k) > ZOOM_EPS * _zoom_k:
		_apply_ranges(k)
	return cam.global_position.distance_to(global_position) > MID_END_M * _zoom_k + LOD_MARGIN_M
