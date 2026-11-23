extends "res://tests/lib/test_case.gd"
## SaveService and Profile persistence: corrupted/empty/old/mistyped files, backup, sanitizing.

const PATH: String = "user://test_io.json"


func _clean() -> void:
	cleanup_test_files()


func test_new_save_shape() -> void:
	var s: Dictionary = SaveService.new_save()
	eq(s["format"], SaveService.FORMAT_NAME, "format")
	eq(s["version"], SaveService.CURRENT_VERSION, "version")
	eq(s["wallet"]["money"], start_money(), "dinheiro inicial")
	eq(s["wallet"]["gold"], 0, "ouro inicial")
	eq(s["inventory"]["weapons"], ["carbine_22"], "arma inicial")
	eq(s["loadout"]["weapons"][0], "carbine_22", "slot 0 equipado")
	eq(s["inventory"]["items"].get("medkit", 0), 1, "medkit inicial")
	for key: String in ["settings", "progression", "stats", "redeemed_codes", "saved_at_unix"]:
		contains(s, key, "chave %s" % key)
	eq(s["settings"], SaveService.default_settings(), "settings padrao")


func test_write_read_roundtrip_and_backup() -> void:
	_clean()
	var data: Dictionary = SaveService.new_save()
	ok(SaveService.write(PATH, data), "primeira escrita")
	ok(not FileAccess.file_exists(SaveService.backup_path(PATH)), "sem backup na primeira escrita")
	data["wallet"]["money"] = 777
	ok(SaveService.write(PATH, data), "segunda escrita")
	ok(FileAccess.file_exists(SaveService.backup_path(PATH)), "backup criado na segunda escrita")
	eq(int(SaveService.read(PATH)["wallet"]["money"]), 777, "leitura do arquivo novo")
	eq(int(SaveService.read(SaveService.backup_path(PATH))["wallet"]["money"]), start_money(), "backup guarda a versao anterior")
	_clean()


func test_read_missing_empty_garbage_and_non_object() -> void:
	_clean()
	eq(SaveService.read("user://nao_existe_xyz.json").size(), 0, "arquivo ausente")
	write_text(PATH, "")
	eq(SaveService.read(PATH).size(), 0, "arquivo vazio")
	write_text(PATH, "   \n\t ")
	eq(SaveService.read(PATH).size(), 0, "so espacos")
	write_text(PATH, "{not json at all")
	eq(SaveService.read(PATH).size(), 0, "JSON quebrado")
	write_text(PATH, "[1,2,3]")
	eq(SaveService.read(PATH).size(), 0, "JSON que nao e objeto")
	write_text(PATH, "\"texto\"")
	eq(SaveService.read(PATH).size(), 0, "JSON string")
	write_bytes(PATH, PackedByteArray([0xFF, 0xFE, 0x00, 0x80, 0x7B]))
	eq(SaveService.read(PATH).size(), 0, "bytes binarios")
	write_text(PATH, "{\"wallet\": {\"money\": 5}")   # truncated mid-write
	eq(SaveService.read(PATH).size(), 0, "arquivo truncado")
	_clean()


func test_corrupted_save_does_not_wipe_a_good_backup() -> void:
	# A corrupted primary must not overwrite the valid backup with garbage.
	_clean()
	var good: Dictionary = SaveService.new_save()
	good["wallet"]["money"] = 4242
	SaveService.write(PATH, good)
	good["wallet"]["money"] = 4343
	SaveService.write(PATH, good)   # backup now has 4242
	write_text(PATH, "{corrompido")
	var wrote: bool = SaveService.write(PATH, SaveService.new_save())
	ok(wrote, "escrita sobre arquivo corrompido funciona")
	eq(int(SaveService.read(SaveService.backup_path(PATH))["wallet"]["money"]), 4242, "backup valido preservado (corrompido nao copiado)")
	_clean()


func test_migrate() -> void:
	var cur: int = SaveService.CURRENT_VERSION
	eq(SaveService.migrate({})["version"], cur, "sem versao -> atual")
	eq(SaveService.migrate({"version": 0})["version"], cur, "versao 0 -> atual")
	eq(SaveService.migrate({"version": -7})["version"], cur, "versao negativa -> atual")
	eq(SaveService.migrate({"version": "abc"})["version"], cur, "versao string -> atual")
	eq(SaveService.migrate({"version": 99})["version"], 99, "versao futura mantida")
	eq(SaveService.migrate({"version": NAN})["version"], cur, "versao NaN -> atual")
	var original: Dictionary = {"version": 1, "x": [1]}
	var out: Dictionary = SaveService.migrate(original)
	(out["x"] as Array).append(2)
	eq((original["x"] as Array).size(), 1, "migrate nao altera a entrada")


func _drone_grant() -> int:
	return int(Data.get_game()["economy"]["start_items"]["scout_drone"])


