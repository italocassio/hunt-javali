class_name NetRtc
extends NetLink.Direct
## Direct transport over WebRTC (docs/multiplayer.md section 4.2): one WebRTCPeerConnection and two
## pre-negotiated data channels, "event" (reliable, ordered) and "state" (unordered, no retransmit).
## Only instantiated in the Web build: native Godot has no WebRTC without an extension.
## The client is the offerer; the host only answers. Signaling goes out through signal_sink and comes
## in through handle_signal(); the room server relays it without reading.

const CHANNEL_EVENT: String = "event"
const CHANNEL_STATE: String = "state"
const CHANNEL_EVENT_ID: int = 1
const CHANNEL_STATE_ID: int = 2
const KIND_OFFER: String = "offer"
const KIND_ANSWER: String = "answer"
const KIND_CANDIDATE: String = "candidate"

var _pc: WebRTCPeerConnection = null
var _event_channel: WebRTCDataChannel = null
var _state_channel: WebRTCDataChannel = null
var _signal_sink: Callable = Callable()   # func(data: Dictionary) -> void
var _offerer: bool = false
var _drop_ice: bool = false
var _remote_set: bool = false
var _pending_candidates: Array[Dictionary] = []
var _failed: bool = false
var _frames: Array[PackedByteArray] = []


## ice_servers = net.ice_servers. drop_ice = never send candidates (test: forces the ICE timeout).
## False when WebRTC is not usable here; the link then simply stays on the relay.
func start(ice_servers: Array, offerer: bool, drop_ice: bool, signal_sink: Callable) -> bool:
	_offerer = offerer
	_drop_ice = drop_ice
	_signal_sink = signal_sink
	_pc = WebRTCPeerConnection.new()
	if _pc.initialize({"iceServers": [{"urls": ice_servers}]}) != OK:
		_fail()
		return false
	_pc.session_description_created.connect(_on_session_description)
	_pc.ice_candidate_created.connect(_on_ice_candidate)
	_event_channel = _pc.create_data_channel(CHANNEL_EVENT, {"negotiated": true, "id": CHANNEL_EVENT_ID})
	_state_channel = _pc.create_data_channel(CHANNEL_STATE,
		{"negotiated": true, "id": CHANNEL_STATE_ID, "ordered": false, "maxRetransmits": 0})
	if _event_channel == null or _state_channel == null:
		_fail()
		return false
	_event_channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	_state_channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	if _offerer and _pc.create_offer() != OK:
		_fail()
		return false
	return true


## data of a {"t":"signal"} message from the remote peer.
func handle_signal(data: Dictionary) -> void:
	if _pc == null:
		return
	var kind: String = str(data.get("kind", ""))
	if kind == KIND_CANDIDATE:
		if _remote_set:
			_add_candidate(data)
		else:
			_pending_candidates.append(data)
		return
	# The offerer only takes an answer and the answerer only takes an offer.
	if kind != (KIND_ANSWER if _offerer else KIND_OFFER) or _remote_set:
		return
	if _pc.set_remote_description(kind, str(data.get("sdp", ""))) != OK:
		_fail()
		return
	_remote_set = true
	for candidate: Dictionary in _pending_candidates:
		_add_candidate(candidate)
	_pending_candidates.clear()


func _add_candidate(data: Dictionary) -> void:
	_pc.add_ice_candidate(str(data.get("media", "")), int(data.get("index", 0)), str(data.get("name", "")))


func _on_session_description(type: String, sdp: String) -> void:
	if _pc == null:
		return
	_pc.set_local_description(type, sdp)
	if _signal_sink.is_valid():
		_signal_sink.call({"kind": type, "sdp": sdp})


func _on_ice_candidate(media: String, index: int, candidate_name: String) -> void:
	if _drop_ice or not _signal_sink.is_valid():
		return
	_signal_sink.call({"kind": KIND_CANDIDATE, "media": media, "index": index, "name": candidate_name})


func poll() -> void:
	if _pc == null:
		return
	_pc.poll()
	var state: int = _pc.get_connection_state()
	if state == WebRTCPeerConnection.STATE_FAILED or state == WebRTCPeerConnection.STATE_CLOSED:
		_failed = true
		return
	_drain(_event_channel)
	_drain(_state_channel)


func _drain(channel: WebRTCDataChannel) -> void:
	while channel.get_available_packet_count() > 0:
		_frames.append(channel.get_packet())


func is_open() -> bool:
	return _pc != null and not _failed \
		and _event_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN \
		and _state_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN


func is_failed() -> bool:
	return _failed


func send_state(frame: PackedByteArray) -> bool:
	return is_open() and _state_channel.put_packet(frame) == OK


func send_event(frame: PackedByteArray) -> bool:
	return is_open() and _event_channel.put_packet(frame) == OK


func take_frames() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = _frames
	_frames = []
	return out


func close() -> void:
	_signal_sink = Callable()
	if _event_channel != null:
		_event_channel.close()
	if _state_channel != null:
		_state_channel.close()
	if _pc != null:
		_pc.close()
	_event_channel = null
	_state_channel = null
	_pc = null
	_failed = true


func _fail() -> void:
	_failed = true
	if _pc != null:
		_pc.close()
	_pc = null
