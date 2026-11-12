extends SceneTree
## Renders a scene in a real window and saves a PNG, then quits.
## Needs a window, so it does not work with --headless.
##
## Usage (from the project root):
##   tools/godot.sh --path . --windowed --resolution 1280x720 -s res://tools/screenshot.gd -- \
##       --scene=res://path/to/scene.tscn --out=C:/abs/path/shot.png [--frames=90] [--shots=3]
##
## --frames  frames to wait before the first capture (default 90)
## --shots   number of captures, one every --frames; files get a _1, _2... suffix (default 1)

const DEFAULT_FRAMES := 90
const HARD_TIMEOUT_SEC := 60.0


func _initialize() -> void:
	var args := _parse_args()
	var scene_path: String = args.get("scene", "")
	var out_path: String = args.get("out", "")
	if scene_path.is_empty() or out_path.is_empty():
		printerr("screenshot: --scene and --out are required")
		quit(2)
		return
	if not ResourceLoader.exists(scene_path):
		printerr("screenshot: scene not found: %s" % scene_path)
		quit(2)
		return

	var frames := maxi(int(args.get("frames", str(DEFAULT_FRAMES))), 1)
	var shots := maxi(int(args.get("shots", "1")), 1)

	create_timer(HARD_TIMEOUT_SEC).timeout.connect(_on_hard_timeout)
	var err := change_scene_to_file(scene_path)
	if err != OK:
		printerr("screenshot: could not open %s (error %d)" % [scene_path, err])
		quit(2)
		return
	_capture.call_deferred(out_path, frames, shots)


func _capture(out_path: String, frames: int, shots: int) -> void:
	for shot in shots:
		for i in frames:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var target := out_path
		if shots > 1:
			target = "%s_%d.%s" % [out_path.get_basename(), shot + 1, out_path.get_extension()]
		var err := image.save_png(target)
		if err != OK:
			printerr("screenshot: could not save %s (error %d)" % [target, err])
			quit(1)
			return
		print("screenshot: saved %s" % target)
	quit(0)


func _on_hard_timeout() -> void:
	printerr("screenshot: timed out after %.0f s" % HARD_TIMEOUT_SEC)
	quit(1)


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.trim_prefix("--").split("=", true, 1)
			parsed[pair[0]] = pair[1]
	return parsed
