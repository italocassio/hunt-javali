extends "res://tests/lib/test_case.gd"
## Multiplayer F1 (docs/multiplayer.md sections 3.4, 3.6, 9.1, 9.9): offline Net stub, data blocks, NetCodec, player_name.
## No socket is involved: everything here runs in a single process.

const MAP_RECT: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)

const NET_KEYS: Array[String] = ["version", "server_url", "dev_server_url", "rtc_enabled", "ice_servers",
	"ice_timeout_s", "rtc_stall_s", "connect_timeout_s", "ping_s", "pong_timeout_s", "max_players", "snapshot_hz",
	"hunter_state_hz", "relay_hz", "boar_interp_delay_ms", "hunter_interp_delay_ms", "max_frame_bytes",
	"reliable_window", "load_timeout_s", "host_stall_warn_s", "host_timeout_s", "peer_absent_s", "peer_timeout_s",
	"hit_claim_tolerance_m", "name_max_chars"]
const COOP_KEYS: Array[String] = ["boar_count_mult_by_players", "extra_group_delay_s", "spawn_spacing_m",
	"spectate_delay_s", "spectate_distance_m", "spectate_height_m", "name_tag_max_m"]


# --- autoload Net: offline stub (F1) ---

func test_net_offline_values() -> void:
	ok(not Net.is_active(), "is_active falso")
	ok(not Net.is_in_room(), "is_in_room falso")
	ok(not Net.is_host(), "is_host falso")
	eq(Net.get_local_slot(), 0, "slot local 0")
	eq(Net.get_role(), Net.Role.OFFLINE, "papel OFFLINE")
	eq(Net.get_room_state(), Net.RoomState.NONE, "estado NONE")
	eq(Net.get_room_code(), "", "sem codigo de sala")
	eq(Net.get_room_link(), "", "sem link de sala")
	eq(Net.get_player_count(), 1, "1 jogador")
	eq(Net.get_roster().size(), 0, "roster vazio")
	eq(Net.get_peer(0), null, "get_peer(0) nulo")
	eq(Net.get_peer(3), null, "get_peer(3) nulo")
	eq(Net.get_peer(-1), null, "get_peer(-1) nulo")
	eq(Net.get_link_path(0), Net.Path.NONE, "sem enlace")
	eq(Net.take_url_room_code(), "", "sem codigo na URL")
	eq(Net.get_selected_contract_index(), 0, "contrato selecionado 0")
	eq(Net.get_selected_map_id(), &"", "sem mapa selecionado")


func test_net_offline_actions_are_inert() -> void:
	# Only calls that must do nothing without a room. create_room/join_room are NOT here: with the real
	# Net they open a session (see test_net_create_room_then_leave_returns_offline).
	ok(Net.get_role() == Net.Role.OFFLINE, "precondicao: nenhum teste anterior deixou sessao aberta")
	var rec: Dictionary = record_signal(Net.room_state_changed)
	Net.leave_room()
	Net.leave_room()   # idempotent
	Net.set_ready(true)
	Net.flush()
	ok(not Net.host_start_hunt(), "host_start_hunt recusado offline")
	ok(not Net.host_select_contract(&"mato_grosso", 0), "host_select_contract recusado offline")
	await frames(2)
	eq(Net.get_role(), Net.Role.OFFLINE, "continua OFFLINE depois das chamadas")
	eq(Net.get_room_state(), Net.RoomState.NONE, "continua NONE")
	eq(rec["count"], 0, "nenhuma mudanca de estado de sala")
	ok(not Net.is_processing(), "Net offline fica com set_process(false)")


func test_net_join_invalid_code_fails_without_session() -> void:
	# A malformed code is refused locally, before any socket exists.
	var errors: Dictionary = record_signal(Net.room_error)
	Net.join_room("!!")
	eq(errors["count"], 1, "room_error emitido uma vez")
	if int(errors["count"]) > 0:
		eq((errors["calls"] as Array)[0][0], &"room_not_found", "codigo de erro")
		ok(String((errors["calls"] as Array)[0][1]) != "", "mensagem em PT-BR nao vazia")
	eq(Net.get_role(), Net.Role.OFFLINE, "continua OFFLINE")
	eq(Net.get_room_state(), Net.RoomState.NONE, "continua NONE")
	Net.leave_room()   # defensive: the test must never leave a session behind
	await frames(2)
	ok(not Net.is_processing(), "Net volta a set_process(false)")


