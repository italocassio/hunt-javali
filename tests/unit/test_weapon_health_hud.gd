extends "res://tests/lib/test_case.gd"
## The weapon panel and the wide health bar of the HUD (docs/arquitetura.md sections 6.8 and 8.4, contract 1.5, HF6):
## WeaponPanel (weapons row, active weapon, ammo text and colour, reload bar, touch keys), HealthStrip (bar colour by
## fraction, number, vest, widths) and the Hud wiring with a real Player and a fake world (bind, weapon switch, health,
## vest, horde infinity, spectator, touch layout, bottom stack).

const CARBINE: StringName = &"carbine_22"
const SHOTGUN: StringName = &"shotgun_12"
const TWO_WEAPONS: Array[StringName] = [&"carbine_22", &"shotgun_12"]
const ONE_WEAPON: Array[StringName] = [&"carbine_22"]
const FAKE_ID: StringName = &"fake_gun"
const SHOTGUN_NAME: String = "Espingarda calibre 12"
const FRAME_SETTLE: int = 3


## Just enough world for the Player and the Hud (same idea as the one of test_compass_minimap).
class FakeWorld extends HuntWorld:
	var player: PlayerBase = null
	var horde: bool = false

	func get_map_rect() -> Rect2:
		return Rect2(-128.0, -128.0, 256.0, 256.0)

	func get_mode() -> StringName:
		return Ids.MODE_HORDE if horde else Ids.MODE_CONTRACT

	func get_player() -> PlayerBase:
		return player


func _end() -> void:
	InputSetup.set_touch_override("auto")


# --------------------------------------------------------------------------------------------
# WeaponPanel on its own (no Hud)
# --------------------------------------------------------------------------------------------

func _panel(ids: Array[StringName] = TWO_WEAPONS) -> WeaponPanel:
	InputSetup.set_touch_override("off")
	var panel: WeaponPanel = WeaponPanel.new()
	track(panel)
	panel.set_weapons(ids)
	return panel


func _mag_color(panel: WeaponPanel) -> Color:
	return (panel.get_node("Main/Ammo/Mag") as Label).get_theme_color("font_color")


func _reserve_color(panel: WeaponPanel) -> Color:
	return (panel.get_node("Main/Ammo/Reserve") as Label).get_theme_color("font_color")


func _chip(panel: WeaponPanel, n: int) -> Control:
	return panel.get_node("Row/Chip_%d" % n) as Control


func test_panel_two_weapons_make_two_chips_a_visible_row_and_the_first_active() -> void:
	var panel: WeaponPanel = _panel()
	ok(panel.has_node("Row/Chip_1"), "Chip_1")
	ok(panel.has_node("Row/Chip_2"), "Chip_2")
	ok(not panel.has_node("Row/Chip_3"), "sem Chip_3")
	ok(panel.is_row_visible(), "fileira visivel com 2 armas")
	eq(panel.get_weapon_ids(), TWO_WEAPONS, "get_weapon_ids")
	eq(panel.get_active_index(), 0, "set_weapons ativa o indice 0 sozinho")
	eq(panel.get_name_text(), "Carabina .22", "nome da arma 0")
	_end()


func test_panel_chip_keys_are_the_weapon_key_labels() -> void:
	var panel: WeaponPanel = _panel()
	eq(panel.get_chip_key_text(0), InputSetup.get_key_label(&"weapon_1"), "tecla do chip 0 = get_key_label(weapon_1)")
	eq(panel.get_chip_key_text(1), InputSetup.get_key_label(&"weapon_2"), "tecla do chip 1 = get_key_label(weapon_2)")
	eq(panel.get_chip_key_text(0), "1", "chip 0: 1")
	eq(panel.get_chip_key_text(1), "2", "chip 1: 2")
	eq(panel.get_chip_key_text(2), "", "fora da faixa: vazio")
	eq(panel.get_chip_key_text(-1), "", "negativo: vazio")
	_end()


func test_panel_one_weapon_hides_the_row_but_keeps_the_chip() -> void:
	var panel: WeaponPanel = _panel(ONE_WEAPON)
	ok(not panel.is_row_visible(), "uma arma: sem fileira")
	ok(panel.has_node("Row/Chip_1"), "o chip existe (so a fileira some)")
	eq(panel.get_active_index(), 0, "ativa a unica arma")
	eq(panel.get_name_text(), "Carabina .22", "nome")
	_end()


func test_panel_five_weapons_make_five_chips_and_no_sixth() -> void:
	var ids: Array[StringName] = Data.get_weapon_ids()
	eq(ids.size(), 5, "weapons.json tem 5 armas")
	var panel: WeaponPanel = _panel(ids)
	for n: int in range(1, 6):
		ok(panel.has_node("Row/Chip_%d" % n), "Chip_%d" % n)
		eq(panel.get_chip_key_text(n - 1), str(n), "tecla do chip %d" % n)
	ok(not panel.has_node("Row/Chip_6"), "sem Chip_6")
	ok(panel.is_row_visible(), "fileira visivel")
	eq(panel.get_active_index(), 0, "ativa a 0")
	_end()


func test_panel_empty_list_leaves_the_panel_without_a_weapon() -> void:
	var panel: WeaponPanel = _panel([] as Array[StringName])
	eq(panel.get_active_index(), -1, "sem arma ativa")
	ok(not panel.is_row_visible(), "sem fileira")
	ok(not panel.has_node("Row/Chip_1"), "sem chips")
	eq(panel.get_name_text(), "", "sem nome")
	eq(panel.get_portrait_path(), "", "sem retrato")
	panel.set_active(0)
	eq(panel.get_active_index(), -1, "set_active(0) em lista vazia nao faz nada")
	eq(panel.get_chip_key_text(0), "", "tecla de chip inexistente")
	panel.set_ammo(0, 0, false, 5)   # the ammo still works without a weapon
	panel.set_reload(true, 0.5)
	_end()


func test_panel_set_weapons_again_rebuilds_everything() -> void:
	var panel: WeaponPanel = _panel(Data.get_weapon_ids())
	panel.set_active(3)
	eq(panel.get_active_index(), 3, "ativa a 3 antes de refazer")
	panel.set_weapons(TWO_WEAPONS)
	ok(panel.has_node("Row/Chip_2"), "Chip_2 existe")
	ok(not panel.has_node("Row/Chip_3"), "Chip_3 foi removido")
	eq(panel.get_active_index(), 0, "refazer volta para o indice 0")
	eq(panel.get_weapon_ids(), TWO_WEAPONS, "lista nova")
	panel.set_weapons(ONE_WEAPON)
	ok(not panel.is_row_visible(), "de volta a uma arma: fileira some")
	panel.set_weapons(TWO_WEAPONS)
	ok(panel.is_row_visible(), "e volta com duas")
	_end()


