extends "res://tests/lib/test_case.gd"
## ItemBelt with time (docs/plano_itens_animados.md 2.2 and 3 item 6): every consumable plays a gesture of `use_time_s`
## seconds and the effect AND the spend land once at the `effect_at` beat, not at the key press. The belt is driven by
## hand (`_process(delta)`), so the clock is exact and no frame timing is involved.
## The energy drink is not here: its effect needs a real Player (stamina lives there); player_stamina_test covers it.

const STEP_S: float = 0.01
const BIG_STEP_S: float = 100.0
const TIMED_IDS: Array[StringName] = [&"medkit", &"corn_bait", &"scout_drone", &"energy_drink"]


## A hunter the test controls: health, alive flag and a heal counter (PlayerBase answers constants).
class StubPlayer extends PlayerBase:
	var hp: float = 50.0
	var alive: bool = true
	var heals: int = 0

	func get_health() -> float:
		return hp

	func is_alive() -> bool:
		return alive

	func heal(amount: float) -> void:
		heals += 1
		hp = minf(hp + amount, get_max_health())


var _belts: Array[ItemBelt] = []


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

func _player(hp: float = 50.0) -> StubPlayer:
	var player: StubPlayer = StubPlayer.new()
	player.hp = hp
	track(player)
	return player


func _belt(player: StubPlayer, ids: Array[StringName], counts: Dictionary = {}) -> ItemBelt:
	var request: HuntRequest = HuntRequest.make_debug()
	request.item_ids = ids
	request.item_counts = {&"medkit": 2, &"corn_bait": 2, &"scout_drone": 2}
	request.item_counts.merge(counts, true)
	var belt: ItemBelt = ItemBelt.new()
	belt.setup(request, player, null)
	_belts.append(belt)
	return belt


func _free_belts() -> void:
	for b: ItemBelt in _belts:
		if is_instance_valid(b):
			b.free()
	_belts.clear()


func _effect(id: StringName) -> Dictionary:
	return Data.get_equipment(id).get("effect", {})


func _use_time(id: StringName) -> float:
	return float(_effect(id).get("use_time_s", 0.0))


func _beat_s(id: StringName) -> float:
	return _use_time(id) * float(_effect(id).get("effect_at", 1.0))


