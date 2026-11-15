extends ScrollContainer
## ScrollContainer that scrolls by dragging a finger anywhere on it, also when the drag starts on top of a
## Button, a card, a CheckButton or an OptionButton (those take the touch and the list never sees the drag).
## Built by UiKit.scroll_list(); no class_name on purpose (loaded through preload, no import cache needed).
##
## One finger reaches the GUI as TWO event streams that this node sees in _input, before any control:
## the mouse that Godot emulates from touch (InputEvent.DEVICE_ID_EMULATION, always first) and the raw
## InputEventScreenTouch / ScreenDrag of the same finger (Godot 4.7 buttons also react to those).
##   - press inside the list: both streams are swallowed and remembered (state PENDING);
##   - moved more than DRAG_DEADZONE_PX: state DRAGGING, the list scrolls and nothing reaches the controls;
##   - released inside the dead zone: it was a tap, the remembered presses and releases are replayed to the
##     GUI at the press position, so the control fires exactly as it would have without this node;
##   - released after a drag: the list keeps gliding with a short inertia.
## Real mouse (desktop: wheel, click, scrollbar) never matches the emulation device and is left alone.
## Scrollbars and text fields keep their own drag: a press that lands on them is not taken over at all.
## A slider is taken over like a button, but when the first real movement goes along the slider (horizontal for
## an HSlider) the held press is handed back to it, so a vertical swipe over a slider scrolls instead of moving it.

## Finger travel (viewport px) before a touch stops being a tap and becomes a scroll (about 8 dp on a phone).
const DRAG_DEADZONE_PX: float = 16.0
## Fling: exponential slow-down rate (1/s), speed limits (content px/s) and the finger idle time (s) that cancels it.
const INERTIA_FRICTION_PER_S: float = 4.0
const INERTIA_MIN_SPEED_PX_S: float = 40.0
const INERTIA_MAX_SPEED_PX_S: float = 6000.0
const FLING_MAX_IDLE_S: float = 0.08
## Weight of the newest sample in the smoothed finger velocity (0..1) and the shortest sample interval used (s).
const VELOCITY_SMOOTHING: float = 0.5
const MIN_SAMPLE_INTERVAL_S: float = 0.004
## The built-in touch scrolling is switched off by giving it a dead zone no screen can reach: it only sees the
## touch through controls that let it pass and would scroll twice.
const NATIVE_TOUCH_DEADZONE_PX: int = 1000000
const NO_FINGER: int = -1

enum Phase { IDLE, PENDING, DRAGGING }
enum Target { PLAIN, OWN_DRAG, SLIDER }

var _phase: Phase = Phase.IDLE
var _held: Array[InputEvent] = []         # swallowed press/release events of the current tap candidate
var _press_pos: Vector2 = Vector2.ZERO
var _press_global_pos: Vector2 = Vector2.ZERO
var _finger: int = NO_FINGER              # ScreenTouch index of the finger that owns the mouse emulation
var _last_pos: Vector2 = Vector2.ZERO
var _last_move_usec: int = 0
var _velocity: Vector2 = Vector2.ZERO     # content px per second
var _scroll_f: Vector2 = Vector2.ZERO     # scroll offset in floats: ScrollBar steps would round small moves away
var _flinging: bool = false
var _tap_blocked: bool = false            # the press only stopped a fling: it must not fire a control
var _tap_release_seen: bool = false       # the mouse release arrived, the tap replay is queued
var _slider_pressed: bool = false         # the press landed on a slider: a drag along it goes back to the slider
var _slider_vertical: bool = false
var _replaying: bool = false


func _ready() -> void:
	scroll_deadzone = NATIVE_TOUCH_DEADZONE_PX
	set_process(false)


func _exit_tree() -> void:
	_reset()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_reset()


func _input(event: InputEvent) -> void:
	if _replaying:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.device != InputEvent.DEVICE_ID_EMULATION or button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_on_mouse_press(button)
		else:
			_on_mouse_release(button)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _phase == Phase.IDLE:
			return
		if motion.device == InputEvent.DEVICE_ID_EMULATION:
			_on_motion(motion)
		elif motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			get_viewport().set_input_as_handled()   # the browser's own pointer stream of the same finger
	elif event is InputEventScreenTouch:
		_on_screen_touch(event)
	elif event is InputEventScreenDrag:
		if _finger != NO_FINGER and (event as InputEventScreenDrag).index == _finger:
			get_viewport().set_input_as_handled()


