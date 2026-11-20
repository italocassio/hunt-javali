extends "res://tests/lib/test_case.gd"
## Preparation and lobby loadout without key labels (docs/arquitetura.md sections 8.4 and 11, contract 1.4, HF5-S):
## no ItemKey_<id> node and no DogKeyLabel anywhere, the dog hint says "Pega! / Volta!" without the letter "E", and
## choosing items and the dog still works as before. Keyboard mode and touch mode.

const DOG_HINT: String = "Na caçada, mande o cão: Pega! / Volta!"
const KEY_LETTERS: Array[String] = ["Q", "G", "V", "B", "E", "H", "R"]


func _panel(touch: String, with_dog: bool) -> Array:
	InputSetup.set_touch_override(touch)
	fresh_profile()
	if with_dog:
		Profile.add_money(20000)
		eq(Profile.buy(&"caramelo"), &"ok", "compra do caramelo")
		Profile.set_loadout_dog(&"caramelo")
	var root: Control = Control.new()
	root.name = "Root"
	track(root)
	var panel: LoadoutPanel = LoadoutPanel.new()
	root.add_child(panel)
	panel.setup(root)
	return [root, panel]


func _end() -> void:
	InputSetup.set_touch_override("auto")


func _all_nodes(node: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(node)
	for c: Node in node.get_children():
		_all_nodes(c, out)
	return out


func _check_no_key_labels(root: Node, where: String) -> void:
	ok(root.find_child("ItemKey_*", true, false) == null, "%s: find_child(\"ItemKey_*\") nao acha nada" % where)
	ok(root.find_child("DogKeyLabel", true, false) == null, "%s: find_child(\"DogKeyLabel\") nao acha nada" % where)
	ok(root.get_node_or_null("%DogKeyLabel") == null, "%s: %%DogKeyLabel nao resolve" % where)
	for n: Node in _all_nodes(root):
		var node_name: String = String(n.name)
		ok(not node_name.begins_with("ItemKey_"), "%s: nenhum no chamado ItemKey_* (achei %s)" % [where, node_name])
		ok(node_name != "DogKeyLabel", "%s: nenhum no chamado DogKeyLabel" % where)
		if n is Label or n is Button:
			var text: String = String(n.get("text")).strip_edges()
			ok(not KEY_LETTERS.has(text), "%s: %s nao mostra uma letra de tecla solta ('%s')" % [where, node_name, text])


func test_keyboard_has_no_key_labels() -> void:
	var made: Array = _panel("off", true)
	_check_no_key_labels(made[0], "teclado")
	_end()


func test_touch_has_no_key_labels() -> void:
	var made: Array = _panel("on", true)
	_check_no_key_labels(made[0], "toque")
	_end()


func test_no_key_labels_without_a_dog_either() -> void:
	var made: Array = _panel("off", false)
	_check_no_key_labels(made[0], "sem cao")
	_end()


func test_item_rows_exist_by_id() -> void:
	for mode: String in ["off", "on"]:
		var made: Array = _panel(mode, true)
		var root: Control = made[0]
		var found: int = 0
		for id: StringName in Data.get_equipment_ids():
			if Profile.owns(id):
				var row: Node = root.get_node_or_null("%%Item_%s" % id)
				ok(row is CheckButton, "%s: Item_%s existe e e um CheckButton" % [mode, id])
				found += 1
				ok(root.find_child("ItemKey_%s" % id, true, false) == null, "%s: sem ItemKey_%s" % [mode, id])
		ok(found >= 2, "%s: o perfil novo tem pelo menos 2 equipamentos (%d)" % [mode, found])
		ok(root.get_node_or_null("%DogOption") is OptionButton, "%s: %%DogOption existe" % mode)
		ok(root.get_node_or_null("%WeaponSlot0") is Button, "%s: %%WeaponSlot0 existe" % mode)
		ok(root.get_node_or_null("%WeaponSlot1") is Button, "%s: %%WeaponSlot1 existe" % mode)
		_end()


func test_dog_hint_has_no_key_letter() -> void:
	var made: Array = _panel("off", true)
	var panel: LoadoutPanel = made[1]
	var hint: String = (panel._dog_hint as Label).text
	eq(hint, DOG_HINT, "frase do cao")
	var letter: RegEx = RegEx.new()
	letter.compile("\\bE\\b")
	ok(letter.search(hint) == null, "a frase nao tem a letra E isolada ('%s')" % hint)
	ok(not hint.contains("(E)") and not hint.contains("Tecla"), "a frase nao cita tecla")
	ok(hint.contains("Pega!") and hint.contains("Volta!"), "a frase cita os dois comandos")
	_end()


func test_dog_hint_in_every_state() -> void:
	var made: Array = _panel("off", false)
	var panel: LoadoutPanel = made[1]
	eq((panel._dog_hint as Label).text, "Compre um cão na Loja para levar à caçada.", "sem cao no inventario")
	_end()
	var owned: Array = _panel("off", true)
	var with_dog: LoadoutPanel = owned[1]
	eq((with_dog._dog_hint as Label).text, DOG_HINT, "cao escolhido")
	Profile.set_loadout_dog(&"")
	with_dog.refresh()
	eq((with_dog._dog_hint as Label).text, "", "tem cao, mas nenhum escolhido: sem frase")
	Profile.set_loadout_dog(&"caramelo")
	with_dog.refresh()
	eq((with_dog._dog_hint as Label).text, DOG_HINT, "cao escolhido de novo")
	_end()


func test_dog_locked_text_replaces_the_hint() -> void:
	InputSetup.set_touch_override("off")
	fresh_profile()
	Profile.add_money(20000)
	Profile.buy(&"caramelo")
	var root: Control = Control.new()
	track(root)
	var panel: LoadoutPanel = LoadoutPanel.new()
	root.add_child(panel)
	panel.setup(root, "O anfitrião escolhe o cão.")
	eq((panel._dog_hint as Label).text, "O anfitrião escolhe o cão.", "texto de bloqueio")
	ok((root.get_node("%DogOption") as OptionButton).disabled, "a escolha do cao fica desabilitada")
	_end()


func test_toggling_items_and_choosing_the_dog_work_as_before() -> void:
	for mode: String in ["off", "on"]:
		var made: Array = _panel(mode, true)
		var root: Control = made[0]
		var panel: LoadoutPanel = made[1]
		var changes: Dictionary = record_signal(panel.changed)
		var kit: CheckButton = root.get_node("%Item_medkit") as CheckButton
		var drone: CheckButton = root.get_node("%Item_scout_drone") as CheckButton
		kit.button_pressed = false
		drone.button_pressed = false
		ok(not Profile.get_loadout_items().has(&"medkit"), "%s: kit desmarcado" % mode)
		kit.button_pressed = true
		ok(Profile.get_loadout_items().has(&"medkit"), "%s: kit marcado entra no loadout" % mode)
		drone.button_pressed = true
		ok(Profile.get_loadout_items().has(&"scout_drone"), "%s: drone marcado entra no loadout" % mode)
		kit.button_pressed = false
		ok(not Profile.get_loadout_items().has(&"medkit"), "%s: kit desmarcado sai do loadout" % mode)
		ok(int(changes["count"]) >= 4, "%s: o painel avisa cada mudanca (%d)" % [mode, int(changes["count"])])
		var option: OptionButton = root.get_node("%DogOption") as OptionButton
		option.item_selected.emit(0)
		eq(Profile.get_loadout_dog(), &"", "%s: 'Sem cao' tira o cao" % mode)
		eq((panel._dog_hint as Label).text, "", "%s: sem cao escolhido, sem frase" % mode)
		var caramelo_at: int = -1
		for i: int in option.item_count:
			if option.get_item_metadata(i) == &"caramelo":
				caramelo_at = i
		ok(caramelo_at > 0, "%s: o caramelo esta na lista" % mode)
		option.item_selected.emit(caramelo_at)
		eq(Profile.get_loadout_dog(), &"caramelo", "%s: escolher o caramelo coloca o cao" % mode)
		eq((panel._dog_hint as Label).text, DOG_HINT, "%s: frase volta" % mode)
		_end()


func test_item_checkbox_text_is_the_name_and_count_only() -> void:
	var made: Array = _panel("off", false)
	var root: Control = made[0]
	var kit: CheckButton = root.get_node("%Item_medkit") as CheckButton
	var def: Dictionary = Data.get_equipment(&"medkit")
	ok(kit.text.begins_with(String(def.get("name", ""))), "o texto comeca pelo nome ('%s')" % kit.text)
	ok(not kit.text.contains("["), "sem rotulo de tecla entre colchetes")
	_end()


## The real Preparation screen, keyboard and touch: the same absence of key labels in the whole scene.
func test_preparation_scene_has_no_key_labels() -> void:
	for mode: String in ["off", "on"]:
		InputSetup.set_touch_override(mode)
		fresh_profile()
		Profile.add_money(20000)
		Profile.buy(&"caramelo")
		Router.selected_map_id = &"mato_grosso"
		Router.selected_contract_index = 0
		var scene: PackedScene = need_scene(ScenePaths.PREPARATION)
		if scene == null:
			return
		var screen: Control = scene.instantiate() as Control
		track(screen)
		await frames(2)
		_check_no_key_labels(screen, "Preparacao (%s)" % mode)
		ok(screen.get_node_or_null("%DogOption") is OptionButton, "%s: %%DogOption na Preparacao" % mode)
		ok(screen.get_node_or_null("%Item_medkit") is CheckButton, "%s: Item_medkit na Preparacao" % mode)
		ok(screen.get_node_or_null("%StartHuntButton") is Button, "%s: %%StartHuntButton continua" % mode)
		_end()
