extends Node
## Deadlines, absences and room lock of multiplayer F5 (docs/multiplayer.md section 6.9), exercised with
## real NetSessions in this process against the local Bun room server. Started by net_e2e.gd with
## --deadlines (it owns the server); it is not a scene of its own.
##
## A "frozen tab" is a session this node stops calling process() on, while the others keep running; the
## scenario S7 freezes the whole process with OS.delay_msec instead. Worlds are stubs that count what Net
## calls on them. Unless --real-timeouts is passed, host_timeout_s / peer_timeout_s / load_timeout_s and the
## ping timings are shortened (the logic is the same; the values from data/net.json are used otherwise).

const ROOM_MS: int = 10000
const SETUP_MS: int = 8000
const SLACK_MS: int = 2000
const SHORT_HOST_TIMEOUT_S: float = 6.0
const SHORT_PEER_TIMEOUT_S: float = 8.0
const SHORT_LOAD_TIMEOUT_S: float = 4.0
const SHORT_PING_S: float = 1.0
const SHORT_PONG_TIMEOUT_S: float = 1.0
const FLUSH_MS: int = 250
const LOOPBACK: String = "127.0.0.1"


## What Net does to a hunt world, counted.
class StubWorld extends HuntWorld:
	var player: PlayerBase = null
	var left: Array[int] = []
	var lost: int = 0
	var snapshots_in: int = 0
	var events_in: Array[int] = []
	var claims_in: Array[int] = []
	var outgoing: PackedByteArray = PackedByteArray()

	func is_world_ready() -> bool:
		return true

	func get_player() -> PlayerBase:
		return player

	func net_write_snapshot(out: StreamPeerBuffer) -> void:
		out.put_u8(1)

	func net_apply_snapshot(_inp: StreamPeerBuffer) -> void:
		snapshots_in += 1

	func net_take_events(out: StreamPeerBuffer) -> void:
		if not outgoing.is_empty():
			out.put_data(outgoing)
		outgoing = PackedByteArray()

	func net_apply_event(type: int, _inp: StreamPeerBuffer, _length: int) -> void:
		events_in.append(type)

	func net_take_claims(out: StreamPeerBuffer) -> void:
		if not outgoing.is_empty():
			out.put_data(outgoing)
		outgoing = PackedByteArray()

	func net_apply_claim(_slot: int, type: int, _inp: StreamPeerBuffer, _length: int) -> void:
		claims_in.append(type)

	func net_peer_left(slot: int) -> void:
		left.append(slot)

	func net_connection_lost() -> void:
		lost += 1


class StubPlayer extends PlayerBase:
	func net_write_state(out: StreamPeerBuffer) -> void:
		var zeros: PackedByteArray = PackedByteArray()
		zeros.resize(NetCodec.HUNTER_STATE_BYTES)
		out.put_data(zeros)


class Peer extends RefCounted:
	var session: NetSession = null
	var world: StubWorld = null
	var frozen: bool = false
	var stalls: Array[bool] = []
	var fails: Array[String] = []
	var fail_messages: Array[String] = []
	var fail_ms: int = 0
	var go_ms: int = 0


## A WebSocket server that accepts, says "created" and never answers a ping.
class MuteServer extends RefCounted:
	var tcp: TCPServer = TCPServer.new()
	var ws: WebSocketPeer = null
	var port: int = 0
	var greeted: bool = false
	var texts: int = 0

	func start(address: String) -> bool:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		for i: int in 40:
			port = 20000 + rng.randi_range(0, 30000)
			if tcp.listen(port, address) == OK:
				return true
		return false

	func poll() -> void:
		if ws == null and tcp.is_connection_available():
			ws = WebSocketPeer.new()
			ws.accept_stream(tcp.take_connection())
		if ws == null:
			return
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if not greeted:
				greeted = true
				ws.send_text("{\"t\":\"created\",\"code\":\"MUTE1\",\"id\":1}")
			while ws.get_available_packet_count() > 0:
				ws.get_packet()
				texts += 1

	func stop() -> void:
		if ws != null:
			ws.close()
		tcp.stop()


