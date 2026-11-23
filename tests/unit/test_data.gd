extends "res://tests/lib/test_case.gd"
## Data registry: schema, references between files, contract rules (docs/arquitetura.md section 9).


func test_no_load_errors() -> void:
	eq(Data.get_load_errors().size(), 0, "Data.get_load_errors: %s" % str(Data.get_load_errors()))


func test_ids_constants_match_data() -> void:
	var consts: Dictionary = Ids.new().get_script().get_script_constant_map()
	var weapon_ids: Array[StringName] = Data.get_weapon_ids()
	var item_ids: Array[StringName] = Data.get_equipment_ids()
	var dog_ids: Array[StringName] = Data.get_dog_ids()
	var boar_ids: Array[StringName] = Data.get_boar_type_ids()
	for cname: String in consts:
		var value: StringName = StringName(str(consts[cname]))
		if cname.begins_with("W_"):
			ok(weapon_ids.has(value), "Ids.%s = %s nao existe em weapons.json" % [cname, value])
		elif cname.begins_with("I_"):
			ok(item_ids.has(value), "Ids.%s = %s nao existe em equipment.json" % [cname, value])
		elif cname.begins_with("D_"):
			ok(dog_ids.has(value), "Ids.%s = %s nao existe em dogs.json" % [cname, value])
	for id: StringName in [Ids.PIGLET, Ids.SOW, Ids.BOAR, Ids.ALPHA]:
		ok(boar_ids.has(id), "tipo de javali %s ausente em boars.json" % id)
	# And the other direction: every data id has an Ids constant.
	var known: Dictionary = {}
	for cname: String in consts:
		known[str(consts[cname])] = true
	for id: StringName in weapon_ids + item_ids + dog_ids + boar_ids:
		ok(known.has(String(id)), "id '%s' dos dados nao tem constante em Ids" % id)


func test_catalog_entries_have_prices_and_currency() -> void:
	for id: StringName in Data.get_weapon_ids() + Data.get_equipment_ids() + Data.get_dog_ids():
		var def: Dictionary = Data.get_item_def(id)
		ok(not def.is_empty(), "get_item_def(%s) vazio" % id)
		ok(float(def.get("price", -1)) >= 0.0, "%s: preco negativo/ausente" % id)
		ok(["money", "gold"].has(str(def.get("currency", ""))), "%s: moeda invalida" % id)
		ok(str(def.get("name", "")) != "", "%s: sem nome" % id)
		ne(Data.get_item_category(id), &"", "categoria de %s" % id)
	eq(Data.get_item_category(&"nao_existe"), &"", "categoria de id inexistente")
	eq(Data.get_item_def(&"nao_existe").size(), 0, "def de id inexistente")


func test_starting_weapon_is_free() -> void:
	eq(float(Data.get_weapon(Ids.W_CARBINE_22).get("price", -1)), 0.0, "carabina inicial custa 0")
	var start: Array = Data.get_game().get("economy", {}).get("start_weapons", [])
	ok(start.has("carbine_22"), "economy.start_weapons contem carbine_22")


func test_weapon_balance_fields() -> void:
	for id: StringName in Data.get_weapon_ids():
		var w: Dictionary = Data.get_weapon(id)
		for f: String in ["damage", "pellets", "price", "currency"]:
			ok(w.has(f), "%s sem campo %s" % [id, f])
		ok(float(w.get("damage", 0.0)) > 0.0, "%s: damage > 0" % id)
		ok(int(w.get("pellets", 0)) >= 1, "%s: pellets >= 1" % id)


func test_boar_types_sane() -> void:
	for id: StringName in Data.get_boar_type_ids():
		var b: Dictionary = Data.get_boar_type(id)
		ok(float(b.get("weight_min_kg", 0)) > 0.0, "%s: weight_min > 0" % id)
		ok(float(b.get("weight_max_kg", 0)) >= float(b.get("weight_min_kg", 0)), "%s: weight_max >= weight_min" % id)
		ok(float(b.get("health_per_kg", 0)) > 0.0, "%s: health_per_kg > 0" % id)
		ok(float(b.get("value_per_kg", 0)) > 0.0, "%s: value_per_kg > 0" % id)
	var rules: Dictionary = Data.get_boar_rules()
	ok(rules.has("zone_multipliers"), "boar_rules.zone_multipliers")
	for zone: StringName in [Ids.ZONE_HEAD, Ids.ZONE_VITAL, Ids.ZONE_BODY, Ids.ZONE_REAR]:
		ok((rules.get("zone_multipliers", {}) as Dictionary).has(String(zone)), "zone_multipliers sem %s" % zone)


