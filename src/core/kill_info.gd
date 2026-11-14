class_name KillInfo
extends RefCounted

var boar_id: int = -1
var type_id: StringName = &""
var weight_kg: float = 0.0
var killing_zone: StringName = &""
var one_shot: bool = false
var clean_kill: bool = false
var reward_money: int = 0
var position: Vector3 = Vector3.ZERO
var time_s: float = 0.0
var killer_slot: int = 0


func to_dict() -> Dictionary:
	return {
		"boar_id": boar_id, "type_id": String(type_id), "weight_kg": weight_kg,
		"killing_zone": String(killing_zone), "one_shot": one_shot, "clean_kill": clean_kill,
		"reward_money": reward_money, "time_s": time_s,
	}
