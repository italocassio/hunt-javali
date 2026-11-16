extends Node3D
## Preview (prototype, not wired into the game): the in-game rifle_308 view with its low-poly arms swapped
## for the HD arms of showcase/arms_hd.gd, posed through ArmsHD.bolt_pose(). Saves PNGs, then quits.
## Needs a window (no --headless):
##   tools/godot.sh --path . --windowed --resolution 960x540 res://assets/preview/preview_arms_showcase.tscn -- \
##       --out=C:/abs/dir [--shots=hip,ads,cycle,reload,close_grip,close_fore] [--frames=30]

const ArmsHD := preload("res://assets/models/weapons/showcase/arms_hd.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const DEFAULT_SHOTS: String = "hip,ads,cycle,reload,close_grip,close_fore"
const GAME_FOV: float = 75.0
const ADS_FOV: float = 45.0
const CYCLE_S: float = 1.2
const RELOAD_S: float = 2.4
const HARD_TIMEOUT_S: float = 110.0

var _out_dir: String = "user://arms_showcase"
var _frames: int = 30
var _world: Node3D


func _ready() -> void:
	var shots: String = DEFAULT_SHOTS
	var phase: float = -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 4)
		elif a.begins_with("--phase="):
			phase = float(a.trim_prefix("--phase="))
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	_print_stats()
	if DisplayServer.get_name() == "headless":
		print("preview_arms_showcase: needs a window, nothing rendered")
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false), phase)


func _on_timeout() -> void:
	printerr("preview_arms_showcase: timed out")
	get_tree().quit(1)


## The in-game .308 view with the HD arms meshes in RightArm / LeftArm.
func _new_view(parent: Node) -> WeaponViewBase:
	var view: WeaponViewBase = (load("res://assets/models/weapons/rifle_308_view.tscn") as PackedScene).instantiate()
	parent.add_child(view)
	view.setup(&"rifle_308")
	var arms: Dictionary = _arms()
	(view.get_node(^"Gun/RightArm") as MeshInstance3D).mesh = arms["right"]
	(view.get_node(^"Gun/LeftArm") as MeshInstance3D).mesh = arms["left"]
	view.set_process(false)
	return view


func _arms() -> Dictionary:
	var model: Dictionary = RifleHD.get_model()
	var faces: PackedVector3Array = (model["body"] as Mesh).get_faces()
	faces.append_array((model["bolt"] as Mesh).get_faces())
	return ArmsHD.get_arms(&"rifle_308", faces)


func _print_stats() -> void:
	var arms: Dictionary = _arms()
	var rifle: Dictionary = RifleHD.get_stats()
	var view: WeaponViewBase = _new_view(self)
	var tris: int = 0
	var meshes: int = 0
	var mats: Dictionary = {}
	for mi: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += int(idx.size() / 3.0) if idx.size() > 0 else int((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
			var m: Material = mi.mesh.surface_get_material(s)
			if m != null:
				mats[m.get_instance_id()] = true
	print("arms_showcase: arms %d tris (right %d, left %d, %d ms) | rifle %d tris | total %d tris, %d MeshInstance3D, %d materials" % [
		int(arms["triangles"]), int(arms["right_tris"]), int(arms["left_tris"]), int(arms["build_ms"]),
		int(rifle["triangles"]), tris, meshes, mats.size()])
	view.queue_free()


func _run(shots: PackedStringArray, phase: float) -> void:
	for shot in shots:
		_clear()
		var cam: Camera3D = _scene()
		var view: WeaponViewBase = _new_view(cam)
		var cycle_t: float = -1.0
		var reload_t: float = -1.0
		match shot:
			"hip", "close_grip", "close_fore":
				pass
			"ads":
				var a: Vector3 = view.get_ads_anchor().position
				view.position = Vector3(-a.x, -a.y, 0.0)
				cam.fov = ADS_FOV
			"cycle":
				cycle_t = phase if phase >= 0.0 else 0.42
			"reload":
				reload_t = phase if phase >= 0.0 else 0.5
			_:
				printerr("preview_arms_showcase: unknown shot '%s'" % shot)
				continue
		_pose(view, cycle_t, reload_t)
		if shot.begins_with("close"):
			_close_camera(cam, view, shot == "close_grip")
		for i in _frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("%s.png" % shot)
		var err: Error = image.save_png(path)
		print("preview_arms_showcase: %s %s" % ["saved" if err == OK else "FAILED", path])
	get_tree().quit(0)


## Drives weapon_view.gd's own pose code at a fixed phase, then places the arms with ArmsHD.bolt_pose().
func _pose(view: WeaponViewBase, cycle_t: float, reload_t: float) -> void:
	view.set(&"_cycle_d", CYCLE_S)
	view.set(&"_cycle_t", cycle_t * CYCLE_S if cycle_t >= 0.0 else -1.0)
	view.set(&"_reload_d", RELOAD_S)
	view.set(&"_reload_t", reload_t * RELOAD_S if reload_t >= 0.0 else -1.0)
	view.call(&"_apply_pose", 0.0)
	var mover: Node3D = view.get_node(^"Gun/Mover")
	var arms: Dictionary = _arms()
	var knob_now: Vector3 = mover.transform * (arms["knob_gun"] as Vector3)
	var xf: Array[Transform3D] = ArmsHD.bolt_pose(arms, cycle_t, reload_t, knob_now)
	(view.get_node(^"Gun/RightArm") as Node3D).transform = xf[0]
	(view.get_node(^"Gun/LeftArm") as Node3D).transform = xf[1]


func _clear() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)


## The art-director map slice (same sky, sun, terrain and flora as the hunt) and the player camera.
func _scene() -> Camera3D:
	var map: Node3D = (load("res://assets/preview/preview_map.tscn") as PackedScene).instantiate()
	map.set(&"with_boars", false)
	_world.add_child(map)
	var ground: float = map.call(&"_h", 2.0, 12.0)
	var cam: Camera3D = Camera3D.new()
	cam.fov = GAME_FOV
	cam.near = 0.05
	cam.far = 400.0
	_world.add_child(cam)
	cam.look_at_from_position(Vector3(2.0, ground + 1.7, 12.0), Vector3(-4.0, ground + 1.45, -10.0), Vector3.UP)
	cam.make_current()
	return cam


## Close-up from the eye toward one hand (narrow lens), the view stays where the player camera put it.
func _close_camera(cam: Camera3D, view: WeaponViewBase, grip: bool) -> void:
	var arms: Dictionary = _arms()
	var gun: Node3D = view.get_node(^"Gun")
	var target: Vector3 = gun.global_transform * ((arms["right_hand"] if grip else arms["left_hand"]) as Vector3)
	var close: Camera3D = Camera3D.new()
	close.fov = 26.0
	close.near = 0.02
	close.far = 400.0
	_world.add_child(close)
	var eye: Vector3 = cam.global_transform * Vector3(-0.06, 0.02, 0.0)
	close.look_at_from_position(eye, target, Vector3.UP)
	close.make_current()
