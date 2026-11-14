class_name FallbackRemoteHunter
extends PlayerBase
## Stand-in remote hunter used by HuntController when ScenePaths.REMOTE_HUNTER does not exist (or is not a
## PlayerBase). A slot-colored capsule that snaps to the last received HUNTER_STATE. No interpolation,
## no animation, no collision. Package A owns the real RemoteHunter.

var _world: HuntWorld = null
var _display_name: String = ""
var _alive: bool = true
var _health: float = 100.0
var _pitch: float = 0.0
var _speed: float = 0.0
var _flags: int = 0
var _weapon_idx: int = 255
var _shot_seq: int = 0
var _last_state: PackedByteArray = PackedByteArray()
var _has_state: bool = false


func _init() -> void:
	collision_layer = 0
	collision_mask = 0


func setup_remote(p_slot: int, p_display_name: String, p_weapon_id: StringName, world: HuntWorld) -> void:
	slot = p_slot
	_display_name = p_display_name
	_world = world
	var visual: HunterVisualBase = HunterVisualBase.create_fallback()
	visual.name = "Visual"
	visual.setup(p_slot, p_weapon_id)
	add_child(visual)


func is_local() -> bool:
	return false


func get_display_name() -> String:
	return _display_name


func is_alive() -> bool:
	return _alive


func get_health() -> float:
	return _health


func is_crouching() -> bool:
	return (_flags & NetCodec.HF_CROUCH) != 0


func get_noise_radius() -> float:
	return 0.0


## Decodes the 14 bytes of HUNTER_STATE (docs/multiplayer.md section 4.5).
func net_apply_state(inp: StreamPeerBuffer) -> void:
	var rect: Rect2 = _world.get_map_rect() if _world != null else Rect2(-128.0, -128.0, 256.0, 256.0)
	var start: int = inp.get_position()
	var xz: Vector2 = NetCodec.get_xz(inp, rect)
	var y: float = float(inp.get_16()) / 100.0
	var yaw: float = NetCodec.u16_to_angle(inp.get_u16())
	_pitch = float(inp.get_8())
	_speed = float(inp.get_u8()) * 0.05
	_flags = inp.get_u8()
	_weapon_idx = inp.get_u8()
	_health = float(inp.get_u8())
	_shot_seq = inp.get_u8()
	_alive = (_flags & NetCodec.HF_ALIVE) != 0
	global_position = Vector3(xz.x, y, xz.y)
	rotation.y = yaw
	_has_state = true
	_last_state = inp.data_array.slice(start, start + NetCodec.HUNTER_STATE_BYTES)


## The host relays every hunter in the snapshot, including remote ones: write back the last received state.
func net_write_state(out: StreamPeerBuffer) -> void:
	if _last_state.size() == NetCodec.HUNTER_STATE_BYTES:
		out.put_data(_last_state)