func test_new_save_has_drones_equipped() -> void:
	var s: Dictionary = SaveService.new_save()
	eq(s["inventory"]["items"].get("scout_drone", 0), _drone_grant(), "drones iniciais")
	eq(s["inventory"]["items"].get("medkit", 0), 1, "medkit iniciais")
	ok((s["loadout"]["items"] as Array).has("scout_drone"), "drone equipado")
	ok((s["loadout"]["items"] as Array).has("medkit"), "medkit equipado")


func test_migrate_v1_grants_drones() -> void:
	var grant: int = _drone_grant()
	var s: Dictionary = SaveService.sanitize(SaveService.migrate({
		"version": 1, "inventory": {"items": {"medkit": 2}}, "loadout": {"items": ["medkit"]}}))
	eq(s["version"], 2, "versao 2")
	eq(s["inventory"]["items"]["scout_drone"], grant, "drones concedidos")
	eq(s["inventory"]["items"]["medkit"], 2, "medkit preservado")
	eq(s["loadout"]["items"], ["medkit", "scout_drone"], "drone equipado")
	# already owned drones are added to
	var t: Dictionary = SaveService.sanitize(SaveService.migrate({
		"version": 1, "inventory": {"items": {"scout_drone": 2}}, "loadout": {"items": []}}))
	eq(t["inventory"]["items"]["scout_drone"], 2 + grant, "soma ao que ja tinha")
	# all item slots taken: inventory grows, loadout unchanged
	var slots: int = int(Data.get_game()["loadout"]["item_slots"])
	var full: Array = ["medkit", "corn_bait", "binoculars", "leather_vest", "extra_ammo"].slice(0, slots)
	var inv_items: Dictionary = {}
	for id: String in full:
		inv_items[id] = 1
	var u: Dictionary = SaveService.sanitize(SaveService.migrate({
		"version": 1, "inventory": {"items": inv_items}, "loadout": {"items": full}}))
	eq(u["inventory"]["items"]["scout_drone"], grant, "drones no inventario com slots cheios")
	eq(u["loadout"]["items"], full, "loadout inalterado")


func test_migrate_v1_is_not_repeated() -> void:
	var grant: int = _drone_grant()
	var once: Dictionary = SaveService.migrate({"version": 1, "inventory": {"items": {"medkit": 1}}, "loadout": {"items": ["medkit"]}})
	var twice: Dictionary = SaveService.migrate(once)
	eq(twice["inventory"]["items"]["scout_drone"], grant, "migrar de novo nao concede")
	var v2: Dictionary = SaveService.migrate({"version": 2, "inventory": {"items": {"medkit": 1}}, "loadout": {"items": ["medkit"]}})
	ok(not v2["inventory"]["items"].has("scout_drone"), "save v2 nao recebe drones")


func test_migrate_malformed_does_not_break() -> void:
	var cases: Array = [
		{"version": 1}, {"version": 1, "inventory": 5, "loadout": "x"},
		{"version": 1, "inventory": {"items": [1, 2]}, "loadout": {"items": {"a": 1}}},
		{"version": 1, "inventory": {"items": {"scout_drone": "muitos"}}, "loadout": {"items": [null, 3]}},
		{"version": 1, "inventory": {"items": {"scout_drone": NAN}}},
	]
	for c: Dictionary in cases:
		var m: Dictionary = SaveService.migrate(c)
		eq(m["version"], 2, "versao 2 em %s" % str(c))
		var s: Dictionary = SaveService.sanitize(m)
		ok(s["inventory"]["items"] is Dictionary, "sanitize ok")
	var s0: Dictionary = SaveService.sanitize(SaveService.migrate({}))
	eq(s0["inventory"]["items"].get("medkit", 0), 1, "migrate({}) mantem medkit")
	eq(s0["inventory"]["items"].get("scout_drone", 0), _drone_grant(), "migrate({}) da drones")
	var s1: Dictionary = SaveService.sanitize(SaveService.migrate({"version": 1, "wallet": {"money": 5}}))
	eq(s1["inventory"]["items"].get("medkit", 0), 1, "sem inventario -> medkit inicial")
	eq(s1["inventory"]["items"].get("scout_drone", 0), _drone_grant(), "sem inventario -> drones iniciais")
	var m1: Dictionary = SaveService.migrate({"version": 1, "inventory": {"items": 7}})
	ok(not (m1["inventory"] as Dictionary).get("items") is Dictionary, "migracao nao cria items em bloco mal tipado")