func test_net_create_room_then_leave_returns_offline() -> void:
	# create_room is real: in native Godot it opens a session against the dev URL. The test only asserts the
	# local state machine and always closes the session itself (no server needs to exist).
	if not Net.is_configured():
		skip("Net sem URL utilizavel nesta plataforma")
		return
	var states: Dictionary = record_signal(Net.room_state_changed)
	Net.create_room()
	eq(Net.get_room_state(), Net.RoomState.CONNECTING, "create_room entra em CONNECTING")
	eq(Net.get_role(), Net.Role.HOST, "papel HOST enquanto conecta")
	Net.create_room()   # second call while a session exists must not open another one
	eq(Net.get_room_state(), Net.RoomState.CONNECTING, "segunda chamada nao muda o estado")
	Net.leave_room()
	eq(Net.get_role(), Net.Role.OFFLINE, "leave_room volta a OFFLINE")
	eq(Net.get_room_state(), Net.RoomState.NONE, "leave_room volta a NONE")
	eq(Net.get_player_count(), 1, "contagem solo de volta")
	eq(Net.get_room_code(), "", "sem codigo")
	Net.leave_room()   # idempotent
	var seen: Array = []
	for c: Variant in states["calls"]:
		seen.append(int((c as Array)[0]))
	eq(seen, [Net.RoomState.CONNECTING, Net.RoomState.NONE], "estados emitidos")
	# The closing socket finishes its handshake in _process; it must wind down by itself.
	var t0: int = Time.get_ticks_msec()
	while Net.is_processing() and Time.get_ticks_msec() - t0 < 4000:
		await frames(1)
	ok(not Net.is_processing(), "Net para de processar depois do fechamento (%d ms)" % (Time.get_ticks_msec() - t0))


func test_net_bind_world_offline_is_harmless() -> void:
	var world: HuntWorld = HuntWorld.new()
	track(world)
	Net.bind_world(world)
	Net.unbind_world(world)
	Net.unbind_world(world)   # twice: _exit_tree may run after an explicit unbind
	eq(Net.get_player_count(), 1, "continua com 1 jogador")


func test_net_enums_match_contract() -> void:
	eq(Net.Role.OFFLINE, 0, "Role.OFFLINE")
	eq(Net.Role.HOST, 1, "Role.HOST")
	eq(Net.Role.CLIENT, 2, "Role.CLIENT")
	eq(Net.RoomState.IN_HUNT, 4, "RoomState.IN_HUNT")
	eq(Net.Path.RTC, 2, "Path.RTC")


func test_net_is_last_autoload() -> void:
	var children: Array[Node] = tree().root.get_children()
	var names: Array[String] = []
	for c: Node in children:
		names.append(str(c.name))
	var idx_net: int = names.find("Net")
	var idx_router: int = names.find("Router")
	ok(idx_net >= 0 and idx_router >= 0, "Net e Router na arvore")
	ok(idx_net > idx_router, "Net depois de Router na ordem dos autoloads")


# --- data ---

