class_name RemoteHunter
extends PlayerBase
## Another player's hunter as seen on this machine (docs/multiplayer.md section 6.2).
## No physics body and no collision shape (it never occupies a layer); a third-person visual
## (HunterVisualBase) is fed by the interpolated network state. Gameplay of the owner runs on the
## owner's machine: apply_damage and heal are no-ops here.

const SPEED_QUANT_MPS: float = 0.05      # wire: speed u8 in steps of 0.05 m/s (docs section 4.5)
const NO_WEAPON_INDEX: int = 255
const MOVING_SPEED_MIN: float = 0.5      # same threshold as Player.get_noise_radius
const STRIDE_M: float = 2.1              # same stride as Player footsteps
const STEP_CROUCH_DB: float = -8.0
const MAX_QUEUED_SAMPLES: int = 12
const TELEPORT_DISTANCE_M: float = 25.0  # a jump larger than this snaps instead of gliding
const NAME_FONT_SIZE: int = 28
const NAME_OUTLINE_SIZE: int = 8
const NAME_PIXEL_SIZE: float = 0.0016
const NAME_LIFT_M: float = 0.25
const DEFAULT_MAP_RECT: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)   # only if no world was given
const STEP_SFX: StringName = &"step_grass"

var _visual: HunterVisualBase = null
var _label: Label3D = null
var _world: HuntWorld = null
var _display_name: String = ""
var _weapon_ids: Array[StringName] = []
var _net_cfg: Dictionary = {}
var _game_cfg: Dictionary = {}
var _tag_max_m: float = 120.0

# Samples: {t: ms of arrival, pos: Vector3, yaw: float, speed: float, pitch: float,
#           flags: int, weapon: int, health: int, shot_seq: int}
var _samples: Array[Dictionary] = []
var _last_raw: PackedByteArray = PackedByteArray()
var _last_rx_ms: float = 0.0
var _has_state: bool = false

# Discrete state already shown on the visual.
var _flags: int = NetCodec.HF_ALIVE
var _health: int = 100
var _shot_seq: int = 0
var _weapon_index: int = NO_WEAPON_INDEX
var _shown_weapon: StringName = &"__none__"
var _speed: float = 0.0
var _pitch_deg: float = 0.0
var _stride: float = 0.0
var _last_flat_pos: Vector3 = Vector3.ZERO
var _have_last_pos: bool = false

# Debug counters (sandbox/tests).
var fire_events: int = 0
var hit_events: int = 0
var reload_events: int = 0


func _init() -> void:
	collision_layer = 0
	collision_mask = 0


func _ready() -> void:
	set_physics_process(false)
	_net_cfg = Data.get_net()
	_game_cfg = Data.get_game()
	_tag_max_m = float(_game_cfg.get("coop", {}).get("name_tag_max_m", _tag_max_m))
	if _weapon_ids.is_empty():
		_weapon_ids = Data.get_weapon_ids()
	_last_rx_ms = _now_ms()
	if _visual == null:
		_build_visual(&"")


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup_remote(p_slot: int, p_display_name: String, p_weapon_id: StringName, p_world: HuntWorld) -> void:
	slot = p_slot
	_display_name = p_display_name
	_world = p_world
	if _weapon_ids.is_empty():
		_weapon_ids = Data.get_weapon_ids()
	if _visual == null:
		_build_visual(p_weapon_id)
	elif _label != null:
		_label.text = _display_name


func _build_visual(weapon_id: StringName) -> void:
	var node: Node = AssetLoader.instantiate(ScenePaths.HUNTER_VISUAL)
	var visual: HunterVisualBase = node as HunterVisualBase
	if visual == null:
		if node != null:
			node.queue_free()
		visual = HunterVisualBase.create_fallback()
	visual.name = "Visual"
	visual.setup(slot, weapon_id)   # exactly once, before add_child
	add_child(visual)
	_visual = visual
	_shown_weapon = weapon_id
	_build_name_tag()


func _build_name_tag() -> void:
	var anchor: Node3D = _visual.get_name_anchor()
	if anchor == null:
		return
	_label = Label3D.new()
	_label.name = "NameTag"
	_label.text = _display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.shaded = false
	_label.double_sided = true
	_label.pixel_size = NAME_PIXEL_SIZE
	_label.font_size = NAME_FONT_SIZE
	_label.outline_size = NAME_OUTLINE_SIZE
	_label.modulate = HunterVisualBase.slot_color(slot)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0.0, NAME_LIFT_M, 0.0)
	_label.visible = _display_name != ""
	anchor.add_child(_label)


# ---------------------------------------------------------------------------
# PlayerBase contract
# ---------------------------------------------------------------------------

func is_local() -> bool:
	return false


func is_present() -> bool:
	var timeout_s: float = float(_net_cfg.get("peer_absent_s", 3.0))
	return (_now_ms() - _last_rx_ms) < timeout_s * 1000.0


func get_display_name() -> String:
	return _display_name


func apply_damage(_amount: float, _source_position: Vector3, _knockback_mps: float = 0.0) -> void:
	pass   # damage belongs to the owner's machine


