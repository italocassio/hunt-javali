extends "res://tests/lib/test_case.gd"
## Objectives and key legend of the first hunts (docs/arquitetura.md sections 6.8, 8.4 and 9.1, contract 1.3, HF4):
## ObjectivesPanel rows / progress / crop edges / touch texts, ControlsLegend rows / open-close / key labels from
## InputSetup.get_key_label, TouchControls.set_action_labels, the Hud decision (who shows what, when), the help key and
## the validation of game.onboarding.objective_kills / objective_crop_min_pct.

const DRONE: StringName = &"scout_drone"
const ALL_ITEMS: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"binoculars"]

var _belts: Array[ItemBelt] = []
var _saved_game_cfg: Dictionary = {}


## A hunter whose belt the Hud reads (same stub the item tests use).
class StubPlayer extends PlayerBase:
	pass


func _end() -> void:
	InputSetup.set_touch_override("auto")
	for b: ItemBelt in _belts:
		if is_instance_valid(b):
			b.free()
	_belts.clear()


func _panel() -> ObjectivesPanel:
	InputSetup.set_touch_override("off")
	var p: ObjectivesPanel = ObjectivesPanel.new()
	track(p)
	return p


func _legend() -> ControlsLegend:
	InputSetup.set_touch_override("off")
	var l: ControlsLegend = ControlsLegend.new()
	track(l)
	return l


func _belt(ids: Array[StringName]) -> ItemBelt:
	var player: StubPlayer = StubPlayer.new()
	track(player)
	var req: HuntRequest = HuntRequest.make_debug()
	req.item_ids = ids
	req.item_counts = {&"medkit": 1, &"corn_bait": 2, &"scout_drone": 3}
	var belt: ItemBelt = ItemBelt.new()
	belt.setup(req, player, null)
	_belts.append(belt)
	return belt


func _row_label(p: ObjectivesPanel, row: StringName) -> Label:
	return p.get_node("Row_%s/Text" % row) as Label


func _text_color(l: Label) -> Color:
	return l.get_theme_color("font_color")


func _mark_state(p: ObjectivesPanel, row: StringName) -> int:
	return int(p.get_node("Row_%s/Mark" % row).get("state"))


func _ob_cfg() -> Dictionary:
	return Data.get_game()["onboarding"]


func _short(id: StringName) -> String:
	return String(Data.get_equipment(id).get("short_name", ""))


# --------------------------------------------------------------------------------------------
# ObjectivesPanel: rows
# --------------------------------------------------------------------------------------------

func test_rows_without_dog_and_drone_are_kills_and_crop() -> void:
	var p: ObjectivesPanel = _panel()
	eq(p.get_row_ids(), [&"kills", &"crop"] as Array[StringName], "sem cao e sem drone")
	_end()


func test_dog_and_drone_rows_follow_presence_in_order() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_dog_present(true)
	eq(p.get_row_ids(), [&"dog", &"kills", &"crop"] as Array[StringName], "com cao")
	p.set_drone_present(true)
	eq(p.get_row_ids(), [&"dog", &"drone", &"kills", &"crop"] as Array[StringName], "com cao e drone")
	p.set_dog_present(false)
	eq(p.get_row_ids(), [&"drone", &"kills", &"crop"] as Array[StringName], "so drone")
	p.set_drone_present(false)
	eq(p.get_row_ids(), [&"kills", &"crop"] as Array[StringName], "de volta ao basico")
	_end()


func test_every_row_has_a_mark_and_a_text() -> void:
	var p: ObjectivesPanel = _panel()
	for row: StringName in [&"dog", &"drone", &"kills", &"crop"]:
		ok(p.has_node("Row_%s/Mark" % row), "Row_%s/Mark" % row)
		ok(p.has_node("Row_%s/Text" % row), "Row_%s/Text" % row)
	eq(p.get_row_text(&"nao_existe"), "", "id desconhecido: texto vazio")
	eq(p.get_row_state(&"nao_existe"), ObjectivesPanel.State.PENDING, "id desconhecido: PENDING")
	_end()


# --------------------------------------------------------------------------------------------
# ObjectivesPanel: texts (keyboard / touch)
# --------------------------------------------------------------------------------------------

