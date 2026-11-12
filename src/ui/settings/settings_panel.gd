extends Control
## Reusable settings panel (settings screen and pause menu). Every change goes through Profile.set_setting.
## Emits `closed` from %CloseButton. `show_close_button` must be set before the node enters the tree.

signal closed

const SLIDER_STEP: float = 0.05
const SLIDER_MIN_HEIGHT: float = 48.0
const VALUE_LABEL_PX: float = 90.0
const BACKDROP_COLOR: Color = Color(0.07, 0.06, 0.05, 0.94)

const SLIDERS: Array[Dictionary] = [
	{"key": "mouse_sensitivity", "title": "Sensibilidade do mouse", "min": 0.1, "max": 3.0, "format": "x"},
	{"key": "touch_sensitivity", "title": "Sensibilidade do toque", "min": 0.1, "max": 3.0, "format": "x"},
	{"key": "volume_master", "title": "Volume geral", "min": 0.0, "max": 1.0, "format": "%"},
	{"key": "volume_sfx", "title": "Volume dos efeitos", "min": 0.0, "max": 1.0, "format": "%"},
	{"key": "volume_ambience", "title": "Volume do ambiente", "min": 0.0, "max": 1.0, "format": "%"},
]
const QUALITY_OPTIONS: Array[Dictionary] = [
	{"value": "auto", "title": "Automática"},
	{"value": "low", "title": "Baixa (mais rápido)"},
	{"value": "medium", "title": "Média"},
	{"value": "high", "title": "Alta"},
]
const TOUCH_OPTIONS: Array[Dictionary] = [
	{"value": "auto", "title": "Automático"},
	{"value": "on", "title": "Sempre ligados"},
	{"value": "off", "title": "Desligados"},
]

var show_close_button: bool = true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if show_close_button:
		var dim: ColorRect = ColorRect.new()
		dim.color = BACKDROP_COLOR
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var edge: int = 24 if show_close_button else 0
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, edge)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	if show_close_button:
		column.add_child(UiKit.label("Configurações", "TitleLabel"))

	var scroller: Array = UiKit.scroll_list(10)
	column.add_child(scroller[0])
	var list: VBoxContainer = scroller[1]
	for def: Dictionary in SLIDERS:
		list.add_child(_slider_row(def))
	list.add_child(_option_row("quality", "Qualidade gráfica", QUALITY_OPTIONS, "Vale a partir da próxima caçada."))
	list.add_child(_option_row("touch_controls", "Controles de toque", TOUCH_OPTIONS, ""))
	list.add_child(_check_row("invert_y", "Inverter o eixo vertical da mira"))
	list.add_child(_check_row("show_fps", "Mostrar quadros por segundo"))

	if show_close_button:
		var close: Button = UiKit.button("Fechar", "PrimaryButton", 72)
		UiKit.mark(close, self, "CloseButton")
		column.add_child(close)
		close.pressed.connect(func() -> void: closed.emit())


func _slider_row(def: Dictionary) -> Control:
	var key: String = str(def["key"])
	var card: PanelContainer = UiKit.card()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var caption: Label = UiKit.label(str(def["title"]))
	caption.custom_minimum_size.x = 300
	row.add_child(caption)
	var slider: HSlider = HSlider.new()
	slider.min_value = float(def["min"])
	slider.max_value = float(def["max"])
	slider.step = SLIDER_STEP
	slider.value = float(Profile.get_setting(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, SLIDER_MIN_HEIGHT)
	slider.name = "Slider_%s" % key
	row.add_child(slider)
	var value: Label = UiKit.label(_format_value(slider.value, str(def["format"])))
	value.custom_minimum_size.x = VALUE_LABEL_PX
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = _format_value(v, str(def["format"]))
		Profile.set_setting(key, v))
	return card


func _option_row(key: String, title: String, options: Array[Dictionary], note: String) -> Control:
	var card: PanelContainer = UiKit.card()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var caption: VBoxContainer = VBoxContainer.new()
	caption.custom_minimum_size.x = 300
	caption.add_child(UiKit.label(title))
	if note != "":
		caption.add_child(UiKit.muted(note))
	row.add_child(caption)
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	option.name = "Option_%s" % key
	if not UiKit.has_global_theme():
		option.add_theme_font_size_override("font_size", 22)
	var current: String = str(Profile.get_setting(key))
	for i: int in options.size():
		option.add_item(str(options[i]["title"]))
		if str(options[i]["value"]) == current:
			option.select(i)
	row.add_child(option)
	option.item_selected.connect(func(index: int) -> void:
		Profile.set_setting(key, str(options[index]["value"])))
	return card


func _check_row(key: String, title: String) -> Control:
	var check: CheckButton = CheckButton.new()
	check.text = title
	check.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	check.button_pressed = bool(Profile.get_setting(key))
	check.name = "Check_%s" % key
	if not UiKit.has_global_theme():
		check.add_theme_font_size_override("font_size", 22)
	check.toggled.connect(func(on: bool) -> void: Profile.set_setting(key, on))
	return check


func _format_value(value: float, kind: String) -> String:
	if kind == "%":
		return "%d%%" % int(roundf(value * 100.0))
	return "%sx" % UiKit.decimal(value, 1)
