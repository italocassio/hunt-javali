extends Node
## Package A4 test for the knife (F4, docs/plano_faca_mochila_folego.md 1.4, 1.5, 1.7, 2.5, 2.6, 2.7; jogo 0.9.9: the
## knife is a melee weapon the hunter **equips**). It covers: X puts the knife in the hand and takes it back, the
## weapon views that swap, `fire` as the swing (one swing per click, never a burst while held), the 0.6 s cadence and
## the 0.45 s lock (no shot, no aim, no reload, no switch, no item, no toggle), weapon_1 / weapon_2 / weapon_swap that
## put the knife away and select the weapon, the damage of the level with no distance falloff, the 2.2 m reach, the aim
## assist sphere, the reload the swing cancels, the blocks of section 1.4, shot_fired after the hit with noise 0, a shot
## id that never repeats a gun shot, an untouched net state, the weapon panel showing "Faca" with no ammunition, the
## touch button (equip, highlight, swing with Tiro, weapon card that puts it away) and the key legend.
## Runs on a SandboxWorld with a test HitZone half a metre below the look line.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/player_knife_test.tscn
## Not part of the game.

const WATCHDOG_S: float = 300.0
const LEVEL_DAMAGE: Array[float] = [30.0, 45.0, 65.0, 90.0]   # the seed of data/upgrades.json (fixture check)
const ZONE_BOX_M: float = 0.4                # test HitZone: a 0.4 m cube
const ZONE_DROP_M: float = 0.5               # the zone sits half a metre below the eye
const NEAR_M: float = 1.5                    # a hit inside the reach
const FAR_M: float = 3.0                     # out of reach
const ASSIST_FORWARD_M: float = 2.0
const ASSIST_SIDE_M: float = 0.3             # beside the look line, inside assist_radius_m of the sphere
const ALLY_SLOT: int = 1
const KILL_DAMAGE: float = 9999.0
const SPECTATE_WAIT_S: float = 2.5           # coop.spectate_delay_s (2 s) plus slack
const SCREENS: Array[Vector2] = [Vector2(1532.0, 720.0), Vector2(1280.0, 720.0), Vector2(1280.0, 960.0)]
## Centre of the Faca button on each of those screens (docs 2.7).
const KNIFE_CENTERS: Array[Vector2] = [Vector2(1432.0, 530.0), Vector2(1180.0, 530.0), Vector2(1180.0, 770.0)]
const STICK_CENTER_FROM_LEFT_PX: float = 242.0
const STICK_CENTER_FROM_BOTTOM_PX: float = 220.0
const STICK_RADIUS_PX: float = 90.0
const CARD_H_PX: float = 55.0                # weapon card height used by the overlap check (as in test_item_hud)
const CARD_BOTTOM_PX: float = 42.0           # card bottom above the screen edge (8 + 28 + 6)
const KNIFE_ID: StringName = &"knife"
const FIRE_ID: StringName = &"fire"
const PANEL_KNIFE_NAME: String = "Faca"      # WeaponPanel.KNIFE_NAME (the text the player reads)

var _passed: int = 0
var _failed: int = 0
var _hits: Array[HitInfo] = []
var _shots: Array[Dictionary] = []     # shot_fired payloads
var _events: Array[String] = []        # "hit" / "shot", in the order they arrived
var _gun_shot_id: int = 0              # shot id of the last gun shot (a lambda cannot write a local)


## A remote hunter stand-in so the horde level 2 revive rules apply (they need two hunters).
class FakeHunter extends PlayerBase:
	func _init() -> void:
		collision_layer = 0
		collision_mask = 0

	func is_local() -> bool:
		return false


## Sandbox whose request carries a chosen knife level.
class KnifeWorld extends SandboxWorld:
	var knife_level: int = 1

	func _request() -> HuntRequest:
		var r: HuntRequest = super()
		r.knife_level = knife_level
		return r


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	GameEvents.shot_fired.connect(_on_shot_fired)
	_check("physics_60", Engine.physics_ticks_per_second == 60, str(Engine.physics_ticks_per_second))
	_test_data_and_clamp()
	await _test_levels()
	await _test_equip_toggle()
	await _test_weapon_keys_unequip()
	await _test_fire_swings()
	await _test_equipped_blocks()
	await _test_reach_and_assist()
	await _test_cadence()
	await _test_swing_locks()
	await _test_view_pose()
	await _test_reload_cancelled()
	await _test_net_untouched()
	await _test_blocks()
	await _test_without_knife()
	await _test_downed()
	await _test_spectator()
	await _test_panel()
	await _test_touch()
	await _test_legend_and_input()
	InputSetup.set_touch_override("auto")
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


## One press of `action` that lasts `hold_frames` physics frames, then released (the hunter reads the edge).
func _tap(action: StringName, hold_frames: int = 2) -> void:
	Input.action_press(action)
	await _frames(hold_frames)
	Input.action_release(action)
	await _frames(2)


func _clear() -> void:
	_hits.clear()
	_shots.clear()
	_events.clear()


func _on_hit(hit: HitInfo) -> void:
	_hits.append(hit)
	_events.append("hit")


func _on_shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float) -> void:
	_shots.append({"weapon_id": weapon_id, "origin": origin, "direction": direction, "noise": noise_radius_m})
	_events.append("shot")


func _stats() -> Dictionary:
	return Data.get_upgrade(Ids.KNIFE).get("stats", {})


func _stat(key: String) -> float:
	return float(_stats().get(key, 0.0))


func _make_world(knife_level: int = 1, horde_level: int = 0, allies: int = 0) -> KnifeWorld:
	_clear()
	var world: KnifeWorld = KnifeWorld.new()
	world.knife_level = knife_level
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
	await get_tree().physics_frame
	return world


func _free_world(world: SandboxWorld) -> void:
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Test HitZone (a cube on layer BOAR_HITZONE) in the world, hooked to _on_hit.
func _make_zone(world: SandboxWorld) -> HitZone:
	var zone: HitZone = HitZone.new()
	zone.name = "KnifeTestZone"
	zone.zone = Ids.ZONE_BODY
	zone.target_id = 99
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE * ZONE_BOX_M
	cs.shape = box
	zone.add_child(cs)
	world.add_child(zone)
	zone.hit_received.connect(_on_hit)
	return zone


## Puts the zone `forward_m` ahead (the hunter spawns looking down -Z), `side_m` to the right and half a metre
## below the eye. Returns its centre.
func _place_zone(zone: HitZone, eye: Vector3, forward_m: float, side_m: float) -> Vector3:
	zone.global_position = eye + Vector3(side_m, -ZONE_DROP_M, -forward_m)
	return zone.global_position


