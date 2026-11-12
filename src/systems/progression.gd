class_name Progression
extends RefCounted
## Contract unlocks and completion per map.

var _maps: Dictionary = {}   # map_id String -> {"unlocked": int, "best_crop_pct": Array[float]}


func unlocked_count(map_id: StringName) -> int:
	if not _is_available(map_id):
		return 0
	var rec: Dictionary = _record(map_id)
	return clampi(int(rec["unlocked"]), 1, maxi(1, Data.get_contract_count(map_id)))


func is_unlocked(map_id: StringName, index: int) -> bool:
	return index >= 0 and index < unlocked_count(map_id)


func is_completed(map_id: StringName, index: int) -> bool:
	if not _is_available(map_id) or index < 0:
		return false
	var best: Array = _record(map_id)["best_crop_pct"]
	return index < best.size() and float(best[index]) >= 0.0


## Best crop health % of a won contract, or -1.0 if never won.
func best_crop_pct(map_id: StringName, index: int) -> float:
	if not _is_available(map_id) or index < 0:
		return -1.0
	var best: Array = _record(map_id)["best_crop_pct"]
	return float(best[index]) if index < best.size() else -1.0


func mark_won(map_id: StringName, index: int, crop_pct: float) -> void:
	var count: int = Data.get_contract_count(map_id) if _is_available(map_id) else 0
	if index < 0 or index >= count:
		return
	var rec: Dictionary = _record(map_id)
	var best: Array = rec["best_crop_pct"]
	best[index] = maxf(float(best[index]), clampf(crop_pct, 0.0, 100.0))
	rec["unlocked"] = maxi(int(rec["unlocked"]), mini(index + 2, count))


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for map_id: String in _maps:
		var rec: Dictionary = _maps[map_id]
		out[map_id] = {"unlocked": int(rec["unlocked"]), "best_crop_pct": (rec["best_crop_pct"] as Array).duplicate()}
	return out


## d is the "progression" block of the save. Unknown maps are dropped, bad entries repaired.
static func from_dict(d: Dictionary) -> Progression:
	var p: Progression = Progression.new()
	for map_id: StringName in Data.get_map_ids():
		var count: int = Data.get_contract_count(map_id)
		if count <= 0:
			continue
		var src: Variant = d.get(String(map_id), {})
		var rec: Dictionary = _fresh(count)
		if src is Dictionary:
			var u: Variant = (src as Dictionary).get("unlocked", 1)
			rec["unlocked"] = clampi(int(u) if (u is int or u is float) else 1, 1, count)
			var raw_best: Variant = (src as Dictionary).get("best_crop_pct", [])
			if raw_best is Array:
				for i: int in mini(count, (raw_best as Array).size()):
					var v: Variant = raw_best[i]
					if (v is float or v is int) and is_finite(float(v)):
						rec["best_crop_pct"][i] = clampf(float(v), -1.0, 100.0)
			for i: int in count:
				if float(rec["best_crop_pct"][i]) >= 0.0:
					rec["unlocked"] = maxi(int(rec["unlocked"]), mini(i + 2, count))
		p._maps[String(map_id)] = rec
	return p


func _is_available(map_id: StringName) -> bool:
	if not Data.get_map_ids().has(map_id):
		return false
	return bool(Data.get_map(map_id).get("available", false)) and Data.get_contract_count(map_id) > 0


func _record(map_id: StringName) -> Dictionary:
	var key: String = String(map_id)
	if not _maps.has(key):
		_maps[key] = _fresh(Data.get_contract_count(map_id))
	var rec: Dictionary = _maps[key]
	var count: int = Data.get_contract_count(map_id)
	var best: Array = rec["best_crop_pct"]
	while best.size() < count:
		best.append(-1.0)
	return rec


static func _fresh(count: int) -> Dictionary:
	var best: Array = []
	for i: int in count:
		best.append(-1.0)
	return {"unlocked": 1, "best_crop_pct": best}
