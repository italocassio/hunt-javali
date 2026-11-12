class_name ItemBelt
extends Node
## Equipment carried into the hunt (docs §8.11): passives (vest, extra ammo, thermal scope),
## the active binoculars and the consumables (medkit, corn bait, scout drone).

signal selection_changed()
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

var _usable: Array[StringName] = []
var _counts: Dictionary = {}          # StringName -> int (consumables only)
var _selected: int = 0
var _binoculars_on: bool = false
var _busy_item: StringName = &""
var _busy_left: float = 0.0
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
	_selected = 0
	selection_changed.emit()


func has_item(item_id: StringName) -> bool:
	return _usable.has(item_id)


func get_usable_ids() -> Array[StringName]:
	return _usable


func get_selected_id() -> StringName:
	if _usable.is_empty():
		return &""
	return _usable[_selected]


## Consumables: remaining count. Active items (binoculars): -1.
func get_count(item_id: StringName) -> int:
	return int(_counts.get(item_id, -1))


func next() -> void:
	if _usable.size() < 2:
		return
	_selected = (_selected + 1) % _usable.size()
	selection_changed.emit()


func is_busy() -> bool:
	return _busy_left > 0.0


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


func use_selected() -> bool:
	return use_item(get_selected_id())


func use_item(item_id: StringName) -> bool:
	if item_id == &"" or not has_item(item_id):
		return false
	if is_busy():
		return false
	var effect: Dictionary = Data.get_equipment(item_id).get("effect", {})
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
			_busy_item = item_id
			_busy_left = float(effect.get("use_time_s", 1.0))
			use_started.emit(item_id, _busy_left)
			return true
		Ids.I_CORN_BAIT:
			_consume(item_id, _bait_position())
			_message("Ceva colocada.")
			return true
		Ids.I_SCOUT_DRONE:
			drone_reveal_s = float(effect.get("reveal_s", 0.0))
			Sfx.play(&"drone_buzz")
			_consume(item_id, _player.global_position)
			_message("Drone batedor no ar.")
			return true
	return false


func cancel_use() -> void:
	if _busy_left > 0.0:
		_busy_left = 0.0
		_busy_item = &""
		use_finished.emit(&"")


func _process(delta: float) -> void:
	if _busy_left <= 0.0:
		return
	_busy_left -= delta
	if _busy_left > 0.0:
		return
	var item_id: StringName = _busy_item
	_busy_item = &""
	_busy_left = 0.0
	if item_id == Ids.I_MEDKIT and _player != null and _player.is_alive():
		var heal_amount: float = float(Data.get_equipment(item_id).get("effect", {}).get("heal", 0.0))
		_consume(item_id, _player.global_position)
		_player.heal(heal_amount)
	use_finished.emit(item_id)


func _busy_total() -> float:
	if _busy_item == &"":
		return 1.0
	return float(Data.get_equipment(_busy_item).get("effect", {}).get("use_time_s", 1.0))


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
