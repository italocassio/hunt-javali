extends CornStockVisualBase
## HD visual corn stock of the barn (docs/horda.md section 11.1). One big pile of grain inside the barn plus six
## heaps / sack stacks on the boars' eating ring. 8 MeshInstance3D, ONE shared material (prop_materials.gd; the
## kernels come from the F_CORN shader feature), no physics, no lights.
## Stages: 4 full, 3/2/1 shrinking (outer heaps shrink and vanish, the inner pile sinks), 0 empty (straw and gnawed cobs).
## The pile mesh is centred on its own origin and the node sits at PILE_CENTER, so stage scaling shrinks it in place.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")
const Corn := preload("res://assets/models/props/corn_hd.gd")

const OUTER_COUNT: int = 6
const PILE_CENTER: Vector3 = Vector3(0.0, 0.0, 0.8)   # inside the barn (x +-7.85, z -5..4.7)
const PILE_RADIUS_X: float = 5.8
const PILE_RADIUS_Z: float = 3.4
const PILE_HEIGHT_M: float = 2.8
const PILE_SEGMENTS: int = 20
const HEAP_RADIUS: float = 1.25
const HEAP_HEIGHT: float = 1.0
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
const DEFAULT_RING_M: float = 11.0
const AO_RAYS: int = 6

## Meshes shared by every instance (pile, heap, sacks) and the per-radius gnawed floor mesh.
static var _meshes: Dictionary = {}
static var _stats: Dictionary = {}

var _pile: MeshInstance3D = null
var _outer: Array[MeshInstance3D] = []
var _empty: MeshInstance3D = null
var _outer_base: Array[Vector3] = []
var _ring_m: float = DEFAULT_RING_M
var _gnawed_ready: bool = false
var _stage: int = -1
var _attack: bool = false
var _tween: Tween = null
var _time: float = 0.0


func _init() -> void:
	name = "BarnCorn"
	_pile = MeshInstance3D.new()
	_pile.name = "InnerPile"
	_pile.mesh = _mesh(&"pile")
	_pile.position = PILE_CENTER
	_pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_pile)
	var heap_mesh: ArrayMesh = _mesh(&"heap")
	var sack_mesh: ArrayMesh = _mesh(&"sacks")
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
	_empty.mesh = ArrayMesh.new()   # built on demand: only the empty stage shows it
	add_child(_empty)
	set_process(false)
	_apply_stage(4, false)


func setup(ring_radius_m: float) -> void:
	_ring_m = ring_radius_m
	for i: int in OUTER_COUNT:
		var ang: float = TAU * float(i) / float(OUTER_COUNT)
		_outer_base[i] = Vector3(sin(ang) * ring_radius_m, 0.0, -cos(ang) * ring_radius_m)
		_outer[i].position = _outer_base[i]
	_gnawed_ready = false
	if _empty.visible:
		_ensure_gnawed()


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


func _ensure_gnawed() -> void:
	if _gnawed_ready:
		return
	_gnawed_ready = true
	_empty.mesh = _build_gnawed(_ring_m)["mesh"]


func _apply_stage(stage: int, animate: bool) -> void:
	_stage = stage
	if _tween != null:
		_tween.kill()
		_tween = null
	if stage == 0:
		_ensure_gnawed()
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

## Shared mesh by key (&"pile", &"heap", &"sacks"), built once.
static func _mesh(key: StringName) -> ArrayMesh:
	if not _meshes.has(key):
		var built: Dictionary
		match key:
			&"pile": built = _build_pile()
			&"heap": built = _build_heap()
			_: built = _build_sacks()
		_meshes[key] = built["mesh"]
		_stats[key] = built
	return _meshes[key]


## Cold build of every mesh (previews and tests): { triangles (all 8 instances), vertices, build_ms, materials, mesh_instances }.
static func build() -> Dictionary:
	_meshes.clear()
	_stats.clear()
	var t0: int = Time.get_ticks_usec()
	_mesh(&"pile")
	_mesh(&"heap")
	_mesh(&"sacks")
	var gn: Dictionary = _build_gnawed(DEFAULT_RING_M)
	var tris: int = int(_stats[&"pile"]["triangles"]) + OUTER_COUNT / 2 * (int(_stats[&"heap"]["triangles"]) + int(_stats[&"sacks"]["triangles"])) + int(gn["triangles"])
	var verts: int = int(_stats[&"pile"]["vertices"]) + int(_stats[&"heap"]["vertices"]) + int(_stats[&"sacks"]["vertices"]) + int(gn["vertices"])
	return {
		"triangles": tris, "vertices": verts, "materials": 1, "mesh_instances": 1 + OUTER_COUNT + 1,
		"build_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"mesh": _meshes[&"pile"], "gnawed": gn["mesh"], "heap": _meshes[&"heap"], "sacks": _meshes[&"sacks"],
	}


static func get_model() -> Dictionary:
	if _meshes.is_empty():
		return build()
	return {"mesh": _meshes[&"pile"]}


