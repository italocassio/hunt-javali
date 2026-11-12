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


func test_mato_grosso_totals_match_contract() -> void:
	var expected: Array[int] = [5, 8, 11, 15, 17]
	eq(Data.get_contract_count(&"mato_grosso"), 5, "5 contratos")
	for i: int in 5:
		var total: int = 0
		for g: Dictionary in Data.get_contract(&"mato_grosso", i).get("groups", []):
			total += (g.get("members", []) as Array).size()
		eq(total, expected[i], "total de javalis do contrato %d" % i)


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
	eq(int(Data.get_game().get("economy", {}).get("start_money", -1)), 500, "start_money")


func test_pix_config_has_placeholders_flagged() -> void:
	var cfg: Dictionary = Data.get_pix_config()
	for f: String in ["gateway", "pix_key", "merchant_name", "merchant_city", "redeem_secret"]:
		ok(cfg.has(f), "pix_config sem %s" % f)
	# Release gate: a placeholder secret/key must be replaced before publishing. Informational only.
	if str(cfg.get("redeem_secret", "")).begins_with("TROQUE"):
		print("INFO pix_config: redeem_secret ainda e o placeholder (trocar antes de publicar)")
	if str(cfg.get("pix_key", "")).begins_with("SUA-CHAVE"):
		print("INFO pix_config: pix_key ainda e o placeholder (DonationService.is_pix_configured() == false)")
