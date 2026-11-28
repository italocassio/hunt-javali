extends "res://tests/lib/test_case.gd"
## Horde mode, pure parts (docs/horda.md sections 3, 5.2 and 10): HordeDirector.plan_waves with the real
## data/horde.json, the cut at 255 boar ids with inflated data, and the horde economy. No scene needed.

const WIRE_ID_LIMIT: int = 255   # NetCodec.MAX_BOARS_PER_HUNT: boar ids travel as u8
const SOLO_WAVE_TOTALS: Array[int] = [6, 9, 12, 15, 18, 21, 24, 23]
const FOUR_PLAYER_WAVE_TOTALS: Array[int] = [11, 17, 23, 29, 34, 40, 46, 44]


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
	eq(_plan_total(HordeDirector.plan_waves(h, 1)), 128, "1 jogador: 128 javalis")
	eq(_plan_total(HordeDirector.plan_waves(h, 2)), 167, "2 jogadores: 167 javalis")
	eq(_plan_total(HordeDirector.plan_waves(h, 3)), 205, "3 jogadores: 205 javalis")
	eq(_plan_total(HordeDirector.plan_waves(h, 4)), 244, "4 jogadores: 244 javalis")


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
	eq(_plan_total(HordeDirector.plan_waves(h, 0)), 128, "0 jogadores = solo")
	eq(_plan_total(HordeDirector.plan_waves(h, -3)), 128, "negativo = solo")
	eq(_plan_total(HordeDirector.plan_waves(h, 5)), 244, "5 jogadores satura no multiplicador do ultimo")
	eq(_plan_total(HordeDirector.plan_waves(h, 99)), 244, "99 jogadores satura")
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



# --- horde 2.0 (docs/plano_horda_nivel2.md): plan_waves by level, validation of the v2 rules, HordeRoute ---

func test_plan_waves_by_level_respects_the_wire_limit() -> void:
	## plan_waves takes the RESOLVED level (Data.get_horde_level), so every level stays <= 255 ids with 1..4 hunters.
	## The levels have DIFFERENT wave counts (docs/plano_horda_boss.md 3): level 1 = the top-level 8 waves (base 128),
	## level 2 = its own 10 waves with the boss in the last one (base 129).
	var expected_waves: Array[int] = [8, 10]
	var expected_base: Array[int] = [128, 129]
	var expected_level_1: Array[int] = [128, 167, 205, 244]
	eq(Data.get_horde_level_count(), expected_waves.size(), "dois niveis no seed")
	for lv: int in range(1, Data.get_horde_level_count() + 1):
		var cfg: Dictionary = Data.get_horde_level(lv)
		ok(not cfg.is_empty(), "nivel %d resolvido" % lv)
		eq(_plan_total(HordeDirector.plan_waves(cfg, 1)), expected_base[lv - 1], "nivel %d: total base %d" % [lv, expected_base[lv - 1]])
		for players: int in [1, 2, 3, 4]:
			var plan: Array = HordeDirector.plan_waves(cfg, players)
			var total: int = _plan_total(plan)
			eq(plan.size(), expected_waves[lv - 1], "nivel %d, %dj: %d ondas" % [lv, players, expected_waves[lv - 1]])
			ok(total >= 1 and total <= WIRE_ID_LIMIT, "nivel %d, %dj: %d javalis (<= %d)" % [lv, players, total, WIRE_ID_LIMIT])
			ok(total <= NetCodec.MAX_BOARS_PER_HUNT, "nivel %d, %dj: %d cabe em NetCodec.MAX_BOARS_PER_HUNT" % [lv, players, total])
			eq(_has_alpha(plan[plan.size() - 1]), 1, "nivel %d, %dj: ultima onda com 1 alfa" % [lv, players])
	for players: int in [1, 2, 3, 4]:
		eq(_plan_total(HordeDirector.plan_waves(Data.get_horde_level(1), players)), expected_level_1[players - 1], "nivel 1 igual a horda de hoje (%dj)" % players)
	# the plan of a level is a fresh copy: editing it must not touch the data
	var p1: Array = HordeDirector.plan_waves(Data.get_horde_level(1), 1)
	var p2: Array = HordeDirector.plan_waves(Data.get_horde_level(2), 1)
	ok(p1.size() != p2.size(), "os dois niveis do seed tem numeros de ondas diferentes (%d e %d)" % [p1.size(), p2.size()])
	((p2[0] as Array)[0] as Dictionary)["members"].append("piglet")
	eq(_plan_total(HordeDirector.plan_waves(Data.get_horde_level(1), 1)), 128, "alterar o plano do nivel 2 nao toca nos dados (nivel 1)")
	eq(_plan_total(HordeDirector.plan_waves(Data.get_horde_level(2), 1)), 129, "nem no nivel 2 (funcao pura)")


