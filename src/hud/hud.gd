class_name Hud
extends CanvasLayer
## In-hunt HUD (docs 8.4). Reads the player directly every frame, polls the world at 10 Hz and listens to
## GameEvents for everything else. Owns the touch layer and the pause overlay as children.

const POLL_INTERVAL_S: float = 0.1
const MARGIN_PX: int = 24
const TOUCH_TOPLEFT_MARGIN_PX: int = 100      # leaves room for the touch pause button
const TOUCH_BOTTOM_RIGHT_MARGIN_PX: int = 530 # leaves room for the touch buttons
const OBJECTIVES_TOP_PX: int = 132            # below the health panel and the crop bar of the compass column
const TOUCH_OBJECTIVES_LEFT_PX: int = 128     # right of the touch zoom slider (x 32..116)
const ALARM_REPEAT_S: float = 3.0
const PROBE_INTERVAL_S: float = 0.1
const PROBE_ROLES: Array[String] = ["offline", "host", "client"]   # Net.Role order
const PROBE_PATHS: Array[String] = ["none", "relay", "rtc"]          # Net.Path order
const DOG_MSG_S: float = 1.2
const END_MSG_S: float = 5.0
const HEAL_MSG_S: float = 1.5
const BLINK_HZ: float = 2.0
const CROP_WARN_PCT: float = 60.0
const CROP_DANGER_PCT: float = 30.0
const ALLY_KILL_TEXT: String = "%s abateu um javali: %s, %d kg"
const ALLY_NAME_FALLBACK: String = "Um caçador"
const HUNTER_LEFT_TEXT: String = "%s saiu da caçada."
const HUNTER_DOWN_TEXT: String = "%s foi derrubado."
const LOCAL_DOWN_TEXT: String = "Você foi derrubado. Aguarde o fim da caçada."
const STALL_TEXT: String = "Anfitrião sem resposta…"
const RECONNECTING_TEXT: String = "Reconectando…"
const RECONNECTED_TEXT: String = "Conexão restabelecida."
const HUNTER_AWAY_TEXT: String = "%s está reconectando…"
const HUNTER_BACK_TEXT: String = "%s voltou."
const ALL_DOWN_TEXT: String = "Todos os caçadores caíram!"
const DISCONNECTED_TEXT: String = "Conexão perdida."
const SPECTATE_TEXT: String = "Assistindo: %s"
const SPECTATE_HINT_TOUCH: String = "Toque em Tiro para trocar de caçador"
const SPECTATE_HINT_KEYS: String = "Clique ou %s para trocar de caçador"
const SPECTATE_HINT_FONT_PX: int = 20
const NO_SLOT: int = -1
const HORDE_CROP_TEXT: String = "Celeiro %d%%"
const HORDE_ALERT_TEXT: String = "Javalis no celeiro!"
const HORDE_LABEL_WAVE: String = "Onda %d/%d · faltam %d"
const HORDE_LABEL_INTERMISSION: String = "Onda %d/%d em %d s"
const HORDE_LABEL_NONE: String = "Onda –"
const HORDE_BANNER_FIRST: String = "Defenda o celeiro! A horda chega em %d s"
const HORDE_BANNER_WAVE: String = "Onda %d de %d"
const HORDE_BANNER_LAST: String = "Última onda! Onda %d de %d"
const HORDE_BANNER_CLEARED: String = "Onda %d vencida!"
const HORDE_AMMO_TEXT: String = "%d | ∞"
const HORDE_WON_TEXT: String = "Celeiro defendido!"
const HORDE_LOST_TEXT: String = "O celeiro foi devorado!"
const HORDE_BANNER_S: float = 3.0
const HORDE_BANNER_TOP_FRAC: float = 0.18
const SOUND_WAVE_START: StringName = &"horde_wave_start"
const SOUND_WAVE_CLEAR: StringName = &"horde_wave_clear"
const ALLY_MSG_S: float = 3.0
const STALL_TOP_FRAC: float = 0.16
const LOCAL_DOWN_TOP_FRAC: float = 0.30
const BANNER_HEIGHT_FRAC: float = 0.07
const BANNER_FONT_PX: int = 28
const COLOR_TEXT: Color = Color("#F4EFE6")
const COLOR_GOOD: Color = Color("#3FAF5A")
const COLOR_WARN: Color = Color("#F2C12E")
const COLOR_DANGER: Color = Color("#D9452B")
const COLOR_PANEL: Color = Color(0.12, 0.10, 0.086, 0.72)
const COLOR_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.55)

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
var _probe_enabled: bool = false   # Web build opened with ?probe=1 (QA hook, see _publish_probe)
var _probe_t: float = 0.0
var _thermal: bool = false
var _last_ammo_text: String = ""
var _dog_slots_on: bool = false       # the Quickbar / touch dog slot is currently shown
var _hunter_names: Dictionary = {}   # slot -> display name seen on hunter_joined (the roster forgets who left)
var _stall_banner: Label = null
var _reconnect_banner: Label = null   # takes the place of the stall banner while this client is reconnecting
var _stalled: bool = false
var _reconnecting: bool = false
var _down_banner: Label = null
var _spectate_banner: Label = null
var _spectate_hint: Label = null
var _spectate_slot: int = NO_SLOT     # the ally the spectator camera follows, NO_SLOT when not spectating
var _local_down: bool = false         # the "knocked down, wait" banner is wanted whenever nothing replaces it
var _ally_points: PackedVector3Array = PackedVector3Array()
var _ally_colors: PackedColorArray = PackedColorArray()
var _ally_yaws: PackedFloat32Array = PackedFloat32Array()
var _ally_down: PackedByteArray = PackedByteArray()
var _horde: bool = false              # horde layout on (docs/horda.md section 8); contract mode never turns it on
var _wave: int = 0
var _wave_count: int = 0
var _wave_phase: StringName = &""
var _wave_countdown_s: float = 0.0
var _wave_total: int = 0
var _wave_remaining: int = 0
var _banner_left_s: float = 0.0
var _crop_pct: float = 100.0
var _objective_icon: Texture2D = null
var _onboarding_ui: bool = false      # objectives, legend and touch labels wanted: hints on and one of the first hunts
var _player_down: bool = false        # the local hunter fell: nothing of the onboarding UI is shown any more

