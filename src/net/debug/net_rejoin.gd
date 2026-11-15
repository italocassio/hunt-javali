extends "res://src/net/debug/net_deadlines.gd"
## Reconnection of a client in the hunt (multiplayer F8, docs/multiplayer.md section 4.7), exercised with real
## NetSessions in this process against the local Bun room server. Started by net_e2e.gd with --rejoin (it owns
## the server); it is not a scene of its own. Rooms, stub worlds and helpers come from net_deadlines.gd.
##
## The cut is NetSession.debug_cut (what Net.debug_cut calls): the room socket is dropped, or muted for the
## half-open case, and rejoin attempts fail without a socket while the cut lasts. Worlds are stubs: the host's
## writes a fake EV_FULL_SYNC with two replayed records, the client's logs every record it is handed, in order.
## The game side of the sync belongs to package B (net_hunt_e2e --scenario=rejoin).
##
## rejoin_timeout_s and peer_timeout_s are shortened (the invariant of section 4.7.9 is kept and checked);
## host_stall_warn_s, rejoin_probe_s and rejoin_backoff_s are the ones of data/net.json.

const SHORT_REJOIN_S: float = 10.0
const SHORT_GRACE_S: float = 18.0
const BRIEF_GRACE_S: float = 5.0          # R4: a host that gives up on the slot before the client is back
const PATIENT_REJOIN_S: float = 60.0      # R4: a client that would keep trying
const CUT_SHORT_S: float = 2.0
const CUT_LONG_S: float = 5.0
const CUT_PAST_GRACE_S: float = 7.0
const CUT_FOREVER_S: float = 600.0
const EVENT_MS: int = 2500                # an event sent by one side shows up on the other
const FRAME_SLACK_MS: int = 250           # scheduling slack of an attempt (frames, not network)
const SYNC_MARK: int = -1                 # EV_FULL_SYNC in SyncWorld.seen
const REPLAYED: Array[int] = [104, 105]   # what the fake sync replays (stands for what happened meanwhile)
const TEST_EVENT: int = NetCodec.EV_MESSAGE
const REPLAY_EVENT: int = NetCodec.EV_BOAR_SPAWN
const FULL_SYNC_BODY_BYTES: int = 10
const CLOSE_REPLACED: int = 4411
const CLOSE_BAD_TOKEN: int = 4401


## Host: counts the syncs it is asked for. Client: logs the value of every record applied, in order.
class SyncWorld extends StubWorld:
	var full_syncs: int = 0
	var seen: Array[int] = []                 # value of every record applied, in order (SYNC_MARK = the sync)
	var sync_bodies: Array[int] = []          # body length of every EV_FULL_SYNC applied
	var sync_records: Array[int] = []         # its n_records
	var snapshots_at_sync: Array[int] = []    # snapshots_in when each sync was applied
	var over: bool = false

	func is_hunt_over() -> bool:
		return over

	func net_write_full_sync(out: StreamPeerBuffer) -> void:
		full_syncs += 1
		out.put_u8(NetCodec.EV_FULL_SYNC)
		out.put_u16(FULL_SYNC_BODY_BYTES)
		out.put_u32(123456)                   # t_ms
		out.put_u16(9050)                     # crop x0.01 %
		out.put_u8(3)                         # killed
		out.put_u8(9)                         # total
		out.put_u16(REPLAYED.size())          # n_records
		for value: int in REPLAYED:
			out.put_u8(REPLAY_EVENT)
			out.put_u16(4)
			out.put_u32(value)

	func net_apply_event(type: int, inp: StreamPeerBuffer, length: int) -> void:
		events_in.append(type)
		if type == NetCodec.EV_FULL_SYNC:
			sync_bodies.append(length)
			sync_records.append(inp.data_array.decode_u16(8) if length >= FULL_SYNC_BODY_BYTES else -1)
			snapshots_at_sync.append(snapshots_in)
			seen.append(SYNC_MARK)
		elif length >= 4:
			seen.append(inp.get_u32())


func _make_world() -> StubWorld:
	return SyncWorld.new()


