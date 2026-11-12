extends Node3D
## Preview: boars of the 4 types side by side, each in a different pose.

@export var mode: String = "types"
@export var yaw: int = 40


func _ready() -> void:
	var env_root: Node = load("res://assets/env/mato_grosso_env.tscn").instantiate() if ResourceLoader.exists("res://assets/env/mato_grosso_env.tscn") else MapEnvironmentBase.create_fallback()
	add_child(env_root)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.64, 0.36, 0.24)
	ground.material_override = gm
	add_child(ground)
	var scn: PackedScene = load("res://assets/models/boar/boar_visual.tscn")
	var defs: Array = [
		[Ids.PIGLET, 30.0, "idle"], [Ids.SOW, 85.0, "walk"], [Ids.BOAR, 130.0, "scrape"], [Ids.ALPHA, 240.0, "charge"],
	]
	if mode == "weights":
		defs = [[Ids.PIGLET, 25.0, "idle"], [Ids.BOAR, 100.0, "idle"], [Ids.ALPHA, 260.0, "idle"]]
	if mode == "poses":
		defs = [[Ids.BOAR, 120.0, "eat"], [Ids.BOAR, 120.0, "alert"], [Ids.BOAR, 120.0, "attack"], [Ids.BOAR, 120.0, "dead"], [Ids.ALPHA, 220.0, "highlight"]]
	var x: float = -(defs.size() - 1) * 1.1
	for d in defs:
		var b: BoarVisualBase = scn.instantiate()
		add_child(b)
		b.setup(d[0], d[1])
		b.scale = Vector3.ONE * BoarVisualBase.scale_for_weight(d[1])
		b.position = Vector3(x, 0, 0)
		b.rotation.y = deg_to_rad(float(yaw))
		x += 2.2
		match d[2]:
			"walk": b.set_locomotion(1.4)
			"scrape": b.play_scrape()
			"charge":
				b.play_scrape()
				b.set_locomotion(10.0)
			"eat": b.set_eating(true)
			"alert": b.play_alert()
			"attack": b.play_attack()
			"dead": b.play_death()
			"highlight": b.set_highlight(true)
		if mode == "weights":
			var zones: Array = BoarVisualBase.HIT_ZONES.values()
			for z in zones:
				var box: MeshInstance3D = MeshInstance3D.new()
				var bm: BoxMesh = BoxMesh.new()
				var sc: float = b.scale.x
				bm.size = z[1] * sc
				box.mesh = bm
				var m: StandardMaterial3D = StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 1, 0.3, 0.25)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				box.material_override = m
				box.position = b.position + z[0] * sc
				add_child(box)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	var span: float = defs.size() * 1.2
	cam.position = Vector3(0.0, 1.3, 2.2 + span * 0.62)
	cam.look_at(Vector3(0, 0.45, 0))
	cam.fov = 42.0