func test_data_net_block() -> void:
	var net: Dictionary = Data.get_net()
	for key: String in NET_KEYS:
		contains(net, key, "data/net.json: chave %s" % key)
	eq(Data.get_load_errors().size(), 0, "Data sem erros de carga")
	eq(int(net["max_players"]), 4, "max_players 4")
	ok(int(net["name_max_chars"]) > 0, "name_max_chars positivo")
	ok(int(net["max_frame_bytes"]) > NetCodec.FRAME_HEADER_BYTES, "max_frame_bytes cabe um cabecalho")
	ok(net["ice_servers"] is Array and (net["ice_servers"] as Array).size() > 0, "ice_servers e lista nao vazia")
	for key: String in ["ice_timeout_s", "rtc_stall_s", "connect_timeout_s", "ping_s", "pong_timeout_s", "load_timeout_s",
			"host_stall_warn_s", "host_timeout_s", "peer_absent_s", "peer_timeout_s"]:
		ok(float(net[key]) > 0.0, "%s positivo" % key)
	for key: String in ["snapshot_hz", "hunter_state_hz", "relay_hz", "reliable_window"]:
		ok(int(net[key]) > 0, "%s positivo (evita divisao por zero no tick)" % key)
	ok(float(net["host_stall_warn_s"]) < float(net["host_timeout_s"]), "aviso de travamento vem antes do timeout")
	ok(float(net["peer_absent_s"]) < float(net["peer_timeout_s"]), "ausente vem antes do timeout")
	ok(int(net["reliable_window"]) < 0x8000, "janela confiavel cabe na comparacao circular de u16")
	ok(String(net["server_url"]).begins_with("wss://"), "producao usa wss")
	ok(String(net["dev_server_url"]).begins_with("ws://"), "dev usa ws")


func test_data_coop_block() -> void:
	var coop: Variant = Data.get_game().get("coop")
	ok(coop is Dictionary, "game.json tem o bloco coop")
	if not coop is Dictionary:
		return
	for key: String in COOP_KEYS:
		contains(coop, key, "coop.%s" % key)
	var mult: Array = coop["boar_count_mult_by_players"]
	eq(mult.size(), int(Data.get_net()["max_players"]), "um multiplicador por quantidade de jogadores")
	eq(float(mult[0]), 1.0, "1 jogador = 1.0 (solo intacto)")
	for i: int in range(1, mult.size()):
		ok(float(mult[i]) >= float(mult[i - 1]), "multiplicador nao decresce em %d jogadores" % (i + 1))
	for key: String in ["extra_group_delay_s", "spawn_spacing_m", "spectate_delay_s", "spectate_distance_m",
			"spectate_height_m", "name_tag_max_m"]:
		ok(float(coop[key]) >= 0.0, "coop.%s nao negativo" % key)


# --- save: player_name ---

func test_player_name_default_in_new_save_and_old_save() -> void:
	var fresh: Dictionary = SaveService.new_save()
	eq(fresh["settings"]["player_name"], "", "save novo: player_name vazio")
	eq(fresh["version"], SaveService.CURRENT_VERSION, "versao do save novo")
	var old: Dictionary = {"version": SaveService.CURRENT_VERSION, "settings": {"quality": "low", "volume_master": 0.5}}
	var migrated: Dictionary = SaveService.migrate(old)
	eq(migrated["version"], SaveService.CURRENT_VERSION, "migrate nao muda a versao por causa do nome")
	var clean: Dictionary = SaveService.sanitize(migrated)
	eq(clean["settings"]["player_name"], "", "save antigo ganha player_name vazio")
	eq(clean["settings"]["quality"], "low", "demais ajustes preservados")
	eq(clean["version"], SaveService.CURRENT_VERSION, "sanitize nao sobe a versao")
	eq(SaveService.CURRENT_VERSION, 2, "versao do save continua 2")


func test_profile_loads_old_save_without_player_name() -> void:
	cleanup_test_files()
	Profile.set_save_path("user://test_save.json")
	write_text("user://test_save.json", JSON.stringify({
		"version": SaveService.CURRENT_VERSION, "wallet": {"money": 321, "gold": 4},
		"settings": {"quality": "medium"}}))
	Profile.load_or_create()
	eq(Profile.get_setting("player_name"), "", "perfil antigo: player_name vazio")
	eq(Profile.get_setting("quality"), "medium", "ajuste antigo preservado")
	eq(Profile.get_money(), 321, "dinheiro preservado")
	eq(int(SaveService.read("user://test_save.json")["version"]), SaveService.CURRENT_VERSION, "versao gravada continua a mesma")
	cleanup_test_files()


