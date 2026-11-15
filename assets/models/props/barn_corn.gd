extends CornStockVisualBase
## Visual corn stock of the barn (docs/horda.md section 11.1). One big pile inside the barn plus six heaps/sacks
## on the boars' eating ring. 8 MeshInstance3D, one shared vertex-color material, no physics, no lights.
## Stages: 4 full, 3/2/1 shrinking (outer heaps shrink and vanish, the inner pile sinks), 0 empty (straw and gnawed cobs).

const CORN: Color = Color(0.91, 0.725, 0.137)
const CORN_DARK: Color = Color(0.74, 0.55, 0.08)
const STRAW: Color = Color(0.76, 0.663, 0.353)
const STRAW_DARK: Color = Color(0.60, 0.51, 0.25)
const SACK: Color = Color(0.725, 0.635, 0.478)
const SACK_DARK: Color = Color(0.58, 0.50, 0.36)

const OUTER_COUNT: int = 6
const PILE_CENTER: Vector3 = Vector3(0.0, 0.0, 0.8)   # inside the barn (x +-7.85, z -5..4.7)
const PILE_RADIUS_X: float = 5.8
const PILE_RADIUS_Z: float = 3.4
const PILE_HEIGHT_M: float = 2.8
const PILE_SEGMENTS: int = 14
const DOME_PROFILE: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.86, 0.42), Vector2(0.58, 0.78), Vector2(0.28, 0.96), Vector2(0.0, 1.0)]
## Per stage (index = stage): inner pile scale (xz, y) and outer heap scale per heap index (0 = hidden).
const PILE_SCALE_XZ: Array[float] = [0.0, 0.5, 0.68, 0.84, 1.0]
const PILE_SCALE_Y: Array[float] = [0.0, 0.22, 0.48, 0.74, 1.0]
const OUTER_SCALE: Array[Array] = [
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.4, 0.0, 0.0, 0.4, 0.0, 0.0],
	[0.6, 0.0, 0.6, 0.6, 0.0, 0.6],
	[0.82, 0.82, 0.82, 0.82, 0.82, 0.82],
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
]
const HIDDEN_SCALE: float = 0.01
const TRANSITION_S: float = 0.4
const SHAKE_AMPLITUDE: float = 0.05
const SHAKE_SPEED: float = 38.0
const SEED: int = 4242

var _pile: MeshInstance3D = null
var _outer: Array[MeshInstance3D] = []
var _empty: MeshInstance3D = null
var _outer_base: Array[Vector3] = []
var _stage: int = -1
var _attack: bool = false
var _tween: Tween = null
var _time: float = 0.0


func _init() -> void:
	name = "BarnCorn"
	var mat: StandardMaterial3D = MeshKit.vcol_material()
	_pile = MeshInstance3D.new()
	_pile.name = "InnerPile"
	_pile.mesh = _build_pile(mat)
	_pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_pile)
	var heap_mesh: ArrayMesh = _build_heap(mat)
	var sack_mesh: ArrayMesh = _build_sacks(mat)
	for i: int in OUTER_COUNT:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Outer_%d" % i
		mi.mesh = heap_mesh if i % 2 == 0 else sack_mesh
		mi.rotation.y = float(i) * 1.7
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_outer.append(mi)
		_outer_base.append(Vector3.ZERO)
	_empty = MeshInstance3D.new()
	_empty.name = "Gnawed"
	_empty.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_empty.mesh = _build_gnawed(mat, 12.0)
	add_child(_empty)
	set_process(false)
	_apply_stage(4, false)


func setup(ring_radius_m: float) -> void:
	for i: int in OUTER_COUNT:
		var ang: float = TAU * float(i) / float(OUTER_COUNT)
		_outer_base[i] = Vector3(sin(ang) * ring_radius_m, 0.0, -cos(ang) * ring_radius_m)
		_outer[i].position = _outer_base[i]
	_empty.mesh = _build_gnawed(MeshKit.vcol_material(), ring_radius_m)


func set_stock_pct(pct: float) -> void:
	var stage: int = CornStockVisualBase.stage_for(pct)
	if stage == _stage:
		return
	_apply_stage(stage, is_inside_tree())


func set_under_attack(on: bool) -> void:
	_attack = on
	set_process(on)
	if not on:
		for i: int in OUTER_COUNT:
			_outer[i].position = _outer_base[i]


func _process(delta: float) -> void:
	_time += delta
	for i: int in OUTER_COUNT:
		if _outer[i].visible:
			var ph: float = _time * SHAKE_SPEED + float(i) * 2.1
			_outer[i].position = _outer_base[i] + Vector3(sin(ph), 0.0, cos(ph * 1.3)) * SHAKE_AMPLITUDE


