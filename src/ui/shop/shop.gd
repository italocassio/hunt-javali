extends Control
## Shop: tabs Armas / Equipamentos / Cães, one ItemCard per item (button Buy_<id>).
## Nodes: %NextHuntButton -> PREPARATION, %BackButton -> MAIN_MENU, %DonateButton -> DONATE, %MessageLabel.
## Purchase rules live in Profile/Shop; this screen only asks and shows the answer.

const TABS: Array[Dictionary] = [
	{"key": "weapons", "title": "Armas"},
	{"key": "equipment", "title": "Equipamentos"},
	{"key": "dogs", "title": "Cães"},
]
const MESSAGES: Dictionary = {
	&"insufficient_funds": "Saldo insuficiente.",
	&"already_owned": "Você já possui este item.",
	&"max_reached": "Estoque cheio para este item.",
	&"unknown_item": "Item indisponível.",
}

const UPGRADE_MESSAGES: Dictionary = {
	&"max_reached": "%s já está no nível máximo.",
	&"insufficient_funds": "%s Saldo insuficiente.",
	&"unknown_item": "%s Item indisponível.",
}

var _cards: Array[ItemCard] = []
var _upgrade_cards: Array[UpgradeCard] = []
var _tab_buttons: Array[Button] = []
var _tab_pages: Array[Control] = []
var _message: Label = null
var _hint: Label = null


func _ready() -> void:
	var page: Dictionary = UiKit.build_page(self, "Loja", true, ScenePaths.PREPARATION_BACKGROUND, UiKit.VEIL_STRONG_ALPHA)
	var body: VBoxContainer = page["body"]

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)

	for i: int in TABS.size():
		var tab: Dictionary = TABS[i]
		var b: Button = UiKit.button(str(tab["title"]), "SecondaryButton", UiKit.MIN_TOUCH_PX, &"", true)
		b.toggle_mode = true
		b.custom_minimum_size.x = 220
		b.name = "Tab_%s" % tab["key"]
		tabs.add_child(b)
		b.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(b)

		var scroller: Array = UiKit.scroll_list(10)
		var scroll: Control = scroller[0]
		body.add_child(scroll)
		_tab_pages.append(scroll)
		if str(tab["key"]) == "equipment" and Data.get_upgrade_ids().has(Ids.BACKPACK):
			var up_card: UpgradeCard = UpgradeCard.new()
			scroller[1].add_child(up_card)
			up_card.setup(Ids.BACKPACK, _on_buy_upgrade)
			_upgrade_cards.append(up_card)
		for id: StringName in _ids_for(str(tab["key"])):
			var card: ItemCard = ItemCard.new()
			scroller[1].add_child(card)
			card.setup(id, _on_buy)
			_cards.append(card)

	_hint = UiKit.label("", "MoneyLabel", true)
	body.add_child(_hint)
	_message = UiKit.muted("")
	UiKit.mark(_message, self, "MessageLabel")
	body.add_child(_message)

	var footer: HBoxContainer = page["footer"]
	var in_room: bool = Net.is_in_room()
	var back: Button = UiKit.button("Voltar à sala" if in_room else "Menu", "SecondaryButton", UiKit.MIN_TOUCH_PX, &"back" if in_room else &"home")
	back.custom_minimum_size.x = 200
	UiKit.mark(back, self, "BackButton")
	footer.add_child(back)
	back.pressed.connect(func() -> void: Router.goto(ScenePaths.LOBBY if in_room else ScenePaths.MAIN_MENU))
	var donate: Button = UiKit.button("Ouro", "SecondaryButton", UiKit.MIN_TOUCH_PX, &"gold")
	donate.custom_minimum_size.x = 200
	UiKit.mark(donate, self, "DonateButton")
	footer.add_child(donate)
	donate.pressed.connect(func() -> void: Router.goto(ScenePaths.DONATE))
	footer.add_child(UiKit.spacer())
	var next: Button = UiKit.button("Próxima caçada", "PrimaryButton", 80, &"play")
	next.custom_minimum_size.x = 340
	UiKit.mark(next, self, "NextHuntButton")
	footer.add_child(next)
	next.pressed.connect(func() -> void: Router.goto(ScenePaths.PREPARATION))
	next.visible = not in_room

	GameEvents.wallet_changed.connect(_on_wallet_changed)
	_show_tab(0)
	_refresh_hint()


func _exit_tree() -> void:
	if GameEvents.wallet_changed.is_connected(_on_wallet_changed):
		GameEvents.wallet_changed.disconnect(_on_wallet_changed)


func _ids_for(key: String) -> Array[StringName]:
	match key:
		"weapons":
			return Data.get_weapon_ids()
		"equipment":
			return Data.get_equipment_ids()
		"dogs":
			return Data.get_dog_ids()
	return []


func _show_tab(index: int) -> void:
	for i: int in _tab_pages.size():
		_tab_pages[i].visible = i == index
		_tab_buttons[i].button_pressed = i == index


func _on_buy(id: StringName) -> void:
	var code: StringName = Profile.buy(id)
	var item_name: String = UiKit.item_name(id)
	if code == &"ok":
		Sfx.play(&"ui_buy")
		_message.text = "Comprado: %s." % item_name
	else:
		_message.text = "%s %s" % [item_name, MESSAGES.get(code, "Não foi possível comprar.")]
	_refresh_cards()


func _on_buy_upgrade(id: StringName) -> void:
	var code: StringName = Profile.buy_upgrade(id)
	var up_name: String = str(Data.get_upgrade(id).get("name", String(id)))
	if code == &"ok":
		Sfx.play(&"ui_buy")
		_message.text = "Comprado: %s nível %d." % [up_name, Profile.get_upgrade_level(id)]
	else:
		_message.text = str(UPGRADE_MESSAGES.get(code, "%s Não foi possível comprar.")) % up_name
	_refresh_cards()


func _on_wallet_changed(_money: int, _gold: int) -> void:
	_refresh_cards()


func _refresh_cards() -> void:
	for card: ItemCard in _cards:
		card.refresh()
	for up_card: UpgradeCard in _upgrade_cards:
		up_card.refresh()
	_refresh_hint()


func _refresh_hint() -> void:
	_hint.text = UiKit.next_purchase_hint()
