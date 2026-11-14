class_name PlayerBase
extends CharacterBody3D
## Contract hunter <-> hunt. Package A implements Player (extends this). Package B uses only this API.
## Origin = feet. Forward = -Z (yaw on this node).

var slot: int = 0


func setup(_request: HuntRequest, _world: HuntWorld) -> void:
	pass


func apply_damage(_amount: float, _source_position: Vector3, _knockback_mps: float = 0.0) -> void:
	pass


func heal(_amount: float) -> void:
	pass


func is_alive() -> bool:
	return true


func get_health() -> float:
	return 100.0


func get_max_health() -> float:
	return 100.0


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.65, 0.0)


func get_look_direction() -> Vector3:
	return -global_transform.basis.z


func is_crouching() -> bool:
	return false


func get_noise_radius() -> float:
	return 0.0


func set_input_enabled(_enabled: bool) -> void:
	pass


func get_current_weapon_id() -> StringName:
	return &""


func get_ammo_in_mag() -> int:
	return 0


func get_ammo_reserve() -> int:
	return 0


func is_reloading() -> bool:
	return false


func setup_remote(_slot: int, _display_name: String, _weapon_id: StringName, _world: HuntWorld) -> void:
	pass


func is_local() -> bool:      # false for RemoteHunter
	return true


func is_present() -> bool:    # false while a remote hunter has been silent for net.peer_absent_s: AI ignores it
	return true


func get_display_name() -> String:
	return ""


func net_write_state(_out: StreamPeerBuffer) -> void:   # writes exactly NetCodec.HUNTER_STATE_BYTES
	pass


func net_apply_state(_inp: StreamPeerBuffer) -> void:   # reads exactly NetCodec.HUNTER_STATE_BYTES
	pass


# --- Bot hooks (tests) ---
func bot_set_enabled(_enabled: bool) -> void:
	pass


func bot_set_move(_direction: Vector2, _sprint: bool) -> void:   # x = right, y = forward, length <= 1
	pass


func bot_look_at(_point: Vector3) -> void:
	pass


func bot_set_aim(_aiming: bool) -> void:
	pass


func bot_fire() -> bool:   # true if a shot was fired
	return false


func bot_reload() -> void:
	pass


func bot_select_weapon(_slot: int) -> void:
	pass


func bot_use_item(_item_id: StringName) -> bool:
	return false


func bot_dog_command() -> void:
	pass


func bot_teleport(target_position: Vector3) -> void:
	global_position = target_position
	velocity = Vector3.ZERO