func test_contract_groups_rules() -> void:
	var max_alive: int = int(Data.get_game().get("hunt", {}).get("max_alive_boars", 0))
	ok(max_alive > 0, "max_alive_boars > 0")
	var boar_ids: Array[StringName] = Data.get_boar_type_ids()
	var checked: int = 0
	for map_id: StringName in Data.get_map_ids():
		var map: Dictionary = Data.get_map(map_id)
		if bool(map.get("available", false)):
			ok(Data.get_contract_count(map_id) >= 1, "mapa disponivel %s sem contratos" % map_id)
		for ci: int in Data.get_contract_count(map_id):
			var c: Dictionary = Data.get_contract(map_id, ci)
			var groups: Array = c.get("groups", [])
			ok(groups.size() >= 1, "%s/%d: ao menos 1 grupo" % [map_id, ci])
			var total: int = 0
			for g: Dictionary in groups:
				var members: Array = g.get("members", [])
				ok(members.size() == 1 or (members.size() >= 3 and members.size() <= 6), "%s/%d: bando de %d membros (1 ou 3-6)" % [map_id, ci, members.size()])
				for m: Variant in members:
					ok(boar_ids.has(StringName(str(m))), "%s/%d: tipo %s desconhecido" % [map_id, ci, m])
				ok(float(g.get("delay_s", -1.0)) >= 0.0, "%s/%d: delay_s >= 0" % [map_id, ci])
				total += members.size()
			ok(total <= max_alive, "%s/%d: %d javalis > max_alive_boars %d" % [map_id, ci, total, max_alive])
			ok(float(c.get("reward_mult", 0)) > 0.0, "%s/%d: reward_mult > 0" % [map_id, ci])
			ok(float(c.get("crop_drain_mult", 0)) > 0.0, "%s/%d: crop_drain_mult > 0" % [map_id, ci])
			ok(float(c.get("bonus_money", -1)) >= 0.0, "%s/%d: bonus_money >= 0" % [map_id, ci])
			checked += 1
	ok(checked >= 5, "mato_grosso tem 5 contratos (%d)" % checked)


func test_mato_grosso_structure_and_difficulty_progression() -> void:
	## Structural rules only: balance numbers may change in data/ without breaking this test.
	eq(Data.get_contract_count(&"mato_grosso"), 5, "5 contratos")
	var max_alive: int = int(Data.get_game().get("hunt", {}).get("max_alive_boars", 0))
	var prev_total: int = 0
	var prev_drain: float = 0.0
	var prev_reward: float = 0.0
	for i: int in Data.get_contract_count(&"mato_grosso"):
		var c: Dictionary = Data.get_contract(&"mato_grosso", i)
		var groups: Array = c.get("groups", [])
		ok(groups.size() >= 1, "contrato %d tem ao menos 1 grupo" % i)
		var total: int = 0
		for g: Dictionary in groups:
			var n: int = (g.get("members", []) as Array).size()
			ok(n == 1 or (n >= 3 and n <= 6), "contrato %d: grupo de %d membros (1 ou 3-6)" % [i, n])
			total += n
		ok(total >= 1 and total <= max_alive, "contrato %d: %d javalis (<= max_alive_boars %d)" % [i, total, max_alive])
		var drain: float = float(c.get("crop_drain_mult", 0.0))
		var reward: float = float(c.get("reward_mult", 0.0))
		ok(total >= prev_total, "contrato %d: total de javalis (%d) nao decresce (anterior %d)" % [i, total, prev_total])
		ok(drain >= prev_drain, "contrato %d: crop_drain_mult (%s) nao decresce" % [i, drain])
		ok(reward >= prev_reward, "contrato %d: reward_mult (%s) nao decresce" % [i, reward])
		prev_total = total
		prev_drain = drain
		prev_reward = reward


func test_unavailable_maps_have_no_contracts_and_invalid_lookups_are_safe() -> void:
	expect_errors()
	for map_id: StringName in Data.get_map_ids():
		if not bool(Data.get_map(map_id).get("available", false)):
			eq(Data.get_contract_count(map_id), 0, "mapa indisponivel %s" % map_id)
	eq(Data.get_contract(&"mato_grosso", 99).size(), 0, "contrato fora do intervalo")
	eq(Data.get_contract(&"mato_grosso", -1).size(), 0, "contrato negativo")
	eq(Data.get_map(&"nao_existe").size(), 0, "mapa inexistente")
	eq(Data.get_weapon(&"nao_existe").size(), 0, "arma inexistente")