## A zone in reach, already under the hunter's look line.
func _zone_in_reach(world: SandboxWorld, player: Player) -> HitZone:
	var zone: HitZone = _make_zone(world)
	player.bot_look_at(_place_zone(zone, player.get_eye_position(), NEAR_M, 0.0))
	await _frames(3)
	return zone


func _knife_of(player: Player) -> Knife:
	return player.get("_knife") as Knife


## The weapon view in the hand right now (null when the holder has none).
func _weapon_view(player: Player) -> Node3D:
	return player.get_weapon_holder().get_current_view()


func _weapon_view_visible(player: Player) -> bool:
	var view: Node3D = _weapon_view(player)
	return view != null and view.visible


func _knife_view_visible(player: Player) -> bool:
	var knife: Knife = _knife_of(player)
	if knife == null or knife.get_view() == null:
		return false
	return knife.get_view().visible


# --- Data, clamp -------------------------------------------------------------------------------------------------

func _test_data_and_clamp() -> void:
	var count: int = Data.get_upgrade_level_count(Ids.KNIFE)
	_check("data_has_knife", count == LEVEL_DAMAGE.size(), "%d niveis" % count)
	for i: int in mini(count, LEVEL_DAMAGE.size()):
		var damage: float = float(Data.get_upgrade_level_def(Ids.KNIFE, i + 1).get("damage", -1.0))
		_check("data_damage_%d" % (i + 1), is_equal_approx(damage, LEVEL_DAMAGE[i]), "%.1f" % damage)
	_check("data_reach", is_equal_approx(_stat("reach_m"), 2.2), "%.2f" % _stat("reach_m"))
	_check("data_assist", is_equal_approx(_stat("assist_radius_m"), 0.35), "%.2f" % _stat("assist_radius_m"))
	_check("data_swing", is_equal_approx(_stat("swing_s"), 0.45), "%.2f" % _stat("swing_s"))
	_check("data_interval", is_equal_approx(_stat("swing_interval_s"), 0.6), "%.2f" % _stat("swing_interval_s"))
	_check("data_noise_zero", _stat("noise_radius_m") == 0.0, "%.2f" % _stat("noise_radius_m"))
	# The Knife clamps the requested level into the levels that exist.
	var low: Knife = Knife.new()
	add_child(low)
	_check("clamp_low", low.setup(0, null) and low.get_level() == 1, str(low.get_level()))
	var high: Knife = Knife.new()
	add_child(high)
	_check("clamp_high", high.setup(99, null) and high.get_level() == count, str(high.get_level()))
	_check("clamp_high_damage", is_equal_approx(high.get_damage(), LEVEL_DAMAGE[LEVEL_DAMAGE.size() - 1]),
		"%.1f" % high.get_damage())
	_check("ready_at_start", high.is_ready() and not high.is_swinging() and high.get_cooldown_frac() == 0.0)
	# Equipped state of the Knife itself (0.9.9): off at setup, instant both ways.
	_check("knife_starts_on_the_belt", not high.is_equipped())
	_check("knife_set_equipped_true", high.set_equipped(true) and high.is_equipped())
	_check("knife_set_equipped_twice", high.set_equipped(true) and high.is_equipped())
	_check("knife_set_equipped_false", high.set_equipped(false) and not high.is_equipped())
	low.queue_free()
	high.queue_free()


# --- One swing per level ------------------------------------------------------------------------------------------

func _test_levels() -> void:
	var reach: float = _stat("reach_m")
	for i: int in LEVEL_DAMAGE.size():
		var level: int = i + 1
		var world: KnifeWorld = await _make_world(level)
		var player: Player = world.player
		var want: float = float(Data.get_upgrade_level_def(Ids.KNIFE, level).get("damage", -1.0))
		_check("player_level_%d" % level, player.get_knife_level() == level, str(player.get_knife_level()))
		_check("player_damage_%d" % level, is_equal_approx(player.get_knife_damage(), want), "%.1f" % player.get_knife_damage())
		var zone: HitZone = _make_zone(world)
		var eye: Vector3 = player.get_eye_position()
		var target: Vector3 = _place_zone(zone, eye, NEAR_M, 0.0)
		player.bot_look_at(target)
		await _frames(3)
		_clear()
		_check("hunt_starts_with_the_weapon_%d" % level, not player.is_knife_equipped())
		_check("swing_happens_%d" % level, player.bot_knife())       # bot_knife equips if needed, then swings
		_check("knife_stays_in_hand_%d" % level, player.is_knife_equipped())
		_check("one_hit_%d" % level, _hits.size() == 1, "%d acertos" % _hits.size())
		if _hits.size() == 1:
			var hit: HitInfo = _hits[0]
			_check("hit_weapon_%d" % level, hit.weapon_id == Ids.KNIFE, str(hit.weapon_id))
			_check("hit_damage_%d" % level, is_equal_approx(hit.damage, want), "%.1f" % hit.damage)
			_check("hit_distance_%d" % level, hit.distance_m > 0.0 and hit.distance_m <= reach, "%.2f m" % hit.distance_m)
			_check("hit_zone_%d" % level, hit.zone == Ids.ZONE_BODY and hit.target_id == 99, str(hit.zone))
			_check("hit_slot_%d" % level, hit.shooter_slot == NetCodec.shot_slot(hit.shot_id) and hit.shooter_slot == Net.get_local_slot())
		_check("one_shot_fired_%d" % level, _shots.size() == 1, "%d sinais" % _shots.size())
		if _shots.size() == 1:
			_check("shot_is_knife_%d" % level, _shots[0]["weapon_id"] == Ids.KNIFE, str(_shots[0]["weapon_id"]))
			_check("shot_noise_zero_%d" % level, float(_shots[0]["noise"]) == 0.0, str(_shots[0]["noise"]))
			_check("shot_origin_%d" % level, (_shots[0]["origin"] as Vector3).distance_to(eye) < 0.01, str(_shots[0]["origin"]))
			_check("shot_direction_%d" % level,
				(_shots[0]["direction"] as Vector3).distance_to(player.get_look_direction()) < 0.01, str(_shots[0]["direction"]))
		_check("shot_after_hit_%d" % level, _events == ["hit", "shot"], str(_events))
		await _free_world(world)


# --- X equips and takes the knife back (0.9.9) --------------------------------------------------------------------

