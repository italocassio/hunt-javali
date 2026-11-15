extends Node
## Package A sandbox for the horde loadout (docs/horda.md section 7): every weapon of data/weapons.json in file
## order, weapon_3..5 and weapon_swap, infinite reserve; and the contract loadout untouched.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/player_horde_test.tscn
## Not part of the game.

const WATCHDOG_S: float = 60.0
const RELOAD_CYCLES: int = 3
const CONTRACT_WEAPON_COUNT: int = 2
const DRAW_WAIT_S: float = 0.6   # longer than the weapon draw lockout

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await _test_horde()
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


func _make_world(horde: bool) -> SandboxWorld:
	var world: SandboxWorld = SandboxWorld.new()
	world.horde_mode = horde
	world.horde_auto = false
	add_child(world)
	await get_tree().process_frame
	return world


## Presses an action for one frame (Player reads it in _process).
func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _slot_ids(player: Player) -> Array[StringName]:
	var ids: Array[StringName] = []
	for slot: int in player.get_weapon_count():
		player.bot_select_weapon(slot)
		ids.append(player.get_current_weapon_id())
	player.bot_select_weapon(0)
	return ids


func _test_horde() -> void:
	var world: SandboxWorld = await _make_world(true)
	var player: Player = world.player
	var expected: Array[StringName] = Data.get_weapon_ids()
	_check("horde_request_mode", player.get_request().is_horde() and world.is_horde())
	_check("horde_weapon_count", player.get_weapon_count() == expected.size(),
		"%d of %d" % [player.get_weapon_count(), expected.size()])
	_check("horde_weapon_order", _slot_ids(player) == expected, str(_slot_ids(player)))
	_check("horde_starts_on_slot_0", player.get_weapon_slot() == 0 and player.get_current_weapon_id() == expected[0])
	_check("horde_infinite_reserve", player.has_infinite_reserve())
	_check("horde_reserve_positive", player.get_ammo_reserve() > 0, str(player.get_ammo_reserve()))

	# weapon_swap cycles through every weapon and wraps to slot 0.
	var visited: Array[int] = []
	for i: int in expected.size():
		await _tap(&"weapon_swap")
		visited.append(player.get_weapon_slot())
	var cycle_ok: bool = visited.size() == expected.size() and visited[visited.size() - 1] == 0
	for i: int in visited.size() - 1:
		cycle_ok = cycle_ok and visited[i] == i + 1
	_check("horde_swap_cycle", cycle_ok, str(visited))

	# Number keys 3..5 pick slots 2..4.
	await _tap(&"weapon_3")
	_check("horde_weapon_3", player.get_current_weapon_id() == Ids.W_RIFLE_308, str(player.get_current_weapon_id()))
	await _tap(&"weapon_4")
	_check("horde_weapon_4", player.get_weapon_slot() == 3 and player.get_current_weapon_id() == expected[3],
		str(player.get_current_weapon_id()))
	await _tap(&"weapon_5")
	_check("horde_weapon_5", player.get_weapon_slot() == 4 and player.get_current_weapon_id() == expected[4],
		str(player.get_current_weapon_id()))
	await _tap(&"weapon_1")
	_check("horde_weapon_1", player.get_weapon_slot() == 0)

	# Empty the magazine and reload: the reserve never moves.
	player.bot_set_enabled(true)
	await get_tree().create_timer(DRAW_WAIT_S).timeout
	var weapon: Weapon = player.get_weapon()
	var reserve_before: int = player.get_ammo_reserve()
	var constant: bool = true
	var refilled: bool = true
	for cycle: int in RELOAD_CYCLES:
		weapon.ammo_in_mag = 1
		var shot: bool = player.bot_fire()
		constant = constant and shot and weapon.ammo_in_mag == 0
		await get_tree().create_timer(0.5).timeout
		if not weapon.is_reloading():
			player.bot_reload()
		await weapon.reload_finished
		refilled = refilled and weapon.ammo_in_mag == int(weapon.def["mag_size"])
		constant = constant and player.get_ammo_reserve() == reserve_before
	_check("horde_reserve_constant_after_reloads", constant and player.get_ammo_reserve() == reserve_before,
		"before=%d after=%d" % [reserve_before, player.get_ammo_reserve()])
	_check("horde_reload_refills_magazine", refilled)
	_free_world(world)
	await get_tree().process_frame
	await get_tree().process_frame


func _test_contract() -> void:
	var world: SandboxWorld = await _make_world(false)
	var player: Player = world.player
	_check("contract_not_horde", not player.get_request().is_horde() and not world.is_horde())
	_check("contract_weapon_count", player.get_weapon_count() == CONTRACT_WEAPON_COUNT, str(player.get_weapon_count()))
	_check("contract_no_infinite_reserve", not player.has_infinite_reserve())
	var weapon: Weapon = player.get_weapon()
	var reserve_before: int = player.get_ammo_reserve()
	var mag: int = int(weapon.def["mag_size"])
	_check("contract_initial_reserve", reserve_before == int(round(float(weapon.def["reserve_ammo"]) * player.get_items().reserve_mult)),
		str(reserve_before))

	# weapon_3..5 do nothing without those slots.
	for action: StringName in [&"weapon_3", &"weapon_4", &"weapon_5"]:
		await _tap(action)
	_check("contract_weapon_3_5_noop", player.get_weapon_slot() == 0 and player.get_current_weapon_id() == Ids.W_CARBINE_22)
	await _tap(&"weapon_2")
	_check("contract_weapon_2_still_works", player.get_weapon_slot() == 1)
	await _tap(&"weapon_1")

	# A reload spends the reserve as before.
	player.bot_set_enabled(true)
	await get_tree().create_timer(DRAW_WAIT_S).timeout
	weapon.ammo_in_mag = 0
	player.bot_reload()
	await weapon.reload_finished
	_check("contract_reload_spends_reserve", weapon.ammo_in_mag == mag and player.get_ammo_reserve() == reserve_before - mag,
		"reserve %d -> %d" % [reserve_before, player.get_ammo_reserve()])
	_free_world(world)
	await get_tree().process_frame


func _free_world(world: SandboxWorld) -> void:
	world.queue_free()
