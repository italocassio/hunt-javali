extends Node3D
## Preview: the four first-person item gestures (assets/models/items/*_view.tscn) over the art-director map slice, with the
## game's camera (fov 75). Plays each gesture in real time and saves a PNG at chosen fractions of it, prints the budget,
## then quits. Needs a window (no --headless); use --fixed-fps so the gesture time is deterministic:
##   tools/godot.ps1 --path . --windowed --resolution 1280x720 --fixed-fps 30 res://assets/preview/items_preview.tscn -- \
##       --out=C:/abs/dir [--only=medkit,corn_bait]
## Per item: <id>_mid.png (middle of the gesture) and <id>_f<percent>.png for the extra fractions.

const GAME_FOV: float = 75.0
const HARD_TIMEOUT_S: float = 150.0
## id -> [duration_s, effect_at, mid fraction, extra fractions]
const ITEMS: Dictionary = {
	&"medkit": [1.5, 0.9, 0.55, [0.25, 0.4, 0.7, 0.9, 0.97]],
	&"energy_drink": [1.5, 0.8, 0.5, [0.2, 0.35, 0.65, 0.8, 0.9]],
	&"scout_drone": [1.2, 0.7, 0.45, [0.2, 0.6, 0.7, 0.8, 0.9]],
	&"corn_bait": [0.9, 0.45, 0.30, [0.15, 0.45, 0.55, 0.7, 0.85]],
}

var _out_dir: String = "user://items_preview"
var _only: PackedStringArray = PackedStringArray()
var _world: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",", false)
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(func() -> void: get_tree().quit(1))
	if DisplayServer.get_name() == "headless":
		_print_budgets()
		print("items_preview: needs a window, nothing rendered")
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _new_view(id: StringName, parent: Node) -> ItemViewBase:
	var path: String = ScenePaths.item_view(id)
	var view: ItemViewBase = (load(path) as PackedScene).instantiate()
	parent.add_child(view)
	return view


func _print_budgets() -> void:
	for id: StringName in ITEMS:
		var view: ItemViewBase = _new_view(id, self)
		var b: Dictionary = view.call(&"get_budget")
		print("items_preview: %s %d triangles, %d geometry nodes, %d materials" % [id, b["triangles"], b["meshes"], b["materials"]])
		for mi: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				printerr("items_preview: %s/%s casts shadows" % [id, mi.name])
		view.queue_free()


func _run() -> void:
	_print_budgets()
	for id: StringName in ITEMS:
		if not _only.is_empty() and not _only.has(String(id)):
			continue
		var spec: Array = ITEMS[id]
		var duration: float = spec[0]
		var beat: float = spec[1]
		var shots: Array = [[spec[2], "mid"]]
		for f: float in spec[3]:
			shots.append([f, "f%02d" % roundi(f * 100.0)])
		shots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		_clear()
		var cam: Camera3D = _scene()
		var view: ItemViewBase = _new_view(id, cam)
		for i in 12:
			await get_tree().process_frame
		view.play_use(duration, beat)
		var elapsed: float = 0.0
		for shot: Array in shots:
			while elapsed < float(shot[0]) * duration:
				await get_tree().process_frame
				elapsed += get_process_delta_time()
			await RenderingServer.frame_post_draw
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = _out_dir.path_join("%s_%s.png" % [id, shot[1]])
			print("items_preview: %s %s (t=%.2f)" % ["saved" if image.save_png(path) == OK else "FAILED", path, elapsed])
	get_tree().quit(0)


func _clear() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)


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