func _apply_stage(stage: int, animate: bool) -> void:
	_stage = stage
	if _tween != null:
		_tween.kill()
		_tween = null
	_empty.visible = stage == 0
	var targets: Array[Vector3] = []
	targets.append(Vector3(PILE_SCALE_XZ[stage], PILE_SCALE_Y[stage], PILE_SCALE_XZ[stage]))
	for i: int in OUTER_COUNT:
		var s: float = OUTER_SCALE[stage][i]
		targets.append(Vector3(s, s, s))
	var nodes: Array[MeshInstance3D] = [_pile]
	nodes.append_array(_outer)
	if animate:
		_tween = create_tween().set_parallel(true)
	for i: int in nodes.size():
		var node: MeshInstance3D = nodes[i]
		var t: Vector3 = targets[i]
		var show: bool = t.y > 0.0
		var goal: Vector3 = t if show else Vector3.ONE * HIDDEN_SCALE
		if animate:
			if show:
				node.visible = true
			_tween.tween_property(node, "scale", goal, TRANSITION_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if not show:
				_tween.tween_callback(node.hide).set_delay(TRANSITION_S)
		else:
			node.scale = goal
			node.visible = show


# ---------------------------------------------------------------- meshes

## Lumpy dome of corn with a few cobs on top. Unit footprint scaled by the caller's radii; origin on the floor.
static func _dome(k: MeshKit, center: Vector3, rx: float, rz: float, h: float, segs: int, rng: RandomNumberGenerator, jitter: float) -> void:
	var rings: Array = []
	for p: Vector2 in DOME_PROFILE:
		var ring: Array = []
		for i: int in segs:
			var a: float = TAU * float(i) / float(segs)
			var j: float = 1.0 + (rng.randf() - 0.5) * jitter if p.x > 0.0 and p.x < 1.0 else 1.0
			ring.append(center + Vector3(cos(a) * rx * p.x * j, p.y * h * (1.0 + (rng.randf() - 0.5) * jitter * 0.5 if p.y < 1.0 else 1.0), sin(a) * rz * p.x * j))
		rings.append(ring)
	var inside: Vector3 = center + Vector3(0.0, h * 0.35, 0.0)
	for r: int in rings.size() - 1:
		var a_ring: Array = rings[r]
		var b_ring: Array = rings[r + 1]
		var tone: float = float(r) / float(rings.size() - 1)
		for i: int in segs:
			var n: int = (i + 1) % segs
			var c0: Color = CORN_DARK.lerp(CORN, tone + 0.25) if i % 2 == 0 else CORN.lerp(STRAW, 0.15 * float((i + r) % 3))
			var c1: Color = c0.lightened(0.08)
			k.tri(a_ring[i], a_ring[n], b_ring[n], c0, c0, c1, inside)
			if r < rings.size() - 2:
				k.tri(a_ring[i], b_ring[n], b_ring[i], c0, c1, c1, inside)


static func _cob(k: MeshKit, pos: Vector3, yaw: float) -> void:
	k.set_xf(pos, Vector3(0.0, yaw, 62.0))
	k.prism(Vector3(0.0, 0.0, 0.0), Vector2(0.15, 0.15), Vector2(0.08, 0.08), 0.5, CORN, STRAW)
	k.reset_xf()


static func _build_pile(mat: Material) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	_dome(k, PILE_CENTER, PILE_RADIUS_X, PILE_RADIUS_Z, PILE_HEIGHT_M, PILE_SEGMENTS, rng, 0.14)
	for i: int in 6:
		var a: float = rng.randf() * TAU
		var d: float = 0.3 + rng.randf() * 0.4
		var py: float = PILE_HEIGHT_M * (1.0 - d * 0.7) * 0.9
		_cob(k, PILE_CENTER + Vector3(cos(a) * PILE_RADIUS_X * d, py, sin(a) * PILE_RADIUS_Z * d), rng.randf() * 360.0)
	return k.build(mat)


static func _build_heap(mat: Material) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 1
	_dome(k, Vector3.ZERO, 1.25, 1.25, 1.0, 8, rng, 0.12)
	for i: int in 3:
		_cob(k, Vector3(cos(float(i) * 2.1) * 0.5, 0.78, sin(float(i) * 2.1) * 0.5), float(i) * 70.0)
	return k.build(mat)


static func _build_sacks(mat: Material) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	var spots: Array[Vector3] = [Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.1), Vector3(0.0, 0.0, -0.6), Vector3(0.0, 0.8, -0.05)]
	var yaws: Array[float] = [8.0, -12.0, 4.0, 25.0]
	for i: int in spots.size():
		k.set_xf(spots[i], Vector3(0.0, yaws[i], 0.0))
		k.prism(Vector3.ZERO, Vector2(0.85, 0.6), Vector2(0.62, 0.42), 0.8, SACK_DARK, SACK)
	k.reset_xf()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 2
	_dome(k, Vector3(0.0, 0.0, 0.9), 0.7, 0.6, 0.35, 6, rng, 0.1)
	return k.build(mat)


## Empty stage: straw and gnawed cobs on the barn floor and on each ring spot.
static func _build_gnawed(mat: Material, ring_radius_m: float) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 3
	var spots: Array[Vector3] = []
	for i: int in 3:
		spots.append(Vector3(rng.randf_range(-5.5, 5.5), 0.0, rng.randf_range(-2.5, 3.5)))
	for i: int in OUTER_COUNT:
		var ang: float = TAU * float(i) / float(OUTER_COUNT)
		spots.append(Vector3(sin(ang) * ring_radius_m, 0.0, -cos(ang) * ring_radius_m))
	for s: Vector3 in spots:
		for j: int in 1:
			var o: Vector3 = s + Vector3(rng.randf_range(-0.8, 0.8), 0.03, rng.randf_range(-0.8, 0.8))
			var yaw: float = rng.randf() * 360.0
			k.set_xf(o, Vector3(0.0, yaw, 0.0))
			var w: float = rng.randf_range(0.5, 0.8)
			k.quad_double(Vector3(-w, 0, -0.18), Vector3(w, 0, -0.12), Vector3(w * 0.9, 0, 0.16), Vector3(-w * 0.8, 0, 0.2), STRAW if j == 0 else STRAW_DARK)
		k.set_xf(s + Vector3(0.25, 0.05, 0.1), Vector3(0.0, rng.randf() * 360.0, 80.0))
		k.prism(Vector3.ZERO, Vector2(0.12, 0.12), Vector2(0.07, 0.07), 0.32, CORN_DARK, STRAW_DARK)
	k.reset_xf()
	return k.build(mat)
