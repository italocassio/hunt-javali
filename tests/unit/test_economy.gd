extends "res://tests/lib/test_case.gd"
## Wallet, Inventory, Shop, RewardCalculator, Progression and Profile hunt bridge.


# --- Wallet ---

func test_wallet_basic() -> void:
	var w: Wallet = Wallet.new()
	w.add(100, Ids.MONEY)
	w.add(7, Ids.GOLD)
	eq(w.money, 100, "money")
	eq(w.gold, 7, "gold")
	ok(w.can_afford(100, Ids.MONEY), "can_afford exato")
	ok(not w.can_afford(101, Ids.MONEY), "nao paga 101")
	ok(not w.can_afford(-1, Ids.MONEY), "preco negativo nao e acessivel")
	ok(w.spend(40, Ids.MONEY), "gasta 40")
	eq(w.money, 60, "saldo apos gasto")
	ok(not w.spend(61, Ids.MONEY), "gasto sem saldo recusado")
	eq(w.money, 60, "saldo intacto apos recusa")
	ok(w.spend(60, Ids.MONEY), "gasta tudo")
	eq(w.money, 0, "zero")
	ok(not w.spend(1, Ids.MONEY), "gastar 1 com saldo 0")
	eq(w.gold, 7, "ouro independente")


func test_wallet_negative_and_overflow() -> void:
	expect_errors()
	var w: Wallet = Wallet.new()
	w.add(-50, Ids.MONEY)
	eq(w.money, 0, "add negativo ignorado")
	ok(not w.spend(-5, Ids.MONEY), "spend negativo recusado")
	eq(w.money, 0, "spend negativo nao credita")
	w.add(Wallet.MAX_BALANCE, Ids.MONEY)
	w.add(Wallet.MAX_BALANCE, Ids.MONEY)
	eq(w.money, Wallet.MAX_BALANCE, "saldo satura em MAX_BALANCE")
	var f: Wallet = Wallet.from_dict({"money": -5, "gold": "x"})
	eq(f.money, 0, "from_dict negativo -> 0")
	eq(f.gold, 0, "from_dict tipo errado -> 0")
	var g: Wallet = Wallet.from_dict({"money": 1.0e30, "gold": NAN})
	eq(g.money, Wallet.MAX_BALANCE, "from_dict gigante satura")
	eq(g.gold, 0, "from_dict NaN -> 0")


# --- Inventory ---

func test_inventory_add_remove() -> void:
	expect_errors()
	var inv: Inventory = Inventory.new()
	inv.add_item(Ids.W_SHOTGUN_12, 5)
	eq(inv.get_count(Ids.W_SHOTGUN_12), 1, "arma nao acumula")
	ok(inv.owns(Ids.W_SHOTGUN_12), "possui arma")
	inv.add_item(Ids.D_DOGO, 1)
	ok(inv.owns(Ids.D_DOGO), "possui cao")
	inv.add_item(Ids.I_MEDKIT, 2)
	inv.add_item(Ids.I_MEDKIT, 3)
	eq(inv.get_count(Ids.I_MEDKIT), 5, "consumivel acumula")
	inv.add_item(Ids.I_BINOCULARS, 4)
	eq(inv.get_count(Ids.I_BINOCULARS), 1, "equipamento fixo limita a 1")
	inv.add_item(Ids.I_MEDKIT, 0)
	inv.add_item(Ids.I_MEDKIT, -3)
	eq(inv.get_count(Ids.I_MEDKIT), 5, "quantidade <= 0 ignorada")
	inv.add_item(&"nao_existe", 1)
	eq(inv.get_count(&"nao_existe"), 0, "id desconhecido nao entra")
	ok(inv.remove_item(Ids.I_MEDKIT, 2), "remove 2")
	eq(inv.get_count(Ids.I_MEDKIT), 3, "restam 3")
	ok(not inv.remove_item(Ids.I_MEDKIT, 4), "remove 4 recusado")
	eq(inv.get_count(Ids.I_MEDKIT), 3, "intacto")
	ok(not inv.remove_item(Ids.I_MEDKIT, -1), "remover negativo recusado")
	ok(inv.remove_item(Ids.I_MEDKIT, 3), "remove tudo")
	ok(not inv.owns(Ids.I_MEDKIT), "nao possui mais")


func test_inventory_prunes_loadout_when_item_runs_out() -> void:
	var inv: Inventory = Inventory.new()
	inv.add_item(Ids.I_CORN_BAIT, 1)
	inv.loadout_items = [Ids.I_CORN_BAIT]
	inv.remove_item(Ids.I_CORN_BAIT, 1)
	eq(inv.loadout_items.size(), 0, "loadout limpo ao acabar o item")


func test_inventory_roundtrip() -> void:
	var inv: Inventory = Inventory.new()
	inv.add_item(Ids.W_CARBINE_22, 1)
	inv.add_item(Ids.W_RIFLE_308, 1)
	inv.add_item(Ids.D_CARAMELO, 1)
	inv.add_item(Ids.I_MEDKIT, 3)
	inv.loadout_weapons = [Ids.W_CARBINE_22, Ids.W_RIFLE_308]
	inv.loadout_dog = Ids.D_CARAMELO
	inv.loadout_items = [Ids.I_MEDKIT]
	var back: Inventory = Inventory.from_dict(JSON.parse_string(JSON.stringify(inv.to_dict())))
	eq(back.owned_weapons, inv.owned_weapons, "armas")
	eq(back.owned_dogs, inv.owned_dogs, "caes")
	eq(back.get_count(Ids.I_MEDKIT), 3, "medkits")
	eq(back.loadout_weapons, inv.loadout_weapons, "loadout armas")
	eq(back.loadout_dog, Ids.D_CARAMELO, "loadout cao")


# --- Shop ---

func _shop_world(money: int, gold: int = 0) -> Array:
	var w: Wallet = Wallet.new()
	w.money = money
	w.gold = gold
	var inv: Inventory = Inventory.new()
	return [w, inv]


func test_shop_insufficient_funds() -> void:
	var wi: Array = _shop_world(int(Data.get_weapon(Ids.W_SHOTGUN_12)["price"]) - 1)
	eq(Shop.buy(Ids.W_SHOTGUN_12, wi[0], wi[1]), &"insufficient_funds", "sem saldo")
	eq(wi[0].money, int(Data.get_weapon(Ids.W_SHOTGUN_12)["price"]) - 1, "saldo intacto")
	ok(not wi[1].owns(Ids.W_SHOTGUN_12), "item nao entregue")
	eq(Shop.check(Ids.W_SHOTGUN_12, wi[0], wi[1]), &"insufficient_funds", "check coerente")