## ok(cond: bool, label: String) -> bool.
func run_rejoin(url: String, ok: Callable) -> void:
	_url = url
	_ok = ok
	_cfg = Data.get_net().duplicate()
	_cfg["rejoin_timeout_s"] = SHORT_REJOIN_S
	_cfg["peer_timeout_s"] = SHORT_GRACE_S
	var data_cfg: Dictionary = Data.get_net()
	_check(float(data_cfg["host_stall_warn_s"]) + float(data_cfg["rejoin_probe_s"]) + float(data_cfg["rejoin_timeout_s"])
		< float(data_cfg["peer_timeout_s"]), "data/net.json: host_stall_warn_s + rejoin_probe_s + rejoin_timeout_s < peer_timeout_s")
	_check(float(_cfg["host_stall_warn_s"]) + float(_cfg["rejoin_probe_s"]) + float(_cfg["rejoin_timeout_s"])
		< float(_cfg["peer_timeout_s"]), "prazos encurtados mantêm o invariante")
	_say("timeouts: stall_warn=%.1f probe=%.1f rejoin=%.1f grace=%.1f absent=%.1f s, backoff %s" % [
		float(_cfg["host_stall_warn_s"]), float(_cfg["rejoin_probe_s"]), float(_cfg["rejoin_timeout_s"]),
		float(_cfg["peer_timeout_s"]), float(_cfg["peer_absent_s"]), str(_cfg["rejoin_backoff_s"])])
	await _r1_cut_and_return()
	await _r2_half_open()
	await _r3_tampered_token()
	await _r4_cut_past_grace()
	await _r5_client_gives_up()
	await _r6_explicit_leave()


func _say(text: String) -> void:
	print("NET_REJOIN %s" % text)


# --- scenarios -----------------------------------------------------------------------------------

