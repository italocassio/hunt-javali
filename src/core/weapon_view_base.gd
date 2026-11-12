class_name WeaponViewBase
extends Node3D
## First-person weapon + arms. Child of the camera; camera space, looking -Z.
## Required children: Muzzle (Marker3D), AdsAnchor (Marker3D).


func setup(_weapon_id: StringName) -> void:
	pass


func play_fire() -> void:
	pass


func play_cycle(_duration_s: float) -> void:
	pass


func play_reload(_duration_s: float) -> void:
	pass


func play_draw(_duration_s: float) -> void:
	pass


func get_muzzle() -> Node3D:
	return get_node_or_null(^"Muzzle") as Node3D


func get_ads_anchor() -> Node3D:
	return get_node_or_null(^"AdsAnchor") as Node3D


static func create_fallback() -> WeaponViewBase:
	var v: WeaponViewBase = WeaponViewBase.new()
	v.name = "WeaponViewFallback"
	var barrel: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.05, 0.08, 0.9)
	barrel.mesh = box
	barrel.position = Vector3(0.2, -0.2, -0.6)
	barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(barrel)
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.2, -0.2, -1.05)
	v.add_child(muzzle)
	var ads: Marker3D = Marker3D.new()
	ads.name = "AdsAnchor"
	ads.position = Vector3(0.2, -0.14, -0.4)
	v.add_child(ads)
	return v
