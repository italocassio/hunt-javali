class_name Hud
extends CanvasLayer
## In-hunt HUD (docs 8.4). Reads the player directly every frame, polls the world at 10 Hz and listens to
## GameEvents for everything else. Owns the touch layer and the pause overlay as children.

const POLL_INTERVAL_S: float = 0.1
const MARGIN_PX: int = 24
const TOUCH_TOPLEFT_MARGIN_PX: int = 100      # leaves room for the touch pause button
const OBJECTIVES_TOP_PX: int = 132            # below the crop bar of the compass column
const TOUCH_OBJECTIVES_LEFT_PX: int = 128     # right of the touch zoom slider (x 32..116)
const HEALTH_BOTTOM_PX: float = 14.0          # gap between the health strip and the bottom edge
const BOTTOM_STACK_GAP_PX: float = 8.0        # gap between the health strip and the item bar above it
const QUICKBAR_BOTTOM_PX: float = HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX + BOTTOM_STACK_GAP_PX
## Touch (HF7): the health bar sits 8 px above the bottom edge and the weapon cards 6 px above the bar, centred in the
## block TouchControls derives from the free width (cards 167 px wide, down to 130 px on a 1280 px screen).
const TOUCH_HEALTH_BOTTOM_PX: float = 8.0
const TOUCH_CARDS_GAP_PX: float = 6.0
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
const HORDE_WON_TEXT: String = "Celeiro defendido!"
const HORDE_LOST_TEXT: String = "O celeiro foi devorado!"
const HORDE_BANNER_S: float = 3.0
## The wave banner hangs below the crop panel (its real bottom edge, read at runtime): gap and height in pixels at the
## 720 px reference height. It must end above the context message text (band starts at CONTEXT_TOP_FRAC).
const HORDE_BANNER_GAP_PX: float = 8.0
const HORDE_BANNER_HEIGHT_PX: float = 40.0
const SOUND_WAVE_START: StringName = &"horde_wave_start"
const SOUND_WAVE_CLEAR: StringName = &"horde_wave_clear"
const ALLY_MSG_S: float = 3.0
## Horde level 2 (docs/plano_horda_nivel2.md section 5): counted ammo, crates, downed and revive.
const AMMO_EMPTY_TEXT: String = "Sem munição: pegue cartuchos no celeiro."
const AMMO_LAST_TEXT: String = "Última carga: pegue cartuchos no celeiro."
const AMMO_PICKUP_TEXT: String = "+%d cartuchos"
const AMMO_WARN_S: float = 3.0
const AMMO_PICKUP_S: float = 1.5
const AMMO_OK: int = 0
const AMMO_LAST: int = 1
const AMMO_EMPTY: int = 2
const REVIVE_PROMPT_KEYS: String = "Segure %s para levantar %s"
const REVIVE_PROMPT_TOUCH: String = "Segure Levantar para ajudar %s"
const REVIVE_BAR_TEXT: String = "Levantando %s…"
const REVIVE_PROMPT_FONT_PX: int = 24
## Ammo crate in reach (owner's Q4: taken with a press of interact): same place and style as the RevivePrompt, never
## at the same time (a revive target wins). Touch: the key is the "Pegar" button of TouchControls.
const AMMO_PROMPT_TEXT: String = "Aperte %s para pegar munição"
const AMMO_PROMPT_TOUCH_TEXT: String = "Toque em %s para pegar munição"
const REVIVE_PROMPT_TOP_FRAC: float = 0.54
const REVIVE_BAR_LABEL_TOP_FRAC: float = 0.565
const REVIVE_BAR_TOP_FRAC: float = 0.62
const REVIVE_BAR_W_PX: float = 280.0
const REVIVE_BAR_H_PX: float = 14.0
const DOWNED_TITLE_TEXT: String = "Você caiu!"
const DOWNED_HINT_TEXT: String = "Um companheiro pode te levantar."
const DOWNED_BLEED_TEXT: String = "Sangrando: %d s"
const DOWNED_TOP_FRAC: float = 0.34          # below the context message band, clear of the alerts above
const DOWNED_HINT_FONT_PX: int = 22
const DOWNED_HINT_HEIGHT_FRAC: float = 0.11
const HUNTER_DOWNED_KEYS_TEXT: String = "%s caiu! Vá até lá e segure %s."
const HUNTER_DOWNED_TOUCH_TEXT: String = "%s caiu! Vá até lá e segure Levantar."
const REVIVED_LOCAL_TEXT: String = "%s te levantou!"
const REVIVED_BY_LOCAL_TEXT: String = "Você levantou %s."
const REVIVED_OTHERS_TEXT: String = "%s levantou %s."
const REVIVE_MSG_S: float = 4.0
const COLOR_DOWNED_TINT: Color = Color("#7A0000", 0.35)
const STALL_TOP_FRAC: float = 0.16
const LOCAL_DOWN_TOP_FRAC: float = 0.30
## Context message band: starts below the "Javalis na lavoura!" alert (which ends near 0.27 of a 720 px height since the
## compass grew 10 px in 1.4) and above the hint banner (0.30).
const CONTEXT_TOP_FRAC: float = 0.25
const CONTEXT_HEIGHT_FRAC: float = 0.08
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
var _crop_rects: Array[Rect2] = []                 # plots of the contract, read once in bind (none in the horde)
var _crop_centers: PackedVector3Array = PackedVector3Array()   # centre of each plot, y = 0, same index as _crop_rects
var _revealed: PackedVector3Array = PackedVector3Array()
var _bait_points: PackedVector3Array = PackedVector3Array()
var _marked_points: PackedVector3Array = PackedVector3Array()
var _ended: bool = false
var _probe_enabled: bool = false   # Web build opened with ?probe=1 (QA hook, see _publish_probe)
var _probe_t: float = 0.0
var _thermal: bool = false
var _last_weapon_slot: int = -1       # slot the weapon panel shows (-1 until bind)
var _last_knife_equipped: bool = false   # F4 (0.9.9): the panel shows "Faca" while the knife is in the hand
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
var _downed: bool = false             # horde level 2: the local hunter is down and bleeding (player_downed .. revived/died)
var _bleed_limited: bool = false      # the fall came with a bleed-out time (bleed_out_s > 0)
var _ammo_state: Dictionary = {}      # weapon slot -> AMMO_OK / AMMO_LAST / AMMO_EMPTY seen last frame
var _ammo_warned: Dictionary = {}     # weapon slot -> true once "Última carga" was shown, until the reserve is refilled
var _ammo_warn_slot: int = NO_SLOT    # weapon slot the ammo warnings looked at last frame

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
var _crop_bar: ProgressBar = ProgressBar.new()
var _crop_label: Label = null
var _crop_alert: Label = null
var _count_label: Label = null
var _wave_label: Label = null
var _wave_banner: Label = null
var _crop_panel: PanelContainer = null
var _downed_overlay: ColorRect = null
var _downed_label: Label = null
var _downed_hint: Label = null
var _revive_prompt: Label = null
var _ammo_prompt: Label = null
var _revive_bar: ProgressBar = null
var _revive_bar_label: Label = null
var _dog_panel: PanelContainer = null
var _dog_card: DogCard = DogCard.new()
var _left_margin: MarginContainer = null
var _objectives: ObjectivesPanel = ObjectivesPanel.new()
var _objectives_panel: PanelContainer = null
var _legend: ControlsLegend = ControlsLegend.new()
var _legend_panel: PanelContainer = null
var _dog_breed: StringName = &""      # breed the card shows (from the hunt request)
var _weapon_panel: WeaponPanel = WeaponPanel.new()
var _weapon_frame: PanelContainer = null
var _frame_fallback_style: StyleBox = null   # the "panel" override _panel() sets when the theme has no HudPanel
var _weapon_nodes: Array[Weapon] = []        # the Weapon nodes of the player, slot order (cards show the pocket weapon too)
var _touch_layout: bool = false              # the touch layout is applied (cards, wide health bar)
var _health: HealthStrip = HealthStrip.new()
var _quickbar: Quickbar = Quickbar.new()
var _hint_banner: HintBanner = HintBanner.new()
var _director: HintDirector = HintDirector.new()
var _hint_slot: StringName = &""      # slot blinking for the hint on screen (&"" = none, e.g. the opening)
var _hints_enabled: bool = true       # false on the Web with ?hints=0 (QA hook, see _ready)
var _zoom_label: Label = null
var _touch: TouchControls = null
var _energy_flashing: bool = false            # F3: the energy drink hint is on (exhausted with drinks left)
var _energy_flash_touch: bool = false         # F3: it was started in touch mode (the Accessories button was switched)
var _energy_prev_accessory: StringName = &""  # F3: the accessory to go back to
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
	_build_downed_overlay()
	_crosshair.name = "Crosshair"
	_root.add_child(_crosshair)
	_build_top_left()
	_build_objectives()
	_build_top_center()
	_build_top_right()
	_build_weapon_panel()
	_build_health()
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
	_touch.layout_changed.connect(_on_touch_layout_changed)
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
	_weapon_panel.set_weapons(_player.get_weapon_ids())
	_weapon_panel.set_active(_player.get_weapon_slot())
	_last_weapon_slot = _player.get_weapon_slot()
	_weapon_nodes.clear()
	for weapon_id: StringName in _player.get_weapon_ids():
		_weapon_nodes.append(_player.get_node_or_null("Weapon_%s" % weapon_id) as Weapon)
	_health.set_vest(items != null and items.damage_reduction > 0.0)
	_health.set_vest_reduction(items.damage_reduction if items != null else 0.0)
	_apply_touch_bottom()
	_feed_card_ammo()
	if _world != null:
		_minimap.map_rect = _world.get_map_rect()
		_minimap.map_texture = _world.get_minimap_texture()
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
			_crop_rects = _world.get_crop_rects()
			_crop_centers.resize(0)
			for rect: Rect2 in _crop_rects:
				var center: Vector2 = rect.get_center()
				_crop_centers.append(Vector3(center.x, 0.0, center.y))
			_minimap.crop_rects = _crop_rects
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
	box.add_child(_fps_counter)   # alone in the corner: inherits the touch left margin, clear of the pause button


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
	_crop_panel = _panel(inner, 8)
	_crop_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_crop_panel)
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


