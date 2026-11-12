class_name Hud
extends CanvasLayer
## In-hunt HUD (docs 8.4). Reads the player directly every frame, polls the world at 10 Hz and listens to
## GameEvents for everything else. Owns the touch layer and the pause overlay as children.

const POLL_INTERVAL_S: float = 0.1
const MARGIN_PX: int = 24
const TOUCH_TOPLEFT_MARGIN_PX: int = 100      # leaves room for the touch pause button
const TOUCH_BOTTOM_RIGHT_MARGIN_PX: int = 530 # leaves room for the touch buttons
const ALARM_REPEAT_S: float = 3.0
const DOG_MSG_S: float = 1.2
const END_MSG_S: float = 5.0
const HEAL_MSG_S: float = 1.5
const BLINK_HZ: float = 2.0
const CROP_WARN_PCT: float = 60.0
const CROP_DANGER_PCT: float = 30.0
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_GOOD: Color = Color("#3FAF5A")
const COLOR_WARN: Color = Color("#F2C12E")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_PANEL: Color = Color(0.12, 0.10, 0.086, 0.72)
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.55)
const DOG_STATE_TEXT: Dictionary = {
	"follow": "Seguindo", "seek": "Procurando", "point": "Apontando", "bay": "Acuando",
	"hold": "Segurando", "retreat": "Ferido", "return": "Voltando",
}

var _player: Player = null
var _world: HuntWorld = null
var _poll_t: float = 0.0
var _last_hit_shot: int = -1
var _crop_attack: bool = false
var _alarm_t: float = 0.0
var _reveal_left: float = 0.0
var _marks: Array[Dictionary] = []
var _event_marks: Array[Dictionary] = []
var _baits: Array[Dictionary] = []
var _revealed: PackedVector3Array = PackedVector3Array()
var _bait_points: PackedVector3Array = PackedVector3Array()
var _marked_points: PackedVector3Array = PackedVector3Array()
var _ended: bool = false
var _thermal: bool = false
var _last_ammo_text: String = ""
var _last_item_text: String = ""

var _root: Control = Control.new()
var _scope: ScopeOverlay = ScopeOverlay.new()
var _damage: DamageIndicator = DamageIndicator.new()
var _crosshair: HudCrosshair = HudCrosshair.new()
var _compass: Compass = Compass.new()
var _minimap: Minimap = Minimap.new()
var _kill_msg: KillMessage = KillMessage.new()
var _ctx_msg: KillMessage = KillMessage.new()
var _dog_msg: KillMessage = KillMessage.new()
var _end_msg: KillMessage = KillMessage.new()
var _topleft_margin: MarginContainer = null
var _bottomright_margin: MarginContainer = null
var _health_bar: ProgressBar = ProgressBar.new()
var _health_label: Label = null
var _vest_label: Label = null
var _crop_bar: ProgressBar = ProgressBar.new()
var _crop_label: Label = null
var _crop_alert: Label = null
var _count_label: Label = null
var _dog_panel: PanelContainer = null
var _dog_label: Label = null
var _dog_bar: ProgressBar = ProgressBar.new()
var _weapon_label: Label = null
var _ammo_label: Label = null
var _reload_bar: ProgressBar = ProgressBar.new()
var _item_label: Label = null
var _zoom_label: Label = null
var _touch: TouchControls = null
var _pause: PauseOverlay = null


func _ready() -> void:
	layer = 10
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_scope.name = "ScopeOverlay"
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_scope)
	_damage.name = "DamageIndicator"
	_damage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage.duration_s = float(Data.get_game().get("player", {}).get("damage_indicator_s", 1.2))
	_root.add_child(_damage)
	_crosshair.name = "Crosshair"
	_root.add_child(_crosshair)
	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_bottom_right()
	_build_messages()
	_touch = AssetLoader.instantiate("res://src/hud/touch/touch_controls.tscn") as TouchControls
	if _touch == null:
		_touch = TouchControls.new()
	_touch.name = "TouchControls"
	add_child(_touch)
	_pause = AssetLoader.instantiate("res://src/hud/pause_overlay.tscn") as PauseOverlay
	if _pause == null:
		_pause = PauseOverlay.new()
	_pause.name = "PauseOverlay"
	add_child(_pause)
	_connect_events()
	_apply_touch_layout(InputSetup.is_touch_mode())


