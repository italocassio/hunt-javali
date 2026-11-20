class_name HintBanner
extends PanelContainer
## Strip of the contextual hints (docs §8.4, "Dicas das primeiras caçadas"): a HudPanel with one HudBigLabel,
## centred horizontally and at 0.30-0.37 of the height, in keyboard and touch mode alike. The panel shrinks to the
## text plus the panel padding; a longer text wraps inside MAX_WIDTH_FRAC of the screen width.
## It has no clock: the HintDirector decides when it appears and when it goes. Fades in and out in FADE_S.

const ANCHOR_CENTER_X: float = 0.5
const MAX_WIDTH_FRAC: float = 0.6   # widest the panel gets, as a fraction of the screen width
const TEXT_SLACK_PX: float = 4.0    # so the measured width never wraps by a rounding error
const ANCHOR_TOP: float = 0.30
const ANCHOR_BOTTOM: float = 0.37
const FONT_PX: int = 24
const FADE_S: float = 0.2
const MARGIN_PX: int = 10
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_PANEL: Color = Color(0.12, 0.10, 0.086, 0.72)

var _label: Label = Label.new()
var _showing: bool = false
var _tween: Tween = null


func _init() -> void:
	name = "HintBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"HudPanel"
	anchor_left = ANCHOR_CENTER_X
	anchor_right = ANCHOR_CENTER_X
	anchor_top = ANCHOR_TOP
	anchor_bottom = ANCHOR_BOTTOM
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH   # the width is the text's: it grows from the centre line
	grow_vertical = Control.GROW_DIRECTION_END   # two wrapped lines grow downwards, away from the context message
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.theme_type_variation = &"HudBigLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", FONT_PX)
	_label.add_theme_color_override("font_color", COLOR_TEXT)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	modulate.a = 0.0
	visible = false


func _ready() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or not theme.has_stylebox(&"panel", &"HudPanel"):
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = COLOR_PANEL
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(MARGIN_PX)
		add_theme_stylebox_override("panel", sb)
	get_viewport().size_changed.connect(_fit_width)


## Width the text asks for on one line, capped to what fits inside MAX_WIDTH_FRAC of the screen minus the padding.
func _fit_width() -> void:
	if not is_inside_tree():
		return
	var font: Font = _label.get_theme_font("font")
	var font_size: int = _label.get_theme_font_size("font_size")
	var padding: float = get_theme_stylebox("panel").get_minimum_size().x
	var max_text: float = maxf(get_viewport_rect().size.x * MAX_WIDTH_FRAC - padding, 0.0)
	var wanted: float = font.get_multiline_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_label.custom_minimum_size.x = minf(ceilf(wanted + TEXT_SLACK_PX), max_text)


func show_hint(text: String) -> void:
	_label.text = text
	_fit_width()
	_showing = true
	visible = true
	_fade_to(1.0, false)


func hide_hint() -> void:
	if not _showing:
		return
	_showing = false
	_fade_to(0.0, true)


## True from show_hint until hide_hint (the fade-out does not count).
func is_showing() -> bool:
	return _showing


## The last text given to show_hint (like Label.text, it stays after the banner is hidden).
func get_text() -> String:
	return _label.text


func _fade_to(alpha: float, then_hide: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		modulate.a = alpha
		visible = not then_hide
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", alpha, FADE_S)
	if then_hide:
		_tween.tween_callback(_finish_hide)


func _finish_hide() -> void:
	if not _showing:
		visible = false