func test_profile_migrates_and_persists_v1_save() -> void:
	_clean()
	Profile.set_save_path("user://test_save.json")
	write_text("user://test_save.json", JSON.stringify({
		"version": 1, "inventory": {"weapons": ["carbine_22"], "dogs": [], "items": {"medkit": 2}},
		"loadout": {"weapons": ["carbine_22", ""], "dog": "", "items": ["medkit"]}}))
	Profile.load_or_create()
	eq(Profile.get_item_count(&"scout_drone"), _drone_grant(), "drones no perfil")
	eq(int(SaveService.read("user://test_save.json")["version"]), 2, "save migrado gravado")
	_clean()


func test_profile_loads_save_with_malformed_version() -> void:
	for bad: Variant in [null, "abc", [1], {"v": 1}, true]:
		_clean()
		Profile.set_save_path("user://test_save.json")
		write_text("user://test_save.json", JSON.stringify({
			"version": bad, "inventory": {"weapons": ["carbine_22"], "dogs": [], "items": {"medkit": 2}},
			"loadout": {"weapons": ["carbine_22", ""], "dog": "", "items": ["medkit"]}}))
		Profile.load_or_create()
		eq(Profile.get_item_count(&"medkit"), 2, "perfil carregado com versao %s" % str(bad))
		eq(int(SaveService.read("user://test_save.json")["version"]), SaveService.CURRENT_VERSION, "versao %s regravada" % str(bad))
	_clean()


func test_sanitize_wrong_types() -> void:
	var s: Dictionary = SaveService.sanitize({
		"wallet": "oops", "inventory": 5, "loadout": [], "progression": "x", "stats": null,
		"redeemed_codes": {"a": 1}, "settings": 3, "version": "z", "saved_at_unix": "ontem",
	})
	eq(s["wallet"]["money"], start_money(), "carteira ruim -> padrao")
	eq(s["inventory"]["weapons"], ["carbine_22"], "inventario ruim -> arma inicial")
	eq(s["loadout"]["weapons"][0], "carbine_22", "loadout ruim")
	eq(s["redeemed_codes"], [], "codigos ruins")
	eq(s["settings"], SaveService.default_settings(), "settings ruins")
	eq(s["stats"]["hunts_played"], 0, "stats ruins")
	eq(s["version"], SaveService.CURRENT_VERSION, "versao ruim")


func test_sanitize_wallet_bounds() -> void:
	var s: Dictionary = SaveService.sanitize({"wallet": {"money": -100, "gold": 1.0e40}})
	eq(s["wallet"]["money"], 0, "dinheiro negativo -> 0")
	eq(s["wallet"]["gold"], Wallet.MAX_BALANCE, "ouro gigante satura")
	var t: Dictionary = SaveService.sanitize({"wallet": {"money": 12.9, "gold": "7"}})
	ok(t["wallet"]["money"] is int, "dinheiro vira int")
	eq(t["wallet"]["money"], 12, "12.9 -> 12")
	var u: Dictionary = SaveService.sanitize({"wallet": {"money": NAN, "gold": INF}})
	ok(u["wallet"]["money"] >= 0 and u["wallet"]["gold"] >= 0, "NaN/INF nao quebram")
	ok(u["wallet"]["money"] is int and u["wallet"]["gold"] is int, "NaN/INF viram int")


func test_sanitize_inventory_unknown_and_cheat_values() -> void:
	var s: Dictionary = SaveService.sanitize({
		"inventory": {"weapons": ["rifle_338", "arma_fantasma", 7, null, "rifle_338"], "dogs": ["dogo", "gato"],
			"items": {"medkit": 9999, "binoculars": 50, "fantasma": 3, "corn_bait": -4, "scout_drone": "muitos"}},
		"loadout": {"weapons": ["rifle_308", "rifle_338"], "dog": "foxhound", "items": ["medkit", "medkit", "corn_bait", "leather_vest", "binoculars", "thermal_scope"]},
	})
	var weapons: Array = s["inventory"]["weapons"]
	ok(weapons.has("rifle_338"), "arma valida mantida")
	ok(not weapons.has("arma_fantasma"), "arma fantasma removida")
	eq(weapons.count("rifle_338"), 1, "sem duplicata")
	ok(weapons.has("carbine_22"), "arma inicial sempre presente")
	eq(s["inventory"]["dogs"], ["dogo"], "caes validos")
	var max_c: int = int(Data.get_game()["shop"]["max_consumable_owned"])
	eq(s["inventory"]["items"]["medkit"], max_c, "consumivel limitado ao maximo")
	eq(s["inventory"]["items"]["binoculars"], 1, "passivo limitado a 1")
	ok(not s["inventory"]["items"].has("fantasma"), "item fantasma removido")
	ok(not s["inventory"]["items"].has("corn_bait"), "quantidade negativa removida")
	ok(not s["inventory"]["items"].has("scout_drone"), "quantidade string removida")
	var lw: Array = s["loadout"]["weapons"]
	eq(lw.size(), 2, "2 slots de arma")
	ok(lw[0] == "" or weapons.has(lw[0]), "slot 0 so com arma possuida")
	ok(lw[1] == "" or weapons.has(lw[1]), "slot 1 so com arma possuida")
	ok(lw[0] != "rifle_308", "arma nao possuida nao entra no loadout")
	eq(s["loadout"]["dog"], "", "cao equipado que nao possui -> vazio")
	var item_slots: int = int(Data.get_game()["loadout"]["item_slots"])
	ok((s["loadout"]["items"] as Array).size() <= item_slots, "no maximo %d itens equipados" % item_slots)
	for id: Variant in s["loadout"]["items"]:
		ok(s["inventory"]["items"].has(id), "item equipado %s e possuido" % id)
	eq((s["loadout"]["items"] as Array).count("medkit"), 1, "sem item equipado em duplicata")


