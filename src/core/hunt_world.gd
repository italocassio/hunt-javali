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


func get_hunters() -> Array[PlayerBase]:      # every hunter in the world, local first. Solo: [get_player()]
	var out: Array[PlayerBase] = []
	var p: PlayerBase = get_player()
	if p != null:
		out.append(p)
	return out


func get_hunter(_slot: int) -> PlayerBase:    # null if that slot is not in the hunt
	return get_player()


func get_local_slot() -> int:
	return 0


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


# --- Net seam: bodies are record payloads of docs/multiplayer.md section 4 ---
func net_write_snapshot(_out: StreamPeerBuffer) -> void:      # host: body of H_SNAPSHOT
	pass


func net_apply_snapshot(_inp: StreamPeerBuffer) -> void:      # client
	pass


func net_take_events(_out: StreamPeerBuffer) -> void:         # host: appends queued EV_* records (type, len, body)
	pass


func net_apply_event(_type: int, _inp: StreamPeerBuffer, _length: int) -> void:   # client
	pass


func net_take_claims(_out: StreamPeerBuffer) -> void:         # client: appends queued C_* event records
	pass


func net_apply_claim(_slot: int, _type: int, _inp: StreamPeerBuffer, _length: int) -> void:   # host
	pass


func net_peer_left(_slot: int) -> void:                       # that hunter (and its dog) leaves the world
	pass


func net_connection_lost() -> void:                           # client: ends DISCONNECTED; host: every remote leaves
	pass
