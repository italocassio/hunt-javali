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
const VEIL_COLOR: Color = Color(0.07, 0.04, 0.03)   # warm black
const VEIL_LIGHT_ALPHA: float = 0.12
const VEIL_MEDIUM_ALPHA: float = 0.4
const VEIL_STRONG_ALPHA: float = 0.58
const PAGE_GRADIENT_ALPHA: float = 0.55
const PAGE_GRADIENT_TOP_EXTENT: float = 0.22
const PAGE_GRADIENT_BOTTOM_EXTENT: float = 0.2
const GRADIENT_TEX_SIZE: int = 64
const PAGE_MARGIN_H: int = 40
const PAGE_MARGIN_V: int = 24
const ACCENT_COLOR: Color = Color(0.95, 0.66, 0.16)
const RULE_HEIGHT: float = 3.0
const RULE_START_ALPHA: float = 0.9
const RULE_TEX_WIDTH: int = 256
const HEADER_SEPARATION: int = 20
const TITLE_RULE_SEPARATION: int = 4
const WALLET_ICON_PX: float = 28.0
const WALLET_SEPARATION: int = 12
const UPPERCASE_BUTTONS: Array[String] = ["PrimaryButton", "SecondaryButton", "DangerButton"]

const _TouchScroll: GDScript = preload("res://src/ui/common/touch_scroll_container.gd")

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
	if variation == "TitleLabel" or variation == "HeaderLabel":
		l.uppercase = true
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label_fallback(l, variation)
	return l


static func muted(text: String) -> Label:
	var l: Label = label(text, "", true)
	l.modulate = Color(1, 1, 1, 0.78)
	return l


## Action buttons (Primary/Secondary/Danger) show their text in capitals; pass `uppercase = false` for content
## buttons (tabs, packages). Text changed later should go through action_text().
static func button(text: String, variation: String = "SecondaryButton", min_height: float = MIN_TOUCH_PX, icon_id: StringName = &"", uppercase: bool = true) -> Button:
	var b: Button = Button.new()
	b.text = text.to_upper() if uppercase and UPPERCASE_BUTTONS.has(variation) else text
	if icon_id != &"":
		b.icon = icon(icon_id)
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, maxf(min_height, MIN_TOUCH_PX))
	b.focus_mode = Control.FOCUS_ALL
	if not has_global_theme():
		b.add_theme_font_size_override("font_size", _FALLBACK_SIZES.get(variation, 22))
	b.pressed.connect(_play_click)
	return b


## Text for an action button that changes after creation (same capitals as button()).
static func action_text(text: String) -> String:
	return text.to_upper()


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
## On touch the list scrolls by dragging anywhere on it, also over buttons (see touch_scroll_container.gd).
static func scroll_list(separation: int = 12) -> Array:
	var scroll: ScrollContainer = _TouchScroll.new()
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


## Side-profile weapon portrait (2:1) or null when the art is not there yet.
static func weapon_art_rect(weapon_id: StringName, width_px: float) -> TextureRect:
	var tex: Texture2D = weapon_art(weapon_id)
	if tex == null:
		return null
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(width_px, width_px * 0.5)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Weapon portrait texture or null when missing.
static func weapon_art(weapon_id: StringName) -> Texture2D:
	var path: String = ScenePaths.weapon_art(weapon_id)
	if not AssetLoader.exists(path):
		return null
	return AssetLoader.load_resource(path) as Texture2D


## Icon texture or null when the art is not there yet.
static func icon(icon_id: StringName) -> Texture2D:
	var path: String = ScenePaths.icon(icon_id)
	if not AssetLoader.exists(path):
		return null
	return AssetLoader.load_resource(path) as Texture2D


# --- Page skeleton ---

## Painted background (cover-fit, one texture) plus a warm dark veil. Nodes: "Background" (TextureRect) and
## "Veil" (ColorRect), both ignoring the mouse. Returns false, adding nothing, when the image is missing:
## the caller then draws the flat background (see add_flat_background).
static func add_background(root: Control, texture_path: String, veil_alpha: float) -> bool:
	if texture_path == "" or not AssetLoader.exists(texture_path):
		return false
	var tex: Texture2D = AssetLoader.load_resource(texture_path) as Texture2D
	if tex == null:
		return false
	var bg: TextureRect = TextureRect.new()
	bg.name = "Background"
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var veil: ColorRect = ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(VEIL_COLOR.r, VEIL_COLOR.g, VEIL_COLOR.b, veil_alpha)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	return true


