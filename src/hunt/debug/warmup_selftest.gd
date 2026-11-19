extends Node
## Shader warm-up + loading progress self-test (docs/arquitetura.md section 8.1): runs hunt.tscn headless with a dog and
## the thermal scope and checks that the warm-up changes no game state, restores the spawn orientation, reveals the whole
## world and leaves the progress at 1.
## Usage: tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/warmup_selftest.tscn
## Not part of the game; the qa-tester owns the real tests in tests/.

var _passed: int = 0
var _failed: int = 0
var _hunt: HuntController = null
var _gameplay_signals: int = 0
var _started_checked: bool = false
var _frames_before_start: int = 0
var _input_closed_frames: int = 0
var _frames_with_player: int = 0
var _player_frames: int = 0
var _boars_before_start: int = 0
var _yaws: Dictionary = {}
var _saw_stage: bool = false


func _ready() -> void:
	GameEvents.boar_hit.connect(func(_a: int, _b: StringName, _c: float, _d: Vector3, _e: int) -> void: _gameplay_signals += 1)
	GameEvents.boar_killed.connect(func(_k: KillInfo) -> void: _gameplay_signals += 1)
	GameEvents.shot_fired.connect(func(_w: StringName, _o: Vector3, _d: Vector3, _n: float) -> void: _gameplay_signals += 1)
	GameEvents.boar_counts_changed.connect(func(_k: int, _t: int) -> void: _gameplay_signals += 1)
	GameEvents.hunt_started.connect(_on_started)
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0)
	req.rng_seed = 777
	req.dog_id = &"caramelo"
	req.item_ids = [Ids.I_THERMAL_SCOPE] as Array[StringName]
	req.quality = Ids.Q_MEDIUM
	Router.set_pending_request(req)
	_hunt = (load(ScenePaths.HUNT) as PackedScene).instantiate() as HuntController
	_hunt.route_on_finish = false
	add_child(_hunt)
	var t0: int = Time.get_ticks_msec()
	while not _hunt.is_world_ready():
		_watch()
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 60000:
			break
	_check("hunt_became_ready", _hunt.is_world_ready())
	_check("hunt_started_seen", _started_checked)
	_check("warmup_took_frames", _frames_before_start > 10, "frames=%d" % _frames_before_start)
	_check("stage_was_shown_and_freed", _saw_stage and _hunt.get_node_or_null(^"ShaderWarmupStage") == null)
	_check("player_input_closed_during", _player_frames > 10 and _input_closed_frames == _player_frames,
		"%d/%d" % [_input_closed_frames, _player_frames])
	_check("no_boar_during", _boars_before_start == 0)
	_check("no_gameplay_signal_during", _gameplay_signals <= 1, "n=%d" % _gameplay_signals)   # the single boar_counts_changed at start
	_check("camera_turned_during_warmup", _yaws.size() >= 4, str(_yaws.keys()))
	_check("overlay_hidden", not (_hunt.get_node(^"LoadingOverlay") as CanvasLayer).visible)
	_check("player_input_open_after", bool(_hunt.get_player().get("_input_enabled")))
	var hist: PackedFloat32Array = (_hunt.get("_progress") as LoadingProgress).get_history()
	var mono: bool = true
	for i: int in range(1, hist.size()):
		mono = mono and hist[i] > hist[i - 1]
	_check("progress_strictly_increasing_to_1", mono and hist.size() > 10 and is_equal_approx(hist[hist.size() - 1], 1.0),
		"n=%d last=%s" % [hist.size(), str(hist[hist.size() - 1]) if hist.size() > 0 else "-"])
	print("RESULT: %d passed, %d failed, 0 skipped" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _watch() -> void:
	if _hunt == null or _started_checked:
		return
	_frames_before_start += 1
	var player: PlayerBase = _hunt.get_player()
	if player != null:
		_player_frames += 1
		if not bool(player.get("_input_enabled")):
			_input_closed_frames += 1
		_yaws[snappedf(player.rotation.y, 0.001)] = true
	if _hunt.get_node_or_null(^"ShaderWarmupStage") != null:
		_saw_stage = true
	_boars_before_start = maxi(_boars_before_start, _hunt.get_alive_boar_ids().size())


func _on_started(_r: HuntRequest) -> void:
	_started_checked = true
	var map: MapRoot = _hunt.get_node(^"Map") as MapRoot
	var spawn: Marker3D = map.get_player_spawn()
	var player: PlayerBase = _hunt.get_player()
	_check("yaw_restored_exactly", player.rotation.y == spawn.global_rotation.y, "%s vs %s" % [player.rotation.y, spawn.global_rotation.y])
	var hidden: Array[String] = []
	for n: Node3D in [map.terrain, map.flora, map.get_node(^"Water"), map.get_node(^"PropSpawns"), _hunt.crop, _hunt.get_dog_of(0)]:
		if n == null or not n.visible:
			hidden.append(str(n))
	for c: Node in map.get_children():
		if c is MultiMeshInstance3D and not (c as MultiMeshInstance3D).visible:
			hidden.append(c.name)
	_check("world_fully_visible", hidden.is_empty(), str(hidden))
	_check("progress_is_1_before_hide", is_equal_approx((_hunt.get("_progress") as LoadingProgress).get_value(), 1.0))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])
