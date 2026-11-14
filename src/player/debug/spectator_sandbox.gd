extends SandboxWorld
## Package A sandbox for F6: allies on the minimap and compass, the spectator camera and the HUD banner.
## Real Player + real Hud + three RemoteHunters fed through net_apply_state (the byte path of the network):
## slot 1 standing near, slot 2 fallen near, slot 3 standing outside the minimap range.
## Scenario: marker checks, the local fall, the spectator delay, the view, target switching by input, the followed
## ally falling and another leaving, then a solo Player that must never start a spectator.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/spectator_sandbox.tscn
## Command line (after "--"): --stage=minimap|spectate (checks that far, then keeps running, for screenshots; with
## tools/screenshot.gd use --frames=900 for the spectate stage so the capture comes after the checks), --cam.
## Not part of the game.

const SEND_INTERVAL_S: float = 0.1
const SETTLE_S: float = 0.6                  # the HUD polls at 10 Hz and remotes interpolate 150 ms behind
const AFTER_DEATH_S: float = 0.3
const TOLERANCE_M: float = 0.06
const TOLERANCE_RAD: float = 0.05
const TERRAIN_TEST_Y: float = 5.0
const NEAR_SLOT: int = 1
const DOWN_SLOT: int = 2
const FAR_SLOT: int = 3
const NEAR_POS: Vector3 = Vector3(25.0, 0.0, -10.0)
const DOWN_POS: Vector3 = Vector3(-30.0, 0.0, 20.0)
const FAR_POS: Vector3 = Vector3(-98.0, 0.0, -98.0)     # 138 m away: outside the minimap and the name tag range
const NEAR_YAW: float = 0.6
const DOWN_YAW: float = -1.2
const FAR_YAW: float = 2.4
const NAMES: Dictionary = {1: "Ana", 2: "Beto", 3: "Caio"}

var _remotes: Dictionary = {}                # slot -> RemoteHunter
var _remote_pos: Dictionary = {}
var _remote_yaw: Dictionary = {}
var _remote_alive: Dictionary = {}
var _hunters_list: Array[PlayerBase] = []
var _terrain_y: float = 0.0
var _last_send_ms: int = 0
var _passed: int = 0
var _failed: int = 0
var _spectate_log: Array[int] = []
var _stage: String = ""


class SoloStub extends HuntWorld:
	var hunter: PlayerBase = null

	func get_player() -> PlayerBase:
		return hunter


func _ready() -> void:
	super._ready()
	_stage = String(_args.get("stage", ""))
	GameEvents.spectate_changed.connect(func(slot: int) -> void: _spectate_log.append(slot))
	_hunters_list = [player] as Array[PlayerBase]
	_add_remote(NEAR_SLOT, NEAR_POS, NEAR_YAW, true)
	_add_remote(DOWN_SLOT, DOWN_POS, DOWN_YAW, false)
	_add_remote(FAR_SLOT, FAR_POS, FAR_YAW, true)
	_send_states()
	if _args.has("cam"):
		var cam: Camera3D = Camera3D.new()
		add_child(cam)
		cam.far = 300.0
		cam.look_at_from_position(Vector3(0.0, 40.0, 40.0), Vector3(0.0, 0.0, 0.0))
		cam.make_current()
	_run.call_deferred()


func _add_remote(slot: int, pos: Vector3, yaw: float, alive: bool) -> void:
	var packed: PackedScene = load(ScenePaths.REMOTE_HUNTER) as PackedScene
	var r: RemoteHunter = packed.instantiate() as RemoteHunter
	r.name = "Hunter_%d" % slot
	r.slot = slot
	add_child(r)
	r.setup_remote(slot, String(NAMES[slot]), Ids.W_CARBINE_22, self)
	_remotes[slot] = r
	_remote_pos[slot] = pos
	_remote_yaw[slot] = yaw
	_remote_alive[slot] = alive
	_hunters_list.append(r)


func _process(delta: float) -> void:
	super._process(delta)
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_send_ms >= roundi(SEND_INTERVAL_S * 1000.0):   # wall clock, like the remotes' interpolation
		_last_send_ms = now_ms
		_send_states()


