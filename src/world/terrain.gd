class_name Terrain
extends Node3D
## Terrain mesh (2x2 blocks) plus collision (HeightMapShape3D at 1 m + 4 border walls, layer "terrain").
## Vertex color mask for the art material: r = crop soil, g = exposed red dirt, b = wet margin.
## Without the art material the masks are baked into plain albedo colors (fallback).

const BLOCKS_PER_SIDE: int = 2
const WALL_THICKNESS_M: float = 2.0
const WALL_HEIGHT_M: float = 40.0
const ROAD_EDGE_M: float = 1.5
const WET_MARGIN_M: float = 4.0
const CROP_EDGE_M: float = 3.0

var heightmap: Heightmap
var _fallback_colors: bool = false

# Mask inputs
var _crop_rects: Array[Rect2] = []
var _road_points: PackedVector2Array = PackedVector2Array()
var _road_half_width: float = 2.0
var _water_centers: PackedVector2Array = PackedVector2Array()
var _water_radii: PackedFloat32Array = PackedFloat32Array()
var _noise: FastNoiseLite


func build(hm: Heightmap, crop_rects: Array[Rect2], road_points: PackedVector2Array, road_width_m: float,
		water_centers: PackedVector2Array, water_radii: PackedFloat32Array, material: Material) -> void:
	heightmap = hm
	_crop_rects = crop_rects
	_road_points = road_points
	_road_half_width = road_width_m * 0.5
	_water_centers = water_centers
	_water_radii = water_radii
	_noise = FastNoiseLite.new()
	_noise.seed = hm.terrain_seed + 7
	_noise.frequency = 0.08
	var mat: Material = material
	if mat == null:
		_fallback_colors = true
		var sm: StandardMaterial3D = StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.roughness = 1.0
		mat = sm
	_build_meshes(mat)
	_build_collision()


func _mask_at(x: float, z: float) -> Color:
	var r: float = 0.0
	for rect: Rect2 in _crop_rects:
		var dx: float = maxf(maxf(rect.position.x - x, x - rect.end.x), 0.0)
		var dz: float = maxf(maxf(rect.position.y - z, z - rect.end.y), 0.0)
		r = maxf(r, 1.0 - smoothstep(0.0, CROP_EDGE_M, sqrt(dx * dx + dz * dz)))
	var g: float = 0.0
	var p: Vector2 = Vector2(x, z)
	for k: int in range(_road_points.size() - 1):
		var a: Vector2 = _road_points[k]
		var b: Vector2 = _road_points[k + 1]
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d: float = p.distance_to(a + ab * t)
		g = maxf(g, 1.0 - smoothstep(_road_half_width, _road_half_width + ROAD_EDGE_M, d))
	var bm: float = 0.0
	for k: int in _water_centers.size():
		var d2: float = p.distance_to(_water_centers[k])
		bm = maxf(bm, 1.0 - smoothstep(_water_radii[k], _water_radii[k] + WET_MARGIN_M, d2))
	return Color(r, g, bm, 1.0)


func _albedo_from_mask(mask: Color, x: float, z: float) -> Color:
	var n: float = _noise.get_noise_2d(x, z) * 0.5 + 0.5
	var grass: Color = Color(0.74, 0.66, 0.36).lerp(Color(0.64, 0.6, 0.3), n)
	var c: Color = grass
	c = c.lerp(Color(0.33, 0.24, 0.15), mask.r)
	c = c.lerp(Color(0.62, 0.27, 0.16), mask.g)
	c = c.lerp(Color(0.36, 0.3, 0.2), mask.b)
	c.a = 1.0
	return c


func _build_meshes(mat: Material) -> void:
	var res: int = heightmap.resolution
	var quads_per_block: int = (res - 1) / BLOCKS_PER_SIDE
	for by: int in BLOCKS_PER_SIDE:
		for bx: int in BLOCKS_PER_SIDE:
			var i0: int = bx * quads_per_block
			var j0: int = by * quads_per_block
			var verts: PackedVector3Array = PackedVector3Array()
			var norms: PackedVector3Array = PackedVector3Array()
			var cols: PackedColorArray = PackedColorArray()
			var uvs: PackedVector2Array = PackedVector2Array()
			var idx: PackedInt32Array = PackedInt32Array()
			var side: int = quads_per_block + 1
			verts.resize(side * side)
			norms.resize(side * side)
			cols.resize(side * side)
			uvs.resize(side * side)
			for j: int in side:
				for i: int in side:
					var gi: int = i0 + i
					var gj: int = j0 + j
					var x: float = heightmap.grid_x(gi)
					var z: float = heightmap.grid_x(gj)
					var k: int = j * side + i
					verts[k] = Vector3(x, heightmap.get_grid(gi, gj), z)
					norms[k] = heightmap.get_normal(x, z)
					var mask: Color = _mask_at(x, z)
					cols[k] = _albedo_from_mask(mask, x, z) if _fallback_colors else mask
					uvs[k] = Vector2(x, z) / 4.0
			for j: int in quads_per_block:
				for i: int in quads_per_block:
					var a: int = j * side + i
					var b: int = a + 1
					var c: int = a + side
					var d: int = c + 1
					idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = idx
			var am: ArrayMesh = ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(0, mat)
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "Block_%d_%d" % [bx, by]
			mi.mesh = am
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


func _build_collision() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	add_child(body)
	var size: int = int(heightmap.size_m) + 1   # 257 samples at 1 m
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(size * size)
	var half: float = heightmap.half
	for j: int in size:
		var z: float = -half + float(j)
		for i: int in size:
			data[j * size + i] = heightmap.get_height(-half + float(i), z)
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = data
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# Border walls (layer terrain).
	var wall_defs: Array = [
		[Vector3(0.0, WALL_HEIGHT_M * 0.5, -half - WALL_THICKNESS_M * 0.5), Vector3(heightmap.size_m + 2.0 * WALL_THICKNESS_M, WALL_HEIGHT_M, WALL_THICKNESS_M)],
		[Vector3(0.0, WALL_HEIGHT_M * 0.5, half + WALL_THICKNESS_M * 0.5), Vector3(heightmap.size_m + 2.0 * WALL_THICKNESS_M, WALL_HEIGHT_M, WALL_THICKNESS_M)],
		[Vector3(-half - WALL_THICKNESS_M * 0.5, WALL_HEIGHT_M * 0.5, 0.0), Vector3(WALL_THICKNESS_M, WALL_HEIGHT_M, heightmap.size_m)],
		[Vector3(half + WALL_THICKNESS_M * 0.5, WALL_HEIGHT_M * 0.5, 0.0), Vector3(WALL_THICKNESS_M, WALL_HEIGHT_M, heightmap.size_m)],
	]
	for def: Array in wall_defs:
		var wall: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = def[1] as Vector3
		wall.shape = box
		wall.position = def[0] as Vector3
		body.add_child(wall)
