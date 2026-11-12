extends Control
## Hunt preparation: pick a contract and set the loadout (2 weapons, 1 dog, up to 3 items).
## Nodes: Contract_<index>, %WeaponSlot0/1, %DogOption, Item_<id>, %StartHuntButton, %ShopButton, %BackButton.

var _map_id: StringName = &"mato_grosso"
var _selected: int = 0
var _contract_buttons: Array[Button] = []
var _detail_box: VBoxContainer = null
var _slot_buttons: Array[Button] = []
var _slot_stats: Array[Label] = []
var _dog_option: OptionButton = null
var _dog_hint: Label = null
var _item_checks: Dictionary = {}   # StringName -> CheckButton
var _item_hint: Label = null
var _start: Button = null


func _ready() -> void:
	_map_id = Router.selected_map_id
	var map: Dictionary = Data.get_map(_map_id)
	var unlocked: int = Profile.get_unlocked_contract_count(_map_id)
	_selected = clampi(Router.selected_contract_index, 0, maxi(0, unlocked - 1))

	var page: Dictionary = UiKit.build_page(self, "Preparação: %s" % map.get("name", _map_id))
	var body: VBoxContainer = page["body"]
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	body.add_child(columns)

	# Left: contracts and details
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	left.add_child(UiKit.label("Contratos", "HeaderLabel"))
	var contract_scroll: Array = UiKit.scroll_list(8)
	left.add_child(contract_scroll[0])
	for i: int in Data.get_contract_count(_map_id):
		var b: Button = _build_contract_button(i)
		contract_scroll[1].add_child(b)
		_contract_buttons.append(b)
	var detail_card: PanelContainer = UiKit.card()
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 4)
	detail_card.add_child(_detail_box)
	left.add_child(detail_card)

	# Right: loadout
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(UiKit.label("Equipamento da caçada", "HeaderLabel"))
	var loadout_scroll: Array = UiKit.scroll_list(10)
	right.add_child(loadout_scroll[0])
	_build_loadout(loadout_scroll[1])

	var footer: HBoxContainer = page["footer"]
	var back: Button = UiKit.button("Voltar", "SecondaryButton")
	back.custom_minimum_size.x = 200
	UiKit.mark(back, self, "BackButton")
	footer.add_child(back)
	back.pressed.connect(func() -> void: Router.goto(ScenePaths.MAP_SELECT))
	var shop: Button = UiKit.button("Loja", "SecondaryButton")
	shop.custom_minimum_size.x = 200
	UiKit.mark(shop, self, "ShopButton")
	footer.add_child(shop)
	shop.pressed.connect(func() -> void: Router.goto(ScenePaths.SHOP))
	footer.add_child(UiKit.spacer())
	_start = UiKit.button("Iniciar caçada", "PrimaryButton", 80)
	_start.custom_minimum_size.x = 340
	UiKit.mark(_start, self, "StartHuntButton")
	footer.add_child(_start)
	_start.pressed.connect(_on_start)

	_select(_selected)
	_refresh_loadout()
	_start.grab_focus()


# --- Contracts ---

func _build_contract_button(index: int) -> Button:
	var c: Dictionary = Data.get_contract(_map_id, index)
	var unlocked: bool = Profile.is_contract_unlocked(_map_id, index)
	var b: Button = UiKit.button("", "SecondaryButton", 76)
	b.name = "Contract_%d" % index
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not unlocked
	var status: String
	if not unlocked:
		status = "Trancado: vença o contrato anterior"
	elif Profile.is_contract_completed(_map_id, index):
		status = "Vencido (lavoura %d%%)" % int(roundf(Profile.get_best_crop_pct(_map_id, index)))
	else:
		status = "Disponível"
	b.text = "%d. %s  |  %d javalis\n%s" % [index + 1, c.get("name", ""), _boar_total(c), status]
	b.pressed.connect(_select.bind(index))
	return b


func _select(index: int) -> void:
	if not Profile.is_contract_unlocked(_map_id, index):
		return
	_selected = index
	Router.selected_contract_index = index
	for i: int in _contract_buttons.size():
		_contract_buttons[i].set_pressed_no_signal(i == index)
	_fill_detail()