# --- Gesture ---

func _on_mouse_press(event: InputEventMouseButton) -> void:
	if _phase != Phase.IDLE or not _held.is_empty():
		_reset()   # a release was lost somewhere: start clean
	if get_viewport().is_input_handled() or not is_visible_in_tree():
		return
	if not _contains(event.position) or not _can_scroll():
		return
	var target: Target = _target_at(event.position)
	if target == Target.OWN_DRAG:
		return
	_held.append(event.duplicate())
	_press_pos = event.position
	_press_global_pos = event.global_position
	_last_pos = event.position
	_finger = NO_FINGER
	_tap_blocked = _flinging
	_tap_release_seen = false
	_slider_pressed = target == Target.SLIDER
	_stop_fling()
	_phase = Phase.PENDING
	get_viewport().set_input_as_handled()


func _on_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		# Godot emulates the mouse first and dispatches the touch right after: this is the sibling of that press.
		if _phase != Phase.IDLE and _finger == NO_FINGER:
			_finger = event.index
			_held.append(event.duplicate())
			get_viewport().set_input_as_handled()
		return
	if _finger == NO_FINGER or event.index != _finger:
		return
	get_viewport().set_input_as_handled()
	_finger = NO_FINGER
	if event.canceled:
		_reset()
	elif _phase == Phase.PENDING or _tap_release_seen:
		_held.append(event.duplicate())   # part of a tap: replayed with the rest


func _on_motion(event: InputEventMouseMotion) -> void:
	get_viewport().set_input_as_handled()
	if _phase == Phase.PENDING:
		var travel: Vector2 = event.position - _press_pos
		if travel.length() < DRAG_DEADZONE_PX:
			return
		if _slider_pressed and (absf(travel.y) > absf(travel.x)) == _slider_vertical:
			_hand_back_to_slider(event)
			return
		_phase = Phase.DRAGGING
		_held.clear()   # not a tap anymore
		_scroll_f = Vector2(get_h_scroll_bar().value, get_v_scroll_bar().value)
		_velocity = Vector2.ZERO
		_last_pos = event.position   # scrolling starts from here: the content does not jump by the dead zone
		_last_move_usec = Time.get_ticks_usec()
		return
	var now: int = Time.get_ticks_usec()
	var dt: float = maxf(float(now - _last_move_usec) / 1000000.0, MIN_SAMPLE_INTERVAL_S)
	var content_delta: Vector2 = _last_pos - event.position   # finger up = the scroll offset grows
	_last_pos = event.position
	_last_move_usec = now
	_velocity = _velocity.lerp(content_delta / dt, VELOCITY_SMOOTHING)
	_scroll_to(_scroll_f + content_delta)


func _on_mouse_release(event: InputEventMouseButton) -> void:
	if _phase == Phase.IDLE:
		return
	get_viewport().set_input_as_handled()
	var was_dragging: bool = _phase == Phase.DRAGGING
	_phase = Phase.IDLE
	if was_dragging:
		var idle_s: float = float(Time.get_ticks_usec() - _last_move_usec) / 1000000.0
		if idle_s <= FLING_MAX_IDLE_S and _velocity.length() >= INERTIA_MIN_SPEED_PX_S:
			_velocity = _velocity.limit_length(INERTIA_MAX_SPEED_PX_S)
			_flinging = true
			set_process(true)
		return
	if _tap_blocked:
		_held.clear()
		return
	_held.append(event.duplicate())
	_tap_release_seen = true
	_replay_tap.call_deferred()   # deferred: the touch release of the same finger is still on its way


## The drag belongs to the slider under the finger: it gets the held press at the original position and the
## motion that crossed the dead zone, then every later event of this finger reaches it untouched.
func _hand_back_to_slider(motion: InputEventMouseMotion) -> void:
	var events: Array[InputEvent] = _held
	_held = []
	_phase = Phase.IDLE
	_finger = NO_FINGER
	_slider_pressed = false
	var viewport: Viewport = get_viewport()
	_replaying = true
	for event: InputEvent in events:
		viewport.push_input(event, true)
	viewport.push_input(motion.duplicate(), true)
	_replaying = false
	viewport.set_input_as_handled()   # the original motion was just delivered by the replay


