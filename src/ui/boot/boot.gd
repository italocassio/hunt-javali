extends Control
## Boot screen: one tap unlocks audio (browser gesture rule) and goes to the main menu.

const TITLE: String = "Caçada ao Javali"
const SUBTITLE: String = "Controle de fauna no cerrado"
const PULSE_S: float = 0.9

var _start: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = UiKit.BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var band: ColorRect = ColorRect.new()
	band.color = Color(0.64, 0.267, 0.165, 0.5)   # terra vermelha
	band.anchor_top = 0.62
	band.anchor_right = 1.0
	band.anchor_bottom = 1.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	var titles: VBoxContainer = VBoxContainer.new()
	titles.set_anchors_preset(Control.PRESET_CENTER_TOP)
	titles.anchor_left = 0.0
	titles.anchor_right = 1.0
	titles.anchor_top = 0.2
	titles.anchor_bottom = 0.5
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 10)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(titles)
	var title: Label = UiKit.label(TITLE.to_upper(), "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not UiKit.has_global_theme():
		title.add_theme_font_size_override("font_size", 64)
	titles.add_child(title)
	var sub: Label = UiKit.label(SUBTITLE, "HeaderLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titles.add_child(sub)

	_start = UiKit.button("", "PrimaryButton", 96)
	_start.flat = true
	_start.theme_type_variation = ""
	for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_start.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	_start.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.mark(_start, self, "StartButton")
	add_child(_start)
	_start.move_to_front()
	_start.pressed.connect(_on_start)
	_start.grab_focus()
	var prompt: Label = UiKit.label("Toque para começar", "HeaderLabel")
	prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	prompt.anchor_top = 0.72
	prompt.anchor_bottom = 0.9
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)

	var tween: Tween = create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.45, PULSE_S).set_trans(Tween.TRANS_SINE)
	tween.tween_property(prompt, "modulate:a", 1.0, PULSE_S).set_trans(Tween.TRANS_SINE)


func _on_start() -> void:
	Sfx.unlock_audio()
	if DisplayServer.is_touchscreen_available() or InputSetup.is_touch_mode():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	Router.goto(ScenePaths.MAIN_MENU)