func test_shop_exact_price_buys_and_already_owned() -> void:
	var price: int = int(Data.get_weapon(Ids.W_SHOTGUN_12)["price"])
	var wi: Array = _shop_world(price)
	eq(Shop.buy(Ids.W_SHOTGUN_12, wi[0], wi[1]), &"ok", "saldo exato compra")
	eq(wi[0].money, 0, "saldo zerado")
	ok(wi[1].owns(Ids.W_SHOTGUN_12), "item entregue")
	wi[0].money = price * 3
	eq(Shop.buy(Ids.W_SHOTGUN_12, wi[0], wi[1]), &"already_owned", "ja possui")
	eq(wi[0].money, price * 3, "nao cobra duas vezes")


func test_shop_consumable_max() -> void:
	var max_owned: int = int(Data.get_game().get("shop", {}).get("max_consumable_owned", 9))
	var price: int = int(Data.get_equipment(Ids.I_CORN_BAIT)["price"])
	var wi: Array = _shop_world(price * (max_owned + 3))
	for i: int in max_owned:
		eq(Shop.buy(Ids.I_CORN_BAIT, wi[0], wi[1]), &"ok", "compra %d" % (i + 1))
	eq(wi[1].get_count(Ids.I_CORN_BAIT), max_owned, "estoque no maximo")
	var money: int = wi[0].money
	eq(Shop.buy(Ids.I_CORN_BAIT, wi[0], wi[1]), &"max_reached", "alem do maximo")
	eq(wi[0].money, money, "nao cobra alem do maximo")


func test_shop_gold_item_uses_gold_not_money() -> void:
	var price: int = int(Data.get_weapon(Ids.W_RIFLE_338)["price"])
	eq(str(Data.get_weapon(Ids.W_RIFLE_338)["currency"]), "gold", ".338 e item de ouro")
	var wi: Array = _shop_world(99999999, price - 1)
	eq(Shop.buy(Ids.W_RIFLE_338, wi[0], wi[1]), &"insufficient_funds", "dinheiro nao compra item de ouro")
	wi[0].gold = price
	eq(Shop.buy(Ids.W_RIFLE_338, wi[0], wi[1]), &"ok", "ouro suficiente")
	eq(wi[0].gold, 0, "ouro gasto")
	eq(wi[0].money, 99999999, "dinheiro intacto")


func test_shop_unknown_item() -> void:
	expect_errors()
	var wi: Array = _shop_world(1000)
	eq(Shop.buy(&"nao_existe", wi[0], wi[1]), &"unknown_item", "id desconhecido")
	eq(Shop.check(&"", wi[0], wi[1]), &"unknown_item", "id vazio")
	eq(wi[0].money, 1000, "intacto")


# --- RewardCalculator ---

func test_reward_example_from_contract_1782() -> void:
	## Formula test with fixed inputs (the section 9.6 example); independent of data/ balance.
	var boar: Dictionary = {"value_per_kg": 6.0}
	var rules: Dictionary = {"reward": {"clean_zones": ["head", "vital"], "clean_kill_mult": 1.25, "one_shot_mult": 1.5}}
	var contract: Dictionary = {"reward_mult": 1.2}
	eq(RewardCalculator.kill_reward(boar, rules, 132.0, Ids.ZONE_VITAL, true, contract), 1782, "exemplo da secao 9.6")
	eq(RewardCalculator.kill_reward(boar, rules, 132.0, Ids.ZONE_BODY, false, contract), int(roundf(132.0 * 6.0 * 1.2)), "sem bonus")


func test_reward_modifiers() -> void:
	var boar: Dictionary = Data.get_boar_type(Ids.BOAR)
	var rules: Dictionary = Data.get_boar_rules()
	var c0: Dictionary = Data.get_contract(&"mato_grosso", 0)
	var plain: int = RewardCalculator.kill_reward(boar, rules, 100.0, Ids.ZONE_BODY, false, c0)
	eq(plain, int(roundf(100.0 * float(boar["value_per_kg"]) * float(c0["reward_mult"]))), "tiro no corpo sem bonus")
	var clean: int = RewardCalculator.kill_reward(boar, rules, 100.0, Ids.ZONE_VITAL, false, c0)
	var clean_mult: float = float(rules["reward"]["clean_kill_mult"])
	eq(clean, int(roundf(float(plain) * clean_mult)), "tiro limpo multiplica")
	ok(clean > plain, "limpo paga mais")
	var one: int = RewardCalculator.kill_reward(boar, rules, 100.0, Ids.ZONE_BODY, true, c0)
	ok(one > plain, "um tiro paga mais")
	eq(RewardCalculator.kill_reward(boar, rules, 0.0, Ids.ZONE_VITAL, true, c0), 0, "peso 0 = R$ 0")
	ok(RewardCalculator.kill_reward(boar, rules, -50.0, Ids.ZONE_VITAL, true, c0) >= 0, "peso negativo nunca paga negativo")
	eq(RewardCalculator.kill_reward({}, {}, 100.0, &"", false, {}), 0, "dicionarios vazios nao quebram")


func test_contract_bonus() -> void:
	var c: Dictionary = Data.get_contract(&"mato_grosso", 0)
	var bonus: int = int(c["bonus_money"])
	eq(RewardCalculator.contract_bonus(c, 100.0), bonus, "lavoura 100%")
	eq(RewardCalculator.contract_bonus(c, 50.0), int(roundf(bonus * 0.5)), "lavoura 50%")
	eq(RewardCalculator.contract_bonus(c, 0.0), 0, "lavoura 0%")
	eq(RewardCalculator.contract_bonus(c, 250.0), bonus, "satura em 100%")
	eq(RewardCalculator.contract_bonus(c, -20.0), 0, "negativo -> 0")
	eq(RewardCalculator.contract_bonus({}, 100.0), 0, "sem contrato")


# --- Progression ---

