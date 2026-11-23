extends Node
## Package A2 test for the stamina (F2, docs/plano_faca_mochila_folego.md 1.2, 2.6, 2.7): sprinting drains it, zero tires the
## hunter (walks, walking noise), it comes back after a delay, the tired state ends at the recover threshold, crouching
## and aiming do not spend it, the tired message shows once per interval, restore / debug setters, the horde level 2 revive
## refills it, and the bar of the HealthStrip. Runs on a SandboxWorld with a bot. Quits by itself with an exit code.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/player_stamina_test.tscn
## Not part of the game.

const WATCHDOG_S: float = 300.0
const FRAME_TOLERANCE: int = 2
const EXHAUST_TEXT: String = "Sem fôlego! Ande para recuperar."
const WALK_EPS_MPS: float = 0.05
const SETTLE_S: float = 0.4                  # time to slow down from the sprint speed to the walk speed
const RUN_BACK_Z_M: float = 60.0             # the bot is put back at the origin past this distance (the ground ends at 100)
const MESSAGE_WAIT_CAP_S: float = 60.0
const SPRINT_PHASE_S: float = 2.0
const AMOUNT_EPS: float = 0.3                # stamina units
const KILL_DAMAGE: float = 9999.0
const REVIVE_HEALTH: float = 50.0
const ALLY_SLOT: int = 1
const STRIP_SIZE: Vector2 = Vector2(400.0, 28.0)
const COLOR_STAMINA: Color = Color("#8EC3E6")
const COLOR_DANGER: Color = Color("#D9452B")
const FORWARD: Vector2 = Vector2(0.0, 1.0)

var _passed: int = 0
var _failed: int = 0
var _hints: Array[Dictionary] = []      # {text, duration, frame}


## A remote hunter stand-in so the horde level 2 revive rules apply (they need two hunters).
class FakeHunter extends PlayerBase:
	func _init() -> void:
		collision_layer = 0
		collision_mask = 0

	func is_local() -> bool:
		return false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	GameEvents.hud_message_requested.connect(func(text: String, duration: float) -> void:
		_hints.append({"text": text, "duration": duration, "frame": Engine.get_physics_frames()}))
	_check("physics_60", Engine.physics_ticks_per_second == 60, str(Engine.physics_ticks_per_second))
	await _test_sprint_cycle()
	await _test_regen()
	await _test_no_drain()
	await _test_api()
	await _test_horde_revive()
	_test_strip()
	await _test_hud_feed()
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


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _make_world(horde_level: int = 0, allies: int = 0) -> SandboxWorld:
	_hints.clear()
	var world: SandboxWorld = SandboxWorld.new()
	if horde_level > 0:
		world.horde_mode = true
		world.horde_auto = false
		world.horde_level = horde_level
	add_child(world)
	for i: int in allies:
		var ally: FakeHunter = FakeHunter.new()
		ally.name = "Ally%d" % (i + 1)
		ally.slot = ALLY_SLOT + i
		world.add_child(ally)
		ally.global_position = Vector3(5.0, 0.0, 0.0)
		world.extra_hunters.append(ally)
	await get_tree().process_frame
	world.player.bot_set_enabled(true)
	return world


func _free_world(world: SandboxWorld) -> void:
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _amount(player: Player) -> float:
	return player.get_stamina_frac() * float(Data.get_game().get("stamina", {}).get("max", 100.0))


