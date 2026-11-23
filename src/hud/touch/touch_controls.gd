class_name TouchControls
extends CanvasLayer
## Touch layer (CanvasLayer 11, docs §8.4). Real multitouch: every finger is bound by index to one
## widget (joystick, look pad, a button, a weapon card or the zoom slider) when it goes down. Emulated mouse
## events are never used, so tapping to look cannot fire the weapon.
## PUBG-style layout (HF7): two Fire buttons (both press the `fire` action, counted per finger), a Cure button
## and one Accessories button with an upward list, and the weapon cards of the Hud (taps on them select a weapon).

## The Hud places the weapon cards and the health bar from this block after every layout (see get_bottom_block).
signal layout_changed()

const SURFACE_MARGIN_PX: float = 24.0
const JOYSTICK_CENTER_FROM_LEFT_PX: float = 242.0   # fixed stick centre, bottom-left area
const JOYSTICK_CENTER_FROM_BOTTOM_PX: float = 220.0
## Backpack (future item, owner's mock-up #3): reserved spot, centre 77 px from the left and 59 px from the bottom.
## No button and no drawing yet; keep this corner free.
# const BACKPACK_FROM_LEFT_PX: float = 77.0
# const BACKPACK_FROM_BOTTOM_PX: float = 59.0
## Buttons whose finger also steers the camera when dragged (shoot / aim while tracking a target). Button ids.
const LOOK_BUTTONS: Array[StringName] = [&"fire", &"fire_left", &"aim"]
const HIT_PADDING_PX: float = 8.0
const SLIDER_LEFT_PX: float = 32.0
const SLIDER_WIDTH_PX: float = 84.0
const SLIDER_TOP_MIN_PX: float = 130.0       # clear of the pause button and the zoom label above the track
const SLIDER_HEIGHT_FRAC: float = 0.42       # of the screen height, when there is room
const SLIDER_TRACK_WIDTH_PX: float = 10.0
const SLIDER_KNOB_RADIUS_PX: float = 26.0
const COLOR_FILL: Color = Color(1.0, 1.0, 1.0, 0.16)
const COLOR_FILL_DOWN: Color = Color(1.0, 1.0, 1.0, 0.38)
const COLOR_FIRE: Color = Color(0.85, 0.27, 0.17, 0.32)
const COLOR_FIRE_DOWN: Color = Color(0.85, 0.27, 0.17, 0.6)
const COLOR_RING: Color = Color(1.0, 1.0, 1.0, 0.55)
const COLOR_ON: Color = Color("#F2C12E")
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_MENU_BG: Color = Color(0.12, 0.10, 0.086, 0.72)
const COLOR_CARD_DOWN: Color = Color(1.0, 1.0, 1.0, 0.22)
const FONT_SIZE: int = 20
const ITEM_NAME_FONT_PX: int = 16
const ITEM_COUNT_FONT_PX: int = 16
const LABEL_BELOW_GAP_PX: float = 20.0       # baseline of a name under the circle, from its edge
const LABEL_ABOVE_GAP_PX: float = 6.0        # baseline of a name above the circle, from its edge
## Circles whose centre is closer than this to the bottom edge draw their name above (never off the screen).
const LABEL_ABOVE_ZONE_PX: float = 130.0
const DOG_SLOT: StringName = &"dog_command"
const INTERACT_ACTION: StringName = &"interact"   # horde level 2: a downed ally ("Levantar") or an ammo crate in reach
const INTERACT_LABEL_CRATE: String = "Pegar"      # the same button over an ammo crate (no revive target)
const PAUSE_ACTION: StringName = &"pause"
const FIRE_ACTION: StringName = &"fire"
const FLASH_HZ: float = 2.0
const DIM_ALPHA: float = 0.35
const BUSY_VEIL: Color = Color(0.0, 0.0, 0.0, 0.55)
const BUSY_SECTOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const COLOR_DANGER: Color = Color("#D9452B")
const BUSY_SECTOR_STEPS: int = 48

## Fixed buttons (diameters, offsets from the corner in virtual px; the owner's marked mock-up, 1532x720).
const FIRE_D: float = 120.0
const FIRE_LEFT_D: float = 100.0
const FIRE_LEFT_FROM_LEFT_PX: float = 69.0
const FIRE_LEFT_FROM_BOTTOM_PX: float = 355.0
const AIM_D: float = 76.0
const RELOAD_D: float = 64.0
const RELOAD_FROM_RIGHT_PX: float = 359.0
const CROUCH_D: float = 72.0
const CURA_D: float = 64.0
const ACCESSORY_D: float = 70.0
## Centre height of the Cure and Accessories buttons above the bottom edge.
const BLOCK_BOTTOM_PX: float = 50.0

## Bottom block (the Hud's weapon cards, health bar and vest chip sit between Cure and Accessories). Left to right:
## Cure | gap | vest chip | gap | card | gap | card | gap | Accessories. All widths are fixed except the cards, which
## shrink when the screen is narrow: the block must fit between the joystick and the Reload button.
const CARD_W_MAX_PX: float = 167.0
const CARD_W_MIN_PX: float = 130.0
const CARD_GAP_PX: float = 8.0
const CARD_ACCESSORY_GAP_PX: float = 10.0   # card to Accessories: the circle hit padding (8) stays off the card
const VEST_CHIP_GAP_PX: float = 6.0          # vest chip to the health bar
const CURA_CHIP_GAP_PX: float = 6.0          # Cure button to the vest chip

## Accessories (ceva, drone, binoculars): one main button, a small tab above it and an upward list.
const ARROW_HIT_SIZE: Vector2 = Vector2(56.0, 44.0)
const ARROW_VISUAL_SIZE: Vector2 = Vector2(44.0, 24.0)
const ARROW_OVERLAP_PX: float = 2.0          # the tab touches the top of the main circle
const MENU_ITEM_D: float = 60.0
const MENU_GAP_PX: float = 6.0
const MENU_HIT_PAD_PX: float = 3.0           # half the gap: the rows of the list never share a touch
const MENU_PAD_PX: float = 6.0
const MENU_RADIUS_PX: int = 10
const ARROW_HALF_W_PX: float = 9.0
const ARROW_HALF_H_PX: float = 5.0