## Runs the belt clock for `seconds` in STEP_S steps.
func _advance(belt: ItemBelt, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var step: float = minf(STEP_S, left)
		belt._process(step)
		left -= step


## Records, in order, what the belt announces: use_started, item_used (the beat) and use_finished.
func _log_events(belt: ItemBelt) -> Array[String]:
	var events: Array[String] = []
	belt.use_started.connect(func(id: StringName, _d: float) -> void: events.append("started:%s" % id))
	GameEvents.item_used.connect(func(id: StringName, _p: Vector3) -> void: events.append("used:%s" % id))
	belt.use_finished.connect(func(id: StringName) -> void: events.append("finished:%s" % id))
	return events


# --------------------------------------------------------------------------------------------
# Data fixture
# --------------------------------------------------------------------------------------------

func test_every_consumable_has_a_gesture_in_the_data() -> void:
	for id: StringName in TIMED_IDS:
		var time_s: float = _use_time(id)
		var at: float = float(_effect(id).get("effect_at", -1.0))
		ok(time_s > 0.0 and time_s <= 3.0, "%s: use_time_s %.2f" % [id, time_s])
		ok(at >= 0.0 and at <= 1.0, "%s: effect_at %.2f em 0..1" % [id, at])
	ok(not Data.get_equipment(&"binoculars").get("effect", {}).has("use_time_s"), "binoculo continua instantaneo")


# --------------------------------------------------------------------------------------------
# The beat
# --------------------------------------------------------------------------------------------

func test_press_starts_the_gesture_and_spends_nothing() -> void:
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone"]:
		var player: StubPlayer = _player()
		var belt: ItemBelt = _belt(player, [id])
		var used: Dictionary = record_signal(GameEvents.item_used)
		var started: Dictionary = record_signal(belt.use_started)
		var changed: Dictionary = record_signal(belt.counts_changed)
		eq(belt.use_item(id), true, "%s: o uso comeca" % id)
		eq(started["count"], 1, "%s: use_started uma vez" % id)
		if int(started["count"]) >= 1:
			eq(started["calls"][0][0], id, "%s: use_started com o id" % id)
			near(float(started["calls"][0][1]), _use_time(id), 0.0001, "%s: duracao do dado" % id)
		ok(belt.is_busy() and belt.get_busy_item() == id, "%s: ocupado com o item" % id)
		eq(belt.get_count(id), 2, "%s: o aperto nao desconta" % id)
		eq(used["count"], 0, "%s: item_used nao sai no aperto" % id)
		eq(changed["count"], 0, "%s: counts_changed nao sai no aperto" % id)
		near(belt.get_busy_progress(), 0.0, 0.0001, "%s: progresso zero no aperto" % id)
		eq(player.heals, 0, "%s: nada curado no aperto" % id)
		near(belt.drone_reveal_s, 0.0, 0.0001, "%s: nada revelado no aperto" % id)
		belt.cancel_use()
		_free_belts()


func test_effect_and_spend_land_once_at_the_beat() -> void:
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone"]:
		var player: StubPlayer = _player()
		var belt: ItemBelt = _belt(player, [id])
		var used: Dictionary = record_signal(GameEvents.item_used)
		var changed: Dictionary = record_signal(belt.counts_changed)
		var beat: float = _beat_s(id)
		belt.use_item(id)
		# a hair before the beat: still nothing
		_advance(belt, beat - 0.03)
		eq(used["count"], 0, "%s: antes do beat nada e anunciado" % id)
		eq(belt.get_count(id), 2, "%s: antes do beat nada e gasto" % id)
		eq(player.heals, 0, "%s: antes do beat nao cura" % id)
		near(belt.drone_reveal_s, 0.0, 0.0001, "%s: antes do beat nao revela" % id)
		# past the beat: exactly one
		_advance(belt, 0.06)
		eq(used["count"], 1, "%s: item_used no beat" % id)
		eq(changed["count"], 1, "%s: counts_changed no beat" % id)
		eq(belt.get_count(id), 1, "%s: 2 -> 1 no beat" % id)
		if int(used["count"]) >= 1:
			eq(used["calls"][0][0], id, "%s: item_used com o id" % id)
		# the rest of the gesture and a long tail afterwards: never a second beat
		_advance(belt, _use_time(id) + 1.0)
		eq(used["count"], 1, "%s: o beat cai uma vez so" % id)
		eq(belt.get_count(id), 1, "%s: desconta uma unidade so" % id)
		match id:
			&"medkit":
				eq(player.heals, 1, "kit: uma cura so")
				near(player.hp, 50.0 + float(_effect(id)["heal"]), 0.001, "kit: cura do dado")
			&"scout_drone":
				near(belt.drone_reveal_s, float(_effect(id)["reveal_s"]), 0.0001, "drone: revelacao do dado")
		_free_belts()


func test_use_finished_at_the_end_not_at_the_beat() -> void:
	for id: StringName in [&"corn_bait", &"scout_drone"]:   # effect_at < 1: beat and end are apart
		var belt: ItemBelt = _belt(_player(), [id])
		var finished: Dictionary = record_signal(belt.use_finished)
		belt.use_item(id)
		_advance(belt, _beat_s(id) + 0.05)
		eq(finished["count"], 0, "%s: use_finished nao sai no beat" % id)
		ok(belt.is_busy(), "%s: ainda ocupado depois do beat" % id)
		_advance(belt, _use_time(id))
		eq(finished["count"], 1, "%s: use_finished uma vez no fim" % id)
		if int(finished["count"]) >= 1:
			eq(finished["calls"][0][0], id, "%s: use_finished com o id" % id)
		ok(not belt.is_busy() and belt.get_busy_item() == &"", "%s: livre no fim" % id)
		near(belt.get_busy_progress(), 0.0, 0.0001, "%s: progresso zerado" % id)
		_free_belts()


func test_effect_at_one_orders_effect_used_finished_in_the_same_frame() -> void:
	ok(is_equal_approx(float(_effect(&"medkit").get("effect_at", 1.0)), 1.0), "fixture: o kit cai no fim")
	var player: StubPlayer = _player()
	var belt: ItemBelt = _belt(player, [&"medkit"])
	var events: Array[String] = _log_events(belt)
	belt.use_item(&"medkit")
	_advance(belt, _use_time(&"medkit") - 0.05)
	eq(player.heals, 0, "kit: nada antes do ultimo frame")
	belt._process(0.1)
	eq(player.heals, 1, "kit: curou no ultimo frame")
	eq(events, ["started:medkit", "used:medkit", "finished:medkit"] as Array[String], "ordem: inicio, item_used, use_finished")
	_free_belts()


func test_one_giant_step_still_beats_once_and_finishes() -> void:
	# a hitch frame longer than the whole gesture: the beat is not skipped and not doubled
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone"]:
		var player: StubPlayer = _player()
		var belt: ItemBelt = _belt(player, [id])
		var used: Dictionary = record_signal(GameEvents.item_used)
		var finished: Dictionary = record_signal(belt.use_finished)
		belt.use_item(id)
		belt._process(BIG_STEP_S)
		eq(used["count"], 1, "%s: um beat em um frame gigante" % id)
		eq(finished["count"], 1, "%s: um fim" % id)
		eq(belt.get_count(id), 1, "%s: 2 -> 1" % id)
		ok(not belt.is_busy(), "%s: livre" % id)
		belt._process(BIG_STEP_S)
		eq(used["count"], 1, "%s: processo ocioso nao repete" % id)
		_free_belts()


func test_zero_delta_frames_do_not_beat_early() -> void:
	var belt: ItemBelt = _belt(_player(), [&"scout_drone"])
	var used: Dictionary = record_signal(GameEvents.item_used)
	belt.use_item(&"scout_drone")
	for i: int in 30:
		belt._process(0.0)
	eq(used["count"], 0, "delta 0 nao avanca o gesto")
	ok(belt.is_busy(), "ainda ocupado")
	belt.cancel_use()
	_free_belts()


func test_progress_grows_with_the_clock_up_to_the_end() -> void:
	var belt: ItemBelt = _belt(_player(), [&"scout_drone"])
	belt.use_item(&"scout_drone")
	var total: float = _use_time(&"scout_drone")
	var last: float = -1.0
	var monotonic: bool = true
	for i: int in 9:
		belt._process(total / 10.0)
		var p: float = belt.get_busy_progress()
		monotonic = monotonic and p >= last
		last = p
	ok(monotonic, "progresso nunca recua")
	near(last, 0.9, 0.02, "progresso a 90%")
	belt._process(total)
	near(belt.get_busy_progress(), 0.0, 0.0001, "progresso zerado depois do fim")
	_free_belts()


# --------------------------------------------------------------------------------------------
# The bait lands where the hunter looks at the beat
# --------------------------------------------------------------------------------------------

func test_bait_position_is_taken_at_the_beat() -> void:
	var player: StubPlayer = _player()
	var belt: ItemBelt = _belt(player, [&"corn_bait"])
	var used: Dictionary = record_signal(GameEvents.item_used)
	var at_press: Vector3 = player.global_position + player.get_look_direction().normalized() * ItemBelt.BAIT_DISTANCE_M
	belt.use_item(&"corn_bait")
	_advance(belt, _beat_s(&"corn_bait") * 0.5)
	player.rotation.y = PI * 0.5   # the hunter turns while the hand winds up
	var at_beat: Vector3 = player.global_position + player.get_look_direction().normalized() * ItemBelt.BAIT_DISTANCE_M
	ok(at_press.distance_to(at_beat) > 1.0, "fixture: virar muda o ponto")
	_advance(belt, _use_time(&"corn_bait"))
	eq(used["count"], 1, "ceva anunciada uma vez")
	if int(used["count"]) >= 1:
		var pos: Vector3 = used["calls"][0][1]
		ok(pos.distance_to(at_beat) < 0.01, "a ceva cai onde olha no beat: %s, esperado %s" % [pos, at_beat])
		ok(pos.distance_to(at_press) > 1.0, "nao onde olhava no aperto")
	_free_belts()


# --------------------------------------------------------------------------------------------
# Busy rules
# --------------------------------------------------------------------------------------------

func test_busy_refuses_other_uses_and_never_spends_them() -> void:
	var belt: ItemBelt = _belt(_player(), [&"medkit", &"corn_bait", &"scout_drone", &"binoculars"])
	var started: Dictionary = record_signal(belt.use_started)
	eq(belt.use_item(&"scout_drone"), true, "drone comeca")
	eq(belt.use_item(&"scout_drone"), false, "o mesmo item de novo")
	eq(belt.use_item(&"corn_bait"), false, "outro consumivel")
	eq(belt.use_item(&"medkit"), false, "kit")
	eq(belt.use_item(&"binoculars"), false, "binoculo tambem espera o gesto")
	eq(belt.is_binoculars_active(), false, "binoculo nao alternou")
	eq(started["count"], 1, "um use_started so")
	_advance(belt, _use_time(&"scout_drone") + 0.1)
	eq(belt.get_count(&"scout_drone"), 1, "so uma unidade do drone")
	eq(belt.get_count(&"corn_bait"), 2, "ceva intacta")
	eq(belt.get_count(&"medkit"), 2, "kit intacto")
	eq(belt.use_item(&"binoculars"), true, "livre de novo: binoculo instantaneo")
	eq(belt.is_busy(), false, "binoculo nao ocupa o cinto")
	_free_belts()


func test_last_unit_is_spent_at_the_beat_and_then_refused() -> void:
	var belt: ItemBelt = _belt(_player(), [&"scout_drone"], {&"scout_drone": 1})
	var used: Dictionary = record_signal(GameEvents.item_used)
	eq(belt.use_item(&"scout_drone"), true, "ultima unidade comeca")
	eq(belt.get_count(&"scout_drone"), 1, "ainda 1 no aperto")
	_advance(belt, _use_time(&"scout_drone") + 0.1)
	eq(belt.get_count(&"scout_drone"), 0, "0 depois do beat")
	eq(belt.use_item(&"scout_drone"), false, "acabou")
	eq(belt.get_count(&"scout_drone"), 0, "nunca negativo")
	eq(used["count"], 1, "um item_used")
	_free_belts()


func test_refusals_do_not_start_a_gesture() -> void:
	var full: StubPlayer = _player(100.0)
	var belt: ItemBelt = _belt(full, [&"medkit"])
	var started: Dictionary = record_signal(belt.use_started)
	var msg: Dictionary = record_signal(GameEvents.hud_message_requested)
	eq(belt.use_item(&"medkit"), false, "vida cheia")
	eq(belt.is_busy(), false, "sem gesto")
	eq(started["count"], 0, "sem use_started")
	eq(msg["calls"][0][0] if int(msg["count"]) >= 1 else "", "Sua vida já está cheia.", "mensagem")
	eq(belt.get_count(&"medkit"), 2, "nada gasto")
	_free_belts()


# --------------------------------------------------------------------------------------------
# Cancelling
# --------------------------------------------------------------------------------------------

func test_cancel_before_the_beat_spends_and_applies_nothing() -> void:
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone"]:
		var player: StubPlayer = _player()
		var belt: ItemBelt = _belt(player, [id])
		var used: Dictionary = record_signal(GameEvents.item_used)
		var changed: Dictionary = record_signal(belt.counts_changed)
		var finished: Dictionary = record_signal(belt.use_finished)
		belt.use_item(id)
		_advance(belt, _beat_s(id) * 0.5)
		belt.cancel_use()
		eq(finished["count"], 1, "%s: use_finished uma vez" % id)
		if int(finished["count"]) >= 1:
			eq(finished["calls"][0][0], &"", "%s: id vazio = cortado" % id)
		ok(not belt.is_busy() and belt.get_busy_item() == &"", "%s: livre" % id)
		eq(belt.get_count(id), 2, "%s: nada consumido" % id)
		eq(used["count"], 0, "%s: sem item_used" % id)
		eq(changed["count"], 0, "%s: sem counts_changed" % id)
		eq(player.heals, 0, "%s: sem cura" % id)
		near(belt.drone_reveal_s, 0.0, 0.0001, "%s: sem revelacao" % id)
		# the clock keeps running after the cut: the dead gesture must not wake up
		_advance(belt, _use_time(id) + 1.0)
		eq(used["count"], 0, "%s: o gesto cortado nao dispara depois" % id)
		eq(finished["count"], 1, "%s: use_finished nao repete" % id)
		# and the item is still usable
		eq(belt.use_item(id), true, "%s: pode usar de novo" % id)
		belt.cancel_use()
		_free_belts()


func test_cancel_after_the_beat_keeps_the_spend() -> void:
	for id: StringName in [&"corn_bait", &"scout_drone"]:
		var belt: ItemBelt = _belt(_player(), [id])
		var used: Dictionary = record_signal(GameEvents.item_used)
		var finished: Dictionary = record_signal(belt.use_finished)
		belt.use_item(id)
		_advance(belt, _beat_s(id) + 0.05)
		eq(used["count"], 1, "%s: o beat ja caiu" % id)
		belt.cancel_use()
		eq(belt.get_count(id), 1, "%s: gasto mantido" % id)
		eq(used["count"], 1, "%s: sem segundo item_used" % id)
		eq(finished["count"], 1, "%s: use_finished uma vez" % id)
		if int(finished["count"]) >= 1:
			eq(finished["calls"][0][0], &"", "%s: id vazio = cortado" % id)
		_advance(belt, _use_time(id) + 1.0)
		eq(used["count"], 1, "%s: nada depois do corte" % id)
		eq(belt.get_count(id), 1, "%s: continua 1" % id)
		_free_belts()


func test_cancel_when_idle_is_silent() -> void:
	var belt: ItemBelt = _belt(_player(), [&"medkit"])
	var finished: Dictionary = record_signal(belt.use_finished)
	belt.cancel_use()
	eq(finished["count"], 0, "sem gesto: nenhum use_finished")
	_free_belts()


# --------------------------------------------------------------------------------------------
# A dead hunter
# --------------------------------------------------------------------------------------------

func test_hunter_dying_before_the_beat_gets_nothing() -> void:
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone"]:
		var player: StubPlayer = _player()
		var belt: ItemBelt = _belt(player, [id])
		var used: Dictionary = record_signal(GameEvents.item_used)
		var finished: Dictionary = record_signal(belt.use_finished)
		belt.use_item(id)
		_advance(belt, _beat_s(id) * 0.5)
		player.alive = false   # no cancel_use from the Player: the belt alone must refuse to apply
		_advance(belt, _use_time(id) + 0.5)
		eq(used["count"], 0, "%s: morto nao gasta" % id)
		eq(belt.get_count(id), 2, "%s: contagem intacta" % id)
		eq(player.heals, 0, "%s: morto nao cura" % id)
		near(belt.drone_reveal_s, 0.0, 0.0001, "%s: morto nao revela" % id)
		ok(not belt.is_busy(), "%s: o cinto nao fica preso" % id)
		eq(finished["count"], 1, "%s: use_finished uma vez" % id)
		if int(finished["count"]) >= 1:
			eq(finished["calls"][0][0], &"", "%s: id vazio = cortado" % id)
		_free_belts()


func test_hunter_dying_exactly_at_the_end_of_a_beat_one_gesture() -> void:
	# medkit: effect_at 1.0, so the beat and the end share a frame
	var player: StubPlayer = _player()
	var belt: ItemBelt = _belt(player, [&"medkit"])
	var used: Dictionary = record_signal(GameEvents.item_used)
	belt.use_item(&"medkit")
	_advance(belt, _use_time(&"medkit") - 0.05)
	player.alive = false
	belt._process(0.2)
	eq(used["count"], 0, "kit: morto no ultimo frame, nada gasto")
	eq(player.heals, 0, "kit: sem cura")
	eq(belt.get_count(&"medkit"), 2, "kit: contagem intacta")
	ok(not belt.is_busy(), "kit: livre")
	_free_belts()


func test_hunter_dying_after_the_beat_keeps_the_spend_and_frees_the_belt() -> void:
	var player: StubPlayer = _player()
	var belt: ItemBelt = _belt(player, [&"scout_drone"])
	var used: Dictionary = record_signal(GameEvents.item_used)
	var finished: Dictionary = record_signal(belt.use_finished)
	belt.use_item(&"scout_drone")
	_advance(belt, _beat_s(&"scout_drone") + 0.05)
	player.alive = false
	_advance(belt, _use_time(&"scout_drone"))
	eq(used["count"], 1, "drone: ja tinha saido da mao")
	eq(belt.get_count(&"scout_drone"), 1, "drone: gasto mantido")
	ok(not belt.is_busy(), "cinto livre")
	eq(finished["count"], 1, "use_finished uma vez")
	_free_belts()


# --------------------------------------------------------------------------------------------
# Edge cases hunted on purpose
# --------------------------------------------------------------------------------------------

func test_medkit_health_filled_during_the_gesture_is_spent_and_never_overheals() -> void:
	# Another source (a revive, a second medkit of an ally is not possible) tops the hunter up mid-gesture.
	# Documented behaviour: the check is at the press only, the kit is spent at the beat, health stays capped.
	var player: StubPlayer = _player(50.0)
	var belt: ItemBelt = _belt(player, [&"medkit"])
	belt.use_item(&"medkit")
	_advance(belt, _use_time(&"medkit") * 0.5)
	player.hp = 100.0
	_advance(belt, _use_time(&"medkit"))
	near(player.hp, 100.0, 0.0001, "vida nunca passa do maximo")
	eq(belt.get_count(&"medkit"), 1, "kit gasto no beat")
	_free_belts()


func test_setup_again_does_not_leave_a_stale_gesture() -> void:
	# A new hunt re-runs setup() on the same belt object only in tests, but the state must not leak a running gesture.
	var player: StubPlayer = _player()
	var belt: ItemBelt = _belt(player, [&"scout_drone"])
	belt.use_item(&"scout_drone")
	belt.cancel_use()
	ok(not belt.is_busy(), "cortado e livre")
	var request: HuntRequest = HuntRequest.make_debug()
	request.item_ids = [&"scout_drone"] as Array[StringName]
	request.item_counts = {&"scout_drone": 1}
	belt.setup(request, player, null)
	eq(belt.get_count(&"scout_drone"), 1, "contagem nova")
	eq(belt.use_item(&"scout_drone"), true, "usa depois do setup")
	_advance(belt, _use_time(&"scout_drone") + 0.1)
	eq(belt.get_count(&"scout_drone"), 0, "gasta no beat")
	_free_belts()
