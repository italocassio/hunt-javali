class_name ShaderWarmup
extends RefCounted
## Makes the browser compile the hunt's shaders a little at a time while the LoadingOverlay is still up
## (docs/arquitetura.md section 8.1, "Pre-aquecimento de shaders"). WebGL compiles on the main thread at the first
## draw of a material, so showing everything at once stalls one frame for many seconds. Instead:
##   1. the world parts are hidden as they are built and revealed one per frame (hide_group / run),
##   2. one visual of each boar type (and each dog breed) is shown in front of the camera, one per frame, and freed,
##   3. the camera turns through `warmup_yaw_steps` directions, one frame each, and goes back to the spawn yaw,
##   4. it waits for `settle_frames` frames in a row faster than `settle_frame_ms` (real time, ceiling `warmup_max_s`).
## It touches no game state: no spawner, no sounds, no gameplay signals. Draws only.

const STAGE_NAME: String = "ShaderWarmupStage"
const STAGE_DISTANCE_M: float = 4.5
const STAGE_DROP_M: float = 1.0
const GROUP_DOGS: StringName = &"dogs"
const DEFAULT_YAW_STEPS: int = 4
const DEFAULT_SETTLE_FRAMES: int = 3
const DEFAULT_SETTLE_MS: float = 120.0
const DEFAULT_MAX_S: float = 30.0

var _host: Node3D = null
var _tree: SceneTree = null
var _groups: Dictionary = {}          # StringName -> Array[Node3D], hidden until run()
var _order: Array[StringName] = []
var _stage: Node3D = null
var _last_us: int = 0
var _done: int = 0
var _total: int = 1
var _on_progress: Callable = Callable()
var _frames_used: int = 0
var _settle_ok: int = 0
var _timing: Array[String] = []


## `host` is the node that owns the stage (the HuntController); it must already be in the tree.
func setup(host: Node3D) -> void:
	_host = host
	_tree = host.get_tree()


## Hides `nodes` until run() reveals them (one group per frame, in the order the groups were registered).
func hide_group(group: StringName, nodes: Array) -> void:
	for n: Variant in nodes:
		var node: Node3D = n as Node3D
		if node == null or not is_instance_valid(node):
			continue
		node.visible = false
		if not _groups.has(group):
			_groups[group] = [] as Array[Node3D]
			_order.append(group)
		(_groups[group] as Array[Node3D]).append(node)


## Terrain, water, props, flora and crop of a built map (call after the crop step, before the camera is active).
## `extra_props` joins the props group (the horde barn's corn stock).
func hide_world(map: MapRoot, crop: Node3D, extra_props: Array = []) -> void:
	hide_group(&"terrain", [map.terrain])
	hide_group(&"water", [map.get_node_or_null(^"Water")])
	var props: Array = [map.get_node_or_null(^"PropSpawns")]
	for c: Node in map.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Group_"):
			props.append(c)
	props.append_array(extra_props)
	hide_group(&"props", props)
	hide_group(&"flora", [map.flora])
	hide_group(&"crop", [crop])


## Reveals everything that is still hidden (abort path and tests).
func reveal_all() -> void:
	for group: StringName in _order:
		for node: Node3D in _groups[group]:
			if is_instance_valid(node):
				node.visible = true
	_groups.clear()
	_order.clear()


func get_frames_used() -> int:
	return _frames_used


func get_settle_frames_ok() -> int:
	return _settle_ok


## Debug: "name=ms" per sub-step of the last run (real time between the frames).
func get_timing() -> Array[String]:
	return _timing


