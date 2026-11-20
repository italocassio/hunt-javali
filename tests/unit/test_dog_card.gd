extends "res://tests/lib/test_case.gd"
## The HUD dog card (docs/arquitetura.md sections 6.8 and 8.4, contract 1.3, HF3): breed, state in colour,
## health bar and the next action ("E: Pega!" / "E: Volta!" / "Ferido: voltando"), plus the defaults of the
## dog target (HuntWorld.get_dog_target_position = INF) and the minimap / compass fields that carry it.

const STATES_RECALL: Array[StringName] = [Ids.DS_SEEK, Ids.DS_POINT, Ids.DS_BAY, Ids.DS_HOLD, Ids.DS_RETURN]
const STATE_TEXTS: Dictionary = {
	Ids.DS_FOLLOW: "Seguindo", Ids.DS_SEEK: "Procurando", Ids.DS_POINT: "Apontando", Ids.DS_BAY: "Acuando",
	Ids.DS_HOLD: "Segurando", Ids.DS_RETREAT: "Ferido", Ids.DS_RETURN: "Voltando",
}


func _card() -> DogCard:
	InputSetup.set_touch_override("off")
	var card: DogCard = DogCard.new()
	track(card)
	return card


func _state_color(card: DogCard) -> Color:
	return (card.get_node("Info/State") as Label).get_theme_color("font_color")


func _end() -> void:
	InputSetup.set_touch_override("auto")


# --------------------------------------------------------------------------------------------
# Action text per state
# --------------------------------------------------------------------------------------------

func test_follow_offers_the_attack() -> void:
	var card: DogCard = _card()
	card.set_state(Ids.DS_FOLLOW)
	eq(card.get_action_text(), "E: Pega!", "follow -> E: Pega!")
	_end()


func test_every_other_active_state_offers_the_recall() -> void:
	var card: DogCard = _card()
	for state: StringName in STATES_RECALL:
		card.set_state(state)
		eq(card.get_action_text(), "E: Volta!", "%s -> E: Volta!" % state)
	_end()


func test_retreat_says_the_dog_is_hurt_and_dims_the_action() -> void:
	var card: DogCard = _card()
	card.set_state(Ids.DS_RETREAT)
	eq(card.get_action_text(), "Ferido: voltando", "retreat")
	var action: Label = card.get_node("Info/Action") as Label
	near(action.modulate.a, DogCard.DIM_ALPHA, 0.001, "acao apagada em retreat")
	card.set_state(Ids.DS_FOLLOW)
	near(action.modulate.a, 1.0, 0.001, "volta ao normal fora de retreat")
	eq(card.get_action_text(), "E: Pega!", "e a acao volta")
	_end()


func test_initial_card_is_in_follow() -> void:
	var card: DogCard = _card()
	eq(card.get_action_text(), "E: Pega!", "cartao novo: ja em follow")
	eq(card.get_state_text(), "Seguindo", "texto do estado inicial")
	eq(card.get_breed_text(), "Cão", "nome generico sem raca")
	_end()


func test_unknown_state_falls_back_to_the_recall_and_shows_the_raw_id() -> void:
	var card: DogCard = _card()
	card.set_state(&"estado_novo")
	eq(card.get_state_text(), "estado_novo", "id desconhecido aparece como esta")
	eq(card.get_action_text(), "E: Volta!", "qualquer estado que nao e follow/retreat: Volta!")
	card.set_state(&"")
	eq(card.get_state_text(), "", "estado vazio: texto vazio")
	_end()


# --------------------------------------------------------------------------------------------
# State text and colour
# --------------------------------------------------------------------------------------------

func test_state_texts() -> void:
	var card: DogCard = _card()
	for state: StringName in STATE_TEXTS:
		card.set_state(state)
		eq(card.get_state_text(), String(STATE_TEXTS[state]), "texto de %s" % state)
	_end()