## Weapon panel (docs §8.4): a HudPanel frame placed by _place_weapon_frame, bottom right on the desktop; on touch the
## frame loses its background and holds the weapon cards, bottom centre above the health bar.
func _build_weapon_panel() -> void:
	_weapon_frame = _panel(_weapon_panel, 8)
	_weapon_frame.name = "WeaponFrame"
	if _weapon_frame.has_theme_stylebox_override(&"panel"):
		_frame_fallback_style = _weapon_frame.get_theme_stylebox(&"panel")
	_root.add_child(_weapon_frame)


## Health strip (docs §8.4): bottom centre, HEALTH_BOTTOM_PX above the edge. It grows from its centre.
func _build_health() -> void:
	_health.name = "HealthStrip"
	_health.anchor_left = 0.5
	_health.anchor_right = 0.5
	_health.anchor_top = 1.0
	_health.anchor_bottom = 1.0
	_health.offset_left = 0.0
	_health.offset_right = 0.0
	_health.offset_top = -(HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX)
	_health.offset_bottom = -HEALTH_BOTTOM_PX
	_health.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_health.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_health)


## Item bar of the desktop (docs §8.4): bottom centre, above the health strip. It grows from its centre.
func _build_quickbar() -> void:
	_quickbar.name = "Quickbar"
	_quickbar.anchor_left = 0.5
	_quickbar.anchor_right = 0.5
	_quickbar.anchor_top = 1.0
	_quickbar.anchor_bottom = 1.0
	_quickbar.offset_left = 0.0
	_quickbar.offset_right = 0.0
	_quickbar.offset_top = -QUICKBAR_BOTTOM_PX - Quickbar.SLOT_SIZE_PX
	_quickbar.offset_bottom = -QUICKBAR_BOTTOM_PX
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
	_place_message(_ctx_msg, "ContextMessage", CONTEXT_TOP_FRAC, CONTEXT_HEIGHT_FRAC, 26)
	_place_message(_dog_msg, "DogMessage", 0.58, 0.08, 28)
	_dog_msg.set_color(COLOR_WARN)
	_place_message(_end_msg, "EndMessage", 0.38, 0.14, 44)
	_stall_banner = _make_banner("StallBanner", STALL_TEXT, STALL_TOP_FRAC, COLOR_WARN)
	_reconnect_banner = _make_banner("ReconnectBanner", RECONNECTING_TEXT, STALL_TOP_FRAC, COLOR_WARN)
	_down_banner = _make_banner("DownBanner", LOCAL_DOWN_TEXT, LOCAL_DOWN_TOP_FRAC, COLOR_DANGER)
	_spectate_banner = _make_banner("SpectateBanner", "", LOCAL_DOWN_TOP_FRAC, COLOR_TEXT)
	_spectate_hint = _make_banner("SpectateHint", SPECTATE_HINT_KEYS, LOCAL_DOWN_TOP_FRAC + BANNER_HEIGHT_FRAC, COLOR_TEXT)
	_spectate_hint.add_theme_font_size_override("font_size", SPECTATE_HINT_FONT_PX)
	_wave_banner = _make_banner("WaveBanner", "", 0.0, COLOR_TEXT)
	_wave_banner.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_build_revive_ui()


