extends Node
## Package A sandbox for the contextual hints (docs §8.4 "Dicas das primeiras caçadas", §14 HF2-A). Two layers:
##  - HintDirector driven by hand: a fake world (extends HuntWorld) and a fake hunter (extends PlayerBase) with the
##    real ItemBelt, time advanced in fixed steps by calling _process, so the 60 s of the drone and the 5 s of each
##    hint cost nothing. Covers every trigger with and without its condition, the queue, the learned ids,
##    hunts_played >= max_hunts, the touch texts, the end of the hunt and the horde text.
##  - The real Hud with a SandboxWorld and the real Player: banner, blinking slot (bar and touch) and the hide on use.
## Prints PASS/FAIL lines and "RESULT: p passed, f failed, 0 skipped", then quits by itself.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hud/debug/hud_hints_test.tscn
## Screenshot mode (needs a window; not headless): add "-- --hint_demo=kit|dog|opening|bar [--touch=on]" and capture with
## tools/screenshot.gd. It sets up the scene and stays DEMO_WATCHDOG_S seconds. Uses its own save file, never the real one.
## Not part of the game.

const WATCHDOG_S: float = 60.0
const DEMO_WATCHDOG_S: float = 30.0
const TEST_SAVE_PATH: String = "user://test_hints_save.json"
const NO_ID: StringName = &""
const ALL_ITEMS: Array[StringName] = [Ids.I_MEDKIT, Ids.I_CORN_BAIT, Ids.I_SCOUT_DRONE, Ids.I_BINOCULARS]
const ALL_COUNTS: Dictionary = {Ids.I_MEDKIT: 2, Ids.I_CORN_BAIT: 1, Ids.I_SCOUT_DRONE: 1}
const IN_FRONT: Vector3 = Vector3(0.0, 0.0, -30.0)       # inside range and the cone, hunter looks at -Z
const BEHIND: Vector3 = Vector3(0.0, 0.0, 40.0)
const OPENING_TEXT: String = "Seus itens ficam na barra embaixo. Aperte a tecla de cada um para usar."
const TEXTS_DESKTOP: Dictionary = {
	"opening": OPENING_TEXT,
	"medkit": "Q: Curar",
	"dog_command": "E: Mandar o cão atacar",
	"scout_drone": "V: Drone revela os javalis no minimapa",
	"corn_bait": "G: Ceva atrai os javalis para longe da lavoura",
}
const TEXTS_TOUCH: Dictionary = {
	"opening": "Cada item tem o seu botão. Toque nele para usar.",
	"medkit": "Toque no kit para curar",
	"dog_command": "Toque em Cão para mandar o cão atacar",
	"scout_drone": "Toque no drone: ele revela os javalis no minimapa",
	"corn_bait": "Toque na ceva para atrair os javalis para longe da lavoura",
}
const BAIT_HORDE_DESKTOP: String = "G: Ceva atrai os javalis para longe do celeiro"
const BAIT_HORDE_TOUCH: String = "Toque na ceva para atrair os javalis para longe do celeiro"

var _passed: int = 0
var _failed: int = 0
var _cfg: Dictionary = {}


## A hunter the director can read: health, alive flag and gaze are plain fields.
class FakePlayer extends PlayerBase:
	var health: float = 100.0
	var alive: bool = true
	var look: Vector3 = Vector3(0.0, 0.0, -1.0)

	func is_alive() -> bool:
		return alive

	func get_health() -> float:
		return health

	func get_look_direction() -> Vector3:
		return look

	func heal(amount: float) -> void:
		health = minf(health + amount, get_max_health())


## A world with the few things the director asks: living boars (id -> position), the dog and the mode.
class FakeWorld extends HuntWorld:
	var boars: Dictionary = {}
	var dog: bool = false
	var dog_state: StringName = Ids.DS_FOLLOW
	var horde: bool = false
	var over: bool = false

	func get_alive_boar_ids() -> PackedInt32Array:
		var ids: PackedInt32Array = PackedInt32Array()
		for boar_id: int in boars:
			ids.append(boar_id)
		return ids

	func get_boar_position(boar_id: int) -> Vector3:
		if not boars.has(boar_id):
			return Vector3.INF
		var pos: Vector3 = boars[boar_id]
		return pos

	func has_dog() -> bool:
		return dog

	func get_dog_state() -> StringName:
		return dog_state

	func get_mode() -> StringName:
		return Ids.MODE_HORDE if horde else Ids.MODE_CONTRACT

	func is_hunt_over() -> bool:
		return over


## One director with its fake world and the real ItemBelt. advance() plays time in STEP_S steps.
class Rig extends RefCounted:
	const STEP_S: float = 0.05

	var world: FakeWorld = null
	var player: FakePlayer = null
	var items: ItemBelt = null
	var director: HintDirector = null
	var request: HuntRequest = null
	var t: float = 0.0
	var shown: Array[Dictionary] = []     # {id, text, slot, t}
	var hidden: Array[Dictionary] = []    # {id, t}
	var max_queue: int = 0

	func on_shown(hint_id: StringName, text: String, slot_id: StringName) -> void:
		shown.append({"id": hint_id, "text": text, "slot": slot_id, "t": t})

	func on_hidden(hint_id: StringName) -> void:
		hidden.append({"id": hint_id, "t": t})

	func advance(seconds: float) -> void:
		for i: int in range(int(round(seconds / STEP_S))):
			t += STEP_S
			items._process(STEP_S)
			director._process(STEP_S)
			max_queue = maxi(max_queue, director.get_queue().size())

	func shown_names() -> Array:
		var out: Array = []
		for entry: Dictionary in shown:
			out.append(String(entry["id"]))
		return out

	func count_shown(hint_id: StringName) -> int:
		var n: int = 0
		for entry: Dictionary in shown:
			if entry["id"] == hint_id:
				n += 1
		return n

	## Shown, on screen or waiting: a trigger that fired, even if the opening still holds the screen.
	func seen(hint_id: StringName) -> bool:
		return count_shown(hint_id) > 0 or director.get_current_hint() == hint_id or director.get_queue().has(hint_id)

	func entry_of(hint_id: StringName) -> Dictionary:
		for entry: Dictionary in shown:
			if entry["id"] == hint_id:
				return entry
		return {}

	func hidden_at(hint_id: StringName) -> float:
		for entry: Dictionary in hidden:
			if entry["id"] == hint_id:
				return float(entry["t"])
		return -1.0

	func queue_names() -> Array:
		var out: Array = []
		for hint_id: StringName in director.get_queue():
			out.append(String(hint_id))
		return out


