class_name NetSession
extends RefCounted
## One multiplayer room seen from this machine (docs/multiplayer.md sections 3.4, 4 and 6.9):
## socket to the room server, roster, lobby records, one NetLink per remote peer, tick clock and
## dispatch of hunt records to the bound HuntWorld. The autoload Net owns at most one session and
## forwards its signals; nothing outside src/net references this class.

signal state_changed(state: int)
signal failed(code: StringName, message: String)   # the session is already closed when this fires
signal roster_changed()
signal hunt_go()
signal stall_changed(stalled: bool)
signal reconnect_changed(active: bool)   # client: true = trying to get back into the hunt, false = it is back

# Same values as the enums of the autoload Net (Role, RoomState).
const ROLE_OFFLINE: int = 0
const ROLE_HOST: int = 1
const ROLE_CLIENT: int = 2
const STATE_NONE: int = 0
const STATE_CONNECTING: int = 1
const STATE_LOBBY: int = 2
const STATE_LOADING: int = 3
const STATE_IN_HUNT: int = 4

const HOST_ID: int = 1            # peer id of the host; slot = id - 1
const CREATE_RETRIES: int = 3     # "create" that lands on a code in use (section 4.2)
const NO_INDEX: int = 255         # "none" for weapon / dog / map indices on the wire
const CODE_MAX_CHARS: int = 16
const L_READY_BYTES: int = 8
const L_LOBBY_HEADER_BYTES: int = 4
const L_LOBBY_ENTRY_BYTES: int = 4
const L_START_HEADER_BYTES: int = 8
const L_START_MASK_AT: int = 7    # map u8, contract u8, rng_seed u32, player_count u8, then slots_mask u8
const LOBBY_FLAG_READY: int = 1
const LOBBY_FLAG_HOST: int = 2
const LOBBY_FLAG_LOADED: int = 4
const LOBBY_FLAG_RTC: int = 8
const DEFAULT_NAME: String = "Caçador %d"
const HOST_V_UNKNOWN: String = "?"
const EPOCH_MAX: int = 15         # link epochs of the re-entries cycle through 1..15; 0 is the first link
const APP_CLOSE_MIN: int = 4400   # close codes the room server chooses (section 4.2): never retried
const APP_CLOSE_MAX: int = 4429
const TRAFFIC_WINDOW_MS: int = 1000

## WebSocket close codes of the room server (section 4.2). The server sends {"t":"error"} and closes right
## away; native Godot drops a text frame that arrives together with the close, so the close code is what
## always survives. The close reason is the error name, optionally followed by " <host version>".
const CLOSE_CODES: Dictionary = {
	4400: &"bad_request", 4403: &"room_full", 4404: &"room_not_found", 4408: &"expired", 4409: &"retry",
	4410: &"host_left", 4413: &"too_big", 4423: &"in_progress", 4426: &"version_mismatch", 4429: &"rate_limited",
	4401: &"bad_token", 4411: &"replaced",
}

## Player-facing texts of Net.room_error (section 6.11).
const MESSAGES: Dictionary = {
	&"not_configured": "O modo com amigos ainda não foi configurado.",
	&"server_unreachable": "O servidor de salas está indisponível agora. Ele é gratuito e tem um limite diário, que renova às 21h (horário de Brasília). Tente mais tarde. O modo solo funciona normalmente.",
	&"room_not_found": "Sala não encontrada. Confira o código.",
	&"room_full": "A sala já está cheia (%d caçadores).",
	&"in_progress": "A caçada dessa sala já começou. Espere ela terminar.",
	&"version_mismatch": "Sua versão (%s) é diferente da do anfitrião (%s). Recarregue a página para atualizar.",
	&"version_mismatch_unknown": "Sua versão (%s) é diferente da do anfitrião. Recarregue a página para atualizar.",
	&"host_left": "O anfitrião saiu. A sala foi fechada.",
	&"connection_lost": "Conexão perdida.",
}

var _cfg: Dictionary = {}
var _url: String = ""
var _version: String = ""
var _name: String = ""
var _rtc: bool = false
var _drop_ice: bool = false
var _use_router: bool = true           # false: tests drive LOADING themselves, nothing changes scene

var _role: int = ROLE_OFFLINE
var _state: int = STATE_NONE
var _code: String = ""
var _local_slot: int = 0
var _peers: Dictionary = {}            # slot -> NetPeerInfo
var _links: Dictionary = {}            # remote peer id -> NetLink
var _remote_rtc: Dictionary = {}       # client: slot -> bool, the host's link to that peer is on RTC
var _sig: NetSignaling = null
var _closing_sigs: Array[NetSignaling] = []   # sockets closing after leave / failure / a rejoin attempt
var _create_attempts: int = 0

# Reconnection (docs/multiplayer.md section 4.7).
var _token: int = 0                    # client: identity of this session for the re-entry, in every L_READY
var _tokens: Dictionary = {}           # host: slot -> last token that slot sent
var _server_gone: Dictionary = {}      # client, LOADING/IN_HUNT: slot -> true, the room server no longer lists it
var _server_joined: Dictionary = {}    # client, LOADING/IN_HUNT: slot -> name the room server announced meanwhile
var _epoch: int = 0                    # client: link epoch of the latest rejoin attempt
var _rejoining: bool = false
var _rejoin_joined: bool = false       # the attempt in flight got "joined"; waiting for EV_FULL_SYNC
var _rejoin_started_ms: int = 0
var _rejoin_failures: int = 0
var _rejoin_next_ms: int = -1          # when the next attempt starts; -1 = one is in flight
var _probed: bool = false              # the socket was already probed in this episode of host silence
var _cut_until_ms: int = 0             # tests (debug_cut): rejoin attempts fail without a socket until then
var _parked: Array[NetSignaling] = []  # tests (debug_cut half-open): muted sockets kept up until the session ends

# Diagnostics of the reconnection (tests).
var rejoin_entries: int = 0            # times this client started reconnecting
var rejoin_returns: int = 0            # times it came back (EV_FULL_SYNC)
var rejoin_connections: int = 0        # sockets opened by rejoin attempts
var rejoin_attempt_ms: PackedInt32Array = PackedInt32Array()   # every attempt of the last episode, ms since it began
var readmissions: int = 0              # host: re-entries served (full syncs written)
var rejoin_refusal: StringName = &""   # error the room server answered the last refused attempt with

var _map_id: StringName = &""
var _contract_index: int = 0
var _mode: StringName = Ids.MODE_CONTRACT   # game mode of the room (docs/horda.md 9.1); wire: index in NetCodec.MODES
var _rng_seed: int = 0
var _local_ready: bool = false

var _world: HuntWorld = null
var _go_received: bool = false         # client: L_GO arrived
var _load_deadline_ms: int = 0
var _queued_events: Array = []         # [slot, type, body] received before bind_world
var _queued_states: Dictionary = {}    # slot -> latest state body received before bind_world
var _pending_left: PackedInt32Array = PackedInt32Array()
var _state_accum: float = 0.0
var _last_rx_ms: Dictionary = {}       # slot -> ticks_msec of the last state from that peer (client: slot 0)
var _stalled: bool = false
var _absent: Dictionary = {}           # slot -> true while that peer is silent for peer_absent_s (host) / stalled (client: host)
var _last_hunt_ms: int = 0             # wall clock of the previous hunt tick: a big gap means this machine froze
var _scratch: StreamPeerBuffer = StreamPeerBuffer.new()

# Traffic of the last closed second (section 4.7.8).
var _traffic_ms: int = 0
var _traffic_seen: Dictionary = {}     # remote peer id -> [link, sent_bytes, received_bytes] at the last sample
var _traffic_links: Array = []         # [{slot, path, up_bps, down_bps}]
var _traffic_up: int = 0
var _traffic_down: int = 0


## cfg = Data.get_net(). env = { url, version, name, rtc, drop_ice } resolved by the autoload.
## env["router"] = false (tests only): LOADING does not call Router.start_hunt.
func setup(cfg: Dictionary, env: Dictionary) -> void:
	_cfg = cfg
	_url = str(env.get("url", ""))
	_version = str(env.get("version", ""))
	_name = str(env.get("name", ""))
	_rtc = bool(env.get("rtc", false))
	_drop_ice = bool(env.get("drop_ice", false))
	_use_router = bool(env.get("router", true))
	_token = maxi(randi(), 1)   # never 0: 0 means "no token" (section 4.7.1)


