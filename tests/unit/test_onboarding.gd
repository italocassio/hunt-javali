extends "res://tests/lib/test_case.gd"
## Onboarding (docs/arquitetura.md sections 6.3, 9.1, 9.3 and 10): game.onboarding / short_name data, the
## "onboarding.learned" block of the save (sanitize, old saves), and the three Profile methods.
## The hint logic itself (HintDirector) is not covered here.

const PATH: String = "user://test_save.json"


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

func _max_hunts() -> int:
	return int(Data.get_game().get("onboarding", {}).get("max_hunts", -1))


func _delete_save_files() -> void:
	for p: String in [PATH, SaveService.backup_path(PATH)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _read_file_dict() -> Dictionary:
	var parsed: Variant = JSON.parse_string(read_text(PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


func _file_learned() -> Array:
	var ob: Variant = _read_file_dict().get("onboarding")
	if ob is Dictionary and (ob as Dictionary).get("learned") is Array:
		return (ob as Dictionary)["learned"]
	return ["<sem bloco onboarding no arquivo>"]


func _played(count: int) -> void:
	## Raises stats.hunts_played by the real path: apply_hunt_result (every hunt ends there).
	for i: int in count:
		var r: HuntResult = HuntResult.new()
		r.outcome = HuntResult.Outcome.DEFEAT_CROP
		r.map_id = &"mato_grosso"
		Profile.apply_hunt_result(r)


func _sanitized_learned(block: Variant) -> Array:
	var out: Dictionary = SaveService.sanitize({"onboarding": block})
	return (out["onboarding"] as Dictionary)["learned"]


# --------------------------------------------------------------------------------------------
# Data
# --------------------------------------------------------------------------------------------

func test_data_loads_clean_with_onboarding_and_short_names() -> void:
	eq(Data.get_load_errors().size(), 0, "Data.get_load_errors: %s" % str(Data.get_load_errors()))
	var ob: Variant = Data.get_game().get("onboarding")
	ok(ob is Dictionary, "game.json tem o bloco onboarding")
	if ob is Dictionary:
		for f: String in ["max_hunts", "eval_interval_s", "opening_delay_s", "opening_duration_s", "hint_duration_s",
				"hint_gap_s", "queue_max", "medkit_health_below_pct", "boar_sighted_range_m",
				"boar_sighted_half_angle_deg", "drone_no_sighting_s"]:
			var v: Variant = (ob as Dictionary).get(f)
			ok(v is int or v is float, "onboarding.%s e numero" % f)
			if v is int or v is float:
				ok(float(v) > 0.0, "onboarding.%s > 0" % f)
	var ids: Array[StringName] = Data.get_equipment_ids()
	eq(ids.size(), 7, "7 itens de equipamento")
	for id: StringName in ids:
		var short_name: Variant = Data.get_equipment(id).get("short_name")
		ok(short_name is String and (short_name as String).strip_edges() != "", "%s tem short_name" % id)
		if short_name is String:
			ok((short_name as String).length() <= 9, "%s: short_name '%s' tem no maximo 9 caracteres" % [id, short_name])


func test_data_validation_rejects_bad_onboarding_and_short_name() -> void:
	## Pokes the live registry (restored below) to prove _validate_onboarding reports the problem.
	var base: int = Data.get_load_errors().size()
	var ob: Dictionary = Data.get_game()["onboarding"]
	var old_max: Variant = ob["max_hunts"]
	var old_angle: Variant = ob["boar_sighted_half_angle_deg"]
	var items: Array = Data._raw["equipment"]["items"]
	var old_short: Variant = (items[0] as Dictionary)["short_name"]
	var errors_seen: Array[int] = []

	ob["max_hunts"] = 0
	Data._validate_onboarding()
	errors_seen.append(Data.get_load_errors().size())
	ob["max_hunts"] = old_max

	ob["boar_sighted_half_angle_deg"] = 120.0
	Data._validate_onboarding()
	errors_seen.append(Data.get_load_errors().size())
	ob["boar_sighted_half_angle_deg"] = old_angle

	(items[0] as Dictionary)["short_name"] = "Nome curto demais"
	Data._validate_onboarding()
	errors_seen.append(Data.get_load_errors().size())
	(items[0] as Dictionary).erase("short_name")
	Data._validate_onboarding()
	errors_seen.append(Data.get_load_errors().size())
	(items[0] as Dictionary)["short_name"] = old_short

	Data._errors.resize(base)   # leave the registry exactly as it was
	eq(Data.get_load_errors().size(), 0, "registro restaurado sem erros")
	eq(errors_seen[0], base + 1, "max_hunts = 0 vira erro")
	eq(errors_seen[1], errors_seen[0] + 1, "angulo > 90 vira erro")
	eq(errors_seen[2], errors_seen[1] + 1, "short_name com mais de 9 caracteres vira erro")
	eq(errors_seen[3], errors_seen[2] + 1, "item sem short_name vira erro")


# --------------------------------------------------------------------------------------------
# Hint ids and sanitize
# --------------------------------------------------------------------------------------------

func test_hint_id_validity() -> void:
	expect_errors()   # known bug: SaveService.is_valid_hint_id logs "Data: unknown id" for ids that are not equipment (relatado no QA da HF1)
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone", &"binoculars", &"dog_command"]:
		ok(SaveService.is_valid_hint_id(id), "%s e id de dica valido" % id)
	for id: StringName in [&"leather_vest", &"extra_ammo", &"thermal_scope", &"opening", &"", &"nope", &"Medkit", &"carbine_22"]:
		ok(not SaveService.is_valid_hint_id(id), "'%s' nao e id de dica" % id)


func test_sanitize_missing_or_wrong_type_block_gives_empty_list() -> void:
	eq(SaveService.sanitize({}).get("onboarding"), {"learned": []}, "sem bloco")
	for bad: Variant in ["texto", 7, [1, 2], null, true, 3.5]:
		eq(_sanitized_learned(bad), [], "bloco onboarding = %s" % str(bad))
	for bad_list: Variant in ["medkit", 5, {"medkit": true}, null, false]:
		eq(_sanitized_learned({"learned": bad_list}), [], "learned = %s" % str(bad_list))
	eq(_sanitized_learned({}), [], "bloco sem learned")


func test_sanitize_filters_unknown_duplicate_and_non_string_ids() -> void:
	expect_errors()   # known bug: SaveService.is_valid_hint_id logs "Data: unknown id" for ids that are not equipment (relatado no QA da HF1)
	var raw: Array = ["medkit", "bogus", "medkit", 42, null, "leather_vest", "dog_command", ["x"], "scout_drone", "dog_command", ""]
	eq(_sanitized_learned({"learned": raw}), ["medkit", "dog_command", "scout_drone"],
		"so ids validos, sem repeticao, na ordem em que estavam")
	var input: Dictionary = {"onboarding": {"learned": ["medkit"]}}
	var out: Dictionary = SaveService.sanitize(input)
	(out["onboarding"]["learned"] as Array).append("corn_bait")
	eq(input["onboarding"]["learned"], ["medkit"], "sanitize nao altera a entrada")


func test_new_save_and_current_version_have_empty_learned() -> void:
	var s: Dictionary = SaveService.new_save()
	eq(s["onboarding"], {"learned": []}, "new_save traz o bloco")
	eq(s["version"], 2, "versao do save continua 2")
	eq(SaveService.CURRENT_VERSION, 2, "CURRENT_VERSION continua 2 (migracao pelo sanitize, sem passo 2 -> 3)")


# --------------------------------------------------------------------------------------------
# Old saves through Profile.load_or_create
# --------------------------------------------------------------------------------------------

func test_old_v2_save_without_onboarding_loads_with_empty_list() -> void:
	fresh_profile()
	Profile.mark_hint_learned(&"medkit")   # in-memory state that the loaded save must replace
	var old: Dictionary = SaveService.new_save()
	old.erase("onboarding")
	write_text(PATH, JSON.stringify(old))
	Profile.load_or_create()
	ok(not Profile.is_hint_learned(&"medkit"), "memoria substituida pelo save carregado")
	for id: StringName in [&"medkit", &"corn_bait", &"scout_drone", &"dog_command", &"binoculars"]:
		ok(not Profile.is_hint_learned(id), "%s nao aprendido" % id)
	ok(Profile.save(), "save depois de carregar")
	eq(_file_learned(), [], "arquivo regravado com learned = []")
	eq(int(_read_file_dict().get("version", -1)), 2, "versao 2")


func test_v1_save_without_onboarding_is_migrated_with_empty_list() -> void:
	fresh_profile()
	var old: Dictionary = SaveService.new_save()
	old["version"] = 1
	old.erase("onboarding")
	write_text(PATH, JSON.stringify(old))
	Profile.load_or_create()   # migrates, then saves at once
	eq(int(_read_file_dict().get("version", -1)), 2, "versao 2 no arquivo")
	eq(_file_learned(), [], "learned = [] no arquivo")
	ok(not Profile.is_hint_learned(&"medkit"), "nada aprendido")


func test_load_filters_dirty_learned_list() -> void:
	expect_errors()   # known bug: SaveService.is_valid_hint_id logs "Data: unknown id" for ids that are not equipment (relatado no QA da HF1)
	fresh_profile()
	var dirty: Dictionary = SaveService.new_save()
	dirty["onboarding"] = {"learned": ["scout_drone", "xyz", "scout_drone", 9, "corn_bait"]}
	write_text(PATH, JSON.stringify(dirty))
	Profile.load_or_create()
	ok(Profile.is_hint_learned(&"scout_drone"), "scout_drone mantido")
	ok(Profile.is_hint_learned(&"corn_bait"), "corn_bait mantido")
	ok(not Profile.is_hint_learned(&"xyz"), "id desconhecido descartado")
	Profile.save()
	eq(_file_learned(), ["scout_drone", "corn_bait"], "arquivo guarda a lista limpa")


func test_corrupted_save_starts_with_empty_learned() -> void:
	fresh_profile()
	Profile.mark_hint_learned(&"medkit")
	Profile.save()
	_delete_save_files()
	write_text(PATH, "{corrompido")
	Profile.load_or_create()   # no backup either: new profile
	ok(not Profile.is_hint_learned(&"medkit"), "perfil novo apos save corrompido")
	eq(_file_learned(), [], "perfil novo regravado com learned = []")


# --------------------------------------------------------------------------------------------
# Profile.is_onboarding_active
# --------------------------------------------------------------------------------------------

func test_onboarding_active_until_max_hunts() -> void:
	fresh_profile()
	var max_hunts: int = _max_hunts()
	eq(max_hunts, 3, "game.onboarding.max_hunts = 3 (contrato 1.3)")
	ok(Profile.is_onboarding_active(), "perfil novo: ativo (hunts_played 0)")
	_played(2)
	eq(int(Profile.get_stats()["hunts_played"]), 2, "hunts_played = 2")
	ok(Profile.is_onboarding_active(), "hunts_played 2: ativo")
	_played(1)
	eq(int(Profile.get_stats()["hunts_played"]), 3, "hunts_played = 3")
	ok(not Profile.is_onboarding_active(), "hunts_played 3: inativo")
	_played(1)
	ok(not Profile.is_onboarding_active(), "hunts_played 4: continua inativo")


func test_onboarding_limit_comes_from_data() -> void:
	fresh_profile()
	var ob: Dictionary = Data.get_game()["onboarding"]
	var original: Variant = ob["max_hunts"]
	_played(2)
	ob["max_hunts"] = 2
	var at_limit: bool = Profile.is_onboarding_active()
	ob["max_hunts"] = 5
	var above_limit: bool = Profile.is_onboarding_active()
	ob["max_hunts"] = original   # restore the live data before asserting
	ok(not at_limit, "max_hunts 2 com 2 jogadas: inativo")
	ok(above_limit, "max_hunts 5 com 2 jogadas: ativo")
	ok(Profile.is_onboarding_active(), "dado restaurado: ativo de novo")


func test_onboarding_state_survives_reload_from_disk() -> void:
	fresh_profile()
	_played(3)
	ok(not Profile.is_onboarding_active(), "inativo apos 3 caçadas")
	Profile.load_or_create()
	ok(not Profile.is_onboarding_active(), "inativo depois de recarregar o save")
	Profile.reset_progress()
	ok(Profile.is_onboarding_active(), "reset_progress volta a ativar")


# --------------------------------------------------------------------------------------------
# Profile.mark_hint_learned / is_hint_learned
# --------------------------------------------------------------------------------------------

func test_mark_hint_learned_is_idempotent() -> void:
	fresh_profile()
	ok(not Profile.is_hint_learned(&"medkit"), "comeca nao aprendido")
	Profile.mark_hint_learned(&"medkit")
	ok(Profile.is_hint_learned(&"medkit"), "aprendido")
	Profile.mark_hint_learned(&"medkit")
	Profile.mark_hint_learned(&"medkit")
	Profile.mark_hint_learned(&"dog_command")
	ok(Profile.is_hint_learned(&"dog_command"), "dog_command aprendido")
	ok(not Profile.is_hint_learned(&"corn_bait"), "outros continuam nao aprendidos")
	Profile.save()
	eq(_file_learned(), ["medkit", "dog_command"], "sem duplicata no arquivo, na ordem da marcacao")


func test_mark_hint_learned_rejects_invalid_ids() -> void:
	expect_errors()   # known bug: SaveService.is_valid_hint_id logs "Data: unknown id" for ids that are not equipment (relatado no QA da HF1)
	fresh_profile()
	for id: StringName in [&"", &"bogus", &"leather_vest", &"opening", &"Medkit", &"extra_ammo"]:
		Profile.mark_hint_learned(id)
		ok(not Profile.is_hint_learned(id), "id invalido '%s' ignorado" % id)
	Profile.save()
	eq(_file_learned(), [], "nada invalido chega ao arquivo")


func test_mark_hint_learned_does_not_write_to_disk() -> void:
	fresh_profile()
	await frames(2)   # let any deferred settings flush from earlier tests run first
	_delete_save_files()
	Profile.mark_hint_learned(&"medkit")
	Profile.mark_hint_learned(&"scout_drone")
	await frames(3)
	ok(not FileAccess.file_exists(PATH), "mark_hint_learned nao grava o save sozinho")
	ok(Profile.is_hint_learned(&"medkit"), "mas fica na memoria")
	ok(Profile.save(), "save() grava")
	eq(_file_learned(), ["medkit", "scout_drone"], "o aprendido aparece no arquivo depois de save()")


func test_learned_in_memory_is_lost_on_reload_but_saved_is_kept() -> void:
	fresh_profile()
	Profile.mark_hint_learned(&"medkit")
	Profile.save()
	Profile.mark_hint_learned(&"corn_bait")   # memory only
	Profile.load_or_create()
	ok(Profile.is_hint_learned(&"medkit"), "o que foi salvo volta")
	ok(not Profile.is_hint_learned(&"corn_bait"), "o que nao foi salvo se perde (aba fechada no meio da caçada)")


func test_apply_hunt_result_persists_learned() -> void:
	fresh_profile()
	Profile.mark_hint_learned(&"scout_drone")
	Profile.mark_hint_learned(&"dog_command")
	_played(1)
	eq(_file_learned(), ["scout_drone", "dog_command"], "apply_hunt_result grava o aprendido da caçada")
	Profile.load_or_create()
	ok(Profile.is_hint_learned(&"scout_drone") and Profile.is_hint_learned(&"dog_command"), "recarrega do disco")


func test_reset_progress_clears_learned_and_keeps_settings() -> void:
	fresh_profile()
	Profile.set_setting("show_fps", true)
	Profile.mark_hint_learned(&"medkit")
	Profile.mark_hint_learned(&"dog_command")
	Profile.reset_progress()
	ok(not Profile.is_hint_learned(&"medkit"), "medkit zerado")
	ok(not Profile.is_hint_learned(&"dog_command"), "dog_command zerado")
	eq(_file_learned(), [], "arquivo zerado")
	eq(Profile.get_setting("show_fps"), true, "settings mantidos")
	Profile.set_setting("show_fps", false)
