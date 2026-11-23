extends Node
## Windowed screenshots of the item gestures (docs/plano_itens_animados.md 3, items 2 and 3). Needs a window.
## Runs the player sandbox, waits for the gesture of one item and saves a PNG at each requested progress, then quits.
## Lives in a scene (not a -s script) so the autoloads exist when the sandbox scripts compile.
## Usage (from the project root):
##   tools/godot.sh --path . --windowed --resolution 1280x720 res://tests/shots/item_shot.tscn -- \
##       --item_use=medkit --hp=50 --out=C:/abs/dir/medkit [--at=0.25,0.5,0.75]
##   drone in the air (the sandbox has no HuntController, so the same ScoutDrone.launch call is made here):
##       --item_use=scout_drone --out=C:/abs/dir/drone --air=0.8
## --at   gesture progress points (0..1) of the shots; files are <out>_<n>.png. Default 0.5.
## --air  seconds of the drone's age at which the shot is taken (looking up at it); replaces --at.
## Not part of the game.

const SANDBOX: String = "res://src/player/debug/player_sandbox.tscn"
const HARD_TIMEOUT_S: float = 40.0
const DEFAULT_AT: String = "0.5"
const DRONE_LIFE_S: float = 10.0
const SETTLE_FRAMES: int = 3

var _out: String = ""
var _ats: Array[float] = []
var _air_s: float = -1.0
var _item: StringName = &""
var _world: SandboxWorld = null
var _drone: ScoutDrone = null


func _ready() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
			args[pair[0]] = pair[1] if pair.size() > 1 else "1"
	_out = String(args.get("out", ""))
	_item = StringName(String(args.get("item_use", "")))
	if _out.is_empty() or _item == &"":
		printerr("item_shot: --out and --item_use are required")
		get_tree().quit(2)
		return
	for part: String in String(args.get("at", DEFAULT_AT)).split(",", false):
		_ats.append(float(part))
	if args.has("air"):
		_air_s = float(args["air"])
	get_tree().create_timer(HARD_TIMEOUT_S).timeout.connect(_on_timeout)
	_world = (load(SANDBOX) as PackedScene).instantiate() as SandboxWorld
	add_child(_world)
	_run.call_deferred()


func _on_timeout() -> void:
	printerr("item_shot: timed out")
	get_tree().quit(1)


func _run() -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	if _world == null or _world.player == null:
		printerr("item_shot: no sandbox player")
		get_tree().quit(1)
		return
	if _air_s >= 0.0:
		await _shoot_drone()
	else:
		await _shoot_gesture()
	get_tree().quit(0)


func _shoot_gesture() -> void:
	var player: Player = _world.player
	var next: int = 0
	while next < _ats.size():
		await get_tree().process_frame
		var items: ItemBelt = player.get_items()
		if items.get_busy_item() != _item:
			continue
		if items.get_busy_progress() >= _ats[next]:
			print("item_shot: progress %.2f hands_showing=%s" % [items.get_busy_progress(), player.get("_hands").is_showing()])
			await _save("%s_%d" % [_out, next + 1])
			next += 1


func _shoot_drone() -> void:
	var player: Player = _world.player
	var eye_m: float = float(Data.get_game().get("player", {}).get("standing_eye_height_m", 1.65))
	GameEvents.item_used.connect(func(id: StringName, at: Vector3) -> void:
		if id == Ids.I_SCOUT_DRONE and _drone == null:
			_drone = ScoutDrone.launch(_world, _world, at + Vector3(0.0, eye_m, 0.0), DRONE_LIFE_S)
			# the sandbox demo reuses the item while it has units: spend the rest so a second gesture does not enter the shot
			(player.get_items().get("_counts") as Dictionary)[_item] = 0)
	while _drone == null:
		await get_tree().process_frame
	while _drone.get_age_s() < _air_s:
		await get_tree().process_frame
	player.bot_set_enabled(true)
	player.bot_look_at(_drone.global_position)
	await get_tree().process_frame
	await get_tree().process_frame
	print("item_shot: drone at %s age %.2f, hunter at %s" % [_drone.global_position, _drone.get_age_s(), player.global_position])
	await _save("%s_1" % _out)


func _save(base: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "%s.png" % base
	var err: Error = get_viewport().get_texture().get_image().save_png(path)
	print("item_shot: saved %s (err %d)" % [path, err])
