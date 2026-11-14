extends Node
## Package B measurement for F4 (docs/multiplayer.md sections 4.6 and 9 F4): a host hunt with a roster of 4
## (the local hunter + 3 RemoteHunter fed with synthetic HUNTER_STATE at net.hunter_state_hz walking around
## it), contract 5 (index 4) of Mato Grosso warped until every group is in, plus one boar so 26 are alive.
## Then, at normal speed for MEASURE_S of wall time, it measures the frame rate and, every 1/snapshot_hz
## of hunt time, the bytes of H_SNAPSHOT and of the EV_* records one client would download.
## The local hunter stands at the edge of the crop looking at it (boars in view) and is healed every frame;
## the crop is kept at 100 % so the hunt never ends during the measure.
## Headless: bandwidth only. With a window (no --headless): also the desktop frame rate.
## Usage: tools/godot.sh [--headless] --path . res://src/hunt/debug/net_perf.tscn [-- --quality=medium]
## Not part of the game.

const CONTRACT: int = 4
const MAP_ID: StringName = &"mato_grosso"
const REMOTES: int = 3
const TARGET_ALIVE: int = 26
const WARP: float = 6.0
const WARP_LIMIT_S: float = 120.0          # hunt seconds
const MEASURE_S: float = 10.0              # wall seconds
const WATCHDOG_REAL_S: float = 240.0
const WALK_RADIUS_M: float = 6.0
const WALK_SPEED_MPS: float = 1.4
const CROP_EDGE_M: float = 6.0
const TRANSPORT_BYTES: int = 85            # IP/UDP/DTLS/SCTP per packet (section 4.6)
const QUALITY_ARG: String = "--quality="

var _hunt: HuntController = null
var _start_ms: int = 0
var _phase: int = 0                        # 0 warm-up, 1 measuring, 2 done
var _state_accum: float = 0.0
var _snap_accum: float = 0.0
var _walk_t: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _weapon_index: int = 0
var _measure_start_ms: int = 0
var _frames: int = 0
var _worst_frame_ms: float = 0.0
var _ticks: int = 0
var _snap_bytes: int = 0
var _snap_max: int = 0
var _event_bytes: int = 0
var _event_ticks: int = 0
var _alive_sum: int = 0
var _alive_min: int = 1000


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	var req: HuntRequest = HuntRequest.make_debug(MAP_ID, CONTRACT)
	req.rng_seed = 777
	req.quality = StringName(_arg(QUALITY_ARG)) if _arg(QUALITY_ARG) != "" else Ids.Q_MEDIUM
	req.player_count = REMOTES + 1
	Router.set_pending_request(req)
	var roster: Array[NetPeerInfo] = []
	for i: int in REMOTES + 1:
		var info: NetPeerInfo = NetPeerInfo.new()
		info.slot = i
		info.display_name = "Caçador %d" % (i + 1)
		info.is_host = i == 0
		info.weapon_id = Ids.W_CARBINE_22
		roster.append(info)
	_weapon_index = Data.get_weapon_ids().find(Ids.W_CARBINE_22)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	_hunt.test_net_role = Net.Role.HOST
	_hunt.test_net_local_slot = 0
	_hunt.test_net_roster = roster
	add_child(_hunt)
	while not _hunt.is_world_ready():
		await get_tree().process_frame
	_hunt.debug_net_go()
	_place_local()
	Engine.time_scale = WARP
	print("NET_PERF quality=%s contract=%d total=%d" % [req.quality, CONTRACT, _hunt.get_boars_total()])


func _process(delta: float) -> void:
	if float(Time.get_ticks_msec() - _start_ms) > WATCHDOG_REAL_S * 1000.0:
		print("NET_PERF FAIL watchdog")
		_quit(1)
		return
	if _hunt == null or not _hunt.is_world_ready() or _phase == 2:
		return
	_hunt.debug_set_crop_health(100.0)
	_hunt.get_player().heal(1000.0)
	_feed_remotes(delta)
	if _phase == 0:
		_warm_up()
	elif _phase == 1:
		_measure(delta)


func _place_local() -> void:
	var rects: Array[Rect2] = _hunt.get_crop_rects()
	var p: PlayerBase = _hunt.get_player()
	p.bot_set_enabled(true)
	if rects.is_empty():
		return
	var r: Rect2 = rects[0]
	var c: Vector2 = r.get_center()
	var edge: Vector2 = Vector2(r.position.x - CROP_EDGE_M, c.y)
	_center = Vector3(edge.x, _hunt.get_height(edge.x, edge.y), edge.y)
	p.bot_teleport(_center + Vector3(0.0, 0.05, 0.0))
	p.bot_look_at(Vector3(c.x, _hunt.get_height(c.x, c.y) + 0.5, c.y))


