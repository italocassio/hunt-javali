extends Node3D
## Procedural farm props. One script, one merged MeshInstance3D per prop (vertex colors, shared material).
## Each <prop_id>.tscn only sets `prop_id`. Origin on the ground at the footprint center, front = -Z.

const WHITE: Color = Color(0.93, 0.90, 0.83)
const WHITE_SHADE: Color = Color(0.80, 0.76, 0.68)
const TILE: Color = Color(0.66, 0.29, 0.17)
const TILE_DARK: Color = Color(0.52, 0.22, 0.13)
const WOOD: Color = Color(0.47, 0.31, 0.18)
const WOOD_DARK: Color = Color(0.33, 0.21, 0.12)
const BARN_RED: Color = Color(0.55, 0.24, 0.17)
const ZINC: Color = Color(0.68, 0.70, 0.72)
const ZINC_DARK: Color = Color(0.5, 0.52, 0.55)
const GLASS: Color = Color(0.35, 0.50, 0.58)
const HAY: Color = Color(0.86, 0.74, 0.36)
const CORN: Color = Color(0.93, 0.76, 0.22)
const WIRE: Color = Color(0.78, 0.78, 0.8)
const TANK: Color = Color(0.55, 0.65, 0.72)

static var _cache: Dictionary = {}

@export var prop_id: StringName = &""


func _ready() -> void:
	if get_child_count() > 0 or prop_id == &"":
		return
	var key: String = String(prop_id)
	if not _cache.has(key):
		_cache[key] = _build(prop_id)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _cache[key]
	add_child(mi)


static func _build(id: StringName) -> ArrayMesh:
	var k: MeshKit = MeshKit.new()
	match id:
		&"farmhouse": _farmhouse(k)
		&"barn": _barn(k)
		&"water_tank": _water_tank(k)
		&"fence_segment": _fence(k)
		&"gate": _gate(k)
		&"corn_bait": _corn_bait(k)
		&"feed_trough": _trough(k)
	return k.build()


static func _bx(k: MeshKit, x: float, y0: float, z: float, w: float, h: float, d: float, c: Color, ct: Color = Color(0, 0, 0, 0)) -> void:
	k.box(Vector3(x, y0 + h * 0.5, z), Vector3(w, h, d), c, ct)


static func _farmhouse(k: MeshKit) -> void:
	_bx(k, 0, 0, 0.7, 11.6, 3.2, 6.6, WHITE, WHITE_SHADE)
	k.prism(Vector3(0, 3.0, 0.0), Vector2(12.4, 8.2), Vector2(12.4, 0.0), 3.0, TILE_DARK, TILE)
	_bx(k, 0, 0, -3.2, 12.0, 0.3, 1.8, WHITE_SHADE)                 # porch floor
	for x: float in [-5.7, -1.9, 1.9, 5.7]:
		_bx(k, x, 0.3, -3.8, 0.25, 2.7, 0.25, WHITE)               # porch posts
	_bx(k, 0, 1.2, -2.65, 1.3, 2.0, 0.12, WOOD_DARK)                # door
	for x: float in [-4.2, -2.4, 2.4, 4.2]:
		_bx(k, x, 1.1, -2.65, 1.1, 1.1, 0.1, GLASS)                 # windows
	_bx(k, 3.8, 4.4, 1.5, 0.8, 1.6, 0.8, TILE_DARK)                 # chimney