static func message_for(code: StringName, args: Array = []) -> String:
	var text: String = MESSAGES.get(code, MESSAGES[&"connection_lost"])
	return text % args if text.contains("%") else text


# --- getters -------------------------------------------------------------------------------------

func get_role() -> int:
	return _role


func get_state() -> int:
	return _state


func get_code() -> String:
	return _code


func get_local_slot() -> int:
	return _local_slot


func get_player_count() -> int:
	return maxi(_peers.size(), 1)


func get_roster() -> Array[NetPeerInfo]:
	var out: Array[NetPeerInfo] = []
	var slots: Array = _peers.keys()
	slots.sort()
	for slot: int in slots:
		var info: NetPeerInfo = _peers[slot]
		info.path = _path_shown(slot)
		out.append(info)
	return out


func get_peer(slot: int) -> NetPeerInfo:
	var info: NetPeerInfo = _peers.get(slot) as NetPeerInfo
	if info != null:
		info.path = _path_shown(slot)
	return info


func get_selected_map_id() -> StringName:
	return _map_id


func get_selected_contract_index() -> int:
	return _contract_index


func get_selected_mode() -> StringName:
	return _mode


func get_rng_seed() -> int:
	return _rng_seed


## True while that peer has been silent for net.peer_absent_s during the hunt (section 6.9): still in
## the room, not removed. Host: its clients. Client: only the host (same as the stall warning).
func is_peer_absent(slot: int) -> bool:
	return bool(_absent.get(slot, false))


## Path of the link between this machine and that peer.
func get_link_path(slot: int) -> int:
	var link: NetLink = _links.get(slot + 1) as NetLink
	return link.get_path() if link != null else NetLink.PATH_NONE


## Client: true from the moment the connection of the hunt is lost until the EV_FULL_SYNC of the re-entry
## (or until the session gives up and ends).
func is_reconnecting() -> bool:
	return _rejoining


## Rate of the last closed second: {"up_bps", "down_bps", "links": [{"slot", "path", "up_bps", "down_bps"}]}.
## Bytes per second of frames (application bytes, no wire overhead), links ordered by slot.
func get_traffic() -> Dictionary:
	return {"up_bps": _traffic_up, "down_bps": _traffic_down, "links": _traffic_links.duplicate(true)}


## A socket being closed after leave / failure / a rejoin attempt (one per call, null when none is left):
## the autoload keeps polling it until the close leaves.
func take_closing_socket() -> NetSignaling:
	if _closing_sigs.is_empty():
		return null
	return _closing_sigs.pop_front()


func get_link(slot: int) -> NetLink:   # tests and diagnostics
	return _links.get(slot + 1) as NetLink


func get_signaling() -> NetSignaling:  # tests and diagnostics
	return _sig


# --- room ----------------------------------------------------------------------------------------

func create() -> void:
	_role = ROLE_HOST
	_mode = Ids.MODE_CONTRACT
	_create_attempts = 0
	_set_state(STATE_CONNECTING)
	if _state == STATE_CONNECTING:
		_connect_socket()


func join(code: String) -> void:
	_role = ROLE_CLIENT
	_mode = Ids.MODE_CONTRACT
	_code = code.strip_edges().to_upper()
	_set_state(STATE_CONNECTING)
	if _state != STATE_CONNECTING:
		return
	if not _is_code(_code):
		_fail(&"room_not_found")
		return
	_connect_socket()


## Idempotent and silent: closes everything and goes back to offline. No world callback.
func leave() -> void:
	if _state == STATE_NONE and _role == ROLE_OFFLINE:
		return
	_teardown()
	_set_state(STATE_NONE)


func _is_code(code: String) -> bool:
	if code.is_empty() or code.length() > CODE_MAX_CHARS:
		return false
	for i: int in code.length():
		var c: int = code.unicode_at(i)
		if not ((c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A)):
			return false
	return true


func _connect_socket() -> void:
	var params: Dictionary = {"t": "create" if _role == ROLE_HOST else "join"}
	if _role == ROLE_CLIENT:
		params["code"] = _code
		params["want"] = 0
	params["v"] = _version
	params["proto"] = NetCodec.PROTOCOL_VERSION
	params["name"] = _name
	_sig = NetSignaling.new()
	if not _sig.open(NetSignaling.build_url(_url, params), _cfg, Time.get_ticks_msec()):
		_sig = null
		_fail(&"server_unreachable")


func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


func _teardown() -> void:
	for id: int in _links:
		(_links[id] as NetLink).close()
	_links.clear()
	_peers.clear()
	_remote_rtc.clear()
	if _sig != null:
		_sig.close(Time.get_ticks_msec())
		_closing_sigs.append(_sig)
		_sig = null
	for muted: NetSignaling in _parked:
		muted.release()
	_parked.clear()
	if _stalled:
		_stalled = false
		stall_changed.emit(false)
	# No reconnect_changed(false) here: false means "it is back" (section 4.7.3). Giving up or leaving
	# ends the hunt on this machine instead; is_reconnecting() simply stops being true.
	_rejoining = false
	_rejoin_joined = false
	_rejoin_next_ms = -1
	_probed = false
	_cut_until_ms = 0
	_tokens.clear()
	_server_gone.clear()
	_server_joined.clear()
	_traffic_seen.clear()
	_traffic_links = []
	_traffic_up = 0
	_traffic_down = 0
	_traffic_ms = 0
	_world = null
	_queued_events.clear()
	_queued_states.clear()
	_pending_left = PackedInt32Array()
	_last_rx_ms.clear()
	_absent.clear()
	_last_hunt_ms = 0
	_go_received = false
	_local_ready = false
	_role = ROLE_OFFLINE
	_code = ""
	_local_slot = 0
	_map_id = &""
	_contract_index = 0
	_mode = Ids.MODE_CONTRACT
	_rng_seed = 0


## Ends the session with a room_error. A bound world hears net_connection_lost() first.
## text_key picks another text for the same code (default: the code's own text).
func _fail(code: StringName, args: Array = [], text_key: StringName = &"") -> void:
	var world: HuntWorld = _live_world()
	_teardown()
	_set_state(STATE_NONE)
	if world != null:
		world.net_connection_lost()
	failed.emit(code, message_for(text_key if text_key != &"" else code, args))


func _live_world() -> HuntWorld:
	if _world != null and not is_instance_valid(_world):
		_world = null
	return _world


func _in_hunt_states() -> bool:
	return _state == STATE_LOADING or _state == STATE_IN_HUNT


# --- frame loop ----------------------------------------------------------------------------------

func process(delta: float) -> void:
	if _state == STATE_NONE:
		return
	var now: int = Time.get_ticks_msec()
	_pump_socket(now)
	if _state == STATE_NONE:
		return
	_pump_links(now)
	if _state == STATE_NONE:
		return
	_update_loading(now)
	_update_hunt(delta, now)
	if _state != STATE_NONE:
		_update_traffic(now)


func _pump_socket(now: int) -> void:
	var sig: NetSignaling = _sig
	if sig == null:
		return
	sig.poll(now)
	for msg: Dictionary in sig.take_messages():
		_on_message(msg)
		if _sig != sig:
			return   # failed, left or reconnecting: that socket is no longer ours
	var relay: Array = sig.take_relay()
	var from_ids: PackedInt32Array = relay[0]
	var payloads: Array[PackedByteArray] = relay[1]
	for i: int in from_ids.size():
		var link: NetLink = _links.get(from_ids[i]) as NetLink
		if link != null:
			link.receive_relay(payloads[i])
	if sig.is_closed():
		if sig.is_muted():
			_parked.append(sig)   # half-open (tests): this end gave up, the connection stays up
		_on_socket_closed(sig.close_code, sig.close_reason)


