class_name PropSpawn
extends Marker3D
## A prop placed by id. MapRoot loads the visual (asset or fallback box), creates a static box
## collider from collision_size (layer "static") and registers a steering obstacle.

@export var prop_id: StringName = &""
## Collision box size (X, Y, Z) in meters, in the marker's local frame. Zero = no collider.
@export var collision_size: Vector3 = Vector3.ZERO
## Steering obstacle radius for boars and dogs. 0 = boars walk through it.
@export var footprint_radius_m: float = 0.0
## Horde layout (MapRoot.set_horde_layout): boxes in the marker's local frame (position = min corner, Y from the
## ground) that replace collision_size for the collider. Empty = collision_size as always.
@export var horde_collision_boxes: Array[AABB] = []
## Horde layout: steering circles (local x, local z, radius) that replace footprint_radius_m for boars and dogs.
## Terrain flattening and flora exclusion keep using footprint_radius_m. Empty = footprint_radius_m as always.
@export var horde_obstacle_circles: PackedVector3Array = PackedVector3Array()
