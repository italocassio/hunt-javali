class_name LookPad
extends Control
## Logic-only region for "drag to look". TouchControls hands it one finger; it forwards the raw pixel
## deltas. It never produces input actions, so touching it cannot fire the weapon.

signal look(rel_px: Vector2)

var _finger: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return _finger != -1


func get_finger() -> int:
	return _finger


func begin(finger: int) -> void:
	_finger = finger


func drag(rel_px: Vector2) -> void:
	if _finger != -1:
		look.emit(rel_px)


func end() -> void:
	_finger = -1
