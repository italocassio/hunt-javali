extends Node
## Sandbox of package N for the room mode (docs/horda.md 9.1, docs/multiplayer.md 4.5): single process, no
## room server. A host NetSession and a client NetSession are wired by a NetLoopback; records are read
## back from the client's link (the exact bytes the host wrote) or built by hand.
## Run: tools/godot.sh --headless --path . res://src/net/debug/net_mode_selftest.tscn
## Prints one FAIL line per failed check and "NET_MODE_SELFTEST checks=N failures=M"; exits 1 on any failure.

const STEP_MS: int = 100
const PUMP_STEPS: int = 8
const SAVE_PATH: String = "user://net_mode_selftest.json"
const HORDE_MAP: StringName = &"mato_grosso"
const LOBBY_BYTES_2_PEERS: int = 13       # 4 header + 2 x 4 + mode
const START_BYTES_NEW: int = 13
const START_BYTES_OLD: int = 12

var _checks: int = 0
var _failures: int = 0
var _cfg: Dictionary = {}
var _now: int = 0
var _max_players: int = 4


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.set_save_path(SAVE_PATH)
	Profile.reset_progress()
	_cfg = Data.get_net()
	_max_players = int(_cfg["max_players"])
	_ok(not Data.get_horde().is_empty(), "Data.get_horde() carregado (pre-requisito)")
	_lobby_records()
	_start_records()
	_select_mode_refusals()
	_select_mode_accepted()
	_host_layout()
	_request_fill()
	_net_facade()
	_cleanup()
	print("NET_MODE_SELFTEST checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL %s" % label)


# --- fixtures -------------------------------------------------------------------------------------

## A session already in the room: role + LOBBY state + two peers (slot 0 host, slot 1 client).
func _session(role: int, slot: int) -> NetSession:
	var s: NetSession = NetSession.new()
	s.setup(_cfg, {"router": false})
	s._role = role
	s._state = NetSession.STATE_LOBBY
	s._local_slot = slot
	s._add_peer(0, "Host")
	s._add_peer(1, "Cliente")
	s._map_id = HORDE_MAP
	s._contract_index = 0
	return s


## [host, client, link_host_side, link_client_side, loopback]
func _pair() -> Array:
	var host: NetSession = _session(NetSession.ROLE_HOST, 0)
	var client: NetSession = _session(NetSession.ROLE_CLIENT, 1)
	var a: NetLink = NetLink.new()
	var b: NetLink = NetLink.new()
	var lp: NetLoopback = NetLoopback.new(7)
	lp.attach(a, b, _cfg)
	host._links[2] = a
	client._links[1] = b
	return [host, client, a, b, lp]


## Everything the host sent to the client since the last pump: Array of [type, body].
func _pump(pair: Array) -> Array:
	var a: NetLink = pair[2]
	var b: NetLink = pair[3]
	var lp: NetLoopback = pair[4]
	var out: Array = []
	for i: int in PUMP_STEPS:
		_now += STEP_MS
		a.poll(_now)
		b.poll(_now)
		lp.step()
		a.poll(_now)
		b.poll(_now)
		for records: PackedByteArray in b.take_events():
			var pos: int = 0
			while pos + NetCodec.RECORD_HEADER_BYTES <= records.size():
				var length: int = records.decode_u16(pos + 1)
				var start: int = pos + NetCodec.RECORD_HEADER_BYTES
				out.append([int(records[pos]), records.slice(start, start + length)])
				pos = start + length
	return out


func _of_type(records: Array, type: int) -> Array:
	var out: Array = []
	for r: Array in records:
		if int(r[0]) == type:
			out.append(r[1])
	return out


## L_LOBBY body of a 2-peer room; mode_byte < 0 = old layout (no byte).
func _lobby_body(state: int, mode_byte: int) -> PackedByteArray:
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.put_u8(state)
	body.put_u8(Data.get_map_ids().find(HORDE_MAP))
	body.put_u8(0)
	body.put_u8(2)
	for slot: int in 2:
		body.put_u8(slot)
		body.put_u8(NetSession.LOBBY_FLAG_HOST if slot == 0 else 0)
		body.put_u8(NetSession.NO_INDEX)
		body.put_u8(NetSession.NO_INDEX)
	if mode_byte >= 0:
		body.put_u8(mode_byte)
	return body.data_array


