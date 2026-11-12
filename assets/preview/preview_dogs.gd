extends Node3D
## Preview: the three dog breeds in different poses. --yaw=<deg> optional.

@export var yaw: int = 75


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--yaw="):
			yaw = int(a.trim_prefix("--yaw="))
	add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.64, 0.36, 0.24)
	ground.material_override = gm
	add_child(ground)
	var scn: PackedScene = load("res://assets/models/dog/dog_visual.tscn")
	var defs: Array = [
		[&"caramelo", "idle"], [&"caramelo", "bark"], [&"foxhound", "walk"], [&"foxhound", "point"], [&"dogo", "idle"], [&"dogo", "bite"], [&"caramelo", "retreat"],
	]
	var x: float = -(defs.size() - 1) * 0.5
	for d in defs:
		var dog: DogVisualBase = scn.instantiate()
		add_child(dog)
		dog.setup(d[0])
		dog.position = Vector3(x, 0, 0)
		dog.rotation.y = deg_to_rad(float(yaw))
		x += 1.0
		match d[1]:
			"bark": dog.play_bark()
			"walk": dog.set_locomotion(1.5)
			"point": dog.play_point()
			"bite": dog.play_bite(true)
			"retreat": dog.set_retreating(true)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 0.9, 4.3)
	cam.look_at(Vector3(0, 0.35, 0))
	cam.fov = 42.0
