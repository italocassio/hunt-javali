class_name NetLink
extends RefCounted
## One peer link (docs/multiplayer.md section 4.4): frames with seq/ack on two lanes.
## Every link is born on the RELAY path (binary frames through the room server) and starts sending
## through its direct transport (RTC) once that opens. Receiving is always accepted from both paths.
## Owns no socket: the relay is a sink Callable, the direct transport is a NetLink.Direct.
##
## Frame:  lane u8 | seq u16 | ack u16 | record*          (NetCodec.FRAME_HEADER_BYTES)
## Relay payload (without the to/from byte): { len u16, frame }+

signal path_changed()

const PATH_NONE: int = 0     # same values as the Net.Path enum
const PATH_RELAY: int = 1
const PATH_RTC: int = 2

const SEQ_MASK: int = 0xFFFF
const SEQ_OFFSET: int = 1
const ACK_OFFSET: int = 3
const RELAY_LEN_BYTES: int = 2
const RELAY_FRAMES_PER_MESSAGE: int = 2   # state frame + event frame of the same tick (section 4.3)
const RELAY_BURST: float = 2.0            # capacity of the relay token bucket, in messages
const KEEPALIVE_DIVISOR: int = 3          # an idle direct path sends an ack frame every rtc_stall_s / 3


## Direct transport of a link (the RTC path): one message = one frame, on two channels.
## Implemented by NetRtc (Web) and by the ports of NetLoopback (tests).
class Direct extends RefCounted:
	func poll() -> void:
		pass

	func is_open() -> bool:        # both channels usable
		return false

	func is_failed() -> bool:      # will never open, or died
		return false

	func send_state(_frame: PackedByteArray) -> bool:   # unreliable, unordered
		return false

	func send_event(_frame: PackedByteArray) -> bool:   # reliable, ordered
		return false

	func take_frames() -> Array[PackedByteArray]:       # frames received since the last call
		return []

	func close() -> void:
		pass


var remote_id: int = 0

# Counters (tests, HUD, quota checks).
var sent_relay_messages: int = 0
var sent_direct_frames: int = 0
var received_frames: int = 0
var stale_state_frames: int = 0
var duplicate_event_frames: int = 0
var malformed_frames: int = 0
var oversize_frames: int = 0
var failed_sends: int = 0

var _path: int = PATH_RELAY
var _relay_sink: Callable = Callable()   # func(payload: PackedByteArray) -> bool
var _direct: Direct = null
var _direct_deadline_ms: int = 0
var _max_frame: int = 0
var _max_relay_payload: int = 0
var _window: int = 0
var _relay_hz: float = 0.0
var _relay_interval_ms: int = 0
var _relay_tokens: float = RELAY_BURST
var _clock_ms: int = -1
var _relay_alive: Callable = Callable()  # func() -> bool: the room server socket is still up (optional)
var _stall_ms: int = 0
var _keepalive_ms: int = 0
var _direct_rx_ms: int = 0               # last time anything arrived by the direct path
var _direct_tx_ms: int = 0               # last time anything left by the direct path
var _need_relay_in: bool = false         # L_NEED_RELAY delivered; applied on the next poll
var _downgraded: bool = false
var _stall_watch: bool = true            # false: the owner knows silence is expected (peers are loading a scene)
var _rx_reset_pending: bool = false

# --- send side ---
var _state_seq: int = 0
var _event_seq: int = 0
var _unacked: Array[PackedByteArray] = []     # event frames not acknowledged yet, oldest first
var _out_state: PackedByteArray = PackedByteArray()   # relay: state frame waiting (latest wins)
var _out_events: Array[PackedByteArray] = []  # relay: event frames waiting for the next message
var _ack_owed: bool = false
var _ack_owed_ms: int = 0

# --- receive side ---
var _state_seen: bool = false
var _last_state_seq: int = 0
var _in_state: PackedByteArray = PackedByteArray()    # records of the newest state frame not taken yet
var _delivered_seq: int = 0                   # last event seq delivered in order (the ack we send)
var _early: Dictionary = {}                   # seq -> records of event frames that arrived ahead
var _in_events: Array[PackedByteArray] = []
var _lost: bool = false
var _lost_reason: StringName = &""


## cfg = Data.get_net(). relay_sink: func(payload: PackedByteArray) -> bool.
func setup(cfg: Dictionary, p_remote_id: int, relay_sink: Callable) -> void:
	remote_id = p_remote_id
	_relay_sink = relay_sink
	_max_frame = int(cfg["max_frame_bytes"])
	_window = int(cfg["reliable_window"])
	_relay_hz = float(cfg["relay_hz"])
	_relay_interval_ms = int(1000.0 / _relay_hz)
	_max_relay_payload = RELAY_FRAMES_PER_MESSAGE * (RELAY_LEN_BYTES + _max_frame)
	_stall_ms = int(float(cfg["rtc_stall_s"]) * 1000.0)
	_keepalive_ms = maxi(_stall_ms / KEEPALIVE_DIVISOR, 1)