func _ready() -> void:
	Profile.set_save_path(TEST_SAVE_PATH)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hint_demo="):
			await _run_demo(arg.trim_prefix("--hint_demo="))
			return
	_cfg = Data.get_game().get("onboarding", {})
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await _test_triggers_and_texts()
	await _test_conditions_off()
	await _test_sighting()
	await _test_drone_clock()
	await _test_queue_default()
	await _test_queue_limit()
	await _test_reevaluation()
	await _test_learned()
	await _test_inactive()
	await _test_end_of_hunt()
	await _test_hud_integration()
	InputSetup.set_touch_override("auto")
	Profile.reset_progress()
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


# ---------------------------------------------------------------------------
# Rig
# ---------------------------------------------------------------------------

func _prepare_profile(hunts_played: int, learned: Array = []) -> void:
	Profile.reset_progress()
	for i: int in hunts_played:
		var result: HuntResult = HuntResult.new()
		result.outcome = HuntResult.Outcome.DEFEAT_DEATH
		Profile.apply_hunt_result(result)
	for hint_id: Variant in learned:
		Profile.mark_hint_learned(StringName(hint_id))


## opts: items (Array[StringName]), counts, dog, horde, hunts, learned, queue_max, start (false = no hunt_started).
func _make_rig(opts: Dictionary = {}) -> Rig:
	_prepare_profile(int(opts.get("hunts", 0)), opts.get("learned", []))
	var rig: Rig = Rig.new()
	rig.world = FakeWorld.new()
	rig.world.dog = bool(opts.get("dog", false))
	rig.world.horde = bool(opts.get("horde", false))
	add_child(rig.world)
	rig.player = FakePlayer.new()
	rig.world.add_child(rig.player)
	rig.request = HuntRequest.make_debug()
	var item_ids: Array = opts.get("items", ALL_ITEMS)
	rig.request.item_ids.assign(item_ids)
	rig.request.item_counts = opts.get("counts", ALL_COUNTS)
	rig.items = ItemBelt.new()
	rig.world.add_child(rig.items)
	rig.items.setup(rig.request, rig.player, rig.world)
	rig.items.set_process(false)          # time is played by Rig.advance
	rig.director = HintDirector.new()
	rig.world.add_child(rig.director)
	rig.director.hint_shown.connect(rig.on_shown)
	rig.director.hint_hidden.connect(rig.on_hidden)
	var onboarding: Dictionary = Data.get_game().get("onboarding", {})
	var saved_max: Variant = onboarding.get("queue_max")
	if opts.has("queue_max"):
		onboarding["queue_max"] = int(opts["queue_max"])   # the director reads it once, in setup
	rig.director.setup(rig.player, rig.items, rig.world)
	onboarding["queue_max"] = saved_max
	if rig.director.is_active():
		rig.director.set_process(false)
	if bool(opts.get("start", true)):
		GameEvents.hunt_started.emit(rig.request)
	return rig


func _free_rig(rig: Rig) -> void:
	rig.world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Puts the world in the state that fires `hint_id` and returns the seconds to play.
func _arrange(rig: Rig, hint_id: StringName) -> float:
	match hint_id:
		Ids.I_MEDKIT:
			rig.player.health = 40.0
			return 0.6
		Quickbar.DOG_SLOT:
			rig.world.boars[1] = IN_FRONT
			return 0.6
		Ids.I_CORN_BAIT:
			GameEvents.crop_under_attack.emit(true)
			return 0.6
		Ids.I_SCOUT_DRONE:
			rig.world.boars[1] = BEHIND
			return 61.0
	return 2.5   # the opening


# ---------------------------------------------------------------------------
# Triggers and texts
# ---------------------------------------------------------------------------