## Red veil of the fallen hunter (horde level 2), under every other element of the HUD.
func _build_downed_overlay() -> void:
	_downed_overlay = ColorRect.new()
	_downed_overlay.name = "DownedOverlay"
	_downed_overlay.color = COLOR_DOWNED_TINT
	_downed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_downed_overlay.visible = false
	_root.add_child(_downed_overlay)


## Revive prompt, hold bar and the "you fell" texts (horde level 2); all hidden until a state turns them on.
func _build_revive_ui() -> void:
	_downed_label = _make_banner("DownedLabel", DOWNED_TITLE_TEXT, DOWNED_TOP_FRAC, COLOR_DANGER)
	_downed_hint = _make_banner("DownedHint", DOWNED_HINT_TEXT, DOWNED_TOP_FRAC + BANNER_HEIGHT_FRAC, COLOR_TEXT)
	_downed_hint.add_theme_font_size_override("font_size", DOWNED_HINT_FONT_PX)
	_downed_hint.anchor_bottom = DOWNED_TOP_FRAC + BANNER_HEIGHT_FRAC + DOWNED_HINT_HEIGHT_FRAC
	_revive_prompt = _label("", REVIVE_PROMPT_FONT_PX)
	_revive_prompt.name = "RevivePrompt"
	_place_centered(_revive_prompt, REVIVE_PROMPT_TOP_FRAC, REVIVE_PROMPT_TOP_FRAC + BANNER_HEIGHT_FRAC)
	_revive_prompt.visible = false
	_root.add_child(_revive_prompt)
	_ammo_prompt = _label("", REVIVE_PROMPT_FONT_PX)
	_ammo_prompt.name = "AmmoPrompt"
	_place_centered(_ammo_prompt, REVIVE_PROMPT_TOP_FRAC, REVIVE_PROMPT_TOP_FRAC + BANNER_HEIGHT_FRAC)
	_ammo_prompt.visible = false
	_root.add_child(_ammo_prompt)
	_revive_bar_label = _label("", REVIVE_PROMPT_FONT_PX)
	_revive_bar_label.name = "ReviveBarLabel"
	_place_centered(_revive_bar_label, REVIVE_BAR_LABEL_TOP_FRAC, REVIVE_BAR_TOP_FRAC)
	_revive_bar_label.visible = false
	_root.add_child(_revive_bar_label)
	_revive_bar = ProgressBar.new()
	_revive_bar.name = "ReviveBar"
	_style_bar(_revive_bar, &"CropBar", REVIVE_BAR_H_PX, REVIVE_BAR_W_PX)
	_revive_bar.max_value = 1.0
	_revive_bar.step = 0.0
	_revive_bar.modulate = COLOR_WARN
	_revive_bar.anchor_left = 0.5
	_revive_bar.anchor_right = 0.5
	_revive_bar.anchor_top = REVIVE_BAR_TOP_FRAC
	_revive_bar.anchor_bottom = REVIVE_BAR_TOP_FRAC
	_revive_bar.offset_left = -REVIVE_BAR_W_PX * 0.5
	_revive_bar.offset_right = REVIVE_BAR_W_PX * 0.5
	_revive_bar.offset_top = 0.0
	_revive_bar.offset_bottom = REVIVE_BAR_H_PX
	_revive_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_revive_bar.visible = false
	_root.add_child(_revive_bar)


