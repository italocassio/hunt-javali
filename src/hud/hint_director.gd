class_name HintDirector
extends Node
## Logic of the contextual hints of the first hunts (docs §8.4, "Dicas das primeiras caçadas"). No Control in here:
## it decides which hint is on screen and for how long, and the Hud turns hint_shown / hint_hidden into the banner
## text and the blinking slot. One hint at a time, a short queue, each id at most once per hunt, and a hint the
## hunter has already learned (used the item, ordered the dog) never comes back. Local only: nothing goes on the net.
##
## Inactive (Profile.is_onboarding_active() false at setup): connects nothing, never processes, never writes.

signal hint_shown(hint_id: StringName, text: String, slot_id: StringName)
signal hint_hidden(hint_id: StringName)

const OPENING: StringName = &"opening"
const MEDKIT: StringName = Ids.I_MEDKIT
const CORN_BAIT: StringName = Ids.I_CORN_BAIT
const SCOUT_DRONE: StringName = Ids.I_SCOUT_DRONE
const DOG_COMMAND: StringName = Quickbar.DOG_SLOT
const LEARNABLE_ITEMS: Array[StringName] = [MEDKIT, CORN_BAIT, SCOUT_DRONE]
## Order in which triggers are tried inside one evaluation (the medkit still jumps the queue).
const TRIGGER_ORDER: Array[StringName] = [OPENING, MEDKIT, DOG_COMMAND, SCOUT_DRONE, CORN_BAIT]
const NO_HINT: StringName = &""
const FULL_PCT: float = 100.0

## Player-facing text (docs §8.4). "%s" is the key label of the action. Touch mode has no key.
const TEXT_KEYS: Dictionary = {
	"opening": "Seus itens ficam na barra embaixo. Aperte a tecla de cada um para usar.",
	"medkit": "%s: Curar",
	"dog_command": "%s: Mandar o cão atacar",
	"scout_drone": "%s: Drone revela os javalis no minimapa",
	"corn_bait": "%s: Ceva atrai os javalis para longe da lavoura",
}
const TEXT_KEYS_HORDE_BAIT: String = "%s: Ceva atrai os javalis para longe do celeiro"
const TEXT_TOUCH: Dictionary = {
	"opening": "Cada item tem o seu botão. Toque nele para usar.",
	"medkit": "Toque no kit para curar",
	"dog_command": "Toque em Cão para mandar o cão atacar",
	"scout_drone": "Toque no drone: ele revela os javalis no minimapa",
	"corn_bait": "Toque na ceva para atrair os javalis para longe da lavoura",
}
const TEXT_TOUCH_HORDE_BAIT: String = "Toque na ceva para atrair os javalis para longe do celeiro"

var _active: bool = false
var _player: PlayerBase = null
var _items: ItemBelt = null
var _world: HuntWorld = null

# game.onboarding, read once in setup
var _eval_interval_s: float = 0.25
var _opening_delay_s: float = 2.0
var _opening_duration_s: float = 6.0
var _hint_duration_s: float = 5.0
var _hint_gap_s: float = 1.5
var _queue_max: int = 3
var _medkit_below_pct: float = 50.0
var _sighted_range_m: float = 60.0
var _sighted_cos_half: float = 0.0
var _drone_no_sighting_s: float = 60.0

var _clock_s: float = 0.0              # own clock, by delta: a paused tree does not advance it
var _started: bool = false             # hunt_started seen
var _finished: bool = false            # hunt over, hunter down or spectating: nothing more to show
var _start_s: float = 0.0
var _last_sighting_s: float = 0.0
var _eval_left_s: float = 0.0
var _gap_left_s: float = 0.0
var _current: StringName = NO_HINT
var _current_left_s: float = 0.0
var _queue: Array[StringName] = []
var _shown: Array[StringName] = []
var _crop_attack: bool = false
var _alive_ids: PackedInt32Array = PackedInt32Array()   # snapshot of the evaluation in course
var _sighted: bool = false


func _init() -> void:
	name = "HintDirector"
	set_process(false)


