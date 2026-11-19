extends Control
## Main menu, poster style: action column bottom left (over the hunter's body), logo in the sky, wallet and
## icon buttons in a top bar on the right, career card bottom center (clear of the big boar at bottom right).
## Presentation only: navigation, data and node names are the same as before.

const SCREEN_MARGIN: float = 32.0
const BOTTOM_MARGIN: float = 24.0
const TOP_MARGIN: float = 16.0
const COLUMN_WIDTH: float = 460.0
const LIST_FONT_SIZE: int = 26
const PLAY_WIDTH: float = 504.0
const COLUMN_SEPARATION: int = 8
const PLAY_HEIGHT: float = 76.0
const ACTION_HEIGHT: float = 64.0
const BADGE_RIGHT_INSET: float = 14.0
const LEFT_GRADIENT_EXTENT: float = 0.42
const LEFT_GRADIENT_ALPHA: float = 0.5
const BOTTOM_GRADIENT_EXTENT: float = 0.12
const LOGO_CENTER_X: float = 0.61
const LOGO_TOP: float = 88.0
const FALLBACK_LOGO_WIDTH: float = 600.0
const ICON_BUTTON_PX: float = 64.0
const SEPARATOR_HEIGHT: float = 36.0
const PROFILE_CENTER_X: float = 0.545
const PROFILE_WIDTH: float = 372.0
const PROFILE_SEPARATION: int = 6
const PROFILE_BODY_SEPARATION: int = 14
const PROFILE_BADGE_PX: float = 88.0
const PROFILE_ROW_ICON_PX: float = 24.0
const PROFILE_ROW_SEPARATION: int = 8
const PROFILE_BOTTOM_MARGIN: float = 24.0
const VERSION_ALPHA: float = 0.75
const VERSION_MARGIN_RIGHT: float = 20.0
const VERSION_MARGIN_BOTTOM: float = 12.0

var _profile_card: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if UiKit.add_background(self, ScenePaths.MENU_BACKGROUND, UiKit.VEIL_LIGHT_ALPHA):
		_add_left_gradient()
		UiKit.add_edge_gradient(self, false, BOTTOM_GRADIENT_EXTENT, UiKit.PAGE_GRADIENT_ALPHA)
	else:
		UiKit.add_flat_background(self)

	_add_logo()
	var play: Button = _build_button_column()
	_add_top_bar()
	_profile_card = _build_profile_card()
	add_child(_profile_card)
	_add_version_label()
	play.grab_focus()


