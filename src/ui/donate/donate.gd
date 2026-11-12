extends Control
## Voluntary Pix donation screen. Talks only to DonationService.
## It never says a payment was verified: the player donates, receives a redeem code from the developer
## and types it here. Nodes: Package_<id>, %PixCodeText, %CopyButton, %RedeemCodeEdit, %RedeemButton,
## %RedeemStatusLabel, %BackButton.

const COPIED_FEEDBACK_S: float = 2.5
const MSG_NOT_CONFIGURED: String = "A chave Pix do jogo ainda não foi configurada pelo dono do jogo. Por isso nenhum código Pix é exibido: ele não receberia doação nenhuma."
const MSG_DISCLAIMER: String = "Isto é uma doação voluntária para apoiar o jogo. Nada aqui confirma o pagamento sozinho: depois de doar, você recebe um código de resgate e digita abaixo para ganhar o ouro. Ouro é conforto e atalho, não é preciso para vencer."
const MSG_NOT_SECURE: String = "Este resgate é conferido só neste aparelho e não é à prova de fraude."

var _service: DonationService = null
var _selected_id: StringName = &""
var _package_buttons: Dictionary = {}   # StringName -> Button
var _pix_text: LineEdit = null
var _copy: Button = null
var _warning: Label = null
var _summary: Label = null
var _redeem_edit: LineEdit = null
var _redeem_button: Button = null
var _redeem_status: Label = null


func _ready() -> void:
	_service = DonationService.new()
	_service.redeem_finished.connect(_on_redeem_finished)
	var page: Dictionary = UiKit.build_page(self, "Apoie o jogo")
	var body: VBoxContainer = page["body"]

	var scroller: Array = UiKit.scroll_list(12)
	body.add_child(scroller[0])
	var content: VBoxContainer = scroller[1]
	content.add_child(UiKit.label(MSG_DISCLAIMER, "", true))

	content.add_child(UiKit.label("1. Escolha um valor", "HeaderLabel"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for pkg: Dictionary in _service.get_packages():
		var id: StringName = StringName(str(pkg.get("id", "")))
		var b: Button = UiKit.button("%s: R$ %s  =  %s" % [pkg.get("name", id), UiKit.decimal(float(pkg.get("price_brl", 0.0)), 2), UiKit.gold_text(int(pkg.get("gold", 0)))], "SecondaryButton", 72)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.name = "Package_%s" % id
		grid.add_child(b)
		b.pressed.connect(_select.bind(id))
		_package_buttons[id] = b

	content.add_child(UiKit.label("2. Doe pelo Pix copia e cola", "HeaderLabel"))
	_summary = UiKit.muted("")
	content.add_child(_summary)
	_warning = UiKit.label(MSG_NOT_CONFIGURED, "", true)
	_warning.add_theme_color_override("font_color", UiKit.DANGER_COLOR)
	_warning.visible = not _service.is_pix_configured()
	content.add_child(_warning)
	var pix_row: HBoxContainer = HBoxContainer.new()
	pix_row.add_theme_constant_override("separation", 12)
	content.add_child(pix_row)
	_pix_text = LineEdit.new()
	_pix_text.editable = false
	_pix_text.placeholder_text = "Código Pix indisponível" if not _service.is_pix_configured() else "Escolha um valor"
	_pix_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pix_text.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	UiKit.mark(_pix_text, self, "PixCodeText")
	pix_row.add_child(_pix_text)
	_copy = UiKit.button("Copiar", "SecondaryButton")
	_copy.custom_minimum_size.x = 200
	_copy.disabled = true
	UiKit.mark(_copy, self, "CopyButton")
	pix_row.add_child(_copy)
	_copy.pressed.connect(_on_copy)
	var support: String = _service.get_support_text()
	if support != "":
		content.add_child(UiKit.muted(support))

	content.add_child(UiKit.label("3. Digite o código de resgate", "HeaderLabel"))
	var redeem_row: HBoxContainer = HBoxContainer.new()
	redeem_row.add_theme_constant_override("separation", 12)
	content.add_child(redeem_row)
	_redeem_edit = LineEdit.new()
	_redeem_edit.placeholder_text = "JV-0000-XXXXXX-0000"
	_redeem_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_redeem_edit.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	_redeem_edit.text_submitted.connect(func(_t: String) -> void: _on_redeem())
	UiKit.mark(_redeem_edit, self, "RedeemCodeEdit")
	redeem_row.add_child(_redeem_edit)
	_redeem_button = UiKit.button("Resgatar", "PrimaryButton")
	_redeem_button.custom_minimum_size.x = 220
	UiKit.mark(_redeem_button, self, "RedeemButton")
	redeem_row.add_child(_redeem_button)
	_redeem_button.pressed.connect(_on_redeem)
	_redeem_status = UiKit.label("", "", true)
	UiKit.mark(_redeem_status, self, "RedeemStatusLabel")
	content.add_child(_redeem_status)
	if not _service.is_secure():
		content.add_child(UiKit.muted(MSG_NOT_SECURE))

	var footer: HBoxContainer = page["footer"]
	var back: Button = UiKit.button("Voltar", "SecondaryButton")
	back.custom_minimum_size.x = 200
	UiKit.mark(back, self, "BackButton")
	footer.add_child(back)
	back.pressed.connect(func() -> void: Router.goto(ScenePaths.MAIN_MENU))

	var packages: Array[Dictionary] = _service.get_packages()
	if not packages.is_empty():
		_select(StringName(str(packages[0].get("id", ""))))


func _select(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _package_buttons:
		(_package_buttons[key] as Button).button_pressed = key == id
	var pkg: Dictionary = Data.get_gold_package(id)
	_summary.text = "Doação de R$ %s: ao receber o código de resgate, você leva %s." % [UiKit.decimal(float(pkg.get("price_brl", 0.0)), 2), UiKit.gold_text(int(pkg.get("gold", 0)))]
	if _service.is_pix_configured():
		_pix_text.text = _service.get_pix_payload(id)
	else:
		_pix_text.text = ""
	_copy.disabled = _pix_text.text == ""
	_copy.text = "Copiar"


func _on_copy() -> void:
	if _pix_text.text == "":
		return
	DisplayServer.clipboard_set(_pix_text.text)
	_copy.text = "Copiado!"
	get_tree().create_timer(COPIED_FEEDBACK_S).timeout.connect(func() -> void:
		if is_instance_valid(_copy):
			_copy.text = "Copiar")


func _on_redeem() -> void:
	_redeem_button.disabled = true
	_redeem_status.text = "Conferindo o código..."
	_service.redeem(_redeem_edit.text)


func _on_redeem_finished(ok: bool, _gold: int, message: String) -> void:
	_redeem_button.disabled = false
	_redeem_status.text = message
	_redeem_status.add_theme_color_override("font_color", UiKit.MONEY_COLOR if ok else UiKit.DANGER_COLOR)
	if ok:
		_redeem_edit.text = ""
		Sfx.play(&"ui_coin")
	else:
		Sfx.play(&"ui_error")