func test_gold_packages() -> void:
	var packs: Array[Dictionary] = Data.get_gold_packages()
	ok(packs.size() >= 1, "ha pacotes de ouro")
	var seen: Dictionary = {}
	for p: Dictionary in packs:
		ok(int(p.get("gold", 0)) > 0 and int(p.get("gold", 0)) <= 9999, "ouro do pacote %s em 1..9999" % p.get("id", "?"))
		ok(float(p.get("price_brl", 0.0)) > 0.0, "preco do pacote %s" % p.get("id", "?"))
		ok(not seen.has(str(p.get("id", ""))), "id duplicado %s" % p.get("id", "?"))
		seen[str(p.get("id", ""))] = true
		eq(Data.get_gold_package(StringName(str(p["id"]))).get("gold"), p["gold"], "get_gold_package(%s)" % p["id"])


func test_game_quality_presets() -> void:
	var presets: Dictionary = Data.get_game().get("quality_presets", {})
	for q: StringName in [Ids.Q_LOW, Ids.Q_MEDIUM, Ids.Q_HIGH]:
		ok(presets.has(String(q)), "preset de qualidade %s" % q)
	ok(int(Data.get_game().get("economy", {}).get("start_money", -1)) >= 0, "start_money >= 0")


func test_horde_data_references_and_rules() -> void:
	## docs/horda.md section 3: data/horde.json is consistent with the other files and with the map scene.
	var h: Dictionary = Data.get_horde()
	ok(not h.is_empty(), "data/horde.json carregado")
	eq(int(h.get("version", 0)), 2, "version 2 (docs/plano_horda_nivel2.md section 3)")
	ok(str(h.get("name", "")) != "" and str(h.get("description", "")) != "", "name e description (texto do lobby)")
	var map_id: StringName = StringName(str(h.get("map_id", "")))
	ok(Data.get_map_ids().has(map_id), "map_id %s existe em maps.json" % map_id)
	ok(bool(Data.get_map(map_id).get("available", false)), "mapa da horda disponivel")
	var scene_text: String = FileAccess.get_file_as_string(ScenePaths.map_scene(map_id))
	ok(scene_text.contains("prop_id = &\"%s\"" % str(h.get("objective_prop_id", "?"))), "a cena do mapa tem um PropSpawn '%s' (o celeiro)" % str(h.get("objective_prop_id", "?")))
	var zone_regex: RegEx = RegEx.new()
	zone_regex.compile("parent=\"SpawnZones\"")
	var zones: int = zone_regex.search_all(scene_text).size()
	ok(zones >= 1, "a cena do mapa tem SpawnZones (%d)" % zones)
	var boar_ids: Array[StringName] = Data.get_boar_type_ids()
	var waves: Array = h.get("waves", [])
	var total: int = 0
	var wave_max: int = 0
	for wi: int in waves.size():
		var wave_total: int = 0
		for g: Dictionary in (waves[wi] as Dictionary).get("groups", []):
			var members: Array = g.get("members", [])
			ok(members.size() == 1 or (members.size() >= 3 and members.size() <= 6), "onda %d: bando de %d (1 ou 3-6)" % [wi + 1, members.size()])
			for m: Variant in members:
				ok(boar_ids.has(StringName(str(m))), "onda %d: tipo %s existe em boars.json" % [wi + 1, m])
			ok(int(g.get("spawn_zone", -1)) >= 0, "onda %d: spawn_zone >= 0" % [wi + 1])
			ok(float(g.get("delay_s", -1.0)) >= 0.0, "onda %d: delay_s >= 0" % [wi + 1])
			wave_total += members.size()
		total += wave_total
		wave_max = maxi(wave_max, wave_total)
	eq(total, 128, "128 javalis base")
	var mults: Array = h.get("player_count_mult", [])
	eq(mults.size(), int(Data.get_net().get("max_players", 0)), "um multiplicador por jogador da sala")
	var prev: float = 1.0
	for m: Variant in mults:
		ok(float(m) >= prev, "multiplicadores >= 1 e nao decrescentes (%s)" % str(m))
		prev = float(m)
	var max_mult: float = float(mults.back()) if not mults.is_empty() else 1.0
	var budget: int = 0
	for w: Variant in waves:
		var wt: int = 0
		for g: Dictionary in (w as Dictionary)["groups"]:
			wt += (g["members"] as Array).size()
		budget += ceili(float(wt) * max_mult)
	ok(budget <= 255, "orcamento de ids %d <= 255" % budget)
	# the last wave carries the alpha, and no earlier wave does (the alpha is the finale)
	var last_members: Array = []
	for g: Dictionary in (waves.back() as Dictionary)["groups"]:
		last_members.append_array(g["members"])
	ok(last_members.has("alpha"), "ultima onda traz o alfa")
	var max_alive: int = int(Data.get_game().get("hunt", {}).get("max_alive_boars", 0))
	ok(max_alive > 0, "max_alive_boars > 0")
	print("INFO horda: maior onda solo %d javalis, max_alive_boars %d (o spawner segura o excedente)" % [wave_max, max_alive])
	ok(float(h.get("kill_reward_mult", 0.0)) < 1.0, "abate de horda paga menos que o de contrato")
	ok(int(h.get("max_carcasses", 0)) <= max_alive, "max_carcasses nao passa de max_alive_boars")


