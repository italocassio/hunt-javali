extends "res://tests/lib/test_case.gd"
## Horde mode, pure parts (docs/horda.md sections 3, 5.2 and 10): HordeDirector.plan_waves with the real
## data/horde.json, the cut at 255 boar ids with inflated data, and the horde economy. No scene needed.

const WIRE_ID_LIMIT: int = 255   # NetCodec.MAX_BOARS_PER_HUNT: boar ids travel as u8
const SOLO_WAVE_TOTALS: Array[int] = [4, 6, 8, 10, 12, 14, 16, 15]
const FOUR_PLAYER_WAVE_TOTALS: Array[int] = [9, 13, 18, 22, 26, 31, 35, 33]


func _horde() -> Dictionary:
	return Data.get_horde().duplicate(true)


func _wave_total(wave: Array) -> int:
	var n: int = 0
	for g: Variant in wave:
		n += ((g as Dictionary)["members"] as Array).size()
	return n


func _plan_total(plan: Array) -> int:
	var n: int = 0
	for wave: Variant in plan:
		n += _wave_total(wave as Array)
	return n


func _has_alpha(wave: Array) -> int:
	var n: int = 0
	for g: Variant in wave:
		for m: Variant in (g as Dictionary)["members"]:
			if str(m) == "alpha":
				n += 1
	return n


# --- data sanity (the seed is part of the contract) ---

func test_seed_is_loaded_and_valid() -> void:
	var h: Dictionary = Data.get_horde()
	ok(not h.is_empty(), "Data.get_horde() nao vazio")
	eq(Data.get_load_errors().size(), 0, "sem erros de dados: %s" % str(Data.get_load_errors()))
	eq(str(h.get("map_id", "")), "mato_grosso", "map_id")
	eq(str(h.get("objective_prop_id", "")), "barn", "objective_prop_id")
	eq((h.get("waves", []) as Array).size(), 8, "8 ondas no seed")
	eq((h.get("player_count_mult", []) as Array).size(), int(Data.get_net().get("max_players", 0)), "player_count_mult tem net.max_players entradas")
	var kill_mult: float = float(h.get("kill_reward_mult", 0.0))
	ok(kill_mult > 0.0 and kill_mult < 1.0, "kill_reward_mult em (0, 1)")
	ok(float(h.get("eat_ring_m", 0.0)) > 0.0, "eat_ring_m > 0")
	ok(int(h.get("max_carcasses", -1)) >= 0, "max_carcasses >= 0")


# --- plan_waves ---

func test_plan_waves_totals_by_player_count() -> void:
	var h: Dictionary = _horde()
	eq(_plan_total(HordeDirector.plan_waves(h, 1)), 85, "1 jogador: 85 javalis")
	eq(_plan_total(HordeDirector.plan_waves(h, 2)), 119, "2 jogadores: 119 javalis")
	eq(_plan_total(HordeDirector.plan_waves(h, 3)), 153, "3 jogadores: 153 javalis")
	eq(_plan_total(HordeDirector.plan_waves(h, 4)), 187, "4 jogadores: 187 javalis")


func test_plan_waves_totals_by_wave() -> void:
	var h: Dictionary = _horde()
	for pair: Array in [[1, SOLO_WAVE_TOTALS], [4, FOUR_PLAYER_WAVE_TOTALS]]:
		var plan: Array = HordeDirector.plan_waves(h, int(pair[0]))
		eq(plan.size(), 8, "%d jogador(es): 8 ondas" % int(pair[0]))
		for i: int in plan.size():
			eq(_wave_total(plan[i]), int((pair[1] as Array)[i]), "%d jogador(es), onda %d" % [int(pair[0]), i + 1])
	# Each wave is no smaller than the previous one up to the last (the last has an alpha and may be smaller).
	var solo: Array = HordeDirector.plan_waves(h, 1)
	for i: int in range(1, 7):
		ok(_wave_total(solo[i]) >= _wave_total(solo[i - 1]), "onda %d >= onda %d (solo)" % [i + 1, i])