func _place_centered(l: Label, top_frac: float, bottom_frac: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_left = 0.2
	l.anchor_right = 0.8
	l.anchor_top = top_frac
	l.anchor_bottom = bottom_frac
	l.offset_left = 0.0
	l.offset_right = 0.0
	l.offset_top = 0.0
	l.offset_bottom = 0.0


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
	GameEvents.player_downed.connect(_on_player_downed)
	GameEvents.player_revived.connect(_on_player_revived)
	GameEvents.hunter_downed.connect(_on_hunter_downed)
	GameEvents.hunter_revived.connect(_on_hunter_revived)
	GameEvents.ammo_picked_up.connect(_on_ammo_picked_up)


func _apply_touch_layout(is_touch: bool) -> void:
	if _topleft_margin != null:
		_topleft_margin.add_theme_constant_override("margin_left", TOUCH_TOPLEFT_MARGIN_PX if is_touch else MARGIN_PX)
	_touch_layout = is_touch
	_weapon_panel.set_touch(is_touch)
	_apply_touch_bottom()
	_dog_card.set_touch(is_touch)
	if _left_margin != null:
		_left_margin.add_theme_constant_override("margin_left", TOUCH_OBJECTIVES_LEFT_PX if is_touch else MARGIN_PX)
		_refresh_onboarding_ui()
	if _spectate_hint != null:
		_spectate_hint.text = SPECTATE_HINT_TOUCH if is_touch else SPECTATE_HINT_KEYS % InputSetup.get_key_label(&"spectate_next")


## The bottom of the screen (docs §8.4): health bar, vest chip and weapon frame. Redone when the layout changes (touch
## mode, window size, TouchControls laying out again).
func _apply_touch_bottom() -> void:
	var block: Dictionary = _touch.get_bottom_block() if _touch != null else {}
	var touch_block: bool = _touch_layout and not block.is_empty()
	var card_w: float = float(block.get("card_w", WeaponPanel.CARD_W_DEFAULT_PX))
	_weapon_panel.set_card_width(card_w)
	_health.set_touch(_touch_layout)
	if touch_block:
		_health.set_touch_width(card_w * 2.0 + float(WeaponPanel.CARD_GAP_PX))
	_place_health(touch_block, block)
	_place_weapon_frame(touch_block, block)
	_sync_touch_cards()


## Health strip anchors: bottom centre, HEALTH_BOTTOM_PX above the edge, growing from its centre (desktop); on touch,
## as wide as the two cards, centred where the touch block says, TOUCH_HEALTH_BOTTOM_PX above the edge.
func _place_health(touch: bool, block: Dictionary) -> void:
	if touch:
		var width: float = float(block["card_w"]) * 2.0 + float(WeaponPanel.CARD_GAP_PX)
		_health.anchor_left = 0.0
		_health.anchor_right = 0.0
		_health.offset_left = float(block["center_x"]) - width * 0.5
		_health.offset_right = float(block["center_x"]) + width * 0.5
		_health.offset_top = -(TOUCH_HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX)
		_health.offset_bottom = -TOUCH_HEALTH_BOTTOM_PX
		_health.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		_health.anchor_left = 0.5
		_health.anchor_right = 0.5
		_health.offset_left = 0.0
		_health.offset_right = 0.0
		_health.offset_top = -(HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX)
		_health.offset_bottom = -HEALTH_BOTTOM_PX
		_health.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_health.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Weapon frame anchors (docs §8.4): bottom right with MARGIN_PX on the desktop (grows up and to the left); on touch,
## no background, exactly over its cards: above the health bar, centred where the touch block says.
func _place_weapon_frame(touch: bool, block: Dictionary) -> void:
	if _weapon_frame == null:
		return
	if touch:
		var rect: Rect2 = _touch_cards_frame_rect(block)
		_weapon_frame.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		_weapon_frame.anchor_left = 0.0
		_weapon_frame.anchor_right = 0.0
		_weapon_frame.anchor_top = 1.0
		_weapon_frame.anchor_bottom = 1.0
		_weapon_frame.offset_left = rect.position.x
		_weapon_frame.offset_right = rect.end.x
		_weapon_frame.offset_top = rect.position.y
		_weapon_frame.offset_bottom = rect.end.y
		_weapon_frame.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		if _frame_fallback_style != null:
			_weapon_frame.add_theme_stylebox_override(&"panel", _frame_fallback_style)
		else:
			_weapon_frame.remove_theme_stylebox_override(&"panel")
		_weapon_frame.anchor_left = 1.0
		_weapon_frame.anchor_right = 1.0
		_weapon_frame.anchor_top = 1.0
		_weapon_frame.anchor_bottom = 1.0
		_weapon_frame.offset_left = -float(MARGIN_PX)
		_weapon_frame.offset_right = -float(MARGIN_PX)
		_weapon_frame.offset_top = -float(MARGIN_PX)
		_weapon_frame.offset_bottom = -float(MARGIN_PX)
		_weapon_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Rectangle of the weapon frame on touch (x absolute, y relative to the bottom edge, so negative): as many cards as
## the panel shows (one or two), centred on the block.
func _touch_cards_frame_rect(block: Dictionary) -> Rect2:
	var card_w: float = float(block["card_w"])
	var count: int = maxi(_weapon_panel.get_card_count(), 1)
	var width: float = card_w * float(count) + float(WeaponPanel.CARD_GAP_PX) * float(count - 1)
	var bottom: float = -(TOUCH_HEALTH_BOTTOM_PX + HealthStrip.HEIGHT_PX + TOUCH_CARDS_GAP_PX)
	return Rect2(Vector2(float(block["center_x"]) - width * 0.5, bottom - WeaponPanel.CARD_H_PX),
		Vector2(width, WeaponPanel.CARD_H_PX))


## Tells TouchControls where the weapon cards are (this is the single source of the rectangles) and what a tap on
## each one presses: `weapon_<n>` of its weapon, nothing for the weapon in hand. With the knife in the hand (0.9.9)
## every card presses its `weapon_<n>`, so a tap on the active one puts the knife away. No cards: outside touch mode,
## in the spectator view, or without a weapon.
func _sync_touch_cards() -> void:
	if _touch == null or not is_inside_tree():
		return
	var rects: Array[Rect2] = []
	var actions: Array[StringName] = []
	var block: Dictionary = _touch.get_bottom_block()
	if _touch_layout and not block.is_empty() and _weapon_frame != null and _weapon_frame.visible:
		var frame: Rect2 = _touch_cards_frame_rect(block)
		var screen_h: float = get_viewport().get_visible_rect().size.y
		var indices: Array[int] = _weapon_panel.get_card_weapon_indices()
		var knife: bool = _player != null and _player.is_knife_equipped()
		for i: int in indices.size():
			rects.append(Rect2(Vector2(frame.position.x + float(i) * (float(block["card_w"]) + float(WeaponPanel.CARD_GAP_PX)),
				screen_h + frame.position.y), Vector2(float(block["card_w"]), WeaponPanel.CARD_H_PX)))
			var in_hand: bool = indices[i] == _weapon_panel.get_active_index() and not knife
			actions.append(&"" if in_hand else StringName("weapon_%d" % (indices[i] + 1)))
	_touch.set_weapon_card_rects(rects, actions)


func _on_touch_layout_changed() -> void:
	if _touch_layout:
		_apply_touch_bottom()


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null:
		return
	_update_health()
	_update_energy_hint()
	_update_weapon()
	_update_revive()
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
		_place_wave_banner()   # the panel may still be laid out when the banner first shows
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
## allies: [{slot, x, z}], items: {item_id: count}, busy_item, binoculars, hint, touch_buttons: {id: [x, y, r]},
## weapon_slot, accessory (item id of the Accessories button, "" = none), accessory_menu_open}, refreshed 10 times per second.
## touch_buttons ids: the action of each button (`fire`, `use_medkit`, ...) plus `fire_left`, `accessory_menu` (the tab),
## `accessory_item_<id>` (rows of the open list) and `weapon_card_<n>` (radius = half the card height). Solo: slot 0, role "offline", path "none", no allies.
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
	var touch_buttons: Dictionary = {}    # id -> [x, y, radius] in viewport px: buttons, accessory tab / list, weapon cards
	var probe_buttons: Dictionary = _touch.get_probe_buttons()
	for button_id: String in probe_buttons:
		var circle: Vector3 = probe_buttons[button_id]
		touch_buttons[button_id] = [snappedf(circle.x, 0.1), snappedf(circle.y, 0.1), snappedf(circle.z, 0.1)]
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
		"weapon_slot": _player.get_weapon_slot(),
		"accessory": String(_touch.get_accessory_current()),
		"accessory_menu_open": _touch.is_accessory_menu_open(),
	}
	JavaScriptBridge.eval("window.huntProbe = " + JSON.stringify(state) + ";", true)