## Runs the warm-up. `breeds` = dog breeds to show (offline/host: the ones with a dog; client: the replica's).
## `with_thermal` adds the thermal highlight material. `on_progress(fraction)` is called after every sub-step.
## Returns false if the host left the tree (the hunt was abandoned while loading).
func run(player: PlayerBase, breeds: Array[StringName], with_thermal: bool, on_progress: Callable) -> bool:
	var cfg: Dictionary = Data.get_game().get("loading", {})
	var yaw_steps: int = maxi(int(cfg.get("warmup_yaw_steps", DEFAULT_YAW_STEPS)), 0)
	var settle_frames: int = maxi(int(cfg.get("settle_frames", DEFAULT_SETTLE_FRAMES)), 0)
	var settle_ms: float = float(cfg.get("settle_frame_ms", DEFAULT_SETTLE_MS))
	var max_s: float = float(cfg.get("warmup_max_s", DEFAULT_MAX_S))
	_on_progress = on_progress
	_timing.clear()
	_frames_used = 0
	var type_ids: Array = Data.get_boar_type_ids()
	var reveal_groups: Array[StringName] = []
	for group: StringName in _order:
		if group != GROUP_DOGS:
			reveal_groups.append(group)
	var dog_frames: int = breeds.size()
	if dog_frames == 0 and _groups.has(GROUP_DOGS):
		dog_frames = 1   # hidden dogs of this machine still need their frame
	_total = maxi(reveal_groups.size() + type_ids.size() + (1 if with_thermal else 0) + dog_frames + yaw_steps
		+ settle_frames, 1)
	_done = 0
	_last_us = Time.get_ticks_usec()

	# 1. World parts, one per frame, camera active.
	for group: StringName in reveal_groups:
		for node: Node3D in _groups[group]:
			if is_instance_valid(node):
				node.visible = true
		if not await _step(String(group)):
			return false
	for group: StringName in reveal_groups:
		_groups.erase(group)

	# 2. Actors in front of the camera, one per frame.
	_make_stage(player)
	var first_visual: BoarVisualBase = null
	for type_id: Variant in type_ids:
		_spawn_boar_visual(type_id as StringName)
		if not await _step("boar_%s" % type_id):
			return false
		_clear_stage()
	if with_thermal and not type_ids.is_empty():
		first_visual = _spawn_boar_visual(type_ids[0] as StringName)
		if first_visual != null:
			first_visual.set_highlight(true)
		if not await _step("thermal"):
			return false
		_clear_stage()
	var dog_nodes: Array = _groups.get(GROUP_DOGS, [])
	for i: int in dog_frames:
		for node: Variant in dog_nodes:
			if is_instance_valid(node):
				(node as Node3D).visible = true
		dog_nodes = []
		if i < breeds.size():
			_spawn_dog_visual(breeds[i])
		if not await _step("dog"):
			return false
		_clear_stage()
	_groups.erase(GROUP_DOGS)
	_free_stage()

	# 3. Turn through the directions, then back to the exact spawn orientation.
	var yaw0: float = player.rotation.y
	for i: int in range(1, yaw_steps + 1):
		player.rotation.y = yaw0 + TAU * float(i) / float(yaw_steps)
		if not await _step("yaw_%d" % i):
			player.rotation.y = yaw0
			return false
	player.rotation.y = yaw0

	# 4. Settle: consecutive frames below the threshold, real time, with a ceiling.
	var t_settle: int = Time.get_ticks_msec()
	_settle_ok = 0
	while _settle_ok < settle_frames:
		if float(Time.get_ticks_msec() - t_settle) / 1000.0 > max_s:
			push_warning("ShaderWarmup: no stable frame rate after %.0f s, going on" % max_s)
			break
		var dt_ms: float = await _frame_ms()
		if dt_ms < 0.0:
			return false
		_settle_ok = _settle_ok + 1 if dt_ms < settle_ms else 0
		_timing.append("settle=%d" % roundi(dt_ms))
		_done = _total - settle_frames + _settle_ok
		_report()
	_done = _total
	_report()
	return true


## One frame; false if the host is gone.
func _step(label: String) -> bool:
	var dt_ms: float = await _frame_ms()
	if dt_ms < 0.0:
		return false
	_timing.append("%s=%d" % [label, roundi(dt_ms)])
	_done += 1
	_report()
	return true


## Real time (ms) between the previous frame boundary and this one, which includes the draw of the previous frame
## (where the shader compilations happen). The engine's delta is clamped, so the clock is read directly.
## -1 if the host left the tree.
func _frame_ms() -> float:
	await _tree.process_frame
	if not is_instance_valid(_host) or not _host.is_inside_tree():
		return -1.0
	var now: int = Time.get_ticks_usec()
	var ms: float = float(now - _last_us) / 1000.0
	_last_us = now
	_frames_used += 1
	return ms


func _report() -> void:
	if _on_progress.is_valid():
		_on_progress.call(clampf(float(_done) / float(_total), 0.0, 1.0))


func _make_stage(player: PlayerBase) -> void:
	_stage = Node3D.new()
	_stage.name = STAGE_NAME
	_host.add_child(_stage)
	var cam: Camera3D = _host.get_viewport().get_camera_3d()
	var origin: Vector3 = cam.global_position if cam != null else player.get_eye_position()
	var forward: Vector3 = -cam.global_transform.basis.z if cam != null else player.get_look_direction()
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	_stage.global_position = origin + forward * STAGE_DISTANCE_M + Vector3.DOWN * STAGE_DROP_M
	# Faces the camera, so the animal shows its side/front like in play.
	_stage.look_at(origin * Vector3(1.0, 0.0, 1.0) + Vector3(0.0, _stage.global_position.y, 0.0), Vector3.UP)


func _clear_stage() -> void:
	if _stage == null:
		return
	for c: Node in _stage.get_children():
		_stage.remove_child(c)
		c.free()


func _free_stage() -> void:
	if _stage != null:
		_clear_stage()
		_host.remove_child(_stage)
		_stage.free()
		_stage = null


## One visual at the average weight of the type (a null scene is the fallback box: nothing to warm up).
func _spawn_boar_visual(type_id: StringName) -> BoarVisualBase:
	var def: Dictionary = Data.get_boar_type(type_id)
	var w_min: float = float(def.get("weight_min_kg", 0.0))
	var w_max: float = maxf(float(def.get("weight_max_kg", w_min)), w_min)
	var kg: float = (w_min + w_max) * 0.5
	var node: Node = AssetLoader.instantiate(ScenePaths.BOAR_VISUAL)
	var visual: BoarVisualBase = node as BoarVisualBase
	if visual == null:
		if node != null:
			node.free()
		return null
	visual.setup(type_id, kg)
	visual.scale = Vector3.ONE * BoarVisualBase.scale_for_weight(kg)
	_stage.add_child(visual)
	return visual


func _spawn_dog_visual(breed: StringName) -> void:
	var node: Node = AssetLoader.instantiate(ScenePaths.DOG_VISUAL)
	var visual: DogVisualBase = node as DogVisualBase
	if visual == null:
		if node != null:
			node.free()
		return
	visual.setup(breed)
	_stage.add_child(visual)