func _pump_links(now: int) -> void:
	for id: int in _links.keys():
		var link: NetLink = _links.get(id) as NetLink
		if link == null:
			continue
		link.set_stall_watch(_state != STATE_LOADING)   # peers loading a scene do not poll: silence is normal
		link.poll(now)
		for records: PackedByteArray in link.take_events():
			_dispatch(id - 1, records, NetCodec.LANE_EVENT)
			if _state == STATE_NONE:
				return
		var state_records: PackedByteArray = link.take_state()
		if not state_records.is_empty():
			_dispatch(id - 1, state_records, NetCodec.LANE_STATE)
			if _state == STATE_NONE:
				return
		if link.is_lost() and _links.get(id) == link:
			_on_link_lost(id)
			if _state == STATE_NONE:
				return


## The event window of a link overflowed. In the hunt this opens the way back instead of ending things
## (section 4.7): the host drops the link and keeps the slot for peer_timeout_s; the client reconnects.
func _on_link_lost(id: int) -> void:
	if _role == ROLE_HOST:
		if _state == STATE_IN_HUNT:
			_drop_link(id)
			roster_changed.emit()
		else:
			_remove_peer(id - 1)
	elif _rejoining:
		_rejoin_attempt_failed(Time.get_ticks_msec())
	elif _can_rejoin():
		_enter_rejoin(Time.get_ticks_msec())
	else:
		_fail(&"connection_lost")


func _drop_link(id: int) -> void:
	var link: NetLink = _links.get(id) as NetLink
	if link != null:
		_links.erase(id)
		link.close()


## The socket closed with no room message (the error frame, if any, was lost with the close): the close
## code says why. No code: unreachable while connecting, connection lost in a room.
## During a hunt the links already on RTC survive the room server (section 6.9).
func _on_socket_closed(close_code: int, close_reason: String) -> void:
	_sig = null
	var code: StringName = CLOSE_CODES.get(close_code, &"")
	var app_close: bool = close_code >= APP_CLOSE_MIN and close_code <= APP_CLOSE_MAX
	if _rejoining:
		# The socket of a rejoin attempt: the server refusing is final, anything else is tried again.
		if app_close:
			_rejoin_refused(code)
		else:
			_rejoin_attempt_failed(Time.get_ticks_msec())
		return
	if code == &"host_left":
		_fail(code)
		return
	if _state == STATE_CONNECTING:
		if code == &"":
			_fail(&"server_unreachable")
			return
		var words: PackedStringArray = close_reason.split(" ", false)
		_on_server_error(code, {"host_v": words[1] if words.size() > 1 else HOST_V_UNKNOWN})
		return
	if _state != STATE_IN_HUNT:
		_fail(&"connection_lost")
		return
	if _role == ROLE_HOST:
		# The room is gone from the server: nobody without a direct link can come back (section 4.7.4).
		for slot: int in _peers.keys():
			var host_link: NetLink = _links.get(slot + 1) as NetLink
			if slot != _local_slot and (host_link == null or host_link.get_path() != NetLink.PATH_RTC):
				_remove_peer(slot)
		if _links.is_empty():
			_fail(&"connection_lost")
		return
	var link: NetLink = _links.get(HOST_ID) as NetLink
	if link != null and link.get_path() == NetLink.PATH_RTC:
		return   # keeps playing without the server; if the direct path stops too, _check_host reconnects
	if not app_close and _can_rejoin():
		_enter_rejoin(Time.get_ticks_msec())   # condition G1 of section 4.7.3
		return
	_drop_link(HOST_ID)
	_fail(&"connection_lost")


# --- room server messages (section 4.2) ---------------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	if _rejoining:
		_on_rejoin_message(msg)
		return
	match str(msg.get("t", "")):
		"created":
			_code = str(msg.get("code", ""))
			_local_slot = int(msg.get("id", HOST_ID)) - 1
			_add_peer(_local_slot, _name)
			_refresh_local_info()
			_pick_default_contract()
			_set_state(STATE_LOBBY)
		"joined":
			_code = str(msg.get("code", _code))
			_local_slot = int(msg.get("id", 0)) - 1
			var others: Variant = msg.get("peers", [])
			if others is Array:
				for entry: Variant in others:
					if entry is Dictionary:
						_add_peer(int((entry as Dictionary).get("id", 0)) - 1, str((entry as Dictionary).get("name", "")))
			_add_peer(_local_slot, _name)
			_refresh_local_info()
			_make_link(HOST_ID)
			_send_ready()
			_set_state(STATE_LOBBY)
		"peer_joined":
			var slot: int = int(msg.get("id", 0)) - 1
			if _in_hunt_states():
				# The hunt roster is the host's (section 4.7.3). Client: only note what the server lists.
				# Host: the room is locked, so this is a hunter coming back to its slot.
				if _role == ROLE_CLIENT:
					_note_server_joined(slot, str(msg.get("name", "")))
				elif _state == STATE_IN_HUNT and slot != _local_slot and _peers.has(slot):
					_readmit(slot, int(msg.get("ep", 0)))
				return   # a slot the host already removed: no link, no roster; that client gives up by itself
			_add_peer(slot, str(msg.get("name", "")))
			if _role == ROLE_HOST:
				_make_link(slot + 1)
				_broadcast_lobby()
			roster_changed.emit()
		"peer_left":
			_on_peer_left(int(msg.get("id", 0)) - 1, bool(msg.get("clean", false)))
		"host_left":
			_fail(&"host_left")
		"signal":
			_on_signal(msg)
		"error":
			_on_server_error(StringName(str(msg.get("code", ""))), msg)


## WebRTC signaling relayed by the room server. data carries the epoch of the link it belongs to: what was
## still on the way for a link that has been replaced is ignored (section 4.7.5).
func _on_signal(msg: Dictionary) -> void:
	var link: NetLink = _links.get(int(msg.get("from", 0))) as NetLink
	var rtc: NetRtc = link.get_direct() as NetRtc if link != null else null
	var data: Variant = msg.get("data")
	if rtc == null or not data is Dictionary:
		return
	if int((data as Dictionary).get("ep", 0)) != link.get_epoch():
		return
	rtc.handle_signal(data)


## Client in LOADING/IN_HUNT: what the room server says about who is connected is only noted. It becomes
## the roster again when this machine goes back to the lobby (unbind_world).
func _note_server_joined(slot: int, peer_name: String) -> void:
	_server_gone.erase(slot)
	_server_joined[slot] = peer_name


func _note_server_left(slot: int) -> void:
	_server_gone[slot] = true
	_server_joined.erase(slot)


## peer_left from the room server. clean = that peer asked to leave; without it the socket just closed.
func _on_peer_left(slot: int, clean: bool) -> void:
	if _role == ROLE_CLIENT and _in_hunt_states():
		_note_server_left(slot)   # who really left the hunt comes from the host's L_LOBBY
		return
	if _role == ROLE_HOST and _state == STATE_IN_HUNT and not clean:
		# A drop: the slot stays for peer_timeout_s, counted from its last state (section 4.7.4).
		var link: NetLink = _links.get(slot + 1) as NetLink
		if link != null and link.get_path() != NetLink.PATH_RTC:
			_drop_link(slot + 1)
			roster_changed.emit()
		return   # on RTC: that client keeps playing without the server
	_remove_peer(slot)


func _on_server_error(code: StringName, msg: Dictionary) -> void:
	if _state != STATE_CONNECTING:
		_fail(&"connection_lost")   # rate_limited, too_big, expired, bad_request in a room
		return
	match code:
		&"retry":
			_create_attempts += 1
			if _create_attempts >= CREATE_RETRIES:
				_fail(&"server_unreachable")
				return
			if _sig != null:   # null when only the close code arrived (see CLOSE_CODES)
				_sig.close(Time.get_ticks_msec(), false)
				_closing_sigs.append(_sig)
			_connect_socket()
		&"room_not_found", &"in_progress":
			_fail(code)
		&"room_full":
			_fail(code, [int(_cfg["max_players"])])
		&"version_mismatch":
			var host_v: String = str(msg.get("host_v", HOST_V_UNKNOWN))
			if host_v == HOST_V_UNKNOWN:
				_fail(code, [_version], &"version_mismatch_unknown")
			else:
				_fail(code, [_version, host_v])
		&"expired":
			_fail(&"room_not_found")
		&"bad_request":
			_fail(&"room_not_found" if _role == ROLE_CLIENT else &"server_unreachable")
		_:
			_fail(&"server_unreachable")


