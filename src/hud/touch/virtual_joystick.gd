class_name TouchJoystick
extends Control
## (The contract calls this class VirtualJoystick; Godot 4.7 ships a native class with that name.)
## Floating analog stick. TouchControls feeds it touch positions by finger index; it drives the
## move_* actions with analog strength and the sprint action (stick > 90% for 0.3 s).

const RADIUS_PX: float = 90.0
const KNOB_RADIUS_PX: float = 42.0
const EDGE_MARGIN_PX: float = 24.0
const SPRINT_THRESHOLD: float = 0.9
const SPRINT_HOLD_S: float = 0.3
const SPRINT_RELEASE_THRESHOLD: float = 0.6
const COLOR_BASE: Color = Color(1.0, 1.0, 1.0, 0.16)
const COLOR_RING: Color = Color(1.0, 1.0, 1.0, 0.5)
const COLOR_KNOB: Color = Color(1.0, 1.0, 1.0, 0.45)

## Where the stick rests (faint hint) while nobody touches it.
var rest_center: Vector2 = Vector2(190.0, 560.0)

var _finger: int = -1
var _origin: Vector2 = Vector2.ZERO
var _vec: Vector2 = Vector2.ZERO     # x right, y up on screen (= forward), length <= 1
var _sprint_t: float = 0.0
var _sprinting: bool = false
var _base_tex: Texture2D = null
var _knob_tex: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if AssetLoader.exists(ScenePaths.icon(&"joystick_base")):
		_base_tex = AssetLoader.load_resource(ScenePaths.icon(&"joystick_base")) as Texture2D
	if AssetLoader.exists(ScenePaths.icon(&"joystick_knob")):
		_knob_tex = AssetLoader.load_resource(ScenePaths.icon(&"joystick_knob")) as Texture2D


func is_active() -> bool:
	return _finger != -1


func get_finger() -> int:
	return _finger


func get_vector() -> Vector2:
	return _vec


func is_sprinting() -> bool:
	return _sprinting


func begin(finger: int, pos: Vector2) -> void:
	_finger = finger
	var lo: float = RADIUS_PX + EDGE_MARGIN_PX
	_origin = Vector2(maxf(pos.x, lo), minf(pos.y, size.y - lo))
	_set_from_position(pos)


func drag(pos: Vector2) -> void:
	_set_from_position(pos)


func end() -> void:
	_finger = -1
	_vec = Vector2.ZERO
	_sprint_t = 0.0
	_sprinting = false
	_apply_actions()
	queue_redraw()


func _set_from_position(pos: Vector2) -> void:
	_vec = ((pos - _origin) / RADIUS_PX * Vector2(1.0, -1.0)).limit_length(1.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _finger == -1:
		return
	if _vec.length() >= SPRINT_THRESHOLD:
		_sprint_t += delta
		if _sprint_t >= SPRINT_HOLD_S:
			_sprinting = true
	elif _vec.length() < SPRINT_RELEASE_THRESHOLD:
		_sprint_t = 0.0
		_sprinting = false
	_apply_actions()


func _apply_actions() -> void:
	_set_axis(&"move_forward", maxf(_vec.y, 0.0))
	_set_axis(&"move_back", maxf(-_vec.y, 0.0))
	_set_axis(&"move_right", maxf(_vec.x, 0.0))
	_set_axis(&"move_left", maxf(-_vec.x, 0.0))
	if _sprinting:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _set_axis(action_name: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action_name, strength)
	else:
		Input.action_release(action_name)


func _draw() -> void:
	var center: Vector2 = _origin if _finger != -1 else rest_center
	var knob: Vector2 = center + Vector2(_vec.x, -_vec.y) * RADIUS_PX
	var idle_mult: float = 1.0 if _finger != -1 else 0.55
	if _base_tex != null:
		draw_texture_rect(_base_tex, Rect2(center - Vector2.ONE * RADIUS_PX, Vector2.ONE * RADIUS_PX * 2.0),
			false, Color(1, 1, 1, idle_mult))
	else:
		draw_circle(center, RADIUS_PX, Color(COLOR_BASE, COLOR_BASE.a * idle_mult))
		draw_arc(center, RADIUS_PX, 0.0, TAU, 48, Color(COLOR_RING, COLOR_RING.a * idle_mult), 3.0, true)
	if _knob_tex != null:
		draw_texture_rect(_knob_tex, Rect2(knob - Vector2.ONE * KNOB_RADIUS_PX, Vector2.ONE * KNOB_RADIUS_PX * 2.0),
			false, Color(1, 1, 1, idle_mult))
	else:
		draw_circle(knob, KNOB_RADIUS_PX, Color(COLOR_KNOB, COLOR_KNOB.a * idle_mult))
		if _sprinting:
			draw_arc(knob, KNOB_RADIUS_PX, 0.0, TAU, 32, Color("#F2C12E"), 4.0, true)