func _test_triggers_and_texts() -> void:
	var ids: Array[StringName] = [HintDirector.OPENING, Ids.I_MEDKIT, Quickbar.DOG_SLOT, Ids.I_SCOUT_DRONE, Ids.I_CORN_BAIT]
	for touch: bool in [false, true]:
		InputSetup.set_touch_override("on" if touch else "off")
		var texts: Dictionary = TEXTS_TOUCH if touch else TEXTS_DESKTOP
		var mode_name: String = "touch" if touch else "desktop"
		for hint_id: StringName in ids:
			var rig: Rig = _make_rig({"dog": true})
			var seconds: float = _arrange(rig, hint_id)
			rig.advance(seconds)
			var entry: Dictionary = rig.entry_of(hint_id)
			var key: String = String(hint_id)
			_check("%s_%s_fires" % [mode_name, key], not entry.is_empty() and rig.count_shown(hint_id) == 1,
				str(rig.shown_names()))
			if not entry.is_empty():
				_check("%s_%s_text" % [mode_name, key], String(entry["text"]) == String(texts[key]), String(entry["text"]))
				var want_slot: StringName = NO_ID if hint_id == HintDirector.OPENING else hint_id
				_check("%s_%s_slot" % [mode_name, key], entry["slot"] == want_slot, String(entry["slot"]))
			await _free_rig(rig)
		# Horde: the bait talks about the barn.
		var horde_rig: Rig = _make_rig({"horde": true})
		GameEvents.crop_under_attack.emit(true)
		horde_rig.advance(0.6)
		var horde_entry: Dictionary = horde_rig.entry_of(Ids.I_CORN_BAIT)
		var want_horde: String = BAIT_HORDE_TOUCH if touch else BAIT_HORDE_DESKTOP
		_check("%s_bait_horde_text" % mode_name, not horde_entry.is_empty() and String(horde_entry["text"]) == want_horde,
			String(horde_entry.get("text", "<none>")))
		await _free_rig(horde_rig)
		GameEvents.crop_under_attack.emit(false)
	InputSetup.set_touch_override("off")

	# Timing: the opening comes opening_delay_s after hunt_started and lasts opening_duration_s.
	var rig: Rig = _make_rig({})
	rig.advance(float(_cfg["opening_delay_s"]) - 0.1)
	_check("opening_not_before_delay", rig.shown.is_empty(), str(rig.shown_names()))
	rig.advance(0.5)
	var opening: Dictionary = rig.entry_of(HintDirector.OPENING)
	var delay: float = float(_cfg["opening_delay_s"])
	_check("opening_after_delay", not opening.is_empty() and float(opening["t"]) >= delay - 0.01
		and float(opening["t"]) <= delay + float(_cfg["eval_interval_s"]) + 0.15, str(opening.get("t")))
	_check("opening_is_current", rig.director.get_current_hint() == HintDirector.OPENING)
	var duration: float = float(_cfg["opening_duration_s"])
	rig.advance(duration - 1.0)
	_check("opening_lasts_duration", rig.director.get_current_hint() == HintDirector.OPENING)
	rig.advance(1.5)
	var gone: float = rig.hidden_at(HintDirector.OPENING)
	_check("opening_hides_after_duration", gone >= 0.0 and absf(gone - float(opening["t"]) - duration) < 0.1,
		"%.2f s on screen" % (gone - float(opening["t"])))
	rig.advance(60.0)
	_check("opening_once_per_hunt", rig.shown_names() == ["opening"], str(rig.shown_names()))
	var shown_copy: Array[StringName] = rig.director.get_shown_this_hunt()
	_check("shown_this_hunt_copy", shown_copy.size() == 1 and shown_copy[0] == HintDirector.OPENING)
	await _free_rig(rig)

	# The opening needs at least one slot: no usable item and no dog = no opening; a dog alone is enough.
	var empty_rig: Rig = _make_rig({"items": [], "counts": {}})
	empty_rig.advance(8.0)
	_check("opening_needs_a_slot", empty_rig.shown.is_empty(), str(empty_rig.shown_names()))
	await _free_rig(empty_rig)
	var dog_only: Rig = _make_rig({"items": [], "counts": {}, "dog": true})
	dog_only.advance(2.5)
	_check("opening_with_dog_slot_only", dog_only.count_shown(HintDirector.OPENING) == 1, str(dog_only.shown_names()))
	await _free_rig(dog_only)


# ---------------------------------------------------------------------------
# Conditions that must NOT fire
# ---------------------------------------------------------------------------