var _url: String = ""
var _ok: Callable = Callable()
var _kill_server: Callable = Callable()
var _real: bool = false
var _cfg: Dictionary = {}
var _peers: Array[Peer] = []
var _lingering: Array[NetSignaling] = []
var _mute: MuteServer = null
var _last_delta: float = 0.0


func _process(delta: float) -> void:
	_last_delta = delta
	for p: Peer in _peers:
		if not p.frozen:
			p.session.process(delta)
			var socket: NetSignaling = p.session.take_closing_socket()
			if socket != null and not socket.is_closed():
				_lingering.append(socket)
	var now: int = Time.get_ticks_msec()
	for i: int in range(_lingering.size() - 1, -1, -1):
		_lingering[i].poll(now)
		if _lingering[i].is_closed():
			_lingering.remove_at(i)
	if _mute != null:
		_mute.poll()


## ok(cond: bool, label: String) -> bool. kill_server(): stops the room server (last scenario).
func run(url: String, ok: Callable, kill_server: Callable, real_timeouts: bool) -> void:
	_url = url
	_ok = ok
	_kill_server = kill_server
	_real = real_timeouts
	_cfg = Data.get_net().duplicate()
	if not _real:
		_cfg["host_timeout_s"] = SHORT_HOST_TIMEOUT_S
		_cfg["peer_timeout_s"] = SHORT_PEER_TIMEOUT_S
		_cfg["load_timeout_s"] = SHORT_LOAD_TIMEOUT_S
	_say("timeouts: stall_warn=%.1f absent=%.1f host_timeout=%.1f peer_timeout=%.1f load_timeout=%.1f s (%s)" % [
		float(_cfg["host_stall_warn_s"]), float(_cfg["peer_absent_s"]), float(_cfg["host_timeout_s"]),
		float(_cfg["peer_timeout_s"]), float(_cfg["load_timeout_s"]), "data/net.json" if _real else "shortened"])
	await _s1_stall_warning()
	await _s2_host_timeout()
	await _s3_client_absent_and_timeout()
	await _s4_load_timeout()
	await _s5_client_never_gets_go()
	await _s6_flush()
	await _s7_lock()
	await _s8_whole_process_frozen()
	await _s9_ping_pong()
	await _s10_server_dies()


# --- scenarios -----------------------------------------------------------------------------------

