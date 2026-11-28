extends SceneTree
## Renders the shop / loadout weapon portraits res://assets/ui/weapons/<weapon_id>.png (ScenePaths.weapon_art)
## from the HD procedural gun models (assets/models/weapons/showcase/<id>_hd.gd), then quits by itself.
## The PNGs are the output of this tool: never edit them by hand, re-run it.
##
## Needs a window (no --headless). Offline only, so it uses Forward+ (the game stays on Compatibility).
## From the project root:
##   tools/godot.sh --path . --rendering-method forward_plus --windowed --resolution 640x360 \
##       -s res://tools/render_weapon_art.gd
##   tools/godot.sh --headless --path . --import      # re-imports the PNGs (lossy WebP + mipmaps)
## Options after `--`:
##   --only=rifle_338,shotgun_12   render only these weapons
##   --out=C:/abs/dir              output folder (default res://assets/ui/weapons)
##   --preview=C:/abs/dir          also save each portrait over a dark card (display size and full size) + a sheet
##
## Look: golden-hour spot key from the upper left pooling on the action, strong amber rim from behind that
## outlines the top edges, warm brown fill and an amber kicker from below, dark warm studio sky with softbox
## strips for the gloss and metal reflections, soft amber halo in the alpha lifted above the gun.
## Framing: orthographic, from the gun's right side (+x in gun space): butt plate on the left, muzzle on the
## right, bore horizontal; every gun fills FILL_WIDTH of the width (same convention for the five).
## Rendered SUPERSAMPLE times larger without MSAA and downsampled premultiplied, so edges have no dark fringe.

const KNIFE_PORTRAIT_LEVEL: int = 4
const WEAPON_IDS: PackedStringArray = ["carbine_22", "shotgun_12", "rifle_308", "rifle_3006", "rifle_338", "knife"]
const MODEL_PATH: String = "res://assets/models/weapons/showcase/%s_hd.gd"
const DEFAULT_OUT: String = "res://assets/ui/weapons"
const OUT_SIZE: Vector2i = Vector2i(1024, 512)
const SUPERSAMPLE: int = 4
const FILL_WIDTH: float = 0.92
const SETTLE_FRAMES: int = 30
const HARD_TIMEOUT_SEC: float = 240.0
const SHADOW_ATLAS: int = 8192

# Lights. `from` = direction toward the light in gun space (camera on +x, screen left = +z = butt, up = +y).
# Key: a spot up and to the left of the camera, aimed a bit behind the middle of the gun, so the light pools
# on the action and the grip and falls off toward the muzzle and the belly of the stock.
const KEY_OFFSET: Vector3 = Vector3(1.25, 1.35, 0.85)
const KEY_AIM_TOWARD_BUTT: float = 0.16     # fraction of the gun length
const KEY_COLOR: Color = Color(1.0, 0.88, 0.74)
const KEY_ENERGY: float = 4.0
const KEY_ANGLE: float = 28.0
const KEY_ANGLE_FALLOFF: float = 1.0
# direction of the key softbox in the studio sky (reflections only)
const KEY_FROM: Vector3 = Vector3(0.50, 0.90, 0.50)
const RIM_FROM: Vector3 = Vector3(-0.80, 0.62, 0.20)
const RIM_COLOR: Color = Color(1.0, 0.56, 0.17)
const RIM_ENERGY: float = 6.0
const RIM2_FROM: Vector3 = Vector3(-0.70, 0.45, -0.55)
const RIM2_COLOR: Color = Color(1.0, 0.64, 0.25)
const RIM2_ENERGY: float = 2.0
const FILL_FROM: Vector3 = Vector3(0.35, -0.94, 0.0)
const FILL_COLOR: Color = Color(0.70, 0.40, 0.22)
const FILL_ENERGY: float = 1.0
# kicker: warm bounce from the sunlit ground behind the gun, a thin edge along the belly
const KICK_FROM: Vector3 = Vector3(-0.75, -0.55, 0.10)
const KICK_COLOR: Color = Color(1.0, 0.50, 0.18)
const KICK_ENERGY: float = 1.6
const AMBIENT_ENERGY: float = 0.3
const EXPOSURE: float = 1.1
const TONEMAP_WHITE: float = 6.0
const CONTRAST: float = 1.18
const SATURATION: float = 0.94

