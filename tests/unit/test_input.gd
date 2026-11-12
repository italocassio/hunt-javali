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


func _touch_event(pressed: bool, index: int = 0) -> InputEventScreenTouch:
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = index
	ev.position = Vector2(300.0, 300.0)
	return ev


func _drag_event(index: int = 0, rel: Vector2 = Vector2(5.0, 0.0), pos: Vector2 = Vector2(300.0, 300.0)) -> InputEventScreenDrag:
	var ev: InputEventScreenDrag = InputEventScreenDrag.new()
	ev.index = index
	ev.relative = rel
	ev.position = pos
	return ev


## Real seconds: the touch window is wall-clock based (Time.get_ticks_msec).
func _wait_touch_window() -> void:
	await tree().create_timer(InputSetup.TOUCH_RECENT_S + 0.1).timeout


func test_hybrid_device_real_click_switches_to_mouse_and_fires() -> void:
	## Hybrid device (touchscreen + mouse): in "auto" with touch mode on and no recent touch, a real left
	## click without any prior mouse motion switches to mouse mode and fires at once.
	_begin_input_test("auto")
	InputSetup._input(_touch_event(true))
	InputSetup._input(_touch_event(false))
	ok(InputSetup.is_touch_mode(), "pre-condicao: modo toque ligado")
	await _wait_touch_window()
	ok(not InputSetup.is_touch_active(), "janela de toque recente expirou")
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true))
	ok(not InputSetup.is_touch_mode(), "clique real sai do modo toque")
	ok(Input.is_action_pressed("fire"), "o mesmo clique dispara fire")
	eq(rec["count"], 1, "touch_mode_changed emitido uma vez")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, false))
	ok(not Input.is_action_pressed("fire"), "soltar libera fire")
	_end_input_test()


func test_auto_mode_switches_with_device() -> void:
	_begin_input_test("auto")
	InputSetup._input(_touch_event(true))
	ok(InputSetup.is_touch_mode(), "toque real liga o modo toque")
	InputSetup._input(_touch_event(false))
	await _wait_touch_window()
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_mouse_motion(Vector2(0.5, 0.0)))
	ok(InputSetup.is_touch_mode(), "tremida de 0,5 px nao troca para mouse")
	InputSetup._input(_mouse_motion(Vector2(30.0, 0.0), InputEvent.DEVICE_ID_EMULATION))
	ok(InputSetup.is_touch_mode(), "movimento emulado nao troca para mouse")
	InputSetup._input(_mouse_motion(Vector2(30.0, 0.0)))
	ok(not InputSetup.is_touch_mode(), "movimento real do mouse (sem toque recente) volta ao modo mouse")
	eq(rec["count"], 1, "touch_mode_changed emitido uma vez")
	InputSetup._input(_touch_event(true))
	ok(InputSetup.is_touch_mode(), "toque volta ao modo toque")
	InputSetup._input(_touch_event(false))
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputSetup._input(key)
	ok(not InputSetup.is_touch_mode(), "tecla volta ao modo mouse/teclado")
	_end_input_test()


func test_finger_down_real_mouse_motion_does_not_leave_touch_mode() -> void:
	## On the Web the mouse events synthesized from a finger arrive with device 0.
	_begin_input_test("auto")
	InputSetup._input(_touch_event(true))
	ok(InputSetup.is_touch_active(), "dedo na tela: toque ativo")
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_mouse_motion(Vector2(80.0, 40.0), 0))
	ok(InputSetup.is_touch_mode(), "movimento de mouse (device 0, grande) com dedo na tela nao desliga o modo toque")
	eq(rec["count"], 0, "touch_mode_changed nao emitido")
	_end_input_test()


