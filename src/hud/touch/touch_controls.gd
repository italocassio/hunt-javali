class_name TouchControls
extends CanvasLayer
## Touch layer (CanvasLayer 11, docs §8.4). Real multitouch: every finger is bound by index to one
## widget (joystick, look pad, a button or the zoom slider) when it goes down. Emulated mouse
## events are never used, so tapping to look cannot fire the weapon.

const SURFACE_MARGIN_PX: float = 24.0
const JOYSTICK_ZONE_FRAC: float = 0.4       # left 40% of the screen
const HIT_PADDING_PX: float = 8.0
const SLIDER_WIDTH_PX: float = 84.0
const SLIDER_TRACK_WIDTH_PX: float = 10.0
const SLIDER_KNOB_RADIUS_PX: float = 26.0
const COLOR_FILL: Color = Color(1.0, 1.0, 1.0, 0.16)
const COLOR_FILL_DOWN: Color = Color(1.0, 1.0, 1.0, 0.38)
const COLOR_FIRE: Color = Color(0.85, 0.27, 0.17, 0.32)
const COLOR_FIRE_DOWN: Color = Color(0.85, 0.27, 0.17, 0.6)
const COLOR_RING: Color = Color(1.0, 1.0, 1.0, 0.55)
const COLOR_ON: Color = Color("#F2C12E")
const COLOR_TEXT: Color = Color("#F4EFE6")
const FONT_SIZE: int = 20

## action, diameter, label, icon id, offset from the bottom-right corner (dx, dy as positive numbers),
## mode: "hold" presses while touched, "toggle" flips on each tap.
const BUTTONS: Array[Dictionary] = [
	{"action": &"fire", "d": 130.0, "label": "Tiro", "icon": &"btn_fire", "from": "br", "ox": 125.0, "oy": 130.0, "mode": "hold"},
	{"action": &"aim", "d": 100.0, "label": "Mira", "icon": &"btn_aim", "from": "br", "ox": 290.0, "oy": 105.0, "mode": "toggle"},
	{"action": &"reload", "d": 84.0, "label": "Recarga", "icon": &"btn_reload", "from": "br", "ox": 100.0, "oy": 285.0, "mode": "hold"},
	{"action": &"weapon_swap", "d": 76.0, "label": "Troca", "icon": &"btn_swap", "from": "br", "ox": 235.0, "oy": 235.0, "mode": "hold"},
	{"action": &"crouch", "d": 76.0, "label": "Agachar", "icon": &"btn_crouch", "from": "br", "ox": 410.0, "oy": 130.0, "mode": "hold"},
	{"action": &"use_item", "d": 84.0, "label": "Item", "icon": &"btn_item", "from": "br", "ox": 380.0, "oy": 250.0, "mode": "hold"},
	{"action": &"item_next", "d": 64.0, "label": "»", "icon": &"", "from": "br", "ox": 475.0, "oy": 250.0, "mode": "hold"},
	{"action": &"dog_command", "d": 76.0, "label": "Cão", "icon": &"btn_dog", "from": "br", "ox": 235.0, "oy": 350.0, "mode": "hold"},
	{"action": &"pause", "d": 64.0, "label": "II", "icon": &"btn_pause", "from": "tl", "ox": 56.0, "oy": 56.0, "mode": "hold"},
]

class TouchSurface extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

var joystick: TouchJoystick = TouchJoystick.new()
var look_pad: LookPad = LookPad.new()

var _player: Player = null
var _surface: TouchSurface = TouchSurface.new()
var _centers: Dictionary = {}         # action -> Vector2
var _radii: Dictionary = {}           # action -> float
var _finger_to_action: Dictionary = {}   # finger -> StringName
var _down: Dictionary = {}            # action -> bool (visual state)
var _toggled: Dictionary = {}         # action -> bool
var _slider_finger: int = -1
var _slider_rect: Rect2 = Rect2()
var _icons: Dictionary = {}           # icon id -> Texture2D
var _item_label: String = ""
var _ended: bool = false


func _ready() -> void:
	layer = 11
	add_child(_surface)
	_surface.add_child(joystick)
	_surface.add_child(look_pad)
	joystick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	look_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.draw.connect(_draw_surface)
	for def: Dictionary in BUTTONS:
		var icon_id: StringName = def["icon"]
		if icon_id != &"" and AssetLoader.exists(ScenePaths.icon(icon_id)):
			_icons[icon_id] = AssetLoader.load_resource(ScenePaths.icon(icon_id))
	look_pad.look.connect(_on_look)
	get_viewport().size_changed.connect(_layout)
	GameEvents.touch_mode_changed.connect(_on_touch_mode_changed)
	_layout()
	_apply_visibility(InputSetup.is_touch_mode())