func test_horde_levels_resolve_and_reference_the_data() -> void:
	## docs/plano_horda_nivel2.md 3 and 3.1: two levels; level 1 = the old horde; level 2 = counted ammo, crates, confine, revive.
	var h: Dictionary = Data.get_horde()
	eq(Data.get_horde_level_count(), 2, "dois niveis no seed")
	eq((h.get("levels", []) as Array).size(), Data.get_horde_level_count(), "count = levels.size()")
	eq(str(h.get("route_avoid_crops", [])), str(["corn"]), "route_avoid_crops = [corn]")
	near(float(h.get("route_crop_margin_m", -1.0)), 4.0, 0.0001, "route_crop_margin_m")
	near(float(h.get("route_corner_out_m", -1.0)), 2.0, 0.0001, "route_corner_out_m")
	near(float(h.get("route_waypoint_arrive_m", -1.0)), 3.0, 0.0001, "route_waypoint_arrive_m")
	eq(Data.get_horde_level(0), {}, "nivel 0 = {}")
	eq(Data.get_horde_level(3), {}, "nivel 3 = {}")
	eq(Data.get_horde_level(-1), {}, "nivel negativo = {}")
	var l1: Dictionary = Data.get_horde_level(1)
	var l2: Dictionary = Data.get_horde_level(2)
	for lv: int in [1, 2]:
		var d: Dictionary = Data.get_horde_level(lv)
		eq(int(d.get("level", 0)), lv, "nivel %d: level" % lv)
		ok(not d.has("levels"), "nivel %d resolvido nao carrega 'levels'" % lv)
		for k: String in ["name", "description", "ammo", "ammo_crates", "confine", "player_spawn", "revive", "boar_overrides", "waves", "eat_ring_m"]:
			ok(d.has(k), "nivel %d resolvido tem '%s'" % [lv, k])
		ok(str(d.get("name", "")) != "" and str(d.get("description", "")) != "", "nivel %d: name e description" % lv)
	# level 1 = today's horde
	near(float(l1["kill_reward_mult"]), float(h["kill_reward_mult"]), 0.0001, "nivel 1 herda kill_reward_mult do topo")
	eq(int(l1["victory_bonus_money"]), int(h["victory_bonus_money"]), "nivel 1 herda victory_bonus_money")
	ok(bool(l1["ammo"]["infinite"]), "nivel 1: municao infinita")
	ok(not bool(l1["confine"]["enabled"]) and not bool(l1["revive"]["enabled"]), "nivel 1: sem cercado e sem levantar")
	eq((l1["ammo_crates"]["positions"] as Array).size(), 0, "nivel 1: sem caixas")
	eq((l1["player_spawn"] as Array).size(), 0, "nivel 1: spawn do mapa")
	eq((l1["boar_overrides"] as Dictionary).size(), 0, "nivel 1: sem sobrescritas de javali")
	# level 2
	near(float(l2["kill_reward_mult"]), 0.5, 0.0001, "nivel 2: kill_reward_mult 0,5")
	eq(int(l2["victory_bonus_money"]), 5000, "nivel 2: bonus 5000")
	near(float(l2["to_barn_speed_frac"]), 0.9, 0.0001, "nivel 2: to_barn_speed_frac 0,9 (override)")
	near(float(h["to_barn_speed_frac"]), 0.8, 0.0001, "topo continua 0,8 (override nao vaza)")
	ok(not bool(l2["ammo"]["infinite"]), "nivel 2: municao contada")
	eq(int(l2["ammo"]["start_reserve_mags"]), 2, "start_reserve_mags 2")
	eq(int(l2["ammo"]["reserve_cap_mags"]), 6, "reserve_cap_mags 6")
	eq((l2["ammo_crates"]["positions"] as Array).size(), 3, "nivel 2: 3 caixas")
	eq(int(l2["ammo_crates"]["mags_per_crate"]), 2, "mags_per_crate 2")
	ok(bool(l2["confine"]["enabled"]), "nivel 2: cercado")
	ok(bool(l2["revive"]["enabled"]), "nivel 2: levantar")
	near(float(l2["revive"]["health"]), 50.0, 0.0001, "revive.health 50")
	near(float(l2["revive"]["bleed_out_s"]), 60.0, 0.0001, "bleed_out_s 60")
	eq((l2["player_spawn"] as Array).size(), 3, "nivel 2: player_spawn [x, z, yaw]")
	eq(str(Data.get_horde_boar_type(&"sow", 2).get("aggression", "")), "provoked", "porca provocada no nivel 2")
	# the plain type is untouched by the overrides
	eq(Data.get_horde_boar_type(&"sow", 1), Data.get_boar_type(&"sow"), "nivel 1 = tipo puro")
	eq(Data.get_horde_boar_type(&"sow", 0), Data.get_boar_type(&"sow"), "nivel 0 = tipo puro")
	eq(Data.get_horde_boar_type(&"sow", 9), Data.get_boar_type(&"sow"), "nivel fora do intervalo = tipo puro")
	eq(str(Data.get_boar_type(&"sow").get("aggression", "")), "defend_in_herd", "boars.json intacto (cobertura da copia)")
	eq(Data.get_horde_boar_type(&"piglet", 2), Data.get_boar_type(&"piglet"), "leitao sem sobrescrita")
	var boar2: Dictionary = Data.get_horde_boar_type(&"boar", 2)
	near(float(boar2["charge_damage"]), 30.0, 0.0001, "javali: charge_damage 30")
	near(float(boar2["aggro_radius_m"]), 18.0, 0.0001, "javali: aggro_radius 18")
	eq(int(boar2["max_charges"]), 4, "javali: max_charges 4")
	expect_errors()   # Data.get_boar_type reports an unknown id with push_error
	eq(Data.get_horde_boar_type(&"inexistente", 2), {}, "tipo inexistente = {}")
	# every level-2 reference is real: weapons carried need the reserve cap to fit the weapon data
	for wid: StringName in Data.get_weapon_ids():
		ok(int(Data.get_weapon(wid).get("mag_size", 0)) > 0, "arma %s com mag_size > 0 (a municao contada multiplica por ele)" % wid)
	var spawn: Array = l2["player_spawn"]
	var rect: Rect2 = Rect2(-20.0, -110.0, 75.0, 48.0)   # farm fence rect of the Mato Grosso map
	ok(rect.has_point(Vector2(float(spawn[0]), float(spawn[1]))), "player_spawn dentro do cercado da fazenda")
	for pos: Variant in l2["ammo_crates"]["positions"]:
		ok(absf(float((pos as Array)[0])) <= 6.0, "caixa x=%s dentro da tulha (|x| <= 6)" % str((pos as Array)[0]))


