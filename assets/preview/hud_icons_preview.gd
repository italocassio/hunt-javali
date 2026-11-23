extends Control
## Preview: the HUD item icons and the knife icons at 40 px and 76 px, on HudPanel and on the touch translucent circle.

const ICONS: Array[String] = ["medkit", "corn_bait", "scout_drone", "binoculars", "btn_dog", "knife", "btn_knife"]
const SIZES: Array[int] = [40, 76]


func _ready() -> void:
	theme = load("res://assets/ui/theme.tres") as Theme
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.42, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(24, 24)
	col.add_theme_constant_override("separation", 20)
	add_child(col)
	for s: int in SIZES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		row.custom_minimum_size.y = 140
		col.add_child(row)
		var panel := PanelContainer.new()
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		panel.theme_type_variation = &"HudPanel"
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		panel.add_child(hb)
		for n: String in ICONS:
			hb.add_child(_icon(n, s))
		row.add_child(panel)
		var touch := HBoxContainer.new()
		touch.add_theme_constant_override("separation", 14)
		for n: String in ICONS:
			var c := Control.new()
			var d: int = int(s * 1.7)
			c.custom_minimum_size = Vector2(d, d)
			c.draw.connect(_draw_circle_bg.bind(c, d))
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var ic := _icon(n, s)
			ic.position = Vector2(d - s, d - s) * 0.5
			c.add_child(ic)
			touch.add_child(c)
		row.add_child(touch)
	await get_tree().create_timer(0.3).timeout


func _draw_circle_bg(c: Control, d: int) -> void:
	var r: float = d * 0.5
	var ctr := Vector2(r, r)
	c.draw_circle(ctr, r, Color(0, 0, 0, 0.35))
	c.draw_arc(ctr, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)


func _icon(n: String, s: int) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture = load("res://assets/ui/icons/%s.svg" % n) as Texture2D
	t.custom_minimum_size = Vector2(s, s)
	t.size = Vector2(s, s)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t
