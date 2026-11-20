class_name ObjectivesPanel
extends VBoxContainer
## Objectives of the first hunts (docs §8.4, "Objetivos e legenda de teclas", 1.3, game 0.8.2): up to four rows on the
## left of the HUD, each with a state mark and a line of text: order the dog to attack, use the drone, bring down N
## boars (team count) and keep the crop above P%. A finished row keeps its done mark and stays on screen.
## Pure view: the Hud feeds it from the signals it already hears (kills, crop, dog command, item used). It never
## decides whether it is shown; the Hud does (onboarding, spectator, death).
## Rows are named children (for QA): Row_dog, Row_drone, Row_kills, Row_crop, each with Mark and Text.

enum State { PENDING, OK, DONE, FAIL }

const ROW_DOG: StringName = &"dog"
const ROW_DRONE: StringName = &"drone"
const ROW_KILLS: StringName = &"kills"
const ROW_CROP: StringName = &"crop"
const ROW_ORDER: Array[StringName] = [ROW_DOG, ROW_DRONE, ROW_KILLS, ROW_CROP]

## Fallbacks of game.onboarding.objective_kills / objective_crop_min_pct (the data wins).
const DEFAULT_KILLS_GOAL: int = 3
const DEFAULT_CROP_MIN_PCT: float = 50.0

const TEXT_DOG: String = "Mande o cão atacar (%s)"
const TEXT_DRONE: String = "Use o drone (%s)"
const TEXT_KILLS_ONE: String = "Abata %d javali (%d/%d)"
const TEXT_KILLS_MANY: String = "Abata %d javalis (%d/%d)"
const TEXT_CROP: String = "Mantenha a lavoura acima de %d%%"
const TOUCH_DOG_BUTTON: String = "botão Cão"
const TOUCH_BUTTON_PREFIX: String = "botão "
const KEY_FALLBACK_DOG: String = "E"
const KEY_FALLBACK_DRONE: String = "V"
const DRONE_NAME_FALLBACK: String = "Drone"

const FONT_PX: int = 17
const OUTLINE_PX: int = 5
const ROW_SEPARATION_PX: int = 4
const MARK_PX: float = 18.0
const MARK_LINE_PX: float = 2.5
const MARK_RING_PX: float = 1.6
const MARK_RING_POINTS: int = 20
const TEXT_SEPARATION_PX: int = 8
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_GOOD: Color = Color("#3FAF5A")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_RING: Color = Color(0.96, 0.94, 0.90, 0.75)
const COLOR_MARK_BG: Color = Color(0.0, 0.0, 0.0, 0.45)


## The round mark of a row, drawn with primitives (no font glyph needed): ring = pending, green dot = holding,
## green disc with a check = done, red disc with a cross = failing.
class Mark extends Control:
	var state: int = ObjectivesPanel.State.PENDING

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2.ONE * ObjectivesPanel.MARK_PX
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_state(value: int) -> void:
		if value == state:
			return
		state = value
		queue_redraw()

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, ObjectivesPanel.COLOR_MARK_BG)
		match state:
			ObjectivesPanel.State.PENDING:
				draw_arc(c, r, 0.0, TAU, ObjectivesPanel.MARK_RING_POINTS, ObjectivesPanel.COLOR_RING,
					ObjectivesPanel.MARK_RING_PX, true)
			ObjectivesPanel.State.OK:
				draw_arc(c, r, 0.0, TAU, ObjectivesPanel.MARK_RING_POINTS, ObjectivesPanel.COLOR_GOOD,
					ObjectivesPanel.MARK_RING_PX, true)
				draw_circle(c, r * 0.45, ObjectivesPanel.COLOR_GOOD)
			ObjectivesPanel.State.DONE:
				draw_circle(c, r, ObjectivesPanel.COLOR_GOOD)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, 0.0), c + Vector2(-r * 0.12, r * 0.4),
					c + Vector2(r * 0.55, -r * 0.4)]), Color.WHITE, ObjectivesPanel.MARK_LINE_PX, true)
			ObjectivesPanel.State.FAIL:
				draw_circle(c, r, ObjectivesPanel.COLOR_DANGER)
				draw_line(c + Vector2(-r, -r) * 0.45, c + Vector2(r, r) * 0.45, Color.WHITE, ObjectivesPanel.MARK_LINE_PX, true)
				draw_line(c + Vector2(r, -r) * 0.45, c + Vector2(-r, r) * 0.45, Color.WHITE, ObjectivesPanel.MARK_LINE_PX, true)


var _rows: Dictionary = {}          # row id -> HBoxContainer
var _marks: Dictionary = {}         # row id -> Mark
var _texts: Dictionary = {}         # row id -> Label
var _states: Dictionary = {}        # row id -> State
var _kills_goal: int = DEFAULT_KILLS_GOAL
var _crop_min_pct: float = DEFAULT_CROP_MIN_PCT
var _killed: int = 0
var _total: int = 0
var _crop_pct: float = 100.0
var _dog_present: bool = false
var _drone_present: bool = false
var _dog_done: bool = false
var _drone_done: bool = false
var _kills_done: bool = false
var _touch: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", ROW_SEPARATION_PX)
	var cfg: Dictionary = Data.get_game().get("onboarding", {})
	_kills_goal = maxi(int(cfg.get("objective_kills", DEFAULT_KILLS_GOAL)), 1)
	_crop_min_pct = float(cfg.get("objective_crop_min_pct", DEFAULT_CROP_MIN_PCT))
	for row_id: StringName in ROW_ORDER:
		_build_row(row_id)
	_rows[ROW_DOG].visible = false
	_rows[ROW_DRONE].visible = false
	_refresh()