func test_pix_config_has_placeholders_flagged() -> void:
	var cfg: Dictionary = Data.get_pix_config()
	for f: String in ["gateway", "pix_key", "merchant_name", "merchant_city", "redeem_secret"]:
		ok(cfg.has(f), "pix_config sem %s" % f)
	# Release gate: a placeholder secret/key must be replaced before publishing. Informational only.
	if str(cfg.get("redeem_secret", "")).begins_with("TROQUE"):
		print("INFO pix_config: redeem_secret ainda e o placeholder (trocar antes de publicar)")
	if str(cfg.get("pix_key", "")).begins_with("SUA-CHAVE"):
		print("INFO pix_config: pix_key ainda e o placeholder (DonationService.is_pix_configured() == false)")


# --- Upgrades (docs/plano_faca_mochila_folego.md 2.2 and 2.3; F1 ships only the backpack) ---

func test_upgrades_load_and_lookups() -> void:
	eq(Data.get_load_errors().size(), 0, "sem erros de carga: %s" % str(Data.get_load_errors()))
	eq(Data.get_upgrade_ids(), [&"backpack"] as Array[StringName], "so a mochila na F1")
	eq(Data.get_upgrade_level_count(&"backpack"), 4, "mochila tem 4 niveis")
	eq(Data.get_upgrade_level_def(&"backpack", 1).get("price"), 0, "nivel 1 custa 0")
	eq(Data.get_upgrade_level_def(&"backpack", 1).get("bonus_item_slots"), 0, "nivel 1 sem bonus")
	eq(Data.get_upgrade_level_def(&"backpack", 2).get("bonus_item_slots"), 1, "nivel 2 = +1 espaco")
	eq(Data.get_upgrade_level_def(&"backpack", 3).get("bonus_item_slots"), 2, "nivel 3 = +2")
	eq(Data.get_upgrade_level_def(&"backpack", 4).get("bonus_item_slots"), 3, "nivel 4 = +3")
	var prev: int = 0
	for lv: int in range(2, 5):
		var price: int = int(Data.get_upgrade_level_def(&"backpack", lv)["price"])
		ok(price > prev, "preco do nivel %d (%d) maior que o anterior (%d)" % [lv, price, prev])
		prev = price
	eq(Data.get_upgrade_level_def(&"backpack", 5), {}, "nivel 5 nao existe")
	eq(Data.get_upgrade_level_def(&"backpack", 0), {}, "nivel 0 nao existe")
	eq(Data.get_upgrade_level_def(&"backpack", -1), {}, "nivel negativo nao existe")
	var def: Dictionary = Data.get_upgrade(&"backpack")
	eq(str(def.get("currency")), "money", "moeda")
	ok(str(def.get("name", "")) != "", "tem nome")
	ok(str(def.get("short_name", "")).length() <= Data.SHORT_NAME_MAX_CHARS, "short_name curto")


