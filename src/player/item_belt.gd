class_name ItemBelt
extends Node
## Equipment carried into the hunt (docs §8.11): passives (vest, extra ammo, thermal scope),
## the active binoculars and the consumables (medkit, energy drink, corn bait, scout drone).
## A consumable with `use_time_s` > 0 plays a timed gesture: the effect and the spend land at the `effect_at` beat
## (docs/plano_itens_animados.md 2.2).

signal counts_changed()
signal binoculars_changed(active: bool)
signal use_started(item_id: StringName, duration_s: float)
signal use_finished(item_id: StringName)

const MESSAGE_S: float = 2.0
## How far ahead of the hunter the corn bait lands (docs §8.11).
const BAIT_DISTANCE_M: float = 2.0

var damage_reduction: float = 0.0
var reserve_mult: float = 1.0
var thermal_range_m: float = 0.0
var drone_reveal_s: float = 0.0
var stamina_restore_frac: float = 0.0

var _usable: Array[StringName] = []
var _counts: Dictionary = {}          # StringName -> int (consumables only)
var _binoculars_on: bool = false
var _busy_item: StringName = &""
var _busy_left: float = 0.0
var _busy_total_s: float = 0.0
var _busy_beat_s: float = 0.0         # seconds into the gesture at which the effect lands
var _busy_beat_done: bool = false
var _player: PlayerBase = null
var _world: HuntWorld = null


func setup(request: HuntRequest, player: PlayerBase, world: HuntWorld) -> void:
	_player = player
	_world = world
	_usable.clear()
	_counts.clear()
	damage_reduction = 0.0
	reserve_mult = 1.0
	thermal_range_m = 0.0
	stamina_restore_frac = 0.0
	for item_id: StringName in request.item_ids:
		var item_def: Dictionary = Data.get_equipment(item_id)
		if item_def.is_empty():
			continue
		var effect: Dictionary = item_def.get("effect", {})
		match String(item_def.get("kind", "")):
			"passive":
				damage_reduction = maxf(damage_reduction, float(effect.get("damage_reduction", 0.0)))
				reserve_mult = maxf(reserve_mult, float(effect.get("reserve_mult", 1.0)))
				thermal_range_m = maxf(thermal_range_m, float(effect.get("highlight_range_m", 0.0)))
			"active":
				_usable.append(item_id)
			"consumable":
				_usable.append(item_id)
				_counts[item_id] = request.get_item_count(item_id)
				if effect.has("stamina_restore_frac"):
					stamina_restore_frac = maxf(stamina_restore_frac, float(effect.get("stamina_restore_frac", 0.0)))
	# Slot order follows InputSetup.ITEM_ACTIONS (docs §8.11), not the loadout order.
	var ordered: Array[StringName] = []
	for item_id: StringName in InputSetup.ITEM_ACTIONS:
		if _usable.has(item_id):
			ordered.append(item_id)
	for item_id: StringName in _usable:
		if not ordered.has(item_id):
			ordered.append(item_id)   # usable item without an action: still listed, after the others
	_usable = ordered
	counts_changed.emit()


func has_item(item_id: StringName) -> bool:
	return _usable.has(item_id)


## Active + consumable items carried, in the order of InputSetup.ITEM_ACTIONS.
func get_usable_ids() -> Array[StringName]:
	return _usable


## Consumables: remaining count. Active items (binoculars): -1.
func get_count(item_id: StringName) -> int:
	return int(_counts.get(item_id, -1))


func is_busy() -> bool:
	return _busy_left > 0.0


## Item whose gesture is running right now; &"" = none.
func get_busy_item() -> StringName:
	return _busy_item if _busy_left > 0.0 else &""


func get_busy_progress() -> float:
	if _busy_left <= 0.0:
		return 0.0
	var total: float = _busy_total()
	return clampf(1.0 - _busy_left / maxf(total, 0.001), 0.0, 1.0)


func is_binoculars_active() -> bool:
	return _binoculars_on


func get_binoculars_zoom() -> float:
	return float(Data.get_equipment(Ids.I_BINOCULARS).get("effect", {}).get("zoom", 1.0))


func set_binoculars(active: bool) -> void:
	if active and not has_item(Ids.I_BINOCULARS):
		return
	if active == _binoculars_on:
		return
	_binoculars_on = active
	Sfx.play(&"binocular_in")
	binoculars_changed.emit(active)