func test_panel_weapon_ids_is_a_copy() -> void:
	var panel: WeaponPanel = _panel()
	var ids: Array[StringName] = panel.get_weapon_ids()
	ids.clear()
	eq(panel.get_weapon_ids().size(), 2, "alterar a copia nao muda o painel")
	var source: Array[StringName] = [CARBINE, SHOTGUN] as Array[StringName]
	panel.set_weapons(source)
	source.clear()
	eq(panel.get_weapon_ids().size(), 2, "alterar a lista de origem nao muda o painel")
	_end()


func test_panel_set_active_switches_name_portrait_and_chips() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_active(1)
	eq(panel.get_active_index(), 1, "indice 1")
	eq(panel.get_name_text(), SHOTGUN_NAME, "nome da espingarda")
	eq(panel.get_portrait_path(), ScenePaths.weapon_art(SHOTGUN), "retrato = PNG da espingarda")
	near(_chip(panel, 2).modulate.a, 1.0, 0.001, "chip ativo com alfa 1")
	near(_chip(panel, 1).modulate.a, WeaponPanel.INACTIVE_ALPHA, 0.001, "chip inativo com INACTIVE_ALPHA")
	panel.set_active(0)
	near(_chip(panel, 1).modulate.a, 1.0, 0.001, "voltou: chip 1 ativo")
	near(_chip(panel, 2).modulate.a, WeaponPanel.INACTIVE_ALPHA, 0.001, "voltou: chip 2 inativo")
	_end()


func test_panel_set_active_out_of_range_changes_nothing() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_active(1)
	panel.set_active(9)
	eq(panel.get_active_index(), 1, "9 nao muda")
	panel.set_active(-1)
	eq(panel.get_active_index(), 1, "-1 nao muda")
	panel.set_active(2)
	eq(panel.get_active_index(), 1, "tamanho da lista nao muda")
	eq(panel.get_name_text(), SHOTGUN_NAME, "nome continua")
	near(_chip(panel, 2).modulate.a, 1.0, 0.001, "chip 2 continua ativo")
	_end()


func test_panel_every_weapon_has_a_portrait_and_the_chip_shares_the_texture() -> void:
	var ids: Array[StringName] = Data.get_weapon_ids()
	var panel: WeaponPanel = _panel(ids)
	for i: int in ids.size():
		panel.set_active(i)
		eq(panel.get_portrait_path(), ScenePaths.weapon_art(ids[i]), "%s: caminho do retrato" % ids[i])
		var big: TextureRect = panel.get_node("Main/Portrait") as TextureRect
		var small: TextureRect = _chip(panel, i + 1).get_node("Portrait") as TextureRect
		ok(big.texture != null, "%s: retrato grande carregado" % ids[i])
		ok(big.texture == small.texture, "%s: a mesma textura serve ao chip" % ids[i])
		eq(big.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "%s: filtro com mipmap" % ids[i])
		eq(small.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "%s: chip com mipmap" % ids[i])
	_end()


func test_panel_unknown_weapon_has_no_portrait_and_does_not_break() -> void:
	expect_errors()   # Data.get_weapon pushes an error for the unknown id
	var panel: WeaponPanel = _panel([FAKE_ID] as Array[StringName])
	eq(panel.get_portrait_path(), "", "sem PNG nem SVG: caminho vazio")
	eq(panel.get_active_index(), 0, "ativa mesmo assim")
	eq(panel.get_name_text(), String(FAKE_ID), "sem nome nos dados: o id")
	ok((panel.get_node("Main/Portrait") as TextureRect).texture == null, "retrato vazio")
	panel.set_ammo(1, 1, false, 2)
	_end()


func test_panel_ammo_texts() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_ammo(5, 30, false, 10)
	eq(panel.get_mag_text(), "5", "pente")
	eq(panel.get_reserve_text(), "| 30", "reserva")
	panel.set_ammo(10, 0, false, 10)
	eq(panel.get_mag_text(), "10", "pente cheio")
	eq(panel.get_reserve_text(), "| 0", "reserva zero aparece")
	panel.set_ammo(5, 30, false, 10)
	panel.set_ammo(5, 29, false, 10)
	eq(panel.get_reserve_text(), "| 29", "so a reserva mudou: o texto acompanha")
	panel.set_ammo(4, 29, false, 10)
	eq(panel.get_mag_text(), "4", "so o pente mudou: o texto acompanha")
	eq((panel.get_node("Main/Ammo/Mag") as Label).text, panel.get_mag_text(), "Mag e get_mag_text iguais")
	eq((panel.get_node("Main/Ammo/Reserve") as Label).text, panel.get_reserve_text(), "Reserve e get_reserve_text iguais")
	_end()


func test_panel_low_ammo_rule_and_colour() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_ammo(5, 30, false, 10)
	ok(not panel.is_ammo_low(), "5 de 10 nao e baixa")
	ok(_mag_color(panel).is_equal_approx(WeaponPanel.COLOR_TEXT), "pente em COLOR_TEXT")
	panel.set_ammo(3, 30, false, 10)
	ok(not panel.is_ammo_low(), "3 de 10 (> 2,5) nao e baixa")
	panel.set_ammo(2, 30, false, 10)
	ok(panel.is_ammo_low(), "2 de 10 (<= 2,5) e baixa")
	ok(_mag_color(panel).is_equal_approx(WeaponPanel.COLOR_DANGER), "pente em COLOR_DANGER")
	ok(_reserve_color(panel).is_equal_approx(WeaponPanel.COLOR_TEXT), "reserva continua em COLOR_TEXT")
	panel.set_ammo(0, 0, false, 5)
	ok(panel.is_ammo_low(), "pente vazio e baixa")
	panel.set_ammo(1, 0, false, 5)
	ok(panel.is_ammo_low(), "1 de 5 (<= 1,25) e baixa")
	panel.set_ammo(2, 0, false, 5)
	ok(not panel.is_ammo_low(), "2 de 5 nao e baixa")
	ok(_mag_color(panel).is_equal_approx(WeaponPanel.COLOR_TEXT), "voltou a COLOR_TEXT")
	panel.set_ammo(0, 10, false, 0)
	ok(panel.is_ammo_low(), "mag_size 0 com pente vazio: baixa, sem erro")
	panel.set_ammo(1, 10, false, 0)
	ok(not panel.is_ammo_low(), "mag_size 0 com 1 bala: nao baixa")
	_end()