## Optional probe of the room server socket: a direct path that stalls is only given up while the relay
## is alive (otherwise there is nowhere to go back to).
func set_relay_alive_check(check: Callable) -> void:
	_relay_alive = check


## Attaches the direct transport. If it is not open by deadline_ms (0 = no deadline) it is closed and
## the link stays on the relay until the end of the room.
func set_direct(direct: Direct, deadline_ms: int = 0) -> void:
	_direct = direct
	_direct_deadline_ms = deadline_ms


func get_direct() -> Direct:
	return _direct


func get_path() -> int:
	return _path


func is_lost() -> bool:
	return _lost


func get_lost_reason() -> StringName:
	return _lost_reason


func get_unacked_count() -> int:
	return _unacked.size()


## True once the direct path was given up (it never comes back).
func was_downgraded() -> bool:
	return _downgraded


func has_pending_output() -> bool:
	return not _out_state.is_empty() or not _out_events.is_empty()


# --- sending -------------------------------------------------------------------------------------

## One state frame (lane 0) with these records. On the relay it replaces a state frame still waiting.
func send_state(records: PackedByteArray) -> void:
	if _lost:
		return
	if NetCodec.FRAME_HEADER_BYTES + records.size() > _max_frame:
		_count_oversize(records.size())
		return
	_state_seq = (_state_seq + 1) & SEQ_MASK
	var frame: PackedByteArray = _make_frame(NetCodec.LANE_STATE, _state_seq, records)
	if _path == PATH_RTC:
		_send_direct(frame, false)
	else:
		_out_state = frame


## Event records (type u8, len u16, body)*, split into as many frames (lane 1) as needed.
func send_events(records: PackedByteArray) -> void:
	if _lost or records.is_empty():
		return
	var budget: int = _max_frame - NetCodec.FRAME_HEADER_BYTES
	var size: int = records.size()
	var start: int = 0
	var pos: int = 0
	while pos < size:
		if pos + NetCodec.RECORD_HEADER_BYTES > size:
			push_error("NetLink.send_events: truncated record header")
			break
		var rec_len: int = NetCodec.RECORD_HEADER_BYTES + records.decode_u16(pos + 1)
		if pos + rec_len > size:
			push_error("NetLink.send_events: truncated record body (type 0x%02X)" % records[pos])
			break
		if rec_len > budget:
			_count_oversize(rec_len)
			if pos > start:
				_queue_event_frame(records.slice(start, pos))
			pos += rec_len
			start = pos
			continue
		if pos + rec_len - start > budget:
			_queue_event_frame(records.slice(start, pos))
			start = pos
		pos += rec_len
	if pos > start:
		_queue_event_frame(records.slice(start, pos))


## Sends now everything that is waiting on the relay, ignoring the rate (urgent events, path switch).
func flush_now() -> void:
	if _lost or _path != PATH_RELAY:
		return
	_flush_relay(true)


func _queue_event_frame(records: PackedByteArray) -> void:
	if _lost:
		return
	_event_seq = (_event_seq + 1) & SEQ_MASK
	var frame: PackedByteArray = _make_frame(NetCodec.LANE_EVENT, _event_seq, records)
	_unacked.append(frame)
	if _unacked.size() > _window:
		_set_lost(&"window")
		return
	if _path == PATH_RTC:
		_send_direct(frame, true)
	else:
		_out_events.append(frame)


func _make_frame(lane: int, seq: int, records: PackedByteArray) -> PackedByteArray:
	var frame: PackedByteArray = PackedByteArray()
	frame.resize(NetCodec.FRAME_HEADER_BYTES)
	frame.encode_u8(0, lane)
	frame.encode_u16(SEQ_OFFSET, seq)
	frame.encode_u16(ACK_OFFSET, 0)
	frame.append_array(records)
	return frame


func _send_direct(frame: PackedByteArray, reliable: bool) -> void:
	var out: PackedByteArray = frame.duplicate()
	out.encode_u16(ACK_OFFSET, _delivered_seq)
	var sent: bool = _direct.send_event(out) if reliable else _direct.send_state(out)
	if sent:
		sent_direct_frames += 1
		_direct_tx_ms = _clock_ms
		_ack_owed = false
	else:
		failed_sends += 1


