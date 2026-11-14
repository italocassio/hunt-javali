extends Node
## tests/flow_test.tscn: boot -> menu -> map -> preparation -> hunt -> result -> shop -> buy -> preparation,
## driven only through the buttons of docs/arquitetura.md section 11 (`button.pressed.emit()`).
##
## Scene changes free the current scene, so the real runner is a second node of the same script that is
## parented to the root window (it survives Router.goto).
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
	_t.call("eq", friends.text, "Jogar com amigos (beta)", "texto do FriendsButton")
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
