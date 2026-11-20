class_name Quickbar
extends HBoxContainer
## Item bar of the desktop HUD (docs §8.4, "Barra de itens"). One slot per usable item the hunter carries,
## in the order of InputSetup.ITEM_ACTIONS, then the dog slot while there is a dog. Each slot shows the
## icon, the key letter, the count, the progress of the use in course, and the dimmed / lit / flashing
## states. Visible only in keyboard/mouse mode and only with at least one slot. Pure display: pressing
## the key is handled by the Player, so nothing here touches input.

const DOG_SLOT: StringName = &"dog_command"
const FLASH_HZ: float = 2.0
const SLOT_SIZE_PX: float = 64.0
const ICON_SIZE_PX: float = 32.0   # leaves the corners to the key letter and the count (no text over the drawing)
const SEPARATION_PX: int = 8
const KEY_FONT_PX: int = 14
const COUNT_FONT_PX: int = 14
const NAME_FONT_PX: int = 14
const DIM_ALPHA: float = 0.35
const VEIL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const SECTOR_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)
const SECTOR_RADIUS_PX: float = 30.0
const SECTOR_STEPS: int = 48
const BORDER_PX: float = 3.0
const COLOR_AMBER: Color = Color("#F2C12E")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_PANEL: Color = Color(0.12, 0.10, 0.086, 0.72)
const COLOR_KEY_BG: Color = Color(0.0, 0.0, 0.0, 0.7)
const DOG_NAME: String = "Cão"


## One square slot. Children (for QA and layout): Icon, Name (icon fallback), Key, Count, Overlay.
class Slot extends Control:
	var slot_id: StringName = &""
	var busy_progress: float = -1.0     # < 0 = not in use
	var lit: bool = false
	var flashing: bool = false
	var icon: TextureRect = TextureRect.new()
	var name_label: Label = Label.new()
	var key_label: Label = Label.new()
	var count_label: Label = Label.new()
	var overlay: Control = Control.new()
	var _panel_style: StyleBox = null

	func _init() -> void:
		custom_minimum_size = Vector2(Quickbar.SLOT_SIZE_PX, Quickbar.SLOT_SIZE_PX)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2.ONE * Quickbar.ICON_SIZE_PX
		icon.position = (Vector2.ONE * (Quickbar.SLOT_SIZE_PX - Quickbar.ICON_SIZE_PX)) * 0.5
		add_child(icon)
		name_label.name = "Name"
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.size = Vector2.ONE * Quickbar.SLOT_SIZE_PX
		name_label.visible = false
		_style_text(name_label, Quickbar.NAME_FONT_PX)
		add_child(name_label)
		key_label.name = "Key"
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.position = Vector2(2.0, 2.0)
		_style_text(key_label, Quickbar.KEY_FONT_PX)
		var key_bg: StyleBoxFlat = StyleBoxFlat.new()
		key_bg.bg_color = Quickbar.COLOR_KEY_BG
		key_bg.set_corner_radius_all(4)
		key_bg.content_margin_left = 4.0
		key_bg.content_margin_right = 4.0
		key_bg.content_margin_top = 0.0
		key_bg.content_margin_bottom = 0.0
		key_label.add_theme_stylebox_override("normal", key_bg)
		add_child(key_label)
		count_label.name = "Count"
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.size = Vector2.ONE * (Quickbar.SLOT_SIZE_PX - 3.0)
		count_label.position = Vector2.ZERO
		_style_text(count_label, Quickbar.COUNT_FONT_PX)
		add_child(count_label)
		overlay.name = "Overlay"
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.draw.connect(_draw_overlay)
		add_child(overlay)

	func _style_text(l: Label, font_px: int) -> void:
		l.add_theme_font_size_override("font_size", font_px)
		l.add_theme_color_override("font_color", Quickbar.COLOR_TEXT)
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		l.add_theme_constant_override("outline_size", 5)

	func _ready() -> void:
		var theme: Theme = ThemeDB.get_project_theme()
		if theme != null and theme.has_stylebox(&"panel", &"HudPanel"):
			_panel_style = theme.get_stylebox(&"panel", &"HudPanel")
		else:
			var flat: StyleBoxFlat = StyleBoxFlat.new()
			flat.bg_color = Quickbar.COLOR_PANEL
			flat.set_corner_radius_all(8)
			_panel_style = flat
		queue_redraw()

	func _draw() -> void:
		if _panel_style != null:
			draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))

	func _draw_overlay() -> void:
		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		if busy_progress >= 0.0:
			overlay.draw_rect(rect, Quickbar.VEIL_COLOR)
			var steps: int = maxi(int(ceil(Quickbar.SECTOR_STEPS * busy_progress)), 1)
			var center: Vector2 = size * 0.5
			var pts: PackedVector2Array = PackedVector2Array([center])
			var sweep: float = TAU * clampf(busy_progress, 0.0, 1.0)
			for i: int in range(steps + 1):
				var a: float = -PI * 0.5 + sweep * float(i) / float(steps)   # clockwise from the top (y points down)
				pts.append(center + Vector2(cos(a), sin(a)) * Quickbar.SECTOR_RADIUS_PX)
			if busy_progress > 0.0 and pts.size() >= 3:
				overlay.draw_colored_polygon(pts, Quickbar.SECTOR_COLOR)
		var flash_on: bool = flashing and fmod(Time.get_ticks_msec() * 0.001 * Quickbar.FLASH_HZ, 1.0) < 0.5
		if lit or flash_on:
			overlay.draw_rect(rect.grow(-Quickbar.BORDER_PX * 0.5), Quickbar.COLOR_AMBER, false, Quickbar.BORDER_PX)