func _send_states() -> void:
	for slot: int in _remotes.keys():
		var r: RemoteHunter = _remotes[slot]
		var out: StreamPeerBuffer = StreamPeerBuffer.new()
		var p: Vector3 = _remote_pos[slot]
		NetCodec.put_xz(out, get_map_rect(), p.x, p.z)
		out.put_16(roundi(p.y * 100.0))
		out.put_u16(NetCodec.angle_to_u16(float(_remote_yaw[slot])))
		out.put_8(0)
		out.put_u8(0)
		out.put_u8(NetCodec.HF_ALIVE if bool(_remote_alive[slot]) else 0)
		out.put_u8(Data.get_weapon_ids().find(Ids.W_CARBINE_22))
		out.put_u8(100 if bool(_remote_alive[slot]) else 0)
		out.put_u8(0)
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = out.data_array
		r.net_apply_state(inp)


# --- HuntWorld overrides -----------------------------------------------------------------------

func get_hunters() -> Array[PlayerBase]:
	return _hunters_list


func get_hunter(for_slot: int) -> PlayerBase:
	if for_slot == player.slot:
		return player
	return _remotes.get(for_slot) as PlayerBase


func get_height(_x: float, _z: float) -> float:
	return _terrain_y


# --- Scenario ----------------------------------------------------------------------------------

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


## Waits `seconds` of game time AND of wall-clock time: the remotes interpolate on the wall clock while the headless
## fixed-fps run is faster than real time.
func _wait(seconds: float) -> void:
	var game_until: float = _elapsed + seconds
	var real_until: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while _elapsed < game_until or Time.get_ticks_msec() < real_until:
		await get_tree().process_frame


func _wait_game(seconds: float) -> void:
	var until: float = _elapsed + seconds
	while _elapsed < until:
		await get_tree().process_frame


## The action is pressed right after process_frame, so the spectator's _process of that frame sees it as just pressed.
func _press(action_name: StringName) -> void:
	await get_tree().process_frame
	Input.action_press(action_name)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action_name)
	await get_tree().process_frame


func _hud() -> Hud:
	return player.get("_hud") as Hud


func _run() -> void:
	var delay_s: float = float(Data.get_game().get("coop", {}).get("spectate_delay_s", 2.0))
	var distance_m: float = float(Data.get_game().get("coop", {}).get("spectate_distance_m", 3.5))
	var height_m: float = float(Data.get_game().get("coop", {}).get("spectate_height_m", 2.0))
	var hud: Hud = _hud()
	await _wait(SETTLE_S)
	_check_markers(hud)
	if _stage == "minimap":
		print("spectator_sandbox: holding for screenshot (minimap)")
		return
	await _check_fall_and_view(hud, delay_s, distance_m, height_m)
	if _stage == "spectate":
		print("spectator_sandbox: holding for screenshot (spectate)")
		return
	await _check_switching_and_loss(hud)
	await _check_solo()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check_markers(hud: Hud) -> void:
	var minimap: Minimap = hud.get("_minimap") as Minimap
	var compass: Compass = hud.get("_compass") as Compass
	_check("minimap_three_allies", minimap.allies.size() == 3, str(minimap.allies.size()))
	_check("minimap_local_not_listed", not minimap.allies.has(player.global_position))
	var slots_ok: bool = minimap.ally_colors.size() == 3 and minimap.ally_yaws.size() == 3 and minimap.ally_down.size() == 3
	_check("minimap_parallel_arrays", slots_ok)
	if not slots_ok:
		return
	_check("minimap_slot_colors", minimap.ally_colors[0] == HunterVisualBase.slot_color(NEAR_SLOT)
		and minimap.ally_colors[1] == HunterVisualBase.slot_color(DOWN_SLOT)
		and minimap.ally_colors[2] == HunterVisualBase.slot_color(FAR_SLOT))
	_check("minimap_down_flags", minimap.ally_down[0] == 0 and minimap.ally_down[1] == 1 and minimap.ally_down[2] == 0,
		str(minimap.ally_down))
	_check("minimap_yaws", absf(angle_difference(minimap.ally_yaws[0], NEAR_YAW)) < 0.01
		and absf(angle_difference(minimap.ally_yaws[2], FAR_YAW)) < 0.01, str(minimap.ally_yaws))
	_check("minimap_in_view", minimap.is_in_view(minimap.allies[0]) and minimap.is_in_view(minimap.allies[1])
		and not minimap.is_in_view(minimap.allies[2]), "near/down in view, far out of view")
	var ally_marks: int = 0
	var down_marks: int = 0
	var colors_ok: bool = true
	for mark: Dictionary in compass.get("_marks") as Array[Dictionary]:
		if mark["kind"] == &"ally":
			ally_marks += 1
			if bool(mark["down"]):
				down_marks += 1
			colors_ok = colors_ok and mark["color"] is Color
	_check("compass_three_allies", ally_marks == 3 and down_marks == 1 and colors_ok, "%d/%d" % [ally_marks, down_marks])
	# Name tags: in range and standing = visible; fallen or beyond coop.name_tag_max_m = hidden; never on the local hunter.
	var near_tag: Label3D = _remotes[NEAR_SLOT].find_child("NameTag", true, false) as Label3D
	var down_tag: Label3D = _remotes[DOWN_SLOT].find_child("NameTag", true, false) as Label3D
	var far_tag: Label3D = _remotes[FAR_SLOT].find_child("NameTag", true, false) as Label3D
	_check("name_tag_near_visible", near_tag != null and near_tag.visible and near_tag.text == "Ana")
	_check("name_tag_fallen_hidden", down_tag != null and not down_tag.visible)
	_check("name_tag_beyond_max_hidden", far_tag != null and not far_tag.visible,
		"max %.0f m" % float(Data.get_game().get("coop", {}).get("name_tag_max_m", 0.0)))
	_check("name_tag_not_on_local", player.find_child("NameTag", true, false) == null)