# --- roster --------------------------------------------------------------------------------------

func _add_peer(slot: int, peer_name: String) -> NetPeerInfo:
	var info: NetPeerInfo = _peers.get(slot) as NetPeerInfo
	if info == null:
		info = NetPeerInfo.new()
		info.slot = slot
		_peers[slot] = info
	info.is_host = slot == HOST_ID - 1
	info.ready = info.is_host
	if peer_name != "" or info.display_name == "":
		info.display_name = peer_name if peer_name != "" else DEFAULT_NAME % (slot + 1)
	return info


func _remove_peer(slot: int) -> void:
	if not _peers.has(slot) or slot == _local_slot:
		return
	_peers.erase(slot)
	_remote_rtc.erase(slot)
	_last_rx_ms.erase(slot)
	_absent.erase(slot)
	_queued_states.erase(slot)
	_server_gone.erase(slot)
	if _role == ROLE_HOST:
		_drop_link(slot + 1)
		var had_token: bool = int(_tokens.get(slot, 0)) != 0
		_tokens.erase(slot)
		if had_token and _in_hunt_states():
			_send_lock(true)   # revoked: the lock goes again without that slot (section 4.7.2)
		_broadcast_lobby()
	if _in_hunt_states():
		var world: HuntWorld = _live_world()
		if world != null:
			world.net_peer_left(slot)
		else:
			_pending_left.append(slot)
	roster_changed.emit()


## What NetPeerInfo.path shows for a slot (lobby: "direto" / "via servidor").
func _path_shown(slot: int) -> int:
	if _role == ROLE_HOST:
		return get_link_path(slot)
	if slot == _local_slot or slot == HOST_ID - 1:
		return get_link_path(HOST_ID - 1)
	return NetLink.PATH_RTC if bool(_remote_rtc.get(slot, false)) else NetLink.PATH_RELAY


## epoch: 0 for the link of the first entry; the epoch of the rejoin attempt for a link that replaces one.
func _make_link(remote_id: int, epoch: int = 0) -> NetLink:
	var link: NetLink = NetLink.new()
	link.setup(_cfg, remote_id, _relay_send.bind(remote_id), epoch)
	link.path_changed.connect(_on_link_path_changed)
	link.set_relay_alive_check(_is_socket_up)
	_links[remote_id] = link
	if not _rtc:
		return link
	# The client offers, the host answers (section 4.2). A peer that never offers leaves this
	# connection idle until ice_timeout_s closes it: the link just stays on the relay.
	var rtc: NetRtc = NetRtc.new()
	if rtc.start(_cfg["ice_servers"], _role == ROLE_CLIENT, _drop_ice, _signal_send.bind(remote_id, epoch)):
		link.set_direct(rtc, Time.get_ticks_msec() + int(float(_cfg["ice_timeout_s"]) * 1000.0))
	return link


func _is_socket_up() -> bool:
	return _sig != null and not _sig.is_closed()


func _relay_send(payload: PackedByteArray, to_id: int) -> bool:
	return _sig != null and _sig.send_relay(to_id, payload)


func _signal_send(data: Dictionary, to_id: int, epoch: int) -> void:
	var link: NetLink = _links.get(to_id) as NetLink
	if _sig == null or link == null or link.get_epoch() != epoch:
		return   # signaling of a transport whose link was replaced
	var out: Dictionary = data.duplicate()
	out["ep"] = epoch
	_sig.send_json({"t": "signal", "to": to_id, "data": out})


## Host: locks / unlocks the room on the server. Locked, it lists who may come back: the token of every
## client slot that sent one (key = peer id). Each lock replaces the list; unlocking erases it.
func _send_lock(locked: bool) -> void:
	if _sig == null:
		return
	var msg: Dictionary = {"t": "lock", "locked": locked}
	if locked:
		var tokens: Dictionary = {}
		for slot: int in _peers:
			if slot != _local_slot and int(_tokens.get(slot, 0)) != 0:
				tokens[str(slot + 1)] = int(_tokens[slot])
		if not tokens.is_empty():
			msg["tokens"] = tokens
	_sig.send_json(msg)


func _on_link_path_changed() -> void:
	if _role == ROLE_HOST:
		_broadcast_lobby()
	roster_changed.emit()


func _local_info() -> NetPeerInfo:
	return _peers.get(_local_slot) as NetPeerInfo


## Loadout summary of this machine: exactly what Profile.build_hunt_request would take to the hunt.
func _refresh_local_info() -> void:
	var me: NetPeerInfo = _local_info()
	if me == null:
		return
	var request: HuntRequest = Profile.build_hunt_request(_map_id, _contract_index)
	me.weapon_id = request.weapon_ids[0] if not request.weapon_ids.is_empty() else &""
	me.dog_id = request.dog_id


func _pick_default_contract() -> void:
	var maps: Array = Data.get_map_ids()
	_map_id = Router.selected_map_id
	_contract_index = Router.selected_contract_index
	if not _contract_allowed(_map_id, _contract_index):
		_map_id = StringName(maps[0]) if not maps.is_empty() else &""
		_contract_index = 0


func _contract_allowed(map_id: StringName, index: int) -> bool:
	return Data.get_map_ids().has(map_id) and index >= 0 and index < Data.get_contract_count(map_id) \
		and Profile.is_contract_unlocked(map_id, index)


# --- lobby API -----------------------------------------------------------------------------------

func set_ready(ready: bool) -> void:
	if _state < STATE_LOBBY:
		return
	_refresh_local_info()
	if _role == ROLE_HOST:
		_broadcast_lobby()   # the host is always ready; only its loadout summary may have changed
	else:
		_local_ready = ready
		_local_info().ready = ready
		_send_ready()
	roster_changed.emit()


## The local loadout changed while in the room: the others see the new weapon.
func refresh_loadout() -> void:
	if _state != STATE_LOBBY:
		return
	_refresh_local_info()
	if _role == ROLE_HOST:
		_broadcast_lobby()
	else:
		_send_ready()
	roster_changed.emit()


func host_select_contract(map_id: StringName, contract_index: int) -> bool:
	if _role != ROLE_HOST or _state != STATE_LOBBY or not _contract_allowed(map_id, contract_index):
		return false
	_map_id = map_id
	_contract_index = contract_index
	_broadcast_lobby()
	roster_changed.emit()
	return true


## Host, LOBBY only. mode must be in NetCodec.MODES; horde also needs data/horde.json loaded and its map
## available. Does not touch the selected map / contract (docs/horda.md 9.1).
func host_select_mode(mode: StringName) -> bool:
	if _role != ROLE_HOST or _state != STATE_LOBBY or not NetCodec.MODES.has(mode):
		return false
	if mode == Ids.MODE_HORDE and not _horde_available():
		return false
	if mode == _mode:
		return true
	_mode = mode
	_broadcast_lobby()
	roster_changed.emit()
	return true


func _horde_available() -> bool:
	var horde: Dictionary = Data.get_horde()
	if horde.is_empty():
		return false
	var map_id: StringName = StringName(str(horde.get("map_id", "")))
	if not Data.get_map_ids().has(map_id):
		return false
	return bool(Data.get_map(map_id).get("available", false))


## mode u8 of L_LOBBY / L_START: index in NetCodec.MODES; absent (old layout) or unknown = contract.
func _mode_from_wire(body: PackedByteArray, at: int) -> StringName:
	if at < 0 or at >= body.size() or body[at] >= NetCodec.MODES.size():
		return Ids.MODE_CONTRACT
	return NetCodec.MODES[body[at]]


func _mode_to_wire() -> int:
	return maxi(NetCodec.MODES.find(_mode), 0)


## What must be equal on every peer, written into the HuntRequest of LOADING (docs/horda.md 9.1).
func _fill_request(request: HuntRequest) -> void:
	request.map_id = _map_id
	request.contract_index = _contract_index
	request.rng_seed = _rng_seed
	request.player_count = _peers.size()
	request.mode = Ids.MODE_CONTRACT
	if _mode != Ids.MODE_HORDE:
		return
	var horde: Dictionary = Data.get_horde()
	if horde.is_empty():
		push_error("NetSession: room is in horde mode but data/horde.json is empty; the hunt stays in contract mode")
		return
	request.mode = Ids.MODE_HORDE
	request.map_id = StringName(str(horde.get("map_id", "")))
	request.contract_index = 0


