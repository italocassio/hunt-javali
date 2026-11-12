extends BoarVisualBase
## Procedural low-poly wild boar. Parts: Body, Head(+mesh), 4 legs = 6 MeshInstance3D.
## Forward -Z, origin on the ground. Root transform is owned by gameplay.

const HEAD_REST: Vector3 = Vector3(0.0, 0.55, -0.62)
const LEG_HIPS: Array[Vector3] = [
	Vector3(-0.15, 0.40, -0.34), # front left
	Vector3(0.15, 0.40, -0.34),  # front right
	Vector3(-0.15, 0.40, 0.42),  # rear left
	Vector3(0.15, 0.40, 0.42),   # rear right
]
const LEG_FL: int = 0
const LEG_FR: int = 1
const LEG_RL: int = 2
const LEG_RR: int = 3

static var _mesh_cache: Dictionary = {}
static var _leg_cache: Dictionary = {}
static var _highlight_mat: StandardMaterial3D = null

var _type: StringName = Ids.BOAR
var _weight: float = 100.0

var _body: MeshInstance3D
var _head: Node3D
var _head_mesh: MeshInstance3D
var _legs: Array[Node3D] = []
var _leg_meshes: Array[MeshInstance3D] = []

var _speed: float = 0.0
var _speed_smooth: float = 0.0
var _phase: float = 0.0
var _eating: bool = false
var _wounded: bool = false
var _highlight: bool = false
var _charge_latch: bool = false
var _scraping: bool = false
var _alert_t: float = 0.0
var _attack_t: float = 0.0
var _hit_t: float = 0.0
var _dead: bool = false
var _death_t: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_build_nodes()
	_apply_type(Ids.BOAR, 100.0)


func _build_nodes() -> void:
	var mat: Material = MeshKit.vcol_material()
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_body)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = HEAD_REST
	add_child(_head)
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "HeadMesh"
	_head_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(_head_mesh)
	var names: Array[String] = ["LegFL", "LegFR", "LegRL", "LegRR"]
	for i in 4:
		var pivot: Node3D = Node3D.new()
		pivot.name = names[i]
		pivot.position = LEG_HIPS[i]
		add_child(pivot)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Mesh"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 40.0
		pivot.add_child(mi)
		_legs.append(pivot)
		_leg_meshes.append(mi)
	var _unused: Material = mat


# --- type styling -------------------------------------------------------------------------

static func _palette(type_id: StringName) -> Dictionary:
	match type_id:
		Ids.PIGLET:
			return {"back": Color(0.50, 0.34, 0.20), "belly": Color(0.74, 0.60, 0.42), "stripe": Color(0.22, 0.14, 0.09),
				"leg": Color(0.42, 0.30, 0.20), "mane": Color(0.30, 0.20, 0.12), "snout": Color(0.55, 0.38, 0.34)}
		Ids.SOW:
			return {"back": Color(0.36, 0.30, 0.25), "belly": Color(0.48, 0.41, 0.34), "stripe": Color(0, 0, 0, 0),
				"leg": Color(0.26, 0.21, 0.18), "mane": Color(0.24, 0.19, 0.16), "snout": Color(0.28, 0.20, 0.18)}
		Ids.ALPHA:
			return {"back": Color(0.07, 0.055, 0.05), "belly": Color(0.17, 0.12, 0.10), "stripe": Color(0, 0, 0, 0),
				"leg": Color(0.07, 0.055, 0.05), "mane": Color(0.30, 0.22, 0.17), "snout": Color(0.10, 0.07, 0.06)}
		_:
			return {"back": Color(0.20, 0.14, 0.10), "belly": Color(0.32, 0.23, 0.17), "stripe": Color(0, 0, 0, 0),
				"leg": Color(0.13, 0.095, 0.075), "mane": Color(0.22, 0.16, 0.12), "snout": Color(0.14, 0.095, 0.08)}


static func _tusk_bucket(type_id: StringName, kg: float) -> int:
	match type_id:
		Ids.SOW:
			return clampi(int(round(inverse_lerp(60.0, 110.0, kg) * 2.0)), 0, 2)
		Ids.BOAR:
			return clampi(int(round(inverse_lerp(90.0, 160.0, kg) * 2.0)), 0, 2)
		Ids.ALPHA:
			return clampi(int(round(inverse_lerp(180.0, 260.0, kg) * 2.0)), 0, 2)
	return 0


