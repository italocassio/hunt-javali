extends ItemViewBase
## First-person consumable gestures, procedural, in camera space (eye at the origin, looking -Z).
## One script serves the four scenes (`item_id` is exported on each .tscn):
##   medkit        left forearm across the screen, the right hand winds a bandage twice around it (Wrap = 20 ribbon stages)
##   energy_drink  the can rises to the lower centre, tilts back for two gulps (the last one is the beat)
##   scout_drone   both hands bring the quadcopter up to the chest and push it up and forward; it leaves at the beat
##   corn_bait     the right hand winds back low and lobs the cob underhand; at the beat the hand is empty
## Budget per view (docs/plano_itens_animados.md 2.4): <= 3500 triangles with arms, <= 3 MeshInstance3D, <= 3 materials
## (the arms shader + the prop material), no shadows, no new shader. Rest = off screen below the bottom edge.
## play_use(duration, effect_at) maps the whole gesture onto `duration`: u in 0..effect_at is the build up that ends
## exactly on the beat pose, u in effect_at..1 is the follow through back to rest.

const ArmsHD := preload("res://assets/models/weapons/showcase/arms_hd.gd")
const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Corn := preload("res://assets/models/props/corn_hd.gd")

@export var item_id: StringName = &""

## Beats later than this lose their follow through (the hands could not leave the screen): the visual beat is clamped.
const MAX_VISUAL_BEAT: float = 0.9
const MIN_VISUAL_BEAT: float = 0.15
const FORE_LEN: float = 0.42
const SHOULDER_LEN: float = 0.85

## Key poses: [fraction, camera-space position of the grip centre, euler degrees (x pitch, y yaw, z roll)].
## PRE ends on the beat pose; POST starts on it and ends at rest.
const ENERGY_PRE: Array = [
	[0.00, Vector3(0.15, -0.66, -0.40), Vector3(0, 0, 0)],
	[0.28, Vector3(0.11, -0.16, -0.38), Vector3(0, 0, 0)],
	[0.50, Vector3(0.05, -0.11, -0.34), Vector3(52, 0, 0)],
	[0.66, Vector3(0.07, -0.14, -0.36), Vector3(18, 0, 0)],
	[1.00, Vector3(0.03, -0.07, -0.31), Vector3(98, 0, 0)],
]
const ENERGY_POST: Array = [
	[0.00, Vector3(0.03, -0.07, -0.31), Vector3(98, 0, 0)],
	[0.40, Vector3(0.10, -0.17, -0.38), Vector3(0, 0, 0)],
	[1.00, Vector3(0.15, -0.66, -0.40), Vector3(0, 0, 0)],
]
const CORN_PRE: Array = [
	[0.00, Vector3(0.20, -0.66, -0.28), Vector3(0, 0, 0)],
	[0.55, Vector3(0.22, -0.27, -0.17), Vector3(-34, 0, 0)],
	[1.00, Vector3(0.07, -0.08, -0.40), Vector3(38, 0, 0)],
]
const CORN_POST: Array = [
	[0.00, Vector3(0.07, -0.08, -0.40), Vector3(38, 0, 0)],
	[0.35, Vector3(0.03, -0.03, -0.48), Vector3(52, 0, 0)],
	[1.00, Vector3(0.20, -0.66, -0.30), Vector3(20, 0, 0)],
]
const DRONE_PRE: Array = [
	[0.00, Vector3(0.0, -0.66, -0.44), Vector3(0, 0, 0)],
	[0.50, Vector3(0.0, -0.15, -0.42), Vector3(0, 0, 0)],
	[0.74, Vector3(0.0, -0.20, -0.38), Vector3(-10, 0, 0)],
	[1.00, Vector3(0.0, 0.03, -0.60), Vector3(24, 0, 0)],
]
const DRONE_POST: Array = [
	[0.00, Vector3(0.0, 0.03, -0.60), Vector3(24, 0, 0)],
	[0.35, Vector3(0.0, 0.10, -0.68), Vector3(30, 0, 0)],
	[1.00, Vector3(0.0, -0.66, -0.52), Vector3(10, 0, 0)],
]

