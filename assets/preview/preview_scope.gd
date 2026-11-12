extends Control
## Preview: scope overlay (duplex left half, mil-dot right half) over a bright backdrop.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.85, 0.75, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var kind: float = 1.0 if OS.get_cmdline_user_args().has("--mildot") else 0.0
	var r: ColorRect = ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://assets/ui/scope_overlay.gdshader")
	m.set_shader_parameter("reticle_kind", kind)
	r.material = m
	add_child(r)
