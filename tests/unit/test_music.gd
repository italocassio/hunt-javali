extends "res://tests/lib/test_case.gd"
## Menu music routing: which scenes keep the music playing (game.json "music", decided by Router).


func test_music_config_is_complete() -> void:
	var cfg: Dictionary = Data.get_game().get("music", {})
	ok(not cfg.is_empty(), "game.json tem o bloco music")
	ne(str(cfg.get("track", "")), "", "music.track definido")
	ok(float(cfg.get("fade_in_s", -1.0)) >= 0.0, "music.fade_in_s >= 0")
	ok(float(cfg.get("fade_out_s", -1.0)) >= 0.0, "music.fade_out_s >= 0")
	ok(float(cfg.get("volume_db", 1.0)) <= 0.0, "music.volume_db <= 0 (fundo)")
	for path: Variant in cfg.get("scenes", []):
		ok(ResourceLoader.exists(str(path)), "cena de musica existe: %s" % path)


func test_music_scenes() -> void:
	# Every menu screen keeps the music going until the hunt starts.
	for path: String in [ScenePaths.MAIN_MENU, ScenePaths.MAP_SELECT, ScenePaths.PREPARATION, ScenePaths.SHOP,
			ScenePaths.DONATE, ScenePaths.SETTINGS, ScenePaths.LOBBY]:
		ok(Router.scene_has_music(path), "tem musica: %s" % path)
	# BOOT has nothing to play yet; HUNT stops it; RESULT stays quiet so the victory/defeat sting is heard.
	for path: String in [ScenePaths.BOOT, ScenePaths.RESULT, ScenePaths.HUNT]:
		ok(not Router.scene_has_music(path), "sem musica: %s" % path)
	ok(not Router.scene_has_music(""), "caminho vazio sem musica")
