class_name WeaponPanel
extends VBoxContainer
## Weapon panel of the HUD (docs §8.4, "Painel da arma e barra de vida"): portrait and name of the active weapon, the
## magazine and reserve counts, the reload bar and, with two weapons or more, a row of chips (one per carried weapon,
## with the key of its slot on keyboard/mouse). Pure display: the Hud feeds it every frame, nothing here reads the
## player, and nothing is clickable.
## Touch (HF7): the same panel shows weapon cards instead (portrait, name, "10 | 50", amber border and reload bar on the
## weapon in hand, the other one dimmed). The cards are still only drawn here; the taps are handled by TouchControls
## from the rectangles the Hud gives it.

const CONTENT_W_PX: float = 224.0
const SEPARATION_PX: int = 4
const NAME_FONT_PX: int = 15
const PORTRAIT_SIZE_PX: Vector2 = Vector2(96.0, 48.0)
const MAG_FONT_PX: int = 36
const RESERVE_FONT_PX: int = 22
const LOW_AMMO_FRAC: float = 0.25
const RELOAD_BAR_H_PX: float = 6.0
const CHIP_SIZE_PX: Vector2 = Vector2(40.0, 28.0)
const CHIP_ART_SIZE_PX: Vector2 = Vector2(36.0, 18.0)
const CHIP_ART_POS_PX: Vector2 = Vector2(2.0, 8.0)
const CHIP_KEY_POS_PX: Vector2 = Vector2(2.0, 0.0)
const CHIP_GAP_PX: int = 6
const CHIP_KEY_FONT_PX: int = 12
const CHIP_BORDER_PX: float = 2.0
const CHIP_RADIUS_PX: int = 4
const INACTIVE_ALPHA: float = 0.5
const ROW_MIN_WEAPONS: int = 2
const RESERVE_FORMAT: String = "| %d"
const INFINITE_RESERVE_TEXT: String = "| ∞"
const OUTLINE_PX: int = 5
const KEY_PAD_X_PX: float = 4.0
const BAR_RADIUS_PX: int = 4
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_AMBER: Color = Color("#F2C12E")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_CHIP_BG: Color = Color(0.0, 0.0, 0.0, 0.35)
const COLOR_KEY_BG: Color = Color(0.0, 0.0, 0.0, 0.7)
const COLOR_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.9)
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.55)
## Touch cards (HF7).
const CARD_H_PX: float = 55.0
const CARD_W_DEFAULT_PX: float = 167.0
const CARD_GAP_PX: int = 8
const CARD_PAD_PX: float = 6.0
const CARD_PORTRAIT_FRAC: float = 0.36        # of the card width; the picture is 2:1
const CARD_TEXT_GAP_PX: float = 6.0
const CARD_NAME_FONT_PX: int = 13
const CARD_MAG_FONT_PX: int = 24
const CARD_RESERVE_FONT_PX: int = 15
const CARD_NAME_BASELINE_PX: float = 17.0
const CARD_AMMO_BASELINE_PX: float = 41.0
const CARD_RESERVE_GAP_PX: float = 4.0
const CARD_RELOAD_H_PX: float = 4.0
const CARD_RELOAD_BOTTOM_PX: float = 4.0
const CARD_RADIUS_PX: int = 8
const CARD_OUTLINE_PX: int = 4
const CARD_MAX_SHOWN: int = 2
const COLOR_CARD_BG: Color = Color(0.12, 0.10, 0.086, 0.72)
## Knife in the hand (F4, jogo 0.9.9): the panel shows this name and no ammunition at all, on keyboard and on touch
## (the card of the weapon in hand becomes the knife card). Text the player reads: PT-BR.
const KNIFE_NAME: String = "Faca"


