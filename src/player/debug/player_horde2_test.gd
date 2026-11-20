extends Node
## Package A1 test for the horde level 2 player rules (docs/plano_horda_nivel2.md sections 2, 4.6, 4.7, 4.9): counted
## ammo and crates (add_ammo_mags / needs_ammo), confinement to world.get_player_bounds() with the HUD hint, going down
## and being revived, bleeding out, reviving a downed ally by holding interact, taking an ammo crate with a press of
## interact (owner's Q4: not by proximity; a revive target wins); and the cases that keep today's death (one hunter,
## level 1, contract). Runs on a SandboxWorld with a fake level and fake allies. Quits by itself.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/player_horde2_test.tscn
## Not part of the game.

const WATCHDOG_S: float = 300.0          # game time: the bleed-out alone waits 60 s
const LEVEL: int = 2
const DRAW_WAIT_S: float = 0.6           # longer than the weapon draw lockout
const EXPECTED_START_RESERVES: Array[int] = [20, 10, 10, 10, 10]   # plan section 3 test vector (no extra_ammo)
const CONFINE_BOUNDS: Rect2 = Rect2(-5.0, -5.0, 10.0, 10.0)
const CONFINE_PUSH_S: float = 6.5
const EDGE_TOLERANCE_M: float = 0.01
const STILL_TOLERANCE_M: float = 0.05
const KILL_DAMAGE: float = 9999.0
const ALLY_SLOT: int = 1
const ALLY_NEAR: Vector3 = Vector3(1.0, 0.0, 0.0)
const ALLY_FAR: Vector3 = Vector3(5.0, 0.0, 0.0)
const REVIVE_HEALTH: float = 50.0
const CRATE_NEAR: Vector3 = Vector3(0.0, 0.0, 1.0)     # inside the level's pickup_radius_m of the player at the origin
const CRATE_FAR: Vector3 = Vector3(0.0, 0.0, 8.0)
const CRATE_HOLD_S: float = 0.5

var _passed: int = 0
var _failed: int = 0
var _downed_log: Array[float] = []
var _revived_log: Array[float] = []
var _died: int = 0
var _damaged: int = 0
var _picked_log: Array[int] = []
var _hints: Array[Dictionary] = []      # {text, duration, frame}
var _ammo_changed: int = 0


## A remote hunter stand-in: alive / downed by hand, never local.
class FakeHunter extends PlayerBase:
	var fake_alive: bool = true
	var fake_downed: bool = false

	func _init() -> void:
		collision_layer = 0
		collision_mask = 0

	func is_alive() -> bool:
		return fake_alive and not fake_downed

	func is_downed() -> bool:
		return fake_downed

	func is_local() -> bool:
		return false

	func get_display_name() -> String:
		return "Ana"


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	GameEvents.player_downed.connect(func(s: float) -> void: _downed_log.append(s))
	GameEvents.player_revived.connect(func(h: float) -> void: _revived_log.append(h))
	GameEvents.player_died.connect(func() -> void: _died += 1)
	GameEvents.player_damaged.connect(func(_a: float, _p: Vector3, _h: float) -> void: _damaged += 1)
	GameEvents.ammo_picked_up.connect(func(r: int) -> void: _picked_log.append(r))
	GameEvents.hud_message_requested.connect(func(text: String, duration: float) -> void:
		_hints.append({"text": text, "duration": duration, "frame": Engine.get_physics_frames()}))
	_check("interact_registered", InputMap.has_action(&"interact") and InputSetup.ACTIONS.has("interact"))
	_check("interact_key_f", InputSetup.get_key_label(&"interact") == "F", InputSetup.get_key_label(&"interact"))
	await _test_ammo()
	await _test_confine()
	await _test_down_and_revive()
	await _test_bleed_out()
	await _test_revive_ally()
	await _test_crate_press()
	await _test_one_hunter_dies()
	await _test_level_1()
	await _test_contract()
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


func _reset_logs() -> void:
	_downed_log.clear()
	_revived_log.clear()
	_died = 0
	_damaged = 0
	_picked_log.clear()
	_hints.clear()
	_ammo_changed = 0