func heal(_amount: float) -> void:
	pass


func is_alive() -> bool:
	return (_flags & NetCodec.HF_ALIVE) != 0


func get_health() -> float:
	return float(_health)


func get_max_health() -> float:
	return float(_game_cfg.get("player", {}).get("max_health", 100.0))


func get_eye_position() -> Vector3:
	var cfg: Dictionary = _game_cfg.get("player", {})
	var h: float = float(cfg.get("crouch_eye_height_m", 1.05)) if is_crouching() \
		else float(cfg.get("standing_eye_height_m", 1.65))
	return global_position + Vector3(0.0, h, 0.0)


func get_look_direction() -> Vector3:
	var pitch: float = deg_to_rad(_pitch_deg)
	var yaw: float = rotation.y
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func is_crouching() -> bool:
	return (_flags & NetCodec.HF_CROUCH) != 0


func is_aiming() -> bool:
	return (_flags & NetCodec.HF_AIM) != 0


func get_noise_radius() -> float:
	if _speed < MOVING_SPEED_MIN:
		return 0.0
	var cfg: Dictionary = _game_cfg.get("player", {})
	if is_crouching():
		return float(cfg.get("noise_radius_crouch_m", 0.0))
	if (_flags & NetCodec.HF_SPRINT) != 0:
		return float(cfg.get("noise_radius_sprint_m", 0.0))
	return float(cfg.get("noise_radius_walk_m", 0.0))


func get_current_weapon_id() -> StringName:
	return _weapon_id_at(_weapon_index)


func is_reloading() -> bool:
	return (_flags & NetCodec.HF_RELOAD) != 0


func get_visual() -> HunterVisualBase:
	return _visual


# ---------------------------------------------------------------------------
# Network state
# ---------------------------------------------------------------------------

## Host relay: the host re-sends every hunter in the snapshot, so a remote writes the last state it received.
func net_write_state(out: StreamPeerBuffer) -> void:
	if _last_raw.size() == NetCodec.HUNTER_STATE_BYTES:
		out.put_data(_last_raw)
		return
	var rect: Rect2 = _map_rect()
	NetCodec.put_xz(out, rect, global_position.x, global_position.z)
	out.put_16(clampi(roundi(global_position.y * 100.0), -32768, 32767))
	out.put_u16(NetCodec.angle_to_u16(rotation.y))
	out.put_8(0)
	out.put_u8(0)
	out.put_u8(NetCodec.HF_ALIVE | NetCodec.HF_UNARMED)
	out.put_u8(NO_WEAPON_INDEX)
	out.put_u8(clampi(int(ceil(float(_health))), 0, 255))
	out.put_u8(_shot_seq & 0xFF)


func net_apply_state(inp: StreamPeerBuffer) -> void:
	var raw: Array = inp.get_data(NetCodec.HUNTER_STATE_BYTES)
	if int(raw[0]) != OK:
		return
	var bytes: PackedByteArray = raw[1]
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	var xz: Vector2 = NetCodec.get_xz(buf, _map_rect())
	var y: float = float(buf.get_16()) * 0.01
	var yaw: float = NetCodec.u16_to_angle(buf.get_u16())
	var pitch: float = float(buf.get_8())
	var speed: float = float(buf.get_u8()) * SPEED_QUANT_MPS
	var flags: int = buf.get_u8()
	var weapon: int = buf.get_u8()
	var health: int = buf.get_u8()
	var shot_seq: int = buf.get_u8()
	_last_raw = bytes
	_last_rx_ms = _now_ms()
	var sample: Dictionary = {
		"t": _last_rx_ms, "pos": Vector3(xz.x, y, xz.y), "yaw": yaw, "speed": speed, "pitch": pitch,
		"flags": flags, "weapon": weapon, "health": health, "shot_seq": shot_seq,
	}
	if not _has_state:
		_has_state = true
		_snap_to(sample)
		return
	_samples.append(sample)
	while _samples.size() > MAX_QUEUED_SAMPLES:
		_samples.remove_at(0)


func _snap_to(sample: Dictionary) -> void:
	_samples.clear()
	_samples.append(sample)
	global_position = sample["pos"]
	rotation.y = float(sample["yaw"])
	_last_flat_pos = global_position
	_have_last_pos = true
	_flags = int(sample["flags"])
	_health = int(sample["health"])
	_shot_seq = int(sample["shot_seq"])
	_weapon_index = int(sample["weapon"])
	_speed = float(sample["speed"])
	_pitch_deg = float(sample["pitch"])
	if _visual != null:
		_sync_weapon()
		_visual.set_crouching(is_crouching())
		_visual.set_aiming(is_aiming())
		_visual.set_look_pitch(deg_to_rad(_pitch_deg))
		_visual.set_locomotion(_speed)
		if not is_alive():
			_visual.play_death(true)