const CARD_ID_PREFIX: String = "weapon_card_"
const MENU_ID: StringName = &"accessory_menu"

## id, action, diameter, label, icon id, offset from a corner (dx, dy as positive numbers), mode: "hold" presses
## while touched, "toggle" flips on each tap. `from`: br / bl / tl corners, cura / acc = the bottom block (see
## get_bottom_block). Two buttons can press the same action (fire / fire_left).
## The dog button only exists while there is a dog (set_dog_present); the interact button ("Levantar") only while a
## downed ally is in reach, or ("Pegar") an ammo crate worth taking, and a downed hunter keeps only the pause button
## and the look drag. The Cure and Accessories buttons are added by _rebuild_buttons from the item belt.
const BUTTONS: Array[Dictionary] = [
	{"id": &"fire", "action": &"fire", "d": FIRE_D, "label": "Tiro", "icon": &"btn_fire", "from": "br", "ox": 245.0, "oy": 181.0, "mode": "hold", "above": true},
	{"id": &"fire_left", "action": &"fire", "d": FIRE_LEFT_D, "label": "Tiro", "icon": &"btn_fire", "from": "bl", "ox": FIRE_LEFT_FROM_LEFT_PX, "oy": FIRE_LEFT_FROM_BOTTOM_PX, "mode": "hold"},
	{"id": &"aim", "action": &"aim", "d": AIM_D, "label": "Mira", "icon": &"btn_aim", "from": "br", "ox": 108.0, "oy": 342.0, "mode": "toggle"},
	{"id": &"reload", "action": &"reload", "d": RELOAD_D, "label": "Recarga", "icon": &"btn_reload", "from": "br", "ox": RELOAD_FROM_RIGHT_PX, "oy": 47.0, "mode": "hold"},
	{"id": &"crouch", "action": &"crouch", "d": CROUCH_D, "label": "Agachar", "icon": &"btn_crouch", "from": "br", "ox": 253.0, "oy": 53.0, "mode": "hold"},
	{"id": &"dog_command", "action": &"dog_command", "d": 76.0, "label": "Cão", "icon": &"btn_dog", "from": "br", "ox": 235.0, "oy": 346.0, "mode": "hold", "slot": &"dog_command"},
	{"id": &"interact", "action": &"interact", "d": 100.0, "label": "Levantar", "icon": &"", "from": "br", "ox": 340.0, "oy": 380.0, "mode": "hold"},
	{"id": &"pause", "action": &"pause", "d": 64.0, "label": "II", "icon": &"btn_pause", "from": "tl", "ox": 56.0, "oy": 56.0, "mode": "hold"},
]

class TouchSurface extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

var joystick: TouchJoystick = TouchJoystick.new()
var look_pad: LookPad = LookPad.new()

var _player: Player = null
var _surface: TouchSurface = TouchSurface.new()
var _centers: Dictionary = {}         # button id -> Vector2
var _radii: Dictionary = {}           # button id -> float
var _finger_to_action: Dictionary = {}   # finger -> button id (despite the name; also a weapon card id)
var _finger_press: Dictionary = {}    # finger -> the action it presses (&"" = a tap that presses nothing)
var _action_fingers: Dictionary = {}  # action -> number of fingers holding it (two Fire buttons share `fire`)
var _down: Dictionary = {}            # button id -> bool (visual state)
var _toggled: Dictionary = {}         # action -> bool
var _slider_finger: int = 0
var _slider_active: bool = false
var _slot_of: Dictionary = {}         # raw platform touch id (any int, even negative) -> local slot 0..N
var _last_pos: Dictionary = {}        # slot -> last known position (deltas are computed here, never from `relative`)
var _max_delta_px: float = 150.0
var _slider_rect: Rect2 = Rect2()
var _icons: Dictionary = {}           # icon id -> Texture2D
var _defs: Array[Dictionary] = []     # buttons that exist right now (BUTTONS minus an absent dog, plus Cure / Accessories)
var _items: ItemBelt = null
var _dog_present: bool = false
var _dog_retreating: bool = false
var _flashing: Dictionary = {}        # slot id -> true
var _ended: bool = false
var _action_labels: bool = false      # onboarding: every action button shows its name next to the circle
var _revive_on: bool = false          # a downed ally is in reach: the interact button exists ("Levantar")
var _crate_on: bool = false           # an ammo crate is in reach (no revive target): the interact button exists ("Pegar")
var _downed: bool = false             # the local hunter is down: only pause and the look drag are left
var _block: Dictionary = {}           # get_bottom_block()
var _card_rects: Array[Rect2] = []    # weapon cards (virtual px), set by the Hud
var _card_actions: Array[StringName] = []   # action pressed by a tap on each card (&"" = the weapon in hand)
var _acc_ids: Array[StringName] = []  # accessories carried (ceva, drone, binoculars), in ITEM_ACTIONS order
var _acc_current: StringName = &""    # the one the main button uses
var _acc_last_count: int = -1         # count of the current one at the last check (auto-switch only on running out)
var _menu_open: bool = false
var _arrow_on: bool = false
var _arrow_rect: Rect2 = Rect2()      # hit rectangle of the tab
var _menu_ids: Array[StringName] = []
var _menu_centers: Array[Vector2] = []
var _menu_style: StyleBoxFlat = StyleBoxFlat.new()
var _tab_style: StyleBoxFlat = StyleBoxFlat.new()