# Halo in the alpha: amber, two radii (fraction of the output size the mask is shrunk to before blurring back).
const HALO_COLOR: Color = Color(0.96, 0.60, 0.17)
const HALO_TIGHT_DIV: int = 6
const HALO_WIDE_DIV: int = 16
const HALO_TIGHT: float = 0.22
const HALO_WIDE: float = 0.34
# the halo is lifted (px) so it glows mostly above the gun, as a back light from above would
const HALO_TIGHT_LIFT: int = 3
const HALO_WIDE_LIFT: int = 9
const HALO_EDGE_FADE_PX: float = 26.0

# Previews (only with --preview): card colour of the shop and its display size.
const CARD_COLOR: Color = Color(0.118, 0.090, 0.071)
const CARD_SIZE: Vector2i = Vector2i(280, 140)

const STUDIO_SKY: String = """
shader_type sky;
// Warm golden-hour studio: never rendered as background (the viewport is transparent), only lights the gun
// through ambient and reflections. Dark warm floor, amber sunset band behind the gun, warm softbox up front.
uniform vec3 key_dir;
uniform vec3 rim_dir;

float softbox(vec3 d, vec3 center, vec2 half_size) {
	float t = dot(d, center);
	if (t <= 0.0) {
		return 0.0;
	}
	vec3 right = normalize(cross(center, vec3(0.0, 1.0, 0.0) + vec3(0.001)));
	vec3 up = normalize(cross(right, center));
	vec3 p = d / t;
	vec2 q = abs(vec2(dot(p, right), dot(p, up)));
	vec2 e = smoothstep(half_size, half_size * 0.55, q);
	return e.x * e.y;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = mix(vec3(0.008, 0.005, 0.003), vec3(0.035, 0.020, 0.011), smoothstep(-0.7, 0.9, d.y));
	// sunset band low behind the gun (-x)
	float band = exp(-pow((d.y - 0.12) / 0.20, 2.0)) * smoothstep(0.2, -0.7, d.x);
	col += vec3(1.0, 0.46, 0.12) * 1.2 * band;
	// warm softboxes: long sheen strip just above the camera (gloss band along the stock and the barrel),
	// key up front, amber strip above and behind
	col += vec3(1.0, 0.90, 0.78) * 4.0 * softbox(d, normalize(vec3(0.82, 0.55, 0.12)), vec2(2.2, 0.10));
	col += vec3(1.0, 0.86, 0.70) * 0.8 * softbox(d, normalize(key_dir), vec2(0.6, 0.25));
	col += vec3(1.0, 0.58, 0.20) * 2.6 * softbox(d, normalize(rim_dir), vec2(1.4, 0.22));
	COLOR = col;
}
"""

var _out_dir: String = DEFAULT_OUT
var _preview_dir: String = ""
var _ids: PackedStringArray = WEAPON_IDS


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_ids = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--preview="):
			_preview_dir = arg.trim_prefix("--preview=")
	create_timer(HARD_TIMEOUT_SEC).timeout.connect(_on_hard_timeout)
	if DisplayServer.get_name() == "headless":
		printerr("render_weapon_art: needs a window (run without --headless)")
		quit(2)
		return
	for id in _ids:
		if not WEAPON_IDS.has(id):
			printerr("render_weapon_art: unknown weapon '%s'" % id)
			quit(2)
			return
	_run.call_deferred()


func _on_hard_timeout() -> void:
	printerr("render_weapon_art: timed out after %.0f s" % HARD_TIMEOUT_SEC)
	quit(1)


func _run() -> void:
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	if not _preview_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_preview_dir)
	var portraits: Array[Image] = []
	for id in _ids:
		var image: Image = await _render(id)
		if image == null:
			quit(1)
			return
		var path: String = _out_dir.path_join("%s.png" % id)
		var err: Error = image.save_png(path)
		if err != OK:
			printerr("render_weapon_art: could not save %s (error %d)" % [path, err])
			quit(1)
			return
		print("render_weapon_art: saved %s %s" % [path, _coverage(image)])
		if not _preview_dir.is_empty():
			_save_previews(id, image)
			portraits.append(image)
	if not _preview_dir.is_empty():
		_save_sheet(portraits)
	quit(0)


# --- render -------------------------------------------------------------------------------------

