extends RefCounted
## Signatures copied from docs/arquitetura.md sections 5 and 6, plus the comparison helpers.
## Used by tests/check_scripts.gd (R3 in section 13.3: drift of signatures).

const GAME_EVENTS_SIGNALS: Array[String] = [
	"hunt_started(request: HuntRequest)",
	"hunt_ended(result: HuntResult)",
	"hunt_paused_changed(paused: bool)",
	"hunt_abandon_requested()",
	"shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float)",
	"player_damaged(amount: float, source_position: Vector3, health_after: float)",
	"player_healed(amount: float, health_after: float)",
	"player_died()",
	"item_used(item_id: StringName, position: Vector3)",
	"thermal_vision_changed(active: bool)",
	"dog_command_requested()",
	"boar_spawned(boar_id: int, type_id: StringName, weight_kg: float)",
	"boar_hit(boar_id: int, zone: StringName, damage: float, hit_position: Vector3, shot_id: int)",
	"boar_state_changed(boar_id: int, state: StringName)",
	"boar_killed(kill: KillInfo)",
	"boar_counts_changed(killed: int, total: int)",
	"crop_health_changed(pct: float)",
	"crop_under_attack(active: bool)",
	"bait_placed(position: Vector3, duration_s: float)",
	"dog_state_changed(state: StringName)",
	"dog_health_changed(pct: float)",
	"dog_marked_boar(position: Vector3, duration_s: float)",
	"dog_command_executed(command: StringName)",
	"hud_message_requested(text: String, duration_s: float)",
	"wallet_changed(money: int, gold: int)",
	"inventory_changed()",
	"loadout_changed()",
	"progression_changed()",
	"settings_changed(key: String, value: Variant)",
	"touch_mode_changed(is_touch: bool)",
	# docs/multiplayer.md section 3.5
	"hunter_joined(slot: int, display_name: String)",
	"hunter_left(slot: int)",
	"hunter_died(slot: int)",
	"spectate_changed(slot: int)",
	"net_stall_changed(stalled: bool)",
	# docs/multiplayer.md section 4.7.9 (F8)
	"net_reconnect_changed(active: bool)",
	"hunter_away_changed(slot: int, away: bool)",
	# docs/horda.md section 4.1
	"horde_wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)",
	"horde_wave_progress(remaining: int, wave_total: int)",
	# docs/plano_horda_nivel2.md section 4.1 (horde level 2: downed / revive / ammo crates)
	"player_downed(bleed_out_s: float)",
	"player_revived(health: float)",
	"hunter_downed(slot: int)",
	"hunter_revived(slot: int, by_slot: int)",
	"ammo_picked_up(rounds: int)",
]

## docs/multiplayer.md section 3.4: autoload Net.
const NET_METHODS: Array[String] = [
	"is_configured() -> bool",
	"is_active() -> bool",
	"is_in_room() -> bool",
	"is_host() -> bool",
	"get_role() -> int",
	"get_room_state() -> int",
	"get_room_code() -> String",
	"get_room_link() -> String",
	"get_local_slot() -> int",
	"get_player_count() -> int",
	"get_roster() -> Array[NetPeerInfo]",
	"get_peer(slot: int) -> NetPeerInfo",
	"get_selected_map_id() -> StringName",
	"get_selected_contract_index() -> int",
	"get_link_path(slot: int) -> int",
	"create_room() -> void",
	"join_room(code: String) -> void",
	"leave_room() -> void",
	"set_ready(ready: bool) -> void",
	"host_select_contract(map_id: StringName, contract_index: int) -> bool",
	"host_start_hunt() -> bool",
	"take_url_room_code() -> String",
	"bind_world(world: HuntWorld) -> void",
	"unbind_world(world: HuntWorld) -> void",
	"flush() -> void",
	# approved by the coordination, outside the original section 3.4 (net.gd)
	"is_peer_absent(slot: int) -> bool",
	"get_hunt_seed() -> int",
	# docs/multiplayer.md section 4.7.9 (F8)
	"is_reconnecting() -> bool",
	"get_traffic() -> Dictionary",
	"debug_cut(duration_s: float, half_open: bool = false) -> void",
	# docs/horda.md section 9.1
	"host_select_mode(mode: StringName) -> bool",
	"get_selected_mode() -> StringName",
	# docs/plano_horda_nivel2.md section 4.8
	"host_select_horde_level(level: int) -> bool",
	"get_selected_horde_level() -> int",
]

const NET_SIGNALS: Array[String] = [
	"room_state_changed(state: int)",
	"room_error(code: StringName, message: String)",
	"roster_changed()",
	"hunt_go()",
]

## Enum name -> member names in declaration order (the order is the numeric value).
const NET_ENUMS: Dictionary = {
	"Role": ["OFFLINE", "HOST", "CLIENT"],
	"RoomState": ["NONE", "CONNECTING", "LOBBY", "LOADING", "IN_HUNT"],
	"Path": ["NONE", "RELAY", "RTC"],
}

const DATA_METHODS: Array[String] = [
	"reload() -> void",
	"get_load_errors() -> PackedStringArray",
	"get_game() -> Dictionary",
	"get_weapon(id: StringName) -> Dictionary",
	"get_weapon_ids() -> Array",
	"get_equipment(id: StringName) -> Dictionary",
	"get_equipment_ids() -> Array",
	"get_dog(id: StringName) -> Dictionary",
	"get_dog_ids() -> Array",
	"get_boar_type(id: StringName) -> Dictionary",
	"get_boar_type_ids() -> Array",
	"get_boar_rules() -> Dictionary",
	"get_map(id: StringName) -> Dictionary",
	"get_map_ids() -> Array",
	"get_contract(map_id: StringName, index: int) -> Dictionary",
	"get_contract_count(map_id: StringName) -> int",
	"get_gold_packages() -> Array",
	"get_gold_package(id: StringName) -> Dictionary",
	"get_pix_config() -> Dictionary",
	"get_item_def(id: StringName) -> Dictionary",
	"get_item_category(id: StringName) -> StringName",
	# docs/horda.md section 10.1
	"get_horde() -> Dictionary",
	# docs/plano_horda_nivel2.md section 3.1
	"get_horde_level_count() -> int",
	"get_horde_level(level: int) -> Dictionary",
	"get_horde_boar_type(type_id: StringName, level: int) -> Dictionary",
]

const PROFILE_METHODS: Array[String] = [
	"set_save_path(path: String) -> void",
	"load_or_create() -> void",
	"save() -> bool",
	"reset_progress() -> void",
	"get_money() -> int",
	"get_gold() -> int",
	"add_money(amount: int) -> void",
	"add_gold(amount: int) -> void",
	"owns(item_id: StringName) -> bool",
	"get_item_count(item_id: StringName) -> int",
	"can_buy(item_id: StringName) -> StringName",
	"buy(item_id: StringName) -> StringName",
	"get_loadout_weapons() -> Array",
	"set_loadout_weapon(slot: int, weapon_id: StringName) -> bool",
	"get_loadout_dog() -> StringName",
	"set_loadout_dog(dog_id: StringName) -> bool",
	"get_loadout_items() -> Array",
	"set_loadout_items(item_ids: Array) -> bool",
	"get_unlocked_contract_count(map_id: StringName) -> int",
	"is_contract_unlocked(map_id: StringName, index: int) -> bool",
	"is_contract_completed(map_id: StringName, index: int) -> bool",
	"get_stats() -> Dictionary",
	"build_hunt_request(map_id: StringName, contract_index: int) -> HuntRequest",
	"kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, map_id: StringName, contract_index: int) -> int",
	"contract_bonus(map_id: StringName, contract_index: int, crop_health_pct: float) -> int",
	"apply_hunt_result(result: HuntResult) -> void",
	"is_code_redeemed(code: String) -> bool",
	"mark_code_redeemed(code: String) -> void",
	"get_setting(key: String) -> Variant",
	"set_setting(key: String, value: Variant) -> void",
	# docs/horda.md section 10.1
	"horde_kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, level: int = 1) -> int",
	"horde_bonus(stock_pct: float, level: int = 1) -> int",
	# docs/arquitetura.md section 6.3 (1.3): onboarding hints
	"is_onboarding_active() -> bool",
	"is_hint_learned(hint_id: StringName) -> bool",
	"mark_hint_learned(hint_id: StringName) -> void",
]