## The weapon cards and the vest chip are laid out around the bottom block. `left_limit` is the right edge of the
## joystick; the right limit is the left edge of the Reload button minus two hit paddings (circles never touch).
## Returns {center_x, card_w, cura_x, acc_x}: the cards are two `card_w` wide with CARD_GAP_PX between, centred on
## `center_x` (the screen centre when the block fits there), Cure and Accessories centres at x `cura_x` / `acc_x`.
static func compute_bottom_block(screen: Vector2, left_limit: float) -> Dictionary:
	var right_limit: float = screen.x - RELOAD_FROM_RIGHT_PX - RELOAD_D * 0.5 - 2.0 * HIT_PADDING_PX
	var side_fixed: float = CARD_GAP_PX * 0.5
	var left_fixed: float = side_fixed + VEST_CHIP_GAP_PX + HealthStrip.VEST_CHIP_W_PX + CURA_CHIP_GAP_PX + CURA_D
	var right_fixed: float = side_fixed + CARD_ACCESSORY_GAP_PX + ACCESSORY_D
	var card_w: float = clampf((right_limit - left_limit - left_fixed - right_fixed) * 0.5, CARD_W_MIN_PX, CARD_W_MAX_PX)
	var center_x: float = clampf(screen.x * 0.5, left_limit + left_fixed + card_w, right_limit - right_fixed - card_w)
	return {
		"center_x": center_x,
		"card_w": card_w,
		"cura_x": center_x - card_w - left_fixed + CURA_D * 0.5,
		"acc_x": center_x + card_w + right_fixed - ACCESSORY_D * 0.5,
	}


func _ready() -> void:
	layer = 11
	_max_delta_px = float(Data.get_game().get("player", {}).get("touch_max_delta_px", 150.0))
	_menu_style.bg_color = COLOR_MENU_BG
	_menu_style.set_corner_radius_all(MENU_RADIUS_PX)
	_tab_style.bg_color = COLOR_FILL
	_tab_style.set_corner_radius_all(MENU_RADIUS_PX)
	_tab_style.set_border_width_all(2)
	_tab_style.border_color = COLOR_RING
	add_child(_surface)
	_surface.add_child(joystick)
	_surface.add_child(look_pad)
	joystick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	look_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.draw.connect(_draw_surface)
	_rebuild_buttons()
	look_pad.look.connect(_on_look)
	get_viewport().size_changed.connect(_layout)
	GameEvents.touch_mode_changed.connect(_on_touch_mode_changed)
	GameEvents.hunt_paused_changed.connect(_on_paused_changed)
	_layout()
	_apply_visibility(InputSetup.is_touch_mode())


func bind(player: Player) -> void:
	_player = player
	_items = player.get_items()
	_rebuild_buttons()


## The dog button exists only while the hunt has a dog.
func set_dog_present(present: bool) -> void:
	if present == _dog_present:
		return
	_dog_present = present
	if not present:
		_dog_retreating = false
		_flashing.erase(DOG_SLOT)
	_rebuild_buttons()


func set_dog_state(state: StringName) -> void:
	_dog_retreating = state == Ids.DS_RETREAT


## Blinks the amber ring of a button (slot ids as in the Quickbar) until flash_slot(id, false). An accessory that
## is not the current one blinks the tab (and its row in the list, while the list is open).
func flash_slot(slot_id: StringName, on: bool) -> void:
	if on:
		_flashing[slot_id] = true
	else:
		_flashing.erase(slot_id)


## During the first hunts (docs §8.4) the action buttons (Tiro, Mira, Recarga, Agachar) show their name next to the
## circle, like the item and dog buttons always do. Off: the buttons look as before. The Hud decides.
func set_action_labels(on: bool) -> void:
	if on == _action_labels:
		return
	_action_labels = on
	_surface.queue_redraw()


func has_action_labels() -> bool:
	return _action_labels


## The Hud places the weapon cards (single source of the rectangles) and tells the touch layer where they are.
## `actions[i]` is what a tap on card i presses (`weapon_1`...); &"" (the weapon in hand) is a tap that does nothing.
## Missing actions default to `weapon_<i+1>`. An empty list removes the cards (spectator, no weapon).
func set_weapon_card_rects(rects: Array[Rect2], actions: Array[StringName] = []) -> void:
	var wanted: Array[StringName] = []
	for i: int in rects.size():
		wanted.append(actions[i] if i < actions.size() else StringName("weapon_%d" % (i + 1)))
	if rects == _card_rects and wanted == _card_actions:
		return
	_release_card_fingers()
	_card_rects = rects.duplicate()
	_card_actions = wanted
	_surface.queue_redraw()


func get_weapon_card_rects() -> Array[Rect2]:
	return _card_rects.duplicate()


## {center_x, card_w, cura_x, acc_x} of the last layout (see compute_bottom_block); empty before the first one.
func get_bottom_block() -> Dictionary:
	return _block.duplicate()


func end_hunt() -> void:
	_ended = true
	_release_everything()
	_apply_visibility(false)


## `action_name` is the button id: the action for most buttons (`use_medkit`, `reload`), `fire_left` for the second Fire.
func get_button_center(action_name: StringName) -> Vector2:
	return _centers.get(action_name, Vector2.INF)


func get_button_radius(action_name: StringName) -> float:
	return float(_radii.get(action_name, 0.0))


func get_button_diameters() -> Dictionary:
	var out: Dictionary = {}
	for button_id: StringName in _radii:
		out[button_id] = float(_radii[button_id]) * 2.0
	return out


## Everything a QA probe can tap, {id: Vector3(x, y, radius)} in viewport px: the buttons (the accessory button under
## the action of the current accessory, e.g. `use_corn_bait`), the tab (`accessory_menu`, only with 2+ accessories),
## the rows of the open list (`accessory_item_<id>`) and the weapon cards (`weapon_card_1`, ..., radius = half height).
func get_probe_buttons() -> Dictionary:
	var out: Dictionary = {}
	for button_id: StringName in _centers:
		var c: Vector2 = _centers[button_id]
		out[String(button_id)] = Vector3(c.x, c.y, float(_radii.get(button_id, 0.0)))
	if _arrow_on:
		var a: Vector2 = _arrow_rect.get_center()
		out[String(MENU_ID)] = Vector3(a.x, a.y, _arrow_rect.size.y * 0.5)
	if _menu_open:
		for i: int in _menu_ids.size():
			out["accessory_item_%s" % _menu_ids[i]] = Vector3(_menu_centers[i].x, _menu_centers[i].y, MENU_ITEM_D * 0.5)
	for i: int in _card_rects.size():
		var cc: Vector2 = _card_rects[i].get_center()
		out["%s%d" % [CARD_ID_PREFIX, i + 1]] = Vector3(cc.x, cc.y, _card_rects[i].size.y * 0.5)
	return out


