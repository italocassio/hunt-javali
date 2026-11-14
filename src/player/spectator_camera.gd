class_name SpectatorCamera
extends Camera3D
## Spectator view of a fallen local hunter (docs/multiplayer.md 6.8). Online only: once coop.spectate_delay_s has
## passed since the fall and an ally is still standing, it takes over as the current camera, third person behind
## that ally (coop.spectate_distance_m back, coop.spectate_height_m above the feet, never under the terrain).
## Fire / item-next / swap (click, F, the touch buttons) cycle through the standing allies; when the followed ally
## falls or leaves, it moves to another one; with nobody left it hands the view back and the hunt is about to end.
## Solo never reaches this node: the Player only creates it when an ally is standing at the moment of the fall.
## Emits GameEvents.spectate_changed(slot) on start and on every change of target, -1 when it lets go.

const SWITCH_ACTIONS: Array[StringName] = [&"fire", &"item_next", &"weapon_swap"]
const POSE_RATE: float = 9.0              # 1/s of the exponential catch-up of position and angles
const PITCH_FOLLOW: float = 0.5           # fraction of the ally's look pitch the camera copies
const MAX_PITCH_DEG: float = 20.0         # keeps the followed ally inside the frame
const GROUND_CLEARANCE_M: float = 0.5
const NO_TARGET: int = -1

var _world: HuntWorld = null
var _local: PlayerBase = null
var _return_camera: Camera3D = null
var _delay_left_s: float = 0.0
var _active: bool = false
var _target_slot: int = NO_TARGET
var _menu_open: bool = false
var _distance_m: float = 3.5
var _height_m: float = 2.0
var _pos: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0


func _init() -> void:
	top_level = true                 # the pose is in world space: nothing inherited from the Player body
	process_priority = 100           # after the remote hunters moved this frame
	current = false


func _ready() -> void:
	GameEvents.hunter_died.connect(_on_hunter_gone)
	GameEvents.hunter_left.connect(_on_hunter_gone)
	GameEvents.hunt_paused_changed.connect(_on_paused_changed)
	set_process(false)


## Starts the countdown to the first view. `view_camera` is the Player's own camera: its lens (fov, near, far)
## is copied and it becomes current again if this view ends.
func begin(local: PlayerBase, world: HuntWorld, view_camera: Camera3D) -> void:
	_local = local
	_world = world
	_return_camera = view_camera
	var coop: Dictionary = Data.get_game().get("coop", {})
	_delay_left_s = float(coop.get("spectate_delay_s", 2.0))
	_distance_m = float(coop.get("spectate_distance_m", 3.5))
	_height_m = float(coop.get("spectate_height_m", 2.0))
	fov = float(Data.get_game().get("player", {}).get("base_fov_deg", 75.0))
	if view_camera != null:
		near = view_camera.near
		far = view_camera.far
	set_process(true)


## True while this view is the current camera.
func is_active() -> bool:
	return _active


## Slot of the ally being followed, -1 when not active.
func get_target_slot() -> int:
	return _target_slot if _active else NO_TARGET


## Standing, present allies of the local hunter, by slot. Allocates: call on events, not every frame.
func get_candidates() -> Array[PlayerBase]:
	var out: Array[PlayerBase] = []
	if _world == null:
		return out
	for hunter: PlayerBase in _world.get_hunters():
		if _is_candidate(hunter):
			out.append(hunter)
	out.sort_custom(func(a: PlayerBase, b: PlayerBase) -> bool: return a.slot < b.slot)
	return out


## Moves to the next standing ally (wraps around). Returns false when there is no other one to go to.
func switch_target() -> bool:
	if not _active:
		return false
	var candidates: Array[PlayerBase] = get_candidates()
	var next: PlayerBase = _next_after(candidates, _target_slot)
	if next == null or next.slot == _target_slot:
		return false
	_set_target(next)
	return true


func _is_candidate(hunter: PlayerBase) -> bool:
	return hunter != null and is_instance_valid(hunter) and hunter != _local and not hunter.is_local() \
		and hunter.is_alive() and hunter.is_present()