const INPUT_SETUP_METHODS: Array[String] = [
	"register_actions() -> void",
	"is_touch_mode() -> bool",
	"set_touch_override(mode: String) -> void",
	"release_all_actions() -> void",
	# docs/arquitetura.md section 4 (1.3): fixed keys per item
	"get_item_action(item_id: StringName) -> StringName",
	"get_key_label(action_name: StringName) -> String",
]

const SFX_METHODS: Array[String] = [
	"has_sound(id: StringName) -> bool",
	"play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void",
	"play_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void",
	"play_loop(id: StringName, volume_db: float = 0.0) -> void",
	"stop_loop(id: StringName) -> void",
	"stop_all_loops() -> void",
	"unlock_audio() -> void",
	"set_bus_volume(bus: StringName, linear: float) -> void",
	"play_music(id: StringName, volume_db: float = 0.0, fade_s: float = 1.0) -> void",
	"stop_music(fade_s: float = 1.0) -> void",
	"is_music_playing(id: StringName = &\"\") -> bool",
]

const ROUTER_METHODS: Array[String] = [
	"goto(scene_path: String) -> void",
	"get_current_scene_path() -> String",
	"scene_has_music(scene_path: String) -> bool",
	"set_pending_request(request: HuntRequest) -> void",
	"get_pending_request() -> HuntRequest",
	"start_hunt(request: HuntRequest) -> void",
	"finish_hunt(result: HuntResult) -> void",
]

## autoload name -> [script path, methods, property names]
const AUTOLOADS: Dictionary = {
	"GameEvents": ["res://src/core/game_events.gd"],
	"Data": ["res://src/systems/data_registry.gd"],
	"Profile": ["res://src/systems/profile.gd"],
	"InputSetup": ["res://src/input/input_setup.gd"],
	"Sfx": ["res://assets/audio/sfx_library.gd"],
	"Router": ["res://src/systems/router.gd"],
	"Net": ["res://src/net/net.gd"],
}
const AUTOLOAD_ORDER: Array[String] = ["GameEvents", "Data", "Profile", "InputSetup", "Sfx", "Router", "Net"]

const ROUTER_PROPERTIES: Array[String] = ["selected_map_id", "selected_contract_index", "last_result"]
const PROFILE_CONSTANTS: Array[String] = ["SAVE_VERSION", "DEFAULT_SAVE_PATH"]
const INPUT_CONSTANTS: Array[String] = ["ACTIONS", "ITEM_ACTIONS"]

