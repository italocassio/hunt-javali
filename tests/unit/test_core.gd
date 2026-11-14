extends "res://tests/lib/test_case.gd"
## Core value classes (HuntResult, HitInfo, KillInfo, HuntRequest, HitZone), BoarVisualBase.scale_for_weight, Heightmap.


func test_hunt_result_defaults_and_dict() -> void:
	var r: HuntResult = HuntResult.new()
	eq(r.outcome, HuntResult.Outcome.ABANDONED, "padrao ABANDONED (nunca vitoria por engano)")
	ok(not r.is_victory(), "padrao nao e vitoria")
	eq(r.total_money, 0, "total padrao 0")
	r.outcome = HuntResult.Outcome.VICTORY
	ok(r.is_victory(), "VICTORY")
	var k: KillInfo = KillInfo.new()
	k.boar_id = 3
	k.type_id = Ids.SOW
	k.reward_money = 120
	r.kills.append(k)
	var d: Dictionary = r.to_dict()
	eq(d["outcome"], "VICTORY", "outcome como texto")
	eq((d["kills"] as Array).size(), 1, "kills no dict")
	eq(d["kills"][0]["type_id"], "sow", "tipo no dict")
	var json_text: String = JSON.stringify(d)
	ok(json_text != "" and JSON.parse_string(json_text) is Dictionary, "to_dict serializa em JSON")
	var outcomes: PackedStringArray = PackedStringArray(HuntResult.Outcome.keys())
	eq(outcomes, PackedStringArray(["VICTORY", "DEFEAT_CROP", "DEFEAT_DEATH", "ABANDONED", "DISCONNECTED"]), "enum Outcome")
	eq(HuntResult.Outcome.VICTORY, 0, "VICTORY continua 0")
	eq(HuntResult.Outcome.ABANDONED, 3, "ABANDONED continua 3")
	eq(HuntResult.Outcome.DISCONNECTED, 4, "DISCONNECTED e o quinto valor, no fim")
	var dc: HuntResult = HuntResult.new()
	dc.outcome = HuntResult.Outcome.DISCONNECTED
	ok(not dc.is_victory(), "DISCONNECTED nao e vitoria")
	eq(dc.to_dict()["outcome"], "DISCONNECTED", "DISCONNECTED no dict")


func test_hunt_result_coop_defaults() -> void:
	var r: HuntResult = HuntResult.new()
	eq(r.counts_for_progression, true, "conta para progressao por padrao (solo)")
	eq(r.player_count, 1, "player_count padrao 1")
	eq(r.team_kills, 0, "team_kills padrao 0")
	eq(r.scoreboard.size(), 0, "scoreboard vazio no solo")
	ok(r.scoreboard is Array, "scoreboard e Array")
	var other: HuntResult = HuntResult.new()
	other.scoreboard.append({"slot": 1, "name": "A", "kills": 2, "money": 10})
	eq(r.scoreboard.size(), 0, "scoreboard nao e compartilhado entre instancias")


func test_hunt_request_coop_defaults() -> void:
	eq(HuntRequest.new().player_count, 1, "player_count padrao 1")
	eq(HuntRequest.make_debug(&"mato_grosso", 0).player_count, 1, "make_debug e solo")


func test_hit_info_defaults() -> void:
	var h: HitInfo = HitInfo.new()
	eq(h.target_id, -1, "target_id padrao -1")
	eq(h.zone, &"", "zona vazia")
	eq(h.damage, 0.0, "dano 0")
	eq(h.shooter_slot, 0, "shooter_slot padrao 0 (anfitriao/solo)")


func test_kill_info_defaults() -> void:
	var k: KillInfo = KillInfo.new()
	eq(k.killer_slot, 0, "killer_slot padrao 0 (anfitriao/solo)")


func test_scene_paths_coop() -> void:
	eq(ScenePaths.LOBBY, "res://src/ui/lobby/lobby.tscn", "LOBBY")
	eq(ScenePaths.REMOTE_HUNTER, "res://src/player/remote_hunter.tscn", "REMOTE_HUNTER")


func test_player_base_solo_virtuals() -> void:
	var p: PlayerBase = PlayerBase.new()
	track(p)
	eq(p.slot, 0, "slot padrao 0")
	ok(p.is_local(), "is_local verdadeiro")
	ok(p.is_present(), "is_present verdadeiro")
	eq(p.get_display_name(), "", "nome vazio")
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	p.net_write_state(out)   # base is a no-op: concrete classes write exactly HUNTER_STATE_BYTES
	p.net_apply_state(out)
	p.setup_remote(1, "x", &"", null)
	eq(p.slot, 0, "setup_remote da base nao mexe no slot")