func test_level_waves_override_keeps_the_budget_per_level() -> void:
	## A level may replace the waves through `overrides`; the resolved level is what plan_waves reads.
	var errs: PackedStringArray = _errors_with(func(h: Dictionary) -> void:
		var waves: Array = (h["waves"] as Array).duplicate(true)
		(waves[0]["groups"] as Array).append_array([
			{"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0}])
		h["levels"][1]["overrides"]["waves"] = waves)
	eq(errs.size(), 0, "override de ondas dentro do orcamento e aceito: %s" % str(errs))
	var over: PackedStringArray = _errors_with(func(h: Dictionary) -> void:
		var waves: Array = (h["waves"] as Array).duplicate(true)
		for i: int in 40:
			(waves[0]["groups"] as Array).append({"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0})
		h["levels"][1]["overrides"]["waves"] = waves)
	ok(_any_contains(over, "horde level 2 needs up to"), "orcamento de ids estourado SO no nivel 2 e reportado com o nivel: %s" % str(over))
	ok(not _any_contains(over, "horde needs up to"), "o topo (nivel 1) continua valido")


func test_validation_rejects_each_broken_v2_rule() -> void:
	var cases: Array[Array] = [
		["versao 1", "horde.version must be 2", func(h: Dictionary) -> void: h["version"] = 1],
		["sem niveis", "horde.levels must have at least one level", func(h: Dictionary) -> void: h["levels"] = []],
		["levels ausente", "horde.levels must have at least one level", func(h: Dictionary) -> void: h.erase("levels")],
		["level fora de ordem", "'level' must be 2", func(h: Dictionary) -> void: h["levels"][1]["level"] = 5],
		["nivel nao e objeto", "is not an object", func(h: Dictionary) -> void: h["levels"][1] = 7],
		["nome ausente", "'name' must be a string", func(h: Dictionary) -> void: h["levels"][1].erase("name")],
		["revive ausente", "'revive' must be an object", func(h: Dictionary) -> void: h["levels"][1].erase("revive")],
		["override proibido", "override 'eat_ring_m' is not allowed", func(h: Dictionary) -> void: h["levels"][1]["overrides"]["eat_ring_m"] = 5.0],
		["override quebra regra de topo", "level 2.kill_reward_mult must be in (0, 1)", func(h: Dictionary) -> void: h["levels"][1]["overrides"]["kill_reward_mult"] = 1.5],
		["override de velocidade", "to_barn_speed_frac must be in (0, 1.5]", func(h: Dictionary) -> void: h["levels"][1]["overrides"]["to_barn_speed_frac"] = 2.0],
		["rota: corner_out zero", "horde.route_corner_out_m must be > 0", func(h: Dictionary) -> void: h["route_corner_out_m"] = 0.0],
		["rota: margem negativa", "horde.route_crop_margin_m must be >= 0", func(h: Dictionary) -> void: h["route_crop_margin_m"] = -1.0],
		["rota: arrive zero", "horde.route_waypoint_arrive_m must be > 0", func(h: Dictionary) -> void: h["route_waypoint_arrive_m"] = 0.0],
		["rota: lavouras nao e lista", "horde.route_avoid_crops must be an array", func(h: Dictionary) -> void: h["route_avoid_crops"] = "corn"],
		["rota: lavoura nao e texto", "route_avoid_crops has a non-string entry", func(h: Dictionary) -> void: h["route_avoid_crops"] = [3]],
		["ammo.infinite nao bool", "ammo.infinite must be a bool", func(h: Dictionary) -> void: h["levels"][1]["ammo"]["infinite"] = 1],
		["ammo negativo", "ammo.start_reserve_mags must be an integer >= 0", func(h: Dictionary) -> void: h["levels"][1]["ammo"]["start_reserve_mags"] = -1],
		["ammo fracionario", "ammo.reserve_cap_mags must be an integer >= 0", func(h: Dictionary) -> void: h["levels"][1]["ammo"]["reserve_cap_mags"] = 2.5],
		["teto menor que o inicio", "ammo.reserve_cap_mags must be >= max(1, start_reserve_mags)", func(h: Dictionary) -> void: h["levels"][1]["ammo"]["start_reserve_mags"] = int(h["levels"][1]["ammo"]["reserve_cap_mags"]) + 1],
		["teto zero sem infinita", "ammo.reserve_cap_mags must be >= max(1, start_reserve_mags)", func(h: Dictionary) -> void:
			h["levels"][1]["ammo"]["start_reserve_mags"] = 0
			h["levels"][1]["ammo"]["reserve_cap_mags"] = 0],
		["mais de 8 caixas", "more than 8 entries", func(h: Dictionary) -> void:
			var pos: Array = []
			for i: int in 9:
				pos.append([float(i), 0.0])
			h["levels"][1]["ammo_crates"]["positions"] = pos],
		["caixa mal formada", "positions entries must be [x, z]", func(h: Dictionary) -> void: h["levels"][1]["ammo_crates"]["positions"] = [[1.0]]],
		["caixa sem cartuchos", "mags_per_crate must be >= 1 with crates", func(h: Dictionary) -> void: h["levels"][1]["ammo_crates"]["mags_per_crate"] = 0],
		["caixa sem raio", "pickup_radius_m must be > 0 with crates", func(h: Dictionary) -> void: h["levels"][1]["ammo_crates"]["pickup_radius_m"] = 0.0],
		["caixa sem retry", "claim_retry_s must be > 0 with crates", func(h: Dictionary) -> void: h["levels"][1]["ammo_crates"]["claim_retry_s"] = 0.0],
		["respawn negativo", "ammo_crates.respawn_s must be >= 0", func(h: Dictionary) -> void: h["levels"][1]["ammo_crates"]["respawn_s"] = -1.0],
		["cercado inset negativo", "confine.inset_m must be >= 0", func(h: Dictionary) -> void: h["levels"][1]["confine"]["inset_m"] = -0.1],
		["cercado hint zero", "confine.hint_s must be > 0", func(h: Dictionary) -> void: h["levels"][1]["confine"]["hint_s"] = 0.0],
		["cercado intervalo zero", "confine.hint_interval_s must be > 0", func(h: Dictionary) -> void: h["levels"][1]["confine"]["hint_interval_s"] = 0.0],
		["cercado enabled nao bool", "confine.enabled must be a bool", func(h: Dictionary) -> void: h["levels"][1]["confine"]["enabled"] = "sim"],
		["spawn incompleto", "'player_spawn' must be [] or [x, z, yaw_deg]", func(h: Dictionary) -> void: h["levels"][1]["player_spawn"] = [1.0, 2.0]],
		["spawn nao e lista", "'player_spawn' must be an array", func(h: Dictionary) -> void: h["levels"][1]["player_spawn"] = "meio"],
		["levantar: vida acima do maximo", "revive.health must be in (0, player.max_health]", func(h: Dictionary) -> void: h["levels"][1]["revive"]["health"] = 9999.0],
		["levantar: vida zero", "revive.health must be in (0, player.max_health]", func(h: Dictionary) -> void: h["levels"][1]["revive"]["health"] = 0.0],
		["levantar: hold zero", "revive.hold_s must be > 0 when enabled", func(h: Dictionary) -> void: h["levels"][1]["revive"]["hold_s"] = 0.0],
		["levantar: raio zero", "revive.radius_m must be > 0 when enabled", func(h: Dictionary) -> void: h["levels"][1]["revive"]["radius_m"] = 0.0],
		["levantar: retry zero", "revive.retry_s must be > 0 when enabled", func(h: Dictionary) -> void: h["levels"][1]["revive"]["retry_s"] = 0.0],
		["levantar: sangramento negativo", "revive.bleed_out_s must be >= 0", func(h: Dictionary) -> void: h["levels"][1]["revive"]["bleed_out_s"] = -5.0],
		["levantar: tolerancia negativa", "revive.claim_tolerance_m must be >= 0", func(h: Dictionary) -> void: h["levels"][1]["revive"]["claim_tolerance_m"] = -1.0],
		["levantar: campo ausente", "revive.hold_s must be a number", func(h: Dictionary) -> void: h["levels"][1]["revive"].erase("hold_s")],
		["javali desconhecido", "unknown boar type 'dragao'", func(h: Dictionary) -> void: h["levels"][1]["boar_overrides"]["dragao"] = {"max_charges": 1}],
		["agressao invalida", "boar_overrides.sow.aggression is invalid", func(h: Dictionary) -> void: h["levels"][1]["boar_overrides"]["sow"]["aggression"] = "furioso"],
		["campo proibido", "boar_overrides.boar.hp is not an allowed field", func(h: Dictionary) -> void: h["levels"][1]["boar_overrides"]["boar"]["hp"] = 5.0],
		["valor negativo", "boar_overrides.boar.charge_damage must be a number >= 0", func(h: Dictionary) -> void: h["levels"][1]["boar_overrides"]["boar"]["charge_damage"] = -1.0],
		["valor nao numerico", "boar_overrides.alpha.recover_s must be a number >= 0", func(h: Dictionary) -> void: h["levels"][1]["boar_overrides"]["alpha"]["recover_s"] = "x"],
	]
	for c: Array in cases:
		var errs: PackedStringArray = _errors_with(c[2] as Callable)
		ok(errs.size() >= 1, "regra v2 quebrada gera erro: %s" % c[0])
		ok(_any_contains(errs, str(c[1])), "regra v2 '%s': esperava '%s', veio %s" % [c[0], c[1], str(errs)])


func test_revive_may_be_off_with_zeros_and_ammo_may_be_infinite() -> void:
	## Level 1 of the seed: revive/crates off with zeros are valid, not errors.
	var errs: PackedStringArray = _errors_with(func(h: Dictionary) -> void:
		h["levels"][1]["revive"]["enabled"] = false
		h["levels"][1]["revive"]["hold_s"] = 0.0
		h["levels"][1]["revive"]["radius_m"] = 0.0
		h["levels"][1]["revive"]["retry_s"] = 0.0
		h["levels"][1]["ammo"] = {"infinite": true, "start_reserve_mags": 0, "reserve_cap_mags": 0}
		h["levels"][1]["ammo_crates"]["positions"] = [])
	eq(errs.size(), 0, "desligados com zeros: valido (%s)" % str(errs))


const CORN: Rect2 = Rect2(23.0, -19.0, 64.0, 78.0)
const CORNER_OUT: float = 2.0


func _obstacles(rects: Array[Rect2], exits: Array[Vector2] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in rects.size():
		out.append({"rect": rects[i], "exit": exits[i] if i < exits.size() else Vector2.INF})
	return out


## True if any point of a-b is strictly inside r (sampled; the plan must never cross an obstacle interior).
func _enters(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var inner: Rect2 = r.grow(-0.01)
	for i: int in 401:
		if inner.has_point(a.lerp(b, float(i) / 400.0)):
			return true
	return false


func _path_clear(from: Vector2, route: PackedVector2Array, rects: Array[Rect2]) -> bool:
	var at: Vector2 = from
	for p: Vector2 in route:
		for r: Rect2 in rects:
			if _enters(at, p, r):
				return false
		at = p
	return true


func test_route_vectors_from_the_contract() -> void:
	## docs/plano_horda_nivel2.md 4.4: only the corn, corner_out_m 2.
	var obs: Array[Dictionary] = _obstacles([CORN])
	var r1: PackedVector2Array = HordeRoute.plan(Vector2(105, 95), Vector2(38, -88), obs, CORNER_OUT)
	eq(r1.size(), 2, "de (105, 95): 2 pontos")
	if r1.size() == 2:
		ok(r1[0].is_equal_approx(Vector2(89, -21)), "de (105, 95): 1o ponto (89, -21), veio %s" % str(r1[0]))
		ok(r1[1].is_equal_approx(Vector2(38, -88)), "termina no destino")
	var r2: PackedVector2Array = HordeRoute.plan(Vector2(20, 115), Vector2(38, -88), obs, CORNER_OUT)
	eq(r2.size(), 2, "de (20, 115): 2 pontos")
	if r2.size() == 2:
		ok(r2[0].is_equal_approx(Vector2(21, -21)), "de (20, 115): 1o ponto (21, -21), veio %s" % str(r2[0]))
		ok(r2[1].is_equal_approx(Vector2(38, -88)), "termina no destino")
	var r3: PackedVector2Array = HordeRoute.plan(Vector2(105, 95), Vector2(38, -88), _obstacles([]), CORNER_OUT)
	eq(r3, PackedVector2Array([Vector2(38, -88)]), "sem obstaculo: so o destino")
	var rects: Array[Rect2] = [CORN]
	ok(_path_clear(Vector2(105, 95), r1, rects), "a rota de (105, 95) nunca entra no milho")
	ok(_path_clear(Vector2(20, 115), r2, rects), "a rota de (20, 115) nunca entra no milho")
	# a free line does not bend: both ends west of the corn
	var free: PackedVector2Array = HordeRoute.plan(Vector2(0, 100), Vector2(0, -88), _obstacles([CORN]), CORNER_OUT)
	eq(free, PackedVector2Array([Vector2(0, -88)]), "linha livre de obstaculos nao faz desvio")


func test_route_border_touch_does_not_block_and_tie_goes_to_the_lowest_node() -> void:
	var box: Rect2 = Rect2(0, 0, 10, 10)
	# running along the border y = 0: touches, does not cross the open interior
	var along: PackedVector2Array = HordeRoute.plan(Vector2(-5, 0), Vector2(15, 0), _obstacles([box]), CORNER_OUT)
	eq(along, PackedVector2Array([Vector2(15, 0)]), "tocar a borda nao bloqueia")
	# straight through the middle: blocked, symmetric detour: ties break to the lowest node index (top: min.y first)
	var tie: PackedVector2Array = HordeRoute.plan(Vector2(-10, 5), Vector2(20, 5), _obstacles([box]), CORNER_OUT)
	eq(tie.size(), 3, "desvio simetrico: 2 quinas + destino (%s)" % str(tie))
	if tie.size() == 3:
		ok(tie[0].is_equal_approx(Vector2(-2, -2)) and tie[1].is_equal_approx(Vector2(12, -2)), "empate: menor indice de no (lado min.y): %s" % str(tie))
	var rects: Array[Rect2] = [box]
	ok(_path_clear(Vector2(-10, 5), tie, rects), "o desvio nao entra na caixa")
	eq(HordeRoute.plan(Vector2(-10, 5), Vector2(20, 5), _obstacles([box]), CORNER_OUT), tie, "mesma entrada, mesma rota")


func test_route_exit_marker_and_ignored_obstacles() -> void:
	var box: Rect2 = Rect2(0, 0, 10, 10)
	# from inside with an exit: the exit comes first, then straight on
	var out_first: PackedVector2Array = HordeRoute.plan(Vector2(5, 5), Vector2(5, -30), _obstacles([box], [Vector2(5, -3)]), CORNER_OUT)
	eq(out_first, PackedVector2Array([Vector2(5, -3), Vector2(5, -30)]), "de dentro com saida: a saida e o 1o ponto")
	# from inside with an exit, destination behind the box: leaves, then goes around
	var around: PackedVector2Array = HordeRoute.plan(Vector2(5, 5), Vector2(5, 30), _obstacles([box], [Vector2(5, -3)]), CORNER_OUT)
	ok(around.size() >= 3 and around[0].is_equal_approx(Vector2(5, -3)) and around[around.size() - 1].is_equal_approx(Vector2(5, 30)), "saida, desvio, destino: %s" % str(around))
	var rects: Array[Rect2] = [box]
	var tail: PackedVector2Array = around.slice(1)
	ok(_path_clear(Vector2(5, -3), tail, rects), "depois da saida a rota contorna a caixa")
	# from inside without an exit: the obstacle is ignored
	eq(HordeRoute.plan(Vector2(5, 5), Vector2(5, 30), _obstacles([box]), CORNER_OUT), PackedVector2Array([Vector2(5, 30)]), "de dentro sem saida: obstaculo ignorado")
	# to inside: the obstacle is ignored
	eq(HordeRoute.plan(Vector2(5, -30), Vector2(5, 5), _obstacles([box]), CORNER_OUT), PackedVector2Array([Vector2(5, 5)]), "destino dentro: obstaculo ignorado")
	# one obstacle ignored does not drop the others
	var wall: Rect2 = Rect2(-30, -20, 60, 8)
	var both: PackedVector2Array = HordeRoute.plan(Vector2(5, -30), Vector2(5, 5), _obstacles([box, wall]), CORNER_OUT)
	ok(both.size() >= 2 and both[both.size() - 1].is_equal_approx(Vector2(5, 5)), "o outro obstaculo continua valendo: %s" % str(both))
	var others: Array[Rect2] = [wall]
	ok(_path_clear(Vector2(5, -30), both, others), "e a rota o contorna")


func test_route_corner_inside_another_rect_is_dropped() -> void:
	## Two overlapping rectangles: the corners of the grown one that fall inside the other are not nodes.
	var a: Rect2 = Rect2(0, 0, 10, 10)
	var b: Rect2 = Rect2(8, 8, 10, 10)
	var obs: Array[Dictionary] = _obstacles([a, b])
	var rects: Array[Rect2] = [a, b]
	var route: PackedVector2Array = HordeRoute.plan(Vector2(-10, -10), Vector2(30, 30), obs, CORNER_OUT)
	ok(route.size() >= 1 and route[route.size() - 1].is_equal_approx(Vector2(30, 30)), "termina no destino: %s" % str(route))
	for i: int in route.size() - 1:
		for r: Rect2 in rects:
			ok(not r.grow(-0.01).has_point(route[i]), "ponto de desvio %s fora dos obstaculos" % str(route[i]))
	ok(_path_clear(Vector2(-10, -10), route, rects), "a rota nao entra em nenhum dos dois retangulos")
	# the corner (12, 12) of the grown `a` lies inside b: never offered as a node
	for p: Vector2 in route:
		ok(not p.is_equal_approx(Vector2(12, 12)), "a quina (12, 12), dentro de b, nao e usada")
	# many random trips never enter the obstacles and always end at `to`
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261120
	var bad: int = 0
	for i: int in 60:
		var f: Vector2 = Vector2(rng.randf_range(-40.0, 60.0), rng.randf_range(-40.0, 60.0))
		var t: Vector2 = Vector2(rng.randf_range(-40.0, 60.0), rng.randf_range(-40.0, 60.0))
		if a.has_point(f) or b.has_point(f) or a.has_point(t) or b.has_point(t):
			continue
		var pr: PackedVector2Array = HordeRoute.plan(f, t, obs, CORNER_OUT)
		if pr.is_empty() or not pr[pr.size() - 1].is_equal_approx(t) or not _path_clear(f, pr, rects):
			bad += 1
	eq(bad, 0, "60 viagens aleatorias: toda rota termina em `to` sem cruzar os obstaculos")