## The single point of use (docs §8.11). True when the use started or had an effect.
func use_item(item_id: StringName) -> bool:
	if item_id == &"" or not Data.get_equipment_ids().has(item_id):   # unknown: false, no message (§8.11)
		return false
	if not has_item(item_id):
		var def: Dictionary = Data.get_equipment(item_id)
		if String(def.get("kind", "")) in ["active", "consumable"]:
			_message("Você não trouxe este item: %s." % String(def.get("name", "item")))
		return false
	if is_busy():
		return false
	if item_id == Ids.I_BINOCULARS:
		set_binoculars(not _binoculars_on)
		return true
	if int(_counts.get(item_id, 0)) <= 0:
		_message("Acabou: %s." % String(Data.get_equipment(item_id).get("name", "item")))
		return false
	match item_id:
		Ids.I_MEDKIT:
			if _player.get_health() >= _player.get_max_health():
				_message("Sua vida já está cheia.")
				return false
		Ids.I_ENERGY_DRINK:
			var hunter: Player = _player as Player   # stamina lives on Player, not on PlayerBase
			if hunter == null:
				return false
			if hunter.get_stamina_frac() >= 1.0:
				_message("Seu fôlego já está cheio.")
				return false
		Ids.I_CORN_BAIT, Ids.I_SCOUT_DRONE:
			pass
		_:
			return false
	var use_time_s: float = _use_time_s(item_id)
	if use_time_s <= 0.0:
		_apply_effect(item_id)   # no gesture in the data: the effect is immediate
		return true
	_busy_item = item_id
	_busy_total_s = use_time_s
	_busy_left = use_time_s
	_busy_beat_s = use_time_s * _effect_at(item_id)
	_busy_beat_done = false
	match item_id:
		Ids.I_MEDKIT:
			Sfx.play(&"bandage_wrap")
		Ids.I_ENERGY_DRINK:
			Sfx.play(&"drink_gulp")
	use_started.emit(item_id, use_time_s)
	return true


## Cuts the gesture. Before the beat nothing was spent and nothing happened; after it the effect already
## landed and the item is gone, only the gesture is cut.
func cancel_use() -> void:
	if _busy_left > 0.0:
		_end_gesture(&"")


func _process(delta: float) -> void:
	if _busy_left <= 0.0:
		return
	_busy_left -= delta
	var item_id: StringName = _busy_item
	if not _busy_beat_done and (_busy_total_s - _busy_left >= _busy_beat_s or _busy_left <= 0.0):
		if _player == null or not _player.is_alive():
			_end_gesture(&"")   # a dead hunter neither heals nor drinks: nothing is spent
			return
		_busy_beat_done = true
		_apply_effect(item_id)
	if _busy_left > 0.0:
		return
	_end_gesture(item_id)


## Clears the busy state, then announces the end (`&""` = cut short).
func _end_gesture(finished_id: StringName) -> void:
	_busy_item = &""
	_busy_left = 0.0
	_busy_beat_done = false
	use_finished.emit(finished_id)


func _busy_total() -> float:
	return _busy_total_s if _busy_item != &"" else 1.0


## Seconds of the gesture; absent or <= 0 means the use is instant.
func _use_time_s(item_id: StringName) -> float:
	return float(Data.get_equipment(item_id).get("effect", {}).get("use_time_s", 0.0))


## Fraction of the gesture at which the effect lands; absent = at the end.
func _effect_at(item_id: StringName) -> float:
	return clampf(float(Data.get_equipment(item_id).get("effect", {}).get("effect_at", 1.0)), 0.0, 1.0)


## The effect of a consumable, then the spend (count down + GameEvents.item_used), in that order.
func _apply_effect(item_id: StringName) -> void:
	var effect: Dictionary = Data.get_equipment(item_id).get("effect", {})
	var at: Vector3 = _player.global_position
	match item_id:
		Ids.I_MEDKIT:
			_player.heal(float(effect.get("heal", 0.0)))
		Ids.I_ENERGY_DRINK:
			var hunter: Player = _player as Player
			if hunter != null:
				hunter.restore_stamina(stamina_restore_frac)
			Sfx.play(&"energy_drink")
		Ids.I_CORN_BAIT:
			at = _bait_position()   # where the hunter looks at the beat, not at the key press
			Sfx.play(&"bait_throw")
			_message("Ceva colocada.")
		Ids.I_SCOUT_DRONE:
			drone_reveal_s = float(effect.get("reveal_s", 0.0))
			Sfx.play(&"drone_buzz")
			_message("Drone batedor no ar.")
		_:
			return
	_consume(item_id, at)


## Decrements the count, then announces the use (only consumables reach the bus).
func _consume(item_id: StringName, position: Vector3) -> void:
	_counts[item_id] = maxi(int(_counts.get(item_id, 0)) - 1, 0)
	counts_changed.emit()
	GameEvents.item_used.emit(item_id, position)


func _bait_position() -> Vector3:
	var forward: Vector3 = _player.get_look_direction()
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var p: Vector3 = _player.global_position + forward.normalized() * BAIT_DISTANCE_M
	if _world != null:
		p.y = _world.get_height(p.x, p.z)
	return p


func _message(text: String) -> void:
	GameEvents.hud_message_requested.emit(text, MESSAGE_S)