func _test_equip_toggle() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = await _zone_in_reach(world, player)
	_clear()
	_check("weapon_view_before_equip", _weapon_view_visible(player))
	_check("knife_view_before_equip", not _knife_view_visible(player))

	await _tap(KNIFE_ID)
	_check("x_equips", player.is_knife_equipped())
	_check("x_equip_has_no_hit", _hits.is_empty() and _shots.is_empty(), "%d acertos" % _hits.size())
	_check("weapon_view_hidden_while_equipped", not _weapon_view_visible(player))
	_check("knife_view_shown_while_equipped", _knife_view_visible(player) or _knife_of(player).get_view() == null,
		"sem assets/models/weapons/knife_view.tscn" if _knife_of(player).get_view() == null else "")

	await _tap(KNIFE_ID)
	_check("x_again_back_to_the_weapon", not player.is_knife_equipped())
	_check("weapon_view_back", _weapon_view_visible(player))
	_check("knife_view_hidden_again", not _knife_view_visible(player))

	# Holding X does not flap: one press is one toggle.
	Input.action_press(KNIFE_ID)
	await _frames(_ticks(1.0))
	_check("hold_x_toggles_once", player.is_knife_equipped())
	Input.action_release(KNIFE_ID)
	await _frames(2)
	_check("hold_x_no_hit", _hits.is_empty(), "%d acertos" % _hits.size())

	# The API the HUD uses.
	_check("toggle_knife_returns_state", not player.toggle_knife() and not player.is_knife_equipped())
	_check("set_knife_equipped_true", player.set_knife_equipped(true) and player.is_knife_equipped())
	_check("set_knife_equipped_true_again", player.set_knife_equipped(true))
	_check("set_knife_equipped_false", player.set_knife_equipped(false) and not player.is_knife_equipped())
	_check("zone_untouched_by_equipping", zone.is_inside_tree())
	await _free_world(world)


# --- weapon_1 / weapon_2 / weapon_swap put the knife away ---------------------------------------------------------

func _test_weapon_keys_unequip() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)
	_check("two_weapons", player.get_weapon_count() >= 2, str(player.get_weapon_count()))

	# weapon_2 with the knife in the hand: it goes away and the second weapon comes out.
	_check("equip_for_weapon_2", player.set_knife_equipped(true))
	await _tap(&"weapon_2")
	_check("weapon_2_unequips", not player.is_knife_equipped())
	_check("weapon_2_selects", player.get_weapon_slot() == 1, str(player.get_weapon_slot()))
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)

	# weapon_1 with the knife in the hand: back to the first weapon.
	_check("equip_for_weapon_1", player.set_knife_equipped(true))
	await _tap(&"weapon_1")
	_check("weapon_1_unequips", not player.is_knife_equipped())
	_check("weapon_1_selects", player.get_weapon_slot() == 0, str(player.get_weapon_slot()))
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)

	# weapon_swap with the knife in the hand: it goes away and the next weapon of the cycle comes out.
	_check("equip_for_swap", player.set_knife_equipped(true))
	await _tap(&"weapon_swap")
	_check("swap_unequips", not player.is_knife_equipped())
	_check("swap_selects_next", player.get_weapon_slot() == 1, str(player.get_weapon_slot()))
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)

	# Asking for the weapon already in the hand is how a tap on its card puts the knife away.
	_check("equip_for_same_slot", player.set_knife_equipped(true))
	player.bot_select_weapon(1)
	await _frames(2)
	_check("same_slot_unequips", not player.is_knife_equipped())
	_check("same_slot_keeps_weapon", player.get_weapon_slot() == 1, str(player.get_weapon_slot()))
	await _free_world(world)


# --- fire is the swing (one per click) ----------------------------------------------------------------------------

func _test_fire_swings() -> void:
	# Touch mode: the fire action is allowed without a captured mouse, so a real press can be tested headless.
	InputSetup.set_touch_override("on")
	var interval: float = _stat("swing_interval_s")
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("zone_ready", zone != null)
	var mag_before: int = player.get_ammo_in_mag()
	var seq_before: int = int(player.get("_net_shot_seq"))
	var state_before: PackedByteArray = _state_bytes(player)
	_check("equip_for_fire", player.set_knife_equipped(true))
	await _frames(2)
	_clear()

	# One click = one swing, with the damage of the level.
	await _tap(FIRE_ID)
	_check("fire_swings_once", _hits.size() == 1, "%d acertos" % _hits.size())
	if _hits.size() == 1:
		_check("fire_hit_is_knife", _hits[0].weapon_id == Ids.KNIFE, str(_hits[0].weapon_id))
		_check("fire_hit_damage", is_equal_approx(_hits[0].damage, player.get_knife_damage()), "%.1f" % _hits[0].damage)
	_check("fire_one_shot_fired", _shots.size() == 1 and _shots[0]["weapon_id"] == Ids.KNIFE, str(_shots.size()))
	_check("fire_shot_after_hit", _events == ["hit", "shot"], str(_events))
	_check("fire_spends_no_ammo", player.get_ammo_in_mag() == mag_before, "%d -> %d" % [mag_before, player.get_ammo_in_mag()])

	# A second click inside the cadence does nothing, and nothing is buffered for later either.
	await _tap(FIRE_ID)
	_check("second_click_inside_cadence", _hits.size() == 1, "%d acertos" % _hits.size())
	await _frames(_ticks(interval) + 4)
	_check("no_buffered_swing_after_cadence", _hits.size() == 1, "%d acertos" % _hits.size())

	# A click after the cadence swings again.
	await _tap(FIRE_ID)
	_check("click_after_cadence_swings", _hits.size() == 2, "%d acertos" % _hits.size())
	await _frames(_ticks(interval) + 4)

	# Holding fire for well over one cadence still swings only once.
	_clear()
	Input.action_press(FIRE_ID)
	await _frames(_ticks(interval * 2.0 + 0.2))
	Input.action_release(FIRE_ID)
	await _frames(2)
	_check("holding_fire_does_not_repeat", _hits.size() == 1, "%d acertos com o botao preso %.1f s" % [_hits.size(), interval * 2.0])

	# The net state is untouched by the swings.
	var state_after: PackedByteArray = _state_bytes(player)
	_check("fire_swing_keeps_net_seq", int(player.get("_net_shot_seq")) == seq_before,
		"%d -> %d" % [seq_before, int(player.get("_net_shot_seq"))])
	if state_before.size() == state_after.size() and state_before.size() >= 14:
		_check("fire_swing_keeps_weapon_byte", state_before[11] == state_after[11],
			"%d -> %d" % [state_before[11], state_after[11]])
		_check("fire_swing_keeps_seq_byte", state_before[13] == state_after[13],
			"%d -> %d" % [state_before[13], state_after[13]])

	# With the knife away, fire is the gun again.
	_check("unequip_for_gun", player.set_knife_equipped(false))
	await _frames(_ticks(interval) + 4)
	_clear()
	await _tap(FIRE_ID)
	_check("fire_shoots_the_gun_again", player.get_ammo_in_mag() == mag_before - 1,
		"%d -> %d" % [mag_before, player.get_ammo_in_mag()])
	_check("gun_shot_is_not_knife", _shots.size() == 1 and _shots[0]["weapon_id"] != Ids.KNIFE, str(_shots))
	_check("gun_shot_moves_net_seq", int(player.get("_net_shot_seq")) != seq_before)
	InputSetup.set_touch_override("auto")
	await _free_world(world)


