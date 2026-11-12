extends Node
## Autoload "Router": the only place that changes scenes, plus the portrait-orientation warning.
## See docs/arquitetura.md §6.6 and §11.

const ORIENTATION_LAYER: int = 100
const ORIENTATION_TEXT: String = "Gire o aparelho para jogar na horizontal"

var selected_map_id: StringName = &"mato_grosso"
var selected_contract_index: int = 0
var last_result: HuntResult = null

var _pending_request: HuntRequest = null
var _orientation_layer: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_orientation_warning()
	get_viewport().size_changed.connect(_update_orientation_warning)
	_update_orientation_warning()


func goto(scene_path: String) -> void:
	get_tree().paused = false
	InputSetup.release_all_actions()
	if not ResourceLoader.exists(scene_path):
		push_error("Router.goto: scene not found: %s" % scene_path)
		return
	get_tree().change_scene_to_file.call_deferred(scene_path)


func get_current_scene_path() -> String:
	var scene: Node = get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func set_pending_request(request: HuntRequest) -> void:
	_pending_request = request


## Does not consume the request.
func get_pending_request() -> HuntRequest:
	return _pending_request


func start_hunt(request: HuntRequest) -> void:
	set_pending_request(request)
	goto(ScenePaths.HUNT)


func finish_hunt(result: HuntResult) -> void:
	last_result = result
	Profile.apply_hunt_result(result)
	goto(ScenePaths.RESULT)


func _build_orientation_warning() -> void:
	_orientation_layer = CanvasLayer.new()
	_orientation_layer.name = "OrientationWarning"
	_orientation_layer.layer = ORIENTATION_LAYER
	var back: ColorRect = ColorRect.new()
	back.color = Color(0.08, 0.07, 0.06, 0.96)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	var label: Label = Label.new()
	label.text = ORIENTATION_TEXT
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 32)
	back.add_child(label)
	_orientation_layer.add_child(back)
	_orientation_layer.visible = false
	add_child(_orientation_layer)


func _update_orientation_warning() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	_orientation_layer.visible = size.y > size.x