## A tap: the GUI gets hover + the held presses and releases at the press position, in the original order.
func _replay_tap() -> void:
	var events: Array[InputEvent] = _held
	_held = []
	_tap_release_seen = false
	if not is_inside_tree() or events.is_empty():
		return
	var viewport: Viewport = get_viewport()
	var hover: InputEventMouseMotion = InputEventMouseMotion.new()
	hover.device = InputEvent.DEVICE_ID_EMULATION
	hover.position = _press_pos
	hover.global_position = _press_global_pos
	_replaying = true
	viewport.push_input(hover, true)
	for event: InputEvent in events:
		if event is InputEventMouseButton:
			(event as InputEventMouseButton).position = _press_pos
			(event as InputEventMouseButton).global_position = _press_global_pos
		elif event is InputEventScreenTouch:
			(event as InputEventScreenTouch).position = _press_pos
		viewport.push_input(event, true)
	_replaying = false


# --- Scrolling ---

func _process(delta: float) -> void:
	if not _flinging:
		set_process(false)
		return
	_velocity *= exp(-INERTIA_FRICTION_PER_S * delta)
	if _velocity.length() < INERTIA_MIN_SPEED_PX_S:
		_stop_fling()
		return
	var before: Vector2 = _scroll_f
	_scroll_to(_scroll_f + _velocity * delta)
	if _scroll_f.is_equal_approx(before):
		_stop_fling()   # reached the end of the list


func _stop_fling() -> void:
	_flinging = false
	_velocity = Vector2.ZERO
	set_process(false)


func _reset() -> void:
	_phase = Phase.IDLE
	_held.clear()
	_finger = NO_FINGER
	_tap_blocked = false
	_tap_release_seen = false
	_slider_pressed = false
	_stop_fling()


## Sets the scroll offset (clamped per enabled axis); _scroll_f keeps the float value.
func _scroll_to(target: Vector2) -> void:
	if horizontal_scroll_mode != SCROLL_MODE_DISABLED:
		_scroll_f.x = _apply(get_h_scroll_bar(), target.x)
	if vertical_scroll_mode != SCROLL_MODE_DISABLED:
		_scroll_f.y = _apply(get_v_scroll_bar(), target.y)


static func _apply(bar: ScrollBar, value: float) -> float:
	var clamped: float = clampf(value, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
	bar.value = clamped
	return clamped


func _can_scroll() -> bool:
	return _axis_range(horizontal_scroll_mode, get_h_scroll_bar()) > 0.0 \
			or _axis_range(vertical_scroll_mode, get_v_scroll_bar()) > 0.0


static func _axis_range(mode: ScrollContainer.ScrollMode, bar: ScrollBar) -> float:
	if mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return 0.0
	return bar.max_value - bar.min_value - bar.page


# --- Hit testing ---

func _contains(viewport_pos: Vector2) -> bool:
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * viewport_pos
	return Rect2(Vector2.ZERO, size).has_point(local)


## What the touch landed on: a scrollbar or text field (own drag), a slider (shared drag) or anything else.
func _target_at(viewport_pos: Vector2) -> Target:
	var node: Node = _topmost_control(self, viewport_pos)
	while node != null and node != self:
		if node is Slider:
			_slider_vertical = node is VSlider
			return Target.SLIDER
		if node is ScrollBar or node is LineEdit or node is TextEdit:
			return Target.OWN_DRAG
		node = node.get_parent()
	return Target.PLAIN


## Last visible Control under the point in tree order (= drawn on top), searching below `parent`.
func _topmost_control(parent: Node, viewport_pos: Vector2) -> Control:
	var found: Control = null
	for child: Node in parent.get_children(true):
		if child is Window:
			continue
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var control: Control = child
			var local: Vector2 = control.get_global_transform_with_canvas().affine_inverse() * viewport_pos
			if control.mouse_filter != Control.MOUSE_FILTER_IGNORE and Rect2(Vector2.ZERO, control.size).has_point(local):
				found = control
		var deeper: Control = _topmost_control(child, viewport_pos)
		if deeper != null:
			found = deeper
	return found