func _test_conditions_off() -> void:
	InputSetup.set_touch_override("off")
	var half: float = float(_cfg["medkit_health_below_pct"])
	# Medkit: full health, exactly at the limit, none left, not carried, being used.
	var rig: Rig = _make_rig({})
	rig.advance(1.9)
	_check("medkit_off_full_health", not rig.seen(Ids.I_MEDKIT))
	rig.player.health = half
	rig.advance(1.0)
	_check("medkit_off_at_limit", not rig.seen(Ids.I_MEDKIT), "health %.0f" % rig.player.health)
	rig.player.health = half - 0.1
	rig.advance(0.5)
	_check("medkit_on_just_below_limit", rig.seen(Ids.I_MEDKIT))
	await _free_rig(rig)
	rig = _make_rig({"counts": {Ids.I_MEDKIT: 0, Ids.I_CORN_BAIT: 1, Ids.I_SCOUT_DRONE: 1}})
	rig.player.health = 10.0
	rig.advance(1.5)
	_check("medkit_off_without_stock", not rig.seen(Ids.I_MEDKIT))
	await _free_rig(rig)
	rig = _make_rig({"items": [Ids.I_CORN_BAIT, Ids.I_BINOCULARS]})
	rig.player.health = 10.0
	rig.advance(1.5)
	_check("medkit_off_not_carried", not rig.seen(Ids.I_MEDKIT))
	await _free_rig(rig)
	rig = _make_rig({})
	rig.player.health = 40.0
	_check("kit_use_starts", rig.items.use_item(Ids.I_MEDKIT) and rig.items.is_busy())
	rig.advance(1.0)   # the use takes use_time_s (1.5): busy for the first evaluations
	_check("medkit_off_while_busy", not rig.seen(Ids.I_MEDKIT), str(rig.shown_names()))
	await _free_rig(rig)

	# Dog: no dog, dog not following, boar not seen.
	rig = _make_rig({"dog": false})
	rig.world.boars[1] = IN_FRONT
	rig.advance(1.5)
	_check("dog_off_without_dog", not rig.seen(Quickbar.DOG_SLOT))
	await _free_rig(rig)
	for state: StringName in [Ids.DS_SEEK, Ids.DS_POINT, Ids.DS_RETREAT]:
		rig = _make_rig({"dog": true})
		rig.world.dog_state = state
		rig.world.boars[1] = IN_FRONT
		rig.advance(1.5)
		_check("dog_off_when_%s" % state, not rig.seen(Quickbar.DOG_SLOT))
		await _free_rig(rig)
	rig = _make_rig({"dog": true})
	rig.advance(1.5)
	_check("dog_off_without_boars", not rig.seen(Quickbar.DOG_SLOT))
	await _free_rig(rig)

	# Drone: not carried, none left, no living boar.
	rig = _make_rig({"items": [Ids.I_MEDKIT]})
	rig.world.boars[1] = BEHIND
	rig.advance(65.0)
	_check("drone_off_not_carried", not rig.seen(Ids.I_SCOUT_DRONE))
	await _free_rig(rig)
	rig = _make_rig({"counts": {Ids.I_MEDKIT: 2, Ids.I_CORN_BAIT: 1, Ids.I_SCOUT_DRONE: 0}})
	rig.world.boars[1] = BEHIND
	rig.advance(65.0)
	_check("drone_off_without_stock", not rig.seen(Ids.I_SCOUT_DRONE))
	await _free_rig(rig)
	rig = _make_rig({})
	rig.advance(65.0)
	_check("drone_off_without_living_boars", not rig.seen(Ids.I_SCOUT_DRONE))
	await _free_rig(rig)

	# Bait: no attack, attack that ended, none left, not carried.
	rig = _make_rig({})
	rig.advance(1.5)
	_check("bait_off_without_attack", not rig.seen(Ids.I_CORN_BAIT))
	GameEvents.crop_under_attack.emit(true)
	GameEvents.crop_under_attack.emit(false)
	rig.advance(1.0)
	_check("bait_off_when_attack_ended", not rig.seen(Ids.I_CORN_BAIT))
	await _free_rig(rig)
	rig = _make_rig({"counts": {Ids.I_MEDKIT: 2, Ids.I_CORN_BAIT: 0, Ids.I_SCOUT_DRONE: 1}})
	GameEvents.crop_under_attack.emit(true)
	rig.advance(1.5)
	_check("bait_off_without_stock", not rig.seen(Ids.I_CORN_BAIT))
	await _free_rig(rig)
	rig = _make_rig({"items": [Ids.I_MEDKIT]})
	GameEvents.crop_under_attack.emit(true)
	rig.advance(1.5)
	_check("bait_off_not_carried", not rig.seen(Ids.I_CORN_BAIT))
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)

	# Nothing is evaluated before hunt_started.
	rig = _make_rig({"start": false})
	rig.player.health = 10.0
	rig.advance(5.0)
	_check("nothing_before_hunt_started", rig.shown.is_empty(), str(rig.shown_names()))
	GameEvents.hunt_started.emit(rig.request)
	rig.advance(0.6)
	_check("fires_after_hunt_started", rig.count_shown(Ids.I_MEDKIT) == 1)
	await _free_rig(rig)


# ---------------------------------------------------------------------------
# "Sighted" criterion
# ---------------------------------------------------------------------------

func _test_sighting() -> void:
	InputSetup.set_touch_override("off")
	var range_m: float = float(_cfg["boar_sighted_range_m"])
	var half_deg: float = float(_cfg["boar_sighted_half_angle_deg"])
	var cases: Array[Dictionary] = [
		{"name": "ahead_in_range", "pos": Vector3(0.0, 0.0, -range_m + 1.0), "want": true},
		{"name": "beyond_range", "pos": Vector3(0.0, 0.0, -range_m - 1.0), "want": false},
		{"name": "inside_cone", "pos": _polar(20.0, half_deg - 5.0), "want": true},
		{"name": "outside_cone", "pos": _polar(20.0, half_deg + 5.0), "want": false},
		{"name": "behind", "pos": BEHIND, "want": false},
		{"name": "on_top_of_hunter", "pos": Vector3(0.0, 0.0, 0.0), "want": true},
	]
	for case: Dictionary in cases:
		var rig: Rig = _make_rig({"dog": true})
		rig.world.boars[1] = case["pos"]
		rig.advance(1.5)
		var fired: bool = rig.count_shown(Quickbar.DOG_SLOT) == 1
		_check("sighted_%s" % case["name"], fired == bool(case["want"]), "fired=%s" % fired)
		await _free_rig(rig)
	# The gaze turns: a boar behind becomes sighted when the hunter looks at it.
	var rig2: Rig = _make_rig({"dog": true})
	rig2.world.boars[1] = BEHIND
	rig2.advance(1.0)
	rig2.player.look = Vector3(0.0, 0.0, 1.0)
	rig2.advance(0.6)
	_check("sighted_follows_the_gaze", rig2.count_shown(Quickbar.DOG_SLOT) == 1)
	await _free_rig(rig2)
	# A dead boar does not count (it left the living list).
	var rig3: Rig = _make_rig({"dog": true})
	rig3.world.boars[1] = IN_FRONT
	rig3.world.boars.erase(1)
	rig3.advance(1.5)
	_check("sighted_ignores_dead_boars", rig3.count_shown(Quickbar.DOG_SLOT) == 0)
	await _free_rig(rig3)