# --- What the knife in the hand blocks ----------------------------------------------------------------------------

func _test_equipped_blocks() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)
	player.bot_set_enabled(true)
	player.bot_set_aim(true)
	await _frames(4)
	_check("aiming_with_the_weapon", player.is_aiming())
	_check("equip_while_aiming", player.set_knife_equipped(true))
	await _frames(4)
	_check("aim_drops_on_equip", not player.is_aiming())
	_check("ads_drops_on_equip", player.get_ads_t() < 0.01, "%.2f" % player.get_ads_t())

	player.bot_reload()
	await _frames(2)
	_check("no_reload_with_the_knife", not player.is_reloading())

	_check("binoculars_refused_with_the_knife", not player.bot_use_item(Ids.I_BINOCULARS))
	_check("binoculars_still_down", not player.is_binocular_view())
	player.debug_set_health(player.get_max_health() * 0.5)
	_check("medkit_still_allowed", player.bot_use_item(Ids.I_MEDKIT))
	items.cancel_use()
	await _frames(2)

	# The binoculars up: the knife cannot come out (the symmetric rule).
	_check("unequip_for_binoculars", player.set_knife_equipped(false))
	items.set_binoculars(true)
	await _frames(2)
	_check("binoculars_on", player.is_binocular_view())
	_check("equip_refused_with_binoculars", not player.set_knife_equipped(true) and not player.is_knife_equipped())
	items.set_binoculars(false)
	await _frames(2)

	# Aim comes back as the button still asks for it once the knife is away.
	_check("equip_again", player.set_knife_equipped(true))
	await _frames(4)
	_check("still_not_aiming", not player.is_aiming())
	_check("unequip_restores_aim_request", player.set_knife_equipped(false))
	await _frames(_ticks(0.4))
	_check("aim_back_after_unequip", player.is_aiming())
	player.bot_set_aim(false)
	player.bot_set_enabled(false)
	await _free_world(world)


# --- Reach and aim assist -----------------------------------------------------------------------------------------

func _test_reach_and_assist() -> void:
	var reach: float = _stat("reach_m")
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = _make_zone(world)
	var eye: Vector3 = player.get_eye_position()
	var far: Vector3 = _place_zone(zone, eye, FAR_M, 0.0)
	player.bot_look_at(far)
	await _frames(3)
	_clear()
	_check("far_swing_happens", player.bot_knife())
	_check("far_no_hit", _hits.is_empty(), "%d acertos a %.1f m" % [_hits.size(), FAR_M])
	_check("far_still_emits_shot", _shots.size() == 1, str(_shots.size()))
	await _frames(_ticks(_stat("swing_interval_s") + 0.1))

	# 0.3 m beside the look line at 2.0 m: the ray misses the box, the assist sphere does not.
	var side: Vector3 = _place_zone(zone, eye, ASSIST_FORWARD_M, ASSIST_SIDE_M)
	player.bot_look_at(eye + Vector3(0.0, -ZONE_DROP_M, -ASSIST_FORWARD_M))
	await _frames(3)
	_clear()
	_check("assist_swing_happens", player.bot_knife())
	_check("assist_hit", _hits.size() == 1, "%d acertos" % _hits.size())
	if _hits.size() == 1:
		var hit: HitInfo = _hits[0]
		_check("assist_position_is_zone_center", hit.position.distance_to(side) < 0.001, str(hit.position))
		_check("assist_distance", is_equal_approx(hit.distance_m, minf(eye.distance_to(side), reach)), "%.3f m" % hit.distance_m)
		_check("assist_damage", is_equal_approx(hit.damage, player.get_knife_damage()), "%.1f" % hit.damage)
	await _free_world(world)


# --- Cadence ------------------------------------------------------------------------------------------------------

func _test_cadence() -> void:
	var interval: float = _stat("swing_interval_s")
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("cadence_zone", zone != null)
	_clear()
	_check("first_swing", player.bot_knife())
	_check("second_swing_same_frame", not player.bot_knife())
	_check("cooldown_frac_full", player.get_knife_cooldown_frac() > 0.99, "%.2f" % player.get_knife_cooldown_frac())
	await _frames(_ticks(interval) - 1)
	_check("still_on_cooldown_before_interval", not player.bot_knife(), "%.3f s" % (float(_ticks(interval) - 1) / 60.0))
	_check("cooldown_frac_small", player.get_knife_cooldown_frac() < 0.1, "%.3f" % player.get_knife_cooldown_frac())
	await _frames(3)
	_check("ready_after_interval", player.get_knife_cooldown_frac() == 0.0 and player.bot_knife())
	_check("two_hits_so_far", _hits.size() == 2, "%d acertos" % _hits.size())
	_check("knife_still_in_hand", player.is_knife_equipped())
	await _free_world(world)


# --- The 0.45 s lock ----------------------------------------------------------------------------------------------

func _test_swing_locks() -> void:
	var swing_s: float = _stat("swing_s")
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("lock_zone", zone != null)
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)
	_clear()
	_check("lock_swing", player.bot_knife())
	await _frames(2)
	_check("is_swinging", player.is_knife_swinging())
	_check("no_fire_while_swinging", not player.bot_fire())
	_check("knife_view_shown_while_swinging", _knife_view_visible(player) or _knife_of(player).get_view() == null)
	_check("weapon_view_hidden_while_swinging", not _weapon_view_visible(player))
	player.bot_reload()
	_check("no_reload_while_swinging", not player.is_reloading())
	player.bot_select_weapon(1)
	_check("no_switch_while_swinging", player.get_weapon_slot() == 0, str(player.get_weapon_slot()))
	_check("no_item_while_swinging", not player.bot_use_item(Ids.I_MEDKIT))
	_check("no_unequip_while_swinging", not player.set_knife_equipped(false) and player.is_knife_equipped())
	_check("no_toggle_while_swinging", player.toggle_knife() and player.is_knife_equipped())
	_check("one_hit_in_the_lock", _hits.size() == 1, "%d acertos" % _hits.size())
	await _frames(_ticks(swing_s) + 3)
	_check("swing_over", not player.is_knife_swinging())
	_check("knife_still_in_hand_after_swing", player.is_knife_equipped())
	_check("weapon_view_still_hidden_after_swing", not _weapon_view_visible(player))
	_check("unequip_after_swing", player.set_knife_equipped(false))
	await _frames(2)
	_check("weapon_view_visible_after_unequip", _weapon_view_visible(player))
	await _free_world(world)