## The hunt has a dog (the row exists only then). Safe to call every poll.
func set_dog_present(present: bool) -> void:
	if present == _dog_present:
		return
	_dog_present = present
	_refresh()


## The hunter carries the scout drone (the row exists only then).
func set_drone_present(present: bool) -> void:
	if present == _drone_present:
		return
	_drone_present = present
	_refresh()


## Team kills and the hunt's total (boar_counts_changed). The goal is min(objective_kills, total) once the total is known.
func set_kills(killed: int, total: int) -> void:
	_killed = killed
	_total = total
	_refresh()


func set_crop_pct(pct: float) -> void:
	_crop_pct = pct
	_refresh()


## The hunter ordered "Pega!" (dog_command_executed with attack). A recall does not count.
func mark_dog_ordered() -> void:
	_dog_done = true
	_refresh()


## The hunter used the drone (item_used with scout_drone).
func mark_drone_used() -> void:
	_drone_done = true
	_refresh()


## Touch mode names the on-screen button instead of the key.
func set_touch(touch: bool) -> void:
	if touch == _touch:
		return
	_touch = touch
	_refresh()


## Rows on screen now, in order.
func get_row_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row_id: StringName in ROW_ORDER:
		if (_rows[row_id] as Control).visible:
			out.append(row_id)
	return out


func get_row_text(row_id: StringName) -> String:
	return (_texts[row_id] as Label).text if _texts.has(row_id) else ""


## One of State.*; State.PENDING for an unknown id.
func get_row_state(row_id: StringName) -> int:
	return int(_states.get(row_id, State.PENDING))


func get_kills_goal() -> int:
	return _effective_kills_goal()


func get_crop_min_pct() -> float:
	return _crop_min_pct


func _effective_kills_goal() -> int:
	return mini(_kills_goal, _total) if _total > 0 else _kills_goal


func _build_row(row_id: StringName) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row_%s" % row_id
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", TEXT_SEPARATION_PX)
	var mark: Mark = Mark.new()
	mark.name = "Mark"
	row.add_child(mark)
	var text: Label = Label.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.theme_type_variation = &"HudLabel"
	text.add_theme_font_size_override("font_size", FONT_PX)
	text.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	text.add_theme_constant_override("outline_size", OUTLINE_PX)
	row.add_child(text)
	add_child(row)
	_rows[row_id] = row
	_marks[row_id] = mark
	_texts[row_id] = text
	_states[row_id] = State.PENDING


func _refresh() -> void:
	(_rows[ROW_DOG] as Control).visible = _dog_present
	(_rows[ROW_DRONE] as Control).visible = _drone_present
	var dog_key: String = TOUCH_DOG_BUTTON if _touch else _key_of(&"dog_command", KEY_FALLBACK_DOG)
	_set_row(ROW_DOG, TEXT_DOG % dog_key, State.DONE if _dog_done else State.PENDING)
	_set_row(ROW_DRONE, TEXT_DRONE % _drone_hint(), State.DONE if _drone_done else State.PENDING)
	var goal: int = _effective_kills_goal()
	if _killed >= goal:
		_kills_done = true   # latched: a late change of the total must not undo it
	_set_row(ROW_KILLS, (TEXT_KILLS_ONE if goal == 1 else TEXT_KILLS_MANY) % [goal, mini(_killed, goal), goal],
		State.DONE if _kills_done else State.PENDING)
	_set_row(ROW_CROP, TEXT_CROP % int(round(_crop_min_pct)),
		State.FAIL if _crop_pct < _crop_min_pct else State.OK)


func _drone_hint() -> String:
	if _touch:
		var def: Dictionary = Data.get_equipment(Ids.I_SCOUT_DRONE)
		return TOUCH_BUTTON_PREFIX + String(def.get("short_name", DRONE_NAME_FALLBACK))
	return _key_of(InputSetup.get_item_action(Ids.I_SCOUT_DRONE), KEY_FALLBACK_DRONE)


func _key_of(action_name: StringName, fallback: String) -> String:
	var label: String = InputSetup.get_key_label(action_name)
	return label if not label.is_empty() else fallback


func _set_row(row_id: StringName, text: String, state: int) -> void:
	_states[row_id] = state
	(_marks[row_id] as Mark).set_state(state)
	var label: Label = _texts[row_id]
	label.text = text
	var color: Color = COLOR_TEXT
	if state == State.DONE:
		color = COLOR_GOOD
	elif state == State.FAIL:
		color = COLOR_DANGER
	label.add_theme_color_override("font_color", color)
