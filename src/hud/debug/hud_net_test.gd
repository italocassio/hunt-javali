extends Node
## Package A sandbox for F4 (networked shooting, player side): shot ids stamped with the local slot, the hit
## marker ignoring allies' hits and the ally kill message. Runs offline (local slot 0).
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hud/debug/hud_net_test.tscn
## Not part of the game.

const ALLY_SLOT: int = 1
const ALLY_SHOT_COUNTER: int = 7
const TARGET_DISTANCE_M: float = 6.0
const TARGET_RADIUS_M: float = 3.0
const ALLY_KILL_WEIGHT_KG: float = 132.0

var _passed: int = 0
var _failed: int = 0
var _abandon_count: int = 0


class StubHunter extends PlayerBase:
	var alive: bool = true
	var local: bool = true
	var input_enabled: bool = true
	var input_calls: int = 0

	func is_alive() -> bool:
		return alive

	func is_local() -> bool:
		return local

	func set_input_enabled(enabled: bool) -> void:
		input_enabled = enabled
		input_calls += 1


class StubWorld extends HuntWorld:
	var hunters: Array[PlayerBase] = []

	func get_hunters() -> Array[PlayerBase]:
		return hunters

	func get_hunter(for_slot: int) -> PlayerBase:
		for h: PlayerBase in hunters:
			if h.slot == for_slot:
				return h
		return null


func _ready() -> void:
	await _test_shot_ids()
	await _test_hud()
	await _test_net_messages()
	await _test_spectate_hud()
	await _test_pause()
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s %s" % [test_name, detail])
	else:
		_failed += 1
		print("FAIL %s: %s" % [test_name, detail])


func _test_shot_ids() -> void:
	_check("make_shot_id_solo", NetCodec.make_shot_id(0, 5) == 5 and NetCodec.make_shot_id(0, 1) == 1)
	_check("make_shot_id_slot", NetCodec.shot_slot(NetCodec.make_shot_id(ALLY_SLOT, 5)) == ALLY_SLOT)
	_check("solo_local_slot", Net.get_local_slot() == 0)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	var zone: HitZone = HitZone.new()
	zone.zone = &"body"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = TARGET_RADIUS_M
	shape.shape = sphere
	zone.add_child(shape)
	add_child(zone)
	zone.position = Vector3(0.0, 0.0, -TARGET_DISTANCE_M)
	var hits: Array[HitInfo] = []
	zone.hit_received.connect(func(h: HitInfo) -> void: hits.append(h))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var weapon: Weapon = Weapon.new()
	add_child(weapon)
	weapon.setup(Ids.W_CARBINE_22)
	Weapon.reset_shot_counter()
	var fired_ids: Array[int] = []
	weapon.fired.connect(func(id: int) -> void: fired_ids.append(id))
	var first_expected: int = Weapon.peek_next_shot_id()
	var shot: bool = weapon.fire(cam, 0.0, 0.0, [] as Array[RID], self)
	_check("weapon_fired", shot and fired_ids.size() == 1)
	_check("solo_shot_id_unchanged", fired_ids.size() == 1 and fired_ids[0] == first_expected and first_expected == 1,
		"id=%s" % str(fired_ids))
	_check("hit_info_stamped", hits.size() >= 1 and hits[0].shot_id == first_expected and hits[0].shooter_slot == 0,
		"hits=%d" % hits.size())
	Weapon.reset_shot_counter()
	cam.queue_free()
	zone.queue_free()
	weapon.queue_free()