func bind(player: PlayerBase, world: HuntWorld) -> void:
	_player = player as Player
	_world = world
	if _player == null:
		push_error("Hud.bind: player is not a Player")
		return
	_touch.bind(_player)
	_pause.bind(_player)
	var items: ItemBelt = _player.get_items()
	if items != null:
		items.selection_changed.connect(_refresh_item_text)
		items.counts_changed.connect(_refresh_item_text)
	_vest_label.visible = items != null and items.damage_reduction > 0.0
	if _world != null:
		_minimap.map_rect = _world.get_map_rect()
		_minimap.crop_rects = _world.get_crop_rects()
		_on_crop_health(_world.get_crop_health_pct())
		_on_counts(_world.get_boars_killed(), _world.get_boars_total())
	_refresh_item_text()
	_update_health()
	_poll_world()


## Called by the Player (pause button, focus loss, lost pointer lock).
func open_pause() -> void:
	if _pause != null:
		_pause.open()


func on_hunt_ended() -> void:
	_ended = true
	_touch.end_hunt()
	_pause.set_enabled(false)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _corner(corner_name: String, h_flag: Control.SizeFlags, v_flag: Control.SizeFlags) -> Array:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = corner_name
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN_PX)
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = h_flag
	box.size_flags_vertical = v_flag
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	_root.add_child(margin)
	return [margin, box]


func _label(text: String, font_size: int, color: Color = COLOR_TEXT, variation: StringName = &"HudLabel") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _panel(inner: Control, margin_px: int = 10) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.theme_type_variation = &"HudPanel"
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or not theme.has_stylebox(&"panel", &"HudPanel"):
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = COLOR_PANEL
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(margin_px)
		p.add_theme_stylebox_override("panel", sb)
	p.add_child(inner)
	return p


func _style_bar(bar: ProgressBar, variation: StringName, height: float, width: float) -> void:
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.theme_type_variation = variation
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(width, height)
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null or not theme.has_stylebox(&"fill", variation):
		var bg: StyleBoxFlat = StyleBoxFlat.new()
		bg.bg_color = COLOR_BAR_BG
		bg.set_corner_radius_all(4)
		var fill: StyleBoxFlat = StyleBoxFlat.new()
		fill.bg_color = Color.WHITE   # tinted through modulate
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)


func _build_top_left() -> void:
	var parts: Array = _corner("TopLeft", Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
	_topleft_margin = parts[0]
	var box: VBoxContainer = parts[1]
	var inner: VBoxContainer = VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label("Vida", 20))
	_style_bar(_health_bar, &"HealthBar", 22.0, 140.0)
	_health_bar.name = "HealthBar"
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_health_bar)
	_health_label = _label("100", 22)
	row.add_child(_health_label)
	inner.add_child(row)
	_vest_label = _label("Colete equipado", 16, COLOR_WARN)
	_vest_label.visible = false
	inner.add_child(_vest_label)
	box.add_child(_panel(inner))


func _build_top_center() -> void:
	var parts: Array = _corner("TopCenter", Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN)
	var box: VBoxContainer = parts[1]
	box.add_child(_compass)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crop_label = _label("Lavoura 100%", 20)
	_crop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_crop_label)
	_style_bar(_crop_bar, &"CropBar", 14.0, 300.0)
	_crop_bar.name = "CropBar"
	inner.add_child(_crop_bar)
	var panel: PanelContainer = _panel(inner, 8)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(panel)
	_crop_alert = _label("Javalis na lavoura!", 26, COLOR_DANGER, &"HudBigLabel")
	_crop_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crop_alert.visible = false
	box.add_child(_crop_alert)


func _build_top_right() -> void:
	var parts: Array = _corner("TopRight", Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_BEGIN)
	var box: VBoxContainer = parts[1]
	box.add_child(_minimap)
	_count_label = _label("Javalis 0/0", 24)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_count_label)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dog_label = _label("Cão", 18)
	inner.add_child(_dog_label)
	_style_bar(_dog_bar, &"HealthBar", 10.0, 150.0)
	inner.add_child(_dog_bar)
	_dog_panel = _panel(inner, 8)
	_dog_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_dog_panel.visible = false
	box.add_child(_dog_panel)