func test_panel_infinite_reserve_shows_the_infinity_sign() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_ammo(3, 0, true, 5)
	eq(panel.get_reserve_text(), "| ∞", "reserva infinita")
	eq(panel.get_mag_text(), "3", "pente continua")
	panel.set_ammo(3, 77, true, 5)
	eq(panel.get_reserve_text(), "| ∞", "o valor da reserva e ignorado na horda")
	panel.set_ammo(3, 77, false, 5)
	eq(panel.get_reserve_text(), "| 77", "sai do infinito: mostra o numero")
	panel.set_ammo(3, 77, true, 5)
	eq(panel.get_reserve_text(), "| ∞", "e volta ao infinito")
	_end()


func test_panel_reload_bar_shows_only_while_reloading() -> void:
	var panel: WeaponPanel = _panel()
	var bar: ProgressBar = panel.get_node("ReloadBar") as ProgressBar
	ok(not bar.visible, "comeca escondida")
	panel.set_reload(true, 0.4)
	ok(bar.visible, "recarregando: visivel")
	near(bar.value, 40.0, 0.01, "valor = progresso x 100")
	panel.set_reload(true, 1.0)
	near(bar.value, 100.0, 0.01, "100%")
	panel.set_reload(true, 0.0)
	ok(bar.visible, "progresso 0 ainda e recarga")
	near(bar.value, 0.0, 0.01, "0%")
	panel.set_reload(false, 0.0)
	ok(not bar.visible, "fim da recarga: some")
	panel.set_reload(true, 7.0)
	ok(bar.value <= 100.0, "progresso fora de 0-1 nao passa de 100")
	_end()


func test_panel_touch_hides_the_chip_keys_and_swaps_the_row_for_cards() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_touch(true)
	eq(panel.get_chip_key_text(0), "", "toque: sem tecla no chip 0")
	eq(panel.get_chip_key_text(1), "", "toque: sem tecla no chip 1")
	ok(not panel.is_row_visible(), "toque: a fileira de chips sai (os cartoes entram)")
	ok(panel.is_cards_visible(), "toque: os cartoes aparecem")
	eq(panel.get_card_count(), 2, "toque: dois cartoes com duas armas")
	ok(not (_chip(panel, 1).get_node("Key") as Label).visible, "o no Key do chip some")
	panel.set_touch(false)
	eq(panel.get_chip_key_text(0), "1", "teclado: tecla 1 de volta")
	eq(panel.get_chip_key_text(1), "2", "teclado: tecla 2 de volta")
	ok(panel.is_row_visible(), "teclado: a fileira volta")
	ok(not panel.is_cards_visible(), "teclado: sem cartoes")
	eq(panel.get_card_count(), 0, "teclado: nenhum cartao")
	panel.set_touch(true)
	panel.set_weapons(Data.get_weapon_ids())
	for i: int in 5:
		eq(panel.get_chip_key_text(i), "", "refazer em modo toque: chip %d sem tecla" % i)
	_end()


func test_panel_touch_cards_follow_the_weapons_the_active_one_and_the_ammo() -> void:
	var panel: WeaponPanel = _panel()
	panel.set_touch(true)
	eq(panel.get_card_weapon_indices(), [0, 1] as Array[int], "duas armas: cartoes na ordem dos slots")
	var cards: Node = panel.get_node("Cards")
	var first: Control = cards.get_child(0) as Control
	var second: Control = cards.get_child(1) as Control
	near(first.modulate.a, 1.0, 0.001, "arma na mao: cartao cheio")
	near(second.modulate.a, WeaponPanel.INACTIVE_ALPHA, 0.001, "a outra: esmaecida")
	panel.set_weapon_ammo(1, 4, 12, false, 4)
	eq(second.get("mag_text"), "4", "pente da arma no bolso")
	eq(second.get("reserve_text"), "| 12", "reserva da arma no bolso")
	panel.set_weapon_ammo(1, 0, 12, false, 4)
	ok(bool(second.get("ammo_low")), "pente vazio: vermelho")
	panel.set_active(1)
	near(first.modulate.a, WeaponPanel.INACTIVE_ALPHA, 0.001, "troca: o primeiro esmaece")
	near(second.modulate.a, 1.0, 0.001, "troca: o segundo fica cheio")
	panel.set_reload(true, 0.5)
	near(float(second.get("reload")), 0.5, 0.001, "a barra de recarga e do cartao da arma na mao")
	near(float(first.get("reload")), -1.0, 0.001, "o outro cartao nao mostra recarga")
	ok(not (panel.get_node("ReloadBar") as Control).visible, "toque: a barra de recarga do teclado fica escondida")
	panel.set_reload(false, 0.0)
	near(float(second.get("reload")), -1.0, 0.001, "fim da recarga")
	# one weapon: a single card
	panel.set_weapons([Ids.W_RIFLE_308] as Array[StringName])
	eq(panel.get_card_count(), 1, "uma arma: um cartao so")
	# the horde: the weapon in hand and the next one in the cycle
	panel.set_weapons(Data.get_weapon_ids())
	eq(panel.get_card_weapon_indices(), [0, 1] as Array[int], "horda: arma 1 e a proxima")
	panel.set_active(4)
	eq(panel.get_card_weapon_indices(), [4, 0] as Array[int], "horda: a ultima e a primeira (volta ao ciclo)")
	eq(panel.get_card_count(), 2, "horda: no maximo dois cartoes")
	_end()


