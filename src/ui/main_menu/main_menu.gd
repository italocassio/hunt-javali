extends Control
## Main menu: play, shop, donate, settings, wallet readout and a short career summary.


func _ready() -> void:
	var page: Dictionary = UiKit.build_page(self, "Caçada ao Javali")
	var body: VBoxContainer = page["body"]
	body.alignment = BoxContainer.ALIGNMENT_CENTER

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 40)
	body.add_child(row)

	var menu: VBoxContainer = VBoxContainer.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 16)
	row.add_child(menu)

	var play: Button = UiKit.button("Jogar", "PrimaryButton", 88)
	UiKit.mark(play, self, "PlayButton")
	menu.add_child(play)
	play.pressed.connect(func() -> void: Router.goto(ScenePaths.MAP_SELECT))
	var shop: Button = UiKit.button("Loja", "SecondaryButton", 72)
	UiKit.mark(shop, self, "ShopButton")
	menu.add_child(shop)
	shop.pressed.connect(func() -> void: Router.goto(ScenePaths.SHOP))
	var donate: Button = UiKit.button("Apoie o jogo (doação Pix)", "SecondaryButton", 72)
	UiKit.mark(donate, self, "DonateButton")
	menu.add_child(donate)
	donate.pressed.connect(func() -> void: Router.goto(ScenePaths.DONATE))
	var settings: Button = UiKit.button("Configurações", "SecondaryButton", 72)
	UiKit.mark(settings, self, "SettingsButton")
	menu.add_child(settings)
	settings.pressed.connect(func() -> void: Router.goto(ScenePaths.SETTINGS))

	var side: PanelContainer = UiKit.card()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	side.add_child(info)
	info.add_child(UiKit.label("Seu perfil de caçador", "HeaderLabel"))
	var stats: Dictionary = Profile.get_stats()
	info.add_child(UiKit.label("Caçadas vencidas: %d de %d jogadas" % [int(stats.get("hunts_won", 0)), int(stats.get("hunts_played", 0))]))
	info.add_child(UiKit.label("Javalis abatidos: %d" % int(stats.get("boars_killed", 0))))
	info.add_child(UiKit.label("Maior javali: %s kg" % UiKit.decimal(float(stats.get("heaviest_kg", 0.0)), 0)))
	info.add_child(UiKit.label("Total ganho: %s" % UiKit.money_text(int(stats.get("money_earned_total", 0)))))
	info.add_child(UiKit.muted("O javali é espécie invasora no Brasil. Proteja a lavoura e a fauna nativa."))
	play.grab_focus()