## Reads Profile.is_onboarding_active() and game.onboarding once. Inactive: connects nothing.
func setup(player: PlayerBase, items: ItemBelt, world: HuntWorld) -> void:
	_player = player
	_items = items
	_world = world
	_active = player != null and world != null and Profile.is_onboarding_active()
	if not _active:
		set_process(false)
		return
	var cfg: Dictionary = Data.get_game().get("onboarding", {})
	_eval_interval_s = float(cfg.get("eval_interval_s", _eval_interval_s))
	_opening_delay_s = float(cfg.get("opening_delay_s", _opening_delay_s))
	_opening_duration_s = float(cfg.get("opening_duration_s", _opening_duration_s))
	_hint_duration_s = float(cfg.get("hint_duration_s", _hint_duration_s))
	_hint_gap_s = float(cfg.get("hint_gap_s", _hint_gap_s))
	_queue_max = int(cfg.get("queue_max", _queue_max))
	_medkit_below_pct = float(cfg.get("medkit_health_below_pct", _medkit_below_pct))
	_sighted_range_m = float(cfg.get("boar_sighted_range_m", _sighted_range_m))
	_sighted_cos_half = cos(deg_to_rad(float(cfg.get("boar_sighted_half_angle_deg", 35.0))))
	_drone_no_sighting_s = float(cfg.get("drone_no_sighting_s", _drone_no_sighting_s))
	_connect(GameEvents.hunt_started, _on_hunt_started)
	_connect(GameEvents.item_used, _on_item_used)
	_connect(GameEvents.crop_under_attack, _on_crop_attack)
	_connect(GameEvents.dog_command_executed, _on_dog_command)
	_connect(GameEvents.hunt_ended, _on_hunt_ended)
	_connect(GameEvents.player_died, _on_player_died)
	_connect(GameEvents.spectate_changed, _on_spectate_changed)
	if _items != null:
		_connect(_items.use_started, _on_use_started)
	set_process(true)


func is_active() -> bool:
	return _active


## The hint on screen now; &"" = none.
func get_current_hint() -> StringName:
	return _current


## Copy of the waiting ids, next one first (tests).
func get_queue() -> Array[StringName]:
	return _queue.duplicate()


## Copy of the ids already shown in this hunt, in the order they appeared (tests).
func get_shown_this_hunt() -> Array[StringName]:
	return _shown.duplicate()


func _connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


# ---------------------------------------------------------------------------
# Clock
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock_s += delta
	if not _started or _finished:
		return
	if _current != NO_HINT:
		_current_left_s -= delta
		if _current_left_s <= 0.0:
			_hide_current()
	elif _gap_left_s > 0.0:
		_gap_left_s -= delta
	_eval_left_s -= delta
	if _eval_left_s <= 0.0:
		_eval_left_s = _eval_interval_s
		if _can_evaluate():
			_evaluate()
	elif _current == NO_HINT and _gap_left_s <= 0.0 and not _queue.is_empty() and _can_evaluate():
		_pump_queue(false)   # the gap ended between two evaluations: do not wait for the next one


func _can_evaluate() -> bool:
	return is_instance_valid(_player) and _player.is_alive() and not _world.is_hunt_over()


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

func _evaluate() -> void:
	_refresh_snapshot()
	for hint_id: StringName in TRIGGER_ORDER:
		if _is_candidate(hint_id) and _condition_holds(hint_id):
			_enqueue(hint_id)
	_pump_queue(true)


## One PackedInt32Array per evaluation (the only allocation) and the sighting that depends on it.
func _refresh_snapshot() -> void:
	_alive_ids = _world.get_alive_boar_ids()
	_sighted = _boar_sighted()
	if _sighted:
		_last_sighting_s = _clock_s


## Cheap sighting (docs §8.4): a living boar within range and inside the half-angle of the gaze, on the XZ plane.
## No line-of-sight ray: a boar behind a tree counts as sighted, which is fine for a hint.
func _boar_sighted() -> bool:
	var look: Vector3 = _player.get_look_direction()
	var gaze: Vector2 = Vector2(look.x, look.z)
	if gaze.length_squared() < 0.0001:
		return false   # looking straight up or down: no heading on the ground
	gaze = gaze.normalized()
	var origin: Vector3 = _player.global_position
	var range_sq: float = _sighted_range_m * _sighted_range_m
	for boar_id: int in _alive_ids:
		var pos: Vector3 = _world.get_boar_position(boar_id)
		if not pos.is_finite():
			continue
		var offset: Vector2 = Vector2(pos.x - origin.x, pos.z - origin.z)
		var dist_sq: float = offset.length_squared()
		if dist_sq > range_sq:
			continue
		if dist_sq < 0.0001 or offset.normalized().dot(gaze) >= _sighted_cos_half:
			return true
	return false


## True when the hint may enter the queue: not learned, not waiting, not on screen, not shown yet in this hunt.
func _is_candidate(hint_id: StringName) -> bool:
	if hint_id == _current or _queue.has(hint_id) or _shown.has(hint_id):
		return false
	return hint_id == OPENING or not Profile.is_hint_learned(hint_id)