func test_sanitize_idempotent() -> void:
	var once: Dictionary = SaveService.sanitize({"wallet": {"money": 99}, "inventory": {"weapons": ["shotgun_12"]}})
	var twice: Dictionary = SaveService.sanitize(once)
	eq(JSON.stringify(once), JSON.stringify(twice), "sanitize(sanitize(x)) == sanitize(x)")
	var fresh: Dictionary = SaveService.new_save()
	eq(JSON.stringify(SaveService.sanitize(fresh)), JSON.stringify(fresh), "novo save ja e canonico")


func test_sanitize_settings() -> void:
	eq(SaveService.sanitize_setting("mouse_sensitivity", 99.0), 3.0, "sensibilidade limitada em cima")
	eq(SaveService.sanitize_setting("mouse_sensitivity", -1.0), 0.1, "sensibilidade limitada embaixo")
	eq(SaveService.sanitize_setting("mouse_sensitivity", "rapido"), 1.0, "tipo errado -> padrao")
	eq(SaveService.sanitize_setting("quality", "ultra"), "auto", "qualidade invalida")
	eq(SaveService.sanitize_setting("quality", "high"), "high", "qualidade valida")
	eq(SaveService.sanitize_setting("touch_controls", 5), "auto", "touch invalido")
	eq(SaveService.sanitize_setting("invert_y", "sim"), false, "bool com tipo errado")
	eq(SaveService.default_settings()["battery_saver"], "auto", "economia de bateria: padrao auto")
	eq(SaveService.sanitize_setting("battery_saver", "on"), "on", "economia valida")
	eq(SaveService.sanitize_setting("battery_saver", "talvez"), "auto", "economia invalida -> auto")
	eq(SaveService.sanitize_setting("battery_saver", true), "auto", "economia com tipo errado -> auto")
	var old: Dictionary = SaveService.sanitize({"settings": {"quality": "low"}})
	eq(old["settings"]["battery_saver"], "auto", "save antigo sem a chave ganha auto")
	var power: Dictionary = Data.get_game().get("power", {})
	ok(int(power.get("battery_saver_fps", 0)) > 0, "data/game.json define battery_saver_fps")
	ok(PowerManager.resolve_battery_saver("auto", true), "auto em modo toque liga")
	ok(not PowerManager.resolve_battery_saver("auto", false), "auto no PC desliga")
	ok(not PowerManager.resolve_battery_saver("off", true), "off vence o modo toque")
	ok(PowerManager.resolve_battery_saver("on", false), "on vence o PC")
	eq(PowerManager.target_max_fps(true, power), int(power["battery_saver_fps"]), "ligada: fps dos dados")
	eq(PowerManager.target_max_fps(false, power), 0, "desligada: sem limite")
	eq(SaveService.sanitize_setting("volume_master", 5.0), 1.0, "volume limitado a 1")
	eq(SaveService.sanitize_setting("volume_master", -5.0), 0.0, "volume limitado a 0")
	eq(SaveService.sanitize_setting("nao_existe", 1), null, "chave desconhecida -> null")
	var nan_value: Variant = SaveService.sanitize_setting("mouse_sensitivity", NAN)
	ok(is_finite(float(nan_value)), "NaN em sensibilidade vira valor finito (%s)" % str(nan_value))


func test_sanitize_codes_capped_and_unique() -> void:
	var many: Array = []
	for i: int in 700:
		many.append("CODE-%d" % i)
	many.append("CODE-1")
	many.append(5)
	many.append("")
	var s: Dictionary = SaveService.sanitize({"redeemed_codes": many})
	eq((s["redeemed_codes"] as Array).size(), SaveService.MAX_CODES, "lista de codigos limitada")


func test_profile_load_corrupted_save_starts_new_profile() -> void:
	expect_errors()
	_clean()
	Profile.set_save_path("user://test_save.json")
	write_text("user://test_save.json", "{{{{ corrompido")
	Profile.load_or_create()
	eq(Profile.get_money(), start_money(), "perfil novo apos save corrompido")
	ok(Profile.owns(Ids.W_CARBINE_22), "carabina inicial")
	ok(not SaveService.read("user://test_save.json").is_empty(), "save regravado valido")
	_clean()