## Dark gradient fading out from the top or bottom edge, `extent` = fraction of the screen height covered.
## Used to give text over a painted background some contrast. Never blocks clicks.
static func add_edge_gradient(root: Control, from_top: bool, extent: float, alpha: float) -> TextureRect:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(VEIL_COLOR.r, VEIL_COLOR.g, VEIL_COLOR.b, alpha if from_top else 0.0))
	grad.set_color(1, Color(VEIL_COLOR.r, VEIL_COLOR.g, VEIL_COLOR.b, 0.0 if from_top else alpha))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = GRADIENT_TEX_SIZE
	tex.height = GRADIENT_TEX_SIZE
	var r: TextureRect = TextureRect.new()
	r.name = "EdgeGradientTop" if from_top else "EdgeGradientBottom"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if from_top else 1.0 - extent
	r.anchor_bottom = extent if from_top else 1.0
	root.add_child(r)
	return r


## The plain dark background with a green band on top (used when there is no painted background).
static func add_flat_background(root: Control, with_band: bool = true) -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	if not with_band:
		return
	var band: ColorRect = ColorRect.new()
	band.name = "Band"
	band.color = BG_BAND_COLOR
	band.anchor_right = 1.0
	band.anchor_bottom = 0.0
	band.offset_bottom = 96
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)


## Dark background (or painted one when `background_path` is given), safe margins, header (title + optional
## wallet), body and footer.
## Returns {"body": VBoxContainer, "header": HBoxContainer, "footer": HBoxContainer, "title": Label}.
static func build_page(root: Control, title: String, show_wallet: bool = true, background_path: String = "", veil_alpha: float = VEIL_MEDIUM_ALPHA) -> Dictionary:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if background_path == "" or not add_background(root, background_path, veil_alpha):
		add_flat_background(root)
	else:
		add_edge_gradient(root, true, PAGE_GRADIENT_TOP_EXTENT, PAGE_GRADIENT_ALPHA)
		add_edge_gradient(root, false, PAGE_GRADIENT_BOTTOM_EXTENT, PAGE_GRADIENT_ALPHA)
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
	header.add_theme_constant_override("separation", HEADER_SEPARATION)
	var title_label: Label = label(title, "TitleLabel")
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true   # a long title shrinks with an ellipsis instead of pushing the wallet off screen
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", TITLE_RULE_SEPARATION)
	title_box.add_child(title_label)
	title_box.add_child(accent_rule())
	header.add_child(title_box)
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


## Thin amber line fading out to the right (poster-style title underline). Never blocks clicks.
static func accent_rule() -> TextureRect:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b, RULE_START_ALPHA))
	grad.set_color(1, Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b, 0.0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.width = RULE_TEX_WIDTH
	tex.height = 1
	var r: TextureRect = TextureRect.new()
	r.name = "AccentRule"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = Vector2(0.0, RULE_HEIGHT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Money and gold readout as a "TopBarPanel" pill with icons. Labels are named %MoneyLabel and %GoldLabel in
## root's scope. The HBoxContainer inside is in meta "row" so callers (main menu) can append buttons.
static func wallet_bar(root: Control) -> PanelContainer:
	var bar: PanelContainer = PanelContainer.new()
	bar.theme_type_variation = "TopBarPanel"
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", WALLET_SEPARATION)
	bar.add_child(row)
	var money: Label = label("", "MoneyLabel")
	var gold: Label = label("", "GoldLabel")
	for pair: Array in [[&"money", money], [&"gold", gold]]:
		var l: Label = pair[1]
		var tex: TextureRect = icon_rect(pair[0], WALLET_ICON_PX)
		if tex != null:
			tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tex)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
	var refresh: Callable = func(m: int, g: int) -> void:
		money.text = money_text(m)
		gold.text = gold_text(g)
	refresh.call(Profile.get_money(), Profile.get_gold())
	GameEvents.wallet_changed.connect(refresh)
	bar.tree_exiting.connect(func() -> void:
		if GameEvents.wallet_changed.is_connected(refresh):
			GameEvents.wallet_changed.disconnect(refresh))
	bar.set_meta("row", row)
	bar.set_meta("money_label", money)
	bar.set_meta("gold_label", gold)
	# Named after the bar is in the tree (owner needs an ancestor): see mark().
	mark(money, root, "MoneyLabel")
	mark(gold, root, "GoldLabel")
	return bar


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
		if best_id != &"":
			break   # weapons first, then dogs, then equipment
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
