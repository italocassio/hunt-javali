class_name LoadingProgress
extends RefCounted
## Progress of the hunt loading (docs/arquitetura.md section 8.1, "Progresso"). Weights per assembly step come from
## data/game.json "loading.step_weights" (key = step name, in assembly order). The value never goes back and
## reaches 1 only in finish(). Shown by the LoadingBoar widget inside the LoadingOverlay; without the widget the
## Label shows "<text> 42%".

signal changed(value: float)

const WIDGET_GAP_PX: float = 28.0
const WIDGET_FALLBACK_SIZE: Vector2 = Vector2(320.0, 140.0)
const FALLBACK_FORMAT: String = "%s %d%%"

var _weights: Dictionary = {}          # step -> weight (0 = skipped)
var _order: Array[String] = []
var _total: float = 0.0
var _value: float = 0.0
var _label: Label = null
var _widget: Control = null
var _base_text: String = ""
var _history: PackedFloat32Array = PackedFloat32Array()


## `overlay` is the LoadingOverlay; the widget (if the asset exists) is added below the label.
func setup(overlay: CanvasLayer, label: Label, base_text: String, weights: Dictionary) -> void:
	_label = label
	_base_text = base_text
	for step: Variant in weights.keys():
		var w: float = maxf(float(weights[step]), 0.0)
		_weights[String(step)] = w
		_order.append(String(step))
	_recompute_total()
	if overlay != null and AssetLoader.exists(ScenePaths.LOADING_BOAR):
		_widget = AssetLoader.instantiate(ScenePaths.LOADING_BOAR) as Control
		if _widget != null and not _widget.has_method(&"set_progress"):
			_widget.free()
			_widget = null
		if _widget != null:
			_widget.name = "LoadingBoar"
			overlay.add_child(_widget)
			_place_widget()
	_show()


func get_value() -> float:
	return _value


## Every value shown so far (tests and timing output).
func get_history() -> PackedFloat32Array:
	return _history


## The step is done: progress = weight of every step up to and including it.
func complete(step: String) -> void:
	_raise(_done_through(step, 1.0))


## Inside a step: `fraction` (0..1) of its weight is done.
func set_fraction(step: String, fraction: float) -> void:
	_raise(_done_through(step, clampf(fraction, 0.0, 1.0)))


## The step does not run in this role (dog, ...): its weight leaves the total.
func skip(step: String) -> void:
	if _weights.has(step):
		_weights[step] = 0.0
		_recompute_total()


## Reaches 1. Called right before the overlay is hidden (or when the hunt has nothing left to load).
func finish() -> void:
	_raise(1.0)


func set_base_text(text: String) -> void:
	_base_text = text
	_show()


func _recompute_total() -> void:
	_total = 0.0
	for step: String in _order:
		_total += float(_weights[step])


## Share of the total done when `fraction` of `step` is complete.
func _done_through(step: String, fraction: float) -> float:
	if _total <= 0.0 or not _weights.has(step):
		return _value
	var done: float = 0.0
	for s: String in _order:
		if s == step:
			done += float(_weights[s]) * fraction
			break
		done += float(_weights[s])
	return done / _total


func _raise(v: float) -> void:
	var next: float = clampf(maxf(v, _value), 0.0, 1.0)
	if is_equal_approx(next, _value) and not _history.is_empty():
		return
	_value = next
	_history.append(_value)
	_show()
	changed.emit(_value)


func _show() -> void:
	if _widget != null and is_instance_valid(_widget):
		_widget.call(&"set_progress", _value)
		if _label != null and is_instance_valid(_label):
			_label.text = _base_text
	elif _label != null and is_instance_valid(_label):
		_label.text = FALLBACK_FORMAT % [_base_text, roundi(_value * 100.0)]


## Below the label, centered on the screen's horizontal axis.
func _place_widget() -> void:
	var size: Vector2 = _widget.custom_minimum_size
	if size.x <= 0.0 or size.y <= 0.0:
		size = WIDGET_FALLBACK_SIZE
	_widget.set_anchors_preset(Control.PRESET_CENTER)
	_widget.offset_left = -size.x * 0.5
	_widget.offset_right = size.x * 0.5
	_widget.offset_top = WIDGET_GAP_PX
	_widget.offset_bottom = WIDGET_GAP_PX + size.y
