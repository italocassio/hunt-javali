extends Node
## Sandbox: exercises NetLink over NetLoopback with no socket and no server, then quits.
## Run: tools/godot.sh --headless --path . res://src/net/debug/link_selftest.tscn
## The official tests live in tests/ (qa-tester); this is the package's own smoke check.

const STEP_MS: int = 16            # simulated frame
const TEST_EVENT: int = NetCodec.EV_MESSAGE
const TEST_STATE: int = NetCodec.H_SNAPSHOT

var _failures: int = 0
var _checks: int = 0
var _now: int = 0
var _state_a: int = 0     # newest state value taken by a / b in _exchange
var _state_b: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg: Dictionary = Data.get_net()
	_relay_only(cfg)
	_lossy_direct(cfg)
	_promotion(cfg)
	_ice_deadline(cfg)
	_frame_split(cfg)
	_window_overflow(cfg)
	_relay_rate(cfg)
	_downgrade_resend(cfg)
	_downgrade_stall(cfg)
	_downgrade_notified(cfg)
	_downgrade_rate(cfg)
	_stall_guards(cfg)
	_flush_paths(cfg)
	print("LINK_SELFTEST checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL %s" % label)


func _record(type: int, value: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(NetCodec.RECORD_HEADER_BYTES + 4)
	out.encode_u8(0, type)
	out.encode_u16(1, 4)
	out.encode_u32(NetCodec.RECORD_HEADER_BYTES, value)
	return out


## Values of every record in a record area.
func _values(records: PackedByteArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= records.size():
		var length: int = records.decode_u16(pos + 1)
		if length >= 4:
			out.append(records.decode_u32(pos + NetCodec.RECORD_HEADER_BYTES))
		pos += NetCodec.RECORD_HEADER_BYTES + length
	return out


func _drain_events(link: NetLink, into: PackedInt32Array) -> void:
	for records: PackedByteArray in link.take_events():
		into.append_array(_values(records))


func _in_order(got: PackedInt32Array, count: int) -> bool:
	if got.size() != count:
		return false
	for i: int in count:
		if got[i] != i + 1:
			return false
	return true


## Events both ways and state one way, all through the relay.
func _relay_only(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(11)
	lp.attach(a, b, cfg)
	var got_b: PackedInt32Array = PackedInt32Array()
	var got_a: PackedInt32Array = PackedInt32Array()
	var last_state: int = 0
	var state_ok: bool = true
	var now: int = 0
	for i: int in 400:
		now += STEP_MS
		if i < 300:
			a.send_events(_record(TEST_EVENT, i + 1))
			a.send_state(_record(TEST_STATE, i + 1))
		if i < 100:
			b.send_events(_record(TEST_EVENT, i + 1))
		a.poll(now)
		b.poll(now)
		lp.step()
		a.poll(now)
		b.poll(now)
		_drain_events(b, got_b)
		_drain_events(a, got_a)
		var st: PackedByteArray = b.take_state()
		if not st.is_empty():
			var v: int = _values(st)[0]
			if v <= last_state:
				state_ok = false
			last_state = v
	_ok(_in_order(got_b, 300), "relay: 300 events a->b in order (got %d)" % got_b.size())
	_ok(_in_order(got_a, 100), "relay: 100 events b->a in order (got %d)" % got_a.size())
	_ok(state_ok and last_state == 300, "relay: state only moves forward and ends at the newest (%d)" % last_state)
	_ok(a.get_unacked_count() == 0 and b.get_unacked_count() == 0,
		"relay: everything acknowledged (%d, %d)" % [a.get_unacked_count(), b.get_unacked_count()])
	_ok(a.get_path() == NetLink.PATH_RELAY and not a.is_lost() and not b.is_lost(), "relay: path and health")
	print("relay_only: messages a->b=%d b->a=%d over %d ms" % [lp.relay_messages_ab, lp.relay_messages_ba, now])


## Direct path with 20% loss and reordering on the state channel: events all arrive, in order.
func _lossy_direct(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(22)
	lp.state_loss = 0.2
	lp.state_reorder = 0.2
	lp.attach(a, b, cfg, true)
	lp.open_direct()
	var got_b: PackedInt32Array = PackedInt32Array()
	var got_a: PackedInt32Array = PackedInt32Array()
	var last_state: int = 0
	var state_ok: bool = true
	var states: int = 0
	var now: int = 0
	for i: int in 700:
		now += STEP_MS
		a.poll(now)
		b.poll(now)
		if i < 600:
			a.send_events(_record(TEST_EVENT, i + 1))
			a.send_state(_record(TEST_STATE, i + 1))
			b.send_state(_record(TEST_STATE, i + 1))
		if i < 200:
			b.send_events(_record(TEST_EVENT, i + 1))
		lp.step()
		a.poll(now)
		b.poll(now)
		_drain_events(b, got_b)
		_drain_events(a, got_a)
		var st: PackedByteArray = b.take_state()
		if not st.is_empty():
			var v: int = _values(st)[0]
			if v <= last_state:
				state_ok = false
			last_state = v
			states += 1
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "direct: both promoted")
	_ok(_in_order(got_b, 600), "direct: 600 events a->b in order with lossy state (got %d)" % got_b.size())
	_ok(_in_order(got_a, 200), "direct: 200 events b->a in order (got %d)" % got_a.size())
	_ok(state_ok, "direct: an older state never replaces a newer one")
	_ok(lp.state_lost > 0 and lp.state_reordered > 0, "direct: loss and reorder really happened")
	_ok(states < 600 and states > 300, "direct: some states were lost, most arrived (%d of 600)" % states)
	_ok(a.get_unacked_count() == 0 and b.get_unacked_count() == 0,
		"direct: acks survive the lossy lane (%d, %d)" % [a.get_unacked_count(), b.get_unacked_count()])
	_ok(lp.relay_messages_ab == 0 and lp.relay_messages_ba == 0, "direct: nothing went through the relay")
	print("lossy_direct: state sent=%d lost=%d reordered=%d applied=%d stale=%d" % [lp.state_sent, lp.state_lost,
		lp.state_reordered, states, b.stale_state_frames])


## The direct transport opens in the middle of a stream: nothing is lost or duplicated.
func _promotion(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(33)
	lp.attach(a, b, cfg, true)
	var got_b: PackedInt32Array = PackedInt32Array()
	var changes: Array[int] = [0]
	a.path_changed.connect(func() -> void: changes[0] += 1)
	var now: int = 0
	for i: int in 300:
		now += STEP_MS
		if i == 120:
			lp.open_direct()
		if i < 240:
			a.send_events(_record(TEST_EVENT, i + 1))
		a.poll(now)
		b.poll(now)
		lp.step()
		a.poll(now)
		b.poll(now)
		_drain_events(b, got_b)
	_ok(_in_order(got_b, 240), "promotion: 240 events in order across the switch (got %d)" % got_b.size())
	_ok(a.get_path() == NetLink.PATH_RTC and changes[0] == 1, "promotion: path_changed once (%d)" % changes[0])
	_ok(b.duplicate_event_frames == 0, "promotion: no duplicate event frame")
	_ok(lp.relay_messages_ab > 0 and a.sent_direct_frames > 0, "promotion: both paths carried frames")


## A direct transport that never opens is dropped at the deadline; the link keeps working on the relay.
func _ice_deadline(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(44)
	lp.attach(a, b, cfg)
	a.set_direct(lp.port_a, 1000)
	b.set_direct(lp.port_b, 1000)
	var got_b: PackedInt32Array = PackedInt32Array()
	var now: int = 0
	for i: int in 150:
		now += STEP_MS
		if i == 100:
			lp.open_direct()   # too late: the deadline already closed it
		if i < 120:
			a.send_events(_record(TEST_EVENT, i + 1))
		a.poll(now)
		b.poll(now)
		lp.step()
		a.poll(now)
		b.poll(now)
		_drain_events(b, got_b)
	_ok(a.get_direct() == null and b.get_direct() == null, "deadline: direct transport dropped")
	_ok(a.get_path() == NetLink.PATH_RELAY, "deadline: stays on the relay")
	_ok(_in_order(got_b, 120), "deadline: events keep flowing (got %d)" % got_b.size())


## A batch bigger than one frame is split on record boundaries.
func _frame_split(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(55)
	lp.attach(a, b, cfg)
	var batch: PackedByteArray = PackedByteArray()
	for i: int in 500:   # 500 x 7 bytes = 3500 bytes: at least 4 frames of 1100
		batch.append_array(_record(TEST_EVENT, i + 1))
	a.send_events(batch)
	var frames: int = a.get_unacked_count()
	var got_b: PackedInt32Array = PackedInt32Array()
	var now: int = 0
	for i: int in 60:
		now += STEP_MS
		a.poll(now)
		b.poll(now)
		lp.step()
		a.poll(now)
		b.poll(now)
		_drain_events(b, got_b)
	var max_frame: int = int(cfg["max_frame_bytes"])
	_ok(frames >= 4, "split: %d frames for 3500 bytes" % frames)
	_ok(_in_order(got_b, 500), "split: 500 records in order (got %d)" % got_b.size())
	_ok(lp.relay_bytes_ab <= lp.relay_messages_ab * 2 * (max_frame + 2), "split: no relay message above the limit")
	_ok(a.oversize_frames == 0, "split: nothing dropped")


## More unacknowledged event frames than the window = link lost.
func _window_overflow(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(66)
	lp.attach(a, b, cfg)
	var window: int = int(cfg["reliable_window"])
	for i: int in window:
		a.send_events(_record(TEST_EVENT, i + 1))
	_ok(not a.is_lost(), "window: exactly the window is still fine")
	a.send_events(_record(TEST_EVENT, window + 1))
	_ok(a.is_lost() and a.get_lost_reason() == &"window", "window: one more loses the link")


## On the relay a link sends at most relay_hz messages per second (plus the initial burst).
func _relay_rate(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(77)
	lp.attach(a, b, cfg)
	var hz: float = float(cfg["relay_hz"])
	var seconds: int = 10
	var now: int = 0
	var applied: int = 0
	for i: int in seconds * 1000:   # 1000 simulated frames per second, a state frame on every one
		now += 1
		a.send_state(_record(TEST_STATE, i + 1))
		a.poll(now)
		lp.step()
		b.poll(now)
		if not b.take_state().is_empty():
			applied += 1
	var limit: int = int(hz * seconds + NetLink.RELAY_BURST)
	_ok(lp.relay_messages_ab <= limit, "rate: %d messages in %d s (limit %d)" % [lp.relay_messages_ab, seconds, limit])
	_ok(lp.relay_messages_ab >= int(hz * seconds) - 1, "rate: not starved (%d)" % lp.relay_messages_ab)
	_ok(lp.relay_messages_ba <= limit, "rate: acks do not exceed the rate either (%d)" % lp.relay_messages_ba)
	print("relay_rate: a->b=%d b->a=%d applied=%d in %d s" % [lp.relay_messages_ab, lp.relay_messages_ba, applied, seconds])


# --- path downgrade (section 4.4) -----------------------------------------------------------------

## One simulated frame of both links: poll, one network hop, poll, then take everything delivered.
func _exchange(a: NetLink, b: NetLink, lp: NetLoopback, got_a: PackedInt32Array, got_b: PackedInt32Array) -> void:
	_now += STEP_MS
	a.poll(_now)
	b.poll(_now)
	lp.step()
	a.poll(_now)
	b.poll(_now)
	_drain_events(a, got_a)
	_drain_events(b, got_b)
	var st_a: PackedByteArray = a.take_state()
	if not st_a.is_empty():
		_state_a = _values(st_a)[0]
	var st_b: PackedByteArray = b.take_state()
	if not st_b.is_empty():
		_state_b = _values(st_b)[0]


## Two links with the direct transport open and already promoted.
func _promoted_pair(cfg: Dictionary, seed_value: int) -> Array:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(seed_value)
	lp.attach(a, b, cfg, true)
	lp.open_direct()
	_now = 0
	_state_a = 0
	_state_b = 0
	var sink: PackedInt32Array = PackedInt32Array()
	for i: int in 10:
		_exchange(a, b, lp, sink, sink)
	return [a, b, lp]


## 5 events not acknowledged when the path dies: all 5 arrive, once, in order.
func _downgrade_resend(cfg: Dictionary) -> void:
	# (1) the 5 frames were lost together with the path.
	var pair: Array = _promoted_pair(cfg, 101)
	var a: NetLink = pair[0]
	var b: NetLink = pair[1]
	var lp: NetLoopback = pair[2]
	var got_a: PackedInt32Array = PackedInt32Array()
	var got_b: PackedInt32Array = PackedInt32Array()
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "resend: promoted before the failure")
	for i: int in 5:
		a.send_events(_record(TEST_EVENT, i + 1))
	_ok(a.get_unacked_count() == 5, "resend: 5 events unacknowledged (%d)" % a.get_unacked_count())
	lp.fail_direct()
	for i: int in 40:
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RELAY and b.get_path() == NetLink.PATH_RELAY, "resend: both back on the relay")
	_ok(_in_order(got_b, 5), "resend: 5 events delivered once, in order, when lost in flight (got %d)" % got_b.size())
	_ok(a.get_unacked_count() == 0 and not a.is_lost() and not b.is_lost(), "resend: acknowledged and healthy")
	# After the downgrade the link goes on working, and the old path is never used again.
	for i: int in 5:
		a.send_events(_record(TEST_EVENT, i + 6))
	for i: int in 40:
		_exchange(a, b, lp, got_a, got_b)
	_ok(_in_order(got_b, 10), "resend: events keep flowing on the relay (got %d)" % got_b.size())
	lp.port_a.failed = false
	lp.port_b.failed = false
	lp.open_direct()
	for i: int in 20:
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RELAY and a.get_direct() == null, "resend: no new promotion after the downgrade")

	# (2) the 5 frames reached the other side, the acknowledgement did not come back: no duplicate delivery.
	pair = _promoted_pair(cfg, 102)
	a = pair[0]
	b = pair[1]
	lp = pair[2]
	got_a = PackedInt32Array()
	got_b = PackedInt32Array()
	for i: int in 5:
		a.send_events(_record(TEST_EVENT, i + 1))
	lp.step()
	b.poll(_now)
	_drain_events(b, got_b)
	_ok(_in_order(got_b, 5) and a.get_unacked_count() == 5, "resend: delivered over the direct path, ack still owed")
	lp.fail_direct()
	for i: int in 40:
		_exchange(a, b, lp, got_a, got_b)
	_ok(_in_order(got_b, 5), "resend: still exactly 5 after the resend (got %d)" % got_b.size())
	_ok(b.duplicate_event_frames >= 5, "resend: the repeats were really sent and dropped (%d)" % b.duplicate_event_frames)
	_ok(a.get_unacked_count() == 0, "resend: and acknowledged (%d)" % a.get_unacked_count())


## The direct path stays "open" but stops delivering: after rtc_stall_s both sides go to the relay and
## everything sent meanwhile still arrives, once and in order.
func _downgrade_stall(cfg: Dictionary) -> void:
	var stall_ms: int = int(float(cfg["rtc_stall_s"]) * 1000.0)
	var pair: Array = _promoted_pair(cfg, 111)
	var a: NetLink = pair[0]
	var b: NetLink = pair[1]
	var lp: NetLoopback = pair[2]
	var got_a: PackedInt32Array = PackedInt32Array()
	var got_b: PackedInt32Array = PackedInt32Array()
	var sent_a: int = 0
	var sent_b: int = 0
	var t_stall: int = 0
	var t_a: int = -1
	var t_b: int = -1
	for i: int in 700:
		if i == 100:
			lp.stall_direct = true
			t_stall = _now
			_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "stall: on the direct path until the stall")
		if i < 500:
			a.send_state(_record(TEST_STATE, i + 1))
			b.send_state(_record(TEST_STATE, i + 1))
			if i % 8 == 0:
				sent_a += 1
				a.send_events(_record(TEST_EVENT, sent_a))
				sent_b += 1
				b.send_events(_record(TEST_EVENT, sent_b))
		_exchange(a, b, lp, got_a, got_b)
		if i >= 100:
			if t_a < 0 and a.get_path() == NetLink.PATH_RELAY:
				t_a = _now - t_stall
			if t_b < 0 and b.get_path() == NetLink.PATH_RELAY:
				t_b = _now - t_stall
	var first: int = mini(t_a, t_b)
	_ok(t_a > 0 and t_b > 0, "stall: both sides went to the relay (a %d ms, b %d ms)" % [t_a, t_b])
	_ok(first >= stall_ms - STEP_MS and first <= stall_ms + 2 * STEP_MS + 300,
		"stall: downgrade after rtc_stall_s=%d ms, not before (%d ms)" % [stall_ms, first])
	_ok(lp.direct_dropped > 0, "stall: the simulated path really swallowed frames (%d)" % lp.direct_dropped)
	_ok(_in_order(got_b, sent_a), "stall: %d events a->b once and in order (got %d)" % [sent_a, got_b.size()])
	_ok(_in_order(got_a, sent_b), "stall: %d events b->a once and in order (got %d)" % [sent_b, got_a.size()])
	_ok(_state_b == 500 and _state_a == 500,
		"stall: state flows by the relay up to the last one (a=%d b=%d)" % [_state_a, _state_b])
	_ok(a.get_unacked_count() == 0 and b.get_unacked_count() == 0 and not a.is_lost() and not b.is_lost(),
		"stall: everything acknowledged and healthy (%d, %d)" % [a.get_unacked_count(), b.get_unacked_count()])
	_ok(a.was_downgraded() and b.was_downgraded(), "stall: marked as downgraded")
	print("downgrade_stall: a %d ms, b %d ms after the stall (rtc_stall_s=%d ms), relay messages a->b=%d b->a=%d" % [
		t_a, t_b, stall_ms, lp.relay_messages_ab, lp.relay_messages_ba])


## Only one side notices (its port dies): it sends L_NEED_RELAY and the other side also goes to the relay,
## long before its own stall timer, resending what it had sent on the dead path.
func _downgrade_notified(cfg: Dictionary) -> void:
	var stall_ms: int = int(float(cfg["rtc_stall_s"]) * 1000.0)
	var pair: Array = _promoted_pair(cfg, 121)
	var a: NetLink = pair[0]
	var b: NetLink = pair[1]
	var lp: NetLoopback = pair[2]
	var got_a: PackedInt32Array = PackedInt32Array()
	var got_b: PackedInt32Array = PackedInt32Array()
	var sent_a: int = 0
	var sent_b: int = 0
	var t_kill: int = 0
	var t_b: int = -1
	var relay_ba_at_kill: int = 0
	for i: int in 180:
		if i == 20:
			lp.kill_port(lp.port_a)
			t_kill = _now
			relay_ba_at_kill = lp.relay_messages_ba
			_ok(b.get_path() == NetLink.PATH_RTC, "notified: b has no reason of its own to leave the direct path yet")
		if i % 3 == 0 and i < 100:
			sent_a += 1
			a.send_events(_record(TEST_EVENT, sent_a))
			sent_b += 1
			b.send_events(_record(TEST_EVENT, sent_b))
		_exchange(a, b, lp, got_a, got_b)
		if i >= 20 and t_b < 0 and b.get_path() == NetLink.PATH_RELAY:
			t_b = _now - t_kill
	_ok(a.get_path() == NetLink.PATH_RELAY, "notified: a (port dead) is on the relay")
	_ok(t_b > 0 and t_b < stall_ms / 2, "notified: b followed L_NEED_RELAY (%d ms, own stall timer is %d ms)" % [t_b, stall_ms])
	_ok(b.get_direct() == null and b.was_downgraded(), "notified: b dropped its direct transport")
	_ok(lp.relay_messages_ba > relay_ba_at_kill, "notified: b now sends through the relay (%d new messages)" % (lp.relay_messages_ba - relay_ba_at_kill))
	_ok(_in_order(got_a, sent_b), "notified: %d events b->a once and in order (got %d)" % [sent_b, got_a.size()])
	_ok(_in_order(got_b, sent_a), "notified: %d events a->b once and in order (got %d)" % [sent_a, got_b.size()])
	_ok(a.get_unacked_count() == 0 and b.get_unacked_count() == 0, "notified: everything acknowledged")


## After the downgrade a link never sends more than relay_hz messages per second per direction
## (plus the bucket's initial burst), even with a state frame and events on every frame.
func _downgrade_rate(cfg: Dictionary) -> void:
	var hz: float = float(cfg["relay_hz"])
	var pair: Array = _promoted_pair(cfg, 131)
	var a: NetLink = pair[0]
	var b: NetLink = pair[1]
	var lp: NetLoopback = pair[2]
	var got_a: PackedInt32Array = PackedInt32Array()
	var got_b: PackedInt32Array = PackedInt32Array()
	var sent_a: int = 0
	var t_down: int = -1
	var window_start: int = 0
	var ab_at_start: int = 0
	var ba_at_start: int = 0
	var worst: int = 0
	var ab_total_at_down: int = 0
	var ba_total_at_down: int = 0
	lp.stall_direct = true
	for i: int in 800:
		a.send_state(_record(TEST_STATE, i + 1))
		b.send_state(_record(TEST_STATE, i + 1))
		if i % 8 == 0:
			sent_a += 1
			a.send_events(_record(TEST_EVENT, sent_a))
		_exchange(a, b, lp, got_a, got_b)
		if t_down < 0 and (a.get_path() == NetLink.PATH_RELAY or b.get_path() == NetLink.PATH_RELAY):
			t_down = _now
			window_start = _now - STEP_MS
			ab_at_start = lp.relay_messages_ab
			ba_at_start = lp.relay_messages_ba
			ab_total_at_down = ab_at_start
			ba_total_at_down = ba_at_start
		elif t_down >= 0 and _now - window_start >= 1000:
			worst = maxi(worst, maxi(lp.relay_messages_ab - ab_at_start, lp.relay_messages_ba - ba_at_start))
			window_start = _now
			ab_at_start = lp.relay_messages_ab
			ba_at_start = lp.relay_messages_ba
	var limit: int = int(hz + NetLink.RELAY_BURST)
	var span_s: float = float(_now - t_down) / 1000.0
	var total_limit: int = int(hz * span_s + NetLink.RELAY_BURST)
	var total_ab: int = lp.relay_messages_ab - ab_total_at_down
	var total_ba: int = lp.relay_messages_ba - ba_total_at_down
	_ok(t_down > 0, "relay rate: the stall was detected")
	_ok(worst <= limit, "relay rate: at most %d messages in any 1 s window per direction (worst %d)" % [limit, worst])
	_ok(total_ab <= total_limit and total_ba <= total_limit,
		"relay rate: %d / %d messages in %.1f s (limit %d)" % [total_ab, total_ba, span_s, total_limit])
	_ok(total_ab >= int(hz * span_s) - 2 and total_ba >= int(hz * span_s) - 2,
		"relay rate: not starved (%d / %d)" % [total_ab, total_ba])
	_ok(_in_order(got_b, sent_a), "relay rate: %d events still arrive in order (got %d)" % [sent_a, got_b.size()])
	print("downgrade_rate: relay_hz=%d, worst 1 s window=%d, total a->b=%d b->a=%d in %.1f s" % [int(hz), worst, total_ab, total_ba, span_s])


## An idle direct path is not mistaken for a dead one, and a dead room server never triggers the
## downgrade (there would be nowhere to go).
func _stall_guards(cfg: Dictionary) -> void:
	var pair: Array = _promoted_pair(cfg, 141)
	var a: NetLink = pair[0]
	var b: NetLink = pair[1]
	var lp: NetLoopback = pair[2]
	var got_a: PackedInt32Array = PackedInt32Array()
	var got_b: PackedInt32Array = PackedInt32Array()
	for i: int in 800:   # about 13 s with nothing to say
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC and not a.was_downgraded(),
		"guards: an idle direct path stays (keepalive)")
	lp.stall_direct = true
	lp.relay_enabled = false
	for i: int in 500:
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "guards: no downgrade while the room server is down")
	lp.relay_enabled = true
	for i: int in 30:
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RELAY and b.get_path() == NetLink.PATH_RELAY, "guards: downgrade as soon as the relay is back")

	# Peers loading a scene do not poll: the owner pauses the watch; resuming gives a fresh window.
	pair = _promoted_pair(cfg, 142)
	a = pair[0]
	b = pair[1]
	lp = pair[2]
	var stall_ms: int = int(float(cfg["rtc_stall_s"]) * 1000.0)
	a.set_stall_watch(false)
	b.set_stall_watch(false)
	lp.stall_direct = true
	for i: int in 700:   # about 11 s of silence
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "guards: no downgrade while the watch is paused")
	a.set_stall_watch(true)
	b.set_stall_watch(true)
	_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "guards: resuming does not downgrade at once")
	for i: int in (stall_ms / STEP_MS) + 20:
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RELAY and b.get_path() == NetLink.PATH_RELAY, "guards: but a path still silent after rtc_stall_s goes")

	# A local hitch (this machine stopped polling for 12 s) is not path silence either.
	pair = _promoted_pair(cfg, 143)
	a = pair[0]
	b = pair[1]
	lp = pair[2]
	_now += 12000
	for i: int in 30:
		_exchange(a, b, lp, got_a, got_b)
	_ok(a.get_path() == NetLink.PATH_RTC and b.get_path() == NetLink.PATH_RTC, "guards: a local hitch of 12 s does not downgrade")