func host_start_hunt() -> bool:
	if _role != ROLE_HOST or _state != STATE_LOBBY or not _contract_allowed(_map_id, _contract_index):
		return false
	for slot: int in _peers:
		if slot != _local_slot and not (_peers[slot] as NetPeerInfo).ready:
			return false
	_refresh_local_info()
	_rng_seed = maxi(randi(), 1)   # never 0: 0 means "randomize" in HuntRequest
	_send_lock(true)
	var slots_mask: int = 0
	for slot: int in _peers:
		slots_mask |= 1 << slot
		var info: NetPeerInfo = _peers[slot]
		info.loaded = false
		info.ready = info.is_host   # everyone readies up again for the next hunt
	_broadcast_lobby()             # the roster each client assembles the hunt with, before L_START
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.put_u8(_index_of(Data.get_map_ids(), _map_id))
	body.put_u8(_contract_index)
	body.put_u32(_rng_seed)
	body.put_u8(_peers.size())
	body.put_u8(slots_mask)
	for slot: int in int(_cfg["max_players"]):
		var info: NetPeerInfo = _peers.get(slot) as NetPeerInfo
		body.put_u8(_index_of(Data.get_dog_ids(), info.dog_id) if info != null else NO_INDEX)
	body.put_u8(_mode_to_wire())
	var record: PackedByteArray = _record(NetCodec.L_START, body.data_array)
	for id: int in _links:
		var link: NetLink = _links[id]
		link.send_events(record)
		link.flush_now()
	_load_deadline_ms = Time.get_ticks_msec() + int(float(_cfg["load_timeout_s"]) * 1000.0)
	_enter_loading()
	return true


## LOADING on this machine. The listener of room_state_changed (the lobby) builds the HuntRequest and
## calls Router.start_hunt inside the signal; Net then fills what must be equal on every peer
## (section 6.10). If nobody started the hunt (the player was in another screen), Net starts it.
func _enter_loading() -> void:
	_go_received = false
	_state_accum = 0.0
	_queued_events.clear()
	_queued_states.clear()
	_pending_left = PackedInt32Array()
	_absent.clear()
	_server_gone.clear()
	_server_joined.clear()
	if not _use_router:
		_set_state(STATE_LOADING)
		return
	var before: HuntRequest = Router.get_pending_request()
	_set_state(STATE_LOADING)
	if _state != STATE_LOADING:
		return
	var request: HuntRequest = Router.get_pending_request()
	var started: bool = request != null and request != before
	if not started:
		request = Profile.build_hunt_request(_map_id, _contract_index)
	_fill_request(request)
	if not started:
		Router.start_hunt(request)


# --- hunt API ------------------------------------------------------------------------------------

func bind_world(world: HuntWorld) -> void:
	if world == null or not _in_hunt_states():
		return
	_world = world
	var me: NetPeerInfo = _local_info()
	if me != null:
		me.loaded = true
	if _role == ROLE_CLIENT:
		_send_events_to_all(_record(NetCodec.L_LOADED, PackedByteArray()))
	else:
		_broadcast_lobby()
	for slot: int in _pending_left:
		world.net_peer_left(slot)
	_pending_left = PackedInt32Array()
	var events: Array = _queued_events
	_queued_events = []
	for entry: Array in events:
		_apply_hunt_event(world, entry[0], entry[1], entry[2])
	var states: Dictionary = _queued_states
	_queued_states = {}
	for slot: int in states:
		_apply_state(world, slot, states[slot])
	roster_changed.emit()
	# hunt_go comes from process(), never from inside this call.


## The hunt scene is gone: the room goes back to the lobby (the host unlocks it).
func unbind_world(world: HuntWorld) -> void:
	if _world != null and _world != world:
		return
	_world = null
	if not _in_hunt_states():
		return
	if _rejoining:
		_fail(&"connection_lost")   # the hunt scene went away with no connection to go back to the lobby with
		return
	_queued_events.clear()
	_queued_states.clear()
	_pending_left = PackedInt32Array()
	_go_received = false
	_absent.clear()
	if _stalled:
		_stalled = false
		stall_changed.emit(false)
	for slot: int in _peers:
		(_peers[slot] as NetPeerInfo).loaded = false
	_set_state(STATE_LOBBY)
	if _state != STATE_LOBBY:
		return
	if _role == ROLE_HOST:
		# Whoever was still inside its grace period has no link to be in a lobby with.
		for slot: int in _peers.keys():
			if slot != _local_slot and not _links.has(slot + 1):
				_remove_peer(slot)
		_send_lock(false)   # also erases the tokens on the server
		_broadcast_lobby()
	else:
		# Back in the lobby the roster is the room server's again: drop who it stopped listing and add
		# who entered the (already unlocked) room while this machine was still in the hunt scene.
		for slot: int in _server_gone.keys():
			_remove_peer(slot)
		_server_gone.clear()
		for slot: int in _server_joined:
			if slot != _local_slot and not _peers.has(slot):
				_add_peer(slot, str(_server_joined[slot]))
		_server_joined.clear()
	roster_changed.emit()


## Sends now the events the world has queued (end of hunt), without waiting for the tick.
func flush() -> void:
	var world: HuntWorld = _live_world()
	if world != null and _in_hunt_states() and not _rejoining:
		_send_events_to_all(_take_world_events(world))
	for id: int in _links:
		(_links[id] as NetLink).flush_now()   # relay: ignores the rate; RTC frames already left in send_events
	if _sig != null:
		_sig.flush()


# --- loading and hunt clock ----------------------------------------------------------------------

func _update_loading(now: int) -> void:
	if _state != STATE_LOADING or _live_world() == null:
		return
	if _role == ROLE_HOST:
		var everyone: bool = true
		for slot: int in _peers:
			if not (_peers[slot] as NetPeerInfo).loaded:
				everyone = false
		if not everyone and now < _load_deadline_ms:
			return
		var record: PackedByteArray = _record(NetCodec.L_GO, PackedByteArray())
		for id: int in _links:
			var link: NetLink = _links[id]
			link.send_events(record)
			link.flush_now()
	elif not _go_received:
		if now > _load_deadline_ms:
			_fail(&"connection_lost")   # the host never said go: it froze or died without the server noticing
		return
	_last_rx_ms.clear()
	for slot: int in _peers:
		_last_rx_ms[slot] = now
	_last_hunt_ms = now
	_state_accum = 0.0
	_set_state(STATE_IN_HUNT)
	if _state == STATE_IN_HUNT:
		hunt_go.emit()


func _update_hunt(delta: float, now: int) -> void:
	if _state != STATE_IN_HUNT:
		return
	# Deadlines run on the wall clock: after a frozen tab _process gets a delta of a few frames at most
	# (measured: 0.07 s after 5 s, Engine.max_physics_steps_per_frame = 4), so delta cannot count them.
	var away_ms: int = now - _last_hunt_ms
	_last_hunt_ms = now
	if away_ms > int(float(_cfg["host_stall_warn_s"]) * 1000.0):
		# It was this machine that stopped, not the others: whatever they sent is still in the socket
		# buffers. Everybody gets a fresh window instead of being blamed for our own freeze.
		for slot: int in _peers:
			_last_rx_ms[slot] = now
		if _rejoining:
			_rejoin_started_ms = now   # the freeze does not count against rejoin_timeout_s either
	if _role == ROLE_HOST:
		_check_peers(now)
	elif _rejoining:
		_update_rejoin(now)
	else:
		_check_host(now)
	if _state != STATE_IN_HUNT or _rejoining:
		return   # reconnecting: no C_STATE and no C_* go out (section 4.7.3)
	var world: HuntWorld = _live_world()
	if world == null:
		return
	var hz: float = float(_cfg["snapshot_hz"] if _role == ROLE_HOST else _cfg["hunter_state_hz"])
	var interval: float = 1.0 / hz
	_state_accum += delta
	if _state_accum < interval:
		return
	_state_accum = fmod(_state_accum, interval)
	if _role == ROLE_HOST:
		_scratch.clear()
		world.net_write_snapshot(_scratch)
		var snapshot: PackedByteArray = _record(NetCodec.H_SNAPSHOT, _scratch.data_array) \
			if _scratch.get_size() > 0 else PackedByteArray()
		var events: PackedByteArray = _take_world_events(world)
		for id: int in _links:
			var link: NetLink = _links[id]
			if not snapshot.is_empty():
				link.send_state(snapshot)
			link.send_events(events)
	else:
		var link: NetLink = _links.get(HOST_ID) as NetLink
		var player: PlayerBase = world.get_player()
		if link == null:
			return
		if player != null:
			_scratch.clear()
			player.net_write_state(_scratch)
			if _scratch.get_size() == NetCodec.HUNTER_STATE_BYTES:
				link.send_state(_record(NetCodec.C_STATE, _scratch.data_array))
		link.send_events(_take_world_events(world))