var _root: Control = Control.new()
var _scope: ScopeOverlay = ScopeOverlay.new()
var _damage: DamageIndicator = DamageIndicator.new()
var _crosshair: HudCrosshair = HudCrosshair.new()
var _compass: Compass = Compass.new()
var _minimap: Minimap = Minimap.new()
var _fps_counter: FpsCounter = FpsCounter.new()
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
var _wave_label: Label = null
var _wave_banner: Label = null
var _dog_panel: PanelContainer = null
var _dog_card: DogCard = DogCard.new()
var _left_margin: MarginContainer = null
var _objectives: ObjectivesPanel = ObjectivesPanel.new()
var _objectives_panel: PanelContainer = null
var _legend: ControlsLegend = ControlsLegend.new()
var _legend_panel: PanelContainer = null
var _dog_breed: StringName = &""      # breed the card shows (from the hunt request)
var _weapon_label: Label = null
var _ammo_label: Label = null
var _reload_bar: ProgressBar = ProgressBar.new()
var _quickbar: Quickbar = Quickbar.new()
var _hint_banner: HintBanner = HintBanner.new()
var _director: HintDirector = HintDirector.new()
var _hint_slot: StringName = &""      # slot blinking for the hint on screen (&"" = none, e.g. the opening)
var _hints_enabled: bool = true       # false on the Web with ?hints=0 (QA hook, see _ready)
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
	_build_objectives()
	_build_top_center()
	_build_top_right()
	_build_bottom_right()
	_build_messages()
	_build_quickbar()
	_root.add_child(_hint_banner)
	_director.hint_shown.connect(_on_hint_shown)
	_director.hint_hidden.connect(_on_hint_hidden)
	add_child(_director)
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
	if OS.has_feature("web"):
		_probe_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('probe') === '1'", true))
		_hints_enabled = not bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('hints') === '0'", true))


func bind(player: PlayerBase, world: HuntWorld) -> void:
	_player = player as Player
	_world = world
	if _player == null:
		push_error("Hud.bind: player is not a Player")
		return
	_touch.bind(_player)
	_pause.bind(_player)
	var items: ItemBelt = _player.get_items()
	_quickbar.bind(items)
	_vest_label.visible = items != null and items.damage_reduction > 0.0
	if _world != null:
		_minimap.map_rect = _world.get_map_rect()
		if _world.is_horde():
			_enter_horde_layout()
			_wave = _world.get_horde_wave()
			_wave_count = _world.get_horde_wave_count()
			_wave_phase = _world.get_horde_phase()
			_wave_countdown_s = _world.get_horde_countdown_s()
			_wave_total = _world.get_horde_wave_total()
			_wave_remaining = _world.get_horde_wave_remaining()
			_refresh_wave_label()
		else:
			_minimap.crop_rects = _world.get_crop_rects()
		_on_crop_health(_world.get_crop_health_pct())
		_on_counts(_world.get_boars_killed(), _world.get_boars_total())
		_sync_dog_slots()
	if _hints_enabled:
		_director.setup(_player, items, _world)   # before hunt_started: the controller binds the HUD first
	_setup_onboarding_ui(items)
	_update_health()
	_poll_world()


## Called by the Player (pause button, focus loss, lost pointer lock).
func open_pause() -> void:
	if _pause != null:
		_pause.open()


