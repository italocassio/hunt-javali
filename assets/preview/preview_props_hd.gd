extends Node3D
## Preview of the HD barn, water tank and small props. User args (after the second --):
##   --measure                         print stats for every HD prop, quit
##   --barn-studio | --tank-studio     prop alone on flat ground, studio camera
##   --barn-map | --tank-map | --far   in the preview map under the game light
##   --small-studio                    fence, gate, bait, trough and the full barn corn stock side by side
##   --small-map | --bait-map          fence + gate / bait + trough in the preview map (game light)
##   --stages                          barn corn stock, stages 4..0 (3 + 2 grid); add --stage-close for the full one only
## Screenshot: tools/godot.sh --path . --windowed --resolution 960x540 -s res://tools/screenshot.gd -- \
##   --scene=res://assets/preview/preview_props_hd.tscn --out=<png> -- --barn-map

const PM := preload("res://assets/models/props/prop_materials.gd")
const FarmhouseHD := preload("res://assets/models/props/farmhouse_hd.gd")
const BarnHD := preload("res://assets/models/props/barn_hd.gd")
const WaterTankHD := preload("res://assets/models/props/water_tank_hd.gd")
const FenceHD := preload("res://assets/models/props/fence_hd.gd")
const GateHD := preload("res://assets/models/props/gate_hd.gd")
const CornBaitHD := preload("res://assets/models/props/corn_bait_hd.gd")
const FeedTroughHD := preload("res://assets/models/props/feed_trough_hd.gd")
const BarnCornScript := preload("res://assets/models/props/barn_corn.gd")

const BARN_POS: Vector2 = Vector2(-48.0, 4.0)
const TANK_POS: Vector2 = Vector2(-20.0, 6.0)
const HOUSE_POS: Vector2 = Vector2(-30.0, -10.0)
const FENCE_POS: Vector2 = Vector2(-14.0, 27.0)     # fence row along X, gate in the middle
const BAIT_POS: Vector2 = Vector2(6.0, 24.0)
const RING_M: float = 7.0
const STAGE_PCTS: Array[float] = [100.0, 60.0, 40.0, 10.0, 0.0]


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--measure"):
		_measure()
		return
	var cam: Camera3D = Camera3D.new()
	cam.fov = 70.0
	if args.has("--stages"):
		_stages(cam, args.has("--stage-close"))
		return
	if args.has("--small-studio"):
		_small_studio(cam)
		return
	if args.has("--small-map") or args.has("--bait-map"):
		_small_map(cam, args.has("--bait-map"))
		return
	if args.has("--barn-map") or args.has("--tank-map") or args.has("--far"):
		var map: Node3D = (load("res://assets/preview/preview_map.tscn") as PackedScene).instantiate()
		map.set("with_boars", false)
		add_child(map)
		var target: Vector3
		var from: Vector3
		if args.has("--barn-map"):
			target = Vector3(BARN_POS.x, 0.0, BARN_POS.y)
			from = target + Vector3(-5.0, 0.0, -25.0)
			target.y = float(map.call("_h", target.x, target.z)) + 2.6
		elif args.has("--tank-map"):
			target = Vector3(TANK_POS.x, 0.0, TANK_POS.y)
			from = target + Vector3(5.0, 0.0, -20.0)
			target.y = float(map.call("_h", target.x, target.z)) + 3.6
		else:
			target = Vector3(-33.0, 0.0, 0.0)
			from = target + Vector3(18.0, 0.0, -57.0)
			target.y = float(map.call("_h", target.x, target.z)) + 3.0
		from.y = float(map.call("_h", from.x, from.z)) + (4.5 if args.has("--far") else 1.7)
		add_child(cam)
		cam.position = from
		cam.look_at(target)
		_clear_line_of_sight(map, from, target)
	else:
		_studio_ground()
		var id: String = "barn" if args.has("--barn-studio") else "water_tank"
		var prop: Node3D = (load("res://assets/models/props/%s.tscn" % id) as PackedScene).instantiate()
		add_child(prop)
		add_child(cam)
		if id == "barn":
			cam.position = Vector3(9.0, 2.0, -13.5)
			cam.look_at(Vector3(0.0, 2.8, 0.0))
		else:
			cam.position = Vector3(6.0, 2.5, -9.0)
			cam.look_at(Vector3(0.0, 4.0, 0.0))
	cam.make_current()


