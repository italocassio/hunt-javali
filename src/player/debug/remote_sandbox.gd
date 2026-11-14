extends SandboxWorld
## Package A sandbox for RemoteHunter (docs/multiplayer.md 6.2). Two remote hunters fed through the same
## byte path as the network: remote 1 follows the real Player (Player.net_write_state -> net_apply_state),
## remote 2 follows a hand-encoded synthetic state (cross-checks the wire format independently).
## Runs a scripted sequence, asserts, and quits by itself.
## Command line (after "--"): --noquit (keep running, for screenshots), --cam (a Camera3D that looks at
## the hunters, for screenshots)

const SEND_INTERVAL_S: float = 0.1
const CIRCLE_RADIUS_M: float = 4.0
const WALK_SPEED_MPS: float = 4.0
const SYNTH_CENTER: Vector3 = Vector3(7.0, 0.0, -2.0)
const SYNTH_RADIUS_M: float = 3.0
const T_CROUCH_S: float = 0.6
const T_AIM_S: float = 1.2
const T_FIRE_S: float = 1.8
const T_STOP_S: float = 3.0
const T_CHECK_S: float = 4.3          # 1.3 s after stopping: "1 s still" plus the interpolation delay
const T_DEATH_S: float = 4.6
const T_SILENCE_S: float = 5.2
const T_END_S: float = 8.7
const POSITION_TOLERANCE_M: float = 0.5
const SYNTH_AIM_PITCH_DEG: int = 15
const SYNTH_HEALTH_AFTER_HIT: int = 70

var _remote1: RemoteHunter = null
var _remote2: RemoteHunter = null
var _t: float = 0.0
var _send_t: float = 0.0
var _synth_angle: float = 0.0
var _synth_moving: bool = true
var _synth_flags: int = NetCodec.HF_ALIVE
var _synth_seq: int = 0
var _synth_health: int = 100
var _synth_pos: Vector3 = Vector3.ZERO
var _synth_yaw: float = 0.0
var _events_done: Dictionary = {}
var _fails: int = 0
var _checked: bool = false
var _silence_checked: bool = false
var _sending: bool = true
var _max_lag_m: float = 0.0
var _bytes_written: int = 0
var _keep_running: bool = false
var _shotgun_index: int = 0
var _silence_from: float = 0.0


func _ready() -> void:
	super._ready()
	_keep_running = _args.has("noquit")
	_shotgun_index = Data.get_weapon_ids().find(Ids.W_SHOTGUN_12)
	player.bot_set_enabled(true)
	player.bot_teleport(Vector3.ZERO)
	player.bot_set_move(Vector2(0.0, 1.0), false)
	_remote1 = _spawn_remote(1, "Ana", Ids.W_CARBINE_22)
	_remote2 = _spawn_remote(2, "Beto", Ids.W_SHOTGUN_12)
	_synth_pos = SYNTH_CENTER + Vector3(SYNTH_RADIUS_M, 0.0, 0.0)
	if _args.has("cam"):
		var cam: Camera3D = Camera3D.new()
		add_child(cam)
		cam.far = 200.0
		cam.look_at_from_position(Vector3(3.5, 2.6, 9.0), Vector3(3.5, 1.0, -1.0))
		cam.make_current()
	_send_states()


func _spawn_remote(p_slot: int, p_name: String, weapon: StringName) -> RemoteHunter:
	var packed: PackedScene = load(ScenePaths.REMOTE_HUNTER) as PackedScene
	var r: RemoteHunter = packed.instantiate() as RemoteHunter
	r.setup_remote(p_slot, p_name, weapon, self)
	add_child(r)
	return r


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	_drive_player(delta)
	_drive_synthetic(delta)
	_send_t += delta
	if _send_t >= SEND_INTERVAL_S:
		_send_t -= SEND_INTERVAL_S
		if _sending:
			_send_states()
	if _t > 1.0 and _t < T_STOP_S:
		_max_lag_m = maxf(_max_lag_m, _remote1.global_position.distance_to(player.global_position))
	_run_script()


