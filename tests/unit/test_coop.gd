extends "res://tests/lib/test_case.gd"
## BoarSpawner.scale_groups (docs/multiplayer.md section 6.10) with the real data of data/maps.json and
## data/game.json: more boars for more hunters. Pure function, no scene needed.

const MAP: StringName = &"mato_grosso"
const WIRE_ID_LIMIT: int = 255   # boar ids travel as u8 (NetCodec / HuntHostSync.MAX_WIRE_ID)


func _groups(index: int) -> Array:
	return Data.get_contract(MAP, index)["groups"]


func _coop() -> Dictionary:
	return Data.get_game()["coop"]


func _total(groups: Array) -> int:
	var n: int = 0
	for g: Variant in groups:
		n += ((g as Dictionary).get("members", []) as Array).size()
	return n


func _max_delay(groups: Array) -> float:
	var d: float = 0.0
	for g: Variant in groups:
		d = maxf(d, float((g as Dictionary).get("delay_s", 0.0)))
	return d


func _has_alpha(members: Array) -> bool:
	return members.has("alpha") or members.has(&"alpha")


# --- the numbers of the contract ---

func test_contract_0_totals_by_player_count() -> void:
	var g: Array = _groups(0)
	eq(_total(g), 9, "contrato 0 tem 9 javalis")
	var want: Array[int] = [9, 14, 18, 23]
	for n: int in 4:
		eq(_total(BoarSpawner.scale_groups(g, n + 1, _coop())), want[n], "contrato 0 com %d jogador(es)" % (n + 1))


func test_contract_1_totals() -> void:
	var g: Array = _groups(1)
	eq(_total(g), 13, "contrato 1 tem 13 javalis")
	eq(_total(BoarSpawner.scale_groups(g, 1, _coop())), 13, "1 jogador")
	eq(_total(BoarSpawner.scale_groups(g, 2, _coop())), 20, "2 jogadores")
	eq(_total(BoarSpawner.scale_groups(g, 4, _coop())), 33, "4 jogadores")


func test_every_contract_hits_the_rounded_target_and_fits_the_wire() -> void:
	var mults: Array = _coop()["boar_count_mult_by_players"]
	var checked: int = 0
	for map_id: StringName in Data.get_map_ids():
		for index: int in Data.get_contract_count(map_id):
			var g: Array = Data.get_contract(map_id, index)["groups"]
			var base: int = _total(g)
			for n: int in range(1, 5):
				var out: Array = BoarSpawner.scale_groups(g, n, _coop())
				var want: int = maxi(base, roundi(float(base) * float(mults[n - 1])))
				eq(_total(out), want, "%s contrato %d com %d jogadores" % [map_id, index, n])
				checked += 1
			ok(_total(BoarSpawner.scale_groups(g, 4, _coop())) <= WIRE_ID_LIMIT,
				"%s contrato %d com 4 jogadores cabe em 255 javalis" % [map_id, index])
	ok(checked >= 20, "percorreu todos os contratos (%d)" % checked)


# --- structure of the result ---

func test_solo_is_an_equal_deep_copy() -> void:
	var g: Array = _groups(0)
	var out: Array = BoarSpawner.scale_groups(g, 1, _coop())
	eq(out, g, "1 jogador: mesmo conteudo")
	((out[0] as Dictionary)["members"] as Array).append("boar")
	((out[0] as Dictionary)["members"] as Array).append("boar")
	eq(_total(_groups(0)), 9, "alterar a copia nao altera os dados do contrato")


func test_input_is_never_mutated() -> void:
	for index: int in Data.get_contract_count(MAP):
		var g: Array = _groups(index)
		var snapshot: Array = g.duplicate(true)
		BoarSpawner.scale_groups(g, 4, _coop())
		eq(g, snapshot, "contrato %d intacto depois de escalar" % index)


func test_original_groups_come_first_unchanged() -> void:
	var g: Array = _groups(0)
	var out: Array = BoarSpawner.scale_groups(g, 4, _coop())
	ok(out.size() > g.size(), "ganhou grupos novos")
	for i: int in g.size():
		eq(out[i], g[i], "grupo original %d preservado na mesma posicao" % i)


