extends Node
## Autoload "InputSetup". Registers the input actions, converts real mouse buttons into actions
## (emulated touch-mouse is ignored) and tracks touch mode. See docs/arquitetura.md §4.

const ACTIONS: PackedStringArray = ["move_forward", "move_back", "move_left", "move_right", "fire", "aim",
	"zoom_in", "zoom_out", "reload", "sprint", "crouch", "weapon_1", "weapon_2", "weapon_swap",
	"dog_command", "use_item", "item_next", "pause"]

const ACTION_DEADZONE: float = 0.2
## Real mouse motion longer than this (px) switches "auto" mode back to mouse/keyboard.
const MOUSE_MOTION_SWITCH_PX: float = 2.0
## Mouse events this soon after the last touch event are treated as synthesized from touch.
const TOUCH_RECENT_S: float = 0.8
## A finger that never reported its release stops blocking real mouse input after this long.
const FINGER_STALE_S: float = 10.0

# action -> physical keycodes (location-specific keys are listed in _LEFT_ONLY)
const _KEYS: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"reload": [KEY_R],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"dog_command": [KEY_E],
	"use_item": [KEY_Q],
	"item_next": [KEY_F],
	"pause": [KEY_ESCAPE, KEY_P],
}
const _LEFT_ONLY: Array[int] = [KEY_SHIFT, KEY_CTRL]

var _touch_mode: bool = false
var _override: String = "auto"
var _touching: Dictionary = {}        # raw touch ids currently on the screen
var _last_touch_msec: int = -100000
var _wheel_release: Dictionary = {}   # action -> process frame at which it may be released


func _ready() -> void:
	register_actions()
	var setting: Variant = Profile.get_setting("touch_controls")
	_override = String(setting) if setting != null else "auto"
	if not _override in ["auto", "on", "off"]:
		_override = "auto"
	_touch_mode = _resolve_initial()
	GameEvents.settings_changed.connect(_on_settings_changed)


func register_actions() -> void:
	for action_name: String in ACTIONS:
		if InputMap.has_action(action_name):
			continue
		InputMap.add_action(action_name, ACTION_DEADZONE)
		for keycode: int in _KEYS.get(action_name, []):
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = keycode as Key
			if keycode in _LEFT_ONLY:
				ev.location = KEY_LOCATION_LEFT
			InputMap.action_add_event(action_name, ev)


## Current override ('auto' | 'on' | 'off'). TouchControls needs it to track the touch that turns the mode on.
func get_touch_override() -> String:
	return _override


func is_touch_mode() -> bool:
	return _touch_mode


func set_touch_override(mode: String) -> void:
	if not mode in ["auto", "on", "off"]:
		push_warning("InputSetup.set_touch_override: unknown mode '%s'" % mode)
		return
	_override = mode
	_touching.clear()   # an explicit mode change starts a fresh touch-activity window
	_last_touch_msec = -100000
	_apply_touch_mode(_resolve_initial())


func release_all_actions() -> void:
	for action_name: String in ACTIONS:
		Input.action_release(action_name)
	_wheel_release.clear()


func _resolve_initial() -> bool:
	match _override:
		"on":
			return true
		"off":
			return false
	return DisplayServer.is_touchscreen_available()


func _apply_touch_mode(value: bool) -> void:
	if value == _touch_mode:
		return
	_touch_mode = value
	GameEvents.touch_mode_changed.emit(_touch_mode)


func _on_settings_changed(key: String, value: Variant) -> void:
	if key == "touch_controls" and value != null:
		set_touch_override(String(value))


func _process(_delta: float) -> void:
	if _wheel_release.is_empty():
		return
	var frame: int = Engine.get_process_frames()
	for action_name: String in _wheel_release.keys():
		if frame > int(_wheel_release[action_name]):
			Input.action_release(action_name)
			_wheel_release.erase(action_name)


## True while a finger is on the screen or touched it a moment ago. On the Web, the mouse events that
## Godot synthesizes from touch (emulate_mouse_from_touch) can arrive WITHOUT DEVICE_ID_EMULATION, so the
## device field is not trusted: any mouse event during this window is treated as emulated.
func is_touch_active() -> bool:
	var age_s: float = float(Time.get_ticks_msec() - _last_touch_msec) / 1000.0
	if not _touching.is_empty():
		return age_s < FINGER_STALE_S
	return age_s < TOUCH_RECENT_S


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		_last_touch_msec = Time.get_ticks_msec()
		if touch.pressed and not touch.canceled:
			_touching[touch.index] = true
		else:
			_touching.erase(touch.index)
		if _override == "auto":
			_apply_touch_mode(true)
		return
	if event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_touching[(event as InputEventScreenDrag).index] = true
		if _override == "auto":
			_apply_touch_mode(true)
		return
	if event is InputEventKey:
		if _override == "auto":
			_apply_touch_mode(false)
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or is_touch_active():
			return   # synthesized from touch
		if _override == "auto":
			if event is InputEventMouseButton:
				_apply_touch_mode(false)   # hybrid laptop: a real click switches to mouse mode and still counts
			elif (event as InputEventMouseMotion).relative.length() > MOUSE_MOTION_SWITCH_PX:
				_apply_touch_mode(false)
		if event is InputEventMouseButton:
			_inject_mouse_button(event as InputEventMouseButton)


func _inject_mouse_button(event: InputEventMouseButton) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or _touch_mode or is_touch_active():
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_set_action("fire", event.pressed)
		MOUSE_BUTTON_RIGHT:
			_set_action("aim", event.pressed)
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_pulse("zoom_in")
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_pulse("zoom_out")


func _set_action(action_name: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action_name)
	else:
		Input.action_release(action_name)


## Presses an action now and releases it on a later process frame, so every _process sees it once.
func _pulse(action_name: String) -> void:
	Input.action_press(action_name)
	_wheel_release[action_name] = Engine.get_process_frames()