## Net.flush() (end of hunt): what is queued leaves at once, ignoring the relay rate, and on the direct
## path it already left in send_events. The sender is not polled again before the receiver looks.
func _flush_paths(cfg: Dictionary) -> void:
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(151)
	lp.attach(a, b, cfg)
	_now = 0
	var got_a: PackedInt32Array = PackedInt32Array()
	var got_b: PackedInt32Array = PackedInt32Array()
	for i: int in 10:
		_exchange(a, b, lp, got_a, got_b)
	for i: int in 6:   # empty the relay token bucket: a normal send would now have to wait for the rate
		a.send_events(_record(TEST_EVENT, 100 + i))
		a.poll(_now)
	a.send_events(_record(TEST_EVENT, 200))
	a.flush_now()
	_ok(not a.has_pending_output(), "flush relay: nothing left waiting in the sender")
	lp.step()
	b.poll(_now)
	_drain_events(b, got_b)
	_ok(got_b.has(200), "flush relay: the record reached the other side without another poll of the sender (%s)" % str(got_b))

	var pair: Array = _promoted_pair(cfg, 152)
	a = pair[0]
	b = pair[1]
	lp = pair[2]
	got_b = PackedInt32Array()
	_ok(a.get_path() == NetLink.PATH_RTC, "flush direct: promoted")
	a.send_events(_record(TEST_EVENT, 300))
	a.flush_now()   # nothing to do on the direct path: it was sent above
	lp.step()
	b.poll(_now)
	_drain_events(b, got_b)
	_ok(got_b == PackedInt32Array([300]), "flush direct: the record is already on the other side (%s)" % str(got_b))