func _update_health() -> void:
	_health.set_health(_player.get_health(), _player.get_max_health())
	_health.set_stamina(_player.get_stamina_frac(), _player.is_exhausted(), _player.get_stamina_recover_frac())


## F3 (docs/plano_faca_mochila_folego.md 2.7): while the hunter is exhausted and still has an energy drink, the drink
## blinks (Quickbar slot on desktop; on touch the Accessories button switches to it and blinks, and goes back to the
## previous accessory when the exhaustion ends or the drinks run out).
func _update_energy_hint() -> void:
	var items: ItemBelt = _player.get_items()
	var has_drink: bool = items != null and items.get_count(Ids.I_ENERGY_DRINK) > 0
	var want: bool = _player.is_alive() and _player.is_exhausted() and has_drink
	if want == _energy_flashing:
		return
	_energy_flashing = want
	if want:
		_energy_flash_touch = InputSetup.is_touch_mode()
		if _energy_flash_touch:
			_energy_prev_accessory = _touch.get_accessory_current()
			_touch.select_accessory(Ids.I_ENERGY_DRINK)
			_touch.flash_slot(Ids.I_ENERGY_DRINK, true)
		else:
			_quickbar.flash(Ids.I_ENERGY_DRINK, true)
		return
	_quickbar.flash(Ids.I_ENERGY_DRINK, false)
	_touch.flash_slot(Ids.I_ENERGY_DRINK, false)
	var prev: StringName = _energy_prev_accessory
	var prev_ok: bool = prev != &"" and prev != Ids.I_ENERGY_DRINK and _touch.get_accessory_ids().has(prev)
	prev_ok = prev_ok and items != null and items.get_count(prev) != 0
	if _energy_flash_touch and _touch.get_accessory_current() == Ids.I_ENERGY_DRINK and prev_ok:
		_touch.select_accessory(prev)
	_energy_flash_touch = false
	_energy_prev_accessory = &""


