class_name MapRoot
extends Node3D
## Root of every map scene (docs/arquitetura.md section 8.5). Reads its marker children and builds the
## heightmap, terrain, water, props, flora and the steering obstacle grid. The HuntController calls the
## build_* steps one per frame.

## Hard budget of static collision shapes (terrain + walls + props + trunks).
const STATIC_SHAPE_BUDGET: int = 200
const TERRAIN_SHAPES: int = 5
const CROP_FLATTEN_BLEND_M: float = 8.0
const BUILDING_FLATTEN_BLEND_M: float = 6.0
const BUILDING_FLATTEN_EXTRA_M: float = 4.0
const BUILDING_MIN_FOOTPRINT_M: float = 1.5
const POND_BLEND_M: float = 6.0
const WATER_SURFACE_BELOW_RIM_M: float = 0.3
const WATER_OBSTACLE_MARGIN_M: float = 0.5
const FLORA_CROP_MARGIN_M: float = 3.0
const FLORA_WATER_MARGIN_M: float = 2.0
const FLORA_PROP_MARGIN_M: float = 2.0
const FLORA_FARM_MARGIN_M: float = 3.0
const FLORA_EDGE_MARGIN_M: float = 6.0
const FLORA_PLACE_TRIES: int = 10
const COLLIDER_PRIORITY_Z: float = -20.0
## Flora whose count scales with the quality density. Trees keep their count on every quality
## so that gameplay (cover, trunks) does not change between devices.
const DENSITY_SCALED_IDS: Array[StringName] = [&"grass_tuft", &"shrub"]
const FALLBACK_PROP_COLORS: Dictionary = {
	&"farmhouse": Color(0.92, 0.9, 0.84), &"barn": Color(0.55, 0.38, 0.25), &"water_tank": Color(0.6, 0.62, 0.65),
	&"fence_segment": Color(0.45, 0.33, 0.22), &"gate": Color(0.5, 0.36, 0.22), &"feed_trough": Color(0.5, 0.4, 0.3),
}
const FALLBACK_PROP_COLOR: Color = Color(0.6, 0.6, 0.6)
const FENCE_IDS: Array[StringName] = [&"fence_segment", &"gate"]

@export var map_size_m: float = 256.0
@export var grid_resolution: int = 129
@export var terrain_seed: int = 1
@export var height_amplitude_m: float = 6.0
@export var base_flora: Dictionary = {}
## Dirt road polyline in XZ (terrain mask only; flora keeps off it).
@export var road_points: PackedVector2Array = PackedVector2Array()
@export var road_width_m: float = 4.0

var heightmap: Heightmap
var obstacles: ObstacleGrid = ObstacleGrid.new()
var terrain: Terrain
var flora: FloraScatter

var _shapes_used: int = 0
var _water_rim: Dictionary = {}   # WaterBody -> rim level
var _farm_rect: Rect2 = Rect2()
var _has_farm_rect: bool = false
var _prop_circles: Array[Vector3] = []   # x, z, radius (flora exclusion)
var _block_crop_rects: Array[Rect2] = []
var _block_water: Array[Vector3] = []     # x, z, radius


func get_map_rect() -> Rect2:
	return Rect2(-map_size_m * 0.5, -map_size_m * 0.5, map_size_m, map_size_m)


func get_player_spawn() -> Marker3D:
	return get_node_or_null(^"PlayerSpawn") as Marker3D


func get_crop_fields() -> Array[CropField]:
	var out: Array[CropField] = []
	var holder: Node = get_node_or_null(^"CropFields")
	if holder != null:
		for c: Node in holder.get_children():
			if c is CropField:
				out.append(c as CropField)
	return out


func get_water_bodies() -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	var holder: Node = get_node_or_null(^"Water")
	if holder != null:
		for c: Node in holder.get_children():
			if c is WaterBody:
				out.append(c as WaterBody)
	return out


func get_spawn_zones() -> PackedVector2Array:
	return _marker_xz(^"SpawnZones")


func get_retreat_zones() -> PackedVector2Array:
	return _marker_xz(^"RetreatZones")


