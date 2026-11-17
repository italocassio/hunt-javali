extends RefCounted
## HD feed trough (prop `feed_trough`, cocho): weathered plank trough on four splayed legs, filled with corn
## (grain mound and a few cobs). 3 x 0.6 x 0.8 m, long axis X, origin on the ground at the centre.
## 100% procedural, one mesh, one shared material (prop_materials.gd).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")
const Corn := preload("res://assets/models/props/corn_hd.gd")

const HALF_X: float = 1.45             # inner half length
const BOTTOM_Y: float = 0.27           # top face of the bottom board
const RIM_Y: float = 0.6
const HALF_BOTTOM: float = 0.2         # half width at the bottom
const HALF_TOP: float = 0.35           # half width at the rim
const T: float = 0.05
const SEED: int = 31
const AO_RAYS: int = 8
const AO_RADIUS: float = 0.35

static var _cache: Dictionary = {}


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	_body(m)
	_legs(m)
	_corn(m)
	return Common.finish(m, t0, AO_RAYS, AO_RADIUS, 0.9, 0.5)


static func _body(m: HDMesh) -> void:
	Common.paint(m, PM.WOOD_LIGHT * 1.05, 0.9, PM.F_WOOD, PM.GRAIN_X)
	m.cbox(Vector3(0.0, BOTTOM_Y - T * 0.5, 0.0), Vector3(2.0 * HALF_X + 0.1, T, 2.0 * HALF_BOTTOM + 0.04), 0.0)
	# sides lean outwards: board between (z = +-HALF_BOTTOM, BOTTOM_Y) and (z = +-HALF_TOP, RIM_Y)
	var dz: float = HALF_TOP - HALF_BOTTOM
	var dy: float = RIM_Y - BOTTOM_Y
	var blen: float = sqrt(dz * dz + dy * dy)
	var ang: float = atan2(dz, dy)
	for sz: float in [-1.0, 1.0]:
		var c: Vector3 = Vector3(0.0, (BOTTOM_Y + RIM_Y) * 0.5, sz * (HALF_BOTTOM + HALF_TOP) * 0.5)
		m.xf = Transform3D(Basis(Vector3.RIGHT, -sz * ang), c)
		m.cbox(Vector3.ZERO, Vector3(2.0 * HALF_X + 0.14, blen, T), 0.0)
		m.xf = Transform3D.IDENTITY
	# end boards: trapezoid slabs
	Common.paint(m, PM.WOOD_LIGHT * 1.15, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	var poly: PackedVector2Array = PackedVector2Array([
		Vector2(-HALF_BOTTOM - 0.02, BOTTOM_Y - T), Vector2(HALF_BOTTOM + 0.02, BOTTOM_Y - T),
		Vector2(HALF_TOP + 0.05, RIM_Y), Vector2(-HALF_TOP - 0.05, RIM_Y)])
	for sx: float in [-1.0, 1.0]:
		var frame: Transform3D = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(sx * (HALF_X + 0.05), 0.0, 0.0))
		m.extrude(poly, frame, -0.03, 0.03, 0.0)


static func _legs(m: HDMesh) -> void:
	Common.paint(m, PM.WOOD_RAW * 1.1, 0.92, PM.F_WOOD, PM.GRAIN_Y)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var top: Vector3 = Vector3(sx * 1.1, BOTTOM_Y - T, sz * 0.17)
			var bot: Vector3 = Vector3(sx * 1.17, 0.0, sz * 0.32)
			Common.beam(m, bot, top, 0.1, 0.1, 0.0)


static func _corn(m: HDMesh) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	Corn.grain_mound(m, Vector3(0.0, BOTTOM_Y, 0.0), 1.38, 0.3, 0.36, 10, rng, 0.08, PM.CORN_YELLOW)
	var cobs: Array = [[-0.85, 0.05, 0.3, 0.25], [0.15, -0.06, 0.2, -0.4], [0.9, 0.04, -0.3, 0.5], [-0.2, 0.08, 0.25, 1.2]]
	for c: Array in cobs:
		var dir: Vector3 = Vector3(cos(float(c[3])), 0.05, sin(float(c[3]))).normalized()
		var mid: Vector3 = Vector3(c[0], BOTTOM_Y + 0.36 * 0.8 + 0.03, c[1])
		Corn.cob(m, mid - dir * 0.11, dir, 0.22, 0.03, 0, PM.CORN_YELLOW if float(c[2]) > 0.0 else PM.CORN_DEEP)