func _update_weapon() -> void:
	var w: Weapon = _player.get_weapon()
	if w == null:
		return
	var slot: int = _player.get_weapon_slot()
	if slot != _last_weapon_slot:
		_last_weapon_slot = slot
		_weapon_panel.set_active(slot)
		_apply_touch_bottom()   # the cards, the frame and the touch hit rectangles follow the weapon in hand
	var knife: bool = _player.is_knife_equipped()
	if knife != _last_knife_equipped:
		_last_knife_equipped = knife
		_weapon_panel.set_knife(knife)
		_sync_touch_cards()   # with the knife out, a tap on the active card goes back to that weapon
	_feed_card_ammo()
	_weapon_panel.set_ammo(w.ammo_in_mag, w.ammo_reserve, _player.has_infinite_reserve(), int(w.def.get("mag_size", 1)))
	_weapon_panel.set_reload(w.is_reloading(), w.get_reload_progress())
	_update_ammo_warning(w, slot)


## Touch cards show the magazine and reserve of every weapon carried, the one in the pocket too (read from the Weapon
## nodes of the player; the panel rewrites text only when a value changes).
func _feed_card_ammo() -> void:
	if not _touch_layout or _player == null:
		return
	var infinite: bool = _player.has_infinite_reserve()
	for i: int in _weapon_nodes.size():
		var carried: Weapon = _weapon_nodes[i]
		if carried != null:
			_weapon_panel.set_weapon_ammo(i, carried.ammo_in_mag, carried.ammo_reserve, infinite, int(carried.def.get("mag_size", 1)))


## Counted ammo (horde level 2 only): one message when the weapon in hand has only the magazine left ("Última carga",
## once per weapon until the reserve is refilled) and one when it has nothing at all ("Sem munição").
func _update_ammo_warning(w: Weapon, slot: int) -> void:
	if not _horde or _ended or _player.has_infinite_reserve() or not _player.is_alive():
		return
	var state: int = AMMO_OK
	if w.ammo_reserve <= 0:
		state = AMMO_EMPTY if w.ammo_in_mag <= 0 else AMMO_LAST
	var previous: int = int(_ammo_state.get(slot, AMMO_OK))
	var slot_changed: bool = slot != _ammo_warn_slot
	_ammo_warn_slot = slot
	_ammo_state[slot] = state
	match state:
		AMMO_OK:
			_ammo_warned.erase(slot)
		AMMO_LAST:
			if not _ammo_warned.has(slot):
				_ammo_warned[slot] = true
				_show_ctx(AMMO_LAST_TEXT, AMMO_WARN_S, COLOR_WARN)
		AMMO_EMPTY:
			if previous != AMMO_EMPTY or slot_changed:
				_show_ctx(AMMO_EMPTY_TEXT, AMMO_WARN_S, COLOR_DANGER)