func test_player_name_is_cleaned_and_truncated() -> void:
	var max_chars: int = int(Data.get_net()["name_max_chars"])
	eq(SaveService.sanitize_setting("player_name", "Joao"), "Joao", "nome normal")
	eq(SaveService.sanitize_setting("player_name", "  Joao  "), "Joao", "espacos nas pontas")
	eq(SaveService.sanitize_setting("player_name", "Jo\u0001a\no\t\u007f"), "Joao", "controles removidos")
	eq(SaveService.sanitize_setting("player_name", "A\u0085B\u009fC"), "ABC", "controles C1 removidos")
	eq(SaveService.sanitize_setting("player_name", "\u0003\u0001\u0002"), "", "so controles vira vazio")
	eq(SaveService.sanitize_setting("player_name", "   "), "", "so espacos vira vazio")
	eq(SaveService.sanitize_setting("player_name", "João Ç"), "João Ç", "acentos preservados")
	var long_name: String = "x".repeat(max_chars * 3)
	eq(String(SaveService.sanitize_setting("player_name", long_name)).length(), max_chars, "cortado em name_max_chars")
	eq(SaveService.sanitize_setting("player_name", "x".repeat(max_chars)), "x".repeat(max_chars), "exatamente no limite passa")
	var spaced: String = "y".repeat(max_chars - 1) + " zzzz"
	eq(SaveService.sanitize_setting("player_name", spaced), "y".repeat(max_chars - 1), "corte nao deixa espaco no fim")
	var mixed: String = "\u0001".repeat(40) + "ok"
	eq(SaveService.sanitize_setting("player_name", mixed), "ok", "controles saem antes do corte")
	for bad: Variant in [null, 5, 1.5, true, [], {}, &"nome"]:
		eq(SaveService.sanitize_setting("player_name", bad), "", "tipo invalido %s vira vazio" % str(bad))


func test_player_name_through_profile_and_save() -> void:
	fresh_profile()
	var max_chars: int = int(Data.get_net()["name_max_chars"])
	Profile.set_setting("player_name", "  Cacador\u0003 Teste " + "w".repeat(40))
	var stored: String = String(Profile.get_setting("player_name"))
	ok(stored.length() <= max_chars, "perfil guarda no maximo name_max_chars (%d)" % stored.length())
	ok(not stored.contains("\u0003"), "perfil sem controle")
	ok(stored == stored.strip_edges(), "perfil sem espacos nas pontas")
	ok(stored.begins_with("Cacador"), "inicio do nome preservado")
	var dirty: Dictionary = SaveService.new_save()
	dirty["settings"]["player_name"] = "Z\u0007" + "q".repeat(100)
	var back: Dictionary = SaveService.sanitize(dirty)
	var back_name: String = String(back["settings"]["player_name"])
	ok(back_name.length() <= max_chars and not back_name.contains("\u0007"), "sanitize limpa nome vindo de save adulterado")
	eq(SaveService.sanitize(back)["settings"]["player_name"], back["settings"]["player_name"], "sanitize idempotente no nome")
	eq(SaveService.default_settings().get("player_name"), "", "default_settings tem player_name vazio")
	cleanup_test_files()


# --- NetCodec ---