func test_state_colours() -> void:
	var card: DogCard = _card()
	for state: StringName in [Ids.DS_POINT, Ids.DS_BAY, Ids.DS_HOLD]:
		card.set_state(state)
		ok(_state_color(card).is_equal_approx(DogCard.COLOR_HIGHLIGHT), "%s em destaque (ambar)" % state)
	card.set_state(Ids.DS_RETREAT)
	ok(_state_color(card).is_equal_approx(DogCard.COLOR_DANGER), "retreat em vermelho")
	for state: StringName in [Ids.DS_FOLLOW, Ids.DS_SEEK, Ids.DS_RETURN]:
		card.set_state(state)
		ok(_state_color(card).is_equal_approx(DogCard.COLOR_TEXT), "%s na cor normal" % state)
	_end()


# --------------------------------------------------------------------------------------------
# Touch
# --------------------------------------------------------------------------------------------

func test_touch_replaces_the_key_with_the_button_name() -> void:
	var card: DogCard = _card()
	card.set_state(Ids.DS_FOLLOW)
	card.set_touch(true)
	eq(card.get_action_text(), "Botão Cão: Pega!", "follow no toque")
	for state: StringName in STATES_RECALL:
		card.set_state(state)
		eq(card.get_action_text(), "Botão Cão: Volta!", "%s no toque" % state)
	card.set_state(Ids.DS_RETREAT)
	eq(card.get_action_text(), "Ferido: voltando", "retreat nao muda no toque")
	card.set_touch(false)
	card.set_state(Ids.DS_FOLLOW)
	eq(card.get_action_text(), "E: Pega!", "de volta ao teclado: E:")
	_end()


func test_touch_toggle_refreshes_the_text_without_a_new_state() -> void:
	var card: DogCard = _card()
	card.set_state(Ids.DS_BAY)
	eq(card.get_action_text(), "E: Volta!", "teclado")
	card.set_touch(true)
	eq(card.get_action_text(), "Botão Cão: Volta!", "set_touch atualiza na hora")
	card.set_touch(true)
	eq(card.get_action_text(), "Botão Cão: Volta!", "idempotente")
	_end()


func test_touch_hides_the_breed_name_but_keeps_its_text() -> void:
	var card: DogCard = _card()
	card.set_breed(&"foxhound")
	var name_label: Label = card.get_node("Info/Name") as Label
	ok(name_label.visible, "teclado: nome visivel")
	card.set_touch(true)
	ok(not name_label.visible, "toque: nome escondido (cartao mais baixo)")
	eq(card.get_breed_text(), "Foxhound Americano", "o texto da raca continua disponivel")
	card.set_touch(false)
	ok(name_label.visible, "teclado de novo: nome volta")
	_end()


func test_action_follows_the_key_label_of_the_input_map() -> void:
	var card: DogCard = _card()
	eq(InputSetup.get_key_label(&"dog_command"), "E", "a tecla do cao e E")
	card.set_state(Ids.DS_FOLLOW)
	ok(card.get_action_text().begins_with(InputSetup.get_key_label(&"dog_command") + ":"), "o prefixo e a letra da acao")
	_end()


# --------------------------------------------------------------------------------------------
# Breed and health
# --------------------------------------------------------------------------------------------

func test_breed_names_come_from_the_data() -> void:
	var card: DogCard = _card()
	var portrait: TextureRect = card.get_node("Portrait") as TextureRect
	for id: StringName in Data.get_dog_ids():
		card.set_breed(id)
		eq(card.get_breed_text(), String(Data.get_dog(id)["name"]), "nome de %s" % id)
		ok(portrait.visible == (portrait.texture != null), "%s: retrato visivel so quando ha textura" % id)
	_end()


func test_unknown_or_empty_breed_keeps_the_generic_card() -> void:
	expect_errors()   # Data.get_dog may log "unknown id" for an id that does not exist
	var card: DogCard = _card()
	var portrait: TextureRect = card.get_node("Portrait") as TextureRect
	card.set_breed(&"")
	eq(card.get_breed_text(), "Cão", "id vazio")
	ok(not portrait.visible, "id vazio: sem retrato")
	card.set_breed(&"caramelo")
	ne(card.get_breed_text(), "Cão", "caramelo tem nome proprio")
	card.set_breed(&"raca_que_nao_existe")
	eq(card.get_breed_text(), "Cão", "raca desconhecida volta ao nome generico")
	ok(not portrait.visible, "raca desconhecida: sem retrato")
	_end()