func _make_world(level: int, horde: bool = true, allies: int = 0) -> SandboxWorld:
	_reset_logs()
	var world: SandboxWorld = SandboxWorld.new()
	world.horde_mode = horde
	world.horde_auto = false
	world.horde_level = level
	add_child(world)
	for i: int in allies:
		var ally: FakeHunter = FakeHunter.new()
		ally.name = "Ally%d" % (i + 1)
		ally.slot = ALLY_SLOT + i
		world.add_child(ally)
		ally.global_position = ALLY_FAR
		world.extra_hunters.append(ally)
	await get_tree().process_frame
	world.player.bot_set_enabled(true)
	return world


func _free_world(world: SandboxWorld) -> void:
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _weapons(player: Player) -> Array[Weapon]:
	var out: Array[Weapon] = []
	for w: Variant in player.get("_weapons"):
		out.append(w as Weapon)
	return out


func _reserves(player: Player) -> Array[int]:
	var out: Array[int] = []
	for w: Weapon in _weapons(player):
		out.append(w.ammo_reserve)
	return out


func _state_flags(player: Player) -> int:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	player.net_write_state(buf)
	return int(buf.data_array[NetCodec.HUNTER_STATE_BYTES - 4])


func _state_health(player: Player) -> int:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	player.net_write_state(buf)
	return int(buf.data_array[NetCodec.HUNTER_STATE_BYTES - 2])


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# --- N1: counted ammo -------------------------------------------------------------------------------------------

func _test_ammo() -> void:
	var world: SandboxWorld = await _make_world(LEVEL)
	var player: Player = world.player
	var ammo: Dictionary = Data.get_horde_level(LEVEL).get("ammo", {})
	var cap_mags: int = int(ammo.get("reserve_cap_mags", 0))
	var weapons: Array[Weapon] = _weapons(player)
	for w: Weapon in weapons:
		w.ammo_changed.connect(func() -> void: _ammo_changed += 1)
	_check("ammo_level_counted", world.get_horde_level() == LEVEL and not bool(ammo.get("infinite", true)))
	_check("ammo_not_infinite", not player.has_infinite_reserve())
	var no_weapon_infinite: bool = true
	for w: Weapon in weapons:
		no_weapon_infinite = no_weapon_infinite and not w.infinite_reserve
	_check("ammo_weapons_not_infinite", no_weapon_infinite)
	_check("ammo_start_reserves", _reserves(player) == EXPECTED_START_RESERVES, str(_reserves(player)))
	_check("ammo_needs_ammo_at_start", player.needs_ammo())

	# A reload spends the reserve.
	await _wait(DRAW_WAIT_S)
	var w0: Weapon = player.get_weapon()
	var mag: int = int(w0.def["mag_size"])
	var before: int = w0.ammo_reserve
	w0.ammo_in_mag = 0
	player.bot_reload()
	await w0.reload_finished
	_check("ammo_reload_spends_reserve", w0.ammo_in_mag == mag and w0.ammo_reserve == before - mag,
		"reserve %d -> %d" % [before, w0.ammo_reserve])

	# add_ammo_mags(2): every weapon gets 2 mags, up to mag x cap.
	_ammo_changed = 0
	var expected_total: int = 0
	var expected_after: Array[int] = []
	for w: Weapon in weapons:
		var m: int = int(w.def["mag_size"])
		var add: int = mini(2 * m, m * cap_mags - w.ammo_reserve)
		expected_total += maxi(add, 0)
		expected_after.append(w.ammo_reserve + maxi(add, 0))
	var got: int = player.add_ammo_mags(2)
	_check("ammo_add_total", got == expected_total and expected_total > 0, "%d (expected %d)" % [got, expected_total])
	_check("ammo_add_reserves", _reserves(player) == expected_after, str(_reserves(player)))
	_check("ammo_picked_up_signal", _picked_log == ([expected_total] as Array[int]), str(_picked_log))
	_check("ammo_changed_per_weapon", _ammo_changed == weapons.size(), str(_ammo_changed))

	# Near the cap: only what fits, then nothing.
	var fill_total: int = 0
	for w: Weapon in weapons:
		w.ammo_reserve = int(w.def["mag_size"]) * cap_mags - 3
		fill_total += 3
	_check("ammo_needs_ammo_below_cap", player.needs_ammo())
	_picked_log.clear()
	got = player.add_ammo_mags(2)
	var at_cap: bool = true
	for w: Weapon in weapons:
		at_cap = at_cap and w.ammo_reserve == int(w.def["mag_size"]) * cap_mags
	_check("ammo_add_respects_cap", got == fill_total and at_cap, "%d (expected %d) %s" % [got, fill_total, str(_reserves(player))])
	_check("ammo_full_no_need", not player.needs_ammo())
	_ammo_changed = 0
	got = player.add_ammo_mags(2)
	_check("ammo_full_adds_nothing", got == 0 and _picked_log.size() == 1 and _ammo_changed == 0,
		"%d, signals %d, changed %d" % [got, _picked_log.size(), _ammo_changed])
	_check("ammo_zero_mags", player.add_ammo_mags(0) == 0)
	await _free_world(world)