func test_codec_constants_and_tables() -> void:
	eq(NetCodec.PROTOCOL_VERSION, 1, "versao do protocolo")
	eq(NetCodec.FRAME_HEADER_BYTES, 5, "cabecalho do quadro")
	eq(NetCodec.RECORD_HEADER_BYTES, 3, "cabecalho do registro")
	eq(NetCodec.HUNTER_STATE_BYTES, 14, "estado do cacador")
	eq(NetCodec.NO_SLOT, 255, "NO_SLOT")
	var types: Array[int] = [NetCodec.L_READY, NetCodec.L_LOBBY, NetCodec.L_START, NetCodec.L_LOADED, NetCodec.L_GO,
		NetCodec.L_NEED_RELAY, NetCodec.H_SNAPSHOT, NetCodec.EV_BOAR_SPAWN, NetCodec.EV_BOAR_HIT, NetCodec.EV_BOAR_ATTACK,
		NetCodec.EV_BOAR_DEATH, NetCodec.EV_CROP_EATEN, NetCodec.EV_BAIT, NetCodec.EV_DOG_MARK, NetCodec.EV_DOG_CMD,
		NetCodec.EV_MESSAGE, NetCodec.EV_HUNT_END, NetCodec.EV_FULL_SYNC, NetCodec.C_STATE, NetCodec.C_SHOT,
		NetCodec.C_CHARGE_HIT, NetCodec.C_BAIT, NetCodec.C_DOG_CMD]
	var seen: Dictionary = {}
	for t: int in types:
		ok(t >= 0 and t <= 255, "tipo %d cabe em u8" % t)
		ok(not seen.has(t), "tipo de registro 0x%02X unico" % t)
		seen[t] = true
	var flags: Array[int] = [NetCodec.HF_CROUCH, NetCodec.HF_AIM, NetCodec.HF_SPRINT, NetCodec.HF_ALIVE,
		NetCodec.HF_RELOAD, NetCodec.HF_UNARMED]
	var acc: int = 0
	for f: int in flags:
		eq(acc & f, 0, "flag %d sem sobreposicao" % f)
		acc |= f
	ok(acc <= 255, "flags cabem em u8")
	eq(NetCodec.BOAR_STATES.size(), 12, "12 estados de javali")
	eq(NetCodec.DOG_STATES.size(), 7, "7 estados de cao")
	eq(NetCodec.ZONES.size(), 5, "5 zonas")


func test_codec_tables_match_game_ids() -> void:
	# Boar zones on the wire must be the zones the game knows (plus "dog").
	for z: StringName in [Ids.ZONE_HEAD, Ids.ZONE_VITAL, Ids.ZONE_BODY, Ids.ZONE_REAR]:
		ok(NetCodec.ZONES.has(z), "ZONES tem %s" % z)
	var seen: Dictionary = {}
	for table: Array in [NetCodec.BOAR_STATES, NetCodec.DOG_STATES, NetCodec.ZONES]:
		seen.clear()
		for s: StringName in table:
			ok(not seen.has(s), "entrada repetida na tabela: %s" % s)
			seen[s] = true