func test_hunt_world_solo_virtuals() -> void:
	var w: HuntWorld = HuntWorld.new()
	track(w)
	eq(w.get_local_slot(), 0, "slot local 0")
	eq(w.get_hunters().size(), 0, "sem jogador: lista vazia")
	eq(w.get_hunter(0), null, "sem jogador: get_hunter nulo")
	var out: StreamPeerBuffer = StreamPeerBuffer.new()
	w.net_write_snapshot(out)
	w.net_take_events(out)
	w.net_take_claims(out)
	eq(out.get_size(), 0, "ganchos de rede da base nao escrevem nada")
	w.net_apply_snapshot(out)
	w.net_apply_event(NetCodec.EV_MESSAGE, out, 0)
	w.net_apply_claim(1, NetCodec.C_SHOT, out, 0)
	w.net_peer_left(1)
	w.net_connection_lost()
	ok(not w.is_hunt_over(), "ganchos de rede da base nao encerram a caçada")


func test_hunter_visual_fallback() -> void:
	for slot: int in [0, 1, 2, 3, 4, -1, 7]:
		var v: HunterVisualBase = HunterVisualBase.create_fallback()
		v.setup(slot, &"carbine_22")
		track(v)
		ok(v.get_muzzle() != null, "Muzzle no slot %d" % slot)
		ok(v.get_name_anchor() != null, "NameAnchor no slot %d" % slot)
		v.play_death()
		v.play_death(true)
		v.set_weapon(&"")
	eq(HunterVisualBase.slot_color(0), HunterVisualBase.SLOT_COLORS[0], "cor do slot 0")
	eq(HunterVisualBase.slot_color(4), HunterVisualBase.SLOT_COLORS[0], "slot 4 volta ao 0")
	eq(HunterVisualBase.slot_color(-1), HunterVisualBase.SLOT_COLORS[3], "slot -1 nao sai do vetor")
	var seen: Dictionary = {}
	for c: Color in HunterVisualBase.SLOT_COLORS:
		seen[c.to_html()] = true
	eq(seen.size(), HunterVisualBase.SLOT_COUNT, "cores dos slots distintas")


func test_hunt_request() -> void:
	var r: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 3)
	eq(r.map_id, &"mato_grosso", "map_id")
	eq(r.contract_index, 3, "contrato")
	eq(r.weapon_ids, [&"carbine_22"] as Array[StringName], "arma padrao")
	eq(r.dog_id, &"", "sem cao")
	eq(r.rng_seed, 0, "seed 0 = aleatorio")
	r.item_ids = [Ids.I_MEDKIT]
	r.item_counts = {Ids.I_MEDKIT: 2}
	ok(r.has_item(Ids.I_MEDKIT), "has_item")
	ok(not r.has_item(Ids.I_CORN_BAIT), "has_item falso")
	eq(r.get_item_count(Ids.I_MEDKIT), 2, "contagem")
	eq(r.get_item_count(Ids.I_CORN_BAIT), 0, "contagem de ausente")


func test_hit_zone_forwards_and_stamps_hit() -> void:
	var zone: HitZone = HitZone.new()
	zone.zone = Ids.ZONE_VITAL
	zone.target_id = 42
	track(zone)
	var rec: Dictionary = record_signal(zone.hit_received)
	var h: HitInfo = HitInfo.new()
	zone.receive_hit(h)
	eq(rec["count"], 1, "hit_received emitido")
	eq(h.zone, Ids.ZONE_VITAL, "zona carimbada")
	eq(h.target_id, 42, "alvo carimbado")
	eq(zone.collision_layer, Layers.BOAR_HITZONE, "camada BOAR_HITZONE")
	eq(zone.collision_mask, 0, "sem mascara")
	zone.disable()
	eq(zone.collision_layer, 0, "desabilitada: sem camada")


func test_scale_for_weight() -> void:
	near(BoarVisualBase.scale_for_weight(100.0), 1.0, 0.0001, "100 kg = escala 1")
	near(BoarVisualBase.scale_for_weight(800.0), 2.0, 0.0001, "800 kg = escala 2 (raiz cubica)")
	near(BoarVisualBase.scale_for_weight(12.5), 0.5, 0.0001, "12,5 kg = 0,5")
	var last: float = 0.0
	for kg: float in [25.0, 45.0, 60.0, 110.0, 160.0, 260.0]:
		var s: float = BoarVisualBase.scale_for_weight(kg)
		ok(s > last, "monotonica em %s kg" % kg)
		last = s
	ok(BoarVisualBase.scale_for_weight(0.0) > 0.0, "peso 0 nunca da escala 0")
	ok(BoarVisualBase.scale_for_weight(-10.0) > 0.0, "peso negativo nunca da escala <= 0")
	ok(is_finite(BoarVisualBase.scale_for_weight(1.0e12)), "peso gigante finito")


func test_boar_visual_zones_table() -> void:
	for zone: StringName in [Ids.ZONE_HEAD, Ids.ZONE_VITAL, Ids.ZONE_BODY, Ids.ZONE_REAR]:
		ok(BoarVisualBase.HIT_ZONES.has(zone), "HIT_ZONES tem %s" % zone)
		var spec: Array = BoarVisualBase.HIT_ZONES[zone]
		ok(spec.size() == 2 and (spec[1] as Vector3).x > 0.0 and (spec[1] as Vector3).y > 0.0 and (spec[1] as Vector3).z > 0.0, "caixa de %s com tamanho positivo" % zone)