func test_plan_waves_marks_every_group_with_its_wave() -> void:
	var h: Dictionary = _horde()
	for players: int in [1, 2, 3, 4]:
		var plan: Array = HordeDirector.plan_waves(h, players)
		for i: int in plan.size():
			var wave: Array = plan[i]
			ok(wave.size() >= 1, "onda %d com ao menos 1 grupo (%dj)" % [i + 1, players])
			for g: Variant in wave:
				var def: Dictionary = g as Dictionary
				ok(def.has("wave"), "grupo da onda %d tem a chave wave (%dj)" % [i + 1, players])
				eq(int(def.get("wave", -1)), i, "grupo na onda %d marcado com o indice 0-based (%dj)" % [i + 1, players])
				var members: Array = def["members"]
				# scale_groups clones trim the last clone to fit the target (resize), so 2 members is possible; same as the contract
				ok(members.size() >= 1 and members.size() <= 6, "grupo de %d membros (1 a 6)" % members.size())
				ok(float(def.get("delay_s", -1.0)) >= 0.0, "delay_s >= 0")
				ok(int(def.get("spawn_zone", -1)) >= 0, "spawn_zone >= 0")


func test_plan_waves_never_exceeds_wire_limit_and_last_wave_has_one_alpha() -> void:
	var h: Dictionary = _horde()
	for players: int in [1, 2, 3, 4]:
		var plan: Array = HordeDirector.plan_waves(h, players)
		ok(_plan_total(plan) <= WIRE_ID_LIMIT, "%d jogador(es): %d <= 255" % [players, _plan_total(plan)])
		eq(_has_alpha(plan[plan.size() - 1]), 1, "ultima onda com exatamente 1 alfa (%dj; R5: o alfa nao escala)" % players)
		for i: int in plan.size() - 1:
			eq(_has_alpha(plan[i]), 0, "onda %d sem alfa (%dj)" % [i + 1, players])


func test_plan_waves_does_not_mutate_the_input() -> void:
	var h: Dictionary = _horde()
	var snapshot: String = JSON.stringify(h)
	HordeDirector.plan_waves(h, 4)
	HordeDirector.plan_waves(h, 1)
	eq(JSON.stringify(h), snapshot, "plan_waves nao altera o dicionario de entrada")
	eq(JSON.stringify(Data.get_horde().duplicate(true)), JSON.stringify(Data.get_horde()), "Data.get_horde intacto")
	var a: Array = HordeDirector.plan_waves(h, 2)
	var b: Array = HordeDirector.plan_waves(h, 2)
	eq(JSON.stringify(a), JSON.stringify(b), "funcao pura: mesma entrada, mesmo plano")
	# the two plans must not share group dictionaries
	((a[0] as Array)[0] as Dictionary)["members"].append("piglet")
	eq(JSON.stringify(HordeDirector.plan_waves(h, 2)), JSON.stringify(b), "planos independentes")


func test_plan_waves_odd_player_counts_are_safe() -> void:
	var h: Dictionary = _horde()
	eq(_plan_total(HordeDirector.plan_waves(h, 0)), 85, "0 jogadores = solo")
	eq(_plan_total(HordeDirector.plan_waves(h, -3)), 85, "negativo = solo")
	eq(_plan_total(HordeDirector.plan_waves(h, 5)), 187, "5 jogadores satura no multiplicador do ultimo")
	eq(_plan_total(HordeDirector.plan_waves(h, 99)), 187, "99 jogadores satura")
	eq(HordeDirector.plan_waves({}, 1).size(), 0, "dados vazios: plano vazio")
	eq(HordeDirector.plan_waves({"waves": []}, 4).size(), 0, "sem ondas: plano vazio")