# medkit: left fist (design = mirror image of a right fist), forearm dir in the right-hand design space.
# LEFT_BACK is where the back of the left hand faces in CAMERA space: up and toward the eye, so the gesture
# shows the knuckles and the curl of a closed fist instead of the edge of the hand.
const LEFT_HOLD: Vector3 = Vector3(0.11, -0.05, -0.54)
const LEFT_FORE: Vector3 = Vector3(0.85, -0.40, 0.35)
const LEFT_BACK: Vector3 = Vector3(0.34, 0.52, 0.78)
const LEFT_GRIP: Vector2 = Vector2(0.010, 0.013)
const RIGHT_FORE: Vector3 = Vector3(0.40, -0.55, 0.75)
const WRAP_AT: Vector2 = Vector2(0.095, 0.190)      # forearm distance from the wrist where the ribbon starts / ends
const WRAP_R: float = 0.050
const WRAP_W: float = 0.036
const WRAP_TURNS: float = 2.0
const WRAP_STEPS: int = 20
const ORBIT_R: float = 0.092

const CORN_FLIGHT: Vector3 = Vector3(-0.35, 1.9, -6.5)
const CORN_GRAVITY: float = 9.8
const DRONE_SCALE: float = 0.85

static var _cache: Dictionary = {}

var _right: MeshInstance3D
var _left: MeshInstance3D
var _item: MeshInstance3D
var _wrap: MeshInstance3D
var _drone: Node3D
var _data: Dictionary = {}
var _t: float = -1.0
var _duration: float = 1.0
var _beat: float = 0.5
var _beat_done: bool = false
var _wrap_stage: int = -1
var _fly_t: float = -1.0
var _fly_from: Vector3 = Vector3.ZERO


func _init() -> void:
	set_process(false)


func _ready() -> void:
	if _right == null and item_id != &"":
		setup(item_id)


func setup(id: StringName) -> void:
	if _right != null:
		return
	item_id = id
	if not _cache.has(id):
		_cache[id] = _build(id)
	_data = _cache[id]
	_right = _mi("RightArm", self)
	_right.mesh = _data["right"]
	if _data.has("left"):
		_left = _mi("LeftArm", self)
		_left.mesh = _data["left"]
	match id:
		Ids.I_MEDKIT:
			_wrap = _mi("Wrap", _left)
		Ids.I_CORN_BAIT:
			_item = _mi("Cob", self)
			_item.mesh = _data["item"]
		Ids.I_SCOUT_DRONE:
			_drone = _make_drone()
			_right.add_child(_drone)
	_apply(0.0)


func _mi(node_name: String, parent: Node) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func play_use(duration_s: float, effect_at: float) -> void:
	if _right == null:
		setup(item_id)
	_duration = maxf(duration_s, 0.05)
	_beat = clampf(effect_at, MIN_VISUAL_BEAT, MAX_VISUAL_BEAT)
	_t = 0.0
	_beat_done = false
	_fly_t = -1.0
	_set_beat_state(false)
	_apply(0.0)
	set_process(true)


func cancel_use() -> void:
	_t = -1.0
	_fly_t = -1.0
	_beat_done = false
	_set_beat_state(false)
	set_process(false)
	if _right != null:
		_apply(0.0)