func _build_bottom_right() -> void:
	var parts: Array = _corner("BottomRight", Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_END)
	_bottomright_margin = parts[0]
	var box: VBoxContainer = parts[1]
	var inner: VBoxContainer = VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_label = _label("", 18)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_weapon_label)
	_ammo_label = _label("0 | 0", 40, COLOR_TEXT, &"HudBigLabel")
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_ammo_label)
	_style_bar(_reload_bar, &"CropBar", 8.0, 160.0)
	_reload_bar.modulate = COLOR_WARN
	_reload_bar.visible = false
	inner.add_child(_reload_bar)
	_item_label = _label("", 16)
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(_item_label)
	box.add_child(_panel(inner))


func _build_messages() -> void:
	_zoom_label = _label("", 24, COLOR_TEXT, &"HudBigLabel")
	_zoom_label.name = "ZoomLabel"
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_zoom_label.position.y += 150.0
	_zoom_label.visible = false
	_root.add_child(_zoom_label)
	_place_message(_kill_msg, "KillMessage", 0.72, 0.12, 30)
	_place_message(_ctx_msg, "ContextMessage", 0.22, 0.08, 26)
	_place_message(_dog_msg, "DogMessage", 0.58, 0.08, 28)
	_dog_msg.set_color(COLOR_WARN)
	_place_message(_end_msg, "EndMessage", 0.38, 0.14, 44)


func _place_message(msg: KillMessage, node_name: String, top_frac: float, height_frac: float, font_px: int) -> void:
	msg.name = node_name
	msg.anchor_left = 0.1
	msg.anchor_right = 0.9
	msg.anchor_top = top_frac
	msg.anchor_bottom = top_frac + height_frac
	msg.offset_left = 0.0
	msg.offset_right = 0.0
	msg.offset_top = 0.0
	msg.offset_bottom = 0.0
	msg.set_font_size(font_px)
	_root.add_child(msg)


func _connect_events() -> void:
	GameEvents.touch_mode_changed.connect(_apply_touch_layout)
	GameEvents.player_damaged.connect(_on_player_damaged)
	GameEvents.player_healed.connect(_on_player_healed)
	GameEvents.boar_hit.connect(_on_boar_hit)
	GameEvents.boar_killed.connect(_on_boar_killed)
	GameEvents.boar_counts_changed.connect(_on_counts)
	GameEvents.crop_health_changed.connect(_on_crop_health)
	GameEvents.crop_under_attack.connect(_on_crop_attack)
	GameEvents.bait_placed.connect(_on_bait_placed)
	GameEvents.dog_state_changed.connect(_on_dog_state)
	GameEvents.dog_health_changed.connect(_on_dog_health)
	GameEvents.dog_marked_boar.connect(_on_dog_marked)
	GameEvents.dog_command_executed.connect(_on_dog_command)
	GameEvents.hud_message_requested.connect(_on_message)
	GameEvents.item_used.connect(_on_item_used)
	GameEvents.thermal_vision_changed.connect(_on_thermal)
	GameEvents.hunt_ended.connect(_on_hunt_ended)


func _apply_touch_layout(is_touch: bool) -> void:
	if _topleft_margin != null:
		_topleft_margin.add_theme_constant_override("margin_left", TOUCH_TOPLEFT_MARGIN_PX if is_touch else MARGIN_PX)
	if _bottomright_margin != null:
		_bottomright_margin.add_theme_constant_override("margin_right",
			TOUCH_BOTTOM_RIGHT_MARGIN_PX if is_touch else MARGIN_PX)
	_refresh_item_text()   # touch mode shows the item on its button instead


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null:
		return
	_update_health()
	_update_weapon()
	_update_scope_and_crosshair()
	var origin: Vector3 = _player.global_position
	var yaw: float = _player.rotation.y
	_compass.update_state(origin, yaw, _marks)
	_damage.set_player_state(origin, yaw)
	_damage.low_health = _player.is_alive() and \
		_player.get_health() / maxf(_player.get_max_health(), 1.0) <= float(
			Data.get_game().get("player", {}).get("low_health_frac", 0.3))
	if _crop_attack and not _ended:
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = ALARM_REPEAT_S
			Sfx.play(&"crop_alarm")
		_crop_alert.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.001 * TAU * BLINK_HZ)
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_INTERVAL_S
		if _reveal_left > 0.0:
			_reveal_left = maxf(_reveal_left - POLL_INTERVAL_S, 0.0)
		_poll_world()
		_minimap.update_player(origin, yaw)


func _update_health() -> void:
	var hp: float = _player.get_health()
	var frac: float = hp / maxf(_player.get_max_health(), 1.0)
	_health_bar.value = frac * 100.0
	_health_bar.modulate = COLOR_GOOD if frac > 0.5 else (COLOR_WARN if frac > 0.3 else COLOR_DANGER)
	_health_label.text = str(int(ceil(hp)))