func test_plan_waves_scaled_groups_start_after_the_originals() -> void:
	## Clones (more hunters) must not start before the wave's own groups, and zones stay non-negative.
	var h: Dictionary = _horde()
	var solo: Array = HordeDirector.plan_waves(h, 1)
	var four: Array = HordeDirector.plan_waves(h, 4)
	for i: int in solo.size():
		var base_groups: int = (solo[i] as Array).size()
		var max_base_delay: float = 0.0
		for g: Variant in solo[i]:
			max_base_delay = maxf(max_base_delay, float((g as Dictionary)["delay_s"]))
		var wave: Array = four[i]
		ok(wave.size() >= base_groups, "onda %d: 4 jogadores nao tem menos grupos" % (i + 1))
		for k: int in wave.size():
			if k < base_groups:
				eq(float((wave[k] as Dictionary)["delay_s"]), float((solo[i][k] as Dictionary)["delay_s"]), "onda %d grupo %d: original preservado" % [i + 1, k])
			else:
				ok(float((wave[k] as Dictionary)["delay_s"]) >= max_base_delay, "onda %d: clone %d nao nasce antes dos originais" % [i + 1, k])


# --- the cut at 255 ids (D3) with inflated data ---

func _inflated(copies: int) -> Dictionary:
	var h: Dictionary = _horde()
	var waves: Array = h["waves"]
	var out: Array = []
	for c: int in copies:
		out.append_array(waves.duplicate(true))
	h["waves"] = out
	return h


func test_plan_waves_trims_inflated_data_to_the_limit() -> void:
	expect_errors()   # the cut reports a push_error by contract
	for players: int in [1, 4]:
		var h: Dictionary = _inflated(4)   # 340 boars solo, 748 with four
		var mark: int = error_mark()
		var plan: Array = HordeDirector.plan_waves(h, players)
		ok(errors_since(mark).size() >= 1, "o corte avisa com push_error (%dj)" % players)
		eq(_plan_total(plan), WIRE_ID_LIMIT, "plano cortado em exatamente 255 (%dj)" % players)
		ok(plan.size() >= 1, "plano nao vazio apos o corte")
		for i: int in plan.size():
			var wave: Array = plan[i]
			ok(wave.size() >= 1, "onda %d nao ficou vazia" % (i + 1))
			for g: Variant in wave:
				var def: Dictionary = g as Dictionary
				ok((def["members"] as Array).size() >= 1, "nenhum grupo vazio sobrevive")
				eq(int(def["wave"]), i, "indice de onda continua consistente depois do corte (onda %d)" % (i + 1))
		# the beginning of the plan is untouched: trimming only eats the tail
		var intact: Array = HordeDirector.plan_waves(_horde(), players)
		for i: int in 3:
			eq(JSON.stringify(plan[i]), JSON.stringify(intact[i]), "onda %d do inicio intacta (%dj)" % [i + 1, players])


func test_plan_waves_at_exactly_the_limit_does_not_error() -> void:
	# one wave, 51 groups of 5 members = 255; one more member would cross the wire limit
	var groups: Array = []
	for i: int in 51:
		groups.append({"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": i % 4, "delay_s": float(i)})
	var h: Dictionary = {"waves": [{"groups": groups}], "player_count_mult": [1.0, 1.4, 1.8, 2.2], "extra_group_delay_s": 4.0}
	var mark: int = error_mark()
	var plan: Array = HordeDirector.plan_waves(h, 1)
	eq(errors_since(mark).size(), 0, "255 e permitido, sem erro")
	eq(_plan_total(plan), 255, "255 javalis intactos")
	expect_errors()
	groups.append({"members": ["boar"], "spawn_zone": 0, "delay_s": 60.0})
	var over: Array = HordeDirector.plan_waves(h, 1)
	eq(_plan_total(over), 255, "256 cortado para 255")
	eq(((over[0] as Array).size()), 51, "so o grupo extra foi removido")


