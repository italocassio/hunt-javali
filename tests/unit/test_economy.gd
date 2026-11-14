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