## RevivePrompt and ReviveBar (horde level 2): the downed ally in reach and the hold progress, read from the player.
## Without a revive target, AmmoPrompt: the ammo crate a press of interact takes (get_ammo_crate_target).
func _update_revive() -> void:
	var target: int = _player.get_revive_target_slot() if _horde and not _ended and not _downed else NO_SLOT
	var crate: bool = target < 0 and _horde and not _ended and not _downed and _player.get_ammo_crate_target() >= 0
	if crate:
		if InputSetup.is_touch_mode():
			_ammo_prompt.text = AMMO_PROMPT_TOUCH_TEXT % TouchControls.INTERACT_LABEL_CRATE
		else:
			_ammo_prompt.text = AMMO_PROMPT_TEXT % InputSetup.get_key_label(&"interact")
	_ammo_prompt.visible = crate
	if target < 0:
		_revive_prompt.visible = false
		_revive_bar.visible = false
		_revive_bar_label.visible = false
		return
	var who: String = _hunter_name(target)
	var progress: float = _player.get_revive_progress()
	var holding: bool = progress > 0.0
	if holding:
		_revive_bar.value = progress
		_revive_bar_label.text = REVIVE_BAR_TEXT % who
	elif InputSetup.is_touch_mode():
		_revive_prompt.text = REVIVE_PROMPT_TOUCH % who
	else:
		_revive_prompt.text = REVIVE_PROMPT_KEYS % [InputSetup.get_key_label(&"interact"), who]
	_revive_prompt.visible = not holding
	_revive_bar.visible = holding
	_revive_bar_label.visible = holding


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
	# _marks is built back to front in MapMarkers.DRAW_ORDER: crop, bait, revealed, boar, dog_target, dog (allies last).
	_marks.clear()
	if not _horde:
		var view_pos: Vector3 = _view_hunter().global_position
		var view_xz: Vector2 = Vector2(view_pos.x, view_pos.z)
		for i: int in _crop_rects.size():
			if not _crop_rects[i].has_point(view_xz):   # the plot the hunter stands in needs no marker
				_marks.append({"pos": _crop_centers[i], "kind": MapMarkers.KIND_CROP})
	_bait_points.resize(0)
	for i: int in range(_baits.size() - 1, -1, -1):
		if float(_baits[i]["until"]) < now_s:
			_baits.remove_at(i)
	for b: Dictionary in _baits:
		_bait_points.append(b["pos"])
		_marks.append({"pos": b["pos"], "kind": MapMarkers.KIND_BAIT})
	_minimap.baits = _bait_points
	_revealed.resize(0)
	if _reveal_left > 0.0:
		for id: int in _world.get_alive_boar_ids():
			var bp: Vector3 = _world.get_boar_position(id)
			if bp.is_finite():
				_revealed.append(bp)
				_marks.append({"pos": bp, "kind": MapMarkers.KIND_REVEALED})
	_minimap.revealed = _revealed
	_marked_points.resize(0)
	var seen: PackedVector3Array = _world.get_marked_boar_positions()
	for p: Vector3 in seen:
		_marked_points.append(p)
		_marks.append({"pos": p, "kind": MapMarkers.KIND_BOAR})
	for i: int in range(_event_marks.size() - 1, -1, -1):
		if float(_event_marks[i]["until"]) < now_s:
			_event_marks.remove_at(i)
	for m: Dictionary in _event_marks:
		_marked_points.append(m["pos"])
		_marks.append({"pos": m["pos"], "kind": MapMarkers.KIND_BOAR})
	var dog_on: bool = _world.has_dog()
	_sync_dog_slots()
	if dog_on and not _dog_panel.visible:
		_dog_panel.visible = true
		_on_dog_health(_world.get_dog_health_pct())
		_on_dog_state(_world.get_dog_state())
	var dog_pos: Vector3 = _world.get_dog_position() if dog_on else Vector3.INF
	var request: HuntRequest = _player.get_request()
	if request != null and request.dog_id != _dog_breed:
		_dog_breed = request.dog_id
		_dog_card.set_breed(_dog_breed)
	if request != null and request.dog_id == Ids.D_CARAMELO and dog_on:
		var nearest: Vector3 = _world.get_nearest_boar_position(_player.global_position)
		if nearest.is_finite():
			_marks.append({"pos": nearest, "kind": MapMarkers.KIND_BOAR})
	# What the dog is after (not while it follows): a ring on the compass and on the minimap.
	var dog_target: Vector3 = Vector3.INF
	if dog_on and _world.get_dog_state() != Ids.DS_FOLLOW:
		dog_target = _world.get_dog_target_position()
	if dog_target.is_finite():
		_marks.append({"pos": dog_target, "kind": MapMarkers.KIND_DOG_TARGET})
	if dog_pos.is_finite():
		_marks.append({"pos": dog_pos, "kind": MapMarkers.KIND_DOG})
	_minimap.dog_position = dog_pos
	_minimap.dog_target = dog_target
	_minimap.marked = _marked_points
	if _horde:
		_poll_horde()
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
		var downed: bool = hunter.is_downed()
		var color: Color = HunterVisualBase.slot_color(hunter.slot)
		if not hunter.is_local() and not down:
			standing += 1
		_ally_points.append(hunter.global_position)
		_ally_colors.append(color)
		_ally_yaws.append(hunter.rotation.y)
		_ally_down.append(Minimap.ALLY_DOWN_DOWNED if downed else (1 if down else 0))
		_marks.append({"pos": hunter.global_position, "kind": &"ally", "color": color, "down": down, "downed": downed})
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
	_crop_rects = []
	_crop_centers.resize(0)
	if _objective_icon == null and AssetLoader.exists(ScenePaths.icon(&"barn")):
		_objective_icon = AssetLoader.load_resource(ScenePaths.icon(&"barn")) as Texture2D
	_minimap.objective_icon = _objective_icon
	_compass.objective_icon = _objective_icon
	_on_crop_health(_crop_pct)
	_refresh_wave_label()