## Text drawn on (or under) an existing button; "" when the button does not exist now.
func get_button_label(button_id: StringName) -> String:
	for def: Dictionary in _defs:
		if def["id"] == button_id:
			return String(def["label"])
	return ""


## The accessory the main button uses now (an item id, &"" = none carried) and whether the list is open.
func get_accessory_current() -> StringName:
	return _acc_current


func get_accessory_ids() -> Array[StringName]:
	return _acc_ids.duplicate()


func is_accessory_menu_open() -> bool:
	return _menu_open


## Any touch outside the stick, the buttons and the slider looks, so the look zone starts at the left edge.
func get_look_zone_start_x() -> float:
	return 0.0


func get_slider_rect() -> Rect2:
	return _slider_rect


func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Rebuilds the list of existing buttons (fixed ones, the dog while present, Cure, Accessories) and lays
## them out. A finger that was holding a button that no longer exists is released.
func _rebuild_buttons() -> void:
	_refresh_accessory_ids()
	_defs.clear()
	for def: Dictionary in BUTTONS:
		var button_id: StringName = def["id"]
		if button_id == DOG_SLOT and not _dog_present:
			continue
		if button_id == INTERACT_ACTION and not _revive_on and not _crate_on:
			continue
		if _downed and button_id != PAUSE_ACTION:
			continue
		if button_id == INTERACT_ACTION and not _revive_on:
			var crate_def: Dictionary = def.duplicate()
			crate_def["label"] = INTERACT_LABEL_CRATE
			_defs.append(crate_def)
			continue
		_defs.append(def)
	if _items != null and not _downed:
		var medkit_action: StringName = InputSetup.get_item_action(Ids.I_MEDKIT)
		if medkit_action != &"" and _items.has_item(Ids.I_MEDKIT):
			_defs.append(_item_def(Ids.I_MEDKIT, medkit_action, CURA_D, "cura"))
		if _acc_current != &"":
			_defs.append(_item_def(_acc_current, InputSetup.get_item_action(_acc_current), ACCESSORY_D, "acc"))
	for def: Dictionary in _defs:
		_load_icon(def["icon"])
	for acc_id: StringName in _acc_ids:
		_load_icon(acc_id)
	_centers.clear()
	_radii.clear()
	_layout()
	for finger: int in _finger_to_action.keys():
		var held: StringName = _finger_to_action[finger]
		if not _radii.has(held) and not String(held).begins_with(CARD_ID_PREFIX):
			_release_button_finger(finger)
			_finger_to_action.erase(finger)


func _item_def(item_id: StringName, action_name: StringName, diameter: float, from: String) -> Dictionary:
	var item: Dictionary = Data.get_equipment(item_id)
	return {"id": action_name, "action": action_name, "d": diameter, "icon": item_id, "slot": item_id,
		"label": String(item.get("short_name", item.get("name", ""))), "from": from, "mode": "hold", "item": true}


func _load_icon(icon_id: StringName) -> void:
	if icon_id != &"" and not _icons.has(icon_id) and AssetLoader.exists(ScenePaths.icon(icon_id)):
		_icons[icon_id] = AssetLoader.load_resource(ScenePaths.icon(icon_id))


func _layout() -> void:
	var s: Vector2 = _screen_size()
	joystick.rest_center = Vector2(JOYSTICK_CENTER_FROM_LEFT_PX, s.y - JOYSTICK_CENTER_FROM_BOTTOM_PX)
	_block = compute_bottom_block(s, joystick.rest_center.x + joystick.radius_px)
	for def: Dictionary in _defs:
		var c: Vector2
		var ox: float = float(def.get("ox", 0.0))
		var oy: float = float(def.get("oy", 0.0))
		match String(def["from"]):
			"br":
				c = Vector2(s.x - ox, s.y - oy)
			"bl":
				c = Vector2(ox, s.y - oy)
			"cura":
				c = Vector2(float(_block["cura_x"]), s.y - BLOCK_BOTTOM_PX)
			"acc":
				c = Vector2(float(_block["acc_x"]), s.y - BLOCK_BOTTOM_PX)
			_:
				c = Vector2(ox, oy)
		_centers[def["id"]] = c
		_radii[def["id"]] = float(def["d"]) * 0.5
	# Zoom slider: the left column above the left Fire button (it does not touch it, the pause button or the
	# objectives panel, which starts at x 128). Its bottom stays clear of the Fire hit circle.
	var fire_left_top: float = s.y - FIRE_LEFT_FROM_BOTTOM_PX - FIRE_LEFT_D * 0.5 - 2.0 * HIT_PADDING_PX
	var slider_h: float = minf(s.y * SLIDER_HEIGHT_FRAC, fire_left_top - SLIDER_TOP_MIN_PX)
	_slider_rect = Rect2(Vector2(SLIDER_LEFT_PX, fire_left_top - slider_h), Vector2(SLIDER_WIDTH_PX, slider_h))
	_layout_accessory_menu()
	_surface.queue_redraw()
	layout_changed.emit()