func bind(player: Player) -> void:
	_player = player
	var items: ItemBelt = player.get_items()
	if items != null:
		items.selection_changed.connect(_refresh_item_label)
		items.counts_changed.connect(_refresh_item_label)
	_refresh_item_label()


func end_hunt() -> void:
	_ended = true
	_release_everything()
	_apply_visibility(false)


func get_button_center(action_name: StringName) -> Vector2:
	return _centers.get(action_name, Vector2.INF)


func get_button_radius(action_name: StringName) -> float:
	return float(_radii.get(action_name, 0.0))


func get_button_diameters() -> Dictionary:
	var out: Dictionary = {}
	for action_name: StringName in _radii:
		out[action_name] = float(_radii[action_name]) * 2.0
	return out


func get_look_zone_start_x() -> float:
	return _screen_size().x * JOYSTICK_ZONE_FRAC


func get_slider_rect() -> Rect2:
	return _slider_rect


func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _layout() -> void:
	var s: Vector2 = _screen_size()
	for def: Dictionary in BUTTONS:
		var c: Vector2
		if String(def["from"]) == "br":
			c = Vector2(s.x - float(def["ox"]), s.y - float(def["oy"]))
		else:
			c = Vector2(float(def["ox"]), float(def["oy"]))
		_centers[def["action"]] = c
		_radii[def["action"]] = float(def["d"]) * 0.5
	joystick.rest_center = Vector2(190.0, s.y - 160.0)
	_slider_rect = Rect2(Vector2(32.0, s.y * 0.26), Vector2(SLIDER_WIDTH_PX, s.y * 0.42))
	_surface.queue_redraw()


func _on_touch_mode_changed(is_touch: bool) -> void:
	if not is_touch:
		_release_everything()
	_apply_visibility(is_touch and not _ended)


func _apply_visibility(touch: bool) -> void:
	visible = touch
	set_process_input(touch)
	set_process(touch)
	joystick.set_process(touch)
	_surface.queue_redraw()


func _release_everything() -> void:
	for finger: int in _finger_to_action.keys():
		_release_button_finger(finger)
	_finger_to_action.clear()
	if joystick.is_active():
		joystick.end()
	look_pad.end()
	_slider_finger = -1
	for action_name: StringName in _toggled.keys():
		if bool(_toggled[action_name]):
			Input.action_release(action_name)
	_toggled.clear()
	_down.clear()


func _process(_delta: float) -> void:
	# The aim toggle must follow the player: if the player dropped the aim (death, pause), reset it.
	if _player != null and bool(_toggled.get(&"aim", false)) and not _player.is_alive():
		_toggled[&"aim"] = false
		Input.action_release(&"aim")
	_surface.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_finger_down(touch.index, touch.position)
		else:
			_finger_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_finger_drag(drag.index, drag.position, drag.relative)


func _finger_down(finger: int, pos: Vector2) -> void:
	# 1. buttons
	for action_name: StringName in _centers:
		var c: Vector2 = _centers[action_name]
		if pos.distance_to(c) <= float(_radii[action_name]) + HIT_PADDING_PX:
			_press_button(finger, action_name)
			return
	# 2. zoom slider (only visible when aiming with an adjustable zoom)
	if _slider_visible() and _slider_rect.grow(HIT_PADDING_PX).has_point(pos):
		_slider_finger = finger
		_set_slider_from(pos)
		return
	# 3. left zone = joystick, rest = look
	if pos.x < _screen_size().x * JOYSTICK_ZONE_FRAC:
		if not joystick.is_active():
			joystick.begin(finger, pos)
	elif not look_pad.is_active():
		look_pad.begin(finger)


func _finger_up(finger: int) -> void:
	if _finger_to_action.has(finger):
		_release_button_finger(finger)
		_finger_to_action.erase(finger)
	if finger == _slider_finger:
		_slider_finger = -1
	if finger == joystick.get_finger():
		joystick.end()
	if finger == look_pad.get_finger():
		look_pad.end()


func _finger_drag(finger: int, pos: Vector2, relative: Vector2) -> void:
	if finger == joystick.get_finger():
		joystick.drag(pos)
	elif finger == look_pad.get_finger():
		look_pad.drag(relative)
	elif finger == _slider_finger:
		_set_slider_from(pos)