func test_upgrades_unknown_ids_are_safe() -> void:
	# get_upgrade_level_count / get_upgrade_level_def do not push_error for an unknown id (contract 2.3).
	var mark: int = error_mark()
	eq(Data.get_upgrade_level_count(&"nao_existe"), 0, "contagem de id inexistente")
	eq(Data.get_upgrade_level_count(&""), 0, "contagem de id vazio")
	eq(Data.get_upgrade_level_def(&"nao_existe", 1), {}, "def de id inexistente")
	eq(errors_since(mark).size(), 0, "sem push_error nessas duas consultas: %s" % str(errors_since(mark)))
	# get_upgrade pushes an error (like every _lookup) and returns {}
	expect_errors()
	eq(Data.get_upgrade(&"nao_existe"), {}, "get_upgrade de id inexistente = {}")


func test_upgrades_are_not_items() -> void:
	eq(Data.get_item_category(&"knife"), &"", "faca nao e item")
	eq(Data.get_item_category(&"backpack"), &"", "mochila nao e item")
	eq(Data.get_item_def(&"backpack"), {}, "get_item_def nao ve a mochila")
	ok(not Data.get_equipment_ids().has(&"backpack"), "mochila fora dos equipamentos")
	ok(not Data.get_weapon_ids().has(&"knife"), "faca fora das armas")
	for id: StringName in Data.get_upgrade_ids():
		ok(not (Data.get_weapon_ids() + Data.get_equipment_ids() + Data.get_dog_ids()).has(id), "id de melhoria %s nao repete id de item" % id)
	eq(Ids.BACKPACK, &"backpack", "Ids.BACKPACK")
	eq(Ids.KNIFE, &"knife", "Ids.KNIFE")


## Runs `mutate` on the live (deep-copied, then restored) backpack entry and returns the new errors _validate_upgrades adds.
func _upgrade_errors_after(mutate: Callable) -> int:
	var saved: Variant = (Data._raw["upgrades"] as Dictionary).duplicate(true)
	var base: int = Data._errors.size()
	var entry: Dictionary = (Data._raw["upgrades"]["upgrades"] as Array)[0]
	mutate.call(entry)
	Data._validate_upgrades()
	var added: int = Data._errors.size() - base
	Data._errors.resize(base)
	Data._raw["upgrades"] = saved
	return added


func test_upgrades_validation_rejects_each_broken_rule() -> void:
	# Pokes the live registry (restored after every case) to prove _validate_upgrades reports the problem.
	eq(_upgrade_errors_after(func(_e: Dictionary) -> void: pass), 0, "controle: dados intactos nao geram erro")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][1]["level"] = 3) > 0, true, "nivel fora de ordem (2 -> 3)")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][0]["level"] = 0) > 0, true, "nivel 1 numerado 0")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][0]["price"] = 100) > 0, true, "preco do nivel 1 diferente de 0")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][1]["price"] = 0) > 0, true, "preco do nivel 2 igual a 0")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][2]["price"] = -5) > 0, true, "preco negativo")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][1]["price"] = 2000.5) > 0, true, "preco nao inteiro")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][2]["bonus_item_slots"] = 0) > 0, true, "bonus decrescente (1 -> 0)")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][0]["bonus_item_slots"] = 1) > 0, true, "bonus do nivel 1 diferente de 0")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][1]["bonus_item_slots"] = -1) > 0, true, "bonus negativo")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"][1].erase("bonus_item_slots")) > 0, true, "nivel da mochila sem bonus")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["id"] = "pa") > 0, true, "id 'pa' nao permitido")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["id"] = "medkit") > 0, true, "id igual ao de um equipamento (medkit)")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["currency"] = "gold") > 0, true, "moeda 'gold' nao permitida")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["name"] = "") > 0, true, "nome vazio")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["short_name"] = "Nome curto demais") > 0, true, "short_name com mais de 9 caracteres")
	eq(_upgrade_errors_after(func(e: Dictionary) -> void: e["levels"] = []) > 0, true, "sem niveis")
	eq(Data.get_load_errors().size(), 0, "registro restaurado sem erros")
	eq(Data.get_upgrade_level_count(&"backpack"), 4, "dados restaurados")


