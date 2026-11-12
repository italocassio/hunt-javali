class_name TouchJoystick
extends Control
## (The contract calls this class VirtualJoystick; Godot 4.7 ships a native class with that name.)
## FIXED analog stick in the bottom-left corner (shooter-game convention): it always shows at its rest
## position and only a touch inside the generous active area grabs it. TouchControls feeds it positions
## by finger slot; it drives the move_* actions with analog strength and the sprint action:
##   - stick > 90% for 0.3 s sprints while held;
##   - pushing far beyond the ring upwards locks the run (stays running with the finger lifted).

const KNOB_RADIUS_PX: float = 42.0
const SPRINT_THRESHOLD: float = 0.9
const SPRINT_HOLD_S: float = 0.3
const SPRINT_RELEASE_THRESHOLD: float = 0.6
const COLOR_BASE: Color = Color(1.0, 1.0, 1.0, 0.16)
const COLOR_RING: Color = Color(1.0, 1.0, 1.0, 0.5)
const COLOR_KNOB: Color = Color(1.0, 1.0, 1.0, 0.45)
const COLOR_LOCK: Color = Color("#F2C12E")

## Fixed stick centre (set by TouchControls on layout).
var rest_center: Vector2 = Vector2(190.0, 560.0)
## Feel numbers, overwritten from data/game.json (player.touch_*) in _ready.
var radius_px: float = 90.0
var deadzone: float = 0.12
var active_mult: float = 1.7
var run_lock_mult: float = 1.8
## True while the run is locked (finger may be lifted).
var run_locked: bool = false

var _finger: int = 0          # which finger (any int is valid; never a sentinel)
var _active: bool = false     # whether a finger owns the stick
var _vec: Vector2 = Vector2.ZERO     # x right, y up on screen (= forward), length <= 1, deadzone applied
var _raw_len: float = 0.0     # unclamped distance / radius, drives the lock indicator
var _sprint_t: float = 0.0
var _sprinting: bool = false
var _base_tex: Texture2D = null
var _knob_tex: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var cfg: Dictionary = Data.get_game().get("player", {})
	radius_px = float(cfg.get("touch_joystick_radius_px", radius_px))
	deadzone = float(cfg.get("touch_joystick_deadzone", deadzone))
	active_mult = float(cfg.get("touch_joystick_active_mult", active_mult))
	run_lock_mult = float(cfg.get("touch_run_lock_mult", run_lock_mult))
	if AssetLoader.exists(ScenePaths.icon(&"joystick_base")):
		_base_tex = AssetLoader.load_resource(ScenePaths.icon(&"joystick_base")) as Texture2D
	if AssetLoader.exists(ScenePaths.icon(&"joystick_knob")):
		_knob_tex = AssetLoader.load_resource(ScenePaths.icon(&"joystick_knob")) as Texture2D


func is_active() -> bool:
	return _active


func owns(finger: int) -> bool:
	return _active and _finger == finger


func get_finger() -> int:
	return _finger


func get_vector() -> Vector2:
	return _vec


func is_sprinting() -> bool:
	return _sprinting or run_locked


## True if a touch at pos should grab the stick (inside the generous active area).
func contains_point(pos: Vector2) -> bool:
	return pos.distance_to(rest_center) <= radius_px * active_mult


func begin(finger: int, pos: Vector2) -> void:
	_finger = finger
	_active = true
	run_locked = false          # touching the stick again cancels a locked run
	_set_from_position(pos)


func drag(pos: Vector2) -> void:
	_set_from_position(pos)


func end() -> void:
	_active = false
	_finger = 0
	_vec = Vector2.ZERO
	_raw_len = 0.0
	_sprint_t = 0.0
	_sprinting = false
	_apply_actions()
	queue_redraw()


func unlock_run() -> void:
	if run_locked:
		run_locked = false
		if not _active:
			_apply_actions()
		queue_redraw()