func test_keyboard_texts_use_the_key_labels() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_dog_present(true)
	p.set_drone_present(true)
	eq(p.get_row_text(&"dog"), "Mande o cão atacar (%s)" % InputSetup.get_key_label(&"dog_command"), "cao: tecla do get_key_label")
	eq(p.get_row_text(&"dog"), "Mande o cão atacar (E)", "cao: E")
	eq(p.get_row_text(&"drone"), "Use o drone (%s)" % InputSetup.get_key_label(&"use_scout_drone"), "drone: tecla do get_key_label")
	eq(p.get_row_text(&"drone"), "Use o drone (V)", "drone: V")
	eq(p.get_row_text(&"crop"), "Mantenha a lavoura acima de 50%", "lavoura: 50%")
	_end()


func test_touch_texts_name_the_buttons() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_dog_present(true)
	p.set_drone_present(true)
	p.set_touch(true)
	eq(p.get_row_text(&"dog"), "Mande o cão atacar (botão Cão)", "cao no toque")
	eq(p.get_row_text(&"drone"), "Use o drone (botão %s)" % _short(DRONE), "drone no toque: short_name do item")
	eq(p.get_row_text(&"drone"), "Use o drone (botão Drone)", "drone no toque: botao Drone")
	p.set_touch(false)
	eq(p.get_row_text(&"dog"), "Mande o cão atacar (E)", "de volta ao teclado: cao")
	eq(p.get_row_text(&"drone"), "Use o drone (V)", "de volta ao teclado: drone")
	_end()


func test_set_touch_is_idempotent() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_dog_present(true)
	p.set_touch(true)
	p.set_touch(true)
	eq(p.get_row_text(&"dog"), "Mande o cão atacar (botão Cão)", "duas vezes no toque")
	_end()


# --------------------------------------------------------------------------------------------
# ObjectivesPanel: kills progress
# --------------------------------------------------------------------------------------------

func test_kills_goal_is_the_data_value_while_total_is_unknown() -> void:
	var p: ObjectivesPanel = _panel()
	eq(p.get_kills_goal(), int(_ob_cfg()["objective_kills"]), "meta = objective_kills (dado)")
	eq(p.get_kills_goal(), 3, "meta 3")
	eq(p.get_row_text(&"kills"), "Abata 3 javalis (0/3)", "texto inicial")
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.PENDING, "pendente")
	p.set_kills(0, 0)
	eq(p.get_kills_goal(), 3, "total 0 (desconhecido): meta continua 3")
	_end()


func test_kills_progress_text_and_done_state() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_kills(0, 8)
	eq(p.get_row_text(&"kills"), "Abata 3 javalis (0/3)", "0 de 8")
	p.set_kills(1, 8)
	eq(p.get_row_text(&"kills"), "Abata 3 javalis (1/3)", "1 de 8")
	p.set_kills(2, 8)
	eq(p.get_row_text(&"kills"), "Abata 3 javalis (2/3)", "2 de 8")
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.PENDING, "2/3 ainda pendente")
	p.set_kills(3, 8)
	eq(p.get_row_text(&"kills"), "Abata 3 javalis (3/3)", "3 de 8")
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.DONE, "3/3 feito")
	p.set_kills(6, 8)
	eq(p.get_row_text(&"kills"), "Abata 3 javalis (3/3)", "o contador nao passa da meta")
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.DONE, "continua feito")
	_end()


func test_kills_goal_is_capped_by_the_total() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_kills(0, 2)
	eq(p.get_kills_goal(), 2, "total 2: meta 2")
	eq(p.get_row_text(&"kills"), "Abata 2 javalis (0/2)", "k/N com N = total")
	p.set_kills(2, 2)
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.DONE, "2/2 feito")
	var q: ObjectivesPanel = _panel()
	q.set_kills(0, 3)
	eq(q.get_kills_goal(), 3, "total igual a objective_kills: meta 3")
	var r: ObjectivesPanel = _panel()
	r.set_kills(0, 100)
	eq(r.get_kills_goal(), 3, "total grande: meta 3")
	_end()


func test_kills_singular_when_the_goal_is_one() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_kills(0, 1)
	eq(p.get_kills_goal(), 1, "total 1: meta 1")
	eq(p.get_row_text(&"kills"), "Abata 1 javali (0/1)", "singular")
	p.set_kills(1, 1)
	eq(p.get_row_text(&"kills"), "Abata 1 javali (1/1)", "singular feito")
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.DONE, "1/1 feito")
	_end()