func test_profile_load_empty_save() -> void:
	expect_errors()
	_clean()
	Profile.set_save_path("user://test_save.json")
	write_text("user://test_save.json", "")
	Profile.load_or_create()
	eq(Profile.get_money(), start_money(), "perfil novo apos save vazio")
	_clean()


func test_profile_recovers_from_backup() -> void:
	expect_errors()
	_clean()
	fresh_profile()
	Profile.add_money(1234)
	var backed_up: int = Profile.get_money()
	Profile.save()
	Profile.add_money(1)      # previous valid file becomes the backup
	Profile.save()
	write_text("user://test_save.json", "lixo")
	Profile.load_or_create()
	eq(Profile.get_money(), backed_up, "restaurou do backup")
	_clean()


func test_profile_persists_across_reload() -> void:
	_clean()
	fresh_profile()
	Profile.add_money(300)
	Profile.add_gold(25)
	Profile.buy(Ids.I_BINOCULARS)
	Profile.set_setting("volume_sfx", 0.25)
	Profile.mark_code_redeemed("jv-0050-aaaaaa-0000")
	Profile.save()
	var money: int = Profile.get_money()
	Profile.load_or_create()
	eq(Profile.get_money(), money, "dinheiro")
	eq(Profile.get_gold(), 25, "ouro")
	ok(Profile.is_code_redeemed("JV-0050-AAAAAA-0000"), "codigo marcado (normalizado)")
	eq(Profile.get_setting("volume_sfx"), 0.25, "setting")
	_clean()


func test_profile_old_version_and_mistyped_save_loads() -> void:
	expect_errors()
	_clean()
	Profile.set_save_path("user://test_save.json")
	write_text("user://test_save.json", JSON.stringify({
		"version": 1, "wallet": {"money": "muito", "gold": 3.7},
		"inventory": {"weapons": "carbine_22", "dogs": {"x": 1}, "items": []},
		"loadout": {"weapons": [1, 2, 3, 4], "dog": 9, "items": "medkit"},
		"progression": {"mato_grosso": {"unlocked": 99, "best_crop_pct": ["a", null, 50]}},
		"settings": {"quality": 7, "mouse_sensitivity": "x"},
	}))
	Profile.load_or_create()
	ok(Profile.get_money() >= 0, "dinheiro valido")
	eq(Profile.get_gold(), 3, "ouro 3.7 -> 3")
	ok(Profile.owns(Ids.W_CARBINE_22), "arma inicial garantida")
	ok(Profile.get_unlocked_contract_count(&"mato_grosso") <= Data.get_contract_count(&"mato_grosso"), "desbloqueios limitados")
	eq(Profile.get_setting("quality"), "auto", "qualidade invalida -> auto")
	var req: HuntRequest = Profile.build_hunt_request(&"mato_grosso", 0)
	ok(req.weapon_ids.size() >= 1, "request sempre tem arma")
	_clean()


func test_profile_settings_are_clamped_and_unknown_key_rejected() -> void:
	expect_errors()
	fresh_profile()
	Profile.set_setting("mouse_sensitivity", 50.0)
	eq(Profile.get_setting("mouse_sensitivity"), 3.0, "limitado")
	Profile.set_setting("chave_inexistente", 1)
	eq(Profile.get_setting("chave_inexistente"), null, "chave desconhecida rejeitada")


func test_save_never_touches_real_save_path() -> void:
	fresh_profile()
	Profile.add_money(1)
	Profile.save()
	ok(FileAccess.file_exists("user://test_save.json"), "gravou no caminho de teste")
	# Informational: the real save is not created by tests (only an earlier real run may have made it).
	cleanup_test_files()


# --- Upgrades block (docs/plano_faca_mochila_folego.md 2.4): migration by sanitize, version stays 2 ---

const UP_ITEMS: Array[String] = ["medkit", "binoculars", "leather_vest", "extra_ammo", "corn_bait", "scout_drone"]


## A save dictionary that owns every id of UP_ITEMS and equips the first `equipped` of them.
func _save_with_items(equipped: int, upgrades: Variant = null) -> Dictionary:
	var owned: Dictionary = {}
	for id: String in UP_ITEMS:
		owned[id] = 1
	var d: Dictionary = {
		"inventory": {"items": owned},
		"loadout": {"items": UP_ITEMS.slice(0, equipped)},
	}
	if upgrades != null:
		d["upgrades"] = upgrades
	return d