func _poll_horde() -> void:
	_minimap.ammo_crates = _world.get_ammo_crate_positions()
	_refresh_downed_hint()
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
	_place_wave_banner()


## Anchors the wave banner under the crop panel, HORDE_BANNER_GAP_PX below its real bottom edge.
func _place_wave_banner() -> void:
	var panel_bottom: float = _crop_panel.global_position.y + _crop_panel.size.y - _root.global_position.y
	_wave_banner.anchor_top = 0.0
	_wave_banner.anchor_bottom = 0.0
	_wave_banner.offset_top = panel_bottom + HORDE_BANNER_GAP_PX
	_wave_banner.offset_bottom = _wave_banner.offset_top + HORDE_BANNER_HEIGHT_PX


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
	_set_downed(false)   # bled out: the fall banner below replaces the "you fell" texts
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
	_weapon_frame.visible = not on
	_sync_touch_cards()
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
	_set_downed(false)
	_revive_prompt.visible = false
	_ammo_prompt.visible = false
	_revive_bar.visible = false
	_revive_bar_label.visible = false


# ---------------------------------------------------------------------------
# Horde level 2: downed, revive and ammo events
# ---------------------------------------------------------------------------

## The local hunter went down (not dead yet): red veil, "Você caiu!" and the bleed-out countdown.
func _on_player_downed(bleed_out_s: float) -> void:
	_bleed_limited = bleed_out_s > 0.0
	_player_down = true
	_refresh_onboarding_ui()
	_set_downed(true)


func _on_player_revived(_health: float) -> void:
	_set_downed(false)
	_player_down = false
	_refresh_onboarding_ui()


func _set_downed(on: bool) -> void:
	_downed = on and not _ended
	if _downed_overlay == null:
		return
	_downed_overlay.visible = _downed
	_downed_label.visible = _downed
	_downed_hint.visible = _downed
	_crosshair.visible = not _downed and _spectate_slot == NO_SLOT   # nothing to aim at from the ground
	_refresh_downed_hint()


## Second line "Sangrando: N s" only when the fall has a time limit; refreshed by the 10 Hz poll.
func _refresh_downed_hint() -> void:
	if not _downed:
		return
	var text: String = DOWNED_HINT_TEXT
	if _bleed_limited and _player != null:
		text += "\n" + DOWNED_BLEED_TEXT % ceili(_player.get_bleed_out_left_s())
	_downed_hint.text = text


## An ally (any slot but ours) went down: where to go and what to hold.
func _on_hunter_downed(slot: int) -> void:
	if _ended or slot == Net.get_local_slot():
		return
	var text: String
	if InputSetup.is_touch_mode():
		text = HUNTER_DOWNED_TOUCH_TEXT % _hunter_name(slot)
	else:
		text = HUNTER_DOWNED_KEYS_TEXT % [_hunter_name(slot), InputSetup.get_key_label(&"interact")]
	_show_ctx(text, REVIVE_MSG_S, HunterVisualBase.slot_color(slot))


func _on_hunter_revived(slot: int, by_slot: int) -> void:
	if _ended:
		return
	var local: int = Net.get_local_slot()
	if slot == local:
		_show_ctx(REVIVED_LOCAL_TEXT % _hunter_name(by_slot), REVIVE_MSG_S, HunterVisualBase.slot_color(by_slot))
	elif by_slot == local:
		_show_ctx(REVIVED_BY_LOCAL_TEXT % _hunter_name(slot), REVIVE_MSG_S, HunterVisualBase.slot_color(slot))
	else:
		_show_ctx(REVIVED_OTHERS_TEXT % [_hunter_name(by_slot), _hunter_name(slot)], REVIVE_MSG_S,
			HunterVisualBase.slot_color(by_slot))


## Cartridges taken from a crate: the "last magazine" warnings may fire again once the reserve runs out again.
func _on_ammo_picked_up(rounds: int) -> void:
	_ammo_warned.clear()
	if not _ended:
		_show_ctx(AMMO_PICKUP_TEXT % rounds, AMMO_PICKUP_S, MapMarkers.COLOR_AMMO)


static func _money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "R$ " + digits + out
