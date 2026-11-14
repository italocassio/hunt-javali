extends Node
## Autoload "Net": multiplayer facade. docs/multiplayer.md section 3.4.
## Offline (no room) it runs nothing: no socket, set_process(false), every getter returns its "solo"
## value. A room lives in one NetSession; this node only resolves the server URL for the platform,
## owns the session, pumps it every frame and forwards its signals.

enum Role { OFFLINE, HOST, CLIENT }
enum RoomState { NONE, CONNECTING, LOBBY, LOADING, IN_HUNT }
enum Path { NONE, RELAY, RTC }

signal room_state_changed(state: int)                 # RoomState
signal room_error(code: StringName, message: String)  # message already in PT-BR
signal roster_changed()
signal hunt_go()

const URL_PLACEHOLDER: String = "SUBDOMINIO"          # production URL not filled in yet (data/net.json)
const LOCAL_HOSTS: Array[String] = ["localhost", "127.0.0.1"]
const SERVER_ARG: String = "--server="                # native: -- --server=ws://host:port/ws
const QUERY_SERVER: String = "server"                 # localhost pages only (section 9.9)
const QUERY_RELAY_ONLY: String = "relay_only"
const QUERY_DROP_ICE: String = "drop_ice"
const QUERY_ROOM: String = "sala"
const QUERY_ON: String = "1"

var _session: NetSession = null
var _lingering: Array[NetSignaling] = []   # sockets finishing their close handshake
var _env_resolved: bool = false
var _server_url: String = ""
var _relay_only: bool = false
var _drop_ice: bool = false
var _query: Dictionary = {}
var _url_code_taken: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	GameEvents.loadout_changed.connect(_on_loadout_changed)


func _process(delta: float) -> void:
	var session: NetSession = _session
	if session != null:
		session.process(delta)
		_collect_socket(session)
		if session == _session and session.get_state() == NetSession.STATE_NONE:
			_session = null
	if not _lingering.is_empty():
		var now: int = Time.get_ticks_msec()
		for i: int in range(_lingering.size() - 1, -1, -1):
			_lingering[i].poll(now)
			if _lingering[i].is_closed():
				_lingering.remove_at(i)
	if _session == null and _lingering.is_empty():
		set_process(false)


# --- state (solo value in parentheses) ---
func is_configured() -> bool:
	_resolve_env()
	return _server_url != ""


func is_active() -> bool:
	var state: int = get_room_state()
	return state == RoomState.LOADING or state == RoomState.IN_HUNT


func is_in_room() -> bool:
	return get_room_state() >= RoomState.LOBBY


func is_host() -> bool:
	return get_role() == Role.HOST


func get_role() -> int:
	return _session.get_role() if _session != null else Role.OFFLINE


func get_room_state() -> int:
	return _session.get_state() if _session != null else RoomState.NONE


func get_room_code() -> String:
	return _session.get_code() if _session != null else ""


func get_room_link() -> String:
	var code: String = get_room_code()
	if code == "" or not OS.has_feature("web"):
		return ""
	return "%s?%s=%s" % [str(JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)),
		QUERY_ROOM, code]


func get_local_slot() -> int:
	return _session.get_local_slot() if _session != null else 0


func get_player_count() -> int:
	return _session.get_player_count() if _session != null else 1


func get_roster() -> Array[NetPeerInfo]:
	if _session == null:
		return []
	return _session.get_roster()


func get_peer(slot: int) -> NetPeerInfo:
	return _session.get_peer(slot) if _session != null else null


func get_selected_map_id() -> StringName:
	return _session.get_selected_map_id() if _session != null else &""


func get_selected_contract_index() -> int:
	return _session.get_selected_contract_index() if _session != null else 0


func get_link_path(slot: int) -> int:
	return _session.get_link_path(slot) if _session != null else Path.NONE


## Not in the contract of section 3.4 (added by package N, reported): true while a peer is silent for
## net.peer_absent_s in the hunt but still in the room. Host: its clients. Client: the host (stall).
func is_peer_absent(slot: int) -> bool:
	return _session != null and _session.is_peer_absent(slot)


## Map seed of the current hunt, equal on every peer (it comes from L_START; never 0 once set).
## (0) outside a room or before the first LOADING. Goes into HuntRequest.rng_seed (section 6.10).
func get_hunt_seed() -> int:
	return _session.get_rng_seed() if _session != null else 0


# --- lobby ---
func create_room() -> void:
	var session: NetSession = _open_session()
	if session != null:
		session.create()