func test_new_save_has_backpack_level_1_and_version_2() -> void:
	var s: Dictionary = SaveService.new_save()
	contains(s, "upgrades", "bloco upgrades no save novo")
	eq(s["upgrades"], {"backpack": 1, "knife": 1}, "mochila e faca no nivel 1")
	eq(SaveService.CURRENT_VERSION, 2, "versao do save continua 2")
	eq(s["version"], 2, "versao gravada no save novo")
	eq(SaveService.item_slots_for_level(1), 3, "item_slots_for_level(1)")
	eq(SaveService.item_slots_for_level(2), 4, "item_slots_for_level(2)")
	eq(SaveService.item_slots_for_level(3), 5, "item_slots_for_level(3)")
	eq(SaveService.item_slots_for_level(4), 6, "item_slots_for_level(4)")
	eq(SaveService.item_slots_for_level(99), 3, "nivel fora da faixa = base")
	eq(SaveService.item_slots_for_level(0), 3, "nivel 0 = base")


func test_sanitize_without_upgrades_block_is_backpack_level_1() -> void:
	var s: Dictionary = SaveService.sanitize(_save_with_items(3))
	eq(s["upgrades"]["backpack"], 1, "bloco ausente = nivel 1")
	eq(s["loadout"]["items"], ["medkit", "binoculars", "leather_vest"], "loadout de 3 itens igual")
	eq(s["version"], 2, "versao 2")
	var four: Dictionary = SaveService.sanitize(_save_with_items(4))
	eq((four["loadout"]["items"] as Array).size(), 3, "save antigo com 4 itens cai em 3 (mochila nivel 1)")
	eq(four["loadout"]["items"], ["medkit", "binoculars", "leather_vest"], "os 3 primeiros")


func test_sanitize_upgrades_level_is_clamped_and_typed() -> void:
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": 9}))["upgrades"]["backpack"], 4, "9 -> 4")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": 4}))["upgrades"]["backpack"], 4, "4 fica 4")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": 2}))["upgrades"]["backpack"], 2, "2 fica 2")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": 0}))["upgrades"]["backpack"], 1, "0 -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": -7}))["upgrades"]["backpack"], 1, "negativo -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": "x"}))["upgrades"]["backpack"], 1, "texto -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": null}))["upgrades"]["backpack"], 1, "null -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": [3]}))["upgrades"]["backpack"], 1, "array -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"backpack": 3.0}))["upgrades"]["backpack"], 3, "3.0 -> 3")
	var nan_level: Variant = SaveService.sanitize(_save_with_items(0, {"backpack": NAN}))["upgrades"]["backpack"]
	ok(nan_level is int and int(nan_level) >= 1 and int(nan_level) <= 4, "NaN vira int valido (%s)" % str(nan_level))
	ok(SaveService.sanitize(_save_with_items(0, {"backpack": 9}))["upgrades"]["backpack"] is int, "nivel e int")
	for bad: Variant in ["texto", 5, [1, 2], null, true]:
		eq(SaveService.sanitize(_save_with_items(0, bad))["upgrades"]["backpack"], 1, "bloco de tipo errado (%s) = 1" % str(bad))


func test_sanitize_upgrades_unknown_ids_are_dropped() -> void:
	var s: Dictionary = SaveService.sanitize(_save_with_items(0, {"foo": 2, "backpack": 3, "knife": 4, "": 2}))
	eq(s["upgrades"].keys(), Data.get_upgrade_ids().map(func(id: StringName) -> String: return String(id)), "so os ids de Data.get_upgrade_ids()")
	ok(not (s["upgrades"] as Dictionary).has("foo"), "foo descartado")
	eq(s["upgrades"]["backpack"], 3, "mochila mantida")
	# since F4 the knife is in the data: its level survives the sanitize
	eq(s["upgrades"]["knife"], 4, "faca mantida (esta nos dados desde a F4)")
	eq(SaveService.sanitize(_save_with_items(0, {"foo": 2}))["upgrades"], {"backpack": 1, "knife": 1}, "so foo = tudo no nivel 1")


func test_sanitize_loadout_limit_follows_backpack_level() -> void:
	for level: int in range(1, 5):
		var s: Dictionary = SaveService.sanitize(_save_with_items(UP_ITEMS.size(), {"backpack": level}))
		var want: int = 3 + level - 1
		eq((s["loadout"]["items"] as Array).size(), want, "mochila nivel %d: %d itens" % [level, want])
		eq(s["loadout"]["items"], UP_ITEMS.slice(0, want), "mochila nivel %d: os %d primeiros" % [level, want])
	var l2: Dictionary = SaveService.sanitize(_save_with_items(5, {"backpack": 2}))
	eq(l2["loadout"]["items"], ["medkit", "binoculars", "leather_vest", "extra_ammo"], "nivel 2 com 5 itens -> os 4 primeiros")
	# the limit uses the SANITIZED level: a level 9 in the file is a level 4 (6 slots), not 9
	var l9: Dictionary = SaveService.sanitize(_save_with_items(UP_ITEMS.size(), {"backpack": 9}))
	eq((l9["loadout"]["items"] as Array).size(), 6, "nivel 9 vira 4: 6 itens, nunca mais")
	# a bad level falls back to 3 slots
	var bad: Dictionary = SaveService.sanitize(_save_with_items(5, {"backpack": "x"}))
	eq((bad["loadout"]["items"] as Array).size(), 3, "nivel ilegivel = 3 itens")


