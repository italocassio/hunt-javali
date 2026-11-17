extends RefCounted
## Corn building blocks for the HD props (bait, feed trough, barn stock): kernelled cobs, husk leaves,
## lumpy grain mounds and loose grains. Kernels come from the shader (feature F_CORN), geometry stays light.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")


## Cob lying along `dir` from `pos` (its cut stem end). detail 1 = 6 sides x 4 rings, 0 = 5 sides x 3 rings.
static func cob(m: HDMesh, pos: Vector3, dir: Vector3, length: float, radius: float, detail: int = 1, color: Color = PM.CORN_YELLOW) -> void:
	m.paint(color, 0.0, 0.5, PM.CORN_COB, PM.F_CORN)
	var prof: Array
	if detail > 0:
		prof = [Vector3(0.0, radius * 0.42, 0.0), Vector3(length * 0.12, radius * 0.96, 0.0), Vector3(length * 0.6, radius, 0.0),
			Vector3(length * 0.92, radius * 0.7, 0.0), Vector3(length, 0.0, 0.0)]
	else:
		prof = [Vector3(0.0, radius * 0.5, 0.0), Vector3(length * 0.15, radius, 0.0), Vector3(length * 0.82, radius * 0.85, 0.0), Vector3(length, 0.0, 0.0)]
	m.lathe(prof, 6 if detail > 0 else 5, pos, dir)


## Bare gnawed cob core (pale, no kernels).
static func bare_cob(m: HDMesh, pos: Vector3, dir: Vector3, length: float, radius: float) -> void:
	m.paint(PM.WOOD_LIGHT.lightened(0.25), 0.0, 0.9, PM.GRAIN_Z, PM.F_WOOD)
	var prof: Array = [Vector3(0.0, radius * 0.7, 0.0), Vector3(length * 0.5, radius, 0.0), Vector3(length, radius * 0.55, 0.0)]
	m.lathe(prof, 5, pos, dir)


## Double-sided husk leaf (palha) from `base` along `dir`, drooping by `droop` at the tip.
static func husk_leaf(m: HDMesh, base: Vector3, dir: Vector3, length: float, width: float, droop: float, color: Color = PM.HUSK) -> void:
	m.paint(color, 0.0, 1.0, 0.0, PM.F_HAY)
	var z: Vector3 = dir.normalized()
	var x: Vector3 = Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var y: Vector3 = z.cross(x)
	var p0: Vector3 = base - x * width * 0.3
	var p1: Vector3 = base + x * width * 0.3
	var mid: Vector3 = base + z * length * 0.45 + y * droop * 0.15
	var m0: Vector3 = mid - x * width * 0.5
	var m1: Vector3 = mid + x * width * 0.5
	var tip: Vector3 = base + z * length - y * droop
	m.begin_part()
	m.quad(p0, p1, m1, m0, y)
	m.tri(m0, m1, tip, y)
	m.quad(p0, m0, m1, p1, -y)
	m.tri(m0, tip, m1, -y)


## Lumpy dome of loose grain, origin `center` on its floor. Elliptical footprint rx x rz, height h.
static func grain_mound(m: HDMesh, center: Vector3, rx: float, rz: float, h: float, segs: int, rng: RandomNumberGenerator, jitter: float, color: Color = PM.CORN_YELLOW) -> void:
	m.paint(color, 0.0, 0.55, PM.CORN_LOOSE, PM.F_CORN)
	var prof: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.88, 0.40), Vector2(0.58, 0.80), Vector2(0.22, 0.98)]
	var rings: Array = []
	for pi: int in prof.size():
		var ring: PackedVector3Array = PackedVector3Array()
		for i: int in segs:
			var a: float = TAU * float(i) / float(segs)
			var j: float = 1.0 + (rng.randf() - 0.5) * jitter if pi > 0 else 1.0
			var hy: float = 1.0 + (rng.randf() - 0.5) * jitter * 0.6 if pi > 0 else 1.0
			ring.push_back(center + Vector3(cos(a) * rx * prof[pi].x * j, prof[pi].y * h * hy, sin(a) * rz * prof[pi].x * j))
		rings.append(ring)
	m.loft(rings, false, true)


## Tiny grains lying on a flat floor at height y, scattered in a disc.
static func loose_grains(m: HDMesh, rng: RandomNumberGenerator, center: Vector3, radius_min: float, radius_max: float, count: int) -> void:
	m.paint(PM.CORN_YELLOW, 0.0, 0.5, PM.CORN_LOOSE, PM.F_CORN)
	for i: int in count:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(radius_min, radius_max)
		var c: Vector3 = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var yaw: float = rng.randf() * TAU
		var d: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw)) * 0.016
		var s: Vector3 = Vector3(-d.z, 0.0, d.x) * 0.55
		m.quad(c - d - s, c + d - s, c + d + s, c - d + s, Vector3.UP)
