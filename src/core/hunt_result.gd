class_name HuntResult
extends RefCounted
## What the hunt returns. Applied once by Profile.apply_hunt_result.

enum Outcome { VICTORY, DEFEAT_CROP, DEFEAT_DEATH, ABANDONED, DISCONNECTED }

var outcome: Outcome = Outcome.ABANDONED
var map_id: StringName = &""
var contract_index: int = 0
var kills: Array[KillInfo] = []
var boars_total: int = 0
var money_from_kills: int = 0
var contract_bonus: int = 0
var total_money: int = 0
var crop_health_pct: float = 100.0
var duration_s: float = 0.0
var shots_fired: int = 0
var shots_hit: int = 0
var consumables_used: Dictionary = {}   # StringName -> int
var counts_for_progression: bool = true
var player_count: int = 1
var team_kills: int = 0
var scoreboard: Array[Dictionary] = []   # {slot, name, kills, money}; empty in solo


func is_victory() -> bool:
	return outcome == Outcome.VICTORY


func to_dict() -> Dictionary:
	var kill_dicts: Array = []
	for k: KillInfo in kills:
		kill_dicts.append(k.to_dict())
	return {
		"outcome": Outcome.keys()[outcome], "map_id": String(map_id), "contract_index": contract_index,
		"kills": kill_dicts, "boars_total": boars_total, "money_from_kills": money_from_kills,
		"contract_bonus": contract_bonus, "total_money": total_money,
		"crop_health_pct": crop_health_pct, "duration_s": duration_s,
		"shots_fired": shots_fired, "shots_hit": shots_hit,
	}