## One weapon chip of the row. Children: Portrait, Key. The border of the active one is drawn here.
class Chip extends Control:
	var portrait: TextureRect = TextureRect.new()
	var key_label: Label = Label.new()
	var active: bool = false
	var _style: StyleBoxFlat = StyleBoxFlat.new()

	func _init() -> void:
		custom_minimum_size = WeaponPanel.CHIP_SIZE_PX
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style.bg_color = WeaponPanel.COLOR_CHIP_BG
		_style.set_corner_radius_all(WeaponPanel.CHIP_RADIUS_PX)
		_style.border_color = WeaponPanel.COLOR_AMBER
		portrait.name = "Portrait"
		WeaponPanel.style_portrait(portrait)
		portrait.position = WeaponPanel.CHIP_ART_POS_PX
		portrait.size = WeaponPanel.CHIP_ART_SIZE_PX
		add_child(portrait)
		key_label.name = "Key"
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.position = WeaponPanel.CHIP_KEY_POS_PX
		key_label.add_theme_font_size_override("font_size", WeaponPanel.CHIP_KEY_FONT_PX)
		key_label.add_theme_color_override("font_color", WeaponPanel.COLOR_TEXT)
		key_label.add_theme_color_override("font_outline_color", WeaponPanel.COLOR_OUTLINE)
		key_label.add_theme_constant_override("outline_size", WeaponPanel.OUTLINE_PX)
		var key_bg: StyleBoxFlat = StyleBoxFlat.new()
		key_bg.bg_color = WeaponPanel.COLOR_KEY_BG
		key_bg.set_corner_radius_all(WeaponPanel.CHIP_RADIUS_PX)
		key_bg.content_margin_left = WeaponPanel.KEY_PAD_X_PX
		key_bg.content_margin_right = WeaponPanel.KEY_PAD_X_PX
		key_bg.content_margin_top = 0.0
		key_bg.content_margin_bottom = 0.0
		key_label.add_theme_stylebox_override("normal", key_bg)
		add_child(key_label)

	func set_active(on: bool) -> void:
		active = on
		modulate.a = 1.0 if on else WeaponPanel.INACTIVE_ALPHA
		queue_redraw()

	func _draw() -> void:
		var border: int = int(WeaponPanel.CHIP_BORDER_PX) if active else 0
		_style.set_border_width_all(border)
		draw_style_box(_style, Rect2(Vector2.ZERO, size))

## One weapon card of the touch layout, everything drawn in `_draw` (no child nodes). Border of the weapon in hand in
## amber; the others are dimmed through `modulate`.
class Card extends Control:
	var weapon_index: int = -1
	var portrait: Texture2D = null
	var name_text: String = ""
	var mag_text: String = ""
	var reserve_text: String = ""
	var ammo_low: bool = false
	var active: bool = false
	var reload: float = -1.0          # 0-1 while reloading (weapon in hand only), -1 = none
	var _style: StyleBoxFlat = StyleBoxFlat.new()
	var _name_shown: String = ""
	var _name_for_width: float = -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_style.bg_color = WeaponPanel.COLOR_CARD_BG
		_style.set_corner_radius_all(WeaponPanel.CARD_RADIUS_PX)
		_style.border_color = WeaponPanel.COLOR_AMBER

	func set_active(on: bool) -> void:
		active = on
		modulate.a = 1.0 if on else WeaponPanel.INACTIVE_ALPHA
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_name_for_width = -1.0
			queue_redraw()

	func _draw() -> void:
		var font: Font = get_theme_font(&"font", &"HudBigLabel")
		_style.set_border_width_all(int(WeaponPanel.CHIP_BORDER_PX) if active else 0)
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
		var pad: float = WeaponPanel.CARD_PAD_PX
		var art_w: float = size.x * WeaponPanel.CARD_PORTRAIT_FRAC
		if portrait != null:
			var box: Rect2 = Rect2(Vector2(pad, 0.0), Vector2(art_w, size.y))
			var tex_size: Vector2 = portrait.get_size()
			var fit: float = minf(box.size.x / tex_size.x, (size.y - 2.0 * pad) / tex_size.y)
			var fitted: Vector2 = tex_size * fit
			draw_texture_rect(portrait, Rect2(box.position + (box.size - fitted) * 0.5, fitted), false)
		var text_x: float = pad + art_w + WeaponPanel.CARD_TEXT_GAP_PX
		var text_w: float = size.x - text_x - pad
		if _name_for_width != text_w:
			_name_for_width = text_w
			_name_shown = _trim(font, name_text, text_w)
		_text(font, _name_shown, Vector2(text_x, WeaponPanel.CARD_NAME_BASELINE_PX), WeaponPanel.CARD_NAME_FONT_PX,
			WeaponPanel.COLOR_TEXT)
		var mag_color: Color = WeaponPanel.COLOR_DANGER if ammo_low else WeaponPanel.COLOR_TEXT
		_text(font, mag_text, Vector2(text_x, WeaponPanel.CARD_AMMO_BASELINE_PX), WeaponPanel.CARD_MAG_FONT_PX, mag_color)
		var mag_w: float = font.get_string_size(mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, WeaponPanel.CARD_MAG_FONT_PX).x
		_text(font, reserve_text, Vector2(text_x + mag_w + WeaponPanel.CARD_RESERVE_GAP_PX, WeaponPanel.CARD_AMMO_BASELINE_PX),
			WeaponPanel.CARD_RESERVE_FONT_PX, WeaponPanel.COLOR_TEXT)
		if active and reload >= 0.0:
			var bar: Rect2 = Rect2(Vector2(pad, size.y - WeaponPanel.CARD_RELOAD_BOTTOM_PX - WeaponPanel.CARD_RELOAD_H_PX),
				Vector2(size.x - 2.0 * pad, WeaponPanel.CARD_RELOAD_H_PX))
			draw_rect(bar, WeaponPanel.COLOR_BAR_BG)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(reload, 0.0, 1.0), bar.size.y)), WeaponPanel.COLOR_AMBER)

	func _text(font: Font, text: String, baseline: Vector2, font_px: int, color: Color) -> void:
		if text == "":
			return
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, WeaponPanel.CARD_OUTLINE_PX,
			WeaponPanel.COLOR_OUTLINE)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)

	## Cuts the name with an ellipsis so it fits `width` (the names never change: this runs once per card size).
	func _trim(font: Font, text: String, width: float) -> String:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, WeaponPanel.CARD_NAME_FONT_PX).x <= width:
			return text
		var cut: String = text
		while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, WeaponPanel.CARD_NAME_FONT_PX).x > width:
			cut = cut.substr(0, cut.length() - 1)
		return cut + "…"


