extends Node3D
## Preview of the HD farmhouse. User args: --measure (print stats, quit), --studio, --map20, --map60.
## Screenshot: tools/godot.sh --path . --windowed --resolution 960x540 -s res://tools/screenshot.gd -- \
##   --scene=res://assets/preview/preview_farmhouse.tscn --out=<png> -- --studio   (args after the second --)

const PM := preload("res://assets/models/props/prop_materials.gd")
const FarmhouseHD := preload("res://assets/models/props/farmhouse_hd.gd")


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--measure"):
		_measure()
		return
	var cam: Camera3D = Camera3D.new()
	cam.fov = 70.0
	if args.has("--map20") or args.has("--map60"):
		var map: Node3D = (load("res://assets/preview/preview_map.tscn") as PackedScene).instantiate()
		map.set("with_boars", false)
		add_child(map)
		var c: Vector3 = Vector3(-30.0, map.call("_h", -30.0, -10.0), -10.0)
		var dist: float = 20.0 if args.has("--map20") else 60.0
		var off: Vector3 = Vector3(0.45, 0.0, -0.89).normalized() * dist
		var p: Vector3 = c + off
		p.y = float(map.call("_h", p.x, p.z)) + 1.7
		add_child(cam)
		cam.position = p
		cam.look_at(c + Vector3(0.0, 2.2 if dist < 30.0 else 2.6, 0.0))
		_clear_line_of_sight(map, p, c)
	else:
		add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
		var ground: MeshInstance3D = MeshInstance3D.new()
		var pm: PlaneMesh = PlaneMesh.new()
		pm.size = Vector2(160, 160)
		ground.mesh = pm
		var gm: StandardMaterial3D = StandardMaterial3D.new()
		gm.albedo_color = Color(0.55, 0.40, 0.26)
		ground.material_override = gm
		add_child(ground)
		var house: Node3D = (load("res://assets/models/props/farmhouse.tscn") as PackedScene).instantiate()
		add_child(house)
		add_child(cam)
		cam.position = Vector3(8.0, 2.4, -10.5)
		cam.look_at(Vector3(-0.5, 2.3, -1.0))
		if args.has("--back"):
			cam.position = Vector3(-9.0, 3.0, 12.0)
			cam.look_at(Vector3(0.0, 2.3, 0.0))
	cam.make_current()


## Hides map scatter (trees, shrubs) that would stand between the camera and the house.
func _clear_line_of_sight(map: Node3D, from: Vector3, to: Vector3) -> void:
	var a: Vector2 = Vector2(from.x, from.z)
	var b: Vector2 = Vector2(to.x, to.z)
	for n: Node in map.get_children():
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_aabb().size.x > 12.0 or n.get_child_count() > 0:
			continue
		var q: Vector2 = Vector2(mi.position.x, mi.position.z)
		var cp: Vector2 = Geometry2D.get_closest_point_to_segment(q, a, b)
		if q.distance_to(cp) < 5.0 and q.distance_to(b) > 8.0 and mi.mesh.get_aabb().size.y > 0.8:
			mi.visible = false


func _measure() -> void:
	var t0: int = Time.get_ticks_usec()
	PM.get_material()
	var t1: int = Time.get_ticks_usec()
	var model: Dictionary = FarmhouseHD.build()
	var t2: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = model["mesh"]
	print("FARMHOUSE tris=%d verts=%d surfaces=%d materials=%d aabb=%s pos=%s" % [model["triangles"], model["vertices"], mesh.get_surface_count(), model["materials"], mesh.get_aabb().size, mesh.get_aabb().position])
	print("FARMHOUSE shared_noise_ms=%.1f assemble_ms=%.1f (emit %.1f weld %.1f ao %.1f)" % [float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0, model["emit_ms"], model["weld_ms"], model["ao_ms"]])
	var t3: int = Time.get_ticks_usec()
	FarmhouseHD.build()
	print("FARMHOUSE warm_assemble_ms=%.1f" % (float(Time.get_ticks_usec() - t3) / 1000.0))
	get_tree().quit()