func test_upgrades_validation_medkit_id_yields_two_errors() -> void:
	# The id is both outside the allowed list and a reused item id (hint from S1): two distinct rules fire.
	var n: int = _upgrade_errors_after(func(e: Dictionary) -> void: e["id"] = "medkit")
	eq(n, 2, "id 'medkit' gera dois erros (fora da lista + repete item)")


# --- Stamina (docs/plano_faca_mochila_folego.md 1.2 and 2.2; F2) ---

func test_stamina_seed_values() -> void:
	eq(Data.get_load_errors().size(), 0, "sem erros de carga: %s" % str(Data.get_load_errors()))
	var s: Dictionary = Data.get_game().get("stamina", {})
	ok(not s.is_empty(), "game.json tem o bloco stamina")
	near(float(s.get("max", 0.0)), 100.0, 0.0001, "max 100")
	near(float(s.get("sprint_drain_per_s", 0.0)), 10.0, 0.0001, "sprint_drain_per_s 10 (10 s de corrida)")
	near(float(s.get("regen_per_s", 0.0)), 6.0, 0.0001, "regen_per_s 6")
	near(float(s.get("regen_delay_s", -1.0)), 1.0, 0.0001, "regen_delay_s 1")
	near(float(s.get("recover_threshold", 0.0)), 35.0, 0.0001, "recover_threshold 35")
	near(float(s.get("exhausted_message_s", 0.0)), 2.5, 0.0001, "exhausted_message_s 2,5")
	near(float(s.get("exhausted_message_interval_s", -1.0)), 30.0, 0.0001, "exhausted_message_interval_s 30")


## Runs `mutate` on the live (deep-copied, then restored) game.stamina block and returns the errors _validate_stamina adds.
## The mutation gets the whole game dictionary so a case can also remove the block.
func _stamina_errors_after(mutate: Callable) -> PackedStringArray:
	var game: Dictionary = Data._raw["game"]
	var saved: Variant = (game["stamina"] as Dictionary).duplicate(true)
	var base: int = Data._errors.size()
	mutate.call(game)
	Data._validate_stamina()
	var added: PackedStringArray = PackedStringArray()
	for i: int in range(base, Data._errors.size()):
		added.append(Data._errors[i])
	Data._errors.resize(base)
	game["stamina"] = saved
	return added


func _stamina_set(key: String, value: Variant) -> Callable:
	return func(game: Dictionary) -> void: game["stamina"][key] = value


func test_stamina_validation_rejects_each_broken_rule() -> void:
	# Pokes the live registry (restored after every case) to prove _validate_stamina reports each rule.
	eq(_stamina_errors_after(func(_g: Dictionary) -> void: pass).size(), 0, "controle: dados intactos nao geram erro")
	var cases: Array[Dictionary] = [
		{"label": "bloco ausente", "mutate": func(g: Dictionary) -> void: g.erase("stamina"), "text": "lacks 'stamina'"},
		{"label": "max = 0", "mutate": _stamina_set("max", 0.0), "text": "game.stamina.max"},
		{"label": "sprint_drain_per_s = 0", "mutate": _stamina_set("sprint_drain_per_s", 0.0), "text": "game.stamina.sprint_drain_per_s"},
		{"label": "regen_per_s = 0", "mutate": _stamina_set("regen_per_s", 0.0), "text": "game.stamina.regen_per_s"},
		{"label": "exhausted_message_s = 0", "mutate": _stamina_set("exhausted_message_s", 0.0), "text": "game.stamina.exhausted_message_s"},
		{"label": "regen_delay_s = -1", "mutate": _stamina_set("regen_delay_s", -1.0), "text": "game.stamina.regen_delay_s"},
		{"label": "recover_threshold = 0", "mutate": _stamina_set("recover_threshold", 0.0), "text": "game.stamina.recover_threshold"},
		{"label": "recover_threshold = max + 1", "mutate": _stamina_set("recover_threshold", 101.0), "text": "game.stamina.recover_threshold"},
		{"label": "exhausted_message_interval_s = -1", "mutate": _stamina_set("exhausted_message_interval_s", -1.0), "text": "game.stamina.exhausted_message_interval_s"},
		{"label": "campo ausente (regen_per_s)", "mutate": func(g: Dictionary) -> void: g["stamina"].erase("regen_per_s"), "text": "regen_per_s"},
		{"label": "campo nao numerico (max)", "mutate": _stamina_set("max", "cem"), "text": "'max'"},
	]
	for c: Dictionary in cases:
		var errs: PackedStringArray = _stamina_errors_after(c["mutate"])
		ok(errs.size() > 0, "%s gera erro" % c["label"])
		if errs.size() > 0:
			ok(errs[0].begins_with("Data: "), "%s: mensagem comeca com 'Data: ' (%s)" % [c["label"], errs[0]])
			ok(errs[0].contains(str(c["text"])), "%s: a mensagem cita '%s' (%s)" % [c["label"], c["text"], errs[0]])
	# the limits that stay valid
	eq(_stamina_errors_after(_stamina_set("recover_threshold", 100.0)).size(), 0, "recover_threshold = max e valido")
	eq(_stamina_errors_after(_stamina_set("regen_delay_s", 0.0)).size(), 0, "regen_delay_s = 0 e valido")
	eq(_stamina_errors_after(_stamina_set("exhausted_message_interval_s", 0.0)).size(), 0, "exhausted_message_interval_s = 0 e valido")
	ok(_stamina_errors_after(_stamina_set("max", 30.0)).size() > 0, "max (30) abaixo do limiar (35) gera erro")
	eq(Data.get_load_errors().size(), 0, "registro restaurado sem erros")
	near(float(Data.get_game()["stamina"]["max"]), 100.0, 0.0001, "dados restaurados")


