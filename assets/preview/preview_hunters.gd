extends Node3D
## Preview: hunters in several poses. --yaw=<deg> (180 = facing the camera), --row=<0|1> picks the pose row,
## --cam=<distance>.

@export var yaw: int = 150
@export var row: int = 0
@export var cam_dist: float = 7.5

var _hunters: Array[HunterVisualBase] = []
var _t: float = 0.0
var _next_fire: float = 0.5
var rapid: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--yaw="):
			yaw = int(a.trim_prefix("--yaw="))
		elif a.begins_with("--row="):
			row = int(a.trim_prefix("--row="))
		elif a == "--rapid":
			rapid = true
		elif a.begins_with("--cam="):
			cam_dist = float(a.trim_prefix("--cam="))
	add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.64, 0.36, 0.24)
	ground.material_override = gm
	add_child(ground)
	var scn: PackedScene = load("res://assets/models/hunter/hunter_visual.tscn")
	var rows: Array = [
		[
			[0, &"rifle_308", "idle"], [1, &"shotgun_12", "walk"], [2, &"carbine_22", "run"], [3, &"rifle_338", "aim_up"],
			[0, &"rifle_3006", "crouch_aim"], [1, &"rifle_308", "reload"], [2, &"shotgun_12", "aim_down"], [3, &"rifle_3006", "dead"], [0, &"carbine_22", "dead_now"],
		],
		[
			[0, &"", "idle"], [1, &"", "walk"], [2, &"rifle_338", "idle"], [3, &"carbine_22", "crouch"],
			[0, &"rifle_338", "aim_fire"], [1, &"shotgun_12", "aim"], [2, &"rifle_3006", "walk"], [3, &"rifle_308", "hit"],
		],
	]
	var defs: Array = rows[clampi(row, 0, rows.size() - 1)]
	var x: float = -(defs.size() - 1) * 0.5 * 1.15
	for d in defs:
		var h: HunterVisualBase = scn.instantiate()
		h.setup(d[0], d[1])
		add_child(h)
		h.position = Vector3(x, 0, 0)
		h.rotation.y = deg_to_rad(float(yaw))
		x += 1.15
		_hunters.append(h)
		match d[2]:
			"walk": h.set_locomotion(4.0)
			"run": h.set_locomotion(6.5)
			"aim_up":
				h.set_aiming(true)
				h.set_look_pitch(0.5)
			"aim_down":
				h.set_aiming(true)
				h.set_look_pitch(-0.45)
			"aim":
				h.set_aiming(true)
			"aim_fire":
				h.set_aiming(true)
			"crouch": h.set_crouching(true)
			"crouch_aim":
				h.set_crouching(true)
				h.set_aiming(true)
			"reload": h.play_reload(100.0)
			"dead": h.play_death()
			"dead_now": h.play_death(true)
			"hit": h.play_hit()
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.5, cam_dist)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.fov = 42.0


func _process(delta: float) -> void:
	_t += delta
	if _t > _next_fire:
		_next_fire += 0.03 if rapid else 1.5
		if row == 1:
			_hunters[4].play_fire()