func _process(delta: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	_t += delta
	var u: float = _t / _duration
	if u >= 1.0:
		_t = -1.0
		_apply(0.0)
		_set_beat_state(false)
		_fly_t = -1.0
		set_process(false)
		return
	if not _beat_done and u >= _beat:
		_beat_done = true
		_on_beat()
	if _fly_t >= 0.0:
		_fly_t += delta
	_apply(u)


# --- gesture ------------------------------------------------------------------------------------------

func _on_beat() -> void:
	match item_id:
		Ids.I_SCOUT_DRONE:
			if _drone != null:
				_drone.visible = false
		Ids.I_CORN_BAIT:
			_fly_t = 0.0
			_fly_from = _right.position


func _set_beat_state(after: bool) -> void:
	if _drone != null:
		_drone.visible = not after
	if _item != null:
		_item.visible = true


## Whole gesture at fraction u of the duration (0 and 1 = rest).
func _apply(u: float) -> void:
	var after: bool = u >= _beat
	var p: float = clampf(u / _beat, 0.0, 1.0)
	var q: float = clampf((u - _beat) / (1.0 - _beat), 0.0, 1.0)
	match item_id:
		Ids.I_ENERGY_DRINK:
			_set_xf(_right, _sample(ENERGY_POST if after else ENERGY_PRE, q if after else p))
		Ids.I_CORN_BAIT:
			_set_xf(_right, _sample(CORN_POST if after else CORN_PRE, q if after else p))
			_apply_cob(after)
		Ids.I_SCOUT_DRONE:
			_set_xf(_right, _sample(DRONE_POST if after else DRONE_PRE, q if after else p))
		Ids.I_MEDKIT:
			_apply_medkit(after, p, q)


func _apply_cob(after: bool) -> void:
	if not after or _fly_t < 0.0:
		_item.visible = true
		_item.transform = _right.transform
		return
	var t: float = _fly_t
	# thrown on from the hand: forward, a little up, falling (camera space; the preview only needs a short arc)
	var pos: Vector3 = _fly_from + Vector3(CORN_FLIGHT.x * t, CORN_FLIGHT.y * t - 0.5 * CORN_GRAVITY * t * t, CORN_FLIGHT.z * t)
	_item.visible = t < 0.22
	_item.transform = Transform3D(_right.transform.basis * Basis.from_euler(Vector3(-t * 6.0, 0.0, t * 9.0)), pos)


func _apply_medkit(after: bool, p: float, q: float) -> void:
	var rest_down: Vector3 = Vector3(0.0, -0.62, 0.0)
	var enter_l: float = smoothstep(0.0, 0.20, p) if not after else 1.0 - smoothstep(0.30, 0.95, q)
	var enter_r: float = smoothstep(0.10, 0.30, p) if not after else 1.0 - smoothstep(0.0, 0.45, q)
	_left.transform = Transform3D(Basis.IDENTITY, LEFT_HOLD + rest_down * (1.0 - enter_l))
	# ribbon turns: the hand circles the forearm twice between 0.28 and 0.86 of the build up
	var spin: float = 1.0 if after else smoothstep(0.28, 0.86, p)
	var phi: float = spin * TAU * WRAP_TURNS
	var tighten: float = 0.0 if after else smoothstep(0.86, 1.0, p)
	if after:
		tighten = 1.0 - smoothstep(0.0, 0.3, q)
	var axis: Vector3 = _data["axis"]
	var u_dir: Vector3 = _data["u"]
	var v_dir: Vector3 = _data["v"]
	var centre: Vector3 = _data["wrist_l"] + axis * (lerpf(WRAP_AT.x, WRAP_AT.y, spin) + 0.012 * tighten)
	var r: float = ORBIT_R - 0.012 * tighten
	var local: Vector3 = centre + (u_dir * cos(phi) + v_dir * sin(phi)) * r
	var hand: Vector3 = _left.transform * local
	_right.transform = Transform3D(Basis.IDENTITY, hand + Vector3(0.18, -0.62, 0.05) * (1.0 - enter_r))
	var stage: int = clampi(int(floor(spin * float(WRAP_STEPS))), 0, WRAP_STEPS)
	if stage != _wrap_stage:
		_wrap_stage = stage
		_wrap.mesh = _data["stages"][stage]


## Linear key sampling with eased segments.
static func _sample(keys: Array, f: float) -> Transform3D:
	var n: int = keys.size()
	var i: int = 0
	while i < n - 2 and f >= (keys[i + 1] as Array)[0]:
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var w: float = smoothstep(0.0, 1.0, clampf((f - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-5), 0.0, 1.0))
	var e: Vector3 = (a[2] as Vector3).lerp(b[2] as Vector3, w)
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))), (a[1] as Vector3).lerp(b[1] as Vector3, w))


func _set_xf(node: Node3D, xf: Transform3D) -> void:
	node.transform = xf


# --- budget (preview and tests) ---------------------------------------------------------------------

