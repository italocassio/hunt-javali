class_name HitInfo
extends RefCounted
## One bullet/pellet impact. Filled by the weapon (A); zone/target_id filled by HitZone.

var shot_id: int = 0
var weapon_id: StringName = &""
var damage: float = 0.0              # after distance falloff, before zone multiplier
var origin: Vector3 = Vector3.ZERO
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var direction: Vector3 = Vector3.FORWARD
var distance_m: float = 0.0
var zone: StringName = &""
var target_id: int = -1
