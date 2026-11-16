extends Node3D
## Preview: renders the HD showcase rifle (assets/models/weapons/showcase) and saves PNGs, then quits.
## Needs a window (no --headless):
##   tools/godot.sh --path . --windowed --resolution 1600x900 res://assets/preview/preview_rifle_showcase.tscn -- \
##       --out=C:/abs/dir [--shots=side,three_quarter,first_person,compare] [--frames=40]
## Extra shots for inspection: left, top, rear, muzzle, grip, bolt_open.

const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const DEFAULT_SHOTS: String = "side,three_quarter,first_person,compare"
const GAME_FOV: float = 75.0
const HARD_TIMEOUT_S: float = 110.0

const STUDIO_SKY: String = """
shader_type sky;
// Neutral backdrop for the camera, softboxes for the reflections (radiance pass only).
uniform vec3 backdrop_top : source_color = vec3(0.40, 0.41, 0.43);
uniform vec3 backdrop_bottom : source_color = vec3(0.13, 0.13, 0.14);

float softbox(vec3 d, vec3 center, vec3 right, vec2 half_size) {
	float t = dot(d, center);
	if (t <= 0.0) {
		return 0.0;
	}
	vec3 up = normalize(cross(center, right));
	vec3 p = d / t;
	vec2 q = abs(vec2(dot(p, right), dot(p, up)));
	vec2 e = smoothstep(half_size, half_size * 0.8, q);
	return e.x * e.y;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = mix(backdrop_bottom, backdrop_top, smoothstep(-0.55, 0.65, d.y));
	if (AT_CUBEMAP_PASS) {
		col = mix(vec3(0.035), vec3(0.20), smoothstep(-0.4, 0.9, d.y));
		col += vec3(1.0, 0.96, 0.90) * 4.5 * softbox(d, normalize(vec3(0.55, 0.75, 0.35)), vec3(0.0, 0.0, 1.0), vec2(1.3, 0.45));
		col += vec3(0.80, 0.88, 1.0) * 2.2 * softbox(d, normalize(vec3(-0.8, 0.35, -0.2)), vec3(0.0, 0.0, 1.0), vec2(1.6, 0.30));
		col += vec3(1.0) * 2.5 * softbox(d, normalize(vec3(0.1, 0.25, 1.0)), vec3(1.0, 0.0, 0.0), vec2(0.5, 0.5));
		col += vec3(1.0) * 1.6 * softbox(d, normalize(vec3(0.3, 0.2, -1.0)), vec3(1.0, 0.0, 0.0), vec2(0.6, 0.35));
	}
	COLOR = col;
}
"""

## --gun=carbine_22|shotgun_12 renders those HD guns instead (studio shots only).
var _gun_script: GDScript = RifleHD
var _out_dir: String = "user://showcase"
var _frames: int = 40
var _world: Node3D
var _overlay: CanvasLayer


func _ready() -> void:
	var shots: String = DEFAULT_SHOTS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--gun="):
			_gun_script = load("res://assets/models/weapons/showcase/%s_hd.gd" % a.trim_prefix("--gun=")) as GDScript
		elif a.begins_with("--frames="):
			_frames = maxi(int(a.trim_prefix("--frames=")), 4)
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	if DisplayServer.get_name() == "headless":
		print("preview_rifle_showcase: needs a window, nothing rendered")
		get_tree().quit(0)
		return
	get_viewport().msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred(shots.split(",", false))


func _on_timeout() -> void:
	printerr("preview_rifle_showcase: timed out")
	get_tree().quit(1)