static func _tusk_len(type_id: StringName, bucket: int) -> float:
	match type_id:
		Ids.PIGLET:
			return 0.0
		Ids.SOW:
			return 0.035 + 0.01 * bucket
		Ids.ALPHA:
			return 0.17 + 0.035 * bucket
		_:
			return 0.10 + 0.025 * bucket


static func _mane_height(type_id: StringName) -> float:
	match type_id:
		Ids.PIGLET:
			return 0.0
		Ids.SOW:
			return 0.05
		Ids.ALPHA:
			return 0.17
		_:
			return 0.10


static func get_body_mesh(type_id: StringName) -> ArrayMesh:
	var key: String = "body_%s" % type_id
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var pal: Dictionary = _palette(type_id)
	var k: MeshKit = MeshKit.new()
	var alpha: bool = type_id == Ids.ALPHA
	var hump: float = 0.03 if alpha else 0.0
	var stations: Array = [
		[-0.52, 0.17, 0.38, 0.70 + hump],
		[-0.38, 0.23, 0.28, 0.80 + hump],
		[-0.12, 0.25, 0.25, 0.85 + hump * 0.5],
		[0.18, 0.24, 0.27, 0.78],
		[0.42, 0.23, 0.33, 0.73],
		[0.60, 0.18, 0.37, 0.68],
		[0.70, 0.10, 0.43, 0.62],
	]
	var fn: Callable = Callable()
	if (pal["stripe"] as Color).a > 0.0:
		var stripe: Color = pal["stripe"]
		var back: Color = pal["back"]
		var belly: Color = pal["belly"]
		fn = func(_p: Vector3, lift: float, idx: int) -> Color:
			var base: Color = belly.lerp(back, lift)
			if lift > 0.35 and idx % 2 == 0:
				return base.lerp(stripe, 0.85)
			return base
	k.loft(stations, 8, pal["belly"], pal["back"], true, true, fn)
	# mane (dorsal bristles)
	var mh: float = _mane_height(type_id)
	if mh > 0.0:
		var mane: Color = pal["mane"]
		var tip: Color = MeshKit.shade(mane, 1.5) if not alpha else Color(0.42, 0.32, 0.24)
		var zs: Array[float] = [-0.46, -0.34, -0.22, -0.10, 0.02, 0.14, 0.26, 0.38]
		for z in zs:
			var ytop: float = _top_y(stations, z) - 0.02
			var h: float = mh * (1.0 if z < 0.15 else 0.7)
			k.frustum(Vector3(0, ytop, z), 0.04 if alpha else 0.03, 0.0, h, 3, mane, tip, false, false, Vector2(0, 0.04))
	# tail
	k.set_xf(Vector3(0, 0.60, 0.68), Vector3(-55, 0, 0))
	k.frustum(Vector3.ZERO, 0.02, 0.006, 0.20, 4, pal["back"], pal["mane"], false, false)
	k.reset_xf()
	var mesh: ArrayMesh = k.build()
	_mesh_cache[key] = mesh
	return mesh


static func _top_y(stations: Array, z: float) -> float:
	for i in stations.size() - 1:
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		if z >= a[0] and z <= b[0]:
			var t: float = inverse_lerp(a[0], b[0], z)
			return lerpf(a[3], b[3], t)
	return 0.7


static func get_head_mesh(type_id: StringName, bucket: int) -> ArrayMesh:
	var key: String = "head_%s_%d" % [type_id, bucket]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var pal: Dictionary = _palette(type_id)
	var back: Color = pal["back"]
	var belly: Color = pal["belly"]
	var k: MeshKit = MeshKit.new()
	var wedge: Array = [
		[0.24, 0.17, -0.19, 0.19],
		[0.06, 0.155, -0.18, 0.14],
		[-0.07, 0.115, -0.15, 0.07],
		[-0.17, 0.06, -0.12, -0.01],
		[-0.20, 0.052, -0.105, -0.015],
	]
	k.loft(wedge, 6, belly, back.lerp(belly, 0.15), true, false)
	# nose disc
	k.box(Vector3(0, -0.062, -0.205), Vector3(0.10, 0.085, 0.03), pal["snout"])
	# ears
	var ear: Color = back.lerp(pal["mane"], 0.4)
	for sx in [-1.0, 1.0]:
		var ex: float = 0.10 * sx
		k.tri_double(Vector3(ex, 0.12, 0.02), Vector3(ex * 1.7, 0.26, 0.08), Vector3(ex * 0.8, 0.14, 0.12), ear, MeshKit.shade(ear, 1.3), ear)
	# eyes
	var eye: Color = Color(0.92, 0.55, 0.12) if type_id == Ids.ALPHA else Color(0.05, 0.03, 0.02)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.105 * sx, 0.03, -0.065), Vector3(0.02, 0.025, 0.03), eye)
	# tusks
	var tl: float = _tusk_len(type_id, bucket)
	if tl > 0.0:
		var ivory: Color = Color(0.94, 0.90, 0.78)
		var thick: float = 0.016 + tl * 0.07
		for sx in [-1.0, 1.0]:
			k.set_xf(Vector3(0.062 * sx, -0.10, -0.15), Vector3(-60, 0, -20.0 * sx))
			k.frustum(Vector3.ZERO, thick, 0.0, tl, 4, MeshKit.shade(ivory, 0.8), ivory, false, false)
			k.reset_xf()
	var mesh: ArrayMesh = k.build()
	_mesh_cache[key] = mesh
	return mesh