func _speed(player: Player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _keep_on_ground(player: Player) -> void:
	if absf(player.global_position.z) > RUN_BACK_Z_M:
		player.global_position = Vector3(0.0, player.global_position.y, 0.0)   # keeps the velocity: the run goes on


func _msgs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hint: Dictionary in _hints:
		if hint["text"] == EXHAUST_TEXT:
			out.append(hint)
	return out


# --- Sprint, exhaustion, recovery, message ------------------------------------------------------------------------

func _test_sprint_cycle() -> void:
	var cfg: Dictionary = Data.get_game().get("stamina", {})
	var pcfg: Dictionary = Data.get_game().get("player", {})
	var walk: float = float(pcfg.get("walk_speed_mps", 4.0))
	var noise_walk: float = float(pcfg.get("noise_radius_walk_m", 0.0))
	var noise_sprint: float = float(pcfg.get("noise_radius_sprint_m", 0.0))
	var drain_s: float = float(cfg.get("max", 100.0)) / float(cfg.get("sprint_drain_per_s", 10.0))
	var recover_s: float = float(cfg.get("regen_delay_s", 1.0)) \
		+ float(cfg.get("recover_threshold", 35.0)) / float(cfg.get("regen_per_s", 6.0))
	var again_s: float = float(cfg.get("recover_threshold", 35.0)) / float(cfg.get("sprint_drain_per_s", 10.0))
	var interval_s: float = float(cfg.get("exhausted_message_interval_s", 30.0))
	var world: SandboxWorld = await _make_world()
	var player: Player = world.player
	_check("start_full", player.get_stamina_frac() == 1.0 and not player.is_exhausted())
	_check("recover_frac", is_equal_approx(player.get_stamina_recover_frac(),
		float(cfg.get("recover_threshold", 35.0)) / float(cfg.get("max", 100.0))), str(player.get_stamina_recover_frac()))
	_check("noise_fixture", noise_sprint > noise_walk and noise_walk > 0.0, "walk %.1f sprint %.1f" % [noise_walk, noise_sprint])

	player.bot_set_move(FORWARD, true)
	var n: int = 0
	var sprint_speed_max: float = 0.0
	while not player.is_exhausted() and n < _ticks(drain_s) * 2:
		await get_tree().physics_frame
		n += 1
		sprint_speed_max = maxf(sprint_speed_max, _speed(player))
		_keep_on_ground(player)
	var want: int = _ticks(drain_s)
	_check("exhausts_in_10s", absi(n - want) <= FRAME_TOLERANCE, "%d frames (%.3f s), expected %d" % [n, float(n) / 60.0, want])
	_check("sprint_was_fast", sprint_speed_max > walk + 1.0, "max %.2f m/s" % sprint_speed_max)
	_check("exhausted_frac_zero", player.get_stamina_frac() == 0.0)
	var first_msgs: Array[Dictionary] = _msgs()
	_check("message_once", first_msgs.size() == 1, str(first_msgs.size()))
	_check("message_duration", first_msgs.size() == 1 and is_equal_approx(float(first_msgs[0]["duration"]),
		float(cfg.get("exhausted_message_s", 2.5))), str(first_msgs))
	var msg_frame: int = int(first_msgs[0]["frame"]) if first_msgs.size() == 1 else 0

	# Tired with sprint held: walks, makes walking noise, and comes back after delay + threshold / regen.
	var m: int = 0
	var tired_speed_max: float = 0.0
	var noise_ok: bool = true
	var never_sprinting: bool = true
	while player.is_exhausted() and m < _ticks(recover_s) * 2:
		await get_tree().physics_frame
		m += 1
		_keep_on_ground(player)
		never_sprinting = never_sprinting and (not player.is_sprinting() or not player.is_exhausted())
		if m > _ticks(SETTLE_S):
			tired_speed_max = maxf(tired_speed_max, _speed(player))
			noise_ok = noise_ok and is_equal_approx(player.get_noise_radius(), noise_walk)
	want = _ticks(recover_s)
	_check("recovers_in_6_83s", absi(m - want) <= FRAME_TOLERANCE, "%d frames (%.3f s), expected %d" % [m, float(m) / 60.0, want])
	_check("tired_speed_le_walk", tired_speed_max <= walk + WALK_EPS_MPS and tired_speed_max > walk * 0.9,
		"max %.3f m/s, walk %.1f" % [tired_speed_max, walk])
	_check("tired_noise_is_walk", noise_ok, "walk %.1f" % noise_walk)
	_check("tired_not_sprinting", never_sprinting)
	await _frames(FRAME_TOLERANCE + 1)
	_check("runs_again", player.is_sprinting() and not player.is_exhausted())

	# Second exhaustion: from the threshold, 35 / 10 s of running; no new message inside the interval.
	var k: int = 0
	while not player.is_exhausted() and k < _ticks(again_s) * 3:
		await get_tree().physics_frame
		k += 1
		_keep_on_ground(player)
	want = _ticks(again_s)
	_check("second_exhaust_3_5s", absi(k - want) <= FRAME_TOLERANCE + 2, "%d frames, expected %d" % [k, want])
	_check("message_not_repeated_in_interval", _msgs().size() == 1, str(_msgs().size()))

	# Keep running and tiring: the next message comes only after the interval.
	var edges: int = 2
	var was_tired: bool = true
	var guard: int = _ticks(MESSAGE_WAIT_CAP_S)
	while _msgs().size() < 2 and guard > 0:
		await get_tree().physics_frame
		guard -= 1
		_keep_on_ground(player)
		if player.is_exhausted() and not was_tired:
			edges += 1
		was_tired = player.is_exhausted()
	var msgs: Array[Dictionary] = _msgs()
	var gap_frames: int = int(msgs[1]["frame"]) - msg_frame if msgs.size() >= 2 else 0
	_check("message_repeats_after_interval", msgs.size() == 2 and gap_frames >= _ticks(interval_s) - 1,
		"%d messages, gap %.2f s, %d exhaustions" % [msgs.size(), float(gap_frames) / 60.0, edges])
	_check("message_skipped_exhaustions", edges >= 3, "%d exhaustions" % edges)
	player.bot_set_move(Vector2.ZERO, false)
	await _free_world(world)


# --- Regeneration delay and rate ----------------------------------------------------------------------------------

func _test_regen() -> void:
	var cfg: Dictionary = Data.get_game().get("stamina", {})
	var delay_s: float = float(cfg.get("regen_delay_s", 1.0))
	var rate: float = float(cfg.get("regen_per_s", 6.0))
	var world: SandboxWorld = await _make_world()
	var player: Player = world.player
	player.bot_set_move(FORWARD, true)
	await _frames(_ticks(SPRINT_PHASE_S))
	var spent: float = _amount(player)
	_check("sprint_spends", absf(spent - (100.0 - 10.0 * SPRINT_PHASE_S)) < 1.0, "%.2f" % spent)
	player.bot_set_move(Vector2.ZERO, false)
	await _frames(3)
	var s0: float = _amount(player)
	await _frames(_ticks(delay_s) - 8)
	_check("no_regen_in_first_second", absf(_amount(player) - s0) < 0.01, "%.3f -> %.3f" % [s0, _amount(player)])
	await _frames(_ticks(delay_s * 0.5) + 8)     # now past the delay
	var a: float = _amount(player)
	await _frames(_ticks(1.0))
	var b: float = _amount(player)
	_check("regen_6_per_s", absf((b - a) - rate) < AMOUNT_EPS, "%.3f -> %.3f over 1 s (+%.3f)" % [a, b, b - a])
	await _free_world(world)


# --- Crouching and aiming do not spend it -------------------------------------------------------------------------

func _test_no_drain() -> void:
	var world: SandboxWorld = await _make_world()
	var player: Player = world.player
	player.debug_set_stamina(50.0)
	player.set("_crouching", true)
	player.bot_set_move(FORWARD, true)
	await _frames(_ticks(1.0))
	_check("crouch_no_sprint", not player.is_sprinting() and player.is_crouching())
	_check("crouch_no_drain", _amount(player) >= 50.0, "%.2f" % _amount(player))
	player.set("_crouching", false)
	player.bot_set_aim(true)
	player.debug_set_stamina(50.0)
	await _frames(_ticks(1.0))
	_check("aim_no_sprint", not player.is_sprinting())
	_check("aim_no_drain", _amount(player) >= 50.0, "%.2f" % _amount(player))
	player.bot_set_aim(false)
	player.bot_set_move(Vector2(1.0, 0.0), true)   # sideways: no forward input, no sprint
	player.debug_set_stamina(50.0)
	await _frames(_ticks(0.5))
	_check("sideways_no_drain", not player.is_sprinting() and _amount(player) >= 50.0, "%.2f" % _amount(player))
	player.bot_set_move(Vector2.ZERO, false)
	await _free_world(world)


# --- Public API ---------------------------------------------------------------------------------------------------

func _test_api() -> void:
	var cfg: Dictionary = Data.get_game().get("stamina", {})
	var world: SandboxWorld = await _make_world()
	var player: Player = world.player
	player.debug_set_stamina(0.0)
	_check("debug_zero_tires", player.is_exhausted() and player.get_stamina_frac() == 0.0)
	player.restore_stamina(0.2)
	_check("restore_below_threshold_stays_tired", player.is_exhausted() and is_equal_approx(player.get_stamina_frac(), 0.2),
		str(player.get_stamina_frac()))
	player.restore_stamina(0.2)
	_check("restore_to_threshold_recovers", not player.is_exhausted() and is_equal_approx(player.get_stamina_frac(), 0.4),
		str(player.get_stamina_frac()))
	player.debug_set_stamina(0.0)
	player.restore_stamina(1.0)
	_check("restore_full", player.get_stamina_frac() == 1.0 and not player.is_exhausted())
	player.restore_stamina(1.0)
	_check("restore_capped", player.get_stamina_frac() == 1.0)
	player.debug_set_stamina(500.0)
	_check("debug_clamp_max", player.get_stamina_frac() == 1.0)
	player.debug_set_stamina(-5.0)
	_check("debug_clamp_min", player.get_stamina_frac() == 0.0 and player.is_exhausted())
	var threshold: float = float(cfg.get("recover_threshold", 35.0))
	player.debug_set_stamina(threshold)
	_check("debug_threshold_clears", not player.is_exhausted())
	player.debug_set_stamina(10.0)
	_check("debug_between_keeps_state", not player.is_exhausted() and is_equal_approx(_amount(player), 10.0))
	player.restore_stamina(0.0)
	player.restore_stamina(-1.0)
	_check("restore_nonpositive_ignored", is_equal_approx(_amount(player), 10.0))
	# Dead: restore does nothing.
	player.debug_set_stamina(0.0)
	player.apply_damage(KILL_DAMAGE, Vector3.ZERO)
	_check("dead_fixture", not player.is_alive())
	player.restore_stamina(1.0)
	_check("dead_restore_nothing", player.get_stamina_frac() == 0.0 and player.is_exhausted())
	await _free_world(world)


# --- Horde level 2: down and revive refill ------------------------------------------------------------------------

func _test_horde_revive() -> void:
	var world: SandboxWorld = await _make_world(2, 1)
	var player: Player = world.player
	await _frames(_ticks(0.6))
	player.debug_set_stamina(0.0)
	_check("horde_tired", player.is_exhausted())
	player.apply_damage(KILL_DAMAGE, Vector3.ZERO)
	_check("horde_downed", player.is_downed() and not player.is_alive())
	player.restore_stamina(1.0)
	await _frames(_ticks(1.0))
	_check("downed_frozen", player.get_stamina_frac() == 0.0 and player.is_exhausted(), str(player.get_stamina_frac()))
	player.revive(REVIVE_HEALTH)
	_check("revive_refills", player.get_stamina_frac() == 1.0 and not player.is_exhausted(), str(player.get_stamina_frac()))
	await _frames(_ticks(0.5))
	_check("revive_stays_full", player.get_stamina_frac() == 1.0 and not player.is_exhausted())
	await _free_world(world)


# --- HealthStrip --------------------------------------------------------------------------------------------------

func _test_strip() -> void:
	_check("strip_height", HealthStrip.HEIGHT_PX == 28.0)
	var strip: HealthStrip = HealthStrip.new()
	add_child(strip)
	strip.size = STRIP_SIZE
	_check("strip_hidden_full", not strip.is_stamina_visible())
	strip.set_stamina(1.0, false, 0.35)
	_check("strip_hidden_when_full", not strip.is_stamina_visible())
	strip.set_stamina(0.5, false, 0.35)
	_check("strip_visible_below_full", strip.is_stamina_visible())
	_check("strip_fill", is_equal_approx(strip.get_stamina_fill_pct(), 50.0), str(strip.get_stamina_fill_pct()))
	_check("strip_color_blue", strip.get_stamina_color().is_equal_approx(COLOR_STAMINA), str(strip.get_stamina_color()))
	var stamina: ProgressBar = strip.get_node("Stamina") as ProgressBar
	var mark: Control = strip.get_node("StaminaMark") as Control
	var bar: ProgressBar = strip.get_node("Bar") as ProgressBar
	_check("strip_mark_hidden_when_not_tired", not mark.visible)
	strip.set_stamina(0.0, true, 0.35)
	_check("strip_visible_tired", strip.is_stamina_visible())
	_check("strip_color_red", strip.get_stamina_color().is_equal_approx(COLOR_DANGER), str(strip.get_stamina_color()))
	_check("strip_mark_shown_when_tired", mark.visible)
	var mark_center: float = mark.position.x + mark.size.x * 0.5
	_check("strip_mark_position", absf(mark_center - (stamina.position.x + 0.35 * stamina.size.x)) < 1.0
		and is_equal_approx(mark.position.y, stamina.position.y),
		"%.1f of %.1f" % [mark_center, stamina.size.x])
	_check("strip_mark_1px", is_equal_approx(mark.size.x, 1.0), str(mark.size))
	_check("strip_mark_text_color", (mark as ColorRect).color.is_equal_approx(Color("#F4EFE6")) and mark.modulate == Color.WHITE)
	strip.set_stamina(0.4, false, 0.35)
	_check("strip_mark_hidden_after_recover", not mark.visible and strip.is_stamina_visible())
	strip.set_stamina(1.0, false, 0.35)
	_check("strip_hidden_again", not strip.is_stamina_visible())
	# Geometry: health bar y 5-19, stamina bar y 21-25, same x and width.
	_check("strip_bar_y", is_equal_approx(bar.position.y, 5.0) and is_equal_approx(bar.size.y, 14.0),
		"y %.1f h %.1f" % [bar.position.y, bar.size.y])
	_check("strip_stamina_y", is_equal_approx(stamina.position.y, 21.0) and is_equal_approx(stamina.size.y, 4.0),
		"y %.1f h %.1f" % [stamina.position.y, stamina.size.y])
	_check("strip_stamina_same_x", is_equal_approx(stamina.position.x, bar.position.x) and is_equal_approx(stamina.size.x, bar.size.x),
		"%.1f/%.1f vs %.1f/%.1f" % [stamina.position.x, stamina.size.x, bar.position.x, bar.size.x])
	# Health display as before.
	strip.set_health(100.0, 100.0)
	_check("strip_health_full", strip.get_value_text() == "100" and is_equal_approx(strip.get_fill_pct(), 100.0))
	strip.set_health(25.4, 100.0)
	_check("strip_health_low", strip.get_value_text() == "26" and is_equal_approx(strip.get_fill_pct(), 25.4)
		and strip.get_fill_color().is_equal_approx(COLOR_DANGER))
	strip.queue_free()


## The Hud feeds the strip of the local player every frame.
func _test_hud_feed() -> void:
	var world: SandboxWorld = await _make_world()
	var player: Player = world.player
	var strip: HealthStrip = player.find_child("HealthStrip", true, false) as HealthStrip
	_check("hud_strip_found", strip != null)
	if strip == null:
		await _free_world(world)
		return
	await get_tree().process_frame
	_check("hud_hidden_when_full", not strip.is_stamina_visible())
	player.debug_set_stamina(40.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("hud_visible_below_full", strip.is_stamina_visible() and absf(strip.get_stamina_fill_pct() - 40.0) < 1.0,
		str(strip.get_stamina_fill_pct()))   # regenerating meanwhile
	_check("hud_color_blue", strip.get_stamina_color().is_equal_approx(COLOR_STAMINA))
	player.debug_set_stamina(0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("hud_tired_red_mark", strip.get_stamina_color().is_equal_approx(COLOR_DANGER) and strip.get_node("StaminaMark").visible)
	_check("hud_health_untouched", strip.get_value_text() == "100" and is_equal_approx(strip.get_fill_pct(), 100.0))
	player.restore_stamina(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("hud_hidden_after_restore", not strip.is_stamina_visible())
	await _free_world(world)