# --- N2: confinement --------------------------------------------------------------------------------------------

func _push_north(player: Player, seconds: float) -> void:
	player.bot_look_at(player.get_eye_position() + Vector3(0.0, 0.0, -100.0))
	player.bot_set_move(Vector2(0.0, 1.0), true)
	await _wait(seconds)
	player.bot_set_move(Vector2.ZERO, false)


func _test_confine() -> void:
	var world: SandboxWorld = await _make_world(LEVEL)
	var player: Player = world.player
	var confine: Dictionary = Data.get_horde_level(LEVEL).get("confine", {})
	world.player_bounds = CONFINE_BOUNDS
	await _push_north(player, CONFINE_PUSH_S)
	var z: float = player.global_position.z
	_check("confine_stops_at_edge", absf(z - CONFINE_BOUNDS.position.y) <= EDGE_TOLERANCE_M, "z = %.3f" % z)
	var texts_ok: bool = not _hints.is_empty()
	for hint: Dictionary in _hints:
		texts_ok = texts_ok and hint["text"] == "Fique dentro do cercado da fazenda." \
			and is_equal_approx(float(hint["duration"]), float(confine.get("hint_s", -1.0)))
	_check("confine_hint_text", texts_ok, str(_hints))
	var min_gap_s: float = INF
	for i: int in range(1, _hints.size()):
		var gap: int = int(_hints[i]["frame"]) - int(_hints[i - 1]["frame"])
		min_gap_s = minf(min_gap_s, float(gap) / float(Engine.physics_ticks_per_second))
	var interval: float = float(confine.get("hint_interval_s", 0.0))
	_check("confine_hint_rate", _hints.size() == 2 and min_gap_s >= interval - 0.02,
		"%d hints, min gap %.2f s (interval %.1f s)" % [_hints.size(), min_gap_s, interval])
	# Standing still at the edge asks nothing more.
	var count: int = _hints.size()
	await _wait(interval + 0.5)
	_check("confine_no_hint_when_still", _hints.size() == count, str(_hints.size()))
	# Every side holds (gate included: no collision there in the real map).
	world.player_bounds = Rect2(-5.0, -5.0, 10.0, 10.0)
	player.bot_teleport(Vector3(0.0, 0.0, 0.0))
	player.bot_look_at(player.get_eye_position() + Vector3(100.0, 0.0, 0.0))
	player.bot_set_move(Vector2(0.0, 1.0), true)
	await _wait(2.5)
	player.bot_set_move(Vector2.ZERO, false)
	_check("confine_east_edge", absf(player.global_position.x - CONFINE_BOUNDS.end.x) <= EDGE_TOLERANCE_M,
		"x = %.3f" % player.global_position.x)
	# No bounds = no limit.
	world.player_bounds = Rect2()
	await _push_north(player, 2.0)
	_check("confine_off_without_bounds", player.global_position.z < CONFINE_BOUNDS.position.y - 1.0,
		"z = %.3f" % player.global_position.z)
	# C1: the body collides with the fence layer (bullets and sight do not).
	_check("body_mask_has_fence", player.collision_mask == Layers.MASK_PLAYER_BODY
		and (player.collision_mask & Layers.FENCE) != 0, str(player.collision_mask))
	var fence: StaticBody3D = StaticBody3D.new()
	fence.collision_layer = Layers.FENCE
	fence.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20.0, 1.3, 0.15)
	shape.shape = box
	fence.add_child(shape)
	world.add_child(fence)
	var fence_z: float = player.global_position.z - 3.0
	fence.global_position = Vector3(player.global_position.x, 0.65, fence_z)
	await get_tree().physics_frame
	await _push_north(player, 2.0)
	_check("fence_blocks_body", player.global_position.z > fence_z, "z = %.3f, fence at %.3f" % [player.global_position.z, fence_z])
	await _free_world(world)


