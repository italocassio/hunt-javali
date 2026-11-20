extends CornStockVisualBase
## HD visual corn stock of the barn (docs/horda.md section 11.1, docs/plano_horda_nivel2.md section 7). A wooden
## grain bin (tulha) inside the barn, fixed footprint x [-6, 6], z [1.6, 4.7], walls 1.2 m, filled with corn, plus six
## heaps / sack stacks on the boars' eating ring. 9 MeshInstance3D, ONE shared material (prop_materials.gd; the
## kernels come from the F_CORN shader feature), no physics, no lights.
## Stages: 4 full, 3/2/1 the grain sinks inside the bin (only the height changes, the footprint is fixed so the
## barn collision matches at every stage) while the outer heaps shrink and vanish, 0 empty (straw, gnawed cobs).
## The grain mesh is centred on its own origin and the node sits at PILE_CENTER, so stage scaling sinks it in place.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")
const Corn := preload("res://assets/models/props/corn_hd.gd")

const OUTER_COUNT: int = 6
const BIN_X: float = 6.0            # outer half width of the bin
const BIN_Z0: float = 1.6           # outer front / back limits (barn frame, front = -Z)
const BIN_Z1: float = 4.7
const BIN_WALL_H: float = 1.2
const BIN_WALL_T: float = 0.06
const BIN_POST: float = 0.16
const BIN_BOARDS: int = 3
const PILE_CENTER: Vector3 = Vector3(0.0, 0.0, 3.15)   # centre of the bin
const PILE_RADIUS_X: float = 5.8
const PILE_RADIUS_Z: float = 1.36
const PILE_HEIGHT_M: float = 1.55   # peak, a little above the wall top
const PILE_SEGMENTS: int = 14
const PILE_CORNER: float = 0.5      # superellipse exponent (0.5 = squarish, fills the bin corners)
const HEAP_RADIUS: float = 1.25
const HEAP_HEIGHT: float = 1.0
## Per stage (index = stage): inner pile scale (xz, y) and outer heap scale per heap index (0 = hidden).
const PILE_SCALE_XZ: Array[float] = [0.0, 1.0, 1.0, 1.0, 1.0]   # fixed footprint
const PILE_SCALE_Y: Array[float] = [0.0, 0.3, 0.5, 0.75, 1.0]
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

var _bin: MeshInstance3D = null
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
	_bin = MeshInstance3D.new()
	_bin.name = "Bin"
	_bin.mesh = _mesh(&"bin")
	_bin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_bin)
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

## Shared mesh by key (&"pile", &"bin", &"heap", &"sacks"), built once.
static func _mesh(key: StringName) -> ArrayMesh:
	if not _meshes.has(key):
		var built: Dictionary
		match key:
			&"pile": built = _build_pile()
			&"bin": built = _build_bin()
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
	_mesh(&"bin")
	_mesh(&"heap")
	_mesh(&"sacks")
	var gn: Dictionary = _build_gnawed(DEFAULT_RING_M)
	var tris: int = int(_stats[&"pile"]["triangles"]) + int(_stats[&"bin"]["triangles"]) + OUTER_COUNT / 2 * (int(_stats[&"heap"]["triangles"]) + int(_stats[&"sacks"]["triangles"])) + int(gn["triangles"])
	var verts: int = int(_stats[&"pile"]["vertices"]) + int(_stats[&"bin"]["vertices"]) + int(_stats[&"heap"]["vertices"]) + int(_stats[&"sacks"]["vertices"]) + int(gn["vertices"])
	return {
		"triangles": tris, "vertices": verts, "materials": 1, "mesh_instances": 2 + OUTER_COUNT + 1,
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


## Grain filling the bin, centred on the origin of its node (squarish dome), with a few cobs half buried in it.
static func _build_pile() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	m.paint(PM.CORN_YELLOW, 0.0, 0.55, PM.CORN_LOOSE, PM.F_CORN)
	var prof: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.88, 0.40), Vector2(0.58, 0.80), Vector2(0.22, 0.98)]
	var rings: Array = []
	for pi: int in prof.size():
		var ring: PackedVector3Array = PackedVector3Array()
		for i: int in PILE_SEGMENTS:
			var a: float = TAU * float(i) / float(PILE_SEGMENTS)
			var c: float = cos(a)
			var sn: float = sin(a)
			var j: float = 1.0 + (rng.randf() - 0.5) * 0.08 if pi > 0 else 1.0
			var hy: float = 1.0 + (rng.randf() - 0.5) * 0.08 if pi > 0 else 1.0
			var x: float = signf(c) * pow(absf(c), PILE_CORNER) * PILE_RADIUS_X * prof[pi].x * j
			var z: float = signf(sn) * pow(absf(sn), PILE_CORNER) * PILE_RADIUS_Z * prof[pi].x * j
			ring.push_back(Vector3(x, prof[pi].y * PILE_HEIGHT_M * hy, z))
		rings.append(ring)
	m.loft(rings, false, true)
	for i: int in 2:
		var px: float = rng.randf_range(-0.8, 0.8) * PILE_RADIUS_X * 0.8
		var pz: float = rng.randf_range(-0.4, 0.4) * PILE_RADIUS_Z
		var py: float = PILE_HEIGHT_M * 0.93
		var yaw: float = rng.randf() * TAU
		var dir: Vector3 = Vector3(cos(yaw), 0.25, sin(yaw)).normalized()
		Corn.cob(m, Vector3(px, py, pz) - dir * 0.17, dir, 0.34, 0.048, 0, PM.CORN_YELLOW if i % 2 == 0 else PM.CORN_DEEP)
	return Common.finish(m, t0, AO_RAYS, 0.6, 0.8, 0.6)