func on_hunt_ended() -> void:
	_ended = true
	_refresh_onboarding_ui()
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
	box.add_child(_fps_counter)   # under the health panel: inherits the touch left margin, clear of minimap and buttons


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
	# Keep the minimap at its minimum width so a wider WaveLabel does not stretch or shift it.
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_minimap)
	_count_label = _label("Javalis 0/0", 24)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_count_label)
	_wave_label = _label(HORDE_LABEL_NONE, 24)
	_wave_label.name = "WaveLabel"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_wave_label.visible = false
	box.add_child(_wave_label)
	_dog_card.name = "DogCard"
	_dog_panel = _panel(_dog_card, 8)
	_dog_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_dog_panel.visible = false
	box.add_child(_dog_panel)
	_legend.name = "ControlsLegend"
	_legend_panel = _panel(_legend, 8)
	_legend_panel.name = "LegendPanel"
	_legend_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_legend_panel.visible = false
	box.add_child(_legend_panel)


## Objectives of the first hunts (docs §8.4), left column under the health panel. Hidden until bind() decides.
func _build_objectives() -> void:
	var parts: Array = _corner("Objectives", Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
	_left_margin = parts[0]
	_left_margin.add_theme_constant_override("margin_top", OBJECTIVES_TOP_PX)
	var box: VBoxContainer = parts[1]
	_objectives.name = "ObjectivesPanel"
	_objectives_panel = _panel(_objectives, 8)
	_objectives_panel.name = "ObjectivesFrame"
	_objectives_panel.visible = false
	box.add_child(_objectives_panel)


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
	box.add_child(_panel(inner))


## Item bar of the desktop (docs §8.4): bottom centre, MARGIN_PX above the edge. It grows from its centre.
func _build_quickbar() -> void:
	_quickbar.name = "Quickbar"
	_quickbar.anchor_left = 0.5
	_quickbar.anchor_right = 0.5
	_quickbar.anchor_top = 1.0
	_quickbar.anchor_bottom = 1.0
	_quickbar.offset_left = 0.0
	_quickbar.offset_right = 0.0
	_quickbar.offset_top = -float(MARGIN_PX) - Quickbar.SLOT_SIZE_PX
	_quickbar.offset_bottom = -float(MARGIN_PX)
	_quickbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_quickbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_quickbar)


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
	_stall_banner = _make_banner("StallBanner", STALL_TEXT, STALL_TOP_FRAC, COLOR_WARN)
	_reconnect_banner = _make_banner("ReconnectBanner", RECONNECTING_TEXT, STALL_TOP_FRAC, COLOR_WARN)
	_down_banner = _make_banner("DownBanner", LOCAL_DOWN_TEXT, LOCAL_DOWN_TOP_FRAC, COLOR_DANGER)
	_spectate_banner = _make_banner("SpectateBanner", "", LOCAL_DOWN_TOP_FRAC, COLOR_TEXT)
	_spectate_hint = _make_banner("SpectateHint", SPECTATE_HINT_KEYS, LOCAL_DOWN_TOP_FRAC + BANNER_HEIGHT_FRAC, COLOR_TEXT)
	_spectate_hint.add_theme_font_size_override("font_size", SPECTATE_HINT_FONT_PX)
	_wave_banner = _make_banner("WaveBanner", "", HORDE_BANNER_TOP_FRAC, COLOR_TEXT)


## Persistent (non-fading) centered text, hidden until a state turns it on.
func _make_banner(node_name: String, text: String, top_frac: float, color: Color) -> Label:
	var l: Label = _label(text, BANNER_FONT_PX, color, &"HudBigLabel")
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.anchor_left = 0.1
	l.anchor_right = 0.9
	l.anchor_top = top_frac
	l.anchor_bottom = top_frac + BANNER_HEIGHT_FRAC
	l.offset_left = 0.0
	l.offset_right = 0.0
	l.offset_top = 0.0
	l.offset_bottom = 0.0
	l.visible = false
	_root.add_child(l)
	return l


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
	GameEvents.hunter_joined.connect(_on_hunter_joined)
	GameEvents.hunter_left.connect(_on_hunter_left)
	GameEvents.hunter_died.connect(_on_hunter_died)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.net_stall_changed.connect(_on_net_stall_changed)
	GameEvents.net_reconnect_changed.connect(_on_net_reconnect_changed)
	GameEvents.hunter_away_changed.connect(_on_hunter_away_changed)
	GameEvents.spectate_changed.connect(_on_spectate_changed)
	GameEvents.horde_wave_changed.connect(_on_horde_wave_changed)
	GameEvents.horde_wave_progress.connect(_on_horde_wave_progress)