func _render(id: String) -> Image:
	var vp: SubViewport = SubViewport.new()
	vp.size = OUT_SIZE * SUPERSAMPLE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	vp.add_child(_environment())
	vp.add_child(_light(RIM_FROM, RIM_COLOR, RIM_ENERGY, true))
	vp.add_child(_light(RIM2_FROM, RIM2_COLOR, RIM2_ENERGY, false))
	vp.add_child(_light(FILL_FROM, FILL_COLOR, FILL_ENERGY, false))
	vp.add_child(_light(KICK_FROM, KICK_COLOR, KICK_ENERGY, false))

	var script: GDScript = load(MODEL_PATH % id) as GDScript
	if script == null:
		printerr("render_weapon_art: model not found for %s" % id)
		return null
	var gun: Node3D = script.new()
	if gun.has_method(&"set_level"):
		gun.call(&"set_level", KNIFE_PORTRAIT_LEVEL)   # the knife has four tiers: the portrait shows the premium one
	vp.add_child(gun)   # _ready builds the model
	gun.call(&"set_hip_pose", false)
	gun.call(&"set_cast_shadows", true)
	gun.set_process(false)

	var bounds: AABB = _bounds(gun)
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = bounds.size.z / FILL_WIDTH
	cam.near = 0.05
	cam.far = 10.0
	var center: Vector3 = bounds.get_center()
	var aim: Vector3 = Vector3(0.0, center.y, center.z + bounds.size.z * KEY_AIM_TOWARD_BUTT)
	var key: SpotLight3D = SpotLight3D.new()
	key.light_color = KEY_COLOR
	key.light_energy = KEY_ENERGY
	key.spot_range = 8.0
	key.spot_attenuation = 0.6
	key.spot_angle = KEY_ANGLE
	key.spot_angle_attenuation = KEY_ANGLE_FALLOFF
	key.shadow_enabled = true
	key.shadow_bias = 0.01
	key.shadow_normal_bias = 0.6
	key.shadow_blur = 1.0
	vp.add_child(key)
	key.look_at_from_position(aim + KEY_OFFSET, aim, Vector3.UP)
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(bounds.end.x + 1.5, center.y, center.z), Vector3(center.x, center.y, center.z), Vector3.UP)
	cam.make_current()

	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot: Image = vp.get_texture().get_image()
	vp.queue_free()
	return _finish(shot)


func _environment() -> WorldEnvironment:
	var shader: Shader = Shader.new()
	shader.code = STUDIO_SKY
	var sky_mat: ShaderMaterial = ShaderMaterial.new()
	sky_mat.shader = shader
	sky_mat.set_shader_parameter(&"key_dir", KEY_FROM.normalized())
	sky_mat.set_shader_parameter(&"rim_dir", RIM_FROM.normalized())
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = EXPOSURE
	env.tonemap_white = TONEMAP_WHITE
	env.adjustment_enabled = true
	env.adjustment_contrast = CONTRAST
	env.adjustment_saturation = SATURATION
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	return we


func _light(from: Vector3, color: Color, energy: float, shadows: bool) -> DirectionalLight3D:
	var l: DirectionalLight3D = DirectionalLight3D.new()
	l.basis = Basis.looking_at(-from.normalized(), Vector3.UP)
	l.light_color = color
	l.light_energy = energy
	l.shadow_enabled = shadows
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	l.directional_shadow_max_distance = 4.0
	l.shadow_bias = 0.01
	l.shadow_normal_bias = 0.4
	l.shadow_blur = 1.0
	return l


