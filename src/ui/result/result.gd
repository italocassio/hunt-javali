extends Control
## Hunt result, the reward moment: outcome, kill list (type, kg, R$), contract bonus, total, crop %.
## Reads Router.last_result (already credited by Profile.apply_hunt_result, nothing is credited here).
## Nodes: %ContinueButton -> SHOP, %RetryButton -> PREPARATION, %MenuButton -> MAIN_MENU.

const COUNT_UP_S: float = 0.9
const KILL_ROW_HEIGHT: float = 44.0
const VALUE_COLUMN_PX: float = 130.0
const WEIGHT_COLUMN_PX: float = 110.0
const TOTAL_FONT_PX: int = 44

const TITLES: Dictionary = {
	HuntResult.Outcome.VICTORY: "Vitória! Lavoura salva",
	HuntResult.Outcome.DEFEAT_CROP: "Derrota: lavoura destruída",
	HuntResult.Outcome.DEFEAT_DEATH: "Derrota: o caçador caiu",
	HuntResult.Outcome.ABANDONED: "Caçada abandonada",
}
const TIPS: Dictionary = {
	HuntResult.Outcome.DEFEAT_CROP: "Os abates feitos foram pagos. Ataque primeiro o bando que já está comendo, e use a ceva de milho para segurar os outros longe da lavoura.",
	HuntResult.Outcome.DEFEAT_DEATH: "Os abates feitos foram pagos. Macho e cachaço raspam o chão antes de investir: saia da linha da corrida. O colete de couro reduz o dano.",
	HuntResult.Outcome.ABANDONED: "Os abates feitos foram pagos. O bônus do contrato só sai na vitória.",
}
const ZONE_NAMES: Dictionary = {"head": "cabeça", "vital": "vitais", "body": "corpo", "rear": "traseiro", "dog": "cão"}

var _result: HuntResult = null
var _total_label: Label = null


func _ready() -> void:
	_result = Router.last_result
	var title: String = "Resultado da caçada"
	if _result != null:
		title = TITLES.get(_result.outcome, title)
	var page: Dictionary = UiKit.build_page(self, title)
	var body: VBoxContainer = page["body"]
	if _result == null:
		var empty: Label = UiKit.label("Nenhuma caçada para mostrar.", "HeaderLabel")
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.add_child(empty)
	else:
		_build_body(body)
	_build_footer(page["footer"])
	if _result != null and _result.total_money > 0:
		_count_up(_result.total_money)


# --- Body ---

func _build_body(body: VBoxContainer) -> void:
	body.add_child(UiKit.muted(_contract_line()))
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	body.add_child(columns)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(UiKit.label("Abates: %d de %d javalis" % [_result.kills.size(), maxi(_result.boars_total, _result.kills.size())], "HeaderLabel"))
	var scroller: Array = UiKit.scroll_list(6)
	left.add_child(scroller[0])
	var list: VBoxContainer = scroller[1]
	if _result.kills.is_empty():
		list.add_child(UiKit.muted("Nenhum javali abatido desta vez."))
	for kill: KillInfo in _result.kills:
		list.add_child(_build_kill_row(kill))

	var right_scroll: Array = UiKit.scroll_list(10)
	(right_scroll[0] as Control).size_flags_stretch_ratio = 1.0
	columns.add_child(right_scroll[0])
	var right: VBoxContainer = right_scroll[1]
	right.add_child(_build_payment_card())
	right.add_child(_build_stats_card())