func get_static_shapes_used() -> int:
	return _shapes_used


# --- Build steps ---------------------------------------------------------------------------------

func build_heightmap() -> void:
	heightmap = Heightmap.new(map_size_m, grid_resolution, terrain_seed, height_amplitude_m)
	for f: CropField in get_crop_fields():
		heightmap.flatten_rect(f.get_rect(), CROP_FLATTEN_BLEND_M)
	var holder: Node = get_node_or_null(^"PropSpawns")
	if holder != null:
		for c: Node in holder.get_children():
			var p: PropSpawn = c as PropSpawn
			if p != null and p.footprint_radius_m >= BUILDING_MIN_FOOTPRINT_M:
				heightmap.flatten_circle(Vector2(p.position.x, p.position.z),
					p.footprint_radius_m + BUILDING_FLATTEN_EXTRA_M, BUILDING_FLATTEN_BLEND_M)
	for w: WaterBody in get_water_bodies():
		_water_rim[w] = heightmap.dig_bowl(Vector2(w.position.x, w.position.z), w.radius_m, w.depth_m, POND_BLEND_M)
		obstacles.add_circle(w.position.x, w.position.z, w.radius_m + WATER_OBSTACLE_MARGIN_M)


func build_terrain() -> void:
	var rects: Array[Rect2] = []
	for f: CropField in get_crop_fields():
		rects.append(f.get_rect())
	var centers: PackedVector2Array = PackedVector2Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for w: WaterBody in get_water_bodies():
		centers.append(Vector2(w.position.x, w.position.z))
		radii.append(w.radius_m)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var mat: Material = AssetLoader.load_resource(ScenePaths.TERRAIN_MATERIAL) as Material
	terrain.build(heightmap, rects, road_points, road_width_m, centers, radii, mat)
	_shapes_used = TERRAIN_SHAPES


func build_props_and_water() -> void:
	_build_water_meshes()
	var holder: Node = get_node_or_null(^"PropSpawns")
	if holder == null:
		return
	for c: Node in holder.get_children():
		var p: PropSpawn = c as PropSpawn
		if p == null:
			continue
		var gx: float = p.global_position.x
		var gz: float = p.global_position.z
		p.global_position = Vector3(gx, heightmap.get_height(gx, gz), gz)
		var visual: Node = AssetLoader.instantiate(ScenePaths.prop(p.prop_id))
		if visual == null or not visual is Node3D:
			if visual != null:
				visual.queue_free()
			var size: Vector3 = p.collision_size if p.collision_size != Vector3.ZERO else Vector3.ONE
			visual = FallbackMeshes.box(size, FALLBACK_PROP_COLORS.get(p.prop_id, FALLBACK_PROP_COLOR) as Color)
		visual.name = "Visual"
		p.add_child(visual)
		if p.collision_size != Vector3.ZERO and _shapes_used < STATIC_SHAPE_BUDGET:
			var body: StaticBody3D = StaticBody3D.new()
			body.name = "Body"
			body.collision_layer = Layers.STATIC
			body.collision_mask = 0
			var cs: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			box.size = p.collision_size
			cs.shape = box
			cs.position = Vector3(0.0, p.collision_size.y * 0.5, 0.0)
			body.add_child(cs)
			p.add_child(body)
			_shapes_used += 1
		if p.footprint_radius_m > 0.0:
			obstacles.add_circle(gx, gz, p.footprint_radius_m)
			_prop_circles.append(Vector3(gx, gz, p.footprint_radius_m))
		if FENCE_IDS.has(p.prop_id):
			var pt: Rect2 = Rect2(Vector2(gx, gz), Vector2.ZERO)
			_farm_rect = _farm_rect.merge(pt) if _has_farm_rect else pt
			_has_farm_rect = true