func test_progression_unlock_and_completion() -> void:
	var p: Progression = Progression.new()
	var m: StringName = &"mato_grosso"
	eq(p.unlocked_count(m), 1, "so o primeiro liberado")
	ok(p.is_unlocked(m, 0), "0 liberado")
	ok(not p.is_unlocked(m, 1), "1 trancado")
	ok(not p.is_unlocked(m, -1), "-1 nunca")
	ok(not p.is_completed(m, 0), "0 nao concluido")
	eq(p.best_crop_pct(m, 0), -1.0, "melhor lavoura sem vitoria")
	p.mark_won(m, 0, 64.0)
	ok(p.is_completed(m, 0), "0 concluido")
	ok(p.is_unlocked(m, 1), "1 liberado apos vencer 0")
	eq(p.best_crop_pct(m, 0), 64.0, "melhor lavoura")
	p.mark_won(m, 0, 30.0)
	eq(p.best_crop_pct(m, 0), 64.0, "nao piora o recorde")
	p.mark_won(m, 0, 90.0)
	eq(p.best_crop_pct(m, 0), 90.0, "melhora o recorde")
	p.mark_won(m, 0, 40.0)
	eq(p.unlocked_count(m), 2, "rejogar o 0 nao libera o 2")
	p.mark_won(m, 1, 100.0)
	eq(p.unlocked_count(m), 3, "vencer 1 libera 2")
	p.mark_won(m, 4, 10.0)
	eq(p.unlocked_count(m), 5, "nunca passa do ultimo contrato")
	ok(not p.is_unlocked(m, 5), "contrato 5 nao existe")


func test_progression_invalid_input() -> void:
	var p: Progression = Progression.new()
	p.mark_won(&"mato_grosso", 99, 50.0)
	p.mark_won(&"mato_grosso", -1, 50.0)
	p.mark_won(&"pantanal", 0, 50.0)   # unavailable
	p.mark_won(&"nao_existe", 0, 50.0)
	eq(p.unlocked_count(&"mato_grosso"), 1, "entradas invalidas ignoradas")
	eq(p.unlocked_count(&"pantanal"), 0, "mapa indisponivel nao tem contratos")
	eq(p.unlocked_count(&"nao_existe"), 0, "mapa inexistente")
	ok(not p.is_completed(&"pantanal", 0), "indisponivel nao concluido")
	p.mark_won(&"mato_grosso", 0, 500.0)
	eq(p.best_crop_pct(&"mato_grosso", 0), 100.0, "lavoura limitada a 100")


func test_progression_roundtrip() -> void:
	var p: Progression = Progression.new()
	p.mark_won(&"mato_grosso", 0, 77.0)
	p.mark_won(&"mato_grosso", 1, 12.5)
	var back: Progression = Progression.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	eq(back.unlocked_count(&"mato_grosso"), 3, "liberados")
	eq(back.best_crop_pct(&"mato_grosso", 1), 12.5, "melhor lavoura 1")
	var junk: Progression = Progression.from_dict({"mato_grosso": {"unlocked": "x", "best_crop_pct": 5}})
	eq(junk.unlocked_count(&"mato_grosso"), 1, "save com tipos errados cai no padrao")


# --- Profile bridge ---

func test_profile_starts_with_start_money() -> void:
	## Package B reported get_money() == 0 right after reset_progress(); the expected value is start_money (500).
	fresh_profile()
	eq(Profile.get_money(), int(Data.get_game()["economy"]["start_money"]), "Profile.get_money() apos reset_progress()")
	eq(Profile.get_gold(), 0, "ouro inicial")
	ok(Profile.owns(Ids.W_CARBINE_22), "carabina inicial")
	eq(Profile.get_item_count(Ids.I_MEDKIT), 1, "kit medico inicial")


func test_profile_buy_and_can_buy() -> void:
	fresh_profile()
	eq(Profile.can_buy(Ids.W_SHOTGUN_12), &"insufficient_funds", "can_buy sem saldo")
	eq(Profile.buy(Ids.W_SHOTGUN_12), &"insufficient_funds", "buy sem saldo")
	eq(Profile.get_money(), start_money(), "saldo intacto")
	ok(start_money() < int(Data.get_weapon(Ids.W_SHOTGUN_12)["price"]), "pre-condicao: saldo inicial nao compra a espingarda")
	# Price comes from data so balancing changes do not break this test.
	var price: int = int(Data.get_weapon(Ids.W_SHOTGUN_12)["price"])
	Profile.add_money(price)
	var before: int = Profile.get_money()
	eq(Profile.buy(Ids.W_SHOTGUN_12), &"ok", "buy ok")
	eq(Profile.get_money(), before - price, "cobrou o preco da arma")
	eq(Profile.can_buy(Ids.W_SHOTGUN_12), &"already_owned", "can_buy apos comprar")
	var rec: Dictionary = record_signal(GameEvents.wallet_changed)
	Profile.add_money(1)
	eq(rec["count"], 1, "wallet_changed emitido")
	# the purchase persisted
	var raw: Dictionary = SaveService.read("user://test_save.json")
	ok((raw.get("inventory", {}).get("weapons", []) as Array).has("shotgun_12"), "compra gravada em disco")


func test_profile_loadout_rules() -> void:
	fresh_profile()
	ok(not Profile.set_loadout_weapon(1, Ids.W_SHOTGUN_12), "nao equipa arma que nao tem")
	Profile.add_money(int(Data.get_weapon(Ids.W_SHOTGUN_12)["price"]))
	Profile.buy(Ids.W_SHOTGUN_12)
	ok(Profile.set_loadout_weapon(1, Ids.W_SHOTGUN_12), "equipa arma comprada no slot 1")
	eq(Profile.get_loadout_weapons()[1], Ids.W_SHOTGUN_12, "slot 1")
	ok(not Profile.set_loadout_dog(Ids.D_CARAMELO), "nao equipa cao que nao tem")
	var req: HuntRequest = Profile.build_hunt_request(&"mato_grosso", 0)
	eq(req.weapon_ids, [Ids.W_CARBINE_22, Ids.W_SHOTGUN_12] as Array[StringName], "request leva as 2 armas")
	eq(req.dog_id, &"", "sem cao")
	ok(req.item_ids.has(Ids.I_MEDKIT), "request leva o medkit equipado")
	eq(req.get_item_count(Ids.I_MEDKIT), 1, "1 medkit")