static func _barn(k: MeshKit) -> void:
	_bx(k, 0, 0, 4.85, 16.0, 5.0, 0.3, BARN_RED, BARN_RED)          # back wall
	_bx(k, -7.85, 0, 0.0, 0.3, 5.0, 10.0, BARN_RED, BARN_RED)       # side walls
	_bx(k, 7.85, 0, 0.0, 0.3, 5.0, 10.0, BARN_RED, BARN_RED)
	k.prism(Vector3(0, 5.0, 0.0), Vector2(16.8, 10.8), Vector2(16.8, 0.0), 2.0, ZINC_DARK, ZINC)
	k.prism(Vector3(0, 5.0, -4.85), Vector2(15.8, 0.25), Vector2(0.0, 0.25), 1.95, BARN_RED, BARN_RED)   # front gable
	for x: float in [-7.8, 7.8]:
		_bx(k, x, 0, -4.85, 0.4, 5.0, 0.4, WOOD)                    # front posts
	_bx(k, 0, 4.7, -4.85, 16.0, 0.4, 0.4, WOOD)                     # front beam
	for p: Array in [[-5.0, 3.0], [-3.8, 3.4], [-4.4, 3.0], [4.0, 2.0]]:
		_bx(k, p[0], 0, p[1], 1.1, 0.55, 0.7, HAY)                  # hay bales
	_bx(k, -4.4, 0.55, 3.2, 1.1, 0.55, 0.7, HAY)


static func _water_tank(k: MeshKit) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.prism(Vector3(sx * 1.25, 0, sz * 1.25), Vector2(0.28, 0.28), Vector2(0.28, 0.28), 5.0, WOOD_DARK, WOOD, Vector2(-sx * 0.4, -sz * 0.4))
	_bx(k, 0, 2.5, 0, 2.4, 0.14, 0.14, WOOD)                         # braces
	_bx(k, 0, 2.5, 0, 0.14, 0.14, 2.4, WOOD)
	_bx(k, 0, 4.95, 0, 2.9, 0.18, 2.9, WOOD_DARK)                    # platform
	k.frustum(Vector3(0, 5.1, 0), 1.45, 1.45, 2.3, 8, TANK, MeshKit.shade(TANK, 1.12), false, false)
	k.frustum(Vector3(0, 7.4, 0), 1.5, 0.0, 0.6, 8, ZINC_DARK, ZINC, true, false)


static func _fence(k: MeshKit) -> void:
	for x: float in [-1.9, 1.9]:
		_bx(k, x, 0, 0, 0.14, 1.3, 0.14, WOOD)
	for y: float in [0.35, 0.65, 0.95, 1.22]:
		_bx(k, 0, y, 0, 3.8, 0.025, 0.025, WIRE)


static func _gate(k: MeshKit) -> void:
	for x: float in [-1.95, 1.95]:
		_bx(k, x, 0, 0, 0.2, 1.4, 0.2, WOOD_DARK)
	for y: float in [0.25, 0.6, 0.95, 1.3]:
		_bx(k, 0, y, 0, 3.7, 0.12, 0.06, WOOD)
	k.set_xf(Vector3(0, 0.78, 0), Vector3(0, 0, 17.0))
	k.box(Vector3.ZERO, Vector3(3.85, 0.1, 0.06), WOOD)
	k.reset_xf()


static func _corn_bait(k: MeshKit) -> void:
	# Mound sits on the ground (y >= 0), about 0.3 m tall: flattened ellipsoid with the lower half moved up
	# by building a short frustum body plus a cap.
	k.frustum(Vector3(0, 0.0, 0), 0.5, 0.3, 0.16, 7, Color(0.80, 0.62, 0.15), CORN, true, false)
	k.frustum(Vector3(0, 0.16, 0), 0.3, 0.0, 0.14, 7, CORN, Color(0.96, 0.82, 0.3), false, false)
	for a: float in [0.0, 1.6, 3.2, 4.8]:
		var p: Vector3 = Vector3(cos(a) * 0.36, 0.1, sin(a) * 0.36)
		k.set_xf(p, Vector3(0, rad_to_deg(-a), 40.0))
		k.box(Vector3.ZERO, Vector3(0.2, 0.06, 0.06), Color(0.96, 0.82, 0.3))
		k.reset_xf()


static func _trough(k: MeshKit) -> void:
	k.prism(Vector3(0, 0.25, 0), Vector2(2.8, 0.6), Vector2(3.0, 0.8), 0.35, WOOD_DARK, CORN)
	for x: float in [-1.2, 1.2]:
		_bx(k, x, 0, 0, 0.15, 0.25, 0.7, WOOD)
