extends Node
## Package A2 sandbox for the horde level 2 HUD (docs/plano_horda_nivel2.md section 5): a SandboxWorld in horde mode with a
## fake level, fake ammo crates and fake allies, and a Player whose revive / bleed / ammo getters are driven by hand
## (FakePlayer), plus the GameEvents signals fired by hand. Checks the exact texts of section 5 in each node, "%d | %d"
## without the infinity sign, the InteractButton only with a revive target ("Levantar") or an ammo crate in reach
## ("Pegar", owner's Q4) with the AmmoPrompt, and that level 1 and the contract keep their HUD. Quits by itself.
## Usage: tools/godot.sh --headless --path . res://src/hud/debug/hud_horde2_test.tscn
## Screenshot with a window: tools/godot.sh --path . res://src/hud/debug/hud_horde2_test.tscn -- --shot=<png path>
## Not part of the game.

const WATCHDOG_S: float = 60.0
const POLL_WAIT_S: float = 0.25    # longer than the HUD's 10 Hz poll
const ALLY_A: int = 1
const ALLY_B: int = 2
const CRATE_POSITIONS: Array[Vector3] = [Vector3(35.0, 0.0, -90.0), Vector3(38.0, 0.0, -90.0), Vector3(41.0, 0.0, -90.0)]
const MIN_INTERACT_DIAMETER_PX: float = 96.0
const SCREEN_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2340, 1080)]

var _passed: int = 0
var _failed: int = 0
var _added_interact_action: bool = false
var _shot_path: String = ""


## The real Player scene with the revive / bleed / ammo getters of the plan driven by the test (the real ones are the
## job of package A1).
class FakePlayer extends Player:
	var downed: bool = false
	var bleed_left_s: float = 0.0
	var revive_target: int = -1
	var revive_progress: float = 0.0
	var crate_target: int = -1
	var infinite: bool = false

	func is_downed() -> bool:
		return downed

	func get_bleed_out_left_s() -> float:
		return bleed_left_s

	func get_revive_target_slot() -> int:
		return revive_target

	func get_revive_progress() -> float:
		return revive_progress

	func get_ammo_crate_target() -> int:
		return crate_target

	func has_infinite_reserve() -> bool:
		return infinite


class FakeAlly extends PlayerBase:
	var downed: bool = false
	var alive: bool = true
	var nickname: String = ""

	func is_alive() -> bool:
		return alive and not downed

	func is_local() -> bool:
		return false

	func is_downed() -> bool:
		return downed

	func get_display_name() -> String:
		return nickname


class FakeWorld extends SandboxWorld:
	var level: int = 2
	var crates: PackedVector3Array = PackedVector3Array()
	var allies: Array[PlayerBase] = []

	func _spawn_player() -> void:
		var packed: PackedScene = load(ScenePaths.PLAYER) as PackedScene
		var node: Node = packed.instantiate()
		node.set_script(FakePlayer)
		player = node as Player
		add_child(player)
		player.global_position = Vector3.ZERO
		player.setup(_request(), self)

	func get_horde_level() -> int:
		return level if horde_mode else 0

	func get_ammo_crate_positions() -> PackedVector3Array:
		return crates

	func get_hunters() -> Array[PlayerBase]:
		var out: Array[PlayerBase] = [player]
		out.append_array(allies)
		return out

	func get_hunter(for_slot: int) -> PlayerBase:
		for h: PlayerBase in get_hunters():
			if h.slot == for_slot:
				return h
		return null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")   # package A1 registers it for real; the test must not depend on the order
		_added_interact_action = true
	if _shot_path != "":
		await _screenshot()
		return
	await _test_ammo()
	await _test_map_markers()
	await _test_revive_prompt()
	await _test_downed_overlay()
	await _test_feed()
	await _test_interact_button()
	await _test_ammo_crate_prompt()
	await _test_level_1()
	await _test_contract()
	if _added_interact_action:
		InputMap.erase_action(&"interact")
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


func _make_world(horde: bool, level: int = 2, infinite: bool = false) -> FakeWorld:
	var world: FakeWorld = FakeWorld.new()
	world.horde_mode = horde
	world.horde_auto = false
	world.level = level
	add_child(world)
	await get_tree().process_frame
	var fake: FakePlayer = world.player as FakePlayer
	fake.infinite = infinite
	for slot: int in [ALLY_A, ALLY_B]:
		var ally: FakeAlly = FakeAlly.new()
		ally.slot = slot
		world.allies.append(ally)
		world.add_child(ally)
		GameEvents.hunter_joined.emit(slot, "Ana" if slot == ALLY_A else "Beto")
	await get_tree().process_frame
	return world