## Host: a client silent for peer_absent_s is marked absent (still in the room); for peer_timeout_s it
## is removed, with or without a link: that is the end of its grace period (sections 6.9 and 4.7.4).
func _check_peers(now: int) -> void:
	var absent_ms: int = int(float(_cfg["peer_absent_s"]) * 1000.0)
	var limit_ms: int = int(float(_cfg["peer_timeout_s"]) * 1000.0)
	var changed: bool = false
	for slot: int in _peers.keys():
		if slot == _local_slot:
			continue
		var silent_ms: int = now - int(_last_rx_ms.get(slot, now))
		if silent_ms > limit_ms:
			_remove_peer(slot)   # also emits roster_changed
			if _state != STATE_IN_HUNT:
				return
			continue
		var absent: bool = silent_ms > absent_ms
		if absent != bool(_absent.get(slot, false)):
			_absent[slot] = absent
			changed = true
	if changed:
		roster_changed.emit()


## Client: no snapshot for host_stall_warn_s raises the warning (and clears it when the host is back);
## nothing at all for host_timeout_s ends the connection.
func _check_host(now: int) -> void:
	var silent_ms: int = now - int(_last_rx_ms.get(HOST_ID - 1, now))
	var stalled: bool = silent_ms > int(float(_cfg["host_stall_warn_s"]) * 1000.0)
	if _can_rejoin():
		# Conditions G1 and G2 of section 4.7.3, checked every frame.
		var link: NetLink = _links.get(HOST_ID) as NetLink
		var socket_open: bool = _sig != null and _sig.is_open()
		if link != null and link.is_lost():
			_enter_rejoin(now)
			return
		if not socket_open and (link == null or link.get_path() != NetLink.PATH_RTC or stalled):
			_enter_rejoin(now)
			return
		if stalled and socket_open and not _probed:
			# Silence with the socket apparently open: is it the host, or a half-open socket? One probe
			# per episode. No pong: the socket is aborted and the next frame reconnects. Pong: it is the
			# host that is silent, and host_timeout_s below keeps counting.
			_probed = true
			_sig.probe(now, int(float(_cfg["rejoin_probe_s"]) * 1000.0))
	if not stalled:
		_probed = false
	if silent_ms > int(float(_cfg["host_timeout_s"]) * 1000.0):
		_fail(&"connection_lost")
		return
	if stalled != _stalled:
		_stalled = stalled
		_absent[HOST_ID - 1] = stalled
		stall_changed.emit(stalled)
		roster_changed.emit()


# --- reconnection, client (section 4.7.3) --------------------------------------------------------

## Only a client in a hunt that is still running reconnects; everything else ends as before F8.
func _can_rejoin() -> bool:
	if _role != ROLE_CLIENT or _state != STATE_IN_HUNT or _rejoining:
		return false
	var world: HuntWorld = _live_world()
	return world != null and not world.is_hunt_over()


func _enter_rejoin(now: int) -> void:
	_drop_link(HOST_ID)
	_discard_socket(now)
	if _stalled:
		_stalled = false
		stall_changed.emit(false)
	_absent.erase(HOST_ID - 1)
	_probed = false
	_rejoining = true
	_rejoin_joined = false
	_rejoin_started_ms = now
	_rejoin_failures = 0
	_rejoin_next_ms = now   # the first attempt is immediate
	rejoin_entries += 1
	rejoin_attempt_ms = PackedInt32Array()
	roster_changed.emit()
	reconnect_changed.emit(true)
	if _rejoining and _state == STATE_IN_HUNT:
		_update_rejoin(now)


## Closes the current socket without saying leave (the slot must stay) and lets go of it.
func _discard_socket(now: int) -> void:
	var sig: NetSignaling = _sig
	_sig = null
	if sig == null:
		return
	if sig.is_muted():
		if not _parked.has(sig):
			_parked.append(sig)   # half-open (tests): it stays up until the session ends
		return
	if not sig.is_closed():
		sig.close(now, false)
		_closing_sigs.append(sig)


func _update_rejoin(now: int) -> void:
	if now - _rejoin_started_ms > int(float(_cfg["rejoin_timeout_s"]) * 1000.0):
		_fail(&"connection_lost")
		return
	if _rejoin_next_ms >= 0 and now >= _rejoin_next_ms:
		_rejoin_attempt(now)


## One connection per attempt, to the same slot, with the token and a new link epoch.
func _rejoin_attempt(now: int) -> void:
	_epoch = _epoch % EPOCH_MAX + 1
	_rejoin_next_ms = -1
	_rejoin_joined = false
	rejoin_attempt_ms.append(now - _rejoin_started_ms)
	if now < _cut_until_ms:
		_rejoin_attempt_failed(now)   # tests (debug_cut): the network is still down, no socket is opened
		return
	var params: Dictionary = {"t": "join", "code": _code, "want": _local_slot + 1, "tok": _token, "ep": _epoch,
		"v": _version, "proto": NetCodec.PROTOCOL_VERSION, "name": _name}
	var sig: NetSignaling = NetSignaling.new()
	if not sig.open(NetSignaling.build_url(_url, params), _cfg, now):
		_rejoin_attempt_failed(now)
		return
	rejoin_connections += 1
	_sig = sig


## The socket did not open, closed without a code, ran out of time, or dropped after "joined": the next
## attempt waits rejoin_backoff_s[min(failures so far, last)].
func _rejoin_attempt_failed(now: int) -> void:
	_drop_link(HOST_ID)
	_discard_socket(now)
	_rejoin_joined = false
	var backoff: Array = _cfg["rejoin_backoff_s"]
	var wait_s: float = float(backoff[mini(_rejoin_failures, backoff.size() - 1)]) if not backoff.is_empty() else 0.0
	_rejoin_failures += 1
	_rejoin_next_ms = now + int(wait_s * 1000.0)


## The room server answered the attempt with an error: there is no way back.
func _rejoin_refused(code: StringName) -> void:
	rejoin_refusal = code
	if code == &"room_not_found" or code == &"host_left":
		_fail(&"host_left")
	else:
		_fail(&"connection_lost")   # bad_token, in_progress, version_mismatch, expired, replaced, ...


## Room server messages on the socket of a rejoin attempt.
func _on_rejoin_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"joined":
			if int(msg.get("id", 0)) - 1 != _local_slot:
				_fail(&"connection_lost")   # never: the server gives the token's slot or refuses
				return
			# The roster is not touched and L_READY is not sent again: the host still has this slot.
			var listed: Dictionary = {}
			var others: Variant = msg.get("peers", [])
			if others is Array:
				for entry: Variant in others:
					if entry is Dictionary:
						listed[int((entry as Dictionary).get("id", 0)) - 1] = true
			_server_gone.clear()
			for slot: int in _peers:
				if slot != _local_slot and not listed.has(slot):
					_server_gone[slot] = true
			for slot: int in _server_joined.keys():
				if not listed.has(slot):
					_server_joined.erase(slot)
			_rejoin_joined = true
			_make_link(HOST_ID, _epoch)   # on the relay; on the Web a new NetRtc offers again
		"peer_joined":
			_note_server_joined(int(msg.get("id", 0)) - 1, str(msg.get("name", "")))
		"peer_left":
			_note_server_left(int(msg.get("id", 0)) - 1)
		"host_left":
			_fail(&"host_left")
		"signal":
			_on_signal(msg)
		"error":
			_rejoin_refused(StringName(str(msg.get("code", ""))))