func test_profile_apply_hunt_result() -> void:
	fresh_profile()
	var r: HuntResult = HuntResult.new()
	r.outcome = HuntResult.Outcome.VICTORY
	r.map_id = &"mato_grosso"
	r.contract_index = 0
	r.boars_total = 1
	r.money_from_kills = 300
	r.contract_bonus = 800
	r.total_money = 1100
	r.crop_health_pct = 55.0
	var k: KillInfo = KillInfo.new()
	k.weight_kg = 77.0
	r.kills.append(k)
	r.consumables_used[Ids.I_MEDKIT] = 1
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 1100, "pago")
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 1100, "mesmo objeto aplicado 2x nao paga de novo")
	ok(Profile.is_contract_unlocked(&"mato_grosso", 1), "contrato 1 liberado")
	eq(Profile.get_best_crop_pct(&"mato_grosso", 0), 55.0, "melhor lavoura")
	eq(Profile.get_item_count(Ids.I_MEDKIT), 0, "medkit consumido")
	var st: Dictionary = Profile.get_stats()
	eq(int(st["hunts_played"]), 1, "hunts_played")
	eq(int(st["hunts_won"]), 1, "hunts_won")
	eq(int(st["boars_killed"]), 1, "boars_killed")
	eq(float(st["heaviest_kg"]), 77.0, "heaviest_kg")
	# defeat: pays only the kills, no unlock
	var d: HuntResult = HuntResult.new()
	d.outcome = HuntResult.Outcome.DEFEAT_CROP
	d.map_id = &"mato_grosso"
	d.contract_index = 1
	d.total_money = 40
	var m1: int = Profile.get_money()
	Profile.apply_hunt_result(d)
	eq(Profile.get_money(), m1 + 40, "derrota paga so os abates")
	ok(not Profile.is_contract_completed(&"mato_grosso", 1), "derrota nao conclui")
	eq(int(Profile.get_stats()["hunts_won"]), 1, "derrota nao conta vitoria")
	# hostile results
	var neg: HuntResult = HuntResult.new()
	neg.total_money = -500
	var m2: int = Profile.get_money()
	Profile.apply_hunt_result(neg)
	eq(Profile.get_money(), m2, "total_money negativo nao debita")
	Profile.apply_hunt_result(null)
	eq(Profile.get_money(), m2, "resultado nulo ignorado")


func test_profile_kill_reward_unknown_type() -> void:
	fresh_profile()
	eq(Profile.kill_reward(&"nao_existe", 100.0, Ids.ZONE_BODY, false, &"mato_grosso", 0), 0, "tipo desconhecido")
	eq(Profile.contract_bonus(&"mato_grosso", 0, 100.0), int(Data.get_contract(&"mato_grosso", 0)["bonus_money"]), "bonus pelo Profile")


# --- economy of the mode (docs/horda.md 3.2 and 10.1) ---

func test_horde_economy_vectors() -> void:
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true), 217, "macho 132 kg, vital, um tiro = R$ 217")
	eq(Profile.horde_bonus(87.0), 2610, "bonus com 87% de estoque = R$ 2610")
	eq(Profile.horde_bonus(100.0), int(Data.get_horde()["victory_bonus_money"]), "100% = bonus cheio")
	eq(Profile.horde_bonus(0.0), 0, "0% = nada")
	eq(Profile.horde_bonus(-5.0), 0, "negativo = nada")
	eq(Profile.horde_bonus(300.0), int(Data.get_horde()["victory_bonus_money"]), "satura em 100%")
	eq(Profile.horde_kill_reward(&"nao_existe", 100.0, &"vital", true), 0, "tipo desconhecido = 0")
	eq(Profile.horde_kill_reward(&"boar", 0.0, &"vital", true), 0, "peso 0 = 0")
	ok(Profile.horde_kill_reward(&"boar", -40.0, &"vital", true) >= 0, "peso negativo nunca paga negativo")


func test_horde_level2_economy_vectors() -> void:
	## docs/plano_horda_nivel2.md 3: level 2 pays half the kill prize (kill_reward_mult 0.5) and a bigger bonus.
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true, 2), 309, "nivel 2: macho 132 kg, vital, um tiro = R$ 309")
	eq(Profile.horde_bonus(87.0, 2), 4350, "nivel 2: bonus com 87% = R$ 4350")
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true, 1), 217, "nivel 1 explicito = R$ 217")
	eq(Profile.horde_bonus(87.0, 1), 2610, "nivel 1 explicito = R$ 2610")
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true), 217, "sem o parametro = nivel 1 (chamadas de hoje nao mudam)")
	eq(Profile.horde_bonus(87.0), 2610, "sem o parametro = nivel 1")
	eq(Profile.horde_bonus(100.0, 2), 5000, "nivel 2: 100% = bonus cheio")
	eq(Profile.horde_bonus(0.0, 2), 0, "nivel 2: 0% = nada")
	eq(Profile.horde_bonus(-5.0, 2), 0, "nivel 2: negativo = nada")
	eq(Profile.horde_bonus(300.0, 2), 5000, "nivel 2: satura em 100%")
	eq(Profile.horde_kill_reward(&"nao_existe", 100.0, &"vital", true, 2), 0, "nivel 2: tipo desconhecido = 0")
	eq(Profile.horde_kill_reward(&"boar", 0.0, &"vital", true, 2), 0, "nivel 2: peso 0 = 0")
	ok(Profile.horde_kill_reward(&"boar", -40.0, &"vital", true, 2) >= 0, "nivel 2: peso negativo nunca paga negativo")
	# levels that do not exist pay nothing (and do not crash)
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true, 0), 0, "nivel 0 = 0")
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true, 3), 0, "nivel 3 = 0")
	eq(Profile.horde_kill_reward(&"boar", 132.0, &"vital", true, -1), 0, "nivel negativo = 0")
	eq(Profile.horde_bonus(87.0, 0), 0, "bonus do nivel 0 = 0")
	eq(Profile.horde_bonus(87.0, 3), 0, "bonus do nivel 3 = 0")
	for type_id: StringName in Data.get_boar_type_ids():
		var w: float = float(Data.get_boar_type(type_id)["weight_max_kg"])
		var l1: int = Profile.horde_kill_reward(type_id, w, Ids.ZONE_VITAL, true, 1)
		var l2: int = Profile.horde_kill_reward(type_id, w, Ids.ZONE_VITAL, true, 2)
		# kill_reward_mult: 0.35 (level 1) -> 0.5 (level 2); the bonus and the multiplier are the level's own
		ok(l2 > l1, "%s: o abate do nivel 2 paga mais que o do nivel 1 (kill_reward_mult 0,5 contra 0,35): %d > %d" % [type_id, l2, l1])
		near(float(l2) / float(l1), 0.5 / 0.35, 0.05, "%s: razao entre os niveis acompanha kill_reward_mult" % type_id)