static func get_leg_mesh(type_id: StringName) -> ArrayMesh:
	var key: String = "leg_%s" % type_id
	if _leg_cache.has(key):
		return _leg_cache[key]
	var pal: Dictionary = _palette(type_id)
	var leg: Color = pal["leg"]
	var k: MeshKit = MeshKit.new()
	# upper (thick) then lower (thin) then hoof; hanging down from the hip pivot at y=0
	k.frustum(Vector3(0, -0.19, 0), 0.040, 0.068, 0.19, 5, leg, MeshKit.shade(leg, 1.1), true, false)
	k.frustum(Vector3(0, -0.36, 0), 0.034, 0.040, 0.17, 5, MeshKit.shade(leg, 0.7), leg, false, false)
	k.frustum(Vector3(0, -0.40, 0), 0.040, 0.034, 0.04, 5, Color(0.04, 0.035, 0.03), Color(0.06, 0.05, 0.04), false, true)
	var mesh: ArrayMesh = k.build()
	_leg_cache[key] = mesh
	return mesh


func _apply_type(type_id: StringName, weight_kg: float) -> void:
	_type = type_id
	_weight = weight_kg
	var bucket: int = _tusk_bucket(type_id, weight_kg)
	_body.mesh = get_body_mesh(type_id)
	_head_mesh.mesh = get_head_mesh(type_id, bucket)
	for m in _leg_meshes:
		m.mesh = get_leg_mesh(type_id)


# --- API ------------------------------------------------------------------------------------

func setup(type_id: StringName, weight_kg: float) -> void:
	_apply_type(type_id, weight_kg)


func set_locomotion(speed_mps: float) -> void:
	_speed = maxf(speed_mps, 0.0)
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
	if _highlight_mat == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.72, 0.38)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.15)
		m.emission_energy_multiplier = 1.6
		_highlight_mat = m
	var ov: Material = _highlight_mat if on else null
	_body.material_override = ov
	_head_mesh.material_override = ov
	for m in _leg_meshes:
		m.material_override = ov


func play_alert() -> void:
	if _dead:
		return
	_alert_t = 1.0
	_scraping = false
	_charge_latch = false


func play_scrape() -> void:
	if _dead:
		return
	_scraping = true
	_charge_latch = true
	_eating = false


func play_attack() -> void:
	if _dead:
		return
	_attack_t = 0.4
	_scraping = false


func play_hit(_zone: StringName) -> void:
	if _dead:
		return
	_hit_t = 0.15


func play_death() -> void:
	if _dead:
		return
	_dead = true
	_death_t = 0.0
	_scraping = false
	_eating = false
	_attack_t = 0.0
	_alert_t = 0.0


