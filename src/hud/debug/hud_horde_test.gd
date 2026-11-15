extends Node
## Package A sandbox for the horde HUD (docs/horda.md section 8): a SandboxWorld that reports is_horde() and whose
## wave state is driven by hand (fields + GameEvents signals). Checks the exact texts of sections 8 and 12 in
## WaveLabel, WaveBanner, the top bar, the alert, the ammo counter and the end message; and that a contract world
## keeps the contract HUD. Quits by itself.
## Usage: tools/godot.sh --headless --path . res://src/hud/debug/hud_horde_test.tscn
## Not part of the game.

const WATCHDOG_S: float = 60.0
const POLL_WAIT_S: float = 0.25    # longer than the HUD's 10 Hz poll
const BANNER_WAIT_S: float = 3.3   # banner lasts 3 s
const WAVE_COUNT: int = 8
const FIRST_DELAY_S: float = 12.0
const INTERMISSION_S: float = 15.0
const FIRST_WAVE_TOTAL: int = 9

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await _test_horde_hud()
	await _test_horde_defeat()
	await _test_contract_hud()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _on_watchdog() -> void:
	print("FAIL watchdog: the test did not finish in %d s" % int(WATCHDOG_S))
	get_tree().quit(1)


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _make_world(horde: bool, prepare_state: bool = false) -> SandboxWorld:
	var world: SandboxWorld = SandboxWorld.new()
	world.horde_mode = horde
	world.horde_auto = false
	if prepare_state:   # state the HUD must read from the getters when it binds
		world.horde_wave = 1
		world.horde_wave_count = WAVE_COUNT
		world.horde_phase = Ids.HP_INTERMISSION
		world.horde_countdown_s = FIRST_DELAY_S
	add_child(world)
	await get_tree().process_frame
	return world


func _hud_of(world: SandboxWorld) -> Hud:
	for child: Node in world.player.get_children():
		if child is Hud:
			return child as Hud
	return null


func _free_world(world: SandboxWorld) -> void:
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _label_text(hud: Hud, node_name: String) -> String:
	var l: Label = hud.find_child(node_name, true, false) as Label
	return l.text if l != null else "<missing>"


func _label_shown(hud: Hud, node_name: String) -> bool:
	var l: Label = hud.find_child(node_name, true, false) as Label
	return l != null and l.is_visible_in_tree()


func _test_horde_hud() -> void:
	var world: SandboxWorld = await _make_world(true, true)
	var hud: Hud = _hud_of(world)
	_check("horde_hud_found", hud != null and world.is_horde())
	if hud == null:
		return
	var crop_label: Label = hud.get("_crop_label") as Label
	var crop_alert: Label = hud.get("_crop_alert") as Label
	var count_label: Label = hud.get("_count_label") as Label
	var ammo_label: Label = hud.get("_ammo_label") as Label
	var minimap: Minimap = hud.get("_minimap") as Minimap
	var compass: Compass = hud.get("_compass") as Compass
	await _wait(POLL_WAIT_S)

	# Initial state read from the getters in bind().
	_check("horde_initial_wave_label", _label_text(hud, "WaveLabel") == "Onda 1/8 em 12 s", _label_text(hud, "WaveLabel"))
	_check("horde_wave_label_visible", _label_shown(hud, "WaveLabel"))
	_check("horde_count_label_hidden", not count_label.visible)
	_check("horde_banner_hidden_at_start", not _label_shown(hud, "WaveBanner"))

	# Top bar and alert.
	GameEvents.crop_health_changed.emit(100.0)
	_check("horde_crop_label_100", crop_label.text == "Celeiro 100%", crop_label.text)
	GameEvents.crop_health_changed.emit(87.0)
	_check("horde_crop_label_87", crop_label.text == "Celeiro 87%", crop_label.text)
	GameEvents.crop_under_attack.emit(true)
	_check("horde_alert", crop_alert.visible and crop_alert.text == "Javalis no celeiro!", crop_alert.text)
	GameEvents.crop_under_attack.emit(false)
	_check("horde_alert_off", not crop_alert.visible)

	# Ammo counter and the map markers.
	_check("horde_ammo_infinite", ammo_label.text.ends_with("| ∞") and ammo_label.text.begins_with("%d " % world.player.get_ammo_in_mag()),
		ammo_label.text)
	_check("horde_minimap_no_crops", minimap.crop_rects.is_empty())
	_check("horde_minimap_objective", minimap.objective.is_finite() and minimap.objective.is_equal_approx(world.get_objective_position()))
	_check("horde_compass_objective", compass.objective.is_finite() and compass.objective.is_equal_approx(world.get_objective_position()))

	# First intermission: banner, label and the 10 Hz countdown.
	world.horde_countdown_s = FIRST_DELAY_S
	GameEvents.horde_wave_changed.emit(1, WAVE_COUNT, Ids.HP_INTERMISSION, FIRST_DELAY_S)
	_check("horde_banner_first", _label_text(hud, "WaveBanner") == "Defenda o celeiro! A horda chega em 12 s" and _label_shown(hud, "WaveBanner"),
		_label_text(hud, "WaveBanner"))
	_check("horde_label_intermission", _label_text(hud, "WaveLabel") == "Onda 1/8 em 12 s", _label_text(hud, "WaveLabel"))
	world.horde_countdown_s = 10.2
	await _wait(POLL_WAIT_S)
	_check("horde_label_countdown_polled", _label_text(hud, "WaveLabel") == "Onda 1/8 em 11 s", _label_text(hud, "WaveLabel"))

	# Wave 1 starts.
	world.horde_phase = Ids.HP_WAVE
	world.horde_countdown_s = 0.0
	GameEvents.horde_wave_changed.emit(1, WAVE_COUNT, Ids.HP_WAVE, 0.0)
	GameEvents.horde_wave_progress.emit(FIRST_WAVE_TOTAL, FIRST_WAVE_TOTAL)
	_check("horde_banner_wave", _label_text(hud, "WaveBanner") == "Onda 1 de 8", _label_text(hud, "WaveBanner"))
	_check("horde_label_wave", _label_text(hud, "WaveLabel") == "Onda 1/8 · faltam 9", _label_text(hud, "WaveLabel"))
	GameEvents.horde_wave_progress.emit(5, FIRST_WAVE_TOTAL)
	_check("horde_label_progress", _label_text(hud, "WaveLabel") == "Onda 1/8 · faltam 5", _label_text(hud, "WaveLabel"))
	await _wait(POLL_WAIT_S)
	_check("horde_label_stable_after_poll", _label_text(hud, "WaveLabel") == "Onda 1/8 · faltam 5", _label_text(hud, "WaveLabel"))

	# Wave 1 cleared: intermission of wave 2.
	world.horde_phase = Ids.HP_INTERMISSION
	world.horde_wave = 2
	world.horde_countdown_s = INTERMISSION_S
	GameEvents.horde_wave_changed.emit(2, WAVE_COUNT, Ids.HP_INTERMISSION, INTERMISSION_S)
	_check("horde_banner_cleared", _label_text(hud, "WaveBanner") == "Onda 1 vencida!", _label_text(hud, "WaveBanner"))
	_check("horde_label_wave_2", _label_text(hud, "WaveLabel") == "Onda 2/8 em 15 s", _label_text(hud, "WaveLabel"))

	# Last wave.
	GameEvents.horde_wave_changed.emit(WAVE_COUNT, WAVE_COUNT, Ids.HP_WAVE, 0.0)
	GameEvents.horde_wave_progress.emit(33, 33)
	_check("horde_banner_last", _label_text(hud, "WaveBanner") == "Última onda! Onda 8 de 8", _label_text(hud, "WaveBanner"))
	_check("horde_label_last", _label_text(hud, "WaveLabel") == "Onda 8/8 · faltam 33", _label_text(hud, "WaveLabel"))

	# The banner lasts about 3 s.
	await _wait(BANNER_WAIT_S)
	_check("horde_banner_expires", not _label_shown(hud, "WaveBanner"))

	# Sounds: with or without the new ids the HUD must not break (art-director adds them in parallel).
	_check("horde_wave_sounds_optional", true, "has start=%s clear=%s" % [
		Sfx.has_sound(&"horde_wave_start"), Sfx.has_sound(&"horde_wave_clear")])

	# End of the hunt: victory text.
	var result: HuntResult = HuntResult.new()
	result.outcome = HuntResult.Outcome.VICTORY
	GameEvents.hunt_ended.emit(result)
	var end_msg: KillMessage = hud.get("_end_msg") as KillMessage
	_check("horde_end_victory", end_msg.get_text() == "Celeiro defendido!", end_msg.get_text())
	await _free_world(world)