func test_horde_level2_victory_credits_once_and_never_progresses() -> void:
	fresh_profile()
	var before_unlocked: int = Profile.get_unlocked_contract_count(&"mato_grosso")
	var r: HuntResult = HuntResult.new()
	r.outcome = HuntResult.Outcome.VICTORY
	r.mode = Ids.MODE_HORDE
	r.horde_level = 2
	r.map_id = &"mato_grosso"
	r.counts_for_progression = false
	r.horde_wave_count = 8
	r.horde_waves_cleared = 8
	r.money_from_kills = 309
	r.contract_bonus = Profile.horde_bonus(87.0, 2)
	r.total_money = r.money_from_kills + r.contract_bonus
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 309 + 4350, "nivel 2: credita abates + bonus")
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 309 + 4350, "o mesmo resultado nao paga duas vezes")
	eq(Profile.get_unlocked_contract_count(&"mato_grosso"), before_unlocked, "horda nivel 2 nao libera contratos")
	eq(int(Profile.get_stats()["hunts_won"]), 1, "vitoria em horda nivel 2 conta em hunts_won")


func test_horde_kill_reward_is_a_fraction_of_the_contract_reward() -> void:
	## Contract-0 reward uses reward_mult; the horde multiplies by kill_reward_mult < 1: never pays more than a
	## contract kill at reward_mult 1 and scales like the same formula.
	var mult: float = float(Data.get_horde()["kill_reward_mult"])
	var boar: Dictionary = Data.get_boar_type(Ids.BOAR)
	var rules: Dictionary = Data.get_boar_rules()
	var full: int = RewardCalculator.kill_reward(boar, rules, 132.0, Ids.ZONE_VITAL, true, {"reward_mult": 1.0})
	var horde: int = Profile.horde_kill_reward(Ids.BOAR, 132.0, Ids.ZONE_VITAL, true)
	eq(horde, int(roundf(float(full) * mult)), "horda = formula x kill_reward_mult")
	ok(horde < full, "abate de horda paga menos que o de contrato")
	var body: int = Profile.horde_kill_reward(Ids.BOAR, 132.0, Ids.ZONE_BODY, false)
	ok(body < horde, "tiro no corpo paga menos que tiro limpo de um tiro")
	for type_id: StringName in Data.get_boar_type_ids():
		var w: float = float(Data.get_boar_type(type_id)["weight_max_kg"])
		ok(Profile.horde_kill_reward(type_id, w, Ids.ZONE_VITAL, true) > 0, "%s paga algo na horda" % type_id)


func test_horde_victory_credits_once_and_never_progresses() -> void:
	fresh_profile()
	var before_unlocked: int = Profile.get_unlocked_contract_count(&"mato_grosso")
	var r: HuntResult = HuntResult.new()
	r.outcome = HuntResult.Outcome.VICTORY
	r.mode = Ids.MODE_HORDE
	r.map_id = &"mato_grosso"
	r.contract_index = 0
	r.counts_for_progression = false
	r.horde_wave_count = 8
	r.horde_waves_cleared = 8
	r.money_from_kills = 1500
	r.contract_bonus = Profile.horde_bonus(87.0)
	r.total_money = r.money_from_kills + r.contract_bonus
	r.crop_health_pct = 87.0
	var k: KillInfo = KillInfo.new()
	k.weight_kg = 120.0
	r.kills.append(k)
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 1500 + 2610, "credita abates + bonus de defesa")
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 1500 + 2610, "o mesmo resultado nao paga duas vezes")
	eq(Profile.get_unlocked_contract_count(&"mato_grosso"), before_unlocked, "horda nao libera contratos")
	ok(not Profile.is_contract_completed(&"mato_grosso", 0), "horda nao conclui o contrato 0")
	eq(Profile.get_best_crop_pct(&"mato_grosso", 0), -1.0, "horda nao grava recorde de lavoura")
	eq(int(Profile.get_stats()["hunts_won"]), 1, "D10: vitoria em horda conta em hunts_won")
	eq(int(Profile.get_stats()["hunts_played"]), 1, "hunts_played")
	# a defeat pays only the kills and counts as played, not won
	var d: HuntResult = HuntResult.new()
	d.outcome = HuntResult.Outcome.DEFEAT_CROP
	d.mode = Ids.MODE_HORDE
	d.counts_for_progression = false
	d.total_money = 90
	var money1: int = Profile.get_money()
	Profile.apply_hunt_result(d)
	eq(Profile.get_money(), money1 + 90, "derrota paga so os abates")
	eq(int(Profile.get_stats()["hunts_won"]), 1, "derrota nao conta vitoria")
	eq(int(Profile.get_stats()["hunts_played"]), 2, "derrota conta como jogada")


# --- Network hunts: counts_for_progression and DISCONNECTED (docs/multiplayer.md sections 3.7 and 6.7) ---
# All of these use the temporary save of fresh_profile(), never user://save.json.

func _net_result(outcome: HuntResult.Outcome, contract_index: int, counts: bool, money: int = 500) -> HuntResult:
	var r: HuntResult = HuntResult.new()
	r.outcome = outcome
	r.map_id = &"mato_grosso"
	r.contract_index = contract_index
	r.total_money = money
	r.crop_health_pct = 70.0
	r.counts_for_progression = counts
	r.player_count = 2
	var k: KillInfo = KillInfo.new()
	k.weight_kg = 90.0
	r.kills.append(k)
	return r


func test_net_win_without_progression_pays_but_does_not_unlock_or_complete() -> void:
	fresh_profile()
	var progress: Dictionary = record_signal(GameEvents.progression_changed)
	var wallet: Dictionary = record_signal(GameEvents.wallet_changed)
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(_net_result(HuntResult.Outcome.VICTORY, 0, false, 640))
	eq(Profile.get_money(), money0 + 640, "vitoria em rede paga o total")
	ok(not Profile.is_contract_unlocked(&"mato_grosso", 1), "nao libera o contrato 1")
	ok(not Profile.is_contract_completed(&"mato_grosso", 0), "nao conclui o contrato 0")
	eq(Profile.get_unlocked_contract_count(&"mato_grosso"), 1, "so o primeiro continua liberado")
	eq(Profile.get_best_crop_pct(&"mato_grosso", 0), -1.0, "sem recorde de lavoura")
	eq(int(Profile.get_stats()["hunts_won"]), 1, "a vitoria conta nas estatisticas")
	eq(int(Profile.get_stats()["hunts_played"]), 1, "hunts_played")
	eq(int(Profile.get_stats()["boars_killed"]), 1, "boars_killed")
	eq(progress["count"], 0, "progression_changed nao e emitido")
	eq(wallet["count"], 1, "wallet_changed emitido uma vez")
	var raw: Dictionary = SaveService.read("user://test_save.json")
	eq(int(raw.get("wallet", {}).get("money", -1)), money0 + 640, "dinheiro gravado em disco")