## Remote hunters walk in a circle around the local one; states arrive at the C_STATE rate.
func _feed_remotes(delta: float) -> void:
	_walk_t += delta
	_state_accum += delta
	var interval: float = 1.0 / float(Data.get_net()["hunter_state_hz"])
	if _state_accum < interval:
		return
	_state_accum = fmod(_state_accum, interval)
	var rect: Rect2 = _hunt.get_map_rect()
	for slot: int in range(1, REMOTES + 1):
		var h: PlayerBase = _hunt.get_hunter(slot)
		if h == null:
			continue
		var ang: float = _walk_t * WALK_SPEED_MPS / WALK_RADIUS_M + TAU * float(slot) / float(REMOTES)
		var x: float = _center.x + cos(ang) * WALK_RADIUS_M
		var z: float = _center.z + sin(ang) * WALK_RADIUS_M
		var out: StreamPeerBuffer = StreamPeerBuffer.new()
		NetCodec.put_xz(out, rect, x, z)
		out.put_16(roundi(_hunt.get_height(x, z) * 100.0))
		out.put_u16(NetCodec.angle_to_u16(ang + PI))
		out.put_8(0)
		out.put_u8(roundi(WALK_SPEED_MPS / 0.05))
		out.put_u8(NetCodec.HF_ALIVE)
		out.put_u8(_weapon_index)
		out.put_u8(100)
		out.put_u8(0)
		var inp: StreamPeerBuffer = StreamPeerBuffer.new()
		inp.data_array = out.data_array
		h.net_apply_state(inp)


func _warm_up() -> void:
	var alive: int = _hunt.get_alive_boar_ids().size()
	var all_in: bool = alive >= _hunt.get_boars_total()
	if all_in and alive < TARGET_ALIVE and _hunt.spawner.get_alive().size() > 0:
		# Contract 5 has 25 boars; the 26th (the ceiling of hunt.max_alive_boars) is added by hand.
		_hunt.spawner.call("_spawn_boar", Ids.BOAR, _hunt.spawner.get_alive()[0].herd)
		return
	if alive >= TARGET_ALIVE or _hunt.get_elapsed_s() > WARP_LIMIT_S:
		Engine.time_scale = 1.0
		var take: StreamPeerBuffer = StreamPeerBuffer.new()
		_hunt.net_take_events(take)   # warm-up events (spawns) are not part of the steady rate
		print("NET_PERF warm-up done: alive=%d hunt_s=%.1f wall_s=%.1f" % [alive, _hunt.get_elapsed_s(),
			float(Time.get_ticks_msec() - _start_ms) / 1000.0])
		_phase = 1
		_measure_start_ms = Time.get_ticks_msec()


func _measure(delta: float) -> void:
	_frames += 1
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
	_snap_accum += delta
	var interval: float = 1.0 / float(Data.get_net()["snapshot_hz"])
	if _snap_accum >= interval:
		_snap_accum = fmod(_snap_accum, interval)
		var snap: StreamPeerBuffer = StreamPeerBuffer.new()
		_hunt.net_write_snapshot(snap)
		var ev: StreamPeerBuffer = StreamPeerBuffer.new()
		_hunt.net_take_events(ev)
		_ticks += 1
		_snap_bytes += snap.get_size()
		_snap_max = maxi(_snap_max, snap.get_size())
		if ev.get_size() > 0:
			_event_bytes += ev.get_size()
			_event_ticks += 1
		var alive: int = _hunt.get_alive_boar_ids().size()
		_alive_sum += alive
		_alive_min = mini(_alive_min, alive)
	var wall_s: float = float(Time.get_ticks_msec() - _measure_start_ms) / 1000.0
	if wall_s < MEASURE_S:
		return
	_phase = 2
	var hz: float = float(Data.get_net()["snapshot_hz"])
	var ticks: float = maxf(float(_ticks), 1.0)
	var snap_avg: float = float(_snap_bytes) / ticks
	# One frame per tick on the state lane: record header + frame header; events ride their own frame.
	var app_per_s: float = (snap_avg + NetCodec.RECORD_HEADER_BYTES + NetCodec.FRAME_HEADER_BYTES) * hz \
		+ (float(_event_bytes) + float(_event_ticks) * NetCodec.FRAME_HEADER_BYTES) / ticks * hz
	var wire_per_s: float = app_per_s + (hz + float(_event_ticks) / ticks * hz) * TRANSPORT_BYTES
	print("NET_PERF boars alive avg=%.1f min=%d | hunters=%d | snapshot avg=%.0f B max=%d B | events %.1f B/s"
		% [float(_alive_sum) / ticks, _alive_min, _hunt.get_hunters().size(), snap_avg, _snap_max,
		float(_event_bytes) / ticks * hz])
	print("NET_PERF client download app=%.2f kB/s wire~%.2f kB/s (meta 5 kB/s)" % [app_per_s / 1000.0, wire_per_s / 1000.0])
	print("NET_PERF fps avg=%.1f worst_frame=%.1f ms over %.1f s (headless=%s)" % [float(_frames) / wall_s,
		_worst_frame_ms, wall_s, str(DisplayServer.get_name() == "headless")])
	_quit(0)


func _quit(code: int) -> void:
	Engine.time_scale = 1.0
	Router.set_pending_request(null)
	get_tree().quit(code)


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""