## A point `dist` metres from the hunter, `deg` degrees to the right of the gaze (-Z).
func _polar(dist: float, deg: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(sin(a) * dist, 0.0, -cos(a) * dist)


# ---------------------------------------------------------------------------
# Drone clock
# ---------------------------------------------------------------------------

func _test_drone_clock() -> void:
	InputSetup.set_touch_override("off")
	var wait_s: float = float(_cfg["drone_no_sighting_s"])
	# Counted from hunt_started.
	var rig: Rig = _make_rig({"items": [Ids.I_SCOUT_DRONE, Ids.I_BINOCULARS]})
	rig.world.boars[1] = BEHIND
	rig.advance(wait_s - 1.0)
	_check("drone_waits_the_full_time", not rig.seen(Ids.I_SCOUT_DRONE), "t=%.1f" % rig.t)
	rig.advance(1.6)
	var entry: Dictionary = rig.entry_of(Ids.I_SCOUT_DRONE)
	_check("drone_fires_after_no_sighting_s", not entry.is_empty() and float(entry["t"]) >= wait_s - 0.01
		and float(entry["t"]) <= wait_s + float(_cfg["eval_interval_s"]) + 0.15, str(entry.get("t")))
	await _free_rig(rig)
	# A sighting restarts the count.
	rig = _make_rig({"items": [Ids.I_SCOUT_DRONE, Ids.I_BINOCULARS]})
	rig.world.boars[1] = BEHIND
	rig.advance(50.0)
	rig.world.boars[2] = IN_FRONT
	rig.advance(0.6)
	rig.world.boars.erase(2)
	rig.advance(wait_s - 5.0)   # t about 105: more than wait_s since the start, less since the sighting
	_check("drone_count_restarts_on_sighting", not rig.seen(Ids.I_SCOUT_DRONE), "t=%.1f" % rig.t)
	rig.advance(7.0)
	var late: Dictionary = rig.entry_of(Ids.I_SCOUT_DRONE)
	_check("drone_fires_after_the_new_count", not late.is_empty() and float(late["t"]) >= 50.0 + wait_s - 0.5,
		str(late.get("t")))
	await _free_rig(rig)


# ---------------------------------------------------------------------------
# Queue
# ---------------------------------------------------------------------------

## Default queue_max: the medkit jumps the queue; everything shows one at a time, each once.
func _test_queue_default() -> void:
	InputSetup.set_touch_override("off")
	var rig: Rig = _make_rig({"dog": true})
	GameEvents.crop_under_attack.emit(true)
	rig.advance(0.4)
	_check("queue_first_is_current", rig.director.get_current_hint() == Ids.I_CORN_BAIT, String(rig.director.get_current_hint()))
	rig.world.boars[1] = IN_FRONT
	rig.advance(0.4)
	_check("queue_waits_behind_current", rig.queue_names() == ["dog_command"], str(rig.queue_names()))
	rig.advance(1.6)   # the opening falls due
	_check("queue_appends_in_order", rig.queue_names() == ["dog_command", "opening"], str(rig.queue_names()))
	rig.player.health = 40.0
	rig.advance(0.3)
	_check("medkit_jumps_the_queue", rig.queue_names() == ["medkit", "dog_command", "opening"], str(rig.queue_names()))
	_check("one_at_a_time_current", rig.director.get_current_hint() == Ids.I_CORN_BAIT)
	rig.advance(80.0)
	var names: Array = rig.shown_names()
	_check("queue_order_of_appearance", names == ["corn_bait", "medkit", "dog_command", "opening"], str(names))
	var once: bool = true
	for hint_id: StringName in rig.director.get_shown_this_hunt():
		once = once and rig.count_shown(hint_id) == 1
	_check("each_id_once_per_hunt", once and names.size() == 4, str(names))
	_check("queue_never_above_max", rig.max_queue <= int(_cfg["queue_max"]), "max %d" % rig.max_queue)
	# One at a time: the shows never overlap (a hide always comes before the next show) and respect the gap.
	var gap: float = float(_cfg["hint_gap_s"])
	var spaced: bool = true
	for i: int in range(rig.shown.size() - 1):
		var hid: float = rig.hidden_at(rig.shown[i]["id"])
		var next_t: float = float(rig.shown[i + 1]["t"])
		spaced = spaced and hid >= 0.0 and next_t - hid >= gap - 0.06
	_check("shows_do_not_overlap_and_keep_the_gap", spaced)
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)


## queue_max = 2: a full queue ignores the newcomer; the medkit pushes the last one out.
func _test_queue_limit() -> void:
	InputSetup.set_touch_override("off")
	var rig: Rig = _make_rig({"dog": true, "queue_max": 2})
	GameEvents.crop_under_attack.emit(true)
	rig.advance(0.4)
	rig.world.boars[1] = IN_FRONT
	rig.advance(0.4)
	_check("limit_queue_has_dog", rig.queue_names() == ["dog_command"], str(rig.queue_names()))
	rig.advance(1.4)   # t = 2.2: the opening falls due, the queue is [dog, opening] = full
	_check("limit_queue_full", rig.queue_names() == ["dog_command", "opening"], str(rig.queue_names()))
	rig.player.health = 40.0
	rig.advance(0.3)
	_check("limit_medkit_pushes_the_last_out", rig.queue_names() == ["medkit", "dog_command"], str(rig.queue_names()))
	_check("limit_pushed_out_is_not_shown", rig.count_shown(HintDirector.OPENING) == 0)
	rig.advance(2.0)
	_check("limit_never_above_max", rig.max_queue <= 2, "max %d" % rig.max_queue)
	rig.advance(80.0)
	# The pushed-out opening fires again once there is room, and everything still shows once.
	_check("limit_all_shown_once", rig.shown_names() == ["corn_bait", "medkit", "dog_command", "opening"], str(rig.shown_names()))
	_check("limit_max_after_all", rig.max_queue <= 2, "max %d" % rig.max_queue)
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)


