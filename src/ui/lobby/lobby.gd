class_name Lobby
extends Control
## Friends lobby (multiplayer phase F6). docs/multiplayer.md section 6.11.
## Entry:      %NameEdit, %CreateRoomButton, %CodeEdit, %JoinButton, %BackButton.
## Connecting: %StatusLabel, %CancelButton.
## Room:       %RoomCodeLabel, %RoomLinkLabel, %CopyLinkButton, Slot_0..Slot_3 (Swatch, Info/Name, Info/Detail, Role),
##             %MapOption + Contract_<index> (host only), %ContractLabel, %HintLabel, LoadoutPanel
##             (%WeaponSlot0/1, %DogOption, Item_<id>), %ReadyButton (client), %StartButton (host),
##             %ShopButton, %LeaveButton.
## Always:     %MessageLabel (errors).
## All rules live in Net / Profile; this script only reflects state and forwards button presses.

## Router meta key where Boot leaves the room code of an invite link (?sala=CODE).
const INVITE_META: StringName = &"invite_room_code"
const COPIED_FEEDBACK_S: float = 2.0
const _DEFAULT_CODE_LENGTH: int = 5
const _DEFAULT_MAX_PLAYERS: int = 4
const _DEFAULT_NAME_CHARS: int = 12
const _CARD_WIDTH_PX: float = 1000.0
const _SWATCH_PX: float = 28.0

var _code_length: int = _DEFAULT_CODE_LENGTH
var _max_players: int = _DEFAULT_MAX_PLAYERS
var _entry_box: Control = null
var _connecting_box: VBoxContainer = null
var _room_box: HBoxContainer = null
var _entry_footer: HBoxContainer = null
var _room_footer: HBoxContainer = null
var _name_edit: LineEdit = null
var _code_edit: LineEdit = null
var _create: Button = null
var _join: Button = null
var _status: Label = null
var _message: Label = null
var _room_code: Label = null
var _room_link: Label = null
var _copy: Button = null
var _hint: Label = null
var _contract_label: Label = null
var _map_option: OptionButton = null
var _contract_box: VBoxContainer = null
var _contract_buttons: Array[Button] = []
var _contracts_map: StringName = &""
var _ready_button: Button = null
var _start: Button = null
var _slot_rows: Array[HBoxContainer] = []
var _hunt_started: bool = false
var _copy_token: int = 0


func _ready() -> void:
	var net_cfg: Dictionary = Data.get_net()
	_code_length = int(net_cfg.get("room_code_length", _DEFAULT_CODE_LENGTH))
	_max_players = int(net_cfg.get("max_players", _DEFAULT_MAX_PLAYERS))
	var name_chars: int = int(net_cfg.get("name_max_chars", _DEFAULT_NAME_CHARS))

	var page: Dictionary = UiKit.build_page(self, "Jogar com amigos (beta)")
	var body: VBoxContainer = page["body"]
	var footer: HBoxContainer = page["footer"]

	_entry_box = _build_entry(name_chars)
	body.add_child(_entry_box)
	_connecting_box = _build_connecting()
	body.add_child(_connecting_box)
	_room_box = _build_room()
	body.add_child(_room_box)

	_message = UiKit.label("", "", true)
	_message.add_theme_color_override("font_color", UiKit.DANGER_COLOR)
	UiKit.mark(_message, self, "MessageLabel")
	body.add_child(_message)

	_entry_footer = HBoxContainer.new()
	footer.add_child(_entry_footer)
	var back: Button = UiKit.button("Voltar", "SecondaryButton")
	back.custom_minimum_size.x = 200
	UiKit.mark(back, self, "BackButton")
	_entry_footer.add_child(back)
	back.pressed.connect(_on_back)
	_build_room_footer(footer)

	Net.room_state_changed.connect(_on_room_state_changed)
	Net.roster_changed.connect(_refresh_roster)
	Net.room_error.connect(_on_room_error)
	if not Net.is_configured():
		_message.text = "O modo com amigos ainda não foi configurado."
	_refresh()
	_join_from_invite()