## The tab sits on top of the main Accessories circle (only with 2+ accessories) and the list climbs from it.
func _layout_accessory_menu() -> void:
	_menu_ids.clear()
	_menu_centers.clear()
	var main_id: StringName = _acc_button_id()
	_arrow_on = main_id != &"" and _centers.has(main_id) and _acc_ids.size() >= 2 and not _downed
	if not _arrow_on:
		_arrow_rect = Rect2()
		_menu_open = false
		return
	var c: Vector2 = _centers[main_id]
	var r: float = float(_radii[main_id])
	_arrow_rect = Rect2(Vector2(c.x - ARROW_HIT_SIZE.x * 0.5, c.y - r + ARROW_OVERLAP_PX - ARROW_HIT_SIZE.y), ARROW_HIT_SIZE)
	var y: float = _arrow_rect.position.y - MENU_GAP_PX - MENU_ITEM_D * 0.5
	for acc_id: StringName in _acc_ids:
		_menu_ids.append(acc_id)
		_menu_centers.append(Vector2(c.x, y))
		y -= MENU_ITEM_D + MENU_GAP_PX


func _acc_button_id() -> StringName:
	return InputSetup.get_item_action(_acc_current) if _acc_current != &"" else &""


# --- Accessories ---

func _refresh_accessory_ids() -> void:
	_acc_ids.clear()
	if _items != null:
		for item_id: StringName in _items.get_usable_ids():
			if item_id != Ids.I_MEDKIT and InputSetup.get_item_action(item_id) != &"":
				_acc_ids.append(item_id)
	_sync_accessory_current()
	if _menu_open and _acc_ids.size() < 2:
		_menu_open = false


## 0 = out of stock. Active items (binoculars) have no count (-1) and never run out.
func _acc_count(item_id: StringName) -> int:
	return _items.get_count(item_id) if _items != null else -1


func _first_accessory_in_stock() -> StringName:
	for item_id: StringName in _acc_ids:
		if _acc_count(item_id) != 0:
			return item_id
	return &""


## Keeps the main button on a valid accessory: the first one in stock at the start, the next one in stock when the
## current one runs out (only when its count falls to 0, so the hunter can still pick an empty one from the list).
## True when the current accessory changed.
func _sync_accessory_current() -> bool:
	var previous: StringName = _acc_current
	if _acc_ids.is_empty():
		_acc_current = &""
		_acc_last_count = -1
	elif not _acc_ids.has(_acc_current):
		_acc_current = _first_accessory_in_stock()
		if _acc_current == &"":
			_acc_current = _acc_ids[0]
	elif _acc_count(_acc_current) == 0 and _acc_last_count != 0:
		var other: StringName = _first_accessory_in_stock()
		if other != &"":
			_acc_current = other
	_acc_last_count = _acc_count(_acc_current) if _acc_current != &"" else -1
	return _acc_current != previous


func _select_accessory(item_id: StringName) -> void:
	if not _acc_ids.has(item_id):
		return
	_acc_current = item_id
	_acc_last_count = _acc_count(item_id)
	_rebuild_buttons()


## Makes `item_id` the accessory of the main button without using it, and closes the list (the HUD does this when the
## energy drink is worth drinking). False when the item is not among the accessories carried.
func select_accessory(item_id: StringName) -> bool:
	if not _acc_ids.has(item_id):
		return false
	_close_menu()
	_select_accessory(item_id)
	return true


func _close_menu() -> void:
	if _menu_open:
		_menu_open = false
		_surface.queue_redraw()


func _menu_item_at(pos: Vector2) -> StringName:
	if not _menu_open:
		return &""
	for i: int in _menu_ids.size():
		if pos.distance_to(_menu_centers[i]) <= MENU_ITEM_D * 0.5 + MENU_HIT_PAD_PX:
			return _menu_ids[i]
	return &""


func _on_touch_mode_changed(is_touch: bool) -> void:
	if not is_touch:
		_release_everything()
	_apply_visibility(is_touch and not _ended)


func _apply_visibility(touch: bool) -> void:
	# _input stays on even while hidden: InputSetup (autoload) sees the first touch after this node,
	# so the press that turns touch mode on must already be tracked here.
	visible = touch
	set_process(touch)
	joystick.set_process(touch)
	_surface.queue_redraw()


func _release_everything() -> void:
	for finger: int in _finger_to_action.keys():
		_release_button_finger(finger)
	_finger_to_action.clear()
	_finger_press.clear()
	for action_name: StringName in _action_fingers.keys():
		Input.action_release(action_name)
	_action_fingers.clear()
	if joystick.is_active():
		joystick.end()
	look_pad.end()
	_slider_active = false
	_slot_of.clear()
	_last_pos.clear()
	joystick.unlock_run()
	for action_name: StringName in _toggled.keys():
		if bool(_toggled[action_name]):
			Input.action_release(action_name)
	_toggled.clear()
	_down.clear()
	_menu_open = false


func _release_card_fingers() -> void:
	for finger: int in _finger_to_action.keys():
		if String(_finger_to_action[finger]).begins_with(CARD_ID_PREFIX):
			_release_button_finger(finger)
			_finger_to_action.erase(finger)


func _process(_delta: float) -> void:
	_sync_revive_state()
	if _items != null and not _downed and _sync_accessory_current():
		_rebuild_buttons()
	# The aim toggle must follow the player: if the player dropped the aim (death, pause), reset it.
	if _player != null and bool(_toggled.get(&"aim", false)) and not _player.is_alive():
		_toggled[&"aim"] = false
		Input.action_release(&"aim")
	# A locked run ends when the hunter aims, crouches, or is gone.
	if joystick.run_locked and (_player == null or not _player.is_alive() or _player.is_aiming()
			or _player.is_crouching() or Input.is_action_pressed(&"aim") or Input.is_action_pressed(&"crouch")):
		joystick.unlock_run()
	_surface.queue_redraw()


## The interact button follows get_revive_target_slot(), get_ammo_crate_target() and the fall of the local hunter (all
## read from the player). A revive target wins over a crate.
func _sync_revive_state() -> void:
	if _player == null:
		return
	var downed: bool = _player.is_downed()
	var target: bool = not downed and _player.get_revive_target_slot() >= 0
	var crate: bool = not downed and not target and _player.get_ammo_crate_target() >= 0
	if downed == _downed and target == _revive_on and crate == _crate_on:
		return
	var went_down: bool = downed and not _downed
	_downed = downed
	_revive_on = target
	_crate_on = crate
	if went_down:
		_release_everything()
	joystick.visible = not _downed
	_rebuild_buttons()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_everything()