func _apply_touch_layout(is_touch: bool) -> void:
	if _topleft_margin != null:
		_topleft_margin.add_theme_constant_override("margin_left", TOUCH_TOPLEFT_MARGIN_PX if is_touch else MARGIN_PX)
	if _bottomright_margin != null:
		_bottomright_margin.add_theme_constant_override("margin_right",
			TOUCH_BOTTOM_RIGHT_MARGIN_PX if is_touch else MARGIN_PX)
	_dog_card.set_touch(is_touch)
	if _left_margin != null:
		_left_margin.add_theme_constant_override("margin_left", TOUCH_OBJECTIVES_LEFT_PX if is_touch else MARGIN_PX)
		_refresh_onboarding_ui()
	if _spectate_hint != null:
		_spectate_hint.text = SPECTATE_HINT_TOUCH if is_touch else SPECTATE_HINT_KEYS % InputSetup.get_key_label(&"spectate_next")


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
	var view: PlayerBase = _view_hunter()   # the map is centred on whoever the camera is looking through
	var view_origin: Vector3 = view.global_position
	var view_yaw: float = view.rotation.y
	_compass.update_state(view_origin, view_yaw, _marks)
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
	if _probe_enabled:
		_probe_t -= delta
		if _probe_t <= 0.0:
			_probe_t = PROBE_INTERVAL_S
			_publish_probe()
	if _banner_left_s > 0.0:
		_banner_left_s -= delta
		if _banner_left_s <= 0.0:
			_wave_banner.visible = false
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_INTERVAL_S
		if _reveal_left > 0.0:
			_reveal_left = maxf(_reveal_left - POLL_INTERVAL_S, 0.0)
		_poll_world()
		_minimap.update_player(view_origin, view_yaw)


## QA hook for the Web build: window.huntProbe = {x, z, yaw_deg, pitch_deg, touch_mode, ammo_mag, health,
## joystick_active, sprinting, look_active, run_locked, t_ms, slot, role, path, boars_alive,
## allies: [{slot, x, z}], items: {item_id: count}, busy_item, binoculars, hint, touch_buttons: {action: [x, y, r]}},
## refreshed 10 times per second. Solo: slot 0, role "offline", path "none", no allies.
func _publish_probe() -> void:
	var allies: Array[Dictionary] = []
	var link_slot: int = -1
	var boars_alive: int = 0
	if _world != null:
		boars_alive = _world.get_alive_boar_ids().size()
		for hunter: PlayerBase in _world.get_hunters():
			if hunter.is_local():
				continue
			allies.append({"slot": hunter.slot, "x": snappedf(hunter.global_position.x, 0.001),
				"z": snappedf(hunter.global_position.z, 0.001)})
			if link_slot < 0:
				link_slot = hunter.slot
	if not Net.is_host():
		link_slot = 0   # a client's only link is the host
	var item_counts: Dictionary = {}      # item id -> count (-1: the binoculars)
	var busy_item: StringName = &""
	var binoculars: bool = false
	var items: ItemBelt = _player.get_items()
	if items != null:
		for item_id: StringName in items.get_usable_ids():
			item_counts[String(item_id)] = items.get_count(item_id)
		busy_item = items.get_busy_item()
		binoculars = items.is_binoculars_active()
	var touch_buttons: Dictionary = {}    # action -> [x, y, radius] in viewport px, every button that exists now
	for action_name: StringName in _touch.get_button_diameters():
		var center: Vector2 = _touch.get_button_center(action_name)
		touch_buttons[String(action_name)] = [snappedf(center.x, 0.1), snappedf(center.y, 0.1),
			snappedf(_touch.get_button_radius(action_name), 0.1)]
	var state: Dictionary = {
		"x": snappedf(_player.global_position.x, 0.001),
		"z": snappedf(_player.global_position.z, 0.001),
		"yaw_deg": snappedf(_player.rotation_degrees.y, 0.01),
		"pitch_deg": snappedf(_player.get_pitch_deg(), 0.01),
		"touch_mode": InputSetup.is_touch_mode(),
		"ammo_mag": _player.get_ammo_in_mag(),
		"health": snappedf(_player.get_health(), 0.1),
		"joystick_active": _touch.joystick.is_active(),
		"sprinting": _player.is_sprinting(),
		"look_active": _touch.look_pad.is_active(),
		"run_locked": _touch.joystick.run_locked,
		"t_ms": Time.get_ticks_msec(),
		"slot": _player.slot,
		"role": PROBE_ROLES[clampi(Net.get_role(), 0, PROBE_ROLES.size() - 1)],
		"path": PROBE_PATHS[clampi(Net.get_link_path(link_slot), 0, PROBE_PATHS.size() - 1)] if link_slot >= 0 else "none",
		"boars_alive": boars_alive,
		"allies": allies,
		"items": item_counts,
		"busy_item": String(busy_item),
		"binoculars": binoculars,
		"hint": String(_director.get_current_hint()),
		"touch_buttons": touch_buttons,
	}
	JavaScriptBridge.eval("window.huntProbe = " + JSON.stringify(state) + ";", true)


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
	var text: String = (HORDE_AMMO_TEXT % w.ammo_in_mag) if _player.has_infinite_reserve() \
		else ("%d | %d" % [w.ammo_in_mag, w.ammo_reserve])
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
	_sync_dog_slots()
	if dog_on and not _dog_panel.visible:
		_dog_panel.visible = true
		_on_dog_health(_world.get_dog_health_pct())
		_on_dog_state(_world.get_dog_state())
	var dog_pos: Vector3 = _world.get_dog_position() if dog_on else Vector3.INF
	if dog_pos.is_finite():
		_marks.append({"pos": dog_pos, "kind": &"dog"})
	var request: HuntRequest = _player.get_request()
	if request != null and request.dog_id != _dog_breed:
		_dog_breed = request.dog_id
		_dog_card.set_breed(_dog_breed)
	# What the dog is after (not while it follows): a ring on the compass and on the minimap.
	var dog_target: Vector3 = Vector3.INF
	if dog_on and _world.get_dog_state() != Ids.DS_FOLLOW:
		dog_target = _world.get_dog_target_position()
	if dog_target.is_finite():
		_marks.append({"pos": dog_target, "kind": &"dog_target"})
	if request != null and request.dog_id == Ids.D_CARAMELO and dog_on:
		var nearest: Vector3 = _world.get_nearest_boar_position(_player.global_position)
		if nearest.is_finite():
			_marks.append({"pos": nearest, "kind": &"boar"})
	_minimap.dog_position = dog_pos
	_minimap.dog_target = dog_target
	_minimap.marked = _marked_points
	_revealed.resize(0)
	if _reveal_left > 0.0:
		for id: int in _world.get_alive_boar_ids():
			var bp: Vector3 = _world.get_boar_position(id)
			if bp.is_finite():
				_revealed.append(bp)
	_minimap.revealed = _revealed
	if _horde:
		_poll_horde()
	_bait_points.resize(0)
	for i: int in range(_baits.size() - 1, -1, -1):
		if float(_baits[i]["until"]) < now_s:
			_baits.remove_at(i)
	for b: Dictionary in _baits:
		_bait_points.append(b["pos"])
	_minimap.baits = _bait_points
	_poll_allies()


