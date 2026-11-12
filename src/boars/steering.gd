class_name Steering
extends RefCounted
## Stateless steering helpers in the XZ plane. Heading convention: forward = -Z, so
## yaw = atan2(-d.x, -d.y) for a direction d = (x, z).


static func yaw_from_dir(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


static func dir_from_yaw(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


static func seek(from: Vector2, to: Vector2) -> Vector2:
	var d: Vector2 = to - from
	if d.length_squared() < 0.0001:
		return Vector2.ZERO
	return d.normalized()


static func flee(from: Vector2, threat: Vector2) -> Vector2:
	var d: Vector2 = from - threat
	if d.length_squared() < 0.0001:
		return Vector2(0.0, 1.0)
	return d.normalized()


## Speed scale for arriving at a target: 1 beyond slow_radius, ramping down near the target.
static func arrive_scale(distance: float, slow_radius: float) -> float:
	if slow_radius <= 0.0:
		return 1.0
	return clampf(distance / slow_radius, 0.2, 1.0)


## Rotates yaw toward target_yaw by at most max_step radians. Returns the new yaw.
static func turn_toward(yaw: float, target_yaw: float, max_step: float) -> float:
	var diff: float = angle_difference(yaw, target_yaw)
	return yaw + clampf(diff, -max_step, max_step)


## Push away from herd mates closer than radius. members hold Node3D (position.x / position.z).
static func separation(pos: Vector2, self_node: Node3D, members: Array, radius: float) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for m: Variant in members:
		var other: Node3D = m as Node3D
		if other == null or other == self_node:
			continue
		var d: Vector2 = Vector2(pos.x - other.position.x, pos.y - other.position.z)
		var len: float = d.length()
		if len < radius and len > 0.001:
			push += d / len * (1.0 - len / radius)
		elif len <= 0.001:
			push += Vector2(randf() - 0.5, randf() - 0.5)
	return push


## Keeps pos inside the map rect shrunk by margin_m.
static func clamp_to_rect(pos: Vector2, rect: Rect2, margin_m: float) -> Vector2:
	return Vector2(
		clampf(pos.x, rect.position.x + margin_m, rect.end.x - margin_m),
		clampf(pos.y, rect.position.y + margin_m, rect.end.y - margin_m))
