extends "res://tests/lib/test_case.gd"
## The item gestures on a real Player over a SandboxWorld (docs/plano_itens_animados.md 2.2, 2.3 and 3): what the
## hunter cannot do while the hands are busy, how the gesture meets the other states (binoculars, aim, reload, hunt end)
## and the double press. Edge cases hunted on purpose; the belt clock itself is in test_item_belt_timed.

const TIME_SCALE: float = 1.0
const WAIT_CAP_S: float = 6.0         # game seconds
const SETTLE_FRAMES: int = 6
const HURT_HEALTH: float = 40.0
const MEDKIT: StringName = &"medkit"
const BAIT: StringName = &"corn_bait"
const DRONE: StringName = &"scout_drone"
const BINOCULARS: StringName = &"binoculars"


## Sandbox that carries every usable item, three of each consumable.
class ItemWorld extends SandboxWorld:
	func _request() -> HuntRequest:
		var r: HuntRequest = super()
		r.item_ids = [Ids.I_MEDKIT, Ids.I_ENERGY_DRINK, Ids.I_SCOUT_DRONE, Ids.I_CORN_BAIT, Ids.I_BINOCULARS]
		r.item_counts = {Ids.I_MEDKIT: 3, Ids.I_ENERGY_DRINK: 3, Ids.I_SCOUT_DRONE: 3, Ids.I_CORN_BAIT: 3}
		return r


func _world() -> ItemWorld:
	var world: ItemWorld = ItemWorld.new()
	track(world)
	await frames(SETTLE_FRAMES)
	world.player.bot_set_enabled(true)
	Engine.time_scale = TIME_SCALE
	return world


## Waits (in real frames, capped in game seconds) until the belt is free again.
func _wait_free(items: ItemBelt) -> void:
	var guard: int = int(WAIT_CAP_S * 60.0)
	while items.is_busy() and guard > 0:
		await physics_frames(1)
		guard -= 1
	await frames(2)


func _weapon_visible(player: Player) -> bool:
	var view: Node3D = player.get_weapon_holder().get_current_view()
	return view != null and view.visible


func _total_spent(items: ItemBelt, start: Dictionary) -> int:
	var spent: int = 0
	for id: StringName in start:
		spent += int(start[id]) - items.get_count(id)
	return spent


func _counts(items: ItemBelt) -> Dictionary:
	return {MEDKIT: items.get_count(MEDKIT), BAIT: items.get_count(BAIT), DRONE: items.get_count(DRONE),
		&"energy_drink": items.get_count(&"energy_drink")}


# --------------------------------------------------------------------------------------------
# What the hands cannot do while a gesture plays
# --------------------------------------------------------------------------------------------

func test_hands_busy_blocks_fire_reload_and_weapon_switch() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	var weapon_before: StringName = player.get_current_weapon_id()
	var ammo_before: int = player.get_ammo_in_mag()
	eq(player.bot_use_item(DRONE), true, "gesto do drone comeca")
	await frames(2)
	eq(player.bot_fire(), false, "nao atira com as maos ocupadas")
	player.bot_reload()
	ok(not player.is_reloading(), "nao recarrega")
	player.bot_select_weapon(1)
	eq(player.get_current_weapon_id(), weapon_before, "nao troca de arma")
	eq(player.get_ammo_in_mag(), ammo_before, "municao intacta")
	player.bot_set_aim(true)
	var max_ads: float = 0.0
	var aimed: bool = false
	var seen_busy: int = 0
	while items.is_busy() and seen_busy < 400:
		await physics_frames(1)
		if not items.is_busy():
			break   # the frame in which the gesture ended already lets the aim start again
		seen_busy += 1
		max_ads = maxf(max_ads, player.get_ads_t())
		aimed = aimed or player.is_aiming()
	ok(seen_busy > 10, "fixture: o gesto durou (%d frames)" % seen_busy)
	ok(not aimed and max_ads < 0.2, "nao mira durante o gesto (ads_t max %.2f, is_aiming %s)" % [max_ads, aimed])
	player.bot_set_aim(false)
	await _wait_free(items)
	ok(_weapon_visible(player), "a arma volta na tela")


func test_sprint_stops_during_the_gesture_and_movement_stays_free() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	player.bot_set_move(Vector2(0.0, 1.0), true)
	await physics_frames(30)
	ok(player.is_sprinting(), "fixture: correndo")
	player.bot_use_item(DRONE)
	await physics_frames(10)
	ok(not player.is_sprinting(), "corrida cortada pelo gesto")
	var v: float = Vector2(player.velocity.x, player.velocity.z).length()
	ok(v > 1.0, "continua andando (%.2f m/s)" % v)
	player.bot_set_move(Vector2.ZERO, false)
	await _wait_free(items)


# --------------------------------------------------------------------------------------------
# Meeting the other states
# --------------------------------------------------------------------------------------------

func test_reload_in_progress_is_dropped_when_the_gesture_starts() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	await physics_frames(30)   # the weapon finishes its draw
	player.bot_fire()          # one round out, so there is something to reload
	await physics_frames(3)
	player.bot_reload()
	await physics_frames(3)
	if not player.is_reloading():
		skip("a arma nao recarregou depois de um tiro (fixture)")
		return
	player.bot_use_item(DRONE)
	await physics_frames(2)
	ok(not player.is_reloading(), "a recarga caiu")
	await _wait_free(items)
	ok(not player.is_reloading(), "e nao volta sozinha")


