class_name LookPad
extends Control
## Logic-only region for "drag to look". TouchControls hands it one finger; it forwards the raw pixel
## deltas. It never produces input actions, so touching it cannot fire the weapon.

signal look(rel_px: Vector2)

var _finger: int = 0          # which finger (any int is valid; never a sentinel)
var _active: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return _active


func owns(finger: int) -> bool:
	return _active and _finger == finger


func get_finger() -> int:
	return _finger


func begin(finger: int) -> void:
	_finger = finger
	_active = true


func drag(rel_px: Vector2) -> void:
	if _active:
		look.emit(rel_px)


func end() -> void:
	_active = false
	_finger = 0
