extends DogVisualBase
## Procedural low-poly dog (3 breeds). Nodes: Body, Head (> Ears), Tail, FrontLegs, RearLegs + Mouth marker.
## Front legs and rear legs are one mesh each (they swing as pairs). Origin on the ground, forward -Z.

const SKY_DARK: Color = Color(0.10, 0.07, 0.06)

## Breed data: h = withers height, l = body length, b = chest width factor, m = muzzle length factor.
const BREEDS: Dictionary = {
	&"caramelo": {"h": 0.52, "l": 0.85, "b": 1.0, "m": 1.0, "fur": Color(0.85, 0.56, 0.26), "belly": Color(0.93, 0.74, 0.48),
		"ear": Color(0.68, 0.42, 0.18), "leg": Color(0.85, 0.56, 0.26), "paw": Color(0.93, 0.74, 0.48), "nose": Color(0.12, 0.08, 0.06),
		"ear_len": 0.11, "ear_w": 0.07, "tail": 0, "saddle": false},
	&"foxhound": {"h": 0.60, "l": 0.95, "b": 0.88, "m": 1.15, "fur": Color(0.78, 0.50, 0.22), "belly": Color(0.95, 0.91, 0.82),
		"ear": Color(0.38, 0.23, 0.13), "leg": Color(0.95, 0.91, 0.82), "paw": Color(0.97, 0.95, 0.9), "nose": Color(0.1, 0.07, 0.06),
		"ear_len": 0.21, "ear_w": 0.08, "tail": 1, "saddle": true},
	&"dogo": {"h": 0.64, "l": 1.0, "b": 1.3, "m": 0.85, "fur": Color(0.97, 0.95, 0.9), "belly": Color(0.88, 0.84, 0.77),
		"ear": Color(0.9, 0.84, 0.78), "leg": Color(0.95, 0.92, 0.86), "paw": Color(0.9, 0.86, 0.8), "nose": Color(0.20, 0.13, 0.12),
		"ear_len": 0.08, "ear_w": 0.07, "tail": 2, "saddle": false},
}

static var _cache: Dictionary = {}

var _body: MeshInstance3D
var _head: MeshInstance3D
var _ears: MeshInstance3D
var _tail: MeshInstance3D
var _fl: MeshInstance3D
var _rl: MeshInstance3D
var _mouth: Marker3D

var _breed: StringName = &""
var _data: Dictionary = {}
var _mouth_local: Vector3 = Vector3.ZERO
var _head_rest: Vector3 = Vector3.ZERO
var _tail_rest: Vector3 = Vector3.ZERO
var _fl_rest: Vector3 = Vector3.ZERO
var _rl_rest: Vector3 = Vector3.ZERO
var _lg: float = 0.25

var _speed: float = 0.0
var _phase: float = 0.0
var _time: float = 0.0
var _retreat: float = 0.0
var _retreat_on: bool = false
var _biting: bool = false
var _pointing: bool = false
var _bark_t: float = -1.0
var _hurt_t: float = -1.0


func _init() -> void:
	_body = _mi("Body")
	_head = _mi("Head")
	_ears = MeshInstance3D.new()
	_ears.name = "Ears"
	_ears.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(_ears)
	_tail = _mi("Tail")
	_fl = _mi("FrontLegs")
	_rl = _mi("RearLegs")
	_mouth = Marker3D.new()
	_mouth.name = "Mouth"
	add_child(_mouth)


func _ready() -> void:
	if _body.mesh == null:
		setup(&"caramelo")


func _mi(node_name: String) -> MeshInstance3D:
	var m: MeshInstance3D = MeshInstance3D.new()
	m.name = node_name
	add_child(m)
	return m


func setup(breed_id: StringName) -> void:
	if not BREEDS.has(breed_id):
		breed_id = &"caramelo"
	_breed = breed_id
	_data = BREEDS[breed_id]
	var h: float = _data["h"]
	var l: float = _data["l"]
	_lg = h * 0.42
	if not _cache.has(breed_id):
		_cache[breed_id] = _build(breed_id)
	var m: Dictionary = _cache[breed_id]
	_body.mesh = m["body"]
	_head.mesh = m["head"]
	_ears.mesh = m["ears"]
	_tail.mesh = m["tail"]
	_fl.mesh = m["fl"]
	_rl.mesh = m["rl"]
	_head_rest = Vector3(0.0, h * 0.86, -l * 0.34)
	_ears.position = Vector3(0.0, h * 0.2, -h * 0.1)
	_tail_rest = Vector3(0.0, h * 0.9, l * 0.42)
	_fl_rest = Vector3(0.0, _lg * 1.02, -l * 0.27)
	_rl_rest = Vector3(0.0, _lg * 1.02, l * 0.3)
	_mouth_local = Vector3(0.0, h * 0.1, -h * 0.4 * float(_data["m"]) - h * 0.2)
	_head.position = _head_rest
	_tail.position = _tail_rest
	_fl.position = _fl_rest
	_rl.position = _rl_rest
	_mouth.position = _head_rest + _mouth_local