func _process(delta: float) -> void:
	if not _has_state or _visual == null:
		return
	var render_ms: float = _now_ms() - float(_net_cfg.get("hunter_interp_delay_ms", 150.0))
	# Advance: samples whose time has passed become the "from" sample and apply their discrete state.
	while _samples.size() >= 2 and float(_samples[1]["t"]) <= render_ms:
		_samples.remove_at(0)
		_apply_discrete(_samples[0])
	var a: Dictionary = _samples[0]
	var target_pos: Vector3 = a["pos"]
	var target_yaw: float = float(a["yaw"])
	var target_speed: float = float(a["speed"])
	var target_pitch: float = float(a["pitch"])
	var glide_velocity: Vector3 = Vector3.ZERO
	if _samples.size() >= 2:
		var b: Dictionary = _samples[1]
		var span: float = maxf(float(b["t"]) - float(a["t"]), 1.0)
		var f: float = clampf((render_ms - float(a["t"])) / span, 0.0, 1.0)
		var pa: Vector3 = a["pos"]
		var pb: Vector3 = b["pos"]
		if pa.distance_to(pb) > TELEPORT_DISTANCE_M:
			target_pos = pb if f >= 0.5 else pa
		else:
			target_pos = pa.lerp(pb, f)
			glide_velocity = (pb - pa) / (span * 0.001)
		target_yaw = lerp_angle(float(a["yaw"]), float(b["yaw"]), f)
		target_speed = lerpf(float(a["speed"]), float(b["speed"]), f)
		target_pitch = lerpf(float(a["pitch"]), float(b["pitch"]), f)
	global_position = target_pos
	rotation.y = target_yaw
	velocity = glide_velocity
	_speed = target_speed
	_pitch_deg = target_pitch
	_visual.set_locomotion(_speed)
	_visual.set_look_pitch(deg_to_rad(_pitch_deg))
	_update_footsteps()
	_update_name_tag()


func _apply_discrete(s: Dictionary) -> void:
	var flags: int = int(s["flags"])
	var old_flags: int = _flags
	_flags = flags
	_weapon_index = int(s["weapon"])
	_sync_weapon()
	_visual.set_crouching((flags & NetCodec.HF_CROUCH) != 0)
	_visual.set_aiming((flags & NetCodec.HF_AIM) != 0)
	var health: int = int(s["health"])
	if health < _health and (flags & NetCodec.HF_ALIVE) != 0:
		hit_events += 1
		_visual.play_hit()
	_health = health
	var seq: int = int(s["shot_seq"])
	if seq != _shot_seq:
		_shot_seq = seq
		fire_events += 1
		_on_remote_fired()
	if (flags & NetCodec.HF_RELOAD) != 0 and (old_flags & NetCodec.HF_RELOAD) == 0:
		reload_events += 1
		var def: Dictionary = Data.get_weapon(get_current_weapon_id())
		_visual.play_reload(float(def.get("reload_s", 2.0)))
	if (old_flags & NetCodec.HF_ALIVE) != 0 and (flags & NetCodec.HF_ALIVE) == 0:
		_visual.play_death()


func _sync_weapon() -> void:
	var wanted: StringName = &"" if (_flags & NetCodec.HF_UNARMED) != 0 else get_current_weapon_id()
	if wanted != _shown_weapon:
		_shown_weapon = wanted
		_visual.set_weapon(wanted)


func _on_remote_fired() -> void:
	_visual.play_fire()
	var def: Dictionary = Data.get_weapon(get_current_weapon_id())
	var sfx: String = String(def.get("shot_sfx", ""))
	if sfx != "":
		var muzzle: Node3D = _visual.get_muzzle()
		var at: Vector3 = muzzle.global_position if muzzle != null else global_position
		Sfx.play_3d(StringName(sfx), at)


func _update_footsteps() -> void:
	var flat: Vector3 = Vector3(global_position.x, 0.0, global_position.z)
	if not _have_last_pos:
		_last_flat_pos = flat
		_have_last_pos = true
		return
	var moved: float = flat.distance_to(Vector3(_last_flat_pos.x, 0.0, _last_flat_pos.z))
	_last_flat_pos = global_position
	if not is_alive() or _speed < MOVING_SPEED_MIN or moved > TELEPORT_DISTANCE_M:
		return
	_stride += moved
	if _stride >= STRIDE_M:
		_stride = 0.0
		Sfx.play_3d(STEP_SFX, global_position, STEP_CROUCH_DB if is_crouching() else 0.0)


func _update_name_tag() -> void:
	if _label == null or _display_name == "":
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var watched: bool = cam is SpectatorCamera and (cam as SpectatorCamera).get_target_slot() == slot   # the HUD names it
	_label.visible = cam.global_position.distance_to(global_position) <= _tag_max_m and is_alive() and not watched


func _weapon_id_at(index: int) -> StringName:
	if index < 0 or index >= _weapon_ids.size():
		return &""
	return _weapon_ids[index]


func _map_rect() -> Rect2:
	return _world.get_map_rect() if _world != null else DEFAULT_MAP_RECT


func _now_ms() -> float:
	return float(Time.get_ticks_usec()) / 1000.0
