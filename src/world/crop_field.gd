class_name CropField
extends Marker3D
## A rectangular crop field centered on this marker (XZ). The terrain is flattened under it.

@export var size_m: Vector2 = Vector2(60.0, 60.0)
@export var crop: StringName = &"soy"


func get_rect() -> Rect2:
	return Rect2(global_position.x - size_m.x * 0.5, global_position.z - size_m.y * 0.5, size_m.x, size_m.y)