func _build(id: StringName) -> Dictionary:
	var d: Dictionary = BREEDS[id]
	var h: float = d["h"]
	var l: float = d["l"]
	var b: float = d["b"]
	var lg: float = h * 0.42
	var fur: Color = d["fur"]
	var belly: Color = d["belly"]
	var saddle: bool = d["saddle"]
	# --- body
	var bk: MeshKit = MeshKit.new()
	var st: Array = [
		[-l * 0.36, 0.06 * b, lg * 1.0, h * 0.95],
		[-l * 0.22, 0.095 * b, lg * 0.86, h * 1.0],
		[l * 0.08, 0.08 * b, lg * 1.02, h * 0.97],
		[l * 0.30, 0.095 * b, lg * 0.97, h * 0.97],
		[l * 0.43, 0.065 * b, lg * 1.02, h * 0.92],
	]
	var fn: Callable = func(p: Vector3, lift: float, _i: int) -> Color:
		if lift < 0.28:
			return belly
		if saddle and lift > 0.5 and p.z > -l * 0.25 and p.z < l * 0.34:
			return Color(0.17, 0.11, 0.08)
		return fur
	bk.loft(st, 6, belly, fur, true, true, fn)
	# --- head (local to the head pivot at the neck base)
	var hk: MeshKit = MeshKit.new()
	var ml: float = d["m"]
	hk.ellipsoid(Vector3(0, h * 0.14, -h * 0.1), Vector3(0.11 * b, 0.13 * h, 0.15 * h), 6, 4, fur, fur)
	hk.ellipsoid(Vector3(0, h * 0.02, h * 0.02), Vector3(0.09 * b, 0.15 * h, 0.12 * h), 5, 3, fur, fur)   # neck
	hk.box(Vector3(0, h * 0.1, -h * 0.28 * ml - h * 0.06), Vector3(0.085 * b, 0.095 * h, 0.24 * h * ml), fur, MeshKit.shade(fur, 1.05))
	hk.box(Vector3(0, h * 0.075, -h * 0.28 * ml - h * 0.06), Vector3(0.08 * b, 0.03 * h, 0.22 * h * ml), belly)
	var nose_z: float = -h * 0.28 * ml - h * 0.06 - h * 0.11 * ml
	hk.box(Vector3(0, h * 0.115, nose_z), Vector3(0.045 * b + 0.02, 0.04 * h + 0.01, 0.04), d["nose"])
	for sx: float in [-1.0, 1.0]:
		hk.box(Vector3(sx * 0.05 * b, h * 0.19, -h * 0.17), Vector3(0.02, 0.02, 0.02), SKY_DARK)
	# --- ears (local to ears pivot, which sits on top of the skull)
	var ek: MeshKit = MeshKit.new()
	var el: float = d["ear_len"] * (h / 0.52)
	var ew: float = d["ear_w"] * 1.8
	for sx: float in [-1.0, 1.0]:
		var top_a: Vector3 = Vector3(sx * 0.06 * b, 0.0, -ew * 0.5)
		var top_b: Vector3 = Vector3(sx * 0.06 * b, 0.0, ew * 0.5)
		var drop: Vector3 = Vector3(sx * (0.09 * b + el * 0.35), -el, ew * 0.2)
		if id == &"dogo":
			drop = Vector3(sx * (0.08 * b), el * 0.6, ew * 0.1)
		ek.tri_double(top_a, top_b, drop, d["ear"], d["ear"], MeshKit.shade(d["ear"], 0.8))
	# --- tail (pivot at rump, built along +Z/up)
	var tk: MeshKit = MeshKit.new()
	var segs: Array = []
	match int(d["tail"]):
		0: segs = [[0.14, 55.0, 0.05, 0.04], [0.12, -50.0, 0.04, 0.02]]
		1: segs = [[0.38 * h / 0.6, 38.0, 0.045, 0.018]]
		_: segs = [[0.30 * h / 0.64, 62.0, 0.06, 0.02]]
	var pos: Vector3 = Vector3.ZERO
	var ang: float = 0.0
	for s: Array in segs:
		ang += s[1]
		var basis: Basis = Basis(Vector3.RIGHT, deg_to_rad(ang))
		tk.xf = Transform3D(basis, pos)
		var tip_col: Color = Color(0.97, 0.95, 0.9) if int(d["tail"]) == 1 else fur
		tk.frustum(Vector3.ZERO, s[2], s[3], s[0], 4, fur, tip_col, true, true)
		pos += basis * Vector3(0, s[0], 0)
	tk.reset_xf()
	# --- legs (local to hip pivots)
	var fk: MeshKit = MeshKit.new()
	var rk: MeshKit = MeshKit.new()
	var lw: float = 0.05 * b
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * 0.068 * b
		_leg(fk, x, lg, lw, d["leg"], d["paw"], false)
		_leg(rk, x, lg, lw * 1.12, d["leg"], d["paw"], true)
	return {"body": bk.build(), "head": hk.build(), "ears": ek.build(), "tail": tk.build(), "fl": fk.build(), "rl": rk.build()}


