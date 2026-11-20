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
# Horde (docs/horda.md section 5): crop_health_pct is the barn corn stock and contract_bonus the defense bonus.
var mode: StringName = &"contract"      # Ids.MODE_CONTRACT | Ids.MODE_HORDE
var horde_wave_count: int = 0           # waves of the plan (0 outside the horde)
var horde_waves_cleared: int = 0        # waves whose every boar died (== horde_wave_count on VICTORY)
var horde_level: int = 0                ## Horde level played (1-based); 0 in contract mode


func is_victory() -> bool:
	return outcome == Outcome.VICTORY


func is_horde() -> bool:
	return mode == Ids.MODE_HORDE


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
		"mode": String(mode), "horde_wave_count": horde_wave_count, "horde_waves_cleared": horde_waves_cleared,
			"horde_level": horde_level,
	}