func _test_hud() -> void:
	var hud: Hud = Hud.new()
	add_child(hud)
	await get_tree().process_frame
	var ctx: KillMessage = hud.get("_ctx_msg") as KillMessage
	var kill_msg: KillMessage = hud.get("_kill_msg") as KillMessage
	var ally_shot: int = NetCodec.make_shot_id(ALLY_SLOT, ALLY_SHOT_COUNTER)
	GameEvents.boar_hit.emit(1, &"body", 10.0, Vector3.ZERO, ally_shot)
	_check("hitmarker_ignores_ally", int(hud.get("_last_hit_shot")) == -1)
	var own_shot: int = NetCodec.make_shot_id(Net.get_local_slot(), ALLY_SHOT_COUNTER)
	GameEvents.boar_hit.emit(1, &"body", 10.0, Vector3.ZERO, own_shot)
	_check("hitmarker_own_shot", int(hud.get("_last_hit_shot")) == own_shot)
	var ally_kill: KillInfo = KillInfo.new()
	ally_kill.type_id = Ids.BOAR
	ally_kill.weight_kg = ALLY_KILL_WEIGHT_KG
	ally_kill.killer_slot = ALLY_SLOT
	GameEvents.boar_killed.emit(ally_kill)
	_check("ally_kill_message", ctx.get_text().contains("abateu um javali") and ctx.get_text().contains("132"),
		ctx.get_text())
	_check("ally_kill_no_own_message", kill_msg.get_text() == "")
	var label: Label = ctx.get_child(0) as Label
	_check("ally_kill_color", label.get_theme_color("font_color") == HunterVisualBase.slot_color(ALLY_SLOT))
	var own_kill: KillInfo = KillInfo.new()
	own_kill.type_id = Ids.BOAR
	own_kill.weight_kg = ALLY_KILL_WEIGHT_KG
	own_kill.killer_slot = Net.get_local_slot()
	ctx.clear()
	var before: String = ctx.get_text()
	GameEvents.boar_killed.emit(own_kill)
	_check("own_kill_message", kill_msg.get_text().contains("abatido") and ctx.get_text() == before, kill_msg.get_text())
	GameEvents.hud_message_requested.emit("teste", 1.0)
	_check("ctx_color_reset", label.get_theme_color("font_color") == Hud.COLOR_TEXT)
	hud.queue_free()


func _test_net_messages() -> void:
	var hud: Hud = Hud.new()
	add_child(hud)
	await get_tree().process_frame
	var ctx: KillMessage = hud.get("_ctx_msg") as KillMessage
	var stall: Label = hud.get("_stall_banner") as Label
	var down: Label = hud.get("_down_banner") as Label
	_check("stall_hidden_initially", not stall.visible and not down.visible)
	GameEvents.net_stall_changed.emit(true)
	_check("stall_banner_on", stall.visible and stall.text.begins_with("Anfitrião sem resposta"), stall.text)
	GameEvents.net_stall_changed.emit(false)
	_check("stall_banner_off", not stall.visible)
	GameEvents.hunter_joined.emit(ALLY_SLOT, "Maria")
	GameEvents.hunter_left.emit(ALLY_SLOT)
	_check("hunter_left_named", ctx.get_text() == "Maria saiu da caçada.", ctx.get_text())
	var label: Label = ctx.get_child(0) as Label
	_check("hunter_left_color", label.get_theme_color("font_color") == HunterVisualBase.slot_color(ALLY_SLOT))
	GameEvents.hunter_left.emit(ALLY_SLOT + 1)
	_check("hunter_left_fallback", ctx.get_text() == "Um caçador saiu da caçada.", ctx.get_text())
	GameEvents.hunter_died.emit(ALLY_SLOT)
	_check("ally_down_message", ctx.get_text() == "Maria foi derrubado.", ctx.get_text())
	ctx.clear()
	var before: String = ctx.get_text()
	GameEvents.hunter_died.emit(Net.get_local_slot())
	_check("local_down_no_ally_message", ctx.get_text() == before)
	# Local fall: banner only with an ally still standing.
	var world: StubWorld = StubWorld.new()
	add_child(world)
	hud.set("_world", world)
	var me: StubHunter = StubHunter.new()
	var ally: StubHunter = StubHunter.new()
	ally.local = false
	ally.slot = ALLY_SLOT
	world.hunters = [me, ally] as Array[PlayerBase]
	ally.alive = false
	GameEvents.player_died.emit()
	_check("down_banner_all_down", not down.visible)
	ally.alive = true
	GameEvents.player_died.emit()
	_check("down_banner_with_ally", down.visible and down.text == "Você foi derrubado. Aguarde o fim da caçada.", down.text)
	var result: HuntResult = HuntResult.new()
	result.outcome = HuntResult.Outcome.DISCONNECTED
	GameEvents.hunt_ended.emit(result)
	var end_msg: KillMessage = hud.get("_end_msg") as KillMessage
	_check("disconnected_text", end_msg.get_text() == "Conexão perdida." and not down.visible, end_msg.get_text())
	hud.on_hunt_ended()
	var last_text: String = ctx.get_text()
	GameEvents.hunter_left.emit(ALLY_SLOT + 2)
	GameEvents.net_stall_changed.emit(true)
	_check("no_messages_after_end", ctx.get_text() == last_text and not stall.visible)
	hud.queue_free()
	world.queue_free()
	me.free()
	ally.free()


