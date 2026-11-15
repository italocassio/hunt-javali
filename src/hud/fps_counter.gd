class_name FpsCounter
extends Label
## Frames-per-second readout driven by the "show_fps" setting. Reads the initial value from Profile and follows
## GameEvents.settings_changed live. It keeps running while the tree is paused (the options panel opens from the
## pause menu) and does no work at all while hidden. In an online hunt (Net.is_active()) it adds a second line with the
## network traffic of the last second (docs/multiplayer.md 4.7.8); solo never asks the Net for anything.

const SETTING_KEY: String = "show_fps"
const UPDATE_INTERVAL_S: float = 0.5
const FONT_PX: int = 18
const OUTLINE_PX: int = 4
const TEXT_FORMAT: String = "%d FPS"
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.9)
const NO_FPS: int = -1
const NET_FORMAT: String = "Rede ↑ %s ↓ %s kB/s · %d direto, %d via servidor"
const BYTES_PER_KB: float = 1000.0   # kB = 1000 bytes of application data (no wire overhead)

var _elapsed_s: float = 0.0
var _last_fps: int = NO_FPS
var _net_line: String = ""
var debug_online: int = -1   # tests only: 0/1 forces "online" off/on, -1 asks Net.is_active()


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
		_net_line = ""
		_refresh()


func _process(delta: float) -> void:
	_elapsed_s += delta
	if _elapsed_s >= UPDATE_INTERVAL_S:
		_elapsed_s = 0.0
		_refresh()


func _refresh() -> void:
	var fps: int = int(Engine.get_frames_per_second())
	var net_line: String = format_net_line(Net.get_traffic()) if _is_online() else ""
	if fps != _last_fps or net_line != _net_line:   # no new string unless something changed
		_last_fps = fps
		_net_line = net_line
		var fps_line: String = TEXT_FORMAT % fps
		text = fps_line if net_line == "" else fps_line + "\n" + net_line


func _is_online() -> bool:
	return Net.is_active() if debug_online < 0 else debug_online == 1


## "Rede ↑ 12,3 ↓ 4,1 kB/s · 2 direto, 1 via servidor" from Net.get_traffic().
static func format_net_line(traffic: Dictionary) -> String:
	var direct: int = 0
	var relayed: int = 0
	var links: Array = traffic.get("links", [])
	for link: Variant in links:
		var path: int = int((link as Dictionary).get("path", Net.Path.NONE))
		if path == Net.Path.RTC:
			direct += 1
		elif path == Net.Path.RELAY:
			relayed += 1
	return NET_FORMAT % [_kbps(int(traffic.get("up_bps", 0))), _kbps(int(traffic.get("down_bps", 0))), direct, relayed]


## Decimal comma, one place (pt-BR).
static func _kbps(bytes_per_s: int) -> String:
	return ("%.1f" % (float(bytes_per_s) / BYTES_PER_KB)).replace(".", ",")


func _on_settings_changed(key: String, value: Variant) -> void:
	if key == SETTING_KEY:
		set_enabled(bool(value))
