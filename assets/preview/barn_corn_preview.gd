extends Node3D
## Preview: the barn prop five times, each with the corn stock at one stage (4 full ... 0 empty), 3 + 2 grid, with the ammo crates at the barn front.
## Screenshot: tools/godot.sh --path . --windowed --resolution 1600x900 -s res://tools/screenshot.gd -- \
##     --scene=res://assets/preview/barn_corn_preview.tscn --out=C:/abs/shot.png --frames=60
## User arg --cam=close frames the first (full) barn only.

const RING_M: float = 11.0
const SPACING_X: float = 28.0
const SPACING_Z: float = 28.0
const CRATE_OFFSETS: Array[Vector3] = [Vector3(-3.0, 0.0, -2.0), Vector3(0.0, 0.0, -2.0), Vector3(3.0, 0.0, -2.0)]   # seed: x 35|38|41 at z -90 around the barn (38, -88)
const STAGE_PCTS: Array[float] = [100.0, 60.0, 40.0, 10.0, 0.0]


func _ready() -> void:
	var env_root: Node = (load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate()
	add_child(env_root)
	for n: Node in env_root.find_children("*", "WorldEnvironment", true, false):
		var we: Environment = (n as WorldEnvironment).environment
		if we != null:
			we.fog_enabled = false   # preview only: keep the corn colors readable at distance
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.44, 0.20)
	ground.material_override = gm
	add_child(ground)
	var barn_scene: PackedScene = load("res://assets/models/props/barn.tscn")
	var corn_scene: PackedScene = load("res://assets/models/props/barn_corn.tscn")
	var crate_scene: PackedScene = load(ScenePaths.AMMO_CRATE)
	var tris: int = 0
	for i: int in STAGE_PCTS.size():
		var col: int = i % 3
		var row: int = i / 3
		var x: float = (float(col) - 1.0) * SPACING_X if row == 0 else (float(col) - 0.5) * SPACING_X
		var pos: Vector3 = Vector3(x, 0.0, float(row) * SPACING_Z)
		var barn: Node3D = barn_scene.instantiate()
		add_child(barn)
		barn.position = pos
		var corn: CornStockVisualBase = corn_scene.instantiate() as CornStockVisualBase
		corn.setup(RING_M)
		add_child(corn)
		corn.position = pos
		corn.set_stock_pct(STAGE_PCTS[i])
		if i == 1:
			corn.set_under_attack(true)
		for off: Vector3 in CRATE_OFFSETS:
			var crate: Node3D = crate_scene.instantiate() as Node3D
			add_child(crate)
			crate.position = pos + off
			crate.rotation.y = off.x * 0.1
		tris = MeshKit.count_triangles(corn)
	print("BARN_CORN tris(all meshes)=%d" % tris)
	var crate_probe: Node3D = crate_scene.instantiate() as Node3D
	add_child(crate_probe)
	print("AMMO_CRATE tris=%d meshes=%d" % [MeshKit.count_triangles(crate_probe), crate_probe.find_children("*", "MeshInstance3D", true, false).size()])
	crate_probe.free()
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.fov = 62.0
	if OS.get_cmdline_user_args().has("--cam=close"):
		cam.position = Vector3(-30.0, 3.2, -14.0)
		cam.look_at(Vector3(-30.0, 1.0, 3.0))
	else:
		cam.position = Vector3(0.0, 16.0, -38.0)
		cam.look_at(Vector3(0.0, 0.0, 12.0))