func _run(shots: PackedStringArray) -> void:
	var stats: Dictionary = RifleHD.get_stats()
	print("showcase stats: %s" % JSON.stringify(stats))
	for shot in shots:
		_clear()
		match shot:
			"side": _shot_studio(Vector3(1.86, 0.02, -0.55), Vector3(0.0, -0.035, -0.55), 22.0)
			"left": _shot_studio(Vector3(-1.86, 0.02, -0.55), Vector3(0.0, -0.035, -0.55), 22.0)
			"top": _shot_studio(Vector3(0.25, 1.55, -0.45), Vector3(0.0, 0.0, -0.50), 26.0)
			"three_quarter": _shot_studio(Vector3(0.40, 0.21, -0.05), Vector3(0.0, 0.012, -0.435), 30.0)
			"rear": _shot_studio(Vector3(-0.30, 0.17, 0.12), Vector3(0.0, 0.0, -0.40), 34.0)
			"muzzle": _shot_studio(Vector3(0.30, 0.12, -1.22), Vector3(0.0, 0.01, -0.80), 30.0)
			"grip": _shot_studio(Vector3(-0.42, -0.02, -0.30), Vector3(0.0, -0.05, -0.33), 30.0)
			"mid": _shot_studio(Vector3(0.62, 0.10, -0.46), Vector3(0.0, -0.012, -0.46), 30.0)
			"fore": _shot_studio(Vector3(-0.40, 0.05, -0.80), Vector3(0.0, -0.01, -0.66), 30.0)
			"bolt_open": _shot_studio(Vector3(0.40, 0.21, -0.05), Vector3(0.0, 0.012, -0.435), 30.0, true)
			"first_person": _shot_first_person(false)
			"first_person_close": _shot_first_person(true)
			"compare": _shot_compare()
			"lineup": _shot_lineup()
			_:
				printerr("preview_rifle_showcase: unknown shot '%s'" % shot)
				continue
		for i in _frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = _out_dir.path_join("%s.png" % shot)
		var err: Error = image.save_png(path)
		print("preview_rifle_showcase: %s %s" % ["saved" if err == OK else "FAILED", path])
	get_tree().quit(0)


func _clear() -> void:
	if _world != null:
		_world.queue_free()
	if _overlay != null:
		_overlay.queue_free()
	_world = Node3D.new()
	add_child(_world)
	_overlay = CanvasLayer.new()
	add_child(_overlay)


# --- studio ---------------------------------------------------------------------------------------

func _studio_lighting() -> void:
	var shader: Shader = Shader.new()
	shader.code = STUDIO_SKY
	var sky_mat: ShaderMaterial = ShaderMaterial.new()
	sky_mat.shader = shader
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_light(Vector3(-48.0, 58.0, 0.0), Color(1.0, 0.96, 0.90), 1.9, true)     # key: above, camera side, a bit from behind the butt
	_light(Vector3(-12.0, -110.0, 0.0), Color(0.80, 0.88, 1.0), 0.45, false)  # fill from the far side
	_light(Vector3(-30.0, 170.0, 0.0), Color(1.0, 1.0, 1.0), 0.8, false)      # rim from the muzzle end