func test_panel_nothing_is_clickable() -> void:
	var panel: WeaponPanel = _panel(Data.get_weapon_ids())
	panel.set_reload(true, 0.5)
	var bad: Array[String] = []
	var stack: Array[Node] = [panel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var control: Control = node as Control
		if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad.append(str(control.get_path_to(panel)) + "/" + control.name)
		stack.append_array(node.get_children())
	eq(bad, [] as Array[String], "todo Control com mouse_filter IGNORE")
	_end()


func test_panel_five_weapons_with_big_numbers_keep_the_content_width() -> void:
	var panel: WeaponPanel = _panel(Data.get_weapon_ids())
	panel.set_active(3)   # the longest name: ".30-06 semiautomatico"
	panel.set_ammo(10, 999, false, 10)
	panel.set_reload(true, 0.5)
	await frames(2)
	near(panel.get_combined_minimum_size().x, WeaponPanel.CONTENT_W_PX, 0.5, "5 chips + numeros grandes: 224 px")
	near(panel.custom_minimum_size.x, 224.0, 0.001, "custom_minimum_size.x")
	eq((panel.get_node("Name") as Label).text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "nome com reticencia")
	_end()


func test_panel_content_height_matches_the_doc() -> void:
	var panel: WeaponPanel = _panel(ONE_WEAPON)
	panel.set_ammo(5, 30, false, 10)
	await frames(2)
	var h1: float = panel.get_combined_minimum_size().y
	in_range(h1, 65.0, 85.0, "so nome e linha principal: ~75 px (obtido %s)" % h1)
	panel.set_weapons(Data.get_weapon_ids())
	await frames(2)
	var h2: float = panel.get_combined_minimum_size().y
	in_range(h2, 97.0, 117.0, "com fileira: ~107 px (obtido %s)" % h2)
	panel.set_reload(true, 0.5)
	await frames(2)
	var h3: float = panel.get_combined_minimum_size().y
	in_range(h3, 107.0, 127.0, "com fileira e recarga: ~117 px (obtido %s)" % h3)
	_end()


# --------------------------------------------------------------------------------------------
# HealthStrip on its own (no Hud)
# --------------------------------------------------------------------------------------------

func _strip() -> HealthStrip:
	InputSetup.set_touch_override("off")
	var strip: HealthStrip = HealthStrip.new()
	track(strip)
	return strip


func _is_color(strip: HealthStrip, expected: Color) -> bool:
	return strip.get_fill_color().is_equal_approx(expected)


func test_strip_constants_and_defaults() -> void:
	near(HealthStrip.HEIGHT_PX, 28.0, 0.0001, "HEIGHT_PX = 28")
	near(HealthStrip.WIDTH_PX, 400.0, 0.0001, "WIDTH_PX = 400")
	near(HealthStrip.TOUCH_WIDTH_PX, 342.0, 0.0001, "TOUCH_WIDTH_PX = 342 (dois cartoes de 167 e o vao)")
	var strip: HealthStrip = _strip()
	near(strip.get_fill_pct(), 100.0, 0.01, "comeca cheia")
	ok(_is_color(strip, HealthStrip.COLOR_GOOD), "comeca verde")
	ok(not strip.has_vest(), "comeca sem colete")
	ok(not (strip.get_node("Vest") as Control).visible, "Vest escondido")
	_end()


func test_strip_full_health_is_green() -> void:
	var strip: HealthStrip = _strip()
	strip.set_health(100.0, 100.0)
	eq(strip.get_value_text(), "100", "numero")
	near(strip.get_fill_pct(), 100.0, 0.01, "100%")
	ok(_is_color(strip, HealthStrip.COLOR_GOOD), "verde")
	_end()


func test_strip_colour_thresholds_are_exclusive() -> void:
	var strip: HealthStrip = _strip()
	strip.set_health(51.0, 100.0)
	ok(_is_color(strip, HealthStrip.COLOR_GOOD), "51: verde")
	strip.set_health(50.0, 100.0)
	ok(_is_color(strip, HealthStrip.COLOR_WARN), "50: ambar (50 nao e > 50)")
	strip.set_health(31.0, 100.0)
	ok(_is_color(strip, HealthStrip.COLOR_WARN), "31: ambar")
	strip.set_health(30.0, 100.0)
	ok(_is_color(strip, HealthStrip.COLOR_DANGER), "30: vermelha (30 nao e > 30)")
	strip.set_health(1.0, 100.0)
	ok(_is_color(strip, HealthStrip.COLOR_DANGER), "1: vermelha")
	strip.set_health(100.0, 100.0)
	ok(_is_color(strip, HealthStrip.COLOR_GOOD), "cura: volta a verde")
	_end()


func test_strip_colour_follows_the_fraction_not_the_number() -> void:
	var strip: HealthStrip = _strip()
	strip.set_health(120.0, 200.0)
	ok(_is_color(strip, HealthStrip.COLOR_GOOD), "120 de 200 (60%): verde")
	strip.set_health(100.0, 200.0)
	ok(_is_color(strip, HealthStrip.COLOR_WARN), "100 de 200 (50%): ambar")
	strip.set_health(60.0, 200.0)
	ok(_is_color(strip, HealthStrip.COLOR_DANGER), "60 de 200 (30%): vermelha")
	near(strip.get_fill_pct(), 30.0, 0.01, "30%")
	eq(strip.get_value_text(), "60", "numero e o hp, nao a fracao")
	_end()


func test_strip_number_is_the_ceiling() -> void:
	var strip: HealthStrip = _strip()
	strip.set_health(0.4, 100.0)
	eq(strip.get_value_text(), "1", "0,4 -> 1")
	strip.set_health(37.2, 100.0)
	eq(strip.get_value_text(), "38", "37,2 -> 38")
	strip.set_health(37.0, 100.0)
	eq(strip.get_value_text(), "37", "37 -> 37")
	strip.set_health(0.0, 100.0)
	eq(strip.get_value_text(), "0", "0 -> 0")
	near(strip.get_fill_pct(), 0.0, 0.01, "0%")
	ok(_is_color(strip, HealthStrip.COLOR_DANGER), "0: vermelha")
	_end()


func test_strip_zero_max_health_does_not_divide_by_zero() -> void:
	var strip: HealthStrip = _strip()
	strip.set_health(0.0, 0.0)
	eq(strip.get_value_text(), "0", "0 de 0")
	near(strip.get_fill_pct(), 0.0, 0.01, "0 de 0: barra vazia")
	strip.set_health(10.0, 0.0)
	eq(strip.get_value_text(), "10", "10 de 0: o numero")
	ok(strip.get_fill_pct() >= 0.0 and strip.get_fill_pct() <= 100.0, "barra dentro de 0-100")
	strip.set_health(10.0, -5.0)
	ok(strip.get_fill_pct() >= 0.0 and strip.get_fill_pct() <= 100.0, "max negativo: barra dentro de 0-100")
	_end()


func test_strip_over_full_health_stays_inside_the_bar() -> void:
	var strip: HealthStrip = _strip()
	strip.set_health(150.0, 100.0)
	ok(strip.get_fill_pct() <= 100.0, "acima do maximo nao passa de 100")
	eq(strip.get_value_text(), "150", "o numero mostra o hp")
	ok(_is_color(strip, HealthStrip.COLOR_GOOD), "verde")
	_end()


func test_strip_vest_toggles_and_keeps_the_height() -> void:
	var strip: HealthStrip = _strip()
	await frames(2)
	near(strip.size.y, HealthStrip.HEIGHT_PX, 0.01, "altura sem colete")
	strip.set_vest(true)
	await frames(2)
	ok(strip.has_vest(), "has_vest")
	ok((strip.get_node("Vest") as Control).visible, "Vest visivel")
	eq((strip.get_node("Vest/Text") as Label).text, "Colete", "texto do colete")
	near(strip.size.y, HealthStrip.HEIGHT_PX, 0.01, "altura com colete")
	near(strip.get_combined_minimum_size().y, HealthStrip.HEIGHT_PX, 0.01, "altura minima com colete")
	strip.set_health(1000.0, 1000.0)
	await frames(2)
	near(strip.size.y, HealthStrip.HEIGHT_PX, 0.01, "altura com colete e 4 digitos")
	strip.set_vest(false)
	ok(not strip.has_vest(), "sem colete")
	ok(not (strip.get_node("Vest") as Control).visible, "Vest escondido")
	_end()


func test_strip_touch_narrows_the_width_and_back() -> void:
	var strip: HealthStrip = _strip()
	await frames(2)
	near(strip.size.x, 400.0, 0.01, "teclado: 400 px")
	strip.set_touch(true)
	await frames(2)
	near(strip.custom_minimum_size.x, 342.0, 0.01, "toque: minimo 342")
	near(strip.size.x, 342.0, 0.01, "toque: largura 342")
	near(strip.size.y, HealthStrip.HEIGHT_PX, 0.01, "toque: mesma altura")
	strip.set_touch_width(300.0)
	await frames(2)
	near(strip.size.x, 300.0, 0.01, "toque: a largura que o Hud passa")
	strip.set_touch(false)
	await frames(2)
	near(strip.size.x, 400.0, 0.01, "teclado de novo: 400 px")
	_end()


func test_strip_children_sit_side_by_side_without_overlap() -> void:
	for touch: bool in [false, true]:
		var strip: HealthStrip = _strip()
		strip.set_touch(touch)
		strip.set_vest(true)
		strip.set_vest_reduction(0.35)
		strip.set_health(100.0, 100.0)
		await frames(2)
		var vest: Control = strip.get_node("Vest") as Control
		var bar: Control = strip.get_node("Bar") as Control
		var value: Control = strip.get_node("Value") as Control
		var tag: String = "toque" if touch else "teclado"
		if touch:
			ok(vest.position.x + vest.size.x <= -HealthStrip.VEST_CHIP_GAP_PX + 0.01, "toque: o colete e um chip a esquerda da faixa")
			ok(bar.position.x >= HealthStrip.PAD_X_PX - 0.01, "toque: a barra comeca na margem (o colete saiu)")
			near(strip.get_chip_rect().size.x, HealthStrip.VEST_CHIP_W_PX, 0.01, "toque: largura do chip")
			ok(strip.get_chip_rect().encloses(Rect2(vest.position, vest.size)), "toque: icone e texto dentro do chip")
		else:
			ok(vest.position.x >= HealthStrip.PAD_X_PX - 0.01, "%s: colete respeita a margem" % tag)
			ok(bar.position.x >= vest.position.x + vest.size.x, "%s: barra depois do colete" % tag)
		ok(bar.position.x + bar.size.x <= value.position.x, "%s: barra antes do numero" % tag)
		ok(value.position.x + value.size.x <= strip.size.x - HealthStrip.PAD_X_PX + 0.01, "%s: numero respeita a margem" % tag)
		ok(bar.size.x > 60.0, "%s: sobra largura util na barra (%s)" % [tag, bar.size.x])
		near(bar.size.y, HealthStrip.BAR_HEIGHT_PX, 0.01, "%s: altura da barra" % tag)
		ok(vest.position.y >= 0.0 and vest.position.y + vest.size.y <= strip.size.y + 0.01, "%s: colete dentro da faixa" % tag)
	_end()


func test_strip_vest_text_is_the_reduction_on_touch_and_the_word_on_keyboard() -> void:
	var strip: HealthStrip = _strip()
	strip.set_vest(true)
	strip.set_vest_reduction(0.35)
	eq(strip.get_vest_text(), "Colete", "teclado: a palavra")
	strip.set_touch(true)
	eq(strip.get_vest_text(), "35%", "toque: a reducao do colete")
	strip.set_vest_reduction(0.0)
	eq(strip.get_vest_text(), "Colete", "toque sem reducao: a palavra")
	strip.set_vest_reduction(0.5)
	strip.set_touch(false)
	eq(strip.get_vest_text(), "Colete", "de volta ao teclado: a palavra")
	_end()


func test_strip_nothing_is_clickable() -> void:
	var strip: HealthStrip = _strip()
	strip.set_vest(true)
	var bad: Array[String] = []
	var stack: Array[Node] = [strip]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var control: Control = node as Control
		if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad.append(control.name)
		stack.append_array(node.get_children())
	eq(bad, [] as Array[String], "todo Control com mouse_filter IGNORE")
	_end()


# --------------------------------------------------------------------------------------------
# Hud wiring: a real Player, a fake world
# --------------------------------------------------------------------------------------------

func _spawn(weapon_ids: Array[StringName] = TWO_WEAPONS, item_ids: Array[StringName] = [] as Array[StringName],
		horde: bool = false) -> Hud:
	InputSetup.set_touch_override("off")
	fresh_profile()
	var world: FakeWorld = FakeWorld.new()
	world.horde = horde
	track(world)
	var player: Player = (load(ScenePaths.PLAYER) as PackedScene).instantiate() as Player
	world.player = player
	world.add_child(player)
	player.global_position = Vector3.ZERO
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE if horde else Ids.MODE_CONTRACT)
	req.weapon_ids = weapon_ids
	req.item_ids = item_ids
	if item_ids.has(Ids.I_MEDKIT):
		req.item_counts = {Ids.I_MEDKIT: 1}
	player.setup(req, world)
	for child: Node in player.get_children():
		if child is Hud:
			await frames(FRAME_SETTLE)
			return child as Hud
	fail("o Player nao criou o Hud")
	return null