## { triangles, meshes, materials } of the nodes of this view (the rotors of the drone prop count as a mesh).
func get_budget() -> Dictionary:
	var tris: int = 0
	var meshes: int = 0
	var mats: Dictionary = {}
	var stage_tris: int = 0
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		meshes += 1
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		var count: int = 0
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			count += int((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3.0)
			var m: Material = mesh.surface_get_material(s)
			if m != null:
				mats[m.get_instance_id()] = true
		if node.name == &"Wrap" and _data.has("stages"):
			count = 0
			for st: ArrayMesh in _data["stages"]:
				count = maxi(count, _mesh_tris(st))
		if node is MultiMeshInstance3D:
			count *= (node as MultiMeshInstance3D).multimesh.instance_count
		tris += count + stage_tris
	return {"triangles": tris, "meshes": meshes, "materials": mats.size()}


static func _mesh_tris(mesh: Mesh) -> int:
	var c: int = 0
	for s in mesh.get_surface_count():
		c += int((mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3.0)
	return c


# --- building -----------------------------------------------------------------------------------------

static func _frame(a: Vector3, y_hint: Vector3) -> Basis:
	var z: Vector3 = a.normalized()
	var y: Vector3 = (y_hint - z * y_hint.dot(z)).normalized()
	return Basis(y.cross(z), y, z)


static func _mirror_vec(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


static func _build(id: StringName) -> Dictionary:
	match id:
		Ids.I_ENERGY_DRINK:
			return _build_energy()
		Ids.I_CORN_BAIT:
			return _build_corn()
		Ids.I_SCOUT_DRONE:
			return _build_drone()
		Ids.I_MEDKIT:
			return _build_medkit()
	return {"right": ArrayMesh.new()}


static func _arm_mats() -> Dictionary:
	return {0: ArmsHD.get_material(), 1: PM.get_material()}


static func _commit(k: HDMesh) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(k.build(), mesh, _arm_mats())
	return mesh


## Gloved right hand closed around a bar of half section `half` whose axis is frame.z: frame.x is the back of
## the hand, frame.y points from the wrist to the knuckles, frame.z runs from the little finger to the thumb.
## The forearm leaves along `fore` (same space). `curl` (0..1) closes the hand further: at 1 the fingertips
## come back onto the palm and the thumb folds across them, i.e. a fist holding nothing. Surface 0 = glove /
## sleeve. Returns the wrist point.
static func _hand(k: HDMesh, half: Vector2, frame: Basis, fore: Vector3, origin: Vector3 = Vector3.ZERO, curl: float = 0.0) -> Vector3:
	var e0: Vector3 = frame.x
	var e1: Vector3 = frame.y
	var a: Vector3 = frame.z
	var fr: Transform3D = Transform3D(frame, Vector3.ZERO)
	var wrist: Vector3 = e0 * (half.x + 0.0275) - e1 * (half.y + 0.038) + a * 0.012
	var fd: Vector3 = fore.normalized()
	var elbow: Vector3 = wrist + fd * FORE_LEN
	var shoulder: Vector3 = wrist + fd * SHOULDER_LEN
	k.crease_deg = 50.0
	var palm: Array = [
		[ArmsHD._wrap(fr, half, 20.0, 0.004, 0.012), 0.039, 0.011],
		[ArmsHD._wrap(fr, half, -20.0, 0.004, 0.015), 0.040, 0.014],
		[ArmsHD._wrap(fr, half, -55.0, 0.006, 0.018), 0.038, 0.017],
		[(ArmsHD._wrap(fr, half, -55.0, 0.006, 0.018) + wrist) * 0.5, 0.034, 0.019],
	]
	ArmsHD._arm_tube(k, palm, wrist, elbow, shoulder, a, 1.0)
	k.surface(0)
	ArmsHD._paint(k, ArmsHD.GLOVE)
	# little finger first, index last (the thumb side): the index is the longest and thickest, and the base
	# joints ride on an arc (the middle one highest) so the knuckle row is not a straight bar
	for f: Array in [[-0.0290, 0.0083, 186.0, 0.0060], [-0.0080, 0.0091, 196.0, 0.0092],
			[0.0130, 0.0097, 198.0, 0.0102], [0.0340, 0.0095, 194.0, 0.0080]]:
		var h: float = f[0]
		var r: float = f[1]
		var last: float = lerpf(float(f[2]), float(f[2]) + 48.0, curl)
		var span: float = (last - 14.0) / 182.0
		var pts: Array = []
		for key: Vector2 in [Vector2(0.0, r + float(f[3])), Vector2(46.0, r + 0.001), Vector2(96.0, r), Vector2(141.0, r * 0.96), Vector2(182.0, r * 0.9)]:
			pts.append(ArmsHD._wrap(fr, half, 14.0 + key.x * span, h, key.y))
		ArmsHD._finger(k, pts, r, a, 0.85)
	ArmsHD._filler(k, frame, a * 0.004, Vector3(0.014 + half.x, 0.016 + half.y, 0.030), origin)
	# thumb: out of the ball of the hand, then across the front of the fingers (a closed fist) or around
	# whatever is held (an open grip)
	var thumb: Array = [ArmsHD._wrap(fr, half, lerpf(20.0, -26.0, curl), 0.030, lerpf(0.012, 0.017, curl)),
		ArmsHD._wrap(fr, half, lerpf(55.0, 22.0, curl), 0.012, lerpf(0.0125, 0.020, curl)),
		ArmsHD._wrap(fr, half, lerpf(85.0, 90.0, curl), -0.012, lerpf(0.0125, 0.016, curl)),
		ArmsHD._wrap(fr, half, lerpf(92.0, 134.0, curl), -0.034, lerpf(0.0115, 0.013, curl))]
	ArmsHD._finger(k, thumb, 0.0107, e0, 0.7)
	return wrist


## The same surface list mirrored across the YZ plane (left hand from a right hand), as surface `new_index`.
static func _mirrored(built: Dictionary, src: int, new_index: int) -> void:
	var sd: Dictionary = (built["surfaces"] as Dictionary)[src]
	var m: Dictionary = {}
	for key: String in sd:
		m[key] = sd[key]
	var pos: PackedVector3Array = (sd["pos"] as PackedVector3Array).duplicate()
	var nrm: PackedVector3Array = (sd["nrm"] as PackedVector3Array).duplicate()
	for i in pos.size():
		pos[i] = _mirror_vec(pos[i])
		nrm[i] = _mirror_vec(nrm[i])
	var idx: PackedInt32Array = (sd["idx"] as PackedInt32Array).duplicate()
	for i in range(0, idx.size(), 3):
		var tmp: int = idx[i + 1]
		idx[i + 1] = idx[i + 2]
		idx[i + 2] = tmp
	m["pos"] = pos
	m["nrm"] = nrm
	m["idx"] = idx
	(built["surfaces"] as Dictionary)[new_index] = m


static func _paint(k: HDMesh, color: Color, rough: float, feature: int, grain: float = 0.0) -> void:
	k.paint(color, 0.0, rough, grain, feature)


# --- energy drink -------------------------------------------------------------------------------------

static func _build_energy() -> Dictionary:
	var k: HDMesh = HDMesh.new()
	var frame: Basis = _frame(Vector3.UP, Vector3(0.0, 0.0, -1.0))
	_hand(k, Vector2(0.033, 0.033), frame, Vector3(0.28, -0.50, 0.80))
	k.surface(1)
	var a: Vector3 = frame.z
	var y: Vector3 = frame.y
	_paint(k, Color(0.62, 0.64, 0.64), 0.35, PM.F_ZINC)
	k.lathe([Vector3(-0.066, 0.0, 0.0), Vector3(-0.066, 0.026, 0.0), Vector3(-0.060, 0.0315, 0.0), Vector3(-0.055, 0.0335, 0.0)], 12, Vector3.ZERO, a, y)
	_paint(k, Color(0.07, 0.15, 0.17), 0.4, PM.F_PAINT)
	k.lathe([Vector3(-0.055, 0.0335, 0.0), Vector3(0.050, 0.0335, 0.0)], 12, Vector3.ZERO, a, y)
	_paint(k, Color(0.76, 0.82, 0.16), 0.4, PM.F_PAINT)
	k.lathe([Vector3(-0.012, 0.0338, 0.0), Vector3(0.020, 0.0338, 0.0)], 12, Vector3.ZERO, a, y)
	_paint(k, Color(0.82, 0.38, 0.10), 0.4, PM.F_PAINT)
	k.lathe([Vector3(0.026, 0.0338, 0.0), Vector3(0.034, 0.0338, 0.0)], 12, Vector3.ZERO, a, y)
	_paint(k, Color(0.42, 0.44, 0.44), 0.35, PM.F_ZINC)
	k.lathe([Vector3(0.050, 0.0335, 0.0), Vector3(0.056, 0.0315, 0.0), Vector3(0.062, 0.027, 0.0), Vector3(0.065, 0.025, 0.0), Vector3(0.065, 0.0, 0.0)], 12, Vector3.ZERO, a, y)
	var keep: Transform3D = k.xf
	k.xf = Transform3D(frame, a * 0.0665)
	k.cbox(Vector3.ZERO, Vector3(0.018, 0.006, 0.003), 0.0008)
	k.xf = keep
	var built: Dictionary = k.build()
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, _arm_mats())
	return {"right": mesh}


# --- corn ---------------------------------------------------------------------------------------------

static func _build_corn() -> Dictionary:
	var a: Vector3 = Vector3(0.10, -0.12, 1.0)
	var frame: Basis = _frame(a, Vector3.UP)
	var k: HDMesh = HDMesh.new()
	_hand(k, Vector2(0.027, 0.027), frame, Vector3(0.35, -0.55, 0.75))
	var mesh: ArrayMesh = _commit(k)
	var c: HDMesh = HDMesh.new()
	var ax: Vector3 = frame.z
	# stem end behind the fist (toward the shooter), tip forward
	Corn.cob(c, ax * 0.085, -ax, 0.21, 0.030, 1)
	Corn.husk_leaf(c, ax * 0.088, ax - frame.y * 0.30 + frame.x * 0.2, 0.05, 0.022, 0.02, PM.HUSK_DRY)
	var built: Dictionary = c.build()
	var cob: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, cob, PM.surfaces())
	return {"right": mesh, "item": cob}


# --- drone --------------------------------------------------------------------------------------------

static func _build_drone() -> Dictionary:
	var frame: Basis = _frame(Vector3(0.0, 0.0, 1.0), Vector3.UP)
	var k: HDMesh = HDMesh.new()
	var half: Vector2 = Vector2(0.017, 0.017)
	var origin: Vector3 = Vector3(0.080, -0.060, 0.0)
	k.xf = Transform3D(Basis.IDENTITY, origin)
	_hand(k, half, frame, Vector3(0.40, -0.35, 0.85), origin)
	var built: Dictionary = k.build()
	# left hand: mirror of the right one, as surface 1 (same glove material)
	_mirrored(built, 0, 2)
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, {0: ArmsHD.get_material(), 2: ArmsHD.get_material()})
	return {"right": mesh}