## One relay message = the waiting state frame plus the event frames that fit. all = keep sending
## messages until nothing waits.
func _flush_relay(all: bool) -> void:
	if not _relay_sink.is_valid():
		return
	while true:
		var payload: PackedByteArray = PackedByteArray()
		if not _out_state.is_empty():
			_append_relay_frame(payload, _out_state)
			_out_state = PackedByteArray()
		while not _out_events.is_empty() \
				and payload.size() + RELAY_LEN_BYTES + _out_events[0].size() <= _max_relay_payload:
			_append_relay_frame(payload, _out_events[0])
			_out_events.remove_at(0)
		if payload.is_empty():
			return
		if bool(_relay_sink.call(payload)):
			sent_relay_messages += 1
			_ack_owed = false
		else:
			failed_sends += 1
		if not all:
			return


func _append_relay_frame(payload: PackedByteArray, frame: PackedByteArray) -> void:
	var base: int = payload.size()
	payload.resize(base + RELAY_LEN_BYTES)
	payload.encode_u16(base, frame.size())
	payload.append_array(frame)
	payload.encode_u16(base + RELAY_LEN_BYTES + ACK_OFFSET, _delivered_seq)   # freshest ack


func _count_oversize(size: int) -> void:
	oversize_frames += 1
	if oversize_frames == 1:
		push_error("NetLink: record area of %d bytes does not fit a frame of %d bytes; dropped" % [size, _max_frame])


# --- receiving -----------------------------------------------------------------------------------

## A relay message from the remote peer, already without the leading from byte.
func receive_relay(payload: PackedByteArray) -> void:
	var size: int = payload.size()
	var pos: int = 0
	while pos + RELAY_LEN_BYTES <= size:
		var frame_len: int = payload.decode_u16(pos)
		pos += RELAY_LEN_BYTES
		if frame_len < NetCodec.FRAME_HEADER_BYTES or pos + frame_len > size:
			malformed_frames += 1
			return
		receive_frame(payload.slice(pos, pos + frame_len))
		pos += frame_len


func receive_frame(frame: PackedByteArray) -> void:
	if _lost:
		return
	if frame.size() < NetCodec.FRAME_HEADER_BYTES:
		malformed_frames += 1
		return
	received_frames += 1
	var lane: int = frame[0]
	var seq: int = frame.decode_u16(SEQ_OFFSET)
	_apply_ack(frame.decode_u16(ACK_OFFSET))
	var records: PackedByteArray = frame.slice(NetCodec.FRAME_HEADER_BYTES)
	if lane == NetCodec.LANE_STATE:
		if _state_seen and not NetCodec.seq_newer(seq, _last_state_seq):
			stale_state_frames += 1
			return
		_state_seen = true
		_last_state_seq = seq
		if not records.is_empty():   # an empty state frame only carries the ack
			_in_state = records
	elif lane == NetCodec.LANE_EVENT:
		_receive_event(seq, records)
	else:
		malformed_frames += 1


func _receive_event(seq: int, records: PackedByteArray) -> void:
	if not _ack_owed:
		_ack_owed = true
		_ack_owed_ms = _clock_ms
	var expected: int = (_delivered_seq + 1) & SEQ_MASK
	if seq == expected:
		_delivered_seq = seq
		_deliver_events(records)
		var next: int = (_delivered_seq + 1) & SEQ_MASK
		while _early.has(next):
			_deliver_events(_early[next])
			_early.erase(next)
			_delivered_seq = next
			next = (_delivered_seq + 1) & SEQ_MASK
	elif NetCodec.seq_newer(seq, expected):
		if ((seq - expected) & SEQ_MASK) >= _window:
			_set_lost(&"window")
		elif not _early.has(seq):
			_early[seq] = records
		else:
			duplicate_event_frames += 1
	else:
		duplicate_event_frames += 1


## An event frame delivered in order. The records stay in the area handed to the owner (it ignores
## L_NEED_RELAY); the link only reads the request itself.
func _deliver_events(records: PackedByteArray) -> void:
	_in_events.append(records)
	var size: int = records.size()
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= size:
		if records[pos] == NetCodec.L_NEED_RELAY:
			_need_relay_in = true
		pos += NetCodec.RECORD_HEADER_BYTES + records.decode_u16(pos + 1)


func _apply_ack(ack: int) -> void:
	while not _unacked.is_empty():
		var seq: int = _unacked[0].decode_u16(SEQ_OFFSET)
		if NetCodec.seq_newer(seq, ack):
			return
		_unacked.remove_at(0)


## Records of the newest state frame received since the last call (empty = none).
func take_state() -> PackedByteArray:
	var out: PackedByteArray = _in_state
	_in_state = PackedByteArray()
	return out


## Record areas of the event frames delivered in order since the last call.
func take_events() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = _in_events
	_in_events = []
	return out


