extends Control
## Map selection. One button per map (Map_<map_id>); unavailable maps are disabled and say "Em breve".

const CARD_HEIGHT: float = 150.0


func _ready() -> void:
	var page: Dictionary = UiKit.build_page(self, "Escolha o mapa")
	var body: VBoxContainer = page["body"]
	var scroller: Array = UiKit.scroll_list(14)
	body.add_child(scroller[0])
	var list: VBoxContainer = scroller[1]
	for map_id: StringName in Data.get_map_ids():
		list.add_child(_build_map_button(map_id))

	var back: Button = UiKit.button("Voltar", "SecondaryButton")
	back.custom_minimum_size.x = 220
	UiKit.mark(back, self, "BackButton")
	(page["footer"] as HBoxContainer).add_child(back)
	back.pressed.connect(func() -> void: Router.goto(ScenePaths.MAIN_MENU))


func _build_map_button(map_id: StringName) -> Button:
	var map: Dictionary = Data.get_map(map_id)
	var available: bool = bool(map.get("available", false))
	var count: int = Data.get_contract_count(map_id)
	var b: Button = UiKit.button("", "SecondaryButton", CARD_HEIGHT)
	b.name = "Map_%s" % map_id
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not available
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = false
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)

	var icon: TextureRect = UiKit.icon_rect(StringName("map_%s" % map_id), 110)
	if icon != null:
		row.add_child(icon)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var title: Label = UiKit.label("%s  (%s)" % [map.get("name", map_id), map.get("region", "")], "HeaderLabel")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)
	var desc: Label = UiKit.label(str(map.get("description", "")), "", true)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(desc)

	var status: Label
	if available:
		var done: int = 0
		for i: int in count:
			if Profile.is_contract_completed(map_id, i):
				done += 1
		status = UiKit.label("%d de %d contratos vencidos" % [done, count], "MoneyLabel")
		b.pressed.connect(_on_map_pressed.bind(map_id))
	else:
		status = UiKit.label("Em breve", "HeaderLabel")
		var lock: TextureRect = UiKit.icon_rect(&"lock", 48)
		if lock != null:
			row.add_child(lock)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status)
	return b


func _on_map_pressed(map_id: StringName) -> void:
	Router.selected_map_id = map_id
	# Suggest the newest unlocked contract: that is where progress is.
	Router.selected_contract_index = maxi(0, Profile.get_unlocked_contract_count(map_id) - 1)
	Router.goto(ScenePaths.PREPARATION)