func test_kills_goal_comes_from_data() -> void:
	var cfg: Dictionary = _ob_cfg()
	var old: Variant = cfg["objective_kills"]
	cfg["objective_kills"] = 5
	var p: ObjectivesPanel = _panel()
	cfg["objective_kills"] = old   # restored before any assertion
	eq(p.get_kills_goal(), 5, "meta 5 vinda do dado")
	p.set_kills(2, 9)
	eq(p.get_row_text(&"kills"), "Abata 5 javalis (2/5)", "texto com a meta do dado")
	p.set_kills(2, 4)
	eq(p.get_kills_goal(), 4, "min(5, total 4)")
	_end()


func test_kills_done_is_latched() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_kills(3, 8)
	p.set_kills(0, 8)   # the count never goes down in a hunt, but the row must not un-finish itself
	eq(p.get_row_state(&"kills"), ObjectivesPanel.State.DONE, "feito fica feito")
	_end()


# --------------------------------------------------------------------------------------------
# ObjectivesPanel: crop (edges at P)
# --------------------------------------------------------------------------------------------

func test_crop_edges_below_equal_above_the_minimum() -> void:
	var p: ObjectivesPanel = _panel()
	var pmin: float = p.get_crop_min_pct()
	near(pmin, 50.0, 0.0001, "minimo vem do dado (50)")
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.OK, "inicio: lavoura inteira, OK")
	p.set_crop_pct(pmin - 0.1)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.FAIL, "abaixo do minimo: FAIL")
	p.set_crop_pct(pmin)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.OK, "exatamente no minimo: OK (limite inclusivo)")
	p.set_crop_pct(pmin + 0.1)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.OK, "acima: OK")
	p.set_crop_pct(100.0)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.OK, "100: OK")
	p.set_crop_pct(0.0)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.FAIL, "0: FAIL")
	_end()


func test_crop_recovers_and_never_reads_done() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_crop_pct(30.0)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.FAIL, "caiu")
	ok(_text_color(_row_label(p, &"crop")).is_equal_approx(ObjectivesPanel.COLOR_DANGER), "texto vermelho em FAIL")
	p.set_crop_pct(80.0)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.OK, "subiu: volta a OK")
	ok(_text_color(_row_label(p, &"crop")).is_equal_approx(ObjectivesPanel.COLOR_TEXT), "texto normal em OK")
	ne(p.get_row_state(&"crop"), ObjectivesPanel.State.DONE, "lavoura nunca fica DONE")
	_end()


func test_crop_text_comes_from_data() -> void:
	var cfg: Dictionary = _ob_cfg()
	var old: Variant = cfg["objective_crop_min_pct"]
	cfg["objective_crop_min_pct"] = 70.0
	var p: ObjectivesPanel = _panel()
	cfg["objective_crop_min_pct"] = old
	near(p.get_crop_min_pct(), 70.0, 0.0001, "minimo 70 vindo do dado")
	eq(p.get_row_text(&"crop"), "Mantenha a lavoura acima de 70%", "texto com 70%")
	p.set_crop_pct(69.0)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.FAIL, "69 < 70")
	p.set_crop_pct(70.0)
	eq(p.get_row_state(&"crop"), ObjectivesPanel.State.OK, "70 = 70")
	_end()


# --------------------------------------------------------------------------------------------
# ObjectivesPanel: dog and drone rows
# --------------------------------------------------------------------------------------------

func test_dog_row_done_only_by_the_attack_mark() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_dog_present(true)
	eq(p.get_row_state(&"dog"), ObjectivesPanel.State.PENDING, "cao pendente")
	p.mark_dog_ordered()
	eq(p.get_row_state(&"dog"), ObjectivesPanel.State.DONE, "cao feito")
	ok(_text_color(_row_label(p, &"dog")).is_equal_approx(ObjectivesPanel.COLOR_GOOD), "texto verde")
	eq(_mark_state(p, &"dog"), ObjectivesPanel.State.DONE, "marca desenhada em DONE")
	ok(p.get_row_ids().has(&"dog"), "linha feita continua na tela")
	_end()


func test_drone_row_done_by_the_use_mark() -> void:
	var p: ObjectivesPanel = _panel()
	p.set_drone_present(true)
	eq(p.get_row_state(&"drone"), ObjectivesPanel.State.PENDING, "drone pendente")
	p.mark_drone_used()
	eq(p.get_row_state(&"drone"), ObjectivesPanel.State.DONE, "drone feito")
	ok(p.get_row_ids().has(&"drone"), "linha feita continua")
	_end()