func test_layers() -> void:
	eq(Layers.MASK_WEAPON_RAY, Layers.TERRAIN | Layers.STATIC | Layers.BOAR_HITZONE, "raio da arma")
	eq(Layers.MASK_LINE_OF_SIGHT & Layers.BOAR_HITZONE, 0, "linha de visao nao enxerga hitzone")
	eq(Layers.MASK_PLAYER_BODY & Layers.PLAYER, 0, "corpo do jogador nao colide com ele mesmo")


# --- Heightmap ---

func test_heightmap_deterministic_by_seed() -> void:
	var a: Heightmap = Heightmap.new(256.0, 65, 777, 6.0)
	var b: Heightmap = Heightmap.new(256.0, 65, 777, 6.0)
	var c: Heightmap = Heightmap.new(256.0, 65, 778, 6.0)
	var same: bool = true
	var differs: bool = false
	for j: int in 65:
		for i: int in 65:
			if a.get_grid(i, j) != b.get_grid(i, j):
				same = false
			if a.get_grid(i, j) != c.get_grid(i, j):
				differs = true
	ok(same, "mesma seed, mesmo terreno")
	ok(differs, "seed diferente, terreno diferente")


func test_heightmap_range_and_grid_points() -> void:
	var hm: Heightmap = Heightmap.new(256.0, 129, 12345, 6.0)
	var lo: float = INF
	var hi: float = -INF
	for j: int in 129:
		for i: int in 129:
			var g: float = hm.get_grid(i, j)
			lo = minf(lo, g)
			hi = maxf(hi, g)
	ok(lo >= -0.001 and hi <= 6.001, "alturas em [0, amplitude] (%.2f..%.2f)" % [lo, hi])
	for p: Vector2i in [Vector2i(0, 0), Vector2i(10, 20), Vector2i(64, 64), Vector2i(100, 5)]:
		near(hm.get_height(hm.grid_x(p.x), hm.grid_x(p.y)), hm.get_grid(p.x, p.y), 0.0001, "get_height no ponto de grade %s" % str(p))


func test_heightmap_bilinear() -> void:
	var hm: Heightmap = Heightmap.new(256.0, 129, 4, 6.0)
	var i: int = 30
	var j: int = 41
	var cx: float = (hm.grid_x(i) + hm.grid_x(i + 1)) * 0.5
	var cz: float = (hm.grid_x(j) + hm.grid_x(j + 1)) * 0.5
	var avg: float = (hm.get_grid(i, j) + hm.get_grid(i + 1, j) + hm.get_grid(i, j + 1) + hm.get_grid(i + 1, j + 1)) * 0.25
	near(hm.get_height(cx, cz), avg, 0.0001, "centro da celula = media dos 4 cantos")
	var mid_x: float = (hm.grid_x(i) + hm.grid_x(i + 1)) * 0.5
	near(hm.get_height(mid_x, hm.grid_x(j)), (hm.get_grid(i, j) + hm.get_grid(i + 1, j)) * 0.5, 0.0001, "meio da aresta X")


func test_heightmap_outside_and_nan_are_safe() -> void:
	var hm: Heightmap = Heightmap.new(256.0, 65, 9, 6.0)
	var far: float = hm.get_height(1.0e6, -1.0e6)
	ok(is_finite(far) and far >= -0.001 and far <= 6.001, "fora do mapa limita na borda (%s)" % far)
	near(hm.get_height(-128.0, -128.0), hm.get_grid(0, 0), 0.0001, "canto minimo")
	near(hm.get_height(128.0, 128.0), hm.get_grid(64, 64), 0.01, "canto maximo")
	var n: Vector3 = hm.get_normal(10.0, 10.0)
	near(n.length(), 1.0, 0.001, "normal unitaria")
	ok(n.y > 0.0, "normal aponta para cima")
	ok(is_finite(hm.get_normal(1.0e6, 1.0e6).length()), "normal fora do mapa finita")


func test_heightmap_flatten_and_bowl() -> void:
	var hm: Heightmap = Heightmap.new(256.0, 129, 5, 6.0)
	var rect: Rect2 = Rect2(-20.0, -20.0, 40.0, 40.0)
	var level: float = hm.flatten_rect(rect, 6.0)
	for p: Vector2 in [Vector2(0, 0), Vector2(10, -10), Vector2(-15, 15)]:
		near(hm.get_height(p.x, p.y), level, 0.001, "plano em %s" % str(p))
	var before: float = hm.get_height(60.0, 60.0)
	hm.dig_bowl(Vector2(60.0, 60.0), 10.0, 1.5, 4.0)
	ok(hm.get_height(60.0, 60.0) < before - 0.5, "bacia mais funda no centro")
