class_name UiKit
extends RefCounted
## Small helpers shared by every menu: styled controls, page skeleton, number formatting, icons.
## The global theme (assets/ui/theme.tres) does the styling; when it is not loaded, fallback sizes and colors
## are applied so the screens stay readable with the default Godot theme. Nothing here assigns `theme`.

const MIN_TOUCH_PX: float = 64.0
const BG_COLOR: Color = Color(0.118, 0.102, 0.086)
const BG_BAND_COLOR: Color = Color(0.184, 0.365, 0.227, 0.35)
const MONEY_COLOR: Color = Color(0.247, 0.686, 0.353)
const GOLD_COLOR: Color = Color(0.91, 0.725, 0.137)
const DANGER_COLOR: Color = Color(0.851, 0.271, 0.169)
const TEXT_COLOR: Color = Color(0.957, 0.937, 0.902)
const MUTED_COLOR: Color = Color(0.78, 0.74, 0.68)
const PAGE_MARGIN_H: int = 40
const PAGE_MARGIN_V: int = 24

const _FALLBACK_SIZES: Dictionary = {
	"TitleLabel": 40, "HeaderLabel": 28, "MoneyLabel": 24, "GoldLabel": 24,
	"PrimaryButton": 26, "SecondaryButton": 22, "DangerButton": 22,
}


static func has_global_theme() -> bool:
	return ThemeDB.get_project_theme() != null


# --- Controls ---

static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label_fallback(l, variation)
	return l


static func muted(text: String) -> Label:
	var l: Label = label(text, "", true)
	l.modulate = Color(1, 1, 1, 0.78)
	return l


static func button(text: String, variation: String = "SecondaryButton", min_height: float = MIN_TOUCH_PX) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, maxf(min_height, MIN_TOUCH_PX))
	b.focus_mode = Control.FOCUS_ALL
	if not has_global_theme():
		b.add_theme_font_size_override("font_size", _FALLBACK_SIZES.get(variation, 22))
	b.pressed.connect(_play_click)
	return b


static func card() -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = "CardPanel"
	if not has_global_theme():
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(0.17, 0.145, 0.122, 0.92)
		box.set_corner_radius_all(10)
		box.set_content_margin_all(14)
		box.border_color = Color(1, 1, 1, 0.08)
		box.set_border_width_all(2)
		p.add_theme_stylebox_override("panel", box)
	return p


static func spacer(horizontal: bool = true) -> Control:
	var c: Control = Control.new()
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Vertical scroll area that fills the remaining space. Returns [scroll, content_vbox].
static func scroll_list(separation: int = 12) -> Array:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", separation)
	scroll.add_child(box)
	return [scroll, box]


static func icon_rect(icon_id: StringName, size_px: float) -> TextureRect:
	var tex: Texture2D = icon(icon_id)
	if tex == null:
		return null
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size_px, size_px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Icon texture or null when the art is not there yet.
static func icon(icon_id: StringName) -> Texture2D:
	var path: String = ScenePaths.icon(icon_id)
	if not AssetLoader.exists(path):
		return null
	return AssetLoader.load_resource(path) as Texture2D


# --- Page skeleton ---

## Dark background, safe margins, header (title + optional wallet), body and footer.
## Returns {"body": VBoxContainer, "header": HBoxContainer, "footer": HBoxContainer, "title": Label}.
static func build_page(root: Control, title: String, show_wallet: bool = true) -> Dictionary:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var band: ColorRect = ColorRect.new()
	band.name = "Band"
	band.color = BG_BAND_COLOR
	band.anchor_right = 1.0
	band.anchor_bottom = 0.0
	band.offset_bottom = 96
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN_H)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN_H)
	margin.add_theme_constant_override("margin_top", PAGE_MARGIN_V)
	margin.add_theme_constant_override("margin_bottom", PAGE_MARGIN_V)
	root.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	var title_label: Label = label(title, "TitleLabel")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	if show_wallet:
		header.add_child(wallet_bar(root))
	column.add_child(header)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	return {"body": body, "header": header, "footer": footer, "title": title_label}