## A waiting hint is evaluated again before it shows: a stale one is dropped and does not count as shown.
func _test_reevaluation() -> void:
	InputSetup.set_touch_override("off")
	var rig: Rig = _make_rig({"dog": true})
	GameEvents.crop_under_attack.emit(true)
	rig.advance(0.4)
	rig.world.boars[1] = IN_FRONT
	rig.advance(0.4)
	_check("reeval_dog_waiting", rig.queue_names() == ["dog_command"], str(rig.queue_names()))
	rig.world.boars.clear()   # the boar is gone before the dog hint gets its turn
	rig.advance(7.5)          # the bait hint ends, the gap passes, the dog hint is reevaluated and dropped
	_check("reeval_stale_is_dropped", rig.count_shown(Quickbar.DOG_SLOT) == 0, str(rig.shown_names()))
	_check("reeval_next_one_shows", rig.shown_names() == ["corn_bait", "opening"], str(rig.shown_names()))
	rig.world.boars[1] = IN_FRONT   # it can fire again later: it was not counted as shown
	rig.advance(15.0)
	_check("reeval_dropped_can_fire_later", rig.count_shown(Quickbar.DOG_SLOT) == 1, str(rig.shown_names()))
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)


# ---------------------------------------------------------------------------
# Learned
# ---------------------------------------------------------------------------

func _test_learned() -> void:
	InputSetup.set_touch_override("off")
	# A learned id never enters the queue.
	var rig: Rig = _make_rig({"dog": true, "learned": ["medkit", "dog_command", "corn_bait", "scout_drone"]})
	rig.player.health = 10.0
	rig.world.boars[1] = IN_FRONT
	GameEvents.crop_under_attack.emit(true)
	rig.advance(65.0)
	_check("learned_never_appears", rig.shown_names() == ["opening"], str(rig.shown_names()))
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)

	# Using the item hides the hint at once and learns it.
	rig = _make_rig({})
	rig.player.health = 40.0
	rig.advance(0.6)
	_check("learn_medkit_hint_on", rig.director.get_current_hint() == Ids.I_MEDKIT)
	GameEvents.item_used.emit(Ids.I_MEDKIT, Vector3.ZERO)
	_check("learn_item_used_hides_at_once", rig.director.get_current_hint() == NO_ID and rig.hidden_at(Ids.I_MEDKIT) >= 0.0)
	_check("learn_item_used_marks_learned", Profile.is_hint_learned(Ids.I_MEDKIT))
	rig.advance(15.0)
	_check("learn_does_not_come_back", rig.count_shown(Ids.I_MEDKIT) == 1)
	await _free_rig(rig)

	# The real kit: the hint goes when the use starts, the learning comes when the kit works.
	rig = _make_rig({})
	rig.player.health = 40.0
	rig.advance(0.6)
	_check("kit_use_hint_on", rig.director.get_current_hint() == Ids.I_MEDKIT)
	_check("kit_use_started", rig.items.use_item(Ids.I_MEDKIT))
	_check("kit_use_hides_hint_at_once", rig.director.get_current_hint() == NO_ID)
	_check("kit_not_learned_before_it_works", not Profile.is_hint_learned(Ids.I_MEDKIT))
	rig.advance(float(Data.get_equipment(Ids.I_MEDKIT).get("effect", {}).get("use_time_s", 1.5)) + 0.2)
	_check("kit_learned_when_it_works", Profile.is_hint_learned(Ids.I_MEDKIT))
	await _free_rig(rig)

	# Each consumable and the dog commands.
	for item_id: StringName in [Ids.I_CORN_BAIT, Ids.I_SCOUT_DRONE]:
		rig = _make_rig({})
		rig.advance(_arrange(rig, item_id))
		_check("learn_%s_hint_on" % item_id, rig.director.get_current_hint() == item_id)
		GameEvents.item_used.emit(item_id, Vector3.ZERO)
		_check("learn_%s_hides_and_marks" % item_id, rig.director.get_current_hint() == NO_ID
			and Profile.is_hint_learned(item_id))
		await _free_rig(rig)
		GameEvents.crop_under_attack.emit(false)
	for command: StringName in [Ids.CMD_ATTACK, Ids.CMD_RECALL]:
		rig = _make_rig({"dog": true})
		rig.world.boars[1] = IN_FRONT
		rig.advance(0.6)
		_check("learn_dog_%s_hint_on" % command, rig.director.get_current_hint() == Quickbar.DOG_SLOT)
		GameEvents.dog_command_executed.emit(command)
		_check("learn_dog_%s_hides_and_marks" % command, rig.director.get_current_hint() == NO_ID
			and Profile.is_hint_learned(Quickbar.DOG_SLOT))
		await _free_rig(rig)

	# Learned without the hint ever showing: it leaves the queue and does not show later.
	rig = _make_rig({"dog": true})
	GameEvents.crop_under_attack.emit(true)
	rig.advance(0.4)   # the bait hint is current
	rig.player.health = 40.0
	rig.advance(0.4)
	_check("learn_queue_has_medkit", rig.queue_names() == ["medkit"], str(rig.queue_names()))
	GameEvents.item_used.emit(Ids.I_MEDKIT, Vector3.ZERO)
	_check("learn_leaves_the_queue", rig.queue_names().is_empty() and Profile.is_hint_learned(Ids.I_MEDKIT))
	rig.advance(10.0)
	_check("learn_queued_never_shows", rig.count_shown(Ids.I_MEDKIT) == 0)
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)

	# Items outside the three consumables do not teach anything.
	rig = _make_rig({})
	GameEvents.item_used.emit(Ids.I_BINOCULARS, Vector3.ZERO)
	_check("learn_ignores_other_items", not Profile.is_hint_learned(Ids.I_MEDKIT) and not Profile.is_hint_learned(Ids.I_CORN_BAIT))
	await _free_rig(rig)


# ---------------------------------------------------------------------------
# Inactive after the first hunts
# ---------------------------------------------------------------------------

