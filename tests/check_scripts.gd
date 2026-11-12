extends Node
## tests/check_scripts.tscn: static checks of the whole project (docs/arquitetura.md section 12).
## Loads every script and scene, instantiates every asset scene, checks autoloads, signatures of
## section 5/6, class declarations, layering rules (section 2) and project/export settings.
##
## Run: tools/godot.sh --headless --path . res://tests/check_scripts.tscn [-- --strict]

const TestCase := preload("res://tests/lib/test_case.gd")
const Sigs := preload("res://tests/lib/contract_sigs.gd")

const WATCHDOG_S: float = 60.0
const SCAN_ROOTS: Array[String] = ["res://src", "res://assets", "res://tests"]
const BINARY_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "exr", "hdr", "wav", "ogg",
	"mp3", "glb", "gltf", "fbx", "obj", "blend", "dae", "ttf", "otf", "woff", "woff2", "mp4", "webm"]
const PHYSICS_FORBIDDEN_IN_ASSETS: Array[String] = ["PhysicsBody3D", "Area3D", "CollisionShape3D",
	"CollisionPolygon3D", "Skeleton3D", "AnimationPlayer", "OmniLight3D", "SpotLight3D"]

var _t: RefCounted
var _totals: Dictionary = {}
var _strict: bool = false
var _start_ms: int = 0
var _finished: bool = false


func _ready() -> void:
	_strict = "--strict" in OS.get_cmdline_user_args()
	_start_ms = Time.get_ticks_msec()
	TestCase.install_catcher()
	_totals = TestCase.new_totals()
	_t = TestCase.new()
	_t.set("host", self)
	_t.set("strict", _strict)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _finished and float(Time.get_ticks_msec() - _start_ms) / 1000.0 > WATCHDOG_S:
		_finished = true
		print("FAIL watchdog: check_scripts excedeu %d s" % int(WATCHDOG_S))
		_totals["fail"] = int(_totals["fail"]) + 1
		_quit()


func _quit() -> void:
	var code: int = TestCase.finish(_totals)
	TestCase.remove_catcher()
	get_tree().quit(code)


func _run() -> void:
	await get_tree().process_frame
	await _case("scripts_compile", _check_scripts_compile)
	await _case("scenes_and_resources_load", _check_scenes_load)
	await _case("asset_scenes_instantiate", _check_assets_instantiate)
	await _case("autoloads_registered", _check_autoloads)
	await _case("autoload_signatures", _check_autoload_signatures)
	await _case("game_events_signals", _check_game_events)
	await _case("autoloads_have_no_class_name", _check_no_class_name_in_autoloads)
	await _case("class_declarations_core", _check_core_classes)
	await _case("class_declarations_package_A", _check_package_classes.bind("A"))
	await _case("class_declarations_package_B", _check_package_classes.bind("B"))
	await _case("class_declarations_systems", _check_package_classes.bind("S"))
	await _case("global_class_names_unique", _check_unique_class_names)
	await _case("layering_no_cross_package_refs", _check_layering)
	await _case("no_ext_resource_to_assets_outside_assets", _check_ext_resources)
	await _case("assets_are_procedural_no_binaries", _check_no_binaries)
	await _case("project_settings", _check_project_settings)
	await _case("export_preset_web", _check_export_preset)
	if not _finished:
		_finished = true
		_quit()


func _case(label: String, fn: Callable) -> void:
	_t.call("begin")
	await fn.call()
	_t.call("conclude", label, _totals)


# --------------------------------------------------------------------------------------------
# File scanning
# --------------------------------------------------------------------------------------------