func _drive_player(delta: float) -> void:
	if _t < T_STOP_S:
		player.rotation.y -= WALK_SPEED_MPS / CIRCLE_RADIUS_M * delta * (0.6 if _t > T_AIM_S else 1.0)
	else:
		player.bot_set_move(Vector2.ZERO, false)


func _drive_synthetic(delta: float) -> void:
	if _synth_moving:
		_synth_angle += WALK_SPEED_MPS / SYNTH_RADIUS_M * delta
		_synth_pos = SYNTH_CENTER + Vector3(cos(_synth_angle), 0.0, sin(_synth_angle)) * SYNTH_RADIUS_M
		# Heading of a circle in XZ: tangent (-sin, cos); forward is -Z so yaw = atan2(-dx, -dz).
		_synth_yaw = atan2(sin(_synth_angle), -cos(_synth_angle))


func _once(key: String, at_s: float) -> bool:
	if _t >= at_s and not _events_done.has(key):
		_events_done[key] = true
		return true
	return false


func _run_script() -> void:
	if _once("crouch", T_CROUCH_S):
		player._crouching = true
		_synth_flags |= NetCodec.HF_CROUCH
	if _once("uncrouch", T_AIM_S - 0.1):
		player._crouching = false
		_synth_flags &= ~NetCodec.HF_CROUCH
	if _once("aim", T_AIM_S):
		player.bot_set_aim(true)
		_synth_flags |= NetCodec.HF_AIM
	if _once("fire", T_FIRE_S):
		check(player.bot_fire(), "player bot_fire fired")
		_synth_seq = (_synth_seq + 1) & 0xFF
	if _once("synth_fire2", T_FIRE_S + 0.5):
		_synth_seq = (_synth_seq + 1) & 0xFF
	if _once("reload", T_FIRE_S + 0.9):
		_synth_flags |= NetCodec.HF_RELOAD
	if _once("reload_end", T_FIRE_S + 1.1):
		_synth_flags &= ~NetCodec.HF_RELOAD
	if _once("hurt", T_FIRE_S + 1.2):
		_synth_health = SYNTH_HEALTH_AFTER_HIT
	if _once("stop", T_STOP_S):
		_synth_moving = false
		player.bot_set_aim(false)
		_synth_flags &= ~NetCodec.HF_AIM
	if not _checked and _t >= T_CHECK_S:
		_checked = true
		_check_convergence()
	if _once("death", T_DEATH_S):
		_synth_flags &= ~NetCodec.HF_ALIVE
		_synth_health = 0
	if not _silence_checked and _t >= T_SILENCE_S:
		_silence_checked = true
		_sending = false
		_silence_from = _t
		check(_remote2.is_present(), "remote still present right after the last state")
	if _silence_checked and _t >= T_END_S:
		_finish()


func _send_states() -> void:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	player.net_write_state(buf)
	_bytes_written = buf.get_size()
	_feed(_remote1, buf.data_array)
	var synth: StreamPeerBuffer = StreamPeerBuffer.new()
	_encode_synthetic(synth)
	_feed(_remote2, synth.data_array)


func _feed(remote: RemoteHunter, bytes: PackedByteArray) -> void:
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = bytes
	remote.net_apply_state(inp)
	check(inp.get_position() == NetCodec.HUNTER_STATE_BYTES,
		"net_apply_state read exactly 14 bytes (%d)" % inp.get_position())


## Independent encoder of HUNTER_STATE (docs 4.5): not shared with player.gd on purpose.
func _encode_synthetic(out: StreamPeerBuffer) -> void:
	NetCodec.put_xz(out, get_map_rect(), _synth_pos.x, _synth_pos.z)
	out.put_16(roundi(_synth_pos.y * 100.0))
	out.put_u16(NetCodec.angle_to_u16(_synth_yaw))
	out.put_8(SYNTH_AIM_PITCH_DEG)
	out.put_u8(roundi((WALK_SPEED_MPS if _synth_moving else 0.0) / 0.05))
	out.put_u8(_synth_flags)
	out.put_u8(_shotgun_index)
	out.put_u8(_synth_health)
	out.put_u8(_synth_seq)