## First candidate with a slot above `slot`, else the lowest one. `candidates` is sorted by slot.
func _next_after(candidates: Array[PlayerBase], slot: int) -> PlayerBase:
	if candidates.is_empty():
		return null
	for hunter: PlayerBase in candidates:
		if hunter.slot > slot:
			return hunter
	return candidates[0]


func _followed() -> PlayerBase:
	if _world == null or _target_slot == NO_TARGET:
		return null
	var hunter: PlayerBase = _world.get_hunter(_target_slot)
	if hunter == null or hunter.slot != _target_slot:   # the base world answers any slot with the local hunter
		return null
	return hunter


func _process(delta: float) -> void:
	if not _active:
		_delay_left_s -= delta
		if _delay_left_s <= 0.0:
			_activate()
		return
	var target: PlayerBase = _followed()
	if not _is_candidate(target):
		_retarget()
		target = _followed()
		if not _active:
			return
	elif not _menu_open and _switch_pressed():
		switch_target()
		target = _followed()
	_follow(target, delta)


func _switch_pressed() -> bool:
	for action_name: StringName in SWITCH_ACTIONS:
		if Input.is_action_just_pressed(action_name):
			return true
	return false


func _activate() -> void:
	var first: PlayerBase = _next_after(get_candidates(), NO_TARGET)
	if first == null:
		set_process(false)   # nobody left to watch: the hunt ends on its own
		return
	_active = true
	_set_target(first)
	_snap_to(first)
	make_current()
	set_process(true)


func _set_target(hunter: PlayerBase) -> void:
	_target_slot = hunter.slot
	GameEvents.spectate_changed.emit(_target_slot)


func _on_hunter_gone(slot: int) -> void:
	if _active and slot == _target_slot and not _is_candidate(_followed()):
		_retarget()


## The followed ally fell, left or went silent: another standing one, or give the view back.
func _retarget() -> void:
	var next: PlayerBase = _next_after(get_candidates(), _target_slot)
	if next != null:
		_set_target(next)
		return
	_active = false
	_target_slot = NO_TARGET
	set_process(false)
	if _return_camera != null and is_instance_valid(_return_camera):
		_return_camera.make_current()
	GameEvents.spectate_changed.emit(NO_TARGET)


func _on_paused_changed(paused: bool) -> void:
	_menu_open = paused


# ---------------------------------------------------------------------------
# Pose
# ---------------------------------------------------------------------------

func _desired_pose(target: PlayerBase) -> Dictionary:
	var yaw: float = target.global_rotation.y
	var look: Vector3 = target.get_look_direction()
	var max_pitch: float = deg_to_rad(MAX_PITCH_DEG)
	var pitch: float = clampf(asin(clampf(look.y, -1.0, 1.0)) * PITCH_FOLLOW, -max_pitch, max_pitch)
	var back: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))   # opposite of the forward (-sin, 0, -cos)
	var p: Vector3 = target.global_position + back * _distance_m + Vector3.UP * _height_m
	var floor_y: float = _world.get_height(p.x, p.z) + GROUND_CLEARANCE_M
	p.y = maxf(p.y, floor_y)
	return {"pos": p, "yaw": yaw, "pitch": pitch}


func _snap_to(target: PlayerBase) -> void:
	var pose: Dictionary = _desired_pose(target)
	_pos = pose["pos"]
	_yaw = float(pose["yaw"])
	_pitch = float(pose["pitch"])
	_apply_pose()


func _follow(target: PlayerBase, delta: float) -> void:
	var pose: Dictionary = _desired_pose(target)
	var k: float = 1.0 - exp(-POSE_RATE * delta)
	_pos = _pos.lerp(pose["pos"], k)
	_yaw = lerp_angle(_yaw, float(pose["yaw"]), k)
	_pitch = lerpf(_pitch, float(pose["pitch"]), k)
	# Catching up with a moving target must not dip below the terrain either.
	_pos.y = maxf(_pos.y, _world.get_height(_pos.x, _pos.z) + GROUND_CLEARANCE_M)
	_apply_pose()


func _apply_pose() -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), _pos)
