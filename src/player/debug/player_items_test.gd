extends Node
## Package A2 test for the item hands (docs/plano_itens_animados.md 2.3): ItemHands shows the view of the item in use,
## the weapon leaves the screen meanwhile and comes back with a draw, the knife goes back to the belt, a cut gesture snaps
## the view back, and an item without art never hides the weapon. The art is not needed: a stub ItemViewBase that counts
## its calls stands in for the real views (ART1 delivers them in parallel). Runs on a SandboxWorld with a bot.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/player_items_test.tscn
## Not part of the game.

const WATCHDOG_S: float = 120.0
const SLACK_S: float = 0.4
const MEDKIT: StringName = Ids.I_MEDKIT
const DRINK: StringName = Ids.I_ENERGY_DRINK
const DRONE: StringName = Ids.I_SCOUT_DRONE
const BAIT: StringName = Ids.I_CORN_BAIT
const HURT_HEALTH: float = 40.0
const KILL_DAMAGE: float = 9999.0
const TIRED_STAMINA: float = 30.0

var _passed: int = 0
var _failed: int = 0


## Counts what ItemHands asks of a view and records the last play_use arguments.
class StubView extends ItemViewBase:
	var play_calls: int = 0
	var cancel_calls: int = 0
	var last_duration: float = -1.0
	var last_effect_at: float = -1.0

	func play_use(duration_s: float, effect_at: float) -> void:
		play_calls += 1
		last_duration = duration_s
		last_effect_at = effect_at

	func cancel_use() -> void:
		cancel_calls += 1


## Sandbox carrying the four consumables.
class ItemWorld extends SandboxWorld:
	func _request() -> HuntRequest:
		var r: HuntRequest = super()
		r.item_ids = [Ids.I_MEDKIT, Ids.I_ENERGY_DRINK, Ids.I_SCOUT_DRONE, Ids.I_CORN_BAIT]
		r.item_counts = {Ids.I_MEDKIT: 3, Ids.I_ENERGY_DRINK: 3, Ids.I_SCOUT_DRONE: 3, Ids.I_CORN_BAIT: 3}
		return r


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await _test_gesture_of_each_item()
	await _test_knife_goes_back_to_the_belt()
	await _test_cancel_before_the_beat()
	await _test_death_cancels()
	await _test_no_art_keeps_the_weapon()
	await _test_rest_visible()
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


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(roundi(seconds * float(Engine.physics_ticks_per_second)))


func _make_world() -> ItemWorld:
	var world: ItemWorld = ItemWorld.new()
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame
	return world


func _free_world(world: SandboxWorld) -> void:
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _hands(player: Player) -> ItemHands:
	return player.get("_hands") as ItemHands


## Replaces whatever view ItemHands has for `item_id` (real art or none) with a stub.
func _stub(player: Player, item_id: StringName) -> StubView:
	var hands: ItemHands = _hands(player)
	var views: Dictionary = hands.get("_views")
	var old: Node = views.get(item_id) as Node
	if old != null:
		old.queue_free()
	var stub: StubView = StubView.new()
	stub.visible = false
	player.get_weapon_holder().add_child(stub)
	views[item_id] = stub
	return stub


func _unstub(player: Player, item_id: StringName) -> void:
	var views: Dictionary = _hands(player).get("_views")
	var old: Node = views.get(item_id) as Node
	if old != null:
		old.queue_free()
	views.erase(item_id)


func _weapon_visible(player: Player) -> bool:
	var view: Node3D = player.get_weapon_holder().get_current_view()
	return view != null and view.visible


func _use_time(item_id: StringName) -> float:
	return float(Data.get_equipment(item_id).get("effect", {}).get("use_time_s", 0.0))


func _effect_at(item_id: StringName) -> float:
	return float(Data.get_equipment(item_id).get("effect", {}).get("effect_at", 1.0))


## Puts the hunter in a state where every consumable accepts a use (medkit and drink refuse a full bar).
func _prepare(player: Player) -> void:
	player.debug_set_health(HURT_HEALTH)
	player.debug_set_stamina(TIRED_STAMINA)


func _test_gesture_of_each_item() -> void:
	var world: ItemWorld = await _make_world()
	var player: Player = world.player
	var hands: ItemHands = _hands(player)
	_check("hands_exist", hands != null)
	await _frames(5)
	for item_id: StringName in [MEDKIT, DRINK, DRONE, BAIT]:
		var tag: String = String(item_id)
		var stub: StubView = _stub(player, item_id)
		_check("%s_get_view" % tag, hands.get_view(item_id) == stub)
		_prepare(player)
		await _frames(2)
		_check("%s_weapon_in_hand_before" % tag, _weapon_visible(player) and not hands.is_showing())
		var time_s: float = _use_time(item_id)
		if time_s <= 0.0:
			_check("%s_has_use_time_in_data" % tag, false, "use_time_s ausente nos dados")
			continue
		_check("%s_use_starts" % tag, player.bot_use_item(item_id))
		await _frames(3)
		_check("%s_showing" % tag, hands.is_showing() and stub.visible)
		_check("%s_play_use_once" % tag, stub.play_calls == 1, str(stub.play_calls))
		_check("%s_play_use_duration" % tag, absf(stub.last_duration - time_s) < 0.001, "%.2f" % stub.last_duration)
		_check("%s_play_use_effect_at" % tag, absf(stub.last_effect_at - _effect_at(item_id)) < 0.001, "%.2f" % stub.last_effect_at)
		_check("%s_weapon_hidden_meanwhile" % tag, not _weapon_visible(player))
		await _seconds(time_s + SLACK_S)
		_check("%s_done_not_showing" % tag, not hands.is_showing() and not stub.visible)
		_check("%s_weapon_back" % tag, _weapon_visible(player))
		_check("%s_no_cancel_on_a_normal_end" % tag, stub.cancel_calls == 0, str(stub.cancel_calls))
		_unstub(player, item_id)
	await _free_world(world)