func test_plan_waves_trim_eats_the_last_group_member_by_member() -> void:
	expect_errors()
	var groups: Array = []
	for i: int in 52:
		groups.append({"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": float(i)})
	var h: Dictionary = {"waves": [{"groups": groups}], "player_count_mult": [1.0, 1.4, 1.8, 2.2], "extra_group_delay_s": 4.0}
	var plan: Array = HordeDirector.plan_waves(h, 1)   # 260 -> 255: the last group loses its last 5 members -> leaves
	eq(_plan_total(plan), 255, "260 cortado para 255")
	eq((plan[0] as Array).size(), 51, "grupo esvaziado sai do plano")
	groups.clear()
	for i: int in 51:
		groups.append({"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": float(i)})
	groups.append({"members": ["sow", "piglet", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 60.0})
	var plan2: Array = HordeDirector.plan_waves({"waves": [{"groups": groups}], "player_count_mult": [1.0], "extra_group_delay_s": 0.0}, 1)
	eq(_plan_total(plan2), 255, "261 cortado para 255")
	eq((plan2[0] as Array).size(), 51, "ultimo grupo (6 membros) removido por inteiro")
	# a trim that leaves a partial group
	groups.clear()
	for i: int in 50:
		groups.append({"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": float(i)})
	groups.append({"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 60.0})
	var plan3: Array = HordeDirector.plan_waves({"waves": [{"groups": groups}], "player_count_mult": [1.0], "extra_group_delay_s": 0.0}, 1)
	eq(_plan_total(plan3), 255, "256 cortado para 255")
	var last_group: Dictionary = (plan3[0] as Array)[(plan3[0] as Array).size() - 1]
	eq((last_group["members"] as Array).size(), 5, "o ultimo grupo perdeu so o ultimo membro")
	eq(str((last_group["members"] as Array)[0]), "boar", "o lider (primeiro membro) continua")


# --- validation rules of data/horde.json (docs/horda.md 3.1): each broken rule generates an error ---

## A throw-away registry with the real files loaded; `mutate` edits a copy of the horde block and _validate runs again.
func _errors_with(mutate: Callable) -> PackedStringArray:
	var script: GDScript = load("res://src/systems/data_registry.gd") as GDScript
	var reg: Node = script.new()
	reg.call("reload")
	var raw: Dictionary = reg.get("_raw")
	var h: Dictionary = (raw["horde"] as Dictionary).duplicate(true)
	mutate.call(h)
	raw["horde"] = h
	var errs: PackedStringArray = PackedStringArray()
	reg.set("_errors", errs)
	reg.call("_validate")
	var out: PackedStringArray = reg.get("_errors")
	reg.free()
	return out


func _any_contains(errs: PackedStringArray, needle: String) -> bool:
	for e: String in errs:
		if e.contains(needle):
			return true
	return false


func test_validation_accepts_the_seed() -> void:
	var errs: PackedStringArray = _errors_with(func(_h: Dictionary) -> void: pass)
	eq(errs.size(), 0, "o seed nao gera erros: %s" % str(errs))


func test_validation_rejects_each_broken_rule() -> void:
	var cases: Array[Array] = [
		["campo ausente", "lacks field 'eat_ring_m'", func(h: Dictionary) -> void: h.erase("eat_ring_m")],
		["tipo errado", "horde.eat_ring_m has the wrong type", func(h: Dictionary) -> void: h["eat_ring_m"] = "dez"],
		["max_carcasses fracionario", "horde.max_carcasses has the wrong type", func(h: Dictionary) -> void: h["max_carcasses"] = 1.5],
		["mapa inexistente", "is not in maps.json", func(h: Dictionary) -> void: h["map_id"] = "atlantida"],
		["mapa indisponivel", "is not available", func(h: Dictionary) -> void: h["map_id"] = "pantanal"],
		["prop vazio", "objective_prop_id is empty", func(h: Dictionary) -> void: h["objective_prop_id"] = ""],
		["first_wave_delay negativo", "first_wave_delay_s must be >= 0", func(h: Dictionary) -> void: h["first_wave_delay_s"] = -1.0],
		["intermission negativo", "intermission_s must be >= 0", func(h: Dictionary) -> void: h["intermission_s"] = -0.5],
		["barn_drain_mult zero", "barn_drain_mult must be > 0", func(h: Dictionary) -> void: h["barn_drain_mult"] = 0.0],
		["eat_ring zero", "eat_ring_m must be > 0", func(h: Dictionary) -> void: h["eat_ring_m"] = 0.0],
		["velocidade acima de 1,5", "to_barn_speed_frac must be in (0, 1.5]", func(h: Dictionary) -> void: h["to_barn_speed_frac"] = 1.6],
		["velocidade zero", "to_barn_speed_frac must be in (0, 1.5]", func(h: Dictionary) -> void: h["to_barn_speed_frac"] = 0.0],
		["max_carcasses negativo", "max_carcasses must be >= 0", func(h: Dictionary) -> void: h["max_carcasses"] = -1],
		["extra_group_delay negativo", "extra_group_delay_s must be >= 0", func(h: Dictionary) -> void: h["extra_group_delay_s"] = -2.0],
		["kill_reward_mult 1,0", "kill_reward_mult must be in (0, 1)", func(h: Dictionary) -> void: h["kill_reward_mult"] = 1.0],
		["kill_reward_mult 0", "kill_reward_mult must be in (0, 1)", func(h: Dictionary) -> void: h["kill_reward_mult"] = 0.0],
		["bonus negativo", "victory_bonus_money must be >= 0", func(h: Dictionary) -> void: h["victory_bonus_money"] = -1],
		["player_count_mult curto", "player_count_mult needs 4 entries", func(h: Dictionary) -> void: h["player_count_mult"] = [1.0, 1.4]],
		["player_count_mult abaixo de 1", "entries must be >= 1.0", func(h: Dictionary) -> void: h["player_count_mult"] = [0.9, 1.4, 1.8, 2.2]],
		["player_count_mult decrescente", "must not decrease", func(h: Dictionary) -> void: h["player_count_mult"] = [1.0, 1.8, 1.4, 2.2]],
		["sem ondas", "must have at least one wave", func(h: Dictionary) -> void: h["waves"] = []],
		["onda sem grupos", "wave 2 has no groups", func(h: Dictionary) -> void: h["waves"][1]["groups"] = []],
		["grupo de 2 membros", "wave 1 has a group of 2 members", func(h: Dictionary) -> void: h["waves"][0]["groups"][0]["members"] = ["sow", "piglet"]],
		["grupo de 7 membros", "group of 7 members", func(h: Dictionary) -> void: h["waves"][0]["groups"][0]["members"] = ["sow", "piglet", "piglet", "piglet", "piglet", "piglet", "piglet"]],
		["tipo desconhecido", "unknown boar type 'dragao'", func(h: Dictionary) -> void: h["waves"][0]["groups"][0]["members"] = ["dragao", "piglet", "piglet"]],
		["spawn_zone negativa", "invalid spawn_zone", func(h: Dictionary) -> void: h["waves"][0]["groups"][0]["spawn_zone"] = -1],
		["spawn_zone ausente", "invalid spawn_zone", func(h: Dictionary) -> void: h["waves"][0]["groups"][0].erase("spawn_zone")],
		["delay negativo", "invalid delay_s", func(h: Dictionary) -> void: h["waves"][0]["groups"][0]["delay_s"] = -1.0],
		["ultima onda sem alfa", "last horde wave must contain an alpha", func(h: Dictionary) -> void: h["waves"][7]["groups"][0]["members"] = ["boar", "boar", "boar"]],
		["orcamento de ids", "boar ids, above 255", func(h: Dictionary) -> void:
			var extra: Array = []
			for i: int in 40:
				extra.append({"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0})
			h["waves"][0]["groups"].append_array(extra)],
	]
	for c: Array in cases:
		var errs: PackedStringArray = _errors_with(c[2] as Callable)
		ok(errs.size() >= 1, "regra quebrada gera erro: %s" % c[0])
		ok(_any_contains(errs, str(c[1])), "regra '%s': esperava '%s', veio %s" % [c[0], c[1], str(errs)])