## R1 (a): the client is cut off for 2 s and comes back to the same slot; then again for 5 s.
func _r1_cut_and_return() -> void:
	_say("R1 cut for %.0f s, back in the same slot; then %.0f s" % [CUT_SHORT_S, CUT_LONG_S])
	var room: Array[Peer] = await _hunt_room(2)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var cut: Peer = room[1]
	var witness: Peer = room[2]
	var backoff: Array = _cfg["rejoin_backoff_s"]
	await _sleep(500)
	_check(cut.session.debug_get_token() != 0 and cut.session.debug_get_token() != witness.session.debug_get_token(),
		"R1 cada cliente sorteou o próprio token (≠ 0)")
	_check(cut.session.get_link(0).get_epoch() == 0 and host.session.get_link(1).get_epoch() == 0, "R1 enlace original é da época 0")
	await _host_events(host, [1, 2, 3])
	_check(await _wait(func() -> bool: return _log(cut) == [1, 2, 3] and _log(witness) == [1, 2, 3], EVENT_MS),
		"R1 antes do corte os dois clientes recebem os eventos %s" % str(_log(cut)))
	await _sleep(1100)   # a closed second of traffic
	var traffic: Dictionary = cut.session.get_traffic()
	var host_traffic: Dictionary = host.session.get_traffic()
	_check((traffic.get("links", []) as Array).size() == 1 and int(traffic.get("down_bps", 0)) > 0 and int(traffic.get("up_bps", 0)) > 0,
		"R1 get_traffic do cliente: 1 enlace, ↑ %d ↓ %d B/s" % [int(traffic.get("up_bps", 0)), int(traffic.get("down_bps", 0))])
	_check((host_traffic.get("links", []) as Array).size() == 2 and int(host_traffic.get("up_bps", 0)) > int(traffic.get("up_bps", 0)),
		"R1 get_traffic do anfitrião: 2 enlaces, ↑ %d ↓ %d B/s" % [int(host_traffic.get("up_bps", 0)), int(host_traffic.get("down_bps", 0))])
	_check(int(((traffic["links"] as Array)[0] as Dictionary).get("path", 0)) == NetLink.PATH_RELAY
		and int(((traffic["links"] as Array)[0] as Dictionary).get("slot", -1)) == 0, "R1 enlace do cliente: slot 0 pelo relay")

	# --- the cut ---
	var t0: int = Time.get_ticks_msec()
	var snapshots_at_cut: int = cut.world.snapshots_in
	cut.session.debug_cut(CUT_SHORT_S)
	_check(cut.session.is_reconnecting() and str(cut.reconnects) == str([true]), "R1 corte: is_reconnecting() e reconnect_changed(true) na hora")
	_check(cut.session.get_state() == NetSession.STATE_IN_HUNT and cut.fails.is_empty() and cut.world.lost == 0,
		"R1 o estado da sala continua IN_HUNT durante a reconexão")
	_check(cut.session.get_link(0) == null and cut.session.get_signaling() == null, "R1 enlace e socket antigos descartados")
	var dropped: bool = await _wait(func() -> bool: return host.session.get_link(1) == null, EVENT_MS)
	_check(dropped and host.session.get_peer(1) != null and host.world.left.is_empty(),
		"R1 anfitrião: peer_left sem clean fecha o enlace e guarda o slot")
	await _host_events(host, [4, 5])   # happens while the client is away: it must come back inside the sync
	_check(await _wait(func() -> bool: return _log(witness) == [1, 2, 3, 4, 5], EVENT_MS), "R1 o outro cliente segue recebendo %s" % str(_log(witness)))
	var back: bool = await _wait(func() -> bool: return cut.reconnects.size() >= 2, int((CUT_SHORT_S + float(backoff.back())) * 1000.0) + SLACK_MS)
	var took: int = Time.get_ticks_msec() - t0
	_check(back and str(cut.reconnects) == str([true, false]) and not cut.session.is_reconnecting(),
		"R1 cliente voltou em %d ms (corte de %d ms) %s" % [took, int(CUT_SHORT_S * 1000.0), str(cut.reconnects)])
	_check(took >= int(CUT_SHORT_S * 1000.0), "R1 nenhuma tentativa passou durante o corte")
	_check(cut.session.get_local_slot() == 1 and cut.session.get_state() == NetSession.STATE_IN_HUNT and cut.fails.is_empty()
		and cut.world.lost == 0, "R1 mesmo slot, IN_HUNT, sem room_error")
	_check(host.world.left.is_empty() and witness.world.left.is_empty(), "R1 ninguém chamou net_peer_left (%s / %s)"
		% [str(host.world.left), str(witness.world.left)])
	_check(_sync(host).full_syncs == 1 and host.session.readmissions == 1, "R1 anfitrião chamou net_write_full_sync uma vez (%d)" % _sync(host).full_syncs)
	_check(_sync(cut).sync_bodies == [FULL_SYNC_BODY_BYTES] and _sync(cut).sync_records == [REPLAYED.size()],
		"R1 cliente recebeu um EV_FULL_SYNC de 10 bytes com n_records = %d %s" % [REPLAYED.size(), str(_sync(cut).sync_bodies)])
	_check(_log(cut) == [1, 2, 3, SYNC_MARK, 104, 105], "R1 mundo do cliente: eventos, sync, repetição; nada do que perdeu chega avulso %s" % str(_log(cut)))
	_check(_sync(cut).snapshots_at_sync == [snapshots_at_cut], "R1 nenhum snapshot aplicado entre o corte e o sync (%s, no corte %d)"
		% [str(_sync(cut).snapshots_at_sync), snapshots_at_cut])
	_check(not _log(witness).has(SYNC_MARK) and _sync(witness).sync_bodies.is_empty(), "R1 o sync vai só para o enlace que voltou")
	var epoch: int = cut.session.get_link(0).get_epoch() if cut.session.get_link(0) != null else -1
	var host_epoch: int = host.session.get_link(1).get_epoch() if host.session.get_link(1) != null else -2
	_check(epoch >= 1 and epoch == host_epoch, "R1 enlace novo com a mesma época nas duas pontas (%d / %d)" % [epoch, host_epoch])
	_check(cut.session.get_link(0) != null and cut.session.get_link(0).get_path() == NetLink.PATH_RELAY, "R1 enlace novo nasce no relay")
	_check(cut.session.rejoin_connections == 1, "R1 uma conexão aberta (%d); tentativas em %s ms" % [cut.session.rejoin_connections, str(cut.session.rejoin_attempt_ms)])
	_check(_follows_backoff(cut.session.rejoin_attempt_ms, backoff), "R1 tentativas seguem rejoin_backoff_s %s" % str(cut.session.rejoin_attempt_ms))
	# --- after the return ---
	await _host_events(host, [6, 7, 8])
	_check(await _wait(func() -> bool: return _log(cut).size() >= 9, EVENT_MS) and _log(cut) == [1, 2, 3, SYNC_MARK, 104, 105, 6, 7, 8],
		"R1 eventos enviados depois chegam uma vez e em ordem %s" % str(_log(cut)))
	_check(await _wait(func() -> bool: return _log(witness) == [1, 2, 3, 4, 5, 6, 7, 8], EVENT_MS), "R1 o outro cliente recebeu tudo, sem sync %s" % str(_log(witness)))
	cut.world.outgoing = _empty_record(NetCodec.C_SHOT)
	var claimed: bool = await _wait(func() -> bool: return host.world.claims_in.has(NetCodec.C_SHOT), EVENT_MS)
	await _sleep(300)
	_check(claimed and host.world.claims_in.count(NetCodec.C_SHOT) == 1, "R1 pedido do cliente depois da volta chega uma vez ao anfitrião")
	var snaps: int = cut.world.snapshots_in
	await _sleep(1000)
	_check(cut.world.snapshots_in > snaps + 3, "R1 snapshots voltaram a chegar (%d em 1 s)" % (cut.world.snapshots_in - snaps))
	_check(not host.session.is_peer_absent(1) and cut.stalls.is_empty(), "R1 ninguém ausente nem faixa de anfitrião sem resposta %s" % str(cut.stalls))
	_say("R1 new link: %d frames accepted, %d of the old epoch dropped" % [cut.session.get_link(0).received_frames,
		cut.session.get_link(0).stale_epoch_frames])

	# --- a second, longer cut in the same hunt: 5 s ---
	_say("R1 second cut, %.0f s" % CUT_LONG_S)
	t0 = Time.get_ticks_msec()
	cut.session.debug_cut(CUT_LONG_S)
	var absent: bool = await _wait(func() -> bool: return host.session.is_peer_absent(1), _ms("peer_absent_s") + SLACK_MS)
	_check(absent and host.session.get_peer(1) != null, "R1b durante o corte o slot fica ausente no anfitrião (%d ms)" % (Time.get_ticks_msec() - t0))
	await _host_events(host, [9])
	back = await _wait(func() -> bool: return cut.reconnects.size() >= 4, int((CUT_LONG_S + float(backoff.back())) * 1000.0) + SLACK_MS)
	took = Time.get_ticks_msec() - t0
	_check(back and str(cut.reconnects) == str([true, false, true, false]),
		"R1b cliente derrubado por %d ms voltou em %d ms (limite %d) %s" % [int(CUT_LONG_S * 1000.0), took,
		int((CUT_LONG_S + float(backoff.back())) * 1000.0) + SLACK_MS, str(cut.reconnects)])
	_check(took >= int(CUT_LONG_S * 1000.0) and cut.session.get_local_slot() == 1 and cut.fails.is_empty() and cut.world.lost == 0,
		"R1b mesmo slot, sem room_error")
	_check(host.world.left.is_empty() and _sync(host).full_syncs == 2 and _sync(cut).sync_bodies.size() == 2,
		"R1b sem net_peer_left; um sync por volta (%d)" % _sync(host).full_syncs)
	var epoch2: int = cut.session.get_link(0).get_epoch() if cut.session.get_link(0) != null else -1
	host_epoch = host.session.get_link(1).get_epoch() if host.session.get_link(1) != null else -2
	_check(epoch2 > epoch and epoch2 == host_epoch, "R1b época nova de novo (%d -> %d, anfitrião %d)" % [epoch, epoch2, host_epoch])
	_check(cut.session.rejoin_connections == 2 and _follows_backoff(cut.session.rejoin_attempt_ms, backoff)
		and cut.session.rejoin_attempt_ms.size() == 5, "R1b tentativas em %s ms: uma conexão no total deste corte" % str(cut.session.rejoin_attempt_ms))
	await _host_events(host, [10, 11])
	_check(await _wait(func() -> bool: return _log(cut).size() >= 14, EVENT_MS)
		and _log(cut) == [1, 2, 3, SYNC_MARK, 104, 105, 6, 7, 8, SYNC_MARK, 104, 105, 10, 11],
		"R1b segunda volta: sync e depois só os eventos novos %s" % str(_log(cut)))
	_check(await _wait(func() -> bool: return not host.session.is_peer_absent(1), EVENT_MS), "R1b ausência some quando o estado volta")
	_check(cut.session.rejoin_entries == 2 and cut.session.rejoin_returns == 2, "R1b duas quedas, duas voltas")
	await _close_room(room)


