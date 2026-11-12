class_name RewardCalculator
extends RefCounted
## Money formulas (docs/arquitetura.md §9.6). Pure functions over data dictionaries.


static func kill_reward(type_def: Dictionary, rules: Dictionary, weight_kg: float, killing_zone: StringName, one_shot: bool, contract_def: Dictionary) -> int:
	var reward_rules: Dictionary = rules.get("reward", {})
	var clean_zones: Array = reward_rules.get("clean_zones", [])
	var clean: bool = clean_zones.has(String(killing_zone))
	var value: float = weight_kg * float(type_def.get("value_per_kg", 0.0))
	if clean:
		value *= float(reward_rules.get("clean_kill_mult", 1.0))
	if one_shot:
		value *= float(reward_rules.get("one_shot_mult", 1.0))
	value *= float(contract_def.get("reward_mult", 1.0))
	return maxi(0, int(roundf(value)))


static func contract_bonus(contract_def: Dictionary, crop_health_pct: float) -> int:
	var pct: float = clampf(crop_health_pct, 0.0, 100.0)
	return maxi(0, int(roundf(float(contract_def.get("bonus_money", 0.0)) * pct / 100.0)))
