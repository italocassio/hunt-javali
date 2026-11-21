class_name CornStockVisualBase
extends Node3D
## Visual-only corn stock of the barn in the horde mode (docs/horda.md section 11). Origin on the ground at the
## barn prop's origin, forward -Z, scale 1 (same frame as the barn prop). Gameplay owns the root transform; the
## asset animates children only. The base implementation drives the fallback heaps; the asset overrides all three.
## Stages: 0 empty, 1 (0-25%], 2 (25-50%], 3 (50-75%], 4 (75-100%].

const STAGE_COUNT: int = 5
const FALLBACK_HEAPS: int = 6
const FALLBACK_COLOR: Color = Color(0.91, 0.73, 0.14)
const FALLBACK_HEAP_RADIUS_M: float = 1.2
const FALLBACK_HEAP_HEIGHT_M: float = 1.0
const MIN_HEAP_SCALE: float = 0.01

static var _fallback_material: StandardMaterial3D = null

var _fallback_heaps: Array[MeshInstance3D] = []


static func stage_for(pct: float) -> int:
	if pct <= 0.0:
		return 0
	return clampi(ceili(pct / 25.0), 1, STAGE_COUNT - 1)


## Called exactly once, before add_child. ring_radius_m = where the boars eat (data/horde.json "eat_ring_m").
func setup(ring_radius_m: float) -> void:
	var n: int = _fallback_heaps.size()
	for i: int in n:
		var ang: float = TAU * float(i) / float(n)
		var heap: MeshInstance3D = _fallback_heaps[i]
		heap.position = Vector3(sin(ang) * ring_radius_m, heap.position.y, -cos(ang) * ring_radius_m)


## Barn stock 0..100 (the hunt's crop health in the horde). Called after add_child and on every change.
func set_stock_pct(pct: float) -> void:
	var k: float = float(stage_for(pct)) / float(STAGE_COUNT - 1)
	var s: float = maxf(k, MIN_HEAP_SCALE)
	for heap: MeshInstance3D in _fallback_heaps:
		heap.visible = k > 0.0
		heap.scale = Vector3(1.0, s, 1.0)
		heap.position.y = FALLBACK_HEAP_HEIGHT_M * 0.5 * s


## Boars eating the stock right now (crop_under_attack). Cosmetic; may be a no-op.
func set_under_attack(_on: bool) -> void:
	pass


## Ground footprint of every heap on the eating ring at full stock, in this node's frame: (x, z, radius) per heap.
## Gameplay keeps the boars' bodies out of these circles (they eat from the edge). Valid after setup.
func get_heap_circles() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for heap: MeshInstance3D in _fallback_heaps:
		out.append(Vector3(heap.position.x, heap.position.z, FALLBACK_HEAP_RADIUS_M))
	return out


static func create_fallback() -> CornStockVisualBase:
	var v: CornStockVisualBase = CornStockVisualBase.new()
	v.name = "CornStockFallback"
	if _fallback_material == null:
		_fallback_material = StandardMaterial3D.new()
		_fallback_material.albedo_color = FALLBACK_COLOR
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = FALLBACK_HEAP_RADIUS_M
	mesh.height = FALLBACK_HEAP_HEIGHT_M
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = _fallback_material
	for i: int in FALLBACK_HEAPS:
		var heap: MeshInstance3D = MeshInstance3D.new()
		heap.name = "Heap_%d" % i
		heap.mesh = mesh
		heap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		heap.position.y = FALLBACK_HEAP_HEIGHT_M * 0.5
		v.add_child(heap)
		v._fallback_heaps.append(heap)
	return v
