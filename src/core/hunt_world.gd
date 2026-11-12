class_name HuntWorld
extends Node3D
## Contract hunt/world <-> player, HUD and tests. Package B implements HuntController (extends this).
## Map rect is in XZ: position = (min_x, min_z), size = (size_x, size_z).

signal world_ready()


func is_world_ready() -> bool:
	return false


func get_map_id() -> StringName:
	return &""


func get_contract_index() -> int:
	return 0


func get_map_rect() -> Rect2:
	return Rect2(-128.0, -128.0, 256.0, 256.0)


func get_height(_x: float, _z: float) -> float:
	return 0.0


func get_normal(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func get_crop_rects() -> Array[Rect2]:
	return []


func get_crop_health_pct() -> float:
	return 100.0


func get_boars_total() -> int:
	return 0


func get_boars_killed() -> int:
	return 0


func get_alive_boar_ids() -> PackedInt32Array:
	return PackedInt32Array()


func get_boar_position(_boar_id: int) -> Vector3:
	return Vector3.INF


func get_boar_type(_boar_id: int) -> StringName:
	return &""


func get_boar_zone_position(_boar_id: int, _zone: StringName) -> Vector3:
	return Vector3.INF


func get_nearest_boar_position(_from: Vector3) -> Vector3:
	return Vector3.INF


func get_marked_boar_positions() -> PackedVector3Array:
	return PackedVector3Array()


func has_dog() -> bool:
	return false


func get_dog_position() -> Vector3:
	return Vector3.INF


func get_dog_state() -> StringName:
	return &""


func get_dog_health_pct() -> float:
	return 0.0


func get_player() -> PlayerBase:
	return null


func get_elapsed_s() -> float:
	return 0.0


func is_hunt_over() -> bool:
	return false


func get_result() -> HuntResult:
	return null


# --- Debug hooks (tests) ---
func debug_kill_boar(_boar_id: int) -> void:
	pass


func debug_set_crop_health(_pct: float) -> void:
	pass


func debug_force_end(_outcome: HuntResult.Outcome) -> void:
	pass