func test_finger_down_mouse_click_does_not_fire_or_switch() -> void:
	_begin_input_test("auto")
	InputSetup._input(_touch_event(true))
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true, 0))
	ok(not Input.is_action_pressed("fire"), "com dedo na tela, clique esquerdo (device 0) nao pressiona fire")
	ok(InputSetup.is_touch_mode(), "com dedo na tela, clique nao troca o modo")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_RIGHT, true, 0))
	ok(not Input.is_action_pressed("aim"), "com dedo na tela, clique direito nao mira")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, 0))
	ok(not Input.is_action_pressed("zoom_in"), "com dedo na tela, roda emulada nao da zoom")
	# Just after lifting the finger (inside the window) the synthesized events still count as emulated.
	InputSetup._input(_touch_event(false))
	ok(InputSetup.is_touch_active(), "logo apos soltar o dedo o toque ainda esta ativo")
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true, 0))
	ok(not Input.is_action_pressed("fire"), "dentro da janela apos soltar: clique nao pressiona fire")
	ok(InputSetup.is_touch_mode(), "dentro da janela apos soltar: modo toque mantido")
	InputSetup._input(_mouse_motion(Vector2(90.0, 0.0), 0))
	ok(InputSetup.is_touch_mode(), "dentro da janela apos soltar: movimento nao troca o modo")
	eq(rec["count"], 0, "touch_mode_changed nao emitido")
	# After the window the same click is a real mouse again.
	await _wait_touch_window()
	InputSetup._input(_mouse_button(MOUSE_BUTTON_LEFT, true, 0))
	ok(Input.is_action_pressed("fire"), "depois da janela o clique volta a valer")
	_end_input_test()


func test_screen_drag_alone_turns_touch_mode_on() -> void:
	_begin_input_test("auto")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W
	InputSetup._input(key)
	ok(not InputSetup.is_touch_mode(), "pre-condicao: modo mouse/teclado")
	var rec: Dictionary = record_signal(GameEvents.touch_mode_changed)
	InputSetup._input(_drag_event())
	ok(InputSetup.is_touch_mode(), "ScreenDrag sozinho liga o modo toque em auto")
	ok(InputSetup.is_touch_active(), "ScreenDrag marca toque ativo")
	eq(rec["count"], 1, "touch_mode_changed emitido uma vez")
	_end_input_test()


func test_override_getter_and_forced_off_ignores_drag() -> void:
	_begin_input_test("off")
	eq(InputSetup.get_touch_override(), "off", "get_touch_override")
	InputSetup._input(_drag_event())
	ok(not InputSetup.is_touch_mode(), "override 'off' nao liga com ScreenDrag")
	InputSetup.set_touch_override("auto")
	eq(InputSetup.get_touch_override(), "auto", "get_touch_override apos mudar")
	_end_input_test()


## Spot in the free area (no button, no stick, no slider) where a finger becomes the look finger.
func _free_spot(tc: TouchControls) -> Vector2:
	var size_px: Vector2 = tc.get_viewport().get_visible_rect().size
	return Vector2(size_px.x * 0.6, size_px.y * 0.3)


func _press_at(tc: TouchControls, finger: int, pos: Vector2) -> void:
	var ev: InputEventScreenTouch = _touch_event(true, finger)
	ev.position = pos
	tc._input(ev)