func test_sanitize_upgrades_is_idempotent() -> void:
	var once: Dictionary = SaveService.sanitize(_save_with_items(5, {"backpack": 3, "foo": 1}))
	var twice: Dictionary = SaveService.sanitize(once)
	eq(JSON.stringify(once), JSON.stringify(twice), "sanitize(sanitize(x)) == sanitize(x) com upgrades")
	eq(twice["upgrades"]["backpack"], 3, "nivel mantido")
	eq((twice["loadout"]["items"] as Array).size(), 5, "loadout mantido")


func test_migrate_v1_save_gets_backpack_level_1() -> void:
	var s: Dictionary = SaveService.sanitize(SaveService.migrate({
		"version": 1, "inventory": {"items": {"medkit": 1, "binoculars": 1, "leather_vest": 1, "extra_ammo": 1}},
		"loadout": {"items": ["medkit", "binoculars", "leather_vest", "extra_ammo"]}}))
	eq(s["version"], 2, "migra para 2")
	eq(s["upgrades"]["backpack"], 1, "save v1 nao tem mochila: nivel 1")
	eq((s["loadout"]["items"] as Array).size(), 3, "v1 continua com a base de 3 espacos")


func test_profile_loads_old_save_without_upgrades_block() -> void:
	_clean()
	Profile.set_save_path("user://test_save.json")
	var old: Dictionary = SaveService.new_save()
	old.erase("upgrades")
	old["inventory"]["items"] = {"medkit": 1, "binoculars": 1, "leather_vest": 1}
	old["loadout"]["items"] = ["medkit", "binoculars", "leather_vest"]
	write_text("user://test_save.json", JSON.stringify(old))
	Profile.load_or_create()
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 1, "save sem bloco abre com mochila nivel 1")
	eq(Profile.get_item_slots(), 3, "3 espacos")
	eq(Profile.get_loadout_items(), [&"medkit", &"binoculars", &"leather_vest"] as Array[StringName], "loadout igual ao do save")
	Profile.save()
	var raw: Dictionary = SaveService.read("user://test_save.json")
	eq(raw["upgrades"]["backpack"], 1, "o bloco passa a ser gravado")
	eq(raw["version"], 2, "versao gravada continua 2")
	_clean()


func test_profile_loads_save_with_bigger_backpack() -> void:
	_clean()
	Profile.set_save_path("user://test_save.json")
	var s: Dictionary = SaveService.new_save()
	s["upgrades"] = {"backpack": 3}
	s["inventory"]["items"] = {"medkit": 1, "binoculars": 1, "leather_vest": 1, "extra_ammo": 1, "corn_bait": 1}
	s["loadout"]["items"] = ["medkit", "binoculars", "leather_vest", "extra_ammo", "corn_bait"]
	write_text("user://test_save.json", JSON.stringify(s))
	Profile.load_or_create()
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 3, "nivel 3 lido")
	eq(Profile.get_item_slots(), 5, "5 espacos")
	eq(Profile.get_loadout_items().size(), 5, "os 5 itens equipados sobrevivem")
	_clean()


func test_profile_hostile_upgrades_blocks_do_not_break() -> void:
	_clean()
	Profile.set_save_path("user://test_save.json")
	for bad: Variant in [{"backpack": "x"}, {"backpack": 99}, {"foo": 2}, "lixo", [1, 2], 7, null]:
		var s: Dictionary = SaveService.new_save()
		s["upgrades"] = bad
		write_text("user://test_save.json", JSON.stringify(s))
		Profile.load_or_create()
		var level: int = Profile.get_upgrade_level(Ids.BACKPACK)
		ok(level >= 1 and level <= 4, "bloco %s: nivel %d na faixa 1..4" % [str(bad), level])
		ok(Profile.get_loadout_items().size() <= Profile.get_item_slots(), "bloco %s: loadout cabe na mochila" % str(bad))
	_clean()


func test_upgrades_roundtrip_through_disk() -> void:
	_clean()
	var data: Dictionary = SaveService.new_save()
	data["upgrades"]["backpack"] = 3
	ok(SaveService.write(PATH, data), "escrita")
	var back: Dictionary = SaveService.read(PATH)
	eq(back["upgrades"]["backpack"], 3, "nivel 3 ida e volta")
	eq(back["version"], 2, "versao 2")
	_clean()