func _hud_of(world: SandboxWorld) -> Hud:
	for child: Node in world.player.get_children():
		if child is Hud:
			return child as Hud
	return null


func _free_world(world: SandboxWorld) -> void:
	InputSetup.set_touch_override("auto")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(count: int = 2) -> void:
	for i: int in count:
		await get_tree().process_frame


func _label(hud: Hud, node_name: String) -> Label:
	return hud.find_child(node_name, true, false) as Label


func _text(hud: Hud, node_name: String) -> String:
	var l: Label = _label(hud, node_name)
	return l.text if l != null else "<missing>"


func _shown(hud: Hud, node_name: String) -> bool:
	var c: Control = hud.find_child(node_name, true, false) as Control
	return c != null and c.is_visible_in_tree()


func _ctx(hud: Hud) -> KillMessage:
	return hud.get("_ctx_msg") as KillMessage


## KillMessage.clear() only hides the label; the text stays. An empty message is the "nothing was said" marker.
func _reset_ctx(hud: Hud) -> void:
	_ctx(hud).show_text("", 1.0)


func _key() -> String:
	return InputSetup.get_key_label(&"interact")


# ---------------------------------------------------------------------------

func _test_ammo() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	_check("ammo_hud_found", hud != null and world.is_horde() and world.get_horde_level() == 2)
	if hud == null:
		return
	var panel: WeaponPanel = hud.get("_weapon_panel") as WeaponPanel
	var w: Weapon = world.player.get_weapon()
	w.ammo_in_mag = 8
	w.ammo_reserve = 20
	await _wait(POLL_WAIT_S)
	var shown: String = "%s %s" % [panel.get_mag_text(), panel.get_reserve_text()]
	_check("ammo_format_counted", shown == "8 | 20", shown)
	_check("ammo_no_infinity_level2", not shown.contains("∞"), shown)
	_check("ammo_no_warning_with_reserve", _ctx(hud).get_text() == "", _ctx(hud).get_text())

	# Last magazine: reserve 0, magazine > 0. Once per weapon until a crate refills it.
	w.ammo_reserve = 0
	await _frames()
	_check("ammo_last_text", _ctx(hud).get_text() == "Última carga: pegue cartuchos no celeiro.", _ctx(hud).get_text())
	_reset_ctx(hud)
	await _frames(3)
	_check("ammo_last_once", _ctx(hud).get_text() == "", _ctx(hud).get_text())
	# Nothing at all: reserve 0 and magazine 0.
	w.ammo_in_mag = 0
	await _frames()
	_check("ammo_empty_text", _ctx(hud).get_text() == "Sem munição: pegue cartuchos no celeiro.", _ctx(hud).get_text())
	_reset_ctx(hud)
	await _frames(3)
	_check("ammo_empty_once", _ctx(hud).get_text() == "", _ctx(hud).get_text())

	# A crate: "+%d cartuchos" and the next last-magazine warning may fire again.
	w.ammo_reserve = 20
	GameEvents.ammo_picked_up.emit(20)
	_check("ammo_pickup_text", _ctx(hud).get_text() == "+20 cartuchos", _ctx(hud).get_text())
	await _frames()
	w.ammo_in_mag = 3
	w.ammo_reserve = 0
	await _frames()
	_check("ammo_last_again_after_pickup", _ctx(hud).get_text() == "Última carga: pegue cartuchos no celeiro.", _ctx(hud).get_text())
	await _free_world(world)