# --- The knife view: rest pose for the pre-warm, then only in the hand (section 1.7, risk R3) ---------------------

func _test_view_pose() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var player_knife: Knife = _knife_of(player)
	_check("player_has_knife_node", player_knife != null)
	if player_knife != null and player_knife.get_view() != null:
		_check("player_view_hidden_after_hunt_started", not player_knife.get_view().visible)
	# A knife of its own, to see the pose before hunt_started (the world already emitted it for the real one).
	var knife: Knife = Knife.new()
	add_child(knife)
	_check("extra_knife_setup", knife.setup(1, player.get_weapon_holder()))
	var view: WeaponViewBase = knife.get_view()
	if view == null:
		_check("knife_view_asset", false, "sem assets/models/weapons/knife_view.tscn: o golpe acontece sem visual")
	else:
		_check("view_rest_visible_before_hunt", view.visible)
		_check("view_has_muzzle_and_anchor", view.get_muzzle() != null and view.get_ads_anchor() != null)
		knife.set_rest_visible(false)
		_check("view_hidden_after_hunt_started", not view.visible)
		_check("view_shown_while_equipped", knife.set_equipped(true) and view.visible)
		_check("view_hidden_when_put_away", knife.set_equipped(false) and not view.visible)
		_check("swing_shows_view", knife.swing(player.get_camera(), [player.get_rid()], null) and view.visible)
		knife.tick(_stat("swing_s") + 0.01)
		_check("view_hidden_after_swing_on_the_belt", not view.visible and not knife.is_swinging())
	knife.queue_free()
	await _free_world(world)


# --- The swing cancels the reload ---------------------------------------------------------------------------------

func _test_reload_cancelled() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("reload_zone", zone != null)
	_check("fire_once_for_room", player.bot_fire())
	await _frames(2)
	player.bot_reload()
	await _frames(2)
	_check("reloading_before_swing", player.is_reloading())
	_clear()
	_check("swing_during_reload", player.bot_knife())
	_check("reload_cancelled_by_swing", not player.is_reloading())
	_check("swing_hit_during_reload", _hits.size() == 1, "%d acertos" % _hits.size())
	await _free_world(world)


# --- The swing leaves the net state alone -------------------------------------------------------------------------

func _state_bytes(player: Player) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	player.net_write_state(buffer)
	return buffer.data_array


func _test_net_untouched() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("net_zone", zone != null)
	_gun_shot_id = 0
	player.get_weapon().fired.connect(_on_gun_fired)
	_check("gun_fires", player.bot_fire())
	await _frames(4)
	_check("gun_shot_id_set", _gun_shot_id != 0, str(_gun_shot_id))
	var before: PackedByteArray = _state_bytes(player)
	var seq_before: int = int(player.get("_net_shot_seq"))
	_clear()
	_check("net_swing", player.bot_knife())
	await _frames(2)
	var after: PackedByteArray = _state_bytes(player)
	_check("net_shot_seq_unchanged", int(player.get("_net_shot_seq")) == seq_before,
		"%d -> %d" % [seq_before, int(player.get("_net_shot_seq"))])
	_check("net_state_size", before.size() == NetCodec.HUNTER_STATE_BYTES and after.size() == before.size(), str(before.size()))
	if before.size() == after.size() and before.size() >= 14:
		_check("net_weapon_byte_unchanged", before[11] == after[11], "%d -> %d" % [before[11], after[11]])
		_check("net_seq_byte_unchanged", before[13] == after[13], "%d -> %d" % [before[13], after[13]])
	_check("knife_hit_logged", _hits.size() == 1, "%d acertos" % _hits.size())
	if _hits.size() == 1:
		_check("shot_id_differs_from_gun", _hits[0].shot_id != _gun_shot_id, "%d vs %d" % [_hits[0].shot_id, _gun_shot_id])
		_check("shot_id_same_slot", NetCodec.shot_slot(_hits[0].shot_id) == NetCodec.shot_slot(_gun_shot_id))
	await _free_world(world)


func _on_gun_fired(shot_id: int) -> void:
	_gun_shot_id = shot_id


# --- Blocks (section 1.4) -----------------------------------------------------------------------------------------

func _test_blocks() -> void:
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("blocks_zone", zone != null)
	_clear()
	player.debug_set_health(player.get_max_health() * 0.5)   # the kit refuses at full health
	_check("medkit_starts", player.bot_use_item(Ids.I_MEDKIT))
	await _frames(2)
	_check("items_busy", items.is_busy())
	_check("blocked_by_item_in_use", not player.bot_knife())
	items.cancel_use()
	await _frames(2)

	items.set_binoculars(true)
	await _frames(2)
	_check("binoculars_on", player.is_binocular_view())
	_check("blocked_by_binoculars", not player.bot_knife())
	items.set_binoculars(false)
	await _frames(2)

	player.bot_select_weapon(1)
	await _frames(2)
	_check("switching_weapon", player.get_weapon_slot() == 1)
	_check("blocked_by_weapon_switch", not player.bot_knife())
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)
	_check("no_hit_while_blocked", _hits.is_empty(), "%d acertos" % _hits.size())
	_check("swings_again_after_switch", player.bot_knife())

	# Dead: no swing and no knife in the hand at all.
	await _frames(_ticks(_stat("swing_interval_s") + 0.1))
	player.apply_damage(KILL_DAMAGE, player.global_position + Vector3.FORWARD)
	await _frames(3)
	_check("died", not player.is_alive())
	_check("death_unequips", not player.is_knife_equipped())
	_check("blocked_by_death", not player.bot_knife())
	_check("equip_refused_when_dead", not player.set_knife_equipped(true))
	await _free_world(world)


# --- No knife at all (the data has no knife): fire is the gun and there is no touch button ------------------------

