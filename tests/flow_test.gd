extends Node
## tests/flow_test.tscn: boot -> menu -> map -> preparation -> hunt -> result -> shop -> buy -> preparation,
## driven only through the buttons of docs/arquitetura.md section 11 (`button.pressed.emit()`).
##
## Scene changes free the current scene, so the real runner is a second node of the same script that is
## parented to the root window (it survives Router.goto).
##
## The three cases after the friends lobby are the backpack route (docs/plano_faca_mochila_folego.md, F1): menu ->
## preparation (level 1, 3 slots) -> shop (buy the backpack, then a 4th item) -> preparation (4 slots) -> hunt with 4 items.
##
## The two cases after the backpack route are the energy drink (docs/plano_faca_mochila_folego.md, F3): menu -> shop (buy
## 2, once without enough money) -> preparation (swap one item for the drink) -> hunt carrying 2 drinks.
##
## The two cases after the energy drink are the knife (docs/plano_faca_mochila_folego.md, F4): menu -> shop (Buy_knife is
## the first card of the weapons tab; buy level 2 with money added through Profile.add_money) -> preparation -> hunt with
## request.knife_level == 2.
##
## The last six cases are the horde route (docs/horda.md section 14): level 1, then level 2 (docs/plano_horda_nivel2.md).
##
## Run: tools/godot.sh --headless --fixed-fps 60 --path . res://tests/flow_test.tscn [-- --strict]

const TestCase := preload("res://tests/lib/test_case.gd")

const WATCHDOG_REAL_S: float = 120.0
const SCENE_TIMEOUT_S: float = 20.0

var is_runner: bool = false
var _t: RefCounted
var _totals: Dictionary = {}
var _strict: bool = false
var _start_ms: int = 0
var _finished: bool = false
var _started_signals: int = 0
var _ended: Array[HuntResult] = []
var _money_before_hunt: int = 0


func _ready() -> void:
	if not is_runner:
		# Shell node: hand over to a runner that lives under the root and is not freed by scene changes.
		var runner: Node = (get_script() as GDScript).new()
		runner.set("is_runner", true)
		runner.name = "FlowTestRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	_strict = "--strict" in OS.get_cmdline_user_args()
	_start_ms = Time.get_ticks_msec()
	TestCase.install_catcher()
	_totals = TestCase.new_totals()
	_t = TestCase.new()
	_t.set("host", self)
	_t.set("strict", _strict)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if is_runner and not _finished and float(Time.get_ticks_msec() - _start_ms) / 1000.0 > WATCHDOG_REAL_S:
		_finished = true
		print("FAIL watchdog: flow_test excedeu %d s" % int(WATCHDOG_REAL_S))
		_totals["fail"] = int(_totals["fail"]) + 1
		_quit()


func _quit() -> void:
	Engine.time_scale = 1.0
	var code: int = TestCase.finish(_totals)
	TestCase.remove_catcher()
	get_tree().quit(code)


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

func _scene() -> Node:
	return get_tree().current_scene


func _scene_path() -> String:
	return _scene().scene_file_path if _scene() != null else ""


func _wait_scene(path: String, timeout_s: float = SCENE_TIMEOUT_S) -> bool:
	var t0: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < timeout_s:
		if _scene() != null and _scene_path() == path:
			await get_tree().process_frame   # let _ready of the new scene finish
			await get_tree().process_frame
			return true
		await get_tree().process_frame
	_t.call("fail", "esperava a cena %s em %d s, atual: '%s'" % [path, int(timeout_s), _scene_path()])
	return false


func _node(node_name: String) -> Node:
	var scene: Node = _scene()
	if scene == null:
		return null
	var n: Node = scene.get_node_or_null("%" + node_name)
	if n == null:
		n = scene.find_child(node_name, true, false)
	return n


func _button(node_name: String) -> Button:
	var n: Node = _node(node_name)
	if n == null:
		_t.call("fail", "cena %s nao tem o no '%s'" % [_scene_path().get_file(), node_name])
		return null
	if not n is BaseButton:
		_t.call("fail", "'%s' nao e botao (%s)" % [node_name, n.get_class()])
		return null
	return n as Button


func _press(node_name: String) -> bool:
	var b: Button = _button(node_name)
	if b == null:
		return false
	if b.disabled:
		_t.call("fail", "botao '%s' esta desabilitado" % node_name)
		return false
	b.pressed.emit()
	return true


func _case(label: String, fn: Callable) -> void:
	if _finished:
		return
	_t.call("begin")
	await fn.call()
	_t.call("conclude", label, _totals)


# --------------------------------------------------------------------------------------------
# Flow
# --------------------------------------------------------------------------------------------

func _run() -> void:
	await get_tree().process_frame
	_t.call("fresh_profile")
	GameEvents.hunt_started.connect(func(_r: HuntRequest) -> void: _started_signals += 1)
	GameEvents.hunt_ended.connect(func(r: HuntResult) -> void: _ended.append(r))
	await _case("boot_to_main_menu", _step_boot)
	await _case("menu_to_map_select", _step_menu)
	await _case("map_to_preparation", _step_map)
	await _case("preparation_contracts_and_start", _step_preparation)
	await _case("hunt_runs_and_ends_to_result", _step_hunt)
	await _case("result_to_shop_with_reward_and_unlock", _step_result)
	await _case("shop_purchases", _step_shop)
	await _case("shop_to_preparation", _step_shop_next)
	await _case("preparation_second_contract", _step_second_request)
	await _case("back_buttons_navigate", _step_back_buttons)
	await _case("friends_lobby_offline_and_back", _step_friends_lobby)
	await _case("backpack_menu_to_shop_via_preparation", _step_backpack_to_shop)
	await _case("backpack_shop_purchase", _step_backpack_shop)
	await _case("backpack_preparation_four_items_and_hunt", _step_backpack_preparation)
	await _case("energy_drink_shop_purchase", _step_energy_shop)
	await _case("energy_drink_preparation_and_hunt", _step_energy_preparation)
	await _case("knife_shop_purchase", _step_knife_shop)
	await _case("knife_preparation_and_hunt", _step_knife_hunt)
	await _case("horde_menu_to_hunt", _step_horde_hunt)
	await _case("horde_result_and_shop", _step_horde_result)
	await _case("horde_shop_back_to_menu", _step_horde_back_to_menu)
	await _case("horde2_menu_to_hunt", _step_horde2_hunt)
	await _case("horde2_result_and_shop", _step_horde2_result)
	await _case("horde2_shop_back_to_menu", _step_horde_back_to_menu)
	_t.call("cleanup_test_files")
	if not _finished:
		_finished = true
		_quit()


func _step_boot() -> void:
	Router.goto(ScenePaths.BOOT)
	if not await _wait_scene(ScenePaths.BOOT):
		return
	_t.call("ok", _button("StartButton") != null, "StartButton existe")
	if _press("StartButton"):
		await _wait_scene(ScenePaths.MAIN_MENU)