## S1: the host freezes for longer than host_stall_warn_s and less than host_timeout_s.
func _s1_stall_warning() -> void:
	_say("S1 host frozen between stall_warn and timeout")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	var warn_ms: int = _ms("host_stall_warn_s")
	await _sleep(500)
	host.frozen = true
	var t0: int = Time.get_ticks_msec()
	var seen: bool = await _wait(func() -> bool: return client.stalls.has(true), warn_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(seen and lag >= warn_ms - 300 and lag <= warn_ms + 1000,
		"S1 cliente avisou a falta de snapshot em %d ms (aviso em %d ms)" % [lag, warn_ms])
	_check(client.session.is_peer_absent(0), "S1 anfitrião marcado ausente no cliente")
	_check(client.session.get_state() == NetSession.STATE_IN_HUNT and client.world.lost == 0,
		"S1 nada terminou durante o aviso")
	await _sleep(1000)
	host.frozen = false
	var cleared: bool = await _wait(func() -> bool: return client.stalls.size() >= 2, SLACK_MS)
	_check(cleared and str(client.stalls) == str([true, false]), "S1 aviso ligou e desligou %s" % str(client.stalls))
	_check(client.session.get_state() == NetSession.STATE_IN_HUNT and client.fails.is_empty() and client.world.lost == 0,
		"S1 cliente segue na caçada depois que o anfitrião voltou")
	_check(not client.session.is_peer_absent(0) and not host.session.is_peer_absent(1) and host.world.left.is_empty(),
		"S1 ninguém ficou ausente nem removido")
	await _close_room(room)


## S2: the host freezes for longer than host_timeout_s: the client ends the connection (N4).
func _s2_host_timeout() -> void:
	_say("S2 host frozen past host_timeout")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	var limit_ms: int = _ms("host_timeout_s")
	await _sleep(500)
	host.frozen = true
	var t0: int = Time.get_ticks_msec()
	var ended: bool = await _wait(func() -> bool: return not client.fails.is_empty(), limit_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(ended and lag >= limit_ms - 300, "S2 cliente terminou em %d ms (host_timeout_s = %d ms, limite +2 s)" % [lag, limit_ms])
	_check(str(client.fails) == str(["connection_lost"]), "S2 room_error connection_lost %s" % str(client.fails))
	_check(str(client.fail_messages) == str(["Conexão perdida."]), "S2 mensagem em português %s" % str(client.fail_messages))
	_check(client.world.lost == 1, "S2 net_connection_lost() chamado uma vez no mundo do cliente (%d)" % client.world.lost)
	_check(client.session.get_state() == NetSession.STATE_NONE and client.session.get_role() == NetSession.ROLE_OFFLINE,
		"S2 cliente voltou a OFFLINE")
	_check(str(client.stalls) == str([true, false]), "S2 aviso ligou e foi desligado ao terminar %s" % str(client.stalls))
	host.frozen = false
	await _close_room(room)


## S3: a client goes silent: absent after peer_absent_s (not removed), removed after peer_timeout_s.
func _s3_client_absent_and_timeout() -> void:
	_say("S3 client frozen: absent, then removed")
	var room: Array[Peer] = await _hunt_room(2)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var quiet: Peer = room[1]
	var other: Peer = room[2]
	var absent_ms: int = _ms("peer_absent_s")
	var limit_ms: int = _ms("peer_timeout_s")
	await _sleep(500)
	quiet.frozen = true
	var t0: int = Time.get_ticks_msec()
	var absent: bool = await _wait(func() -> bool: return host.session.is_peer_absent(1), absent_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(absent and lag >= absent_ms - 300, "S3 cliente marcado ausente em %d ms (peer_absent_s = %d ms)" % [lag, absent_ms])
	_check(host.world.left.is_empty() and host.session.get_peer(1) != null, "S3 ausente não foi removido")
	_check(not host.session.is_peer_absent(2), "S3 o outro cliente não ficou ausente")
	var removed: bool = await _wait(func() -> bool: return host.world.left.has(1), limit_ms + SLACK_MS)
	lag = Time.get_ticks_msec() - t0
	_check(removed and lag >= limit_ms - 300, "S3 cliente removido em %d ms (peer_timeout_s = %d ms, limite +2 s)" % [lag, limit_ms])
	_check(str(host.world.left) == str([1]), "S3 net_peer_left chamado só para o slot 1 %s" % str(host.world.left))
	_check(host.session.get_state() == NetSession.STATE_IN_HUNT and host.session.get_peer(1) == null
		and host.session.get_player_count() == 2, "S3 caçada segue com os outros (%d na sala)" % host.session.get_player_count())
	_check(other.session.get_state() == NetSession.STATE_IN_HUNT and other.fails.is_empty(), "S3 o outro cliente não foi afetado")
	# It comes back: the host no longer talks to it, so it ends by its own host_timeout_s.
	quiet.frozen = false
	var dropped: bool = await _wait(func() -> bool: return not quiet.fails.is_empty(), _ms("host_timeout_s") + SLACK_MS * 2)
	_check(dropped and str(quiet.fails) == str(["connection_lost"]), "S3 removido que volta termina por host_timeout %s" % str(quiet.fails))
	# A shorter freeze (past absent, short of timeout) is forgiven.
	await _close_room(room)
	room = await _hunt_room(1)
	if room.is_empty():
		return
	host = room[0]
	quiet = room[1]
	await _sleep(500)
	quiet.frozen = true
	await _wait(func() -> bool: return host.session.is_peer_absent(1), absent_ms + SLACK_MS)
	quiet.frozen = false
	var back: bool = await _wait(func() -> bool: return not host.session.is_peer_absent(1), SLACK_MS)
	_check(back and host.world.left.is_empty() and quiet.fails.is_empty() and quiet.stalls.is_empty(),
		"S3 silêncio curto: ausência some quando volta; ninguém removido nem avisado (stalls %s)" % str(quiet.stalls))
	await _close_room(room)


## S4: a peer that does not load in load_timeout_s: the hunt starts without it (hunt_go goes out anyway).
func _s4_load_timeout() -> void:
	_say("S4 load deadline")
	var limit_ms: int = _ms("load_timeout_s")
	# (a) the late one finishes loading a second after go.
	var room: Array[Peer] = await _lobby_room(2)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var fast: Peer = room[1]
	var slow: Peer = room[2]
	var t0: int = Time.get_ticks_msec()
	_check(await _start_and_wait_loading(room), "S4 anfitrião iniciou e todos entraram em LOADING")
	_bind(host)
	_bind(fast)
	var went: bool = await _wait(func() -> bool: return host.go_ms > 0, limit_ms + SLACK_MS)
	var lag: int = host.go_ms - t0
	_check(went and lag >= limit_ms - 500 and lag <= limit_ms + 1500,
		"S4 hunt_go do anfitrião saiu em %d ms sem esperar o atrasado (load_timeout_s = %d ms)" % [lag, limit_ms])
	await _wait(func() -> bool: return fast.go_ms > 0, SLACK_MS)
	_check(fast.go_ms > 0 and slow.go_ms == 0, "S4 cliente carregado começou; o atrasado ainda não")
	_check(not host.session.get_peer(2).loaded, "S4 atrasado não consta como carregado")
	await _sleep(1000)
	_bind(slow)
	var caught: bool = await _wait(func() -> bool: return slow.go_ms > 0, SLACK_MS + 1000)
	_check(caught and slow.session.get_state() == NetSession.STATE_IN_HUNT, "S4 atrasado que termina de carregar entra na caçada em andamento")
	await _sleep(1500)
	_check(host.world.left.is_empty() and not host.session.is_peer_absent(2), "S4 atrasado que carregou não foi removido nem ficou ausente")
	await _close_room(room)
	# (b) the late one never loads: absent, then removed like any silent peer (section 6.9).
	room = await _lobby_room(2)
	if room.is_empty():
		return
	host = room[0]
	fast = room[1]
	slow = room[2]
	_check(await _start_and_wait_loading(room), "S4 segunda rodada em LOADING")
	_bind(host)
	_bind(fast)
	await _wait(func() -> bool: return host.go_ms > 0, limit_ms + SLACK_MS)
	var t1: int = Time.get_ticks_msec()
	var absent: bool = await _wait(func() -> bool: return host.session.is_peer_absent(2), _ms("peer_absent_s") + SLACK_MS)
	_check(absent and not host.world.left.has(2), "S4 quem não carrega fica ausente (javalis o ignoram) sem ser removido")
	var removed: bool = await _wait(func() -> bool: return host.world.left.has(2), _ms("peer_timeout_s") + SLACK_MS)
	_check(removed and str(host.world.left) == str([2]), "S4 e é removido depois de peer_timeout_s (%d ms após o go)" % (Time.get_ticks_msec() - t1))
	_check(host.session.get_state() == NetSession.STATE_IN_HUNT and fast.session.get_state() == NetSession.STATE_IN_HUNT,
		"S4 a caçada segue para os demais")
	await _close_room(room)


## S5: the host never says go (its own world never binds): the client gives up after load + host timeouts.
func _s5_client_never_gets_go() -> void:
	_say("S5 client waiting for a go that never comes")
	var room: Array[Peer] = await _lobby_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	_check(await _start_and_wait_loading(room), "S5 LOADING nos dois")
	_bind(client)
	var t0: int = Time.get_ticks_msec()
	var limit_ms: int = _ms("load_timeout_s") + _ms("host_timeout_s")
	var ended: bool = await _wait(func() -> bool: return not client.fails.is_empty(), limit_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(ended and lag >= limit_ms - 500 and str(client.fails) == str(["connection_lost"]),
		"S5 cliente desistiu em %d ms (limite %d ms) %s" % [lag, limit_ms, str(client.fails)])
	_check(client.world.lost == 1 and client.session.get_state() == NetSession.STATE_NONE, "S5 mundo avisado e cliente OFFLINE")
	await _close_room(room)


## S6: flush() sends the pending events at once, in both directions, without waiting for the tick.
func _s6_flush() -> void:
	_say("S6 Net.flush")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	await _sleep(500)
	# The sender is frozen: only flush() can have put the record on the wire.
	host.frozen = true
	host.world.outgoing = _empty_record(NetCodec.EV_HUNT_END)
	host.session.flush()
	var got_event: bool = await _wait(func() -> bool: return client.world.events_in.has(NetCodec.EV_HUNT_END), FLUSH_MS)
	_check(got_event, "S6 evento do anfitrião chegou ao cliente com o anfitrião parado (flush, relay)")
	host.frozen = false
	client.frozen = true
	client.world.outgoing = _empty_record(NetCodec.C_SHOT)
	client.session.flush()
	var got_claim: bool = await _wait(func() -> bool: return host.world.claims_in.has(NetCodec.C_SHOT), FLUSH_MS)
	_check(got_claim, "S6 pedido do cliente chegou ao anfitrião com o cliente parado (flush, relay)")
	client.frozen = false
	await _close_room(room)


## S7: the room is locked while the hunt runs and unlocked when the host's world is gone.
func _s7_lock() -> void:
	_say("S7 room lock")
	var room: Array[Peer] = await _lobby_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var code: String = host.session.get_code()
	_check(await _start_and_wait_loading(room), "S7 caçada iniciada")
	_bind(host)
	_bind(room[1])
	await _wait(func() -> bool: return host.session.get_state() == NetSession.STATE_IN_HUNT, SETUP_MS)
	var late: Peer = _new_peer("Atrasado")
	late.session.join(code)
	await _wait(func() -> bool: return not late.fails.is_empty() or late.session.get_state() == NetSession.STATE_LOBBY, SETUP_MS)
	_check(str(late.fails) == str(["in_progress"]), "S7 sala trancada recusa entrada na caçada %s" % str(late.fails))
	_check(late.fail_messages.size() == 1 and late.fail_messages[0].contains("já começou"), "S7 mensagem em português")
	# Back to the lobby: the world goes away on every machine; the host unlocks.
	room[1].session.unbind_world(room[1].world)
	host.session.unbind_world(host.world)
	_check(host.session.get_state() == NetSession.STATE_LOBBY and room[1].session.get_state() == NetSession.STATE_LOBBY,
		"S7 todos voltaram ao LOBBY")
	var again: Peer = _new_peer("Volta")
	again.session.join(code)
	var joined: bool = await _wait(func() -> bool: return again.session.get_state() == NetSession.STATE_LOBBY or not again.fails.is_empty(), SETUP_MS)
	_check(joined and again.session.get_state() == NetSession.STATE_LOBBY, "S7 sala destrancada aceita entrada de novo %s" % str(again.fails))
	_check(host.session.get_player_count() == 3, "S7 anfitrião vê 3 na sala (%d)" % host.session.get_player_count())
	room.append(late)
	room.append(again)
	await _close_room(room)


## S8: the whole process freezes (a hidden tab): nobody is blamed for it afterwards.
func _s8_whole_process_frozen() -> void:
	_say("S8 whole process frozen")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	await _sleep(500)
	var freeze_ms: int = _ms("host_timeout_s") + SLACK_MS
	var before_frame: float = _last_delta
	OS.delay_msec(freeze_ms)
	await get_tree().process_frame   # resumes before the _process calls of the next frame
	await get_tree().process_frame   # _last_delta is now the delta of the first frame after the freeze
	_say("S8 after %d ms frozen: _process delta of the next frame %.4f s (was %.4f s)" % [freeze_ms, _last_delta, before_frame])
	_check(_last_delta < 1.0, "S8 delta do _process depois do congelamento (%.3f s) não carrega o tempo perdido" % _last_delta)
	await _sleep(SLACK_MS + 500)
	_check(host.session.get_state() == NetSession.STATE_IN_HUNT and client.session.get_state() == NetSession.STATE_IN_HUNT,
		"S8 os dois seguem na caçada depois de %d s parados" % (freeze_ms / 1000))
	_check(host.fails.is_empty() and client.fails.is_empty() and host.world.left.is_empty() and client.world.lost == 0,
		"S8 ninguém foi dado por perdido pelo prazo de relógio de parede")
	_check(client.stalls.is_empty() or client.stalls.back() == false, "S8 sem faixa de aviso presa %s" % str(client.stalls))
	await _close_room(room)


## S9: ping goes out every ping_s and is answered; a server that does not answer is given up on.
func _s9_ping_pong() -> void:
	_say("S9 ping / pong")
	var saved_ping: Variant = _cfg["ping_s"]
	var saved_pong: Variant = _cfg["pong_timeout_s"]
	_cfg["ping_s"] = SHORT_PING_S
	_cfg["pong_timeout_s"] = SHORT_PONG_TIMEOUT_S
	var live: Peer = _new_peer("Ping")
	live.session.create()
	await _wait(func() -> bool: return live.session.get_state() == NetSession.STATE_LOBBY, SETUP_MS)
	var sent_before: int = live.session.get_signaling().sent_text
	await _sleep(int((SHORT_PING_S * 3.0 + SHORT_PONG_TIMEOUT_S) * 1000.0))
	var sent: int = live.session.get_signaling().sent_text - sent_before
	_check(sent >= 2, "S9 pings enviados a cada ping_s (%d em %.1f s)" % [sent, SHORT_PING_S * 3.0 + SHORT_PONG_TIMEOUT_S])
	_check(live.session.get_state() == NetSession.STATE_LOBBY and live.fails.is_empty(), "S9 servidor que responde pong mantém a sala")
	await _close_one(live)
	# A server that never answers.
	_mute = MuteServer.new()
	if not _check(_mute.start(LOOPBACK), "S9 servidor mudo ouvindo"):
		_mute = null
		return
	var mute_url: String = "ws://%s:%d/ws" % [LOOPBACK, _mute.port]
	var deaf: Peer = _new_peer("Surdo", mute_url)
	deaf.session.create()
	await _wait(func() -> bool: return deaf.session.get_state() == NetSession.STATE_LOBBY, SETUP_MS)
	var t0: int = Time.get_ticks_msec()
	var limit_ms: int = int((SHORT_PING_S + SHORT_PONG_TIMEOUT_S) * 1000.0)
	var dropped: bool = await _wait(func() -> bool: return not deaf.fails.is_empty(), limit_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(dropped and str(deaf.fails) == str(["connection_lost"]) and lag >= limit_ms - 600 and lag <= limit_ms + 1500,
		"S9 sem pong a sala caiu em %d ms (ping_s + pong_timeout_s = %d ms) %s" % [lag, limit_ms, str(deaf.fails)])
	_check(_mute.texts >= 1, "S9 o servidor mudo recebeu o ping (%d)" % _mute.texts)
	_cfg["ping_s"] = saved_ping
	_cfg["pong_timeout_s"] = saved_pong
	await _close_one(deaf)
	_mute.stop()
	_mute = null


## S10 (last: it stops the server): the room server dies mid-hunt with every link on the relay.
func _s10_server_dies() -> void:
	_say("S10 room server dies in the hunt")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	await _sleep(500)
	_kill_server.call()
	var t0: int = Time.get_ticks_msec()
	var both: bool = await _wait(func() -> bool: return not host.fails.is_empty() and not client.fails.is_empty(), SETUP_MS)
	_check(both, "S10 os dois terminaram em %d ms sem o servidor" % (Time.get_ticks_msec() - t0))
	_check(str(host.fails) == str(["connection_lost"]) and str(client.fails) == str(["connection_lost"]),
		"S10 room_error connection_lost nos dois (%s / %s)" % [str(host.fails), str(client.fails)])
	_check(client.world.lost == 1 and host.world.lost == 1 and str(host.world.left) == str([1]),
		"S10 mundos avisados (cliente lost=%d, anfitrião lost=%d left=%s)" % [client.world.lost, host.world.lost, str(host.world.left)])
	_check(host.session.get_state() == NetSession.STATE_NONE and client.session.get_state() == NetSession.STATE_NONE, "S10 ambos OFFLINE")
	await _close_room(room)


# --- room helpers --------------------------------------------------------------------------------

func _new_peer(player_name: String, url: String = "") -> Peer:
	var p: Peer = Peer.new()
	p.session = NetSession.new()
	p.session.setup(_cfg, {"url": url if url != "" else _url, "name": player_name, "rtc": false, "router": false,
		"version": str(ProjectSettings.get_setting("application/config/version", ""))})
	p.session.stall_changed.connect(func(stalled: bool) -> void: p.stalls.append(stalled))
	p.session.failed.connect(func(code: StringName, message: String) -> void:
		p.fails.append(str(code))
		p.fail_messages.append(message)
		p.fail_ms = Time.get_ticks_msec())
	p.session.hunt_go.connect(func() -> void: p.go_ms = Time.get_ticks_msec())
	_peers.append(p)
	return p


## Host plus `clients` clients in the lobby, every client ready. [] (and a failed check) if it did not work.
func _lobby_room(clients: int) -> Array[Peer]:
	var room: Array[Peer] = []
	var host: Peer = _new_peer("Host")
	room.append(host)
	host.session.create()
	if not _check(await _wait(func() -> bool: return host.session.get_state() == NetSession.STATE_LOBBY, SETUP_MS), "sala criada"):
		await _close_room(room)
		return []
	for i: int in clients:
		var c: Peer = _new_peer("Cliente %d" % (i + 1))
		room.append(c)
		c.session.join(host.session.get_code())
		if not _check(await _wait(func() -> bool: return c.session.get_state() == NetSession.STATE_LOBBY, SETUP_MS), "cliente %d entrou" % (i + 1)):
			await _close_room(room)
			return []
		c.session.set_ready(true)
	var ready: bool = await _wait(func() -> bool:
		for p: Peer in room:
			if not host.session.get_peer(p.session.get_local_slot()).ready:
				return false
		return true, SETUP_MS)
	if not _check(ready, "todos prontos no lobby"):
		await _close_room(room)
		return []
	return room


func _start_and_wait_loading(room: Array[Peer]) -> bool:
	if not room[0].session.host_start_hunt():
		return false
	return await _wait(func() -> bool:
		for p: Peer in room:
			if p.session.get_state() != NetSession.STATE_LOADING:
				return false
		return true, SETUP_MS)


func _bind(p: Peer) -> void:
	p.world = StubWorld.new()
	p.world.player = StubPlayer.new()
	p.session.bind_world(p.world)


## A room already IN_HUNT on every machine.
func _hunt_room(clients: int) -> Array[Peer]:
	var room: Array[Peer] = await _lobby_room(clients)
	if room.is_empty():
		return []
	if not _check(await _start_and_wait_loading(room), "caçada iniciada, todos em LOADING"):
		await _close_room(room)
		return []
	for p: Peer in room:
		_bind(p)
	var in_hunt: bool = await _wait(func() -> bool:
		for p: Peer in room:
			if p.session.get_state() != NetSession.STATE_IN_HUNT:
				return false
		return true, ROOM_MS)
	if not _check(in_hunt, "hunt_go nos %d peers" % room.size()):
		await _close_room(room)
		return []
	return room


func _close_one(p: Peer) -> void:
	var room: Array[Peer] = [p]
	await _close_room(room)


func _close_room(room: Array[Peer]) -> void:
	for i: int in range(room.size() - 1, -1, -1):
		var p: Peer = room[i]
		p.frozen = false
		p.session.leave()
	await _sleep(150)
	for p: Peer in room:
		_peers.erase(p)
		if p.world != null:
			if p.world.player != null:
				p.world.player.free()
			p.world.free()
			p.world = null


# --- helpers -------------------------------------------------------------------------------------

func _ms(key: String) -> int:
	return int(float(_cfg[key]) * 1000.0)


func _empty_record(type: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(NetCodec.RECORD_HEADER_BYTES)
	out.encode_u8(0, type)
	out.encode_u16(1, 0)
	return out


func _check(cond: bool, label: String) -> bool:
	return bool(_ok.call(cond, label))


func _say(text: String) -> void:
	print("NET_DEADLINES %s" % text)


func _wait(cond: Callable, timeout_ms: int) -> bool:
	var limit: int = Time.get_ticks_msec() + timeout_ms
	while not bool(cond.call()):
		if Time.get_ticks_msec() >= limit:
			return false
		await get_tree().process_frame
	return true


func _sleep(ms: int) -> void:
	var limit: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < limit:
		await get_tree().process_frame