func _test_knife_goes_back_to_the_belt() -> void:
	var world: ItemWorld = await _make_world()
	var player: Player = world.player
	var hands: ItemHands = _hands(player)
	var stub: StubView = _stub(player, MEDKIT)
	await _frames(5)
	player.debug_set_health(HURT_HEALTH)
	_check("knife_equipped", player.set_knife_equipped(true) and player.is_knife_equipped())
	_check("knife_use_starts", player.bot_use_item(MEDKIT))
	await _frames(3)
	_check("knife_back_on_the_belt", not player.is_knife_equipped())
	_check("knife_gesture_showing", hands.is_showing() and stub.visible)
	await _seconds(_use_time(MEDKIT) + SLACK_S)
	_check("knife_stays_on_the_belt_after", not player.is_knife_equipped())
	_check("knife_weapon_back", _weapon_visible(player) and not hands.is_showing())
	await _free_world(world)


func _test_cancel_before_the_beat() -> void:
	var world: ItemWorld = await _make_world()
	var player: Player = world.player
	var hands: ItemHands = _hands(player)
	var items: ItemBelt = player.get_items()
	var stub: StubView = _stub(player, MEDKIT)
	await _frames(5)
	player.debug_set_health(HURT_HEALTH)
	var count: int = items.get_count(MEDKIT)
	_check("cancel_use_starts", player.bot_use_item(MEDKIT))
	await _seconds(_use_time(MEDKIT) * 0.3)
	_check("cancel_showing_first", hands.is_showing())
	items.cancel_use()
	_check("cancel_view_snapped_back", stub.cancel_calls == 1 and not stub.visible and not hands.is_showing(),
		"cancel_calls=%d" % stub.cancel_calls)
	_check("cancel_nothing_spent", items.get_count(MEDKIT) == count and is_equal_approx(player.get_health(), HURT_HEALTH))
	await _frames(3)
	_check("cancel_weapon_back", _weapon_visible(player))
	# Cancelling through the hands alone (nothing showing) is a no-op.
	hands.cancel()
	_check("cancel_idle_no_op", stub.cancel_calls == 1)
	await _free_world(world)


func _test_death_cancels() -> void:
	var world: ItemWorld = await _make_world()
	var player: Player = world.player
	var hands: ItemHands = _hands(player)
	var stub: StubView = _stub(player, DRINK)
	await _frames(5)
	player.debug_set_stamina(TIRED_STAMINA)
	var count: int = player.get_items().get_count(DRINK)
	_check("death_use_starts", player.bot_use_item(DRINK))
	await _seconds(_use_time(DRINK) * 0.3)
	_check("death_showing_first", hands.is_showing())
	player.apply_damage(KILL_DAMAGE, Vector3.ZERO)
	await _frames(3)
	_check("death_not_alive", not player.is_alive())
	_check("death_view_cut", stub.cancel_calls == 1 and not stub.visible and not hands.is_showing(), "cancel_calls=%d" % stub.cancel_calls)
	_check("death_item_not_spent", player.get_items().get_count(DRINK) == count)
	_check("death_stamina_not_refilled", player.get_stamina_frac() < 1.0)
	await _free_world(world)


func _test_no_art_keeps_the_weapon() -> void:
	var world: ItemWorld = await _make_world()
	var player: Player = world.player
	var hands: ItemHands = _hands(player)
	_unstub(player, BAIT)
	await _frames(5)
	_check("noart_no_view", hands.get_view(BAIT) == null)
	_check("noart_unknown_id_no_view", hands.get_view(&"nothing") == null)
	_check("noart_use_starts", player.bot_use_item(BAIT))
	await _frames(3)
	_check("noart_busy", player.get_items().is_busy())
	_check("noart_not_showing", not hands.is_showing())
	_check("noart_weapon_stays", _weapon_visible(player))
	await _seconds(_use_time(BAIT) + SLACK_S)
	_check("noart_weapon_still_there", _weapon_visible(player) and not player.get_items().is_busy())
	await _free_world(world)


func _test_rest_visible() -> void:
	var world: ItemWorld = await _make_world()
	var player: Player = world.player
	var hands: ItemHands = _hands(player)
	var stub: StubView = _stub(player, MEDKIT)
	hands.set_rest_visible(true)
	_check("rest_visible_true_shows", stub.visible)
	hands.set_rest_visible(false)
	_check("rest_visible_false_hides", not stub.visible)
	_check("rest_not_a_gesture", not hands.is_showing())
	await _free_world(world)
