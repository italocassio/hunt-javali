extends RefCounted
## Shared plumbing of the small HD props (fence, gate, bait, trough, barn corn stock): turns an HDMesh into an
## ArrayMesh on the shared prop material, bakes the vertex AO and reports the stats the previews print.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const PM := preload("res://assets/models/props/prop_materials.gd")


## { mesh, triangles, vertices, materials, build_ms, emit_ms, weld_ms, ao_ms }. `t0` = Time.get_ticks_usec() when emission began.
static func finish(m: HDMesh, t0: int, ao_rays: int, ao_radius: float, ao_strength: float = 1.0, ao_floor: float = 0.5) -> Dictionary:
	var t1: int = Time.get_ticks_usec()
	var built: Dictionary = m.build()
	var t2: int = Time.get_ticks_usec()
	var tm: TriangleMesh = TriangleMesh.new()
	tm.create_from_faces(m.get_faces())
	HDMesh.bake_ao(built, tm, ao_rays, ao_radius, ao_strength, ao_floor)
	var t3: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = ArrayMesh.new()
	HDMesh.commit(built, mesh, PM.surfaces())
	var verts: int = 0
	for si: int in built["surfaces"]:
		verts += (built["surfaces"][si]["pos"] as PackedVector3Array).size()
	return {
		"mesh": mesh, "triangles": m.triangle_count(), "vertices": verts, "materials": 1,
		"build_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"emit_ms": float(t1 - t0) / 1000.0, "weld_ms": float(t2 - t1) / 1000.0, "ao_ms": float(t3 - t2) / 1000.0,
	}


static func paint(m: HDMesh, color: Color, rough: float, feature: int, grain: float = 0.0) -> void:
	m.paint(color, 0.0, rough, grain, feature)


## Square-section beam between two points (width w across, thickness t), bevel b.
static func beam(m: HDMesh, a: Vector3, b: Vector3, w: float, t: float, bevel: float = 0.0) -> void:
	var d: Vector3 = (b - a).normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(d.y) > 0.9 else Vector3.UP
	var x: Vector3 = ref.cross(d).normalized()
	var y: Vector3 = d.cross(x)
	m.xf = Transform3D(Basis(x, y, d), (a + b) * 0.5)
	m.cbox(Vector3.ZERO, Vector3(w, t, a.distance_to(b)), bevel)
	m.xf = Transform3D.IDENTITY