func _on_paused_changed(paused: bool) -> void:
	if paused:
		_release_everything()


## Touch ids from the browser/OS are arbitrary integers (WebKit may send negative or huge values).
## They are mapped to small local slots on press; nothing below ever treats an id as a sentinel.
func _accepts_touch() -> bool:
	return not _ended and InputSetup.get_touch_override() != "off"


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and not touch.canceled:
			if not _accepts_touch():
				return
			if _slot_of.has(touch.index):   # repeated press without a release: free the stale finger first
				_finger_up(int(_slot_of[touch.index]))
				_last_pos.erase(int(_slot_of[touch.index]))
				_slot_of.erase(touch.index)
			var slot: int = _acquire_slot()
			_slot_of[touch.index] = slot
			_last_pos[slot] = touch.position
			_finger_down(slot, touch.position)
		elif _slot_of.has(touch.index):    # released or canceled (iOS cancels when it takes over a gesture)
			var slot: int = int(_slot_of[touch.index])
			_slot_of.erase(touch.index)
			_last_pos.erase(slot)
			_finger_up(slot)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if not _slot_of.has(drag.index):
			if not _accepts_touch():
				return
			var new_slot: int = _acquire_slot()   # drag without a press (missed event): adopt the finger
			_slot_of[drag.index] = new_slot
			_last_pos[new_slot] = drag.position
			_finger_down(new_slot, drag.position)
			return
		# Never trust drag.relative: on the Web it is computed against another finger's position.
		var drag_slot: int = int(_slot_of[drag.index])
		var previous: Vector2 = _last_pos.get(drag_slot, drag.position)
		_last_pos[drag_slot] = drag.position
		_finger_drag(drag_slot, drag.position, (drag.position - previous).limit_length(_max_delta_px))


func _acquire_slot() -> int:
	var slot: int = 0
	while _slot_of.values().has(slot):
		slot += 1
	return slot


func _finger_down(finger: int, pos: Vector2) -> void:
	# 0. the open accessory list: a row picks that accessory (no use), the tab closes it, anywhere else closes it and
	#    the touch goes on to whatever is there.
	if _menu_open:
		var picked: StringName = _menu_item_at(pos)
		if picked != &"":
			_close_menu()
			_select_accessory(picked)
			return
		if _arrow_rect.has_point(pos):
			_close_menu()
			return
		_close_menu()
	# 1. the tab above the Accessories button
	if _arrow_on and _arrow_rect.has_point(pos):
		_menu_open = true
		_surface.queue_redraw()
		return
	# 2. buttons
	for button_id: StringName in _centers:
		var c: Vector2 = _centers[button_id]
		if pos.distance_to(c) <= float(_radii[button_id]) + HIT_PADDING_PX:
			_press_button(finger, button_id, _action_of(button_id))
			return
	# 3. weapon cards (below the buttons in priority)
	if not _downed:
		for i: int in _card_rects.size():
			if _card_rects[i].has_point(pos):
				_press_button(finger, StringName("%s%d" % [CARD_ID_PREFIX, i + 1]), _card_actions[i])
				return
	# 4. zoom slider (only visible when aiming with an adjustable zoom)
	if _slider_visible() and _slider_rect.grow(HIT_PADDING_PX).has_point(pos):
		_slider_finger = finger
		_slider_active = true
		_set_slider_from(pos)
		return
	# 5. the fixed stick's active area; 6. anywhere else = look (one look finger at a time, extras ignored)
	if joystick.contains_point(pos) and not _downed:
		if not joystick.is_active():
			joystick.begin(finger, pos)
	elif not look_pad.is_active():
		look_pad.begin(finger)


func _finger_up(finger: int) -> void:
	if _finger_to_action.has(finger):
		_release_button_finger(finger)
		_finger_to_action.erase(finger)
	if _slider_active and finger == _slider_finger:
		_slider_active = false
	if joystick.owns(finger):
		joystick.end()
	if look_pad.owns(finger):
		look_pad.end()


func _finger_drag(finger: int, pos: Vector2, relative: Vector2) -> void:
	if joystick.owns(finger):
		joystick.drag(pos)
	elif look_pad.owns(finger):
		look_pad.drag(relative)
	elif _finger_to_action.has(finger):
		if LOOK_BUTTONS.has(_finger_to_action[finger]):
			_on_look(relative)   # the finger holding Fire / Aim steers the camera while it keeps pressing
	elif _slider_active and finger == _slider_finger:
		_set_slider_from(pos)


## Binds `finger` to the button `button_id`, which presses `action_name` (&"" = nothing, e.g. the card of the weapon in
## hand). A hold action counts fingers: two Fire buttons keep `fire` pressed until the last finger leaves.
func _press_button(finger: int, button_id: StringName, action_name: StringName) -> void:
	if button_id == &"crouch" or button_id == &"aim":
		joystick.unlock_run()   # a locked run ends when the hunter crouches or aims
	_finger_to_action[finger] = button_id
	_finger_press[finger] = action_name
	_down[button_id] = true
	if action_name == &"":
		return
	if _mode_of(button_id) == "toggle":
		var on: bool = not bool(_toggled.get(action_name, false))
		_toggled[action_name] = on
		if on:
			Input.action_press(action_name)
		else:
			Input.action_release(action_name)
	else:
		_action_fingers[action_name] = int(_action_fingers.get(action_name, 0)) + 1
		Input.action_press(action_name)