## Whose eyes the compass and the minimap follow: the hunter the spectator camera is on, otherwise the local one.
func _view_hunter() -> PlayerBase:
	if _spectate_slot != NO_SLOT and _world != null:
		var followed: PlayerBase = _world.get_hunter(_spectate_slot)
		if followed != null and followed.slot == _spectate_slot:
			return followed
	return _player


## Allies on the minimap and the compass (docs/multiplayer.md 6.7): one marker per hunter other than the one in the
## centre, in the slot colour; the fallen are marked apart. While spectating, the local hunter's body shows as fallen.
func _poll_allies() -> void:
	_ally_points.resize(0)
	_ally_colors.resize(0)
	_ally_yaws.resize(0)
	_ally_down.resize(0)
	for i: int in range(_marks.size() - 1, -1, -1):   # also called outside the 10 Hz poll: never stack the marks
		if _marks[i]["kind"] == &"ally":
			_marks.remove_at(i)
	var standing: int = 0
	var spectating: bool = _spectate_slot != NO_SLOT
	for hunter: PlayerBase in _world.get_hunters():
		if hunter.is_local() and not spectating:
			continue   # solo, or the centre of the map
		if spectating and hunter.slot == _spectate_slot:
			continue   # the ally in the centre of the map
		var down: bool = not hunter.is_alive()
		var color: Color = HunterVisualBase.slot_color(hunter.slot)
		if not hunter.is_local() and not down:
			standing += 1
		_ally_points.append(hunter.global_position)
		_ally_colors.append(color)
		_ally_yaws.append(hunter.rotation.y)
		_ally_down.append(1 if down else 0)
		_marks.append({"pos": hunter.global_position, "kind": &"ally", "color": color, "down": down})
	_minimap.allies = _ally_points
	_minimap.ally_colors = _ally_colors
	_minimap.ally_yaws = _ally_yaws
	_minimap.ally_down = _ally_down
	_spectate_hint.visible = spectating and not _ended and standing > 0


## The dog slot of the Quickbar, the dog button of the touch layer and the dog rows of the objectives and of the
## legend exist only while the hunt has a dog.
func _sync_dog_slots() -> void:
	var present: bool = _world != null and _world.has_dog()
	if present == _dog_slots_on:
		return
	_dog_slots_on = present
	_quickbar.set_dog_present(present)
	_touch.set_dog_present(present)
	_objectives.set_dog_present(present)
	_legend.set_dog_present(present)


## Objectives, key legend and touch button names (docs §8.4): only in the first hunts (the same switch as the hints,
## so ?hints=0 turns them off too). Decided once per hunt, here; _refresh_onboarding_ui applies it.
func _setup_onboarding_ui(items: ItemBelt) -> void:
	_onboarding_ui = _hints_enabled and Profile.is_onboarding_active()
	if _onboarding_ui:
		var item_ids: Array[StringName] = items.get_usable_ids() if items != null else ([] as Array[StringName])
		_legend.set_items(item_ids)
		_objectives.set_drone_present(item_ids.has(Ids.I_SCOUT_DRONE))
	_refresh_onboarding_ui()