# --- clock ---------------------------------------------------------------------------------------

## Call every frame: drains the direct transport, promotes the path and sends the relay message of
## this tick when the rate allows (at most relay_hz messages per second, section 4.3).
func poll(now_ms: int) -> void:
	if _lost:
		return
	if _clock_ms < 0:
		_clock_ms = now_ms
	var gap_ms: int = now_ms - _clock_ms
	_relay_tokens = minf(RELAY_BURST, _relay_tokens + float(gap_ms) * _relay_hz / 1000.0)
	_clock_ms = now_ms
	if _rx_reset_pending or gap_ms * 2 >= _stall_ms:
		# This machine was not polling (hitch while loading a scene, hidden tab): the silence
		# says nothing about the path. The other side gets a fresh window to speak.
		_rx_reset_pending = false
		_direct_rx_ms = now_ms
	if _direct != null:
		_direct.poll()
		var frames: Array[PackedByteArray] = _direct.take_frames()
		if not frames.is_empty():
			_direct_rx_ms = now_ms
		for frame: PackedByteArray in frames:
			receive_frame(frame)
		if _lost:
			return
	if _need_relay_in:
		_need_relay_in = false
		_leave_direct(false)   # the other side gave up its direct path: stop using ours too
	if _direct != null:
		if _path == PATH_RELAY:
			if _direct.is_open():
				_flush_relay(true)   # nothing stays behind on the old path
				_path = PATH_RTC
				_direct_rx_ms = now_ms
				_direct_tx_ms = now_ms
				path_changed.emit()
			elif _direct.is_failed() or (_direct_deadline_ms > 0 and now_ms >= _direct_deadline_ms):
				_direct.close()
				_direct = null       # relay until the end of the room (fallback of decision D4b)
		elif _direct.is_failed() or not _direct.is_open():
			_leave_direct(true)      # died in the middle of the room: failed, closed or channel closed
		elif _stall_watch and now_ms - _direct_rx_ms >= _stall_ms and _is_relay_alive():
			_leave_direct(true)      # silent for rtc_stall_s while the room server answers
	var ack_due: bool = _ack_owed and now_ms - _ack_owed_ms >= _relay_interval_ms
	if _path == PATH_RELAY:
		if (has_pending_output() or ack_due) and _relay_tokens >= 1.0:
			if not has_pending_output():
				_out_state = _make_ack_frame()
			_relay_tokens -= 1.0
			_flush_relay(false)
	elif ack_due:
		# Through the reliable channel: a lost ack-only frame would never be sent again.
		_send_direct(_make_ack_frame(), true)
	elif now_ms - _direct_tx_ms >= _keepalive_ms:
		# Idle direct path: an ack-only frame keeps the other side's stall timer from firing.
		_send_direct(_make_ack_frame(), true)


## The owner pauses the stall watch while silence is expected (the peers are loading a hunt scene and
## do not poll). Resuming gives the other side a fresh rtc_stall_s.
func set_stall_watch(enabled: bool) -> void:
	if enabled and not _stall_watch:
		_rx_reset_pending = true
	_stall_watch = enabled


func _is_relay_alive() -> bool:
	return not _relay_alive.is_valid() or bool(_relay_alive.call())


## Gives up the direct transport for good (no new promotion). If it was carrying the link, goes back to
## sending by RELAY: the event frames not acknowledged are queued again, in order (the other side drops
## the ones it already has), and notify = tell it with L_NEED_RELAY so it does the same.
func _leave_direct(notify: bool) -> void:
	var was_rtc: bool = _path == PATH_RTC
	if _direct != null:
		_direct.close()
		_direct = null
	_direct_deadline_ms = 0
	_downgraded = true
	if not was_rtc:
		return
	_path = PATH_RELAY
	_out_events.clear()
	_out_events.append_array(_unacked)
	if notify:
		var request: PackedByteArray = PackedByteArray()
		request.resize(NetCodec.RECORD_HEADER_BYTES)
		request.encode_u8(0, NetCodec.L_NEED_RELAY)
		request.encode_u16(1, 0)
		_queue_event_frame(request)
	path_changed.emit()


func _make_ack_frame() -> PackedByteArray:
	_state_seq = (_state_seq + 1) & SEQ_MASK
	return _make_frame(NetCodec.LANE_STATE, _state_seq, PackedByteArray())


func close() -> void:
	if _direct != null:
		_direct.close()
		_direct = null
	_relay_sink = Callable()
	_out_state = PackedByteArray()
	_out_events.clear()
	_unacked.clear()
	_early.clear()
	_path = PATH_NONE


func _set_lost(reason: StringName) -> void:
	_lost = true
	_lost_reason = reason
