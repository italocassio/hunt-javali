class_name ScopeOverlay
extends Control
## Full-screen scope / binocular view (docs §7.9). Uses assets/ui/scope_overlay.gdshader when it
## exists, otherwise draws a black mask with a circular hole and a cross.

const VIGNETTE_RADIUS: float = 0.42
const COLOR_MASK: Color = Color.BLACK
const COLOR_RETICLE: Color = Color(0.05, 0.05, 0.05, 0.95)
const MIL_DOT_COUNT: int = 4
const MIL_DOT_STEP_PX: float = 22.0

var reticle_kind: int = 0
var show_reticle: bool = true

var _alpha: float = 0.0
var _rect: ColorRect = null
var _material: ShaderMaterial = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	var shader: Shader = AssetLoader.load_resource(ScenePaths.SCOPE_SHADER) as Shader
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_rect = ColorRect.new()
		_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.material = _material
		add_child(_rect)


func is_using_shader() -> bool:
	return _rect != null


func get_alpha() -> float:
	return _alpha


func set_state(alpha: float, p_reticle_kind: int, p_show_reticle: bool) -> void:
	_alpha = clampf(alpha, 0.0, 1.0)
	reticle_kind = p_reticle_kind
	show_reticle = p_show_reticle
	visible = _alpha > 0.01
	if not visible:
		return
	modulate.a = _alpha
	if _material != null:
		_material.set_shader_parameter("reticle_kind", float(reticle_kind))
		_material.set_shader_parameter("vignette_radius", VIGNETTE_RADIUS)
		_material.set_shader_parameter("reticle_color",
			COLOR_RETICLE if show_reticle else Color(0.0, 0.0, 0.0, 0.0))
	else:
		queue_redraw()


func _draw() -> void:
	if _rect != null:
		return
	var c: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * VIGNETTE_RADIUS * 2.0 * 0.5 + minf(size.x, size.y) * 0.08
	var band: float = c.length() - radius + 4.0
	# Soft inner edge: a few translucent rings, then the opaque mask.
	for i: int in 4:
		var ring_r: float = radius - float(i) * 6.0
		var ring_color: Color = Color(0.0, 0.0, 0.0, 0.18)
		draw_arc(c, ring_r, 0.0, TAU, 96, ring_color, 6.0)
	draw_arc(c, radius + band * 0.5, 0.0, TAU, 128, COLOR_MASK, band)
	if not show_reticle:
		return
	var span: float = radius
	draw_line(c - Vector2(span, 0.0), c + Vector2(span, 0.0), COLOR_RETICLE, 2.0)
	draw_line(c - Vector2(0.0, span), c + Vector2(0.0, span), COLOR_RETICLE, 2.0)
	if reticle_kind == 1:
		for i: int in range(1, MIL_DOT_COUNT + 1):
			var off: float = MIL_DOT_STEP_PX * float(i)
			for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_circle(c + dir * off, 2.5, COLOR_RETICLE)
	else:
		draw_circle(c, 3.0, COLOR_RETICLE)
