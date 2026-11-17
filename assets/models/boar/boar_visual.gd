extends BoarVisualBase
## HD wild boar: script of boar_visual.tscn (contract docs/arquitetura.md 7.1).
## Rigid parts, no skeleton: Rig (trunk + mane, tail, far LOD), Head (contract node, turns about the neck),
## four leg pivots. Three LODs by visibility_range (near <= 25 m, mid 25-60 m, far > 60 m: one mesh, no legs),
## the ranges stretched by the camera zoom (scope) so a scoped boar keeps its detail.
## Meshes and the one material per type come from boar_hd_model.gd (static cache, shared by every instance).
## Forward -Z, origin on the ground; the root transform belongs to gameplay.

const Model := preload("res://assets/models/boar/boar_hd_model.gd")

const NEAR_END_M: float = 25.0
const MID_END_M: float = 60.0
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
const GALLOP_OFFSETS: Array[float] = [0.0, 0.12, 0.55, 0.66]
const WALK_DUTY: float = 0.65
const TROT_DUTY: float = 0.5
const GALLOP_DUTY: float = 0.38
const TROT_FROM_MPS: float = 1.6
const TROT_FULL_MPS: float = 2.4
const GALLOP_FROM_MPS: float = 4.8
const GALLOP_FULL_MPS: float = 5.2
const STRIDE_BASE_M: float = 0.5
const STRIDE_PER_MPS: float = 0.16
const STRIDE_MAX_M: float = 2.1
const MOVE_EPS_MPS: float = 0.08

const ALERT_S: float = 1.0
const ATTACK_S: float = 0.4
const HIT_S: float = 0.15
const DEATH_S: float = 0.7
const SCRAPE_HZ: float = 2.2
const HIND_SWING: float = 0.8

static var last_build_ms: float = 0.0

var _type: StringName = &""
var _weight: float = 100.0
var _bucket: int = -1

var _rig: Node3D
var _body: Array[MeshInstance3D] = []
var _far: MeshInstance3D
var _tail: Node3D
var _tail_m: Array[MeshInstance3D] = []
var _head: Node3D
var _head_m: Array[MeshInstance3D] = []
var _legs: Array[Node3D] = []
var _leg_m: Array = []          # per leg: [near, mid]
var _all: Array[MeshInstance3D] = []

var _speed: float = 0.0
var _speed_smooth: float = 0.0
var _cycle: float = 0.0
var _eating: bool = false
var _wounded: bool = false
var _highlight: bool = false
var _charge_latch: bool = false
var _scraping: bool = false
var _scrape_t: float = 0.0
var _alert_t: float = 0.0
var _attack_t: float = 0.0
var _hit_t: float = 0.0
var _hit_zone: StringName = &""
var _dead: bool = false
var _death_t: float = 0.0
var _time: float = 0.0
var _zoom_k: float = 1.0


func _init() -> void:
	_build_nodes()


func _ready() -> void:
	if _type == &"":
		setup(Ids.BOAR, REFERENCE_WEIGHT_KG)
	_apply_ranges(1.0)
	_time = fposmod(float(get_instance_id() % 997) * 0.37, 10.0)