## L_START body; with_mode false = the 12-byte layout of before 0.5.0.
func _start_body(mode_byte: int, with_mode: bool) -> PackedByteArray:
	var body: StreamPeerBuffer = StreamPeerBuffer.new()
	body.put_u8(Data.get_map_ids().find(HORDE_MAP))
	body.put_u8(0)
	body.put_u32(12345)
	body.put_u8(2)
	body.put_u8(3)
	for slot: int in _max_players:
		body.put_u8(NetSession.NO_INDEX)
	if with_mode:
		body.put_u8(mode_byte)
	return body.data_array


# --- cases ----------------------------------------------------------------------------------------

func _lobby_records() -> void:
	var c: NetSession = _session(NetSession.ROLE_CLIENT, 1)
	_ok(c.get_selected_mode() == Ids.MODE_CONTRACT, "L_LOBBY: modo inicial = contrato")
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, 1))
	_ok(c.get_selected_mode() == Ids.MODE_HORDE, "L_LOBBY com byte final 1 -> horda (%s)" % str(c.get_selected_mode()))
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, 0))
	_ok(c.get_selected_mode() == Ids.MODE_CONTRACT, "L_LOBBY com byte final 0 -> contrato")
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, 1))
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, -1))
	_ok(c.get_selected_mode() == Ids.MODE_CONTRACT, "L_LOBBY sem o byte final (layout antigo) volta a contrato")
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, 1))
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, 200))
	_ok(c.get_selected_mode() == Ids.MODE_CONTRACT, "L_LOBBY com modo desconhecido (200) -> contrato")
	c._on_lobby(_lobby_body(NetSession.STATE_LOBBY, 1))
	var map_before: StringName = c.get_selected_map_id()
	c._state = NetSession.STATE_IN_HUNT
	c._on_lobby(_lobby_body(NetSession.STATE_IN_HUNT, 0))
	_ok(c.get_selected_mode() == Ids.MODE_HORDE, "L_LOBBY durante a caçada nao muda o modo")
	_ok(c.get_selected_map_id() == map_before, "L_LOBBY: mapa continua o mesmo")
	# Through the dispatcher, as the wire delivers it.
	var d: NetSession = _session(NetSession.ROLE_CLIENT, 1)
	var rec: PackedByteArray = d._record(NetCodec.L_LOBBY, _lobby_body(NetSession.STATE_LOBBY, 1))
	d._dispatch(0, rec, NetCodec.LANE_EVENT)
	_ok(d.get_selected_mode() == Ids.MODE_HORDE, "L_LOBBY pelo despachante -> horda")


func _start_records() -> void:
	var cases: Array = [
		["L_START de 13 bytes, modo 1", _start_body(1, true), Ids.MODE_HORDE, START_BYTES_NEW],
		["L_START de 13 bytes, modo 0", _start_body(0, true), Ids.MODE_CONTRACT, START_BYTES_NEW],
		["L_START de 12 bytes (sem modo)", _start_body(0, false), Ids.MODE_CONTRACT, START_BYTES_OLD],
		["L_START de 13 bytes, modo desconhecido", _start_body(9, true), Ids.MODE_CONTRACT, START_BYTES_NEW],
	]
	for case: Array in cases:
		var body: PackedByteArray = case[1]
		_ok(body.size() == int(case[3]), "%s: corpo com %d bytes (%d)" % [case[0], int(case[3]), body.size()])
		var c: NetSession = _session(NetSession.ROLE_CLIENT, 1)
		c._mode = Ids.MODE_HORDE if case[2] == Ids.MODE_CONTRACT else Ids.MODE_CONTRACT   # must be overwritten
		c._on_start(body)
		_ok(c.get_selected_mode() == case[2], "%s -> %s (%s)" % [case[0], str(case[2]), str(c.get_selected_mode())])
		_ok(c.get_state() == NetSession.STATE_LOADING, "%s: entrou em LOADING" % case[0])
		_ok(c.get_rng_seed() == 12345 and c.get_player_count() == 2, "%s: semente e jogadores intactos" % case[0])
	# L_START ignored outside the lobby: the mode must not change.
	var late: NetSession = _session(NetSession.ROLE_CLIENT, 1)
	late._state = NetSession.STATE_IN_HUNT
	late._on_start(_start_body(1, true))
	_ok(late.get_selected_mode() == Ids.MODE_CONTRACT, "L_START fora do LOBBY e ignorado")