## Shows or hides what _setup_onboarding_ui allowed: gone with the hunt, with the fall and in the spectator view; the
## objectives also skip the horde (no fixed boar total, no crop); the legend skips touch (the buttons carry the names).
func _refresh_onboarding_ui() -> void:
	var show: bool = _onboarding_ui and not _ended and not _player_down and _spectate_slot == NO_SLOT
	var touch: bool = InputSetup.is_touch_mode()
	_objectives.set_touch(touch)
	_objectives_panel.visible = show and not _horde
	_legend_panel.visible = show and not touch
	_touch.set_action_labels(show)


## The help key opens and closes the legend (it is in the HUD because the tree pauses everything under it).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"help") and not event.is_echo() and _legend_panel != null and _legend_panel.visible:
		_legend.toggle()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _on_player_damaged(amount: float, source_position: Vector3, _health_after: float) -> void:
	_damage.add_hit(amount, source_position)


func _on_player_healed(amount: float, _health_after: float) -> void:
	_show_ctx("+%d de vida" % int(round(amount)), HEAL_MSG_S)


func _on_boar_hit(_boar_id: int, _zone: StringName, _damage_amount: float, _pos: Vector3, shot_id: int) -> void:
	if NetCodec.shot_slot(shot_id) != Net.get_local_slot():
		return   # an ally's hit: no marker, no sound
	if shot_id == _last_hit_shot:
		return   # shotgun pellets of one shot count once
	_last_hit_shot = shot_id
	_crosshair.flash_hit(false)
	Sfx.play(&"hit_marker")


func _on_boar_killed(kill: KillInfo) -> void:
	var type_name: String = String(Data.get_boar_type(kill.type_id).get("name", "Javali"))
	if kill.killer_slot != Net.get_local_slot():
		_show_ally_kill(kill, type_name)
		return
	var text: String = "%s abatido — %d kg · %s" % [type_name, int(round(kill.weight_kg)), _money(kill.reward_money)]
	if kill.clean_kill:
		text += " · Tiro limpo!"
	if kill.one_shot:
		text += " · Um tiro só!"
	_kill_msg.show_text(text, float(Data.get_game().get("hunt", {}).get("kill_message_s", 3.0)))
	_crosshair.flash_hit(true)
	Sfx.play(&"kill_confirm")


## Context-line message for a kill made by another hunter, tinted with that hunter's slot color.
func _show_ally_kill(kill: KillInfo, type_name: String) -> void:
	var peer: NetPeerInfo = Net.get_peer(kill.killer_slot)
	var who: String = peer.display_name if peer != null and peer.display_name != "" else ALLY_NAME_FALLBACK
	_show_ctx(ALLY_KILL_TEXT % [who, type_name, int(round(kill.weight_kg))],
		float(Data.get_game().get("hunt", {}).get("kill_message_s", 3.0)),
		HunterVisualBase.slot_color(kill.killer_slot))


func _show_ctx(text: String, duration_s: float, color: Color = COLOR_TEXT) -> void:
	_ctx_msg.set_color(color)
	_ctx_msg.show_text(text, duration_s)


func _on_counts(killed: int, total: int) -> void:
	_count_label.text = "Javalis %d/%d" % [killed, total]
	_objectives.set_kills(killed, total)


func _on_crop_health(pct: float) -> void:
	_crop_pct = pct
	_objectives.set_crop_pct(pct)
	_crop_bar.value = pct
	_crop_label.text = (HORDE_CROP_TEXT if _horde else "Lavoura %d%%") % int(round(pct))
	_crop_bar.modulate = COLOR_GOOD if pct > CROP_WARN_PCT else (COLOR_WARN if pct > CROP_DANGER_PCT else COLOR_DANGER)


func _on_crop_attack(active: bool) -> void:
	_crop_attack = active
	_crop_alert.visible = active
	_crop_alert.modulate.a = 1.0
	_alarm_t = 0.0


# ---------------------------------------------------------------------------
# Horde mode (docs/horda.md section 8)
# ---------------------------------------------------------------------------

## Idempotent: switches the top bar, alert, counter and map to the barn layout.
func _enter_horde_layout() -> void:
	if _horde:
		return
	_horde = true
	_refresh_onboarding_ui()
	_count_label.visible = false
	_wave_label.visible = true
	_crop_alert.text = HORDE_ALERT_TEXT
	_minimap.crop_rects = []
	if _objective_icon == null and AssetLoader.exists(ScenePaths.icon(&"barn")):
		_objective_icon = AssetLoader.load_resource(ScenePaths.icon(&"barn")) as Texture2D
	_minimap.objective_icon = _objective_icon
	_compass.objective_icon = _objective_icon
	_on_crop_health(_crop_pct)
	_refresh_wave_label()