## Union of the mesh bounds of the gun (gun space = world space here: hip pose off, gun at the origin).
func _bounds(gun: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [gun]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


# --- post: supersample down, halo -----------------------------------------------------------------

## Downsamples the supersampled shot (premultiplied, so the edges get no dark fringe) and adds the halo.
func _finish(shot: Image) -> Image:
	shot.convert(Image.FORMAT_RGBA8)
	shot.premultiply_alpha()
	shot.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var gun: PackedByteArray = shot.get_data()
	var tight: PackedByteArray = _blurred_alpha(shot, HALO_TIGHT_DIV)
	var wide: PackedByteArray = _blurred_alpha(shot, HALO_WIDE_DIV)
	var out: PackedByteArray = PackedByteArray()
	out.resize(gun.size())
	var hr: float = HALO_COLOR.r
	var hg: float = HALO_COLOR.g
	var hb: float = HALO_COLOR.b
	for y in OUT_SIZE.y:
		var fy: float = minf(float(y), float(OUT_SIZE.y - 1 - y)) / HALO_EDGE_FADE_PX
		var row_t: int = mini(y + HALO_TIGHT_LIFT, OUT_SIZE.y - 1) * OUT_SIZE.x
		var row_w: int = mini(y + HALO_WIDE_LIFT, OUT_SIZE.y - 1) * OUT_SIZE.x
		for x in OUT_SIZE.x:
			var i: int = y * OUT_SIZE.x + x
			var o: int = i * 4
			var a: float = gun[o + 3] / 255.0
			var fade: float = clampf(minf(fy, minf(float(x), float(OUT_SIZE.x - 1 - x)) / HALO_EDGE_FADE_PX), 0.0, 1.0)
			var h: float = clampf(tight[row_t + x] / 255.0 * HALO_TIGHT + wide[row_w + x] / 255.0 * HALO_WIDE, 0.0, 1.0) * fade * fade
			h *= 1.0 - a
			var oa: float = a + h
			if oa <= 0.0:
				continue
			var inv: float = 255.0 / oa
			out[o] = clampi(roundi((gun[o] / 255.0 + hr * h) * inv), 0, 255)
			out[o + 1] = clampi(roundi((gun[o + 1] / 255.0 + hg * h) * inv), 0, 255)
			out[o + 2] = clampi(roundi((gun[o + 2] / 255.0 + hb * h) * inv), 0, 255)
			out[o + 3] = clampi(roundi(oa * 255.0), 0, 255)
	return Image.create_from_data(OUT_SIZE.x, OUT_SIZE.y, false, Image.FORMAT_RGBA8, out)


## Alpha of `img` blurred by shrinking it `div` times and scaling it back up; one byte per pixel.
func _blurred_alpha(img: Image, div: int) -> PackedByteArray:
	var mask: Image = img.duplicate() as Image
	mask.convert(Image.FORMAT_LA8)
	@warning_ignore("integer_division")
	mask.resize(maxi(OUT_SIZE.x / div, 1), maxi(OUT_SIZE.y / div, 1), Image.INTERPOLATE_LANCZOS)
	mask.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_CUBIC)
	var la: PackedByteArray = mask.get_data()
	var out: PackedByteArray = PackedByteArray()
	out.resize(OUT_SIZE.x * OUT_SIZE.y)
	for i in out.size():
		out[i] = la[i * 2 + 1]
	return out


## "bbox=(x0,y0)-(x1,y1) width=..%" of the opaque part (alpha >= 128) and whether anything touches the edge.
func _coverage(img: Image) -> String:
	var x0: int = OUT_SIZE.x
	var y0: int = OUT_SIZE.y
	var x1: int = -1
	var y1: int = -1
	var edge: bool = false
	var data: PackedByteArray = img.get_data()
	for y in OUT_SIZE.y:
		for x in OUT_SIZE.x:
			var a: int = data[(y * OUT_SIZE.x + x) * 4 + 3]
			if a > 0 and (x == 0 or y == 0 or x == OUT_SIZE.x - 1 or y == OUT_SIZE.y - 1):
				edge = true
			if a >= 128:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return "bbox=(%d,%d)-(%d,%d) width=%.1f%% touches_edge=%s" % [x0, y0, x1, y1, 100.0 * float(x1 - x0 + 1) / OUT_SIZE.x, edge]


# --- previews ---------------------------------------------------------------------------------------

func _over_card(img: Image) -> Image:
	var card: Image = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	card.fill(CARD_COLOR)
	card.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	return card


func _save_previews(id: String, img: Image) -> void:
	var large: Image = _over_card(img)
	large.save_png(_preview_dir.path_join("%s_large.png" % id))
	var small: Image = large.duplicate() as Image
	small.resize(CARD_SIZE.x, CARD_SIZE.y, Image.INTERPOLATE_LANCZOS)
	small.save_png(_preview_dir.path_join("%s_card.png" % id))


## All cards at display size in one column (and the same at 2x on the right, as on a dense phone screen).
func _save_sheet(portraits: Array[Image]) -> void:
	if portraits.is_empty():
		return
	var pad: int = 12
	var w: int = pad * 3 + CARD_SIZE.x * 3
	var h: int = pad + (CARD_SIZE.y * 2 + pad) * portraits.size()
	var sheet: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.045, 0.035))
	for i in portraits.size():
		var y: int = pad + i * (CARD_SIZE.y * 2 + pad)
		var small: Image = _over_card(portraits[i])
		small.resize(CARD_SIZE.x, CARD_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, CARD_SIZE), Vector2i(pad, y))
		var big: Image = _over_card(portraits[i])
		big.resize(CARD_SIZE.x * 2, CARD_SIZE.y * 2, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(big, Rect2i(Vector2i.ZERO, CARD_SIZE * 2), Vector2i(pad * 2 + CARD_SIZE.x, y))
	sheet.save_png(_preview_dir.path_join("sheet.png"))