func _fill_detail() -> void:
	for child: Node in _detail_box.get_children():
		child.queue_free()
	var c: Dictionary = Data.get_contract(_map_id, _selected)
	_detail_box.add_child(UiKit.label(str(c.get("name", "")), "HeaderLabel"))
	_detail_box.add_child(UiKit.label(str(c.get("description", "")), "", true))
	var comp: Dictionary = {}
	for g: Dictionary in c.get("groups", []):
		for m: Variant in g.get("members", []):
			comp[str(m)] = int(comp.get(str(m), 0)) + 1
	var parts: PackedStringArray = []
	for type_id: StringName in Data.get_boar_type_ids():
		if comp.has(String(type_id)):
			parts.append("%d x %s" % [comp[String(type_id)], UiKit.boar_name(type_id)])
	_detail_box.add_child(UiKit.label("Alvos (%d): %s" % [_boar_total(c), ", ".join(parts)], "", true))
	_detail_box.add_child(UiKit.label("Prêmio por abate: x%s   |   Bônus de lavoura: até %s" % [UiKit.decimal(float(c.get("reward_mult", 1.0)), 2), UiKit.money_text(int(c.get("bonus_money", 0)))], "MoneyLabel", true))


func _boar_total(c: Dictionary) -> int:
	var total: int = 0
	for g: Dictionary in c.get("groups", []):
		total += (g.get("members", []) as Array).size()
	return total


# --- Loadout ---

func _build_loadout(list: VBoxContainer) -> void:
	var weapons_card: PanelContainer = UiKit.card()
	var wbox: VBoxContainer = VBoxContainer.new()
	wbox.add_theme_constant_override("separation", 6)
	weapons_card.add_child(wbox)
	wbox.add_child(UiKit.label("Armas (toque para trocar)", "HeaderLabel"))
	for slot: int in 2:
		var b: Button = UiKit.button("", "SecondaryButton", 72)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiKit.mark(b, self, "WeaponSlot%d" % slot)
		wbox.add_child(b)
		b.pressed.connect(_cycle_slot.bind(slot))
		_slot_buttons.append(b)
		var stats: Label = UiKit.muted("")
		wbox.add_child(stats)
		_slot_stats.append(stats)
	list.add_child(weapons_card)

	var dog_card: PanelContainer = UiKit.card()
	var dbox: VBoxContainer = VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 6)
	dog_card.add_child(dbox)
	dbox.add_child(UiKit.label("Cão", "HeaderLabel"))
	_dog_option = OptionButton.new()
	_dog_option.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
	_dog_option.theme_type_variation = "SecondaryButton"
	if not UiKit.has_global_theme():
		_dog_option.add_theme_font_size_override("font_size", 22)
	var popup: PopupMenu = _dog_option.get_popup()
	popup.add_theme_constant_override("v_separation", 22)
	popup.add_theme_font_size_override("font_size", 24)
	_dog_option.add_item("Sem cão", 0)
	_dog_option.set_item_metadata(0, &"")
	for dog_id: StringName in Data.get_dog_ids():
		if Profile.owns(dog_id):
			_dog_option.add_item(UiKit.item_name(dog_id))
			_dog_option.set_item_metadata(_dog_option.item_count - 1, dog_id)
	UiKit.mark(_dog_option, self, "DogOption")
	dbox.add_child(_dog_option)
	_dog_option.item_selected.connect(_on_dog_selected)
	_dog_hint = UiKit.muted("")
	dbox.add_child(_dog_hint)
	list.add_child(dog_card)

	var items_card: PanelContainer = UiKit.card()
	var ibox: VBoxContainer = VBoxContainer.new()
	ibox.add_theme_constant_override("separation", 6)
	items_card.add_child(ibox)
	var slots: int = int(Data.get_game().get("loadout", {}).get("item_slots", 3))
	ibox.add_child(UiKit.label("Equipamentos (até %d)" % slots, "HeaderLabel"))
	var any_owned: bool = false
	for id: StringName in Data.get_equipment_ids():
		if not Profile.owns(id):
			continue
		any_owned = true
		var check: CheckButton = CheckButton.new()
		check.name = "Item_%s" % id
		check.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
		check.button_pressed = Profile.get_loadout_items().has(id)
		if not UiKit.has_global_theme():
			check.add_theme_font_size_override("font_size", 22)
		ibox.add_child(check)
		check.toggled.connect(_on_item_toggled)
		_item_checks[id] = check
	if not any_owned:
		ibox.add_child(UiKit.muted("Você ainda não tem equipamentos."))
	_item_hint = UiKit.muted("")
	ibox.add_child(_item_hint)
	list.add_child(items_card)


