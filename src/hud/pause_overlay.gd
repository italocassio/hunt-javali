class_name PauseOverlay
extends CanvasLayer
## Pause menu (docs §8.4, §11): Retomar / Configurações / Desistir da caçada. Layer 20, keeps
## running while the tree is paused.

const BUTTON_MIN_HEIGHT_PX: float = 72.0
const BUTTON_MIN_WIDTH_PX: float = 420.0
const DIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)
const ABANDON_TEXT_SOLO: String = "Desistir da caçada"
const ABANDON_TEXT_HOST: String = "Encerrar a caçada para todos"
const ABANDON_TEXT_CLIENT: String = "Sair da caçada"

var _open: bool = false
## Test hook (sandboxes only): a Net.Role value makes the overlay behave as if Net were in that role during an
## active hunt. -1 = ask Net.
var debug_role: int = -1
var _networked: bool = false  # the menu was opened during an online hunt (the tree is not paused)
var _opened_down: bool = false  # opened by a fallen hunter who watches the hunt online: the way out of the hunt
var _enabled: bool = true
var _player: PlayerBase = null
var _menu: VBoxContainer = null
var _settings: Control = null
var _abandon_button: Button = null
var _abandon_armed: bool = false
var _resume_button: Button = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu = VBoxContainer.new()
	_menu.name = "Menu"
	_menu.add_theme_constant_override("separation", 16)
	center.add_child(_menu)
	var title: Label = Label.new()
	title.text = "Pausado"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(title)
	_resume_button = _make_button("Retomar", &"PrimaryButton", close)
	_menu.add_child(_resume_button)
	if AssetLoader.exists(ScenePaths.SETTINGS_PANEL):
		_menu.add_child(_make_button("Configurações", &"SecondaryButton", _open_settings))
	_abandon_button = _make_button(ABANDON_TEXT_SOLO,&"DangerButton", _on_abandon_pressed)
	_menu.add_child(_abandon_button)


func bind(player: PlayerBase) -> void:
	_player = player


func is_open() -> bool:
	return _open


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled and _open:
		close(false)   # the hunt is over: nobody gets the input back


func _make_button(text: String, variation: StringName, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH_PX, BUTTON_MIN_HEIGHT_PX)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(handler)
	return b


## Polled instead of _input: the touch pause button uses Input.action_press, which sends no InputEvent.
func _process(_delta: float) -> void:
	if _open and _networked and not _opened_down and _player != null and not _player.is_alive():
		close(false)   # knocked down while the world kept running behind the menu
		return
	if not Input.is_action_just_pressed(&"pause") or _settings != null:
		return
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open or not _enabled:
		return
	var fallen: bool = _player != null and not _player.is_alive()
	if fallen and not _net_online():
		return   # solo: the fall ends the hunt on the spot
	_open = true
	_abandon_armed = false
	# Online the world keeps running (section 6.12): the tree is not paused, the hunter just stops answering input.
	_networked = _net_online()
	_opened_down = fallen   # a fallen hunter can still leave the hunt (spectators must not be stuck until it ends)
	_abandon_button.text = _abandon_text()
	visible = true
	get_tree().paused = not _networked
	if _networked and _player != null:
		_player.set_input_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	InputSetup.release_all_actions()
	GameEvents.hunt_paused_changed.emit(true)
	_resume_button.grab_focus()


## restore_input = false when the hunt ended, the hunter fell or the player is leaving: input stays off.
func close(restore_input: bool = true) -> void:
	if not _open:
		return
	_open = false
	visible = false
	if _settings != null:
		_settings.queue_free()
		_settings = null
	get_tree().paused = false
	if _networked and restore_input and _player != null and _player.is_alive():
		_player.set_input_enabled(true)
	_networked = false
	_opened_down = false
	if not InputSetup.is_touch_mode() and not _is_bot():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # the click on "Retomar" is a valid gesture
	GameEvents.hunt_paused_changed.emit(false)


func _is_bot() -> bool:
	return _player != null and _player.has_method("is_bot") and _player.call("is_bot")


func _on_abandon_pressed() -> void:
	if not _abandon_armed:
		_abandon_armed = true
		_abandon_button.text = "Toque de novo para confirmar"
		return
	# Unpause first so the hunt controller can finish and route to the result screen.
	var leaves_room: bool = _networked and not _net_is_host()
	close(false)
	if leaves_room:
		Net.leave_room()   # a client walks out alone; the host's abandon ends the hunt for everyone
	GameEvents.hunt_abandon_requested.emit()


func _abandon_text() -> String:
	if not _networked:
		return ABANDON_TEXT_SOLO
	return ABANDON_TEXT_HOST if _net_is_host() else ABANDON_TEXT_CLIENT


func _net_online() -> bool:
	if debug_role >= 0:
		return debug_role != Net.Role.OFFLINE
	return Net.is_active()


func _net_is_host() -> bool:
	if debug_role >= 0:
		return debug_role == Net.Role.HOST
	return Net.is_host()


func _open_settings() -> void:
	var panel: Control = AssetLoader.instantiate(ScenePaths.SETTINGS_PANEL) as Control
	if panel == null:
		return
	_settings = panel
	_menu.get_parent().visible = false
	add_child(panel)
	if panel.has_signal(&"closed"):
		panel.connect(&"closed", _on_settings_closed)


func _on_settings_closed() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
	_menu.get_parent().visible = true
