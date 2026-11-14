class_name LoadoutPanel
extends VBoxContainer
## Loadout editor (2 weapons, 1 dog, up to N items), shared by Preparation and the friends lobby.
## All rules live in Profile; this panel only reflects them and forwards presses.
## Call setup(root) after adding it to the tree: nodes are registered as %WeaponSlot0/1, %DogOption and
## Item_<id> in the scope of `root` (the screen that owns the panel), so tests find them by the same names.

signal changed()

var _root: Control = null
var _slot_buttons: Array[Button] = []
var _slot_stats: Array[Label] = []
var _dog_option: OptionButton = null
var _dog_hint: Label = null
var _item_checks: Dictionary = {}   # StringName -> CheckButton
var _item_hint: Label = null
var _dog_locked_text: String = ""


## `dog_locked_text`: when not empty the dog choice is disabled and this text is shown instead of the hint.
func setup(root: Control, dog_locked_text: String = "") -> void:
	_root = root
	_dog_locked_text = dog_locked_text
	add_theme_constant_override("separation", 10)
	_build_weapons()
	_build_dog()
	_build_items()
	refresh()


func _build_weapons() -> void:
	var weapons_card: PanelContainer = UiKit.card()
	var wbox: VBoxContainer = VBoxContainer.new()
	wbox.add_theme_constant_override("separation", 6)
	weapons_card.add_child(wbox)
	wbox.add_child(UiKit.label("Armas (toque para trocar)", "HeaderLabel"))
	for slot: int in 2:
		var b: Button = UiKit.button("", "SecondaryButton", 72)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiKit.mark(b, _root, "WeaponSlot%d" % slot)
		wbox.add_child(b)
		b.pressed.connect(_cycle_slot.bind(slot))
		_slot_buttons.append(b)
		var stats: Label = UiKit.muted("")
		wbox.add_child(stats)
		_slot_stats.append(stats)
	add_child(weapons_card)


func _build_dog() -> void:
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
	UiKit.mark(_dog_option, _root, "DogOption")
	dbox.add_child(_dog_option)
	_dog_option.item_selected.connect(_on_dog_selected)
	_dog_option.disabled = _dog_locked_text != ""
	_dog_hint = UiKit.muted("")
	dbox.add_child(_dog_hint)
	add_child(dog_card)


func _build_items() -> void:
	var items_card: PanelContainer = UiKit.card()
	var ibox: VBoxContainer = VBoxContainer.new()
	ibox.add_theme_constant_override("separation", 6)
	items_card.add_child(ibox)
	ibox.add_child(UiKit.label("Equipamentos (até %d)" % _item_slots(), "HeaderLabel"))
	var any_owned: bool = false
	for id: StringName in Data.get_equipment_ids():
		if not Profile.owns(id):
			continue
		any_owned = true
		var check: CheckButton = CheckButton.new()
		check.custom_minimum_size = Vector2(0, UiKit.MIN_TOUCH_PX)
		check.button_pressed = Profile.get_loadout_items().has(id)
		if not UiKit.has_global_theme():
			check.add_theme_font_size_override("font_size", 22)
		UiKit.mark(check, _root, "Item_%s" % id)
		ibox.add_child(check)
		check.toggled.connect(_on_item_toggled)
		_item_checks[id] = check
	if not any_owned:
		ibox.add_child(UiKit.muted("Você ainda não tem equipamentos."))
	_item_hint = UiKit.muted("")
	ibox.add_child(_item_hint)
	add_child(items_card)


func _item_slots() -> int:
	return int(Data.get_game().get("loadout", {}).get("item_slots", 3))


func refresh() -> void:
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
	if _dog_locked_text != "":
		_dog_hint.text = _dog_locked_text
	else:
		_dog_hint.text = "Compre um cão na Loja para levar à caçada." if _dog_option.item_count <= 1 else ("Use E ou o botão Cão: Pega! / Volta!" if dog != &"" else "")
	_item_hint.text = ""
	var chosen: Array[StringName] = Profile.get_loadout_items()
	var slots: int = _item_slots()
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
	refresh()
	changed.emit()


func _on_dog_selected(index: int) -> void:
	Profile.set_loadout_dog(_dog_option.get_item_metadata(index))
	refresh()
	changed.emit()


func _on_item_toggled(_pressed: bool) -> void:
	var list: Array[StringName] = []
	for id: StringName in Data.get_equipment_ids():
		if _item_checks.has(id) and (_item_checks[id] as CheckButton).button_pressed:
			list.append(id)
	if not Profile.set_loadout_items(list):
		Sfx.play(&"ui_error")
	refresh()
	changed.emit()