func _studio_ground(no_fog: bool = false) -> void:
	var env_root: Node = (load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate()
	add_child(env_root)
	if no_fog:   # preview only: keep far colours readable
		for n: Node in env_root.find_children("*", "WorldEnvironment", true, false):
			var we: Environment = (n as WorldEnvironment).environment
			if we != null:
				we.fog_enabled = false
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.40, 0.26)
	ground.material_override = gm
	add_child(ground)


func _prop(id: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var prop: Node3D = (load("res://assets/models/props/%s.tscn" % id) as PackedScene).instantiate()
	prop.position = pos
	prop.rotation.y = deg_to_rad(yaw)
	add_child(prop)
	return prop


func _small_studio(cam: Camera3D) -> void:
	_studio_ground()
	_prop("fence_segment", Vector3(-7.5, 0.0, 0.0))
	_prop("gate", Vector3(-3.0, 0.0, 0.0))
	_prop("corn_bait", Vector3(0.4, 0.0, 0.0))
	_prop("feed_trough", Vector3(3.6, 0.0, 0.0), 12.0)
	var corn: CornStockVisualBase = (load("res://assets/models/props/barn_corn.tscn") as PackedScene).instantiate() as CornStockVisualBase
	corn.setup(RING_M)
	add_child(corn)
	corn.position = Vector3(1.0, 0.0, 9.5)
	corn.set_stock_pct(100.0)
	cam.fov = 62.0
	add_child(cam)
	cam.position = Vector3(0.0, 3.4, -8.2)
	cam.look_at(Vector3(0.0, 0.7, 2.5))
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):   # --cam=px,py,pz,tx,ty,tz overrides the camera (close-ups)
			var v: PackedStringArray = a.trim_prefix("--cam=").split(",")
			cam.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
	cam.make_current()


func _small_map(cam: Camera3D, bait: bool) -> void:
	var map: Node3D = (load("res://assets/preview/preview_map.tscn") as PackedScene).instantiate()
	map.set("with_boars", false)
	add_child(map)
	var target: Vector3
	var from: Vector3
	if bait:
		target = Vector3(BAIT_POS.x + 0.9, 0.0, BAIT_POS.y + 0.4)
		from = Vector3(BAIT_POS.x - 0.8, 0.0, BAIT_POS.y - 4.4)
		_map_prop(map, "corn_bait", BAIT_POS + Vector2(-1.0, 0.2), 0.0)
		_map_prop(map, "feed_trough", BAIT_POS + Vector2(2.7, 1.2), 8.0)
		target.y = float(map.call("_h", target.x, target.z)) + 0.35
		from.y = float(map.call("_h", from.x, from.z)) + 1.55
	else:
		for i: int in 7:
			var id: String = "gate" if i == 3 else "fence_segment"
			_map_prop(map, id, Vector2(FENCE_POS.x + 4.0 * float(i), FENCE_POS.y), 0.0)
		target = Vector3(FENCE_POS.x + 12.0, 0.0, FENCE_POS.y)
		from = Vector3(FENCE_POS.x + 8.0, 0.0, FENCE_POS.y - 8.0)
		target.y = float(map.call("_h", target.x, target.z)) + 0.8
		from.y = float(map.call("_h", from.x, from.z)) + 1.7
	add_child(cam)
	cam.position = from
	cam.look_at(target)
	cam.make_current()
	_clear_line_of_sight(map, from, target, 0.5)


func _map_prop(map: Node3D, id: String, p: Vector2, yaw: float) -> void:
	_prop(id, Vector3(p.x, float(map.call("_h", p.x, p.y)), p.y), yaw)