func _test_spectate_hud() -> void:
	var hud: Hud = Hud.new()
	add_child(hud)
	await get_tree().process_frame
	var banner: Label = hud.get("_spectate_banner") as Label
	var hint: Label = hud.get("_spectate_hint") as Label
	var down: Label = hud.get("_down_banner") as Label
	var weapon_panel: Control = hud.get("_bottomright_margin") as Control
	var minimap: Minimap = hud.get("_minimap") as Minimap
	var world: StubWorld = StubWorld.new()
	add_child(world)
	hud.set("_world", world)
	var me: StubHunter = StubHunter.new()
	var ana: StubHunter = StubHunter.new()
	var beto: StubHunter = StubHunter.new()
	ana.local = false
	ana.slot = ALLY_SLOT
	beto.local = false
	beto.slot = ALLY_SLOT + 1
	world.hunters = [me, ana, beto] as Array[PlayerBase]
	world.add_child(me)
	world.add_child(ana)
	world.add_child(beto)
	hud.set("_player", me)   # StubHunter is a PlayerBase, enough for the map and the banners
	GameEvents.hunter_joined.emit(ALLY_SLOT, "Ana")
	GameEvents.hunter_joined.emit(ALLY_SLOT + 1, "Beto")
	_check("spectate_hidden_initially", not banner.visible and not hint.visible)
	GameEvents.player_died.emit()
	_check("fall_shows_down_banner", down.visible and not banner.visible)
	GameEvents.spectate_changed.emit(ALLY_SLOT)
	_check("spectate_banner_named", banner.visible and banner.text == "Assistindo: Ana", banner.text)
	_check("spectate_banner_color", banner.get_theme_color("font_color") == HunterVisualBase.slot_color(ALLY_SLOT))
	_check("spectate_replaces_down_banner", not down.visible)
	_check("spectate_hides_weapon_panel", not weapon_panel.visible)
	_check("spectate_hint_with_second_ally", hint.visible)
	_check("spectate_map_skips_followed", minimap.allies.size() == 2 and minimap.center_color == HunterVisualBase.slot_color(ALLY_SLOT),
		str(minimap.allies.size()))
	GameEvents.spectate_changed.emit(ALLY_SLOT + 1)
	_check("spectate_banner_follows_change", banner.text == "Assistindo: Beto", banner.text)
	beto.alive = false
	GameEvents.spectate_changed.emit(ALLY_SLOT)
	_check("spectate_hint_hidden_when_alone", not hint.visible)
	GameEvents.spectate_changed.emit(-1)
	_check("spectate_end_restores_hud", not banner.visible and not hint.visible and down.visible and weapon_panel.visible
		and minimap.center_color == Minimap.COLOR_PLAYER)
	GameEvents.spectate_changed.emit(ALLY_SLOT)
	hud.on_hunt_ended()
	var result: HuntResult = HuntResult.new()
	result.outcome = HuntResult.Outcome.DEFEAT_DEATH
	GameEvents.hunt_ended.emit(result)
	GameEvents.spectate_changed.emit(ALLY_SLOT + 1)
	_check("spectate_silent_after_end", not banner.visible and not hint.visible and not down.visible)
	hud.queue_free()
	world.queue_free()