func _poll_horde() -> void:
	var objective: Vector3 = _world.get_objective_position()
	_minimap.objective = objective
	_compass.objective = objective
	if _wave_phase == Ids.HP_INTERMISSION:
		_wave_countdown_s = _world.get_horde_countdown_s()
	_refresh_wave_label()


func _refresh_wave_label() -> void:
	if _wave_label == null:
		return
	if _wave_phase == Ids.HP_WAVE:
		_wave_label.text = HORDE_LABEL_WAVE % [_wave, _wave_count, _wave_remaining]
	elif _wave_phase == Ids.HP_INTERMISSION:
		_wave_label.text = HORDE_LABEL_INTERMISSION % [_wave, _wave_count, ceili(_wave_countdown_s)]
	else:
		_wave_label.text = HORDE_LABEL_NONE


func _show_wave_banner(text: String) -> void:
	_wave_banner.text = text
	_wave_banner.visible = not _ended
	_banner_left_s = HORDE_BANNER_S


func _play_wave_sound(id: StringName) -> void:
	if Sfx.has_sound(id):
		Sfx.play(id)


func _on_horde_wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float) -> void:
	_enter_horde_layout()
	_wave = wave
	_wave_count = wave_count
	_wave_phase = phase
	_wave_countdown_s = countdown_s
	if phase == Ids.HP_WAVE:
		_wave_remaining = _wave_total   # until the progress signal of this wave arrives
	_refresh_wave_label()
	if _ended:
		return
	if phase == Ids.HP_WAVE:
		_show_wave_banner((HORDE_BANNER_LAST if wave == wave_count else HORDE_BANNER_WAVE) % [wave, wave_count])
		_play_wave_sound(SOUND_WAVE_START)
	elif wave <= 1:
		_show_wave_banner(HORDE_BANNER_FIRST % ceili(countdown_s))
	else:
		_show_wave_banner(HORDE_BANNER_CLEARED % (wave - 1))
		_play_wave_sound(SOUND_WAVE_CLEAR)


func _on_horde_wave_progress(remaining: int, wave_total: int) -> void:
	_enter_horde_layout()
	_wave_remaining = remaining
	_wave_total = wave_total
	_refresh_wave_label()


func _on_bait_placed(position: Vector3, duration_s: float) -> void:
	_baits.append({"pos": position, "until": Time.get_ticks_msec() * 0.001 + duration_s})


func _on_dog_state(state: StringName) -> void:
	_quickbar.set_dog_state(state)
	_touch.set_dog_state(state)
	_dog_panel.visible = true
	_dog_card.set_state(state)


func _on_dog_health(pct: float) -> void:
	_dog_card.set_health_pct(pct)


func _on_dog_marked(position: Vector3, duration_s: float) -> void:
	_event_marks.append({"pos": position, "until": Time.get_ticks_msec() * 0.001 + duration_s})


func _on_dog_command(command: StringName) -> void:
	_dog_msg.show_text("Pega!" if command == Ids.CMD_ATTACK else "Volta!", DOG_MSG_S)
	if command == Ids.CMD_ATTACK:
		_objectives.mark_dog_ordered()


func _on_message(text: String, duration_s: float) -> void:
	_show_ctx(text, duration_s)


func _on_item_used(item_id: StringName, _position: Vector3) -> void:
	if item_id == Ids.I_SCOUT_DRONE:
		_reveal_left = float(Data.get_equipment(item_id).get("effect", {}).get("reveal_s", 0.0))
		_objectives.mark_drone_used()


func _on_thermal(active: bool) -> void:
	_thermal = active


## A contextual hint (§8.4): the text in the banner and, when it is about a slot, that slot blinks in both layouts.
func _on_hint_shown(_hint_id: StringName, text: String, slot_id: StringName) -> void:
	_hint_banner.show_hint(text)
	_set_hint_flash(_hint_slot, false)
	_hint_slot = slot_id
	_set_hint_flash(_hint_slot, true)


func _on_hint_hidden(_hint_id: StringName) -> void:
	_hint_banner.hide_hint()
	_set_hint_flash(_hint_slot, false)
	_hint_slot = &""


func _set_hint_flash(slot_id: StringName, on: bool) -> void:
	if slot_id == &"":
		return
	_quickbar.flash(slot_id, on)
	_touch.flash_slot(slot_id, on)


## Roster name first, then the one seen on hunter_joined, then the hunter node, then a generic fallback.
func _hunter_name(slot: int) -> String:
	var peer: NetPeerInfo = Net.get_peer(slot)
	if peer != null and peer.display_name != "":
		return peer.display_name
	var known: String = String(_hunter_names.get(slot, ""))
	if known != "":
		return known
	if _world != null:
		var hunter: PlayerBase = _world.get_hunter(slot)
		if hunter != null and hunter.slot == slot and hunter.get_display_name() != "":
			return hunter.get_display_name()
	return ALLY_NAME_FALLBACK