# --- Knife level (docs/plano_faca_mochila_folego.md 2.4; F4) ---

func test_sanitize_f1_save_with_only_backpack_gains_knife_level_1() -> void:
	# a save written by 0.9.5..0.9.7 has only "backpack": the same sanitize adds "knife": 1, backpack untouched
	var s: Dictionary = SaveService.sanitize(_save_with_items(2, {"backpack": 3}))
	eq(s["upgrades"], {"backpack": 3, "knife": 1}, "save da F1 abre com faca nivel 1 e a mochila intacta")
	eq(s["version"], 2, "versao continua 2")
	var absent: Dictionary = SaveService.sanitize(_save_with_items(2))
	eq(absent["upgrades"]["knife"], 1, "sem o bloco: faca nivel 1")


func test_sanitize_knife_level_is_clamped_and_typed() -> void:
	eq(SaveService.sanitize(_save_with_items(0, {"knife": 9}))["upgrades"]["knife"], 4, "9 -> 4")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": 4}))["upgrades"]["knife"], 4, "4 fica 4")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": 2}))["upgrades"]["knife"], 2, "2 fica 2")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": 0}))["upgrades"]["knife"], 1, "0 -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": -3}))["upgrades"]["knife"], 1, "negativo -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": "x"}))["upgrades"]["knife"], 1, "texto -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": null}))["upgrades"]["knife"], 1, "null -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": [3]}))["upgrades"]["knife"], 1, "array -> 1")
	eq(SaveService.sanitize(_save_with_items(0, {"knife": 3.0}))["upgrades"]["knife"], 3, "3.0 -> 3")
	ok(SaveService.sanitize(_save_with_items(0, {"knife": 9}))["upgrades"]["knife"] is int, "nivel e int")
	# a broken knife level never touches the backpack level, and the other way around
	var mixed: Dictionary = SaveService.sanitize(_save_with_items(0, {"backpack": 2, "knife": "x"}))
	eq(mixed["upgrades"], {"backpack": 2, "knife": 1}, "faca com tipo errado nao derruba a mochila")
	for bad: Variant in ["lixo", [1, 2], 7, true]:
		eq(SaveService.sanitize(_save_with_items(0, bad))["upgrades"]["knife"], 1, "bloco de tipo errado (%s) = faca 1" % str(bad))


func test_sanitize_knife_does_not_change_the_loadout_limit() -> void:
	# the knife takes no backpack space: a level 4 knife with backpack level 1 still keeps only 3 items
	var s: Dictionary = SaveService.sanitize(_save_with_items(UP_ITEMS.size(), {"backpack": 1, "knife": 4}))
	eq((s["loadout"]["items"] as Array).size(), 3, "faca nivel 4 nao abre espaco de mochila")


func test_knife_roundtrip_through_disk_and_profile() -> void:
	_clean()
	var data: Dictionary = SaveService.new_save()
	data["upgrades"]["knife"] = 3
	ok(SaveService.write(PATH, data), "escrita")
	var back: Dictionary = SaveService.read(PATH)
	eq(back["upgrades"]["knife"], 3, "faca nivel 3 ida e volta")
	eq(back["upgrades"]["backpack"], 1, "mochila continua 1")
	eq(back["version"], 2, "versao gravada continua 2")
	_clean()
	# through the Profile: a F1 save (only "backpack") opens with knife 1 and is rewritten with both blocks
	Profile.set_save_path("user://test_save.json")
	var f1: Dictionary = SaveService.new_save()
	f1["upgrades"] = {"backpack": 2}
	write_text("user://test_save.json", JSON.stringify(f1))
	Profile.load_or_create()
	eq(Profile.get_upgrade_level(Ids.KNIFE), 1, "save da F1 abre com faca nivel 1")
	eq(Profile.get_upgrade_level(Ids.BACKPACK), 2, "mochila nivel 2 mantida")
	Profile.save()
	var raw: Dictionary = SaveService.read("user://test_save.json")
	eq((raw["upgrades"] as Dictionary).size(), 2, "o bloco gravado traz as duas melhorias")
	eq(int(raw["upgrades"]["backpack"]), 2, "mochila nivel 2 gravada")
	eq(int(raw["upgrades"]["knife"]), 1, "faca nivel 1 gravada")
	eq(raw["version"], 2, "versao gravada continua 2")
	# a stored knife level survives a reload
	var f4: Dictionary = SaveService.new_save()
	f4["upgrades"] = {"backpack": 1, "knife": 3}
	write_text("user://test_save.json", JSON.stringify(f4))
	Profile.load_or_create()
	eq(Profile.get_upgrade_level(Ids.KNIFE), 3, "faca nivel 3 lida")
	_clean()
