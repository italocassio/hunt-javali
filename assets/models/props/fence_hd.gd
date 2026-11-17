extends RefCounted
## HD barbed-wire fence segment (prop `fence_segment`): two round weathered posts (mourões), five strands of
## steel wire with a slight sag and a few barbs, one thin dropper in the middle. 4 x 1.3 x 0.15 m along X,
## wires on the -Z face. 100% procedural, one mesh, one shared material (prop_materials.gd).
## The map instances ~60 of these; map_root.gd already merges repeats into one MultiMesh (one draw call).

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")
const Common := preload("res://assets/models/props/prop_hd_common.gd")

const POST_X: float = 1.95
const POST_R: float = 0.065
const POST_TOP: float = 1.3
const POST_BOTTOM: float = -0.12
const WIRE_Z: float = -0.07
const WIRE_R: float = 0.009
const WIRE_YS: Array[float] = [0.30, 0.55, 0.80, 1.04, 1.24]
const SAG: float = 0.022
const BARB_XS: Array[float] = [-1.1, -0.2, 0.7, 1.45]
const BARB_WIRES: Array[int] = [1, 3]
const POST_SEGS: int = 6
const AO_RAYS: int = 6
const AO_RADIUS: float = 0.25

static var _cache: Dictionary = {}


static func get_model() -> Dictionary:
	if _cache.is_empty():
		_cache = build()
	return _cache


static func build() -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var m: HDMesh = HDMesh.new()
	_posts(m)
	_wires(m)
	return Common.finish(m, t0, AO_RAYS, AO_RADIUS, 0.8, 0.6)


static func _posts(m: HDMesh) -> void:
	m.paint(Color(0.40, 0.31, 0.23), 0.0, 0.92, PM.GRAIN_Y, PM.F_WOOD)
	for sx: float in [-1.0, 1.0]:
		var prof: Array = [Vector3(POST_BOTTOM, POST_R * 1.15, 0.0), Vector3(POST_TOP - 0.12, POST_R * 0.95, 0.0),
			Vector3(POST_TOP - 0.05, POST_R * 0.75, 0.0), Vector3(POST_TOP, POST_R * 0.2, 0.0)]
		m.lathe(prof, POST_SEGS, Vector3(sx * POST_X, 0.0, 0.0), Vector3.UP)
	# dropper (balancim): thin stake that keeps the strands apart
	m.paint(Color(0.46, 0.36, 0.26), 0.0, 0.92, PM.GRAIN_Y, PM.F_WOOD)
	m.cbox(Vector3(0.0, 0.62, WIRE_Z + 0.002), Vector3(0.032, 1.26, 0.026), 0.0)


static func _wires(m: HDMesh) -> void:
	Common.paint(m, PM.WIRE_STEEL, 0.4, PM.F_ZINC)
	var section: PackedVector2Array = HDMesh.circle_section(WIRE_R, 3)
	for yi: int in WIRE_YS.size():
		var y: float = WIRE_YS[yi]
		var path: Array = []
		for k: int in 4:
			var t: float = float(k) / 3.0
			var sag: float = SAG * sin(t * PI)
			path.append(Vector3(lerpf(-POST_X, POST_X, t), y - sag, WIRE_Z))
		m.sweep(path, section, Vector3.BACK)
	# barbs: little flat kites on two of the strands
	for wi: int in BARB_WIRES:
		for bx: float in BARB_XS:
			var t2: float = (bx + POST_X) / (2.0 * POST_X)
			var by: float = WIRE_YS[wi] - SAG * sin(t2 * PI)
			var c: Vector3 = Vector3(bx, by, WIRE_Z)
			m.begin_part()
			m.quad(c + Vector3(0.0, -0.03, 0.0), c + Vector3(0.011, 0.0, 0.0), c + Vector3(0.0, 0.03, 0.0), c + Vector3(-0.011, 0.0, 0.0), Vector3.FORWARD)
			m.quad(c + Vector3(0.0, -0.03, 0.0), c + Vector3(-0.011, 0.0, 0.0), c + Vector3(0.0, 0.03, 0.0), c + Vector3(0.011, 0.0, 0.0), Vector3.BACK)