func _stages(cam: Camera3D, close: bool) -> void:
	_studio_ground(true)
	var corn_scene: PackedScene = load("res://assets/models/props/barn_corn.tscn")
	var spacing: float = 17.0
	for i: int in STAGE_PCTS.size():
		var corn: CornStockVisualBase = corn_scene.instantiate() as CornStockVisualBase
		corn.setup(RING_M)
		add_child(corn)
		corn.position = Vector3((2.0 - float(i)) * spacing, 0.0, 0.0)   # stage 4 at the left of the picture
		corn.set_stock_pct(STAGE_PCTS[i])
		if close:
			break
	add_child(cam)
	if close:
		cam.fov = 62.0
		cam.position = Vector3(2.0, 7.5, -12.0)
		cam.look_at(Vector3(0.0, 0.8, 1.5))
	else:
		cam.fov = 70.0
		cam.position = Vector3(0.0, 15.0, -34.0)
		cam.look_at(Vector3(0.0, 0.0, 0.0))
	cam.make_current()


## Hides map scatter (trees, shrubs) that would stand between the camera and the target.
func _clear_line_of_sight(map: Node3D, from: Vector3, to: Vector3, keep_radius: float = 8.0) -> void:
	var a: Vector2 = Vector2(from.x, from.z)
	var b: Vector2 = Vector2(to.x, to.z)
	for n: Node in map.get_children():
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_aabb().size.x > 12.0 or n.get_child_count() > 0:
			continue
		var q: Vector2 = Vector2(mi.position.x, mi.position.z)
		var cp: Vector2 = Geometry2D.get_closest_point_to_segment(q, a, b)
		if q.distance_to(cp) < 5.0 and q.distance_to(b) > keep_radius and mi.mesh.get_aabb().size.y > 0.8:
			mi.visible = false


func _measure() -> void:
	var t0: int = Time.get_ticks_usec()
	PM.get_material()
	var t1: int = Time.get_ticks_usec()
	print("SHARED noise+material_ms=%.1f" % (float(t1 - t0) / 1000.0))
	var total: float = 0.0
	var small: float = 0.0
	var entries: Array = [["FARMHOUSE", FarmhouseHD], ["BARN", BarnHD], ["WATER_TANK", WaterTankHD],
		["FENCE_SEGMENT", FenceHD], ["GATE", GateHD], ["CORN_BAIT", CornBaitHD], ["FEED_TROUGH", FeedTroughHD]]
	for entry: Array in entries:
		var script: GDScript = entry[1]
		var t2: int = Time.get_ticks_usec()
		var model: Dictionary = script.build()
		var cold: float = float(Time.get_ticks_usec() - t2) / 1000.0
		total += cold
		if script != FarmhouseHD and script != BarnHD and script != WaterTankHD:
			small += cold
		var mesh: ArrayMesh = model["mesh"]
		var bb: AABB = mesh.get_aabb()
		print("%s tris=%d verts=%d surfaces=%d materials=%d mesh_instances=1 aabb_size=%s aabb_pos=%s cold_ms=%.1f (emit %.1f weld %.1f ao %.1f)" % [entry[0], model["triangles"], model["vertices"], mesh.get_surface_count(), model["materials"], bb.size, bb.position, cold, model["emit_ms"], model["weld_ms"], model["ao_ms"]])
	var t3: int = Time.get_ticks_usec()
	var bc: Dictionary = BarnCornScript.build()
	var cold_bc: float = float(Time.get_ticks_usec() - t3) / 1000.0
	total += cold_bc
	small += cold_bc
	print("BARN_CORN tris(all 8 instances)=%d verts(unique meshes)=%d materials=%d mesh_instances=%d cold_ms=%.1f" % [bc["triangles"], bc["vertices"], bc["materials"], bc["mesh_instances"], cold_bc])
	for k: StringName in [&"pile", &"heap", &"sacks"]:
		var st: Dictionary = BarnCornScript._stats[k]
		var mb: AABB = (BarnCornScript._meshes[k] as ArrayMesh).get_aabb()
		print("  BARN_CORN %s tris=%d build_ms=%.1f aabb_size=%s aabb_pos=%s" % [k, st["triangles"], st["build_ms"], mb.size, mb.position])
	print("TOTAL cold_ms=%.1f (small props + barn_corn only %.1f)" % [total, small])
	get_tree().quit()