## The wooden bin: plank walls (4 boards high) between square posts. Barn frame (x, z), origin on the floor.
static func _build_bin() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var xc: float = BIN_X - BIN_POST * 0.5   # wall centre lines
	var zf: float = BIN_Z0 + BIN_POST * 0.5
	var zb: float = BIN_Z1 - BIN_POST * 0.5
	var zc: float = (zf + zb) * 0.5
	var bh: float = BIN_WALL_H / float(BIN_BOARDS) - 0.012
	for k: int in BIN_BOARDS:
		var y: float = (float(k) + 0.5) * BIN_WALL_H / float(BIN_BOARDS)
		var col: Color = PM.WOOD_LIGHT if k % 2 == 0 else PM.WOOD_RAW.lightened(0.08)
		m.paint(col, 0.0, 0.9, PM.GRAIN_X, PM.F_WOOD)
		m.cbox(Vector3(0.0, y, zf), Vector3(2.0 * xc, bh, BIN_WALL_T), 0.0)
		m.cbox(Vector3(0.0, y, zb), Vector3(2.0 * xc, bh, BIN_WALL_T), 0.0)
		m.paint(col, 0.0, 0.9, PM.GRAIN_Z, PM.F_WOOD)
		m.cbox(Vector3(xc, y, zc), Vector3(BIN_WALL_T, bh, zb - zf), 0.0)
		m.cbox(Vector3(-xc, y, zc), Vector3(BIN_WALL_T, bh, zb - zf), 0.0)
	m.paint(PM.WOOD_RAW.darkened(0.15), 0.0, 0.9, PM.GRAIN_Y, PM.F_WOOD)
	var post_x: Array[float] = [-xc, xc]
	for x: float in post_x:
		m.cbox(Vector3(x, BIN_WALL_H * 0.5 + 0.06, zf), Vector3(BIN_POST, BIN_WALL_H + 0.12, BIN_POST), 0.0)
		m.cbox(Vector3(x, BIN_WALL_H * 0.5 + 0.06, zb), Vector3(BIN_POST, BIN_WALL_H + 0.12, BIN_POST), 0.0)
	return Common.finish(m, t0, 4, 0.5, 0.7, 0.6)


## Heap of grain with a few cobs on top (outer heap, origin on the floor).
static func _build_heap() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 1
	Corn.grain_mound(m, Vector3.ZERO, HEAP_RADIUS, HEAP_RADIUS, HEAP_HEIGHT, 6, rng, 0.1)
	for i: int in 1:
		var a: float = float(i) * 2.1 + 0.4
		var d: float = 0.35
		var dir: Vector3 = Vector3(cos(a + 1.4), 0.3, sin(a + 1.4)).normalized()
		var p: Vector3 = Vector3(cos(a) * HEAP_RADIUS * d, _dome_y(d) * HEAP_HEIGHT * 0.95, sin(a) * HEAP_RADIUS * d)
		Corn.cob(m, p - dir * 0.14, dir, 0.3, 0.045, 0, PM.CORN_YELLOW if i % 2 == 0 else PM.CORN_DEEP)
	return Common.finish(m, t0, AO_RAYS, 0.4, 0.8, 0.6)


## Two burlap sacks side by side (origin on the floor).
static func _build_sacks() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	m.paint(PM.SACK_CLOTH, 0.0, 1.0, 0.0, PM.F_HAY)
	var spots: Array[Vector3] = [Vector3(-0.5, 0.2, 0.0), Vector3(0.45, 0.2, 0.1)]
	var yaws: Array[float] = [8.0, -14.0]
	for i: int in spots.size():
		m.xf = Transform3D(Basis(Vector3.UP, deg_to_rad(yaws[i])), spots[i])
		m.cbox(Vector3.ZERO, Vector3(0.95, 0.4, 0.58), 0.13)
	m.xf = Transform3D.IDENTITY
	return Common.finish(m, t0, AO_RAYS, 0.4, 0.8, 0.6)


## Empty stage: straw and gnawed cobs on each ring spot.
static func _build_gnawed(ring_radius_m: float) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED + 3
	var spots: Array[Vector3] = []
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
