class_name PropSpawn
extends Marker3D
## A prop placed by id. MapRoot loads the visual (asset or fallback box), creates a static box
## collider from collision_size (layer "static") and registers a steering obstacle.

@export var prop_id: StringName = &""
## Collision box size (X, Y, Z) in meters, in the marker's local frame. Zero = no collider.
@export var collision_size: Vector3 = Vector3.ZERO
## Steering obstacle radius for boars and dogs. 0 = boars walk through it.
@export var footprint_radius_m: float = 0.0