func _player_of(hud: Hud) -> Player:
	return hud.get("_player") as Player


func _frame_of(hud: Hud) -> PanelContainer:
	return hud.get("_weapon_frame") as PanelContainer


func _panel_of(hud: Hud) -> WeaponPanel:
	return hud.get("_weapon_panel") as WeaponPanel


func _strip_of(hud: Hud) -> HealthStrip:
	return hud.get("_health") as HealthStrip


func _rect_of(c: Control) -> Rect2:
	return Rect2(c.global_position, c.size)


func test_hud_bind_feeds_the_panel_from_the_player() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var panel: WeaponPanel = _panel_of(hud)
	eq(player.get_weapon_ids(), TWO_WEAPONS, "Player.get_weapon_ids na ordem do loadout")
	eq(panel.get_weapon_ids(), player.get_weapon_ids(), "painel = armas do Player")
	eq(panel.get_active_index(), player.get_weapon_slot(), "arma ativa = slot do Player")
	eq(panel.get_active_index(), 0, "comeca na arma 0")
	eq(panel.get_mag_text(), str(player.get_ammo_in_mag()), "pente")
	eq(panel.get_reserve_text(), "| %d" % player.get_ammo_reserve(), "reserva")
	ok(panel.is_row_visible(), "2 armas: fileira visivel")
	ok(panel.get_parent() != null and panel.get_parent() == _frame_of(hud), "o painel vive dentro do WeaponFrame")
	eq(_frame_of(hud).name, &"WeaponFrame", "nome do quadro")
	eq(_strip_of(hud).name, &"HealthStrip", "nome da faixa")
	_end()