static func _leg(k: MeshKit, x: float, lg: float, w: float, col: Color, paw: Color, rear: bool) -> void:
	var top_w: float = w * (1.5 if rear else 1.2)
	k.prism(Vector3(x, -lg + 0.03, 0.0), Vector2(w, w * 1.1), Vector2(top_w, top_w * 1.2), lg - 0.03, col, col)
	k.box(Vector3(x, -lg + 0.015, -0.015), Vector3(w * 1.15, 0.03, w * 2.0), paw)


# --- animation -------------------------------------------------------------------------------

func set_locomotion(speed_mps: float) -> void:
	_speed = maxf(speed_mps, 0.0)
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


func _process(delta: float) -> void:
	_time += delta
	_retreat = move_toward(_retreat, 1.0 if _retreat_on else 0.0, delta * 4.0)
	var gait: float = clampf(_speed / 3.0, 0.0, 1.0)
	_phase += delta * (3.0 + _speed * 1.6) * (1.0 if _speed > 0.05 else 0.0)
	var amp: float = 0.6 * gait if _speed > 0.05 else 0.0
	var gallop: float = clampf((_speed - 5.0) / 3.0, 0.0, 1.0)
	var swing: float = sin(_phase * TAU * 0.5)
	var f_rot: float = swing * amp
	var r_rot: float = -swing * amp * (1.0 - gallop) + swing * amp * gallop
	var bob: float = absf(sin(_phase * TAU * 0.5)) * 0.02 * gait
	var head_rot: Vector3 = Vector3(sin(_time * 1.3) * 0.02, sin(_time * 0.7) * 0.03, 0.0)
	var tail_rot: Vector3 = Vector3(0.0, sin(_time * (5.0 + _speed)) * 0.25, 0.0)
	var ears_rot: float = bob * 6.0
	var body_off: Vector3 = Vector3(0.0, bob, 0.0)
	var body_rot: Vector3 = Vector3.ZERO

	if _pointing:
		head_rot = Vector3(-0.12 + sin(_time * 14.0) * 0.01, 0.0, 0.0)
		f_rot = 0.55
		r_rot = -0.1
		tail_rot = Vector3(0.45, 0.0, 0.0)
		body_rot.x = 0.05
	if _biting:
		head_rot = Vector3(-0.2 + sin(_time * 30.0) * 0.12, sin(_time * 21.0) * 0.28, 0.0)
		tail_rot.y = sin(_time * 14.0) * 0.4
		body_off.z += sin(_time * 18.0) * 0.012
	if _bark_t >= 0.0:
		_bark_t += delta
		var t: float = clampf(_bark_t / 0.3, 0.0, 1.0)
		var p: float = sin(t * PI)
		head_rot.x += 0.42 * p
		body_off.z += 0.04 * p
		body_off.y += 0.015 * p
		if _bark_t >= 0.3:
			_bark_t = -1.0
	if _hurt_t >= 0.0:
		_hurt_t += delta
		var t2: float = clampf(_hurt_t / 0.3, 0.0, 1.0)
		var fade: float = 1.0 - t2
		body_rot.z = sin(_hurt_t * 60.0) * 0.12 * fade
		body_off.z += 0.07 * fade
		head_rot.x += 0.3 * fade
		tail_rot.x += 0.9 * fade
		if _hurt_t >= 0.3:
			_hurt_t = -1.0
	if _retreat > 0.0:
		head_rot.x -= 0.35 * _retreat
		tail_rot.x = lerpf(tail_rot.x, 1.1, _retreat)
		tail_rot.y *= 1.0 - _retreat
		ears_rot += 0.7 * _retreat
		body_off.y -= 0.03 * _retreat

	_body.position = body_off
	_body.rotation = body_rot
	_head.position = _head_rest + body_off
	_head.rotation = head_rot
	_ears.rotation = Vector3(ears_rot, 0.0, 0.0)
	_tail.position = _tail_rest + body_off
	_tail.rotation = tail_rot
	_fl.position = _fl_rest + Vector3(0.0, -bob * 0.5, 0.0)
	_fl.rotation = Vector3(f_rot, 0.0, 0.0)
	_rl.position = _rl_rest + Vector3(0.0, -bob * 0.5, 0.0)
	_rl.rotation = Vector3(r_rot, 0.0, 0.0)
	_mouth.position = _head.position + _head.basis * _mouth_local
