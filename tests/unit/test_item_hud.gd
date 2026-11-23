extends "res://tests/lib/test_case.gd"
## Fixed item keys and the item bar (docs/arquitetura.md sections 4, 8.4 and 8.11, contract 1.3):
## InputSetup.get_item_action / get_key_label, ItemBelt.use_item by id, Quickbar slots, TouchControls item buttons.
## No selection exists any more: every usable item has its own action.

const ITEM_ORDER: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink"]
## The four usable items of before F3 (the energy drink closes the list; docs/plano_faca_mochila_folego.md 1.3).
const ITEMS_BEFORE_F3: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"binoculars"]


## A hunter whose health the test controls (PlayerBase answers a constant 100 / 100).
class StubPlayer extends PlayerBase:
	var hp: float = 100.0

	func get_health() -> float:
		return hp

	func heal(amount: float) -> void:
		hp = minf(hp + amount, get_max_health())


var _belts: Array[ItemBelt] = []


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

func _request(ids: Array[StringName], counts: Dictionary = {}) -> HuntRequest:
	var r: HuntRequest = HuntRequest.make_debug()
	r.item_ids = ids
	r.item_counts = counts
	return r


## Belt set up with `ids`; consumables default to the counts the Profile start gives (medkit 1, drone 3, bait 2).
func _belt(ids: Array[StringName], counts: Dictionary = {}, hp: float = 100.0) -> ItemBelt:
	var player: StubPlayer = StubPlayer.new()
	player.hp = hp
	track(player)
	var merged: Dictionary = {&"medkit": 1, &"corn_bait": 2, &"scout_drone": 3}
	merged.merge(counts, true)
	var belt: ItemBelt = ItemBelt.new()
	belt.setup(_request(ids, merged), player, null)
	_belts.append(belt)
	return belt


func _free_belts() -> void:
	for b: ItemBelt in _belts:
		if is_instance_valid(b):
			b.free()
	_belts.clear()


func _item_name(id: StringName) -> String:
	return String(Data.get_equipment(id).get("name", ""))


func _bar(belt: ItemBelt) -> Quickbar:
	var qb: Quickbar = Quickbar.new()
	track(qb)
	qb.bind(belt)
	return qb


func _slot(qb: Quickbar, id: StringName) -> Quickbar.Slot:
	return qb.get_node_or_null("Slot_%s" % id) as Quickbar.Slot


# --------------------------------------------------------------------------------------------
# InputSetup: actions, keys, labels
# --------------------------------------------------------------------------------------------

func test_item_actions_table_matches_data() -> void:
	eq(InputSetup.ITEM_ACTIONS.keys(), ITEM_ORDER, "ITEM_ACTIONS: ids na ordem dos espacos")
	for id: StringName in InputSetup.ITEM_ACTIONS:
		var action: StringName = InputSetup.ITEM_ACTIONS[id]
		eq(action, StringName("use_" + String(id)), "%s -> use_<id>" % id)
		ok(InputSetup.ACTIONS.has(String(action)), "%s esta em ACTIONS" % action)
		ok(InputMap.has_action(action), "%s registrada no InputMap" % action)
		var kind: String = String(Data.get_equipment(id).get("kind", ""))
		ok(kind == "active" or kind == "consumable", "%s e usavel (kind %s)" % [id, kind])
	# every usable item in the data has a key (nothing usable is left without one)
	for id: StringName in Data.get_equipment_ids():
		var kind: String = String(Data.get_equipment(id).get("kind", ""))
		if kind == "active" or kind == "consumable":
			ok(InputSetup.ITEM_ACTIONS.has(id), "item usavel %s tem acao" % id)
	for gone: String in ["use_item", "item_next"]:
		ok(not InputMap.has_action(gone), "acao removida '%s' nao existe mais" % gone)
		ok(not InputSetup.ACTIONS.has(gone), "'%s' fora de ACTIONS" % gone)
	ok(InputMap.has_action("spectate_next"), "spectate_next registrada")


func test_get_item_action() -> void:
	eq(InputSetup.get_item_action(&"medkit"), &"use_medkit", "kit")
	eq(InputSetup.get_item_action(&"corn_bait"), &"use_corn_bait", "ceva")
	eq(InputSetup.get_item_action(&"scout_drone"), &"use_scout_drone", "drone")
	eq(InputSetup.get_item_action(&"binoculars"), &"use_binoculars", "binoculo")
	eq(InputSetup.get_item_action(&"energy_drink"), &"use_energy_drink", "energetico (F3)")
	for passive: StringName in [&"leather_vest", &"extra_ammo", &"thermal_scope"]:
		eq(InputSetup.get_item_action(passive), &"", "passivo %s nao tem acao" % passive)
	eq(InputSetup.get_item_action(&""), &"", "id vazio")
	eq(InputSetup.get_item_action(&"inexistente"), &"", "id desconhecido")


func test_get_key_label_of_each_item_action() -> void:
	eq(InputSetup.get_key_label(&"use_medkit"), "Q", "kit")
	eq(InputSetup.get_key_label(&"use_corn_bait"), "G", "ceva")
	eq(InputSetup.get_key_label(&"use_scout_drone"), "V", "drone")
	eq(InputSetup.get_key_label(&"use_binoculars"), "B", "binoculo")
	eq(InputSetup.get_key_label(&"use_energy_drink"), "T", "energetico (F3)")
	eq(InputSetup.get_key_label(&"dog_command"), "E", "cao")
	eq(InputSetup.get_key_label(&"spectate_next"), "F", "espectador")
	for id: StringName in InputSetup.ITEM_ACTIONS:
		ne(InputSetup.get_key_label(InputSetup.get_item_action(id)), "", "%s tem letra" % id)


func test_get_key_label_edge_cases() -> void:
	eq(InputSetup.get_key_label(&"fire"), "", "fire nao tem tecla (vem do mouse)")
	eq(InputSetup.get_key_label(&"aim"), "", "aim nao tem tecla")
	eq(InputSetup.get_key_label(&"weapon_swap"), "", "weapon_swap so no toque")
	eq(InputSetup.get_key_label(&"nao_existe"), "", "acao desconhecida")
	eq(InputSetup.get_key_label(&""), "", "acao vazia")
	eq(InputSetup.get_key_label(&"weapon_1"), "1", "tecla numerica")


func test_item_keys_are_unique_physical_keys() -> void:
	var want: Dictionary = {"use_medkit": KEY_Q, "use_corn_bait": KEY_G, "use_scout_drone": KEY_V,
		"use_binoculars": KEY_B, "use_energy_drink": KEY_T, "dog_command": KEY_E, "spectate_next": KEY_F}
	for action: String in want:
		var keys: Array[int] = []
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append(int((ev as InputEventKey).physical_keycode))
		eq(keys, [int(want[action])] as Array[int], "%s: so a tecla %s" % [action, OS.get_keycode_string(int(want[action]))])
	# no physical key serves two actions, with ONE documented exception: F serves spectate_next and interact
	# (docs/plano_horda_nivel2.md 4.9 and risk R9: interact is read only with the player alive, spectate_next only
	# with the spectator camera active, so they never act together). Exactly that pair and nothing else.
	var owners_of: Dictionary = {}
	for action: String in InputSetup.ACTIONS:
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var code: int = int((ev as InputEventKey).physical_keycode)
				if not owners_of.has(code):
					owners_of[code] = []
				(owners_of[code] as Array).append(action)
	for code: int in owners_of:
		var owners: Array = owners_of[code]
		owners.sort()
		if code == int(KEY_F):
			eq(owners, ["interact", "spectate_next"], "F e compartilhada exatamente por interact e spectate_next")
		else:
			eq(owners.size(), 1, "tecla %s usada por mais de uma acao: %s" % [OS.get_keycode_string(code), str(owners)])


func test_pressing_an_item_key_presses_only_its_action() -> void:
	InputSetup.release_all_actions()
	InputSetup.set_touch_override("off")
	for action: String in ["use_medkit", "use_corn_bait", "use_scout_drone", "use_binoculars", "use_energy_drink", "spectate_next"]:
		var code: int = int((InputMap.action_get_events(action)[0] as InputEventKey).physical_keycode)
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code as Key
		ev.pressed = true
		Input.parse_input_event(ev)
		await frames(2)
		ok(Input.is_action_pressed(action), "tecla aperta aperta %s" % action)
		for other: String in InputSetup.ACTIONS:
			if other == action:
				continue
			if action == "spectate_next" and other == "interact":
				ok(Input.is_action_pressed(other), "F aperta spectate_next e interact juntas (par documentado, R9)")
				continue
			ok(not Input.is_action_pressed(other), "%s nao aperta %s" % [action, other])
		ev = ev.duplicate() as InputEventKey
		ev.pressed = false
		Input.parse_input_event(ev)
		await frames(2)
		ok(not Input.is_action_pressed(action), "soltar a tecla solta %s" % action)
	InputSetup.release_all_actions()
	InputSetup.set_touch_override("auto")


# --------------------------------------------------------------------------------------------
# ItemBelt
# --------------------------------------------------------------------------------------------

func test_belt_has_no_selection_api() -> void:
	var belt: ItemBelt = _belt([&"medkit"])
	for gone: String in ["next", "get_selected_id", "use_selected"]:
		ok(not belt.has_method(gone), "ItemBelt.%s foi removido" % gone)
	ok(not belt.has_signal("selection_changed"), "signal selection_changed foi removido")
	for kept: String in ["use_item", "get_busy_item", "get_usable_ids", "get_count", "cancel_use"]:
		ok(belt.has_method(kept), "ItemBelt.%s existe" % kept)
	_free_belts()