func _test_without_knife() -> void:
	InputSetup.set_touch_override("on")
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var touch: TouchControls = player.find_child("TouchControls", true, false) as TouchControls
	await _frames(3)
	# The data does have a knife here, so the no-knife path is reproduced by dropping the Knife node, which is exactly
	# what Player.setup leaves behind when Data has no knife entry.
	var knife: Knife = _knife_of(player)
	player.set("_knife", null)
	if knife != null:
		knife.queue_free()
	if touch != null:
		touch.call("_rebuild_buttons")
	await _frames(2)
	_check("no_knife_level", player.get_knife_level() == 0, str(player.get_knife_level()))
	_check("no_knife_not_equipped", not player.is_knife_equipped())
	_check("no_knife_toggle_refused", not player.toggle_knife() and not player.is_knife_equipped())
	_check("no_knife_set_equipped_refused", not player.set_knife_equipped(true))
	_check("no_knife_unequip_is_a_no_op", player.set_knife_equipped(false))
	_check("no_knife_bot_swing_refused", not player.bot_knife())
	_check("no_knife_cooldown_zero", player.get_knife_cooldown_frac() == 0.0)
	_check("no_knife_no_swinging", not player.is_knife_swinging())
	if touch != null:
		_check("no_knife_no_touch_button", touch.get_button_center(KNIFE_ID) == Vector2.INF,
			str(touch.get_button_center(KNIFE_ID)))
	var mag_before: int = player.get_ammo_in_mag()
	_clear()
	await _tap(FIRE_ID)
	_check("no_knife_fire_is_the_gun", player.get_ammo_in_mag() == mag_before - 1,
		"%d -> %d" % [mag_before, player.get_ammo_in_mag()])
	_check("no_knife_weapon_view_visible", _weapon_view_visible(player))
	InputSetup.set_touch_override("auto")
	await _free_world(world)


# --- Down and revive ----------------------------------------------------------------------------------------------

func _test_downed() -> void:
	InputSetup.set_touch_override("on")
	var world: KnifeWorld = await _make_world(4, 2, 1)
	var player: Player = world.player
	var touch: TouchControls = player.find_child("TouchControls", true, false) as TouchControls
	await _frames(3)
	_check("downed_world_touch_button", touch != null and touch.get_button_center(KNIFE_ID) != Vector2.INF)
	_check("equip_before_falling", player.set_knife_equipped(true))
	await _frames(2)
	player.apply_damage(KILL_DAMAGE, player.global_position + Vector3.FORWARD)
	await _frames(4)
	_check("downed", player.is_downed())
	_check("fall_unequips", not player.is_knife_equipped())
	_check("blocked_while_downed", not player.bot_knife())
	_check("no_swing_state_while_downed", not player.is_knife_swinging())
	if touch != null:
		_check("touch_button_gone_while_downed", touch.get_button_center(KNIFE_ID) == Vector2.INF,
			str(touch.get_button_center(KNIFE_ID)))
	world.request_revive(0)
	player.revive(50.0)
	await _frames(4)
	_check("revived", player.is_alive() and not player.is_downed())
	_check("revived_with_the_weapon", not player.is_knife_equipped())
	await _frames(_ticks(Player.DRAW_TIME_S) + 3)
	_check("revived_weapon_view_visible", _weapon_view_visible(player))
	if touch != null:
		_check("touch_button_back_after_revive", touch.get_button_center(KNIFE_ID) != Vector2.INF)
	InputSetup.set_touch_override("auto")
	await _free_world(world)


# --- Spectator (death with an ally still standing) ----------------------------------------------------------------

func _test_spectator() -> void:
	var world: KnifeWorld = await _make_world(1, 0, 1)
	var player: Player = world.player
	await _frames(3)
	_check("spectator_equip", player.set_knife_equipped(true))
	player.apply_damage(KILL_DAMAGE, player.global_position + Vector3.FORWARD)
	await _frames(4)
	_check("spectator_death_unequips", not player.is_knife_equipped())
	await _frames(_ticks(SPECTATE_WAIT_S))
	_check("spectating", player.is_spectating())
	_check("spectator_equip_refused", not player.set_knife_equipped(true) and not player.is_knife_equipped())
	_check("spectator_swing_refused", not player.bot_knife())
	await _free_world(world)


# --- The weapon panel shows "Faca" with no ammunition -------------------------------------------------------------