## R2 (b): half-open socket. Nothing closes: the client only finds out by the probe, and the re-entry
## replaces the socket the server still held.
func _r2_half_open() -> void:
	_say("R2 half-open socket: found by the probe, replaced on the server")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	var warn_ms: int = _ms("host_stall_warn_s")
	var probe_ms: int = _ms("rejoin_probe_s")
	await _sleep(500)
	var old_link: NetLink = host.session.get_link(1)
	var t0: int = Time.get_ticks_msec()
	client.session.debug_cut(CUT_SHORT_S, true)
	_check(not client.session.is_reconnecting() and client.session.get_signaling() != null and client.session.get_signaling().is_open(),
		"R2 socket mudo parece aberto: nada acontece na hora")
	var warned: bool = await _wait(func() -> bool: return client.stalls.has(true), warn_ms + SLACK_MS)
	var warn_lag: int = Time.get_ticks_msec() - t0
	_check(warned and warn_lag >= warn_ms - 300 and not client.session.is_reconnecting(),
		"R2 primeiro só a faixa de anfitrião sem resposta, em %d ms" % warn_lag)
	_check(host.session.get_link(1) == old_link and not old_link.is_lost(), "R2 servidor não avisou queda: o enlace antigo do anfitrião segue de pé")
	var found: bool = await _wait(func() -> bool: return not client.reconnects.is_empty(), probe_ms + SLACK_MS)
	var found_lag: int = Time.get_ticks_msec() - t0
	_check(found and found_lag >= warn_ms + probe_ms - 300 and found_lag <= warn_ms + probe_ms + 1500,
		"R2 a sonda sem pong abriu a reconexão em %d ms (stall + sonda = %d ms)" % [found_lag, warn_ms + probe_ms])
	_check(str(client.stalls) == str([true, false]), "R2 faixa de anfitrião sem resposta zerada ao reconectar %s" % str(client.stalls))
	_check(host.world.left.is_empty() and host.session.get_peer(1) != null, "R2 anfitrião não removeu o slot")
	var back: bool = await _wait(func() -> bool: return client.reconnects.size() >= 2, SLACK_MS * 2)
	_check(back and str(client.reconnects) == str([true, false]) and client.session.rejoin_connections == 1,
		"R2 voltou na primeira tentativa, %d ms depois do corte" % (Time.get_ticks_msec() - t0))
	_check(client.session.get_local_slot() == 1 and client.fails.is_empty() and client.world.lost == 0, "R2 mesmo slot, sem room_error")
	var new_link: NetLink = host.session.get_link(1)
	_check(new_link != null and new_link != old_link and new_link.get_epoch() >= 1 and _sync(host).full_syncs == 1,
		"R2 anfitrião trocou o enlace (época %d) e mandou um sync" % (new_link.get_epoch() if new_link != null else -1))
	_check(host.world.left.is_empty(), "R2 sem net_peer_left no anfitrião")
	# The socket the server still had: it was told "replaced" and closed with 4411.
	var parked: Array[NetSignaling] = client.session.debug_take_parked()
	if _check(parked.size() == 1, "R2 o socket mudo ficou guardado, sem fechar (%d)" % parked.size()):
		var old_socket: NetSignaling = parked[0]
		old_socket.debug_unmute()
		var closed: bool = await _wait(func() -> bool:
			old_socket.poll(Time.get_ticks_msec())
			return old_socket.is_closed(), SLACK_MS)
		_check(closed and old_socket.close_code == CLOSE_REPLACED, "R2 servidor fechou o socket antigo com replaced / %d (%d)"
			% [CLOSE_REPLACED, old_socket.close_code])
		old_socket.abort()
	await _host_events(host, [21, 22])
	_check(await _wait(func() -> bool: return _log(client).size() >= 5, EVENT_MS) and _log(client) == [SYNC_MARK, 104, 105, 21, 22],
		"R2 eventos depois da volta em ordem %s" % str(_log(client)))
	await _sleep(500)
	_check(host.world.left.is_empty() and host.session.get_state() == NetSession.STATE_IN_HUNT and client.session.get_state() == NetSession.STATE_IN_HUNT,
		"R2 o fechamento do socket antigo não derrubou ninguém")
	await _close_room(room)


