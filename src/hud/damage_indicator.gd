class_name DamageIndicator
extends Control
## Directional damage arcs around the crosshair (fade over player.damage_indicator_s) plus a red
## edge flash on hit and a slow pulse while health is low.

const RING_RADIUS_PX: float = 170.0
const ARC_SPAN_RAD: float = 0.7
const ARC_WIDTH_PX: float = 14.0
const COLOR_ARC: Color = Color("#D9452B")
const FLASH_FADE_RATE: float = 2.5
const FLASH_PER_DAMAGE: float = 0.02
const FLASH_MAX: float = 0.55
const LOW_PULSE_HZ: float = 0.9
const LOW_PULSE_ALPHA: float = 0.25
const VIGNETTE_SHADER: String = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.85, 0.12, 0.08, 1.0);
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.25, 0.75, length(d) * 1.4142);
	COLOR = vec4(tint.rgb, v * strength);
}
"""

var duration_s: float = 1.2
var low_health: bool = false

var _hits: Array[Dictionary] = []    # {pos: Vector3, age: float}
var _flash: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _vignette: ColorRect = ColorRect.new()
var _material: ShaderMaterial = ShaderMaterial.new()
var _low_t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = VIGNETTE_SHADER
	_material.shader = shader
	_vignette.material = _material
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)


func add_hit(amount: float, source_position: Vector3) -> void:
	_hits.append({"pos": source_position, "age": 0.0})
	_flash = minf(_flash + amount * FLASH_PER_DAMAGE + 0.2, FLASH_MAX)


func set_player_state(origin: Vector3, yaw_rad: float) -> void:
	_origin = origin
	_yaw = yaw_rad


func get_active_count() -> int:
	return _hits.size()


func _process(delta: float) -> void:
	for i: int in range(_hits.size() - 1, -1, -1):
		_hits[i]["age"] = float(_hits[i]["age"]) + delta
		if float(_hits[i]["age"]) >= duration_s:
			_hits.remove_at(i)
	_flash = maxf(_flash - FLASH_FADE_RATE * delta * FLASH_MAX, 0.0)
	var strength: float = _flash
	if low_health:
		_low_t += delta
		strength = maxf(strength, (0.5 + 0.5 * sin(_low_t * TAU * LOW_PULSE_HZ)) * LOW_PULSE_ALPHA)
	_material.set_shader_parameter("strength", strength)
	if not _hits.is_empty():
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	for hit: Dictionary in _hits:
		var p: Vector3 = hit["pos"]
		# Angle on screen: 0 = up (ahead), clockwise positive.
		var to_src: float = atan2(p.x - _origin.x, -(p.z - _origin.z))
		var rel: float = wrapf(to_src - (-_yaw), -PI, PI)
		var screen_angle: float = rel - PI * 0.5   # draw_arc measures from +X
		var alpha: float = 1.0 - float(hit["age"]) / maxf(duration_s, 0.01)
		var color: Color = COLOR_ARC
		color.a = clampf(alpha * 1.4, 0.0, 1.0)
		draw_arc(center, RING_RADIUS_PX, screen_angle - ARC_SPAN_RAD * 0.5,
			screen_angle + ARC_SPAN_RAD * 0.5, 16, color, ARC_WIDTH_PX, true)
