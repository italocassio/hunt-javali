class_name DogCard
extends HBoxContainer
## The dog card of the HUD (docs §8.4, 1.3): breed portrait, breed name, the state in colour, the health bar and
## the next action ("E: Pega!" / "E: Volta!"). Pure view: the Hud feeds it (breed, state, health, touch mode).
## Children (for QA): Portrait, Info/Name, Info/State, Info/HealthBar, Info/Action.

const PORTRAIT_PX: float = 40.0
const BAR_WIDTH_PX: float = 150.0
const BAR_HEIGHT_PX: float = 10.0
const NAME_FONT_PX: int = 16
const STATE_FONT_PX: int = 18
const ACTION_FONT_PX: int = 16
const OUTLINE_PX: int = 5
const SEPARATION_PX: int = 8
const INFO_SEPARATION_PX: int = 0
const BAR_RADIUS_PX: int = 4
const HEALTH_GOOD_PCT: float = 50.0
const HEALTH_WARN_PCT: float = 30.0
const DIM_ALPHA: float = 0.55
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_HIGHLIGHT: Color = Color("#F2C12E")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_GOOD: Color = Color("#3FAF5A")
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.55)
const FALLBACK_NAME: String = "Cão"
const KEY_FALLBACK: String = "E"
const TOUCH_KEY_TEXT: String = "Botão Cão"
const ACTION_ATTACK: String = "%s: Pega!"
const ACTION_RECALL: String = "%s: Volta!"
const ACTION_RETREAT: String = "Ferido: voltando"
const STATE_TEXT: Dictionary = {
	"follow": "Seguindo", "seek": "Procurando", "point": "Apontando", "bay": "Acuando",
	"hold": "Segurando", "retreat": "Ferido", "return": "Voltando",
}
## Colour of the state line: the highlighted states are the ones where the dog holds a boar for the hunter.
const HIGHLIGHT_STATES: Array[StringName] = [Ids.DS_POINT, Ids.DS_BAY, Ids.DS_HOLD]

var _portrait: TextureRect = TextureRect.new()
var _name: Label = null
var _state_label: Label = null
var _bar: ProgressBar = ProgressBar.new()
var _action: Label = null
var _state: StringName = Ids.DS_FOLLOW
var _touch: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", SEPARATION_PX)
	_portrait.name = "Portrait"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.custom_minimum_size = Vector2.ONE * PORTRAIT_PX
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_portrait)
	var info: VBoxContainer = VBoxContainer.new()
	info.name = "Info"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", INFO_SEPARATION_PX)
	_name = _make_label("Name", FALLBACK_NAME, NAME_FONT_PX)
	info.add_child(_name)
	_state_label = _make_label("State", "", STATE_FONT_PX)
	info.add_child(_state_label)
	_style_bar()
	info.add_child(_bar)
	_action = _make_label("Action", "", ACTION_FONT_PX)
	info.add_child(_action)
	add_child(info)
	_refresh()


## Breed shown: its portrait (ScenePaths.icon) and its name from the data. An unknown id leaves the generic card.
func set_breed(dog_id: StringName) -> void:
	var path: String = ScenePaths.icon(dog_id) if dog_id != &"" else ""
	_portrait.texture = AssetLoader.load_resource(path) as Texture2D if not path.is_empty() and AssetLoader.exists(path) else null
	_portrait.visible = _portrait.texture != null
	var def: Dictionary = Data.get_dog(dog_id) if dog_id != &"" else {}
	_name.text = String(def.get("name", FALLBACK_NAME))


func set_state(state: StringName) -> void:
	_state = state
	_refresh()


func set_health_pct(pct: float) -> void:
	_bar.value = pct
	_bar.modulate = COLOR_GOOD if pct > HEALTH_GOOD_PCT else (COLOR_HIGHLIGHT if pct > HEALTH_WARN_PCT else COLOR_DANGER)


## Touch mode names the on-screen button instead of the key and drops the breed name (the portrait stays): the
## card must end above the Cão button of the touch layer, which sits right under it.
func set_touch(touch: bool) -> void:
	_touch = touch
	_name.visible = not touch
	_refresh()


func get_state_text() -> String:
	return _state_label.text


func get_action_text() -> String:
	return _action.text


func get_breed_text() -> String:
	return _name.text


func _refresh() -> void:
	_state_label.text = String(STATE_TEXT.get(String(_state), String(_state)))
	var color: Color = COLOR_TEXT
	if _state == Ids.DS_RETREAT:
		color = COLOR_DANGER
	elif _state in HIGHLIGHT_STATES:
		color = COLOR_HIGHLIGHT
	_state_label.add_theme_color_override("font_color", color)
	var key: String = TOUCH_KEY_TEXT if _touch else _key_text()
	var retreating: bool = _state == Ids.DS_RETREAT
	if retreating:
		_action.text = ACTION_RETREAT
	else:
		_action.text = (ACTION_ATTACK if _state == Ids.DS_FOLLOW else ACTION_RECALL) % key
	_action.modulate.a = DIM_ALPHA if retreating else 1.0


func _key_text() -> String:
	var label: String = InputSetup.get_key_label(&"dog_command")
	return label if not label.is_empty() else KEY_FALLBACK


func _make_label(label_name: String, text: String, font_px: int) -> Label:
	var l: Label = Label.new()
	l.name = label_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"HudLabel"
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", COLOR_TEXT)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", OUTLINE_PX)
	return l


func _style_bar() -> void:
	_bar.name = "HealthBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.theme_type_variation = &"HealthBar"
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 100.0
	_bar.custom_minimum_size = Vector2(BAR_WIDTH_PX, BAR_HEIGHT_PX)
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or not theme.has_stylebox(&"fill", &"HealthBar"):
		var bg: StyleBoxFlat = StyleBoxFlat.new()
		bg.bg_color = COLOR_BAR_BG
		bg.set_corner_radius_all(BAR_RADIUS_PX)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color.WHITE   # tinted through modulate
		fill.set_corner_radius_all(BAR_RADIUS_PX)
		_bar.add_theme_stylebox_override("background", bg)
		_bar.add_theme_stylebox_override("fill", fill)
