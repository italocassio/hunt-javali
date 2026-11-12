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

var _cards: Array[ItemCard] = []
var _tab_buttons: Array[Button] = []
var _tab_pages: Array[Control] = []
var _message: Label = null
var _hint: Label = null


func _ready() -> void:
	var page: Dictionary = UiKit.build_page(self, "Loja")
	var body: VBoxContainer = page["body"]

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	var holder: Control = Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(holder)

	for i: int in TABS.size():
		var tab: Dictionary = TABS[i]
		var b: Button = UiKit.button(str(tab["title"]), "SecondaryButton")
		b.toggle_mode = true
		b.custom_minimum_size.x = 220
		b.name = "Tab_%s" % tab["key"]
		tabs.add_child(b)
		b.pressed.connect(_show_tab.bind(i))
		_tab_buttons.append(b)

		var scroller: Array = UiKit.scroll_list(10)
		var scroll: Control = scroller[0]
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(scroll)
		_tab_pages.append(scroll)
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
	var back: Button = UiKit.button("Menu", "SecondaryButton")
	back.custom_minimum_size.x = 200
	UiKit.mark(back, self, "BackButton")
	footer.add_child(back)
	back.pressed.connect(func() -> void: Router.goto(ScenePaths.MAIN_MENU))
	var donate: Button = UiKit.button("Ouro", "SecondaryButton")
	donate.custom_minimum_size.x = 200
	UiKit.mark(donate, self, "DonateButton")
	footer.add_child(donate)
	donate.pressed.connect(func() -> void: Router.goto(ScenePaths.DONATE))
	footer.add_child(UiKit.spacer())
	var next: Button = UiKit.button("Próxima caçada", "PrimaryButton", 80)
	next.custom_minimum_size.x = 340
	UiKit.mark(next, self, "NextHuntButton")
	footer.add_child(next)
	next.pressed.connect(func() -> void: Router.goto(ScenePaths.PREPARATION))

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


func _on_wallet_changed(_money: int, _gold: int) -> void:
	_refresh_cards()


func _refresh_cards() -> void:
	for card: ItemCard in _cards:
		card.refresh()
	_refresh_hint()


func _refresh_hint() -> void:
	_hint.text = UiKit.next_purchase_hint()