func _make_drone() -> Node3D:
	var n: Node3D = null
	var path: String = ScenePaths.prop(&"scout_drone")
	if AssetLoader.exists(path):
		n = AssetLoader.instantiate(path) as Node3D
	if n == null:
		n = _fallback_drone()
	n.name = "Drone"
	n.scale = Vector3.ONE * DRONE_SCALE
	return n


## Plain quadcopter used only when the prop scene is missing: a body, four arms with rotor discs, one mesh.
static func _fallback_drone() -> Node3D:
	var root: Node3D = Node3D.new()
	var k: HDMesh = HDMesh.new()
	_paint(k, Color(0.36, 0.40, 0.27), 0.6, PM.F_PAINT)
	k.cbox(Vector3.ZERO, Vector3(0.09, 0.03, 0.12), 0.006)
	_paint(k, Color(0.13, 0.14, 0.13), 0.6, PM.F_PAINT)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var tip: Vector3 = Vector3(0.105 * sx, 0.012, 0.105 * sz)
			k.cbox(tip * 0.5, Vector3(0.012, 0.010, 0.15), 0.002)
			k.lathe([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.06, 0.0), Vector3(0.002, 0.06, 0.0), Vector3(0.002, 0.0, 0.0)], 8, tip + Vector3(0.0, 0.02, 0.0), Vector3.UP)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(k.build(), mesh, PM.surfaces())
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