func check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL ", label)


func _check_convergence() -> void:
	var e1: float = _remote1.global_position.distance_to(player.global_position)
	var e2: float = _remote2.global_position.distance_to(_synth_pos)
	print("remote1 error after stop: %.3f m (max lag while moving %.2f m)" % [e1, _max_lag_m])
	print("remote2 error after stop: %.3f m" % e2)
	check(player.global_position.length() > 1.0 and _synth_pos.distance_to(Vector3.ZERO) > 1.0, "sources actually moved")
	check(_remote1.global_position.length() > 1.0, "remote1 actually left the origin")
	check(e1 <= POSITION_TOLERANCE_M, "remote1 converges to the real player (%.3f m)" % e1)
	check(e2 <= POSITION_TOLERANCE_M, "remote2 converges to the synthetic truth (%.3f m)" % e2)
	var yaw1: float = absf(angle_difference(_remote1.rotation.y, player.rotation.y))
	var yaw2: float = absf(angle_difference(_remote2.rotation.y, _synth_yaw))
	check(yaw1 < deg_to_rad(3.0) and yaw2 < deg_to_rad(3.0),
		"yaw converges (%.2f, %.2f deg)" % [rad_to_deg(yaw1), rad_to_deg(yaw2)])
	check(_remote1.get_current_weapon_id() == Ids.W_CARBINE_22, "remote1 weapon id from index")
	check(_remote2.get_current_weapon_id() == Ids.W_SHOTGUN_12, "remote2 weapon id from index")
	check(not _remote1.is_crouching() and not _remote1.is_aiming(), "remote1 crouch/aim cleared after stop")
	check(_remote1.fire_events == 1, "remote1 saw exactly 1 shot (%d)" % _remote1.fire_events)
	check(_remote2.fire_events == 2, "remote2 saw exactly 2 shots (%d)" % _remote2.fire_events)
	check(_remote2.reload_events == 1, "remote2 reload seen once (%d)" % _remote2.reload_events)
	check(_remote2.hit_events == 1, "remote2 hit seen once (%d)" % _remote2.hit_events)
	check(is_equal_approx(_remote2.get_health(), float(SYNTH_HEALTH_AFTER_HIT)), "remote2 health")
	check(_remote2.is_alive() and _remote1.is_alive(), "both alive before death")
	check(_remote1.get_noise_radius() == 0.0, "still remote makes no noise")
	check(_bytes_written == NetCodec.HUNTER_STATE_BYTES, "Player.net_write_state wrote %d bytes" % _bytes_written)
	check(_remote1.collision_layer == 0 and _remote1.collision_mask == 0, "remote has no collision layers")
	check(_remote1.find_children("*", "CollisionShape3D", true, false).is_empty(), "remote has no collision shape")
	check(not _remote1.is_local() and player.is_local(), "is_local")
	check(_remote1.slot == 1 and _remote2.slot == 2, "slots")
	check(_remote1.get_display_name() == "Ana", "display name")
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	_remote1.net_write_state(out)
	check(out.get_size() == NetCodec.HUNTER_STATE_BYTES, "remote relay writes 14 bytes")


func _finish() -> void:
	check(not _remote2.is_present(), "remote absent after %.1f s of silence" % (_t - _silence_from))
	check(not _remote2.is_alive(), "remote2 dead after HF_ALIVE dropped")
	check(_remote2.get_health() == 0.0, "remote2 health 0")
	print("remote_sandbox: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	set_process(false)
	if not _keep_running:
		get_tree().quit(1 if _fails > 0 else 0)