func _test_inactive() -> void:
	InputSetup.set_touch_override("off")
	var max_hunts: int = int(_cfg["max_hunts"])
	var rig: Rig = _make_rig({"hunts": max_hunts - 1})
	_check("active_before_max_hunts", rig.director.is_active() and Profile.is_onboarding_active())
	await _free_rig(rig)

	var watched: Array[Signal] = [GameEvents.hunt_started, GameEvents.item_used, GameEvents.crop_under_attack,
		GameEvents.dog_command_executed, GameEvents.hunt_ended, GameEvents.player_died, GameEvents.spectate_changed]
	var before: Array[int] = []
	for sig: Signal in watched:
		before.append(sig.get_connections().size())
	rig = _make_rig({"hunts": max_hunts, "dog": true, "start": false})
	var after: Array[int] = []
	for sig: Signal in watched:
		after.append(sig.get_connections().size())
	_check("inactive_is_active_false", not rig.director.is_active() and not Profile.is_onboarding_active())
	_check("inactive_connects_nothing", before == after, "%s -> %s" % [before, after])
	_check("inactive_does_not_process", not rig.director.is_processing())
	GameEvents.hunt_started.emit(rig.request)
	rig.player.health = 10.0
	rig.world.boars[1] = IN_FRONT
	GameEvents.crop_under_attack.emit(true)
	rig.advance(70.0)
	_check("inactive_no_signal", rig.shown.is_empty() and rig.hidden.is_empty(), str(rig.shown_names()))
	_check("inactive_empty_state", rig.director.get_current_hint() == NO_ID and rig.director.get_queue().is_empty()
		and rig.director.get_shown_this_hunt().is_empty())
	GameEvents.item_used.emit(Ids.I_MEDKIT, Vector3.ZERO)
	GameEvents.dog_command_executed.emit(Ids.CMD_ATTACK)
	_check("inactive_writes_nothing", not Profile.is_hint_learned(Ids.I_MEDKIT) and not Profile.is_hint_learned(Quickbar.DOG_SLOT))
	await _free_rig(rig)
	GameEvents.crop_under_attack.emit(false)


# ---------------------------------------------------------------------------
# End of the hunt
# ---------------------------------------------------------------------------

## Medkit on screen, dog and bait waiting.
func _rig_with_queue() -> Rig:
	var rig: Rig = _make_rig({"dog": true})
	GameEvents.crop_under_attack.emit(true)
	rig.world.boars[1] = IN_FRONT
	rig.player.health = 40.0
	rig.advance(0.6)
	return rig


func _test_end_of_hunt() -> void:
	InputSetup.set_touch_override("off")
	var enders: Array[Dictionary] = [
		{"name": "player_died", "fire": func() -> void: GameEvents.player_died.emit()},
		{"name": "hunt_ended", "fire": func() -> void: GameEvents.hunt_ended.emit(HuntResult.new())},
		{"name": "spectate_changed", "fire": func() -> void: GameEvents.spectate_changed.emit(1)},
	]
	for ender: Dictionary in enders:
		var rig: Rig = _rig_with_queue()
		_check("end_%s_setup" % ender["name"], rig.director.get_current_hint() == Ids.I_MEDKIT and rig.queue_names().size() == 2,
			"%s %s" % [rig.director.get_current_hint(), rig.queue_names()])
		var fire: Callable = ender["fire"]
		fire.call()
		_check("end_%s_hides_and_clears" % ender["name"], rig.director.get_current_hint() == NO_ID
			and rig.hidden_at(Ids.I_MEDKIT) >= 0.0 and rig.queue_names().is_empty())
		var count: int = rig.shown.size()
		rig.advance(30.0)
		_check("end_%s_nothing_new" % ender["name"], rig.shown.size() == count, str(rig.shown_names()))
		await _free_rig(rig)
		GameEvents.crop_under_attack.emit(false)
	# Letting go of the spectator camera is not an end.
	var rig2: Rig = _rig_with_queue()
	GameEvents.spectate_changed.emit(-1)
	_check("spectate_released_is_not_an_end", rig2.director.get_current_hint() == Ids.I_MEDKIT)
	await _free_rig(rig2)
	GameEvents.crop_under_attack.emit(false)
	# Hunter down or hunt over without the event yet: nothing new is evaluated.
	var rig3: Rig = _make_rig({"dog": true})
	rig3.player.alive = false
	rig3.player.health = 0.0
	rig3.world.boars[1] = IN_FRONT
	rig3.advance(6.0)
	_check("dead_hunter_gets_no_hint", rig3.shown.is_empty(), str(rig3.shown_names()))
	await _free_rig(rig3)
	var rig4: Rig = _make_rig({"dog": true})
	rig4.world.over = true
	rig4.world.boars[1] = IN_FRONT
	rig4.advance(6.0)
	_check("finished_hunt_gets_no_hint", rig4.shown.is_empty(), str(rig4.shown_names()))
	await _free_rig(rig4)


# ---------------------------------------------------------------------------
# Hud: banner, blinking slot, real Player and SandboxWorld
# ---------------------------------------------------------------------------

func _hud_of(world: SandboxWorld) -> Hud:
	for child: Node in world.player.get_children():
		if child is Hud:
			return child as Hud
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _slot_flashing(hud: Hud, slot_id: StringName) -> bool:
	var slot: Node = hud.find_child("Slot_" + String(slot_id), true, false)
	return slot != null and bool(slot.get("flashing"))


func _touch_flashing(hud: Hud, slot_id: StringName) -> bool:
	var touch: TouchControls = hud.find_child("TouchControls", true, false) as TouchControls
	var flashing: Dictionary = touch.get("_flashing")
	return flashing.has(slot_id)


func _make_world(hunts_played: int, dog: bool) -> SandboxWorld:
	_prepare_profile(hunts_played)
	var world: SandboxWorld = SandboxWorld.new()
	world.dog_present = dog
	add_child(world)
	await get_tree().process_frame
	return world