# --- medkit -------------------------------------------------------------------------------------------

static func _build_medkit() -> Dictionary:
	var mirror_fore: Vector3 = _mirror_vec(LEFT_FORE.normalized())
	# Left fist, built as a right hand and then mirrored. The hand carries on from the forearm (knuckles away
	# from the elbow) with the back of the hand turned to the eye, and it holds nothing: a real closed fist.
	var lk: HDMesh = HDMesh.new()
	var e1d: Vector3 = -LEFT_FORE.normalized()
	var backd: Vector3 = _mirror_vec(LEFT_BACK.normalized())
	var e0d: Vector3 = (backd - e1d * backd.dot(e1d)).normalized()
	var lframe: Basis = Basis(e0d, e1d, e0d.cross(e1d))
	var wrist_design: Vector3 = _hand(lk, LEFT_GRIP, lframe, LEFT_FORE, Vector3.ZERO, 1.0)
	var lbuilt: Dictionary = lk.build()
	_mirrored(lbuilt, 0, 0)
	var left: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(lbuilt, left, {0: ArmsHD.get_material()})
	var wrist_l: Vector3 = _mirror_vec(wrist_design)
	var axis: Vector3 = mirror_fore
	var u_dir: Vector3 = (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
	var v_dir: Vector3 = axis.cross(u_dir).normalized()
	# right fist holding the roll, roll axis along the forearm, orbiting it
	var rframe: Basis = _frame(axis, u_dir)
	var rk: HDMesh = HDMesh.new()
	_hand(rk, Vector2(0.034, 0.034), rframe, RIGHT_FORE)
	rk.surface(1)
	_paint(rk, Color(0.92, 0.90, 0.80), 0.9, PM.F_PLASTER)
	var ra: Vector3 = rframe.z
	rk.lathe([Vector3(-0.100, 0.0, 0.0), Vector3(-0.100, 0.030, 0.0), Vector3(-0.096, 0.036, 0.0), Vector3(0.036, 0.036, 0.0),
		Vector3(0.040, 0.030, 0.0), Vector3(0.040, 0.0, 0.0)], 10, Vector3.ZERO, ra, rframe.y)
	_paint(rk, Color(0.50, 0.44, 0.33), 0.9, PM.F_PLASTER)
	rk.lathe([Vector3(-0.1005, 0.0, 0.0), Vector3(-0.1005, 0.014, 0.0), Vector3(-0.0895, 0.014, 0.0), Vector3(-0.0895, 0.0, 0.0)], 8, Vector3.ZERO, ra, rframe.y)
	var right: ArrayMesh = _commit(rk)
	# ribbon stages around the left forearm: stage i has wound i/WRAP_STEPS of the two turns
	var stages: Array[ArrayMesh] = []
	for i in WRAP_STEPS + 1:
		var m: ArrayMesh = ArrayMesh.new()
		if i >= 1:
			var wk: HDMesh = HDMesh.new()
			_paint(wk, Color(0.92, 0.90, 0.80), 0.9, PM.F_PLASTER)
			var path: Array = []
			for j in i + 1:
				var s: float = float(j) / float(WRAP_STEPS)
				var ang: float = s * TAU * WRAP_TURNS
				var centre: Vector3 = wrist_l + axis * lerpf(WRAP_AT.x, WRAP_AT.y, s)
				path.append(centre + (u_dir * cos(ang) + v_dir * sin(ang)) * WRAP_R)
			var section: PackedVector2Array = PackedVector2Array([Vector2(WRAP_W * 0.5, -0.0025), Vector2(WRAP_W * 0.5, 0.0025),
				Vector2(-WRAP_W * 0.5, 0.0025), Vector2(-WRAP_W * 0.5, -0.0025)])
			wk.sweep(path, section, axis)
			HDMesh.commit(wk.build(), m, PM.surfaces())
		stages.append(m)
	return {"right": right, "left": left, "stages": stages, "axis": axis, "u": u_dir, "v": v_dir, "wrist_l": wrist_l}
