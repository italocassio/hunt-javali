class_name ItemHands
extends Node
## First-person item hands: builds one ItemViewBase per carried consumable that has art and plays the use gesture
## while the ItemBelt is busy with that item (docs/plano_itens_animados.md 2.3).
##
## Child of the Player, same relation the Knife has with its view. The Player owns the gates and hides the weapon view
## while is_showing() is true. The art is optional: an item without assets/models/items/<id>_view.tscn gets no view,
## is_showing() stays false for it and the weapon is never hidden (the screen is never left empty).

const VIEW_NAME_FORMAT: String = "View_item_%s"
const KIND_CONSUMABLE: String = "consumable"
## Used when the data has no `effect_at` for the item: the effect lands at the very end of the gesture.
const DEFAULT_EFFECT_AT: float = 1.0

var _holder: Node3D = null
var _belt: ItemBelt = null
var _views: Dictionary = {}                   # item_id (StringName) -> ItemViewBase
## The view stands in its rest pose from setup until hunt_started, so the pre-warm compiles its materials behind the
## loading overlay (risk R3). After that it shows only while its gesture plays.
var _rest_visible: bool = true
var _showing_id: StringName = &""


## Views become children of `holder` (the WeaponHolder) and the node listens to the belt. Safe to call once.
func setup(belt: ItemBelt, holder: Node3D) -> void:
	_belt = belt
	_holder = holder
	if _belt == null or _holder == null:
		return
	for item_id: StringName in _belt.get_usable_ids():
		if String(Data.get_equipment(item_id).get("kind", "")) != KIND_CONSUMABLE:
			continue
		_create_view(item_id)
	_belt.use_started.connect(_on_use_started)
	_belt.use_finished.connect(_on_use_finished)


## True while a gesture with a view is on screen. The Player hides the weapon meanwhile.
func is_showing() -> bool:
	return _showing_id != &""


## The hunt started (false): the views leave their rest pose. Before that they stay visible for the pre-warm.
func set_rest_visible(on: bool) -> void:
	_rest_visible = on
	for item_id: StringName in _views:
		var view: ItemViewBase = _views[item_id] as ItemViewBase
		if is_instance_valid(view) and item_id != _showing_id:
			view.visible = on


## Cuts the gesture at once (no animation) and hides its view. Does nothing when nothing is showing.
func cancel() -> void:
	_stop_showing(true)


## The view of a carried consumable, or null (no art, not carried, not a consumable). Tests only.
func get_view(item_id: StringName) -> ItemViewBase:
	var view: ItemViewBase = _views.get(item_id) as ItemViewBase
	return view if is_instance_valid(view) else null


func _create_view(item_id: StringName) -> void:
	var path: String = ScenePaths.item_view(item_id)
	if not AssetLoader.exists(path):
		return
	var node: Node = AssetLoader.instantiate(path)
	var view: ItemViewBase = node as ItemViewBase
	if view == null:
		if node != null:
			node.queue_free()
		return
	view.name = VIEW_NAME_FORMAT % item_id
	_holder.add_child(view)
	view.setup(item_id)
	view.visible = _rest_visible
	_views[item_id] = view


func _on_use_started(item_id: StringName, duration_s: float) -> void:
	if _showing_id != &"":
		_stop_showing(true)   # a second use cannot start while busy; this is only a guard
	var view: ItemViewBase = get_view(item_id)
	if view == null:
		return
	var effect: Dictionary = Data.get_equipment(item_id).get("effect", {})
	var effect_at: float = clampf(float(effect.get("effect_at", DEFAULT_EFFECT_AT)), 0.0, 1.0)
	_showing_id = item_id
	view.visible = true
	view.play_use(duration_s, effect_at)


## `&""` = the use was cut short (ItemBelt.cancel_use): the view snaps back to rest first.
func _on_use_finished(item_id: StringName) -> void:
	_stop_showing(item_id == &"")


func _stop_showing(cut_short: bool) -> void:
	if _showing_id == &"":
		return
	var view: ItemViewBase = get_view(_showing_id)
	_showing_id = &""
	if view == null:
		return
	if cut_short:
		view.cancel_use()
	view.visible = _rest_visible
