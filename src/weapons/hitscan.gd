class_name Hitscan
extends RefCounted
## Stateless ray cast for bullets and pellets. Hits terrain, statics and HitZone areas.


## Returns the intersect_ray dictionary (position, normal, collider, rid...) plus "distance", or {} on a miss.
static func cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_range_m: float,
		exclude: Array[RID]) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir.normalized() * max_range_m, Layers.MASK_WEAPON_RAY, exclude)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return hit
	hit["distance"] = from.distance_to(hit["position"] as Vector3)
	return hit