## Public classes of packages A, B and game-systems (6.8, 6.9, 6.10).
## name -> {path, base (script class name or native class), methods, signals, props, pkg (A, B, S or N)}
const CLASSES: Array[Dictionary] = [
	# --- Package A ---
	{"name": "Player", "path": "res://src/player/player.gd", "base": "PlayerBase", "pkg": "A",
		"methods": ["get_spectator() -> SpectatorCamera", "is_spectating() -> bool",
				# docs/horda.md section 7
				"get_weapon_count() -> int", "has_infinite_reserve() -> bool",
				# docs/arquitetura.md section 6.8 (1.5, HF6)
				"get_weapon_ids() -> Array[StringName]", "debug_set_health(hp: float) -> void"]},
	# docs/multiplayer.md 6.8 (F6): the view of a fallen local hunter. Created by Player only when an ally stands.
	{"name": "SpectatorCamera", "path": "res://src/player/spectator_camera.gd", "base": "Camera3D", "pkg": "A",
		"methods": ["begin(local: PlayerBase, world: HuntWorld, view_camera: Camera3D) -> void",
			"get_target_slot() -> int", "get_candidates() -> Array[PlayerBase]", "switch_target() -> bool",
			"is_active() -> bool"]},
	{"name": "Weapon", "path": "res://src/weapons/weapon.gd", "base": "Node", "pkg": "A"},
	{"name": "WeaponHolder", "path": "res://src/weapons/weapon_holder.gd", "base": "Node3D", "pkg": "A"},
	{"name": "Hitscan", "path": "res://src/weapons/hitscan.gd", "base": "RefCounted", "pkg": "A",
		"methods": ["cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_range_m: float, exclude: Array) -> Dictionary"]},
	# docs/arquitetura.md section 8.11 (1.3): direct use by id, no selection (selection_changed/next/get_selected_id/use_selected are gone)
	{"name": "ItemBelt", "path": "res://src/player/item_belt.gd", "base": "Node", "pkg": "A",
		"signals": ["counts_changed()", "binoculars_changed(active: bool)", "use_started(item_id: StringName, duration_s: float)",
			"use_finished(item_id: StringName)"],
		"methods": ["setup(request: HuntRequest, player: PlayerBase, world: HuntWorld) -> void",
			"has_item(item_id: StringName) -> bool", "get_usable_ids() -> Array[StringName]", "get_count(item_id: StringName) -> int",
			"use_item(item_id: StringName) -> bool", "cancel_use() -> void", "is_busy() -> bool",
			"get_busy_item() -> StringName", "get_busy_progress() -> float", "is_binoculars_active() -> bool",
			"get_binoculars_zoom() -> float", "set_binoculars(active: bool) -> void"]},
	# docs/arquitetura.md sections 6.8 and 8.4: the desktop item bar
	{"name": "Quickbar", "path": "res://src/hud/quickbar.gd", "base": "HBoxContainer", "pkg": "A",
		"methods": ["bind(items: ItemBelt) -> void", "set_dog_present(present: bool) -> void",
			"set_dog_state(state: StringName) -> void", "flash(slot_id: StringName, on: bool) -> void",
			"get_slot_ids() -> Array[StringName]"]},
	# docs/arquitetura.md sections 6.8 and 8.4: the logic of the first-hunt hints (no Control) and its banner.
	# HintDirector.OPENING (const) is not checked: the package-class check compares methods, props and signals only.
	{"name": "HintDirector", "path": "res://src/hud/hint_director.gd", "base": "Node", "pkg": "A",
		"signals": ["hint_shown(hint_id: StringName, text: String, slot_id: StringName)", "hint_hidden(hint_id: StringName)"],
		"methods": ["setup(player: PlayerBase, items: ItemBelt, world: HuntWorld) -> void", "is_active() -> bool",
			"get_current_hint() -> StringName", "get_queue() -> Array[StringName]",
			"get_shown_this_hunt() -> Array[StringName]"]},
	{"name": "HintBanner", "path": "res://src/hud/hint_banner.gd", "base": "PanelContainer", "pkg": "A",
		"methods": ["show_hint(text: String) -> void", "hide_hint() -> void", "is_showing() -> bool",
			"get_text() -> String"]},
	# docs/arquitetura.md sections 6.8 and 8.4 (1.3, HF3): the dog card of the HUD (a view, the Hud feeds it).
	{"name": "DogCard", "path": "res://src/hud/dog_card.gd", "base": "HBoxContainer", "pkg": "A",
		"methods": ["set_breed(dog_id: StringName) -> void", "set_state(state: StringName) -> void",
			"set_health_pct(pct: float) -> void", "set_touch(touch: bool) -> void", "get_state_text() -> String",
			"get_action_text() -> String", "get_breed_text() -> String"]},
	# docs/arquitetura.md sections 6.8 and 8.4 (1.5, HF6): the weapon panel and the wide health bar of the HUD (views, the
	# Hud feeds them). HealthStrip.HEIGHT_PX (const) is checked by tests/unit/test_weapon_health_hud.gd.
	{"name": "WeaponPanel", "path": "res://src/hud/weapon_panel.gd", "base": "VBoxContainer", "pkg": "A",
		"methods": ["set_weapons(weapon_ids: Array[StringName]) -> void", "set_active(index: int) -> void",
			"set_ammo(in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void",
			"set_reload(active: bool, progress: float) -> void", "set_touch(touch: bool) -> void",
			"get_weapon_ids() -> Array[StringName]", "get_active_index() -> int", "get_name_text() -> String",
			"get_mag_text() -> String", "get_reserve_text() -> String", "is_ammo_low() -> bool",
			"get_chip_key_text(index: int) -> String", "get_portrait_path() -> String", "is_row_visible() -> bool",
			# HF7: touch cards (the Hud feeds them, TouchControls handles the taps)
			"set_card_width(width_px: float) -> void",
			"set_weapon_ammo(index: int, in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void",
			"get_card_count() -> int", "get_card_weapon_indices() -> Array[int]", "is_cards_visible() -> bool"]},
	{"name": "HealthStrip", "path": "res://src/hud/health_strip.gd", "base": "Control", "pkg": "A",
		"methods": ["set_health(hp: float, max_hp: float) -> void", "set_vest(on: bool) -> void",
			"set_touch(touch: bool) -> void", "get_value_text() -> String", "get_fill_pct() -> float",
			"get_fill_color() -> Color", "has_vest() -> bool",
			# HF7: touch chip of the vest and the width the Hud gives the strip
			"set_touch_width(width_px: float) -> void", "set_vest_reduction(fraction: float) -> void",
			"get_vest_text() -> String", "get_chip_rect() -> Rect2"]},
	# docs/arquitetura.md sections 6.8 and 8.4 (1.3, HF4): objectives and key legend of the first hunts (views, the Hud feeds them).
	{"name": "ObjectivesPanel", "path": "res://src/hud/objectives_panel.gd", "base": "VBoxContainer", "pkg": "A",
		"methods": ["set_dog_present(present: bool) -> void", "set_drone_present(present: bool) -> void",
			"set_kills(killed: int, total: int) -> void", "set_crop_pct(pct: float) -> void",
			"mark_dog_ordered() -> void", "mark_drone_used() -> void", "set_touch(touch: bool) -> void",
			"get_row_ids() -> Array[StringName]", "get_row_text(row_id: StringName) -> String",
			"get_row_state(row_id: StringName) -> int", "get_kills_goal() -> int", "get_crop_min_pct() -> float"]},
	{"name": "ControlsLegend", "path": "res://src/hud/controls_legend.gd", "base": "VBoxContainer", "pkg": "A",
		"methods": ["set_items(item_ids: Array[StringName]) -> void", "set_dog_present(present: bool) -> void",
			"set_open(open: bool) -> void", "toggle() -> void", "is_open() -> bool",
			"get_row_ids() -> Array[StringName]", "get_key_text(row_id: StringName) -> String",
			"get_row_text(row_id: StringName) -> String", "get_tab_text() -> String"]},
	# docs/arquitetura.md sections 6.8 and 8.4 (1.4, HF5): the single table of marker shapes and colours of the compass
	# and the minimap. The KIND_*/COLOR_*/DRAW_ORDER constants are checked by tests/unit/test_compass_minimap.gd.
	{"name": "MapMarkers", "path": "res://src/hud/map_markers.gd", "base": "RefCounted", "pkg": "A",
		"methods": ["draw(ci: CanvasItem, kind: StringName, at: Vector2, color: Color, half_px: float) -> void",
			"color_of(kind: StringName) -> Color"]},
	{"name": "Compass", "path": "res://src/hud/compass.gd", "base": "Control", "pkg": "A",
		"props": ["objective", "objective_icon"],
		"methods": ["update_state(origin: Vector3, yaw_rad: float, marks: Array[Dictionary]) -> void",
			"bearing_of(dx: float, dz: float) -> float", "heading_deg_of(yaw_rad: float) -> int",
			"label_for(deg: int) -> String", "get_heading_deg() -> int", "get_heading_text() -> String"]},
	{"name": "Minimap", "path": "res://src/hud/minimap.gd", "base": "Control", "pkg": "A",
		"props": ["map_rect", "map_texture", "crop_rects", "dog_position", "dog_target", "marked", "revealed", "baits",
			"objective", "objective_icon", "allies", "ally_colors", "ally_yaws", "ally_down", "center_color"],
		"methods": ["update_player(origin: Vector3, yaw_rad: float) -> void", "is_in_view(world: Vector3) -> bool",
			"get_map_src_rect() -> Rect2", "get_map_dst_rect() -> Rect2"]},
	{"name": "Hud", "path": "res://src/hud/hud.gd", "base": "CanvasLayer", "pkg": "A",
		"methods": ["bind(player: PlayerBase, world: HuntWorld) -> void"]},
	{"name": "PauseOverlay", "path": "res://src/hud/pause_overlay.gd", "base": "CanvasLayer", "pkg": "A"},
	{"name": "TouchControls", "path": "res://src/hud/touch/touch_controls.gd", "base": "CanvasLayer", "pkg": "A",
		"methods": ["bind(player: Player) -> void", "set_dog_present(present: bool) -> void",
			"set_dog_state(state: StringName) -> void", "flash_slot(slot_id: StringName, on: bool) -> void",
			"get_button_center(action_name: StringName) -> Vector2", "get_button_radius(action_name: StringName) -> float",
			# docs/arquitetura.md section 8.4 (1.3, HF4)
			"set_action_labels(on: bool) -> void", "has_action_labels() -> bool",
			# HF7: PUBG-style layout (the Hud places the weapon cards and hands the rectangles over)
			"set_weapon_card_rects(rects: Array[Rect2], actions: Array[StringName] = []) -> void",
			"get_weapon_card_rects() -> Array[Rect2]", "get_bottom_block() -> Dictionary",
			"get_probe_buttons() -> Dictionary", "get_accessory_current() -> StringName",
			"get_accessory_ids() -> Array[StringName]", "is_accessory_menu_open() -> bool"],
		"signals": ["layout_changed()"]},
	{"name": "TouchJoystick", "path": "res://src/hud/touch/virtual_joystick.gd", "base": "Control", "pkg": "A"},
	# docs/multiplayer.md section 3.3 / 3.6: an ally in the world. The PlayerBase virtuals it overrides.
	{"name": "RemoteHunter", "path": "res://src/player/remote_hunter.gd", "base": "PlayerBase", "pkg": "A",
		"methods": ["is_local() -> bool", "is_present() -> bool", "get_display_name() -> String", "is_alive() -> bool",
			"net_write_state(out: StreamPeerBuffer) -> void", "net_apply_state(inp: StreamPeerBuffer) -> void"]},
	# --- Package B ---
	{"name": "HuntController", "path": "res://src/hunt/hunt_controller.gd", "base": "HuntWorld", "pkg": "B",
		"props": ["route_on_finish"],
			# docs/horda.md sections 4.2 and 5.6
			"methods": ["get_mode() -> StringName", "get_objective_position() -> Vector3", "get_horde_wave() -> int",
				"get_horde_wave_count() -> int", "get_horde_phase() -> StringName", "get_horde_countdown_s() -> float",
				"get_horde_wave_total() -> int", "get_horde_wave_remaining() -> int", "get_horde_waves_cleared() -> int",
				"debug_horde_start_next_wave() -> void", "get_horde_eat_point(boar_id: int) -> Vector2",
					# docs/arquitetura.md section 8.4 (1.3, HF3)
					"get_dog_target_position() -> Vector3",
					# docs/arquitetura.md sections 8.1 and 8.4 (1.4, HF5): the baked map image of the hunt
					"get_minimap_texture() -> Texture2D"]},
	# docs/horda.md section 5.2: internal to package B.
	{"name": "HordeDirector", "path": "res://src/hunt/horde_director.gd", "base": "Node", "pkg": "B",
		"signals": ["wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)",
			"wave_progress(remaining: int, wave_total: int)"],
		"methods": ["plan_waves(horde: Dictionary, player_count: int) -> Array",
			"setup(world: HuntController, spawner: BoarSpawner, horde: Dictionary, plan: Array) -> void",
			"begin() -> void", "skip_intermission() -> void", "get_wave() -> int", "get_wave_count() -> int",
			"get_phase() -> StringName", "get_countdown_s() -> float", "get_wave_total() -> int",
			"get_wave_remaining() -> int", "get_waves_cleared() -> int", "get_killed_before() -> int"]},
	# docs/plano_horda_nivel2.md section 4.4: the route around the corn and the barn (static, pure)
	{"name": "HordeRoute", "path": "res://src/boars/horde_route.gd", "base": "RefCounted", "pkg": "B",
		"methods": ["plan(from: Vector2, to: Vector2, obstacles: Array[Dictionary], corner_out_m: float) -> PackedVector2Array"]},
	{"name": "BoarSpawner", "path": "res://src/hunt/boar_spawner.gd", "base": "Node", "pkg": "B",
		"methods": ["scale_groups(groups: Array, player_count: int, coop: Dictionary) -> Array",
			"notify_shot(origin: Vector3, noise_radius_m: float) -> void",
			"release_wave(wave_index: int) -> void", "get_wave_total(wave_index: int) -> int",
			"get_wave_remaining(wave_index: int) -> int"]},
	{"name": "HuntHostSync", "path": "res://src/hunt/hunt_host_sync.gd", "base": "Node", "pkg": "B",
		"methods": ["setup(world: HuntController, spawner: BoarSpawner) -> void", "write_boars(out: StreamPeerBuffer) -> void",
			"take_events(out: StreamPeerBuffer) -> void", "queue_bait(at: Vector3, duration_s: float) -> void",
			"queue_message(target_slot: int, msg: int) -> void",
			"queue_hunt_end(outcome: int, crop_pct: float, duration_s: float, killed: int, total: int, entries: Array) -> void",
			"queue_death(boar: Boar, kill: KillInfo, killed: int, total: int) -> void",
			"apply_claim(from_slot: int, type: int, inp: StreamPeerBuffer, length: int) -> void",
			"queue_horde_wave(wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int) -> void",
			"write_horde_wave_replay(out: StreamPeerBuffer, wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int) -> void",
			# docs/plano_horda_nivel2.md section 4.8
			"queue_hunter_revived(target_slot: int, by_slot: int) -> void",
			"queue_ammo_crate(crate: int, available: bool, taker_slot: int) -> void",
			"write_ammo_crate_replay(out: StreamPeerBuffer, crate: int, available: bool) -> void"]},
	{"name": "HuntReplica", "path": "res://src/hunt/hunt_replica.gd", "base": "Node3D", "pkg": "B",
		"signals": ["kill_confirmed(kill: KillInfo, killed: int, total: int)", "bait_received(at: Vector3, duration_s: float)",
			"message_received(msg: int)", "hunt_end_received(outcome: int, crop_pct: float, killed: int, total: int, entries: Array)",
			"horde_wave_received(wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int)",
			# docs/plano_horda_nivel2.md section 4.8
			"hunter_revived_received(target_slot: int, by_slot: int)", "ammo_crate_received(crate: int, available: bool, taker_slot: int)"],
		"methods": ["setup(world: HuntWorld, heightmap: Heightmap, map_rect: Rect2, crop: CropManager) -> void",
			"render_time_ms() -> float", "apply_snapshot_boars(inp: StreamPeerBuffer, t_ms: int) -> void",
			"apply_event(type: int, inp: StreamPeerBuffer, length: int) -> void",
			"apply_crop_state(crop_pct: float, flags: int) -> void", "queue_bait_claim(at: Vector3) -> void",
			"take_claims(out: StreamPeerBuffer) -> void", "refresh_thermal() -> void", "is_thermal_on() -> bool",
			"get_alive_ids() -> PackedInt32Array", "get_puppet(boar_id: int) -> BoarPuppet",
			"get_boar_position(boar_id: int) -> Vector3", "get_boar_type(boar_id: int) -> StringName",
			"get_boar_zone_position(boar_id: int, zone: StringName) -> Vector3",
			"get_nearest_boar_position(from: Vector3) -> Vector3",
			# docs/plano_horda_nivel2.md section 4.8
			"queue_revive_claim(target_slot: int) -> void", "queue_ammo_crate_claim(crate: int) -> void"]},
	{"name": "BoarPuppet", "path": "res://src/boars/boar_puppet.gd", "base": "Node3D", "pkg": "B",
		"props": ["boar_id", "type_id", "weight_kg", "state", "wounded", "alive"],
		"signals": ["hit_by_local(puppet: BoarPuppet, hit: HitInfo)"],
		"methods": ["get_xz() -> Vector2", "get_yaw() -> float", "get_zone_position(zone: StringName) -> Vector3",
			"zone_multiplier(zone: StringName) -> float", "set_highlight(on: bool) -> void", "is_highlighted() -> bool",
			"push_sample(t_ms: float, xz: Vector2, yaw: float, st: int) -> void",
			"update_pose(render_t_ms: float, delta: float) -> void", "try_charge_hit(hunter: PlayerBase) -> bool",
			"play_hit_feedback(zone: StringName) -> void", "play_attack() -> void", "die(xz: Vector2, yaw: float) -> void"]},
	{"name": "FallbackPlayer", "path": "res://src/hunt/debug/fallback_player.gd", "base": "PlayerBase", "pkg": "B"},
	{"name": "MapRoot", "path": "res://src/world/map_root.gd", "base": "Node3D", "pkg": "B",
		"props": ["map_size_m", "grid_resolution", "terrain_seed", "height_amplitude_m", "base_flora"],
		"methods": ["build_flora(density: float, sync_layout: bool = false) -> void",
			"find_prop_spawn(prop_id: StringName) -> PropSpawn",
			# docs/arquitetura.md section 8.4 (1.4, HF5): the map image the minimap draws
			"build_minimap(cfg: Dictionary) -> void", "get_minimap_texture() -> Texture2D", "get_minimap_image() -> Image",
			# docs/plano_horda_nivel2.md section 4.3
			"set_horde_layout(on: bool) -> void", "get_farm_rect() -> Rect2",
			"get_horde_route_obstacles(avoid_crops: Array, crop_margin_m: float, corner_out_m: float) -> Array[Dictionary]"]},
	{"name": "Heightmap", "path": "res://src/world/heightmap.gd", "base": "RefCounted", "pkg": "B",
		"methods": ["get_height(x: float, z: float) -> float", "get_normal(x: float, z: float) -> Vector3",
			# docs/arquitetura.md section 8.5 (1.4, HF5): the grid itself, read only
			"get_grid_data() -> PackedFloat32Array"]},
	{"name": "Terrain", "path": "res://src/world/terrain.gd", "base": "Node3D", "pkg": "B",
		"methods": ["get_grid_mask() -> PackedColorArray"]},
	# docs/arquitetura.md sections 8.1 and 8.4 (1.4, HF5): the CPU-baked top-down image of the map (static helpers)
	{"name": "MinimapBaker", "path": "res://src/world/minimap_baker.gd", "base": "RefCounted", "pkg": "B",
		"methods": ["bake(map: MapRoot, cfg: Dictionary) -> Image",
			"world_to_pixel(map_rect: Rect2, image_px: int, x: float, z: float) -> Vector2i"]},
	{"name": "CropField", "path": "res://src/world/crop_field.gd", "base": "Marker3D", "pkg": "B",
		"props": ["size_m", "crop"]},
	{"name": "CropManager", "path": "res://src/world/crop_manager.gd", "base": "Node3D", "pkg": "B",
		"signals": ["patch_eaten(index: int)"],
		"methods": ["apply_eaten(indices: PackedInt32Array) -> void", "set_replicated_health(pct: float) -> void",
			"set_store_mode(on: bool) -> void", "is_store_mode() -> bool"]},
	{"name": "PropSpawn", "path": "res://src/world/prop_spawn.gd", "base": "Marker3D", "pkg": "B",
		"props": ["prop_id", "collision_size", "footprint_radius_m", "horde_collision_boxes", "horde_obstacle_circles"]},
	{"name": "WaterBody", "path": "res://src/world/water_body.gd", "base": "Marker3D", "pkg": "B",
		"props": ["radius_m", "depth_m"]},
	{"name": "FloraZone", "path": "res://src/world/flora_zone.gd", "base": "Marker3D", "pkg": "B",
		"props": ["radius_m", "counts"]},
	{"name": "FloraScatter", "path": "res://src/world/flora_scatter.gd", "base": "Node3D", "pkg": "B"},
	{"name": "ObstacleGrid", "path": "res://src/world/obstacle_grid.gd", "base": "RefCounted", "pkg": "B"},
	{"name": "Bait", "path": "res://src/world/bait.gd", "base": "Node3D", "pkg": "B"},
	{"name": "Steering", "path": "res://src/boars/steering.gd", "base": "RefCounted", "pkg": "B"},
	{"name": "Boar", "path": "res://src/boars/boar.gd", "base": "Node3D", "pkg": "B"},
	{"name": "BoarHerd", "path": "res://src/boars/boar_herd.gd", "base": "RefCounted", "pkg": "B"},
	# docs/multiplayer.md 3.7 / 6.5 (F7): one Dog per slot with a dog on the host; owner_slot 0 offline.
	{"name": "Dog", "path": "res://src/dogs/dog.gd", "base": "Node3D", "pkg": "B",
		"props": ["owner_slot"],
		"methods": ["setup(p_breed_id: StringName, world: HuntController, spawn_position: Vector3, p_owner_slot: int = 0) -> void",
			"command() -> void", "net_state_byte() -> int", "get_yaw() -> float", "is_local_owner() -> bool",
			"get_xz() -> Vector2", "get_health_pct() -> float", "leave() -> void",
				# docs/arquitetura.md section 8.4 (1.3, HF3): the boar the dog is after; INF = none
				"get_target_position() -> Vector3"]},
	# docs/multiplayer.md 6.5 (F7): the client replica of a host dog. Visual only.
	{"name": "DogPuppet", "path": "res://src/dogs/dog_puppet.gd", "base": "Node3D", "pkg": "B",
		"props": ["owner_slot", "breed_id", "state", "health_pct"],
		"methods": ["setup(p_owner_slot: int, p_breed_id: StringName, xz: Vector2, yaw: float, hm: Heightmap) -> void",
			"get_xz() -> Vector2", "get_yaw() -> float", "get_health_pct() -> float", "is_local_owner() -> bool",
			"set_local_owner(on: bool) -> void",
			"push_sample(t_ms: float, xz: Vector2, yaw: float, st: int, health: float) -> void",
			"update_pose(render_t_ms: float, delta: float) -> void", "play_command(cmd: int) -> void"]},
	# --- game-systems ---
	{"name": "Wallet", "path": "res://src/systems/wallet.gd", "base": "RefCounted", "pkg": "S",
		"props": ["money", "gold"],
		"methods": ["balance(currency: StringName) -> int", "can_afford(price: int, currency: StringName) -> bool",
			"spend(price: int, currency: StringName) -> bool", "add(amount: int, currency: StringName) -> void",
			"to_dict() -> Dictionary", "from_dict(d: Dictionary) -> Wallet"]},
	{"name": "Inventory", "path": "res://src/systems/inventory.gd", "base": "RefCounted", "pkg": "S",
		"props": ["owned_weapons", "owned_dogs", "items", "loadout_weapons", "loadout_dog", "loadout_items"],
		"methods": ["owns(id: StringName) -> bool", "get_count(id: StringName) -> int",
			"add_item(id: StringName, count: int) -> void", "remove_item(id: StringName, count: int) -> bool",
			"to_dict() -> Dictionary", "from_dict(d: Dictionary) -> Inventory"]},
	{"name": "Progression", "path": "res://src/systems/progression.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["unlocked_count(map_id: StringName) -> int", "is_unlocked(map_id: StringName, index: int) -> bool",
			"is_completed(map_id: StringName, index: int) -> bool",
			"mark_won(map_id: StringName, index: int, crop_pct: float) -> void",
			"to_dict() -> Dictionary", "from_dict(d: Dictionary) -> Progression"]},
	{"name": "Shop", "path": "res://src/systems/shop.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["check(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName",
			"buy(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName"]},
	{"name": "RewardCalculator", "path": "res://src/systems/reward_calculator.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["kill_reward(type_def: Dictionary, rules: Dictionary, weight_kg: float, killing_zone: StringName, one_shot: bool, contract_def: Dictionary) -> int",
			"contract_bonus(contract_def: Dictionary, crop_health_pct: float) -> int"]},
	{"name": "SaveService", "path": "res://src/systems/save_service.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["write(path: String, data: Dictionary) -> bool", "read(path: String) -> Dictionary",
			"migrate(data: Dictionary) -> Dictionary", "sanitize(data: Dictionary) -> Dictionary",
			"new_save() -> Dictionary"]},
	{"name": "PixBrCode", "path": "res://src/systems/pix/pix_br_code.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["crc16_ccitt(text: String) -> int",
			"build(pix_key: String, amount_brl: float, merchant_name: String, merchant_city: String, txid: String = \"***\", description: String = \"\") -> String",
			"sanitize(text: String, max_len: int) -> String"]},
	{"name": "PixGateway", "path": "res://src/systems/pix/pix_gateway.gd", "base": "RefCounted", "pkg": "S",
		"signals": ["redeem_completed(ok: bool, gold: int, message: String)"],
		"methods": ["get_payment_payload(package: Dictionary) -> String", "request_redeem(code: String) -> void",
			"is_secure() -> bool", "create_from_config(config: Dictionary) -> PixGateway"]},
	{"name": "OfflineRedeemGateway", "path": "res://src/systems/pix/offline_redeem_gateway.gd", "base": "PixGateway", "pkg": "S",
		"methods": ["is_secure() -> bool"]},
	{"name": "RedeemCode", "path": "res://src/systems/pix/redeem_code.gd", "base": "RefCounted", "pkg": "S",
		"methods": ["normalize(code: String) -> String",
			"generate(gold: int, nonce: String, secret: String) -> String",
			"parse(code: String, secret: String) -> int"]},
	{"name": "DonationService", "path": "res://src/systems/pix/donation_service.gd", "base": "RefCounted", "pkg": "S",
		"signals": ["redeem_finished(ok: bool, gold: int, message: String)"],
		"methods": ["_init(gateway: PixGateway = null)", "get_packages() -> Array",
			"get_pix_payload(package_id: StringName) -> String", "redeem(code: String) -> void"]},
	# --- F6 UI (docs/multiplayer.md 6.11): the loadout editor shared by Preparation and the lobby, and the lobby ---
	{"name": "LoadoutPanel", "path": "res://src/ui/common/loadout_panel.gd", "base": "VBoxContainer", "pkg": "S",
		"signals": ["changed()"],
		"methods": ["setup(root: Control, dog_locked_text: String = \"\") -> void", "refresh() -> void",
			"set_weapons_locked(text: String) -> void"]},
	{"name": "Lobby", "path": "res://src/ui/lobby/lobby.gd", "base": "Control", "pkg": "S",
		"methods": ["player_label(info: NetPeerInfo, slot: int, is_local: bool) -> String",
			"status_text(info: NetPeerInfo) -> String", "path_text(path: int) -> String",
			"dog_label(dog_id: StringName) -> String"]},
	# --- package N (src/net, internal: the contract of section 3.3 only names the classes; these are the entry
	# points that Net, the sandboxes and the tests call, so a rename shows up here) ---
	{"name": "NetSession", "path": "res://src/net/net_session.gd", "base": "RefCounted", "pkg": "N",
		"signals": ["state_changed(state: int)", "failed(code: StringName, message: String)", "roster_changed()",
			"hunt_go()", "stall_changed(stalled: bool)", "reconnect_changed(active: bool)"],
		"methods": ["setup(cfg: Dictionary, env: Dictionary) -> void", "get_role() -> int", "get_state() -> int",
			"get_code() -> String", "get_local_slot() -> int", "get_player_count() -> int",
			"get_roster() -> Array[NetPeerInfo]", "get_peer(slot: int) -> NetPeerInfo",
			"get_selected_map_id() -> StringName", "get_selected_contract_index() -> int", "get_rng_seed() -> int",
			"is_peer_absent(slot: int) -> bool", "get_link_path(slot: int) -> int", "create() -> void",
			"join(code: String) -> void", "leave() -> void", "process(delta: float) -> void", "set_ready(ready: bool) -> void",
			"host_select_contract(map_id: StringName, contract_index: int) -> bool", "host_start_hunt() -> bool",
			"bind_world(world: HuntWorld) -> void", "unbind_world(world: HuntWorld) -> void", "flush() -> void",
			"is_reconnecting() -> bool", "get_traffic() -> Dictionary",
			"debug_cut(duration_s: float, half_open: bool = false) -> void",
			"host_select_mode(mode: StringName) -> bool", "get_selected_mode() -> StringName",
			# docs/plano_horda_nivel2.md section 4.8
			"host_select_horde_level(level: int) -> bool", "get_selected_horde_level() -> int"]},
	{"name": "NetSignaling", "path": "res://src/net/net_signaling.gd", "base": "RefCounted", "pkg": "N",
		"methods": ["build_url(base: String, params: Dictionary) -> String",
			"open(url: String, cfg: Dictionary, now_ms: int) -> bool", "is_open() -> bool", "is_closed() -> bool",
			"poll(now_ms: int) -> void", "take_messages() -> Array", "take_relay() -> Array",
			"send_json(msg: Dictionary) -> bool", "flush() -> void",
			"send_relay(to_id: int, payload: PackedByteArray) -> bool", "close(now_ms: int, say_leave: bool = true) -> void",
			"probe(now_ms: int, timeout_ms: int) -> void"]},
	{"name": "NetLink", "path": "res://src/net/net_link.gd", "base": "RefCounted", "pkg": "N",
		"signals": ["path_changed()"],
		"methods": ["get_path() -> int", "is_lost() -> bool", "send_state(records: PackedByteArray) -> void",
			"send_events(records: PackedByteArray) -> void", "flush_now() -> void",
			"receive_relay(payload: PackedByteArray) -> void", "receive_frame(frame: PackedByteArray) -> void",
			"take_state() -> PackedByteArray", "take_events() -> Array", "poll(now_ms: int) -> void", "close() -> void"]},
	# NetRtc extends the inner class NetLink.Direct, whose global name is empty: the base check uses RefCounted.
	{"name": "NetRtc", "path": "res://src/net/net_rtc.gd", "base": "RefCounted", "pkg": "N",
		"methods": ["start(ice_servers: Array, offerer: bool, drop_ice: bool, signal_sink: Callable) -> bool",
			"handle_signal(data: Dictionary) -> void", "poll() -> void", "is_open() -> bool", "is_failed() -> bool",
			"send_state(frame: PackedByteArray) -> bool", "send_event(frame: PackedByteArray) -> bool",
			"take_frames() -> Array", "close() -> void"]},
	{"name": "NetLoopback", "path": "res://src/net/net_loopback.gd", "base": "RefCounted", "pkg": "N",
		"methods": ["attach(link_a: NetLink, link_b: NetLink, cfg: Dictionary, with_direct: bool = false) -> void",
			"open_direct() -> void", "fail_direct() -> void", "step() -> void"]},
]