func test_clones_follow_the_rules() -> void:
	var g: Array = _groups(0)
	var coop: Dictionary = _coop()
	var out: Array = BoarSpawner.scale_groups(g, 4, coop)
	var max_delay: float = _max_delay(g)
	var extra: float = float(coop["extra_group_delay_s"])
	var last_delay: float = -1.0
	for i: int in range(g.size(), out.size()):
		var clone: Dictionary = out[i]
		var order: int = i - g.size()
		var members: Array = clone["members"]
		ok(not members.is_empty(), "clone %d tem membros" % order)
		near(float(clone["delay_s"]), max_delay + extra * float(order + 1), 0.001, "atraso do clone %d" % order)
		ok(float(clone["delay_s"]) > last_delay, "atrasos crescem (clone %d)" % order)
		last_delay = float(clone["delay_s"])
		# Each clone is a prefix of one of the source groups: the leader (index 0) is never the one dropped.
		var is_prefix: bool = false
		for src: Variant in g:
			var sm: Array = (src as Dictionary)["members"]
			if members.size() <= sm.size() and sm.slice(0, members.size()) == members:
				is_prefix = true
		ok(is_prefix, "clone %d e prefixo de um grupo de origem (lider preservado)" % order)


func test_alpha_group_is_never_cloned() -> void:
	var g: Array = _groups(4)   # the alpha leads group 0
	var alphas_before: int = 0
	for grp: Variant in g:
		if _has_alpha((grp as Dictionary)["members"]):
			alphas_before += 1
	eq(alphas_before, 1, "pre-condicao: o contrato 4 tem um grupo com alfa")
	for n: int in range(2, 5):
		var alphas: int = 0
		for grp: Variant in BoarSpawner.scale_groups(g, n, _coop()):
			for m: Variant in (grp as Dictionary)["members"]:
				if String(m) == "alpha":
					alphas += 1
		eq(alphas, 1, "so um alfa com %d jogadores" % n)


# --- edge cases ---

func test_player_count_out_of_range() -> void:
	var g: Array = _groups(0)
	var coop: Dictionary = _coop()
	eq(_total(BoarSpawner.scale_groups(g, 0, coop)), 9, "0 jogadores = solo")
	eq(_total(BoarSpawner.scale_groups(g, -3, coop)), 9, "negativo = solo")
	var four: int = _total(BoarSpawner.scale_groups(g, 4, coop))
	eq(_total(BoarSpawner.scale_groups(g, 5, coop)), four, "5 jogadores usa o ultimo multiplicador")
	eq(_total(BoarSpawner.scale_groups(g, 1000, coop)), four, "1000 jogadores usa o ultimo multiplicador")


func test_degenerate_inputs_terminate() -> void:
	var coop: Dictionary = _coop()
	eq(BoarSpawner.scale_groups([], 4, coop), [], "sem grupos")
	eq(_total(BoarSpawner.scale_groups(_groups(0), 4, {})), 9, "coop vazio: sem crescimento")
	eq(_total(BoarSpawner.scale_groups(_groups(0), 4, {"boar_count_mult_by_players": []})), 9, "lista de multiplicadores vazia")
	var shrink: Dictionary = {"boar_count_mult_by_players": [1.0, 0.5, 0.5, 0.5], "extra_group_delay_s": 5.0}
	eq(_total(BoarSpawner.scale_groups(_groups(0), 4, shrink)), 9, "multiplicador < 1 nunca remove javalis")
	var only_alpha: Array = [{"members": ["alpha"], "spawn_zone": 0, "delay_s": 0.0}]
	eq(_total(BoarSpawner.scale_groups(only_alpha, 4, coop)), 1, "so alfa: nada para clonar e sem laco infinito")
	var only_empty: Array = [{"members": [], "spawn_zone": 0, "delay_s": 0.0}]
	eq(_total(BoarSpawner.scale_groups(only_empty, 4, coop)), 0, "grupo vazio: sem laco infinito")
	var big: Dictionary = {"boar_count_mult_by_players": [1.0, 1.0, 1.0, 40.0], "extra_group_delay_s": 1.0}
	eq(_total(BoarSpawner.scale_groups(_groups(0), 4, big)), 360, "multiplicador grande termina e acerta o alvo")
	var no_delay: Array = [{"members": ["boar", "piglet"]}]
	var out: Array = BoarSpawner.scale_groups(no_delay, 2, coop)
	eq(_total(out), 3, "grupo sem delay_s nem spawn_zone ainda escala")
	eq(int((out[1] as Dictionary)["spawn_zone"]), 1, "clone sem spawn_zone parte de 0 + 1")