## Money and gold readout. Labels are named %MoneyLabel and %GoldLabel in root's scope.
static func wallet_bar(root: Control) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	box.alignment = BoxContainer.ALIGNMENT_END
	var money: Label = label("", "MoneyLabel")
	var gold: Label = label("", "GoldLabel")
	for l: Label in [money, gold]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var refresh: Callable = func(m: int, g: int) -> void:
		money.text = money_text(m)
		gold.text = gold_text(g)
	refresh.call(Profile.get_money(), Profile.get_gold())
	GameEvents.wallet_changed.connect(refresh)
	box.tree_exiting.connect(func() -> void:
		if GameEvents.wallet_changed.is_connected(refresh):
			GameEvents.wallet_changed.disconnect(refresh))
	box.add_child(money)
	box.add_child(gold)
	box.set_meta("money_label", money)
	box.set_meta("gold_label", gold)
	# Named after the box is in the tree (owner needs an ancestor): see mark_later().
	mark_later(money, root, "MoneyLabel")
	mark_later(gold, root, "GoldLabel")
	return box


# --- Scene-unique names ---

## Names `node` and registers it as %Name for `root`. Works before or after the node is added:
## `owner` is only accepted by the engine once root is an ancestor, so it is set then.
static func mark(node: Node, root: Node, node_name: String) -> void:
	node.name = node_name
	if root.is_ancestor_of(node):
		_claim(node, root)
	else:
		node.tree_entered.connect(_claim.bind(node, root), CONNECT_ONE_SHOT)


## Kept for callers that build a subtree first; same as mark().
static func mark_later(node: Node, root: Node, node_name: String) -> void:
	mark(node, root, node_name)


static func _claim(node: Node, root: Node) -> void:
	if not root.is_ancestor_of(node):
		push_warning("UiKit.mark: '%s' is not under '%s', %%%s will not resolve." % [node.name, root.name, node.name])
		return
	node.owner = root
	node.unique_name_in_owner = true


# --- Formatting ---

static func money_text(amount: int) -> String:
	return "R$ " + group_digits(amount)


static func gold_text(amount: int) -> String:
	return "%s ouro" % group_digits(amount)


static func price_text(amount: int, currency: StringName) -> String:
	if currency == Ids.GOLD:
		return "%s ouro" % group_digits(amount)
	return money_text(amount)


static func price_color(currency: StringName) -> Color:
	return GOLD_COLOR if currency == Ids.GOLD else MONEY_COLOR


## 1234567 -> "1.234.567"
static func group_digits(amount: int) -> String:
	var s: String = str(absi(amount))
	var out: String = ""
	for i: int in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return ("-" if amount < 0 else "") + out


## Decimal comma, e.g. num(132.5, 1) = "132,5".
static func num(value: float, decimals: int = 0) -> String:
	return ("%." + str(decimals) + "f") % value if decimals > 0 else str(int(roundf(value)))


static func decimal(value: float, decimals: int = 1) -> String:
	return num(value, decimals).replace(".", ",")


static func item_name(id: StringName) -> String:
	return str(Data.get_item_def(id).get("name", String(id)))


## Next goal for the wallet: the cheapest money item the player does not own yet.
## "" when everything is owned.
static func next_purchase_hint() -> String:
	var best_id: StringName = &""
	var best_price: int = 0
	var pools: Array = [Data.get_weapon_ids(), Data.get_dog_ids(), Data.get_equipment_ids()]
	for pool: Array in pools:
		for id: StringName in pool:
			var def: Dictionary = Data.get_item_def(id)
			if str(def.get("currency", "money")) != "money":
				continue
			if def.get("kind", "") == "consumable" or Profile.owns(id):
				continue
			var price: int = int(def.get("price", 0))
			if best_id == &"" or price < best_price:
				best_id = id
				best_price = price
	if best_id == &"":
		return ""
	var missing: int = best_price - Profile.get_money()
	if missing <= 0:
		return "Já dá para comprar: %s (%s)" % [item_name(best_id), money_text(best_price)]
	return "Próxima meta: %s, faltam %s" % [item_name(best_id), money_text(missing)]


static func boar_name(type_id: StringName) -> String:
	if Data.get_boar_type_ids().has(type_id):
		return str(Data.get_boar_type(type_id).get("name", String(type_id)))
	return String(type_id)


# --- Internals ---

static func _label_fallback(l: Label, variation: String) -> void:
	if has_global_theme():
		return
	var size: int = _FALLBACK_SIZES.get(variation, 20)
	l.add_theme_font_size_override("font_size", size)
	match variation:
		"MoneyLabel":
			l.add_theme_color_override("font_color", MONEY_COLOR)
		"GoldLabel":
			l.add_theme_color_override("font_color", GOLD_COLOR)


static func _play_click() -> void:
	Sfx.play(&"ui_click")