## EV_FULL_SYNC arrived on the new link: this client is back.
func _finish_rejoin() -> void:
	_rejoining = false
	_rejoin_joined = false
	_rejoin_next_ms = -1
	_probed = false
	_last_rx_ms[HOST_ID - 1] = Time.get_ticks_msec()
	rejoin_returns += 1
	roster_changed.emit()
	reconnect_changed.emit(false)


# --- reconnection, host (section 4.7.4) ----------------------------------------------------------

## A hunter came back to its slot: new link of the epoch it announced, then the state of the hunt.
func _readmit(slot: int, epoch: int) -> void:
	var now: int = Time.get_ticks_msec()
	var id: int = slot + 1
	_drop_link(id)                                    # 1. the old link, alive or not
	var link: NetLink = _make_link(id, epoch & 0x0F)
	_last_rx_ms[slot] = now                           # 2. its grace period starts again
	var world: HuntWorld = _live_world()
	if world != null:
		# 3. What was waiting for the tick goes only to the links that already existed: for the new one
		#    it is already inside the sync.
		var pending: PackedByteArray = _take_world_events(world)
		for other_id: int in _links:
			if other_id != id:
				(_links[other_id] as NetLink).send_events(pending)
	_broadcast_lobby()                                # 4. L_LOBBY (to the others it is only the path change) ...
	if world != null:
		_scratch.clear()
		world.net_write_full_sync(_scratch)           #    ... then EV_FULL_SYNC and the replayed records
		link.send_events(_scratch.data_array)
		readmissions += 1
	link.flush_now()                                  # 5.
	if _sig != null:
		_sig.flush()
	roster_changed.emit()


# --- traffic (section 4.7.8) -----------------------------------------------------------------------

## Once per second: bytes of frames sent and received by each link since the previous sample.
func _update_traffic(now: int) -> void:
	if _traffic_ms == 0:
		_traffic_ms = now
		return
	var elapsed_ms: int = now - _traffic_ms
	if elapsed_ms < TRAFFIC_WINDOW_MS:
		return
	_traffic_ms = now
	var seen: Dictionary = {}
	var links: Array = []
	var up: int = 0
	var down: int = 0
	var ids: Array = _links.keys()
	ids.sort()
	for id: int in ids:
		var link: NetLink = _links[id]
		var before: Array = _traffic_seen.get(id, [])
		var same: bool = before.size() == 3 and before[0] == link   # a replaced link starts from zero
		var link_up: int = (link.sent_bytes - (int(before[1]) if same else 0)) * 1000 / elapsed_ms
		var link_down: int = (link.received_bytes - (int(before[2]) if same else 0)) * 1000 / elapsed_ms
		seen[id] = [link, link.sent_bytes, link.received_bytes]
		links.append({"slot": id - 1, "path": link.get_path(), "up_bps": link_up, "down_bps": link_down})
		up += link_up
		down += link_down
	_traffic_seen = seen
	_traffic_links = links
	_traffic_up = up
	_traffic_down = down


# --- tests only ------------------------------------------------------------------------------------

## Drops the room socket and the direct transport now; for duration_s every rejoin attempt fails without
## opening a socket. half_open: the socket goes mute instead of closing (nothing read or written, never
## closed until the session ends), so the session has to find out by the probe and the server still sees it.
func debug_cut(duration_s: float, half_open: bool = false) -> void:
	if _state == STATE_NONE:
		return
	var now: int = Time.get_ticks_msec()
	_cut_until_ms = now + int(duration_s * 1000.0)
	for id: int in _links:
		var direct: NetLink.Direct = (_links[id] as NetLink).get_direct()
		if direct != null:
			direct.close()
	var sig: NetSignaling = _sig
	if sig == null:
		return
	if half_open:
		sig.debug_mute()
		return
	sig.abort()
	_on_socket_closed(sig.close_code, sig.close_reason)


## The token this session presents to come back (tests: a tampered one must be refused).
func debug_set_token(token: int) -> void:
	_token = token


func debug_get_token() -> int:
	return _token


## The muted sockets of debug_cut(_, true), handed over: the caller now owns them (release() when done).
func debug_take_parked() -> Array[NetSignaling]:
	var out: Array[NetSignaling] = _parked
	_parked = []
	return out


## Host: queued EV_* records. Client: queued C_* records.
func _take_world_events(world: HuntWorld) -> PackedByteArray:
	_scratch.clear()
	if _role == ROLE_HOST:
		world.net_take_events(_scratch)
	else:
		world.net_take_claims(_scratch)
	return _scratch.data_array


# --- records -------------------------------------------------------------------------------------