var _items: ItemBelt = null
var _slots: Dictionary = {}              # slot id -> Slot
var _flashing: Dictionary = {}           # slot id -> true
var _has_dog: bool = false
var _dog_retreating: bool = false
var _spectating: bool = false
var _key_text: Dictionary = {}           # slot id -> action StringName (for refreshing the letters)


func _init() -> void:
	name = "Quickbar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", SEPARATION_PX)
	alignment = BoxContainer.ALIGNMENT_CENTER
	visible = false
	set_process(false)


func _ready() -> void:
	GameEvents.touch_mode_changed.connect(_on_touch_mode_changed)
	GameEvents.spectate_changed.connect(_on_spectate_changed)


## Creates Slot_<id> for every usable item, in order, and keeps the dog slot last. Safe to call again.
func bind(items: ItemBelt) -> void:
	if _items != null:
		_disconnect_items()
	_items = items
	for slot_id: StringName in _slots.keys():
		if slot_id != DOG_SLOT:
			_remove_slot(slot_id)
	if _items != null:
		_items.counts_changed.connect(_refresh_all)
		_items.binoculars_changed.connect(_on_binoculars_changed)
		_items.use_started.connect(_on_use_started)
		_items.use_finished.connect(_on_use_finished)
		for item_id: StringName in _items.get_usable_ids():
			_add_slot(item_id)
	if _slots.has(DOG_SLOT):
		move_child(_slots[DOG_SLOT] as Slot, get_child_count() - 1)   # the dog is always the last one
	_refresh_all()


func set_dog_present(present: bool) -> void:
	if present == _has_dog:
		return
	_has_dog = present
	if present:
		_add_slot(DOG_SLOT)
	else:
		_remove_slot(DOG_SLOT)
		_dog_retreating = false
	_refresh_all()


func set_dog_state(state: StringName) -> void:
	_dog_retreating = state == Ids.DS_RETREAT
	_refresh_all()


## Blinks the amber border of a slot at FLASH_HZ until flash(id, false). Unknown id: nothing.
func flash(slot_id: StringName, on: bool) -> void:
	var slot: Slot = _slots.get(slot_id) as Slot
	if slot == null:
		return
	if on:
		_flashing[slot_id] = true
	else:
		_flashing.erase(slot_id)
	slot.flashing = on
	slot.overlay.queue_redraw()
	_update_processing()


## Slot ids in screen order.
func get_slot_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for child: Node in get_children():
		var slot: Slot = child as Slot
		if slot != null:
			out.append(slot.slot_id)
	return out


func _process(_delta: float) -> void:
	var busy_id: StringName = _items.get_busy_item() if _items != null else &""
	for slot_id: StringName in _slots:
		var slot: Slot = _slots[slot_id]
		slot.busy_progress = _items.get_busy_progress() if slot_id == busy_id and busy_id != &"" else -1.0
		slot.overlay.queue_redraw()
	_update_processing()


