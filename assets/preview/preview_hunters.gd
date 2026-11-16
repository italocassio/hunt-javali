extends Node3D
## Preview: third-person hunters (assets/models/hunter/hunter_visual.tscn). Prints build times and budgets,
## then renders the requested shots to PNG and quits. Stats only with --headless.
##   tools/godot.sh --path . --windowed --resolution 960x540 res://assets/preview/preview_hunters.tscn -- \
##       --out=C:/abs/dir [--shots=stand,walk,crouch,aim_up,dead,slots,far,reload,unarmed_aim] [--frames=20]

const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const Held := preload("res://assets/models/hunter/hunter_held.gd")
const SCENE: String = "res://assets/models/hunter/hunter_visual.tscn"
const DEFAULT_SHOTS: String = "stand,walk,crouch,aim_up,dead,slots,far"
const GUNS: Array[StringName] = [&"rifle_308", &"shotgun_12", &"carbine_22", &"rifle_3006", &"rifle_338", &""]
const HARD_TIMEOUT_S: float = 120.0

var _out_dir: String = "user://hunters"
var _frames: int = 20
var _world: Node3D


func _ready() -> void:
	var shots: String = DEFAULT_SHOTS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 4)
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	_print_stats()
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false))


func _on_timeout() -> void:
	printerr("preview_hunters: timed out")
	get_tree().quit(1)


func _new_hunter(slot: int, weapon: StringName) -> HunterVisualBase:
	var h: HunterVisualBase = (load(SCENE) as PackedScene).instantiate()
	h.setup(slot, weapon)
	return h