func _new_mesh(parent: Node3D, node_name: String, shadow: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_all.append(mi)
	return mi


func _build_nodes() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_body = [_new_mesh(_rig, "BodyNear", true), _new_mesh(_rig, "BodyMid", true)]
	_far = _new_mesh(_rig, "Far", true)
	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Model.TAIL_ROOT
	_rig.add_child(_tail)
	_tail_m = [_new_mesh(_tail, "Near", false), _new_mesh(_tail, "Mid", false)]
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Model.HEAD_REST
	add_child(_head)
	_head_m = [_new_mesh(_head, "Near", false), _new_mesh(_head, "Mid", false)]
	for i in 4:
		var pivot: Node3D = Node3D.new()
		pivot.name = LEG_NAMES[i]
		pivot.position = Model.LEG_HIPS[i]
		add_child(pivot)
		_legs.append(pivot)
		_leg_m.append([_new_mesh(pivot, "Near", false), _new_mesh(pivot, "Mid", false)])


## LOD ranges, stretched by `k` (>= 1 when the camera zooms in).
func _apply_ranges(k: float) -> void:
	_zoom_k = k
	var near_end: float = NEAR_END_M * k
	var mid_end: float = MID_END_M * k
	var sets: Array = [_body, _tail_m, _head_m]
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

func setup(type_id: StringName, weight_kg: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var t: StringName = type_id if type_id in [Ids.PIGLET, Ids.SOW, Ids.BOAR, Ids.ALPHA] else Ids.BOAR
	var bucket: int = Model.tusk_bucket(t, weight_kg)
	_weight = weight_kg
	if t == _type and bucket == _bucket:
		return
	_type = t
	_bucket = bucket
	var meshes: Dictionary = Model.get_set(t, bucket)
	for i in 2:
		_body[i].mesh = (meshes["body"] as Array)[i]
		_head_m[i].mesh = (meshes["head"] as Array)[i]
		_tail_m[i].mesh = (meshes["tail"] as Array)[i]
		for leg in 4:
			((_leg_m[leg] as Array)[i] as MeshInstance3D).mesh = (meshes["leg_f" if leg < 2 else "leg_h"] as Array)[i]
	_far.mesh = meshes["far"]
	last_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if _highlight:
		set_highlight(true)


func set_locomotion(speed_mps: float) -> void:
	_speed = clampf(speed_mps, 0.0, 30.0)
	if _speed > 0.05:
		_scraping = false
		_eating = false
	else:
		_charge_latch = false


func set_eating(on: bool) -> void:
	_eating = on
	if on:
		_scraping = false
		_charge_latch = false


func set_wounded(on: bool) -> void:
	_wounded = on


func set_highlight(on: bool) -> void:
	_highlight = on
	var ov: Material = Model.get_highlight_material() if on else null
	for mi in _all:
		mi.material_override = ov


func play_alert() -> void:
	if _dead:
		return
	_alert_t = ALERT_S
	_scraping = false
	_charge_latch = false


func play_scrape() -> void:
	if _dead:
		return
	if not _scraping:
		_scrape_t = 0.0
	_scraping = true
	_charge_latch = true
	_eating = false


func play_attack() -> void:
	if _dead:
		return
	_attack_t = ATTACK_S
	_scraping = false


func play_hit(zone: StringName) -> void:
	if _dead:
		return
	_hit_t = HIT_S
	_hit_zone = zone


func play_death() -> void:
	if _dead:
		return
	_dead = true
	_death_t = 0.0
	_scraping = false
	_eating = false
	_attack_t = 0.0
	_alert_t = 0.0
	_hit_t = 0.0


# --- animation ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var far: bool = _update_camera()
	if _dead:
		_death_t = minf(_death_t + delta / DEATH_S, 1.0)
		_pose_death(_death_t)
		if _death_t >= 1.0:
			set_process(false)
		return
	_speed_smooth = lerpf(_speed_smooth, _speed, clampf(delta * 10.0, 0.0, 1.0))
	var s: float = _speed_smooth
	var moving: bool = s > MOVE_EPS_MPS
	var stride: float = clampf(STRIDE_BASE_M + STRIDE_PER_MPS * s, STRIDE_BASE_M, STRIDE_MAX_M)
	if moving:
		_cycle = fposmod(_cycle + delta * s / stride, 1.0)
	_alert_t = maxf(_alert_t - delta, 0.0)
	_attack_t = maxf(_attack_t - delta, 0.0)
	_hit_t = maxf(_hit_t - delta, 0.0)
	if _scraping:
		_scrape_t += delta

	var w_trot: float = smoothstep(TROT_FROM_MPS, TROT_FULL_MPS, s)
	var w_gal: float = smoothstep(GALLOP_FROM_MPS, GALLOP_FULL_MPS, s)
	var duty: float = lerpf(lerpf(WALK_DUTY, TROT_DUTY, w_trot), GALLOP_DUTY, w_gal)

	# --- body ---
	var bob: float = 0.0
	var pitch: float = 0.0
	var roll: float = 0.0
	var shift: Vector3 = Vector3.ZERO
	var c2: float = _cycle * TAU
	if moving:
		var amt: float = clampf(s / 1.2, 0.0, 1.0)
		bob = (sin(c2 * 2.0) * 0.008 * (1.0 - w_gal) + sin(c2 + 0.6) * 0.035 * w_gal) * amt
		pitch = sin(c2 + 0.2) * 0.065 * w_gal + sin(c2 * 2.0) * 0.008 * (1.0 - w_gal) * amt
		roll = sin(c2) * 0.02 * (1.0 - w_trot) * amt
	else:
		bob = sin(_time * 1.9) * 0.003      # breathing

	# --- head (pitch +: snout up), offsets in rig space at the neck ---
	var hp: float = 0.0
	var hy: float = 0.0
	var hr: float = 0.0
	var hoff: Vector3 = Vector3.ZERO
	var tail_pitch: float = -0.12
	var tail_yaw: float = 0.0
	if _eating and not moving:
		hp = -0.86 + sin(_time * 6.0) * 0.07 + sin(_time * 2.1) * 0.04
		hy = sin(_time * 2.3) * 0.13
		hoff = Vector3(0.0, -0.06, 0.0)
		pitch -= 0.06
		bob -= 0.02
		tail_yaw = sin(_time * 3.1) * 0.4 * maxf(sin(_time * 0.6), 0.0)
	elif _scraping:
		var snort: float = maxf(sin(_scrape_t * 5.5), 0.0) * maxf(sin(_scrape_t * 1.3), 0.0)
		hp = -0.42 - snort * 0.12
		hy = sin(_scrape_t * 1.7) * 0.06
		hoff = Vector3(0.0, -0.04, 0.0)
		pitch -= 0.07
		bob -= 0.03
		shift.z += 0.03
		tail_pitch = -0.6
		tail_yaw = sin(_scrape_t * 13.0) * 0.5
	elif _charge_latch and moving:
		hp = -0.38 + sin(c2 * 2.0) * 0.04
		hoff = Vector3(0.0, -0.035, 0.0)
		pitch -= 0.04
		tail_pitch = -1.15
		tail_yaw = sin(c2 * 2.0) * 0.25
	elif moving:
		hp = -0.06 + sin(c2 * 2.0 + 0.5) * 0.04 * (1.0 - w_gal) - 0.12 * w_gal + sin(c2 + 1.2) * 0.06 * w_gal
		tail_pitch = lerpf(-0.2, -1.2, w_gal) + sin(c2 * 2.0) * 0.1
		tail_yaw = sin(c2) * 0.25 * (1.0 - w_gal)
	elif _alert_t > 0.0:
		var a: float = sin(clampf(_alert_t / ALERT_S, 0.0, 1.0) * PI)
		a = minf(a * 1.6, 1.0)
		hp = 0.34 * a
		hy = sin(_time * 3.0) * 0.12 * a
		hoff = Vector3(0.0, 0.03 * a, 0.0)
		pitch += 0.04 * a
		bob += 0.01 * a
		tail_pitch = -1.2 * a - 0.12
	else:
		hp = -0.1 + sin(_time * 1.3) * 0.05 + maxf(sin(_time * 0.37), 0.0) * -0.12
		hy = sin(_time * 0.45) * 0.18 * maxf(sin(_time * 0.21 + 1.0), 0.0)
		tail_yaw = sin(_time * 2.6) * 0.35 * maxf(sin(_time * 0.5), 0.0)

	if _attack_t > 0.0:
		var t: float = 1.0 - _attack_t / ATTACK_S
		var dip: float = smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.55, t))
		var hook: float = smoothstep(0.3, 0.55, t) * (1.0 - smoothstep(0.65, 1.0, t))
		hp = lerpf(hp, -0.55, dip)
		hp = lerpf(hp, 0.36, hook)
		hy += 0.32 * hook
		hr = 0.25 * hook
		shift.z -= 0.05 * dip + 0.16 * hook
		pitch += 0.06 * hook - 0.04 * dip
		bob -= 0.02 * dip

	if _hit_t > 0.0:
		var h: float = sin(_hit_t / HIT_S * PI * 0.5)
		match _hit_zone:
			Ids.ZONE_HEAD:
				hp += 0.28 * h
				hy -= 0.16 * h
				shift.z += 0.03 * h
			Ids.ZONE_REAR:
				pitch += 0.1 * h
				shift.z -= 0.04 * h
				bob -= 0.02 * h
			_:
				roll += 0.09 * h
				shift.x += 0.035 * h
				pitch -= 0.04 * h
				hp += 0.1 * h

	if _wounded:
		pitch -= 0.03
		roll -= 0.03
		bob -= 0.015
		if moving:
			# the head jerks up when the bad front leg lands
			var p_fl: float = fposmod(_cycle + _offset(LEG_FL, w_trot, w_gal), 1.0)
			var on_bad: float = sin(clampf(p_fl / duty, 0.0, 1.0) * PI) if p_fl < duty else 0.0
			hp += 0.12 * on_bad
			bob += 0.02 * on_bad
			roll -= 0.03 * on_bad

	var rig: Transform3D = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0.0, bob, 0.0) + shift)
	_rig.transform = rig
	_tail.transform = Transform3D(Basis.from_euler(Vector3(tail_pitch, tail_yaw, 0.0)), Model.TAIL_ROOT)
	_head.transform = rig * Transform3D(Basis.IDENTITY, Model.NECK_PIVOT + hoff) \
		* Transform3D(Basis.from_euler(Vector3(hp, hy, hr)), Model.HEAD_REST - Model.NECK_PIVOT)
	if far:
		return

	# --- legs: planted while on the ground, lifted while swinging ---
	var stance_half: float = stride * duty * 0.5
	for i in 4:
		var hip: Vector3 = Model.LEG_HIPS[i]
		var length: float = hip.y
		var amp: float = asin(clampf(stance_half / length, 0.0, 0.8)) if moving else 0.0
		var swing: float = 0.0
		var lift: float = 0.0
		var plant: float = 1.0 - 0.5 * w_gal
		if moving:
			var ph: float = fposmod(_cycle + _offset(i, w_trot, w_gal), 1.0)
			# the hind legs swing less: their ham would leave the trunk behind
			var a: float = amp * (0.45 if _wounded and i == LEG_FL else (HIND_SWING if i >= LEG_RL else 1.0))
			if ph < duty:
				swing = lerpf(a, -a, ph / duty)
			else:
				var q: float = (ph - duty) / (1.0 - duty)
				swing = lerpf(-a, a, smoothstep(0.0, 1.0, q))
				lift = sin(q * PI) * clampf(0.04 + 0.012 * s, 0.0, 0.13) * (0.5 if _wounded and i == LEG_FL else 1.0)
		elif _wounded and i == LEG_FL:
			swing = 0.12
			lift = 0.03
		if _scraping and i == LEG_FL:
			var q2: float = fposmod(_scrape_t * SCRAPE_HZ, 1.0)
			if q2 < 0.45:
				var u: float = q2 / 0.45
				swing = lerpf(-0.30, 0.45, smoothstep(0.0, 1.0, u))
				lift = sin(u * PI) * 0.09
			else:
				swing = lerpf(0.45, -0.30, (q2 - 0.45) / 0.55)
		if _eating and not moving and i < 2:
			swing = 0.08
		var total: float = swing + pitch
		var at: Vector3 = rig * hip
		var ground_y: float = length * cos(total) + lift
		var y: float = lerpf(at.y + lift, ground_y, plant)
		y = clampf(y, at.y - 0.12, at.y + 0.1)
		_legs[i].transform = Transform3D(Basis.from_euler(Vector3(total, 0.0, roll)), Vector3(at.x, y, at.z))