func test_belt_usable_ids_follow_item_actions_order_not_loadout_order() -> void:
	var belt: ItemBelt = _belt([&"binoculars", &"scout_drone", &"leather_vest", &"medkit"])
	eq(belt.get_usable_ids(), [&"medkit", &"scout_drone", &"binoculars"] as Array[StringName], "ordem de ITEM_ACTIONS, sem o colete")
	ok(not belt.has_item(&"leather_vest"), "passivo nao e usavel")
	eq(belt.get_count(&"medkit"), 1, "contagem do kit")
	eq(belt.get_count(&"scout_drone"), 3, "contagem do drone")
	eq(belt.get_count(&"binoculars"), -1, "binoculo: -1")
	eq(belt.get_count(&"corn_bait"), -1, "item nao trazido: -1")
	var all4: ItemBelt = _belt([&"scout_drone", &"corn_bait", &"binoculars", &"medkit"])
	eq(all4.get_usable_ids(), ITEMS_BEFORE_F3, "sem o energetico: os 4 usaveis na ordem das acoes")
	var all5: ItemBelt = _belt([&"energy_drink", &"scout_drone", &"corn_bait", &"binoculars", &"medkit"], {&"energy_drink": 2})
	eq(all5.get_usable_ids(), ITEM_ORDER, "com o energetico: os 5 usaveis, ele por ultimo")
	eq(all5.get_count(&"energy_drink"), 2, "contagem do energetico")
	_free_belts()


func test_use_item_not_brought_says_so_and_does_nothing() -> void:
	var belt: ItemBelt = _belt([&"medkit"])
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	var used: Dictionary = record_signal(GameEvents.item_used)
	eq(belt.use_item(&"scout_drone"), false, "drone nao trazido")
	eq(msg["count"], 1, "uma mensagem")
	if int(msg["count"]) >= 1:
		eq(msg["calls"][0][0], "Você não trouxe este item: %s." % _item_name(&"scout_drone"), "texto (nome completo do dado)")
		eq(msg["calls"][0][1], ItemBelt.MESSAGE_S, "duracao da mensagem")
	eq(belt.use_item(&"binoculars"), false, "binoculo nao trazido")
	eq(belt.use_item(&"corn_bait"), false, "ceva nao trazida")
	eq(msg["count"], 3, "uma mensagem por tentativa")
	eq(used["count"], 0, "nenhum item_used")
	eq(belt.is_busy(), false, "nao ficou ocupado")
	eq(belt.is_binoculars_active(), false, "binoculo continua desligado")
	_free_belts()


func test_use_item_passive_empty_or_unknown_is_false_without_message() -> void:
	var belt: ItemBelt = _belt([&"leather_vest", &"medkit"])
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	eq(belt.use_item(&"leather_vest"), false, "passivo trazido")
	eq(belt.use_item(&"extra_ammo"), false, "passivo nao trazido")
	eq(belt.use_item(&"thermal_scope"), false, "outro passivo")
	eq(belt.use_item(&""), false, "id vazio")
	eq(msg["count"], 0, "nenhuma mensagem")
	_free_belts()


func test_use_item_unknown_id_is_false_without_message() -> void:
	expect_errors()   # known bug: ItemBelt.use_item(unknown id) makes Data.get_equipment log "Data: unknown id" (relatado no QA da HF1)
	var belt: ItemBelt = _belt([&"medkit"])
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	eq(belt.use_item(&"inexistente"), false, "id desconhecido")
	eq(msg["count"], 0, "nenhuma mensagem")
	_free_belts()


func test_use_item_exhausted_says_so_and_keeps_zero() -> void:
	var belt: ItemBelt = _belt([&"scout_drone", &"medkit"], {&"scout_drone": 0, &"medkit": 0}, 50.0)
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	var used: Dictionary = record_signal(GameEvents.item_used)
	eq(belt.get_count(&"scout_drone"), 0, "comecou com 0")
	eq(belt.use_item(&"scout_drone"), false, "drone esgotado")
	eq(belt.use_item(&"medkit"), false, "kit esgotado (vida nao esta cheia)")
	eq(msg["count"], 2, "duas mensagens")
	if int(msg["count"]) >= 2:
		eq(msg["calls"][0][0], "Acabou: %s." % _item_name(&"scout_drone"), "texto do drone")
		eq(msg["calls"][1][0], "Acabou: %s." % _item_name(&"medkit"), "texto do kit")
	eq(belt.get_count(&"scout_drone"), 0, "continua 0, nunca negativo")
	eq(belt.is_busy(), false, "kit esgotado nao inicia uso")
	eq(used["count"], 0, "nenhum item_used")
	_free_belts()


func test_use_item_ok_consumes_and_announces() -> void:
	var belt: ItemBelt = _belt([&"scout_drone", &"corn_bait"])
	var used: Dictionary = record_signal(GameEvents.item_used)
	var changed: Dictionary = record_signal(belt.counts_changed)
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	eq(belt.use_item(&"scout_drone"), true, "drone usado")
	eq(belt.get_count(&"scout_drone"), 2, "3 -> 2")
	eq(used["count"], 1, "item_used uma vez")
	if int(used["count"]) >= 1:
		eq(used["calls"][0][0], &"scout_drone", "item_used com o id")
	eq(changed["count"], 1, "counts_changed uma vez")
	near(belt.drone_reveal_s, float(Data.get_equipment(&"scout_drone")["effect"]["reveal_s"]), 0.001, "revelacao vem do dado")
	eq(msg["calls"][0][0], "Drone batedor no ar.", "mensagem do drone")
	eq(belt.use_item(&"corn_bait"), true, "ceva usada")
	eq(belt.get_count(&"corn_bait"), 1, "2 -> 1")
	eq(used["count"], 2, "item_used da ceva")
	# the drone runs dry after its 3 units, then says so
	eq(belt.use_item(&"scout_drone"), true, "segundo drone")
	eq(belt.use_item(&"scout_drone"), true, "terceiro drone")
	eq(belt.get_count(&"scout_drone"), 0, "esgotou")
	eq(belt.use_item(&"scout_drone"), false, "quarto drone: acabou")
	eq(belt.get_count(&"scout_drone"), 0, "continua 0")
	_free_belts()


func test_use_item_medkit_flow() -> void:
	var belt: ItemBelt = _belt([&"medkit", &"scout_drone"], {}, 60.0)
	var started: Dictionary = record_signal(belt.use_started)
	var finished: Dictionary = record_signal(belt.use_finished)
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	eq(belt.get_busy_item(), &"", "ninguem em uso no inicio")
	eq(belt.use_item(&"medkit"), true, "kit com vida 60 comeca")
	eq(belt.get_busy_item(), &"medkit", "get_busy_item")
	ok(belt.is_busy(), "ocupado")
	eq(started["count"], 1, "use_started")
	if int(started["count"]) >= 1:
		eq(started["calls"][0][0], &"medkit", "use_started com o id")
		near(float(started["calls"][0][1]), float(Data.get_equipment(&"medkit")["effect"]["use_time_s"]), 0.001, "duracao do dado")
	eq(belt.get_count(&"medkit"), 1, "nao gasta ate terminar")
	# busy: nothing else can start
	eq(belt.use_item(&"medkit"), false, "kit de novo enquanto usa")
	eq(belt.use_item(&"scout_drone"), false, "drone enquanto usa o kit")
	eq(belt.get_count(&"scout_drone"), 3, "drone intacto")
	var duration: float = float(Data.get_equipment(&"medkit")["effect"]["use_time_s"])
	belt._process(duration * 0.5)
	near(belt.get_busy_progress(), 0.5, 0.01, "metade do uso")
	eq(belt.get_busy_item(), &"medkit", "ainda em uso")
	belt._process(duration)
	eq(belt.get_busy_item(), &"", "terminou")
	eq(belt.is_busy(), false, "livre")
	eq(belt.get_count(&"medkit"), 0, "kit gasto")
	eq(finished["count"], 1, "use_finished")
	if int(finished["count"]) >= 1:
		eq(finished["calls"][0][0], &"medkit", "use_finished com o id")
	near(belt.get_busy_progress(), 0.0, 0.0001, "progresso zerado")
	# the stub hunter was healed by the data amount
	var player: StubPlayer = get_stub_player_of(belt)
	if player != null:
		near(player.hp, minf(60.0 + float(Data.get_equipment(&"medkit")["effect"]["heal"]), 100.0), 0.01, "vida curada")
	# exhausted now: the same key says "Acabou" even though health is not full
	player.hp = 40.0
	eq(belt.use_item(&"medkit"), false, "sem kit")
	eq(msg["calls"][msg["calls"].size() - 1][0], "Acabou: %s." % _item_name(&"medkit"), "mensagem de esgotado")
	_free_belts()


func get_stub_player_of(belt: ItemBelt) -> StubPlayer:
	return belt._player as StubPlayer


func test_use_item_medkit_with_full_health_does_not_spend() -> void:
	var belt: ItemBelt = _belt([&"medkit"], {}, 100.0)
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	var started: Dictionary = record_signal(belt.use_started)
	eq(belt.use_item(&"medkit"), false, "vida cheia")
	eq(msg["calls"][0][0], "Sua vida já está cheia.", "mensagem")
	eq(belt.get_count(&"medkit"), 1, "kit nao gasto")
	eq(started["count"], 0, "sem use_started")
	eq(belt.get_busy_item(), &"", "ninguem em uso")
	_free_belts()


func test_cancel_use_clears_busy_item_and_keeps_the_kit() -> void:
	var belt: ItemBelt = _belt([&"medkit"], {}, 30.0)
	var finished: Dictionary = record_signal(belt.use_finished)
	eq(belt.use_item(&"medkit"), true, "comecou")
	belt.cancel_use()
	eq(belt.get_busy_item(), &"", "cancelado")
	eq(belt.is_busy(), false, "livre")
	eq(belt.get_count(&"medkit"), 1, "kit nao gasto")
	eq(finished["count"], 1, "use_finished")
	if int(finished["count"]) >= 1:
		eq(finished["calls"][0][0], &"", "&\"\" = uso cancelado")
	belt.cancel_use()
	eq(finished["count"], 1, "cancelar sem uso nao emite")
	_free_belts()


