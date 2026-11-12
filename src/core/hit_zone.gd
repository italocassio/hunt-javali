class_name HitZone
extends Area3D
## Shootable zone of a target. The weapon calls receive_hit(); the owner listens to hit_received.

signal hit_received(hit: HitInfo)

@export var zone: StringName = &"body"
var target_id: int = -1


func _ready() -> void:
	collision_layer = Layers.BOAR_HITZONE
	collision_mask = 0
	monitoring = false
	monitorable = true


func receive_hit(hit: HitInfo) -> void:
	hit.zone = zone
	hit.target_id = target_id
	hit_received.emit(hit)


func disable() -> void:
	collision_layer = 0
	set_deferred("monitorable", false)