func _release_button_finger(finger: int) -> void:
	var button_id: StringName = _finger_to_action.get(finger, &"")
	if button_id == &"":
		return
	_down[button_id] = false
	var action_name: StringName = _finger_press.get(finger, &"")
	_finger_press.erase(finger)
	if action_name == &"" or _mode_of(button_id) == "toggle":
		return
	var left: int = int(_action_fingers.get(action_name, 0)) - 1
	if left > 0:
		_action_fingers[action_name] = left
	else:
		_action_fingers.erase(action_name)
		Input.action_release(action_name)


func _action_of(button_id: StringName) -> StringName:
	for def: Dictionary in _defs:
		if def["id"] == button_id:
			return def["action"]
	return button_id


func _mode_of(button_id: StringName) -> String:
	for def: Dictionary in BUTTONS:
		if def["id"] == button_id:
			return String(def["mode"])
	return "hold"


func _on_look(rel_px: Vector2) -> void:
	if _player != null:
		_player.apply_touch_look(rel_px)


func _slider_visible() -> bool:
	return _player != null and _player.is_aiming() and _player.has_zoom_range()


func _set_slider_from(pos: Vector2) -> void:
	if _player == null:
		return
	var t: float = 1.0 - clampf((pos.y - _slider_rect.position.y) / _slider_rect.size.y, 0.0, 1.0)
	_player.set_zoom_fraction(t)


# --- Drawing ---

func _draw_surface() -> void:
	if not visible:
		return
	var font: Font = ThemeDB.fallback_font
	var s: Vector2 = _screen_size()
	var flash_on: bool = fmod(Time.get_ticks_msec() * 0.001 * FLASH_HZ, 1.0) < 0.5
	for def: Dictionary in _defs:
		var button_id: StringName = def["id"]
		var c: Vector2 = _centers.get(button_id, Vector2.ZERO)
		var r: float = float(_radii.get(button_id, 0.0))
		var down: bool = bool(_down.get(button_id, false))
		var on: bool = bool(_toggled.get(def["action"], false))
		var fire: bool = def["action"] == FIRE_ACTION
		var slot_id: StringName = def.get("slot", &"")
		var is_slot: bool = slot_id != &""
		var state: Dictionary = _slot_state(slot_id) if is_slot else {}
		var dimmed: bool = bool(state.get("dimmed", false))
		var lit: bool = bool(state.get("lit", false))
		var alpha: float = DIM_ALPHA if dimmed else 1.0
		var fill: Color = COLOR_FIRE if fire else COLOR_FILL
		if down or on:
			fill = COLOR_FIRE_DOWN if fire else COLOR_FILL_DOWN
		fill.a *= alpha
		_surface.draw_circle(c, r, fill)
		var ring: Color = COLOR_ON if (on or lit or button_id == INTERACT_ACTION) else COLOR_RING
		ring.a *= alpha
		_surface.draw_arc(c, r, 0.0, TAU, 48, ring, 4.0 if (on or lit or button_id == INTERACT_ACTION) else 3.0, true)
		var icon_id: StringName = def["icon"]
		var label: String = String(def["label"])
		var show_name: bool = is_slot or (_action_labels and button_id != PAUSE_ACTION)
		if bool(def.get("item", false)) and _menu_open and def["from"] == "acc":
			show_name = false   # the list climbs where the name would be
		if _icons.has(icon_id):
			var tex: Texture2D = _icons[icon_id]
			var icon_size: float = r * 1.2
			var tint: Color = Color(COLOR_ON.r, COLOR_ON.g, COLOR_ON.b, alpha) if lit else Color(1.0, 1.0, 1.0, alpha)
			_surface.draw_texture_rect(tex, Rect2(c - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false, tint)
			if show_name:
				_draw_text(font, label, _label_anchor(def, c, r, s), ITEM_NAME_FONT_PX)
		else:
			_draw_text(font, label, c + Vector2(0.0, 7.0), FONT_SIZE if label.length() < 8 else 15)
		if is_slot:
			_draw_slot_state(font, c, r, state, flash_on and _flashing.has(slot_id))
	_draw_cards()
	if _arrow_on:
		_draw_accessory_tab(flash_on)
		if _menu_open:
			_draw_accessory_menu(font, flash_on)
	if _slider_visible():
		_draw_slider()


## Baseline-centre of the name of a button: under the circle, or above it near the bottom edge (never off screen).
## The Accessories name goes above its tab when there is one.
func _label_anchor(def: Dictionary, c: Vector2, r: float, s: Vector2) -> Vector2:
	var above: bool = bool(def.get("above", false)) or c.y > s.y - LABEL_ABOVE_ZONE_PX
	if not above:
		return c + Vector2(0.0, r + LABEL_BELOW_GAP_PX)
	var top: float = c.y - r
	if _arrow_on and def["from"] == "acc":
		top = _arrow_rect.end.y - ARROW_VISUAL_SIZE.y
	return Vector2(c.x, top - LABEL_ABOVE_GAP_PX)


func _draw_cards() -> void:
	for i: int in _card_rects.size():
		if bool(_down.get(StringName("%s%d" % [CARD_ID_PREFIX, i + 1]), false)):
			_surface.draw_rect(_card_rects[i], COLOR_CARD_DOWN)


func _draw_accessory_tab(flash_now: bool) -> void:
	var visual: Rect2 = Rect2(Vector2(_arrow_rect.get_center().x - ARROW_VISUAL_SIZE.x * 0.5,
		_arrow_rect.end.y - ARROW_VISUAL_SIZE.y), ARROW_VISUAL_SIZE)
	var blink: bool = flash_now and _other_accessory_flashing()
	_tab_style.border_color = COLOR_ON if (blink or _menu_open) else COLOR_RING
	_tab_style.bg_color = COLOR_FILL_DOWN if _menu_open else COLOR_FILL
	_surface.draw_style_box(_tab_style, visual)
	var mid: Vector2 = visual.get_center()
	var tip: float = ARROW_HALF_H_PX * (1.0 if _menu_open else -1.0)   # open: the chevron points down (close)
	_surface.draw_polyline(PackedVector2Array([Vector2(mid.x - ARROW_HALF_W_PX, mid.y - tip),
		Vector2(mid.x, mid.y + tip), Vector2(mid.x + ARROW_HALF_W_PX, mid.y - tip)]), COLOR_TEXT, 3.0, true)


func _other_accessory_flashing() -> bool:
	for item_id: StringName in _acc_ids:
		if item_id != _acc_current and _flashing.has(item_id):
			return true
	return false


func _draw_accessory_menu(font: Font, flash_now: bool) -> void:
	if _menu_centers.is_empty():
		return
	var first: Vector2 = _menu_centers[0]
	var last: Vector2 = _menu_centers[_menu_centers.size() - 1]
	var half: float = MENU_ITEM_D * 0.5 + MENU_PAD_PX
	_surface.draw_style_box(_menu_style, Rect2(Vector2(first.x - half, last.y - half),
		Vector2(half * 2.0, first.y - last.y + half * 2.0)))
	for i: int in _menu_ids.size():
		var item_id: StringName = _menu_ids[i]
		var c: Vector2 = _menu_centers[i]
		var r: float = MENU_ITEM_D * 0.5
		var state: Dictionary = _slot_state(item_id)
		var alpha: float = DIM_ALPHA if bool(state["dimmed"]) else 1.0
		var lit: bool = bool(state["lit"])
		var fill: Color = COLOR_FILL_DOWN if item_id == _acc_current else COLOR_FILL
		fill.a *= alpha
		_surface.draw_circle(c, r, fill)
		var ring: Color = COLOR_ON if (lit or item_id == _acc_current) else COLOR_RING
		ring.a *= alpha
		_surface.draw_arc(c, r, 0.0, TAU, 48, ring, 4.0 if item_id == _acc_current else 3.0, true)
		if _icons.has(item_id):
			var icon_size: float = r * 1.2
			var tint: Color = Color(COLOR_ON.r, COLOR_ON.g, COLOR_ON.b, alpha) if lit else Color(1.0, 1.0, 1.0, alpha)
			_surface.draw_texture_rect(_icons[item_id] as Texture2D,
				Rect2(c - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false, tint)
		_draw_count(font, c, r, int(state["count"]))
		if flash_now and _flashing.has(item_id):
			_surface.draw_arc(c, r + 2.0, 0.0, TAU, 48, COLOR_ON, 5.0, true)


## Display state of an item / dog button: {dimmed, lit, count (-1 = none), busy (< 0 = idle)}.
func _slot_state(slot_id: StringName) -> Dictionary:
	var state: Dictionary = {"dimmed": false, "lit": false, "count": -1, "busy": -1.0}
	if slot_id == DOG_SLOT:
		state["dimmed"] = _dog_retreating
		return state
	if _items == null:
		return state
	var count: int = _items.get_count(slot_id)
	state["count"] = count
	state["dimmed"] = count == 0
	state["lit"] = slot_id == Ids.I_BINOCULARS and _items.is_binoculars_active()
	if _items.get_busy_item() == slot_id:
		state["busy"] = _items.get_busy_progress()
	return state


func _draw_slot_state(font: Font, c: Vector2, r: float, state: Dictionary, flash_now: bool) -> void:
	var busy: float = float(state["busy"])
	if busy >= 0.0:
		_surface.draw_circle(c, r, BUSY_VEIL)
		if busy > 0.0:
			var steps: int = maxi(int(ceil(BUSY_SECTOR_STEPS * busy)), 1)
			var pts: PackedVector2Array = PackedVector2Array([c])
			for i: int in range(steps + 1):
				var a: float = -PI * 0.5 + TAU * busy * float(i) / float(steps)   # clockwise from the top
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.85)
			if pts.size() >= 3:
				_surface.draw_colored_polygon(pts, BUSY_SECTOR)
	_draw_count(font, c, r, int(state["count"]))
	if flash_now:
		_surface.draw_arc(c, r + 2.0, 0.0, TAU, 48, COLOR_ON, 5.0, true)


## "x2" on the top-right corner of a circle, written over the ring (-1 = no count: not drawn).
func _draw_count(font: Font, c: Vector2, r: float, count: int) -> void:
	if count < 0:
		return
	var text: String = "x%d" % count
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ITEM_COUNT_FONT_PX).x
	var anchor: Vector2 = c + Vector2(r * 0.72 - w * 0.5, -r * 0.72 + ITEM_COUNT_FONT_PX * 0.35)
	_surface.draw_string_outline(font, anchor, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ITEM_COUNT_FONT_PX, 5, Color.BLACK)
	_surface.draw_string(font, anchor, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ITEM_COUNT_FONT_PX,
		COLOR_DANGER if count == 0 else COLOR_TEXT)


