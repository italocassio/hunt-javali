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
	ok(Router.scene_has_music(ScenePaths.MAIN_MENU), "menu principal tem musica")
	ok(Router.scene_has_music(ScenePaths.LOBBY), "sala (jogar com amigos) tem musica")
	for path: String in [ScenePaths.BOOT, ScenePaths.MAP_SELECT, ScenePaths.PREPARATION, ScenePaths.SHOP,
			ScenePaths.RESULT, ScenePaths.DONATE, ScenePaths.SETTINGS, ScenePaths.HUNT]:
		ok(not Router.scene_has_music(path), "sem musica: %s" % path)
	ok(not Router.scene_has_music(""), "caminho vazio sem musica")