## Classes the multiplayer contract plans (docs/multiplayer.md section 3.3) that may not exist yet.
## Only the names matter: they feed the layering rule of check_scripts (section 3.2) even before the file exists.
## Once a class is delivered, move it to CLASSES with its signatures (RemoteHunter, HuntHostSync, HuntReplica,
## BoarPuppet and the five classes of package N were moved in F4/F5; SpectatorCamera and LoadoutPanel in F6;
## DogPuppet in F7).
const PLANNED_NET_CLASSES: Array[String] = []
const PLANNED_A_CLASSES: Array[String] = []
const PLANNED_B_CLASSES: Array[String] = []
const PLANNED_S_CLASSES: Array[String] = []

## Additions of docs/multiplayer.md section 3.6 to src/core (the core classes themselves are listed in
## check_scripts.gd). name -> {path, base, methods, props, consts}. Constants compare by value.
const CORE_CLASSES: Array[Dictionary] = [
	{"name": "NetCodec", "path": "res://src/core/net_codec.gd", "base": "RefCounted",
		"methods": ["make_shot_id(slot: int, counter: int) -> int", "shot_slot(shot_id: int) -> int",
			"put_xz(out: StreamPeerBuffer, rect: Rect2, x: float, z: float) -> void",
			"get_xz(inp: StreamPeerBuffer, rect: Rect2) -> Vector2",
			"angle_to_u8(rad: float) -> int", "u8_to_angle(q: int) -> float",
			"angle_to_u16(rad: float) -> int", "u16_to_angle(q: int) -> float",
			"seq_newer(a: int, b: int) -> bool"],
		"consts": {"PROTOCOL_VERSION": 1, "LANE_STATE": 0, "LANE_EVENT": 1, "FRAME_HEADER_BYTES": 5,
			"RECORD_HEADER_BYTES": 3, "HUNTER_STATE_BYTES": 14, "NO_SLOT": 255,
			"L_READY": 0x10, "L_LOBBY": 0x11, "L_START": 0x12, "L_LOADED": 0x13, "L_GO": 0x14, "L_NEED_RELAY": 0x15,
			"H_SNAPSHOT": 0x20, "EV_BOAR_SPAWN": 0x21, "EV_BOAR_HIT": 0x22, "EV_BOAR_ATTACK": 0x23,
			"EV_BOAR_DEATH": 0x24, "EV_CROP_EATEN": 0x25, "EV_BAIT": 0x26, "EV_DOG_MARK": 0x27, "EV_DOG_CMD": 0x28,
			"EV_MESSAGE": 0x29, "EV_HUNT_END": 0x2A, "EV_FULL_SYNC": 0x2B, "EV_HORDE_WAVE": 0x2C, "MAX_BOARS_PER_HUNT": 255,
			# docs/plano_horda_nivel2.md section 4.1
			"EV_HUNTER_REVIVED": 0x2D, "EV_AMMO_CRATE": 0x2E,
			"C_STATE": 0x40, "C_SHOT": 0x41, "C_CHARGE_HIT": 0x42, "C_BAIT": 0x43, "C_DOG_CMD": 0x44,
			"C_REVIVE": 0x45, "C_AMMO_CRATE": 0x46,
			"HF_CROUCH": 1, "HF_AIM": 2, "HF_SPRINT": 4, "HF_ALIVE": 8, "HF_RELOAD": 16, "HF_UNARMED": 32, "HF_AWAY": 64,
			"HF_DOWNED": 128}},
	{"name": "NetPeerInfo", "path": "res://src/core/net_peer_info.gd", "base": "RefCounted",
		"props": ["slot", "display_name", "is_host", "ready", "loaded", "weapon_id", "dog_id", "path"]},
	{"name": "HunterVisualBase", "path": "res://src/core/hunter_visual_base.gd", "base": "Node3D",
		"methods": ["setup(slot: int, weapon_id: StringName) -> void", "play_death(instant: bool = false) -> void",
			"slot_color(slot: int) -> Color"]},
	{"name": "HuntRequest", "path": "res://src/core/hunt_request.gd", "base": "RefCounted", "props": ["player_count", "mode", "horde_level"],
		"methods": ["make_debug(p_map_id: StringName = &\"mato_grosso\", p_contract_index: int = 0, p_mode: StringName = &\"contract\", p_horde_level: int = 1) -> HuntRequest",
			"is_horde() -> bool"]},
	{"name": "HuntResult", "path": "res://src/core/hunt_result.gd", "base": "RefCounted",
		"props": ["counts_for_progression", "player_count", "team_kills", "scoreboard", "mode", "horde_wave_count", "horde_waves_cleared", "horde_level"],
		"methods": ["is_horde() -> bool"]},
	{"name": "KillInfo", "path": "res://src/core/kill_info.gd", "base": "RefCounted", "props": ["killer_slot"]},
	{"name": "HitInfo", "path": "res://src/core/hit_info.gd", "base": "RefCounted", "props": ["shooter_slot"]},
	{"name": "ScenePaths", "path": "res://src/core/scene_paths.gd", "base": "RefCounted",
		"consts": {"LOBBY": "res://src/ui/lobby/lobby.tscn", "REMOTE_HUNTER": "res://src/player/remote_hunter.tscn",
			"BARN_CORN": "res://assets/models/props/barn_corn.tscn",
			"AMMO_CRATE": "res://assets/models/props/ammo_crate.tscn"}},
	{"name": "PlayerBase", "path": "res://src/core/player_base.gd", "base": "CharacterBody3D", "props": ["slot"],
		"methods": ["get_weapon_count() -> int", "has_infinite_reserve() -> bool",
			# docs/plano_horda_nivel2.md section 4.1 (revive, ammo crates, bot interact)
			"is_downed() -> bool", "revive(health: float) -> void", "get_bleed_out_left_s() -> float",
			"needs_ammo() -> bool", "add_ammo_mags(mags: int) -> int", "get_revive_target_slot() -> int",
			"get_revive_progress() -> float", "bot_set_interact(held: bool) -> void",
			# Q4 (owner): the ammo crate is taken with a press of interact
			"get_ammo_crate_target() -> int",
			"setup_remote(slot: int, display_name: String, weapon_id: StringName, world: HuntWorld) -> void",
			"is_local() -> bool", "is_present() -> bool", "get_display_name() -> String",
			"net_write_state(out: StreamPeerBuffer) -> void", "net_apply_state(inp: StreamPeerBuffer) -> void"]},
	{"name": "HuntWorld", "path": "res://src/core/hunt_world.gd", "base": "Node3D",
		"methods": ["get_hunters() -> Array[PlayerBase]", "get_hunter(slot: int) -> PlayerBase",
			"get_local_slot() -> int",
			"net_write_snapshot(out: StreamPeerBuffer) -> void", "net_apply_snapshot(inp: StreamPeerBuffer) -> void",
			"net_take_events(out: StreamPeerBuffer) -> void",
			"net_apply_event(type: int, inp: StreamPeerBuffer, length: int) -> void",
			"net_take_claims(out: StreamPeerBuffer) -> void",
			"net_apply_claim(slot: int, type: int, inp: StreamPeerBuffer, length: int) -> void",
			"net_peer_left(slot: int) -> void", "net_connection_lost() -> void",
			"net_write_full_sync(out: StreamPeerBuffer) -> void",
			# docs/horda.md section 4.2
			"get_mode() -> StringName", "is_horde() -> bool", "get_objective_position() -> Vector3",
			"get_horde_wave() -> int", "get_horde_wave_count() -> int", "get_horde_phase() -> StringName",
			"get_horde_countdown_s() -> float", "get_horde_wave_total() -> int", "get_horde_wave_remaining() -> int",
			"get_horde_waves_cleared() -> int", "debug_horde_start_next_wave() -> void",
			# docs/arquitetura.md section 8.4 (1.3, HF3): INF = no dog target (the default)
			"get_dog_target_position() -> Vector3",
			# docs/arquitetura.md section 8.4 (1.4, HF5): null = the world has no map image
			"get_minimap_texture() -> Texture2D",
			# docs/plano_horda_nivel2.md section 4.1: 0 / Rect2() / no-op / empty outside horde level 2
			"get_horde_level() -> int", "get_player_bounds() -> Rect2", "request_revive(target_slot: int) -> void",
			"get_ammo_crate_positions() -> PackedVector3Array",
			# Q4 (owner): crate in reach (-1 = none) and the press of interact that takes it
			"get_ammo_crate_in_reach(at: Vector3) -> int", "request_ammo_crate(crate: int) -> void"]},
	{"name": "CornStockVisualBase", "path": "res://src/core/corn_stock_visual_base.gd", "base": "Node3D",
		"methods": ["stage_for(pct: float) -> int", "setup(ring_radius_m: float) -> void", "set_stock_pct(pct: float) -> void",
			"set_under_attack(on: bool) -> void", "create_fallback() -> CornStockVisualBase"],
		"consts": {"STAGE_COUNT": 5, "FALLBACK_HEAPS": 6}},
	{"name": "Ids", "path": "res://src/core/ids.gd", "base": "RefCounted",
		"consts": {"MODE_CONTRACT": &"contract", "MODE_HORDE": &"horde", "HP_INTERMISSION": &"intermission", "HP_WAVE": &"wave"}},
]