func _select_mode_refusals() -> void:
	var client: NetSession = _session(NetSession.ROLE_CLIENT, 1)
	_ok(not client.host_select_mode(Ids.MODE_HORDE), "host_select_mode recusa cliente")
	_ok(client.get_selected_mode() == Ids.MODE_CONTRACT, "cliente: modo intacto apos a recusa")
	var off: NetSession = _session(NetSession.ROLE_OFFLINE, 0)
	_ok(not off.host_select_mode(Ids.MODE_HORDE), "host_select_mode recusa sessao offline")
	for state: int in [NetSession.STATE_NONE, NetSession.STATE_CONNECTING, NetSession.STATE_LOADING, NetSession.STATE_IN_HUNT]:
		var host: NetSession = _session(NetSession.ROLE_HOST, 0)
		host._state = state
		_ok(not host.host_select_mode(Ids.MODE_HORDE), "host_select_mode recusa fora do LOBBY (estado %d)" % state)
		_ok(host.get_selected_mode() == Ids.MODE_CONTRACT, "estado %d: modo intacto" % state)
	var host2: NetSession = _session(NetSession.ROLE_HOST, 0)
	_ok(not host2.host_select_mode(&"bogus"), "host_select_mode recusa id desconhecido")
	_ok(not host2.host_select_mode(&""), "host_select_mode recusa id vazio")
	var saved: Dictionary = Data.get_horde()
	Data._raw["horde"] = {}
	_ok(not host2.host_select_mode(Ids.MODE_HORDE), "host_select_mode recusa horda com Data.get_horde() vazio")
	_ok(host2.host_select_mode(Ids.MODE_CONTRACT), "host_select_mode aceita contrato com Data.get_horde() vazio")
	var bad: Dictionary = saved.duplicate(true)
	bad["map_id"] = "mapa_que_nao_existe"
	Data._raw["horde"] = bad
	_ok(not host2.host_select_mode(Ids.MODE_HORDE), "host_select_mode recusa horda com mapa inexistente")
	Data._raw["horde"] = saved
	_ok(host2.get_selected_mode() == Ids.MODE_CONTRACT, "recusas deixaram o modo em contrato")
	_ok(not Net.host_select_mode(Ids.MODE_HORDE), "Net.host_select_mode sem sala = false")
	_ok(Net.get_selected_mode() == Ids.MODE_CONTRACT, "Net.get_selected_mode() sem sala = contrato")


func _select_mode_accepted() -> void:
	var pair: Array = _pair()
	var host: NetSession = pair[0]
	var client: NetSession = pair[1]
	var rosters: Array = [0]
	host.roster_changed.connect(func() -> void: rosters[0] += 1)
	_ok(host.host_select_mode(Ids.MODE_HORDE), "host_select_mode(horda) aceito")
	_ok(host.get_selected_mode() == Ids.MODE_HORDE, "anfitriao: modo horda")
	_ok(rosters[0] == 1, "roster_changed emitido 1x (%d)" % rosters[0])
	_ok(host.get_selected_map_id() == HORDE_MAP and host.get_selected_contract_index() == 0, "mapa e contrato intactos")
	var lobbies: Array = _of_type(_pump(pair), NetCodec.L_LOBBY)
	_ok(lobbies.size() == 1, "um L_LOBBY enviado ao cliente (%d)" % lobbies.size())
	for body: PackedByteArray in lobbies:
		client._on_lobby(body)
	_ok(client.get_selected_mode() == Ids.MODE_HORDE, "cliente recebeu o modo horda")
	_ok(host.host_select_mode(Ids.MODE_HORDE), "repetir o mesmo modo devolve true")
	_ok(_of_type(_pump(pair), NetCodec.L_LOBBY).is_empty() and rosters[0] == 1, "mesmo modo: nada reenviado")
	_ok(host.host_select_mode(Ids.MODE_CONTRACT), "voltar a contrato aceito")
	for body: PackedByteArray in _of_type(_pump(pair), NetCodec.L_LOBBY):
		client._on_lobby(body)
	_ok(client.get_selected_mode() == Ids.MODE_CONTRACT, "cliente voltou a contrato")
	# A new room starts in contract even if the object kept horde (create / join / teardown).
	host._mode = Ids.MODE_HORDE
	host._teardown()
	_ok(host.get_selected_mode() == Ids.MODE_CONTRACT, "_teardown (leave) volta a contrato")


