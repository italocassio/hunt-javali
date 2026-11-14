class_name FpsCounter
extends Label
## Frames-per-second readout driven by the "show_fps" setting. Reads the initial value from Profile and follows
## GameEvents.settings_changed live. It keeps running while the tree is paused (the options panel opens from the
## pause menu) and does no work at all while hidden.

const SETTING_KEY: String = "show_fps"
const UPDATE_INTERVAL_S: float = 0.5
const FONT_PX: int = 18
const OUTLINE_PX: int = 4
const TEXT_FORMAT: String = "%d FPS"
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.9)
const NO_FPS: int = -1

var _elapsed_s: float = 0.0
var _last_fps: int = NO_FPS


func _init() -> void:
	name = "FpsCounter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_type_variation = &"HudLabel"
	add_theme_font_size_override("font_size", FONT_PX)
	add_theme_color_override("font_color", COLOR_TEXT)
	add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	add_theme_constant_override("outline_size", OUTLINE_PX)
	visible = false
	set_process(false)


func _ready() -> void:
	GameEvents.settings_changed.connect(_on_settings_changed)
	set_enabled(bool(Profile.get_setting(SETTING_KEY)))


func set_enabled(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	if enabled:
		_elapsed_s = 0.0
		_last_fps = NO_FPS
		_refresh()


func _process(delta: float) -> void:
	_elapsed_s += delta
	if _elapsed_s >= UPDATE_INTERVAL_S:
		_elapsed_s = 0.0
		_refresh()


func _refresh() -> void:
	var fps: int = int(Engine.get_frames_per_second())
	if fps != _last_fps:   # no new string unless the number changed
		_last_fps = fps
		text = TEXT_FORMAT % fps


func _on_settings_changed(key: String, value: Variant) -> void:
	if key == SETTING_KEY:
		set_enabled(bool(value))
