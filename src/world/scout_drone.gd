class_name ScoutDrone
extends Node3D
## Scout drone as a world object (docs/plano_itens_animados.md section 2.6). Created by HuntController from
## item_used(scout_drone) on every machine, so allies see it with no network message. Purely visual: no collision,
## no light, no sound. It leaves the hand in front of the eyes, climbs while flying away forward (so it is seen
## shrinking in the first second), then flies one wide slow circle and leaves when reveal_s (data/equipment.json)
## runs out. The minimap reveal is not here (ItemBelt/HUD).

const PROP_ID: StringName = &"scout_drone"

const VISUAL_SCALE: float = 2.0        # the prop is hand-sized (0.35 m); in the sky it must still read at 8 m
const HAND_FORWARD_M: float = 1.2      # where the hand lets go, ahead of the eyes
const CLIMB_M: float = 10.0            # height gained over the launch point
const CLIMB_TIME_S: float = 1.5        # smoothed climb time
const CLIMB_FORWARD_M: float = 9.0     # distance flown forward while climbing
const MIN_CLEARANCE_M: float = 6.0     # never closer than this to the terrain below it
const ORBIT_RADIUS_M: float = 12.0
const ORBIT_SPEED_RAD_S: float = 0.4   # about 15 s per lap: slow
const LEAVE_TIME_S: float = 2.0        # the end of the life: it climbs and drifts away
const LEAVE_CLIMB_M: float = 14.0
const LEAVE_OUT_M: float = 30.0        # radius it opens by while leaving
const TURN_SPEED: float = 6.0          # yaw smoothing, 1/s

var _world: HuntWorld = null
var _life_s: float = 10.0
var _age_s: float = 0.0
var _launch: Vector3 = Vector3.ZERO
var _forward: Vector2 = Vector2(0.0, -1.0)
var _center_xz: Vector2 = Vector2.ZERO
var _angle: float = 0.0
var _spin: float = 1.0
var _visual: Node3D = null


## Spawns a drone under `parent`. Null (and nothing added) when the prop does not exist yet.
static func launch(parent: Node, world: HuntWorld, from: Vector3, life_s: float) -> ScoutDrone:
	if not AssetLoader.exists(ScenePaths.prop(PROP_ID)):
		return null
	var visual: Node = AssetLoader.instantiate(ScenePaths.prop(PROP_ID))
	if visual == null or not visual is Node3D:
		if visual != null:
			visual.queue_free()
		return null
	var drone: ScoutDrone = ScoutDrone.new()
	drone.name = "ScoutDrone"
	parent.add_child(drone)
	drone._visual = visual as Node3D
	drone._visual.scale = Vector3.ONE * VISUAL_SCALE
	drone.add_child(visual)
	drone.setup(world, from, life_s)
	return drone


func setup(world: HuntWorld, from: Vector3, life_s: float) -> void:
	_world = world
	_life_s = maxf(life_s, 0.1)
	# The drone leaves the hand ahead of where the camera looks, so it is seen from the first frame.
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var f: Vector3 = -cam.global_transform.basis.z
		var flat: Vector2 = Vector2(f.x, f.z)
		if flat.length_squared() > 0.0001:
			_forward = flat.normalized()
	_launch = from + Vector3(_forward.x, 0.0, _forward.y) * HAND_FORWARD_M
	# The circle lies to the side of where the climb ends, tangent to the flight direction there.
	var end_xz: Vector2 = Vector2(_launch.x, _launch.z) + _forward * CLIMB_FORWARD_M
	var side: Vector2 = _forward.rotated(PI * 0.5)
	_center_xz = end_xz + side * ORBIT_RADIUS_M
	var from_center: Vector2 = -side
	_angle = from_center.angle()
	var tangent: Vector2 = Vector2(-from_center.y, from_center.x)
	_spin = 1.0 if tangent.dot(_forward) >= 0.0 else -1.0
	global_position = _launch
	set_process(_visual != null)


func get_age_s() -> float:
	return _age_s


func _process(delta: float) -> void:
	var prev_age: float = _age_s
	_age_s += delta
	if _age_s >= _life_s:
		set_process(false)
		queue_free()
		return
	var climb_t: float = clampf(_age_s / CLIMB_TIME_S, 0.0, 1.0)
	var climb: float = smoothstep(0.0, 1.0, climb_t)
	var leave: float = _leave_factor()
	var xz: Vector2
	if _age_s < CLIMB_TIME_S:
		# Cubic Hermite along the forward line: starts at rest in the hand, ends at the orbit's speed.
		var s: float = climb_t
		var ride: float = CLIMB_FORWARD_M * (3.0 * s * s - 2.0 * s * s * s) 			+ ORBIT_RADIUS_M * ORBIT_SPEED_RAD_S * CLIMB_TIME_S * (s * s * s - s * s)
		xz = Vector2(_launch.x, _launch.z) + _forward * ride
	else:
		_angle += _spin * ORBIT_SPEED_RAD_S * (_age_s - maxf(prev_age, CLIMB_TIME_S))
		xz = _center_xz + Vector2.from_angle(_angle) * (ORBIT_RADIUS_M + LEAVE_OUT_M * leave)
	var y: float = _launch.y + CLIMB_M * climb + LEAVE_CLIMB_M * leave
	if _world != null:
		y = maxf(y, _world.get_height(xz.x, xz.y) + MIN_CLEARANCE_M * climb)
	var next: Vector3 = Vector3(xz.x, y, xz.y)
	var step: Vector3 = next - global_position
	global_position = next
	if _visual != null and Vector2(step.x, step.z).length_squared() > 0.000001:
		var target_yaw: float = atan2(-step.x, -step.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _leave_factor() -> float:
	var left: float = _life_s - _age_s
	if left >= LEAVE_TIME_S:
		return 0.0
	return smoothstep(0.0, 1.0, 1.0 - left / LEAVE_TIME_S)
