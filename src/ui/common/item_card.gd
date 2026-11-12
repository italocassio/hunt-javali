class_name ItemCard
extends PanelContainer
## Shop card for a weapon, equipment or dog: icon, name, what it does, price and one action button.
## The action button is named Buy_<id>. State text is refreshed with refresh().

const ICON_SIZE: float = 96.0

var item_id: StringName = &""
var buy_button: Button = null
var _price_label: Label = null
var _status_label: Label = null


## Builds the card for item id. `on_buy` is called with the id when the button is pressed.
func setup(id: StringName, on_buy: Callable) -> void:
	item_id = id
	theme_type_variation = "CardPanel"
	var def: Dictionary = Data.get_item_def(id)
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

	var icon: TextureRect = UiKit.icon_rect(id, ICON_SIZE)
	if icon != null:
		row.add_child(icon)
	else:
		var badge: Label = UiKit.label(_initials(str(def.get("name", "?"))), "HeaderLabel")
		badge.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(badge)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_row.add_child(UiKit.label(str(def.get("name", id)), "HeaderLabel"))
	var tag: String = kind_tag(id)
	if tag != "":
		var tag_label: Label = UiKit.label(tag)
		tag_label.modulate = Color(1, 1, 1, 0.7)
		tag_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		name_row.add_child(tag_label)
	info.add_child(name_row)
	info.add_child(UiKit.label(str(def.get("description", "")), "", true))
	info.add_child(UiKit.muted(stats_text(id)))

	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size = Vector2(230, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	_price_label = UiKit.label("", "GoldLabel" if def.get("currency", "money") == "gold" else "MoneyLabel")
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_price_label)
	buy_button = UiKit.button("Comprar", "PrimaryButton", 72)
	buy_button.name = "Buy_%s" % id
	buy_button.pressed.connect(on_buy.bind(id))
	side.add_child(buy_button)
	_status_label = UiKit.muted("")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(_status_label)
	refresh()


## Updates price, button text and enabled state from Profile.
func refresh() -> void:
	var def: Dictionary = Data.get_item_def(item_id)
	var currency: StringName = StringName(str(def.get("currency", "money")))
	var price: int = int(def.get("price", 0))
	_price_label.text = UiKit.price_text(price, currency)
	var state: StringName = Profile.can_buy(item_id)
	var count: int = Profile.get_item_count(item_id)
	var consumable: bool = def.get("kind", "") == "consumable"
	_status_label.text = ""
	match state:
		&"ok":
			buy_button.text = "Comprar"
			buy_button.disabled = false
			if consumable:
				_status_label.text = "Você tem: %d" % count
		&"already_owned":
			buy_button.text = "Você possui"
			buy_button.disabled = true
		&"max_reached":
			buy_button.text = "Estoque cheio"
			buy_button.disabled = true
			_status_label.text = "Você tem: %d (máximo)" % count
		&"insufficient_funds":
			buy_button.text = "Saldo insuficiente"
			buy_button.disabled = true
			var missing: int = price - (Profile.get_gold() if currency == Ids.GOLD else Profile.get_money())
			_status_label.text = "Faltam %s" % UiKit.price_text(missing, currency)
			if consumable and count > 0:
				_status_label.text += "  |  Tem: %d" % count
		_:
			buy_button.text = "Indisponível"
			buy_button.disabled = true


static func kind_tag(id: StringName) -> String:
	var def: Dictionary = Data.get_item_def(id)
	match Data.get_item_category(id):
		&"weapon":
			return "Arma"
		&"dog":
			return "Cão"
		&"equipment":
			match str(def.get("kind", "")):
				"consumable":
					return "Consumível, até %d por caçada" % int(def.get("max_per_hunt", 1))
				"active":
					return "Equipamento de uso"
				_:
					return "Equipamento fixo"
	return ""


## One line with the numbers that matter for the player's choice.
static func stats_text(id: StringName) -> String:
	var def: Dictionary = Data.get_item_def(id)
	match Data.get_item_category(id):
		&"weapon":
			var pellets: int = int(def.get("pellets", 1))
			var dmg: String = "%d" % int(def.get("damage", 0)) if pellets <= 1 else "%d x %d bagos" % [int(def.get("damage", 0)), pellets]
			var parts: PackedStringArray = ["Dano %s" % dmg]
			parts.append("Alcance %d m" % int(def.get("max_range_m", 0)))
			parts.append("Cadência %s tiros/s" % UiKit.decimal(1.0 / maxf(float(def.get("fire_interval_s", 1.0)), 0.05), 1))
			parts.append("Pente %d (+%d)" % [int(def.get("mag_size", 0)), int(def.get("reserve_ammo", 0))])
			if bool(def.get("scoped", false)):
				parts.append("Luneta %sx a %sx" % [UiKit.decimal(float(def.get("ads_zoom_min", 1.0)), 0), UiKit.decimal(float(def.get("ads_zoom_max", 1.0)), 0)])
			return "  |  ".join(parts)
		&"dog":
			var ability: String = {"point": "Aponta o javali", "bay": "Acua o javali", "hold": "Agarra o javali"}.get(str(def.get("ability", "")), "")
			return "%s  |  Vida %d  |  Alcance de busca %d m" % [ability, int(def.get("max_health", 0)), int(def.get("search_radius_m", 0))]
		&"equipment":
			var effect: Dictionary = def.get("effect", {})
			match id:
				&"binoculars":
					return "Zoom %sx" % UiKit.decimal(float(effect.get("zoom", 1.0)), 0)
				&"leather_vest":
					return "Dano recebido -%d%%" % int(roundf(float(effect.get("damage_reduction", 0.0)) * 100.0))
				&"medkit":
					return "Cura %d de vida em %s s" % [int(effect.get("heal", 0)), UiKit.decimal(float(effect.get("use_time_s", 0.0)), 1)]
				&"corn_bait":
					return "Dura %d s  |  Atrai até %d javalis a %d m" % [int(effect.get("duration_s", 0)), int(effect.get("max_boars", 0)), int(effect.get("attract_radius_m", 0))]
				&"extra_ammo":
					return "Munição de reserva x%s" % UiKit.decimal(float(effect.get("reserve_mult", 1.0)), 0)
				&"thermal_scope":
					return "Destaca javalis até %d m ao mirar" % int(effect.get("highlight_range_m", 0))
				&"scout_drone":
					return "Revela todos no minimapa por %d s" % int(effect.get("reveal_s", 0))
	return ""


static func _initials(text: String) -> String:
	var out: String = ""
	for word: String in text.split(" "):
		if word.length() > 2 and out.length() < 2:
			out += word.substr(0, 1).to_upper()
	return out if out != "" else text.substr(0, 1).to_upper()