var _weapon_ids: Array[StringName] = []
var _names: Array[String] = []
var _textures: Array[Texture2D] = []
var _paths: Array[String] = []
var _chips: Array[Chip] = []
var _active: int = -1
var _touch: bool = false
var _mag_text: String = ""
var _reserve_text: String = ""
var _ammo_low: bool = false
var _has_ammo: bool = false
var _last_mag: int = -1
var _last_reserve: int = -1
var _last_infinite: bool = false
var _last_mag_size: int = -1
var _w_mag: Array[int] = []            # per weapon (touch cards): magazine, reserve, infinite flag, magazine size
var _w_reserve: Array[int] = []
var _w_infinite: Array[bool] = []
var _w_mag_size: Array[int] = []
var _cards: Array[Card] = []
var _shown: Array[int] = []            # weapon index of each card on screen
var _card_w: float = CARD_W_DEFAULT_PX
var _reload_on: bool = false
var _reload_progress: float = 0.0
var _knife_on: bool = false            # knife in the hand (F4, 0.9.9): name "Faca", no ammunition
var _knife_texture: Texture2D = null
var _knife_loaded: bool = false

var _name_label: Label = Label.new()
var _main: HBoxContainer = HBoxContainer.new()
var _portrait: TextureRect = TextureRect.new()
var _ammo_box: HBoxContainer = HBoxContainer.new()
var _mag_label: Label = Label.new()
var _reserve_label: Label = Label.new()
var _reload_bar: ProgressBar = ProgressBar.new()
var _row: HBoxContainer = HBoxContainer.new()
var _cards_box: HBoxContainer = HBoxContainer.new()


## Portrait look shared by the big picture and the chips: mipmapped (the thin barrel aliases without), 2:1 kept.
static func style_portrait(rect: TextureRect) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _init() -> void:
	name = "WeaponPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CONTENT_W_PX, 0.0)
	add_theme_constant_override("separation", SEPARATION_PX)

	_name_label.name = "Name"
	_style_label(_name_label, NAME_FONT_PX, &"HudLabel")
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_name_label)

	_main.name = "Main"
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.alignment = BoxContainer.ALIGNMENT_END
	_main.add_theme_constant_override("separation", SEPARATION_PX)
	add_child(_main)
	_portrait.name = "Portrait"
	style_portrait(_portrait)
	_portrait.custom_minimum_size = PORTRAIT_SIZE_PX
	_main.add_child(_portrait)
	_ammo_box.name = "Ammo"
	_ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_box.size_flags_vertical = Control.SIZE_SHRINK_END   # bottoms line up with the picture
	_ammo_box.add_theme_constant_override("separation", SEPARATION_PX)
	_main.add_child(_ammo_box)
	_mag_label.name = "Mag"
	_style_label(_mag_label, MAG_FONT_PX, &"HudBigLabel")
	_mag_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_box.add_child(_mag_label)
	_reserve_label.name = "Reserve"
	_style_label(_reserve_label, RESERVE_FONT_PX, &"HudBigLabel")
	_reserve_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_box.add_child(_reserve_label)

	_reload_bar.name = "ReloadBar"
	_style_bar(_reload_bar)
	_reload_bar.modulate = COLOR_AMBER
	_reload_bar.visible = false
	add_child(_reload_bar)

	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_END
	_row.add_theme_constant_override("separation", CHIP_GAP_PX)
	_row.visible = false
	add_child(_row)

	_cards_box.name = "Cards"
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("separation", CARD_GAP_PX)
	_cards_box.visible = false
	add_child(_cards_box)