func _offset(leg: int, w_trot: float, w_gal: float) -> float:
	return lerpf(lerpf(WALK_OFFSETS[leg], TROT_OFFSETS[leg], w_trot), GALLOP_OFFSETS[leg], w_gal)


## Updates the zoom-stretched LOD ranges; true when the boar is drawn with the far mesh (legs not animated).
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


func _pose_death(t: float) -> void:
	var buckle: float = smoothstep(0.0, 0.35, t)
	var fall: float = smoothstep(0.12, 1.0, t)
	fall = fall * fall * (2.0 - fall)
	var side: Vector3 = Vector3(0.235, 0.0, 0.0)
	var roll: Basis = Basis(Vector3.BACK, -fall * PI * 0.5)
	var drop: Vector3 = Vector3(0.0, -0.07 * buckle * (1.0 - fall), 0.0)
	var rig: Transform3D = Transform3D(Basis.IDENTITY, side + drop) * Transform3D(roll, Vector3.ZERO) \
		* Transform3D(Basis(Vector3.RIGHT, -0.05 * buckle), -side)
	_rig.transform = rig
	_tail.transform = Transform3D(Basis.from_euler(Vector3(-0.15 - 0.3 * fall, 0.0, 0.0)), Model.TAIL_ROOT)
	_head.transform = rig * Transform3D(Basis.IDENTITY, Model.NECK_PIVOT) \
		* Transform3D(Basis.from_euler(Vector3(-0.12 * buckle + 0.05 * fall, -0.3 * fall, 0.0)), Model.HEAD_REST - Model.NECK_PIVOT)
	for i in 4:
		var front: bool = i < 2
		var swing: float = lerpf(0.0, -0.5 if front else 0.35, buckle * (1.0 - fall)) + (0.35 if front else -0.3) * fall
		var droop: float = (0.18 if Model.LEG_HIPS[i].x < 0.0 else 0.05) * fall
		_legs[i].transform = rig * Transform3D(Basis.from_euler(Vector3(swing, 0.0, droop)), Model.LEG_HIPS[i])
