extends Node
## Autoload "Sfx" — PHASE 0 STUB. Owner: art-director.
## Replace the bodies, keep every signature. See docs/arquitetura.md §7.8.


func has_sound(_id: StringName) -> bool:
	return false


func play(_id: StringName, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
	pass


func play_3d(_id: StringName, _position: Vector3, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
	pass


func play_loop(_id: StringName, _volume_db: float = 0.0) -> void:
	pass


func stop_loop(_id: StringName) -> void:
	pass


func stop_all_loops() -> void:
	pass


func unlock_audio() -> void:
	pass


func set_bus_volume(_bus: StringName, _linear: float) -> void:
	pass