func build_flora(density: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = terrain_seed * 7919 + 13
	var placements: Dictionary = {}
	_block_crop_rects.clear()
	for f: CropField in get_crop_fields():
		_block_crop_rects.append(f.get_rect().grow(FLORA_CROP_MARGIN_M))
	_block_water.clear()
	for w: WaterBody in get_water_bodies():
		_block_water.append(Vector3(w.position.x, w.position.z, w.radius_m + FLORA_WATER_MARGIN_M))
	var rect: Rect2 = get_map_rect().grow(-FLORA_EDGE_MARGIN_M)
	for key: Variant in base_flora.keys():
		var id: StringName = StringName(String(key))
		var n: int = _scaled_count(id, int(base_flora[key]), density)
		var list: PackedVector2Array = _list(placements, id)
		for i: int in n:
			for t: int in FLORA_PLACE_TRIES:
				var p: Vector2 = Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
				if not _flora_blocked(p):
					list.append(p)
					break
		placements[id] = list
	var zones_holder: Node = get_node_or_null(^"FloraZones")
	if zones_holder != null:
		for c: Node in zones_holder.get_children():
			var z: FloraZone = c as FloraZone
			if z == null:
				continue
			for key: Variant in z.counts.keys():
				var id: StringName = StringName(String(key))
				var n: int = _scaled_count(id, int(z.counts[key]), density)
				var list: PackedVector2Array = _list(placements, id)
				for i: int in n:
					for t: int in FLORA_PLACE_TRIES:
						var ang: float = rng.randf_range(0.0, TAU)
						var rad: float = sqrt(rng.randf()) * z.radius_m
						var p: Vector2 = Vector2(z.position.x + cos(ang) * rad, z.position.z + sin(ang) * rad)
						if rect.has_point(p) and not _flora_blocked(p):
							list.append(p)
							break
				placements[id] = list
	flora = FloraScatter.new()
	flora.name = "Flora"
	add_child(flora)
	var budget: int = maxi(STATIC_SHAPE_BUDGET - _shapes_used, 0)
	_shapes_used += flora.build(placements, heightmap, rng, obstacles, budget, COLLIDER_PRIORITY_Z)


# --- Internals -----------------------------------------------------------------------------------

func _marker_xz(path: NodePath) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var holder: Node = get_node_or_null(path)
	if holder != null:
		for c: Node in holder.get_children():
			if c is Node3D:
				out.append(Vector2((c as Node3D).global_position.x, (c as Node3D).global_position.z))
	return out


func _scaled_count(id: StringName, count: int, density: float) -> int:
	if DENSITY_SCALED_IDS.has(id):
		return int(round(float(count) * density))
	return count


func _list(placements: Dictionary, id: StringName) -> PackedVector2Array:
	if placements.has(id):
		return placements[id] as PackedVector2Array
	return PackedVector2Array()


func _flora_blocked(p: Vector2) -> bool:
	for r: Rect2 in _block_crop_rects:
		if r.has_point(p):
			return true
	for w: Vector3 in _block_water:
		if p.distance_to(Vector2(w.x, w.y)) < w.z:
			return true
	if _has_farm_rect and _farm_rect.grow(FLORA_FARM_MARGIN_M).has_point(p):
		return true
	for c: Vector3 in _prop_circles:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + FLORA_PROP_MARGIN_M:
			return true
	for k: int in range(road_points.size() - 1):
		var a: Vector2 = road_points[k]
		var ab: Vector2 = road_points[k + 1] - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < road_width_m * 0.5 + 1.0:
			return true
	return false


func _build_water_meshes() -> void:
	var water_mat: Material = AssetLoader.load_resource(ScenePaths.WATER_MATERIAL) as Material
	if water_mat == null:
		var sm: StandardMaterial3D = StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.42, 0.55, 0.75)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.roughness = 0.2
		water_mat = sm
	for w: WaterBody in get_water_bodies():
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = w.radius_m
		disc.bottom_radius = w.radius_m
		disc.height = 0.02
		disc.radial_segments = 40
		disc.rings = 1
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Surface"
		mi.mesh = disc
		mi.material_override = water_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(mi)
		var rim: float = float(_water_rim.get(w, 0.0))
		w.global_position = Vector3(w.global_position.x, rim - WATER_SURFACE_BELOW_RIM_M, w.global_position.z)
