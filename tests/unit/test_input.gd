extends "res://tests/lib/test_case.gd"
## InputSetup: real mouse vs emulated mouse (touch), touch mode switching, wheel pulses, release on scene change.
## Events are fed straight into InputSetup._input (headless has no real devices).

var _saved_override: String = "auto"


func _mouse_button(index: int, pressed: bool, device: int = 0) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = index as MouseButton
	ev.pressed = pressed
	ev.device = device
	return ev


func _mouse_motion(rel: Vector2, device: int = 0) -> InputEventMouseMotion:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = rel
	ev.device = device
	return ev


func _begin_input_test(mode: String) -> void:
	InputSetup.release_all_actions()
	InputSetup.set_touch_override(mode)


func _end_input_test() -> void:
	InputSetup.release_all_actions()
	InputSetup.set_touch_override("auto")


func test_all_actions_registered() -> void:
	for action_name: String in InputSetup.ACTIONS:
		ok(InputMap.has_action(action_name), "acao %s registrada" % action_name)
	ok(not InputMap.action_get_events("fire").has(null), "fire sem eventos nulos")
	# Mouse actions are injected in code, keyboard ones come from the map.
	eq(InputMap.action_get_events("fire").size(), 0, "fire nao tem tecla (vem do mouse/toque)")
	ok(InputMap.action_get_events("move_forward").size() >= 2, "move_forward: W e seta")
	ok(InputMap.action_get_events("pause").size() >= 2, "pause: Esc e P")


func test_real_mouse_fires_in_mouse_mode() -> void:
	_begin_input_test("off")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true))
	ok(Input.is_action_pressed("fire"), "botao esquerdo real aperta fire")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, false))
	ok(not Input.is_action_pressed("fire"), "soltar libera fire")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_RIGHT, true))
	ok(Input.is_action_pressed("aim"), "botao direito aperta aim")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_RIGHT, false))
	ok(not Input.is_action_pressed("aim"), "soltar libera aim")
	_end_input_test()


func test_emulated_mouse_from_touch_does_not_fire() -> void:
	## emulate_mouse_from_touch is on: a finger tap also arrives as a mouse button (device = emulation).
	_begin_input_test("off")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true, InputEvent.DEVICE_ID_EMULATION))
	ok(not Input.is_action_pressed("fire"), "toque emulado como mouse nao dispara fire (o botao de toque dispara)")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_RIGHT, true, InputEvent.DEVICE_ID_EMULATION))
	ok(not Input.is_action_pressed("aim"), "toque emulado nao mira")
	_end_input_test()


func test_forced_touch_mode_ignores_real_mouse_buttons() -> void:
	## Override "on" is an explicit user choice: real mouse buttons stay ignored.
	_begin_input_test("on")
	ok(InputSetup.is_touch_mode(), "modo toque ligado")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true))
	ok(not Input.is_action_pressed("fire"), "override 'on': mouse real nao dispara")
	ok(InputSetup.is_touch_mode(), "override 'on': continua em modo toque")
	_end_input_test()


func test_hybrid_device_real_click_switches_to_mouse_and_fires() -> void:
	## Hybrid device (touchscreen + mouse): in "auto" with touch mode on, a real left click without any
	## prior mouse motion must switch to mouse mode and fire at once.
	_begin_input_test("auto")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	InputSetup._input(touch)
	ok(InputSetup.is_touch_mode(), "pre-condicao: modo toque ligado")
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true))
	ok(not InputSetup.is_touch_mode(), "clique real sai do modo toque")
	ok(Input.is_action_pressed("fire"), "o mesmo clique dispara fire")
	eq(rec["count"], 1, "touch_mode_changed emitido uma vez")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, false))
	ok(not Input.is_action_pressed("fire"), "soltar libera fire")
	# The emulated mouse click that a finger tap produces must not switch modes nor fire.
	InputSetup._input(touch)
	ok(InputSetup.is_touch_mode(), "toque volta ao modo toque")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true, InputEvent.DEVICE_ID_EMULATION))
	ok(InputSetup.is_touch_mode(), "clique emulado nao sai do modo toque")
	ok(not Input.is_action_pressed("fire"), "clique emulado nao dispara")
	_end_input_test()


func test_auto_mode_switches_with_device() -> void:
	_begin_input_test("auto")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	InputSetup._input(touch)
	ok(InputSetup.is_touch_mode(), "toque real liga o modo toque")
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_mouse_motion(Vector2(0.5, 0.0)))
	ok(InputSetup.is_touch_mode(), "tremida de 0,5 px nao troca para mouse")
	InputSetup._input(_mouse_motion(Vector2(30.0, 0.0), InputEvent.DEVICE_ID_EMULATION))
	ok(InputSetup.is_touch_mode(), "movimento emulado nao troca para mouse")
	InputSetup._input(_mouse_motion(Vector2(30.0, 0.0)))
	ok(not InputSetup.is_touch_mode(), "movimento real do mouse volta ao modo mouse")
	eq(rec["count"], 1, "touch_mode_changed emitido uma vez")
	InputSetup._input(touch)
	ok(InputSetup.is_touch_mode(), "toque volta ao modo toque")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputSetup._input(key)
	ok(not InputSetup.is_touch_mode(), "tecla volta ao modo mouse/teclado")
	_end_input_test()


func test_forced_modes_ignore_device_events() -> void:
	_begin_input_test("on")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W
	InputSetup._input(key)
	ok(InputSetup.is_touch_mode(), "override 'on' nao muda com teclado")
	InputSetup.set_touch_override("off")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	InputSetup._input(touch)
	ok(not InputSetup.is_touch_mode(), "override 'off' nao muda com toque")
	expect_errors()
	InputSetup.set_touch_override("invalido")
	ok(not InputSetup.is_touch_mode(), "override invalido ignorado")
	_end_input_test()


func test_wheel_pulses_once_per_frame() -> void:
	_begin_input_test("off")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true))
	ok(Input.is_action_pressed("zoom_in"), "roda para cima aperta zoom_in")
	await frames(3)
	ok(not Input.is_action_pressed("zoom_in"), "zoom_in solto depois de alguns frames")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true))
	ok(Input.is_action_pressed("zoom_out"), "roda para baixo aperta zoom_out")
	await frames(3)
	ok(not Input.is_action_pressed("zoom_out"), "zoom_out solto")
	_end_input_test()


func test_release_all_actions() -> void:
	_begin_input_test("off")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true))
	Input.action_press("move_forward")
	Input.action_press("sprint")
	InputSetup.release_all_actions()
	for action_name: String in InputSetup.ACTIONS:
		ok(not Input.is_action_pressed(action_name), "%s solta apos release_all_actions (troca de cena)" % action_name)
	_end_input_test()


func test_router_goto_releases_actions_and_unpauses() -> void:
	expect_errors()   # unknown scene path logs an error by design
	Input.action_press("fire")
	tree().paused = true
	Router.goto("res://nao_existe.tscn")
	ok(not Input.is_action_pressed("fire"), "goto solta as acoes")
	ok(not tree().paused, "goto despausa a arvore")
	eq(Router.get_current_scene_path() != "res://nao_existe.tscn", true, "cena inexistente nao e carregada")