func test_marks_follow_the_row_states() -> void:
	var p: ObjectivesPanel = _panel()
	eq(_mark_state(p, &"kills"), ObjectivesPanel.State.PENDING, "kills pendente")
	eq(_mark_state(p, &"crop"), ObjectivesPanel.State.OK, "crop OK")
	p.set_crop_pct(10.0)
	eq(_mark_state(p, &"crop"), ObjectivesPanel.State.FAIL, "crop FAIL")
	p.set_kills(3, 5)
	eq(_mark_state(p, &"kills"), ObjectivesPanel.State.DONE, "kills DONE")
	_end()


# --------------------------------------------------------------------------------------------
# ControlsLegend
# --------------------------------------------------------------------------------------------

func test_legend_rows_without_items_or_dog() -> void:
	var l: ControlsLegend = _legend()
	eq(l.get_row_ids(), [&"move", &"mouse_buttons", &"reload", &"sprint", &"crouch", &"weapons", &"help"] as Array[StringName],
		"linhas fixas e a de ajuda")
	_end()


func test_legend_rows_with_items_and_dog_in_order() -> void:
	var l: ControlsLegend = _legend()
	l.set_items(ALL_ITEMS)
	l.set_dog_present(true)
	eq(l.get_row_ids(), [&"move", &"mouse_buttons", &"reload", &"sprint", &"crouch", &"weapons",
		&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"dog_command", &"help"] as Array[StringName],
		"fixas, itens, cao e ajuda")
	l.set_dog_present(false)
	ok(not l.get_row_ids().has(&"dog_command"), "sem cao, sem a linha do cao")
	_end()


func test_legend_grid_has_a_chip_and_a_text_per_row() -> void:
	var l: ControlsLegend = _legend()
	l.set_items(ALL_ITEMS)
	l.set_dog_present(true)
	eq(l.get_node("Rows").get_child_count(), l.get_row_ids().size() * 2, "dois filhos por linha")
	l.set_dog_present(false)
	l.set_items([&"medkit"] as Array[StringName])
	eq(l.get_node("Rows").get_child_count(), l.get_row_ids().size() * 2, "dois filhos por linha depois de reconstruir")
	_end()


func test_legend_passive_items_get_no_row() -> void:
	var l: ControlsLegend = _legend()
	l.set_items([&"leather_vest", &"extra_ammo", &"thermal_scope", &"scout_drone"] as Array[StringName])
	var ids: Array[StringName] = l.get_row_ids()
	ok(ids.has(&"scout_drone"), "drone tem linha")
	for passive: StringName in [&"leather_vest", &"extra_ammo", &"thermal_scope"]:
		ok(not ids.has(passive), "%s sem linha" % passive)
	_end()


func test_legend_keys_come_from_get_key_label() -> void:
	var l: ControlsLegend = _legend()
	l.set_items(ALL_ITEMS)
	l.set_dog_present(true)
	eq(l.get_key_text(&"move"), "%s%s%s%s" % [InputSetup.get_key_label(&"move_forward"), InputSetup.get_key_label(&"move_left"),
		InputSetup.get_key_label(&"move_back"), InputSetup.get_key_label(&"move_right")], "mover = 4 teclas juntas")
	eq(l.get_key_text(&"move"), "WASD", "WASD")
	eq(l.get_key_text(&"reload"), InputSetup.get_key_label(&"reload"), "recarregar")
	eq(l.get_key_text(&"sprint"), InputSetup.get_key_label(&"sprint"), "correr")
	eq(l.get_key_text(&"crouch"), InputSetup.get_key_label(&"crouch"), "agachar")
	eq(l.get_key_text(&"weapons"), "%s–%s" % [InputSetup.get_key_label(&"weapon_1"), InputSetup.get_key_label(&"weapon_5")], "armas 1–5")
	eq(l.get_key_text(&"weapons"), "1–5", "1–5")
	eq(l.get_key_text(&"medkit"), InputSetup.get_key_label(&"use_medkit"), "kit")
	eq(l.get_key_text(&"corn_bait"), InputSetup.get_key_label(&"use_corn_bait"), "ceva")
	eq(l.get_key_text(&"scout_drone"), InputSetup.get_key_label(&"use_scout_drone"), "drone")
	eq(l.get_key_text(&"binoculars"), InputSetup.get_key_label(&"use_binoculars"), "binoculo")
	eq(l.get_key_text(&"dog_command"), InputSetup.get_key_label(&"dog_command"), "cao")
	eq(l.get_key_text(&"help"), InputSetup.get_key_label(&"help"), "ajuda")
	eq(l.get_key_text(&"help"), "H", "ajuda = H")
	eq(l.get_key_text(&"mouse_buttons"), "Mouse", "so o mouse tem texto fixo")
	for id: StringName in l.get_row_ids():
		ne(l.get_key_text(id), "", "chip de %s nao esta vazio" % id)
	eq(l.get_key_text(&"nao_existe"), "", "id desconhecido: vazio")
	_end()