func _record(type: int, body: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(NetCodec.RECORD_HEADER_BYTES)
	out.encode_u8(0, type)
	out.encode_u16(1, body.size())
	out.append_array(body)
	return out


func _send_events_to_all(records: PackedByteArray) -> void:
	if records.is_empty():
		return
	for id: int in _links:
		(_links[id] as NetLink).send_events(records)


func _index_of(ids: Array, id: StringName) -> int:
	var index: int = ids.find(id) if id != &"" else -1
	return index if index >= 0 and index < NO_INDEX else NO_INDEX


func _id_at(ids: Array, index: int) -> StringName:
	return StringName(ids[index]) if index >= 0 and index < ids.size() else &""


func _dispatch(from_slot: int, records: PackedByteArray, lane: int) -> void:
	var size: int = records.size()
	var pos: int = 0
	while pos + NetCodec.RECORD_HEADER_BYTES <= size:
		var type: int = records[pos]
		var start: int = pos + NetCodec.RECORD_HEADER_BYTES
		var end: int = start + records.decode_u16(pos + 1)
		if end > size:
			return
		_on_record(from_slot, type, records.slice(start, end), lane)
		if _state == STATE_NONE:
			return
		pos = end


func _on_record(from_slot: int, type: int, body: PackedByteArray, lane: int) -> void:
	if _rejoining:
		# Until the EV_FULL_SYNC of the new link nothing of the hunt is applied: a snapshot or an event
		# that came first would be laid over a world that is still missing what happened meanwhile.
		if lane != NetCodec.LANE_EVENT:
			return
		if type == NetCodec.L_LOBBY:
			_on_lobby(body)
		elif type == NetCodec.EV_FULL_SYNC and _rejoin_joined:
			_finish_rejoin()
			_on_hunt_event(from_slot, type, body)
		return
	if lane == NetCodec.LANE_STATE:
		if type == (NetCodec.C_STATE if _role == ROLE_HOST else NetCodec.H_SNAPSHOT):
			_on_state(from_slot, body)
		return
	if _role == ROLE_HOST:
		match type:
			NetCodec.L_READY:
				_on_ready(from_slot, body)
			NetCodec.L_LOADED:
				var info: NetPeerInfo = _peers.get(from_slot) as NetPeerInfo
				if info != null and _in_hunt_states():
					info.loaded = true
					_broadcast_lobby()
					roster_changed.emit()
			NetCodec.L_NEED_RELAY:
				pass   # handled inside NetLink (path downgrade)
			_:
				if type > NetCodec.C_STATE:
					_on_hunt_event(from_slot, type, body)
	else:
		match type:
			NetCodec.L_LOBBY:
				_on_lobby(body)
			NetCodec.L_START:
				_on_start(body)
			NetCodec.L_GO:
				if _state == STATE_LOADING:
					_go_received = true
			NetCodec.L_NEED_RELAY:
				pass   # handled inside NetLink (path downgrade)
			_:
				if type > NetCodec.H_SNAPSHOT and type < NetCodec.C_STATE:
					_on_hunt_event(from_slot, type, body)


## Hunter state (host: C_STATE of that slot) or snapshot (client). Only the newest one matters.
func _on_state(from_slot: int, body: PackedByteArray) -> void:
	if _role == ROLE_HOST and body.size() != NetCodec.HUNTER_STATE_BYTES:
		return
	_last_rx_ms[from_slot] = Time.get_ticks_msec()
	if not _in_hunt_states():
		return
	var world: HuntWorld = _live_world()
	if world == null:
		_queued_states[from_slot] = body
	else:
		_apply_state(world, from_slot, body)


func _apply_state(world: HuntWorld, from_slot: int, body: PackedByteArray) -> void:
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = body
	if _role == ROLE_CLIENT:
		world.net_apply_snapshot(inp)
		return
	var hunter: PlayerBase = world.get_hunter(from_slot)
	if hunter != null and not hunter.is_local():
		hunter.net_apply_state(inp)


## EV_* (client) or C_* (host). Before bind_world they wait in a queue and keep their order.
func _on_hunt_event(from_slot: int, type: int, body: PackedByteArray) -> void:
	if not _in_hunt_states():
		return
	var world: HuntWorld = _live_world()
	if world == null:
		_queued_events.append([from_slot, type, body])
	else:
		_apply_hunt_event(world, from_slot, type, body)


func _apply_hunt_event(world: HuntWorld, from_slot: int, type: int, body: PackedByteArray) -> void:
	var inp: StreamPeerBuffer = StreamPeerBuffer.new()
	inp.data_array = body
	if _role == ROLE_HOST:
		world.net_apply_claim(from_slot, type, inp, body.size())
	else:
		world.net_apply_event(type, inp, body.size())


# --- lobby records (section 4.5) -----------------------------------------------------------------

## Client -> host: ready u8, weapon0 u8, weapon1 u8, dog u8, token u32 (token: reconnection, F8).
func _send_ready() -> void:
	var link: NetLink = _links.get(HOST_ID) as NetLink
	var me: NetPeerInfo = _local_info()
	if link == null or me == null:
		return
	var request: HuntRequest = Profile.build_hunt_request(_map_id, _contract_index)
	var weapons: Array = Data.get_weapon_ids()
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.put_u8(1 if _local_ready else 0)
	body.put_u8(_index_of(weapons, me.weapon_id))
	body.put_u8(_index_of(weapons, request.weapon_ids[1]) if request.weapon_ids.size() > 1 else NO_INDEX)
	body.put_u8(_index_of(Data.get_dog_ids(), me.dog_id))
	body.put_u32(_token)
	link.send_events(_record(NetCodec.L_READY, body.data_array))


func _on_ready(from_slot: int, body: PackedByteArray) -> void:
	var info: NetPeerInfo = _peers.get(from_slot) as NetPeerInfo
	if info == null or body.size() < L_READY_BYTES:
		return
	info.ready = body[0] != 0
	info.weapon_id = _id_at(Data.get_weapon_ids(), body[1])
	info.dog_id = _id_at(Data.get_dog_ids(), body[3])
	_tokens[from_slot] = body.decode_u32(4)   # 0 from a client of before F8: it cannot come back
	_broadcast_lobby()
	roster_changed.emit()


## Host -> clients: state u8, map u8, contract u8, n u8, n x { slot u8, flags u8, weapon0 u8, dog u8 }, mode u8.
func _broadcast_lobby() -> void:
	if _role != ROLE_HOST or _links.is_empty():
		return
	var weapons: Array = Data.get_weapon_ids()
	var dogs: Array = Data.get_dog_ids()
	var slots: Array = _peers.keys()
	slots.sort()
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.put_u8(_state)
	body.put_u8(_index_of(Data.get_map_ids(), _map_id))
	body.put_u8(_contract_index)
	body.put_u8(slots.size())
	for slot: int in slots:
		var info: NetPeerInfo = _peers[slot]
		var flags: int = 0
		if info.ready:
			flags |= LOBBY_FLAG_READY
		if info.is_host:
			flags |= LOBBY_FLAG_HOST
		if info.loaded:
			flags |= LOBBY_FLAG_LOADED
		if get_link_path(slot) == NetLink.PATH_RTC:
			flags |= LOBBY_FLAG_RTC
		body.put_u8(slot)
		body.put_u8(flags)
		body.put_u8(_index_of(weapons, info.weapon_id))
		body.put_u8(_index_of(dogs, info.dog_id))
	body.put_u8(_mode_to_wire())
	_send_events_to_all(_record(NetCodec.L_LOBBY, body.data_array))


func _on_lobby(body: PackedByteArray) -> void:
	if body.size() < L_LOBBY_HEADER_BYTES:
		return
	var map_id: StringName = _id_at(Data.get_map_ids(), body[1])
	if map_id != &"" and not _in_hunt_states():
		_map_id = map_id
		_contract_index = body[2]
	var weapons: Array = Data.get_weapon_ids()
	var dogs: Array = Data.get_dog_ids()
	var count: int = body[3]
	if not _in_hunt_states():
		_mode = _mode_from_wire(body, L_LOBBY_HEADER_BYTES + count * L_LOBBY_ENTRY_BYTES)
	var listed: Dictionary = {}
	for i: int in count:
		var at: int = L_LOBBY_HEADER_BYTES + i * L_LOBBY_ENTRY_BYTES
		if at + L_LOBBY_ENTRY_BYTES > body.size():
			break
		var slot: int = body[at]
		var flags: int = body[at + 1]
		listed[slot] = true
		var info: NetPeerInfo = _peers.get(slot) as NetPeerInfo
		# Who is in the room comes from the room server (joined / peer_joined / peer_left), which is
		# ordered; an L_LOBBY relayed before a peer_left may still list that peer and must not bring it back.
		if info == null:
			continue
		_remote_rtc[slot] = (flags & LOBBY_FLAG_RTC) != 0
		if slot == _local_slot:
			continue   # this machine knows its own state better than the echo
		info.is_host = (flags & LOBBY_FLAG_HOST) != 0
		info.ready = (flags & LOBBY_FLAG_READY) != 0
		info.loaded = (flags & LOBBY_FLAG_LOADED) != 0
		info.weapon_id = _id_at(weapons, body[at + 2])
		info.dog_id = _id_at(dogs, body[at + 3])
	if body[0] >= STATE_LOADING and _in_hunt_states() and listed.size() == count:
		# In the hunt, who left comes from the host (section 4.7.3): the room server's peer_left may be
		# just a drop that the host is still waiting for.
		for slot: int in _peers.keys():
			if slot != _local_slot and not listed.has(slot):
				_remove_peer(slot)
				if _state == STATE_NONE:
					return
	roster_changed.emit()


## Host -> clients: map u8, contract u8, rng_seed u32, player_count u8, slots_mask u8, dog[max_players] u8,
## mode u8 (absent in the old 12-byte layout = contract).
func _on_start(body: PackedByteArray) -> void:
	if body.size() < L_START_HEADER_BYTES or _state != STATE_LOBBY:
		return
	var map_id: StringName = _id_at(Data.get_map_ids(), body[0])
	if map_id == &"":
		return
	_map_id = map_id
	_contract_index = body[1]
	_mode = _mode_from_wire(body, L_START_HEADER_BYTES + int(_cfg["max_players"]))
	_rng_seed = body.decode_u32(2)
	# The host's slots_mask is the hunt roster: drop peers whose peer_left is still on the way and add
	# any peer this machine has not heard of yet, so every machine assembles the same hunters.
	var slots_mask: int = body[L_START_MASK_AT]
	for slot: int in _peers.keys():
		if slot != _local_slot and (slots_mask & (1 << slot)) == 0:
			_remove_peer(slot)
	for slot: int in int(_cfg["max_players"]):
		if (slots_mask & (1 << slot)) != 0 and not _peers.has(slot):
			_add_peer(slot, "")
	var dogs: Array = Data.get_dog_ids()
	for slot: int in _peers:
		var info: NetPeerInfo = _peers[slot]
		var at: int = L_START_HEADER_BYTES + slot
		info.dog_id = _id_at(dogs, body[at]) if at < body.size() else &""
		info.loaded = false
		info.ready = info.is_host
	_local_ready = false
	_refresh_local_info()
	# Wall-clock limit for L_GO: the host's own load_timeout_s plus the time to notice it died.
	_load_deadline_ms = Time.get_ticks_msec() + int((float(_cfg["load_timeout_s"]) + float(_cfg["host_timeout_s"])) * 1000.0)
	_enter_loading()