# --------------------------------------------------------------------------------------------
# Parsing and comparing
# --------------------------------------------------------------------------------------------

static func parse(spec: String) -> Dictionary:
	var open: int = spec.find("(")
	var close: int = spec.rfind(")")
	var arrow: int = spec.rfind("->")
	if arrow > 0:
		close = spec.rfind(")", arrow)
	var out: Dictionary = {"name": spec.substr(0, open).strip_edges(), "args": [], "ret": ""}
	if arrow > 0:
		out["ret"] = spec.substr(arrow + 2).strip_edges()
	var inner: String = spec.substr(open + 1, close - open - 1).strip_edges()
	if inner != "":
		for part: String in _split_top_level(inner):
			var p: String = part.strip_edges()
			var default_idx: int = p.find(" = ")
			var has_default: bool = default_idx >= 0
			if has_default:
				p = p.substr(0, default_idx)
			var colon: int = p.find(":")
			(out["args"] as Array).append({
				"name": p.substr(0, colon).strip_edges(),
				"type": p.substr(colon + 1).strip_edges(),
				"default": has_default,
			})
	return out


static func _split_top_level(text: String) -> Array[String]:
	var parts: Array[String] = []
	var depth: int = 0
	var in_str: bool = false
	var cur: String = ""
	for ch: String in text:
		if ch == "\"":
			in_str = not in_str
		if not in_str:
			if ch == "[" or ch == "(":
				depth += 1
			elif ch == "]" or ch == ")":
				depth -= 1
			elif ch == "," and depth == 0:
				parts.append(cur)
				cur = ""
				continue
		cur += ch
	parts.append(cur)
	return parts


