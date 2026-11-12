class_name DogVisualBase
extends Node3D
## Visual-only dog. Origin on the ground, forward -Z. Breed proportions are applied by the asset.


func setup(_breed_id: StringName) -> void:
	pass


func set_locomotion(_speed_mps: float) -> void:
	pass


func set_retreating(_on: bool) -> void:
	pass


func play_bark() -> void:
	pass


func play_bite(_on: bool) -> void:
	pass


func play_hurt() -> void:
	pass


func play_point() -> void:
	pass


static func create_fallback() -> DogVisualBase:
	var v: DogVisualBase = DogVisualBase.new()
	v.name = "DogVisualFallback"
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.25, 0.3, 0.8)
	body.mesh = box
	body.position = Vector3(0.0, 0.45, 0.0)
	v.add_child(body)
	var mouth: Marker3D = Marker3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0.0, 0.5, -0.45)
	v.add_child(mouth)
	return v
