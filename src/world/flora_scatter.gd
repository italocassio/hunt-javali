class_name FloraScatter
extends Node3D
## Scatters flora as MultiMeshes (one per id per block) and creates trunk colliders (layer "static")
## plus steering obstacles for trees. Meshes come from the art library; FallbackMeshes otherwise.

## Block edge per id. Small blocks for short-range flora so visibility_range culls evenly.
const BLOCK_DEFAULT_M: float = 128.0
const BLOCK_SHORT_RANGE_M: float = 32.0
const SHORT_RANGE_IDS: Array[StringName] = [&"grass_tuft", &"shrub"]
const VISIBILITY_END_M: Dictionary = {&"grass_tuft": 60.0, &"shrub": 90.0}
const NO_SHADOW_IDS: Array[StringName] = [&"grass_tuft", &"shrub"]
## id -> [radius, height] of the trunk collider.
const COLLIDERS: Dictionary = {
	&"cerrado_tree": [0.2, 3.0],
	&"ipe": [0.3, 4.0],
	&"buriti": [0.25, 6.0],
	&"termite_mound": [0.6, 1.2],
}
const OBSTACLE_MARGIN_M: float = 0.3
const SCALE_JITTER: float = 0.2

var _lib: Script = null
var _lib_loaded: bool = false
var _warned: Dictionary = {}


## placements: StringName id -> PackedVector2Array of XZ positions.
## Returns the number of collision shapes created (<= shape_budget).
func build(placements: Dictionary, hm: Heightmap, rng: RandomNumberGenerator, obstacles: ObstacleGrid,
		shape_budget: int, priority_z: float) -> int:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TrunkBody"
	body.collision_layer = Layers.STATIC
	body.collision_mask = 0
	add_child(body)

	var candidates: Array = []   # [priority, id, x, z]
	for id: StringName in placements.keys():
		var positions: PackedVector2Array = placements[id] as PackedVector2Array
		_add_multimeshes(id, positions, hm, rng)
		if COLLIDERS.has(id):
			var info: Array = COLLIDERS[id] as Array
			for p: Vector2 in positions:
				obstacles.add_circle(p.x, p.y, float(info[0]) + OBSTACLE_MARGIN_M)
				candidates.append([absf(p.y - priority_z), id, p.x, p.y])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var used: int = 0
	for c: Array in candidates:
		if used >= shape_budget:
			break
		var info: Array = COLLIDERS[c[1]] as Array
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = float(info[0])
		cyl.height = float(info[1])
		cs.shape = cyl
		var x: float = float(c[2])
		var z: float = float(c[3])
		cs.position = Vector3(x, hm.get_height(x, z) + float(info[1]) * 0.5, z)
		body.add_child(cs)
		used += 1
	return used


func get_mesh(id: StringName) -> Mesh:
	if not _lib_loaded:
		_lib_loaded = true
		_lib = AssetLoader.load_resource(ScenePaths.FLORA_LIBRARY) as Script
	var mesh: Mesh = null
	if _lib != null:
		mesh = _lib.call(&"build_mesh", id) as Mesh
	if mesh == null:
		if _lib != null and not _warned.has(id):
			_warned[id] = true
			push_warning("FloraScatter: flora library has no mesh for '%s', using fallback." % id)
		mesh = FallbackMeshes.build(id)
	return mesh


func _add_multimeshes(id: StringName, positions: PackedVector2Array, hm: Heightmap, rng: RandomNumberGenerator) -> void:
	if positions.is_empty():
		return
	var mesh: Mesh = get_mesh(id)
	if mesh == null:
		push_warning("FloraScatter: unknown flora id '%s'" % id)
		return
	var block_m: float = BLOCK_SHORT_RANGE_M if SHORT_RANGE_IDS.has(id) else BLOCK_DEFAULT_M
	var blocks: Dictionary = {}   # Vector2i -> Array[Transform3D]
	for p: Vector2 in positions:
		var key: Vector2i = Vector2i(int(floor((p.x + hm.half) / block_m)), int(floor((p.y + hm.half) / block_m)))
		if not blocks.has(key):
			blocks[key] = []
		var s: float = 1.0 + rng.randf_range(-SCALE_JITTER, SCALE_JITTER)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
		(blocks[key] as Array).append(Transform3D(basis, Vector3(p.x, hm.get_height(p.x, p.y), p.y)))
	for key: Vector2i in blocks.keys():
		var list: Array = blocks[key] as Array
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k: int in list.size():
			mm.set_instance_transform(k, list[k] as Transform3D)
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [id, key.x, key.y]
		mmi.multimesh = mm
		if NO_SHADOW_IDS.has(id):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if VISIBILITY_END_M.has(id):
			mmi.visibility_range_end = float(VISIBILITY_END_M[id])
		add_child(mmi)