func _on_abandon() -> void:
	_abandon_count += 1


func _test_pause() -> void:
	GameEvents.hunt_abandon_requested.connect(_on_abandon)
	var me: StubHunter = StubHunter.new()
	var overlay: PauseOverlay = PauseOverlay.new()
	add_child(overlay)
	overlay.bind(me)
	var button: Button = overlay.get("_abandon_button") as Button
	# Solo (Net offline): pauses the tree, input untouched.
	overlay.open()
	_check("solo_pause_pauses_tree", get_tree().paused and overlay.is_open() and button.text == "Desistir da caçada")
	_check("solo_pause_keeps_input_calls", me.input_calls == 0)
	overlay.close()
	_check("solo_resume_unpauses", not get_tree().paused and me.input_calls == 0)
	# Online client: tree keeps running, input off while open, back on after.
	overlay.debug_role = Net.Role.CLIENT
	overlay.open()
	_check("net_pause_keeps_tree_running", not get_tree().paused and overlay.is_open())
	_check("net_pause_disables_input", not me.input_enabled)
	_check("net_client_abandon_text", button.text == "Sair da caçada", button.text)
	overlay.close()
	_check("net_resume_enables_input", me.input_enabled and not get_tree().paused)
	overlay.debug_role = Net.Role.HOST
	overlay.open()
	_check("net_host_abandon_text", button.text == "Encerrar a caçada para todos", button.text)
	overlay.close()
	# Knocked down while the menu is open: it closes and the input stays off.
	overlay.debug_role = Net.Role.CLIENT
	overlay.open()
	me.alive = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check("net_death_closes_menu", not overlay.is_open() and not me.input_enabled)
	me.alive = true
	me.input_enabled = true
	# A fallen hunter watching an online hunt can still open the menu and leave; solo cannot (the fall ends the hunt).
	me.alive = false
	overlay.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("net_fallen_can_open_menu", overlay.is_open() and not get_tree().paused)
	overlay.close()
	_check("net_fallen_close_keeps_input_off", not overlay.is_open() and not me.input_enabled)
	overlay.debug_role = Net.Role.OFFLINE
	overlay.open()
	_check("solo_fallen_cannot_open_menu", not overlay.is_open())
	overlay.debug_role = Net.Role.CLIENT
	me.alive = true
	me.input_enabled = true
	# Hunt ends while the menu is open: input must not come back.
	overlay.open()
	overlay.set_enabled(false)
	_check("net_hunt_end_keeps_input_off", not overlay.is_open() and not me.input_enabled)
	overlay.set_enabled(true)
	me.input_enabled = true
	# Abandon: two presses, one request, input stays off, nothing paused.
	overlay.open()
	var count_before: int = _abandon_count
	overlay._on_abandon_pressed()
	_check("net_abandon_armed", button.text == "Toque de novo para confirmar" and _abandon_count == count_before)
	overlay._on_abandon_pressed()
	_check("net_abandon_emits", _abandon_count == count_before + 1 and not overlay.is_open() and not me.input_enabled
		and not get_tree().paused)
	# Solo abandon still closes and unpauses.
	overlay.debug_role = -1
	me.input_enabled = true
	overlay.open()
	overlay._on_abandon_pressed()
	overlay._on_abandon_pressed()
	_check("solo_abandon_emits", _abandon_count == count_before + 2 and not get_tree().paused and me.input_enabled)
	GameEvents.hunt_abandon_requested.disconnect(_on_abandon)
	overlay.queue_free()
	me.free()