## R3 (c): a token that is not the one the host registered: bad_token, DISCONNECTED, no second attempt.
## Then the host goes back to the lobby: the slot that never came back leaves the roster and the room unlocks.
func _r3_tampered_token() -> void:
	_say("R3 tampered token")
	var room: Array[Peer] = await _hunt_room(2)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var forger: Peer = room[1]
	var witness: Peer = room[2]
	await _sleep(500)
	forger.session.debug_set_token(forger.session.debug_get_token() ^ 1 if forger.session.debug_get_token() > 1 else 2)
	forger.session.debug_cut(0.0)
	var ended: bool = await _wait(func() -> bool: return not forger.fails.is_empty(), SLACK_MS * 2)
	_check(ended and str(forger.fails) == str(["connection_lost"]) and forger.session.rejoin_refusal == &"bad_token",
		"R3 servidor recusou com bad_token → connection_lost (%s, %s)" % [str(forger.fails), forger.session.rejoin_refusal])
	_check(str(forger.fail_messages) == str(["Conexão perdida."]), "R3 mensagem em português %s" % str(forger.fail_messages))
	_check(forger.world.lost == 1 and forger.session.get_state() == NetSession.STATE_NONE, "R3 mundo avisado (DISCONNECTED) e cliente OFFLINE")
	_check(forger.session.rejoin_connections == 1 and forger.session.rejoin_attempt_ms.size() == 1,
		"R3 sem nova tentativa depois da recusa (%d conexões)" % forger.session.rejoin_connections)
	_check(str(forger.reconnects) == str([true]) and not forger.session.is_reconnecting(), "R3 desistir não anuncia volta %s" % str(forger.reconnects))
	await _sleep(500)
	_check(host.world.left.is_empty() and host.session.get_peer(1) != null and _sync(host).full_syncs == 0,
		"R3 anfitrião não foi enganado: slot guardado, nenhum sync")
	_check(witness.world.left.is_empty() and witness.session.get_peer(1) != null, "R3 o outro cliente ainda vê o slot (quem tira é o anfitrião)")
	# Hunt over: everybody goes back to the lobby.
	witness.session.unbind_world(witness.world)
	host.session.unbind_world(host.world)
	_check(host.session.get_state() == NetSession.STATE_LOBBY and host.session.get_peer(1) == null and host.session.get_player_count() == 2,
		"R3 de volta ao lobby o anfitrião tira o slot sem enlace (%d na sala)" % host.session.get_player_count())
	_check(witness.session.get_state() == NetSession.STATE_LOBBY and witness.session.get_peer(1) == null and witness.session.get_player_count() == 2,
		"R3 o outro cliente tira do roster quem o servidor deixou de listar (%d na sala)" % witness.session.get_player_count())
	var again: Peer = _new_peer("Volta")
	again.session.join(host.session.get_code())
	var joined: bool = await _wait(func() -> bool: return again.session.get_state() == NetSession.STATE_LOBBY or not again.fails.is_empty(), SETUP_MS)
	_check(joined and again.session.get_state() == NetSession.STATE_LOBBY and again.session.get_local_slot() == 1,
		"R3 sala destrancada aceita entrada normal no slot livre %s" % str(again.fails))
	_check(await _wait(func() -> bool: return host.session.get_player_count() == 3 and witness.session.get_player_count() == 3, SETUP_MS),
		"R3 todos veem 3 na sala (%d / %d)" % [host.session.get_player_count(), witness.session.get_player_count()])
	room.append(again)
	await _close_room(room)


