class_name HunterVisualBase
extends Node3D
## Visual-only third-person hunter: how a player is seen by the other players in multiplayer.
## Origin on the ground between the feet, forward -Z. Scale 1 = 1.78 m tall standing.
## Gameplay owns the root transform (position + yaw). The asset animates children only.
## Required children: Muzzle (Marker3D, follows the weapon tip), NameAnchor (Marker3D above the head).

const SLOT_COUNT: int = 4

## Identity color of each player slot. Single source for the model, name tag, minimap and lobby.
## Chosen to stand out against cerrado greens/browns and to stay apart from damage red.
const SLOT_COLORS: Array[Color] = [
	Color(0.93, 0.47, 0.13),   # 0 orange
	Color(0.20, 0.56, 0.90),   # 1 blue
	Color(0.96, 0.80, 0.18),   # 2 yellow
	Color(0.74, 0.36, 0.84),   # 3 purple
]


static func slot_color(slot: int) -> Color:
	return SLOT_COLORS[posmod(slot, SLOT_COUNT)]


var _fallback_body: MeshInstance3D = null   # set only by create_fallback()


func setup(slot: int, _weapon_id: StringName) -> void:   # cosmetic; called once before entering the tree
	if _fallback_body != null:   # fallback capsule: paint with the slot color
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = slot_color(slot)
		_fallback_body.material_override = mat


func set_weapon(_weapon_id: StringName) -> void:   # &"" = unarmed
	pass


func set_locomotion(_speed_mps: float) -> void:   # 0 = idle; called every frame
	pass


func set_crouching(_on: bool) -> void:
	pass


func set_aiming(_on: bool) -> void:   # weapon shouldered vs. carried low
	pass


func set_look_pitch(_pitch_rad: float) -> void:   # positive = looking up; bends torso/weapon
	pass


func play_fire() -> void:   # recoil kick + muzzle flash
	pass


func play_reload(_duration_s: float) -> void:
	pass


func play_hit() -> void:   # flinch when damaged
	pass


func play_death(_instant: bool = false) -> void:   # falls and freezes; instant = born fallen; ignores later calls
	pass


func get_muzzle() -> Node3D:
	return get_node_or_null(^"Muzzle") as Node3D


func get_name_anchor() -> Node3D:
	return get_node_or_null(^"NameAnchor") as Node3D


static func create_fallback() -> HunterVisualBase:
	var v: HunterVisualBase = HunterVisualBase.new()
	v.name = "HunterVisualFallback"
	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.78
	body.mesh = capsule
	body.position = Vector3(0.0, 0.89, 0.0)
	v.add_child(body)
	v._fallback_body = body
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.2, 1.35, -0.9)
	v.add_child(muzzle)
	var name_anchor: Marker3D = Marker3D.new()
	name_anchor.name = "NameAnchor"
	name_anchor.position = Vector3(0.0, 2.05, 0.0)
	v.add_child(name_anchor)
	return v
