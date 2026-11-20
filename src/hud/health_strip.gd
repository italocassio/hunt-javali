class_name HealthStrip
extends Control
## Wide health bar at the bottom centre of the HUD (docs §8.4, "Painel da arma e barra de vida"): the vest icon and
## "Colete" when the hunter wears one, the bar and the number. Pure display: the Hud feeds it every frame. The children
## are placed by this script (no container that could grow the height).

const HEIGHT_PX: float = 28.0
const WIDTH_PX: float = 400.0
const TOUCH_WIDTH_PX: float = 300.0
const PAD_X_PX: float = 10.0
const GAP_PX: float = 8.0
const BAR_HEIGHT_PX: float = 14.0
const VALUE_FONT_PX: int = 20
const VALUE_MIN_W_PX: float = 40.0
const VEST_ICON_PX: float = 20.0
const VEST_FONT_PX: int = 15
const VEST_SEPARATION_PX: int = 4
const VEST_TEXT: String = "Colete"
const WARN_FRAC: float = 0.5
const DANGER_FRAC: float = 0.3
const OUTLINE_PX: int = 5
const PANEL_RADIUS_PX: int = 8
const BAR_RADIUS_PX: int = 4
const COLOR_GOOD: Color = Color("#3FAF5A")
const COLOR_WARN: Color = Color("#F2C12E")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_PANEL: Color = Color(0.12, 0.10, 0.086, 0.72)
const COLOR_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.9)
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.55)

var _vest_on: bool = false
var _touch: bool = false
var _shown_hp: int = -1
var _panel_style: StyleBox = null

var _vest: HBoxContainer = HBoxContainer.new()
var _vest_icon: TextureRect = TextureRect.new()
var _vest_text: Label = Label.new()
var _bar: ProgressBar = ProgressBar.new()
var _value: Label = Label.new()


func _init() -> void:
	name = "HealthStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH_PX, HEIGHT_PX)

	_vest.name = "Vest"
	_vest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vest.add_theme_constant_override("separation", VEST_SEPARATION_PX)
	_vest.visible = false
	add_child(_vest)
	_vest_icon.name = "Icon"
	_vest_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vest_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vest_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_vest_icon.custom_minimum_size = Vector2.ONE * VEST_ICON_PX
	_vest_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_path: String = ScenePaths.icon(Ids.I_LEATHER_VEST)
	if AssetLoader.exists(icon_path):
		_vest_icon.texture = AssetLoader.load_resource(icon_path) as Texture2D
	_vest_icon.visible = _vest_icon.texture != null
	_vest.add_child(_vest_icon)
	_vest_text.name = "Text"
	_style_label(_vest_text, VEST_FONT_PX, COLOR_WARN, &"HudLabel")
	_vest_text.text = VEST_TEXT
	_vest.add_child(_vest_text)

	_bar.name = "Bar"
	_style_bar(_bar)
	add_child(_bar)

	_value.name = "Value"
	_style_label(_value, VALUE_FONT_PX, COLOR_TEXT, &"HudBigLabel")
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_value)
	set_health(1.0, 1.0)


func _ready() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme != null and theme.has_stylebox(&"panel", &"HudPanel"):
		_panel_style = theme.get_stylebox(&"panel", &"HudPanel")
	else:
		var flat: StyleBoxFlat = StyleBoxFlat.new()
		flat.bg_color = COLOR_PANEL
		flat.set_corner_radius_all(PANEL_RADIUS_PX)
		_panel_style = flat
	_layout()
	queue_redraw()


func _draw() -> void:
	if _panel_style != null:
		draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


## Bar from `hp / max_hp`, colour by fraction (above WARN_FRAC green, above DANGER_FRAC amber, else red), number is
## ceil(hp). The text is rewritten only when the integer changes.
func set_health(hp: float, max_hp: float) -> void:
	var frac: float = hp / maxf(max_hp, 1.0)
	_bar.value = frac * 100.0
	_bar.modulate = COLOR_GOOD if frac > WARN_FRAC else (COLOR_WARN if frac > DANGER_FRAC else COLOR_DANGER)
	var shown: int = ceili(hp)
	if shown != _shown_hp:
		_shown_hp = shown
		_value.text = str(shown)
		_layout()


func set_vest(on: bool) -> void:
	_vest_on = on
	_vest.visible = on
	_layout()


## Touch layout: 400 -> 300 px wide (the height is the same).
func set_touch(touch: bool) -> void:
	_touch = touch
	custom_minimum_size = Vector2(TOUCH_WIDTH_PX if touch else WIDTH_PX, HEIGHT_PX)
	_layout()


func get_value_text() -> String:
	return _value.text


func get_fill_pct() -> float:
	return _bar.value


func get_fill_color() -> Color:
	return _bar.modulate


func has_vest() -> bool:
	return _vest_on


## Left to right: vest, bar (the rest of the width), value; everything centred on the vertical.
func _layout() -> void:
	if _bar == null or _value == null or _vest == null:
		return
	var x: float = PAD_X_PX
	if _vest_on:
		var vest_size: Vector2 = _vest.get_combined_minimum_size()
		_vest.size = vest_size
		_vest.position = Vector2(x, (size.y - vest_size.y) * 0.5)
		x += vest_size.x + GAP_PX
	var value_w: float = maxf(VALUE_MIN_W_PX, _value.get_combined_minimum_size().x)
	var value_h: float = _value.get_combined_minimum_size().y
	_value.size = Vector2(value_w, value_h)
	_value.position = Vector2(size.x - PAD_X_PX - value_w, (size.y - value_h) * 0.5)
	var bar_w: float = maxf(_value.position.x - GAP_PX - x, 0.0)
	_bar.size = Vector2(bar_w, BAR_HEIGHT_PX)
	_bar.position = Vector2(x, (size.y - BAR_HEIGHT_PX) * 0.5)


func _style_label(label: Label, font_px: int, color: Color, variation: StringName) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", OUTLINE_PX)


## Theme variation HealthBar; a flat fallback when the theme lacks it. Tinted through modulate.
func _style_bar(bar: ProgressBar) -> void:
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.theme_type_variation = &"HealthBar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(0.0, BAR_HEIGHT_PX)
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or not theme.has_stylebox(&"fill", &"HealthBar"):
		var bg: StyleBoxFlat = StyleBoxFlat.new()
		bg.bg_color = COLOR_BAR_BG
		bg.set_corner_radius_all(BAR_RADIUS_PX)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color.WHITE
		fill.set_corner_radius_all(BAR_RADIUS_PX)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