func _test_panel() -> void:
	# The panel on its own (no Hud), on keyboard and on touch.
	var panel: WeaponPanel = WeaponPanel.new()
	add_child(panel)
	panel.set_weapons([Ids.W_CARBINE_22, Ids.W_SHOTGUN_12] as Array[StringName])
	panel.set_active(0)
	panel.set_ammo(5, 30, false, 10)
	var weapon_name: String = panel.get_name_text()
	_check("panel_weapon_name", weapon_name != "" and weapon_name != PANEL_KNIFE_NAME, weapon_name)
	_check("panel_weapon_ammo", panel.get_mag_text() == "5" and panel.get_reserve_text() == "| 30",
		"%s %s" % [panel.get_mag_text(), panel.get_reserve_text()])
	panel.set_knife(true)
	_check("panel_knife_name", panel.get_name_text() == PANEL_KNIFE_NAME, panel.get_name_text())
	_check("panel_knife_no_ammo", panel.get_mag_text() == "" and panel.get_reserve_text() == "",
		"'%s' '%s'" % [panel.get_mag_text(), panel.get_reserve_text()])
	_check("panel_knife_shown", panel.is_knife_shown())
	panel.set_ammo(5, 30, false, 10)
	_check("panel_knife_ignores_ammo", panel.get_mag_text() == "", panel.get_mag_text())
	panel.set_knife(false)
	panel.set_ammo(5, 30, false, 10)
	_check("panel_back_to_weapon_name", panel.get_name_text() == weapon_name, panel.get_name_text())
	_check("panel_back_to_weapon_ammo", panel.get_mag_text() == "5" and panel.get_reserve_text() == "| 30",
		"%s %s" % [panel.get_mag_text(), panel.get_reserve_text()])

	# Touch: the card of the weapon in hand becomes the knife card.
	panel.set_touch(true)
	panel.set_weapon_ammo(0, 5, 30, false, 10)
	panel.set_weapon_ammo(1, 2, 8, false, 5)
	await get_tree().process_frame
	var card_name: String = panel.get_card_name_text(0)
	_check("card_weapon_name", card_name != "" and card_name != PANEL_KNIFE_NAME, card_name)
	_check("card_weapon_ammo", panel.get_card_mag_text(0) == "5", panel.get_card_mag_text(0))
	panel.set_knife(true)
	_check("card_knife_name", panel.get_card_name_text(0) == PANEL_KNIFE_NAME, panel.get_card_name_text(0))
	_check("card_knife_no_ammo", panel.get_card_mag_text(0) == "", "'%s'" % panel.get_card_mag_text(0))
	_check("other_card_keeps_its_weapon", panel.get_card_name_text(1) != PANEL_KNIFE_NAME
		and panel.get_card_mag_text(1) == "2", "%s %s" % [panel.get_card_name_text(1), panel.get_card_mag_text(1)])
	panel.set_weapon_ammo(0, 5, 30, false, 10)
	_check("card_knife_stays_empty", panel.get_card_mag_text(0) == "", "'%s'" % panel.get_card_mag_text(0))
	panel.set_knife(false)
	_check("card_back_to_weapon", panel.get_card_name_text(0) == card_name and panel.get_card_mag_text(0) == "5",
		"%s %s" % [panel.get_card_name_text(0), panel.get_card_mag_text(0)])
	panel.queue_free()

	# The real Hud follows the player, in both modes.
	for touch_mode: String in ["off", "on"]:
		InputSetup.set_touch_override(touch_mode)
		var world: KnifeWorld = await _make_world()
		var player: Player = world.player
		var hud_panel: WeaponPanel = player.find_child("WeaponPanel", true, false) as WeaponPanel
		_check("hud_panel_found_%s" % touch_mode, hud_panel != null)
		if hud_panel != null:
			await _frames(3)
			_check("hud_panel_weapon_%s" % touch_mode, not hud_panel.is_knife_shown())
			_check("hud_equip_%s" % touch_mode, player.set_knife_equipped(true))
			await _frames(3)
			_check("hud_panel_knife_%s" % touch_mode, hud_panel.is_knife_shown())
			if touch_mode == "off":
				_check("hud_panel_knife_name", hud_panel.get_name_text() == PANEL_KNIFE_NAME, hud_panel.get_name_text())
				_check("hud_panel_knife_no_ammo", hud_panel.get_mag_text() == "", "'%s'" % hud_panel.get_mag_text())
			else:
				var active: int = hud_panel.get_active_index()
				_check("hud_card_knife_name", hud_panel.get_card_name_text(active) == PANEL_KNIFE_NAME,
					hud_panel.get_card_name_text(active))
				_check("hud_card_knife_no_ammo", hud_panel.get_card_mag_text(active) == "",
					"'%s'" % hud_panel.get_card_mag_text(active))
			_check("hud_unequip_%s" % touch_mode, player.set_knife_equipped(false))
			await _frames(3)
			_check("hud_panel_weapon_again_%s" % touch_mode, not hud_panel.is_knife_shown())
			if touch_mode == "off":
				_check("hud_panel_weapon_ammo_back", hud_panel.get_mag_text() != "", hud_panel.get_mag_text())
		await _free_world(world)
	InputSetup.set_touch_override("auto")


# --- Touch button -------------------------------------------------------------------------------------------------

func _center_of(def: Dictionary, screen: Vector2, block: Dictionary) -> Vector2:
	match String(def["from"]):
		"br":
			return Vector2(screen.x - float(def["ox"]), screen.y - float(def["oy"]))
		"bl":
			return Vector2(float(def["ox"]), screen.y - float(def["oy"]))
		"cura":
			return Vector2(float(block["cura_x"]), screen.y - TouchControls.BLOCK_BOTTOM_PX)
		"acc":
			return Vector2(float(block["acc_x"]), screen.y - TouchControls.BLOCK_BOTTOM_PX)
	return Vector2(float(def["ox"]), float(def["oy"]))


## One tap (press and release) at `pos` on the touch layer.
func _touch_tap(touch: TouchControls, pos: Vector2, index: int = 1) -> void:
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = index
	down.pressed = true
	down.position = pos
	touch._input(down)
	await _frames(2)
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = index
	up.pressed = false
	up.position = pos
	touch._input(up)
	await _frames(2)


