class_name FallbackMeshes
extends RefCounted
## Low-poly stand-ins for flora and crops, used only when the art-director library is missing.
## One surface per mesh, colors in vertex color, one shared material.

static var _material: StandardMaterial3D = null
static var _cache: Dictionary = {}


static func get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
	return _material


## Returns the fallback mesh for a flora/crop id, or null for unknown ids.
static func build(id: StringName) -> Mesh:
	if _cache.has(id):
		return _cache[id] as Mesh
	var mesh: Mesh = null
	match id:
		&"grass_tuft":
			mesh = _compose([[_cone(0.18, 0.42, 4), Vector3(0.0, 0.21, 0.0), Color(0.82, 0.72, 0.36)]])
		&"shrub":
			mesh = _compose([[_sphere(0.6, 0.45, 6), Vector3(0.0, 0.4, 0.0), Color(0.36, 0.45, 0.22)]])
		&"cerrado_tree":
			mesh = _compose([
				[_cyl(0.16, 0.22, 2.4, 5), Vector3(0.0, 1.2, 0.0), Color(0.33, 0.24, 0.16)],
				[_sphere(1.5, 1.0, 6), Vector3(0.0, 3.5, 0.0), Color(0.30, 0.45, 0.2)]])
		&"ipe":
			mesh = _compose([
				[_cyl(0.24, 0.32, 4.2, 5), Vector3(0.0, 2.1, 0.0), Color(0.36, 0.27, 0.18)],
				[_sphere(2.5, 1.4, 7), Vector3(0.0, 5.6, 0.0), Color(0.95, 0.76, 0.16)]])
		&"buriti":
			mesh = _compose([
				[_cyl(0.2, 0.28, 10.0, 5), Vector3(0.0, 5.0, 0.0), Color(0.45, 0.36, 0.25)],
				[_cone(3.0, 1.6, 7), Vector3(0.0, 10.6, 0.0), Color(0.22, 0.46, 0.2)]])
		&"termite_mound":
			mesh = _compose([[_cone(0.6, 1.2, 6), Vector3(0.0, 0.6, 0.0), Color(0.58, 0.28, 0.17)]])
		&"soy_patch":
			mesh = _compose([[_cyl(0.8, 1.2, 0.6, 6), Vector3(0.0, 0.3, 0.0), Color(0.40, 0.58, 0.2)]])
		&"soy_eaten":
			mesh = _compose([[_cyl(0.8, 1.2, 0.15, 6), Vector3(0.0, 0.075, 0.0), Color(0.38, 0.27, 0.16)]])
		&"corn_patch":
			mesh = _compose([[_cyl(0.7, 0.9, 2.0, 6), Vector3(0.0, 1.0, 0.0), Color(0.62, 0.62, 0.22)]])
		&"corn_eaten":
			mesh = _compose([[_cyl(0.7, 0.9, 0.5, 6), Vector3(0.0, 0.25, 0.0), Color(0.45, 0.36, 0.16)]])
		_:
			return null
	_cache[id] = mesh
	return mesh


static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	return mi


static func _cyl(top_r: float, bottom_r: float, height: float, segs: int) -> Mesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = segs
	m.rings = 1
	return m


static func _cone(radius: float, height: float, segs: int) -> Mesh:
	return _cyl(0.0, radius, height, segs)


static func _sphere(radius_xz: float, radius_y: float, segs: int) -> Mesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius_xz
	m.height = radius_y * 2.0
	m.radial_segments = segs
	m.rings = 3
	return m


## parts: Array of [Mesh, Vector3 offset, Color].
static func _compose(parts: Array) -> Mesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()
	for part: Array in parts:
		var src: Mesh = part[0] as Mesh
		var offset: Vector3 = part[1] as Vector3
		var color: Color = part[2] as Color
		var arrays: Array = src.get_mesh_arrays()
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var base: int = verts.size()
		for k: int in pv.size():
			verts.append(pv[k] + offset)
			norms.append(pn[k])
			cols.append(color)
		for k: int in pi.size():
			idx.append(pi[k] + base)
	var out_arrays: Array = []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = verts
	out_arrays[Mesh.ARRAY_NORMAL] = norms
	out_arrays[Mesh.ARRAY_COLOR] = cols
	out_arrays[Mesh.ARRAY_INDEX] = idx
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	am.surface_set_material(0, get_material())
	return am