func test_binoculars_up_then_an_item_gesture() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	eq(player.bot_use_item(BINOCULARS), true, "binoculo sobe")
	await physics_frames(20)
	ok(player.is_binocular_view(), "fixture: binoculo ativo")
	var started: Dictionary = record_signal(items.use_started)
	var accepted: bool = player.bot_use_item(DRONE)
	if not accepted:
		eq(started["count"], 0, "recusado: nada comecou")
		return
	# Accepted: the binocular zoom must be let go while the hands work (the view eases out), and come back afterwards.
	var busy_frames: int = 0
	while items.is_busy() and busy_frames < 400:
		await physics_frames(1)
		busy_frames += 1
	ok(busy_frames > 10, "fixture: o gesto durou (%d frames)" % busy_frames)
	ok(player.get_ads_t() < 0.15, "zoom do binoculo solto no fim do gesto (ads_t %.2f)" % player.get_ads_t())
	await physics_frames(90)
	ok(player.is_binocular_view() and player.get_ads_t() > 0.9, "o binoculo volta sozinho depois (ads_t %.2f)" % player.get_ads_t())
	player.bot_use_item(BINOCULARS)


func test_hunt_ending_in_the_middle_of_a_gesture_cuts_it_and_spends_nothing() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	var start: Dictionary = _counts(items)
	player.bot_use_item(DRONE)
	await physics_frames(5)
	ok(items.is_busy(), "fixture: no meio do gesto, antes do beat")
	var result: HuntResult = HuntResult.new()
	result.outcome = HuntResult.Outcome.DEFEAT_CROP
	GameEvents.hunt_ended.emit(result)
	await frames(2)
	ok(not items.is_busy(), "o cinto soltou")
	eq(_total_spent(items, start), 0, "nada gasto")
	ok(not player.get("_hands").is_showing(), "a mao saiu da tela")


func test_double_press_in_one_frame_spends_one_unit() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	var start: Dictionary = _counts(items)
	var first: bool = player.bot_use_item(DRONE)
	var second: bool = player.bot_use_item(BAIT)     # same frame: "mouse e toque ao mesmo tempo"
	var third: bool = player.bot_use_item(DRONE)
	eq(first, true, "o primeiro entra")
	eq(second, false, "o segundo e recusado")
	eq(third, false, "o terceiro tambem")
	await _wait_free(items)
	eq(_total_spent(items, start), 1, "uma unidade so")
	eq(items.get_count(DRONE), int(start[DRONE]) - 1, "foi a do primeiro")


func test_real_key_actions_pressed_together_spend_one_unit() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	player.bot_set_enabled(false)   # the real input path, as a player with keyboard and a touch button at once
	var items: ItemBelt = player.get_items()
	var start: Dictionary = _counts(items)
	Input.action_press(&"use_scout_drone")
	Input.action_press(&"use_corn_bait")
	await physics_frames(4)
	Input.action_release(&"use_scout_drone")
	Input.action_release(&"use_corn_bait")
	await _wait_free(items)
	eq(_total_spent(items, start), 1, "duas teclas juntas: uma unidade so (gastou %d)" % _total_spent(items, start))


func test_held_key_does_not_chain_gestures() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	player.bot_set_enabled(false)
	var items: ItemBelt = player.get_items()
	var start: Dictionary = _counts(items)
	Input.action_press(&"use_scout_drone")
	var guard: int = int(4.0 * 60.0)
	while guard > 0 and not (items.get_count(DRONE) < int(start[DRONE]) and not items.is_busy()):
		await physics_frames(1)
		guard -= 1
	await physics_frames(30)    # still held after the gesture ended
	Input.action_release(&"use_scout_drone")
	await _wait_free(items)
	eq(_total_spent(items, start), 1, "tecla segurada nao repete o uso sozinha (gastou %d)" % _total_spent(items, start))


func test_item_during_knife_swing_is_refused_and_after_it_the_knife_goes_back() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	if not player.bot_knife():
		skip("sem faca nos dados")
		return
	eq(player.bot_use_item(DRONE), false, "no meio do golpe: recusado")
	eq(items.is_busy(), false, "nada comecou")
	var guard: int = 120
	while player.is_knife_swinging() and guard > 0:
		await physics_frames(1)
		guard -= 1
	eq(player.bot_use_item(DRONE), true, "depois do golpe: aceito")
	await physics_frames(2)
	ok(not player.is_knife_equipped(), "a faca voltou ao cinto antes do gesto")
	await _wait_free(items)
	ok(not player.is_knife_equipped() and _weapon_visible(player), "no fim quem volta e a arma, nao a faca")


func test_medkit_at_full_health_and_drink_at_full_stamina_start_no_gesture() -> void:
	var world: ItemWorld = await _world()
	var player: Player = world.player
	var items: ItemBelt = player.get_items()
	var started: Dictionary = record_signal(items.use_started)
	eq(player.bot_use_item(MEDKIT), false, "vida cheia")
	eq(player.bot_use_item(&"energy_drink"), false, "folego cheio")
	eq(started["count"], 0, "sem gesto")
	ok(_weapon_visible(player), "a arma segue na mao")
	player.debug_set_health(HURT_HEALTH)
	eq(player.bot_use_item(MEDKIT), true, "ferido: aceito")
	await _wait_free(items)
	ok(player.get_health() > HURT_HEALTH, "curou (%.0f)" % player.get_health())
