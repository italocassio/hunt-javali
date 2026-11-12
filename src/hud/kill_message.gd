class_name KillMessage
extends Control
## Centered text that pops in, holds and fades out. Used for kill messages and context messages.

const POP_S: float = 0.12
const FADE_S: float = 0.4
const POP_SCALE: float = 1.25
const OUTLINE_PX: int = 6

var _label: Label = Label.new()
var _tween: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.theme_type_variation = &"HudBigLabel"
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color("#F4EFE6"))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", OUTLINE_PX)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	modulate.a = 0.0


func set_font_size(px: int) -> void:
	_label.add_theme_font_size_override("font_size", px)


func set_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)


func get_text() -> String:
	return _label.text


func show_text(text: String, duration_s: float) -> void:
	_label.text = text
	pivot_offset = size * 0.5
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	scale = Vector2.ONE * POP_SCALE
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(maxf(duration_s - FADE_S, 0.0))
	_tween.tween_property(self, "modulate:a", 0.0, FADE_S)


func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