func _refresh_loadout() -> void:
	var loadout: Array[StringName] = Profile.get_loadout_weapons()
	for slot: int in 2:
		var id: StringName = loadout[slot]
		_slot_buttons[slot].text = "Arma %d:  %s" % [slot + 1, UiKit.item_name(id) if id != &"" else "(vazio)"]
		_slot_stats[slot].text = ItemCard.stats_text(id) if id != &"" else ("Slot opcional: leve uma segunda arma." if slot == 1 else "")
	var owned_count: int = 0
	for id: StringName in Data.get_weapon_ids():
		if Profile.owns(id):
			owned_count += 1
	_slot_buttons[1].tooltip_text = "Compre mais armas na Loja." if owned_count < 2 else ""

	var dog: StringName = Profile.get_loadout_dog()
	for i: int in _dog_option.item_count:
		if _dog_option.get_item_metadata(i) == dog:
			_dog_option.select(i)
	_dog_hint.text = "Compre um cão na Loja para levar à caçada." if _dog_option.item_count <= 1 else ("Use E ou o botão Cão: Pega! / Volta!" if dog != &"" else "")
	_item_hint.text = ""
	var chosen: Array[StringName] = Profile.get_loadout_items()
	var slots: int = int(Data.get_game().get("loadout", {}).get("item_slots", 3))
	for id: StringName in _item_checks:
		var check: CheckButton = _item_checks[id]
		var def: Dictionary = Data.get_equipment(id)
		var label: String = str(def.get("name", id))
		if def.get("kind", "") == "consumable":
			label += "  (você tem %d, leva até %d)" % [Profile.get_item_count(id), int(def.get("max_per_hunt", 1))]
		check.text = label
		check.set_pressed_no_signal(chosen.has(id))
		check.disabled = not chosen.has(id) and chosen.size() >= slots
	if chosen.size() >= slots:
		_item_hint.text = "Limite de %d equipamentos. Desmarque um para trocar." % slots


func _cycle_slot(slot: int) -> void:
	var loadout: Array[StringName] = Profile.get_loadout_weapons()
	var other: StringName = loadout[1 - slot]
	var options: Array[StringName] = []
	for id: StringName in Data.get_weapon_ids():
		if Profile.owns(id) and id != other:
			options.append(id)
	if slot == 1:
		options.append(&"")
	if options.size() <= 1:
		Sfx.play(&"ui_error")
		return
	var at: int = options.find(loadout[slot])
	Profile.set_loadout_weapon(slot, options[(at + 1) % options.size()])
	_refresh_loadout()


func _on_dog_selected(index: int) -> void:
	Profile.set_loadout_dog(_dog_option.get_item_metadata(index))
	_refresh_loadout()


func _on_item_toggled(_pressed: bool) -> void:
	var list: Array[StringName] = []
	for id: StringName in Data.get_equipment_ids():
		if _item_checks.has(id) and (_item_checks[id] as CheckButton).button_pressed:
			list.append(id)
	if not Profile.set_loadout_items(list):
		Sfx.play(&"ui_error")
	_refresh_loadout()


func _on_start() -> void:
	if not Profile.is_contract_unlocked(_map_id, _selected):
		Sfx.play(&"ui_error")
		return
	Router.selected_contract_index = _selected
	Router.start_hunt(Profile.build_hunt_request(_map_id, _selected))