func _test_hud_integration() -> void:
	# Desktop: opening on the banner, then the kit with the slot blinking; using it hides everything.
	InputSetup.set_touch_override("off")
	var world: SandboxWorld = await _make_world(0, true)
	var hud: Hud = _hud_of(world)
	_check("hud_found", hud != null)
	if hud == null:
		return
	var banner: HintBanner = hud.find_child("HintBanner", true, false) as HintBanner
	var director: HintDirector = hud.find_child("HintDirector", true, false) as HintDirector
	_check("hud_has_banner_and_director", banner != null and director != null and director.is_active())
	_check("hud_banner_is_under_root", banner != null and banner.get_parent() == hud.find_child("Root", false, false))
	_check("hud_banner_anchors", banner != null and is_equal_approx(banner.anchor_left, HintBanner.ANCHOR_CENTER_X) and is_equal_approx(banner.anchor_right, HintBanner.ANCHOR_CENTER_X)
		and is_equal_approx(banner.anchor_top, 0.30) and is_equal_approx(banner.anchor_bottom, 0.37)
		and banner.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("hud_banner_hidden_at_start", not banner.is_showing() and not banner.visible)
	# The sandbox has a target 10 m ahead and a dog: the dog hint comes first (a boar is in sight).
	await _wait(0.5)
	_check("hud_dog_hint_banner", banner.is_showing() and banner.get_text() == TEXTS_DESKTOP["dog_command"], banner.get_text())
	_check("hud_dog_slot_blinks", _slot_flashing(hud, Quickbar.DOG_SLOT) and _touch_flashing(hud, Quickbar.DOG_SLOT))
	world.player.apply_damage(90.0, Vector3(0.0, 0.0, 10.0))
	await _wait(0.5)
	_check("hud_player_hurt", world.player.get_health() < 50.0, "hp %.0f" % world.player.get_health())
	# The dog hint is current; the kit waits and jumps ahead of the opening.
	_check("hud_one_at_a_time", director.get_current_hint() == Quickbar.DOG_SLOT and director.get_queue().size() >= 1
		and director.get_queue()[0] == Ids.I_MEDKIT, "%s %s" % [director.get_current_hint(), director.get_queue()])
	GameEvents.dog_command_executed.emit(Ids.CMD_ATTACK)   # the hunter orders the dog: its hint goes away at once
	_check("hud_dog_order_hides_banner", not banner.is_showing() and not _slot_flashing(hud, Quickbar.DOG_SLOT)
		and not _touch_flashing(hud, Quickbar.DOG_SLOT))
	await _wait(float(_cfg["hint_gap_s"]) + 0.5)
	_check("hud_kit_hint_banner", banner.is_showing() and banner.get_text() == TEXTS_DESKTOP["medkit"], banner.get_text())
	_check("hud_kit_slot_blinks", _slot_flashing(hud, Ids.I_MEDKIT) and _touch_flashing(hud, Ids.I_MEDKIT))
	_check("hud_kit_hint_in_director", director.get_current_hint() == Ids.I_MEDKIT)
	var items: ItemBelt = world.player.get_items()
	items.use_item(Ids.I_MEDKIT)
	_check("hud_use_hides_banner_and_blink", not banner.is_showing() and not _slot_flashing(hud, Ids.I_MEDKIT)
		and not _touch_flashing(hud, Ids.I_MEDKIT))
	await _wait(0.4)
	_check("hud_banner_fades_out", not banner.visible)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Opening on screen after opening_delay_s.
	world = await _make_world(0, false)
	hud = _hud_of(world)
	banner = hud.find_child("HintBanner", true, false) as HintBanner
	await _wait(float(_cfg["opening_delay_s"]) + 0.6)
	_check("hud_opening_banner", banner.is_showing() and banner.get_text() == OPENING_TEXT, banner.get_text())
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Touch: the same hint with the button name, the touch button blinks.
	InputSetup.set_touch_override("on")
	world = await _make_world(0, true)
	world.player.apply_damage(90.0, Vector3(0.0, 0.0, 10.0))
	GameEvents.dog_command_executed.emit(Ids.CMD_ATTACK)   # clear the dog hint (a boar is ahead) so the kit shows
	hud = _hud_of(world)
	banner = hud.find_child("HintBanner", true, false) as HintBanner
	await _wait(0.8)
	_check("hud_touch_kit_banner", banner.is_showing() and banner.get_text() == TEXTS_TOUCH["medkit"], banner.get_text())
	_check("hud_touch_kit_blinks", _touch_flashing(hud, Ids.I_MEDKIT))
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# After the first hunts the Hud shows nothing.
	InputSetup.set_touch_override("off")
	world = await _make_world(int(_cfg["max_hunts"]), true)
	world.player.apply_damage(90.0, Vector3(0.0, 0.0, 10.0))
	hud = _hud_of(world)
	banner = hud.find_child("HintBanner", true, false) as HintBanner
	director = hud.find_child("HintDirector", true, false) as HintDirector
	await _wait(float(_cfg["opening_delay_s"]) + 0.8)
	_check("hud_inactive_after_max_hunts", not director.is_active() and not banner.is_showing() and not banner.visible
		and director.get_current_hint() == NO_ID)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Screenshot mode
# ---------------------------------------------------------------------------

## kit | dog | opening | bar. Extra user args reach the SandboxWorld (--touch=on, --items=a,b ...).
func _run_demo(kind: String) -> void:
	get_tree().create_timer(DEMO_WATCHDOG_S).timeout.connect(get_tree().quit)
	_prepare_profile(3 if kind == "bar" else 0)
	var world: SandboxWorld = SandboxWorld.new()
	world.dog_present = kind != "opening"
	add_child(world)
	await get_tree().process_frame
	if kind == "kit":
		world.player.apply_damage(90.0, Vector3(0.0, 0.0, 10.0))