func _test_touch() -> void:
	InputSetup.set_touch_override("on")
	var world: KnifeWorld = await _make_world()
	var player: Player = world.player
	var touch: TouchControls = player.find_child("TouchControls", true, false) as TouchControls
	_check("touch_found", touch != null)
	if touch == null:
		InputSetup.set_touch_override("auto")
		await _free_world(world)
		return
	await _frames(3)
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = touch.get_button_center(KNIFE_ID)
	_check("knife_button_center", center == Vector2(screen.x - 100.0, screen.y - 190.0),
		"%s em %s (esperado %s)" % [center, screen, Vector2(screen.x - 100.0, screen.y - 190.0)])
	_check("knife_button_radius", is_equal_approx(touch.get_button_radius(KNIFE_ID), 34.0), str(touch.get_button_radius(KNIFE_ID)))
	_check("knife_button_label", touch.get_button_label(KNIFE_ID) == "Faca", touch.get_button_label(KNIFE_ID))
	_check("knife_in_probe", touch.get_probe_buttons().has(String(KNIFE_ID)))
	_check("knife_not_in_quickbar", not InputSetup.ITEM_ACTIONS.has(KNIFE_ID) and InputSetup.get_item_action(KNIFE_ID) == &"")

	# A tap on Faca puts the knife in the hand (no swing), and the button shows it.
	var zone: HitZone = await _zone_in_reach(world, player)
	_check("touch_zone", zone != null)
	_clear()
	_check("button_not_lit_before", not touch.is_button_on(KNIFE_ID))
	await _touch_tap(touch, center)
	_check("touch_tap_equips", player.is_knife_equipped())
	_check("touch_tap_has_no_hit", _hits.is_empty(), "%d acertos" % _hits.size())
	_check("button_lit_while_equipped", touch.is_button_on(KNIFE_ID))

	# The Tiro button swings.
	var fire_center: Vector2 = touch.get_button_center(&"fire")
	await _touch_tap(touch, fire_center, 2)
	_check("touch_fire_swings", _hits.size() == 1, "%d acertos" % _hits.size())
	_check("touch_cooldown_veil", player.get_knife_cooldown_frac() > 0.0, "%.2f" % player.get_knife_cooldown_frac())
	_check("touch_still_equipped_after_swing", player.is_knife_equipped())

	# The Mira button does nothing with the knife in the hand.
	var aim_center: Vector2 = touch.get_button_center(&"aim")
	await _touch_tap(touch, aim_center, 3)
	await _frames(4)
	_check("touch_aim_does_nothing", not player.is_aiming() and not touch.is_button_on(&"aim"))

	# A tap on a weapon card puts the knife away and takes that weapon.
	await _frames(_ticks(_stat("swing_interval_s") + 0.1))
	var rects: Array[Rect2] = touch.get_weapon_card_rects()
	_check("touch_has_cards", rects.size() >= 2, str(rects.size()))
	if rects.size() >= 2:
		var slot_before: int = player.get_weapon_slot()
		await _touch_tap(touch, rects[1].get_center(), 4)
		await _frames(2)
		_check("card_tap_unequips", not player.is_knife_equipped())
		_check("card_tap_selects", player.get_weapon_slot() != slot_before, str(player.get_weapon_slot()))
		await _frames(_ticks(Player.DRAW_TIME_S) + 3)
		# And a tap on the card of the weapon in hand only puts the knife away (that weapon stays).
		_check("equip_for_active_card", player.set_knife_equipped(true))
		await _frames(3)
		var active_slot: int = player.get_weapon_slot()
		var cards: Array[Rect2] = touch.get_weapon_card_rects()
		var active_index: int = _weapon_panel_card_index(player, active_slot)
		if active_index >= 0 and active_index < cards.size():
			await _touch_tap(touch, cards[active_index].get_center(), 5)
			_check("active_card_tap_unequips", not player.is_knife_equipped())
			_check("active_card_tap_keeps_the_weapon", player.get_weapon_slot() == active_slot,
				"%d -> %d" % [active_slot, player.get_weapon_slot()])
		else:
			_check("active_card_found", false, "cartao da arma na mao nao encontrado (%d cartoes)" % cards.size())

	# Worst case layout (dog and interact present) against every other button, card and the stick, on 3 screens.
	touch.set_dog_present(true)
	touch.set("_revive_on", true)
	touch.call("_rebuild_buttons")
	await _frames(2)
	var defs: Array[Dictionary] = touch.get("_defs")
	_check("worst_case_has_knife", _has_def(defs, KNIFE_ID))
	for s: int in SCREENS.size():
		var screen_px: Vector2 = SCREENS[s]
		var block: Dictionary = TouchControls.compute_bottom_block(screen_px, STICK_CENTER_FROM_LEFT_PX + STICK_RADIUS_PX)
		var centers: Dictionary = {}
		var reach: Dictionary = {}
		for def: Dictionary in defs:
			centers[def["id"]] = _center_of(def, screen_px, block)
			reach[def["id"]] = float(def["d"]) * 0.5 + TouchControls.HIT_PADDING_PX
		var knife_center: Vector2 = centers[KNIFE_ID]
		var knife_reach: float = float(reach[KNIFE_ID])
		_check("knife_center_%dx%d" % [int(screen_px.x), int(screen_px.y)], knife_center == KNIFE_CENTERS[s],
			"%s (contrato %s)" % [knife_center, KNIFE_CENTERS[s]])
		var worst: float = INF
		var worst_id: StringName = &""
		for other: StringName in centers:
			if other == KNIFE_ID:
				continue
			var gap: float = knife_center.distance_to(centers[other] as Vector2) - knife_reach - float(reach[other])
			if gap < worst:
				worst = gap
				worst_id = other
		_check("knife_gap_%dx%d" % [int(screen_px.x), int(screen_px.y)], worst >= -0.01,
			"menor folga %.1f px (para %s), centro %s" % [worst, worst_id, knife_center])
		var box: Rect2 = Rect2(knife_center - Vector2.ONE * knife_reach, Vector2.ONE * knife_reach * 2.0)
		_check("knife_on_screen_%dx%d" % [int(screen_px.x), int(screen_px.y)],
			Rect2(Vector2.ZERO, screen_px).encloses(box), str(box))
		var card_w: float = float(block["card_w"])
		for i: int in 2:
			var card: Rect2 = Rect2(Vector2(float(block["center_x"]) - card_w - TouchControls.CARD_GAP_PX * 0.5
				+ float(i) * (card_w + TouchControls.CARD_GAP_PX), screen_px.y - CARD_BOTTOM_PX - CARD_H_PX),
				Vector2(card_w, CARD_H_PX))
			_check("knife_vs_card_%d_%dx%d" % [i + 1, int(screen_px.x), int(screen_px.y)], not box.intersects(card), str(card))
		var stick: Vector2 = Vector2(STICK_CENTER_FROM_LEFT_PX, screen_px.y - STICK_CENTER_FROM_BOTTOM_PX)
		_check("knife_vs_stick_%dx%d" % [int(screen_px.x), int(screen_px.y)],
			knife_center.distance_to(stick) - knife_reach >= STICK_RADIUS_PX,
			"%.1f px" % (knife_center.distance_to(stick) - knife_reach))
	InputSetup.set_touch_override("auto")
	await _free_world(world)


## Index of the card (left to right) that shows weapon `slot`, or -1.
func _weapon_panel_card_index(player: Player, slot: int) -> int:
	var panel: WeaponPanel = player.find_child("WeaponPanel", true, false) as WeaponPanel
	if panel == null:
		return -1
	return panel.get_card_weapon_indices().find(slot)


func _has_def(defs: Array[Dictionary], button_id: StringName) -> bool:
	for def: Dictionary in defs:
		if def["id"] == button_id:
			return true
	return false


# --- Legend and input ---------------------------------------------------------------------------------------------

func _test_legend_and_input() -> void:
	_check("action_registered", InputMap.has_action(KNIFE_ID))
	_check("action_is_last", InputSetup.ACTIONS[InputSetup.ACTIONS.size() - 1] == "knife",
		InputSetup.ACTIONS[InputSetup.ACTIONS.size() - 1])
	_check("key_label_x", InputSetup.get_key_label(KNIFE_ID) == "X", InputSetup.get_key_label(KNIFE_ID))
	var world: KnifeWorld = await _make_world()
	var legend: ControlsLegend = world.player.find_child("ControlsLegend", true, false) as ControlsLegend
	_check("legend_found", legend != null)
	if legend != null:
		var rows: Array[StringName] = legend.get_row_ids()
		var knife_row: int = rows.find(KNIFE_ID)
		_check("legend_has_knife", knife_row >= 0, str(rows))
		_check("legend_knife_after_weapons", knife_row == rows.find(ControlsLegend.ROW_WEAPONS) + 1, str(rows))
		_check("legend_knife_key", legend.get_key_text(KNIFE_ID) == "X", legend.get_key_text(KNIFE_ID))
		_check("legend_knife_text", legend.get_row_text(KNIFE_ID) == "Faca", legend.get_row_text(KNIFE_ID))
	await _free_world(world)