func test_use_item_binoculars_toggles() -> void:
	var belt: ItemBelt = _belt([&"binoculars"])
	var changed: Dictionary = record_signal(belt.binoculars_changed)
	eq(belt.use_item(&"binoculars"), true, "liga")
	ok(belt.is_binoculars_active(), "ativo")
	eq(belt.use_item(&"binoculars"), true, "desliga")
	ok(not belt.is_binoculars_active(), "inativo")
	eq(changed["count"], 2, "binoculars_changed duas vezes")
	if int(changed["count"]) >= 2:
		eq([changed["calls"][0][0], changed["calls"][1][0]], [true, false], "true depois false")
	eq(belt.get_count(&"binoculars"), -1, "sem contagem")
	_free_belts()


# --------------------------------------------------------------------------------------------
# Quickbar
# --------------------------------------------------------------------------------------------

func test_quickbar_constants() -> void:
	eq(Quickbar.DOG_SLOT, &"dog_command", "DOG_SLOT")
	eq(Quickbar.FLASH_HZ, 2.0, "FLASH_HZ")


func test_quickbar_slot_order_follows_item_actions_with_dog_last() -> void:
	InputSetup.set_touch_override("off")
	var belt: ItemBelt = _belt([&"binoculars", &"scout_drone", &"medkit"])
	var qb: Quickbar = _bar(belt)
	eq(qb.get_slot_ids(), [&"medkit", &"scout_drone", &"binoculars"] as Array[StringName], "ordem das acoes")
	qb.set_dog_present(true)
	eq(qb.get_slot_ids(), [&"medkit", &"scout_drone", &"binoculars", &"dog_command"] as Array[StringName], "cao por ultimo")
	# the order on screen (child order) matches get_slot_ids
	var names: Array[String] = []
	for c: Node in qb.get_children():
		names.append(String(c.name))
	eq(names, ["Slot_medkit", "Slot_scout_drone", "Slot_binoculars", "Slot_dog_command"], "nomes dos nos")
	# the same order for any loadout order: compare with ITEM_ACTIONS filtered by what was brought
	var expected: Array[StringName] = []
	for id: StringName in InputSetup.ITEM_ACTIONS:
		if belt.has_item(id):
			expected.append(id)
	expected.append(&"dog_command")
	eq(qb.get_slot_ids(), expected, "= ITEM_ACTIONS filtrado + cao")
	qb.set_dog_present(true)
	eq(qb.get_slot_ids().size(), 4, "set_dog_present(true) duas vezes nao duplica")
	qb.set_dog_present(false)
	eq(qb.get_slot_ids(), [&"medkit", &"scout_drone", &"binoculars"] as Array[StringName], "sem cao")
	ok(qb.get_node_or_null("Slot_dog_command") == null, "no do cao removido")
	qb.set_dog_present(false)
	eq(qb.get_slot_ids().size(), 3, "set_dog_present(false) duas vezes e inofensivo")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_dog_stays_last_across_rebind() -> void:
	InputSetup.set_touch_override("off")
	var qb: Quickbar = _bar(_belt([&"medkit", &"corn_bait", &"scout_drone"]))
	qb.set_dog_present(true)
	eq(qb.get_slot_ids().back(), &"dog_command", "cao por ultimo")
	qb.bind(_belt([&"binoculars", &"corn_bait"]))
	eq(qb.get_slot_ids(), [&"corn_bait", &"binoculars", &"dog_command"] as Array[StringName], "novo bind troca os itens, cao continua por ultimo")
	ok(qb.get_node_or_null("Slot_medkit") == null, "slot antigo removido")
	qb.bind(null)
	eq(qb.get_slot_ids(), [&"dog_command"] as Array[StringName], "bind(null): so o cao")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_with_the_energy_drink_has_six_slots_with_the_drink_before_the_dog() -> void:
	## docs/plano_faca_mochila_folego.md 1.3: the energy drink is the last usable slot (by ITEM_ACTIONS order), the dog stays last.
	InputSetup.set_touch_override("off")
	var belt: ItemBelt = _belt([&"energy_drink", &"binoculars", &"scout_drone", &"corn_bait", &"medkit"], {&"energy_drink": 3})
	var qb: Quickbar = _bar(belt)
	eq(qb.get_slot_ids(), ITEM_ORDER, "5 usaveis na ordem das acoes, o energetico por ultimo")
	qb.set_dog_present(true)
	eq(qb.get_slot_ids(), [&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink", &"dog_command"] as Array[StringName],
		"5 usaveis + cao = 6 espacos, o cao por ultimo")
	var drink: Quickbar.Slot = _slot(qb, &"energy_drink")
	ok(drink != null, "espaco do energetico existe")
	if drink != null:
		eq(drink.key_label.text, "T", "tecla do energetico")
		eq(drink.count_label.text, "x3", "quantidade do energetico")
		ok(drink.count_label.visible, "o energetico (consumivel) mostra quantidade")
		near(drink.self_modulate.a, 1.0, 0.001, "com estoque: normal")
		belt._counts[&"energy_drink"] = 0
		belt.counts_changed.emit()
		eq(drink.count_label.text, "x0", "contagem atualizada pelo sinal")
		near(drink.self_modulate.a, Quickbar.DIM_ALPHA, 0.001, "acabou: espaco apagado")
	# the flash goes to the drink slot only (the HUD blinks it when the hunter gets tired)
	qb.flash(&"energy_drink", true)
	qb.flash(&"energy_drink", false)
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_item_card_stats_text_of_the_energy_drink() -> void:
	eq(ItemCard.stats_text(&"energy_drink"), "Fôlego cheio na hora", "cartao da loja (frac 1,0)")
	eq(Data.get_item_category(&"energy_drink"), &"equipment", "categoria do energetico")


func test_quickbar_slot_contents() -> void:
	InputSetup.set_touch_override("off")
	var qb: Quickbar = _bar(_belt([&"medkit", &"scout_drone", &"binoculars"]))
	qb.set_dog_present(true)
	var kit: Quickbar.Slot = _slot(qb, &"medkit")
	var drone: Quickbar.Slot = _slot(qb, &"scout_drone")
	var bino: Quickbar.Slot = _slot(qb, &"binoculars")
	var dog: Quickbar.Slot = _slot(qb, &"dog_command")
	ok(kit != null and drone != null and bino != null and dog != null, "os 4 espacos existem")
	if kit == null or drone == null or bino == null or dog == null:
		return
	eq(kit.key_label.text, "Q", "tecla do kit")
	eq(drone.key_label.text, "V", "tecla do drone")
	eq(bino.key_label.text, "B", "tecla do binoculo")
	eq(dog.key_label.text, "E", "tecla do cao")
	eq(kit.count_label.text, "x1", "quantidade do kit")
	eq(drone.count_label.text, "x3", "quantidade do drone")
	ok(kit.count_label.visible and drone.count_label.visible, "consumiveis mostram quantidade")
	ok(not bino.count_label.visible, "binoculo nao mostra quantidade")
	ok(not dog.count_label.visible, "cao nao mostra quantidade")
	for slot: Quickbar.Slot in [kit, drone, bino, dog]:
		near(slot.self_modulate.a, 1.0, 0.001, "%s normal (nao apagado)" % slot.slot_id)
		ok(slot.icon.visible or slot.name_label.visible, "%s mostra icone ou nome" % slot.slot_id)
	eq(dog.name_label.text, "Cão", "nome do cao")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_exhausted_slot_dims_and_shows_zero() -> void:
	InputSetup.set_touch_override("off")
	var belt: ItemBelt = _belt([&"scout_drone", &"medkit"], {&"scout_drone": 1})
	var qb: Quickbar = _bar(belt)
	var drone: Quickbar.Slot = _slot(qb, &"scout_drone")
	near(drone.self_modulate.a, 1.0, 0.001, "com 1 drone: normal")
	belt.use_item(&"scout_drone")
	eq(drone.count_label.text, "x0", "contagem atualizada pelo sinal")
	near(drone.self_modulate.a, Quickbar.DIM_ALPHA, 0.001, "painel apagado")
	near(drone.icon.modulate.a, Quickbar.DIM_ALPHA, 0.001, "icone apagado")
	var danger: Color = drone.count_label.get_theme_color("font_color")
	ok(danger.is_equal_approx(Quickbar.COLOR_DANGER), "quantidade 0 em vermelho")
	near(_slot(qb, &"medkit").self_modulate.a, 1.0, 0.001, "o kit continua normal")
	ok(qb.get_slot_ids().has(&"scout_drone"), "o espaco esgotado continua na barra (apertavel)")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_dog_retreat_dims_only_the_dog() -> void:
	InputSetup.set_touch_override("off")
	var qb: Quickbar = _bar(_belt([&"medkit"]))
	qb.set_dog_present(true)
	var dog: Quickbar.Slot = _slot(qb, &"dog_command")
	qb.set_dog_state(Ids.DS_RETREAT)
	near(dog.self_modulate.a, Quickbar.DIM_ALPHA, 0.001, "cao recuando: apagado")
	near(_slot(qb, &"medkit").self_modulate.a, 1.0, 0.001, "kit normal")
	qb.set_dog_state(Ids.DS_FOLLOW)
	near(dog.self_modulate.a, 1.0, 0.001, "cao seguindo: normal")
	qb.set_dog_state(Ids.DS_RETREAT)
	qb.set_dog_present(false)
	qb.set_dog_present(true)
	near(_slot(qb, &"dog_command").self_modulate.a, 1.0, 0.001, "cao novo nao herda o recuo")
	qb.set_dog_state(&"estado_desconhecido")
	near(_slot(qb, &"dog_command").self_modulate.a, 1.0, 0.001, "estado desconhecido: normal")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_busy_progress_and_binoculars_lit() -> void:
	InputSetup.set_touch_override("off")
	var belt: ItemBelt = _belt([&"medkit", &"binoculars", &"scout_drone"], {}, 40.0)
	var qb: Quickbar = _bar(belt)
	var kit: Quickbar.Slot = _slot(qb, &"medkit")
	var bino: Quickbar.Slot = _slot(qb, &"binoculars")
	ok(kit.busy_progress < 0.0, "kit livre: sem setor")
	belt.use_item(&"medkit")
	ok(kit.busy_progress >= 0.0, "kit em uso: setor ativo")
	ok(_slot(qb, &"scout_drone").busy_progress < 0.0, "so o espaco do kit mostra o uso")
	var duration: float = float(Data.get_equipment(&"medkit")["effect"]["use_time_s"])
	belt._process(duration * 0.5)
	qb._process(0.0)
	near(kit.busy_progress, 0.5, 0.01, "setor em 50%")
	belt._process(duration)
	ok(kit.busy_progress < 0.0, "uso terminou: sem setor")
	eq(kit.count_label.text, "x0", "kit gasto")
	ok(not bino.lit, "binoculo desligado: sem borda")
	belt.use_item(&"binoculars")
	ok(bino.lit, "binoculo ligado: borda ambar")
	belt.use_item(&"binoculars")
	ok(not bino.lit, "desligado de novo")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_visibility_rules() -> void:
	InputSetup.set_touch_override("off")
	var empty_bar: Quickbar = _bar(_belt([&"leather_vest", &"extra_ammo"]))
	eq(empty_bar.get_slot_ids().size(), 0, "so passivos: nenhum espaco")
	ok(not empty_bar.visible, "sem espaco: barra invisivel")
	empty_bar.set_dog_present(true)
	ok(empty_bar.visible, "so o cao: barra visivel")
	empty_bar.set_dog_present(false)
	ok(not empty_bar.visible, "sem cao e sem item: invisivel de novo")
	var qb: Quickbar = _bar(_belt([&"medkit"]))
	ok(qb.visible, "teclado/mouse com item: visivel")
	InputSetup.set_touch_override("on")
	ok(not qb.visible, "modo toque: invisivel")
	InputSetup.set_touch_override("off")
	ok(qb.visible, "voltou ao teclado: visivel")
	GameEvents.spectate_changed.emit(1)
	ok(not qb.visible, "espectando: invisivel")
	GameEvents.spectate_changed.emit(-1)
	ok(qb.visible, "fim da espectacao: visivel")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_quickbar_flash() -> void:
	InputSetup.set_touch_override("off")
	var qb: Quickbar = _bar(_belt([&"medkit", &"scout_drone"]))
	var kit: Quickbar.Slot = _slot(qb, &"medkit")
	qb.flash(&"inexistente", true)   # unknown id: nothing happens, no error
	qb.flash(&"dog_command", true)   # no dog now: nothing either
	ok(not qb.is_processing(), "ids inexistentes nao ligam o processamento")
	qb.flash(&"medkit", true)
	ok(kit.flashing, "kit piscando")
	ok(not _slot(qb, &"scout_drone").flashing, "so o kit")
	ok(qb.is_processing(), "processa enquanto pisca")
	qb.flash(&"medkit", false)
	ok(not kit.flashing, "parou de piscar")
	await frames(1)
	ok(not qb.is_processing(), "sem nada piscando ou em uso: nao processa")
	InputSetup.set_touch_override("auto")
	_free_belts()


# --------------------------------------------------------------------------------------------
# TouchControls: item and dog buttons
# --------------------------------------------------------------------------------------------

## TouchControls.bind needs a real Player, so the belt is injected the way bind() would (private fields).
func _touch(belt: ItemBelt) -> TouchControls:
	InputSetup.set_touch_override("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	tc._items = belt
	tc._rebuild_buttons()
	return tc


func _screen(tc: TouchControls) -> Vector2:
	return tc.get_viewport().get_visible_rect().size


func _touch_at(tc: TouchControls, index: int, pos: Vector2, pressed: bool) -> void:
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	tc._input(ev)


func _tap(tc: TouchControls, index: int, pos: Vector2) -> void:
	_touch_at(tc, index, pos, true)
	_touch_at(tc, index, pos, false)


func _block_cura(tc: TouchControls) -> Vector2:
	var b: Dictionary = tc.get_bottom_block()
	return Vector2(float(b["cura_x"]), _screen(tc).y - TouchControls.BLOCK_BOTTOM_PX)


func _block_acc(tc: TouchControls) -> Vector2:
	var b: Dictionary = tc.get_bottom_block()
	return Vector2(float(b["acc_x"]), _screen(tc).y - TouchControls.BLOCK_BOTTOM_PX)


func test_touch_cura_and_accessory_buttons_positions_and_removed_buttons() -> void:
	var tc: TouchControls = _touch(_belt([&"medkit", &"scout_drone"]))
	eq(tc.get_button_center(&"use_medkit"), _block_cura(tc), "kit: botao Cura no bloco de baixo")
	near(tc.get_button_radius(&"use_medkit"), 32.0, 0.001, "Cura de 64 px")
	eq(tc.get_button_center(&"use_scout_drone"), _block_acc(tc), "drone: botao Acessorios no bloco de baixo")
	near(tc.get_button_radius(&"use_scout_drone"), 35.0, 0.001, "Acessorios de 70 px")
	for gone: StringName in [&"use_item", &"item_next", &"weapon_swap"]:
		eq(tc.get_button_center(gone), Vector2.INF, "%s sem botao" % gone)
		eq(tc.get_button_radius(gone), 0.0, "%s sem raio" % gone)
	eq(tc.get_button_center(&"use_corn_bait"), Vector2.INF, "ceva nao trazida: sem botao")
	eq(tc.get_button_center(&"use_binoculars"), Vector2.INF, "binoculo nao trazido: sem botao")
	eq(tc.get_button_center(&"dog_command"), Vector2.INF, "sem cao: sem botao")
	for fixed: StringName in [&"fire", &"fire_left", &"aim", &"reload", &"crouch", &"pause"]:
		ne(tc.get_button_center(fixed), Vector2.INF, "botao fixo %s continua" % fixed)
	var s: Vector2 = _screen(tc)
	eq(tc.get_button_center(&"fire"), Vector2(s.x - 245.0, s.y - 181.0), "Tiro direito: br (245, 181)")
	near(tc.get_button_radius(&"fire"), 60.0, 0.001, "Tiro direito de 120 px")
	eq(tc.get_button_center(&"fire_left"), Vector2(69.0, s.y - 355.0), "Tiro esquerdo: 69 da esquerda, 355 de baixo")
	near(tc.get_button_radius(&"fire_left"), 50.0, 0.001, "Tiro esquerdo de 100 px")
	eq(tc.get_button_center(&"aim"), Vector2(s.x - 108.0, s.y - 342.0), "Mira: br (108, 342)")
	eq(tc.get_button_center(&"reload"), Vector2(s.x - 359.0, s.y - 47.0), "Recarregar: br (359, 47)")
	eq(tc.get_button_center(&"crouch"), Vector2(s.x - 253.0, s.y - 53.0), "Agachar: br (253, 53)")
	near(tc.joystick.rest_center.x, 242.0, 0.001, "joystick: 242 da esquerda")
	near(tc.joystick.rest_center.y, s.y - 220.0, 0.001, "joystick: 220 do fundo")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_no_usable_item_and_no_dog_means_only_the_fixed_buttons() -> void:
	var tc: TouchControls = _touch(_belt([&"leather_vest", &"extra_ammo"]))
	for action: StringName in [&"use_medkit", &"use_corn_bait", &"use_scout_drone", &"use_binoculars", &"dog_command"]:
		eq(tc.get_button_center(action), Vector2.INF, "%s sem botao" % action)
	var keys: Array = tc.get_button_diameters().keys()
	eq(keys.size(), 6, "so os 6 botoes fixos: %s" % str(keys))
	eq(tc.get_accessory_current(), &"", "sem acessorio: nenhum atual")
	ok(not tc.get_probe_buttons().has("accessory_menu"), "sem acessorio: sem seta")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_dog_button_comes_and_goes() -> void:
	var tc: TouchControls = _touch(_belt([&"medkit"]))
	var s: Vector2 = _screen(tc)
	tc.set_dog_present(true)
	eq(tc.get_button_center(&"dog_command"), Vector2(s.x - 235.0, s.y - 346.0), "botao do cao no lugar de sempre")
	near(tc.get_button_radius(&"dog_command"), 38.0, 0.001, "76 px")
	tc.set_dog_present(true)
	eq(tc.get_button_center(&"dog_command"), Vector2(s.x - 235.0, s.y - 346.0), "idempotente")
	tc.set_dog_state(Ids.DS_RETREAT)
	tc.flash_slot(&"dog_command", true)
	tc.flash_slot(&"nada", true)   # unknown ids are harmless
	tc.flash_slot(&"dog_command", false)
	tc.set_dog_present(false)
	eq(tc.get_button_center(&"dog_command"), Vector2.INF, "cao saiu: botao some")
	ne(tc.get_button_center(&"use_medkit"), Vector2.INF, "o botao do kit fica")
	InputSetup.set_touch_override("auto")
	_free_belts()


## Every button of the largest layout (kit, accessories, dog, interact) against each other, the weapon cards and the
## stick, on the three reference screens: hit circles (radius + padding) never touch.
func test_touch_buttons_do_not_overlap_each_other_the_cards_or_the_stick() -> void:
	var hunter: KnifeStubPlayer = KnifeStubPlayer.new()   # F4: the Faca button is part of the largest layout
	var tc: TouchControls = _touch(_belt([&"medkit", &"corn_bait", &"scout_drone", &"binoculars"]))
	tc._player = hunter
	tc.set_dog_present(true)
	tc._revive_on = true
	tc._rebuild_buttons()
	ok(tc.get_button_center(&"knife") != Vector2.INF, "pre-condicao: o botao Faca esta no layout testado")
	var pad: float = TouchControls.HIT_PADDING_PX
	for size_px: Vector2 in [Vector2(1532.0, 720.0), Vector2(1280.0, 720.0), Vector2(1280.0, 960.0)]:
		var block: Dictionary = TouchControls.compute_bottom_block(size_px, 242.0 + 90.0)
		var card_w: float = float(block["card_w"])
		var rects: Array[Rect2] = []
		for i: int in 2:
			rects.append(Rect2(Vector2(float(block["center_x"]) - card_w - 4.0 + float(i) * (card_w + 8.0),
				size_px.y - 8.0 - 28.0 - 6.0 - 55.0), Vector2(card_w, 55.0)))
		var centers: Dictionary = {}
		var reach: Dictionary = {}   # id -> radius + padding
		for def: Dictionary in tc._defs:
			var center: Vector2
			match String(def["from"]):
				"br":
					center = Vector2(size_px.x - float(def["ox"]), size_px.y - float(def["oy"]))
				"bl":
					center = Vector2(float(def["ox"]), size_px.y - float(def["oy"]))
				"cura":
					center = Vector2(float(block["cura_x"]), size_px.y - TouchControls.BLOCK_BOTTOM_PX)
				"acc":
					center = Vector2(float(block["acc_x"]), size_px.y - TouchControls.BLOCK_BOTTOM_PX)
				_:
					center = Vector2(float(def["ox"]), float(def["oy"]))
			centers[def["id"]] = center
			reach[def["id"]] = float(def["d"]) * 0.5 + pad
		var ids: Array = centers.keys()
		for i: int in ids.size():
			for j: int in range(i + 1, ids.size()):
				var gap: float = (centers[ids[i]] as Vector2).distance_to(centers[ids[j]] as Vector2) - float(reach[ids[i]]) - float(reach[ids[j]])
				ok(gap >= -0.01, "%s: %s e %s se sobrepoem (folga %.1f px)" % [size_px, ids[i], ids[j], gap])
		for id: StringName in ids:
			var box: Rect2 = Rect2((centers[id] as Vector2) - Vector2.ONE * float(reach[id]), Vector2.ONE * float(reach[id]) * 2.0)
			for card: Rect2 in rects:
				ok(not box.intersects(card), "%s: o botao %s toca um cartao" % [size_px, id])
			ok(Rect2(Vector2.ZERO, size_px).encloses(box.grow(-pad)), "%s: %s sai da tela" % [size_px, id])
		var stick: Vector2 = Vector2(242.0, size_px.y - 220.0)
		for id: StringName in [&"use_medkit", &"use_corn_bait"]:
			ok((centers[id] as Vector2).distance_to(stick) - float(reach[id]) >= 90.0 * 1.7 - 0.01,
				"%s: %s dentro da area ativa do joystick" % [size_px, id])
		ok(card_w >= TouchControls.CARD_W_MIN_PX - 0.01 and card_w <= TouchControls.CARD_W_MAX_PX + 0.01,
			"%s: largura do cartao %.1f" % [size_px, card_w])
		ok(float(block["acc_x"]) + 35.0 + 2.0 * pad <= size_px.x - 359.0 - 32.0 + 0.01, "%s: Acessorios antes do Recarregar" % size_px)
	_drop_hunter(tc, hunter)
	InputSetup.set_touch_override("auto")
	_free_belts()


# --------------------------------------------------------------------------------------------
# TouchControls: the Faca button (docs/plano_faca_mochila_folego.md 2.7; F4)
# --------------------------------------------------------------------------------------------

## A hunter the test steers: the knife level, the knife in the hand, a revive target (the Levantar button) and the fall
## are plain fields.
## Never added to the tree (no _ready); TouchControls only reads it through the Player getters.
class KnifeStubPlayer extends Player:
	var knife_level: int = 2
	var revive_target: int = -1
	var downed: bool = false
	var knife_equipped: bool = false   # 0.9.9: the knife in the hand lights the Faca button

	func get_knife_level() -> int:
		return knife_level

	func is_knife_equipped() -> bool:
		return knife_equipped

	func get_revive_target_slot() -> int:
		return revive_target

	func is_downed() -> bool:
		return downed


## A TouchControls with the belt injected and `player` bound as its hunter (private fields, the way bind() would).
func _touch_with_hunter(belt: ItemBelt, player: Player) -> TouchControls:
	var tc: TouchControls = _touch(belt)
	tc._player = player
	tc._rebuild_buttons()
	return tc


## Detaches the stub from a TouchControls before it is freed (the controls keep processing until the frame ends).
func _drop_hunter(tc: TouchControls, player: Player) -> void:
	tc._player = null
	tc._rebuild_buttons()
	player.free()


func test_touch_knife_button_exists_only_with_a_knife_and_a_standing_hunter() -> void:
	var belt: ItemBelt = _belt([&"medkit"])
	var tc: TouchControls = _touch(belt)
	eq(tc.get_button_center(TouchControls.KNIFE_ACTION), Vector2.INF, "sem caçador ligado: sem botao Faca")
	eq(tc.get_button_radius(TouchControls.KNIFE_ACTION), 0.0, "sem caçador ligado: raio 0")
	var hunter: KnifeStubPlayer = KnifeStubPlayer.new()
	tc._player = hunter
	tc._rebuild_buttons()
	var s: Vector2 = _screen(tc)
	eq(tc.get_button_center(&"knife"), Vector2(s.x - 100.0, s.y - 190.0), "Faca: br (100, 190), sem ajuste")
	near(tc.get_button_radius(&"knife"), 34.0, 0.001, "Faca de 68 px")
	eq(tc.get_button_label(&"knife"), "Faca", "texto do botao")
	ok(tc.get_button_diameters().has(&"knife"), "o botao entra em get_button_diameters")
	# a knife of level 0 = no knife in the data: no button
	hunter.knife_level = 0
	tc._rebuild_buttons()
	eq(tc.get_button_center(&"knife"), Vector2.INF, "faca nivel 0 (sem faca nos dados): sem botao")
	hunter.knife_level = 4
	tc._rebuild_buttons()
	ne(tc.get_button_center(&"knife"), Vector2.INF, "faca nivel 4: com botao")
	# a fallen hunter keeps only Pause (like Reload)
	hunter.downed = true
	tc._sync_revive_state()
	eq(tc.get_button_center(&"knife"), Vector2.INF, "caido: o botao Faca some")
	ne(tc.get_button_center(&"pause"), Vector2.INF, "caido: o Pause fica")
	hunter.downed = false
	tc._sync_revive_state()
	ne(tc.get_button_center(&"knife"), Vector2.INF, "levantado: o botao Faca volta")
	_drop_hunter(tc, hunter)
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_knife_button_shows_the_equipped_state() -> void:
	## 0.9.9: the Faca button is a toggle of the knife in the hand; it is drawn "on" while the knife is equipped.
	var tc: TouchControls = _touch_with_hunter(_belt([&"medkit"]), KnifeStubPlayer.new())
	var hunter: KnifeStubPlayer = tc._player as KnifeStubPlayer
	ok(not tc.is_button_on(&"knife"), "faca na cintura: o botao Faca nao esta aceso")
	hunter.knife_equipped = true
	ok(tc.is_button_on(&"knife"), "faca na mao: o botao Faca fica aceso")
	hunter.knife_equipped = false
	ok(not tc.is_button_on(&"knife"), "faca guardada: o botao apaga")
	ok(not tc.is_button_on(&"aim"), "a Mira nao acende por causa da faca")
	# the other buttons are not lit by the knife
	hunter.knife_equipped = true
	ok(not tc.is_button_on(&"use_medkit"), "o kit nao acende com a faca na mao")
	ok(not tc.is_button_on(&"fire"), "o Tiro nao acende com a faca na mao")
	# a button that does not exist is never on, even with the knife out
	hunter.knife_level = 0
	tc._rebuild_buttons()
	ok(not tc.is_button_on(&"knife"), "sem faca nos dados: nao ha botao, nao ha estado aceso")
	ok(not tc.is_button_on(&"nada"), "id desconhecido: falso")
	_drop_hunter(tc, hunter)
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_aim_button_does_nothing_with_the_knife_in_the_hand() -> void:
	## 0.9.9: no aim with the knife; the Mira toggle neither presses `aim` nor flips, and a toggle left on is dropped.
	var tc: TouchControls = _touch_with_hunter(_belt([&"medkit"]), KnifeStubPlayer.new())
	var hunter: KnifeStubPlayer = tc._player as KnifeStubPlayer
	var c: Vector2 = tc.get_button_center(&"aim")
	Input.action_release(&"aim")
	hunter.knife_equipped = true
	_tap(tc, 0, c)
	ok(not Input.is_action_pressed(&"aim"), "faca na mao: tocar na Mira nao aperta aim")
	ok(not tc.is_button_on(&"aim"), "faca na mao: a Mira nao liga")
	hunter.knife_equipped = false
	_tap(tc, 0, c)
	ok(Input.is_action_pressed(&"aim"), "faca guardada: a Mira volta a ligar")
	ok(tc.is_button_on(&"aim"), "faca guardada: a Mira fica ligada")
	hunter.knife_equipped = true
	tc._process(0.016)
	ok(not Input.is_action_pressed(&"aim"), "pegar a faca com a Mira ligada solta aim")
	ok(not tc.is_button_on(&"aim"), "pegar a faca desliga a Mira")
	Input.action_release(&"aim")
	_drop_hunter(tc, hunter)
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_knife_button_press_holds_the_knife_action() -> void:
	var tc: TouchControls = _touch_with_hunter(_belt([&"medkit"]), KnifeStubPlayer.new())
	var hunter: Player = tc._player
	var c: Vector2 = tc.get_button_center(&"knife")
	Input.action_release(&"knife")
	_touch_at(tc, 0, c, true)
	ok(Input.is_action_pressed(&"knife"), "tocar no botao aperta a acao knife")
	_touch_at(tc, 0, c, false)
	ok(not Input.is_action_pressed(&"knife"), "soltar o dedo solta a acao knife")
	# a tap anywhere else never presses it
	var free_spot: Vector2 = Vector2(c.x - 300.0, c.y)
	_tap(tc, 1, free_spot)
	ok(not Input.is_action_pressed(&"knife"), "um toque longe do botao nao aperta knife")
	_drop_hunter(tc, hunter)
	InputSetup.set_touch_override("auto")
	_free_belts()


## The Faca button in the largest layout (dog, Levantar, kit, accessories, all 4 accessory rows open) against every other
## button, the weapon cards and the screen edges, on the three reference screens. Same general rule as the F3 test
## (`>= -0.01`), no exception for any pair.
func test_touch_knife_button_does_not_overlap_anything_on_the_three_screens() -> void:
	var sizes: Array[Vector2i] = [Vector2i(1532, 720), Vector2i(1280, 720), Vector2i(1280, 960)]
	var expected: Dictionary = {Vector2i(1532, 720): Vector2(1432.0, 530.0), Vector2i(1280, 720): Vector2(1180.0, 530.0),
		Vector2i(1280, 960): Vector2(1180.0, 770.0)}
	await frames(2)   # nodes freed by the previous test still listen to the window size until the end of the frame
	for win_size: Vector2i in sizes:
		_set_window(win_size)
		await frames(2)
		var hunter: KnifeStubPlayer = KnifeStubPlayer.new()
		hunter.revive_target = 0   # the Levantar button is on
		var tc: TouchControls = _touch(_belt([&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink"], {&"energy_drink": 3}))
		tc._player = hunter
		tc.set_dog_present(true)
		tc._sync_revive_state()
		await frames(2)
		var size_px: Vector2 = _screen(tc)
		var label: String = "%dx%d" % [win_size.x, win_size.y]
		near(size_px.x, float(win_size.x), 0.5, "%s: pre-condicao, largura da viewport" % label)
		near(size_px.y, float(win_size.y), 0.5, "%s: pre-condicao, altura da viewport" % label)
		var knife_at: Vector2 = tc.get_button_center(&"knife")
		eq(knife_at, expected[win_size], "%s: centro do botao Faca" % label)
		near(tc.get_button_radius(&"knife"), 34.0, 0.001, "%s: raio do botao Faca" % label)
		ok(tc.get_probe_buttons().has("interact") and tc.get_probe_buttons().has("dog_command"),
			"%s: pre-condicao, Levantar e Cao presentes (pior caso)" % label)
		var arrow: Vector3 = tc.get_probe_buttons()["accessory_menu"]
		_tap(tc, 1, Vector2(arrow.x, arrow.y))
		ok(tc.is_accessory_menu_open(), "%s: lista aberta" % label)
		var probe: Dictionary = tc.get_probe_buttons()
		var rows: Array[Rect2] = []
		for key: Variant in probe:
			if String(key).begins_with("accessory_item_"):
				rows.append(_row_rect(probe[key] as Vector3))
		eq(rows.size(), 4, "%s: 4 linhas na lista" % label)
		ok(probe.has("knife"), "%s: o botao Faca esta no probe" % label)
		# every button against every other one (hit circles = radius + padding), the same rule as the general test
		var pad: float = TouchControls.HIT_PADDING_PX
		var ids: Array = []
		for key: Variant in probe:
			var pname: String = String(key)
			if pname.begins_with("accessory_item_") or pname.begins_with("weapon_card_") or pname == String(TouchControls.MENU_ID):
				continue
			ids.append(key)
		for i: int in ids.size():
			for j: int in range(i + 1, ids.size()):
				var a: Vector3 = probe[ids[i]] as Vector3
				var b: Vector3 = probe[ids[j]] as Vector3
				var gap: float = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - (a.z + pad) - (b.z + pad)
				ok(gap >= -0.01, "%s: %s e %s se sobrepoem (folga %.1f px)" % [label, ids[i], ids[j], gap])
		# the knife button against the open list, the arrow and the weapon cards
		var knife_box: Rect2 = Rect2(knife_at - Vector2.ONE * (34.0 + pad), Vector2.ONE * (34.0 + pad) * 2.0)
		for i: int in rows.size():
			var gap_row: float = rows[i].get_center().distance_to(knife_at) - rows[i].size.x * 0.5 - 34.0
			ok(gap_row >= -0.01, "%s: a linha %d toca o botao Faca (folga %.1f px)" % [label, i, gap_row])
		var block: Dictionary = tc.get_bottom_block()
		var card_w: float = float(block["card_w"])
		for i: int in 2:
			var card: Rect2 = Rect2(Vector2(float(block["center_x"]) - card_w - 4.0 + float(i) * (card_w + 8.0),
				size_px.y - 8.0 - 28.0 - 6.0 - 55.0), Vector2(card_w, 55.0))
			ok(not knife_box.intersects(card), "%s: o botao Faca toca o cartao de arma %d" % [label, i])
		ok(Rect2(Vector2.ZERO, size_px).encloses(knife_box.grow(-pad)), "%s: o botao Faca sai da tela" % label)
		_drop_hunter(tc, hunter)
		_end_hud_test()
		_free_belts()


func test_touch_bottom_block_matches_the_mockup_at_1532() -> void:
	var block: Dictionary = TouchControls.compute_bottom_block(Vector2(1532.0, 720.0), 332.0)
	near(float(block["card_w"]), 167.0, 0.001, "1532: cartoes de 167")
	near(float(block["center_x"]), 766.0, 0.001, "1532: centro da tela")
	near(float(block["cura_x"]) - 766.0, -277.0, 0.5, "Cura a 277 px a esquerda do centro")
	near(float(block["acc_x"]) - 766.0, 216.0, 0.5, "Acessorios a 216 px a direita do centro (214 na foto, +2 de folga)")
	var narrow: Dictionary = TouchControls.compute_bottom_block(Vector2(1280.0, 720.0), 332.0)
	ok(float(narrow["card_w"]) < 167.0 and float(narrow["card_w"]) >= 130.0, "1280: cartoes mais estreitos (%.1f)" % float(narrow["card_w"]))


func test_touch_two_fire_buttons_share_the_action_by_finger_count() -> void:
	var tc: TouchControls = _touch(_belt([&"medkit"]))
	var right: Vector2 = tc.get_button_center(&"fire")
	var left: Vector2 = tc.get_button_center(&"fire_left")
	ok(not Input.is_action_pressed(&"fire"), "pre-condicao: fire solto")
	_touch_at(tc, 1, right, true)
	ok(Input.is_action_pressed(&"fire"), "Tiro direito aperta fire")
	_touch_at(tc, 2, left, true)
	ok(Input.is_action_pressed(&"fire"), "os dois dedos: fire apertado")
	_touch_at(tc, 1, right, false)
	ok(Input.is_action_pressed(&"fire"), "soltar um nao solta fire enquanto o outro segue")
	_touch_at(tc, 2, left, false)
	ok(not Input.is_action_pressed(&"fire"), "soltar o ultimo solta fire")
	_touch_at(tc, 3, left, true)
	ok(Input.is_action_pressed(&"fire"), "Tiro esquerdo sozinho aperta fire")
	_touch_at(tc, 3, left, false)
	ok(not Input.is_action_pressed(&"fire"), "soltou")
	ok(TouchControls.LOOK_BUTTONS.has(&"fire") and TouchControls.LOOK_BUTTONS.has(&"fire_left"), "os dois Tiros giram a camera ao arrastar")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_accessory_button_default_switch_and_list() -> void:
	var belt: ItemBelt = _belt([&"medkit", &"corn_bait", &"scout_drone", &"binoculars"], {&"corn_bait": 0})
	var tc: TouchControls = _touch(belt)
	eq(tc.get_accessory_ids(), [&"corn_bait", &"scout_drone", &"binoculars"] as Array[StringName], "ordem de ITEM_ACTIONS, sem o kit")
	eq(tc.get_accessory_current(), &"scout_drone", "padrao: o primeiro com contagem > 0 (a ceva esta zerada)")
	ne(tc.get_button_center(&"use_scout_drone"), Vector2.INF, "o botao usa a acao do acessorio atual")
	eq(tc.get_button_center(&"use_corn_bait"), Vector2.INF, "a ceva nao tem botao proprio")
	var probe: Dictionary = tc.get_probe_buttons()
	ok(probe.has("accessory_menu"), "3 acessorios: a seta aparece")
	ok(probe.has("use_scout_drone") and probe.has("fire_left"), "probe traz o acessorio atual e o Tiro esquerdo")
	var arrow: Vector3 = probe["accessory_menu"]
	_tap(tc, 1, Vector2(arrow.x, arrow.y))
	ok(tc.is_accessory_menu_open(), "tocar na seta abre a lista")
	var rows: Dictionary = tc.get_probe_buttons()
	var acc_y: float = tc.get_button_center(&"use_scout_drone").y
	for id: StringName in [&"corn_bait", &"scout_drone", &"binoculars"]:
		var row: Vector3 = rows["accessory_item_%s" % id]
		ok(row.y < acc_y - 70.0, "a lista sobe: %s acima do botao" % id)
		near(row.z, 30.0, 0.001, "linha de 60 px")
	var count_before: int = belt.get_count(&"scout_drone")
	var bino: Vector3 = rows["accessory_item_binoculars"]
	_tap(tc, 1, Vector2(bino.x, bino.y))
	ok(not tc.is_accessory_menu_open(), "escolher um item fecha a lista")
	eq(tc.get_accessory_current(), &"binoculars", "o item escolhido virou o atual")
	ok(not belt.is_binoculars_active(), "escolher nao usa: o binoculo continua apagado")
	eq(belt.get_count(&"scout_drone"), count_before, "escolher nao gasta o drone")
	ne(tc.get_button_center(&"use_binoculars"), Vector2.INF, "o botao agora aperta use_binoculars")
	eq(tc.get_button_center(&"use_scout_drone"), Vector2.INF, "o botao do drone sumiu (e o mesmo botao)")
	arrow = tc.get_probe_buttons()["accessory_menu"]
	_tap(tc, 1, Vector2(arrow.x, arrow.y))
	ok(tc.is_accessory_menu_open(), "reabre")
	_tap(tc, 1, Vector2(700.0, 200.0))
	ok(not tc.is_accessory_menu_open(), "tocar fora fecha a lista")
	var main: Vector2 = tc.get_button_center(&"use_binoculars")
	_touch_at(tc, 2, main, true)
	ok(Input.is_action_pressed(&"use_binoculars"), "tocar no botao aperta a acao do acessorio atual")
	_touch_at(tc, 2, main, false)
	ok(not Input.is_action_pressed(&"use_binoculars"), "soltar libera")
	InputSetup.set_touch_override("auto")
	_free_belts()


## The energy drink is the 4th accessory (the last): the open list has 4 rows, in ITEM_ACTIONS order, climbing from the tab.
func test_touch_accessory_list_has_four_rows_with_the_energy_drink_last() -> void:
	var belt: ItemBelt = _belt([&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink"], {&"energy_drink": 2})
	var tc: TouchControls = _touch(belt)
	var want: Array[StringName] = [&"corn_bait", &"scout_drone", &"binoculars", &"energy_drink"]
	eq(tc.get_accessory_ids(), want, "4 acessorios (sem o kit), o energetico por ultimo")
	eq(tc.get_accessory_current(), &"corn_bait", "padrao: o primeiro com contagem > 0")
	var arrow: Vector3 = tc.get_probe_buttons()["accessory_menu"]
	_tap(tc, 1, Vector2(arrow.x, arrow.y))
	ok(tc.is_accessory_menu_open(), "tocar na seta abre a lista")
	var rows: Dictionary = tc.get_probe_buttons()
	var ys: Array[float] = []
	for id: StringName in want:
		ok(rows.has("accessory_item_%s" % id), "linha de %s na lista" % id)
		if rows.has("accessory_item_%s" % id):
			ys.append((rows["accessory_item_%s" % id] as Vector3).y)
	var row_count: int = 0
	for key: Variant in rows:
		if String(key).begins_with("accessory_item_"):
			row_count += 1
	eq(row_count, 4, "a lista tem exatamente 4 linhas")
	eq(ys.size(), 4, "pre-condicao: 4 posicoes")
	if ys.size() == 4:
		ok(ys[0] > ys[1] and ys[1] > ys[2] and ys[2] > ys[3], "a lista sobe: o energetico fica na linha de cima")
	# choosing the drink makes it the current accessory without drinking it
	var row: Vector3 = rows["accessory_item_energy_drink"]
	_tap(tc, 1, Vector2(row.x, row.y))
	eq(tc.get_accessory_current(), &"energy_drink", "o energetico virou o atual")
	eq(belt.get_count(&"energy_drink"), 2, "escolher nao bebe")
	ne(tc.get_button_center(&"use_energy_drink"), Vector2.INF, "o botao agora aperta use_energy_drink")
	InputSetup.set_touch_override("auto")
	_free_belts()


## select_accessory (F3): the HUD puts the drink on the main button without using it; false for an item not carried.
func test_touch_select_accessory_picks_the_drink_and_refuses_what_is_not_carried() -> void:
	var tc: TouchControls = _touch(_belt([&"medkit", &"corn_bait", &"energy_drink"], {&"energy_drink": 1}))
	eq(tc.get_accessory_current(), &"corn_bait", "padrao: a ceva")
	var arrow: Vector3 = tc.get_probe_buttons()["accessory_menu"]
	_tap(tc, 1, Vector2(arrow.x, arrow.y))
	ok(tc.is_accessory_menu_open(), "pre-condicao: lista aberta")
	ok(tc.select_accessory(&"energy_drink"), "select_accessory devolve true")
	eq(tc.get_accessory_current(), &"energy_drink", "o energetico e o atual")
	ok(not tc.is_accessory_menu_open(), "a lista fecha")
	ok(not Input.is_action_pressed(&"use_energy_drink"), "selecionar nao aperta a acao")
	ok(not tc.select_accessory(&"scout_drone"), "item nao trazido: false")
	ok(not tc.select_accessory(&"medkit"), "o kit nao e acessorio: false")
	ok(not tc.select_accessory(&""), "id vazio: false")
	eq(tc.get_accessory_current(), &"energy_drink", "as recusas nao mudam o atual")
	InputSetup.set_touch_override("auto")
	_free_belts()


func _row_rect(row: Vector3) -> Rect2:
	return Rect2(Vector2(row.x, row.y) - Vector2.ONE * row.z, Vector2.ONE * row.z * 2.0)


## The open list of 4 rows (5 usable items, the kit has its own button) against the other buttons, the weapon cards and
## the screen edges on the three reference screens.
func test_touch_accessory_list_of_four_rows_does_not_overlap_anything_on_the_three_screens() -> void:
	var sizes: Array[Vector2i] = [Vector2i(1532, 720), Vector2i(1280, 720), Vector2i(1280, 960)]
	var acc_actions: Array[String] = ["use_corn_bait", "use_scout_drone", "use_binoculars", "use_energy_drink"]
	await frames(2)   # nodes freed by the previous test still listen to the window size until the end of the frame
	for win_size: Vector2i in sizes:
		_set_window(win_size)
		await frames(2)
		var tc: TouchControls = _touch(_belt([&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink"], {&"energy_drink": 3}))
		tc.set_dog_present(true)
		tc._revive_on = true
		tc._rebuild_buttons()
		await frames(2)
		var size_px: Vector2 = _screen(tc)
		var label: String = "%dx%d" % [win_size.x, win_size.y]
		near(size_px.x, float(win_size.x), 0.5, "%s: pre-condicao, largura da viewport" % label)
		var arrow: Vector3 = tc.get_probe_buttons()["accessory_menu"]
		_tap(tc, 1, Vector2(arrow.x, arrow.y))
		ok(tc.is_accessory_menu_open(), "%s: lista aberta" % label)
		var probe: Dictionary = tc.get_probe_buttons()
		var rows: Array[Rect2] = []
		for key: Variant in probe:
			if String(key).begins_with("accessory_item_"):
				rows.append(_row_rect(probe[key] as Vector3))
		eq(rows.size(), 4, "%s: 4 linhas" % label)
		ok(probe.has("interact") and probe.has("dog_command"), "%s: interact e cao estao no probe (a regra geral os confere)" % label)
		var screen_rect: Rect2 = Rect2(Vector2.ZERO, size_px)
		var cards: Array[Rect2] = []
		var block: Dictionary = tc.get_bottom_block()
		var card_w: float = float(block["card_w"])
		for i: int in 2:
			cards.append(Rect2(Vector2(float(block["center_x"]) - card_w - 4.0 + float(i) * (card_w + 8.0),
				size_px.y - 8.0 - 28.0 - 6.0 - 55.0), Vector2(card_w, 55.0)))
		for i: int in rows.size():
			ok(screen_rect.encloses(rows[i]), "%s: linha %d dentro da tela (%s)" % [label, i, rows[i]])
			for j: int in range(i + 1, rows.size()):
				ok(not rows[i].intersects(rows[j]), "%s: linhas %d e %d se sobrepoem" % [label, i, j])
			for card: Rect2 in cards:
				ok(not rows[i].intersects(card), "%s: linha %d toca um cartao de arma" % [label, i])
			for bid: Variant in probe:
				var bname: String = String(bid)
				# rows, cards and the tab are checked elsewhere; the main Accessories button is the list's own origin
				if bname.begins_with("accessory_item_") or bname.begins_with("weapon_card_") or bname == String(TouchControls.MENU_ID) \
						or acc_actions.has(bname):
					continue
				var b: Vector3 = probe[bid] as Vector3
				var gap: float = rows[i].get_center().distance_to(Vector2(b.x, b.y)) - rows[i].size.x * 0.5 - b.z
				ok(gap >= -0.01, "%s: a linha %d toca o botao %s (folga %.1f px)" % [label, i, bname, gap])
		_end_hud_test()
		_free_belts()


func test_touch_accessory_switches_by_itself_when_the_current_runs_out() -> void:
	var belt: ItemBelt = _belt([&"corn_bait", &"scout_drone"], {&"corn_bait": 1, &"scout_drone": 2})
	var tc: TouchControls = _touch(belt)
	eq(tc.get_accessory_current(), &"corn_bait", "comeca na ceva")
	belt._counts[&"corn_bait"] = 0
	tc._process(0.016)
	eq(tc.get_accessory_current(), &"scout_drone", "a ceva acabou: troca sozinha para o drone")
	tc._select_accessory(&"corn_bait")
	tc._process(0.016)
	eq(tc.get_accessory_current(), &"corn_bait", "escolhida a mao: nao volta sozinha")
	var single: TouchControls = _touch(_belt([&"scout_drone"]))
	ok(not single.get_probe_buttons().has("accessory_menu"), "um acessorio so: sem seta")
	ne(single.get_button_center(&"use_scout_drone"), Vector2.INF, "mas o botao existe")
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_accessory_flash_goes_to_the_button_or_the_tab() -> void:
	var tc: TouchControls = _touch(_belt([&"medkit", &"corn_bait", &"scout_drone"]))
	eq(tc.get_accessory_current(), &"corn_bait", "atual: a ceva")
	tc.flash_slot(&"scout_drone", true)
	ok(tc._other_accessory_flashing(), "drone nao e o atual: a seta pisca")
	tc.flash_slot(&"scout_drone", false)
	ok(not tc._other_accessory_flashing(), "apagou")
	tc.flash_slot(&"corn_bait", true)
	ok(not tc._other_accessory_flashing(), "ceva e o atual: pisca o botao, nao a seta")
	tc.flash_slot(&"corn_bait", false)
	InputSetup.set_touch_override("auto")
	_free_belts()


func test_touch_weapon_cards_tap_selects_with_button_priority() -> void:
	var tc: TouchControls = _touch(_belt([&"medkit"]))
	var rects: Array[Rect2] = [Rect2(600.0, 600.0, 160.0, 55.0), Rect2(768.0, 600.0, 160.0, 55.0)]
	tc.set_weapon_card_rects(rects, [&"", &"weapon_2"] as Array[StringName])
	var probe: Dictionary = tc.get_probe_buttons()
	ok(probe.has("weapon_card_1") and probe.has("weapon_card_2"), "o probe traz os dois cartoes")
	_touch_at(tc, 1, Vector2(850.0, 630.0), true)
	ok(Input.is_action_pressed(&"weapon_2"), "tocar no cartao da outra arma aperta weapon_2")
	_touch_at(tc, 1, Vector2(850.0, 630.0), false)
	ok(not Input.is_action_pressed(&"weapon_2"), "soltar libera")
	_touch_at(tc, 1, Vector2(680.0, 630.0), true)
	ok(not Input.is_action_pressed(&"weapon_1") and not tc.look_pad.is_active(), "tocar no cartao da arma na mao nao faz nada (e nao vira olhar)")
	_touch_at(tc, 1, Vector2(680.0, 630.0), false)
	var button: Vector2 = tc.get_button_center(&"use_medkit")
	tc.set_weapon_card_rects([Rect2(button - Vector2(80.0, 30.0), Vector2(160.0, 60.0))] as Array[Rect2])
	_touch_at(tc, 2, button, true)
	ok(Input.is_action_pressed(&"use_medkit") and not Input.is_action_pressed(&"weapon_1"), "o botao tem prioridade sobre o cartao")
	_touch_at(tc, 2, button, false)
	tc.set_weapon_card_rects([] as Array[Rect2])
	eq(tc.get_weapon_card_rects().size(), 0, "sem cartoes")
	InputSetup.set_touch_override("auto")
	_free_belts()


# --------------------------------------------------------------------------------------------
# Backpack (F1): the biggest item bar the HUD can show (docs/plano_faca_mochila_folego.md 3, "F1")
# --------------------------------------------------------------------------------------------

## Just enough world for the Player and the Hud, with a dog (same idea as the one of test_weapon_health_hud).
class DogWorld extends HuntWorld:
	var player: PlayerBase = null

	func get_map_rect() -> Rect2:
		return Rect2(-128.0, -128.0, 256.0, 256.0)

	func get_player() -> PlayerBase:
		return player

	func has_dog() -> bool:
		return true


var _hud_world: DogWorld = null
var _saved_window_size: Vector2i = Vector2i.ZERO


## The headless window is 64x64 (a 1280x1280 viewport with the project stretch): the layout tests need a real shape.
func _set_window(size: Vector2i) -> void:
	var win: Window = host.get_window()
	if _saved_window_size == Vector2i.ZERO:
		_saved_window_size = win.size
	win.size = size


## Frees the world (and its Hud, so nothing stays connected to GameEvents) and restores the window and the input mode.
func _end_hud_test() -> void:
	if _hud_world != null and is_instance_valid(_hud_world):
		if _hud_world.get_parent() != null:
			_hud_world.get_parent().remove_child(_hud_world)
		_hud_world.free()
	_hud_world = null
	if _saved_window_size != Vector2i.ZERO:
		host.get_window().size = _saved_window_size
		_saved_window_size = Vector2i.ZERO
	InputSetup.set_touch_override("auto")


## A real Player (and its Hud) carrying `item_ids`, with the dog slot on. Returns the Hud (null + a failure otherwise).
func _spawn_hud_with_dog(item_ids: Array[StringName]) -> Hud:
	InputSetup.set_touch_override("off")
	fresh_profile()
	_hud_world = DogWorld.new()
	track(_hud_world)
	var player: Player = (load(ScenePaths.PLAYER) as PackedScene).instantiate() as Player
	_hud_world.player = player
	_hud_world.add_child(player)
	player.global_position = Vector3.ZERO
	var req: HuntRequest = HuntRequest.make_debug()
	req.weapon_ids = Data.get_weapon_ids()   # the biggest weapon frame (5 weapons)
	req.item_ids = item_ids
	req.item_counts = {&"medkit": 1, &"corn_bait": 2, &"scout_drone": 3, &"energy_drink": 2}
	player.setup(req, _hud_world)
	for child: Node in player.get_children():
		if child is Hud:
			await frames(4)
			return child as Hud
	fail("o Player nao criou o Hud")
	return null


func _rect(c: Control) -> Rect2:
	return Rect2(c.global_position, c.size)


## The five-slot bar (4 usable items + the dog) against the weapon frame, the kill message and the health strip.
func _check_five_slot_bar(hud: Hud, label: String) -> void:
	_check_item_bar(hud, label, 5)


## The item bar of `slots` spaces (usable items + the dog) against the weapon frame, the kill message and the health strip.
func _check_item_bar(hud: Hud, label: String, slots: int) -> void:
	var qb: Quickbar = hud.get("_quickbar") as Quickbar
	var frame: Control = hud.get("_weapon_frame") as Control
	var kill: Control = hud.get("_kill_msg") as Control
	var strip: Control = hud.get("_health") as Control
	var root: Control = hud.get("_root") as Control
	eq(qb.get_slot_ids().size(), slots, "%s: itens usaveis + cao = %d espacos" % [label, slots])
	eq(qb.get_slot_ids()[slots - 1], Quickbar.DOG_SLOT, "%s: o cao e o ultimo" % label)
	ok(qb.visible, "%s: barra visivel" % label)
	var qb_rect: Rect2 = _rect(qb)
	var frame_rect: Rect2 = _rect(frame)
	var kill_rect: Rect2 = _rect(kill)
	var strip_rect: Rect2 = _rect(strip)
	var root_rect: Rect2 = Rect2(Vector2.ZERO, root.size)
	var width: float = float(slots) * Quickbar.SLOT_SIZE_PX + float(slots - 1) * float(Quickbar.SEPARATION_PX)
	near(qb_rect.size.x, width, 1.0, "%s: largura da barra com %d espacos (%s)" % [label, slots, qb_rect])
	near(qb_rect.size.y, Quickbar.SLOT_SIZE_PX, 1.0, "%s: altura de um espaco" % label)
	near(qb_rect.get_center().x, root.size.x * 0.5, 1.0, "%s: barra centrada (%s)" % [label, qb_rect])
	ok(root_rect.encloses(qb_rect), "%s: barra dentro da tela (%s em %s)" % [label, qb_rect, root_rect])
	ok(not qb_rect.intersects(frame_rect), "%s: barra nao encosta no WeaponFrame (barra %s, quadro %s)" % [label, qb_rect, frame_rect])
	ok(not qb_rect.intersects(kill_rect), "%s: barra nao encosta na mensagem de abate (barra %s, mensagem %s)" % [label, qb_rect, kill_rect])
	ok(not qb_rect.intersects(strip_rect), "%s: barra nao encosta na faixa de vida (barra %s, faixa %s)" % [label, qb_rect, strip_rect])
	ok(qb_rect.end.y <= strip_rect.position.y - Hud.BOTTOM_STACK_GAP_PX + 0.5, "%s: barra acima da faixa, com folga" % label)


func test_quickbar_with_four_usable_items_and_dog_clears_weapon_frame_and_kill_message() -> void:
	# Five slots (4 usable items + the dog): the bar a hunter without the energy drink gets (F3 adds the sixth slot).
	_set_window(Vector2i(1280, 720))
	await frames(2)
	var hud: Hud = await _spawn_hud_with_dog([&"medkit", &"corn_bait", &"scout_drone", &"binoculars"] as Array[StringName])
	if hud == null:
		_end_hud_test()
		return
	var root: Control = hud.get("_root") as Control
	near(root.size.x, 1280.0, 0.5, "pre-condicao: largura 1280 (%s)" % root.size)
	near(root.size.y, 720.0, 0.5, "pre-condicao: altura 720")
	_check_five_slot_bar(hud, "1280x720")
	# with a reload on the panel the weapon frame is at its tallest
	(hud.get("_weapon_panel") as WeaponPanel).set_reload(true, 0.5)
	await frames(2)
	_check_five_slot_bar(hud, "1280x720 recarregando")
	_end_hud_test()


func test_quickbar_five_slots_on_a_wide_phone_screen() -> void:
	# 2340x1080 landscape: the project stretch (expand) makes it 1560x720; the weapon frame hugs the right edge.
	_set_window(Vector2i(2340, 1080))
	await frames(2)
	var hud: Hud = await _spawn_hud_with_dog([&"medkit", &"corn_bait", &"scout_drone", &"binoculars"] as Array[StringName])
	if hud == null:
		_end_hud_test()
		return
	_check_five_slot_bar(hud, "2340x1080")
	_end_hud_test()


func test_quickbar_never_grows_past_four_items_plus_dog_with_a_six_item_backpack() -> void:
	# Backpack level 4 carries 6 items, but only 4 are usable by key here (the other two are passive): the bar keeps 5 slots.
	_set_window(Vector2i(1280, 720))
	await frames(2)
	var six: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"leather_vest", &"extra_ammo"]
	var hud: Hud = await _spawn_hud_with_dog(six)
	if hud == null:
		_end_hud_test()
		return
	_check_five_slot_bar(hud, "mochila 6 itens")
	_end_hud_test()


## F3: the widest bar there is, 5 usable items (the energy drink closes the list) + the dog = 6 spaces, on the three
## reference screens (1532x720 and 1280x720 landscape phones, 1280x960 tablet), also with a reload on the weapon panel.
func test_quickbar_with_the_energy_drink_and_dog_has_six_slots_and_overlaps_nothing_on_the_three_screens() -> void:
	var five: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink"]
	var sizes: Array[Vector2i] = [Vector2i(1532, 720), Vector2i(1280, 720), Vector2i(1280, 960)]
	await frames(2)   # nodes freed by the previous test still listen to the window size until the end of the frame
	for win_size: Vector2i in sizes:
		var label: String = "%dx%d" % [win_size.x, win_size.y]
		_set_window(win_size)
		await frames(2)
		var hud: Hud = await _spawn_hud_with_dog(five)
		if hud == null:
			_end_hud_test()
			return
		var root: Control = hud.get("_root") as Control
		near(root.size.x, float(win_size.x), 0.5, "%s: pre-condicao, largura (%s)" % [label, root.size])
		near(root.size.y, float(win_size.y), 0.5, "%s: pre-condicao, altura" % label)
		var qb: Quickbar = hud.get("_quickbar") as Quickbar
		eq(qb.get_slot_ids(), [&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"energy_drink", &"dog_command"] as Array[StringName],
			"%s: 5 usaveis + cao, o energetico antes do cao" % label)
		_check_item_bar(hud, label, 6)
		(hud.get("_weapon_panel") as WeaponPanel).set_reload(true, 0.5)
		await frames(2)
		_check_item_bar(hud, label + " recarregando", 6)
		_end_hud_test()