func _step_menu() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	for node_name: String in ["PlayButton", "ShopButton", "DonateButton", "SettingsButton"]:
		_button(node_name)
	var money_label: Label = _node("MoneyLabel") as Label
	var gold_label: Label = _node("GoldLabel") as Label
	_t.call("ok", money_label != null, "MoneyLabel existe")
	_t.call("ok", gold_label != null, "GoldLabel existe")
	if money_label != null:
		_t.call("contains", money_label.text, str(Profile.get_money()), "MoneyLabel mostra o saldo (%s)" % money_label.text)
	if _press("PlayButton"):
		await _wait_scene(ScenePaths.MAP_SELECT)


func _step_map() -> void:
	if _scene_path() != ScenePaths.MAP_SELECT:
		_t.call("fail", "pre-condicao: nao esta no mapa (%s)" % _scene_path())
		return
	_t.call("ok", _button("BackButton") != null, "BackButton existe")
	var map_btn: Button = _button("Map_mato_grosso")
	if map_btn == null:
		return
	_t.call("eq", map_btn.disabled, false, "Map_mato_grosso habilitado")
	for id: StringName in Data.get_map_ids():
		_t.call("ok", _node("Map_%s" % id) != null, "botao Map_%s existe" % id)
	map_btn.pressed.emit()
	if await _wait_scene(ScenePaths.PREPARATION):
		_t.call("eq", Router.selected_map_id, &"mato_grosso", "Router.selected_map_id")
		_t.call("eq", Router.selected_contract_index, 0, "Router.selected_contract_index (perfil novo)")


func _step_preparation() -> void:
	if _scene_path() != ScenePaths.PREPARATION:
		_t.call("fail", "pre-condicao: nao esta na preparacao (%s)" % _scene_path())
		return
	var c0: Button = _button("Contract_0")
	var c1: Button = _button("Contract_1")
	if c0 != null:
		_t.call("eq", c0.disabled, false, "Contract_0 liberado")
	if c1 != null:
		_t.call("eq", c1.disabled, true, "Contract_1 trancado no perfil novo")
	for node_name: String in ["WeaponSlot0", "WeaponSlot1", "DogOption", "ShopButton", "BackButton"]:
		_t.call("ok", _node(node_name) != null, "%s existe" % node_name)
	if c0 != null:
		c0.pressed.emit()
	_money_before_hunt = Profile.get_money()
	_started_signals = 0
	if _press("StartHuntButton"):
		await _wait_scene(ScenePaths.HUNT, 30.0)