## Bytes the host writes, one by one (docs/multiplayer.md 4.5, docs/horda.md 9.1).
func _host_layout() -> void:
	var pair: Array = _pair()
	var host: NetSession = pair[0]
	var client: NetSession = pair[1]
	host._refresh_local_info()
	var map_index: int = Data.get_map_ids().find(HORDE_MAP)
	var weapon0: int = NetSession.NO_INDEX
	var dog0: int = NetSession.NO_INDEX
	var info0: NetPeerInfo = host._peers[0]
	if info0.weapon_id != &"":
		weapon0 = Data.get_weapon_ids().find(info0.weapon_id)
	if info0.dog_id != &"":
		dog0 = Data.get_dog_ids().find(info0.dog_id)
	host.host_select_mode(Ids.MODE_HORDE)
	var lobby: Array = _of_type(_pump(pair), NetCodec.L_LOBBY)
	_ok(lobby.size() == 1, "layout: um L_LOBBY")
	if lobby.size() == 1:
		var expected: PackedByteArray = PackedByteArray([NetSession.STATE_LOBBY, map_index, 0, 2,
			0, NetSession.LOBBY_FLAG_HOST | NetSession.LOBBY_FLAG_READY, weapon0, dog0,
			1, 0, NetSession.NO_INDEX, NetSession.NO_INDEX,
			1])
		_ok(lobby[0].size() == LOBBY_BYTES_2_PEERS, "L_LOBBY do anfitriao tem 5+4n = 13 bytes (%d)" % lobby[0].size())
		_ok(lobby[0] == expected, "L_LOBBY do anfitriao byte a byte: %s esperado %s" % [str(lobby[0]), str(expected)])
	# Start: client ready, then L_LOBBY + L_START on the wire.
	(host._peers[1] as NetPeerInfo).ready = true
	_ok(host.host_start_hunt(), "layout: host_start_hunt aceito")
	var records: Array = _pump(pair)
	var starts: Array = _of_type(records, NetCodec.L_START)
	var lobbies: Array = _of_type(records, NetCodec.L_LOBBY)
	_ok(starts.size() == 1 and lobbies.size() == 1, "layout: um L_LOBBY e um L_START (%d, %d)" % [lobbies.size(), starts.size()])
	if starts.size() == 1:
		var expected_start: StreamPeerBuffer = StreamPeerBuffer.new()
		expected_start.put_u8(map_index)
		expected_start.put_u8(0)
		expected_start.put_u32(host.get_rng_seed())
		expected_start.put_u8(2)
		expected_start.put_u8(3)
		expected_start.put_u8(dog0)
		expected_start.put_u8(NetSession.NO_INDEX)   # slot 1: the client's dog is not known to the host here
		for slot: int in range(2, _max_players):
			expected_start.put_u8(NetSession.NO_INDEX)
		expected_start.put_u8(1)
		_ok(starts[0].size() == START_BYTES_NEW, "L_START do anfitriao tem 8 + max_players + 1 = 13 bytes (%d)" % starts[0].size())
		_ok(starts[0] == expected_start.data_array, "L_START do anfitriao byte a byte: %s esperado %s"
			% [str(starts[0]), str(expected_start.data_array)])
		_ok(starts[0][starts[0].size() - 1] == 1, "L_START: ultimo byte = modo horda")
		client._on_start(starts[0])
		_ok(client.get_selected_mode() == Ids.MODE_HORDE and client.get_state() == NetSession.STATE_LOADING,
			"cliente le o L_START do anfitriao: horda e LOADING")
	if lobbies.size() == 1:
		_ok(lobbies[0][lobbies[0].size() - 1] == 1 and lobbies[0].size() == LOBBY_BYTES_2_PEERS,
			"L_LOBBY antes do L_START tambem leva o modo")
	# Same thing in contract mode: last byte 0, same sizes.
	var pair2: Array = _pair()
	var host2: NetSession = pair2[0]
	(host2._peers[1] as NetPeerInfo).ready = true
	host2.host_start_hunt()
	var starts2: Array = _of_type(_pump(pair2), NetCodec.L_START)
	_ok(starts2.size() == 1 and starts2[0].size() == START_BYTES_NEW and starts2[0][START_BYTES_NEW - 1] == 0,
		"L_START em contrato: 13 bytes, ultimo = 0")