func _update_weapon() -> void:
	var w: Weapon = _player.get_weapon()
	if w == null:
		return
	var text: String = "%d | %d" % [w.ammo_in_mag, w.ammo_reserve]
	if text != _last_ammo_text:
		_last_ammo_text = text
		_ammo_label.text = text
		_weapon_label.text = String(w.def.get("name", ""))
	var low: bool = w.ammo_in_mag <= 0 or w.ammo_in_mag * 4 <= int(w.def.get("mag_size", 1))
	_ammo_label.add_theme_color_override("font_color", COLOR_DANGER if low else COLOR_TEXT)
	_reload_bar.visible = w.is_reloading()
	if w.is_reloading():
		_reload_bar.value = w.get_reload_progress() * 100.0


func _update_scope_and_crosshair() -> void:
	var scope_t: float = _player.get_scope_t()
	var binoc: bool = _player.is_binocular_view()
	var w: Weapon = _player.get_weapon()
	var kind: int = int(w.get_def_float("reticle_kind")) if w != null else 0
	_scope.set_state(scope_t, kind, not binoc)
	_crosshair.set_visibility_t(1.0 - clampf(scope_t * 1.5, 0.0, 1.0))
	var half_h: float = _root.size.y * 0.5
	var half_fov: float = deg_to_rad(_player.get_fov_deg()) * 0.5
	var spread_px: float = tan(deg_to_rad(_player.get_spread_deg())) / maxf(tan(half_fov), 0.01) * half_h
	_crosshair.set_gap(spread_px)
	var show_zoom: bool = (_player.is_aiming() and (_player.has_zoom_range() or _thermal)) or binoc
	_zoom_label.visible = show_zoom
	if show_zoom:
		var zoom_text: String = "%.1fx" % _player.get_zoom_value()
		_zoom_label.text = ("Térmica · " + zoom_text) if _thermal else zoom_text


func _poll_world() -> void:
	if _world == null or _player == null:
		return
	var now_s: float = Time.get_ticks_msec() * 0.001
	_marks.clear()
	_marked_points.resize(0)
	var seen: PackedVector3Array = _world.get_marked_boar_positions()
	for p: Vector3 in seen:
		_marked_points.append(p)
		_marks.append({"pos": p, "kind": &"boar"})
	for i: int in range(_event_marks.size() - 1, -1, -1):
		if float(_event_marks[i]["until"]) < now_s:
			_event_marks.remove_at(i)
	for m: Dictionary in _event_marks:
		_marked_points.append(m["pos"])
		_marks.append({"pos": m["pos"], "kind": &"boar"})
	var dog_on: bool = _world.has_dog()
	if dog_on and not _dog_panel.visible:
		_dog_panel.visible = true
		_dog_bar.value = _world.get_dog_health_pct()
		_on_dog_state(_world.get_dog_state())
	var dog_pos: Vector3 = _world.get_dog_position() if dog_on else Vector3.INF
	if dog_pos.is_finite():
		_marks.append({"pos": dog_pos, "kind": &"dog"})
	var request: HuntRequest = _player.get_request()
	if request != null and request.dog_id == Ids.D_CARAMELO and dog_on:
		var nearest: Vector3 = _world.get_nearest_boar_position(_player.global_position)
		if nearest.is_finite():
			_marks.append({"pos": nearest, "kind": &"boar"})
	_minimap.dog_position = dog_pos
	_minimap.marked = _marked_points
	_revealed.resize(0)
	if _reveal_left > 0.0:
		for id: int in _world.get_alive_boar_ids():
			var bp: Vector3 = _world.get_boar_position(id)
			if bp.is_finite():
				_revealed.append(bp)
	_minimap.revealed = _revealed
	_bait_points.resize(0)
	for i: int in range(_baits.size() - 1, -1, -1):
		if float(_baits[i]["until"]) < now_s:
			_baits.remove_at(i)
	for b: Dictionary in _baits:
		_bait_points.append(b["pos"])
	_minimap.baits = _bait_points