## The trigger table of docs §8.4 against the current snapshot.
func _condition_holds(hint_id: StringName) -> bool:
	match hint_id:
		OPENING:
			return _clock_s - _start_s >= _opening_delay_s and _has_any_slot()
		MEDKIT:
			return _has_stock(MEDKIT) and not _items.is_busy() \
				and _player.get_health() / maxf(_player.get_max_health(), 1.0) * FULL_PCT < _medkit_below_pct
		DOG_COMMAND:
			return _world.has_dog() and _world.get_dog_state() == Ids.DS_FOLLOW and _sighted
		SCOUT_DRONE:
			return _has_stock(SCOUT_DRONE) and not _alive_ids.is_empty() \
				and _clock_s - _last_sighting_s >= _drone_no_sighting_s
		CORN_BAIT:
			return _has_stock(CORN_BAIT) and _crop_attack
	return false


func _has_stock(item_id: StringName) -> bool:
	return _items != null and _items.has_item(item_id) and _items.get_count(item_id) > 0


func _has_any_slot() -> bool:
	return (_items != null and not _items.get_usable_ids().is_empty()) or _world.has_dog()


func _enqueue(hint_id: StringName) -> void:
	if hint_id == MEDKIT:
		_queue.push_front(hint_id)   # the kit jumps the queue; if that overflows, the last one leaves
		if _queue.size() > _queue_max:
			_queue.pop_back()
	elif _queue.size() < _queue_max:
		_queue.append(hint_id)   # full queue: ignored, it fires again on the next evaluation


## Shows the next waiting hint when nothing is on screen and the gap is over. The head is evaluated again first:
## one whose condition no longer holds is dropped without counting as shown.
func _pump_queue(snapshot_fresh: bool) -> void:
	var refreshed: bool = snapshot_fresh
	while _current == NO_HINT and _gap_left_s <= 0.0 and not _queue.is_empty():
		var hint_id: StringName = _queue.pop_front()
		if hint_id != OPENING and Profile.is_hint_learned(hint_id):
			continue
		if not refreshed:
			_refresh_snapshot()
			refreshed = true
		if _condition_holds(hint_id):
			_show(hint_id)


func _show(hint_id: StringName) -> void:
	_current = hint_id
	_current_left_s = _opening_duration_s if hint_id == OPENING else _hint_duration_s
	_shown.append(hint_id)
	var slot_id: StringName = NO_HINT if hint_id == OPENING else hint_id
	hint_shown.emit(hint_id, _text_for(hint_id), slot_id)


func _hide_current() -> void:
	if _current == NO_HINT:
		return
	var hint_id: StringName = _current
	_current = NO_HINT
	_gap_left_s = _hint_gap_s
	hint_hidden.emit(hint_id)


## Text in the mode of the moment (docs §8.4): touch has button names, the keyboard has the key letter.
func _text_for(hint_id: StringName) -> String:
	var key: String = String(hint_id)
	var horde_bait: bool = hint_id == CORN_BAIT and _world.is_horde()
	if InputSetup.is_touch_mode():
		return TEXT_TOUCH_HORDE_BAIT if horde_bait else String(TEXT_TOUCH.get(key, ""))
	var template: String = TEXT_KEYS_HORDE_BAIT if horde_bait else String(TEXT_KEYS.get(key, ""))
	if not template.contains("%s"):
		return template
	var action: StringName = DOG_COMMAND if hint_id == DOG_COMMAND else InputSetup.get_item_action(hint_id)
	return template % InputSetup.get_key_label(action)


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _on_hunt_started(_request: HuntRequest) -> void:
	_started = true
	_start_s = _clock_s
	_last_sighting_s = _clock_s   # the drone's "no boar seen" count starts with the hunt
	_eval_left_s = _eval_interval_s


func _on_crop_attack(active: bool) -> void:
	_crop_attack = active


func _on_item_used(item_id: StringName, _position: Vector3) -> void:
	if LEARNABLE_ITEMS.has(item_id):
		_learn(item_id)


func _on_dog_command(_command: StringName) -> void:
	_learn(DOG_COMMAND)


## The kit takes 1.5 s to work and only then announces item_used: hide its hint when the use begins.
func _on_use_started(item_id: StringName, _duration_s: float) -> void:
	if item_id == _current:
		_hide_current()


## Learned counts even if the hint never showed: it leaves the queue and, if on screen, goes away at once.
func _learn(hint_id: StringName) -> void:
	Profile.mark_hint_learned(hint_id)
	_queue.erase(hint_id)
	if _current == hint_id:
		_hide_current()


func _on_hunt_ended(_result: HuntResult) -> void:
	_finish()


func _on_player_died() -> void:
	_finish()


func _on_spectate_changed(slot: int) -> void:
	if slot >= 0:
		_finish()


func _finish() -> void:
	_finished = true
	_queue.clear()
	_hide_current()
