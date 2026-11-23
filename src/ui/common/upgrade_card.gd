class_name UpgradeCard
extends PanelContainer
## Shop card for a permanent upgrade (backpack, knife): image, name + tag, description, current level,
## next level, price of the next level and one button named Buy_<upgrade_id>.
## Visual follows ItemCard. Purchase rules live in Profile/Shop (docs/plano_faca_mochila_folego.md §2.9).

var _upgrade_id: StringName = &""
var buy_button: Button = null
var _price_label: Label = null
var _status_label: Label = null
var _level_label: Label = null
var _next_label: Label = null


## `on_buy` is called with the upgrade id when the button is pressed.
func setup(upgrade_id: StringName, on_buy: Callable) -> void:
	_upgrade_id = upgrade_id
	theme_type_variation = "CardPanel"
	var def: Dictionary = Data.get_upgrade(upgrade_id)
	if not UiKit.has_global_theme():
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(0.17, 0.145, 0.122, 0.92)
		box.set_corner_radius_all(10)
		box.set_content_margin_all(14)
		box.border_color = Color(1, 1, 1, 0.08)
		box.set_border_width_all(2)
		add_theme_stylebox_override("panel", box)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	var image: TextureRect = null
	if upgrade_id == Ids.KNIFE:
		image = UiKit.weapon_art_rect(upgrade_id, ItemCard.WEAPON_ART_WIDTH)
	if image == null:
		image = UiKit.icon_rect(upgrade_id, ItemCard.ICON_SIZE)
	if image != null:
		row.add_child(image)
	else:
		var badge: Label = UiKit.label(str(def.get("name", "?")).left(1).to_upper(), "HeaderLabel")
		badge.custom_minimum_size = Vector2(ItemCard.ICON_SIZE, ItemCard.ICON_SIZE)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(badge)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_row.add_child(UiKit.label(str(def.get("name", upgrade_id)), "HeaderLabel"))
	var tag_label: Label = UiKit.label(_tag())
	tag_label.modulate = Color(1, 1, 1, 0.7)
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_row.add_child(tag_label)
	info.add_child(name_row)
	info.add_child(UiKit.label(str(def.get("description", "")), "", true))
	_level_label = UiKit.muted("")
	info.add_child(_level_label)
	_next_label = UiKit.muted("")
	info.add_child(_next_label)

	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size = Vector2(230, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	_price_label = UiKit.label("", "MoneyLabel")
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_label.add_theme_font_size_override("font_size", ItemCard.PRICE_FONT_PX)
	side.add_child(_price_label)
	buy_button = UiKit.button("Comprar", "PrimaryButton", 72, ItemCard.BUY_ICON)
	buy_button.name = "Buy_%s" % upgrade_id
	buy_button.pressed.connect(on_buy.bind(upgrade_id))
	side.add_child(buy_button)
	_status_label = UiKit.muted("")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_status_label)
	refresh()


## Updates level lines, price, button text and enabled state from Profile.
func refresh() -> void:
	var level: int = Profile.get_upgrade_level(_upgrade_id)
	var max_level: int = Profile.get_upgrade_max_level(_upgrade_id)
	_level_label.text = _level_line(level, max_level)
	_next_label.text = get_next_text()
	_status_label.text = ""
	var state: StringName = Profile.can_buy_upgrade(_upgrade_id)
	var next_price: int = int(Data.get_upgrade_level_def(_upgrade_id, level + 1).get("price", 0))
	_price_label.text = UiKit.price_text(next_price, Ids.MONEY) if level < max_level else ""
	_price_label.visible = level < max_level
	match state:
		&"ok":
			buy_button.text = UiKit.action_text("Comprar nível %d" % (level + 1))
			buy_button.disabled = false
		&"max_reached":
			buy_button.text = UiKit.action_text("Nível máximo")
			buy_button.disabled = true
		&"insufficient_funds":
			buy_button.text = UiKit.action_text("Saldo insuficiente")
			buy_button.disabled = true
			_status_label.text = "Faltam %s" % UiKit.price_text(next_price - Profile.get_money(), Ids.MONEY)
		_:
			buy_button.text = UiKit.action_text("Indisponível")
			buy_button.disabled = true


## "Nível 2 de 4 · 4 espaços de equipamento" (tests).
func get_level_text() -> String:
	return _level_label.text if _level_label != null else ""


## "Próximo nível: 5 espaços" or "Nível máximo" (computed from the current state; tests).
func get_next_text() -> String:
	var level: int = Profile.get_upgrade_level(_upgrade_id)
	if level >= Profile.get_upgrade_max_level(_upgrade_id):
		return "Nível máximo"
	match _upgrade_id:
		Ids.BACKPACK:
			return "Próximo nível: %d espaços" % SaveService.item_slots_for_level(level + 1)
		Ids.KNIFE:
			return "Próximo nível: dano %d" % int(Data.get_upgrade_level_def(_upgrade_id, level + 1).get("damage", 0))
	return ""


func _tag() -> String:
	return "Arma branca, sempre com você" if _upgrade_id == Ids.KNIFE else "Melhoria permanente"


func _level_line(level: int, max_level: int) -> String:
	match _upgrade_id:
		Ids.BACKPACK:
			return "Nível %d de %d · %d espaços de equipamento" % [level, max_level, SaveService.item_slots_for_level(level)]
		Ids.KNIFE:
			var stats: Dictionary = Data.get_upgrade(_upgrade_id).get("stats", {})
			var cadence: String = UiKit.decimal(1.0 / maxf(float(stats.get("swing_interval_s", 1.0)), 0.05), 2)
			return "Nível %d de %d · Dano %d\nAlcance %s m  |  %s golpes/s" % [
				level, max_level, int(Data.get_upgrade_level_def(_upgrade_id, level).get("damage", 0)),
				UiKit.decimal(float(stats.get("reach_m", 0.0)), 1), cadence]
	return "Nível %d de %d" % [level, max_level]