func _test_map_markers() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("markers_hud_found", false)
		return
	var minimap: Minimap = hud.get("_minimap") as Minimap
	_check("marker_colors", MapMarkers.COLOR_AMMO.is_equal_approx(Color("#8FB339"))
		and MapMarkers.COLOR_DOWNED.is_equal_approx(Color("#E04A3A"))
		and MapMarkers.color_of(MapMarkers.KIND_AMMO).is_equal_approx(Color("#8FB339")))
	_check("marker_ammo_6px", is_equal_approx(float(Minimap.HALF_PX[MapMarkers.KIND_AMMO]) * 2.0, 6.0))
	world.crates = PackedVector3Array(CRATE_POSITIONS)
	var ally: FakeAlly = world.allies[0] as FakeAlly
	ally.global_position = Vector3(10.0, 0.0, -10.0)
	await _wait(POLL_WAIT_S)
	_check("minimap_crates", minimap.ammo_crates.size() == CRATE_POSITIONS.size()
		and minimap.ammo_crates[0].is_equal_approx(CRATE_POSITIONS[0]), str(minimap.ammo_crates.size()))
	world.crates = PackedVector3Array([CRATE_POSITIONS[1]])   # one crate taken
	await _wait(POLL_WAIT_S)
	_check("minimap_crate_taken", minimap.ammo_crates.size() == 1)
	_check("minimap_ally_standing", minimap.ally_down.size() == 2 and minimap.ally_down[0] == 0, str(minimap.ally_down))
	ally.downed = true
	await _wait(POLL_WAIT_S)
	_check("minimap_ally_downed_red_dot", minimap.ally_down[0] == Minimap.ALLY_DOWN_DOWNED, str(minimap.ally_down))
	var marks: Array[Dictionary] = hud.get("_marks")
	var downed_marks: int = 0
	for mark: Dictionary in marks:
		if mark["kind"] == MapMarkers.KIND_ALLY and bool(mark.get("downed", false)):
			downed_marks += 1
	_check("compass_ally_downed_mark", downed_marks == 1, str(downed_marks))
	ally.downed = false
	ally.alive = false   # dead for good: the dimmed cross of today, not the red dot
	await _wait(POLL_WAIT_S)
	_check("minimap_ally_dead_is_not_downed", minimap.ally_down[0] == 1, str(minimap.ally_down))
	await _free_world(world)


func _test_revive_prompt() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("prompt_hud_found", false)
		return
	var fake: FakePlayer = world.player as FakePlayer
	var bar: ProgressBar = hud.find_child("ReviveBar", true, false) as ProgressBar
	_check("prompt_hidden_without_target", not _shown(hud, "RevivePrompt") and not _shown(hud, "ReviveBarLabel")
		and bar != null and not bar.visible)
	_check("prompt_bar_range", bar != null and is_equal_approx(bar.min_value, 0.0) and is_equal_approx(bar.max_value, 1.0))
	var prompt: Label = _label(hud, "RevivePrompt")
	_check("prompt_is_hud_label", prompt != null and prompt.theme_type_variation == &"HudLabel")
	InputSetup.set_touch_override("off")
	fake.revive_target = ALLY_A
	await _frames()
	_check("prompt_keys", _shown(hud, "RevivePrompt") and _text(hud, "RevivePrompt") == "Segure %s para levantar Ana" % _key(),
		_text(hud, "RevivePrompt"))
	if InputMap.has_action(&"interact") and not _added_interact_action:
		_check("prompt_key_is_f", _key() == "F", _key())
	fake.revive_progress = 0.5
	await _frames()
	_check("bar_label", _shown(hud, "ReviveBarLabel") and _text(hud, "ReviveBarLabel") == "Levantando Ana…", _text(hud, "ReviveBarLabel"))
	_check("bar_value", bar.visible and is_equal_approx(bar.value, 0.5), str(bar.value))
	_check("prompt_replaced_while_holding", not _shown(hud, "RevivePrompt"))
	fake.revive_progress = 0.0
	InputSetup.set_touch_override("on")
	await _frames()
	_check("prompt_touch", _shown(hud, "RevivePrompt") and _text(hud, "RevivePrompt") == "Segure Levantar para ajudar Ana",
		_text(hud, "RevivePrompt"))
	fake.revive_target = ALLY_B
	await _frames()
	_check("prompt_other_target", _text(hud, "RevivePrompt") == "Segure Levantar para ajudar Beto", _text(hud, "RevivePrompt"))
	fake.revive_target = -1
	await _frames()
	_check("prompt_hidden_again", not _shown(hud, "RevivePrompt") and not bar.visible)
	await _free_world(world)