# --- N4: down, revive, bleed out ---------------------------------------------------------------------------------

func _test_down_and_revive() -> void:
	var world: SandboxWorld = await _make_world(LEVEL, true, 1)
	var player: Player = world.player
	var revive: Dictionary = Data.get_horde_level(LEVEL).get("revive", {})
	var bleed_s: float = float(revive.get("bleed_out_s", 0.0))
	await _wait(DRAW_WAIT_S)
	player.apply_damage(KILL_DAMAGE, player.global_position + Vector3(0.0, 0.0, -2.0))
	_check("down_not_alive", not player.is_alive())
	_check("down_is_downed", player.is_downed())
	_check("down_no_player_died", _died == 0, str(_died))
	_check("down_signal", _downed_log == ([bleed_s] as Array[float]), str(_downed_log))
	var flags: int = _state_flags(player)
	_check("down_state_flags", (flags & NetCodec.HF_DOWNED) != 0 and (flags & NetCodec.HF_ALIVE) == 0, str(flags))
	_check("down_state_health", _state_health(player) == 0)
	_check("down_bleed_left", is_equal_approx(player.get_bleed_out_left_s(), bleed_s), str(player.get_bleed_out_left_s()))
	var damaged: int = _damaged
	player.apply_damage(10.0, Vector3.ZERO)
	_check("down_ignores_damage", _damaged == damaged and player.get_health() == 0.0)
	_check("down_cannot_fire", not player.bot_fire())
	_check("down_no_target", player.get_revive_target_slot() == -1)
	var start: Vector2 = _flat(player.global_position)
	player.bot_set_move(Vector2(0.0, 1.0), true)
	await _wait(1.0)
	player.bot_set_move(Vector2.ZERO, false)
	_check("down_cannot_move", _flat(player.global_position).distance_to(start) < STILL_TOLERANCE_M,
		"%.3f m" % _flat(player.global_position).distance_to(start))
	var eye_h: float = player.get_eye_position().y - player.global_position.y
	_check("down_camera_on_ground", absf(eye_h - Player.DOWNED_EYE_HEIGHT_M) < 0.01, "%.3f m" % eye_h)
	_check("down_camera_roll", absf(rad_to_deg(player.get_camera().rotation.z) - Player.DOWNED_ROLL_DEG) < 0.5,
		"%.1f deg" % rad_to_deg(player.get_camera().rotation.z))
	_check("down_bleeding", player.get_bleed_out_left_s() < bleed_s - 0.9 and player.get_bleed_out_left_s() > bleed_s - 1.1,
		str(player.get_bleed_out_left_s()))

	player.revive(REVIVE_HEALTH)
	_check("revive_alive", player.is_alive() and not player.is_downed())
	_check("revive_health", is_equal_approx(player.get_health(), REVIVE_HEALTH), str(player.get_health()))
	_check("revive_signal", _revived_log == ([REVIVE_HEALTH] as Array[float]), str(_revived_log))
	flags = _state_flags(player)
	_check("revive_state_flags", (flags & NetCodec.HF_ALIVE) != 0 and (flags & NetCodec.HF_DOWNED) == 0, str(flags))
	_check("revive_bleed_zero", player.get_bleed_out_left_s() == 0.0)
	player.revive(REVIVE_HEALTH)
	_check("revive_noop_when_alive", _revived_log.size() == 1)
	await _wait(DRAW_WAIT_S)
	_check("revive_can_fire", player.bot_fire())
	start = _flat(player.global_position)
	player.bot_set_move(Vector2(0.0, 1.0), false)
	await _wait(0.5)
	player.bot_set_move(Vector2.ZERO, false)
	_check("revive_can_move", _flat(player.global_position).distance_to(start) > 0.5)
	eye_h = player.get_eye_position().y - player.global_position.y
	_check("revive_camera_up", eye_h > 1.0, "%.3f m" % eye_h)
	_check("revive_no_death", _died == 0)
	await _free_world(world)