## Once per hunt (Hud.bind): one chip per carried weapon, the portraits loaded here and never again. Calling it again
## rebuilds everything. The first weapon becomes the active one; an empty list leaves the panel without a weapon.
func set_weapons(weapon_ids: Array[StringName]) -> void:
	for chip: Chip in _chips:
		_row.remove_child(chip)
		chip.queue_free()
	_chips.clear()
	_weapon_ids = weapon_ids.duplicate()
	_names.clear()
	_textures.clear()
	_paths.clear()
	_w_mag.clear()
	_w_reserve.clear()
	_w_infinite.clear()
	_w_mag_size.clear()
	_shown.clear()   # the touch cards are rebuilt for the new list
	for i: int in _weapon_ids.size():
		var weapon_id: StringName = _weapon_ids[i]
		_names.append(String(Data.get_weapon(weapon_id).get("name", String(weapon_id))))
		var path: String = ScenePaths.weapon_art(weapon_id)
		if not AssetLoader.exists(path):
			path = ScenePaths.icon(weapon_id)
		var texture: Texture2D = null
		if AssetLoader.exists(path):
			texture = AssetLoader.load_resource(path) as Texture2D
		_paths.append(path if texture != null else "")
		_textures.append(texture)
		var chip: Chip = Chip.new()
		chip.name = "Chip_%d" % (i + 1)
		chip.portrait.texture = texture
		chip.set_active(false)
		_row.add_child(chip)
		_chips.append(chip)
		_w_mag.append(0)
		_w_reserve.append(0)
		_w_infinite.append(false)
		_w_mag_size.append(1)
	_active = -1
	_refresh_keys()
	if _weapon_ids.is_empty():
		_name_label.text = ""
		_portrait.texture = null
	else:
		set_active(0)
	_apply_mode()


## Portrait, name and highlighted chip of weapon `index`. Out of range: nothing changes.
func set_active(index: int) -> void:
	if index < 0 or index >= _weapon_ids.size():
		return
	_active = index
	_apply_face()
	for i: int in _chips.size():
		_chips[i].set_active(i == index)
	_rebuild_cards()


## Knife in the hand or back on the belt (F4, 0.9.9): the panel shows "Faca" and no magazine, no reserve and no reload
## bar while it is out, and goes back to the weapon in the hand when it is put away. Works in both modes: on touch the
## card of the weapon in hand becomes the knife card.
func set_knife(on: bool) -> void:
	if on == _knife_on:
		return
	_knife_on = on
	if on:
		_mag_text = ""
		_reserve_text = ""
		_ammo_low = false
		_mag_label.text = ""
		_reserve_label.text = ""
		_mag_label.add_theme_color_override("font_color", COLOR_TEXT)
	else:
		_has_ammo = false   # the next set_ammo writes the numbers of the weapon again
	_apply_face()
	_reload_bar.visible = _reload_on and not _touch and not _knife_on
	for card: Card in _cards:
		_apply_card_face(card)
		_fill_card_ammo(card)


## True while the panel shows the knife instead of the weapon in the hand (tests).
func is_knife_shown() -> bool:
	return _knife_on


## Big name and portrait: the knife while it is in the hand, otherwise the active weapon.
func _apply_face() -> void:
	if _knife_on:
		_name_label.text = KNIFE_NAME
		_portrait.texture = _knife_art()
	elif _active >= 0 and _active < _weapon_ids.size():
		_name_label.text = _names[_active]
		_portrait.texture = _textures[_active]


## The knife portrait (assets/ui/weapons/knife.png, or its SVG icon), loaded at most once.
func _knife_art() -> Texture2D:
	if _knife_loaded:
		return _knife_texture
	_knife_loaded = true
	var path: String = ScenePaths.weapon_art(Ids.KNIFE)
	if not AssetLoader.exists(path):
		path = ScenePaths.icon(Ids.KNIFE)
	if AssetLoader.exists(path):
		_knife_texture = AssetLoader.load_resource(path) as Texture2D
	return _knife_texture