func _on_hunter_joined(slot: int, display_name: String) -> void:
	if display_name != "":
		_hunter_names[slot] = display_name


func _on_hunter_left(slot: int) -> void:
	if _ended:
		return
	_show_ctx(HUNTER_LEFT_TEXT % _hunter_name(slot), ALLY_MSG_S, HunterVisualBase.slot_color(slot))


func _on_hunter_died(slot: int) -> void:
	if _ended or slot == Net.get_local_slot():
		return   # the local fall has its own persistent banner (_on_player_died)
	_show_ctx(HUNTER_DOWN_TEXT % _hunter_name(slot), ALLY_MSG_S, HunterVisualBase.slot_color(slot))


## Local hunter fell. Online with an ally still up, the hunt goes on without input: say so until it ends.
func _on_player_died() -> void:
	_player_down = true
	_refresh_onboarding_ui()
	if _ended or _world == null:
		return   # solo has no allies, so the loop below never shows the banner there
	for hunter: PlayerBase in _world.get_hunters():
		if not hunter.is_local() and hunter.is_alive():
			_local_down = true
			_down_banner.visible = _spectate_slot == NO_SLOT
			return


## The spectator camera started following an ally, changed ally, or let go (NO_SLOT). While it is on: the weapon
## panel and the crosshair step aside, the banner names who is being watched and the map moves to that hunter.
func _on_spectate_changed(slot: int) -> void:
	_spectate_slot = slot
	_refresh_onboarding_ui()
	var on: bool = slot != NO_SLOT and not _ended
	_spectate_banner.visible = on
	if on:
		_spectate_banner.text = SPECTATE_TEXT % _hunter_name(slot)
		_spectate_banner.add_theme_color_override("font_color", HunterVisualBase.slot_color(slot))
	_down_banner.visible = _local_down and not on and not _ended
	_bottomright_margin.visible = not on
	_crosshair.visible = not on
	_minimap.center_color = HunterVisualBase.slot_color(slot) if slot != NO_SLOT else Minimap.COLOR_PLAYER
	if _world != null:
		_poll_allies()
		var view: PlayerBase = _view_hunter()
		if view != null:
			_minimap.update_player(view.global_position, view.rotation.y)
	else:
		_spectate_hint.visible = false


func _on_net_stall_changed(stalled: bool) -> void:
	_stalled = stalled
	_refresh_net_banners()


## The reconnection banner replaces the "host not answering" one while it is up; neither takes touch.
func _refresh_net_banners() -> void:
	_reconnect_banner.visible = _reconnecting and not _ended
	_stall_banner.visible = _stalled and not _reconnecting and not _ended


func _on_net_reconnect_changed(active: bool) -> void:
	var was: bool = _reconnecting
	_reconnecting = active
	_refresh_net_banners()
	if was and not active and not _ended:
		_show_ctx(RECONNECTED_TEXT, ALLY_MSG_S)


## An ally went quiet or came back (the host decides; docs/multiplayer.md 4.7.7). The local slot is never reported.
func _on_hunter_away_changed(slot: int, away: bool) -> void:
	if _ended or slot == Net.get_local_slot():
		return
	_show_ctx((HUNTER_AWAY_TEXT if away else HUNTER_BACK_TEXT) % _hunter_name(slot), ALLY_MSG_S,
		HunterVisualBase.slot_color(slot))


func _on_hunt_ended(result: HuntResult) -> void:
	_ended = true   # whichever of this and on_hunt_ended() runs first, the net banners and messages stop here
	_refresh_onboarding_ui()
	if _ctx_msg.get_text() == RECONNECTED_TEXT:
		_ctx_msg.clear()   # giving up must not read "connection restored" right before "connection lost"
	var text: String = ""
	var color: Color = COLOR_TEXT
	var online: bool = Net.get_role() != Net.Role.OFFLINE
	match result.outcome:
		HuntResult.Outcome.VICTORY:
			text = HORDE_WON_TEXT if _horde else "Missão cumprida!"
			color = COLOR_GOOD
		HuntResult.Outcome.DEFEAT_CROP:
			text = HORDE_LOST_TEXT if _horde else "A lavoura foi destruída!"
			color = COLOR_DANGER
		HuntResult.Outcome.DEFEAT_DEATH:
			text = ALL_DOWN_TEXT if online else "Você foi abatido!"
			color = COLOR_DANGER
		HuntResult.Outcome.DISCONNECTED:
			text = DISCONNECTED_TEXT
			color = COLOR_DANGER
	_stall_banner.visible = false
	_reconnect_banner.visible = false
	_down_banner.visible = false
	_spectate_banner.visible = false
	_spectate_hint.visible = false
	if text != "":
		_end_msg.set_color(color)
		_end_msg.show_text(text, END_MSG_S)
	_crop_alert.visible = false
	_crop_attack = false
	_wave_banner.visible = false
	_banner_left_s = 0.0


static func _money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "R$ " + digits + out