func _test_downed_overlay() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("downed_hud_found", false)
		return
	var fake: FakePlayer = world.player as FakePlayer
	var overlay: ColorRect = hud.find_child("DownedOverlay", true, false) as ColorRect
	_check("downed_hidden_at_start", overlay != null and not overlay.visible and not _shown(hud, "DownedLabel")
		and not _shown(hud, "DownedHint"))
	_check("downed_overlay_color", overlay != null and overlay.color.is_equal_approx(Color("#7A0000", 0.35)),
		str(overlay.color))
	_check("downed_label_is_big", _label(hud, "DownedLabel").theme_type_variation == &"HudBigLabel")
	# Fall with a bleed-out time.
	fake.downed = true
	fake.bleed_left_s = 42.3
	GameEvents.player_downed.emit(60.0)
	_check("downed_shown", overlay.visible and _shown(hud, "DownedLabel") and _shown(hud, "DownedHint"))
	_check("downed_label_text", _text(hud, "DownedLabel") == "Você caiu!", _text(hud, "DownedLabel"))
	_check("downed_hint_bleeding", _text(hud, "DownedHint") == "Um companheiro pode te levantar.\nSangrando: 43 s", _text(hud, "DownedHint"))
	fake.bleed_left_s = 41.0
	await _wait(POLL_WAIT_S)
	_check("downed_hint_countdown_polled", _text(hud, "DownedHint") == "Um companheiro pode te levantar.\nSangrando: 41 s", _text(hud, "DownedHint"))
	_check("downed_hides_revive_prompt", not _shown(hud, "RevivePrompt"))
	# Revived.
	fake.downed = false
	GameEvents.player_revived.emit(50.0)
	_check("downed_cleared_on_revive", not overlay.visible and not _shown(hud, "DownedLabel") and not _shown(hud, "DownedHint"))
	# Fall without a time limit: a single line.
	fake.downed = true
	GameEvents.player_downed.emit(0.0)
	await _wait(POLL_WAIT_S)
	_check("downed_hint_without_limit", _text(hud, "DownedHint") == "Um companheiro pode te levantar.", _text(hud, "DownedHint"))
	# Bled out: the usual death flow takes over.
	fake.downed = false
	GameEvents.player_died.emit()
	_check("downed_cleared_on_death", not overlay.visible and not _shown(hud, "DownedLabel") and not _shown(hud, "DownedHint"))
	await _free_world(world)


func _test_feed() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("feed_hud_found", false)
		return
	var ctx: KillMessage = _ctx(hud)
	InputSetup.set_touch_override("off")
	GameEvents.hunter_downed.emit(ALLY_A)
	_check("feed_downed_keys", ctx.get_text() == "Ana caiu! Vá até lá e segure %s." % _key(), ctx.get_text())
	InputSetup.set_touch_override("on")
	GameEvents.hunter_downed.emit(ALLY_B)
	_check("feed_downed_touch", ctx.get_text() == "Beto caiu! Vá até lá e segure Levantar.", ctx.get_text())
	_reset_ctx(hud)
	GameEvents.hunter_downed.emit(Net.get_local_slot())
	_check("feed_downed_local_ignored", ctx.get_text() == "", ctx.get_text())
	GameEvents.hunter_revived.emit(Net.get_local_slot(), ALLY_A)
	_check("feed_revived_me", ctx.get_text() == "Ana te levantou!", ctx.get_text())
	GameEvents.hunter_revived.emit(ALLY_A, Net.get_local_slot())
	_check("feed_revived_by_me", ctx.get_text() == "Você levantou Ana.", ctx.get_text())
	GameEvents.hunter_revived.emit(ALLY_A, ALLY_B)
	_check("feed_revived_others", ctx.get_text() == "Beto levantou Ana.", ctx.get_text())
	await _free_world(world)