## Finger ids outside the usual 0..N (WebKit sends negative or huge ids): the bug that left the hunter
## standing still on iPhone. TouchControls is instantiated by class and fed events directly.
## The stick is FIXED now: presses must start near `joystick.rest_center`.
func test_touch_controls_negative_finger_id_drives_joystick_and_look() -> void:
	_begin_input_test("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	await frames(2)
	var stick: Vector2 = tc.joystick.rest_center + Vector2(20.0, -10.0)
	var right: Vector2 = _free_spot(tc)
	var finger: int = -1
	_press_at(tc, finger, stick)
	ok(tc.joystick.is_active(), "dedo com index -1 ativa o joystick")
	tc._input(_drag_event(finger, Vector2.ZERO, stick + Vector2(0.0, -80.0)))
	await frames(2)
	ok(Input.is_action_pressed("move_forward"), "arrastar para cima pressiona move_forward")
	tc._input(_touch_event(false, finger))
	await frames(1)
	ok(not tc.joystick.is_active(), "soltar libera o joystick")
	ok(not Input.is_action_pressed("move_forward"), "soltar libera move_forward")
	# Look pad with a huge negative id.
	var looks: Array = []
	tc.look_pad.look.connect(func(rel: Vector2) -> void: looks.append(rel))
	var big: int = -2147483000
	_press_at(tc, big, right)
	ok(tc.look_pad.is_active(), "dedo com id gigante negativo ativa o olhar")
	tc._input(_drag_event(big, Vector2(12.0, 3.0), right + Vector2(12.0, 3.0)))
	eq(looks.size(), 1, "arrasto emite look uma vez")
	if looks.size() == 1:
		eq(looks[0], Vector2(12.0, 3.0), "delta do olhar (calculado pela posicao)")
	tc._input(_touch_event(false, big))
	ok(not tc.look_pad.is_active(), "soltar libera o olhar")
	# Two fingers at once, one negative and one positive: each widget keeps its own finger.
	_press_at(tc, -7, stick)
	_press_at(tc, 3, right)
	ok(tc.joystick.is_active() and tc.look_pad.is_active(), "multitoque: joystick e olhar ao mesmo tempo")
	tc._input(_touch_event(false, -7))
	ok(not tc.joystick.is_active() and tc.look_pad.is_active(), "soltar o do joystick nao solta o olhar")
	tc._input(_touch_event(false, 3))
	_end_input_test()


func test_touch_controls_fixed_joystick_activation_area() -> void:
	_begin_input_test("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	await frames(2)
	var center: Vector2 = tc.joystick.rest_center
	var active_r: float = tc.joystick.radius_px * tc.joystick.active_mult
	eq(center.x, TouchControls.JOYSTICK_CENTER_FROM_LEFT_PX, "centro do joystick: 190 px da esquerda")
	near(center.y, tc.get_viewport().get_visible_rect().size.y - TouchControls.JOYSTICK_CENTER_FROM_BOTTOM_PX, 0.01, "centro do joystick: 160 px do fundo")
	_press_at(tc, 1, center + Vector2(active_r - 6.0, 0.0))
	ok(tc.joystick.is_active() and not tc.look_pad.is_active(), "toque logo dentro da area ativa: joystick")
	tc._input(_touch_event(false, 1))
	_press_at(tc, 1, center + Vector2(active_r + 6.0, 0.0))
	ok(not tc.joystick.is_active() and tc.look_pad.is_active(), "toque logo fora da area ativa: olhar")
	tc._input(_touch_event(false, 1))
	# Left half, mid height, far from the stick: must look, never grab the stick.
	var mid_left: Vector2 = Vector2(center.x - 100.0, center.y - 300.0)
	_press_at(tc, 1, mid_left)
	ok(not tc.joystick.is_active() and tc.look_pad.is_active(), "metade esquerda longe do centro: olhar")
	# A second finger on the stick still works while the first one looks (one look finger at a time).
	_press_at(tc, 2, center)
	ok(tc.joystick.is_active(), "com um dedo olhando, o joystick ainda pega o segundo dedo")
	_press_at(tc, 3, _free_spot(tc))
	eq(tc.look_pad.get_finger(), tc._slot_of[1], "um dedo de olhar por vez: o terceiro dedo e ignorado")
	tc._input(_touch_event(false, 1))
	tc._input(_touch_event(false, 2))
	tc._input(_touch_event(false, 3))
	_end_input_test()


## The reported bug: walking with one finger while turning with another made the camera jump up/down
## because Godot Web fills ScreenDrag.relative against ANOTHER finger's last position. TouchControls must
## derive the delta from the finger's own positions, so wrong `relative` values change nothing.
func test_touch_look_delta_ignores_wrong_relative_with_two_fingers() -> void:
	_begin_input_test("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	await frames(2)
	var looks: Array = []
	tc.look_pad.look.connect(func(rel: Vector2) -> void: looks.append(rel))
	var stick: Vector2 = tc.joystick.rest_center + Vector2(0.0, -20.0)
	var look_start: Vector2 = _free_spot(tc)
	_press_at(tc, 11, stick)       # stick finger
	_press_at(tc, 22, look_start)  # look finger
	ok(tc.joystick.is_active() and tc.look_pad.is_active(), "pre-condicao: os dois dedos presos")
	var sum: Vector2 = Vector2.ZERO
	for i: int in range(1, 11):
		# Stick finger jitters; its relative is garbage (what the other finger's move would produce).
		tc._input(_drag_event(11, Vector2(0.0, 40.0), stick + Vector2(sin(float(i)) * 3.0, -float(i))))
		# Look finger moves ONLY horizontally by 8 px per event, but the platform reports a wrong relative.
		tc._input(_drag_event(22, Vector2(3.0, -35.0), look_start + Vector2(8.0 * float(i), 0.0)))
	for rel: Vector2 in looks:
		sum += rel
	eq(looks.size(), 10, "um evento de olhar por arrasto do dedo de olhar (o do joystick nao olha)")
	near(sum.x, 80.0, 0.001, "soma horizontal = distancia arrastada")
	near(sum.y, 0.0, 0.001, "soma vertical = 0: o relative errado nao muda o pitch")
	for rel: Vector2 in looks:
		near(rel.y, 0.0, 0.001, "cada delta e puramente horizontal")
	# Same dragging with the events in the opposite interleaving (look finger first).
	looks.clear()
	for i: int in range(11, 16):
		tc._input(_drag_event(22, Vector2(-9.0, 50.0), look_start + Vector2(8.0 * float(i), 0.0)))
		tc._input(_drag_event(11, Vector2(7.0, 7.0), stick))
	near(_sum_y(looks), 0.0, 0.001, "ordem invertida: pitch continua 0")
	tc._input(_touch_event(false, 11))
	tc._input(_touch_event(false, 22))
	_end_input_test()


func _sum_y(deltas: Array) -> float:
	var total: float = 0.0
	for d: Vector2 in deltas:
		total += d.y
	return total


func test_touch_look_delta_is_clamped_per_event() -> void:
	_begin_input_test("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	await frames(2)
	var looks: Array = []
	tc.look_pad.look.connect(func(rel: Vector2) -> void: looks.append(rel))
	var start: Vector2 = _free_spot(tc)
	_press_at(tc, 5, start)
	tc._input(_drag_event(5, Vector2.ZERO, start + Vector2(2000.0, 0.0)))
	eq(looks.size(), 1, "um evento de olhar")
	if looks.size() == 1:
		near((looks[0] as Vector2).length(), tc._max_delta_px, 0.001, "salto de 2000 px limitado a touch_max_delta_px")
	tc._input(_touch_event(false, 5))
	_end_input_test()


func test_touch_run_lock_survives_finger_lift_and_unlocks_on_touch() -> void:
	_begin_input_test("on")
	var tc: TouchControls = TouchControls.new()
	track(tc)
	await frames(2)
	var center: Vector2 = tc.joystick.rest_center
	var r: float = tc.joystick.radius_px
	_press_at(tc, 1, center)
	tc._input(_drag_event(1, Vector2.ZERO, center + Vector2(0.0, -r * 1.2)))
	ok(not tc.joystick.run_locked, "dentro de 1,2 x raio ainda nao trava a corrida")
	tc._input(_drag_event(1, Vector2.ZERO, center + Vector2(0.0, -r * (tc.joystick.run_lock_mult + 0.3))))
	ok(tc.joystick.run_locked, "empurrar alem de 1,8 x raio para cima trava a corrida")
	tc._input(_touch_event(false, 1))
	ok(tc.joystick.run_locked, "soltar o dedo mantem a corrida travada")
	ok(not tc.joystick.is_active(), "joystick inativo com o dedo solto")
	ok(Input.is_action_pressed("move_forward") and Input.is_action_pressed("sprint"), "travada: anda para frente e corre sem dedo")
	_press_at(tc, 1, center)
	ok(not tc.joystick.run_locked, "tocar o joystick de novo destrava")
	tc._input(_touch_event(false, 1))
	ok(not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("sprint"), "destravada e solta: para")
	# Pushing sideways far away must NOT lock (only mostly-upward pushes do).
	_press_at(tc, 1, center)
	tc._input(_drag_event(1, Vector2.ZERO, center + Vector2(r * 2.5, -r * 2.0)))
	ok(not tc.joystick.run_locked, "empurrar quase na horizontal nao trava")
	tc._input(_touch_event(false, 1))
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