func _request_fill() -> void:
	var host: NetSession = _session(NetSession.ROLE_HOST, 0)
	host._rng_seed = 777
	host._contract_index = 2
	var req: HuntRequest = HuntRequest.new()
	host._fill_request(req)
	_ok(req.mode == Ids.MODE_CONTRACT and req.map_id == HORDE_MAP and req.contract_index == 2,
		"request em contrato: modo contrato, mapa e contrato da sala")
	_ok(req.rng_seed == 777 and req.player_count == 2, "request em contrato: semente e jogadores")
	_ok(host.host_select_mode(Ids.MODE_HORDE), "request: sala em horda")
	var horde_map: StringName = StringName(str(Data.get_horde().get("map_id", "")))
	var req2: HuntRequest = HuntRequest.new()
	req2.map_id = &"outro"
	req2.contract_index = 4
	host._fill_request(req2)
	_ok(req2.mode == Ids.MODE_HORDE, "request em horda: mode == horde")
	_ok(req2.map_id == horde_map and req2.map_id == HORDE_MAP, "request em horda: map_id == mato_grosso (%s)" % str(req2.map_id))
	_ok(req2.contract_index == 0, "request em horda: contract_index == 0 (%d)" % req2.contract_index)
	_ok(req2.rng_seed == 777 and req2.player_count == 2, "request em horda: semente e jogadores")
	_ok(host.get_selected_contract_index() == 2, "a sala guarda o contrato escolhido (L_START continua levando)")


## Net facade: create_room goes back to contract; leave_room too. The socket opened by create_room never
## connects (nothing listens) and is closed right away by leave_room.
func _net_facade() -> void:
	if not Net.is_configured():
		print("SKIP Net.create_room: servidor de salas nao configurado neste ambiente")
		return
	var stale: NetSession = _session(NetSession.ROLE_HOST, 0)
	stale._state = NetSession.STATE_NONE
	stale._mode = Ids.MODE_HORDE
	Net._session = stale
	_ok(Net.get_selected_mode() == Ids.MODE_HORDE, "Net.get_selected_mode() le a sessao")
	Net.create_room()
	_ok(Net._session != stale and Net.get_selected_mode() == Ids.MODE_CONTRACT, "Net.create_room volta o modo a contrato")
	Net.leave_room()
	_ok(Net.get_selected_mode() == Ids.MODE_CONTRACT, "Net.leave_room: contrato")
	var live: NetSession = _session(NetSession.ROLE_HOST, 0)
	Net._session = live
	_ok(Net.host_select_mode(Ids.MODE_HORDE) and Net.get_selected_mode() == Ids.MODE_HORDE, "Net.host_select_mode repassa para a sessao")
	Net.leave_room()
	_ok(Net.get_selected_mode() == Ids.MODE_CONTRACT, "Net.leave_room tira a sala e o modo volta a contrato")


func _cleanup() -> void:
	for path: String in [SAVE_PATH, SAVE_PATH.replace(".json", ".bak.json")]:
		var abs_path: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			DirAccess.remove_absolute(abs_path)