func _press_button(finger: int, action_name: StringName) -> void:
	_finger_to_action[finger] = action_name
	_down[action_name] = true
	var mode: String = _mode_of(action_name)
	if mode == "toggle":
		var on: bool = not bool(_toggled.get(action_name, false))
		_toggled[action_name] = on
		if on:
			Input.action_press(action_name)
		else:
			Input.action_release(action_name)
	else:
		Input.action_press(action_name)


func _release_button_finger(finger: int) -> void:
	var action_name: StringName = _finger_to_action.get(finger, &"")
	if action_name == &"":
		return
	_down[action_name] = false
	if _mode_of(action_name) != "toggle":
		Input.action_release(action_name)


func _mode_of(action_name: StringName) -> String:
	for def: Dictionary in BUTTONS:
		if def["action"] == action_name:
			return String(def["mode"])
	return "hold"


func _on_look(rel_px: Vector2) -> void:
	if _player != null:
		_player.apply_touch_look(rel_px)


func _slider_visible() -> bool:
	return _player != null and _player.is_aiming() and _player.has_zoom_range()


func _set_slider_from(pos: Vector2) -> void:
	if _player == null:
		return
	var t: float = 1.0 - clampf((pos.y - _slider_rect.position.y) / _slider_rect.size.y, 0.0, 1.0)
	_player.set_zoom_fraction(t)


func _refresh_item_label() -> void:
	_item_label = ""
	if _player == null or _player.get_items() == null:
		return
	var items: ItemBelt = _player.get_items()
	var id: StringName = items.get_selected_id()
	if id == &"":
		return
	var count: int = items.get_count(id)
	var short_name: String = String(Data.get_equipment(id).get("name", ""))
	_item_label = short_name if count < 0 else "%s x%d" % [short_name, count]
	_surface.queue_redraw()


# --- Drawing ---

func _draw_surface() -> void:
	if not visible:
		return
	var font: Font = ThemeDB.fallback_font
	for def: Dictionary in BUTTONS:
		var action_name: StringName = def["action"]
		var c: Vector2 = _centers.get(action_name, Vector2.ZERO)
		var r: float = float(_radii.get(action_name, 0.0))
		var down: bool = bool(_down.get(action_name, false))
		var on: bool = bool(_toggled.get(action_name, false))
		var fire: bool = action_name == &"fire"
		var fill: Color = COLOR_FIRE if fire else COLOR_FILL
		if down or on:
			fill = COLOR_FIRE_DOWN if fire else COLOR_FILL_DOWN
		_surface.draw_circle(c, r, fill)
		_surface.draw_arc(c, r, 0.0, TAU, 48, COLOR_ON if on else COLOR_RING, 4.0 if on else 3.0, true)
		var icon_id: StringName = def["icon"]
		var label: String = String(def["label"])
		if action_name == &"use_item" and _item_label != "":
			label = _item_label
		if _icons.has(icon_id):
			var tex: Texture2D = _icons[icon_id]
			var icon_size: float = r * 1.2
			_surface.draw_texture_rect(tex, Rect2(c - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false)
			if action_name == &"use_item":
				_draw_text(font, label, c + Vector2(0.0, r + 20.0), 16)
		else:
			_draw_text(font, label, c + Vector2(0.0, 7.0), FONT_SIZE if label.length() < 8 else 15)
	if _slider_visible():
		_draw_slider()


func _draw_text(font: Font, text: String, baseline_center: Vector2, size_px: int) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var p: Vector2 = baseline_center - Vector2(w * 0.5, 0.0)
	_surface.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 5, Color.BLACK)
	_surface.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, COLOR_TEXT)


func _draw_slider() -> void:
	var r: Rect2 = _slider_rect
	var cx: float = r.position.x + r.size.x * 0.5
	_surface.draw_rect(r, Color(0.0, 0.0, 0.0, 0.25))
	_surface.draw_line(Vector2(cx, r.position.y + 12.0), Vector2(cx, r.end.y - 12.0), COLOR_RING, SLIDER_TRACK_WIDTH_PX)
	var t: float = _player.get_zoom_fraction()
	var ky: float = lerpf(r.end.y - 12.0, r.position.y + 12.0, t)
	_surface.draw_circle(Vector2(cx, ky), SLIDER_KNOB_RADIUS_PX, COLOR_FILL_DOWN)
	_surface.draw_arc(Vector2(cx, ky), SLIDER_KNOB_RADIUS_PX, 0.0, TAU, 32, COLOR_ON, 3.0, true)
	var font: Font = ThemeDB.fallback_font
	_draw_text(font, "%.1fx" % _player.get_zoom_value(), Vector2(cx, r.position.y - 10.0), 20)