func _refresh_item_text() -> void:
	if _player == null or _item_label == null:
		return
	var items: ItemBelt = _player.get_items()
	var text: String = ""
	if items != null and items.get_selected_id() != &"":
		var id: StringName = items.get_selected_id()
		var count: int = items.get_count(id)
		text = String(Data.get_equipment(id).get("name", ""))
		if count >= 0:
			text += " x%d" % count
		if not InputSetup.is_touch_mode():
			text += "  [Q]" + (" [F]" if items.get_usable_ids().size() > 1 else "")
	_item_label.text = text
	_item_label.visible = text != "" and not InputSetup.is_touch_mode()


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _on_player_damaged(amount: float, source_position: Vector3, _health_after: float) -> void:
	_damage.add_hit(amount, source_position)


func _on_player_healed(amount: float, _health_after: float) -> void:
	_ctx_msg.show_text("+%d de vida" % int(round(amount)), HEAL_MSG_S)


func _on_boar_hit(_boar_id: int, _zone: StringName, _damage_amount: float, _pos: Vector3, shot_id: int) -> void:
	if shot_id == _last_hit_shot:
		return   # shotgun pellets of one shot count once
	_last_hit_shot = shot_id
	_crosshair.flash_hit(false)
	Sfx.play(&"hit_marker")


func _on_boar_killed(kill: KillInfo) -> void:
	var type_name: String = String(Data.get_boar_type(kill.type_id).get("name", "Javali"))
	var text: String = "%s abatido — %d kg · %s" % [type_name, int(round(kill.weight_kg)), _money(kill.reward_money)]
	if kill.clean_kill:
		text += " · Tiro limpo!"
	if kill.one_shot:
		text += " · Um tiro só!"
	_kill_msg.show_text(text, float(Data.get_game().get("hunt", {}).get("kill_message_s", 3.0)))
	_crosshair.flash_hit(true)
	Sfx.play(&"kill_confirm")


func _on_counts(killed: int, total: int) -> void:
	_count_label.text = "Javalis %d/%d" % [killed, total]


func _on_crop_health(pct: float) -> void:
	_crop_bar.value = pct
	_crop_label.text = "Lavoura %d%%" % int(round(pct))
	_crop_bar.modulate = COLOR_GOOD if pct > CROP_WARN_PCT else (COLOR_WARN if pct > CROP_DANGER_PCT else COLOR_DANGER)


func _on_crop_attack(active: bool) -> void:
	_crop_attack = active
	_crop_alert.visible = active
	_crop_alert.modulate.a = 1.0
	_alarm_t = 0.0


func _on_bait_placed(position: Vector3, duration_s: float) -> void:
	_baits.append({"pos": position, "until": Time.get_ticks_msec() * 0.001 + duration_s})


func _on_dog_state(state: StringName) -> void:
	_dog_panel.visible = true
	var name_text: String = String(DOG_STATE_TEXT.get(String(state), String(state)))
	_dog_label.text = "Cão: " + name_text


func _on_dog_health(pct: float) -> void:
	_dog_bar.value = pct
	_dog_bar.modulate = COLOR_GOOD if pct > 50.0 else (COLOR_WARN if pct > 30.0 else COLOR_DANGER)


func _on_dog_marked(position: Vector3, duration_s: float) -> void:
	_event_marks.append({"pos": position, "until": Time.get_ticks_msec() * 0.001 + duration_s})


func _on_dog_command(command: StringName) -> void:
	_dog_msg.show_text("Pega!" if command == Ids.CMD_ATTACK else "Volta!", DOG_MSG_S)


func _on_message(text: String, duration_s: float) -> void:
	_ctx_msg.show_text(text, duration_s)


func _on_item_used(item_id: StringName, _position: Vector3) -> void:
	if item_id == Ids.I_SCOUT_DRONE:
		_reveal_left = float(Data.get_equipment(item_id).get("effect", {}).get("reveal_s", 0.0))


func _on_thermal(active: bool) -> void:
	_thermal = active


func _on_hunt_ended(result: HuntResult) -> void:
	var text: String = ""
	var color: Color = COLOR_TEXT
	match result.outcome:
		HuntResult.Outcome.VICTORY:
			text = "Missão cumprida!"
			color = COLOR_GOOD
		HuntResult.Outcome.DEFEAT_CROP:
			text = "A lavoura foi destruída!"
			color = COLOR_DANGER
		HuntResult.Outcome.DEFEAT_DEATH:
			text = "Você foi abatido!"
			color = COLOR_DANGER
	if text != "":
		_end_msg.set_color(color)
		_end_msg.show_text(text, END_MSG_S)
	_crop_alert.visible = false
	_crop_attack = false


static func _money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "R$ " + digits + out
