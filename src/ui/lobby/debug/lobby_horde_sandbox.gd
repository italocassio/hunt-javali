extends Node
## Debug sandbox for the lobby mode selector (docs/horda.md 10.2). Headless: puts a fake in-room session in the
## Net autoload (no socket), builds the lobby inside SubViewports of 1280x720 and 2340x1080 and checks the
## layout by Control sizes. Run: tools/godot.sh --headless --path . res://src/ui/lobby/debug/lobby_horde_sandbox.tscn
## Prints PASS/FAIL per item and exits with code 1 on any failure. Uses a throwaway save path.

const SAVE_PATH: String = "user://lobby_horde_sandbox.json"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2340, 1080)]
const MIN_MODE_BUTTON_PX: float = 64.0
const SESSION_SCRIPT: String = "res://src/net/net_session.gd"
const SETTLE_FRAMES: int = 3

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.set_save_path(SAVE_PATH)
	Profile.reset_progress()
	for size: Vector2i in SIZES:
		await _case(size, true)
		await _case(size, false)
	Net.set("_session", null)
	for path: String in [SAVE_PATH, SAVE_PATH.replace(".json", ".bak.json")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("LOBBY_HORDE_SANDBOX checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures += 1


func _fake_session(host: bool) -> Object:
	var script: GDScript = load(SESSION_SCRIPT)
	var s: Object = script.new()
	s.call("setup", Data.get_net(), {"router": false})
	s.set("_role", script.get("ROLE_HOST") if host else script.get("ROLE_CLIENT"))
	s.set("_state", script.get("STATE_LOBBY"))
	s.set("_local_slot", 0 if host else 1)
	s.call("_add_peer", 0, "Anfitrião")
	s.call("_add_peer", 1, "Cliente")
	s.set("_map_id", Data.get_map_ids()[0])
	s.set("_contract_index", 0)
	return s


func _case(size: Vector2i, host: bool) -> void:
	var tag: String = "%dx%d %s" % [size.x, size.y, "anfitriao" if host else "cliente"]
	var session: Object = _fake_session(host)
	Net.set("_session", session)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var lobby: Control = (load(ScenePaths.LOBBY) as PackedScene).instantiate()
	viewport.add_child(lobby)
	await _settle()

	var mode_label: Label = lobby.get_node_or_null("%ModeLabel") as Label
	var b_contract: Button = lobby.get_node_or_null("%ModeContractButton") as Button
	var b_horde: Button = lobby.get_node_or_null("%ModeHordeButton") as Button
	var info: Label = lobby.get_node_or_null("%HordeInfoLabel") as Label
	var start: Button = lobby.get_node_or_null("%StartButton") as Button
	var slot0: Button = lobby.get_node_or_null("%WeaponSlot0") as Button
	var slot1: Button = lobby.get_node_or_null("%WeaponSlot1") as Button
	var locked: Label = lobby.get_node_or_null("%WeaponsLockedLabel") as Label
	var map_option: Control = lobby.get_node_or_null("%MapOption") as Control
	var nodes_ok: bool = mode_label != null and b_contract != null and b_horde != null and info != null \
			and slot0 != null and slot1 != null and locked != null and map_option != null and start != null
	_ok(nodes_ok, "%s nos existem" % tag)
	if not nodes_ok:
		viewport.queue_free()
		return

	# Contract mode.
	_ok(mode_label.is_visible_in_tree() and mode_label.text == "Modo: Contrato", "%s ModeLabel contrato" % tag)
	_ok(b_contract.is_visible_in_tree() == host and b_horde.is_visible_in_tree() == host, "%s botoes de modo so para o anfitriao" % tag)
	if host:
		_ok(b_contract.size.y >= MIN_MODE_BUTTON_PX and b_horde.size.y >= MIN_MODE_BUTTON_PX, "%s botoes de modo >= 64 px (%.0f, %.0f)" % [tag, b_contract.size.y, b_horde.size.y])
		_ok(b_contract.button_pressed and not b_horde.button_pressed, "%s botao Contrato pressionado" % tag)
	_ok(not slot0.disabled and not slot1.disabled and not locked.visible, "%s armas liberadas em contrato" % tag)
	_ok(not info.visible, "%s HordeInfoLabel escondido em contrato" % tag)
	_ok(start.text == UiKit.action_text("Iniciar caçada"), "%s Start Iniciar caçada" % tag)

	# Horde mode.
	if host:
		b_horde.pressed.emit()
	else:
		session.set("_mode", Ids.MODE_HORDE)
		Net.roster_changed.emit()
		lobby.call("_refresh_roster")
	await _settle()
	_ok(Net.get_selected_mode() == Ids.MODE_HORDE, "%s Net em horda" % tag)
	_ok(mode_label.is_visible_in_tree() and mode_label.text == "Modo: Horda Javali", "%s ModeLabel horda" % tag)
	_ok(info.is_visible_in_tree() and info.text == str(Data.get_horde().get("description", "x")), "%s HordeInfoLabel = descricao" % tag)
	_ok(not map_option.is_visible_in_tree(), "%s MapOption escondido" % tag)
	var contract_buttons: int = 0
	for n: Node in lobby.find_children("Contract_*", "Button", true, false):
		if (n as Button).is_visible_in_tree():
			contract_buttons += 1
	_ok(contract_buttons == 0, "%s contratos escondidos" % tag)
	_ok(slot0.disabled and slot1.disabled and locked.visible, "%s WeaponSlot0/1 desabilitados + aviso" % tag)
	_ok(locked.text == "Na Horda Javali todos levam todas as armas, com munição infinita.", "%s texto do aviso" % tag)
	_ok(start.text == UiKit.action_text("Iniciar horda"), "%s Start Iniciar horda" % tag)
	var contract_label: Label = lobby.get_node_or_null("%ContractLabel") as Label
	_ok(contract_label != null and contract_label.text.contains("Horda Javali, ") and contract_label.text.contains(" ondas"), "%s ContractLabel" % tag)
	var detail: Label = lobby.find_child("Detail", true, false) as Label
	_ok(detail != null and detail.text.contains("Todas as armas"), "%s detalhe Todas as armas" % tag)
	var level_row: Control = lobby.get_node_or_null("%HordeLevelRow") as Control
	var level_label: Label = lobby.get_node_or_null("%HordeLevelLabel") as Label
	var l1: Button = lobby.find_child("HordeLevel_1", true, false) as Button
	var l2: Button = lobby.find_child("HordeLevel_2", true, false) as Button
	_ok(level_row != null and level_label != null and l1 != null and l2 != null, "%s nos de nivel existem" % tag)
	if level_row != null and level_label != null and l1 != null and l2 != null:
		_ok(level_row.is_visible_in_tree() == host, "%s botoes de nivel so para o anfitriao em horda" % tag)
		_ok(level_label.is_visible_in_tree() and level_label.text == "Nível escolhido: Nível 1", "%s HordeLevelLabel nivel 1" % tag)
		_ok(contract_label.text.contains("Horda Javali, Nível 1, "), "%s ContractLabel com nivel 1" % tag)
		if host:
			_ok(l1.size.y >= MIN_MODE_BUTTON_PX and l2.size.y >= MIN_MODE_BUTTON_PX, "%s botoes de nivel >= 64 px (%.0f, %.0f)" % [tag, l1.size.y, l2.size.y])
			_ok(l1.button_pressed and not l2.button_pressed, "%s HordeLevel_1 pressionado" % tag)
			_ok(not l1.get_global_rect().intersects(l2.get_global_rect()), "%s botoes de nivel sem sobreposicao" % tag)
			l2.pressed.emit()
		else:
			session.set("_horde_level", 2)
			Net.roster_changed.emit()
			lobby.call("_refresh_roster")
		await _settle()
		_ok(Net.get_selected_horde_level() == 2, "%s Net no nivel 2" % tag)
		_ok(level_label.text == "Nível escolhido: Nível 2", "%s HordeLevelLabel nivel 2" % tag)
		_ok(info.text == str(Data.get_horde_level(2).get("description", "x")), "%s HordeInfoLabel = descricao do nivel 2" % tag)
		_ok(locked.text == "Na Horda Javali todos levam todas as armas. Munição contada: pegue cartuchos no celeiro." and not locked.text.contains("infinita"), "%s aviso de municao contada" % tag)
		_ok(contract_label.text.contains("Horda Javali, Nível 2, "), "%s ContractLabel com nivel 2" % tag)
		if host:
			_ok(l2.button_pressed and not l1.button_pressed, "%s HordeLevel_2 pressionado" % tag)
		await _screenshot(viewport, size, host)
	if host:
		_ok(b_horde.size.y >= MIN_MODE_BUTTON_PX and b_horde.button_pressed and not b_contract.button_pressed, "%s botao Horda pressionado e >= 64 px" % tag)
		b_contract.pressed.emit()
		await _settle()
		_ok(Net.get_selected_mode() == Ids.MODE_CONTRACT and not slot0.disabled and map_option.is_visible_in_tree(), "%s volta a contrato" % tag)

	viewport.queue_free()
	Net.set("_session", null)
	await get_tree().process_frame


## Only with a window and the "--screenshots" user arg (the viewport does not render headless).
func _screenshot(viewport: SubViewport, size: Vector2i, host: bool) -> void:
	if not OS.get_cmdline_user_args().has("--screenshots") or not host:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i: int in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var path: String = "user://lobby_level_%dx%d.png" % [size.x, size.y]
	viewport.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", ProjectSettings.globalize_path(path))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