func _check_fall_and_view(hud: Hud, delay_s: float, distance_m: float, height_m: float) -> void:
	_check("no_spectator_while_alive", player.get_spectator() == null and _spectate_log.is_empty())
	player.apply_damage(1000.0, Vector3(5.0, 0.0, 0.0))
	_check("player_dead", not player.is_alive())
	_check("spectator_created_with_ally_up", player.get_spectator() != null and not player.is_spectating())
	var down_banner: Label = hud.get("_down_banner") as Label
	var banner: Label = hud.get("_spectate_banner") as Label
	await _wait_game(AFTER_DEATH_S)
	_check("down_banner_during_delay", down_banner.visible and not banner.visible)
	_check("still_first_person_before_delay", get_viewport().get_camera_3d() == player.get_camera()
		and _spectate_log.is_empty())
	await _wait_game(delay_s - AFTER_DEATH_S + SETTLE_S)
	var cam: SpectatorCamera = player.get_spectator()
	_check("spectating_after_delay", player.is_spectating() and cam.get_target_slot() == NEAR_SLOT)
	var first_log: Array[int] = [NEAR_SLOT]
	_check("spectate_changed_first", _spectate_log == first_log, str(_spectate_log))
	_check("spectator_is_current_camera", get_viewport().get_camera_3d() == cam)
	_check("banner_text", banner.visible and banner.text == "Assistindo: Ana", banner.text)
	_check("banner_color", banner.get_theme_color("font_color") == HunterVisualBase.slot_color(NEAR_SLOT))
	_check("down_banner_replaced", not down_banner.visible)
	var hint: Label = hud.get("_spectate_hint") as Label
	_check("switch_hint_with_two_allies", hint.visible and hint.text.contains("trocar"), hint.text)
	_check("weapon_panel_hidden", not (hud.get("_bottomright_margin") as Control).visible
		and not (hud.get("_crosshair") as Control).visible)
	var target: RemoteHunter = _remotes[NEAR_SLOT]
	var watched_tag: Label3D = target.find_child("NameTag", true, false) as Label3D
	_check("followed_name_tag_hidden", watched_tag != null and not watched_tag.visible, "the banner names the ally")
	var flat: Vector2 = Vector2(cam.global_position.x - target.global_position.x, cam.global_position.z - target.global_position.z)
	_check("camera_distance_behind", absf(flat.length() - distance_m) < TOLERANCE_M, "%.3f m" % flat.length())
	var forward: Vector2 = Vector2(-sin(target.rotation.y), -cos(target.rotation.y))
	_check("camera_is_behind_target", flat.dot(forward) < 0.0)
	_check("camera_height", absf((cam.global_position.y - target.global_position.y) - height_m) < TOLERANCE_M,
		"%.3f m" % (cam.global_position.y - target.global_position.y))
	var look: Vector3 = -cam.global_transform.basis.z
	var look_yaw: float = atan2(-look.x, -look.z)
	_check("camera_looks_along_ally_gaze", absf(angle_difference(look_yaw, target.rotation.y)) < TOLERANCE_RAD,
		"%.3f vs %.3f" % [look_yaw, target.rotation.y])
	_check("camera_fov_and_far", is_equal_approx(cam.fov, float(Data.get_game().get("player", {}).get("base_fov_deg", 75.0)))
		and is_equal_approx(cam.far, player.get_camera().far))
	var minimap: Minimap = hud.get("_minimap") as Minimap
	_check("minimap_centred_on_followed", minimap.get("_origin").distance_to(target.global_position) < TOLERANCE_M
		and minimap.center_color == HunterVisualBase.slot_color(NEAR_SLOT))
	var down_listed: bool = minimap.allies.has(player.global_position) and minimap.allies.size() == 3
	_check("minimap_lists_own_body_and_others", down_listed, str(minimap.allies.size()))
	# Terrain: the camera never goes below the height of the world plus the clearance.
	_terrain_y = TERRAIN_TEST_Y
	await _wait(SETTLE_S)
	_check("camera_above_terrain", cam.global_position.y >= TERRAIN_TEST_Y + SpectatorCamera.GROUND_CLEARANCE_M - 0.01,
		"y=%.2f" % cam.global_position.y)
	_terrain_y = 0.0
	await _wait(SETTLE_S)