## Invite link: Boot read ?sala=CODE and left it in the Router; enter the room without typing.
func _join_from_invite() -> void:
	var code: String = str(Router.get_meta(INVITE_META, ""))
	if code == "":
		return
	Router.remove_meta(INVITE_META)
	if Net.get_room_state() != Net.RoomState.NONE:
		return
	_code_edit.text = code
	_on_code_changed(_code_edit.text)   # the field may have truncated the code (max_length)
	if code.length() != _code_length:
		_message.text = "O link de convite está incompleto. Peça um link novo ao anfitrião."
		return
	_on_join()


# --- Construction ---

func _build_entry(name_chars: int) -> Control:
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	var card: PanelContainer = UiKit.card()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size.x = _CARD_WIDTH_PX
	wrap.add_child(card)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	card.add_child(columns)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	left.add_child(UiKit.label("Seu nome", "HeaderLabel"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = name_chars
	_name_edit.placeholder_text = "Caçador"
	_name_edit.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	_name_edit.text = str(Profile.get_setting("player_name"))
	_name_edit.text_changed.connect(func(text: String) -> void: Profile.set_setting("player_name", text.strip_edges()))
	UiKit.mark(_name_edit, self, "NameEdit")
	left.add_child(_name_edit)
	_create = UiKit.button("Criar sala", "PrimaryButton", 80)
	UiKit.mark(_create, self, "CreateRoomButton")
	left.add_child(_create)
	_create.pressed.connect(_on_create)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	right.add_child(UiKit.label("Ou entre com o código da sala", "HeaderLabel"))
	_code_edit = LineEdit.new()
	_code_edit.max_length = _code_length
	_code_edit.placeholder_text = "CÓDIGO"
	_code_edit.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	_code_edit.text_changed.connect(_on_code_changed)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	UiKit.mark(_code_edit, self, "CodeEdit")
	right.add_child(_code_edit)
	_join = UiKit.button("Entrar", "SecondaryButton", 80)
	UiKit.mark(_join, self, "JoinButton")
	right.add_child(_join)
	_join.pressed.connect(_on_join)
	return wrap


func _build_connecting() -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_status = UiKit.label("Conectando...", "HeaderLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.mark(_status, self, "StatusLabel")
	box.add_child(_status)
	var cancel: Button = UiKit.button("Cancelar", "SecondaryButton", 72)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size.x = 320
	UiKit.mark(cancel, self, "CancelButton")
	box.add_child(cancel)
	cancel.pressed.connect(_on_leave)
	return box


func _build_room() -> HBoxContainer:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)

	# Left: code, players, contract.
	var left_scroll: Array = UiKit.scroll_list(10)
	columns.add_child(left_scroll[0])
	var left: VBoxContainer = left_scroll[1]

	var code_row: HBoxContainer = HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	left.add_child(code_row)
	code_row.add_child(UiKit.label("Sala", "HeaderLabel"))
	_room_code = UiKit.label("", "TitleLabel")
	UiKit.mark(_room_code, self, "RoomCodeLabel")
	code_row.add_child(_room_code)
	code_row.add_child(UiKit.spacer())
	_copy = UiKit.button("Copiar link", "SecondaryButton")
	_copy.custom_minimum_size.x = 240
	UiKit.mark(_copy, self, "CopyLinkButton")
	code_row.add_child(_copy)
	_copy.pressed.connect(_on_copy)
	_room_link = UiKit.muted("")
	UiKit.mark(_room_link, self, "RoomLinkLabel")
	left.add_child(_room_link)

	var players: PanelContainer = UiKit.card()
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	players.add_child(rows)
	for slot: int in _max_players:
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Slot_%d" % slot
		row.add_theme_constant_override("separation", 12)
		var swatch: ColorRect = ColorRect.new()
		swatch.name = "Swatch"
		swatch.custom_minimum_size = Vector2(_SWATCH_PX, _SWATCH_PX)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var info_box: VBoxContainer = VBoxContainer.new()
		info_box.name = "Info"
		info_box.add_theme_constant_override("separation", 0)
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_box)
		var who: Label = UiKit.label("", "")
		who.name = "Name"
		who.clip_text = true
		info_box.add_child(who)
		var detail: Label = UiKit.label("")
		detail.name = "Detail"
		detail.modulate = Color(1, 1, 1, 0.7)
		detail.clip_text = true
		info_box.add_child(detail)
		var role: Label = UiKit.label("")
		role.name = "Role"
		role.custom_minimum_size.x = 130
		role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(role)
		rows.add_child(row)
		_slot_rows.append(row)
	left.add_child(players)

	_hint = UiKit.muted("")
	UiKit.mark(_hint, self, "HintLabel")
	left.add_child(_hint)

	left.add_child(UiKit.label("Mapa e contrato", "HeaderLabel"))
	_contract_label = UiKit.label("", "", true)
	UiKit.mark(_contract_label, self, "ContractLabel")
	left.add_child(_contract_label)
	_map_option = OptionButton.new()
	_map_option.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	_map_option.theme_type_variation = "SecondaryButton"
	if not UiKit.has_global_theme():
		_map_option.add_theme_font_size_override("font_size", 22)
	_map_option.get_popup().add_theme_constant_override("v_separation", 22)
	_map_option.get_popup().add_theme_font_size_override("font_size", 24)
	for map_id: StringName in Data.get_map_ids():
		_map_option.add_item(str(Data.get_map(map_id).get("name", map_id)))
		_map_option.set_item_metadata(_map_option.item_count - 1, map_id)
	UiKit.mark(_map_option, self, "MapOption")
	_map_option.item_selected.connect(_on_map_selected)
	left.add_child(_map_option)
	_contract_box = VBoxContainer.new()
	_contract_box.add_theme_constant_override("separation", 8)
	left.add_child(_contract_box)
	left.add_child(UiKit.muted("Quem cria a sala deve ter o melhor aparelho e conexão. Se o anfitrião sair do jogo, a partida termina para todos."))

	# Right: own loadout.
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(UiKit.label("Seu equipamento", "HeaderLabel"))
	var loadout_scroll: Array = UiKit.scroll_list(10)
	right.add_child(loadout_scroll[0])
	var panel: LoadoutPanel = LoadoutPanel.new()
	loadout_scroll[1].add_child(panel)
	panel.setup(self, "Cães em rede: em breve.")
	return columns


func _build_room_footer(footer: HBoxContainer) -> void:
	_room_footer = HBoxContainer.new()
	_room_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_footer.add_theme_constant_override("separation", 16)
	footer.add_child(_room_footer)
	var leave: Button = UiKit.button("Sair da sala", "SecondaryButton")
	leave.custom_minimum_size.x = 220
	UiKit.mark(leave, self, "LeaveButton")
	_room_footer.add_child(leave)
	leave.pressed.connect(_on_leave)
	var shop: Button = UiKit.button("Loja", "SecondaryButton")
	shop.custom_minimum_size.x = 200
	UiKit.mark(shop, self, "ShopButton")
	_room_footer.add_child(shop)
	shop.pressed.connect(func() -> void: Router.goto(ScenePaths.SHOP))
	_room_footer.add_child(UiKit.spacer())
	_ready_button = UiKit.button("Pronto", "PrimaryButton", 72)
	_ready_button.custom_minimum_size.x = 340
	UiKit.mark(_ready_button, self, "ReadyButton")
	_room_footer.add_child(_ready_button)
	_ready_button.pressed.connect(_on_ready)
	_start = UiKit.button("Iniciar caçada", "PrimaryButton", 72)
	_start.custom_minimum_size.x = 340
	UiKit.mark(_start, self, "StartButton")
	_room_footer.add_child(_start)
	_start.pressed.connect(_on_start)


# --- Reflecting Net state ---

func _refresh() -> void:
	var state: int = Net.get_room_state()
	var in_room: bool = state >= Net.RoomState.LOBBY
	var connecting: bool = state == Net.RoomState.CONNECTING
	_entry_box.visible = not in_room and not connecting
	_entry_footer.visible = not in_room
	_connecting_box.visible = connecting
	_room_box.visible = in_room
	_room_footer.visible = in_room
	_create.disabled = not Net.is_configured()
	_on_code_changed(_code_edit.text)
	if in_room:
		_room_code.text = Net.get_room_code()
		var link: String = Net.get_room_link()
		_room_link.text = link
		_room_link.visible = link != ""
		_refresh_roster()


func _refresh_roster() -> void:
	if not _room_box.visible:
		return
	var roster: Array[NetPeerInfo] = Net.get_roster()
	var local_slot: int = Net.get_local_slot()
	var waiting: int = 0
	for slot: int in _slot_rows.size():
		var row: HBoxContainer = _slot_rows[slot]
		var swatch: ColorRect = row.get_node("Swatch")
		var who: Label = row.get_node("Info/Name")
		var detail: Label = row.get_node("Info/Detail")
		var role: Label = row.get_node("Role")
		var info: NetPeerInfo = null
		for p: NetPeerInfo in roster:
			if p.slot == slot:
				info = p
		if info == null:
			swatch.color = Color(1, 1, 1, 0.12)
			who.text = "Vaga livre"
			who.modulate = Color(1, 1, 1, 0.5)
			detail.text = ""
			role.text = ""
			continue
		if not info.is_host and not info.ready:
			waiting += 1
		swatch.color = HunterVisualBase.slot_color(slot)
		who.modulate = Color.WHITE
		who.text = player_label(info, slot, slot == local_slot)
		var parts: PackedStringArray = []
		if info.weapon_id != &"":
			parts.append(UiKit.item_name(info.weapon_id))
		var link: String = "" if slot == local_slot else path_text(info.path if info.path != Net.Path.NONE else Net.get_link_path(slot))
		if link != "":
			parts.append(link)
		detail.text = "  |  ".join(parts)
		role.text = status_text(info)
		role.add_theme_color_override("font_color", UiKit.MONEY_COLOR if info.is_host or info.ready else UiKit.GOLD_COLOR)

	var is_host: bool = Net.is_host()
	_start.visible = is_host
	_start.disabled = waiting > 0
	_ready_button.visible = not is_host
	var me: NetPeerInfo = Net.get_peer(local_slot)
	var me_ready: bool = me != null and me.ready
	_ready_button.text = "Cancelar pronto" if me_ready else "Pronto"
	if is_host:
		if roster.size() <= 1:
			_hint.text = "Compartilhe o link ou o código com seus amigos."
		elif waiting > 0:
			_hint.text = ("Aguardando 1 caçador ficar pronto." if waiting == 1
					else "Aguardando %d caçadores ficarem prontos." % waiting)
		else:
			_hint.text = "Todos prontos. Inicie a caçada!"
	else:
		_hint.text = "Aguardando o anfitrião iniciar a caçada." if me_ready else "Ajuste seu equipamento e toque em Pronto."
	_refresh_contracts()


## Host picks map and contract among the ones it has unlocked; everyone sees the choice.
func _refresh_contracts() -> void:
	var is_host: bool = Net.is_host()
	var map_id: StringName = Net.get_selected_map_id()
	var index: int = Net.get_selected_contract_index()
	if map_id == &"":
		_contract_label.text = "Aguardando o anfitrião escolher o contrato."
	else:
		var contract: Dictionary = Data.get_contract(map_id, index)
		_contract_label.text = "%s: %d. %s" % [Data.get_map(map_id).get("name", map_id), index + 1, contract.get("name", "")]
	_map_option.visible = is_host
	_contract_box.visible = is_host
	if not is_host or map_id == &"":
		return
	for i: int in _map_option.item_count:
		if _map_option.get_item_metadata(i) == map_id:
			_map_option.select(i)
	if _contracts_map != map_id:
		_rebuild_contract_buttons(map_id)
	for i: int in _contract_buttons.size():
		_contract_buttons[i].set_pressed_no_signal(i == index)


func _rebuild_contract_buttons(map_id: StringName) -> void:
	for b: Button in _contract_buttons:
		_contract_box.remove_child(b)
		b.queue_free()
	_contract_buttons.clear()
	_contracts_map = map_id
	for i: int in Data.get_contract_count(map_id):
		var c: Dictionary = Data.get_contract(map_id, i)
		var unlocked: bool = Profile.is_contract_unlocked(map_id, i)
		var b: Button = UiKit.button("", "SecondaryButton", 64)
		b.name = "Contract_%d" % i
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		b.text = "%d. %s  |  %d javalis%s" % [i + 1, c.get("name", ""), _boar_total(c), "" if unlocked else "  (trancado)"]
		b.pressed.connect(_on_contract_pressed.bind(i))
		_contract_box.add_child(b)
		_contract_buttons.append(b)


func _boar_total(contract: Dictionary) -> int:
	var total: int = 0
	for g: Dictionary in contract.get("groups", []):
		total += (g.get("members", []) as Array).size()
	return total


## Text for the player's name column. Empty names show "Caçador N" (N = slot + 1).
static func player_label(info: NetPeerInfo, slot: int, is_local: bool) -> String:
	var text: String = info.display_name if info.display_name != "" else "Caçador %d" % (slot + 1)
	return text + (" (você)" if is_local else "")


static func status_text(info: NetPeerInfo) -> String:
	if info.is_host:
		return "Anfitrião"
	return "Pronto" if info.ready else "Preparando"


static func path_text(path: int) -> String:
	match path:
		Net.Path.RTC:
			return "direto"
		Net.Path.RELAY:
			return "via servidor"
	return ""


# --- Signals from Net ---

func _on_room_state_changed(state: int) -> void:
	if state == Net.RoomState.LOBBY:
		_message.text = ""
	elif state == Net.RoomState.LOADING:
		_begin_hunt()
		return
	_refresh()


func _on_room_error(_code: StringName, message: String) -> void:
	_message.text = message
	_refresh()


func _on_code_changed(text: String) -> void:
	var upper: String = text.to_upper()
	if upper != text:
		var caret: int = _code_edit.caret_column
		_code_edit.text = upper
		_code_edit.caret_column = caret
	_join.disabled = not Net.is_configured() or upper.length() != _code_length


# --- Actions ---

func _on_create() -> void:
	_message.text = ""
	Net.create_room()


func _on_join() -> void:
	if _join.disabled:
		return
	_message.text = ""
	Net.join_room(_code_edit.text)


func _on_leave() -> void:
	Net.leave_room()
	_message.text = ""
	_refresh()


func _on_back() -> void:
	Net.leave_room()
	Router.goto(ScenePaths.MAIN_MENU)


func _on_ready() -> void:
	var me: NetPeerInfo = Net.get_peer(Net.get_local_slot())
	Net.set_ready(me == null or not me.ready)


func _on_start() -> void:
	if not Net.host_start_hunt():
		Sfx.play(&"ui_error")
		_message.text = "Aguarde todos os caçadores ficarem prontos."


func _on_map_selected(index: int) -> void:
	var map_id: StringName = _map_option.get_item_metadata(index)
	# Newest unlocked contract of the chosen map: that is where the host's progress is.
	var contract: int = maxi(0, Profile.get_unlocked_contract_count(map_id) - 1)
	if not Net.host_select_contract(map_id, contract):
		Sfx.play(&"ui_error")
		_refresh_contracts()


func _on_contract_pressed(index: int) -> void:
	if not Net.host_select_contract(Net.get_selected_map_id(), index):
		Sfx.play(&"ui_error")
		_refresh_contracts()


func _on_copy() -> void:
	var text: String = Net.get_room_link()
	var copied_label: String = "Link copiado!"
	if text == "":
		text = Net.get_room_code()
		copied_label = "Código copiado!"
	DisplayServer.clipboard_set(text)
	_copy.text = copied_label
	_copy_token += 1
	var token: int = _copy_token
	await get_tree().create_timer(COPIED_FEEDBACK_S).timeout
	if token == _copy_token and is_instance_valid(_copy):
		_copy.text = "Copiar link"


## Every peer (host included) builds its own request when the room goes to LOADING.
func _begin_hunt() -> void:
	if _hunt_started:
		return
	_hunt_started = true
	var map_id: StringName = Net.get_selected_map_id()
	if map_id == &"":
		map_id = Router.selected_map_id
	var request: HuntRequest = Profile.build_hunt_request(map_id, Net.get_selected_contract_index())
	request.player_count = Net.get_player_count()
	request.rng_seed = Net.get_hunt_seed()
	request.dog_id = &""   # dogs join the network in phase F7; the panel shows the choice as locked
	Router.start_hunt(request)
