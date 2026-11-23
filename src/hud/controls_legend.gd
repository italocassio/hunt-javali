class_name ControlsLegend
extends VBoxContainer
## Key legend of the first hunts (docs §8.4, "Objetivos e legenda de teclas", 1.3, game 0.8.2), keyboard/mouse only.
## Open: one row per control (key chip + what it does). Closed: only the tab "H: Ajuda". Every key label comes from
## InputSetup.get_key_label; only the mouse rows carry fixed text, because the mouse has no key action to ask.
## Pure view: the Hud decides when it is shown and forwards the help key to toggle(). Starts open.
## Children (for QA): Tab, Rows (a grid of PAIR_COLUMNS pairs per line, each pair a key chip and its text).

const ROW_MOVE: StringName = &"move"
const ROW_MOUSE_BUTTONS: StringName = &"mouse_buttons"
const ROW_RELOAD: StringName = &"reload"
const ROW_SPRINT: StringName = &"sprint"
const ROW_CROUCH: StringName = &"crouch"
const ROW_WEAPONS: StringName = &"weapons"
const ROW_KNIFE: StringName = &"knife"
const ROW_DOG: StringName = &"dog_command"
const ROW_HELP: StringName = &"help"

## Rows above the items. "actions" feed the key chip (labels joined by "joiner"); "key" is fixed text (mouse only).
const ROWS_BEFORE_ITEMS: Array[Dictionary] = [
	{"id": ROW_MOVE, "actions": [&"move_forward", &"move_left", &"move_back", &"move_right"], "joiner": "", "text": "Mover"},
	{"id": ROW_MOUSE_BUTTONS, "key": "Mouse", "text": "Atirar / Mirar"},
	{"id": ROW_RELOAD, "actions": [&"reload"], "joiner": "", "text": "Recarregar"},
	{"id": ROW_SPRINT, "actions": [&"sprint"], "joiner": "", "text": "Correr"},
	{"id": ROW_CROUCH, "actions": [&"crouch"], "joiner": "", "text": "Agachar"},
	{"id": ROW_WEAPONS, "actions": [&"weapon_1", &"weapon_5"], "joiner": "–", "text": "Armas"},
	{"id": ROW_KNIFE, "actions": [&"knife"], "joiner": "", "text": "Faca"},
]
const TEXT_DOG: String = "Mandar o cão"
const TEXT_HELP_OPEN: String = "Recolher"
const TAB_TEXT: String = "%s: Ajuda"
const KEY_FALLBACK_HELP: String = "H"

const FONT_PX: int = 16
const OUTLINE_PX: int = 5
const PAIR_COLUMNS: int = 2             # rows side by side: the legend must end above the weapon panel (720 px high)
const GRID_H_SEPARATION_PX: int = 8
const GRID_V_SEPARATION_PX: int = 3
const PAIR_GAP_PX: float = 14.0
const KEY_MARGIN_H_PX: float = 5.0
const KEY_RADIUS_PX: int = 4
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_KEY_BG: Color = Color(0.0, 0.0, 0.0, 0.7)

var _tab: Label = null
var _grid: GridContainer = GridContainer.new()
var _item_ids: Array[StringName] = []
var _dog_present: bool = false
var _open: bool = true
var _row_ids: Array[StringName] = []
var _keys: Dictionary = {}     # row id -> chip Label
var _texts: Dictionary = {}    # row id -> text Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab = _make_label("Tab", "", COLOR_TEXT)
	add_child(_tab)
	_grid.name = "Rows"
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.columns = PAIR_COLUMNS * 2
	_grid.add_theme_constant_override("h_separation", GRID_H_SEPARATION_PX)
	_grid.add_theme_constant_override("v_separation", GRID_V_SEPARATION_PX)
	add_child(_grid)
	_rebuild()


## The usable items the hunter carries (ItemBelt.get_usable_ids order): one row each, with the key of its action.
func set_items(item_ids: Array[StringName]) -> void:
	if item_ids == _item_ids:
		return
	_item_ids = item_ids.duplicate()
	_rebuild()


## The hunt has a dog: the "E" row exists only then.
func set_dog_present(present: bool) -> void:
	if present == _dog_present:
		return
	_dog_present = present
	_rebuild()


func set_open(open: bool) -> void:
	_open = open
	_apply_open()


## What the help key does: open <-> tab.
func toggle() -> void:
	set_open(not _open)


func is_open() -> bool:
	return _open


## Rows on screen when open, in order.
func get_row_ids() -> Array[StringName]:
	return _row_ids.duplicate()


## Key chip text of a row ("" for an unknown id).
func get_key_text(row_id: StringName) -> String:
	return (_keys[row_id] as Label).text if _keys.has(row_id) else ""


func get_row_text(row_id: StringName) -> String:
	return (_texts[row_id] as Label).text if _texts.has(row_id) else ""


## "H: Ajuda", the tab of the closed legend.
func get_tab_text() -> String:
	return _tab.text


func _rebuild() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_row_ids.clear()
	_keys.clear()
	_texts.clear()
	for def: Dictionary in ROWS_BEFORE_ITEMS:
		var key_text: String = String(def["key"]) if def.has("key") else _joined_labels(def["actions"], String(def["joiner"]))
		_add_row(def["id"], key_text, String(def["text"]))
	for item_id: StringName in _item_ids:
		var action_name: StringName = InputSetup.get_item_action(item_id)
		if action_name == &"":
			continue
		var item_def: Dictionary = Data.get_equipment(item_id)
		_add_row(item_id, InputSetup.get_key_label(action_name), String(item_def.get("short_name", item_def.get("name", ""))))
	if _dog_present:
		_add_row(ROW_DOG, InputSetup.get_key_label(&"dog_command"), TEXT_DOG)
	var help_key: String = _help_key()
	_add_row(ROW_HELP, help_key, TEXT_HELP_OPEN)
	_tab.text = TAB_TEXT % help_key
	_apply_open()


func _apply_open() -> void:
	_grid.visible = _open
	_tab.visible = not _open


func _help_key() -> String:
	var label: String = InputSetup.get_key_label(&"help")
	return label if not label.is_empty() else KEY_FALLBACK_HELP


func _joined_labels(actions: Array, joiner: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for action_name: StringName in actions:
		parts.append(InputSetup.get_key_label(action_name))
	return joiner.join(parts)


func _add_row(row_id: StringName, key_text: String, text: String) -> void:
	var key: Label = _make_label("Key_%s" % row_id, key_text, COLOR_TEXT)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = COLOR_KEY_BG
	bg.set_corner_radius_all(KEY_RADIUS_PX)
	bg.content_margin_left = KEY_MARGIN_H_PX
	bg.content_margin_right = KEY_MARGIN_H_PX
	key.add_theme_stylebox_override("normal", bg)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grid.add_child(key)
	var label: Label = _make_label("Text_%s" % row_id, text, COLOR_TEXT)
	if _row_ids.size() % PAIR_COLUMNS != PAIR_COLUMNS - 1:   # not the last pair of the line: leave a gap before the next
		var gap: StyleBoxEmpty = StyleBoxEmpty.new()
		gap.content_margin_right = PAIR_GAP_PX
		label.add_theme_stylebox_override("normal", gap)
	_grid.add_child(label)
	_row_ids.append(row_id)
	_keys[row_id] = key
	_texts[row_id] = label


func _make_label(label_name: String, text: String, color: Color) -> Label:
	var l: Label = Label.new()
	l.name = label_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"HudLabel"
	l.add_theme_font_size_override("font_size", FONT_PX)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", OUTLINE_PX)
	return l