# --- animation ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _dead:
		if _death_t < 1.0:
			_death_t = minf(_death_t + delta / 0.7, 1.0)
			_pose_death(_death_t)
		return
	_speed_smooth = lerpf(_speed_smooth, _speed, clampf(delta * 12.0, 0.0, 1.0))
	var s: float = _speed_smooth
	var moving: bool = s > 0.08
	if moving:
		var hz: float = 0.6 + s * 0.38
		_phase += delta * TAU * hz
	_alert_t = maxf(_alert_t - delta, 0.0)
	_attack_t = maxf(_attack_t - delta, 0.0)
	_hit_t = maxf(_hit_t - delta, 0.0)

	var gallop: bool = s > 5.0
	var amp: float = clampf(0.30 + s * 0.09, 0.0, 0.95)
	var swing: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var lift: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if moving:
		if gallop:
			swing[LEG_FL] = sin(_phase) * amp
			swing[LEG_FR] = sin(_phase + 0.35) * amp
			swing[LEG_RL] = sin(_phase + 2.6) * amp
			swing[LEG_RR] = sin(_phase + 2.95) * amp
		else:
			swing[LEG_FL] = sin(_phase) * amp
			swing[LEG_RR] = sin(_phase) * amp
			swing[LEG_FR] = sin(_phase + PI) * amp
			swing[LEG_RL] = sin(_phase + PI) * amp
	var wound_scale: float = 1.0
	if _wounded:
		wound_scale = 0.45
		swing[LEG_FL] *= wound_scale
		lift[LEG_FL] = 0.0

	# body bob / pitch
	var bob: float = 0.0
	var pitch: float = 0.0
	if moving:
		bob = absf(sin(_phase)) * (0.012 + s * 0.006)
		if gallop:
			bob = sin(_phase * 1.0 + 0.5) * 0.04
			pitch = sin(_phase + 0.5) * 0.06
	if _wounded:
		bob -= 0.025 + (sin(_phase) * 0.012 if moving else 0.0)
		pitch += 0.05

	# head
	var head_pitch: float = 0.0
	var head_y: float = 0.0
	var head_z: float = 0.0
	if _eating and not moving:
		head_pitch = -0.78 + sin(_time * 7.0) * 0.12
		head_y = -0.27
		head_z = -0.06
		bob -= 0.02
		pitch -= 0.1
		swing[LEG_FL] = 0.0
	elif _scraping:
		head_pitch = -0.62 + sin(_time * 3.0) * 0.04
		head_y = -0.14
		head_z = -0.05
		pitch -= 0.14
		bob -= 0.03
		# front-left paw rakes the ground, hard and fast
		var rake: float = sin(_time * 14.0)
		swing[LEG_FL] = -0.35 + rake * 0.55
		lift[LEG_FL] = 0.12 + maxf(rake, 0.0) * 0.1
		swing[LEG_FR] = 0.0
	elif _charge_latch and moving:
		head_pitch = -0.55 + sin(_phase * 2.0) * 0.04
		head_y = -0.12
		head_z = -0.04
		pitch -= 0.06
	elif moving:
		head_pitch = -0.1 + sin(_phase * 2.0) * 0.05 if not gallop else -0.18
		head_y = -0.03
	elif _alert_t > 0.0:
		var a: float = sin(clampf(_alert_t, 0.0, 1.0) * PI)
		head_pitch = 0.34 * a
		head_y = 0.06 * a
		head_z = 0.03 * a
		pitch += 0.05 * a
		bob += 0.01 * a
	else:
		# idle: slow sniffing
		head_pitch = -0.08 + sin(_time * 1.4) * 0.05
		head_y = sin(_time * 1.1) * 0.01

	var attack_off: Vector3 = Vector3.ZERO
	if _attack_t > 0.0:
		var t: float = 1.0 - _attack_t / 0.4
		var thrust: float = sin(t * PI)
		head_pitch = lerpf(-0.5, 0.55, thrust) if t < 0.5 else lerpf(0.55, -0.2, (t - 0.5) * 2.0)
		head_z -= 0.14 * thrust
		attack_off = Vector3(0, 0.0, -0.18 * thrust)
		pitch += 0.12 * thrust

	var hit_off: Vector3 = Vector3.ZERO
	if _hit_t > 0.0:
		var h: float = _hit_t / 0.15
		hit_off = Vector3(0, 0.02 * h, 0.07 * h)
		pitch -= 0.12 * h
		head_pitch += 0.15 * h

	var rig: Transform3D = Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(0, bob, 0) + attack_off + hit_off)
	_body.transform = rig
	_head.transform = rig * Transform3D(Basis(Vector3.RIGHT, head_pitch), HEAD_REST + Vector3(0, head_y, head_z))
	for i in 4:
		var pos: Vector3 = LEG_HIPS[i] + Vector3(0, lift[i], 0)
		_legs[i].transform = rig * Transform3D(Basis(Vector3.RIGHT, swing[i]), pos)


func _pose_death(t: float) -> void:
	var e: float = 1.0 - pow(1.0 - t, 2.0)
	var rig: Transform3D = Transform3D(Basis(Vector3.BACK, e * PI * 0.5), Vector3(0.5 * e, 0.27 * e, 0.0))
	_body.transform = rig
	_head.transform = rig * Transform3D(Basis(Vector3.RIGHT, -0.2 * e), HEAD_REST + Vector3(0, -0.06 * e, 0))
	for i in 4:
		var splay: float = (0.35 if i < 2 else -0.25) * e
		_legs[i].transform = rig * Transform3D(Basis(Vector3.RIGHT, splay), LEG_HIPS[i])
