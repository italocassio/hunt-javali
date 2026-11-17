extends RefCounted
## HD corn bait (prop `corn_bait`, ceva): a small mound of loose grain with kernelled cobs laid on it, a few
## husk leaves (palha) and grains scattered on the ground. 1 x 0.3 x 1 m, origin on the ground at the centre.
## 100% procedural, one mesh, one shared material (prop_materials.gd).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")
const Corn := preload("res://assets/models/props/corn_hd.gd")

const SEED: int = 777
const COB_L: float = 0.21
const COB_R: float = 0.03
const MOUND_R: float = 0.36
const MOUND_H: float = 0.17
const AO_RAYS: int = 8
const AO_RADIUS: float = 0.25

static var _cache: Dictionary = {}


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


## Mound height at radius r (close enough to the lumpy dome to sit cobs on it).
static func _mound_y(r: float) -> float:
	return MOUND_H * clampf(1.0 - (r / MOUND_R) * (r / MOUND_R) * 0.9, 0.0, 1.0)


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	Corn.grain_mound(m, Vector3.ZERO, MOUND_R, MOUND_R * 0.95, MOUND_H, 12, rng, 0.1, PM.CORN_DEEP)
	# husk first (under the cobs): peeled leaves around the heap
	for i: int in 5:
		var a: float = 0.4 + float(i) * 1.27
		var base: Vector3 = Vector3(cos(a) * 0.2, 0.05, sin(a) * 0.2)
		Corn.husk_leaf(m, base, Vector3(cos(a), -0.04, sin(a)), 0.2 + rng.randf() * 0.05, 0.1, 0.04, PM.HUSK_DRY if i % 2 == 0 else PM.HUSK.darkened(0.2))
	# cobs: [angle, radius from centre, top layer flag]
	var layout: Array = [[0.0, 0.2, 0.0], [1.15, 0.22, 0.0], [2.3, 0.18, 0.0], [3.5, 0.21, 0.0], [4.7, 0.2, 0.0], [5.6, 0.24, 0.0], [0.6, 0.1, 1.0], [2.9, 0.08, 1.0]]
	for e: Array in layout:
		var ang: float = e[0]
		var rr: float = e[1]
		var top: bool = e[2] > 0.5
		var y: float = _mound_y(rr) + COB_R * (1.0 if not top else 2.7)
		var yaw: float = ang + 1.5 + rng.randf() * 0.5
		var dir: Vector3 = Vector3(cos(yaw), 0.12, sin(yaw)).normalized()
		var mid: Vector3 = Vector3(cos(ang) * rr, y, sin(ang) * rr)
		var color: Color = PM.CORN_YELLOW if (int(ang * 3.0) % 2 == 0) else PM.CORN_DEEP
		Corn.cob(m, mid - dir * COB_L * 0.5, dir, COB_L, COB_R, 1, color)
	# one cob that rolled off the heap, onto the ground
	Corn.cob(m, Vector3(0.28, COB_R, -0.40), Vector3(0.6, 0.0, 0.8).normalized(), COB_L, COB_R, 0, PM.CORN_YELLOW)
	Corn.loose_grains(m, rng, Vector3(0.0, 0.004, 0.0), 0.33, 0.47, 8)
	# grains that rolled furthest: they set the 1 x 1 m footprint
	for k: int in 4:
		var ang: float = float(k) * PI * 0.5 + 0.2
		Corn.loose_grains(m, rng, Vector3(cos(ang) * 0.485, 0.004, sin(ang) * 0.485), 0.0, 0.0, 1)
	return Common.finish(m, t0, AO_RAYS, AO_RADIUS, 0.9, 0.5)