func test_net_win_with_progression_unlocks() -> void:
	fresh_profile()
	var progress: Dictionary = record_signal(GameEvents.progression_changed)
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(_net_result(HuntResult.Outcome.VICTORY, 0, true, 640))
	eq(Profile.get_money(), money0 + 640, "paga")
	ok(Profile.is_contract_completed(&"mato_grosso", 0), "contrato 0 concluido")
	ok(Profile.is_contract_unlocked(&"mato_grosso", 1), "contrato 1 liberado")
	eq(Profile.get_best_crop_pct(&"mato_grosso", 0), 70.0, "recorde de lavoura")
	eq(progress["count"], 1, "progression_changed emitido uma vez")
	eq(int(Profile.get_stats()["hunts_won"]), 1, "hunts_won")


func test_net_win_without_progression_then_with_progression() -> void:
	## A friend's win on a locked contract must not "use up" the unlock: the player's own later win still counts.
	fresh_profile()
	Profile.apply_hunt_result(_net_result(HuntResult.Outcome.VICTORY, 1, false))
	ok(not Profile.is_contract_completed(&"mato_grosso", 1), "contrato 1 (trancado) nao conclui em rede sem progressao")
	eq(Profile.get_unlocked_contract_count(&"mato_grosso"), 1, "continua com 1 liberado")
	Profile.apply_hunt_result(_net_result(HuntResult.Outcome.VICTORY, 0, true))
	eq(Profile.get_unlocked_contract_count(&"mato_grosso"), 2, "a vitoria propria libera o 1")
	eq(int(Profile.get_stats()["hunts_won"]), 2, "as duas vitorias contam")


func test_net_disconnected_pays_but_is_not_a_win() -> void:
	fresh_profile()
	var money0: int = Profile.get_money()
	# counts_for_progression stays true here (the default): DISCONNECTED must not unlock anything by itself.
	var r: HuntResult = _net_result(HuntResult.Outcome.DISCONNECTED, 0, true, 275)
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 275, "DISCONNECTED paga os abates")
	eq(int(Profile.get_stats()["hunts_won"]), 0, "nao incrementa hunts_won")
	eq(int(Profile.get_stats()["hunts_played"]), 1, "conta como partida jogada")
	ok(not Profile.is_contract_completed(&"mato_grosso", 0), "nao conclui")
	ok(not Profile.is_contract_unlocked(&"mato_grosso", 1), "nao libera")
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0 + 275, "mesmo resultado aplicado 2x nao paga de novo")
	eq(int(Profile.get_stats()["hunts_played"]), 1, "nem conta 2x")


func test_net_other_outcomes_pay_and_do_not_progress() -> void:
	fresh_profile()
	for outcome: HuntResult.Outcome in [HuntResult.Outcome.DEFEAT_CROP, HuntResult.Outcome.DEFEAT_DEATH, HuntResult.Outcome.ABANDONED]:
		var before: int = Profile.get_money()
		Profile.apply_hunt_result(_net_result(outcome, 0, true, 90))
		eq(Profile.get_money(), before + 90, "%s paga os abates" % HuntResult.Outcome.keys()[outcome])
	ok(not Profile.is_contract_completed(&"mato_grosso", 0), "nenhuma derrota conclui")
	eq(int(Profile.get_stats()["hunts_won"]), 0, "nenhuma derrota conta vitoria")
	eq(int(Profile.get_stats()["hunts_played"]), 3, "tres partidas")


func test_net_result_hostile_values() -> void:
	## Negative money and a junk scoreboard coming out of a network hunt cannot debit or crash the profile.
	fresh_profile()
	var r: HuntResult = _net_result(HuntResult.Outcome.DISCONNECTED, 0, false, -900)
	r.scoreboard = [{"slot": 3, "name": "X", "kills": -1, "money": -5}]
	var money0: int = Profile.get_money()
	Profile.apply_hunt_result(r)
	eq(Profile.get_money(), money0, "total_money negativo nao debita")
	eq(int(Profile.get_stats()["hunts_played"]), 1, "ainda conta a partida")


# --- Backpack upgrade (docs/plano_faca_mochila_folego.md 1.1, 2.3 and 2.4) ---

func _backpack_price(level: int) -> int:
	return int(Data.get_upgrade_level_def(Ids.BACKPACK, level)["price"])


func _base_slots() -> int:
	return int(Data.get_game()["loadout"]["item_slots"])


## Gives the profile every equipment item (no payment) so a loadout of any size can be built from owned ids.
func _own_all_equipment() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in Data.get_equipment_ids():
		Profile._inventory.add_item(id, 1)
		ids.append(id)
	return ids


## Money exactly equal to `amount`: tops up (negative top-ups are ignored by the wallet, so the profile must be below).
func _set_money(amount: int) -> void:
	var missing: int = amount - Profile.get_money()
	ok(missing >= 0, "pre-condicao: saldo atual (%d) nao passa de %d" % [Profile.get_money(), amount])
	Profile.add_money(missing)
	eq(Profile.get_money(), amount, "saldo ajustado")


func test_backpack_new_profile_is_level_1_with_base_slots() -> void:
	fresh_profile()
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 1, "mochila nivel 1")
	eq(Profile.get_upgrade_max_level(Ids.BACKPACK), 4, "nivel maximo 4")
	eq(Profile.get_item_slots(), 3, "3 espacos no nivel 1")
	eq(Profile.get_item_slots(), _base_slots(), "= game.loadout.item_slots")
	eq(Profile.get_upgrade_level(&"foo"), 0, "id que nao e melhoria = 0")
	eq(Profile.get_upgrade_level(&""), 0, "id vazio = 0")
	eq(Profile.get_upgrade_max_level(&"foo"), 0, "max de id inexistente = 0")


