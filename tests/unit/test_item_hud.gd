extends "res://tests/lib/test_case.gd"
## Fixed item keys and the item bar (docs/arquitetura.md sections 4, 8.4 and 8.11, contract 1.3):
## InputSetup.get_item_action / get_key_label, ItemBelt.use_item by id, Quickbar slots, TouchControls item buttons.
## No selection exists any more: every usable item has its own action.

const ITEM_ORDER: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"binoculars"]


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
	for passive: StringName in [&"leather_vest", &"extra_ammo", &"thermal_scope"]:
		eq(InputSetup.get_item_action(passive), &"", "passivo %s nao tem acao" % passive)
	eq(InputSetup.get_item_action(&""), &"", "id vazio")
	eq(InputSetup.get_item_action(&"inexistente"), &"", "id desconhecido")


func test_get_key_label_of_each_item_action() -> void:
	eq(InputSetup.get_key_label(&"use_medkit"), "Q", "kit")
	eq(InputSetup.get_key_label(&"use_corn_bait"), "G", "ceva")
	eq(InputSetup.get_key_label(&"use_scout_drone"), "V", "drone")
	eq(InputSetup.get_key_label(&"use_binoculars"), "B", "binoculo")
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
		"use_binoculars": KEY_B, "dog_command": KEY_E, "spectate_next": KEY_F}
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
	for action: String in ["use_medkit", "use_corn_bait", "use_scout_drone", "use_binoculars", "spectate_next"]:
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
	eq(all4.get_usable_ids(), ITEM_ORDER, "os 4 usaveis na ordem das acoes")
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
	var tc: TouchControls = _touch(_belt([&"medkit", &"corn_bait", &"scout_drone", &"binoculars"]))
	tc.set_dog_present(true)
	tc._revive_on = true
	tc._rebuild_buttons()
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
	InputSetup.set_touch_override("auto")
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