func _step_hunt() -> void:
	if _scene_path() != ScenePaths.HUNT:
		_t.call("fail", "pre-condicao: nao esta na caçada (%s)" % _scene_path())
		return
	var hunt: HuntController = _scene() as HuntController
	if hunt == null:
		_t.call("fail", "cena HUNT nao e HuntController")
		return
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_t.call("ok", hunt.is_world_ready(), "mundo pronto")
	for i: int in 5:
		await get_tree().process_frame
	_t.call("eq", _started_signals, 1, "hunt_started 1x")
	_t.call("eq", hunt.get_map_id(), &"mato_grosso", "map_id da caçada")
	_t.call("eq", hunt.get_contract_index(), 0, "contrato da caçada")
	_t.call("ok", hunt.get_player() != null, "jogador existe")
	# Real kills are covered by playthrough; here the win is forced and routed by the real controller.
	_ended.clear()
	hunt.debug_force_end(HuntResult.Outcome.VICTORY)
	await _wait_scene(ScenePaths.RESULT, 30.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended 1x")


func _step_result() -> void:
	if _scene_path() != ScenePaths.RESULT:
		_t.call("fail", "pre-condicao: nao esta no resultado (%s)" % _scene_path())
		return
	_t.call("ok", Router.last_result != null, "Router.last_result definido")
	if Router.last_result != null:
		_t.call("eq", Router.last_result.outcome, HuntResult.Outcome.VICTORY, "outcome em last_result")
		_t.call("ok", Router.last_result.total_money > 0, "total_money > 0 (bonus do contrato)")
		_t.call("eq", Profile.get_money(), _money_before_hunt + Router.last_result.total_money, "saldo aumentou em total_money (1x)")
	_t.call("ok", Profile.get_money() > _money_before_hunt, "saldo aumentou")
	_t.call("ok", Profile.is_contract_unlocked(&"mato_grosso", 1), "contrato 1 desbloqueado")
	_t.call("ok", Profile.is_contract_completed(&"mato_grosso", 0), "contrato 0 concluido")
	_t.call("ok", _button("MenuButton") != null, "MenuButton existe")
	_t.call("ok", _button("RetryButton") != null, "RetryButton existe")
	if _press("ContinueButton"):
		await _wait_scene(ScenePaths.SHOP)


func _step_shop() -> void:
	if _scene_path() != ScenePaths.SHOP:
		_t.call("fail", "pre-condicao: nao esta na loja (%s)" % _scene_path())
		return
	_t.call("ok", _button("NextHuntButton") != null, "NextHuntButton existe")
	_t.call("ok", _button("BackButton") != null, "BackButton existe")
	var buy: Button = _button("Buy_shotgun_12")
	if buy == null:
		return
	# Without enough money the button is disabled and pressing it does nothing.
	var price: int = int(Data.get_item_def(&"shotgun_12").get("price", 0))
	var rich_id: StringName = &"rifle_3006"
	var rich_price: int = int(Data.get_item_def(rich_id).get("price", 0))
	var rich_btn: Button = _button("Buy_%s" % rich_id)
	if rich_btn != null:
		_t.call("ok", Profile.get_money() < rich_price, "pre-condicao: saldo (%d) menor que %d" % [Profile.get_money(), rich_price])
		_t.call("eq", rich_btn.disabled, true, "Buy_%s desabilitado sem saldo" % rich_id)
		var m0: int = Profile.get_money()
		rich_btn.pressed.emit()
		_t.call("eq", Profile.owns(rich_id), false, "compra sem saldo nao concede item")
		_t.call("eq", Profile.get_money(), m0, "compra sem saldo nao cobra")
	# With forced balance the purchase goes through.
	Profile.add_money(maxi(0, price + 123 - Profile.get_money()))
	await get_tree().process_frame
	_t.call("eq", Profile.get_money(), price + 123, "saldo forcado")
	_t.call("eq", buy.disabled, false, "Buy_shotgun_12 habilitado com saldo")
	buy.pressed.emit()
	await get_tree().process_frame
	_t.call("eq", Profile.owns(&"shotgun_12"), true, "shotgun_12 comprada")
	_t.call("eq", Profile.get_money(), 123, "saldo descontado exatamente o preco")
	_t.call("eq", buy.disabled, true, "botao desabilita apos comprar (ja possui)")
	buy.pressed.emit()   # a second press must not charge again
	_t.call("eq", Profile.get_money(), 123, "segundo clique nao cobra")
	# Consumable purchase.
	var consumable: StringName = &"corn_bait"
	var cbtn: Button = _button("Buy_%s" % consumable)
	if cbtn != null:
		var cprice: int = int(Data.get_item_def(consumable).get("price", 0))
		Profile.add_money(cprice)
		await get_tree().process_frame
		var before: int = Profile.get_item_count(consumable)
		var money: int = Profile.get_money()
		cbtn.pressed.emit()
		await get_tree().process_frame
		_t.call("eq", Profile.get_item_count(consumable), before + 1, "milho comprado, estoque +1")
		_t.call("eq", Profile.get_money(), money - cprice, "milho cobrado")


func _step_shop_next() -> void:
	if _scene_path() != ScenePaths.SHOP:
		_t.call("fail", "pre-condicao: nao esta na loja (%s)" % _scene_path())
		return
	if _press("NextHuntButton"):
		await _wait_scene(ScenePaths.PREPARATION)


func _step_second_request() -> void:
	if _scene_path() != ScenePaths.PREPARATION:
		_t.call("fail", "pre-condicao: nao esta na preparacao (%s)" % _scene_path())
		return
	var c1: Button = _button("Contract_1")
	if c1 != null:
		_t.call("eq", c1.disabled, false, "Contract_1 liberado depois da vitoria")
		c1.pressed.emit()
	_t.call("eq", Router.selected_contract_index, 1, "contrato 1 selecionado")
	var req: HuntRequest = Profile.build_hunt_request(&"mato_grosso", 1)
	_t.call("eq", req.contract_index, 1, "request.contract_index")
	_t.call("ok", req.weapon_ids.size() >= 1 and req.weapon_ids[0] == &"carbine_22", "slot 0 segue carbine_22")
	_t.call("ok", Profile.owns(&"shotgun_12"), "shotgun_12 persiste entre cenas")


func _step_back_buttons() -> void:
	if _scene_path() != ScenePaths.PREPARATION:
		_t.call("fail", "pre-condicao: nao esta na preparacao (%s)" % _scene_path())
		return
	if _press("BackButton") and await _wait_scene(ScenePaths.MAP_SELECT):
		if _press("BackButton"):
			await _wait_scene(ScenePaths.MAIN_MENU)
	if _scene_path() == ScenePaths.MAIN_MENU:
		if _press("SettingsButton") and await _wait_scene(ScenePaths.SETTINGS):
			if _press("BackButton"):
				await _wait_scene(ScenePaths.MAIN_MENU)
		if _press("DonateButton") and await _wait_scene(ScenePaths.DONATE):
			if _press("BackButton"):
				await _wait_scene(ScenePaths.MAIN_MENU)
		if _press("ShopButton") and await _wait_scene(ScenePaths.SHOP):
			if _press("BackButton"):
				await _wait_scene(ScenePaths.MAIN_MENU)


## F6: "Jogar com amigos (beta)" is always in the menu. Offline (no server URL in a desktop run, nothing listening
## anywhere): menu -> lobby entry screen -> Voltar -> menu, with no room and no stuck state in Net.
func _step_friends_lobby() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	var friends: Button = _button("FriendsButton")
	if friends == null:
		return
	_t.call("ok", friends.visible and not friends.disabled, "FriendsButton visivel e habilitado sem ?mp=1")
	_t.call("eq", friends.text, "JOGAR COM AMIGOS", "texto do FriendsButton (o \"BETA\" e um selo filho do botao)")
	_t.call("eq", Net.get_room_state(), Net.RoomState.NONE, "pre-condicao: Net sem sala")
	friends.pressed.emit()
	if not await _wait_scene(ScenePaths.LOBBY):
		return
	for node_name: String in ["NameEdit", "CreateRoomButton", "CodeEdit", "JoinButton", "BackButton", "MessageLabel", "StatusLabel"]:
		_t.call("ok", _node(node_name) != null, "lobby tem %s" % node_name)
	var join: Button = _node("JoinButton") as Button
	var create: Button = _node("CreateRoomButton") as Button
	var code: LineEdit = _node("CodeEdit") as LineEdit
	var message: Label = _node("MessageLabel") as Label
	if join != null:
		_t.call("eq", join.disabled, true, "Entrar desabilitado sem codigo")
	if create != null and message != null and not Net.is_configured():
		_t.call("eq", create.disabled, true, "Criar sala desabilitado sem servidor configurado")
		_t.call("ok", message.text != "", "mensagem de modo nao configurado (%s)" % message.text)
	if code != null and join != null:
		code.text = "abc"
		code.text_changed.emit("abc")
		_t.call("eq", code.text, "ABC", "codigo vira maiusculo")
		_t.call("eq", join.disabled, true, "Entrar segue desabilitado com codigo curto")
		code.text = ""
		code.text_changed.emit("")
	_t.call("eq", Net.get_room_state(), Net.RoomState.NONE, "o lobby sozinho nao abre sala")
	_t.call("ok", not Net.is_in_room(), "Net fora de sala no lobby de entrada")
	if _press("BackButton"):
		await _wait_scene(ScenePaths.MAIN_MENU)
	_t.call("eq", Net.get_room_state(), Net.RoomState.NONE, "Net sem sala depois de Voltar")


# --------------------------------------------------------------------------------------------
# Backpack route (docs/plano_faca_mochila_folego.md, F1)
# --------------------------------------------------------------------------------------------

const BACKPACK_ITEMS: Array[StringName] = [&"medkit", &"scout_drone", &"corn_bait", &"binoculars"]

var _backpack_money_before: int = 0


## Header and limit hint of the preparation, level 1: "Equipamentos (mochila nível 1: até 3)".
func _step_backpack_to_shop() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	_t.call("eq", Profile.get_upgrade_level(Ids.BACKPACK), 1, "pre-condicao: mochila nivel 1")
	if not (_press("PlayButton") and await _wait_scene(ScenePaths.MAP_SELECT)):
		return
	var map_btn: Button = _button("Map_mato_grosso")
	if map_btn == null:
		return
	map_btn.pressed.emit()
	if not await _wait_scene(ScenePaths.PREPARATION):
		return
	_t.call("ok", _find_label("Equipamentos (mochila nível 1: até 3)") != null, "cabecalho da Preparacao no nivel 1")
	_t.call("eq", Profile.get_item_slots(), 3, "3 espacos no nivel 1")
	var chosen: int = Profile.get_loadout_items().size()
	if chosen >= 3:
		_t.call("ok", _find_label("Mochila cheia (3). Desmarque um ou compre uma mochila maior na Loja.") != null, "dica de limite abaixo do maximo (nivel 1)")
	else:
		_t.call("ok", _find_label("Mochila cheia (3). Desmarque um ou compre uma mochila maior na Loja.") == null, "sem dica de limite com espaco livre")
	if _press("ShopButton"):
		await _wait_scene(ScenePaths.SHOP)


## Buy_backpack: the first card of the equipment tab, texts of section 2.11, then the 4th item and back.
func _step_backpack_shop() -> void:
	if _scene_path() != ScenePaths.SHOP:
		_t.call("fail", "pre-condicao: nao esta na loja (%s)" % _scene_path())
		return
	var buy: Button = _button("Buy_backpack")
	if buy == null:
		return
	var card: UpgradeCard = buy.get_parent().get_parent() as UpgradeCard
	if card == null:
		# the button sits in a VBox inside the card's HBox; walk up to the card
		var n: Node = buy
		while n != null and not (n is UpgradeCard):
			n = n.get_parent()
		card = n as UpgradeCard
	_t.call("ok", card != null, "Buy_backpack pertence a um UpgradeCard")
	if card == null:
		return
	_t.call("eq", card.get_index(), 0, "o cartao da mochila e o 1o da aba Equipamentos")
	var page: Node = card.get_parent()
	var medkit_btn: Button = _button("Buy_medkit")
	if medkit_btn != null:
		var sibling: Node = medkit_btn
		while sibling != null and sibling.get_parent() != page:
			sibling = sibling.get_parent()
		_t.call("ok", sibling != null and sibling.get_index() > 0, "os cartoes de equipamento vem depois da mochila")
	var weapon_btn: Button = _button("Buy_shotgun_12")
	if weapon_btn != null:
		_t.call("ok", not page.is_ancestor_of(weapon_btn), "a mochila nao esta na aba de armas")
	_t.call("eq", card.get_level_text(), "Nível 1 de 4 · 3 espaços de equipamento", "texto do nivel 1")
	_t.call("eq", card.get_next_text(), "Próximo nível: 4 espaços", "texto do proximo nivel")
	# 1) not enough money: exactly one real below the price
	var price: int = int(Data.get_upgrade_level_def(Ids.BACKPACK, 2)["price"])
	Profile._wallet.money = price - 1
	Profile.add_money(0)
	await get_tree().process_frame
	_t.call("eq", Profile.get_money(), price - 1, "saldo R$ 1.999")
	_t.call("eq", buy.disabled, true, "Buy_backpack desabilitado sem saldo")
	_t.call("eq", buy.text, "SALDO INSUFICIENTE", "texto do botao sem saldo")
	buy.pressed.emit()
	_t.call("eq", Profile.get_upgrade_level(Ids.BACKPACK), 1, "clique sem saldo nao sobe o nivel")
	_t.call("eq", Profile.get_money(), price - 1, "clique sem saldo nao cobra")
	# 2) enough money (Profile.add_money): the button enables and buys
	Profile.add_money(1)
	await get_tree().process_frame
	_t.call("eq", Profile.get_money(), price, "saldo R$ 2.000")
	_t.call("eq", buy.disabled, false, "Buy_backpack habilitado com saldo")
	_t.call("eq", buy.text, "COMPRAR NÍVEL 2", "texto do botao com saldo")
	buy.pressed.emit()
	await get_tree().process_frame
	_t.call("eq", Profile.get_upgrade_level(Ids.BACKPACK), 2, "mochila nivel 2")
	_t.call("eq", Profile.get_money(), 0, "cobrou R$ 2.000")
	_t.call("eq", Profile.get_item_slots(), 4, "4 espacos")
	var message: Label = _node("MessageLabel") as Label
	if message != null:
		_t.call("eq", message.text, "Comprado: Mochila nível 2.", "mensagem da loja")
	_t.call("eq", card.get_level_text(), "Nível 2 de 4 · 4 espaços de equipamento", "texto do nivel 2")
	_t.call("eq", card.get_next_text(), "Próximo nível: 5 espaços", "texto do proximo nivel (2)")
	_t.call("eq", buy.disabled, true, "sem saldo para o nivel 3")
	_t.call("eq", buy.text, "SALDO INSUFICIENTE", "botao do nivel 3 sem saldo")
	# 3) the card at the top level: "Nível máximo", disabled (level poked directly, no payment)
	Profile._inventory.upgrades[Ids.BACKPACK] = 4
	card.refresh()
	_t.call("eq", buy.disabled, true, "nivel maximo: botao desabilitado")
	_t.call("eq", buy.text, "NÍVEL MÁXIMO", "nivel maximo: texto do botao")
	_t.call("eq", card.get_next_text(), "Nível máximo", "nivel maximo: linha do proximo")
	_t.call("eq", card.get_level_text(), "Nível 4 de 4 · 6 espaços de equipamento", "nivel maximo: linha do nivel")
	Profile._inventory.upgrades[Ids.BACKPACK] = 2
	card.refresh()
	_t.call("eq", Profile.get_upgrade_level(Ids.BACKPACK), 2, "nivel de volta a 2")
	# 4) the 4th item, bought from the shop with the new room: binoculars (auto-equipped), and a 5th owned item
	var bino: Button = _button("Buy_binoculars")
	if bino != null:
		Profile.add_money(int(Data.get_equipment(&"binoculars")["price"]))
		await get_tree().process_frame
		bino.pressed.emit()
		await get_tree().process_frame
		_t.call("ok", Profile.owns(&"binoculars"), "binoculo comprado")
	Profile._inventory.add_item(&"leather_vest", 1)   # a 5th owned item that must not fit in 4 slots
	_t.call("eq", Profile.get_loadout_items().size(), 4, "4 itens equipados (3 + o binoculo no espaco novo)")
	_backpack_money_before = Profile.get_money()
	if _press("NextHuntButton"):
		await _wait_scene(ScenePaths.PREPARATION)


## Preparation at level 2: header, 4 checked items, the 5th blocked, StartHuntButton -> request with 4 item_ids -> hunt.
func _step_backpack_preparation() -> void:
	if _scene_path() != ScenePaths.PREPARATION:
		_t.call("fail", "pre-condicao: nao esta na preparacao (%s)" % _scene_path())
		return
	_t.call("ok", _find_label("Equipamentos (mochila nível 2: até 4)") != null, "cabecalho da Preparacao no nivel 2")
	for id: StringName in BACKPACK_ITEMS:
		var check: CheckButton = _node("Item_%s" % id) as CheckButton
		if check == null:
			_t.call("fail", "Preparacao nao tem Item_%s" % id)
			continue
		if not check.button_pressed:
			_t.call("eq", check.disabled, false, "Item_%s pode ser marcado" % id)
			check.button_pressed = true
	var picked: Array[StringName] = Profile.get_loadout_items()
	_t.call("eq", picked.size(), 4, "4 itens no loadout do perfil")
	for id: StringName in BACKPACK_ITEMS:
		_t.call("ok", picked.has(id), "%s no loadout" % id)
	var vest: CheckButton = _node("Item_leather_vest") as CheckButton
	if vest != null:
		_t.call("eq", vest.button_pressed, false, "o 5o item segue desmarcado")
		_t.call("eq", vest.disabled, true, "o 5o item fica bloqueado com a mochila cheia")
	_t.call("ok", _find_label("Mochila cheia (4). Desmarque um ou compre uma mochila maior na Loja.") != null, "dica de limite (nivel 2 de 4)")
	# StartHuntButton builds the request synchronously (the scene change is deferred)
	var c0: Button = _button("Contract_0")
	if c0 != null:
		c0.pressed.emit()
	_started_signals = 0
	_ended.clear()
	if not _press("StartHuntButton"):
		return
	var request: HuntRequest = Router.get_pending_request()
	_t.call("ok", request != null, "Router tem o pedido pendente")
	if request != null:
		_t.call("eq", request.item_ids.size(), 4, "request.item_ids.size() == 4")
		for id: StringName in BACKPACK_ITEMS:
			_t.call("ok", request.item_ids.has(id), "request leva %s" % id)
	if not await _wait_scene(ScenePaths.HUNT, 30.0):
		return
	var hunt: HuntController = _scene() as HuntController
	if hunt == null:
		_t.call("fail", "cena HUNT nao e HuntController")
		return
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_t.call("ok", hunt.is_world_ready(), "mundo pronto")
	for i: int in 5:
		await get_tree().process_frame
	var player: Player = hunt.get_player() as Player
	_t.call("ok", player != null, "jogador existe")
	if player != null and player.get_items() != null:
		var usable: Array[StringName] = player.get_items().get_usable_ids()
		_t.call("eq", usable.size(), 4, "a caçada chega com os 4 itens usaveis no cinto (%s)" % str(usable))
	_ended.clear()
	hunt.debug_force_end(HuntResult.Outcome.ABANDONED)
	if await _wait_scene(ScenePaths.RESULT, 30.0):
		_t.call("eq", _ended.size(), 1, "hunt_ended 1x")
		if _press("MenuButton"):
			await _wait_scene(ScenePaths.MAIN_MENU)


# --------------------------------------------------------------------------------------------
# Energy drink route (docs/plano_faca_mochila_folego.md, F3)
# --------------------------------------------------------------------------------------------

## Menu -> shop: the card says "Fôlego cheio na hora"; without money the button is off; two purchases charge R$ 150 each.
func _step_energy_shop() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	_t.call("eq", Profile.get_item_count(Ids.I_ENERGY_DRINK), 0, "pre-condicao: o perfil nao tem energetico")
	if not (_press("ShopButton") and await _wait_scene(ScenePaths.SHOP)):
		return
	var buy: Button = _button("Buy_energy_drink")
	if buy == null:
		return
	_t.call("ok", _find_label("Fôlego cheio na hora") != null, "o cartao do energetico mostra 'Fôlego cheio na hora'")
	var price: int = int(Data.get_equipment(Ids.I_ENERGY_DRINK).get("price", 0))
	_t.call("eq", price, 150, "energetico custa R$ 150")
	# 1) one real short: the button is off and pressing it does nothing
	Profile._wallet.money = price - 1
	Profile.add_money(0)
	await get_tree().process_frame
	_t.call("eq", buy.disabled, true, "Buy_energy_drink desabilitado sem saldo")
	buy.pressed.emit()
	_t.call("eq", Profile.get_item_count(Ids.I_ENERGY_DRINK), 0, "clique sem saldo nao entrega")
	_t.call("eq", Profile.get_money(), price - 1, "clique sem saldo nao cobra")
	# 2) money for exactly two: two purchases, R$ 150 each
	Profile.add_money(price + 1)
	await get_tree().process_frame
	_t.call("eq", Profile.get_money(), price * 2, "saldo de 2 energeticos")
	_t.call("eq", buy.disabled, false, "Buy_energy_drink habilitado com saldo")
	buy.pressed.emit()
	await get_tree().process_frame
	_t.call("eq", Profile.get_item_count(Ids.I_ENERGY_DRINK), 1, "1o energetico comprado")
	_t.call("eq", Profile.get_money(), price, "cobrou R$ 150")
	buy.pressed.emit()
	await get_tree().process_frame
	_t.call("eq", Profile.get_item_count(Ids.I_ENERGY_DRINK), 2, "2o energetico comprado")
	_t.call("eq", Profile.get_money(), 0, "cobrou R$ 150 de novo")
	_t.call("eq", buy.disabled, true, "sem saldo para o 3o")
	if _press("NextHuntButton"):
		await _wait_scene(ScenePaths.PREPARATION)


## Preparation (backpack level 2, 4/4 full): drop one item, tick the drink, start -> the request carries 2 drinks -> hunt.
func _step_energy_preparation() -> void:
	if _scene_path() != ScenePaths.PREPARATION:
		_t.call("fail", "pre-condicao: nao esta na preparacao (%s)" % _scene_path())
		return
	var drink: CheckButton = _node("Item_energy_drink") as CheckButton
	if drink == null:
		_t.call("fail", "Preparacao nao tem Item_energy_drink")
		return
	_t.call("eq", drink.button_pressed, false, "o energetico comecou desmarcado (mochila cheia, sem espaco)")
	_t.call("eq", drink.disabled, true, "e bloqueado com a mochila cheia")
	var bait: CheckButton = _node("Item_corn_bait") as CheckButton
	if bait == null:
		_t.call("fail", "Preparacao nao tem Item_corn_bait")
		return
	bait.button_pressed = false   # frees one space
	await get_tree().process_frame
	_t.call("eq", drink.disabled, false, "com um espaco livre o energetico pode ser marcado")
	drink.button_pressed = true
	var picked: Array[StringName] = Profile.get_loadout_items()
	_t.call("ok", picked.has(Ids.I_ENERGY_DRINK), "energetico no loadout do perfil")
	_t.call("ok", not picked.has(Ids.I_CORN_BAIT), "a ceva saiu para dar lugar")
	var c0: Button = _button("Contract_0")
	if c0 != null:
		c0.pressed.emit()
	_started_signals = 0
	_ended.clear()
	if not _press("StartHuntButton"):
		return
	var request: HuntRequest = Router.get_pending_request()
	_t.call("ok", request != null, "Router tem o pedido pendente")
	if request != null:
		_t.call("ok", request.item_ids.has(Ids.I_ENERGY_DRINK), "request.item_ids leva o energetico")
		_t.call("eq", int(request.item_counts.get(Ids.I_ENERGY_DRINK, 0)), 2, "request.item_counts[energy_drink] == 2")
		_t.call("eq", request.get_item_count(Ids.I_ENERGY_DRINK), 2, "request.get_item_count(energy_drink) == 2")
	if not await _wait_scene(ScenePaths.HUNT, 30.0):
		return
	var hunt: HuntController = _scene() as HuntController
	if hunt == null:
		_t.call("fail", "cena HUNT nao e HuntController")
		return
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_t.call("ok", hunt.is_world_ready(), "mundo pronto")
	for i: int in 5:
		await get_tree().process_frame
	var player: Player = hunt.get_player() as Player
	_t.call("ok", player != null, "jogador existe")
	if player != null and player.get_items() != null:
		var items: ItemBelt = player.get_items()
		_t.call("eq", items.get_count(Ids.I_ENERGY_DRINK), 2, "o cinto chega com 2 energeticos")
		var usable: Array[StringName] = items.get_usable_ids()
		_t.call("ok", not usable.is_empty() and usable.back() == Ids.I_ENERGY_DRINK, "o energetico e o ultimo espaco usavel (%s)" % str(usable))
	_ended.clear()
	hunt.debug_force_end(HuntResult.Outcome.ABANDONED)
	if await _wait_scene(ScenePaths.RESULT, 30.0):
		_t.call("eq", _ended.size(), 1, "hunt_ended 1x")
		_t.call("eq", Profile.get_item_count(Ids.I_ENERGY_DRINK), 2, "nenhum energetico usado: o estoque segue em 2")
		if _press("MenuButton"):
			await _wait_scene(ScenePaths.MAIN_MENU)


# --------------------------------------------------------------------------------------------
# Knife route (docs/plano_faca_mochila_folego.md, F4): menu -> shop (Buy_knife, first card of the weapons tab) -> buy level 2
# -> preparation -> hunt carrying a level 2 knife. The knife is not an item: it takes no loadout slot.
# --------------------------------------------------------------------------------------------

## Menu -> shop: Buy_knife is the first weapons card; one real short keeps it off; R$ 1.500 buys level 2 (money set with
## Profile.add_money, never a poke at the level).
func _step_knife_shop() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	_t.call("eq", Profile.get_upgrade_level(Ids.KNIFE), 1, "pre-condicao: faca nivel 1")
	var slots_before: int = Profile.get_item_slots()
	var items_before: Array[StringName] = Profile.get_loadout_items()
	if not (_press("ShopButton") and await _wait_scene(ScenePaths.SHOP)):
		return
	var buy: Button = _button("Buy_knife")
	if buy == null:
		return
	var card: Node = buy
	while card != null and not (card is UpgradeCard):
		card = card.get_parent()
	_t.call("ok", card != null, "Buy_knife pertence a um UpgradeCard")
	if card == null:
		return
	var upgrade_card: UpgradeCard = card as UpgradeCard
	_t.call("eq", upgrade_card.get_index(), 0, "o cartao da faca e o 1o da aba Armas")
	var page: Node = upgrade_card.get_parent()
	var gun_btn: Button = _button("Buy_shotgun_12")
	if gun_btn != null:
		_t.call("ok", page.is_ancestor_of(gun_btn), "a faca esta na mesma aba das armas")
		var sibling: Node = gun_btn
		while sibling != null and sibling.get_parent() != page:
			sibling = sibling.get_parent()
		_t.call("ok", sibling != null and sibling.get_index() > 0, "as armas vem depois da faca")
	var backpack_btn: Button = _button("Buy_backpack")
	if backpack_btn != null:
		_t.call("ok", not page.is_ancestor_of(backpack_btn), "a mochila nao esta na aba da faca")
	_t.call("eq", upgrade_card.get_level_text(), "Nível 1 de 4 · Dano 30\nAlcance 2,2 m  |  1,67 golpes/s", "texto do nivel 1 (dano, alcance e cadencia)")
	_t.call("eq", upgrade_card.get_next_text(), "Próximo nível: dano 45", "texto do proximo nivel")
	_t.call("ok", _find_label("Arma branca, sempre com você") != null, "etiqueta do cartao da faca")
	# 1) one real short: the button is off and pressing it does nothing
	var price: int = int(Data.get_upgrade_level_def(Ids.KNIFE, 2)["price"])
	_t.call("eq", price, 1500, "faca nivel 2 custa R$ 1.500")
	Profile._wallet.money = price - 1
	Profile.add_money(0)
	await get_tree().process_frame
	_t.call("eq", buy.disabled, true, "Buy_knife desabilitado sem saldo")
	buy.pressed.emit()
	_t.call("eq", Profile.get_upgrade_level(Ids.KNIFE), 1, "clique sem saldo nao sobe o nivel")
	_t.call("eq", Profile.get_money(), price - 1, "clique sem saldo nao cobra")
	# 2) the missing real arrives through Profile.add_money: the button enables and buys
	Profile.add_money(1)
	await get_tree().process_frame
	_t.call("eq", Profile.get_money(), price, "saldo R$ 1.500")
	_t.call("eq", buy.disabled, false, "Buy_knife habilitado com saldo")
	buy.pressed.emit()
	await get_tree().process_frame
	_t.call("eq", Profile.get_upgrade_level(Ids.KNIFE), 2, "faca nivel 2")
	_t.call("eq", Profile.get_money(), 0, "cobrou R$ 1.500")
	var message: Label = _node("MessageLabel") as Label
	if message != null:
		_t.call("eq", message.text, "Comprado: Faca de caça nível 2.", "mensagem da loja")
	_t.call("eq", upgrade_card.get_level_text(), "Nível 2 de 4 · Dano 45\nAlcance 2,2 m  |  1,67 golpes/s", "texto do nivel 2")
	_t.call("eq", upgrade_card.get_next_text(), "Próximo nível: dano 65", "texto do proximo nivel (2)")
	# the knife takes no backpack space and no loadout slot
	_t.call("eq", Profile.get_item_slots(), slots_before, "a faca nao abre espaco de mochila")
	_t.call("eq", Profile.get_loadout_items(), items_before, "a compra nao mexe nos equipamentos escolhidos")
	_t.call("ok", not Profile.get_loadout_weapons().has(Ids.KNIFE), "a faca nao entra nas armas do loadout")
	if _press("NextHuntButton"):
		await _wait_scene(ScenePaths.PREPARATION)


## Preparation -> start: the request carries knife_level 2 -> hunt: the Player has a level 2 knife (45 damage) -> result.
func _step_knife_hunt() -> void:
	if _scene_path() != ScenePaths.PREPARATION:
		_t.call("fail", "pre-condicao: nao esta na preparacao (%s)" % _scene_path())
		return
	_t.call("ok", _node("Item_knife") == null, "a Preparacao nao oferece a faca como equipamento")
	var c0: Button = _button("Contract_0")
	if c0 != null:
		c0.pressed.emit()
	_started_signals = 0
	_ended.clear()
	if not _press("StartHuntButton"):
		return
	var request: HuntRequest = Router.get_pending_request()
	_t.call("ok", request != null, "Router tem o pedido pendente")
	if request != null:
		_t.call("eq", request.knife_level, 2, "request.knife_level == 2")
		_t.call("ok", not request.weapon_ids.has(Ids.KNIFE), "a faca nao esta em request.weapon_ids")
		_t.call("ok", not request.item_ids.has(Ids.KNIFE), "a faca nao esta em request.item_ids")
	if not await _wait_scene(ScenePaths.HUNT, 30.0):
		return
	var hunt: HuntController = _scene() as HuntController
	if hunt == null:
		_t.call("fail", "cena HUNT nao e HuntController")
		return
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_t.call("ok", hunt.is_world_ready(), "mundo pronto")
	for i: int in 5:
		await get_tree().process_frame
	var player: Player = hunt.get_player() as Player
	_t.call("ok", player != null, "jogador existe")
	if player != null:
		_t.call("eq", player.get_knife_level(), 2, "o jogador chega com a faca nivel 2")
		_t.call("near", player.get_knife_damage(), 45.0, 0.0001, "dano do golpe = 45")
		_t.call("eq", player.get_weapon_count(), request.weapon_ids.size() if request != null else -1, "a faca nao e uma arma do cinto")
	_ended.clear()
	hunt.debug_force_end(HuntResult.Outcome.ABANDONED)
	if await _wait_scene(ScenePaths.RESULT, 30.0):
		_t.call("eq", _ended.size(), 1, "hunt_ended 1x")
		_t.call("eq", Profile.get_upgrade_level(Ids.KNIFE), 2, "a faca continua no nivel 2 depois da caçada")
		if _press("MenuButton"):
			await _wait_scene(ScenePaths.MAIN_MENU)


# --------------------------------------------------------------------------------------------
# Horde route (docs/horda.md section 14): menu -> hunt in horde mode -> result -> shop. The contract route above
# is untouched. The horde hunt is started through Router.start_hunt with the debug request (the room is the
# only way to pick the mode in the UI, and it needs a server).
# --------------------------------------------------------------------------------------------

func _find_label(text: String) -> Label:
	var scene: Node = _scene()
	if scene == null:
		return null
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).text == text:
			return n as Label
		stack.append_array(n.get_children())
	return null