func test_codec_xz_roundtrip_within_tolerance() -> void:
	# 256 m over 65535 steps: 3.9 mm per step, so the error stays below half a step.
	var tol: float = MAP_RECT.size.x / 65535.0 * 0.5 + 0.00001
	var samples: Array[Vector2] = [Vector2(0, 0), Vector2(-128, -128), Vector2(128, 128), Vector2(-128, 128),
		Vector2(127.999, -127.999), Vector2(12.345, -67.891), Vector2(-100.25, 99.75), Vector2(0.001, -0.001)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260101
	for i: int in 200:
		samples.append(Vector2(rng.randf_range(-128.0, 128.0), rng.randf_range(-128.0, 128.0)))
	for p: Vector2 in samples:
		var buf: StreamPeerBuffer = StreamPeerBuffer.new()
		NetCodec.put_xz(buf, MAP_RECT, p.x, p.y)
		eq(buf.get_size(), 4, "put_xz escreve 4 bytes")
		buf.seek(0)
		var q: Vector2 = NetCodec.get_xz(buf, MAP_RECT)
		near(q.x, p.x, tol, "x de %s" % str(p))
		near(q.y, p.y, tol, "z de %s" % str(p))


func test_codec_xz_extremes_and_out_of_range() -> void:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	NetCodec.put_xz(buf, MAP_RECT, -128.0, -128.0)
	NetCodec.put_xz(buf, MAP_RECT, 128.0, 128.0)
	NetCodec.put_xz(buf, MAP_RECT, -5000.0, 5000.0)   # outside the map: clamped, never wraps
	NetCodec.put_xz(buf, MAP_RECT, 5000.0, -5000.0)
	buf.seek(0)
	var a: Vector2 = NetCodec.get_xz(buf, MAP_RECT)
	var b: Vector2 = NetCodec.get_xz(buf, MAP_RECT)
	var c: Vector2 = NetCodec.get_xz(buf, MAP_RECT)
	var d: Vector2 = NetCodec.get_xz(buf, MAP_RECT)
	near(a.x, -128.0, 0.0001, "canto minimo exato")
	near(b.x, 128.0, 0.0001, "canto maximo exato")
	near(c.x, -128.0, 0.0001, "x muito negativo prende no minimo")
	near(c.y, 128.0, 0.0001, "z muito positivo prende no maximo")
	near(d.x, 128.0, 0.0001, "x muito positivo prende no maximo")
	near(d.y, -128.0, 0.0001, "z muito negativo prende no minimo")
	# Non-square, offset rect.
	var odd: Rect2 = Rect2(10.0, -40.0, 100.0, 50.0)
	var buf2: StreamPeerBuffer = StreamPeerBuffer.new()
	NetCodec.put_xz(buf2, odd, 60.0, -15.0)
	buf2.seek(0)
	var r: Vector2 = NetCodec.get_xz(buf2, odd)
	near(r.x, 60.0, 0.002, "x em rect deslocado")
	near(r.y, -15.0, 0.002, "z em rect deslocado")


func test_codec_angle_u8_roundtrip() -> void:
	var step: float = TAU / 256.0
	for deg: int in range(-720, 721, 7):
		var rad: float = deg_to_rad(float(deg))
		var q: int = NetCodec.angle_to_u8(rad)
		ok(q >= 0 and q <= 255, "u8 em faixa para %d graus (%d)" % [deg, q])
		var back: float = NetCodec.u8_to_angle(q)
		var diff: float = absf(wrapf(back - rad, -PI, PI))
		ok(diff <= step * 0.5 + 0.0001, "erro de %d graus dentro de meio passo (%.4f rad)" % [deg, diff])
	eq(NetCodec.angle_to_u8(0.0), 0, "0 rad")
	eq(NetCodec.angle_to_u8(TAU), 0, "2pi volta ao 0 (sem 256)")
	eq(NetCodec.angle_to_u8(-0.0001), 0, "pouco abaixo de 0 arredonda para 0")
	eq(NetCodec.angle_to_u8(PI), 128, "pi = 128")
	eq(NetCodec.angle_to_u8(-PI / 2.0), 192, "-pi/2 = 192")
	eq(NetCodec.angle_to_u8(TAU - 0.0001), 0, "quase uma volta = 0")


func test_codec_angle_u16_roundtrip() -> void:
	var step: float = TAU / 65536.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 300:
		var rad: float = rng.randf_range(-4.0 * PI, 4.0 * PI)
		var q: int = NetCodec.angle_to_u16(rad)
		ok(q >= 0 and q <= 65535, "u16 em faixa (%d)" % q)
		var diff: float = absf(wrapf(NetCodec.u16_to_angle(q) - rad, -PI, PI))
		ok(diff <= step * 0.5 + 0.00001, "erro u16 %.7f rad" % diff)
	eq(NetCodec.angle_to_u16(TAU), 0, "2pi volta ao 0")
	eq(NetCodec.angle_to_u16(PI), 32768, "pi = 32768")
	eq(NetCodec.angle_to_u16(-PI), 32768, "-pi = 32768")


func test_codec_seq_newer_wraps() -> void:
	ok(NetCodec.seq_newer(5, 4), "5 e mais novo que 4")
	ok(not NetCodec.seq_newer(4, 5), "4 nao e mais novo que 5")
	ok(not NetCodec.seq_newer(7, 7), "igual nao e mais novo")
	# wrap: 0 comes right after 65535
	ok(NetCodec.seq_newer(0, 65535), "0 e mais novo que 65535 (volta do u16)")
	ok(not NetCodec.seq_newer(65535, 0), "65535 nao e mais novo que 0")
	ok(NetCodec.seq_newer(3, 65533), "3 mais novo que 65533 (5 passos)")
	ok(not NetCodec.seq_newer(65533, 3), "65533 nao e mais novo que 3")
	ok(NetCodec.seq_newer(100, 65500), "100 mais novo que 65500 (136 passos)")
	# the half-circle boundary
	ok(NetCodec.seq_newer(0x7FFF, 0), "0x7FFF passos a frente: mais novo")
	ok(not NetCodec.seq_newer(0x8000, 0), "0x8000 passos: ambiguo, tratado como antigo")
	ok(not NetCodec.seq_newer(0x8001, 0), "alem da metade: antigo")
	# antisymmetry over the whole circle for a few bases
	for base: int in [0, 1, 255, 32767, 32768, 65534, 65535]:
		for delta: int in [1, 2, 100, 32767]:
			var newer: int = (base + delta) & 0xFFFF
			ok(NetCodec.seq_newer(newer, base), "%d+%d e mais novo" % [base, delta])
			ok(not NetCodec.seq_newer(base, newer), "%d nao e mais novo que %d+%d" % [base, base, delta])


func test_codec_shot_id() -> void:
	eq(NetCodec.make_shot_id(0, 0), 0, "slot 0, contador 0")
	eq(NetCodec.make_shot_id(0, 1), 1, "slot 0 devolve o proprio contador (solo nao muda)")
	eq(NetCodec.make_shot_id(0, 123456), 123456, "slot 0, contador grande")
	eq(NetCodec.make_shot_id(0, 0xFFFFFF), 0xFFFFFF, "slot 0, contador no maximo")
	eq(NetCodec.make_shot_id(0, 0x1000000), 0, "contador estoura 24 bits sem vazar para o slot")
	eq(NetCodec.make_shot_id(0, 0x1000005), 5, "contador estoura 24 bits")
	for slot: int in [0, 1, 2, 3]:
		for counter: int in [0, 1, 99, 0xFFFFFF]:
			var id: int = NetCodec.make_shot_id(slot, counter)
			eq(NetCodec.shot_slot(id), slot, "slot %d recuperado de contador %d" % [slot, counter])
			eq(id & 0xFFFFFF, counter, "contador %d preservado no slot %d" % [counter, slot])
	ne(NetCodec.make_shot_id(1, 5), NetCodec.make_shot_id(2, 5), "slots diferentes, ids diferentes")
	ne(NetCodec.make_shot_id(1, 5), NetCodec.make_shot_id(0, 5), "slot 1 difere do solo")
	ok(NetCodec.make_shot_id(3, 0xFFFFFF) > 0, "id do slot 3 nao fica negativo")
	ok(NetCodec.make_shot_id(3, 0xFFFFFF) < 0x100000000, "id cabe em u32")
	# Solo ids (slot 0) must be what boar_hit already carries today: a plain incrementing int.
	eq(NetCodec.shot_slot(0), 0, "shot_slot(0)")
	eq(NetCodec.shot_slot(77), 0, "shot_slot de id solo")


func test_peer_info_defaults() -> void:
	var p: NetPeerInfo = NetPeerInfo.new()
	eq(p.slot, 0, "slot")
	eq(p.display_name, "", "nome")
	ok(not p.is_host, "is_host")
	ok(not p.ready, "ready")
	ok(not p.loaded, "loaded")
	eq(p.weapon_id, &"", "arma")
	eq(p.dog_id, &"", "cao")
	eq(p.path, Net.Path.NONE, "path NONE")


## Named to run last in this file (methods run in alphabetical order): no test above may leave a session open.
func test_zz_no_session_left_open() -> void:
	eq(Net.get_role(), Net.Role.OFFLINE, "Net OFFLINE no fim de test_net")
	eq(Net.get_room_state(), Net.RoomState.NONE, "Net sem sala no fim de test_net")
	ok(not Net.is_host(), "is_host falso no fim de test_net")


func test_hunter_state_buffer_roundtrip_base_is_noop() -> void:
	# The base class writes nothing: concrete hunters must write exactly HUNTER_STATE_BYTES (checked in F2).
	var p: PlayerBase = PlayerBase.new()
	track(p)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	p.net_write_state(buf)
	eq(buf.get_size(), 0, "base nao escreve")
	ok(NetCodec.HUNTER_STATE_BYTES == 14, "tamanho acordado do estado")