func test_hud_player_get_weapon_ids_is_a_copy_in_slot_order() -> void:
	var hud: Hud = await _spawn([SHOTGUN, CARBINE] as Array[StringName])
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var ids: Array[StringName] = player.get_weapon_ids()
	eq(ids, [SHOTGUN, CARBINE] as Array[StringName], "ordem dos slots = ordem do pedido")
	eq(player.get_weapon_count(), ids.size(), "get_weapon_count igual ao tamanho")
	ids.clear()
	eq(player.get_weapon_ids().size(), 2, "alterar a copia nao muda o Player")
	eq(_panel_of(hud).get_name_text(), SHOTGUN_NAME, "o slot 0 e a espingarda")
	_end()


func test_hud_weapon_switch_moves_the_panel() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var panel: WeaponPanel = _panel_of(hud)
	player.bot_select_weapon(1)
	await frames(2)
	eq(player.get_weapon_slot(), 1, "o Player trocou")
	eq(panel.get_active_index(), 1, "o painel acompanha")
	eq(panel.get_name_text(), SHOTGUN_NAME, "nome")
	eq(panel.get_mag_text(), str(player.get_ammo_in_mag()), "pente da arma nova")
	eq(panel.get_reserve_text(), "| %d" % player.get_ammo_reserve(), "reserva da arma nova")
	eq(panel.get_portrait_path(), ScenePaths.weapon_art(SHOTGUN), "retrato")
	player.bot_select_weapon(0)
	await frames(2)
	eq(panel.get_active_index(), 0, "volta para 0")
	eq(panel.get_name_text(), "Carabina .22", "nome da carabina")
	player.bot_select_weapon(7)   # out of range: the player ignores it and the panel keeps
	await frames(2)
	eq(panel.get_active_index(), 0, "slot invalido: nada muda")
	_end()


func test_hud_one_weapon_has_no_row() -> void:
	var hud: Hud = await _spawn(ONE_WEAPON)
	if hud == null:
		_end()
		return
	ok(not _panel_of(hud).is_row_visible(), "uma arma no loadout: sem fileira")
	eq(_panel_of(hud).get_weapon_ids().size(), 1, "uma arma")
	_end()


func test_hud_ammo_follows_the_weapon() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var panel: WeaponPanel = _panel_of(hud)
	var weapon: Weapon = player.get_weapon()
	var mag_size: int = int(weapon.def.get("mag_size", 1))
	eq(panel.get_mag_text(), str(mag_size), "pente cheio no inicio")
	ok(not panel.is_ammo_low(), "cheio nao e baixa")
	weapon.ammo_in_mag = 2
	weapon.ammo_reserve = 17
	await frames(2)
	eq(panel.get_mag_text(), "2", "2 no pente")
	eq(panel.get_reserve_text(), "| 17", "17 de reserva")
	ok(panel.is_ammo_low(), "2 de %d: baixa" % mag_size)
	weapon.ammo_in_mag = 0
	weapon.ammo_reserve = 0
	await frames(2)
	eq(panel.get_mag_text(), "0", "pente vazio")
	eq(panel.get_reserve_text(), "| 0", "sem reserva")
	ok(panel.is_ammo_low(), "vazio: baixa")
	_end()


func test_hud_a_real_shot_and_a_reload_reach_the_panel() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var panel: WeaponPanel = _panel_of(hud)
	var bar: ProgressBar = panel.get_node("ReloadBar") as ProgressBar
	ok(not bar.visible, "sem recarga: barra escondida")
	await wait_s(0.6)   # let the draw time pass
	var before: int = player.get_ammo_in_mag()
	var fired: bool = player.bot_fire()
	await frames(2)
	ok(fired, "o tiro saiu")
	if fired:
		eq(panel.get_mag_text(), str(before - 1), "o pente desceu uma bala")
		eq(panel.get_mag_text(), str(player.get_ammo_in_mag()), "painel = Player")
	player.bot_reload()
	await frames(3)
	if player.is_reloading():
		ok(bar.visible, "recarregando: barra visivel")
		ok(bar.value >= 0.0 and bar.value <= 100.0, "valor entre 0 e 100")
		await wait_s(float(player.get_weapon().def.get("reload_s", 2.0)) + 0.5)
		ok(not player.is_reloading(), "terminou de recarregar")
		ok(not bar.visible, "fim da recarga: barra some")
		eq(panel.get_mag_text(), str(player.get_ammo_in_mag()), "pente cheio de novo no painel")
	else:
		fail("o Player nao entrou em recarga depois de um tiro")
	_end()