func join_room(code: String) -> void:
	var session: NetSession = _open_session()
	if session != null:
		session.join(code)


func leave_room() -> void:
	var session: NetSession = _session
	if session == null:
		return
	session.leave()
	_collect_socket(session)
	if _session == session:
		_session = null


func set_ready(ready: bool) -> void:
	if _session != null:
		_session.set_ready(ready)


func host_select_contract(map_id: StringName, contract_index: int) -> bool:
	return _session != null and _session.host_select_contract(map_id, contract_index)


func host_start_hunt() -> bool:
	return _session != null and _session.host_start_hunt()


func take_url_room_code() -> String:
	if _url_code_taken or not OS.has_feature("web"):
		return ""
	_url_code_taken = true
	_resolve_env()
	return str(_query.get(QUERY_ROOM, "")).strip_edges().to_upper()


# --- hunt ---
func bind_world(world: HuntWorld) -> void:
	if _session != null:
		_session.bind_world(world)


func unbind_world(world: HuntWorld) -> void:
	if _session != null:
		_session.unbind_world(world)


func flush() -> void:
	if _session != null:
		_session.flush()


# --- internals ---

## Server URL for this platform (section 9.9): the dev URL in native Godot and in pages served from
## localhost, the production URL everywhere else. Test overrides only where they cannot reach players.
func _resolve_env() -> void:
	if _env_resolved:
		return
	_env_resolved = true
	var cfg: Dictionary = Data.get_net()
	if not cfg.has("server_url") or not cfg.has("dev_server_url"):
		return
	var url: String = ""
	if OS.has_feature("web"):
		_query = _parse_query(str(JavaScriptBridge.eval("window.location.search", true)))
		if LOCAL_HOSTS.has(str(JavaScriptBridge.eval("window.location.hostname", true))):
			url = str(_query.get(QUERY_SERVER, cfg["dev_server_url"]))
			_relay_only = str(_query.get(QUERY_RELAY_ONLY, "")) == QUERY_ON
			_drop_ice = str(_query.get(QUERY_DROP_ICE, "")) == QUERY_ON
		else:
			url = str(cfg["server_url"])
	else:
		url = str(cfg["dev_server_url"])
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with(SERVER_ARG):
				url = arg.trim_prefix(SERVER_ARG)
	if url.contains(URL_PLACEHOLDER) or not (url.begins_with("ws://") or url.begins_with("wss://")):
		return
	_server_url = url


func _parse_query(search: String) -> Dictionary:
	var out: Dictionary = {}
	for pair: String in search.trim_prefix("?").split("&", false):
		var eq: int = pair.find("=")
		var key: String = pair if eq < 0 else pair.substr(0, eq)
		out[key.uri_decode()] = "" if eq < 0 else pair.substr(eq + 1).uri_decode()
	return out


## A new session, or null when one is already running or the mode is not configured.
func _open_session() -> NetSession:
	if _session != null and _session.get_state() != NetSession.STATE_NONE:
		return null
	if not is_configured():
		room_error.emit(&"not_configured", NetSession.message_for(&"not_configured"))
		return null
	var cfg: Dictionary = Data.get_net()
	var player_name: Variant = Profile.get_setting("player_name")
	var session: NetSession = NetSession.new()
	session.setup(cfg, {
		"url": _server_url,
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"name": player_name if player_name is String else "",
		"rtc": OS.has_feature("web") and bool(cfg["rtc_enabled"]) and not _relay_only,
		"drop_ice": _drop_ice,
	})
	session.state_changed.connect(_on_session_state)
	session.failed.connect(_on_session_failed)
	session.roster_changed.connect(_on_session_roster)
	session.hunt_go.connect(_on_session_go)
	session.stall_changed.connect(_on_session_stall)
	_session = session
	set_process(true)
	return session


func _collect_socket(session: NetSession) -> void:
	var socket: NetSignaling = session.take_closing_socket()
	if socket != null and not socket.is_closed():
		_lingering.append(socket)


func _on_session_state(state: int) -> void:
	room_state_changed.emit(state)


func _on_session_failed(code: StringName, message: String) -> void:
	room_error.emit(code, message)


func _on_session_roster() -> void:
	roster_changed.emit()


func _on_session_go() -> void:
	hunt_go.emit()


func _on_session_stall(stalled: bool) -> void:
	GameEvents.net_stall_changed.emit(stalled)


func _on_loadout_changed() -> void:
	if _session != null:
		_session.refresh_loadout()
