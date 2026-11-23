extends Node3D
## Preview: the first-person knife view (assets/models/weapons/knife_view.tscn) at rest and during the swing, over the
## art-director map slice, with the game's camera (fov 75). Saves PNGs and a 2x2 sheet, prints the budget, then quits.
## Needs a window (no --headless):
##   tools/godot.sh --path . --windowed --resolution 1280x720 res://assets/preview/knife_preview.tscn -- \
##       --out=C:/abs/dir [--shots=rest,windup,strike,follow] [--frames=24]
## Shots are swing fractions: rest = 0, windup 0.12, strike 0.30 (the tip over the screen centre), follow 0.46.

const GAME_FOV: float = 75.0
const SHOT_PHASE: Dictionary = {"rest": 0.0, "windup": 0.12, "strike": 0.30, "mid": 0.20, "follow": 0.46, "return": 0.70}
const HARD_TIMEOUT_S: float = 110.0

var _out_dir: String = "user://knife_preview"
var _frames: int = 24
var _world: Node3D


func _ready() -> void:
	var shots: String = "rest,windup,strike,follow"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 4)
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(func() -> void: get_tree().quit(1))
	_print_stats()
	if DisplayServer.get_name() == "headless":
		print("knife_preview: needs a window, nothing rendered")
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false))


func _new_view(parent: Node) -> WeaponViewBase:
	var view: WeaponViewBase = (load("res://assets/models/weapons/knife_view.tscn") as PackedScene).instantiate()
	parent.add_child(view)
	return view


func _print_stats() -> void:
	var view: WeaponViewBase = _new_view(self)
	var tris: int = 0
	var meshes: int = 0
	var mats: Dictionary = {}
	for mi: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			printerr("knife_preview: %s casts shadows" % mi.name)
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += int(idx.size() / 3.0)
			var m: Material = mi.mesh.surface_get_material(s)
			if m != null:
				mats[m.get_instance_id()] = true
		print("knife_preview: %s %d surfaces" % [mi.name, mi.mesh.get_surface_count()])
	print("knife_preview: %d triangles, %d MeshInstance3D, %d materials" % [tris, meshes, mats.size()])
	var cam_tip: Vector3 = view.call(&"get_tip_at", 0.30)
	print("knife_preview: tip at 30%% of the swing -> x/z %.3f, y/z %.3f (0, 0 = screen centre)" % [cam_tip.x / -cam_tip.z, cam_tip.y / -cam_tip.z])
	for u: float in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.7, 1.0]:
		var p: Vector3 = view.call(&"get_tip_at", u)
		print("  u=%.2f tip x/z %.3f y/z %.3f depth %.2f" % [u, p.x / -p.z, p.y / -p.z, -p.z])
	view.queue_free()


func _run(shots: PackedStringArray) -> void:
	var images: Array[Image] = []
	for shot in shots:
		if not SHOT_PHASE.has(shot):
			printerr("knife_preview: unknown shot '%s'" % shot)
			continue
		_clear()
		var cam: Camera3D = _scene()
		var view: WeaponViewBase = _new_view(cam)
		view.set_process(false)
		var u: float = SHOT_PHASE[shot]
		view.call(&"_apply", view.call(&"_pose", u))
		for i in _frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("knife_%s.png" % shot)
		print("knife_preview: %s %s" % ["saved" if image.save_png(path) == OK else "FAILED", path])
		images.append(image)
	if images.size() == 4:
		var w: int = images[0].get_width()
		var h: int = images[0].get_height()
		var sheet: Image = Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
		for i in 4:
			sheet.blit_rect(images[i], Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i >> 1) * h))
		sheet.save_png(_out_dir.path_join("knife_sheet.png"))
	get_tree().quit(0)


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