func _draw_text(font: Font, text: String, baseline_center: Vector2, size_px: int) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var p: Vector2 = baseline_center - Vector2(w * 0.5, 0.0)
	_surface.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 5, Color.BLACK)
	_surface.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, COLOR_TEXT)


func _draw_slider() -> void:
	var r: Rect2 = _slider_rect
	var cx: float = r.position.x + r.size.x * 0.5
	_surface.draw_rect(r, Color(0.0, 0.0, 0.0, 0.25))
	_surface.draw_line(Vector2(cx, r.position.y + 12.0), Vector2(cx, r.end.y - 12.0), COLOR_RING, SLIDER_TRACK_WIDTH_PX)
	var t: float = _player.get_zoom_fraction()
	var ky: float = lerpf(r.end.y - 12.0, r.position.y + 12.0, t)
	_surface.draw_circle(Vector2(cx, ky), SLIDER_KNOB_RADIUS_PX, COLOR_FILL_DOWN)
	_surface.draw_arc(Vector2(cx, ky), SLIDER_KNOB_RADIUS_PX, 0.0, TAU, 32, COLOR_ON, 3.0, true)
	var font: Font = ThemeDB.fallback_font
	_draw_text(font, "%.1fx" % _player.get_zoom_value(), Vector2(cx, r.position.y - 10.0), 20)
