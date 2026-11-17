extends RefCounted
## HD farm gate (prop `gate`, porteira): two square timber posts, a leaf with four rails, two stiles, a middle
## stile and a diagonal brace, steel hinges and a latch. 4 x 1.4 x 0.2 m, closed, front = -Z.
## 100% procedural, one mesh, one shared material (prop_materials.gd).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")

const POST_X: float = 1.9
const POST_W: float = 0.2
const POST_TOP: float = 1.4
const POST_BOTTOM: float = -0.1
const LEAF_X: float = 1.72            # centre of the stiles
const RAIL_YS: Array[float] = [0.28, 0.58, 0.88, 1.18]
const RAIL_Z: float = -0.04
const BRACE_Z: float = -0.085
const AO_RAYS: int = 6
const AO_RADIUS: float = 0.3

static var _cache: Dictionary = {}


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	_posts(m)
	_leaf(m)
	_ironwork(m)
	return Common.finish(m, t0, AO_RAYS, AO_RADIUS, 0.9, 0.55)


static func _posts(m: HDMesh) -> void:
	Common.paint(m, PM.WOOD_RAW * 0.92, 0.92, PM.F_WOOD, PM.GRAIN_Y)
	var h: float = POST_TOP - POST_BOTTOM
	for sx: float in [-1.0, 1.0]:
		m.cbox(Vector3(sx * POST_X, POST_BOTTOM + h * 0.5, 0.0), Vector3(POST_W, h, POST_W), 0.014)


static func _leaf(m: HDMesh) -> void:
	# stiles and the middle stile behind the rails
	Common.paint(m, PM.WOOD_LIGHT, 0.9, PM.F_WOOD, PM.GRAIN_Y)
	var y0: float = RAIL_YS[0] - 0.06
	var y1: float = RAIL_YS[RAIL_YS.size() - 1] + 0.06
	for x: float in [-LEAF_X, 0.0, LEAF_X]:
		m.cbox(Vector3(x, (y0 + y1) * 0.5, 0.012), Vector3(0.09 if x != 0.0 else 0.07, y1 - y0, 0.05), 0.0)
	# rails in front
	Common.paint(m, PM.WOOD_LIGHT, 0.9, PM.F_WOOD, PM.GRAIN_X)
	for y: float in RAIL_YS:
		m.cbox(Vector3(0.0, y, RAIL_Z), Vector3(2.0 * (POST_X - POST_W * 0.5) - 0.02, 0.1, 0.045), 0.008)
	# diagonal brace: from the low hinge end up to the high latch end
	Common.paint(m, PM.WOOD_RAW, 0.9, PM.F_WOOD, PM.GRAIN_X)
	var a: Vector3 = Vector3(-LEAF_X, RAIL_YS[0], BRACE_Z)
	var b: Vector3 = Vector3(LEAF_X, RAIL_YS[RAIL_YS.size() - 1], BRACE_Z)
	Common.beam(m, a, b, 0.04, 0.09, 0.008)


static func _ironwork(m: HDMesh) -> void:
	Common.paint(m, PM.ZINC_GREY * 0.55, 0.5, PM.F_ZINC)
	for y: float in [RAIL_YS[0], RAIL_YS[3]]:
		m.cbox(Vector3(-POST_X + 0.12, y, -0.1), Vector3(0.36, 0.045, 0.014), 0.0)
	m.cbox(Vector3(POST_X - 0.06, RAIL_YS[2] + 0.1, -0.108), Vector3(0.14, 0.05, 0.02), 0.0)