func _update_processing() -> void:
	var busy: bool = _items != null and _items.is_busy()
	set_process(busy or not _flashing.is_empty())


func _add_slot(slot_id: StringName) -> void:
	if _slots.has(slot_id):
		return
	var slot: Slot = Slot.new()
	slot.slot_id = slot_id
	slot.name = "Slot_" + String(slot_id)
	_slots[slot_id] = slot
	add_child(slot)
	var is_dog: bool = slot_id == DOG_SLOT
	var icon_id: StringName = &"btn_dog" if is_dog else slot_id
	var path: String = ScenePaths.icon(icon_id)
	if AssetLoader.exists(path):
		slot.icon.texture = AssetLoader.load_resource(path) as Texture2D
	slot.icon.visible = slot.icon.texture != null
	slot.name_label.text = DOG_NAME if is_dog else _short_name(slot_id)
	slot.name_label.visible = slot.icon.texture == null
	var action: StringName = DOG_SLOT if is_dog else InputSetup.get_item_action(slot_id)
	_key_text[slot_id] = action
	if is_dog:
		move_child(slot, get_child_count() - 1)


func _remove_slot(slot_id: StringName) -> void:
	var slot: Slot = _slots.get(slot_id) as Slot
	if slot == null:
		return
	_slots.erase(slot_id)
	_flashing.erase(slot_id)
	_key_text.erase(slot_id)
	remove_child(slot)
	slot.queue_free()


func _short_name(item_id: StringName) -> String:
	var def: Dictionary = Data.get_equipment(item_id)
	return String(def.get("short_name", def.get("name", "")))


func _disconnect_items() -> void:
	if _items.counts_changed.is_connected(_refresh_all):
		_items.counts_changed.disconnect(_refresh_all)
	if _items.binoculars_changed.is_connected(_on_binoculars_changed):
		_items.binoculars_changed.disconnect(_on_binoculars_changed)
	if _items.use_started.is_connected(_on_use_started):
		_items.use_started.disconnect(_on_use_started)
	if _items.use_finished.is_connected(_on_use_finished):
		_items.use_finished.disconnect(_on_use_finished)


func _refresh_all() -> void:
	for slot_id: StringName in _slots:
		_refresh_slot(_slots[slot_id] as Slot)
	_update_visibility()
	_update_processing()


func _refresh_slot(slot: Slot) -> void:
	var is_dog: bool = slot.slot_id == DOG_SLOT
	var action: StringName = _key_text.get(slot.slot_id, &"") as StringName
	var key: String = InputSetup.get_key_label(action) if action != &"" else ""
	slot.key_label.text = key
	slot.key_label.visible = key != ""
	var dimmed: bool = false
	var count: int = -1
	if is_dog:
		dimmed = _dog_retreating
	elif _items != null:
		count = _items.get_count(slot.slot_id)
		dimmed = count == 0
	slot.count_label.visible = count >= 0
	slot.count_label.text = "x%d" % maxi(count, 0)
	slot.count_label.add_theme_color_override("font_color", COLOR_DANGER if count == 0 else COLOR_TEXT)
	slot.lit = slot.slot_id == Ids.I_BINOCULARS and _items != null and _items.is_binoculars_active()
	slot.self_modulate.a = DIM_ALPHA if dimmed else 1.0   # the panel only; the icon is dimmed below
	slot.icon.modulate = Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, DIM_ALPHA if dimmed else 1.0) \
		if slot.lit else Color(1.0, 1.0, 1.0, DIM_ALPHA if dimmed else 1.0)
	slot.name_label.modulate.a = DIM_ALPHA if dimmed else 1.0
	slot.overlay.queue_redraw()


func _update_visibility() -> void:
	visible = not _slots.is_empty() and not InputSetup.is_touch_mode() and not _spectating


func _on_binoculars_changed(_active: bool) -> void:
	_refresh_all()


func _on_use_started(_item_id: StringName, _duration_s: float) -> void:
	_update_processing()
	_process(0.0)


func _on_use_finished(_item_id: StringName) -> void:
	for slot_id: StringName in _slots:
		(_slots[slot_id] as Slot).busy_progress = -1.0
	_refresh_all()


func _on_touch_mode_changed(_is_touch: bool) -> void:
	_update_visibility()


func _on_spectate_changed(slot: int) -> void:
	_spectating = slot >= 0
	_update_visibility()