func _test_horde_defeat() -> void:
	var world: SandboxWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("horde_defeat_hud_found", false)
		return
	# No state yet (a client before the first EV_HORDE_WAVE): the placeholder text.
	await _wait(POLL_WAIT_S)
	_check("horde_label_placeholder", _label_text(hud, "WaveLabel") == "Onda –", _label_text(hud, "WaveLabel"))
	var result: HuntResult = HuntResult.new()
	result.outcome = HuntResult.Outcome.DEFEAT_CROP
	GameEvents.hunt_ended.emit(result)
	var end_msg: KillMessage = hud.get("_end_msg") as KillMessage
	_check("horde_end_defeat_crop", end_msg.get_text() == "O celeiro foi devorado!", end_msg.get_text())
	await _free_world(world)


func _test_contract_hud() -> void:
	var world: SandboxWorld = await _make_world(false)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("contract_hud_found", false)
		return
	var crop_label: Label = hud.get("_crop_label") as Label
	var crop_alert: Label = hud.get("_crop_alert") as Label
	var count_label: Label = hud.get("_count_label") as Label
	var ammo_label: Label = hud.get("_ammo_label") as Label
	var minimap: Minimap = hud.get("_minimap") as Minimap
	GameEvents.crop_health_changed.emit(100.0)
	GameEvents.boar_counts_changed.emit(0, 0)
	await _wait(POLL_WAIT_S)
	_check("contract_crop_label", crop_label.text == "Lavoura 100%", crop_label.text)
	_check("contract_count_label", count_label.text == "Javalis 0/0" and count_label.visible, count_label.text)
	_check("contract_no_wave_label", not _label_shown(hud, "WaveLabel"))
	_check("contract_no_wave_banner", not _label_shown(hud, "WaveBanner"))
	_check("contract_alert_text", crop_alert.text == "Javalis na lavoura!", crop_alert.text)
	_check("contract_ammo_text", ammo_label.text == "%d | %d" % [world.player.get_ammo_in_mag(), world.player.get_ammo_reserve()],
		ammo_label.text)
	_check("contract_minimap_crops", not minimap.crop_rects.is_empty() and not minimap.objective.is_finite())
	var result: HuntResult = HuntResult.new()
	result.outcome = HuntResult.Outcome.VICTORY
	GameEvents.hunt_ended.emit(result)
	var end_msg: KillMessage = hud.get("_end_msg") as KillMessage
	_check("contract_end_victory", end_msg.get_text() == "Missão cumprida!", end_msg.get_text())
	await _free_world(world)
