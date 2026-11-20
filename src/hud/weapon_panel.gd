class_name WeaponPanel
extends VBoxContainer
## Weapon panel of the HUD (docs §8.4, "Painel da arma e barra de vida"): portrait and name of the active weapon, the
## magazine and reserve counts, the reload bar and, with two weapons or more, a row of chips (one per carried weapon,
## with the key of its slot on keyboard/mouse). Pure display: the Hud feeds it every frame, nothing here reads the
## player, and nothing is clickable.

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

var _name_label: Label = Label.new()
var _main: HBoxContainer = HBoxContainer.new()
var _portrait: TextureRect = TextureRect.new()
var _ammo_box: HBoxContainer = HBoxContainer.new()
var _mag_label: Label = Label.new()
var _reserve_label: Label = Label.new()
var _reload_bar: ProgressBar = ProgressBar.new()
var _row: HBoxContainer = HBoxContainer.new()


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
	_row.visible = _weapon_ids.size() >= ROW_MIN_WEAPONS
	_active = -1
	_refresh_keys()
	if _weapon_ids.is_empty():
		_name_label.text = ""
		_portrait.texture = null
	else:
		set_active(0)


## Portrait, name and highlighted chip of weapon `index`. Out of range: nothing changes.
func set_active(index: int) -> void:
	if index < 0 or index >= _weapon_ids.size():
		return
	_active = index
	_name_label.text = _names[index]
	_portrait.texture = _textures[index]
	for i: int in _chips.size():
		_chips[i].set_active(i == index)


## Magazine and reserve. Text and colour are touched only when a value changes.
func set_ammo(in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void:
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
	_reload_bar.visible = active
	if active:
		_reload_bar.value = progress * 100.0


## Touch hides the key of every chip (there is no keyboard); the row stays, informative only.
func set_touch(touch: bool) -> void:
	_touch = touch
	_refresh_keys()


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