func _build_kill_row(kill: KillInfo) -> Control:
	var panel: PanelContainer = UiKit.card()
	panel.custom_minimum_size = Vector2(0, KILL_ROW_HEIGHT)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon: TextureRect = UiKit.icon_rect(&"boar", 32)
	if icon != null:
		row.add_child(icon)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	texts.add_child(UiKit.label(UiKit.boar_name(kill.type_id)))
	var detail: String = _kill_detail(kill)
	if detail != "":
		texts.add_child(UiKit.muted(detail))
	var weight: Label = UiKit.label("%s kg" % UiKit.decimal(kill.weight_kg, 1))
	weight.custom_minimum_size = Vector2(WEIGHT_COLUMN_PX, 0)
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weight.size_flags_vertical = Control.SIZE_FILL
	row.add_child(weight)
	var value: Label = UiKit.label(UiKit.money_text(kill.reward_money), "MoneyLabel")
	value.custom_minimum_size = Vector2(VALUE_COLUMN_PX, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.size_flags_vertical = Control.SIZE_FILL
	row.add_child(value)
	return panel


func _kill_detail(kill: KillInfo) -> String:
	var parts: PackedStringArray = []
	var zone: String = ZONE_NAMES.get(String(kill.killing_zone), "")
	if kill.clean_kill:
		parts.append("Tiro limpo (%s)" % zone if zone != "" else "Tiro limpo")
	elif zone != "":
		parts.append("Acerto final: %s" % zone)
	if kill.one_shot:
		parts.append("um tiro só")
	return "  |  ".join(parts)


func _build_payment_card() -> Control:
	var card: PanelContainer = UiKit.card()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(UiKit.label("Pagamento", "HeaderLabel"))
	box.add_child(_value_row("Abates", UiKit.money_text(_result.money_from_kills)))
	var contract: Dictionary = _contract()
	var bonus_max: int = int(contract.get("bonus_money", 0))
	if _result.is_victory():
		box.add_child(_value_row("Bônus do contrato", UiKit.money_text(_result.contract_bonus)))
		box.add_child(UiKit.muted("Lavoura em %d%% de %s" % [int(roundf(_result.crop_health_pct)), UiKit.money_text(bonus_max)]))
	else:
		box.add_child(_value_row("Bônus do contrato", UiKit.money_text(0)))
		box.add_child(UiKit.muted("Só na vitória (até %s)" % UiKit.money_text(bonus_max)))
	box.add_child(HSeparator.new())
	var total_row: HBoxContainer = HBoxContainer.new()
	var total_caption: Label = UiKit.label("Total recebido", "HeaderLabel")
	total_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_caption.size_flags_vertical = Control.SIZE_FILL
	total_row.add_child(total_caption)
	_total_label = UiKit.label(UiKit.money_text(_result.total_money), "MoneyLabel")
	_total_label.add_theme_font_size_override("font_size", TOTAL_FONT_PX)
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiKit.mark(_total_label, self, "TotalLabel")
	total_row.add_child(_total_label)
	box.add_child(total_row)
	return card


func _build_stats_card() -> Control:
	var card: PanelContainer = UiKit.card()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(_value_row("Lavoura preservada", "%d%%" % int(roundf(clampf(_result.crop_health_pct, 0.0, 100.0)))))
	if _result.shots_fired > 0:
		var pct: int = int(roundf(clampf(100.0 * float(_result.shots_hit) / float(_result.shots_fired), 0.0, 100.0)))
		box.add_child(_value_row("Tiros certeiros", "%d%% (%d tiros)" % [pct, _result.shots_fired]))
	box.add_child(_value_row("Tempo de caçada", _duration_text(_result.duration_s)))
	var heaviest: KillInfo = null
	for kill: KillInfo in _result.kills:
		if heaviest == null or kill.weight_kg > heaviest.weight_kg:
			heaviest = kill
	if heaviest != null:
		box.add_child(_value_row("Maior abate", "%s, %s kg" % [UiKit.boar_name(heaviest.type_id), UiKit.decimal(heaviest.weight_kg, 1)]))
	var progress: String = _progress_text()
	if progress != "":
		box.add_child(HSeparator.new())
		box.add_child(UiKit.label(progress, "", true))
	var goal: String = UiKit.next_purchase_hint()
	if goal != "":
		box.add_child(UiKit.label(goal, "MoneyLabel", true))
	return card


func _value_row(caption: String, value: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left: Label = UiKit.label(caption)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right: Label = UiKit.label(value)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	return row


# --- Footer ---

func _build_footer(footer: HBoxContainer) -> void:
	var victory: bool = _result != null and _result.is_victory()
	var menu: Button = UiKit.button("Menu", "SecondaryButton")
	menu.custom_minimum_size.x = 200
	UiKit.mark(menu, self, "MenuButton")
	footer.add_child(menu)
	menu.pressed.connect(func() -> void: Router.goto(ScenePaths.MAIN_MENU))
	var retry: Button = UiKit.button("Caçar de novo" if victory else "Tentar de novo", "SecondaryButton")
	retry.custom_minimum_size.x = 240
	UiKit.mark(retry, self, "RetryButton")
	footer.add_child(retry)
	retry.pressed.connect(_on_retry)
	footer.add_child(UiKit.spacer())
	var cont: Button = UiKit.button("Continuar para a loja", "PrimaryButton", 80)
	cont.custom_minimum_size.x = 360
	UiKit.mark(cont, self, "ContinueButton")
	footer.add_child(cont)
	cont.pressed.connect(_on_continue)
	cont.grab_focus()


func _on_retry() -> void:
	if _result != null:
		Router.selected_map_id = _result.map_id
		Router.selected_contract_index = _result.contract_index
	Router.goto(ScenePaths.PREPARATION)


func _on_continue() -> void:
	if _result != null:
		Router.selected_map_id = _result.map_id
		# After a win the next hunt is the next contract (if there is one).
		var next: int = _result.contract_index + (1 if _result.is_victory() else 0)
		Router.selected_contract_index = clampi(next, 0, maxi(0, Profile.get_unlocked_contract_count(_result.map_id) - 1))
	Router.goto(ScenePaths.SHOP)


# --- Texts ---

func _contract() -> Dictionary:
	if _result == null or not Data.get_map_ids().has(_result.map_id):
		return {}
	if _result.contract_index < 0 or _result.contract_index >= Data.get_contract_count(_result.map_id):
		return {}
	return Data.get_contract(_result.map_id, _result.contract_index)


func _contract_line() -> String:
	var contract: Dictionary = _contract()
	if contract.is_empty():
		return ""
	var map_name: String = str(Data.get_map(_result.map_id).get("name", _result.map_id))
	return "Contrato %d: %s  |  %s" % [_result.contract_index + 1, contract.get("name", ""), map_name]


func _progress_text() -> String:
	if not _result.is_victory():
		return TIPS.get(_result.outcome, "")
	var count: int = Data.get_contract_count(_result.map_id) if Data.get_map_ids().has(_result.map_id) else 0
	var next: int = _result.contract_index + 1
	if next < count:
		return "Próximo contrato liberado: %d. %s" % [next + 1, Data.get_contract(_result.map_id, next).get("name", "")]
	if count > 0:
		return "Você venceu o último contrato deste mapa. A fazenda está livre dos javalis!"
	return ""


func _duration_text(seconds: float) -> String:
	var total: int = int(roundf(maxf(seconds, 0.0)))
	@warning_ignore("integer_division")
	var minutes: int = total / 60
	if minutes <= 0:
		return "%d s" % total
	return "%d min %02d s" % [minutes, total % 60]


# --- Reward animation ---

func _count_up(total: int) -> void:
	if _total_label == null:
		return
	Sfx.play(&"ui_coin")
	_set_total(0.0)
	var tween: Tween = create_tween()
	tween.tween_method(_set_total, 0.0, float(total), COUNT_UP_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_set_total.bind(float(total)))


func _set_total(value: float) -> void:
	_total_label.text = UiKit.money_text(int(roundf(value)))
