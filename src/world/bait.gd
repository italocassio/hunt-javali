class_name Bait
extends Node3D
## Corn bait. Attracts up to max_boars boars within attract_radius_m for duration_s.
## Boars eating at the bait do not drain the crop.

signal expired(bait: Bait)

const FALLBACK_SIZE: Vector3 = Vector3(1.0, 0.3, 1.0)
const FALLBACK_COLOR: Color = Color(0.9, 0.75, 0.2)

var duration_s: float = 45.0
var attract_radius_m: float = 80.0
var max_boars: int = 4
var remaining_s: float = 45.0
var active: bool = true

var _reserved: Dictionary = {}   # boar_id -> true


func setup(world_pos: Vector3, p_duration_s: float, p_attract_radius_m: float, p_max_boars: int) -> void:
	position = world_pos
	duration_s = p_duration_s
	remaining_s = p_duration_s
	attract_radius_m = p_attract_radius_m
	max_boars = p_max_boars
	var visual: Node = AssetLoader.instantiate(ScenePaths.prop(&"corn_bait"))
	if visual == null or not visual is Node3D:
		if visual != null:
			visual.queue_free()
		visual = FallbackMeshes.box(FALLBACK_SIZE, FALLBACK_COLOR)
	add_child(visual)


func get_xz() -> Vector2:
	return Vector2(position.x, position.z)


func has_slot() -> bool:
	return active and _reserved.size() < max_boars


func try_reserve(boar_id: int) -> bool:
	if _reserved.has(boar_id):
		return active
	if not has_slot():
		return false
	_reserved[boar_id] = true
	return true


func release(boar_id: int) -> void:
	_reserved.erase(boar_id)


func get_reserved_count() -> int:
	return _reserved.size()


func _process(delta: float) -> void:
	if not active:
		return
	remaining_s -= delta
	if remaining_s <= 0.0:
		active = false
		_reserved.clear()
		expired.emit(self)
		queue_free()