## Magazine and reserve. Text and colour are touched only when a value changes. Ignored while the knife is in the
## hand: the knife has no ammunition (0.9.9).
func set_ammo(in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void:
	if _knife_on:
		return
	if _has_ammo and in_mag == _last_mag and infinite == _last_infinite and mag_size == _last_mag_size \
			and (infinite or reserve == _last_reserve):
		return
	_has_ammo = true
	_last_mag = in_mag
	_last_reserve = reserve
	_last_infinite = infinite
	_last_mag_size = mag_size
	_mag_text = str(in_mag)
	_reserve_text = INFINITE_RESERVE_TEXT if infinite else RESERVE_FORMAT % reserve
	_ammo_low = in_mag <= 0 or float(in_mag) <= float(mag_size) * LOW_AMMO_FRAC
	_mag_label.text = _mag_text
	_reserve_label.text = _reserve_text
	_mag_label.add_theme_color_override("font_color", COLOR_DANGER if _ammo_low else COLOR_TEXT)


## The amber bar under the ammunition: visible only while reloading. `progress` is 0-1.
func set_reload(active: bool, progress: float) -> void:
	_reload_bar.visible = active and not _touch and not _knife_on
	if active:
		_reload_bar.value = progress * 100.0
	if active != _reload_on or (active and not is_equal_approx(progress, _reload_progress)):
		_reload_on = active
		_reload_progress = progress
		_refresh_card_reload()


## Touch (HF7) swaps the name / portrait / ammo block and the chip row for the weapon cards; the keys of the chips
## only exist on keyboard/mouse. In touch the panel is as wide as its cards.
func set_touch(touch: bool) -> void:
	_touch = touch
	_apply_mode()
	_refresh_keys()
	_reload_bar.visible = _reload_on and not _touch and not _knife_on


## Width of each touch card (the Hud derives it from the free width at the bottom of the screen).
func set_card_width(width_px: float) -> void:
	_card_w = width_px
	for card: Card in _cards:
		card.custom_minimum_size = Vector2(_card_w, CARD_H_PX)


## Magazine and reserve of weapon `index` for its touch card (the weapon in the pocket only comes through here).
## Text is rewritten only when a value changes.
func set_weapon_ammo(index: int, in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void:
	if index < 0 or index >= _weapon_ids.size():
		return
	if _w_mag[index] == in_mag and _w_reserve[index] == reserve and _w_infinite[index] == infinite \
			and _w_mag_size[index] == mag_size and _has_card_text(index):
		return
	_w_mag[index] = in_mag
	_w_reserve[index] = reserve
	_w_infinite[index] = infinite
	_w_mag_size[index] = mag_size
	for card: Card in _cards:
		if card.weapon_index == index:
			_fill_card_ammo(card)


## Number of cards on screen (0 outside touch mode; 1 with a single weapon, otherwise 2).
func get_card_count() -> int:
	return _cards.size() if _touch else 0


## Weapon index shown by each card, left to right. With 3+ weapons (horde): the one in hand and the next in the cycle.
func get_card_weapon_indices() -> Array[int]:
	return _shown.duplicate() if _touch else ([] as Array[int])


func is_cards_visible() -> bool:
	return _cards_box.visible


## Name drawn on the card of weapon `index` ("" without that card). For tests.
func get_card_name_text(index: int) -> String:
	for card: Card in _cards:
		if card.weapon_index == index:
			return card.name_text
	return ""


## Magazine text drawn on the card of weapon `index` ("" without that card, and "" on the knife card). For tests.
func get_card_mag_text(index: int) -> String:
	for card: Card in _cards:
		if card.weapon_index == index:
			return card.mag_text
	return ""


func get_weapon_ids() -> Array[StringName]:
	return _weapon_ids.duplicate()


func get_active_index() -> int:
	return _active


func get_name_text() -> String:
	return _name_label.text


func get_mag_text() -> String:
	return _mag_text


func get_reserve_text() -> String:
	return _reserve_text


func is_ammo_low() -> bool:
	return _ammo_low


func get_chip_key_text(index: int) -> String:
	if index < 0 or index >= _chips.size():
		return ""
	var key: Label = _chips[index].key_label
	return key.text if key.visible else ""


## Path of the texture the big portrait shows: the PNG, the SVG fallback or "".
func get_portrait_path() -> String:
	return _paths[_active] if _active >= 0 and _active < _paths.size() else ""


func is_row_visible() -> bool:
	return _row.visible


func _apply_mode() -> void:
	_name_label.visible = not _touch
	_main.visible = not _touch
	_row.visible = not _touch and _weapon_ids.size() >= ROW_MIN_WEAPONS
	custom_minimum_size = Vector2(0.0 if _touch else CONTENT_W_PX, CARD_H_PX if _touch else 0.0)
	_rebuild_cards()


## Cards of the touch layout: every weapon up to CARD_MAX_SHOWN in slot order; with more (horde), the weapon in hand
## and the next one in the cycle (tapping it takes the place of the old swap button).
func _rebuild_cards() -> void:
	if not _touch:
		_cards_box.visible = false
		return
	var wanted: Array[int] = []
	if _weapon_ids.size() <= CARD_MAX_SHOWN:
		for i: int in _weapon_ids.size():
			wanted.append(i)
	elif _active >= 0:
		wanted.append(_active)
		wanted.append((_active + 1) % _weapon_ids.size())
	if wanted != _shown or _cards.size() != wanted.size():
		for old: Card in _cards:
			_cards_box.remove_child(old)
			old.queue_free()
		_cards.clear()
		_shown = wanted
		for index: int in _shown:
			var card: Card = Card.new()
			card.name = "Card_%d" % (index + 1)
			card.weapon_index = index
			card.custom_minimum_size = Vector2(_card_w, CARD_H_PX)
			_apply_card_face(card)
			_cards_box.add_child(card)
			_cards.append(card)
			_fill_card_ammo(card)
	for card: Card in _cards:
		card.set_active(card.weapon_index == _active)
	_cards_box.visible = not _cards.is_empty()
	_refresh_card_reload()


func _has_card_text(index: int) -> bool:
	for card: Card in _cards:
		if card.weapon_index == index:
			return card.mag_text != "" or (_knife_on and index == _active)   # the knife card shows no ammunition
	return true


## Portrait and name of a card: the knife on the card of the weapon in hand while it is out, the weapon otherwise.
func _apply_card_face(card: Card) -> void:
	var index: int = card.weapon_index
	if index < 0 or index >= _weapon_ids.size():
		return
	var knife: bool = _knife_on and index == _active
	card.portrait = _knife_art() if knife else _textures[index]
	card.name_text = KNIFE_NAME if knife else _names[index]
	card._name_for_width = -1.0   # the name changed: trim it again for this width
	card.queue_redraw()


func _fill_card_ammo(card: Card) -> void:
	var index: int = card.weapon_index
	if _knife_on and index == _active:
		card.mag_text = ""
		card.reserve_text = ""
		card.ammo_low = false
		card.queue_redraw()
		return
	card.mag_text = str(_w_mag[index])
	card.reserve_text = INFINITE_RESERVE_TEXT if _w_infinite[index] else RESERVE_FORMAT % _w_reserve[index]
	card.ammo_low = _w_mag[index] <= 0 or float(_w_mag[index]) <= float(_w_mag_size[index]) * LOW_AMMO_FRAC
	card.queue_redraw()


func _refresh_card_reload() -> void:
	for card: Card in _cards:
		var value: float = _reload_progress if (_reload_on and not _knife_on and card.weapon_index == _active) else -1.0
		if not is_equal_approx(card.reload, value):
			card.reload = value
			card.queue_redraw()


func _refresh_keys() -> void:
	for i: int in _chips.size():
		var key: String = ""
		if not _touch:
			key = InputSetup.get_key_label(StringName("weapon_%d" % (i + 1)))
		_chips[i].key_label.text = key
		_chips[i].key_label.visible = key != ""


func _style_label(label: Label, font_px: int, variation: StringName) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", OUTLINE_PX)


## Same bar as the crop bar of the Hud (theme variation CropBar); a flat fallback when the theme lacks it.
func _style_bar(bar: ProgressBar) -> void:
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.theme_type_variation = &"CropBar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(CONTENT_W_PX, RELOAD_BAR_H_PX)
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or not theme.has_stylebox(&"fill", &"CropBar"):
		var bg: StyleBoxFlat = StyleBoxFlat.new()
		bg.bg_color = COLOR_BAR_BG
		bg.set_corner_radius_all(BAR_RADIUS_PX)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color.WHITE   # tinted through modulate
		fill.set_corner_radius_all(BAR_RADIUS_PX)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