func _scan(dir_path: String, extensions: Array[String], out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	var subs: PackedStringArray = dir.get_directories()
	subs.sort()
	for sub: String in subs:
		if sub.begins_with("."):
			continue
		_scan(dir_path.path_join(sub), extensions, out)
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for f: String in files:
		if f.get_extension() in extensions:
			out.append(dir_path.path_join(f))


func _files(roots: Array[String], extensions: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for r: String in roots:
		_scan(r, extensions, out)
	return out


# --------------------------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------------------------

func _check_scripts_compile() -> void:
	var files: Array[String] = _files(SCAN_ROOTS, ["gd"])
	_t.call("ok", files.size() > 0, "nenhum .gd encontrado")
	for path: String in files:
		var mark: int = _t.call("error_mark")
		var script: GDScript = ResourceLoader.load(path) as GDScript
		if script == null:
			_t.call("fail", "%s: nao carregou como GDScript" % path)
		elif not script.can_instantiate():
			_t.call("fail", "%s: GDScript.can_instantiate() == false (erro de parser)" % path)
		var errs: Array = _t.call("errors_since", mark)
		if not errs.is_empty():
			_t.call("fail", "%s: %s" % [path, str(errs[0])])
	# errors were already reported per file; do not count them twice
	_t.call("expect_errors")


func _check_scenes_load() -> void:
	var scenes: Array[String] = _files(SCAN_ROOTS, ["tscn"])
	_t.call("ok", scenes.size() > 0, "nenhuma .tscn encontrada")
	for path: String in scenes:
		var mark: int = _t.call("error_mark")
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed == null:
			_t.call("fail", "%s: nao carrega como PackedScene" % path)
		var errs: Array = _t.call("errors_since", mark)
		if not errs.is_empty():
			_t.call("fail", "%s: %s" % [path, str(errs[0])])
	for path: String in _files(SCAN_ROOTS, ["tres", "res"]):
		var mark2: int = _t.call("error_mark")
		var res: Resource = ResourceLoader.load(path)
		if res == null:
			_t.call("fail", "%s: recurso nao carrega" % path)
		var errs2: Array = _t.call("errors_since", mark2)
		if not errs2.is_empty():
			_t.call("fail", "%s: %s" % [path, str(errs2[0])])
	_t.call("expect_errors")


func _check_assets_instantiate() -> void:
	var scenes: Array[String] = _files(["res://assets"], ["tscn"])
	if scenes.is_empty():
		_t.call("skip_or_fail", "assets/ ainda nao tem nenhuma cena (art-director)")
		return
	var count: int = 0
	for path: String in scenes:
		if path.begins_with("res://assets/preview"):
			continue   # screenshot scenes, not used by the game
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed == null:
			continue   # reported by scenes_and_resources_load
		var mark: int = _t.call("error_mark")
		var node: Node = packed.instantiate()
		if node == null:
			_t.call("fail", "%s: instantiate() devolveu null" % path)
			continue
		add_child(node)
		await get_tree().process_frame
		await get_tree().process_frame
		node.queue_free()
		await get_tree().process_frame
		count += 1
		var errs: Array = _t.call("errors_since", mark)
		if not errs.is_empty():
			_t.call("fail", "%s: %s" % [path, str(errs[0])])
	_t.call("expect_errors")
	_t.call("ok", count > 0, "nenhuma cena de assets/ instanciada")


func _check_autoloads() -> void:
	var last_order: int = -1
	for aname: String in Sigs.AUTOLOAD_ORDER:
		var key: String = "autoload/%s" % aname
		if not ProjectSettings.has_setting(key):
			_t.call("fail", "project.godot: autoload '%s' nao registrado" % aname)
			continue
		var value: String = str(ProjectSettings.get_setting(key))
		_t.call("ok", value.begins_with("*"), "autoload %s deve ser singleton (prefixo *): %s" % [aname, value])
		var expected_path: String = Sigs.AUTOLOADS[aname][0]
		var actual: String = value.trim_prefix("*")
		if actual.begins_with("uid://"):
			actual = ResourceUID.get_id_path(ResourceUID.text_to_id(actual))
		_t.call("eq", actual, expected_path, "caminho do autoload %s" % aname)
		var order: int = ProjectSettings.get_order(key)
		_t.call("ok", order > last_order, "ordem dos autoloads: %s deveria vir depois do anterior" % aname)
		last_order = order
		var node: Node = get_tree().root.get_node_or_null(aname)
		if node == null:
			_t.call("fail", "autoload %s nao existe na arvore" % aname)
		elif node.get_script() != null:
			_t.call("eq", (node.get_script() as Script).resource_path, expected_path, "script do autoload %s" % aname)


func _check_methods(node: Object, specs: Array[String], label: String) -> void:
	var entries: Array[Dictionary] = node.get_method_list()
	for spec_text: String in specs:
		var spec: Dictionary = Sigs.parse(spec_text)
		var entry: Dictionary = Sigs.find_method(entries, spec["name"])
		if entry.is_empty():
			_t.call("fail", "%s: falta o metodo %s" % [label, spec_text])
			continue
		var diff: String = Sigs.compare_method(entry, spec)
		if diff != "":
			_t.call("fail", "%s.%s: %s" % [label, spec["name"], diff])


func _check_autoload_signatures() -> void:
	var table: Dictionary = {
		"Data": Sigs.DATA_METHODS, "Profile": Sigs.PROFILE_METHODS, "InputSetup": Sigs.INPUT_SETUP_METHODS,
		"Sfx": Sigs.SFX_METHODS, "Router": Sigs.ROUTER_METHODS,
	}
	for aname: String in table:
		var node: Node = get_tree().root.get_node_or_null(aname)
		if node == null:
			_t.call("fail", "autoload %s ausente" % aname)
			continue
		var specs: Array[String] = []
		specs.assign(table[aname])
		_check_methods(node, specs, aname)
	var router: Node = get_tree().root.get_node_or_null("Router")
	if router != null:
		var props: Array[String] = []
		for p: Dictionary in router.get_property_list():
			props.append(str(p["name"]))
		for want: String in Sigs.ROUTER_PROPERTIES:
			_t.call("ok", want in props, "Router.%s ausente" % want)
	var profile: Node = get_tree().root.get_node_or_null("Profile")
	if profile != null:
		for c: String in Sigs.PROFILE_CONSTANTS:
			_t.call("ok", c in profile.get_script().get_script_constant_map(), "Profile.%s ausente" % c)
		var consts: Dictionary = profile.get_script().get_script_constant_map()
		_t.call("eq", consts.get("SAVE_VERSION", -1), 1, "Profile.SAVE_VERSION")
		_t.call("eq", consts.get("DEFAULT_SAVE_PATH", ""), "user://save.json", "Profile.DEFAULT_SAVE_PATH")
	var input_setup: Node = get_tree().root.get_node_or_null("InputSetup")
	if input_setup != null:
		var iconsts: Dictionary = input_setup.get_script().get_script_constant_map()
		_t.call("ok", iconsts.has("ACTIONS"), "InputSetup.ACTIONS ausente")
		if iconsts.has("ACTIONS"):
			var expected: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "fire", "aim",
				"zoom_in", "zoom_out", "reload", "sprint", "crouch", "weapon_1", "weapon_2", "weapon_swap",
				"dog_command", "use_item", "item_next", "pause"]
			var got: Array[String] = []
			for a: Variant in iconsts["ACTIONS"]:
				got.append(str(a))
			_t.call("eq", got, expected, "InputSetup.ACTIONS")


func _check_game_events() -> void:
	var node: Node = get_tree().root.get_node_or_null("GameEvents")
	if node == null:
		_t.call("fail", "autoload GameEvents ausente")
		return
	var entries: Array[Dictionary] = node.get_signal_list()
	for spec_text: String in Sigs.GAME_EVENTS_SIGNALS:
		var spec: Dictionary = Sigs.parse(spec_text)
		_t.call("ok", node.has_signal(spec["name"]), "GameEvents sem o sinal %s" % spec["name"])
		var entry: Dictionary = Sigs.find_signal(entries, spec["name"])
		if entry.is_empty():
			continue
		var diff: String = Sigs.compare_signal(entry, spec)
		if diff != "":
			_t.call("fail", "GameEvents.%s: %s" % [spec["name"], diff])
	# the bus declares signals only: no extra signals beyond the contract
	var declared: Dictionary = {}
	for spec_text: String in Sigs.GAME_EVENTS_SIGNALS:
		declared[Sigs.parse(spec_text)["name"]] = true
	for e: Dictionary in entries:
		var sname: String = str(e["name"])
		if not declared.has(sname) and (node.get_script() as Script).get_script_signal_list().any(
				func(s: Dictionary) -> bool: return str(s["name"]) == sname):
			_t.call("fail", "GameEvents declara sinal fora do contrato: %s" % sname)


func _check_no_class_name_in_autoloads() -> void:
	for aname: String in Sigs.AUTOLOADS:
		var path: String = Sigs.AUTOLOADS[aname][0]
		if not FileAccess.file_exists(path):
			_t.call("fail", "%s: arquivo do autoload %s nao existe" % [path, aname])
			continue
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("class_name"):
				_t.call("fail", "%s: autoload nao pode declarar class_name (%s)" % [path, line.strip_edges()])


func _global_classes() -> Dictionary:
	var out: Dictionary = {}
	for d: Dictionary in ProjectSettings.get_global_class_list():
		out[str(d["class"])] = d
	return out


func _check_core_classes() -> void:
	var core: Dictionary = {
		"Layers": "res://src/core/layers.gd", "Ids": "res://src/core/ids.gd",
		"ScenePaths": "res://src/core/scene_paths.gd", "AssetLoader": "res://src/core/asset_loader.gd",
		"HitInfo": "res://src/core/hit_info.gd", "HitZone": "res://src/core/hit_zone.gd",
		"KillInfo": "res://src/core/kill_info.gd", "HuntRequest": "res://src/core/hunt_request.gd",
		"HuntResult": "res://src/core/hunt_result.gd", "PlayerBase": "res://src/core/player_base.gd",
		"HuntWorld": "res://src/core/hunt_world.gd", "BoarVisualBase": "res://src/core/boar_visual_base.gd",
		"DogVisualBase": "res://src/core/dog_visual_base.gd", "WeaponViewBase": "res://src/core/weapon_view_base.gd",
		"MapEnvironmentBase": "res://src/core/map_environment_base.gd",
	}
	var classes: Dictionary = _global_classes()
	for cname: String in core:
		if not classes.has(cname):
			_t.call("fail", "class_name %s nao registrado (rode --import?)" % cname)
		else:
			_t.call("eq", str(classes[cname]["path"]), core[cname], "caminho de %s" % cname)


func _base_chain(script: Script) -> Array[String]:
	var chain: Array[String] = []
	var s: Script = script.get_base_script()
	while s != null:
		chain.append(s.get_global_name())
		s = s.get_base_script()
	chain.append(script.get_instance_base_type())
	return chain


func _check_package_classes(pkg: String) -> void:
	var missing: Array[String] = []
	var present: int = 0
	var classes: Dictionary = _global_classes()
	for spec: Dictionary in Sigs.CLASSES:
		if spec["pkg"] != pkg:
			continue
		var path: String = spec["path"]
		var cname: String = spec["name"]
		if not ResourceLoader.exists(path):
			missing.append(cname)
			continue
		present += 1
		var script: GDScript = ResourceLoader.load(path) as GDScript
		if script == null:
			_t.call("fail", "%s: nao carrega" % path)
			continue
		_t.call("eq", script.get_global_name(), cname, "%s: class_name declarado" % path)
		if not classes.has(cname):
			_t.call("fail", "%s: class_name %s fora do cache global (rode --import)" % [path, cname])
		var chain: Array[String] = _base_chain(script)
		var want_base: String = spec["base"]
		var base_ok: bool = want_base in chain
		if not base_ok:
			for native: String in chain:
				if ClassDB.class_exists(native) and ClassDB.class_exists(want_base) and ClassDB.is_parent_class(native, want_base):
					base_ok = true
		_t.call("ok", base_ok, "%s deve estender %s (cadeia: %s)" % [cname, want_base, str(chain)])
		var entries: Array[Dictionary] = script.get_script_method_list()
		for spec_text: String in spec.get("methods", []):
			var parsed: Dictionary = Sigs.parse(spec_text)
			var entry: Dictionary = Sigs.find_method(entries, parsed["name"])
			if entry.is_empty():
				_t.call("fail", "%s: falta o metodo %s" % [cname, spec_text])
				continue
			var diff: String = Sigs.compare_method(entry, parsed)
			if diff != "":
				_t.call("fail", "%s.%s: %s" % [cname, parsed["name"], diff])
		var props: Array[String] = []
		for p: Dictionary in script.get_script_property_list():
			props.append(str(p["name"]))
		for want: String in spec.get("props", []):
			_t.call("ok", want in props, "%s: falta a propriedade '%s'" % [cname, want])
		var sig_entries: Array[Dictionary] = script.get_script_signal_list()
		for sig_text: String in spec.get("signals", []):
			var sp: Dictionary = Sigs.parse(sig_text)
			var se: Dictionary = Sigs.find_signal(sig_entries, sp["name"])
			if se.is_empty():
				_t.call("fail", "%s: falta o sinal %s" % [cname, sig_text])
				continue
			var sdiff: String = Sigs.compare_signal(se, sp)
			if sdiff != "":
				_t.call("fail", "%s.%s: %s" % [cname, sp["name"], sdiff])
	if present == 0:
		_t.call("skip_or_fail", "pacote %s ainda nao entregou nenhuma classe publica (%d esperadas)" % [pkg, missing.size()])
	elif not missing.is_empty():
		_t.call("skip_or_fail", "pacote %s: faltam %s" % [pkg, ", ".join(missing)])


func _check_unique_class_names() -> void:
	var seen: Dictionary = {}
	for d: Dictionary in ProjectSettings.get_global_class_list():
		var cname: String = str(d["class"])
		if seen.has(cname):
			_t.call("fail", "class_name duplicado %s: %s e %s" % [cname, seen[cname], d["path"]])
		seen[cname] = str(d["path"])


# --- layering (section 2) ----------------------------------------------------------------

func _strip_code(text: String) -> String:
	## Removes comments and string literals so class names inside them are not counted.
	var out: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		var cleaned: String = ""
		var quote: String = ""
		var i: int = 0
		while i < line.length():
			var ch: String = line[i]
			if quote != "":
				if ch == "\\":
					i += 2
					continue
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
			elif ch == "#":
				break
			else:
				cleaned += ch
			i += 1
		out.append(cleaned)
	return "\n".join(out)


func _class_names(pkg: String) -> Array[String]:
	var out: Array[String] = []
	for spec: Dictionary in Sigs.CLASSES:
		if spec["pkg"] == pkg:
			out.append(spec["name"])
	return out


func _check_layering() -> void:
	var a_classes: Array[String] = _class_names("A")
	var b_classes: Array[String] = _class_names("B")
	var s_classes: Array[String] = _class_names("S")
	# folder -> forbidden class names
	var rules: Array[Array] = [
		[["res://src/input", "res://src/player", "res://src/weapons", "res://src/hud"], b_classes + s_classes, "pacote A"],
		[["res://src/hunt", "res://src/world", "res://src/boars", "res://src/dogs"], a_classes + s_classes, "pacote B"],
		[["res://src/systems", "res://src/ui"], a_classes + b_classes, "game-systems"],
		[["res://assets"], a_classes + b_classes + s_classes, "art-director"],
	]
	var checked: int = 0
	for rule: Array in rules:
		var roots: Array[String] = []
		roots.assign(rule[0])
		var forbidden: Array[String] = []
		forbidden.assign(rule[1])
		var regexes: Dictionary = {}
		for cname: String in forbidden:
			var re: RegEx = RegEx.new()
			re.compile("\\b%s\\b" % cname)
			regexes[cname] = re
		for path: String in _files(roots, ["gd"]):
			checked += 1
			var code: String = _strip_code(FileAccess.get_file_as_string(path))
			for cname: String in regexes:
				var m: RegExMatch = (regexes[cname] as RegEx).search(code)
				if m != null:
					_t.call("fail", "%s (%s): referencia a classe proibida '%s' (section 2)" % [path, rule[2], cname])
	if checked == 0:
		_t.call("skip_or_fail", "nenhum script dos pacotes ainda")


func _check_ext_resources() -> void:
	var re: RegEx = RegEx.new()
	re.compile("ext_resource[^\\n]*res://assets/")
	var checked: int = 0
	for path: String in _files(["res://src", "res://tests"], ["tscn", "tres"]):
		checked += 1
		if re.search(FileAccess.get_file_as_string(path)) != null:
			_t.call("fail", "%s: .tscn fora de assets/ com ext_resource para assets/ (section 2; use AssetLoader)" % path)
	if checked == 0:
		_t.call("skip", "nenhuma cena em src/ ainda")


func _check_no_binaries() -> void:
	for path: String in _files(["res://assets", "res://src"], BINARY_EXTENSIONS):
		_t.call("fail", "%s: arquivo binario/baixado proibido (tudo e procedural; SVG escrito a mao e permitido)" % path)
	# physics / skeleton / lights are forbidden inside asset scenes: checked here textually,
	# the unit test (assets contract) checks the instantiated trees.
	var re_types: RegEx = RegEx.new()
	re_types.compile("type=\"(%s)\"" % "|".join(PHYSICS_FORBIDDEN_IN_ASSETS))
	for path: String in _files(["res://assets"], ["tscn"]):
		var text: String = FileAccess.get_file_as_string(path)
		var m: RegExMatch = re_types.search(text)
		if m != null:
			_t.call("fail", "%s: no proibido em assets (%s)" % [path, m.get_string(1)])


func _check_project_settings() -> void:
	_t.call("eq", str(ProjectSettings.get_setting("application/config/name")), "Caçada ao Javali", "config/name")
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	if main_scene.begins_with("uid://"):
		main_scene = ResourceUID.get_id_path(ResourceUID.text_to_id(main_scene))
	_t.call("eq", main_scene, ScenePaths.BOOT, "run/main_scene")
	_t.call("eq", str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "gl_compatibility", "renderer")
	_t.call("eq", str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")), "gl_compatibility", "renderer mobile")
	_t.call("eq", int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1280, "viewport_width")
	_t.call("eq", int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720, "viewport_height")
	_t.call("eq", str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items", "stretch mode")
	_t.call("eq", str(ProjectSettings.get_setting("display/window/stretch/aspect")), "expand", "stretch aspect")
	_t.call("eq", int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")), 60, "physics ticks")
	_t.call("eq", int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame")), 4, "max steps")
	_t.call("eq", bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse")), false, "emulate_touch_from_mouse")
	_t.call("eq", bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch")), true, "emulate_mouse_from_touch")
	var layer_names: Array[String] = ["terrain", "static", "player", "boar_hitzone"]
	for i: int in 4:
		_t.call("eq", str(ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % (i + 1))), layer_names[i], "layer_%d" % (i + 1))
	_t.call("eq", Layers.TERRAIN, 1, "Layers.TERRAIN")
	_t.call("eq", Layers.STATIC, 2, "Layers.STATIC")
	_t.call("eq", Layers.PLAYER, 4, "Layers.PLAYER")
	_t.call("eq", Layers.BOAR_HITZONE, 8, "Layers.BOAR_HITZONE")
	# No [input] section: actions are registered in code by InputSetup (section 3).
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = str(prop["name"])
		if pname.begins_with("input/") and not pname.begins_with("input/ui_"):
			_t.call("fail", "project.godot nao deve ter acoes em [input]: %s (InputSetup registra em codigo)" % pname)
	# Theme is applied globally once art-director delivers it.
	var theme_path: String = str(ProjectSettings.get_setting("gui/theme/custom", ""))
	if ResourceLoader.exists(ScenePaths.UI_THEME):
		_t.call("eq", theme_path, ScenePaths.UI_THEME, "gui/theme/custom (theme.tres ja existe; deve estar no project.godot)")
	if ResourceLoader.exists("res://assets/ui/icons/app_icon.svg"):
		_t.call("eq", str(ProjectSettings.get_setting("application/config/icon", "")), "res://assets/ui/icons/app_icon.svg", "config/icon")


func _check_export_preset() -> void:
	var path: String = "res://export_presets.cfg"
	if not FileAccess.file_exists(path):
		_t.call("fail", "export_presets.cfg ausente")
		return
	var text: String = FileAccess.get_file_as_string(path)
	_t.call("contains", text, "platform=\"Web\"", "preset Web")
	_t.call("contains", text, "name=\"Web\"", "nome do preset")
	_t.call("contains", text, "include_filter=\"data/*.json\"", "JSON nao e recurso: include_filter obrigatorio")
	_t.call("contains", text, "export_filter=\"all_resources\"", "export_filter")
	_t.call("contains", text, "variant/thread_support=false", "sem threads (Safari iOS)")
	_t.call("contains", text, "variant/extensions_support=false", "sem extensoes")
	_t.call("contains", text, "html/canvas_resize_policy=2", "canvas_resize_policy")
	_t.call("contains", text, "html/experimental_virtual_keyboard=true", "teclado virtual")
	_t.call("contains", text, "progressive_web_app/enabled=false", "PWA desligado")
	_t.call("contains", text, "build/web/index.html", "saida do export")
	for excl: String in ["tests/*", "docs/*", "tools/*", "assets/preview/*"]:
		_t.call("contains", text, excl, "exclude_filter")