func test_legend_texts() -> void:
	var l: ControlsLegend = _legend()
	l.set_items(ALL_ITEMS)
	l.set_dog_present(true)
	eq(l.get_row_text(&"move"), "Mover", "mover")
	eq(l.get_row_text(&"mouse_buttons"), "Atirar / Mirar", "mouse")
	eq(l.get_row_text(&"reload"), "Recarregar", "recarregar")
	eq(l.get_row_text(&"sprint"), "Correr", "correr")
	eq(l.get_row_text(&"crouch"), "Agachar", "agachar")
	eq(l.get_row_text(&"weapons"), "Armas", "armas")
	eq(l.get_row_text(&"dog_command"), "Mandar o cão", "cao")
	eq(l.get_row_text(&"help"), "Recolher", "ajuda")
	for id: StringName in ALL_ITEMS:
		eq(l.get_row_text(id), _short(id), "%s usa o short_name" % id)
	eq(l.get_row_text(&"scout_drone"), "Drone", "drone")
	_end()


func test_legend_keys_follow_a_rebinding() -> void:
	var saved_dog: Array[InputEvent] = InputMap.action_get_events(&"dog_command")
	var saved_help: Array[InputEvent] = InputMap.action_get_events(&"help")
	for action: StringName in [&"dog_command", &"help"]:
		InputMap.action_erase_events(action)
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_T if action == &"dog_command" else KEY_J
		InputMap.action_add_event(action, ev)
	var l: ControlsLegend = _legend()
	l.set_dog_present(true)
	var p: ObjectivesPanel = _panel()
	p.set_dog_present(true)
	var chip_dog: String = l.get_key_text(&"dog_command")
	var chip_help: String = l.get_key_text(&"help")
	var tab: String = l.get_tab_text()
	var obj_dog: String = p.get_row_text(&"dog")
	for action: StringName in [&"dog_command", &"help"]:
		InputMap.action_erase_events(action)
		for ev: InputEvent in (saved_dog if action == &"dog_command" else saved_help):
			InputMap.action_add_event(action, ev)
	eq(chip_dog, "T", "legenda: tecla do cao religada")
	eq(chip_help, "J", "legenda: tecla de ajuda religada")
	eq(tab, "J: Ajuda", "aba usa a tecla religada")
	eq(obj_dog, "Mande o cão atacar (T)", "objetivo do cao usa a tecla religada")
	eq(InputSetup.get_key_label(&"dog_command"), "E", "InputMap restaurado")
	eq(InputSetup.get_key_label(&"help"), "H", "InputMap restaurado (ajuda)")
	_end()


func test_legend_starts_open_and_toggles_to_the_tab() -> void:
	var l: ControlsLegend = _legend()
	ok(l.is_open(), "comeca aberta")
	ok((l.get_node("Rows") as Control).visible, "grade visivel")
	ok(not (l.get_node("Tab") as Control).visible, "aba escondida")
	l.toggle()
	ok(not l.is_open(), "H recolhe")
	ok(not (l.get_node("Rows") as Control).visible, "grade escondida")
	ok((l.get_node("Tab") as Control).visible, "aba visivel")
	eq(l.get_tab_text(), "H: Ajuda", "aba 'H: Ajuda'")
	l.toggle()
	ok(l.is_open(), "H reabre")
	ok((l.get_node("Rows") as Control).visible, "grade volta")
	ok(not (l.get_node("Tab") as Control).visible, "aba some")
	_end()


func test_legend_set_open_is_explicit_and_survives_rebuilds() -> void:
	var l: ControlsLegend = _legend()
	l.set_open(false)
	l.set_open(false)
	ok(not l.is_open(), "fechada")
	l.set_items(ALL_ITEMS)
	l.set_dog_present(true)
	ok(not l.is_open(), "reconstruir as linhas nao reabre")
	ok(not (l.get_node("Rows") as Control).visible, "grade continua escondida")
	ok((l.get_node("Tab") as Control).visible, "aba continua visivel")
	l.set_open(true)
	ok(l.is_open() and (l.get_node("Rows") as Control).visible, "set_open(true) reabre")
	_end()