func _set_from_position(pos: Vector2) -> void:
	var raw: Vector2 = (pos - rest_center) / radius_px * Vector2(1.0, -1.0)
	_raw_len = raw.length()
	var v: Vector2 = raw.limit_length(1.0)
	if v.length() < deadzone:
		v = Vector2.ZERO
	else:
		v = v.normalized() * ((v.length() - deadzone) / (1.0 - deadzone))
	_vec = v
	# Run lock: pushed well past the ring, and mostly upwards.
	if not run_locked and raw.y > run_lock_mult and absf(raw.x) < raw.y:
		run_locked = true
	elif run_locked and raw.y < (1.0 + (run_lock_mult - 1.0) * 0.2):
		run_locked = false   # pulled back into the ring while still touching: cancel the lock
	queue_redraw()


func _process(delta: float) -> void:
	if not _active:
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
	var forward: float = maxf(_vec.y, 0.0)
	if run_locked:
		forward = 1.0
	_set_axis(&"move_forward", forward)
	_set_axis(&"move_back", maxf(-_vec.y, 0.0) if not run_locked else 0.0)
	_set_axis(&"move_right", maxf(_vec.x, 0.0))
	_set_axis(&"move_left", maxf(-_vec.x, 0.0))
	if _sprinting or run_locked:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _set_axis(action_name: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action_name, strength)
	else:
		Input.action_release(action_name)


func _draw() -> void:
	var center: Vector2 = rest_center
	var knob: Vector2 = center + Vector2(_vec.x, -_vec.y) * radius_px
	if _active:
		# Show the raw finger offset up to the ring so the knob follows the thumb.
		knob = center + Vector2(_vec.x, -_vec.y) * radius_px
	var idle_mult: float = 1.0 if _active else 0.6
	if _base_tex != null:
		draw_texture_rect(_base_tex, Rect2(center - Vector2.ONE * radius_px, Vector2.ONE * radius_px * 2.0),
			false, Color(1, 1, 1, idle_mult))
	else:
		draw_circle(center, radius_px, Color(COLOR_BASE, COLOR_BASE.a * idle_mult))
		draw_arc(center, radius_px, 0.0, TAU, 48, Color(COLOR_RING, COLOR_RING.a * idle_mult), 3.0, true)
	if _knob_tex != null:
		draw_texture_rect(_knob_tex, Rect2(knob - Vector2.ONE * KNOB_RADIUS_PX, Vector2.ONE * KNOB_RADIUS_PX * 2.0),
			false, Color(1, 1, 1, idle_mult))
	else:
		draw_circle(knob, KNOB_RADIUS_PX, Color(COLOR_KNOB, COLOR_KNOB.a * idle_mult))
		if _sprinting or run_locked:
			draw_arc(knob, KNOB_RADIUS_PX, 0.0, TAU, 32, COLOR_LOCK, 4.0, true)
	_draw_run_indicator(center)


## Chevrons above the ring: a faint hint while pushing towards the lock, solid gold while locked.
func _draw_run_indicator(center: Vector2) -> void:
	var progress: float = clampf((_raw_len - 1.0) / maxf(run_lock_mult - 1.0, 0.1), 0.0, 1.0) if _active else 0.0
	if not run_locked and progress <= 0.05:
		return
	var color: Color = COLOR_LOCK if run_locked else Color(1.0, 1.0, 1.0, 0.35 + 0.4 * progress)
	var top: float = center.y - radius_px - 26.0
	for i: int in 2:
		var y: float = top - float(i) * 16.0
		draw_polyline(PackedVector2Array([Vector2(center.x - 16.0, y + 8.0), Vector2(center.x, y - 4.0),
			Vector2(center.x + 16.0, y + 8.0)]), Color(0.0, 0.0, 0.0, 0.6), 8.0)
		draw_polyline(PackedVector2Array([Vector2(center.x - 16.0, y + 8.0), Vector2(center.x, y - 4.0),
			Vector2(center.x + 16.0, y + 8.0)]), color, 4.0)