func _print_stats() -> void:
	var t0: int = Time.get_ticks_usec()
	RifleHD.get_materials()
	var noise_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var vis: GDScript = load("res://assets/models/hunter/hunter_visual.gd")
	var lines: PackedStringArray = PackedStringArray()
	lines.append("noise texture of the HD materials (already built in game by the 1st-person gun): %.1f ms" % noise_ms)
	var combos: Array = [[0, &"rifle_308"], [1, &"shotgun_12"], [2, &"carbine_22"], [3, &"rifle_3006"], [0, &"rifle_338"],
		[1, &"rifle_308"], [2, &"shotgun_12"]]
	for c: Array in combos:
		var h: HunterVisualBase = (load(SCENE) as PackedScene).instantiate()
		var ts: int = Time.get_ticks_usec()
		h.setup(c[0], c[1])
		lines.append("setup(slot %d, %s): %.2f ms (built: %.2f ms)" % [c[0], c[1], float(Time.get_ticks_usec() - ts) / 1000.0,
			float(vis.get(&"last_build_ms"))])
		h.free()
	var h2: HunterVisualBase = _new_hunter(0, &"rifle_308")
	var t1: int = Time.get_ticks_usec()
	h2.set_weapon(&"shotgun_12")
	lines.append("set_weapon(seen weapon): %.3f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))
	h2.free()
	# triangles / meshes / materials per weapon
	var mats: Dictionary = {}
	for w: StringName in GUNS:
		var h: HunterVisualBase = _new_hunter(0, w)
		add_child(h)
		if w == &"":
			h.set_aiming(true)
		h.call(&"_update_pose", 1.0)
		var tris: int = 0
		var mis: int = 0
		for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
			mis += 1
			if mi.mesh == null or (not mi.visible and mi.name != "Flash"):
				continue
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				tris += int((idx as PackedInt32Array).size() / 3.0) if idx is PackedInt32Array else int((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
				var m: Material = mi.mesh.surface_get_material(s)
				if m != null:
					mats[m.get_instance_id()] = m.resource_path if m.resource_path != "" else str(m.get_class())
		lines.append("%s: %d tris (visible + flash), %d MeshInstance3D, gun build %.1f ms, item tris %d" % [
			w if w != &"" else &"unarmed (binoculars aimed)", tris, mis, float(Held.get_item(w)["ms"]), int(Held.get_item(w)["tris"])])
		lines.append("   item gun %d tris; per pose %s" % [int(Held.get_item(w)["gun_tris"]), str((Held.get_item(w)["poses"] as Dictionary).keys().map(func(kk: String) -> String: return "%s %d" % [kk, int(Held.get_item(w)["poses"][kk]["tris"])]))])
		h.free()
	lines.append("unique materials over all 5 guns + unarmed: %d" % mats.size())
	lines.append("body part tris: %s" % str(load("res://assets/models/hunter/hunter_body.gd").get(&"_shared")["tris"]))
	for l in lines:
		print("preview_hunters: " + l)


func _run(shots: PackedStringArray) -> void:
	for shot in shots:
		_clear()
		var cam: Camera3D = _scene()
		var hunters: Array[HunterVisualBase] = []
		match shot:
			"stand":
				hunters.append(_place(0, &"rifle_308", Vector3.ZERO, 150.0))
				_frame(cam, Vector3(0.0, 1.0, 0.0), 3.6, 1.15)
			"walk":
				var h: HunterVisualBase = _place(1, &"shotgun_12", Vector3.ZERO, 115.0)
				h.set_locomotion(3.2)
				hunters.append(h)
				_frame(cam, Vector3(0.0, 1.0, 0.0), 3.6, 1.15)
			"crouch":
				var h: HunterVisualBase = _place(2, &"carbine_22", Vector3(-0.7, 0, 0), 140.0)
				h.set_crouching(true)
				var h2: HunterVisualBase = _place(3, &"rifle_3006", Vector3(0.7, 0, 0), 120.0)
				h2.set_crouching(true)
				h2.set_aiming(true)
				_frame(cam, Vector3(0.0, 0.75, 0.0), 4.0, 1.0)
			"aim_up":
				var h: HunterVisualBase = _place(3, &"rifle_338", Vector3(-0.6, 0, 0), 100.0)
				h.set_aiming(true)
				h.set_look_pitch(0.45)
				var h2: HunterVisualBase = _place(0, &"rifle_308", Vector3(0.7, 0, 0), 160.0)
				h2.set_aiming(true)
				_frame(cam, Vector3(0.0, 1.1, 0.0), 4.2, 1.25)
			"dead":
				var h: HunterVisualBase = _place(1, &"rifle_3006", Vector3(-0.3, 0, 0), 60.0)
				h.play_death(true)
				_frame(cam, Vector3(0.0, 0.4, 0.0), 3.6, 1.5)
			"slots":
				var weapons: Array[StringName] = [&"rifle_308", &"shotgun_12", &"carbine_22", &"rifle_338"]
				for i in 4:
					hunters.append(_place(i, weapons[i], Vector3((float(i) - 1.5) * 1.05, 0, 0), 150.0))
				hunters[1].set_aiming(true)
				_frame(cam, Vector3(0.0, 0.95, 0.0), 6.2, 1.2)
			"far":
				var weapons: Array[StringName] = [&"rifle_308", &"shotgun_12", &"", &"rifle_338"]
				for i in 4:
					var h: HunterVisualBase = _place(i, weapons[i], Vector3((float(i) - 1.5) * 3.0, 0, 0), 120.0 + 30.0 * i)
					hunters.append(h)
				hunters[0].set_locomotion(3.0)
				hunters[1].set_aiming(true)
				hunters[3].set_crouching(true)
				_frame(cam, Vector3(0.0, 1.0, 0.0), 40.0, 1.6)
				cam.fov = 40.0
			"reload":
				var h: HunterVisualBase = _place(0, &"rifle_3006", Vector3(-0.6, 0, 0), 120.0)
				h.play_reload(0.7)
				var h2: HunterVisualBase = _place(2, &"shotgun_12", Vector3(0.7, 0, 0), 120.0)
				h2.play_reload(0.7)
				_frame(cam, Vector3(0.0, 1.0, 0.0), 4.2, 1.25)
			"unarmed_aim":
				var h: HunterVisualBase = _place(1, &"", Vector3(-0.6, 0, 0), 150.0)
				h.set_aiming(true)
				var h2: HunterVisualBase = _place(3, &"", Vector3(0.7, 0, 0), 150.0)
				h2.set_locomotion(3.0)
				_frame(cam, Vector3(0.0, 1.1, 0.0), 4.2, 1.25)
			_:
				printerr("preview_hunters: unknown shot '%s'" % shot)
				continue
		for i in _frames:
			await get_tree().process_frame
		if shot == "walk":
			pass
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("%s.png" % shot)
		var err: Error = image.save_png(path)
		print("preview_hunters: %s %s" % ["saved" if err == OK else "FAILED", path])
	get_tree().quit(0)


func _place(slot: int, weapon: StringName, pos: Vector3, yaw_deg: float) -> HunterVisualBase:
	var h: HunterVisualBase = _new_hunter(slot, weapon)
	_world.add_child(h)
	h.position = pos
	h.rotation.y = deg_to_rad(yaw_deg)
	return h


func _frame(cam: Camera3D, target: Vector3, dist: float, height: float) -> void:
	cam.position = target + Vector3(0.0, height - target.y + 0.35, dist)
	cam.look_at(target)


func _clear() -> void:
	if _world != null:
		_world.free()
	_world = Node3D.new()
	add_child(_world)


func _scene() -> Camera3D:
	_world.add_child((load("res://assets/env/mato_grosso_env.tscn") as PackedScene).instantiate())
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.40, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	_world.add_child(ground)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	cam.far = 400.0
	_world.add_child(cam)
	cam.current = true
	return cam