func test_legend_set_items_same_list_keeps_rows() -> void:
	var l: ControlsLegend = _legend()
	l.set_items(ALL_ITEMS)
	var before: Array[StringName] = l.get_row_ids()
	l.set_items(ALL_ITEMS)
	eq(l.get_row_ids(), before, "mesma lista, mesmas linhas")
	_end()


# --------------------------------------------------------------------------------------------
# help action and TouchControls labels
# --------------------------------------------------------------------------------------------

func test_help_action_is_h_and_last() -> void:
	ok(InputMap.has_action(&"help"), "InputMap tem 'help'")
	# docs/plano_horda_nivel2.md 4.9: `interact` comes right after `help`; the energy drink (F3) closes the list after both
	var help_at: int = InputSetup.ACTIONS.find("help")
	ok(help_at >= 0, "help esta em ACTIONS")
	eq(String(InputSetup.ACTIONS[InputSetup.ACTIONS.size() - 3]), "help", "help e a antepenultima ACTIONS (interact e use_energy_drink vem depois)")
	eq(String(InputSetup.ACTIONS[help_at + 1]), "interact", "interact logo depois de help")
	eq(String(InputSetup.ACTIONS[help_at + 2]), "use_energy_drink", "use_energy_drink logo depois de interact (F3)")
	var found: bool = false
	for ev: InputEvent in InputMap.action_get_events(&"help"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_H:
			found = true
	ok(found, "help = tecla H")
	eq(InputSetup.get_key_label(&"help"), "H", "rotulo H")


func test_touch_action_labels_toggle() -> void:
	InputSetup.set_touch_override("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	ok(not tc.has_action_labels(), "comeca sem nomes")
	tc.set_action_labels(true)
	ok(tc.has_action_labels(), "ligado")
	tc.set_action_labels(true)
	ok(tc.has_action_labels(), "ligar de novo e inofensivo")
	tc.set_action_labels(false)
	ok(not tc.has_action_labels(), "desligado")
	tc.set_action_labels(false)
	ok(not tc.has_action_labels(), "desligar de novo e inofensivo")
	_end()


# --------------------------------------------------------------------------------------------
# Hud: who shows what, when (private state is injected the way bind() would leave it)
# --------------------------------------------------------------------------------------------

func _hud(onboarding: bool = true, belt_ids: Array[StringName] = ALL_ITEMS) -> Hud:
	fresh_profile()
	InputSetup.set_touch_override("off")
	var h: Hud = Hud.new()
	track(h)
	if onboarding:
		h._setup_onboarding_ui(_belt(belt_ids))
	else:
		h._setup_onboarding_ui(null)
	return h


func _hud_visibility(h: Hud) -> Array[bool]:
	return [h._objectives_panel.visible, h._legend_panel.visible, h._touch.has_action_labels()]


func test_hud_first_hunt_shows_objectives_legend_and_labels_on_keyboard() -> void:
	var h: Hud = _hud()
	eq(_hud_visibility(h), [true, true, true] as Array[bool], "teclado: objetivos, legenda e nomes nos botoes")
	ok(h._legend.is_open(), "legenda comeca aberta")
	ok(h._objectives.get_row_ids().has(&"drone"), "drone na belt: linha do drone")
	ok(h._legend.get_row_ids().has(&"binoculars"), "legenda traz os itens da belt")
	_end()


func test_hud_after_the_first_hunts_everything_is_hidden() -> void:
	fresh_profile()
	for i: int in int(_ob_cfg()["max_hunts"]):
		var r: HuntResult = HuntResult.new()
		r.outcome = HuntResult.Outcome.DEFEAT_CROP
		r.map_id = &"mato_grosso"
		Profile.apply_hunt_result(r)
	ok(not Profile.is_onboarding_active(), "perfil fora das primeiras cacadas")
	InputSetup.set_touch_override("off")
	var h: Hud = Hud.new()
	track(h)
	h._setup_onboarding_ui(_belt(ALL_ITEMS))
	eq(_hud_visibility(h), [false, false, false] as Array[bool], "tudo escondido")
	_end()


func test_hud_hints_off_hides_everything() -> void:
	fresh_profile()
	InputSetup.set_touch_override("off")
	var h: Hud = Hud.new()
	track(h)
	h._hints_enabled = false   # the Web ?hints=0 switch
	h._setup_onboarding_ui(_belt(ALL_ITEMS))
	eq(_hud_visibility(h), [false, false, false] as Array[bool], "?hints=0: tudo escondido")
	_end()


func test_hud_without_a_drone_in_the_belt_has_no_drone_row() -> void:
	var h: Hud = _hud(true, [&"medkit", &"binoculars"] as Array[StringName])
	ok(not h._objectives.get_row_ids().has(&"drone"), "sem drone, sem linha do drone")
	ok(not h._legend.get_row_ids().has(&"scout_drone"), "sem drone, sem linha na legenda")
	_end()


func test_hud_touch_hides_the_legend_and_keeps_objectives_and_labels() -> void:
	var h: Hud = _hud()
	InputSetup.set_touch_override("on")   # emits touch_mode_changed: the Hud reapplies
	eq(_hud_visibility(h), [true, false, true] as Array[bool], "toque: objetivos e nomes, sem legenda")
	InputSetup.set_touch_override("off")
	eq(_hud_visibility(h), [true, true, true] as Array[bool], "de volta ao teclado")
	_end()


func test_hud_horde_keeps_only_the_legend() -> void:
	var h: Hud = _hud()
	h._horde = true
	h._refresh_onboarding_ui()
	eq(h._objectives_panel.visible, false, "horda: sem objetivos")
	eq(h._legend_panel.visible, true, "horda: legenda fica")
	_end()


func test_hud_spectator_hides_everything_and_returns() -> void:
	var h: Hud = _hud()
	GameEvents.spectate_changed.emit(1)
	eq(_hud_visibility(h), [false, false, false] as Array[bool], "espectador: tudo escondido")
	GameEvents.spectate_changed.emit(Hud.NO_SLOT)
	eq(_hud_visibility(h), [true, true, true] as Array[bool], "saiu do espectador: volta")
	_end()


func test_hud_fallen_hunter_hides_everything() -> void:
	var h: Hud = _hud()
	GameEvents.player_died.emit()
	eq(_hud_visibility(h), [false, false, false] as Array[bool], "caido: tudo escondido")
	_end()


func test_hud_end_of_hunt_hides_everything() -> void:
	var h: Hud = _hud()
	h.on_hunt_ended()
	eq(_hud_visibility(h), [false, false, false] as Array[bool], "fim da cacada: tudo escondido")
	_end()


func test_hud_feeds_the_objectives_from_game_events() -> void:
	var h: Hud = _hud()
	GameEvents.boar_counts_changed.emit(2, 6)
	eq(h._objectives.get_row_text(&"kills"), "Abata 3 javalis (2/3)", "contagem do time")
	GameEvents.crop_health_changed.emit(20.0)
	eq(h._objectives.get_row_state(&"crop"), ObjectivesPanel.State.FAIL, "lavoura em 20%: FAIL")
	GameEvents.crop_health_changed.emit(90.0)
	eq(h._objectives.get_row_state(&"crop"), ObjectivesPanel.State.OK, "lavoura em 90%: OK")
	GameEvents.item_used.emit(&"medkit", Vector3.ZERO)
	eq(h._objectives.get_row_state(&"drone"), ObjectivesPanel.State.PENDING, "outro item nao conta como drone")
	GameEvents.item_used.emit(DRONE, Vector3.ZERO)
	eq(h._objectives.get_row_state(&"drone"), ObjectivesPanel.State.DONE, "drone usado")
	h._objectives.set_dog_present(true)
	GameEvents.dog_command_executed.emit(Ids.CMD_RECALL)
	eq(h._objectives.get_row_state(&"dog"), ObjectivesPanel.State.PENDING, "'Volta!' nao conta")
	GameEvents.dog_command_executed.emit(Ids.CMD_ATTACK)
	eq(h._objectives.get_row_state(&"dog"), ObjectivesPanel.State.DONE, "'Pega!' conta")
	_end()


func test_hud_help_key_toggles_the_legend_only_while_visible() -> void:
	var h: Hud = _hud()
	await _press_help()
	ok(not h._legend.is_open(), "H recolhe a legenda")
	await _press_help()
	ok(h._legend.is_open(), "H reabre a legenda")
	GameEvents.spectate_changed.emit(1)   # legend hidden: the key must do nothing
	await _press_help()
	ok(h._legend.is_open(), "legenda escondida: H nao mexe")
	GameEvents.spectate_changed.emit(Hud.NO_SLOT)
	_end()


func test_hud_help_key_does_nothing_on_the_late_hunts() -> void:
	fresh_profile()
	InputSetup.set_touch_override("off")
	var h: Hud = Hud.new()
	track(h)
	h._hints_enabled = false
	h._setup_onboarding_ui(null)
	await _press_help()
	ok(h._legend.is_open(), "fora das primeiras cacadas: H nao faz nada")
	_end()


func _press_help() -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = &"help"
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up: InputEventAction = InputEventAction.new()
	up.action = &"help"
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


# --------------------------------------------------------------------------------------------
# Data validation (same technique as test_onboarding: poke the live registry, then restore it)
# --------------------------------------------------------------------------------------------

func test_data_has_the_objective_keys_and_loads_clean() -> void:
	eq(Data.get_load_errors().size(), 0, "Data.get_load_errors: %s" % str(Data.get_load_errors()))
	var cfg: Dictionary = _ob_cfg()
	for key: String in ["objective_kills", "objective_crop_min_pct"]:
		ok(cfg.has(key), "onboarding.%s existe" % key)
		var v: Variant = cfg.get(key)
		ok(v is int or v is float, "onboarding.%s e numero" % key)
		if v is int or v is float:
			ok(float(v) > 0.0, "onboarding.%s > 0" % key)
	eq(int(cfg["objective_kills"]), 3, "objective_kills = 3")
	near(float(cfg["objective_crop_min_pct"]), 50.0, 0.0001, "objective_crop_min_pct = 50")
	ok(float(cfg["objective_crop_min_pct"]) <= 100.0, "objective_crop_min_pct <= 100")
	eq(float(cfg["objective_kills"]), floorf(float(cfg["objective_kills"])), "objective_kills inteiro")


## Errors that _validate_onboarding reports with `key` set to `value` (restored; the registry ends as it was).
func _errors_with(key: String, value: Variant, erase: bool = false) -> PackedStringArray:
	var base: int = Data.get_load_errors().size()
	var cfg: Dictionary = _ob_cfg()
	var old: Variant = cfg[key]
	if erase:
		cfg.erase(key)
	else:
		cfg[key] = value
	Data._validate_onboarding()
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(base, Data.get_load_errors().size()):
		out.append(Data.get_load_errors()[i])
	cfg[key] = old
	Data._errors.resize(base)
	return out


func test_data_validation_accepts_the_edges() -> void:
	eq(_errors_with("objective_kills", 1).size(), 0, "objective_kills 1")
	eq(_errors_with("objective_kills", 3.0).size(), 0, "objective_kills 3.0 (inteiro em float)")
	eq(_errors_with("objective_crop_min_pct", 100.0).size(), 0, "objective_crop_min_pct 100")
	eq(_errors_with("objective_crop_min_pct", 0.5).size(), 0, "objective_crop_min_pct 0.5")
	eq(Data.get_load_errors().size(), 0, "registro intacto")


func test_data_validation_rejects_a_fractional_objective_kills() -> void:
	var errs: PackedStringArray = _errors_with("objective_kills", 2.5)
	eq(errs.size(), 1, "objective_kills 2.5: um erro (%s)" % str(errs))
	if errs.size() > 0:
		contains(errs[0], "objective_kills", "o erro cita a chave")
		contains(errs[0], "integer", "o erro diz que tem de ser inteiro")
	eq(Data.get_load_errors().size(), 0, "registro restaurado")


func test_data_validation_rejects_a_crop_minimum_above_100() -> void:
	var errs: PackedStringArray = _errors_with("objective_crop_min_pct", 120.0)
	eq(errs.size(), 1, "objective_crop_min_pct 120: um erro (%s)" % str(errs))
	if errs.size() > 0:
		contains(errs[0], "objective_crop_min_pct", "o erro cita a chave")
		contains(errs[0], "100", "o erro cita o limite")
	eq(Data.get_load_errors().size(), 0, "registro restaurado")


func test_data_validation_rejects_missing_zero_and_negative_objectives() -> void:
	for key: String in ["objective_kills", "objective_crop_min_pct"]:
		eq(_errors_with(key, null, true).size(), 1, "%s ausente: um erro" % key)
		eq(_errors_with(key, 0).size(), 1, "%s = 0: um erro" % key)
		eq(_errors_with(key, -5).size(), 1, "%s negativo: um erro" % key)
		eq(_errors_with(key, "3").size(), 1, "%s texto: um erro" % key)
	eq(Data.get_load_errors().size(), 0, "registro restaurado")