var _horde_money_before: int = 0
var _horde_unlocked_before: int = 0
var _horde_completed_before: Array[bool] = []


func _step_horde_hunt() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	_horde_money_before = Profile.get_money()
	_horde_unlocked_before = Profile.get_unlocked_contract_count(&"mato_grosso")
	_horde_completed_before.clear()
	for i: int in Data.get_contract_count(&"mato_grosso"):
		_horde_completed_before.append(Profile.is_contract_completed(&"mato_grosso", i))
	_started_signals = 0
	_ended.clear()
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE)
	_t.call("ok", req.is_horde(), "pedido de horda")
	Router.start_hunt(req)
	if not await _wait_scene(ScenePaths.HUNT, 30.0):
		return
	var hunt: HuntController = _scene() as HuntController
	if hunt == null:
		_t.call("fail", "cena HUNT nao e HuntController")
		return
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_t.call("ok", hunt.is_world_ready(), "mundo da horda pronto")
	for i: int in 5:
		await get_tree().process_frame
	_t.call("eq", _started_signals, 1, "hunt_started 1x na horda")
	_t.call("eq", hunt.get_mode(), Ids.MODE_HORDE, "get_mode() == horda")
	_t.call("ok", hunt.is_horde(), "is_horde()")
	_t.call("eq", hunt.get_horde_wave(), 1, "onda 1 anunciada")
	_t.call("eq", hunt.get_horde_wave_count(), 8, "8 ondas")
	_t.call("eq", hunt.get_horde_phase(), Ids.HP_INTERMISSION, "comeca no intervalo")
	_t.call("ok", hunt.get_horde_countdown_s() > 0.0 and hunt.get_horde_countdown_s() <= float(Data.get_horde()["first_wave_delay_s"]), "contador do primeiro intervalo (%.1f)" % hunt.get_horde_countdown_s())
	_t.call("ok", hunt.get_objective_position().is_finite(), "celeiro tem posicao")
	_t.call("eq", hunt.get_player().get_weapon_count(), Data.get_weapon_ids().size(), "todas as armas")
	_t.call("ok", hunt.get_player().has_infinite_reserve(), "reserva infinita")
	# the HUD in horde layout (A): wave label and banner exist, the contract counter is gone, the bar says "Celeiro"
	_t.call("ok", hunt.find_child("WaveLabel", true, false) != null, "HUD: WaveLabel existe")
	_t.call("ok", hunt.find_child("WaveBanner", true, false) != null, "HUD: WaveBanner existe")
	_t.call("ok", _find_label("Celeiro 100%") != null, "HUD: barra do topo diz 'Celeiro 100%'")
	_t.call("ok", _find_label("Lavoura 100%") == null, "HUD: sem 'Lavoura' na horda")
	_ended.clear()
	hunt.debug_force_end(HuntResult.Outcome.VICTORY)
	await _wait_scene(ScenePaths.RESULT, 30.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended 1x na horda")


func _step_horde_result() -> void:
	if _scene_path() != ScenePaths.RESULT:
		_t.call("fail", "pre-condicao: nao esta no resultado (%s)" % _scene_path())
		return
	var r: HuntResult = Router.last_result
	_t.call("ok", r != null, "Router.last_result definido")
	if r != null:
		_t.call("eq", r.mode, Ids.MODE_HORDE, "last_result.mode")
		_t.call("eq", r.outcome, HuntResult.Outcome.VICTORY, "outcome")
		_t.call("ok", not r.counts_for_progression, "horda nunca conta para progressao")
		_t.call("eq", r.contract_bonus, Profile.horde_bonus(100.0), "bonus de defesa com o estoque cheio")
		_t.call("eq", r.horde_wave_count, 8, "horde_wave_count")
		_t.call("eq", r.horde_waves_cleared, 8, "vitoria forcada: ondas vencidas = ondas do plano")
		_t.call("eq", Profile.get_money(), _horde_money_before + Profile.horde_bonus(100.0), "saldo += Profile.horde_bonus(100) (1x)")
	_t.call("eq", Profile.get_unlocked_contract_count(&"mato_grosso"), _horde_unlocked_before, "contratos liberados iguais")
	for i: int in _horde_completed_before.size():
		_t.call("eq", Profile.is_contract_completed(&"mato_grosso", i), _horde_completed_before[i], "contrato %d: concluido como antes" % i)
	_t.call("ok", _find_label("Celeiro defendido!") != null, "titulo 'Celeiro defendido!'")
	_t.call("ok", _find_label("Ondas vencidas") != null, "linha 'Ondas vencidas'")
	_t.call("ok", _find_label("8 de 8") != null, "valor '8 de 8'")
	_t.call("ok", _find_label("Celeiro preservado") != null, "linha 'Celeiro preservado'")
	var retry: Button = _button("RetryButton")
	if retry != null:
		_t.call("eq", retry.is_visible_in_tree(), false, "%RetryButton invisivel na horda")
	var cont: Button = _button("ContinueButton")
	if cont != null:
		_t.call("ok", cont.is_visible_in_tree(), "%ContinueButton visivel")
	if _press("ContinueButton"):
		await _wait_scene(ScenePaths.SHOP)


func _step_horde_back_to_menu() -> void:
	if _scene_path() != ScenePaths.SHOP:
		_t.call("fail", "pre-condicao: nao esta na loja (%s)" % _scene_path())
		return
	if _press("BackButton"):
		await _wait_scene(ScenePaths.MAIN_MENU)


# --------------------------------------------------------------------------------------------
# Horde level 2 (docs/plano_horda_nivel2.md): menu -> hunt at level 2 -> result -> shop. Same route as level 1; what
# changes is the rules (counted ammo, crates, confine, spawn) and the prize/header of the result.
# --------------------------------------------------------------------------------------------

func _step_horde2_hunt() -> void:
	if _scene_path() != ScenePaths.MAIN_MENU:
		_t.call("fail", "pre-condicao: nao esta no menu (%s)" % _scene_path())
		return
	_horde_money_before = Profile.get_money()
	_horde_unlocked_before = Profile.get_unlocked_contract_count(&"mato_grosso")
	_horde_completed_before.clear()
	for i: int in Data.get_contract_count(&"mato_grosso"):
		_horde_completed_before.append(Profile.is_contract_completed(&"mato_grosso", i))
	_started_signals = 0
	_ended.clear()
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, 2)
	_t.call("ok", req.is_horde() and req.horde_level == 2, "pedido de horda Nivel 2")
	Router.start_hunt(req)
	if not await _wait_scene(ScenePaths.HUNT, 30.0):
		return
	var hunt: HuntController = _scene() as HuntController
	if hunt == null:
		_t.call("fail", "cena HUNT nao e HuntController")
		return
	var t0: int = Time.get_ticks_msec()
	while not hunt.is_world_ready() and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	_t.call("ok", hunt.is_world_ready(), "mundo da horda Nivel 2 pronto")
	for i: int in 5:
		await get_tree().process_frame
	_t.call("eq", _started_signals, 1, "hunt_started 1x na horda Nivel 2")
	_t.call("ok", hunt.is_horde(), "is_horde()")
	_t.call("eq", hunt.get_horde_level(), 2, "get_horde_level() == 2")
	_t.call("eq", hunt.get_horde_wave(), 1, "onda 1 anunciada")
	_t.call("eq", hunt.get_horde_phase(), Ids.HP_INTERMISSION, "comeca no intervalo")
	var player: PlayerBase = hunt.get_player()
	_t.call("eq", player.get_weapon_count(), Data.get_weapon_ids().size(), "todas as armas")
	_t.call("ok", not player.has_infinite_reserve(), "Nivel 2: reserva contada (nao infinita)")
	_t.call("ok", player.get_ammo_reserve() > 0, "Nivel 2: comeca com reserva (%d)" % player.get_ammo_reserve())
	_t.call("ok", not player.needs_ammo() or player.get_ammo_reserve() > 0, "needs_ammo coerente")
	var spawn: Vector3 = player.global_position
	_t.call("ok", Vector2(spawn.x, spawn.z).distance_to(Vector2(30.0, -74.0)) <= 4.0, "jogador nasce a <= 4 m de (30, -74): %s" % str(spawn))
	var bounds: Rect2 = hunt.get_player_bounds()
	_t.call("ok", bounds.has_area() and bounds.has_point(Vector2(spawn.x, spawn.z)), "get_player_bounds() definido e com o jogador dentro (%s)" % str(bounds))
	_t.call("eq", hunt.get_ammo_crate_positions().size(), 3, "3 caixas de municao disponiveis")
	_t.call("ok", hunt.debug_ammo_crates() != null, "no AmmoCrates existe")
	_t.call("ok", hunt.find_child("AmmoCrates", true, false) != null, "no 'AmmoCrates' na cena")
	_t.call("ok", hunt.find_child("WaveLabel", true, false) != null, "HUD: WaveLabel existe")
	_t.call("ok", _find_label("Celeiro 100%") != null, "HUD: barra do topo diz 'Celeiro 100%'")
	_ended.clear()
	hunt.debug_force_end(HuntResult.Outcome.VICTORY)
	await _wait_scene(ScenePaths.RESULT, 30.0)
	_t.call("eq", _ended.size(), 1, "hunt_ended 1x na horda Nivel 2")