func _test_interact_button() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("button_hud_found", false)
		return
	var fake: FakePlayer = world.player as FakePlayer
	InputSetup.set_touch_override("on")
	var touch: TouchControls = hud.get("_touch") as TouchControls
	await _frames(3)
	_check("button_hidden_without_target", not touch.get_button_diameters().has(&"interact"))
	fake.revive_target = ALLY_A
	await _frames(3)
	var diameters: Dictionary = touch.get_button_diameters()
	_check("button_visible_with_target", diameters.has(&"interact"))
	_check("button_size", float(diameters.get(&"interact", 0.0)) >= MIN_INTERACT_DIAMETER_PX, str(diameters.get(&"interact")))
	# No overlap with the other buttons (and the joystick) at the two reference sizes.
	var window: Window = get_window()
	var original_size: Vector2i = window.size
	for size: Vector2i in SCREEN_SIZES:
		window.size = size
		await _frames(2)
		var screen: Vector2 = get_viewport().get_visible_rect().size
		var worst_gap: float = INF
		var worst_pair: String = ""
		var mine: Vector2 = touch.get_button_center(&"interact")
		var my_r: float = touch.get_button_radius(&"interact")
		for action_name: StringName in touch.get_button_diameters():
			if action_name == &"interact":
				continue
			var gap: float = mine.distance_to(touch.get_button_center(action_name)) - my_r - touch.get_button_radius(action_name)
			if gap < worst_gap:
				worst_gap = gap
				worst_pair = String(action_name)
		var inside: bool = Rect2(Vector2.ZERO, screen).grow(-my_r).has_point(mine)
		_check("button_no_overlap_%dx%d" % [size.x, size.y], worst_gap > 0.0 and inside,
			"screen=%s centre=%s closest=%s gap=%.1f" % [str(screen), str(mine), worst_pair, worst_gap])
	window.size = original_size
	await _frames(2)
	# Pressing the button holds the interact action; losing the target lets it go.
	touch.get_button_center(&"interact")
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 7
	down.pressed = true
	down.position = touch.get_button_center(&"interact")
	touch._input(down)
	_check("button_holds_interact", Input.is_action_pressed(&"interact"))
	fake.revive_target = -1
	await _frames(3)
	_check("button_gone_releases_interact", not Input.is_action_pressed(&"interact")
		and not touch.get_button_diameters().has(&"interact"))
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 7
	up.pressed = false
	touch._input(up)
	# Downed: only the pause button is left (and the look drag).
	fake.downed = true
	fake.revive_target = ALLY_A
	await _frames(3)
	var left: Dictionary = touch.get_button_diameters()
	_check("button_downed_only_pause", left.size() == 1 and left.has(&"pause"), str(left.keys()))
	fake.downed = false
	await _frames(3)
	_check("button_back_after_revive", touch.get_button_diameters().has(&"fire") and touch.get_button_diameters().has(&"interact"))
	await _free_world(world)


func _test_ammo_crate_prompt() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("crate_prompt_hud_found", false)
		return
	var fake: FakePlayer = world.player as FakePlayer
	var touch: TouchControls = hud.get("_touch") as TouchControls
	InputSetup.set_touch_override("off")
	await _frames()
	_check("crate_prompt_hidden_without_crate", _label(hud, "AmmoPrompt") != null and not _shown(hud, "AmmoPrompt"))
	_check("crate_prompt_is_hud_label", _label(hud, "AmmoPrompt") != null
		and _label(hud, "AmmoPrompt").theme_type_variation == &"HudLabel")
	fake.crate_target = 0
	await _frames()
	_check("crate_prompt_keys", _shown(hud, "AmmoPrompt") and _text(hud, "AmmoPrompt") == "Aperte %s para pegar munição" % _key(),
		_text(hud, "AmmoPrompt"))
	if InputMap.has_action(&"interact") and not _added_interact_action:
		_check("crate_prompt_key_is_f", _text(hud, "AmmoPrompt") == "Aperte F para pegar munição", _text(hud, "AmmoPrompt"))
	_check("crate_prompt_no_revive_prompt", not _shown(hud, "RevivePrompt"))
	InputSetup.set_touch_override("on")
	await _frames(3)
	_check("crate_prompt_touch", _shown(hud, "AmmoPrompt") and _text(hud, "AmmoPrompt") == "Toque em Pegar para pegar munição",
		_text(hud, "AmmoPrompt"))
	var diameters: Dictionary = touch.get_button_diameters()
	_check("crate_button_visible", diameters.has(&"interact") and touch.get_button_label(&"interact") == "Pegar",
		"%s '%s'" % [str(diameters.keys()), touch.get_button_label(&"interact")])
	_check("crate_button_size", float(diameters.get(&"interact", 0.0)) >= MIN_INTERACT_DIAMETER_PX, str(diameters.get(&"interact")))
	# The button presses interact (the Player takes the crate on the press).
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 8
	down.pressed = true
	down.position = touch.get_button_center(&"interact")
	touch._input(down)
	_check("crate_button_presses_interact", Input.is_action_pressed(&"interact"))
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 8
	up.pressed = false
	touch._input(up)
	_check("crate_button_release", not Input.is_action_pressed(&"interact"))
	# A revive target wins: "Levantar" and the RevivePrompt, no AmmoPrompt.
	fake.revive_target = ALLY_A
	await _frames(3)
	_check("crate_revive_wins_prompt", _shown(hud, "RevivePrompt") and not _shown(hud, "AmmoPrompt"))
	_check("crate_revive_wins_button", touch.get_button_label(&"interact") == "Levantar", touch.get_button_label(&"interact"))
	fake.revive_target = -1
	await _frames(3)
	_check("crate_back_after_revive", _shown(hud, "AmmoPrompt") and touch.get_button_label(&"interact") == "Pegar",
		touch.get_button_label(&"interact"))
	# Downed: nothing about crates.
	fake.downed = true
	GameEvents.player_downed.emit(60.0)
	await _frames(3)
	_check("crate_prompt_hidden_when_downed", not _shown(hud, "AmmoPrompt")
		and not touch.get_button_diameters().has(&"interact"))
	fake.downed = false
	GameEvents.player_revived.emit(50.0)
	# No crate (out of reach, or reserve at the cap: the Player returns -1): no prompt, no button.
	fake.crate_target = -1
	await _frames(3)
	_check("crate_prompt_hidden_again", not _shown(hud, "AmmoPrompt") and not touch.get_button_diameters().has(&"interact"))
	await _free_world(world)