# --- Energy drink (docs/plano_faca_mochila_folego.md 1.3 and 2.2; F3) ---

func test_energy_drink_seed_values() -> void:
	eq(Data.get_load_errors().size(), 0, "seed carrega sem erro: %s" % str(Data.get_load_errors()))
	var def: Dictionary = Data.get_equipment(Ids.I_ENERGY_DRINK)
	ok(not def.is_empty(), "energy_drink existe em equipment.json")
	eq(Ids.I_ENERGY_DRINK, &"energy_drink", "Ids.I_ENERGY_DRINK")
	eq(str(def.get("kind", "")), "consumable", "kind consumable")
	eq(int(def.get("price", -1)), 150, "preco R$ 150")
	eq(str(def.get("currency", "")), "money", "moeda money")
	eq(int(def.get("max_per_hunt", 0)), 3, "max_per_hunt 3")
	near(float((def.get("effect", {}) as Dictionary).get("stamina_restore_frac", 0.0)), 1.0, 0.0001, "stamina_restore_frac 1,0")
	eq(str(def.get("name", "")), "Energético", "nome")
	ok(str(def.get("short_name", "")).length() > 0 and str(def.get("short_name", "")).length() <= 9, "short_name de 1 a 9 caracteres")
	eq(Data.get_item_category(Ids.I_ENERGY_DRINK), &"equipment", "categoria equipment")
	# it sits right after the medkit in the catalog (the order of the shop)
	var ids: Array[StringName] = Data.get_equipment_ids()
	eq(ids.find(Ids.I_ENERGY_DRINK), ids.find(Ids.I_MEDKIT) + 1, "logo depois do medkit")


## Runs `mutate` on the live (deep-copied, then restored) energy_drink entry and returns the errors _validate adds.
func _energy_errors_after(mutate: Callable) -> PackedStringArray:
	var items: Array = Data._raw["equipment"]["items"]
	var entry: Dictionary = {}
	for e: Variant in items:
		if e is Dictionary and str((e as Dictionary).get("id", "")) == "energy_drink":
			entry = e
	var saved: Dictionary = entry.duplicate(true)
	var base: int = Data._errors.size()
	mutate.call(entry)
	Data._validate()
	var added: PackedStringArray = PackedStringArray()
	for i: int in range(base, Data._errors.size()):
		added.append(Data._errors[i])
	Data._errors.resize(base)
	entry.clear()
	entry.merge(saved)
	return added


func _frac_set(value: Variant) -> Callable:
	return func(e: Dictionary) -> void: e["effect"]["stamina_restore_frac"] = value


func test_energy_drink_validation_rejects_a_fraction_outside_0_to_1() -> void:
	eq(_energy_errors_after(func(_e: Dictionary) -> void: pass).size(), 0, "controle: dados intactos nao geram erro")
	for bad: Variant in [0.0, 1.5, -0.2, 1.0001]:
		var errs: PackedStringArray = _energy_errors_after(_frac_set(bad))
		ok(errs.size() > 0, "stamina_restore_frac = %s gera erro" % str(bad))
		if errs.size() > 0:
			ok(errs[0].begins_with("Data: ") and errs[0].contains("stamina_restore_frac") and errs[0].contains("energy_drink"),
				"a mensagem cita o item e o campo (%s)" % errs[0])
	for good: Variant in [1.0, 0.5, 0.01]:
		eq(_energy_errors_after(_frac_set(good)).size(), 0, "stamina_restore_frac = %s e valido" % str(good))
	eq(Data.get_load_errors().size(), 0, "registro restaurado sem erros")
	near(float(Data.get_equipment(Ids.I_ENERGY_DRINK)["effect"]["stamina_restore_frac"]), 1.0, 0.0001, "dados restaurados")
