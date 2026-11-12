class_name BoarVisualBase
extends Node3D
## Visual-only boar. Origin on the ground, forward -Z. Scale 1 = 100 kg reference animal.
## Gameplay owns the root transform (sets uniform scale with scale_for_weight).

const REFERENCE_WEIGHT_KG: float = 100.0
## zone -> [center, size] in meters at scale 1 (gameplay multiplies both by scale_for_weight).
const HIT_ZONES: Dictionary = {
	&"head": [Vector3(0.0, 0.55, -0.62), Vector3(0.30, 0.35, 0.40)],
	&"vital": [Vector3(0.0, 0.50, -0.25), Vector3(0.42, 0.40, 0.35)],
	&"body": [Vector3(0.0, 0.52, 0.15), Vector3(0.46, 0.46, 0.50)],
	&"rear": [Vector3(0.0, 0.50, 0.52), Vector3(0.42, 0.44, 0.30)],
}


static func scale_for_weight(weight_kg: float) -> float:
	return pow(maxf(weight_kg, 1.0) / REFERENCE_WEIGHT_KG, 1.0 / 3.0)


func setup(_type_id: StringName, _weight_kg: float) -> void:
	pass


func set_locomotion(_speed_mps: float) -> void:
	pass


func set_eating(_on: bool) -> void:
	pass


func set_wounded(_on: bool) -> void:
	pass


func set_highlight(_on: bool) -> void:
	pass


func play_alert() -> void:
	pass


func play_scrape() -> void:
	pass


func play_attack() -> void:
	pass


func play_hit(_zone: StringName) -> void:
	pass


func play_death() -> void:
	pass


static func create_fallback() -> BoarVisualBase:
	var v: BoarVisualBase = BoarVisualBase.new()
	v.name = "BoarVisualFallback"
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.48, 0.55, 1.4)
	body.mesh = box
	body.position = Vector3(0.0, 0.5, 0.05)
	v.add_child(body)
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.55, -0.62)
	v.add_child(head)
	return v