func _test_level_1() -> void:
	var world: FakeWorld = await _make_world(true, 1, true)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("level1_hud_found", false)
		return
	var panel: WeaponPanel = hud.get("_weapon_panel") as WeaponPanel
	var w: Weapon = world.player.get_weapon()
	w.ammo_in_mag = 0
	w.ammo_reserve = 0
	await _wait(POLL_WAIT_S)
	_check("level1_infinite_text", panel.get_reserve_text() == "| ∞", panel.get_reserve_text())
	_check("level1_no_ammo_warning", _ctx(hud).get_text() == "", _ctx(hud).get_text())
	var minimap: Minimap = hud.get("_minimap") as Minimap
	_check("level1_no_crates", minimap.ammo_crates.is_empty())
	_check("level1_no_revive_ui", not _shown(hud, "RevivePrompt") and not _shown(hud, "DownedLabel"))
	await _free_world(world)


func _test_contract() -> void:
	var world: FakeWorld = await _make_world(false)
	var hud: Hud = _hud_of(world)
	if hud == null:
		_check("contract_hud_found", false)
		return
	var fake: FakePlayer = world.player as FakePlayer
	fake.revive_target = ALLY_A   # the contract never has a revive target; even a stray value must show nothing
	var w: Weapon = world.player.get_weapon()
	w.ammo_in_mag = 0
	w.ammo_reserve = 0
	await _wait(POLL_WAIT_S)
	_check("contract_no_revive_prompt", not _shown(hud, "RevivePrompt"))
	fake.revive_target = -1
	fake.crate_target = 0   # stray value: the contract never shows the crate prompt
	await _frames()
	_check("contract_no_ammo_prompt", not _shown(hud, "AmmoPrompt"))
	_check("contract_no_ammo_warning", _ctx(hud).get_text() == "", _ctx(hud).get_text())
	await _free_world(world)


## --shot=<png>: the level 2 HUD in the middle of a revive (window needed; --headless draws nothing).
func _screenshot() -> void:
	var world: FakeWorld = await _make_world(true)
	var hud: Hud = _hud_of(world)
	var fake: FakePlayer = world.player as FakePlayer
	world.crates = PackedVector3Array([Vector3(12.0, 0.0, -14.0), Vector3(-9.0, 0.0, -6.0)])
	(world.allies[0] as FakeAlly).global_position = Vector3(14.0, 0.0, -30.0)
	(world.allies[0] as FakeAlly).downed = true
	(world.allies[1] as FakeAlly).global_position = Vector3(-20.0, 0.0, -20.0)
	var w: Weapon = world.player.get_weapon()
	w.ammo_in_mag = 6
	w.ammo_reserve = 14
	world.horde_wave = 3
	world.horde_wave_count = 8
	world.horde_phase = Ids.HP_WAVE
	world.horde_wave_remaining = 5
	world.horde_wave_total = 9
	GameEvents.horde_wave_progress.emit(5, 9)
	GameEvents.horde_wave_changed.emit(3, 8, Ids.HP_WAVE, 0.0)
	fake.revive_target = ALLY_A
	fake.revive_progress = 0.45
	GameEvents.hunter_downed.emit(ALLY_A)
	await _wait(0.6)
	_save_shot(_shot_path)
	fake.revive_target = -1
	fake.revive_progress = 0.0
	fake.downed = true
	fake.bleed_left_s = 37.0
	(world.allies[0] as FakeAlly).downed = false
	GameEvents.player_downed.emit(60.0)
	await _wait(0.6)
	_save_shot(_shot_path.replace(".png", "_downed.png"))
	hud.queue_free()
	get_tree().quit(0)


func _save_shot(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("FAIL screenshot: no image (headless?)")
		return
	img.save_png(path)
	print("screenshot saved: ", path)