## Variant.Type for a contract type name; -1 = any (Variant), -2 = unknown class name (object).
static func type_code(type_name: String) -> int:
	if type_name.begins_with("Array["):   # typed arrays are TYPE_ARRAY in the method list
		return TYPE_ARRAY
	match type_name:
		"int", "HuntResult.Outcome":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"bool":
			return TYPE_BOOL
		"String":
			return TYPE_STRING
		"StringName":
			return TYPE_STRING_NAME
		"Vector2":
			return TYPE_VECTOR2
		"Vector3":
			return TYPE_VECTOR3
		"Rect2":
			return TYPE_RECT2
		"Dictionary":
			return TYPE_DICTIONARY
		"Array":
			return TYPE_ARRAY
		"Color":
			return TYPE_COLOR
		"PackedStringArray":
			return TYPE_PACKED_STRING_ARRAY
		"PackedInt32Array":
			return TYPE_PACKED_INT32_ARRAY
		"PackedByteArray":
			return TYPE_PACKED_BYTE_ARRAY
		"Callable":
			return TYPE_CALLABLE
		"PackedVector3Array":
			return TYPE_PACKED_VECTOR3_ARRAY
		"PackedVector2Array":
			return TYPE_PACKED_VECTOR2_ARRAY
		"PackedFloat32Array":
			return TYPE_PACKED_FLOAT32_ARRAY
		"PackedColorArray":
			return TYPE_PACKED_COLOR_ARRAY
		"Vector2i":
			return TYPE_VECTOR2I
		"Variant":
			return -1
	return TYPE_OBJECT