func test_hud_health_follows_the_player() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var strip: HealthStrip = _strip_of(hud)
	var max_hp: float = player.get_max_health()
	eq(strip.get_value_text(), str(ceili(player.get_health())), "vida cheia no inicio")
	ok(strip.get_fill_color().is_equal_approx(HealthStrip.COLOR_GOOD), "verde cheia")
	player.debug_set_health(37.0)
	await frames(2)
	eq(strip.get_value_text(), "37", "37 na faixa")
	near(strip.get_fill_pct(), 37.0 / max_hp * 100.0, 0.01, "barra a 37%")
	ok(strip.get_fill_color().is_equal_approx(HealthStrip.COLOR_WARN), "37: ambar")
	player.debug_set_health(20.0)
	await frames(2)
	eq(strip.get_value_text(), "20", "20 na faixa")
	ok(strip.get_fill_color().is_equal_approx(HealthStrip.COLOR_DANGER), "20: vermelha")
	player.debug_set_health(max_hp)
	await frames(2)
	ok(strip.get_fill_color().is_equal_approx(HealthStrip.COLOR_GOOD), "cheia de novo: verde")
	_end()


func test_player_debug_set_health_clamps_and_never_kills() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var max_hp: float = player.get_max_health()
	player.debug_set_health(0.0)
	near(player.get_health(), 1.0, 0.0001, "0 vira 1")
	ok(player.is_alive(), "continua vivo")
	player.debug_set_health(-50.0)
	near(player.get_health(), 1.0, 0.0001, "negativo vira 1")
	player.debug_set_health(max_hp * 3.0)
	near(player.get_health(), max_hp, 0.0001, "acima do maximo vira o maximo")
	player.debug_set_health(42.5)
	near(player.get_health(), 42.5, 0.0001, "valor no meio passa direto")
	_end()


func test_hud_vest_shows_only_with_the_vest_equipped() -> void:
	var with_vest: Hud = await _spawn(TWO_WEAPONS, [Ids.I_LEATHER_VEST] as Array[StringName])
	if with_vest == null:
		_end()
		return
	ok(_strip_of(with_vest).has_vest(), "com colete no loadout: has_vest")
	ok((_strip_of(with_vest).get_node("Vest") as Control).visible, "Vest visivel")
	var without: Hud = await _spawn(TWO_WEAPONS, [Ids.I_MEDKIT] as Array[StringName])
	if without == null:
		_end()
		return
	ok(not _strip_of(without).has_vest(), "sem colete: nao tem")
	_end()


func test_hud_horde_has_all_weapons_and_an_infinite_reserve() -> void:
	var hud: Hud = await _spawn(ONE_WEAPON, [] as Array[StringName], true)
	if hud == null:
		_end()
		return
	var player: Player = _player_of(hud)
	var panel: WeaponPanel = _panel_of(hud)
	ok(player.has_infinite_reserve(), "horda: reserva infinita no Player")
	eq(player.get_weapon_ids(), Data.get_weapon_ids(), "horda: todas as armas, na ordem do arquivo")
	eq(panel.get_weapon_ids().size(), 5, "5 chips")
	ok(panel.is_row_visible(), "fileira visivel")
	eq(panel.get_reserve_text(), "| ∞", "reserva infinita")
	eq(panel.get_mag_text(), str(player.get_ammo_in_mag()), "pente")
	player.bot_select_weapon(3)
	await frames(2)
	eq(panel.get_active_index(), 3, "slot 3")
	eq(panel.get_reserve_text(), "| ∞", "continua infinita na outra arma")
	for n: int in range(1, 6):
		eq(panel.get_chip_key_text(n - 1), str(n), "tecla %d" % n)
	_end()


func test_hud_contract_reserve_is_a_number() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var panel: WeaponPanel = _panel_of(hud)
	ok(not panel.get_reserve_text().contains("∞"), "contrato: sem infinito")
	ok(panel.get_reserve_text().begins_with("| "), "contrato: '| N'")
	_end()


func test_hud_spectator_hides_the_weapon_frame_and_keeps_the_health() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var frame: PanelContainer = _frame_of(hud)
	var strip: HealthStrip = _strip_of(hud)
	ok(frame.visible and strip.visible, "comeca tudo visivel")
	GameEvents.spectate_changed.emit(1)
	ok(not frame.visible, "espectador: WeaponFrame some")
	ok(strip.visible, "espectador: a faixa de vida fica")
	GameEvents.spectate_changed.emit(Hud.NO_SLOT)
	ok(frame.visible, "saiu do espectador: WeaponFrame volta")
	ok(strip.visible, "faixa continua")
	_end()


func test_hud_fall_and_end_of_hunt_hide_nothing_of_the_weapon_or_health() -> void:
	var hud: Hud = await _spawn()
	if hud == null:
		_end()
		return
	var frame: PanelContainer = _frame_of(hud)
	var strip: HealthStrip = _strip_of(hud)
	GameEvents.player_died.emit()
	ok(frame.visible, "queda sem espectador: WeaponFrame fica")
	ok(strip.visible, "queda sem espectador: faixa fica")
	hud.on_hunt_ended()
	ok(frame.visible, "fim da cacada: WeaponFrame fica")
	ok(strip.visible, "fim da cacada: faixa fica")
	_end()