## Soft dark fade from the left edge, behind the button column. Never blocks clicks.
func _add_left_gradient() -> void:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(UiKit.VEIL_COLOR.r, UiKit.VEIL_COLOR.g, UiKit.VEIL_COLOR.b, LEFT_GRADIENT_ALPHA))
	grad.set_color(1, Color(UiKit.VEIL_COLOR.r, UiKit.VEIL_COLOR.g, UiKit.VEIL_COLOR.b, 0.0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.width = UiKit.GRADIENT_TEX_SIZE
	tex.height = UiKit.GRADIENT_TEX_SIZE
	var r: TextureRect = TextureRect.new()
	r.name = "EdgeGradientLeft"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = LEFT_GRADIENT_EXTENT
	r.anchor_bottom = 1.0
	add_child(r)


func _add_logo() -> void:
	var logo: Control = AssetLoader.instantiate(ScenePaths.GAME_LOGO) as Control
	if logo == null:
		logo = UiKit.label("Caçada ao Javali", "TitleLabel")
		(logo as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		logo.custom_minimum_size = Vector2(FALLBACK_LOGO_WIDTH, 0.0)
	logo.name = "Logo"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size_px: Vector2 = logo.get_combined_minimum_size()
	logo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	logo.anchor_left = LOGO_CENTER_X
	logo.anchor_right = LOGO_CENTER_X
	logo.offset_left = -size_px.x * 0.5
	logo.offset_right = size_px.x * 0.5
	logo.offset_top = LOGO_TOP
	logo.offset_bottom = LOGO_TOP + size_px.y
	add_child(logo)


func _build_button_column() -> Button:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "ButtonColumn"
	column.add_theme_constant_override("separation", COLUMN_SEPARATION)
	column.anchor_top = 1.0
	column.anchor_bottom = 1.0
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_left = SCREEN_MARGIN
	column.offset_bottom = -BOTTOM_MARGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var play: Button = _menu_button("JOGAR", "play", "PlayButton", "MenuPrimaryButton", PLAY_HEIGHT, PLAY_WIDTH, column)
	play.pressed.connect(func() -> void: Router.goto(ScenePaths.MAP_SELECT))
	var shop: Button = _menu_button("LOJA", "shop", "ShopButton", "MenuListButton", ACTION_HEIGHT, COLUMN_WIDTH, column)
	shop.pressed.connect(func() -> void: Router.goto(ScenePaths.SHOP))
	var friends: Button = _menu_button("JOGAR COM AMIGOS", "friends", "FriendsButton", "MenuListButton", ACTION_HEIGHT, COLUMN_WIDTH, column)
	friends.pressed.connect(func() -> void: Router.goto(ScenePaths.LOBBY))
	_add_badge(friends, "BETA")
	var donate: Button = _menu_button("APOIE O JOGO (DOAÇÃO PIX)", "heart", "DonateButton", "MenuListButton", ACTION_HEIGHT, COLUMN_WIDTH, column)
	donate.pressed.connect(func() -> void: Router.goto(ScenePaths.DONATE))
	var settings: Button = _menu_button("CONFIGURAÇÕES", "settings", "SettingsButton", "MenuListButton", ACTION_HEIGHT, COLUMN_WIDTH, column)
	settings.pressed.connect(func() -> void: Router.goto(ScenePaths.SETTINGS))
	# Closing the game in a browser leaves a black page, so Quit only exists on native builds.
	if not OS.has_feature("web"):
		var quit: Button = _menu_button("SAIR", "exit", "QuitButton", "MenuListButton", ACTION_HEIGHT, COLUMN_WIDTH, column)
		quit.pressed.connect(func() -> void: get_tree().quit())
	return play


func _menu_button(text: String, icon_id: StringName, node_name: String, variation: String, height: float, width: float, parent: Control) -> Button:
	var b: Button = UiKit.button(text, variation, height)
	b.custom_minimum_size.x = width
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if variation == "MenuListButton":
		b.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	b.icon = UiKit.icon(icon_id)
	UiKit.mark(b, self, node_name)
	parent.add_child(b)
	return b


## Pill badge pinned to the right end of the button, clear of the text.
func _add_badge(button: Button, text: String) -> void:
	var badge: Label = UiKit.label(text, "BadgeLabel")
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 0.5
	badge.anchor_bottom = 0.5
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BOTH
	badge.offset_right = -BADGE_RIGHT_INSET
	button.add_child(badge)


func _add_top_bar() -> void:
	var bar: PanelContainer = UiKit.wallet_bar(self)
	bar.name = "TopBar"
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -SCREEN_MARGIN
	bar.offset_top = TOP_MARGIN
	add_child(bar)
	var row: HBoxContainer = bar.get_meta("row")
	var sep: VSeparator = VSeparator.new()
	sep.custom_minimum_size.y = SEPARATOR_HEIGHT
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	var profile_button: Button = _icon_button("profile", "ProfileButton", "Mostrar ou esconder o perfil de caçador", row)
	profile_button.pressed.connect(func() -> void: _profile_card.visible = not _profile_card.visible)
	var settings_button: Button = _icon_button("settings", "SettingsIconButton", "Configurações", row)
	settings_button.pressed.connect(func() -> void: Router.goto(ScenePaths.SETTINGS))


func _icon_button(icon_id: StringName, node_name: String, tooltip: String, parent: Control) -> Button:
	var b: Button = UiKit.button("", "IconButton", ICON_BUTTON_PX)
	b.custom_minimum_size.x = ICON_BUTTON_PX
	b.icon = UiKit.icon(icon_id)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.tooltip_text = tooltip
	UiKit.mark(b, self, node_name)
	parent.add_child(b)
	return b


func _build_profile_card() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.name = "ProfileCard"
	card.theme_type_variation = "ProfileCardPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = PROFILE_CENTER_X
	card.anchor_right = PROFILE_CENTER_X
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = -PROFILE_WIDTH * 0.5
	card.offset_right = PROFILE_WIDTH * 0.5
	card.offset_bottom = -PROFILE_BOTTOM_MARGIN
	UiKit.mark(card, self, "ProfileCard")

	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", PROFILE_SEPARATION)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(info)
	var title: Label = UiKit.label("SEU PERFIL DE CAÇADOR", "MenuHeaderLabel")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(title)

	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", PROFILE_BODY_SEPARATION)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(body)
	var badge: TextureRect = UiKit.icon_rect(&"hunter_badge", PROFILE_BADGE_PX)
	if badge != null:
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(badge)
		var sep: VSeparator = VSeparator.new()
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(sep)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", PROFILE_SEPARATION)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rows)

	var stats: Dictionary = Profile.get_stats()
	_add_stat_row(rows, &"trophy", "Caçadas vencidas: %d de %d" % [int(stats.get("hunts_won", 0)), int(stats.get("hunts_played", 0))])
	_add_stat_row(rows, &"target", "Javalis abatidos: %d" % int(stats.get("boars_killed", 0)))
	_add_stat_row(rows, &"weight", "Maior javali: %s kg" % UiKit.decimal(float(stats.get("heaviest_kg", 0.0)), 0))
	_add_stat_row(rows, &"coins", "Total ganho: %s" % UiKit.money_text(int(stats.get("money_earned_total", 0))))
	return card


func _add_stat_row(parent: Control, icon_id: StringName, text: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", PROFILE_ROW_SEPARATION)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var icon: TextureRect = UiKit.icon_rect(icon_id, PROFILE_ROW_ICON_PX)
	if icon != null:
		row.add_child(icon)
	var l: Label = UiKit.label(text)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)


## Bottom-right corner. The number comes from application/config/version in project.godot.
func _add_version_label() -> void:
	var version: Label = Label.new()
	version.text = "Versão %s" % String(ProjectSettings.get_setting("application/config/version", "?"))
	version.modulate = Color(1.0, 1.0, 1.0, VERSION_ALPHA)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version.anchor_left = 1.0
	version.anchor_top = 1.0
	version.anchor_right = 1.0
	version.anchor_bottom = 1.0
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -VERSION_MARGIN_RIGHT
	version.offset_bottom = -VERSION_MARGIN_BOTTOM
	UiKit.mark(version, self, "VersionLabel")
	add_child(version)
