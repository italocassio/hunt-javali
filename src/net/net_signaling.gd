class_name NetSignaling
extends RefCounted
## WebSocket to the room server (docs/multiplayer.md sections 4.2 and 4.3): the request goes in the
## URL, room and signaling messages are JSON text frames, relay frames are binary ([to u8] payload out,
## [from u8] payload in). Knows nothing about rooms: it only moves messages and watches the socket.

enum State { IDLE, CONNECTING, OPEN, CLOSING, CLOSED }

const PING_TEXT: String = "{\"t\":\"ping\"}"
const LEAVE_TEXT: String = "{\"t\":\"leave\"}"
const CLOSE_NORMAL: int = 1000

var close_code: int = -1
var close_reason: String = ""
var timed_out: bool = false       # connect or pong deadline expired

# Counters (quota checks).
var sent_text: int = 0
var sent_binary: int = 0
var received_binary: int = 0

var _ws: WebSocketPeer = null
var _state: int = State.IDLE
var _connect_deadline_ms: int = 0
var _ping_ms: int = 0
var _pong_timeout_ms: int = 0
var _next_ping_ms: int = 0
var _pong_deadline_ms: int = 0
var _last_poll_ms: int = 0
var _messages: Array[Dictionary] = []
var _relay_from: PackedInt32Array = PackedInt32Array()
var _relay_payloads: Array[PackedByteArray] = []


static func build_url(base: String, params: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in params:
		parts.append("%s=%s" % [key, str(params[key]).uri_encode()])
	return base + ("&" if base.contains("?") else "?") + "&".join(parts)


## cfg = Data.get_net(). False when the connection could not even start.
func open(url: String, cfg: Dictionary, now_ms: int) -> bool:
	_ping_ms = int(float(cfg["ping_s"]) * 1000.0)
	_pong_timeout_ms = int(float(cfg["pong_timeout_s"]) * 1000.0)
	_connect_deadline_ms = now_ms + int(float(cfg["connect_timeout_s"]) * 1000.0)
	_ws = WebSocketPeer.new()
	if _ws.connect_to_url(url) != OK:
		_ws = null
		_state = State.CLOSED
		return false
	_state = State.CONNECTING
	return true


func get_state() -> int:
	return _state


func is_open() -> bool:
	return _state == State.OPEN


func is_closed() -> bool:
	return _state == State.CLOSED


func poll(now_ms: int) -> void:
	if _ws == null:
		return
	var gap_ms: int = now_ms - _last_poll_ms if _last_poll_ms > 0 else 0
	_last_poll_ms = now_ms
	_ws.poll()
	_read_packets()
	var ready: int = _ws.get_ready_state()
	if ready == WebSocketPeer.STATE_CLOSED:
		close_code = _ws.get_close_code()
		close_reason = _ws.get_close_reason()
		_ws = null
		_state = State.CLOSED
		return
	if _state == State.CLOSING:
		if now_ms >= _connect_deadline_ms:   # the close handshake never came back
			_ws = null
			_state = State.CLOSED
		return
	if ready == WebSocketPeer.STATE_CONNECTING:
		if now_ms >= _connect_deadline_ms:
			_abort()
		return
	if ready != WebSocketPeer.STATE_OPEN:
		return
	if _state == State.CONNECTING:
		_state = State.OPEN
		_next_ping_ms = now_ms + _ping_ms
	if _pong_deadline_ms > 0 and gap_ms * 2 >= _pong_timeout_ms:
		# This machine was not polling (frozen tab): the pong may be sitting in a buffer that was not
		# read yet, so the server gets a fresh window instead of being declared dead.
		_pong_deadline_ms = now_ms + _pong_timeout_ms
	if _pong_deadline_ms > 0 and now_ms >= _pong_deadline_ms:
		_abort()
		return
	if now_ms >= _next_ping_ms:
		_next_ping_ms = now_ms + _ping_ms
		if _ws.send_text(PING_TEXT) == OK:
			sent_text += 1
			if _pong_deadline_ms == 0:
				_pong_deadline_ms = now_ms + _pong_timeout_ms


func _abort() -> void:
	timed_out = true
	_ws.close()
	_ws = null
	_state = State.CLOSED


func _read_packets() -> void:
	while _ws.get_available_packet_count() > 0:
		var packet: PackedByteArray = _ws.get_packet()
		if _ws.was_string_packet():
			var json: JSON = JSON.new()
			if json.parse(packet.get_string_from_utf8()) != OK or not json.data is Dictionary:
				continue
			var msg: Dictionary = json.data
			if str(msg.get("t", "")) == "pong":
				_pong_deadline_ms = 0
			else:
				_messages.append(msg)
		elif packet.size() >= 1:
			received_binary += 1
			_relay_from.append(packet[0])
			_relay_payloads.append(packet.slice(1))


## JSON messages received since the last call, in order (pong is consumed here).
func take_messages() -> Array[Dictionary]:
	var out: Array[Dictionary] = _messages
	_messages = []
	return out


## Relay messages received since the last call: [from ids, payloads], same order and size.
func take_relay() -> Array:
	var out: Array = [_relay_from, _relay_payloads]
	_relay_from = PackedInt32Array()
	_relay_payloads = []
	return out


func send_json(msg: Dictionary) -> bool:
	if _state != State.OPEN or _ws == null:
		return false
	if _ws.send_text(JSON.stringify(msg)) != OK:
		return false
	sent_text += 1
	return true


## Pushes what send_* queued onto the wire now instead of at the next poll (native sockets write in poll).
func flush() -> void:
	if _ws != null and _state == State.OPEN:
		_ws.poll()


func send_relay(to_id: int, payload: PackedByteArray) -> bool:
	if _state != State.OPEN or _ws == null:
		return false
	var message: PackedByteArray = PackedByteArray([to_id])
	message.append_array(payload)
	if _ws.send(message, WebSocketPeer.WRITE_MODE_BINARY) != OK:
		return false
	sent_binary += 1
	return true


## Starts closing. Keep calling poll() until is_closed() so the close frame really leaves.
func close(now_ms: int, say_leave: bool = true) -> void:
	if _ws == null:
		_state = State.CLOSED
		return
	if _state == State.OPEN:
		if say_leave and _ws.send_text(LEAVE_TEXT) == OK:
			sent_text += 1
		_ws.close(CLOSE_NORMAL, "leave")
		_ws.poll()
		_state = State.CLOSING
		_connect_deadline_ms = now_ms + _pong_timeout_ms
	else:
		_ws.close()
		_ws = null
		_state = State.CLOSED