func test_buy_backpack_level_2() -> void:
	fresh_profile()
	var items: Array[StringName] = _own_all_equipment()
	_set_money(_backpack_price(2))
	eq(_backpack_price(2), 2000, "preco do nivel 2 = R$ 2.000")
	eq(Profile.can_buy_upgrade(Ids.BACKPACK), &"ok", "can_buy_upgrade com saldo exato")
	var wallet: Dictionary = record_signal(GameEvents.wallet_changed)
	var inv: Dictionary = record_signal(GameEvents.inventory_changed)
	var load_rec: Dictionary = record_signal(GameEvents.loadout_changed)
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"ok", "compra ok")
	eq(Profile.get_money(), 0, "dinheiro -2000")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 2, "nivel 2")
	eq(Profile.get_item_slots(), 4, "4 espacos")
	eq(wallet["count"], 1, "wallet_changed emitido uma vez")
	eq(inv["count"], 1, "inventory_changed emitido uma vez")
	eq(load_rec["count"], 1, "loadout_changed emitido uma vez")
	eq(wallet["calls"][0][0], 0, "wallet_changed leva o saldo novo")
	var four: Array[StringName] = [items[0], items[1], items[2], items[3]]
	var five: Array[StringName] = [items[0], items[1], items[2], items[3], items[4]]
	ok(not Profile.set_loadout_items(five), "5 itens recusados no nivel 2")
	ok(Profile.set_loadout_items(four), "4 itens aceitos no nivel 2")
	eq(Profile.get_loadout_items(), four, "loadout com 4 itens")
	var raw: Dictionary = SaveService.read("user://test_save.json")
	eq(int(raw.get("upgrades", {}).get("backpack", -1)), 2, "nivel gravado em disco")
	eq(int(raw.get("version", -1)), 2, "versao do save continua 2")


func test_backpack_three_items_only_at_level_1() -> void:
	fresh_profile()
	var items: Array[StringName] = _own_all_equipment()
	var four: Array[StringName] = [items[0], items[1], items[2], items[3]]
	ok(not Profile.set_loadout_items(four), "4 itens recusados no nivel 1")
	var three: Array[StringName] = [items[0], items[1], items[2]]
	ok(Profile.set_loadout_items(three), "3 itens aceitos no nivel 1")


func test_backpack_all_levels_and_max_reached() -> void:
	fresh_profile()
	var items: Array[StringName] = _own_all_equipment()
	var total: int = _backpack_price(2) + _backpack_price(3) + _backpack_price(4)
	Profile.add_money(total)
	var money0: int = Profile.get_money()
	var spent: int = 0
	for level: int in range(2, 5):
		eq(Profile.buy_upgrade(Ids.BACKPACK), &"ok", "compra do nivel %d" % level)
		spent += _backpack_price(level)
		eq(Profile.get_upgrade_level(Ids.BACKPACK), level, "nivel %d" % level)
		eq(Profile.get_item_slots(), _base_slots() + level - 1, "espacos no nivel %d" % level)
		eq(Profile.get_money(), money0 - spent, "dinheiro apos o nivel %d" % level)
	eq(Profile.get_item_slots(), 6, "6 espacos no nivel 4")
	# six slots: six distinct owned items fit; a seventh does not (there are 7 equipment items today)
	var six: Array[StringName] = [items[0], items[1], items[2], items[3], items[4], items[5]]
	ok(Profile.set_loadout_items(six), "6 itens aceitos no nivel 4")
	if items.size() >= 7:
		var seven: Array[StringName] = six.duplicate()
		seven.append(items[6])
		ok(not Profile.set_loadout_items(seven), "7 itens recusados no nivel 4")
	# max level: refused, no charge, no event
	Profile.add_money(50000)
	var money: int = Profile.get_money()
	var wallet: Dictionary = record_signal(GameEvents.wallet_changed)
	var load_rec: Dictionary = record_signal(GameEvents.loadout_changed)
	eq(Profile.can_buy_upgrade(Ids.BACKPACK), &"max_reached", "can_buy_upgrade no maximo")
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"max_reached", "buy_upgrade no maximo")
	eq(Profile.get_money(), money, "nao cobra alem do maximo")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 4, "continua no nivel 4")
	eq(wallet["count"], 0, "sem wallet_changed na recusa")
	eq(load_rec["count"], 0, "sem loadout_changed na recusa")


func test_buy_backpack_without_funds_has_no_effect() -> void:
	fresh_profile()
	_set_money(_backpack_price(2) - 1)
	var wallet: Dictionary = record_signal(GameEvents.wallet_changed)
	var inv: Dictionary = record_signal(GameEvents.inventory_changed)
	var load_rec: Dictionary = record_signal(GameEvents.loadout_changed)
	eq(Profile.can_buy_upgrade(Ids.BACKPACK), &"insufficient_funds", "can_buy_upgrade sem saldo")
	eq(Profile.get_money(), _backpack_price(2) - 1, "can_buy_upgrade nao cobra")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 1, "can_buy_upgrade nao sobe o nivel")
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"insufficient_funds", "buy_upgrade sem saldo (R$ 1.999)")
	eq(Profile.get_money(), _backpack_price(2) - 1, "saldo intacto")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 1, "nivel intacto")
	eq(Profile.get_item_slots(), 3, "espacos intactos")
	eq(int(wallet["count"]) + int(inv["count"]) + int(load_rec["count"]), 0, "nenhum sinal na recusa")
	# gold does not pay for the backpack
	Profile.add_gold(99999)
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"insufficient_funds", "ouro nao compra a mochila")
	eq(Profile.get_gold(), 99999, "ouro intacto")


func test_buy_backpack_one_level_per_purchase() -> void:
	## Plenty of money buys exactly one level per call (never skips to the max).
	fresh_profile()
	Profile.add_money(_backpack_price(2) + _backpack_price(3) + _backpack_price(4) + 777)
	var money0: int = Profile.get_money()
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"ok", "compra")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 2, "so um nivel")
	eq(Profile.get_money(), money0 - _backpack_price(2), "cobra so o preco do proximo nivel")


func test_buy_upgrade_unknown_item() -> void:
	fresh_profile()
	Profile.add_money(99999)
	var money: int = Profile.get_money()
	for bad: StringName in [&"foo", &"", &"medkit", &"carbine_22"]:
		eq(Profile.can_buy_upgrade(bad), &"unknown_item", "can_buy_upgrade(%s)" % bad)
		eq(Profile.buy_upgrade(bad), &"unknown_item", "buy_upgrade(%s)" % bad)
	eq(Profile.get_money(), money, "saldo intacto")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 1, "mochila intacta")
	# an upgrade is not an item: Profile.buy does not sell it
	eq(Profile.can_buy(Ids.BACKPACK), &"unknown_item", "can_buy(backpack) = unknown_item")
	eq(Profile.buy(Ids.BACKPACK), &"unknown_item", "buy(backpack) = unknown_item")
	eq(Profile.get_money(), money, "saldo intacto apos buy(backpack)")


