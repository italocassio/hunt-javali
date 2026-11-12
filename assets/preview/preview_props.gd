extends Node3D
## Preview: all farm props in a row plus the impact effects firing.


func _ready() -> void:
	add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.36, 0.22)
	ground.material_override = gm
	add_child(ground)
	var spots: Dictionary = {
		&"farmhouse": Vector3(-14, 0, -8), &"barn": Vector3(6, 0, -8), &"water_tank": Vector3(-24, 0, -6),
		&"fence_segment": Vector3(-6, 0, 4), &"gate": Vector3(-1, 0, 4), &"corn_bait": Vector3(3, 0, 4), &"feed_trough": Vector3(7, 0, 4),
	}
	var tris: int = 0
	for id: StringName in spots:
		var p: Node3D = (load("res://assets/models/props/%s.tscn" % id) as PackedScene).instantiate()
		add_child(p)
		p.position = spots[id]
		tris += MeshKit.count_triangles(p)
		var aabb: AABB = (p.get_child(0) as MeshInstance3D).get_aabb() if p.get_child_count() > 0 else AABB()
		print("PROP %s size=%s tris=%d" % [id, aabb.size, MeshKit.count_triangles(p)])
	var fx_x: float = 10.0
	for id: String in ["impact_dust", "impact_blood", "impact_wood"]:
		var fx: CPUParticles3D = (load("res://assets/vfx/%s.tscn" % id) as PackedScene).instantiate()
		add_child(fx)
		fx.position = Vector3(fx_x, 0.5, 4.0)
		fx.emitting = true
		fx_x += 1.2
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-4, 7, 22)
	if OS.get_cmdline_user_args().has("--front"):
		cam.position = Vector3(-4, 6, -26)
	cam.look_at(Vector3(-4, 2.5, -2))
	cam.fov = 60.0