static func _type_name(code: int) -> String:
	return type_string(code) if code >= 0 else "any"


## Compares one method entry (from get_method_list / get_script_method_list) against a spec.
## Returns "" when it matches, otherwise a human readable difference.
static func compare_method(entry: Dictionary, spec: Dictionary) -> String:
	var problems: PackedStringArray = PackedStringArray()
	var args: Array = entry.get("args", [])
	var spec_args: Array = spec["args"]
	if args.size() != spec_args.size():
		problems.append("%d parametros (esperado %d)" % [args.size(), spec_args.size()])
	else:
		for i: int in args.size():
			var want: Dictionary = spec_args[i]
			var got: Dictionary = args[i]
			var want_code: int = type_code(want["type"])
			var got_code: int = int(got.get("type", TYPE_NIL))
			var got_name: String = str(got.get("name", "")).trim_prefix("_")
			if got_name != want["name"]:
				problems.append("parametro %d chama '%s' (esperado '%s')" % [i, got_name, want["name"]])
			if want_code >= 0 and got_code != want_code and not (want_code == TYPE_OBJECT and got_code == TYPE_OBJECT):
				problems.append("parametro '%s' e %s (esperado %s)" % [want["name"], _type_name(got_code), want["type"]])
			elif want_code == TYPE_OBJECT and got_code == TYPE_OBJECT:
				var cls: String = str(got.get("class_name", ""))
				if cls != "" and cls != want["type"] and not _derives(cls, want["type"]):
					problems.append("parametro '%s' e %s (esperado %s)" % [want["name"], cls, want["type"]])
		var defaults: Array = entry.get("default_args", [])
		var want_defaults: int = 0
		for a: Dictionary in spec_args:
			if a["default"]:
				want_defaults += 1
		if defaults.size() != want_defaults:
			problems.append("%d valores padrao (esperado %d)" % [defaults.size(), want_defaults])
	var ret_name: String = spec["ret"]
	if ret_name != "" and entry.has("return"):
		var ret: Dictionary = entry["return"]
		var ret_code: int = int(ret.get("type", TYPE_NIL))
		var is_variant: bool = (int(ret.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT) != 0
		if ret_name == "void":
			if ret_code != TYPE_NIL or is_variant:
				problems.append("retorno nao e void")
		elif ret_name != "Variant":
			var want_ret: int = type_code(ret_name)
			if ret_code != want_ret and not (is_variant and ret_code == TYPE_NIL):
				problems.append("retorno e %s (esperado %s)" % [_type_name(ret_code), ret_name])
	return "; ".join(problems)


static func _derives(cls: String, base: String) -> bool:
	if ClassDB.class_exists(cls):
		return ClassDB.is_parent_class(cls, base)
	return false


static func find_method(entries: Array[Dictionary], name: String) -> Dictionary:
	for e: Dictionary in entries:
		if str(e.get("name", "")) == name:
			return e
	return {}


static func find_signal(entries: Array[Dictionary], name: String) -> Dictionary:
	for e: Dictionary in entries:
		if str(e.get("name", "")) == name:
			return e
	return {}


## Same as compare_method but for signals (no defaults, no return).
static func compare_signal(entry: Dictionary, spec: Dictionary) -> String:
	var as_method: Dictionary = {"args": entry.get("args", []), "default_args": []}
	var spec_copy: Dictionary = spec.duplicate(true)
	spec_copy["ret"] = ""
	for a: Dictionary in spec_copy["args"]:
		a["default"] = false
	return compare_method(as_method, spec_copy)
