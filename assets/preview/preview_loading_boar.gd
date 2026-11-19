extends Control
## Preview: loading overlay mock-up with the LoadingBoar widget, screenshots at two sizes.

const OUT_DIR: String = "C:/Users/adrie/AppData/Local/Temp/claude/90ca056d862530a5/55c12a92-8818-41cf-bdfc-05bab440ccbc/scratchpad/loading/"
const SIZES: Array[Vector2i] = [Vector2i(960, 540), Vector2i(844, 390), Vector2i(1920, 1080)]
const PROGRESS: Array[float] = [0.0, 0.42, 1.0]
const PHASES: Array[float] = [0.0, 0.15, 0.3]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Hide autoload overlays (e.g. rotate-device hint) that would cover the portrait shots.
	for n: Node in get_tree().root.get_children():
		if n != self:
			for d: Node in n.find_children("*", "CanvasLayer", true, false):
				for c: Node in d.get_children():
					if c is CanvasItem:
						(c as CanvasItem).visible = false
			if n is CanvasLayer:
				(n as CanvasLayer).visible = false
	for sz: Vector2i in SIZES:
		get_window().size = sz
		await get_tree().process_frame
		await _shoot(sz)
	get_tree().quit()


func _shoot(sz: Vector2i) -> void:
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	theme = load("res://assets/ui/theme.tres")
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.118, 0.102, 0.086)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var label: Label = Label.new()
	label.text = "Preparando a caçada…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var widget: LoadingBoar = load("res://assets/ui/loading_boar.tscn").instantiate()
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	widget.custom_minimum_size = Vector2(maxf(320.0, sz.x * 0.6), maxf(210.0, sz.y * 0.3))
	box.add_child(widget)
	for p: float in PROGRESS:
		# Fresh widget state per progress value so the no-regress rule does not hide 0.0.
		var w2: LoadingBoar = load("res://assets/ui/loading_boar.tscn").instantiate()
		w2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w2.custom_minimum_size = widget.custom_minimum_size
		box.add_child(w2)
		box.remove_child(widget)
		widget.queue_free()
		widget = w2
		widget.set_progress(p)
		await get_tree().process_frame
		widget.set_process(false)
		widget._shown = p
		for ph: float in PHASES:
			widget.debug_time = ph * LoadingBoar.GALLOP_PERIOD * 3.0
			widget.queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			var path: String = "%sloading_%dx%d_p%03d_ph%d.png" % [OUT_DIR, sz.x, sz.y, int(p * 100.0), PHASES.find(ph)]
			img.save_png(path)
			print("saved ", path)