func test_health_bar_value_and_colour() -> void:
	var card: DogCard = _card()
	var bar: ProgressBar = card.get_node("Info/HealthBar") as ProgressBar
	near(bar.value, 100.0, 0.001, "barra comeca cheia")
	card.set_health_pct(80.0)
	near(bar.value, 80.0, 0.001, "valor 80")
	ok(bar.modulate.is_equal_approx(DogCard.COLOR_GOOD), "acima de 50: verde")
	card.set_health_pct(DogCard.HEALTH_GOOD_PCT)
	ok(bar.modulate.is_equal_approx(DogCard.COLOR_HIGHLIGHT), "exatamente 50: ambar (limite exclusivo)")
	card.set_health_pct(40.0)
	ok(bar.modulate.is_equal_approx(DogCard.COLOR_HIGHLIGHT), "40: ambar")
	card.set_health_pct(DogCard.HEALTH_WARN_PCT)
	ok(bar.modulate.is_equal_approx(DogCard.COLOR_DANGER), "exatamente 30: vermelho (limite exclusivo)")
	card.set_health_pct(0.0)
	near(bar.value, 0.0, 0.001, "valor 0")
	ok(bar.modulate.is_equal_approx(DogCard.COLOR_DANGER), "0: vermelho")
	_end()


func test_health_out_of_range_is_clamped_by_the_bar() -> void:
	var card: DogCard = _card()
	var bar: ProgressBar = card.get_node("Info/HealthBar") as ProgressBar
	card.set_health_pct(150.0)
	ok(bar.value <= bar.max_value, "acima de 100 nao passa do maximo")
	card.set_health_pct(-20.0)
	ok(bar.value >= bar.min_value, "negativo nao passa do minimo")
	ok(bar.modulate.is_equal_approx(DogCard.COLOR_DANGER), "negativo: vermelho")
	_end()


func test_card_ignores_the_mouse() -> void:
	var card: DogCard = _card()
	eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE, "o cartao nao captura toque nem clique")
	for path: String in ["Portrait", "Info", "Info/Name", "Info/State", "Info/HealthBar", "Info/Action"]:
		eq((card.get_node(path) as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignora o mouse" % path)
	_end()


# --------------------------------------------------------------------------------------------
# Dog target: defaults of the world and of the two map widgets
# --------------------------------------------------------------------------------------------

func test_hunt_world_dog_target_is_inf_by_default() -> void:
	var world: HuntWorld = HuntWorld.new()
	track(world)
	eq(world.get_dog_target_position(), Vector3.INF, "sem cao / sem alvo: INF")
	ok(not world.get_dog_target_position().is_finite(), "INF nao e finito (o HUD usa is_finite)")


func test_minimap_dog_target_defaults_to_none_and_draws() -> void:
	var mm: Minimap = Minimap.new()
	track(mm)
	mm.size = Vector2(180.0, 180.0)
	eq(mm.dog_target, Vector3.INF, "sem alvo por padrao")
	mm.update_player(Vector3.ZERO, 0.0)
	mm.dog_position = Vector3(5.0, 0.0, 5.0)
	mm.dog_target = Vector3(0.0, 0.0, -30.0)
	mm.update_player(Vector3.ZERO, 0.0)
	mm.dog_target = Vector3(900.0, 0.0, 900.0)   # far outside the view: the ring sticks to the frame
	mm.update_player(Vector3.ZERO, 0.0)
	await frames(2)
	ok(true, "desenhou com alvo dentro e fora da vista sem erro")


func test_compass_accepts_the_dog_target_mark() -> void:
	var compass: Compass = Compass.new()
	track(compass)
	compass.size = Vector2(480.0, 44.0)
	var marks: Array[Dictionary] = [
		{"pos": Vector3(0.0, 0.0, -30.0), "kind": &"dog_target"},
		{"pos": Vector3(0.0, 0.0, 30.0), "kind": &"dog_target"},   # behind the hunter: pinned to the edge
		{"pos": Vector3(5.0, 0.0, 5.0), "kind": &"dog"},
		{"pos": Vector3(0.0, 0.0, -30.0), "kind": &"boar"},
	]
	compass.update_state(Vector3.ZERO, 0.0, marks)
	await frames(2)
	ok(true, "desenhou a marca dog_target na frente e atras sem erro")
