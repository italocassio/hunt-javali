extends Control
## Preview: global theme variations + every icon in a grid.

const ICONS: Array[String] = ["carbine_22", "shotgun_12", "rifle_308", "rifle_3006", "rifle_338", "binoculars", "leather_vest", "medkit", "corn_bait", "extra_ammo", "thermal_scope", "scout_drone", "caramelo", "foxhound", "dogo", "money", "gold", "boar", "crop", "health", "ammo", "lock", "dog_paw", "app_icon", "map_mato_grosso", "map_pantanal", "map_campanha_gaucha", "map_triangulo_mineiro", "btn_fire", "btn_aim", "btn_reload", "btn_swap", "btn_dog", "btn_item", "btn_crouch", "btn_pause", "joystick_base", "joystick_knob"]


func _ready() -> void:
	theme = load("res://assets/ui/theme.tres")
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: HBoxContainer = HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	root.add_child(left)
	var title: Label = Label.new()
	title.text = "Caçada ao Javali"
	title.theme_type_variation = &"TitleLabel"
	left.add_child(title)
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	left.add_child(card)
	var cv: VBoxContainer = VBoxContainer.new()
	card.add_child(cv)
	for pair: Array in [["HeaderLabel", "Rifle .308"], ["MoneyLabel", "R$ 1.250"], ["GoldLabel", "35 ouro"]]:
		var l: Label = Label.new()
		l.text = pair[1]
		l.theme_type_variation = StringName(pair[0])
		cv.add_child(l)
	for pair: Array in [["PrimaryButton", "Iniciar caçada"], ["SecondaryButton", "Loja"], ["DangerButton", "Desistir"]]:
		var b: Button = Button.new()
		b.text = pair[1]
		b.theme_type_variation = StringName(pair[0])
		left.add_child(b)
	var plain: Button = Button.new()
	plain.text = "Botão padrão"
	left.add_child(plain)
	for pair: Array in [["CropBar", 0.7], ["HealthBar", 0.4]]:
		var pb: ProgressBar = ProgressBar.new()
		pb.theme_type_variation = StringName(pair[0])
		pb.value = pair[1] * 100.0
		pb.custom_minimum_size = Vector2(0, 24)
		left.add_child(pb)
	var hud: PanelContainer = PanelContainer.new()
	hud.theme_type_variation = &"HudPanel"
	var hl: Label = Label.new()
	hl.theme_type_variation = &"HudBigLabel"
	hl.text = "Javali abatido!"
	hud.add_child(hl)
	left.add_child(hud)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	root.add_child(grid)
	for id in ICONS:
		var tr: TextureRect = TextureRect.new()
		tr.texture = load("res://assets/ui/icons/%s.svg" % id)
		tr.custom_minimum_size = Vector2(80, 80)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		grid.add_child(tr)