func _step_horde2_result() -> void:
	if _scene_path() != ScenePaths.RESULT:
		_t.call("fail", "pre-condicao: nao esta no resultado (%s)" % _scene_path())
		return
	var r: HuntResult = Router.last_result
	_t.call("ok", r != null, "Router.last_result definido")
	if r != null:
		_t.call("eq", r.mode, Ids.MODE_HORDE, "last_result.mode")
		_t.call("eq", r.horde_level, 2, "last_result.horde_level == 2")
		_t.call("eq", r.outcome, HuntResult.Outcome.VICTORY, "outcome")
		_t.call("ok", not r.counts_for_progression, "horda nunca conta para progressao")
		_t.call("eq", r.contract_bonus, Profile.horde_bonus(100.0, 2), "bonus do Nivel 2 com o estoque cheio")
		_t.call("eq", r.contract_bonus, 5000, "bonus de R$ 5000")
		_t.call("eq", Profile.get_money(), _horde_money_before + Profile.horde_bonus(100.0, 2), "saldo += Profile.horde_bonus(100, 2) (1x)")
	_t.call("eq", Profile.get_unlocked_contract_count(&"mato_grosso"), _horde_unlocked_before, "contratos liberados iguais")
	for i: int in _horde_completed_before.size():
		_t.call("eq", Profile.is_contract_completed(&"mato_grosso", i), _horde_completed_before[i], "contrato %d: concluido como antes" % i)
	_t.call("ok", _find_label("Celeiro defendido!") != null, "titulo 'Celeiro defendido!'")
	var level_name: String = str(Data.get_horde_level(2).get("name", ""))
	var map_name: String = str(Data.get_map(&"mato_grosso").get("name", "mato_grosso"))
	_t.call("ok", _find_label("Horda Javali · %s  |  %s" % [level_name, map_name]) != null, "cabecalho 'Horda Javali · %s  |  %s'" % [level_name, map_name])
	var retry: Button = _button("RetryButton")
	if retry != null:
		_t.call("eq", retry.is_visible_in_tree(), false, "%RetryButton invisivel na horda")
	var cont: Button = _button("ContinueButton")
	if cont != null:
		_t.call("ok", cont.is_visible_in_tree(), "%ContinueButton visivel")
	if _press("ContinueButton"):
		await _wait_scene(ScenePaths.SHOP)