func _test_bleed_out() -> void:
	var world: SandboxWorld = await _make_world(LEVEL, true, 1)
	var player: Player = world.player
	var bleed_s: float = float(Data.get_horde_level(LEVEL).get("revive", {}).get("bleed_out_s", 0.0))
	player.apply_damage(KILL_DAMAGE, Vector3.ZERO)
	_check("bleed_downed", player.is_downed() and _died == 0)
	await _wait(bleed_s - 1.0)
	_check("bleed_still_down_before", player.is_downed() and _died == 0, "left %.2f s" % player.get_bleed_out_left_s())
	await _wait(2.0)
	_check("bleed_died_once", _died == 1, str(_died))
	_check("bleed_dead_state", not player.is_alive() and not player.is_downed())
	var flags: int = _state_flags(player)
	_check("bleed_state_flags", (flags & (NetCodec.HF_ALIVE | NetCodec.HF_DOWNED)) == 0, str(flags))
	player.revive(REVIVE_HEALTH)
	_check("bleed_revive_too_late", not player.is_alive() and _revived_log.is_empty())
	await _wait(1.0)
	_check("bleed_died_only_once", _died == 1, str(_died))
	await _free_world(world)


func _test_revive_ally() -> void:
	var world: SandboxWorld = await _make_world(LEVEL, true, 1)
	var player: Player = world.player
	var revive: Dictionary = Data.get_horde_level(LEVEL).get("revive", {})
	var hold_s: float = float(revive.get("hold_s", 0.0))
	var ally: FakeHunter = world.extra_hunters[0] as FakeHunter
	ally.global_position = ALLY_NEAR
	await _wait(DRAW_WAIT_S)
	_check("ally_standing_no_target", player.get_revive_target_slot() == -1)
	ally.fake_downed = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ally_down_target", player.get_revive_target_slot() == ALLY_SLOT, str(player.get_revive_target_slot()))
	_check("ally_no_progress_without_hold", player.get_revive_progress() == 0.0)

	player.bot_set_interact(true)
	player.bot_set_move(Vector2(0.0, 1.0), true)
	var start: Vector2 = _flat(player.global_position)
	await _wait(hold_s * 0.5)
	var p: float = player.get_revive_progress()
	_check("ally_progress_half", absf(p - 0.5) < 0.05, "%.3f" % p)
	_check("ally_hold_freezes_move", _flat(player.global_position).distance_to(start) < STILL_TOLERANCE_M,
		"%.3f m" % _flat(player.global_position).distance_to(start))
	_check("ally_hold_blocks_fire", not player.bot_fire())
	player.bot_set_move(Vector2.ZERO, false)   # stay next to the ally for the rest (the retry window frees the move)
	_check("ally_no_request_yet", world.revive_requests.is_empty())
	await _wait(hold_s * 0.5 + 0.2)
	_check("ally_request_once", world.revive_requests == ([ALLY_SLOT] as Array[int]), str(world.revive_requests))
	_check("ally_progress_reset", player.get_revive_progress() < 0.1, "%.3f" % player.get_revive_progress())
	await _wait(1.0)   # still holding: the target is ignored for retry_s, then a new hold starts from 0
	_check("ally_request_still_once", world.revive_requests.size() == 1, str(world.revive_requests))
	_check("ally_still_in_range", _flat(player.global_position).distance_to(_flat(ALLY_NEAR)) < 2.0,
		"%.2f m" % _flat(player.global_position).distance_to(_flat(ALLY_NEAR)))

	player.bot_set_interact(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ally_release_resets", player.get_revive_progress() == 0.0)
	player.bot_set_interact(true)
	await _wait(0.5)
	_check("ally_progress_again", player.get_revive_progress() > 0.0,
		"target %d, progress %.3f" % [player.get_revive_target_slot(), player.get_revive_progress()])
	ally.global_position = ALLY_FAR
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ally_out_of_range", player.get_revive_target_slot() == -1 and player.get_revive_progress() == 0.0)
	ally.global_position = ALLY_NEAR
	ally.fake_downed = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ally_up_no_target", player.get_revive_target_slot() == -1)
	player.bot_set_interact(false)
	player.bot_set_move(Vector2.ZERO, false)
	_check("ally_total_requests", world.revive_requests.size() == 1, str(world.revive_requests))
	await _free_world(world)


# --- Q4: the ammo crate is taken with a press of interact ---------------------------------------------------------

func _press(player: Player) -> void:
	player.bot_set_interact(true)
	await get_tree().process_frame
	player.bot_set_interact(false)
	await get_tree().process_frame


func _test_crate_press() -> void:
	var world: SandboxWorld = await _make_world(LEVEL, true, 1)
	var player: Player = world.player
	var reach: float = float(Data.get_horde_level(LEVEL).get("ammo_crates", {}).get("pickup_radius_m", 0.0))
	_check("crate_fixture_in_reach", reach > CRATE_NEAR.length() and reach < CRATE_FAR.length(), "pickup_radius_m %.2f" % reach)
	world.ammo_crate_positions = PackedVector3Array([CRATE_FAR, CRATE_NEAR])
	await _wait(DRAW_WAIT_S)
	_check("crate_target_in_reach", player.get_ammo_crate_target() == 1, str(player.get_ammo_crate_target()))
	_check("crate_standing_requests_nothing", world.ammo_crate_requests.is_empty(), str(world.ammo_crate_requests))
	await _press(player)
	_check("crate_press_requests_once", world.ammo_crate_requests == ([1] as Array[int]), str(world.ammo_crate_requests))
	# Holding is one press: one more request, not one per frame.
	player.bot_set_interact(true)
	await _wait(CRATE_HOLD_S)
	player.bot_set_interact(false)
	await get_tree().process_frame
	_check("crate_hold_is_one_press", world.ammo_crate_requests == ([1, 1] as Array[int]), str(world.ammo_crate_requests))
	# Interact already held while walking up to the crate: no press, nothing taken.
	world.ammo_crate_requests.clear()
	world.ammo_crate_positions = PackedVector3Array([CRATE_FAR])
	player.bot_set_interact(true)
	await _frames(2)
	_check("crate_out_of_reach_no_target", player.get_ammo_crate_target() == -1, str(player.get_ammo_crate_target()))
	world.ammo_crate_positions = PackedVector3Array([CRATE_NEAR])
	await _frames(2)
	player.bot_set_interact(false)
	await _frames(2)
	_check("crate_held_before_reach_takes_nothing", world.ammo_crate_requests.is_empty(), str(world.ammo_crate_requests))
	# Reserve at the cap: no target and a press takes nothing.
	var cap_mags: int = int(Data.get_horde_level(LEVEL).get("ammo", {}).get("reserve_cap_mags", 0))
	var saved: Array[int] = _reserves(player)
	for w: Weapon in _weapons(player):
		w.ammo_reserve = int(w.def["mag_size"]) * cap_mags
	await _frames(2)
	_check("crate_full_no_target", not player.needs_ammo() and player.get_ammo_crate_target() == -1, str(player.get_ammo_crate_target()))
	await _press(player)
	_check("crate_full_press_takes_nothing", world.ammo_crate_requests.is_empty(), str(world.ammo_crate_requests))
	var weapons: Array[Weapon] = _weapons(player)
	for i: int in weapons.size():
		weapons[i].ammo_reserve = saved[i]
	await _frames(2)
	_check("crate_target_back_below_cap", player.get_ammo_crate_target() == 0, str(player.get_ammo_crate_target()))
	# A downed ally in reach: interact revives, the crate waits.
	var ally: FakeHunter = world.extra_hunters[0] as FakeHunter
	ally.global_position = ALLY_NEAR
	ally.fake_downed = true
	await _frames(2)
	_check("crate_revive_wins_target", player.get_revive_target_slot() == ALLY_SLOT and player.get_ammo_crate_target() == -1,
		"revive %d crate %d" % [player.get_revive_target_slot(), player.get_ammo_crate_target()])
	await _press(player)
	_check("crate_revive_wins_press", world.ammo_crate_requests.is_empty() and player.get_revive_progress() == 0.0,
		str(world.ammo_crate_requests))
	ally.fake_downed = false
	await _frames(2)
	_check("crate_after_revive_target_gone", player.get_ammo_crate_target() == 0, str(player.get_ammo_crate_target()))
	# Down: no crate.
	player.apply_damage(KILL_DAMAGE, Vector3.ZERO)
	await _frames(2)
	_check("crate_downed_no_target", player.is_downed() and player.get_ammo_crate_target() == -1)
	await _press(player)
	_check("crate_downed_press_takes_nothing", world.ammo_crate_requests.is_empty(), str(world.ammo_crate_requests))
	await _free_world(world)
	# Level 1 (infinite ammo): a crate in reach is never a target.
	world = await _make_world(1, true, 1)
	world.ammo_crate_positions = PackedVector3Array([CRATE_NEAR])
	await _frames(2)
	_check("crate_level1_no_target", world.player.get_ammo_crate_target() == -1)
	await _press(world.player)
	_check("crate_level1_press_nothing", world.ammo_crate_requests.is_empty())
	await _free_world(world)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


# --- Today's death kept -----------------------------------------------------------------------------------------

func _expect_plain_death(world: SandboxWorld, label: String) -> void:
	var player: Player = world.player
	player.apply_damage(KILL_DAMAGE, Vector3.ZERO)
	_check("%s_dies" % label, _died == 1 and not player.is_alive() and not player.is_downed(),
		"died %d, downed %s" % [_died, str(player.is_downed())])
	_check("%s_no_downed_signal" % label, _downed_log.is_empty())
	await _wait(0.5)
	_check("%s_died_once" % label, _died == 1)


func _test_one_hunter_dies() -> void:
	var world: SandboxWorld = await _make_world(LEVEL)
	await _expect_plain_death(world, "solo_level2")
	await _free_world(world)


func _test_level_1() -> void:
	var world: SandboxWorld = await _make_world(1, true, 1)
	var player: Player = world.player
	_check("level1_infinite", player.has_infinite_reserve() and not player.needs_ammo())
	_check("level1_no_crate_ammo", player.add_ammo_mags(2) == 0 and _picked_log.is_empty())
	world.player_bounds = Rect2()
	await _expect_plain_death(world, "level1")
	await _free_world(world)


func _test_contract() -> void:
	var world: SandboxWorld = await _make_world(LEVEL, false, 1)
	var player: Player = world.player
	_check("contract_not_horde", not player.get_request().is_horde() and world.get_horde_level() == 0)
	_check("contract_no_infinite", not player.has_infinite_reserve() and not player.needs_ammo())
	world.player_bounds = CONFINE_BOUNDS   # ignored outside the horde
	await _push_north(player, 2.0)
	_check("contract_no_confine", player.global_position.z < CONFINE_BOUNDS.position.y - 1.0,
		"z = %.3f" % player.global_position.z)
	_check("contract_no_hint", _hints.is_empty())
	await _expect_plain_death(world, "contract")
	await _free_world(world)