func test_hud_touch_layout_moves_the_frame_and_narrows_the_strip() -> void:
	var hud: Hud = await _spawn(Data.get_weapon_ids())
	if hud == null:
		_end()
		return
	var frame: PanelContainer = _frame_of(hud)
	var strip: HealthStrip = _strip_of(hud)
	var panel: WeaponPanel = _panel_of(hud)
	# keyboard / mouse
	near(strip.custom_minimum_size.x, 400.0, 0.01, "teclado: faixa 400")
	near(frame.anchor_left, 1.0, 0.0001, "teclado: quadro ancorado a direita")
	near(frame.offset_left, -float(Hud.MARGIN_PX), 0.0001, "teclado: margem direita")
	near(frame.offset_bottom, -float(Hud.MARGIN_PX), 0.0001, "teclado: margem de baixo")
	eq(panel.get_chip_key_text(0), "1", "teclado: tecla no chip")
	# touch (HF7): two weapon cards over a wide health bar, bottom centre
	InputSetup.set_touch_override("on")
	await frames(2)
	var touch: TouchControls = hud.get("_touch") as TouchControls
	var block: Dictionary = touch.get_bottom_block()
	var card_w: float = float(block["card_w"])
	var total_w: float = card_w * 2.0 + float(WeaponPanel.CARD_GAP_PX)
	near(strip.custom_minimum_size.x, total_w, 0.01, "toque: faixa com a largura dos dois cartoes")
	near(strip.size.x, total_w, 0.01, "toque: largura real")
	near(frame.anchor_left, 0.0, 0.0001, "toque: quadro ancorado pela esquerda (posicao absoluta)")
	near(frame.offset_left, float(block["center_x"]) - total_w * 0.5, 0.01, "toque: quadro centrado no bloco")
	near(frame.offset_right - frame.offset_left, total_w, 0.01, "toque: quadro tem a largura dos cartoes")
	near(frame.offset_bottom, -(Hud.TOUCH_HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX + Hud.TOUCH_CARDS_GAP_PX), 0.01, "toque: quadro 6 px acima da faixa")
	near(frame.offset_bottom - frame.offset_top, WeaponPanel.CARD_H_PX, 0.01, "toque: altura do cartao")
	ok(frame.get_theme_stylebox(&"panel") is StyleBoxEmpty, "toque: o quadro perde o fundo (cada cartao tem o seu)")
	near(strip.offset_bottom, -Hud.TOUCH_HEALTH_BOTTOM_PX, 0.01, "toque: faixa a 8 px da borda")
	eq(panel.get_chip_key_text(0), "", "toque: sem tecla no chip")
	ok(not panel.is_row_visible(), "toque: sem fileira de chips")
	eq(panel.get_card_count(), 2, "toque: dois cartoes")
	var rects: Array[Rect2] = touch.get_weapon_card_rects()
	eq(rects.size(), 2, "toque: o TouchControls recebeu os dois retangulos")
	if rects.size() == 2:
		near(rects[0].size.x, card_w, 0.01, "retangulo 1: largura")
		near(rects[1].position.x - rects[0].end.x, float(WeaponPanel.CARD_GAP_PX), 0.01, "retangulos separados pelo vao")
		near(rects[0].end.y, hud.get("_root").size.y - (Hud.TOUCH_HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX + Hud.TOUCH_CARDS_GAP_PX), 0.5,
			"retangulo: acima da faixa de vida")
	# back
	InputSetup.set_touch_override("off")
	await frames(2)
	near(strip.custom_minimum_size.x, 400.0, 0.01, "de volta: faixa 400")
	near(frame.anchor_left, 1.0, 0.0001, "de volta: quadro a direita")
	near(frame.offset_left, -float(Hud.MARGIN_PX), 0.0001, "de volta: offset_left")
	ok(not (frame.get_theme_stylebox(&"panel") is StyleBoxEmpty), "de volta: o fundo do quadro volta")
	eq(touch.get_weapon_card_rects().size(), 0, "de volta: nenhum cartao no TouchControls")
	eq(frame.grow_horizontal, Control.GROW_DIRECTION_BEGIN, "de volta: cresce para a esquerda")
	eq(panel.get_chip_key_text(0), "1", "de volta: tecla no chip")
	_end()


func test_hud_bottom_stack_offsets_and_no_overlap() -> void:
	var hud: Hud = await _spawn(Data.get_weapon_ids())
	if hud == null:
		_end()
		return
	var strip: HealthStrip = _strip_of(hud)
	var quickbar: Quickbar = hud.get("_quickbar") as Quickbar
	var root: Control = hud.get("_root") as Control
	near(Hud.HEALTH_BOTTOM_PX, 14.0, 0.0001, "HEALTH_BOTTOM_PX")
	near(Hud.BOTTOM_STACK_GAP_PX, 8.0, 0.0001, "BOTTOM_STACK_GAP_PX")
	near(Hud.QUICKBAR_BOTTOM_PX, 50.0, 0.0001, "QUICKBAR_BOTTOM_PX = 50")
	near(Hud.TOUCH_HEALTH_BOTTOM_PX, 8.0, 0.0001, "TOUCH_HEALTH_BOTTOM_PX = 8")
	near(Hud.TOUCH_CARDS_GAP_PX, 6.0, 0.0001, "TOUCH_CARDS_GAP_PX = 6")
	near(quickbar.offset_bottom, -50.0, 0.0001, "Quickbar.offset_bottom = -50")
	near(quickbar.offset_top, -50.0 - Quickbar.SLOT_SIZE_PX, 0.0001, "Quickbar.offset_top")
	near(strip.offset_bottom, -14.0, 0.0001, "HealthStrip.offset_bottom = -14")
	near(strip.offset_top, -42.0, 0.0001, "HealthStrip.offset_top = -42")
	near(strip.anchor_left, 0.5, 0.0001, "HealthStrip ancorada ao centro")
	near(strip.anchor_top, 1.0, 0.0001, "HealthStrip ancorada embaixo")
	var root_rect: Rect2 = Rect2(Vector2.ZERO, root.size)
	var strip_rect: Rect2 = _rect_of(strip)
	near(strip_rect.size.y, 28.0, 0.01, "faixa: 28 px de altura")
	near(strip_rect.end.y, root.size.y - 14.0, 0.5, "faixa termina 14 px acima da base")
	near(strip_rect.get_center().x, root.size.x * 0.5, 0.5, "faixa centrada")
	ok(root_rect.encloses(strip_rect), "faixa dentro da tela")
	if quickbar.visible:
		var quick_rect: Rect2 = _rect_of(quickbar)
		ok(quick_rect.end.y <= strip_rect.position.y - Hud.BOTTOM_STACK_GAP_PX + 0.5, "barra de itens acima da faixa, com folga")
	# the weapon frame: 5 weapons and a reload, the biggest it gets
	_panel_of(hud).set_reload(true, 0.5)
	await frames(2)
	var frame_rect: Rect2 = _rect_of(_frame_of(hud))
	ok(root_rect.encloses(frame_rect), "teclado: quadro da arma dentro da tela (%s em %s)" % [frame_rect, root_rect])
	ok(not frame_rect.intersects(strip_rect), "teclado: quadro da arma nao cobre a faixa de vida")
	InputSetup.set_touch_override("on")
	await frames(2)
	frame_rect = _rect_of(_frame_of(hud))
	strip_rect = _rect_of(strip)
	ok(root_rect.encloses(frame_rect), "toque: quadro da arma dentro da tela (%s em %s)" % [frame_rect, root_rect])
	ok(not frame_rect.intersects(strip_rect), "toque: quadro da arma nao cobre a faixa de vida")
	var touch_block: Dictionary = (hud.get("_touch") as TouchControls).get_bottom_block()
	near(strip_rect.size.x, float(touch_block["card_w"]) * 2.0 + float(WeaponPanel.CARD_GAP_PX), 0.5, "toque: faixa da largura dos cartoes")
	near(strip_rect.get_center().x, float(touch_block["center_x"]), 0.5, "toque: faixa centrada no bloco")
	_end()