## Dome height share (0..1) at the normalised radius rho (1 = rim), same profile as Corn.grain_mound.
static func _dome_y(rho: float) -> float:
	var prof: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.88, 0.40), Vector2(0.58, 0.80), Vector2(0.22, 0.98), Vector2(0.0, 1.0)]
	for i: int in prof.size() - 1:
		if rho <= prof[i].x and rho >= prof[i + 1].x:
			var t: float = (prof[i].x - rho) / maxf(prof[i].x - prof[i + 1].x, 1e-5)
			return lerpf(prof[i].y, prof[i + 1].y, t)
	return 0.0 if rho > 1.0 else 1.0


## Big pile centred on the origin of its node, with a few cobs half buried in the grain.
static func _build_pile() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	Corn.grain_mound(m, Vector3.ZERO, PILE_RADIUS_X, PILE_RADIUS_Z, PILE_HEIGHT_M, PILE_SEGMENTS, rng, 0.12)
	for i: int in 6:
		var a: float = rng.randf() * TAU
		var d: float = 0.25 + rng.randf() * 0.4
		var px: float = cos(a) * PILE_RADIUS_X * d
		var pz: float = sin(a) * PILE_RADIUS_Z * d
		var py: float = _dome_y(d) * PILE_HEIGHT_M * 0.97
		var yaw: float = rng.randf() * TAU
		var dir: Vector3 = Vector3(cos(yaw), 0.25, sin(yaw)).normalized()
		Corn.cob(m, Vector3(px, py, pz) - dir * 0.17, dir, 0.34, 0.048, 0, PM.CORN_YELLOW if i % 2 == 0 else PM.CORN_DEEP)
	return Common.finish(m, t0, AO_RAYS, 0.6, 0.8, 0.6)


## Heap of grain with a few cobs on top (outer heap, origin on the floor).
static func _build_heap() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 1
	Corn.grain_mound(m, Vector3.ZERO, HEAP_RADIUS, HEAP_RADIUS, HEAP_HEIGHT, 8, rng, 0.1)
	for i: int in 3:
		var a: float = float(i) * 2.1 + 0.4
		var d: float = 0.35
		var dir: Vector3 = Vector3(cos(a + 1.4), 0.3, sin(a + 1.4)).normalized()
		var p: Vector3 = Vector3(cos(a) * HEAP_RADIUS * d, _dome_y(d) * HEAP_HEIGHT * 0.95, sin(a) * HEAP_RADIUS * d)
		Corn.cob(m, p - dir * 0.14, dir, 0.3, 0.045, 0, PM.CORN_YELLOW if i % 2 == 0 else PM.CORN_DEEP)
	return Common.finish(m, t0, AO_RAYS, 0.4, 0.8, 0.6)


## Three burlap sacks stacked, with grain spilled at the front (origin on the floor).
static func _build_sacks() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 2
	Corn.grain_mound(m, Vector3(0.0, 0.0, 0.95), 0.7, 0.55, 0.3, 6, rng, 0.1)
	m.paint(PM.SACK_CLOTH, 0.0, 1.0, 0.0, PM.F_HAY)
	var spots: Array[Vector3] = [Vector3(-0.5, 0.19, 0.0), Vector3(0.5, 0.19, 0.08), Vector3(0.0, 0.57, 0.03)]
	var yaws: Array[float] = [8.0, -12.0, 78.0]
	for i: int in spots.size():
		m.xf = Transform3D(Basis(Vector3.UP, deg_to_rad(yaws[i])), spots[i])
		m.cbox(Vector3.ZERO, Vector3(0.95, 0.4, 0.58), 0.13)
	m.xf = Transform3D.IDENTITY
	return Common.finish(m, t0, AO_RAYS, 0.4, 0.8, 0.6)


## Empty stage: straw and gnawed cobs on the barn floor and on each ring spot.
static func _build_gnawed(ring_radius_m: float) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 3
	var spots: Array[Vector3] = []
	for i: int in 3:
		spots.append(Vector3(rng.randf_range(-5.5, 5.5), 0.0, rng.randf_range(-2.5, 3.5)))
	for i: int in OUTER_COUNT:
		var ang: float = TAU * float(i) / float(OUTER_COUNT)
		spots.append(Vector3(sin(ang) * ring_radius_m, 0.0, -cos(ang) * ring_radius_m))
	for s: Vector3 in spots:
		var yaw: float = rng.randf() * TAU
		var o: Vector3 = s + Vector3(rng.randf_range(-0.8, 0.8), 0.03, rng.randf_range(-0.8, 0.8))
		Corn.husk_leaf(m, o, Vector3(cos(yaw), 0.0, sin(yaw)), rng.randf_range(0.9, 1.3), 0.45, 0.0, PM.HUSK_DRY)
		var cyaw: float = rng.randf() * TAU
		Corn.bare_cob(m, s + Vector3(0.25, 0.04, 0.1), Vector3(cos(cyaw), 0.0, sin(cyaw)), 0.3, 0.045)
	return Common.finish(m, t0, 4, 0.3, 0.6, 0.7)