func test_reset_progress_resets_backpack() -> void:
	fresh_profile()
	Profile.add_money(_backpack_price(2))
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"ok", "compra")
	eq(Profile.get_item_slots(), 4, "4 espacos")
	Profile.reset_progress()
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 1, "reset volta ao nivel 1")
	eq(Profile.get_item_slots(), 3, "reset volta a 3 espacos")
	ok(Profile.get_loadout_items().size() <= 3, "loadout cabe nos 3 espacos")


func test_backpack_level_survives_reload() -> void:
	fresh_profile()
	Profile.add_money(_backpack_price(2) + _backpack_price(3))
	Profile.buy_upgrade(Ids.BACKPACK)
	Profile.buy_upgrade(Ids.BACKPACK)
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 3, "nivel 3")
	Profile.load_or_create()
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 3, "nivel 3 apos recarregar")
	eq(Profile.get_item_slots(), 5, "5 espacos apos recarregar")


func test_backpack_auto_equip_follows_slots() -> void:
	## A purchased equipment item goes to the loadout only while there is a free slot; a bigger backpack gives room.
	fresh_profile()
	var spare: Array[StringName] = []
	for id: StringName in Data.get_equipment_ids():
		var def: Dictionary = Data.get_equipment(id)
		if not Profile.owns(id) and str(def["currency"]) == "money" and str(def["kind"]) != "consumable":
			spare.append(id)
	ok(spare.size() >= 3, "pre-condicao: 3 passivos/ativos a comprar com dinheiro (%d)" % spare.size())
	Profile.add_money(100000)
	var before: int = Profile.get_loadout_items().size()
	ok(before < 3, "pre-condicao: o perfil novo nao enche a mochila (%d itens)" % before)
	for id: StringName in spare:
		eq(Profile.buy(id), &"ok", "compra de %s" % id)
	eq(Profile.get_loadout_items().size(), 3, "loadout para em 3 espacos no nivel 1")
	eq(Profile.buy_upgrade(Ids.BACKPACK), &"ok", "compra da mochila nivel 2")
	var left_out: StringName = &""
	for id: StringName in spare:
		if not Profile.get_loadout_items().has(id):
			left_out = id
			break
	ne(left_out, &"", "algum item comprado ficou de fora do loadout cheio")
	if left_out != &"":
		var picked: Array[StringName] = Profile.get_loadout_items()
		picked.append(left_out)
		ok(Profile.set_loadout_items(picked), "o item que ficou de fora cabe no 4o espaco")
		eq(Profile.get_loadout_items().size(), 4, "4 itens")


# --- Shop.check_upgrade / buy_upgrade and Inventory (no Profile, no save) ---

func test_shop_upgrade_rules_on_loose_objects() -> void:
	var wi: Array = _shop_world(_backpack_price(2) - 1)
	var w: Wallet = wi[0]
	var inv: Inventory = wi[1]
	eq(inv.get_upgrade_level(Ids.BACKPACK), 1, "Inventory novo: nivel 1")
	eq(Shop.check_upgrade(Ids.BACKPACK, w, inv), &"insufficient_funds", "check sem saldo")
	eq(Shop.buy_upgrade(Ids.BACKPACK, w, inv), &"insufficient_funds", "buy sem saldo")
	eq(w.money, _backpack_price(2) - 1, "saldo intacto")
	eq(inv.get_upgrade_level(Ids.BACKPACK), 1, "nivel intacto")
	w.money = _backpack_price(2)
	eq(Shop.check_upgrade(Ids.BACKPACK, w, inv), &"ok", "check com saldo exato")
	eq(w.money, _backpack_price(2), "check nao cobra")
	eq(Shop.buy_upgrade(Ids.BACKPACK, w, inv), &"ok", "buy com saldo exato")
	eq(w.money, 0, "saldo zerado")
	eq(inv.get_upgrade_level(Ids.BACKPACK), 2, "nivel 2")
	w.money = 99999
	eq(Shop.buy_upgrade(Ids.BACKPACK, w, inv), &"ok", "nivel 3")
	eq(Shop.buy_upgrade(Ids.BACKPACK, w, inv), &"ok", "nivel 4")
	var money: int = w.money
	eq(Shop.check_upgrade(Ids.BACKPACK, w, inv), &"max_reached", "check no maximo")
	eq(Shop.buy_upgrade(Ids.BACKPACK, w, inv), &"max_reached", "buy no maximo")
	eq(w.money, money, "nao cobra no maximo")
	eq(inv.get_upgrade_level(Ids.BACKPACK), 4, "continua no 4")
	eq(Shop.check_upgrade(&"foo", w, inv), &"unknown_item", "id desconhecido")
	eq(Shop.buy_upgrade(&"", w, inv), &"unknown_item", "id vazio")
	eq(Shop.buy_upgrade(&"medkit", w, inv), &"unknown_item", "um equipamento nao e melhoria")
	eq(w.money, money, "saldo intacto apos recusas")


func test_inventory_upgrades_roundtrip_and_defaults() -> void:
	var inv: Inventory = Inventory.new()
	eq(inv.get_upgrade_level(Ids.BACKPACK), 1, "sem bloco = nivel 1")
	inv.upgrades[Ids.BACKPACK] = 3
	var d: Dictionary = JSON.parse_string(JSON.stringify(inv.to_dict()))
	eq(int(d["upgrades"]["backpack"]), 3, "to_dict grava o bloco upgrades")
	var back: Inventory = Inventory.from_dict(d)
	eq(back.get_upgrade_level(Ids.BACKPACK), 3, "ida e volta mantem o nivel")
	var junk: Inventory = Inventory.from_dict({"upgrades": {"backpack": "x"}})
	eq(junk.get_upgrade_level(Ids.BACKPACK), 1, "valor de tipo errado nao entra")
	var not_dict: Inventory = Inventory.from_dict({"upgrades": [1, 2]})
	eq(not_dict.get_upgrade_level(Ids.BACKPACK), 1, "bloco de tipo errado = nivel 1")