func _check_switching_and_loss(hud: Hud) -> void:
	var cam: SpectatorCamera = player.get_spectator()
	var banner: Label = hud.get("_spectate_banner") as Label
	var hint: Label = hud.get("_spectate_hint") as Label
	await _press(&"fire")
	_check("switch_to_next_standing", cam.get_target_slot() == FAR_SLOT and banner.text == "Assistindo: Caio",
		"%d %s" % [cam.get_target_slot(), banner.text])
	await _press(&"item_next")
	_check("switch_wraps_around", cam.get_target_slot() == NEAR_SLOT and banner.text == "Assistindo: Ana")
	# The menu is open: the click on its button must not switch.
	GameEvents.hunt_paused_changed.emit(true)
	await _press(&"fire")
	_check("no_switch_while_menu_open", cam.get_target_slot() == NEAR_SLOT)
	GameEvents.hunt_paused_changed.emit(false)
	# The followed ally falls: state arrives, then the controller's signal.
	_remote_alive[NEAR_SLOT] = false
	await _wait(SETTLE_S)
	GameEvents.hunter_died.emit(NEAR_SLOT)
	_check("followed_fell_switches", cam.get_target_slot() == FAR_SLOT and banner.text == "Assistindo: Caio",
		"%d %s" % [cam.get_target_slot(), banner.text])
	var expected_log: Array[int] = [NEAR_SLOT, FAR_SLOT, NEAR_SLOT, FAR_SLOT]
	_check("log_after_fall", _spectate_log == expected_log, str(_spectate_log))
	await _wait(SETTLE_S)
	_check("hint_hidden_with_one_ally_left", not hint.visible)
	var log_size: int = _spectate_log.size()
	await _press(&"fire")
	_check("no_switch_without_alternative", cam.get_target_slot() == FAR_SLOT and _spectate_log.size() == log_size)
	# The last standing ally leaves the hunt: the view goes back to the local camera and the signal says -1.
	var gone: RemoteHunter = _remotes[FAR_SLOT]
	_remotes.erase(FAR_SLOT)
	_hunters_list.erase(gone)
	gone.queue_free()
	GameEvents.hunter_left.emit(FAR_SLOT)
	await get_tree().process_frame
	_check("no_ally_left_stops", not player.is_spectating() and _spectate_log.back() == -1, str(_spectate_log))
	_check("camera_returned_to_player", get_viewport().get_camera_3d() == player.get_camera())
	_check("banners_after_stop", not banner.visible and (hud.get("_down_banner") as Label).visible
		and (hud.get("_bottomright_margin") as Control).visible)
	_check("minimap_back_to_own_view", (hud.get("_minimap") as Minimap).center_color == Minimap.COLOR_PLAYER)


func _check_solo() -> void:
	var solo: SoloStub = SoloStub.new()
	add_child(solo)
	var packed: PackedScene = load(ScenePaths.PLAYER) as PackedScene
	var p2: Player = packed.instantiate() as Player
	solo.add_child(p2)
	p2.setup(_request(), solo)
	solo.hunter = p2
	p2.apply_damage(1000.0, Vector3(5.0, 0.0, 0.0))
	await _wait(float(Data.get_game().get("coop", {}).get("spectate_delay_s", 2.0)) + SETTLE_S)
	_check("solo_never_spectates", not p2.is_alive() and p2.get_spectator() == null and not p2.is_spectating())
	_check("solo_keeps_own_camera", get_viewport().get_camera_3d() == p2.get_camera())
	var solo_hud: Hud = p2.get("_hud") as Hud
	_check("solo_no_spectate_banner", not (solo_hud.get("_spectate_banner") as Label).visible)