## R4 (d): the cut outlasts the host's grace period: the host removes the slot and revokes the token; the
## client, still trying, is refused with bad_token.
func _r4_cut_past_grace() -> void:
	_say("R4 cut longer than the grace period")
	var host_cfg: Dictionary = _cfg.duplicate()
	host_cfg["peer_timeout_s"] = BRIEF_GRACE_S
	var client_cfg: Dictionary = _cfg.duplicate()
	client_cfg["rejoin_timeout_s"] = PATIENT_REJOIN_S
	var room: Array[Peer] = await _hunt_room(1, host_cfg, client_cfg)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	var grace_ms: int = int(BRIEF_GRACE_S * 1000.0)
	await _sleep(500)
	var t0: int = Time.get_ticks_msec()
	client.session.debug_cut(CUT_PAST_GRACE_S)
	var removed: bool = await _wait(func() -> bool: return host.world.left.has(1), grace_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(removed and lag >= grace_ms - 300 and str(host.world.left) == str([1]),
		"R4 anfitrião removeu o slot no fim da carência, em %d ms (peer_timeout_s = %d ms)" % [lag, grace_ms])
	_check(host.session.get_peer(1) == null and host.session.get_state() == NetSession.STATE_IN_HUNT, "R4 a caçada do anfitrião segue")
	_check(client.session.is_reconnecting() and client.fails.is_empty(), "R4 cliente ainda tentando")
	var ended: bool = await _wait(func() -> bool: return not client.fails.is_empty(), int(CUT_PAST_GRACE_S * 1000.0) + 4000 + SLACK_MS - lag)
	lag = Time.get_ticks_msec() - t0
	_check(ended and lag >= int(CUT_PAST_GRACE_S * 1000.0) and client.session.rejoin_refusal == &"bad_token"
		and str(client.fails) == str(["connection_lost"]),
		"R4 token revogado: bad_token → connection_lost em %d ms (%s, %s)" % [lag, client.session.rejoin_refusal, str(client.fails)])
	_check(client.world.lost == 1 and client.session.rejoin_connections == 1 and _sync(host).full_syncs == 0,
		"R4 cliente termina DISCONNECTED na primeira conexão que passa; nenhum sync")
	await _sleep(300)
	_check(str(host.world.left) == str([1]) and host.fails.is_empty(), "R4 anfitrião não foi afetado pela tentativa recusada")
	await _close_room(room)


## R5 (e, g): the cut outlasts rejoin_timeout_s: the client gives up by itself, having tried on the backoff
## schedule; the host keeps the slot until the grace period ends.
func _r5_client_gives_up() -> void:
	_say("R5 cut longer than rejoin_timeout_s")
	var room: Array[Peer] = await _hunt_room(1)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var client: Peer = room[1]
	var patience_ms: int = _ms("rejoin_timeout_s")
	var grace_ms: int = _ms("peer_timeout_s")
	var backoff: Array = _cfg["rejoin_backoff_s"]
	await _sleep(500)
	var t0: int = Time.get_ticks_msec()
	client.session.debug_cut(CUT_FOREVER_S)
	var ended: bool = await _wait(func() -> bool: return not client.fails.is_empty(), patience_ms + SLACK_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(ended and lag >= patience_ms - 100 and lag <= patience_ms + 1000,
		"R5 cliente desistiu sozinho em %d ms (rejoin_timeout_s = %d ms)" % [lag, patience_ms])
	_check(str(client.fails) == str(["connection_lost"]) and client.world.lost == 1 and client.session.get_state() == NetSession.STATE_NONE,
		"R5 connection_lost, mundo avisado, OFFLINE %s" % str(client.fails))
	_check(str(client.reconnects) == str([true]), "R5 reconnect_changed só (true): desistir não é voltar %s" % str(client.reconnects))
	var attempts: PackedInt32Array = client.session.rejoin_attempt_ms
	var expected: Array[int] = _schedule(backoff, patience_ms)
	_check(attempts.size() == expected.size() and _follows_backoff(attempts, backoff),
		"R5 tentativas em %s ms (esperado %s)" % [str(attempts), str(expected)])
	_check(client.session.rejoin_connections == 0, "R5 nenhuma conexão aberta durante o corte (%d)" % client.session.rejoin_connections)
	_check(host.world.left.is_empty() and host.session.get_peer(1) != null and host.session.is_peer_absent(1),
		"R5 anfitrião ainda guarda o slot, ausente, quando o cliente desiste")
	var removed: bool = await _wait(func() -> bool: return host.world.left.has(1), grace_ms - lag + SLACK_MS)
	lag = Time.get_ticks_msec() - t0
	_check(removed and lag >= grace_ms - 300 and str(host.world.left) == str([1]) and host.session.get_peer(1) == null,
		"R5 fim da carência sem enlace: net_peer_left em %d ms (peer_timeout_s = %d ms)" % [lag, grace_ms])
	_check(host.session.get_state() == NetSession.STATE_IN_HUNT and host.fails.is_empty(), "R5 a caçada do anfitrião segue")
	await _close_room(room)


## R6 (f): leaving on purpose removes the hunter at once, on the host and on the other clients, and
## revokes its token.
func _r6_explicit_leave() -> void:
	_say("R6 explicit leave")
	var room: Array[Peer] = await _hunt_room(2)
	if room.is_empty():
		return
	var host: Peer = room[0]
	var leaver: Peer = room[1]
	var witness: Peer = room[2]
	var code: String = host.session.get_code()
	var token: int = leaver.session.debug_get_token()
	await _sleep(500)
	var t0: int = Time.get_ticks_msec()
	leaver.session.leave()
	var removed: bool = await _wait(func() -> bool: return host.world.left.has(1), EVENT_MS)
	var lag: int = Time.get_ticks_msec() - t0
	_check(removed and lag <= 1500 and str(host.world.left) == str([1]) and host.session.get_peer(1) == null,
		"R6 saída explícita: net_peer_left no anfitrião em %d ms, sem carência" % lag)
	var told: bool = await _wait(func() -> bool: return witness.world.left.has(1), EVENT_MS)
	_check(told and str(witness.world.left) == str([1]) and witness.session.get_peer(1) == null,
		"R6 o outro cliente tira o caçador quando o anfitrião deixa de listá-lo (%d ms)" % (Time.get_ticks_msec() - t0))
	_check(leaver.reconnects.is_empty() and leaver.fails.is_empty(), "R6 quem saiu não tentou reconectar")
	await _sleep(300)
	# The token of who left is no longer good: a re-entry with it is refused.
	var probe: NetSignaling = NetSignaling.new()
	var url: String = NetSignaling.build_url(_url, {"t": "join", "code": code, "want": 2, "tok": token, "ep": 1,
		"v": str(ProjectSettings.get_setting("application/config/version", "")), "proto": NetCodec.PROTOCOL_VERSION, "name": "Fantasma"})
	if _check(probe.open(url, _cfg, Time.get_ticks_msec()), "R6 conexão de reentrada aberta"):
		var closed: bool = await _wait(func() -> bool:
			probe.poll(Time.get_ticks_msec())
			return probe.is_closed(), SETUP_MS)
		_check(closed and probe.close_code == CLOSE_BAD_TOKEN, "R6 token de quem saiu foi revogado: close %d (%d)" % [CLOSE_BAD_TOKEN, probe.close_code])
	_check(host.session.get_player_count() == 2 and host.world.left.size() == 1 and _sync(host).full_syncs == 0,
		"R6 anfitrião segue com 2 na caçada")
	await _close_room(room)


# --- helpers -------------------------------------------------------------------------------------

func _sync(p: Peer) -> SyncWorld:
	return p.world as SyncWorld


func _log(p: Peer) -> Array[int]:
	return _sync(p).seen


## Queues test events on the host's world (they leave on its next tick) and waits for that tick.
func _host_events(host: Peer, values: Array[int]) -> void:
	var records: PackedByteArray = host.world.outgoing
	for value: int in values:
		var record: PackedByteArray = PackedByteArray()
		record.resize(NetCodec.RECORD_HEADER_BYTES + 4)
		record.encode_u8(0, TEST_EVENT)
		record.encode_u16(1, 4)
		record.encode_u32(NetCodec.RECORD_HEADER_BYTES, value)
		records.append_array(record)
	host.world.outgoing = records
	await _wait(func() -> bool: return host.world.outgoing.is_empty(), EVENT_MS)


## Attempt times (ms since the episode began) of a client whose attempts fail at once, until patience_ms.
func _schedule(backoff: Array, patience_ms: int) -> Array[int]:
	var out: Array[int] = []
	var at: int = 0
	var failures: int = 0
	while at <= patience_ms:
		out.append(at)
		at += int(float(backoff[mini(failures, backoff.size() - 1)]) * 1000.0)
		failures += 1
	return out


## Each attempt comes rejoin_backoff_s[min(failures so far, last)] after the previous one failed. Attempts
## that fail at once (the cut) are exactly that far apart; the last one may have taken a real connection.
func _follows_backoff(attempts: PackedInt32Array, backoff: Array) -> bool:
	if attempts.is_empty() or attempts[0] > FRAME_SLACK_MS:
		return false
	for i: int in range(1, attempts.size()):
		var wait_ms: int = int(float(backoff[mini(i - 1, backoff.size() - 1)]) * 1000.0)
		var gap: int = attempts[i] - attempts[i - 1]
		if gap < wait_ms or gap > wait_ms + FRAME_SLACK_MS:
			return false
	return true