func _light(rot_deg: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var l: DirectionalLight3D = DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	l.shadow_enabled = shadows
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	l.directional_shadow_max_distance = 4.0
	l.shadow_bias = 0.01
	l.shadow_normal_bias = 0.4
	l.shadow_blur = 1.5
	_world.add_child(l)


func _new_rifle(parent: Node, hip: bool) -> Node3D:
	var rifle: Node3D = _gun_script.new()
	parent.add_child(rifle)
	rifle.call(&"set_hip_pose", hip)
	return rifle


func _camera(pos: Vector3, target: Vector3, fov: float) -> Camera3D:
	var cam: Camera3D = Camera3D.new()
	cam.fov = fov
	cam.near = 0.02
	cam.far = 50.0
	_world.add_child(cam)
	cam.look_at_from_position(pos, target, Vector3.UP)
	cam.make_current()
	return cam


func _shot_studio(cam_pos: Vector3, target: Vector3, fov: float, bolt_open: bool = false) -> void:
	_studio_lighting()
	var rifle: Node3D = _new_rifle(_world, false)
	rifle.call(&"set_cast_shadows", true)
	if bolt_open:
		rifle.set_process(false)
		var bolt: Node3D = rifle.get_node_or_null(^"Gun/Bolt")
		if bolt == null:
			bolt = rifle.get_node(^"Gun/Mover")
		if _gun_script.resource_path.contains("shotgun"):
			bolt.position = Vector3(0.0, 0.0, 0.13)   # pump racked back
		else:
			bolt.rotation = Vector3(0.0, 0.0, 1.05)
			bolt.position = Vector3(0.0, 0.0, 0.06)
	_camera(cam_pos, target, fov)


# --- game context ---------------------------------------------------------------------------------

## close = false: contract hip pose (butt at about (0.20, -0.22, -0.30)).
## close = true: suggested framing, butt pulled back beside the body so the action fills the corner.
func _shot_first_person(close: bool) -> void:
	# The art-director map slice (same sky, sun, terrain shader and flora as the hunt).
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
	var rifle: Node3D = _new_rifle(cam, not close)
	if close:
		rifle.transform = Transform3D(Basis.from_euler(Vector3(0.03, 0.05, -0.20)), Vector3(0.175, -0.170, 0.075))


func _shot_compare() -> void:
	_studio_lighting()
	# current game model, moved so its butt sits where the HD one has it (gun space)
	var old_holder: Node3D = Node3D.new()
	old_holder.position = Vector3(-0.40, 0.19 + 0.185, 0.38)
	_world.add_child(old_holder)
	var old_view: Node3D = (load("res://assets/models/weapons/rifle_308_view.tscn") as PackedScene).instantiate()
	old_view.position = Vector3(0.20, 0.0, 0.0)   # |x| = 0.20 turns the hip toe-in off
	old_holder.add_child(old_view)
	for arm: String in ["Gun/RightArm", "Gun/LeftArm"]:
		var node: Node3D = old_view.get_node_or_null(arm) as Node3D
		if node != null:
			node.visible = false
	var new_holder: Node3D = Node3D.new()
	new_holder.position = Vector3(0.0, -0.125, 0.0)
	_world.add_child(new_holder)
	var rifle: Node3D = _new_rifle(new_holder, false)
	rifle.call(&"set_cast_shadows", true)
	_camera(Vector3(1.75, 0.42, -0.02), Vector3(0.0, 0.0, -0.56), 23.0)
	_label("ATUAL  rifle_308_view.tscn  (MeshKit, cor por vertice; bracos ocultos)", Vector2(24, 18))
	var stats: Dictionary = RifleHD.get_stats()
	_label("NOVO  showcase/rifle_308_hd.gd  (%d triangulos, %d materiais)" % [int(stats["triangles"]), int(stats["materials"])], Vector2(24, 372))


## The five guns side by side from the right, same scale (orthographic), butts aligned: 2 columns x 3 rows of the
## frame (carbine, shotgun, .308 | .30-06, .338). Meant for a 960x540 window.
func _shot_lineup() -> void:
	_studio_lighting()
	var ids: Array[String] = ["carbine_22", "shotgun_12", "rifle_308", "rifle_3006", "rifle_338"]
	var view_h: float = 1.375
	var col_w: float = view_h * 16.0 / 9.0 * 0.5
	for i in ids.size():
		var col: int = i / 3
		var row: int = i % 3
		var gun: Node3D = (load("res://assets/models/weapons/showcase/%s_hd.gd" % ids[i]) as GDScript).new()
		_world.add_child(gun)
		gun.call(&"set_hip_pose", false)
		gun.call(&"set_cast_shadows", true)
		# screen right = -z, so the butt of the left column sits at the left edge
		gun.position = Vector3(0.0, view_h / 3.0 * (1.0 - float(row)) + 0.02, col_w - 0.04 if col == 0 else -0.04)
		var lbl: Label = Label.new()
		lbl.text = ids[i]
		lbl.position = Vector2(12.0 + 640.0 * float(col), 8.0 + 240.0 * float(row))
		lbl.add_theme_font_size_override(&"font_size", 16)
		lbl.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.85))
		_overlay.add_child(lbl)
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_h
	cam.near = 0.05
	cam.far = 20.0
	_world.add_child(cam)
	cam.look_at_from_position(Vector3(4.0, 0.0, 0.0), Vector3.ZERO, Vector3.UP)
	cam.make_current()


func _label(text: String, pos: Vector2) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override(&"font_size", 20)
	lbl.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.92))
	lbl.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override(&"outline_size", 5)
	_overlay.add_child(lbl)
