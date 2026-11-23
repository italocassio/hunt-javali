extends Node3D
## Scout drone prop (quadcopter, ~0.36 m). The same scene is the drone in the hunter's hand and the one flying over
## the map: it builds its own airframe (one MeshInstance3D) and four rotors (one MultiMeshInstance3D) and spins the
## rotors in _process, so nobody outside has to animate them. Origin at the body centre, front = -Z.
## No light, no physics, no shadow. Opposite rotors counter-rotate.

const HD := preload("res://assets/models/props/scout_drone_hd.gd")

## Rotor angular speed in rad/s (fast enough to blur at 30 fps).
@export var rotor_speed: float = 70.0

var _rotors: MultiMesh = null
var _positions: Array[Vector3] = []
var _angle: float = 0.0


func _ready() -> void:
	if get_child_count() > 0:
		return
	var model: Dictionary = HD.get_model()
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = model["mesh"]
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	_positions = HD.rotor_positions()
	_rotors = MultiMesh.new()
	_rotors.transform_format = MultiMesh.TRANSFORM_3D
	_rotors.mesh = model["rotor_mesh"]
	_rotors.instance_count = _positions.size()
	var spin: MultiMeshInstance3D = MultiMeshInstance3D.new()
	spin.name = "Rotors"
	spin.multimesh = _rotors
	spin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.custom_aabb = AABB(Vector3(-0.2, -0.05, -0.2), Vector3(0.4, 0.15, 0.4))
	add_child(spin)
	_update_rotors()


func _process(delta: float) -> void:
	_angle = fposmod(_angle + rotor_speed * delta, TAU)
	_update_rotors()


func _update_rotors() -> void:
	if _rotors == null:
		return
	for i: int in _positions.size():
		var dir: float = 1.0 if (i == 0 or i == 3) else -1.0
		var phase: float = float(i) * 0.7
		_rotors.set_instance_transform(i, Transform3D(Basis(Vector3.UP, dir * _angle + phase), _positions[i]))
