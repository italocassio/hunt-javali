extends Node3D
## Preview: the pond seen at a grazing angle (regression check for the white-line bug).


func _ready() -> void:
	add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.64, 0.36, 0.24)
	ground.material_override = gm
	add_child(ground)
	var water: MeshInstance3D = MeshInstance3D.new()
	var wm: PlaneMesh = PlaneMesh.new()
	wm.size = Vector2(30, 30)
	water.mesh = wm
	water.material_override = load("res://assets/materials/water.tres")
	water.position = Vector3(0, 0.02, -20)
	add_child(water)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.7, 0)
	cam.look_at(Vector3(0, 1.0, -20))
	cam.fov = 70.0
